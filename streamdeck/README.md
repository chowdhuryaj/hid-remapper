# RadMapper Radiology — Stream Deck MK.2 profile

A 15-key Stream Deck profile for the PowerScribe + IntelliSpace reading room,
built from the shortcuts RadMapper already knows about. Every button has a
drawn icon (dark navy, RadMapper's palette) with its name baked into the image,
so nothing has to be read from a Stream Deck title.

**Files**

| File | What it is |
|---|---|
| `RadMapper Radiology.streamDeckProfile` | Import this: double-click it, or Stream Deck > Preferences > Profiles > ⋯ > Import. Pick your Stream Deck MK.2 when asked. |
| `preview.png` | Every page rendered as a contact sheet |
| `keymap.md` | Every button, the key(s) it sends, and where that key came from |
| `build_profile.py` | Regenerates all of the above (`python3 build_profile.py`; needs Pillow) |

## Navigation

Home is the launch pad. Every other page ends in a **strip** (bottom row):
Home first, then the other sections, so any section is one press from any
other. The Number pad keeps its 3×3 digit block and links only to Home and
Editing, which are the two places you go from numbers.

## Pages

**Home**

| | | | | |
|---|---|---|---|---|
| Dictate (F4) | Prev field (Shift+Tab) | Next field (Tab) | Switch app (Alt+Tab) | Show desktop (Win+D) |
| Prev series (F7) | Next series (F8) | Window to left monitor (Win+Shift+←) | Window to right monitor (Win+Shift+→) | 📁 System |
| 📁 Editing | 📁 PACS tools | 📁 Windowing | 📁 Number pad | 📁 Web & windows |

**Editing (PowerScribe)**: Dictate, Prev/Next field, **Next field & dictate** ⛓, Impression (Ctrl+Shift+1), Undo, Redo, **Copy whole report** ⛓ (Ctrl+A then Ctrl+C, ready to paste into Claude), Paste, Sign ⚙, strip.

**PACS tools**: Ruler (R), ROI (Shift+R), Magnify (Y), CLAHE (Shift+C), Delete measurement, Spine labeling ⚙, Localizer ⚙, Scout lines ⚙, Zoom in ⚙, Zoom out ⚙, strip.

**Windowing**: the nine RadMapper presets on digits 1–9 (Soft tissue, Bone, Brain, C-spine soft tissue, CTA, Infarct, Liver, Lung, Lung wide), Invert ⚙, strip.

**Number pad**: 7 8 9 / 4 5 6 / 1 2 3 on the left, Backspace, Enter, 0 and `.` on the right, Home and Editing in the corner. Sends the top-row digit keys, not the numeric keypad, so it works with NumLock off (RadMapper uses NumLock as its pause key).

**Web & windows**: mail.umn.edu, claude.ai, openevidence.com, umnradiology.com, **Open all sites** ⛓, Snap left/right (Win+←/→), Maximize/Minimize (Win+↑/↓), Close window (Alt+F4), strip.

**System**: RadMapper Settings (Ctrl+Alt+Shift+F9), Pause/resume engine (Ctrl+Alt+Shift+F11), Unstick buttons (Ctrl+Alt+Q), Clipboard history (Ctrl+Alt+C), Scratchpad (Ctrl+Alt+N), Task view (Win+Tab), window to left/right monitor, **Clear & next series** ⛓ (Delete then F8), Switch app, strip.

⛓ = a Stream Deck **Multi Action**: several steps in one press, run by the
Stream Deck software itself.

## Native keys, and where RadMapper still helps

The buttons send the apps' own shortcuts, so they work with or without
RadMapper running. The catch is that a Stream Deck keystroke goes to whatever
window is in front:

- **PowerScribe keys** (F4, Tab, Shift+Tab, Ctrl+Shift+1, Undo/Redo/Copy/Paste, Sign)
  need PowerScribe to be the active window. If you want Dictate and field
  navigation to work while the PACS viewer has the cursor, set
  `ROUTE_PS_VIA_RADMAPPER = True` at the top of the key-routing section in
  `build_profile.py` and rebuild: those three buttons then send RadMapper's
  global `` ` `` `[` `]` bindings, and RadMapper brings PowerScribe forward,
  delivers the key and returns focus. (Or bind the same keys yourself on
  RadMapper's Keyboard page.)
- **PACS keys** (R, Shift+R, Y, Shift+C, F7, F8, Delete, digits 1–9) are the values
  in RadMapper's shipped PACS wheel and Window-preset ring and go straight to
  IntelliSpace, so the viewer must be in front. To fire them from PowerScribe,
  bind the same key on RadMapper's Keyboard page to **PACS: send keys** with
  the same value.
- The **System** page's RadMapper keys are its default hotkeys from Settings.
  If you changed them there, change them here (or in `build_profile.py`).

F4 is PowerScribe's default dictation toggle and is user-configurable in
PowerScribe; if yours differs, edit the Dictate buttons in the Stream Deck app.

## Buttons marked with the gear badge ⚙

IntelliSpace and PowerScribe One shortcuts are configured per user, and
RadMapper deliberately does not guess them. These buttons send a key that is
unlikely to collide with anything; assign that key to the function once in the
app and the button is live:

| Button | Sends | Where to assign it |
|---|---|---|
| Spine labeling | Shift+S | IntelliSpace > Preferences > Keyboard shortcuts |
| Localizer mode | L | same |
| Scout line mode | Shift+L | same |
| Zoom in | = | same |
| Zoom out | - | same |
| Invert | Shift+I | same |
| Sign report | Ctrl+Shift+S | PowerScribe One > Settings > Quick Keys |

If your site already has a shortcut for one of these, edit that button in the
Stream Deck app instead (click the key, change the hotkey) or change the key
name in `build_profile.py` and rebuild.

## Editing the icons

`build_profile.py` draws each icon with a few primitives (`ic_ruler`,
`ic_spine`, ...). Change a drawing function, run the script, re-import the
profile. Icons are 288×288 PNG, drawn at 4× and downsampled.
