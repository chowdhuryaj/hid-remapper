# Handoff — Stream Deck MK.2 radiology profile

**Objective.** A Stream Deck MK.2 profile for the PowerScribe One +
IntelliSpace reading room, generated from RadMapper's known shortcuts, with
drawn radiology-themed icons and no dependency on RadMapper running.
Everything ships from one generator: `streamdeck/build_profile.py` draws every
icon with Pillow and writes the v2 profile bundle, `preview.png` and
`keymap.md`.

**State.** PR #8 (https://github.com/chowdhuryaj/hid-remapper/pull/8) is open
against `master`, branch `claude/gallant-lamport-hiv2cu`, latest commit
`489dbb0`. No CI covers `streamdeck/`. This round's changes (README
restructure, this file, the layout and icon changes below) are in the working
tree and **not committed**.

## What exists

- **Eight pages**, 15 keys each: Home, PowerScribe editing, PACS tools, PACS
  more, Windowing, Number pad, Web & windows, System.
- **Three Multi Actions**: *Dictate + next field* (F4, 150 ms, Tab),
  *Report → Claude* (Ctrl+A, 150 ms, Ctrl+C, 150 ms, Left, open claude.ai),
  *Open all sites* (four website steps).
- **Eight gear-badged functions** on placeholder keys F13–F20: Spine labeling
  F13, Localizer F14, Scout lines F15, Zoom in F16, Zoom out F17, Invert F18,
  Sign F19, Impression F20. They do nothing until the user assigns them in
  IntelliSpace / PowerScribe; they are listed in README section 2 and at the
  end of `keymap.md`.
- PowerScribe keys are native (F4 / Tab / Shift+Tab). `ROUTE_PS_VIA_RADMAPPER`
  at the top of the key-routing section switches them to RadMapper's global
  `` ` `` `[` `]` bindings.

## Decisions, and where each one came from

- **KeyModifiers bitmask: Shift=1, Ctrl=2, Alt/Option=4, Win/Cmd=8.** Verified
  against a real Stream Deck export, `AngelCruzL/.dotfiles`
  `config/streamdeck/*.sdProfile` (Shift alone 1, Ctrl alone 2, Alt alone 4,
  Cmd alone 8, Ctrl+Shift 3, Ctrl+Alt 6, Cmd+Shift 9). The widely copied
  Graham42 skill document states this backwards (Alt=1 … Shift=4). **Do not
  "fix" it back to that.** `KeyModifiers` is derived from the same booleans the
  key sets, so the two can be re-checked against each other in any build.
- **Page folder names** are a base32-with-`Z` encoding of the page UUID
  (`page_folder_id`), verified against a real export and against what the
  user's own device produced. Do not rename them to plain UUIDs.
- **Home key** is `com.elgato.streamdeck.profile.rotate` with `PageIndex 0` and
  the bundle UUID, so it returns from any depth rather than popping one folder.
  **Untested on hardware.** The fallback is Navigation > Back to Parent per
  level.
- **Multi Action nesting** is `Actions: [{Actions: [steps]}, {Actions: []}]` —
  the outer list is per-state, so state 1 is present and empty. Taken from a
  real Multi Action export seen in round 2/3. The same export carried
  `Plugin`, `Resources` and `OverrideState` on the inner steps, so those are
  emitted too; they are not noise, keep them.
- **Delay step** is `com.elgato.streamdeck.multiactions.delay` with
  `Settings.duration` in ms, from opendeck-factory's reference for the
  multiactions plugin. **Untested** — no export containing a delay has been
  seen.
- **`NativeCode` = the Windows virtual-key code.** The only export available
  was from macOS, where that field holds the Mac key code; using the VK there
  is the reasonable Windows analogue but is **untested on Windows**. If letter
  keys do nothing on the device, this is the first thing to suspect.
- **Top-row digit VKs, not numpad VKs**, because RadMapper uses NumLock as its
  pause key.
- **F13–F20 are placeholders**, not real site shortcuts. RadMapper deliberately
  does not guess IntelliSpace / PS One shortcuts. F13+ was chosen because no
  keyboard sends those keys, so a stray press can never type a character into a
  report. Some shortcut recorders refuse to record them — the README tells the
  user to test F13 and F19 before assigning all eight.
- **Dictate is pinned at (4,1) on every page except Number pad**, where 0 holds
  that slot. Home included, as of this round.
- **Fixed strip columns** (`STRIP_SLOTS = ["ps", "pacs", "wl", "web"]`, with
  Home always at column 0). On a page that is itself a strip section, its own
  column holds Number pad — except PACS tools, whose own column holds PACS
  more, the only link to it. Pages outside `STRIP_SLOTS` (Number pad, PACS
  more, System) match no column and get the plain strip, which is what keeps
  Number pad reachable from Home, Editing, Windowing and Web & windows.
- **No `Device` block** in the bundle manifest, so the import dialog asks which
  device.
- **Fixed zip timestamps** and a sorted walk order, so two rebuilds of the same
  layout differ only in the UUIDs. **Every rebuild regenerates every
  `ActionID`, page UUID and bundle UUID**, so a rebuild with no layout change
  is a large pure-churn diff — do not commit one.
- **Captions are drawn into the image**, so `Icon.label` shrinks a caption to
  fit 248 px (floor 22) and raises `SystemExit` naming the caption if it still
  does not fit. Windows renders them in Segoe UI, not the DejaVu used here, so
  the shrink loop is not optional.

## Verified

- The first revision imported successfully on the user's MK.2.
- Page-folder naming and the modifier bitmask, against a real export.
- The Multi Action nesting shape, against a real export.
- Structural self-check passes: 8 pages × 15 actions, unique titles per page,
  every referenced image present in the zip, `KeyModifiers` consistent with the
  boolean flags on every hotkey, every Multi Action nested as above, Dictate at
  (4,1) everywhere but Number pad, PACS tools ↔ PACS more cross-links.

## Untested

Home key behaviour; `NativeCode` = VK on Windows; the Delay step; whether F13+
can be recorded in the user's IntelliSpace / PowerScribe builds; every revision
after the first import (nav strips, Multi Actions, this round's layout).

## Next steps — hardware checklist for the user

1. Import, pick the MK.2, confirm Home appears.
2. Open Notepad, press **Ruler** on PACS tools: a lowercase `r` must appear.
   That is the `NativeCode` test.
3. Press **Home** from PACS more (two levels down) and see where it lands.
4. Press **Dictate + next field** in a scratch report: both steps must land,
   and 150 ms must be enough of a pause.
5. Try recording F13 in IntelliSpace and F19 in PowerScribe One, then assign
   the remaining six.
6. Report the real site shortcuts so the F13–F20 placeholders can be replaced
   in `build_profile.py`.

## Key files

`streamdeck/build_profile.py` (the only source of truth),
`streamdeck/README.md` (user-facing), `streamdeck/HANDOFF.md` (this file),
`streamdeck/keymap.md`, `streamdeck/preview.png`,
`streamdeck/RadMapper Radiology.streamDeckProfile` — the last three are
generated by `python3 build_profile.py`.
