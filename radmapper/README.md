# RadMapper 0.7.2

A single-file mouse and keyboard remapper for the reading room (PowerScribe +
IntelliSpace). Everything is in `RadMapper.ahk`: no installer, no folders.

**This is a review build.** It has been checked for syntax balance, by reading,
and by the portable checks below, but it has not yet run on a Windows
workstation. Treat it as a candidate for testing.

**0.7.1 starts fresh.** The first time 0.7.1 loads an existing config, it
copies it aside as `RadMapperConfig.pre-reset-<date>.json` in the config
folder (`%APPDATA%\RadMapper`) and starts from the shipped defaults. This
happens once. To get the old setup back, use **Import config…** on that file.

## Try it in two minutes (Windows)

1. Install **AutoHotkey v2** from https://www.autohotkey.com (the v2 installer, not v1).
2. Double-click `RadMapper.ahk`. A tray icon appears and the settings window
   opens on **Home** the first time each version runs.
3. On Home, pick what you want to do:
   - **Change what a mouse button does** (opens the Mouse page: click a part
     of the mouse, then Add new opens the binding editor)
   - **Change what a keyboard key does**
   - **Apply a starter pack** (one click sets up a common arrangement, such as
     PowerScribe on the thumb buttons or PACS zoom and pan; anything
     it would replace is listed first, and the result is ordinary settings you
     can edit or delete on the Mouse page)

To watch every button light up as you press it, use **Test my mouse and
keyboard…** on the Diagnostics page.

**Shipped defaults are active:** a tap of CapsLock or the backtick key toggles
dictation (CapsLock is seeded once into an existing config too), the two
thumb buttons jump the pointer between monitors on a tap. Review or remove
these on the Mouse and Keyboard pages. Nothing else is remapped until you add
it.

**Radial menus are a separate script** as of 0.7.2. RadMapper no longer draws
them; a row that opened one is dropped on load and named in Diagnostics. If
the radial script uses the thumb buttons in PACS, leave those buttons' PACS
**hold** slots empty here so the two scripts do not both claim them.

**Layers are tabs.** The Mouse and Keyboard pages have a tab strip: **Base**,
**Hold Button 4**, **Hold Button 5** and **Hold CapsLock** by default.
**Layer buttons…** at the end of the tab strip changes which inputs hold a
layer (up to six: middle, right, button 4/5 or any key -- never left), for a
mouse without thumb buttons. A tab shows what every part of the mouse does *while that button is
held*, exactly like a keymap layer in QMK or ZMK. Click a part of the mouse
and its two slots appear on the right, **Tap it** and **Hold it down**, each
with Set/Change and Clear.

**What a button can do (0.7):** a button has a **tap** and a **hold**, and
nothing else. Left, right and middle click are always instant; a hold on them
works only inside one program you name. Only the layer buttons can hold a
layer open; rows under any other layer are dropped on load and named in
Diagnostics.

**Which program a setting follows (0.7.2):** a mouse button or the wheel uses
the window *under the pointer*; a key uses the window you are typing in. So
with PowerScribe focused and the pointer over PACS, your PACS mouse settings
apply. **Toggle engine pause** on a button or key both pauses and resumes. A **wheel deck** (hold a thumb button, turn the wheel) waits for the
wheel to stop before it takes over, so a scroll still in motion stays a scroll.

The window opens in **Simple** view: Home, Mouse, Keyboard, Settings and
Diagnostics, with a short list of actions. The switch on Home, "Show advanced
pages and every action", adds Macros, Apps, Windows and Pointer, the wheel
decks ("Scroll wheel…" on the Mouse and Keyboard pages) and the full action
list. Nothing is lost either way.

Press **F1** in the settings window for quick help. Open the window at any time
with **Ctrl+Alt+Shift+F9** or by double-clicking the tray icon.

## Sending keys to PACS

**Sending keys to PACS from anywhere:** the action **PACS: send keys** works
like the PowerScribe actions. Bind it to any button in any program and the
viewer is brought forward, receives the shortcut, and focus returns to where
you were. It targets the PACS profile on the Apps page and prefers the window
whose title contains "VirtualMonitor" (the IntelliSpace viewer); both are
settings if your PACS differs.

## If something feels wrong

| Problem | Do this |
|---|---|
| A button or modifier seems stuck | Press **Ctrl+Alt+Q**, or **Unstick my buttons** at the bottom of the settings window |
| I want everything native right now | **Ctrl+Alt+Shift+F11** pauses the whole engine; press again to resume. NumLock also pauses. |
| The settings window will not open | Tray icon > *Rendering self-test…* shows whether graphics draw on this machine; copy Diagnostics and send it. The engine keeps working either way. |
| I lost my bindings after updating | You did not. Config lives in `%APPDATA%\RadMapper\RadMapperConfig.json`; the path is shown on Home. |
| The header says "Not saved to disk" | A write to the settings folder failed. Your edits still work in memory; fix access to the folder and make any edit to retry. Details are on the Diagnostics page. |
| A corrupt config was found on start | It was copied next to the original with a `.corrupt-` suffix and defaults were loaded. If that copy could not be made, saving is blocked until you move the file and restart. |

These are the default hotkeys; Home shows the ones actually configured.

## Sharing feedback

The **Diagnostics** page lists anything that went wrong and has a **Copy this
list** button. Paste it into your message with what you pressed and what you
expected. **Test my mouse and keyboard…** on that page opens the live input monitor.

## Checks

- Anywhere: `python3 tests/check_source.py` (structural checks and text
  contrast). It does not parse or run AutoHotkey.
- Windows with AutoHotkey v2:

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut tests\regression.ahk
```

The regression script sets `RM_TEST` so RadMapper's startup (tray, hooks,
hotkeys) is skipped, then exercises the real JSON, config and save helpers
with a temporary config. It installs no bindings.

See `SECOND-PASS.md` for the second-pass findings and remaining Windows checks,
and the changelog at the top of `RadMapper.ahk` for everything since 0.5.2.
