# RadMapper handoff

## Objective
Fix: the whole computer froze whenever the user copied or cut (Ctrl+C / Ctrl+X) in any app while RadMapper was running.

## Root cause
`ClipChanged` (registered via `OnClipboardChange`) read `A_Clipboard` synchronously inside the clipboard hook. WM_CLIPBOARDUPDATE fires while the source app may still hold the clipboard or use delayed rendering, so the read blocked or deadlocked. RadMapper's low-level keyboard/mouse hooks live on the same thread, so a blocked thread stalled all input system-wide.

## Completed
- `ClipChanged` no longer touches the clipboard; it arms a one-shot `ClipHarvest` timer (bursts coalesce).
- `ClipHarvest` checks CF_UNICODETEXT, skips hung owners, size-checks via GlobalSize before any read, then reads `A_Clipboard` off the hook thread. Dedupe / MAXCLIP logic unchanged.
- `#ClipboardTimeout 250` added beside `SendMode "Event"`.
- Same edit applied to the user's live v0.6.6.5 copy (delivered as a file in the session); the repo copy is v0.6.1-preview and has diverged (repo copy carries the `RM_TEST` guard and tests).
- Installed `.claude/skills/efficient-fable` (from BuilderIO/skills) for orchestrating Fable with cheaper subagents.

## Decisions
- Did not replace the repo copy with the newer v0.6.6.5 upload: the lineages diverged (762 repo-only lines, incl. test hooks). Fix was ported to both instead.
- No version bump or changelog entry in the header; comment at the fix site only.

## Verification
- `python3 radmapper/tests/check_source.py` → PASS.
- `ClipChanged`/`ClipHarvest` blocks byte-identical between repo copy and live copy.
- Runtime test on Windows still needed: copy/cut in Word/browser/PowerScribe with RadMapper running; confirm no freeze and the Ctrl+Alt+C shelf still fills.

## Leads from the read-only scan (not applied; none causes an every-copy freeze)
- `Warp.Key` (~L22262 in v0.6.6.5): while the keyboard pointer overlay is open, its suppressing InputHook eats Ctrl+C/X as grid letters. Fix: return early on letters when Ctrl is physically down.
- `KeyNameValid` (~L2237): accepts bare modifier names (`Ctrl`, `LControl`...) and `c`/`x` as key rows, which puts a main-thread `#HotIf` evaluation on every such press. Consider rejecting bare modifiers in the key picker.
- GpGFX `Dialog.MsgBox` Ctrl+C handler (~L37473): writes `A_Clipboard` without stamping `g_ClipMine`, so its own copy is re-harvested. Minor.

## Next steps
- User runs the fixed v0.6.6.5 copy on the workstation and confirms.
- Consider syncing the repo copy up to v0.6.6.5 in a separate PR.

## Key files
- `radmapper/RadMapper.ahk` — `ClipChanged`, `ClipHarvest`, `#ClipboardTimeout`
- `.claude/skills/efficient-fable/SKILL.md`
