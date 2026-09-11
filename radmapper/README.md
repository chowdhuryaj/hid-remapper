# RadMapper 0.6.1-preview

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
   - **Apply a starter pack** (one click sets up a common arrangement, such as
     PowerScribe on the thumb buttons or the PACS wheel on button 4; anything
     it would replace is listed first, and the result is ordinary settings you
     can edit or delete on the Mouse page)

To watch every button light up as you press it, use **Test my mouse and
keyboard…** on the Diagnostics page.

**Shipped defaults are active:** the backtick key toggles dictation, and the two
thumb buttons jump the pointer between monitors. Review or remove these on the
Mouse and Keyboard pages. Nothing else is remapped until you add it.

The window opens in **Simple** view: Home, Mouse, Keyboard, Menus, Settings and
Diagnostics, with a short list of actions. The switch on Home, "Show advanced
pages and every action", adds Layers, Macros, Apps, Windows and Pointer and the
full action list. Nothing is lost either way.

Press **F1** in the settings window for quick help. Open the window at any time
with **Ctrl+Alt+Shift+F9** or by double-clicking the tray icon.

## Radial menus

A **PACS** menu ships ready to use: Next series (F8) up, Prev series (F7) down,
Ruler (R), ROI (Shift+R), Magnify (Y), Delete, CLAHE (Shift+C), and
**Windowing**, which opens a second ring of numbered window presets (1 Soft
tissue, 2 Bone, 3 Brain, 4 C-spine soft tissue, 5 CTA, 6 Infarct, 7 Liver,
8 Lung, 9 Lung wide). Rename any of these on the Menus page to match your site.

1. **Menus → select PACS → Assign a button.** The Hold trigger is prefilled;
   pick the button, then save.
2. **Hold** that button, **move** toward a command, **release**. Release in
   the centre hub, or press Escape, and nothing fires.
3. For a preset: hold, move to **Windowing**, pause a moment and the preset
   ring appears under the cursor, move to the number, release.
4. If the menu is bound to a **tap** instead, it stays open: rest on a command
   to fire it, or **tap the button again to close it**.
5. **Practice safely** on the Menus page shows the wheel without sending anything.

**Sending keys to PACS from anywhere:** the action **PACS: send keys** works
like the PowerScribe actions. Bind it to any button in any program and the
viewer is brought forward, receives the shortcut, and focus returns to where
you were. It targets the PACS profile on the Apps page and prefers the window
whose title contains "VirtualMonitor" (the IntelliSpace viewer); both are
settings if your PACS differs.

To edit a menu, use **Edit commands**: each row has a label, an action, the
recorded shortcut, and an icon. A row set to "Radial menu" opens another menu
inside this one. Size 9 is the numbered ring for presets.

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
