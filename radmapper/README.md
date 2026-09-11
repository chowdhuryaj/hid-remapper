# RadMapper v0.6.0.1a (prototype)

A mouse and keyboard remapper for the reading room (PowerScribe + IntelliSpace).
Everything is one file: `RadMapper.ahk`. No installer, no folders.

## Try it in two minutes

1. Install **AutoHotkey v2** from https://www.autohotkey.com (the v2 installer, not v1).
2. Double-click `RadMapper.ahk`. A tray icon appears and the settings window opens
   on a **Home** page the first time.
3. On Home, pick what you want to do:
   - **Change what a mouse button does**
   - **Change what a keyboard key does**
   - **Test my mouse** (every button lights up as you press it; nothing is changed)
   - **Fix a stuck button** (releases anything RadMapper is holding)

Nothing is remapped until you add a binding, so the mouse and keyboard stay
completely native out of the box (apart from three shipped defaults: `` ` ``
toggles dictation, the two thumb buttons jump the pointer between monitors).

## If something feels wrong

| Problem | Do this |
|---|---|
| A button or modifier seems stuck | Press **Ctrl+Alt+Q** (panic release) or tray icon > *Panic release* |
| I want everything back to native right now | **Ctrl+Alt+Shift+F11** pauses the whole engine; press again to resume. NumLock also pauses. |
| The settings window won't open | Tray icon > *Settings (classic)…* opens the plain Windows version |
| I lost my bindings after updating | You didn't. Config lives in `%APPDATA%\RadMapper\RadMapperConfig.json`; the path is shown on the Settings page. |

Open the settings window at any time with **Ctrl+Alt+Shift+F9** or by
double-clicking the tray icon.

## Sharing feedback

The **Diagnostics** page has a live input monitor and a problem log. Copy the log
(there is a button) and paste it into your message, along with what you
pressed and what you expected to happen.

## What changed in 0.6.0.1a

See the changelog at the top of `RadMapper.ahk`.
