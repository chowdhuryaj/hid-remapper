---
name: ahk-radiology
description: >
  Expert knowledge for writing, fixing, and improving AutoHotkey v2 scripts
  for a radiology workstation. Use this skill whenever the user asks to create,
  add to, debug, or refactor an AHK script that involves PowerScribe (PSOne or
  PS360), a PACS viewer (IntelliSpace or other), dictation control, mouse
  remapping, multi-monitor teleporting, or any hotkey automation in a clinical
  reading environment. Also trigger when the user pastes AHK code and asks what
  is wrong with it, or describes a symptom like "key not working", "taskbar
  flashing", "focus not returning", or "modifier stuck". This skill encodes
  every bug and design decision learned from iteratively building and debugging
  a real radiology workstation script — always read it before writing or editing
  any AHK code in this context.
---

# AHK v2 Radiology Workstation Skill

## Environment at a glance

| App | Process | Notes |
|---|---|---|
| PowerScribe One | `Nuance.PSOne.exe` | Multi-window WPF app; GUID in class |
| PowerScribe 360 | `Nuance.PowerScribe360.exe` | Same caveats; only one runs at a time |
| PACS worklist | `IntelliSpacePACSRadiology.exe` | Title: "Philips IntelliSpace Radiology" |
| PACS DICOM viewer | `IntelliSpacePACSRadiology.exe` | Title: "VirtualMonitor"; SAME process as worklist |
| Dictation toggle key | `{F4}` (default; user-configurable in PS prefs) | |
| Input device | High-res trackball + programmable buttons | XButton1/XButton2 = thumb buttons |

---

## §1 — Critical identification rules

### Always match by EXE, never by title or class for PS and PACS

**PowerScribe** is a WPF app whose `ahk_class` embeds a per-run GUID:
```
HwndWrapper[DefaultDomain;;7cdebc79-5599-43f1-9d7f-2b2f2dd84485]
```
The GUID changes every launch. **Never use `ahk_class` for PowerScribe.**
Title also varies (patient names, study states). **Use `ahk_exe` only.**

**PACS (IntelliSpace)** has two visible windows under one process:
- Worklist: `"Philips IntelliSpace Radiology"` 
- DICOM viewer: `"VirtualMonitor"`

Titles change when a study is loaded. The old codebase used `"iSite"` as the
title match — **this never worked**. Both windows share `IntelliSpacePACSRadiology.exe`.
Match by exe; you catch both windows automatically and survive title changes.

### Detection helpers (canonical forms)

```ahk
; True when EITHER PowerScribe owns the active window
PSActive() {
    global PS_EXES          ; ["Nuance.PowerScribe360.exe", "Nuance.PSOne.exe"]
    for exe in PS_EXES {
        if WinActive("ahk_exe " . exe)
            return true
    }
    return false
}

; True when PACS (IntelliSpace) owns the active window
PACSActive() {
    global PACS_MATCH       ; "ahk_exe IntelliSpacePACSRadiology.exe"
    return WinActive(PACS_MATCH) ? true : false
}
```

---

## §2 — The PowerScribe focus / keystroke problem

### Root cause of the "taskbar flash" bug

PowerScribe One has **multiple top-level windows** (ribbon, dictation bar, report
editor, etc.). `WinExist("ahk_exe Nuance.PSOne.exe")` returns the **first** hwnd
Windows enumerates — which is almost never the one that currently has focus.

Old pattern (broken):
```ahk
target := WinExist("ahk_exe Nuance.PSOne.exe")   ; wrong hwnd
WinActive("ahk_id " . target)                     ; always false even when PS is focused
WinActivate("ahk_id " . target)                   ; tries to raise the wrong window -> flash
```
Symptoms: taskbar icon flashes, keystroke lands nowhere or in the wrong field,
and the behaviour is the same whether you're in PACS *or already inside PS*.

### Correct pattern — PSFire

Never target a specific hwnd. Check and activate **by exe**:

```ahk
PSFire(keys) {
    global PS_EXES, RETURN_DELAY

    if PSActive() {             ; already in PS (any PS window) -> just press the key
        Send(keys)
        return
    }

    win := ""
    for exe in PS_EXES {
        if WinExist("ahk_exe " . exe) {
            win := "ahk_exe " . exe
            break
        }
    }
    if (win = "")
        return                  ; PS not running -> do nothing

    prev := WinExist("A")
    try WinActivate(win)
    if !WinWaitActive(win, , 1)
        return                  ; failed to bring PS forward -> don't misfire
    Sleep(50)
    Send(keys)
    if prev {
        Sleep(RETURN_DELAY)     ; global, default 60 ms
        try WinActivate("ahk_id " . prev)
    }
}
```

