# Desktop app (no Chromium, no browser)

A native desktop wrapper for the Vial-style configurator. It renders the same
web UI in your OS's built-in webview — **WKWebView** on macOS, **WebKitGTK** on
Linux — and talks to the device through **hidapi**, so there is no Chrome, no
Edge, and no bundled Chromium anywhere. Same idea as Vial's and Pipette's
desktop apps.

## Install

The `hid` Python package needs the native hidapi library present:

- **macOS:** `brew install hidapi`
- **Linux (Debian/Ubuntu):** `sudo apt install libhidapi-hidraw0`

Then, ideally in a virtualenv:

```
cd config-tool-vial/desktop
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

On macOS, `pywebview` pulls in `pyobjc`; on Linux it uses the system
`gobject-introspection` / `WebKitGTK` (`sudo apt install python3-gi gir1.2-webkit2-4.1`).

## Run

```
python3 app.py
```

The window opens and auto-connects to a plugged-in HID Remapper. Edit the keymap
and behaviors exactly as in the web version, then **Save to device**.

## How it works

`app.py` serves the parent `config-tool-vial/` folder from a localhost HTTP
server (so ES modules load cleanly in the webview) and opens it with
`?native=1`. That flag tells `vial.js` to route HID through `window.pywebview.api`
(the `HidBridge` class here) instead of WebHID. The bridge prepends the report id
and calls hidapi's `send_feature_report` / `get_feature_report` — the exact
framing the repo's `config-tool/common.py` already uses.

## Permissions

Opening the HID Remapper's vendor configuration interface does not normally need
special permissions. On Linux you may need a udev rule (or to run with
sufficient privileges) to access the `hidraw` device; on macOS no Input
Monitoring permission is required for feature reports to the vendor interface.
