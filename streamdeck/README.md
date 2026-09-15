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
| `keymap.md` | Every button, the key it sends, and where that key came from |
| `build_profile.py` | Regenerates all of the above (`python3 build_profile.py`; needs Pillow) |

## Layout

**Home** (launch pad)

| | | | | |
|---|---|---|---|---|
| Dictate (`` ` ``) | Prev field (`]`) | Next field (`[`) | Switch app (Alt+Tab) | Show desktop (Win+D) |
| Prev series (F7) | Next series (F8) | Window to left monitor (Win+Shift+←) | Window to right monitor (Win+Shift+→) | 📁 Windows |
| 📁 Editing (PowerScribe) | 📁 PACS tools | 📁 Windowing | 📁 Number pad | 📁 Websites |

**Editing (PowerScribe)**: Dictate, Prev/Next field, Impression (Ctrl+Shift+1), Undo, Redo, Select all, Copy, Paste, Backspace, Delete forward, Top of report (Ctrl+Home), End of report (Ctrl+End), Sign ⚙.

**PACS tools**: Ruler, ROI, Magnify, CLAHE (Shift+C), Spine labeling ⚙, Localizer ⚙, Scout lines ⚙, Zoom in ⚙, Zoom out ⚙, Prev/Next series, Delete, Invert ⚙, and a door to Windowing.

**Windowing**: the nine RadMapper presets on digits 1–9 (Soft tissue, Bone, Brain, C-spine soft tissue, CTA, Infarct, Liver, Lung, Lung wide), 0 as a spare, Invert ⚙, Magnify, CLAHE, and a door back to PACS tools.

**Number pad**: 0–9, `-`, `.`, Backspace, Enter. Sends the top-row digit keys, not the numeric keypad, so it works with NumLock off (RadMapper uses NumLock as its pause key).

**Websites**: mail.umn.edu, claude.ai, openevidence.com, umnradiology.com.

**Windows**: Snap left/right (Win+←/→), Maximize/Minimize (Win+↑/↓), Move window to left/right monitor (Win+Shift+←/→), Task view (Win+Tab), Switch app (Alt+Tab), Show desktop (Win+D), Close window (Alt+F4), then RadMapper's own hotkeys: Settings (Ctrl+Alt+Shift+F9), Pause/resume engine (Ctrl+Alt+Shift+F11), Unstick buttons (Ctrl+Alt+Q), Clipboard history (Ctrl+Alt+C).

Every folder page has **Back** in its top-left key.

## How it fits with RadMapper

The Stream Deck only sends keystrokes to whatever window is in front. RadMapper
is what makes the PowerScribe keys work from anywhere:

- `` ` ``, `[` and `]` are RadMapper's **shipped global bindings** (`ps_dictate`,
  `ps_next`, `ps_prev`). RadMapper brings PowerScribe forward, delivers F4 / Tab /
  Shift+Tab, and returns focus. So Dictate and field navigation work while the
  PACS viewer has the cursor. If you delete those bindings on RadMapper's
  Keyboard page, these three buttons stop working.
- The PACS keys (R, Shift+R, Y, Shift+C, F7, F8, Delete, digits 1–9) are the
  values in RadMapper's shipped PACS wheel and Window-preset ring. They go
  straight to IntelliSpace, so the viewer must be the active window. If you
  want them to work from PowerScribe too, bind the same keys on RadMapper's
  Keyboard page to **PACS: send keys** with the same value.
- The Windows page's last four keys are RadMapper's default hotkeys from
  Settings. If you changed them there, change them here (or in
  `build_profile.py`) to match.

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
