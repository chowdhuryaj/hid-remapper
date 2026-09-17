# RadMapper handoff

**Objective.** Keep `radmapper/RadMapper.ahk` (single-file AHK v2 build) in
step with the copy running on the reading workstation, and land requested
UI fixes.

**State (v0.6.6.6).** Branch `claude/determined-sagan-7w3fl7`, draft PR #9.

Done in 0.6.6.6:
- MatchScore: layer component +16 (was +2) so a held layer row beats a program's plain row.
- Field edit loop ends when EditGuard zeroed `Lumi.editing` or after 10 idle minutes.
- Conflicts report line for layer-vs-plain-row precedence.

Done in 0.6.6.5:
- `LAYER_KEY_HOSTS := ["CapsLock"]`: always in LayerChoices; `HoldReservedForLayer()` refuses a
  "hold" key row on CapsLock in DoSave and classic KeyOk.

Done in 0.6.6.4:
- Watchdog sweeps only synthetic-down states (passthru/eager1/held); pending/armedmod get
  the 30 s cap. `HookChanged()` stamps hook (re)installs; physical "up" must persist 2 ticks.
  Swept states set `down := false` before ClearBS.

Done in 0.6.6.3:
- Tilt (WheelLeft/Right) bypasses the own-window native passthrough in OnWheelHK.
- Teleport flash deferred (`TeleportSignalLater`) out of the hotkey thread.
- Dropped notches show in the status bar via LastEvent.

Done in 0.6.6.2:
- `st.physSeen`: a press that never read as physical (driver-injected button) is not
  swept by the watchdog on physical state (30 s cap only); RepeatTick same rule.
- `CommitTaps` returns for a holder with `usedAsMod`; eager1 release honours it too.
- `SpecFor`: under AppNoHold, an app-scoped hold/taphold row is kept.
- `ConflictReport()` / `Atlas.ConflictsDlg()`; "Conflicts…" on Mouse, Keyboard, Diagnostics.

Done in 0.6.6.1:
- Follow-focus exceptions: `followExcept` setting (";"-separated exe / title: / class:),
  `FollowExcepted()` in FollowTick, Settings > Behaviour field + "Grab window in front".

Done in 0.6.6:
- Set-a-button wizard removed; Home / Mouse / Keyboard open `BindDlg` directly.
- Home essentials: PACS wheel and Window presets rows removed.
- Radial editor (`Atlas.MenuDlg`): 1000 px wide, one-line header, wider Icon
  column, live wheel (`MenuWheelPaint`) with drag-to-swap (`MenuWheelDrag`).
- Macros page is native (`Atlas.PanelMacros`, `StepDlg`); classic window no
  longer opened for macros.
- Delete/Backspace deletes the picked row (`Atlas.DeleteKey`); right-click a
  row for a menu (`Atlas.RowMenu`, `"ctx"` from `Lumi.__ListDo`).
- Hover floor (`Atlas.LeaveCheck`) covers dialog and option list.
- Follow-focus: no park warp when the pointer is already inside the focused
  window; 1.5 s grace after a monitor teleport (`TeleportNoteFollow`).

**Version rule for today.** Base is 0.6.6; each further iteration today is
0.6.6.1, 0.6.6.2, ... (`RM_VERSION` at ~line 1157 and the header line 2).

**Verification.** `python3 radmapper/tests/check_source.py` passes; brace
balance checked. Not run under AutoHotkey (Linux container) — first Windows
run should open: Home, Mouse > Add new, Menus > Edit commands (drag a
wedge), Macros (add/edit/move a step), right-click and Delete on a row.

**Next.** Run on Windows, fix anything the first run turns up; bump to
0.6.6.7 for the next iteration.