Key principles:
- `PSActive()` first — if already in PS, just `Send(keys)` and return. No activation.
- Activate by **exe string**, not hwnd.
- `WinWaitActive` to confirm before sending — if it fails, bail rather than misfire.
- `try` on both `WinActivate` calls — window may vanish between check and activate.
- **Do NOT call `WinRestore`** on PS — it will un-maximize a full-screen PS window.

---

## §3 — Mouse button remapping patterns

### Context gating with `#HotIf`

Use function-based `#HotIf` expressions so hotkeys are scoped to one app.
Declare contexts from **most specific → least specific**; AHK evaluates them in
order and the last match wins within the same key.

```ahk
#HotIf PACSActive()
XButton1::PacsTapOrDrag("XButton1", "r", "LAlt")
XButton2::PacsTapOrDrag("XButton2", "m", "LCtrl")

#HotIf PSActive()
XButton1::PsTapOrRepeat("XButton1", "Backspace")
XButton2::PsTapOrRepeat("XButton2", "Delete")

#HotIf     ; close the block — restores native behaviour everywhere else
```

Buttons NOT listed inside a `#HotIf` block keep their native OS function.
**Never remap a button globally if you only need it contextually.**

### Tap-vs-hold detection

```ahk
global TAPHOLD := 0.2   ; seconds; tune to taste

; PACS: tap = keystroke, hold = modifier+left-drag
PacsTapOrDrag(btn, tapKey, modKey) {
    global TAPHOLD
    if KeyWait(btn, "T" . TAPHOLD) {        ; released before timeout -> tap
        Send(tapKey)
        return
    }
    ; held -> modifier drag; try/finally guarantees release on any exit
    Send("{" . modKey . " Down}{LButton Down}")
    try {
        KeyWait(btn)
    } finally {
        Send("{LButton Up}{" . modKey . " Up}")
    }
}

; PowerScribe: tap = one key, hold = auto-repeat
PsTapOrRepeat(btn, key) {
    global TAPHOLD, REPEAT_RATE
    Send("{" . key . "}")
    if KeyWait(btn, "T" . TAPHOLD)
        return
    safety := 0
    while GetKeyState(btn, "P") {
        if KeyWait(btn, "T" . REPEAT_RATE)
            break
        safety += 1
        if (safety > 400)       ; ~20 s hard cap
            break
        Send("{" . key . "}")
    }
}
```

### Middle button — do not intercept

**Do not remap MButton** in these apps. The previous implementation held
`{MButton Down}` synthetically and relied on a matching `Up` that didn't always
land, leaving the button logically stuck — every subsequent click then behaved
like a middle-click and the script appeared to "stop working". The middle button
is native in all contexts. If dictation on middle-click is ever requested again,
the only safe approach is `~MButton` (passthrough) with the dictation as a
*side effect*, accepting that every middle-click also dictates.

---

## §4 — Multi-monitor teleport

Sorts monitors left-to-right by physical X position (not OS enumeration order)
so `step = -1` always goes visually left and `step = +1` always goes right,
wrapping at the edges.

```ahk
TeleportMonitor(step) {
    mons := _MonitorsByX()
    n := mons.Length
    if (n < 1)
        return
    MouseGetPos(&mx, &my)
    cur := 1
    Loop n {
        m := mons[A_Index]
        if (mx >= m.l && mx < m.r && my >= m.t && my < m.b) {
            cur := A_Index
            break
        }
    }
    tgt := Mod(cur - 1 + step + n, n) + 1
    m := mons[tgt]
    DllCall("SetCursorPos", "int", (m.l + m.r) // 2, "int", (m.t + m.b) // 2)
}
```

---

## §5 — Script-level boilerplate

Always include at the top. The trackball fires wheel hotkeys very fast; without
the raised rate limit AHK shows a warning popup.

```ahk
#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
SendMode "Input"
CoordMode "Mouse", "Screen"
SetTitleMatchMode 2

A_MaxHotkeysPerInterval := 2000
A_HotkeyInterval := 1000
```

### Global config block (§1 in the script)

All tunable values live here so they're easy to find and change:

