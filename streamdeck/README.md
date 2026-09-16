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

Home is the launch pad. Every other page ends in a **strip** (bottom row) whose
columns never move, so a section is always under the same finger:

| | | | | |
|---|---|---|---|---|
| 🏠 Home | 📁 Editing | 📁 PACS tools | 📁 Windowing | 📁 Web & windows |

On one of those four section pages its own column holds **📁 Number pad**
instead, since you are already there. System is reached from Home, PACS more
from PACS tools, and the Number pad links back to Home and Editing.

**Home** is a Switch Profile action: it switches back to the profile root, so
it returns from any depth rather than popping one folder. If a Stream Deck
version lands on the last-open page instead of the root, the fallback is the
Back key behaviour — change that key to **Navigation > Back** (Parent Folder)
in the Stream Deck app and press it once per level.

## Pages

**Home**

| | | | | |
|---|---|---|---|---|
| Dictate (F4) | Prev field (Shift+Tab) | Next field (Tab) | Switch app (Alt+Tab) | Impression (Ctrl+Shift+1) |
| Prev series (F7) | Next series (F8) | Undo (Ctrl+Z) | Redo (Ctrl+Y) | 📁 Number pad |
| 📁 System | 📁 Editing | 📁 PACS tools | 📁 Windowing | 📁 Web & windows |

**Editing (PowerScribe)**

| | | | | |
|---|---|---|---|---|
| Dictate (F4) | Prev field (Shift+Tab) | Next field (Tab) | **Dictate + next field** ⛓ | Impression (Ctrl+Shift+1) |
| Undo (Ctrl+Z) | Redo (Ctrl+Y) | **Copy whole report** ⛓ | Sign ⚙ (Ctrl+Shift+S) | Paste (Ctrl+V) |
| strip | | | | |

Copy whole report sends Ctrl+A, Ctrl+C, Ctrl+End: the report is on the
clipboard (ready to paste into Claude) and nothing is left selected. Paste sits
at the far end of the row so it is never next to Copy.

**PACS tools**: Ruler (R), ROI (Shift+R), Magnify (Y), CLAHE (Shift+C), Delete
measurement (Delete); Prev series (F7), Next series (F8), Zoom in ⚙ (=), Zoom
out ⚙ (-), 📁 PACS more; strip.

**PACS more**: Spine labeling ⚙ (Shift+S), Localizer ⚙ (L), Scout lines ⚙
(Shift+L), Invert ⚙ (Shift+I), W/L 8 Lung (8); W/L 1 Soft tissue (1), W/L 2
Bone (2), W/L 3 Brain (3), Prev series (F7), Next series (F8); the PACS tools
strip (its column still holds Number pad).

**Windowing**: the nine RadMapper presets on digits 1–9 (Soft tissue, Bone, Brain,
C-spine soft tissue, CTA, Infarct, Liver, Lung, Lung wide), Invert ⚙, strip.

**Number pad**

| | | | | |
|---|---|---|---|---|
| Backspace | 7 | 8 | 9 | Enter |
| . | 4 | 5 | 6 | 0 |
| 🏠 Home | 1 | 2 | 3 | 📁 Editing |

The digits are a 3×3 block in the middle three columns; 0 finishes the middle
row and `.` starts it, so neither sits where a keyboard numpad puts it — this
is a Stream Deck layout, not a numpad copy. Backspace and Enter are the top
corners, Home and Editing the bottom corners. The keys send the top-row digits,
not the numeric keypad, so they work with NumLock off (RadMapper uses NumLock as
its pause key). These are the same keystrokes as the Windowing digits, so with
IntelliSpace in front any digit is read as a window preset, not as a number —
type numbers only into PowerScribe.

**Web & windows**: mail.umn.edu, claude.ai, openevidence.com, umnradiology.com,
Close window (Alt+F4); Snap left/right (Win+←/→), Maximize/Minimize (Win+↑/↓),
**Open all sites** ⛓; strip.

**System**: RadMapper Settings (Ctrl+Alt+Shift+F9), Pause/resume engine
(Ctrl+Alt+Shift+F11), Unstick buttons (Ctrl+Alt+Q), Clipboard history
(Ctrl+Alt+C), Scratchpad (Ctrl+Alt+N); Task view (Win+Tab), window to left /
right monitor (Win+Shift+←/→), Show desktop (Win+D), Switch app (Alt+Tab);
strip.

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
  `build_profile.py` and rebuild. That reroutes every Dictate, Prev field and
  Next field key — the three on Home and the three on Editing — plus the first
  step of **Dictate + next field**, so they send RadMapper's global `` ` ``
  `[` `]` bindings instead, and RadMapper brings PowerScribe forward, delivers
  the key and returns focus. (Or bind the same keys yourself on RadMapper's
  Keyboard page.) The backtick / bracket bindings are RadMapper's shipped
  defaults, but `SeedDefaultBindings` returns early once any binding exists, so
  they are seeded **only on a fresh config**. On a config you have already
  edited, add them on RadMapper's Keyboard page first — otherwise these keys
  just type `` ` `` `[` `]` into the report. They are distinct from the blank
  `hkDictate` / `hkPrevField` / `hkNextField` hotkey settings, which stay empty.
- **PACS keys** (R, Shift+R, Y, Shift+C, F7, F8, Delete, digits 1–9) are the values
  in RadMapper's shipped PACS wheel and Window-preset ring and go straight to
  IntelliSpace, so the viewer must be in front. To fire them from PowerScribe,
  bind the same key on RadMapper's Keyboard page to **PACS: send keys** with
  the same value.
- The **System** page's RadMapper keys are its default hotkeys from Settings.
  If you changed them there, change them here (or in `build_profile.py`).

F4 is PowerScribe's default dictation toggle and is user-configurable in
PowerScribe; if yours differs, edit the Dictate buttons in the Stream Deck app.

### Keys that act on whatever window is in front

These three do something destructive to the front window, so check what has
focus first:

| Button | Sends | With the PACS viewer in front | With PowerScribe in front |
|---|---|---|---|
| Delete measurement | Delete | deletes the selected measurement | **deletes report text** (the selection, or the character after the cursor) |
| Copy whole report ⛓ | Ctrl+A, Ctrl+C, Ctrl+End | selects everything the viewer will select and copies it | selects the report, copies it, then Ctrl+End drops the selection and parks the cursor at the end — nothing is left selected to overtype |
| Close window | Alt+F4 | closes the viewer | closes PowerScribe |

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
