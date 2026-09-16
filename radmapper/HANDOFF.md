# Handoff — RadMapper 0.6.4-preview: radial menus, review pass 4

**Objective.** Ship a single-file AutoHotkey v2 remapper for a PowerScribe +
IntelliSpace reading room that is configured entirely at runtime: mouse and
keyboard remapping, window arrangements that follow the radiologist between
stations, a keyboard-driven pointer, and Kando-style radial (marking) menus
for PACS shortcuts. This session was review pass 4 (v0.6.4a): a P0 load
failure, a P0 usability defect in the wedge geometry, and a set of P1-P3
robustness and polish fixes.

**State.** Branch `claude/gallant-lamport-hiv2cu`. Latest commit: **see
`git log`** — this session's work is in the working tree and was
deliberately **not committed**. Everything lives in
`radmapper/RadMapper.ahk` (≈35.9k lines, single file, GpGFX vendored).
Portable checks pass. **Still never run on Windows** — there is no
AutoHotkey, no Windows and no display in this environment.

## The passes, in order

Each pass is written out in full in the changelog at the top of
`RadMapper.ahk`; these paragraphs say only what each one was FOR, so the
changelog stays the single source of truth.

**v0.6.2a — engine and delivery (review pass 1).** The first pass over the
engine after the rewrite: press/release state, the action executor, the
PowerScribe delivery path (skill §2: activate by EXE, never by hwnd), stuck
modifiers, and the guarantee that every synthetic Down has a matching Up.

**v0.6.2b — settings UI (review pass 2).** The Lumi Atlas widget kit and the
Atlas front-end: layer ownership (a widget records the layer it was BUILT
on and never consults the global again), dialog lifetime, the option-list
popup, full-erase repaints, and the contrast rules that `check_source.py`
still asserts.

**v0.6.2c — stations + keyboard pointer (review pass 3).** Station-aware
window arrangements (identity from monitor sizes in left-to-right order,
imaging screens ranked against the MEDIAN screen), per-monitor-v2 DPI
awareness set before the config is read, the UIA vtable fix (42, not 43),
loupe alignment at the TRUE ratio, and `Warp.ClearMods` so a warp click does
not inherit the Ctrl+Alt that opened the overlay.

**v0.6.3 — keyboard setup, mouse outputs, click lock.** The whole settings
window from the keyboard (`Lumi.Focus`: every widget registers itself as it
is built; the ring is not drawn until Tab), mouse buttons as OUTPUTS in the
wizard, and click lock made configurable from the UI.

**v0.6.4 — Kando radial menus.** Wedges instead of nearest-centre selection,
marking mode (a corner or a pause opens a door without stopping), child
rings spaced 360/(n+1) around the way back, a hub that says what is armed,
and the movement/wedge switches on the Menus page.

**v0.6.4a — this pass.** A load-blocking member collision in `class Warp`;
the wedge tolerance rolled back to full sectors everywhere except a
non-numbered child ring; orphaned wheel layers made impossible; a click now
cancels a practice wheel; the focus keys and the keyboard pointer stop
fighting over Tab/Space/Enter/arrows; keyboard focus survives a wizard
answer; arrow-stepping the action dropdown reopens the wizard once instead
of five times; `Atlas.IsFront` made cheap; the radial safety floors measure
the whole menu rather than the current ring; a corner inside the hub opens
nothing; docs rewritten.

## Decisions, and why

- **Skill rules honoured throughout.** PowerScribe is matched by EXE only
  (its `ahk_class` carries a per-launch GUID, its title carries the
  patient); PACS by `ahk_exe IntelliSpacePACSRadiology.exe`, which catches
  worklist and viewer together; `PSFire` checks `PSActive()` first and never
  calls `WinRestore`; every hold path releases in a `finally`; MButton is
  never held synthetically; `^!q` is the panic release.
- **Wedge policy (v0.6.4a).** Root ring = FULL sectors. Child ring = half
  the gap, the rest is `back`. Numbered (9-way preset) ring = FULL sectors
  at any depth, with a zero-span `back` marker so the parent node and its
  connector still draw. Rationale: dead space is only worth having where a
  bearing landing in it MEANS something, and the only ring where it does is
  a child ring. At the root a leftover bearing would fire nothing and read
  as a dropped button press. A bearing exactly on a shared edge goes to the
  lower-numbered slice, because a boundary has to belong to somebody.
- **Practice cancels on a click.** The old trial exemption made a practice
  wheel the one window in RadMapper you had to wait out. Cancelling is part
  of the gesture, so it is a thing to practise. A cancelled trial returns to
  the settings window through `RadialClose`'s existing trial branch.
- **The focus ring appears only after Tab.** A person who never touches the
  keyboard sees exactly the interface they saw before. A dialog is the one
  exception: it opens focused on its first control. The wizard's reopen now
  carries `armed` as well as the index, so a mouse-driven wizard still shows
  no ring.
- **F13-F24 are not relevant here.** They matter in the older
  `radiology_hotkeys` script, where PowerScribe's prev/next-field keys were
  bound to F13/F14. RadMapper binds nothing to them by default; they are
  just ordinary key names in the input tables.

## Verified by reading / by portable checks

Everything below was actually run in this environment:

- `python3 radmapper/tests/check_source.py` — PASS. It now runs the
  case-insensitive member-collision check over EVERY top-level class the
  script declares (found by brace depth, with comments and string literals
  stripped first), not just `Lumi` and `Atlas`. Confirmed it FAILS on the
  pre-fix source (a copy with the collision reintroduced) and passes on the
  current one.
- `node radmapper/tests/mockup.cjs` — PASS.
- Brace/paren/bracket balance of every edited function, and of the two test
  files, computed with the same stripper.
