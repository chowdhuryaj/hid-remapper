#!/usr/bin/env python3
"""Desktop shell for the HID Remapper Vial configurator.

Runs the static web UI inside a *native* OS webview (WKWebView on macOS,
WebKitGTK on Linux) — no Chromium, no browser — and bridges HID feature reports
to the device through hidapi. The web UI (device.js) detects this bridge via
``window.pywebview.api`` and uses it instead of WebHID when launched with
``?native=1``.

Framing matches the repo's command-line tool (config-tool/common.py): the JS
side hands us a report id plus the 32-byte config packet; we prepend the report
id for hidapi, exactly like ``device.send_feature_report(add_crc(data))``.

Run:  python3 app.py   (see requirements.txt and README.md in this folder)
"""

import functools
import http.server
import json
import os
import socket
import threading
import time

import hid
import webview

CONFIG_USAGE_PAGE = 0xFF00
CONFIG_USAGE = 0x0020

SERVER_PORT = None  # set in main(), used by the HUD window URL


def _remapper_devices():
    return [
        d for d in hid.enumerate()
        if d["usage_page"] == CONFIG_USAGE_PAGE and d["usage"] == CONFIG_USAGE
    ]


class HidBridge:
    """Exposed to the page as window.pywebview.api."""

    def __init__(self):
        self.device = None
        self.hud = None

    # --- HUD overlay (Flask-style always-on-top panel) ---
    def toggle_hud(self):
        if self.hud is not None:
            try:
                self.hud.destroy()
            except Exception:
                pass
            self.hud = None
            return {"open": False}
        self.hud = webview.create_window(
            "Aloo HUD",
            f"http://127.0.0.1:{SERVER_PORT}/hud.html",
            width=340,
            height=240,
            on_top=True,
            frameless=True,
            easy_drag=True,
            resizable=True,
            js_api=self,
        )
        self.hud.events.closed += self._hud_closed
        return {"open": True}

    def _hud_closed(self):
        self.hud = None

    def hud_push(self, state):
        if self.hud is not None:
            try:
                self.hud.evaluate_js(
                    "window.hudUpdate && window.hudUpdate(" + json.dumps(state) + ")")
            except Exception:
                pass
        return True

    def hud_close(self):
        # called from inside the HUD window (its close button)
        return self.toggle_hud()

    def list_devices(self):
        return [
            {
                "product": d.get("product_string") or "HID Remapper",
                "vendor_id": d["vendor_id"],
                "product_id": d["product_id"],
            }
            for d in _remapper_devices()
        ]

    def open(self):
        try:
            devices = _remapper_devices()
            if not devices:
                return {"ok": False, "error": "No HID Remapper found. Is it plugged in?"}
            if self.device is not None:
                self.close()
            self.device = hid.Device(path=devices[0]["path"])
            return {"ok": True, "product": devices[0].get("product_string") or "HID Remapper"}
        except Exception as e:  # surfaced to the UI as a notice
            return {"ok": False, "error": str(e)}

    def send_feature(self, report_id, data):
        payload = bytes((int(x) & 0xFF) for x in data)
        self.device.send_feature_report(bytes([report_id]) + payload)
        return True

    def get_feature(self, report_id, size):
        attempts, delay = 8, 0.002
        while True:
            data = self.device.get_feature_report(report_id, size)
            if len(data) > 1 or attempts <= 0:
                return list(data)
            attempts -= 1
            time.sleep(delay)
            delay *= 2

    def close(self):
        if self.device is not None:
            try:
                self.device.close()
            finally:
                self.device = None
        return True


def _free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _serve(directory, port):
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=directory)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()


def main():
    global SERVER_PORT
    webroot = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # config-tool-vial/
    SERVER_PORT = _free_port()
    threading.Thread(target=_serve, args=(webroot, SERVER_PORT), daemon=True).start()

    webview.create_window(
        "AlooMapper",
        f"http://127.0.0.1:{SERVER_PORT}/index.html?native=1",
        js_api=HidBridge(),
        width=980,
        height=920,
        min_size=(720, 600),
    )
    webview.start()


if __name__ == "__main__":
    main()
