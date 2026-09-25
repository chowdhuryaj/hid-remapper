# RadMapper 0.7.1

A single-file mouse and keyboard remapper for the reading room (PowerScribe +
IntelliSpace). Everything is in `RadMapper.ahk`: no installer, no folders.

**This is a review build.** It has been checked for syntax balance, by reading,
and by the portable checks below, but it has not yet run on a Windows
workstation. Treat it as a candidate for testing.

**0.7.1 starts fresh.** The first time 0.7.1 loads an existing config, it
copies it aside as `RadMapperConfig.pre-reset-<date>.json` in the config
folder (`%APPDATA%\RadMapper`) and starts from the shipped defaults. This
happens once. To get the old setup back, use **Import config…** on that file.

**Running RadWheel too.** RadMapper writes `RadMapperHooks.txt` in its
config folder: the buttons and keys it has hooked right now, empty while
paused. RadWheel (`../radwheel`) reads it and never takes those inputs, so
the two scripts never fight over a button. Pause RadMapper and RadWheel gets
them back within 3 s.

## Try it in two minutes (Windows)

1. Install **AutoHotkey v2** from https://www.autohotkey.com (the v2 installer, not v1).
2. Double-click `RadMapper.ahk`. A tray icon appears and the settings window
   opens on **Home** the first time each version runs.
3. On Home, pick what you want to do:
   - **Change what a mouse button does** (opens the Mouse page: click a part
     of the mouse, then Add new opens the binding editor)
   - **Change what a keyboard key does**
   - **Set up a radial menu** (commands around the pointer, picked by direction)
   - **Apply a starter pack** (one click sets up a common arrangement, such as
     PowerScribe on the thumb buttons or the PACS wheel on button 4; anything
     it would replace is listed first, and the result is ordinary settings you
     can edit or delete on the Mouse page)

To watch every button light up as you press it, use **Test my mouse and
keyboard…** on the Diagnostics page.

**Shipped defaults are active:** a tap of CapsLock or the backtick key toggles
dictation (CapsLock is seeded once into an existing config too), the two
thumb buttons jump the pointer between monitors on a tap, and inside PACS a
**hold** of button 4 opens the PACS wheel and a hold of button 5 the window
presets. Review or remove these on the Mouse and Keyboard pages. Nothing else
is remapped until you add it.

**Layers are tabs.** The Mouse and Keyboard pages have a tab strip: **Base**,
**Hold Button 4**, **Hold Button 5** and **Hold CapsLock** -- the only three
layers. A tab shows what every part of the mouse does *while that button is
held*, exactly like a keymap layer in QMK or ZMK. Click a part of the mouse
and its two slots appear on the right, **Tap it** and **Hold it down**, each
with Set/Change and Clear.

**What a button can do (0.7):** a button has a **tap** and a **hold**, and
nothing else. Left, right and middle click are always instant; a hold on them
works only inside one program you name. Only the thumb buttons and CapsLock
can hold a layer open; rows under any other layer are dropped on load and named
in Diagnostics. A **wheel deck** (hold a thumb button, turn the wheel) waits for the
wheel to stop before it takes over, so a scroll still in motion stays a scroll.

The window opens in **Simple** view: Home, Mouse, Keyboard, Menus, Settings and
Diagnostics, with a short list of actions. The switch on Home, "Show advanced
pages and every action", adds Macros, Apps, Windows and Pointer, the wheel
decks ("Scroll wheel…" on the Mouse and Keyboard pages) and the full action
list. Nothing is lost either way.

Press **F1** in the settings window for quick help. Open the window at any time
with **Ctrl+Alt+Shift+F9** or by double-clicking the tray icon.

## Radial menus

A **PACS** menu ships ready to use: Next series (F8) up, Prev series (F7) down,
Ruler (R), ROI (Shift+R), Magnify (Y), Delete, CLAHE (Shift+C), and
**Windowing**, which opens a second ring of numbered window presets (1 Soft
tissue, 2 Bone, 3 Brain, 4 C-spine soft tissue, 5 CTA, 6 Infarct, 7 Liver,
8 Lung, 9 Lung wide). Rename any of these on the Menus page to match your site.

**In PACS it is already on the thumb buttons:** hold **button 4** for the
PACS wheel, hold **button 5** for the window presets. A tap of either still
hops the pointer between monitors.

1. **Hold** the button, **move** toward a command, **release**. Release in
   the centre hub, or press Escape, and nothing fires.
2. For a preset: hold button 5, move to the number, release. (From the PACS
   wheel: hold 4, move to **Windowing**, pause, move to the number, release.)
3. A menu only ever opens while a button is **held**; there is no tap-opened
   menu, so letting go is always the way out.
4. To put a menu on another button: **Menus → select the menu → Assign a
   button**. The Hold trigger is the only one a menu accepts.
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
| The settings window will not open | Tray icon > *Rendering self-test…* shows whether graphics draw on this machine; copy Diagnostics and send it. The engine keeps working either way. |
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
