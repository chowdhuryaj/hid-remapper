# RadMapper handoff

## Objective
1. Fix: whole computer froze on every copy/cut with RadMapper running. (done)
2. Follow-ups: three Ctrl+C leads, a full freeze/crash sweep with fixes, and a UX pass to cut clicks. (done)

## Branch / PR
`claude/charming-lamport-6k3h7e`, draft PR #10. Repo copy is now the canonical v0.6.6.5 script (was stale at 0.6.1-preview).

## Completed (commits, newest last)
- Clipboard hook: `ClipChanged` only arms a `ClipHarvest` timer; `#ClipboardTimeout 250`.
- Repo synced to the live v0.6.6.5 script.
- Ctrl+C leads: Warp passes Ctrl+letter/digit to the app (closes overlay, re-sends with {Blind}); `KeyNameValid` rejects bare modifiers; GpGFX dialog stamps `g_ClipMine`.
- UX (12 items): Duplicate row (Ctrl+D), hotkey rows for Shelf/Scratchpad/Warp/Click lock on Settings (4-column band), "Change…" edits the existing essential, single-row delete with Ctrl+Z undo toast, row 1 selected on Menus/Macros/Apps, "Save & practice", Ctrl+S/Ctrl+Enter commit, dropdown typeahead, right-click on zones/tiles, starter pack offers to create a missing menu, help/README text, 26 px Home buttons.
- Freeze/crash sweep (16 items): see commit 6bb7f3f message.
- Left button: always native in the base layer (LButtonHookActive; hook registered only when a layer/click-lock row needs it; base-layer and layer-host LButton rows refused in editors and dropped on load). "Hold Left Button" removed from layer hosts.
- PowerScribe field nav killing left click: PSDeliverNow/AppDeliverNow defer while an engine-unowned button is down (1.5 s bound); keystroke sent under Critical; Watchdog sweeps stuck modifiers and an orphan logical LButton down; injected (physSeen=false) states release ~2 s after stable physical up.
- Calibrator: picker for "Any key (global)" or one input with hold rows; aimed at an input it captures that key/mouse button and Apply writes holdMs onto that input's hold/taphold rows (globals untouched). Entry from zone/tile/row right-click. check_source.py now covers Calib, Shelf, Chooser, Warp.
- Tap/hold: per-row `holdMs` on hold/taphold rows (engine `RowHoldMs`/`SpecHoldMs`, editor field "Hold after (ms)", classic dialogs, list suffix, conflicts text). Pointer travel past dragThreshold during a pending tap+hold press on any mouse button except RButton becomes a native drag and cancels the hold (`OnPressHK` dragEligible broadening).

## Decisions
- Tap/hold item 3 ("click right away" opt-in mode: tap at press, hold still fires) NOT done; user to decide after testing 1 and 2.
- Tap/hold: RButton excluded from movement-resolve (right-drag is window/level); MButton included only when a hold row exists on it.
- One canonical file; the user's workstation copy is delivered from the repo file after each pass.
- Deferred UX items: 7 (conflicts report → jump to row), 9 ("Try it" in binding editor), 12 (segmented controls). Deferred sweep items: 14 (RadialPaint Critical cost, measure first), 18 (PSDrain ordering), 19 (Field Ctrl+V read).
- No version bump / changelog entry; the user owns the header.

## Verification
- `python3 radmapper/tests/check_source.py` PASS after every pass. Brace-depth scans clean.
- NOT runtime-tested (no Windows/AHK here). Workstation checks to run:
  - Copy/cut in Word, browser, PowerScribe: no freeze; Ctrl+Alt+C shelf fills.
  - Settings band at 940x640 and 1120x720 (4-column hotkey band, tilt guard on heading line).
  - CapsLock layer host while paused: Caps state unchanged, nothing stuck.
  - Practice wheel from "Save & practice": settings window does not flash back.
  - Hold thumb button, scroll the app switcher, release (ClearBS now clears st.down).
  - Animations still run on a machine without GpGFX.Core.dll (FrameTimer Stop now works).
  - Left click: stock config shows no *LButton hotkey; left click/drag/marquee identical to engine off. Layer with LButton row: hold host, press left, release host first then left → no stuck state. Editors refuse base-layer LButton rows and LButton as a layer host.
  - PS field nav: bind ps_prev to a thumb tap, hammer left click in PACS while tapping it → no shift-click state, left click never dies without Unstick. Bind ps_prev to a HOLD → fires immediately. Force `{LShift Down}` / `{LButton Down}` from another script with nothing held → toasts "released a stuck LShift / left button" within ~1.5 s. Alt+drag zoom, click lock, drag scroll, Warp, injected middle-drag pan must all survive 5+ s.
  - Calibrator: Diagnostics entry still global; right-click button 4 → Calibrate → rows show "(N ms)", globals unchanged; LButton run: Esc cancels, Apply clickable at results, nothing stuck afterwards; wrong key shows a hint.
  - Tap/hold: set "Hold after (ms)" on one thumb-button hold row and confirm it fires at that time; drag button 4 (tap+hold) > 8 px → native drag, no hold; stationary hold fires; jitter < 8 px does not resolve; taphold second press keeps its own travel; hold-only radial still opens while drifting.

## Key files
- `radmapper/RadMapper.ahk`, `radmapper/README.md`, `radmapper/tests/check_source.py`
- `.claude/skills/efficient-fable/SKILL.md` (orchestration pattern used for all subagent work)
