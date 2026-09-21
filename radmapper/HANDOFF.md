# RadMapper handoff

**Objective.** Cut the tap-hold and chord complexity colleagues tripped over in
0.6.6.5, and make the radial menu (windowing in PACS above all) the fast path.

**State (v0.6.7).** Branch `claude/sleepy-maxwell-s6cvzw`, built on 0.6.6.6
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
4. Simple action list trimmed to 11; version 0.6.7; header changelog; README.
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

## Decisions
- Unused layer host with no tap row stays silent on release (pre-0.6.7 rule).
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

## Next
- Run on the workstation. Sonnet review findings (engine, radial/watchdog,
  config/editors) are being applied on this branch; see the PR for the list.
