# RadWheel handoff

**Objective.** RadMapper's radial menu as a separate, simple AHK v2 script
for radiologists (Kando-style gesture + Stream-Deck-style setup). Main use:
PACS tool selection, replacing the right-click where reasonable. Per-wheel
activation is programmable: hold and/or tap-to-toggle.

**State.** `radwheel/RadWheel.ahk` (single file), README, `tests/check_source.py`.
Branch `claude/relaxed-hamilton-88wxwj`. Not yet run under AutoHotkey.

## Decisions
- Standalone: own GDI+ layered-window renderer (no GpGFX), INI config
  (UTF-16, quoted values, `\n` escapes), sections `[Menu <name>]` in order.
- Per wheel: trigger, Hold (opens | same as tap), Tap (toggle | native |
  none | any command, edited as the wheel's centre), Move (flick | drag
  passthrough), Works in (program under pointer for mouse triggers).
- Slots 4/6/8/9/10/12, slot 1 north, clockwise, full sectors; 4<->8 keeps
  compass slots. Submenus open on rest, on crossing the ring, or on
  release (then stay open for a click).
- Right-click menu action (`rclick`): right-click at the wheel's origin,
  find items by text via MSAA, click them (`RightClickMethod` click|action);
  `#N` keyboard fallback; "Read menu…" reads a 2-level tree for picking.
- Speed: ring bitmaps cached per (menu, scale, config stamp) and pre-warmed;
  click/Esc/digit hotkeys registered only while open; timeBeginPeriod(1)
  only while open; no paint for fast flicks.
- Defaults: PACS tools on hold RButton in PACS (tap = native menu), Window
  presets on button 5 (hold + tap toggle), PACS more (door), PowerScribe
  on button 4 in PS.

## Review round 1 (subagent, static)
- Fixed: case-insensitive name clashes (G/g in all draw funcs, Ed/ed,
  COUNTS/counts; global S renamed Conf); L/R/M-button ownership while a
  wheel is open (TrigOwnsClick, shared by TrigGate and ClickGate); release
  checked before pause, DropHeld keeps swallowing held triggers; keyboard
  auto-repeat by timestamp; TapMs (300) tap window; RecordKeys reads
  modifiers physically; overlay pixels before Show.
- check_source.py now flags case clashes (proved on the old file).
- Not changed: PACS tools seeded as flick (user asked for speed); HotIf
  stall while MSAA calls block (short, rare).

## User testing (round 1)
- PR chowdhuryaj/hid-remapper#14 open; b8d7069 sent to the user.
- Caps Lock turning on when the wheel opened = running RadMapper at the
  same time (user confirmed). Offered, not built: warn at start if RadMapper
  is running.

## 1.1: bug sweep, speed, RadMapper coexistence
Branch `claude/dazzling-mendel-pvayp0` (PR #14's branch merged in, then this).
- RadMapper facts it relies on: mutex `Local\RadMapper-single-copy`; config
  `%APPDATA%\RadMapper\RadMapperConfig.json` (or beside a portable script);
  SyncHooks hooks every non-inert row's `button` plus each `layer` part (and
  clicklock targets); HookFrontTick re-hooks ahead of every other hook every
  10 s in PACS; SendMode Event, SendLevel 0; defaults hook XButton1/2,
  CapsLock, backtick; RButton is not hooked.
- §11b: `RmCheck` (3 s timer) -> `RmReadOwned` (small JSON reader) ->
  `RmOwned`; `TrigGate` returns false for an owned key, so the press stays
  with RadMapper. Toast on change; editor summary shows ⚠. INI
  `YieldToRadMapper="0"` turns it off. Paused RadMapper still counts
  (its pause is internal; not visible from outside).
- SendMode Event + SetKeyDelay -1 (was Input; falls back to Event at 10 ms
  per key while RadMapper's keyboard hook exists).
- `ExeOf`: exe name cached per hwnd (checked by pid) for the per-press gate.
- Fixes: a keyboard trigger held to choose from a tapped-open wheel reopened
  it on auto-repeat (`EatRepeat`); an empty hold wheel swallowed its button
  (`Claims` now needs a live slot; `opened` flag makes a never-opened hold
  a tap).
- Review pass (subagent) fixes: EatRepeat checked before the toggle
  branch (a held key no longer re-chooses in a submenu); a stale Held
  entry is dropped when the gate changes its mind, and a declined click
  clears a leftover Swallow; empty hold wheels don't toast on every press;
  RmCheck keys on mtime+size and a readOk flag; OpenMutex ACCESS_DENIED
  (elevated RadMapper) counts as running. Not done: numpad twin names.
- Caps Lock report: not reproduced from the code. With the defaults both
  scripts hooked nothing in common except XButton1/2 (RadWheel's button 5
  in PACS, button 4 in PowerScribe), which now yield.
- JSON reader logic checked against a Python port (escapes, surrogates,
  malformed input, owned-set rules). Still never run under AutoHotkey.

## Next steps / risks to verify on Windows
- README "First run checks" 7 (RadMapper running alongside).
- Load errors (never executed). Run `README.md` "First run checks".
- MSAA on IntelliSpace's context menu (WinForms?): names, HASPOPUP state,
  popup detection by new window of the PACS pid.
- Whether PACS applies keys to the viewport under the pointer or the
  selected one (a suppressed right-click no longer selects the viewport).
- Seed shortcuts (r, +r, y, Space, F7/F8/F11/F12, digits) vs site config.