- `git diff --check` — clean. No v1 syntax in any added line.
- The new wedge assertions were simulated in Python against a line-for-line
  port of `RadialWedges` / `RadialAngleIn` / `RadialPickIn` before being
  written into `tests/regression.ahk`, including both 360-bearing sweeps.

## NOT verified — needs Windows

Anything that needs a window, a hook, a monitor, GDI+, an InputHook, UIA or
DWM is unproven. That is: every layer and every repaint, the radial overlay
and its click-through/pass-thru registration, `Critical` interaction with
GpGFX's message pumping, the keyboard pointer's InputHook and its loupe
capture, `SetWindowDisplayAffinity`, UIA `ElementFromPoint`, station
detection and window placement, the focus ring's hit rectangles, MsgBox
ownership, and the timing of every debounce. `tests/regression.ahk` itself
has never been executed — it needs `AutoHotkey64.exe`.

## Windows test list, in priority order

1. **Does it load at all.** Double-click `RadMapper.ahk`. v0.6.4 did not:
   `class Warp` had `static grab` beside `static Grab()`. If a
   duplicate-declaration error appears, read the class name in it and look
   for the same shape elsewhere.
2. `AutoHotkey64.exe /ErrorStdOut tests\regression.ahk` — expect one PASS
   line, no FAIL.
3. **Keyboard pointer, end to end.** Ctrl+Alt+G → grid → a cell → refine
   with Q W E / A S D / Z X C → check the loupe's overlays sit exactly over
   the magnified pixels → N to snap to a small toolbar control → G to drag.
4. **The wheel under the hand.** Thumb button → hold → flick to
   **Windowing** → turn a corner toward a number → release. Twenty times,
   counting misfires: a wrong preset, a ring that opened on the wrong door,
   a release that sent nothing.
5. **Practice, then a real study.** Menus page → Practice safely → flick
   around, then **click**: the wheel must vanish, send nothing, and hand
   the settings window back. Then open a real study and confirm a click
   cancels a live menu there too without reaching the image.
6. **Ctrl+Alt+G with the settings window focused**, then press Space. The
   pointer must refuse to open ("Close the settings window first") and
   Space must press whatever the focus ring is on — one key doing one job.
7. **Tab through the wizard end to end.** Set a button → Tab to a tile →
   Space → the ring must be where it was, not back at control 1. Then step
   the action dropdown with Left/Right through several actions in one run:
   the dialog must reopen ONCE, when the arrows stop.
8. **Ctrl+Alt+Q as a child ring opens.** Panic during a gesture, repeatedly,
   looking for a stuck wheel: a click-through overlay left on top of the
   study with no timer behind it. `g_RadialLayers` is the net under this.

Still open from 0.6.2c:

9. `SetWindowDisplayAffinity` on a layered window — if it refuses, the loupe
   falls back to hiding the intersecting overlays for the BitBlt. Cannot be
   proved without a machine that refuses.
10. **Imaging reservation on a 3-head station.** Windows page → "This
    station" on a portrait + 4K desk: the portraits should be reserved, not
    "none".
11. **Guard mode 2 after a restart.** Arm "place new windows", exit, start
    again, open PACS: it should land in place untouched. Disarm and re-arm,
    open another window: it should be placed again.

## Key files and where to look

- `radmapper/RadMapper.ahk` — the whole program. Navigate by the `§`
  banners, and inside them by function name:
  - §1 constants and globals: `g_Radial`, `g_RadialLayers`.
  - §5 engine: `OnPressHK` (holds the radial click-cancel gate),
    `OnReleaseHK`.
  - §7c window layouts: `StationMons`, `StationKey`, `ImagingMons`,
    `LayoutSlotTarget`, `MigrateLayoutSlots`.
  - §7d radial menus: `RadialSliceAngles`, `RadialWedges`, `RadialPickIn`,
    `RadialCornerAt`, `RadialRing`, `RadialOpen`, `RadialTick`,
    `RadialEnter`, `RadialBack`, `RadialSweepLayers`, `RadialClose`,
    `RadialPaint`, `RadialCancelActive` / `RadialCancelHit` /
    `RadialBindCancel`.
  - §10b safety: `PanicRelease`; §12 lifecycle: `Cleanup`, `Init`.
  - §13 `class Lumi`: `Lumi.Focus` (`Reset`, `Restore`, `Add`, `Move`,
    `Do`, `Paint`), `Lumi.Select`, `Lumi.SelectNudge`, `Lumi.nudging`.
  - §14 `class Atlas`: `BindEscape`, `DoFocusKey`, `IsFront`, `Help` /
    `HelpBox`, `Confirm`, `StartTick` / `StopTick`, `WizardDlg`,
    `WizRefocus`, `WizDraft`, `DoWizPick`, `DoWizAct`, `DoWizActPicked`,
    `WizReopenDue` / `WizReopenNow` / `WizReopenCancel`, `DoWizRecKey`,
    `CloseDlg`, `RebuildAfterDlg`, `PanelWindows`.
  - §14e `class Warp`: `Open`, `Close`, `Grab`, `Sub`, and the renamed
    members `grabbing` and `NINTH`.
- `radmapper/tests/check_source.py` — structural checks; `strip_ahk` is the
  comment/string stripper the collision and balance checks share.
- `radmapper/tests/regression.ahk` — pure-function tests; the wedge block is
  near the top, the `Warp.grabbing` / `Warp.NINTH` existence check is at the
  bottom next to the PASS line.
- `radmapper/tests/mockup.cjs`, `radmapper/mockup/` — the HTML menu mockup.
- `radmapper/README.md`, `radmapper/DESIGN.md`, `radmapper/SECOND-PASS.md`.

**Next.** Get it in front of AutoHotkey on the workstation and work the list
above from the top. Nothing else in this repo should change until item 1
passes.
