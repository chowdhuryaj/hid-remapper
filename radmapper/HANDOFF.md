# RadMapper handoff

**Objective.** Cut the tap-hold and chord complexity colleagues tripped over in
0.6.6.5, and make the radial menu (windowing in PACS above all) the fast path.

**State (v0.7).** Branch `claude/sleepy-maxwell-s6cvzw`, built on 0.6.6.6
(`claude/determined-sagan-7w3fl7`). The parallel 0.6.6.5 line on
`claude/charming-lamport-6k3h7e` (per-row hold threshold, per-input calibrator,
left-button guarantee) is NOT merged here; only its left-button idea survives
in spirit (left/right/middle instant everywhere).

## Completed (one commit each)
1. Triggers are tap / hold / turn. Tap-dance engine (eager1, wait, TapTimer,
   CommitTaps, tapWindow) and the calibrator (`class Calib`) removed. Retired
   rows dropped on load with a Diagnostics "retired" line (`ValidateCfg`).
2. Layer hosts: `LAYER_HOSTS` (button 4, 5) plus non-typing keys, one at a
   time (`LayerHostAllowed`, `LayerPathAllowed`). Pairs, CapsLock reservation
   and R/M hosts gone. `IsPrimaryButton` L/R/M: hold only when app-scoped;
   `noHold` field, `AppNoHold`, Apps-page "Instant clicks" retired. "Only while
   holding" and Layer scope selectors are Advanced-only. `[`/`]` defaults gone.
3. Radial hold-only: `latched` is true only for practice; tap-radial rows
   become hold rows on load; editors refuse radial on tap/turn; release on a
   door shows a hint. `SeedPacsWheelRows`: PACS hold 4 = PACS wheel, hold 5 =
   Window presets (new configs, and once via `seedPacsWheel067`). Wheel deck
   settle: `deckSettleMs` (250), `g_WheelLast`, `st.deckLocked`, Settings row.
4. Simple action list trimmed to 11; version 0.7; header changelog; README.
5. Wheel decks ("Scroll wheel…" buttons, deck settle row) are Advanced-only;
   the Layers page already was (Atlas.HIDDEN).

## Review fixes (three Sonnet passes: engine; radial/switcher/watchdog; config/editors)
- ForceReleaseActive closes the switcher and marks swept states released.
- Radial 15 s floor closes only a holder that is gone / physically up; 60 s cap.
- Wheel notches while a (non-practice) menu is open stay native.
- ValidateCfg runs again after MigrateCfg; converted tap→radial rows never
  shadow an existing hold row (RowKeyTaken); wheel deck editor offers and
  accepts only allowed hosts; PACS rows use the profile matched by exe
  (PacsAppName).
- HoldTimer: a stateful hold on a host whose layer was already used goes to
  armedmod (silent). Dead LButton drag-watch (dragEligible) removed; MovePoll
  stops once a dragmove is out. A wheel target on a hold native row sends one
  notch on the down and nothing on the up.
- Not done (low value): FindDupBinding via g_Idx; RadialFocusLost PID cache.

## Round 3 review fixes
- ValidateCfg pre-scans hold keys so a converted radial row is never shadowed
  silently; PACS wheel rows seed only when both menus exist by name.
- Conflicts: warns when a host both hosts a layer with mouse rows and opens a
  menu on hold; the "withholds the click" warning fires only for a real wait,
  on any of left/right/middle.
- Tilt notches are dropped while a menu is open (vertical stays native).
- OnPressHK's menu-cancel and keyboard-pointer branches release a still-down
  state before NewBS (no orphaned synthetic Down).
- Settings band 1 minimum 184 so the Advanced timing caption fits at 940x640.
- Deferred (documented in PR): Settings bands oversubscribe 940x640 by 42 px
  (pre-existing), BindDlg blank strip in Simple mode, HoldTimer dead branch.

## UI redesign (v0.7, after the review rounds)
- `Atlas.LayerTabs`: one tab strip (Base / Hold Button 4 / Hold Button 5 /
  key hosts in Advanced) drives `Atlas.layerIdx` for BOTH pages (`kbLayerIdx`
  removed; `KbScopeLayer` returns `ScopeLayer`).
