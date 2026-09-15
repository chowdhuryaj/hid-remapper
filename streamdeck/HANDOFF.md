# Handoff — Stream Deck MK.2 radiology profile

**Objective.** A Stream Deck MK.2 profile for the PowerScribe + IntelliSpace
reading room, generated from RadMapper's known shortcuts, with drawn
radiology-themed icons.

**State.** Complete for the requests so far. PR #8
(https://github.com/chowdhuryaj/hid-remapper/pull/8) is open, ready for
review, clean against `master`, no CI applies to `streamdeck/`. Branch:
`claude/gallant-lamport-hiv2cu`. Last commit: 41e3b31.

**Done.**
- `build_profile.py` draws every icon (Pillow, 288 px, 4x supersampled) and
  writes the v2 bundle (`<uuid>.sdProfile/manifest.json` + `Profiles/<id>/`).
- Seven pages: Home (launch pad), Editing, PACS tools, Windowing, Number pad,
  Web & windows, System. Every non-Home page ends in a nav strip.
- PowerScribe keys are native (F4 / Tab / Shift+Tab); `ROUTE_PS_VIA_RADMAPPER`
  flag switches to RadMapper's global ` [ ] bindings.
- Four Multi Actions (next field & dictate, copy whole report, open all sites,
  clear & next series), written in both the 6.x `Actions` and legacy
  `Settings.Routine` layouts.
- Seven site-configurable functions send placeholder keys with a gear badge
  (listed in README.md and keymap.md).

**Decisions.** No `Device` block in the bundle manifest so the import dialog
asks which device. Top-row digit VKs instead of numpad VKs because RadMapper
uses NumLock as its pause key. Modifier bitmask: Alt=1, Ctrl=2, Shift=4, Win=8.

**Verified.** User confirmed the first revision imports on the MK.2. Later
revisions (nav strips, Multi Actions) were not re-imported in this session.

**Open / next.**
- Confirm the Multi Action keys populate on import; if not, the Stream Deck
  version decides which of the two layouts to keep.
- Confirm real IntelliSpace / PS One shortcuts for the gear-badged buttons and
  replace the placeholders in `build_profile.py`.
- Icon polish is iterative: edit an `ic_*` function, run
  `python3 build_profile.py`, re-import.

**Key files.** `streamdeck/build_profile.py`, `streamdeck/README.md`,
`streamdeck/keymap.md`, `streamdeck/preview.png`,
`streamdeck/RadMapper Radiology.streamDeckProfile`.
