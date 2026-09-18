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

## Decisions
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

## Key files
- `radmapper/RadMapper.ahk`, `radmapper/README.md`, `radmapper/tests/check_source.py`
- `.claude/skills/efficient-fable/SKILL.md` (orchestration pattern used for all subagent work)