```ahk
global PS_EXES      := ["Nuance.PowerScribe360.exe", "Nuance.PSOne.exe"]
global KEY_DICTATE  := "{F4}"          ; confirm in PS > Tools > Preferences > Keyboard
global RETURN_DELAY := 60              ; ms before returning focus to prior window
global PACS_MATCH   := "ahk_exe IntelliSpacePACSRadiology.exe"
global TAPHOLD      := 0.2            ; seconds, tap-vs-hold threshold
global REPEAT_RATE  := 0.05           ; seconds between auto-repeat keystrokes
```

---

## §6 — Safety net

Add a global panic hotkey to force-release any stuck modifier or button:

```ahk
^!+F12::Send("{LButton Up}{RButton Up}{MButton Up}{LCtrl Up}{RCtrl Up}{LAlt Up}{RAlt Up}{LShift Up}{RShift Up}{LWin Up}{RWin Up}")
```

---

## §7 — Debugging checklist

When something doesn't fire or behaves wrongly, work through this list:

1. **Taskbar flash on PS hotkeys** → `PSFire` is targeting a wrong hwnd.
   Fix: use `PSActive()` (exe-based) for the "already in PS" check.

2. **PACS hotkey fires in wrong app** → title-based `PACS_MATCH` drifted.
   Fix: switch to `ahk_exe IntelliSpacePACSRadiology.exe`.

3. **Modifier or button stuck** → a `Down` was sent without a guaranteed `Up`.
   Fix: wrap the hold logic in `try/finally`; press the panic hotkey (`^!+F12`)
   to recover the current session.

4. **Hotkey fires in all windows** → missing or mis-ordered `#HotIf` / `#HotIf`
   closing block. Every context block needs a bare `#HotIf` at the end.

5. **`WinActive` returns false when window looks focused** → you're checking
   a specific hwnd but a *different* window of the same app actually has focus.
   Fix: check by exe string instead.

6. **Auto-repeat runs away and deletes the whole field** → `PsTapOrRepeat` is
   missing the safety cap or the `GetKeyState` physical-key check.

7. **Script won't load / hotkeys missing** → v1 syntax in a v2 file. Common
   v1→v2 traps: `%var%` → `var`, `IfWinActive` → `WinActive()`, `WinActivate,`
   → `WinActivate()`, `Sleep, 100` → `Sleep(100)`, `#IfWinActive` → `#HotIf`.

---

## §8 — How to get Window Spy info

When adding support for a new app, always ask for Window Spy output:

```
Window Spy is in the AHK tray icon right-click menu.
Hover the target window and note:
  - ahk_exe   ← primary identifier (use this)
  - ahk_class ← useful only if it's static (no GUIDs, no addresses)
  - title     ← use only if it never changes
```

---

## §9 — Requesting changes from the user

When the user describes a new remap or feature, clarify:

- **Tap vs hold?** Does the button do one thing on a quick press and something
  else when held, or the same thing either way?
- **Which apps?** PACS only, PS only, both, or global?
- **Both PACS windows?** Worklist and viewer, or just the viewer?
- **Hold behaviour for drags:** single modified click, or press-and-hold so you
  can drag (hold modifier + hold LButton until physical release)?
- **Hold behaviour for key-repeat:** auto-repeat (like a held keyboard key), or
  just fire once?
- **Return focus?** When firing into PS from PACS, always return to PACS after?
- **Native fallback?** What should the button do in all other apps?

---

## §10 — Current script section map

| Section | What it contains |
|---|---|
| §1 CONFIG | All globals/tunable constants |
| (helpers) | `PACSActive()`, `PSActive()`, `PSFire()`, `PacsTapOrDrag()`, `PsTapOrRepeat()` |
| §3 | PowerScribe hotkeys: `` ` `` dictate, F13 prev-field, F14 next-field |
| §4 | Multi-monitor mouse teleport: Shift+F7 / Shift+F8 |
| §5 | Context-sensitive XButton1/XButton2 (PACS: R/M/drag; PS: Backspace/Delete) |
| §6 | Emergency key release: Ctrl+Alt+Shift+F12 |

---

## §11 — Load-time and first-run traps (learned from RadMapper 0.6.x reviews)

No AutoHotkey runtime is available in the cloud sessions where this code is
written, so every one of these reached the workstation before it was caught.
Check for them by reading, or with a scanner like `radmapper/tests/check_source.py`,
**before** handing over a file.

### Names are case-insensitive — everywhere

- **Variables.** `W := R.wedges` then `w := W.slices[i]` overwrite the *same*
  variable. Parses fine, throws on the first run ("no property named slices").
  Never use `W` and `w`, `B` and `b`, etc. in one function. Rename the
  collection (`WD`, `bands`), not the loop variable.
- **Nested functions vs parameters.** `RadialIcon(name, x, y)` containing
  `X(d) => Round(x + d)` fails to load: "This function declaration conflicts
  with an existing parameter". Same for a nested name matching any local.
  Prefix nested helpers (`gX`, `gY`).
- **Locals vs classes and functions.** `line := 0x58…` then `Line(x, y, …)`
  in the same function: `Line` is a GpGFX *class*, i.e. a variable holding
  a Class object, so the call goes through the local integer and throws
  "This value of type Integer is not callable". Never name a local or
  parameter after a class or function the body calls (`Line`, `Text`,
  `Rectangle`, `Picture`, `Layer`, `HUD`, …).
- **Class members.** `static grab := false` beside `static Grab()` in the same
  class either refuses to load ("Duplicate declaration") or the static
  initialiser clobbers the method. Scan every class, not just the big ones.

### `try` one-liners

```ahk
if cond
    try Foo()        ; the brace-less try takes the else as ITS else clause
