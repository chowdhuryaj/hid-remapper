# RadMapper handoff

**Objective.** Keep RadMapper (single-file AHK v2 remapper for PowerScribe +
IntelliSpace) reliable. v0.7.2 removes radial menus (now a separate script)
and lands a five-area bug sweep.

**State (v0.7.2).** Branch `claude/compassionate-clarke-ffcwdy`. Not yet run
on Windows: all verification is by reading + portable checks. Round 3
reviews done: latest-commit regressions fixed (2a3f990); whole-file
syntax/scope pass found no load-time or guaranteed-runtime errors.

## Completed
- "0" labels draw (GpGFX `== 0` / `!== 0` emptiness tests); braces in Send
  syntax no longer parsed as markup (markup is opt-in via `shape.markup`).
- Radial menus removed: engine, Menus page, editor, "radial" action,
  settings (retired), seeding, starter packs, previews/mockup. Load drops
  radial rows (Diagnostics "retired") and deletes the `menus` key.
- LoadCfg saves once when NormalizeCfg changed the config.
- Config: seed flags in DefaultCfg; one-shot panic migration; MigrateRow
  before first ValidateCfg; dup profile names refused; pacsApp follows a
  rename; AppDelete avoids shadowing; restore/normalize ordering; SaveCfg
  Critical; RestoreDefaults backs up.
- Delivery/actions: defer clock reset on panic/pause; panic closes the
  switcher; foreground re-check before PS/PACS send; ControlSend fallback
  removed; macros stop on pause, pskeys syncs, failed focus stops the
  macro, Run errors logged; teleport "1" = screen 1; Warp hook ignores
  our sends; follow-focus stands down during delivery.
- Engine: key->mouse passthru no repeat Downs; Up hotkeys pass when the
  engine owns the press (UpOwned); click lock skips its own trigger;
  switcher holder closed in ClearBS; held layer host not swept at 30 s;
  panic releases key targets; RegisterKbHotkeys after resume; RepeatMs().
- GUI: Rec on Settings writes the field buffer; nav/scope clicks end a
  live edit and clear selection; no pre-selected modifier row; Delete
  confirm names mods/scope; focus kept across BindDlg rebuild; app pickers
  re-indexed on profile delete.
- Text compares: SameText() for clipboard, snippets, macro names; ParkOf
  rejects non-numeric spots.

## Round 2 (user decisions applied)
- Mouse input follows the window under the pointer: CurCtx(btn) ->
  AppNameAt(RM_WinAt()) for mouse/wheel; keys use the foreground.
- Layer buttons are a setting: config "layerHosts" (default XButton1,
  XButton2, CapsLock; max 6; never LButton/wheels), edited in
  Atlas.LayerHostsDlg ("Layer buttons…" on the tab strip). CleanLayerHosts
  runs in NormalizeCfg before ValidateCfg. SpecFor lets M/R host when listed.
- "Toggle engine pause" rows stay hooked while paused and resume
  (PauseTglRowFor via MatchScore; g_SwallowUp eats the toggling release and
  OS key repeats).
- Focus restore after Chooser/Shelf Esc: user said fine, not changed.
- Second sweep fixes: click-lock hotkey refuses unhooked buttons; pause
  restores speed/closes Warp; WinMoveSure (DPI); ClipboardAll in grab;
  layoutGuardMs clamp; hotkey dup/bad warnings; switcher commit regression
  fixed; swapped psWin/win in delivery fixed (was breaking ALL PS/PACS
  delivery that needed activation); primary-button drag passthrough from
  pending/armedmod (MovePoll); layer marked used at press; held = armed
  hosts only; scores layer 64 / mod 9 / app 8; tilt native rate limit;
  dial/switch use holder; fgOurs mouse resolves normally.

## Not done
- ModsHeld ignores modifiers RadMapper holds via a native remap
  (XButton1 -> LCtrl + a Ctrl+Wheel row won't match). Edge case.

## Verification
- `python3 tests/check_source.py` PASS (now also guards `str !== 0`).
- Brace/paren delta of the whole session diff is 0.
- `tests/regression.ahk` updated (radial rows dropped, key "0"); needs a
  Windows run: `AutoHotkey64.exe /ErrorStdOut tests\regression.ahk`.

## Round 3
- Wheel with our window in front activates the window under the pointer.
- Pause row inside a layer resumes (layer judged physically).
- Only a layer TAP marks the host used at press.
- Primary dragmove hold drags its target; a host turned plain drag drops
  its layer (spec is per press -- SpecFor must never cache).

## Round 4 (simplify)
- Removed the clipboard history + scratchpad (Shelf, OnClipboardChange
  hook -- suspected cause of freezes on copy/cut), their actions, hotkeys,
  tray entries and config snippets.
- Removed sniper/boost, drag scroll/zoom (+ cursor hiding), W/L dial.
  Kept: keyboard pointer, window layouts, switcher, follow/park, macros.
- Old rows for removed actions are dropped with a Diagnostics line;
  their settings are in RETIRED_SETTINGS. Removal review: clean.

## Round 5 (freezes, pass-through, cleanup)
- Freeze fixes: watchdog sweeps only within 10 s of our own synthetic
  input (g_SynthAt); #HotIfTimeout 150; Atlas/Chooser/switcher context keys
  On only while their window is up (KeysOn / AppSwitchBindKeys(on));
  HookFrontTick reinstalls once per PACS focus; layout guard async
  SetWindowPos + IsHungAppWindow skip + 3-strike give-up; HUD toasts via
  SetTimer.
- Pass-through action "bypass" (g_Bypass, BypassFor/On/Off/Toggle/Expire):
  hold = while held, tap = toggle (2 min cap); native at the HotIf gate
  except inputs already held with a live state; src + layer hosts exempt.
- Window/layout and settings-page sweep fixes (see git log).
- Cleanup: version history -> CHANGELOG.md; dead app functions removed;
  ~3,574 unreachable GpGFX lines pruned (verified clean by a second
  reference check). File ~28,800 lines.

## Round 6 (scope hardening, interactions, perf)
- Program-scoped vs global: AimFg brings the scoping window forward
  before keystroke actions; GateNative decides unbound presses NATIVE at
  the HotIf gate (no suppress/re-send); UpClaimed for Ups; stock/none
  carve-out in SpecFor; layer rows use the host's program (layApp);
  ProfileOf (most specific match); AppDelete deletes rows by default.
- Gate claims: a Down handed to the engine (g_GateClaim) keeps its Up;
  a stale claim sends the native Up if the Down went out. Teardown
  (ForceReleaseActive) swallows releases of held inputs (g_SwallowUp),
  kept hooked until released. Click lock checked first at the gate.
- Perf: Map lookups for input names, HkInput memo, FindBindingFor score,
  hung-window guards, ListLines/KeyHistory 0.
- Lite (no-GpGFX) build was made and then dropped at the user's request.
- Invariants: SpecFor must build a fresh spec per press; every HotIf
  path that returns native should clear g_GateClaim (GateNativeClear).

## Next steps
Run on the workstation; run regression.ahk; check Diagnostics after first
launch (expect "retired" lines for old radial rows).