- `Atlas.SlotPanel`: per selected input, Tap/Hold (or Turn) slot cards with
  Set/Change/Clear (`SlotRef`, `EditSlot` seeds `BindDlg` with a NewBinding,
  `ClearGo` -> `DeleteRef`), plus a list of modifier rows underneath.
- `BindDlg` no longer offers "Only while holding": the layer is the tab.
- `MouseMap` redrawn: channel for the wheel column, no overlapping zones,
  thumb shelf. Card footprint unchanged (300 x bodyH+56).
- Workstation checks: tabs switch the map; Set on an empty slot opens the
  editor with program/layer/button/trigger prefilled; Clear asks first; the
  Hold Button 4 tab shows button 4 as "held" with no slots; Keyboard page
  same; 940x640 layout (slots + list + buttons fit in the right column).

## Decisions
- Unused layer host with no tap row stays silent on release (pre-0.7 rule).
- Deck settle measures "wheel still turning" from any notch of any wheel input.
- Middle-button hold warning kept for program-scoped middle holds.

## Verification
- `python3 radmapper/tests/check_source.py` PASS after every cut.
- Brace/paren balance checked per changed line (curly-quote strings confuse
  the crude file-wide count; the per-line diff sums to zero).
- NOT run under AutoHotkey. First Windows run should check: load without
  error; Diagnostics shows "retired" lines for an old config; Mouse > Add new
  shows tap/hold only and no "Only while holding" in Simple view; hold button
  4 in PACS opens the wheel, hold 5 the presets, tap still hops monitors; a
  hold row on right button with program "Global" is refused; scroll a stack,
  press the deck button mid-scroll, keep scrolling: notches stay native until
  the wheel pauses 250 ms; hold thumb 4, tap thumb 5 inside the threshold,
  keep holding 4 past it: the PACS wheel must NOT open.

## Click freeze between PACS and PS + per-tab key list (branch `claude/modest-cray-0ufegs`)
- **Cause.** 0.7 never got the 0.6.6.5 fix (`4fd8f6b` on
  `claude/charming-lamport-6k3h7e`). ps_next/ps_prev/PACS-keys deliveries
  send from a non-Critical timer; a click landing inside a "+{Tab}" leaves
  Shift and/or LButton logically down in the OS while g_BS balances, so the
  watchdog saw nothing and Diagnostics stayed empty until Panic.
- **Ported:** `PSSendAtomic` (keystroke under Critical), `PSDeferForButtons`
  (per-delivery, front-of-queue, 100 ms retry, 1.5 s bound; settled
  held/fired/armedmod/consumed presses do not count), PSDrain stops on
  "defer". Watchdog parts 4/5 sweep a modifier or orphan LButton that is
  logically down / physically up for two ticks, guarded by
  `WatchdogSweepSafe` (no live press, latch, drag scroll, menu, switcher,
  Warp, delivery, macro). Each sweep logs a "recovered" Problem.
- **New:** `PanicSnapshot` -- Panic logs a "panic" Diagnostics line first
  (stuck keys/buttons, engine states, live features, foreground exe).
- **Keyboard page:** tiles are `Atlas.KeysInScope()` -- only keys with a row
  on the current tab + program (host key of the tab excluded). Slot Clear
  works on any row incl. system-default (inert) ones.
- **Workstation checks:** tap ps_prev while clicking in PACS repeatedly: no
  dead click; force `{LShift Down}` / `{LButton Down}` from another script:
  toast + Diagnostics "recovered" within ~1.5 s; Panic writes a "panic"
  line; moddrag / click lock / drag scroll / Warp survive 5+ s; Keyboard
  page: a key mapped only under Hold Button 4 is absent on Base; a key with
  only a "Native" row can be Cleared and disappears.

## Simplification pass: three layer hosts, CapsLock dictate
- `LAYER_HOSTS` = XButton1, XButton2, CapsLock; `LayerHostAllowed` is plain
  membership; `LayerChoices` = Base + those three; the tab strip shows all
  three in Simple and Advanced. Rows under any other host drop on load.
- CapsLock tap = `ps_dictate`: `CapsLockDictateRow`, in `SeedDefaultBindings`
  and once via `seedCapsLock07` (skipped if any CapsLock row exists). A
  key host's unused hold is silent (OnReleaseHK armedmod) so a long CapsLock
  press never toggles dictation; thumb buttons keep their tap-on-unused rule.