else                 ; -> "Unexpected Else" at load
    Bar()
```
A braced `try { … }` takes the `else` too (v2 `try` has its own `else`
clause). Put the braces on the `if`/`else` and the one-line `try` inside:
`if cond {` / `    try Foo()` / `} else {` / `    Bar()` / `}`. A one-line `try`
followed by `catch` on the next line is fine.

### Timers, hooks, contexts

- `SetTimer(ObjBindMethod(obj, "M"), -120)` creates a **new** BoundFunc each
  call, so `SetTimer(fn, 0)` can never cancel it. Cache the BoundFunc in a
  static and cancel that one on close/panic/exit.
- `HotIf(fn)` persists for the rest of the thread. Wrap every
  `HotIf(...); Hotkey(...)` group in `try { … } finally { HotIf() }`, or a
  throw leaves the panic key and pause key gated on a stale condition.
- Two hotkey handlers can fire for one press: a `~`-prefixed hotkey (e.g.
  `~Space` for a focus manager) does not suppress the key, so an InputHook
  elsewhere (a keyboard pointer) also sees it. Gate each handler on the
  other's state.

### Sending input from an overlay

- `{Blind}` preserves whatever modifiers are physically down. A "click" sent
  while Ctrl+Alt is still held from the hotkey that opened the overlay is a
  Ctrl+Alt+click — in IntelliSpace that is window/level, not a click. Send
  explicit `{LCtrl Up}{RCtrl Up}{LAlt Up}{RAlt Up}{LShift Up}{RShift Up}`
  first for any click/drag/wheel from an overlay.
- Windows delivers `WM_MOUSEWHEEL` to the **focused** window. To scroll the
  window under a point, `WindowFromPoint` + `PostMessage(0x020A, …)`.

### Monitors and DPI

- Call `SetProcessDpiAwarenessContext(-4)` at the top of the auto-execute
  section, before anything reads `MonitorGet`/`MonitorGetWorkArea`. Lazy
  awareness (set when the first GDI+ layer is created) means config load and
  the first station key see *virtualised* coordinates on a 125 %/150 % display.
- `WinMove` then `WinMaximize` maximises onto the monitor with the largest
  intersection: size the window to fit the target monitor before maximising.
- Skip owned windows (`GetWindow(hwnd, 4)`) and windows without
  `WS_THICKFRAME` when arranging; PowerScribe's "Sign report?" dialog is
  otherwise claimed by the report-editor slot.

### System-wide side effects that must be undone

- `SetSystemCursor` hides the pointer for **every** application; restore it
  from `OnExit`, `OnError`, the panic key, *and* a watchdog tick, because a
  hard kill runs none of the exit paths.
- `SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0)` persists for the
  login session; read the old value (SPI 0x2000) first and restore it on exit.

### UIA / COM

- `IUIAutomationElement` vtable: `ElementFromPoint` = 7 on the automation
  object, `get_CurrentName` = 23, `get_CurrentBoundingRectangle` = **42**
  (43 is `get_CurrentLabeledBy`, which returns a pointer and looks like a
  garbage rect). Free BSTRs in `finally`; drop the cached UIA object when a
  call fails so the next press re-creates it.

### Portable checks worth keeping in the repo

A Python script that runs without AutoHotkey can assert: case-insensitive
member collisions in every class; nested function names vs enclosing
parameters; case-variant variable names within one function; one-line `try`
between an `if` and its `else`; cached timer BoundFuncs; text/background
contrast pairs; and that hard-coded UI offsets fit the minimum window width.
Run it on every commit; it has paid for itself several times.
