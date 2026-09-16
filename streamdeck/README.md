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
instead, since you are already there — except on PACS tools, where that column
holds **📁 PACS more**, the only way through to it. System is reached from
Home, and the Number pad links back to Home and Web & windows. PACS more itself
shows the full strip, so PACS tools is back in column 2 there.

**Dictate is at (4,1) — the last key of the middle row — on every page except
Home and the Number pad.** Wherever you are, the one key you always need is
under the same finger.

**Home** is a Switch Profile action: it switches back to the profile root, so
it returns from any depth rather than popping one folder. **This has not been
tested on hardware.** If it does nothing, or lands on the last-open page
instead of the root, then either (a) change the Home key's action to
**Navigation > Back to Parent** in the Stream Deck app and press it once per
level, or (b) report which of the two happened, so the generator can be
switched to emit Back to Parent for every Home key.

### Test on hardware first

Three things in this profile have never run on a device. Check them before you
rely on the profile in a live list:

1. **The Home key** — press it from PACS more (two levels down) and see whether
   you land on Home.
2. **One F13+ assignment in each app** — try recording F13 in IntelliSpace and
   F19 in PowerScribe One before assigning the rest (see below).
3. **One Multi Action** — press **Dictate + next field** in a scratch report and
   check both steps land, and that 150 ms is enough of a pause.

## Pages

**Home**

| | | | | |
|---|---|---|---|---|
| Dictate (F4) | Prev field (Shift+Tab) | Next field (Tab) | Switch app (Alt+Tab) | Impression ⚙ (F20) |
| Prev series (F7) | Next series (F8) | Undo (Ctrl+Z) | Redo (Ctrl+Y) | 📁 Number pad |
| 📁 System | 📁 Editing | 📁 PACS tools | 📁 Windowing | 📁 Web & windows |

**Editing (PowerScribe)**

| | | | | |
|---|---|---|---|---|
| Prev field (Shift+Tab) | Next field (Tab) | **Dictate + next field** ⛓ | Impression ⚙ (F20) | Paste (Ctrl+V) |
| Undo (Ctrl+Z) | Redo (Ctrl+Y) | **Report → Claude** ⛓ | Sign ⚙ (F19) | Dictate (F4) |
| strip | | | | |

Report → Claude sends Ctrl+A, Ctrl+C, Left and then opens claude.ai: the report
is on the clipboard, ready to paste, and the Left collapses the selection so
nothing can be overtyped. Paste sits in the other row, at the far end, so it is
never next to it. Dictate takes the (4,1) slot here as on every other page, so
this page has no separate Dictate in the top-left corner.

**PACS tools**: Ruler (R), ROI (Shift+R), Magnify (Y), CLAHE (Shift+C), Delete
measurement (Delete); Prev series (F7), Next series (F8), W/L 8 Lung (8), W/L 1
Soft tissue (1), Dictate (F4); strip — and its own column holds
📁 **PACS more** rather than Number pad, since that is the only link to it.

**PACS more**: Spine labeling ⚙ (F13), Localizer ⚙ (F14), Scout lines ⚙ (F15),
Invert ⚙ (F18), Zoom in ⚙ (F16); Zoom out ⚙ (F17), W/L 2 Bone (2), W/L 3 Brain
(3), Next series (F8), Dictate (F4); the full strip, so PACS tools is back in
column 2.

**Windowing**: the nine RadMapper presets on digits 1–9 (Soft tissue, Bone, Brain,
C-spine soft tissue, CTA, Infarct, Liver, Lung, Lung wide), Dictate (F4), strip.

**Number pad**

| | | | | |
|---|---|---|---|---|
| Backspace | 7 | 8 | 9 | Enter |
| . | 4 | 5 | 6 | 0 |
| 🏠 Home | 1 | 2 | 3 | 📁 Web & windows |

