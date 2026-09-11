# RadMapper 0.6.0.2-preview

A single-file mouse and keyboard remapper for the reading room (PowerScribe +
IntelliSpace). Everything is in `RadMapper.ahk`: no installer, no folders.

**This is a review build.** It has been checked for syntax balance, by reading,
and by the portable checks below, but it has not yet run on a Windows
workstation. Treat it as a candidate for testing.

## Try it in two minutes (Windows)

1. Install **AutoHotkey v2** from https://www.autohotkey.com (the v2 installer, not v1).
2. Double-click `RadMapper.ahk`. A tray icon appears and the settings window
   opens on **Home** the first time each version runs.
3. On Home, pick what you want to do:
   - **Change what a mouse button does**
   - **Change what a keyboard key does**
   - **Set up a radial menu** (commands around the pointer, picked by direction)
   - **Test my mouse** (every button lights up as you press it; nothing is changed)

**Shipped defaults are active:** the backtick key toggles dictation, and the two
thumb buttons jump the pointer between monitors. Review or remove these on the
Mouse and Keyboard pages. Nothing else is remapped until you add it.

Press **F1** in the settings window for quick help. Open the window at any time
with **Ctrl+Alt+Shift+F9** or by double-clicking the tray icon.

## Set up one radial menu

1. **Home → Set up a radial menu → Edit commands.** Start with four directions.
   Give each a label, choose **Send keys**, then use **Rec** to record the
   shortcut from your viewer's settings. Leave unused directions Disabled.
2. Save, select the menu, and choose **Assign a button**. The menu and the Hold
   trigger are prefilled; pick the program and button, then save.
3. Choose **Practice safely**. Practice never sends a command. In real use, hold
   the assigned button, move toward a command, and release. Release in the
   centre or press Escape to cancel.
4. Verify one assignment in the intended app before adding more. PACS shortcuts
   vary by site, so the supplied PACS labels deliberately have no keys.

## If something feels wrong

| Problem | Do this |
|---|---|
| A button or modifier seems stuck | Press **Ctrl+Alt+Q**, or **Unstick my buttons** at the bottom of the settings window |
| I want everything native right now | **Ctrl+Alt+Shift+F11** pauses the whole engine; press again to resume. NumLock also pauses. |
| The settings window will not open | Tray icon > *Settings (classic)…* opens the plain Windows version |
| I lost my bindings after updating | You did not. Config lives in `%APPDATA%\RadMapper\RadMapperConfig.json`; the path is shown on Home. |
| The header says "Not saved to disk" | A write to the settings folder failed. Your edits still work in memory; fix access to the folder and make any edit to retry. Details are on the Diagnostics page. |
| A corrupt config was found on start | It was copied next to the original with a `.corrupt-` suffix and defaults were loaded. If that copy could not be made, saving is blocked until you move the file and restart. |

These are the default hotkeys; Home shows the ones actually configured.

## Sharing feedback

The **Diagnostics** page lists anything that went wrong and has a **Copy this
list** button. Paste it into your message with what you pressed and what you
expected. **Test my mouse and keyboard…** on that page opens the live input monitor.

## Preview on a Mac

`RadMapper-preview.html` opens in Safari or Chrome, works offline with sample
data, and cannot remap anything. It is a design prototype of a possible next
interface (a visual wheel editor); the Windows build uses a direction table with
the same setup sequence.

## Checks

- Anywhere: `python3 tests/check_source.py` (structural checks and text contrast)
  and `node tests/mockup.cjs`. Neither parses or runs AutoHotkey.
- Windows with AutoHotkey v2:

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut tests\regression.ahk
```

The regression script sets `RM_TEST` so RadMapper's startup (tray, hooks,
hotkeys) is skipped, then exercises the real JSON, config, menu and save helpers
with a temporary config. It installs no bindings.

See `SECOND-PASS.md` for the second-pass findings and remaining Windows checks,
and the changelog at the top of `RadMapper.ahk` for everything since 0.5.2.