- Removed: hidden Layers page (PanelLayers/LayerHosts/GoLayer*), CapLayerDepth,
  g_Layer/g_LayerStack, dead EventCodeOf/InputPhrase/LayoutIndexOf/MenuNames/
  ModifierCodeFromLabel, Shelf.IsOpen.
- Vendored GpGFX kept on purpose: Atlas, radial menus, switcher, shelf,
  Warp and toasts all draw with it (user chose "remove classic only").
- Workstation checks: tap CapsLock anywhere -> dictation toggles, Caps Lock
  light stays off; add a row on the Hold CapsLock tab -> tap still dictates
  (on release), hold + use the row works, long hold unused does nothing;
  an old config with a layer on another key shows "retired" in Diagnostics.

## Classic window removed; tilt fix
- Removed BuildMain/ShowClassic, the tray item, Atlas.Classic, g_UI and
  every top-level function left unreachable (call-graph pass, 426 -> ~359
  functions, -1.5k lines). Kept shared helpers Atlas uses (RecordCombo,
  KeyPicker, InputPicker, FieldEdit, AppDlg, StyleDlg, ModalOpen/Close).
- Ported: input tester -> `TesterShow`/`TesterClose` (own small Gui,
  g_TestUI); app profiles -> Programs page Add/Edit/Delete (`Atlas.AppEdit`
  -> `AppDlg`, owner `DlgOwner()`, `AtlasRefresh()`).
- ShowMain has no fallback now: an Atlas failure logs + MsgBox.
- Tilt: `HookActive` never gates WheelLeft/Right; `TiltNote` logs a bound
  tilt that still passes through ("tilt" in Diagnostics).
- Workstation checks: tray has no classic item; Programs page Add/Edit/
  Delete; Diagnostics > Test my mouse opens the tester, bars light, Close
  stops it; tilt over the PACS series list teleports. If it still scrolls,
  copy Diagnostics: no "tilt" line + no LastEvent means the trackball driver
  sends it past the hook (check the trackball software's tilt setting).

## Tilt eaten by PACS's own mouse hook
- User report: tilt still scrolls the series list, no Diagnostics, wired
  Logitech without software. Cause taken as IntelliSpace installing its own
  low-level mouse hook after ours (newest hook runs first and can eat it).
- `HookFrontTick` (2 s timer): when an IntelliSpace window comes to the front
  and every 10 s while it stays there, with nothing held (no g_BS down, no
  logical button down, no menu/switcher/latch/drag scroll/Warp),
  `InstallMouseHook(true, true)` + `HookChanged()`. Logs "hook" once.
- `WatchdogSweepSafe` stands down 5 s after any hook change (the physical
  table is wiped).
- Check: tilt over the series list teleports; Diagnostics shows one "hook"
  line. If not, the next suspect is raw input, which no hook can block.

## Keyboard hook + UI audit
- HookFrontTick reinstalls the keyboard hook too (also waits for no
  modifier held and no key recording).
- Type: four styles only (Title 14B, Body 13, Small 11, Mono Consolas 11);
  documented at Lumi.Size. Buttons, accent and section labels not bold.
- Layout audit (subagent, static): applied the verified fixes -- 4 overlaps
  (Diag list/label, Processes label, Home status lines, Pointer toggles),
  label/control centre mismatches (header, nav, Home, NumRow, Pointer,
  Settings path row, App labels), Rec/Pick gaps, empty-state labels in the
  first-row slot, slot-card buttons 30 px, Menus/Apps button rows on
  BtnRow, list rowH 30 everywhere, Settings gutter 12.
- Deferred items done in the next pass: Atlas.MINH 640 -> 760 (Compact
  960x760, Default/winH 1120x800); Settings bands [adv 228|184, 148, 188],
  timing pitch 34-38; Behaviour card is a 3x2 grid (5 toggles + HUD corner)
  with a BtnRow of six, config path moved to the Home footer; Tilt guard in
  the compact hotkey-cell shape; Home job rows 8 px apart; MenuDlg pitch
  34/38, grid gaps 8, wheel header off the rule; BtnRow default gap and all
  dialog footers 12 px; Lumi.Toggle takes a label width.

## Next
- Run on the workstation. Sonnet review findings (engine, radial/watchdog,
  config/editors) are being applied on this branch; see the PR for the list.