The digits are a 3×3 block in the middle three columns; 0 finishes the middle
row and `.` starts it, so neither sits where a keyboard numpad puts it — this
is a Stream Deck layout, not a numpad copy. Backspace and Enter are the top
corners, Home and Web & windows the bottom corners. Column 4 still holds the
Web key the strip would put there, so only columns 1–3 deviate from the usual
page shape, and it is the one page without Dictate at (4,1).

The keys send the top-row digits, not the numeric keypad, so they work with
NumLock off (RadMapper uses NumLock as its pause key). These are the same keystrokes as the Windowing digits, so with
IntelliSpace in front any digit is read as a window preset, not as a number —
type numbers only into PowerScribe.

**Web & windows**: mail.umn.edu, claude.ai, openevidence.com, umnradiology.com,
**Open all sites** ⛓; Snap left/right (Win+←/→), window to left / right monitor
(Win+Shift+←/→), Dictate (F4); strip.

**System**: RadMapper Settings (Ctrl+Alt+Shift+F9), Pause/resume engine
(Ctrl+Alt+Shift+F11), Unstick buttons (Ctrl+Alt+Q), Clipboard history
(Ctrl+Alt+C), Scratchpad (Ctrl+Alt+N); Task view (Win+Tab), Show desktop
(Win+D), Maximize (Win+↑), Minimize (Win+↓), Dictate (F4); strip. Close window
(Alt+F4) is deliberately not on the deck — one stray press closes PowerScribe.

⛓ = a Stream Deck **Multi Action**: several steps in one press, run by the
Stream Deck software itself.

## Native keys, and where RadMapper still helps

The buttons send the apps' own shortcuts, so they work with or without
RadMapper running. The catch is that a Stream Deck keystroke goes to whatever
window is in front:

- **PowerScribe keys** (F4, Tab, Shift+Tab, Undo/Redo/Copy/Paste, Impression, Sign)
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

These two do something destructive to the front window, so check what has
focus first:

| Button | Sends | With the PACS viewer in front | With PowerScribe in front |
|---|---|---|---|
| Delete measurement | Delete | deletes the selected measurement | **deletes report text** (the selection, or the character after the cursor) |
| Report → Claude ⛓ | Ctrl+A, Ctrl+C, Left, open claude.ai | selects everything the viewer will select and copies it | selects the report, copies it, then Left collapses the selection: the caret ends up at the **top of the report with nothing selected**, not in a field. Press **Next field** to get back into a field before dictating. |

## Buttons marked with the gear badge ⚙

IntelliSpace and PowerScribe One shortcuts are configured per user, and
RadMapper deliberately does not guess them. Assign the key to the function once
in the app and the button is live:

| Button | Sends | Where to assign it |
|---|---|---|
| Spine labeling | F13 | IntelliSpace > Preferences > Keyboard shortcuts |
| Localizer mode | F14 | same |
| Scout line mode | F15 | same |
| Zoom in | F16 | same |
| Zoom out | F17 | same |
| Invert | F18 | same |
| Sign report | F19 | PowerScribe One > Settings > Quick Keys |
| Impression | F20 | PowerScribe One > Settings > Quick Keys |

**Why F13–F20.** These keys exist in the keyboard protocol but on no keyboard
you own, so nothing else on the machine sends them and they can never type a
character into a report — which is exactly what a bare letter or a digit would
do if the wrong window had focus. The catch is that some shortcut recorders
refuse to record F13 and above: **test one in each app before assigning all of
them** (try F13 in IntelliSpace and F19 in PowerScribe One). If a recorder
refuses, pick any unused combination it does accept and edit that one key in
the Stream Deck app.

If your site already has a shortcut for one of these, edit that button in the
Stream Deck app instead (click the key, change the hotkey) or change the key
name in `build_profile.py` and rebuild.

## Editing the icons

`build_profile.py` draws each icon with a few primitives (`ic_ruler`,
`ic_spine`, ...). Change a drawing function, run the script, re-import the
profile. Icons are 288×288 PNG, drawn at 4× and downsampled.
