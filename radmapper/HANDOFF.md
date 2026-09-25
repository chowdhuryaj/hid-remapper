# RadMapper handoff

**Objective.** Keep RadMapper (single-file AHK v2 remapper for PowerScribe +
IntelliSpace) reliable. v0.7.2 removes radial menus (now a separate script)
and lands a five-area bug sweep.

**State (v0.7.2).** Branch `claude/compassionate-clarke-ffcwdy`. Not yet run
on Windows: all verification is by reading + portable checks.

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

## Deliberately not done (need a decision)
- CurCtx picks program rows by FOREGROUND window even for mouse input
  (PS focused + pointer over PACS -> PACS rows don't match). Positional
  would change behavior; ask the user.
- A "Toggle engine pause" row cannot resume (its input is unhooked while
  paused). The pause hotkey still works.
- Chooser/Shelf don't restore focus after Esc.

## Verification
- `python3 tests/check_source.py` PASS (now also guards `str !== 0`).
- Brace/paren delta of the whole session diff is 0.
- `tests/regression.ahk` updated (radial rows dropped, key "0"); needs a
  Windows run: `AutoHotkey64.exe /ErrorStdOut tests\regression.ahk`.

## Next steps
Run on the workstation; run regression.ahk; check Diagnostics after first
launch (expect "retired" lines for old radial rows).
