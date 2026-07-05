# HID Remapper — Vial-style configurator

A second configuration front-end for [HID Remapper](https://github.com/jfedor2/hid-remapper)
that presents the device as a **Vial/QMK-style keymap** — a picture of your
device, layer tabs, and a searchable keycode picker — instead of a flat list of
input→output mappings.

It talks to the **stock, unmodified firmware** over the same WebHID protocol as
the official tool, so no reflash is needed. It targets a USB-to-USB converter
build (e.g. an Adafruit Feather RP2040 USB Host driving an Elecom Huge Plus
trackball), but works with any HID Remapper.

> Status: **keymap + per-key flags + settings + macros + behaviors + desktop app
> implemented**, all verified in-browser. Keymap editor (layout, 8 layers,
> searchable picker, per-key sticky/tap/hold actions); a Settings tab (tap-hold
> threshold, etc.); a Vial-style Macros editor (assignable as "Macro N"); and
> five no-RPN behavior builders (DPI shift, cursor→keys, chording, tap-dance,
> scroll-text). A no-Chromium desktop app (`desktop/`) runs the same UI in a
> native webview over hidapi. Still to do: hardware testing of the generated
> expression behaviors (tap-dance timing, cursor→keys feel) on a real device.

## Why a second tool

The stock tool is powerful but expresses everything as mappings and
hand-written RPN expressions. This tool keeps that power (the RPN editor stays
one click away) but adds:

- a **visual device layout** with click-to-assign, like Vial;
- **layer tabs** (HID Remapper already has 8 layers);
- point-and-click **builders** for behaviors that normally require RPN —
  held/sticky **DPI shift**, **cursor → arrow keys** (4 cardinal, proportional
  to distance), **chording** (2–4 buttons, configurable timing), and
  **scroll-wheel text input**. Each builder compiles down to ordinary HID
  Remapper mappings/expressions.

## How it relates to the stock config

The device only ever stores compiled mappings/expressions — it can't tell a
generated chord from hand-written RPN. So, like Vial's `.vil` file, this tool
keeps a **project file** as the source of truth for your high-level intent
(chords, behaviors, which profile), and compiles it to the device on save.

Export also produces a plain `hid-remapper-config.json` that is **byte-compatible
with the stock tool** — you can move between the two freely.

## Running it

**Desktop app (recommended — no Chromium, no browser):** a native-webview wrapper
that talks to the device over hidapi. See [`desktop/README.md`](desktop/README.md):

```
cd config-tool-vial/desktop
pip install -r requirements.txt    # plus: brew install hidapi (macOS)
python3 app.py
```

**In a browser (WebHID):** serve the folder over `localhost` and open it in
Chrome / a Chromium browser:

```
cd config-tool-vial
python3 -m http.server 8000
# then open http://localhost:8000/ in Chrome
```

No build step either way — these are static ES modules. The UI is identical; only
the transport differs (hidapi in the desktop app, WebHID in the browser), chosen
automatically (the desktop app loads the page with `?native=1`).

## Architecture

| File | Responsibility |
|---|---|
| `crc.js` | CRC-32 for the config packets (copied from the stock tool). |
| `protocol.js` | Wire protocol: command constants, usage pages, 32-byte packet (de)serialization, `sendFeatureCommand`/`readConfigFeature`. No DOM. |
| `expr.js` | Expression (RPN) opcode table and `exprToElems` / `elemToToken` serialization. |
| `model.js` | The config data model: `defaultConfig`, `migrateConfig`, `newMapping`, helpers. Same JSON shape as the stock tool. |
| `device.js` | `RemapperDevice` — open / load / save / usages over WebHID **or** the native bridge (a transport abstraction; ported from the stock `code.js`). |
| `profiles.js` | Device profiles (input list + upstream usages). Ships the Elecom Huge Plus; add a profile to support a new device. |
| `keycodes.js` | Categorized keycode picker data + usage-name resolution. |
| `usages.js` | Usage-name tables (vendored copy of the stock tool's, so this folder is self-contained). |
| `keymap.js` | Pure per-(input, layer) assignment logic over a config. Unit-tested. |
| `behaviors.js` | The no-RPN behavior compiler — DPI shift, cursor→keys, chords, scroll-text → mappings/expressions. Unit-tested. |
| `project.js` | The project document (base keymap + behaviors) and `compileProject`. |
| `index.html`, `vial.js` | The UI: keymap tab (layout, layer tabs, picker), behaviors tab (the four builders), load/save/import/export. |
| `desktop/` | The native desktop app (`app.py`, pywebview + hidapi). No Chromium. |

## Adding a device

Add an entry to `profiles.js` describing the buttons (with their upstream HID
usages) and where to draw them. HID Remapper merges inputs from all connected
devices, so a profile is about presentation and defaults, not gating.
