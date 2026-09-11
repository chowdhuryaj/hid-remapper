# RadMapper second pass

## Result and source

The local review build is **0.6.0.2-preview**, on branch `codex/radmapper-welcoming-setup`. Source: [Claude's branch](https://github.com/chowdhuryaj/hid-remapper/tree/claude/gallant-dijkstra-mtdyku/radmapper), starting at commit `70f3275`. The default branch contains no RadMapper AHK file. The private Claude attachment URL was blocked by the browser; its contents could not be compared byte-for-byte with GitHub.

The work includes a patched single-file AHK script, an offline interactive Mac mockup, a quick-start guide, portable checks, and a Windows regression script. Nothing was pushed or published. The Windows program has **not** been run here: this Mac has neither AutoHotkey nor Wine. Treat the AHK file as a candidate for testing, not a validated release.

## Fixed in source

**RadMapper.ahk:5617** — P1 — Changing a four-way menu to eight previously moved Right to Up-right and Down to Right. The resize helper now preserves compass positions, fills new diagonals with disabled slots, and the editor asks before removing populated diagonals.

**RadMapper.ahk:5630** — P1 — Renaming a menu left name-based bindings pointing at the old name. Renaming now updates explicit radial bindings and radial actions nested in other menus; automatic blank-name selection stays unchanged.

**RadMapper.ahk:5817** — P1 — A generic radial command could execute after focus moved to a different window. The menu remembers its opening window, cancels on focus change, and checks focus and pause state again before the deferred action fires. This does not override deliberate PowerScribe routing.

**RadMapper.ahk:1934** — P1 — Loading defaults after an unrecoverable corrupt file did not protect it from the later first-launch welcome save. The original is now copied to a unique recovery file. If preservation fails, writes are blocked and the user gets a recovery instruction.

**RadMapper.ahk:2090** — P1 — Save cleared the dirty flag before writing and did not report failure to callers. Dirty state now survives failure, the funnel returns success/failure, and Atlas shows persistent unsaved status. Binding and menu editors keep the draft open on write failure. Some legacy callers still use their older success messages; see limitations.

**RadMapper.ahk:2181** — P1 — Import installed the candidate globally before normalization, which could fail after replacement. Container shape is checked first, normalization is guarded, and failure restores the previous in-memory config. A failed disk save also rolls back the candidate.

**RadMapper.ahk:974** — P2 — The JSON parser accepted trailing garbage and permissive number strings. It now enforces a number grammar, rejects trailing content and rejects raw control characters in strings. This is not a claim of full JSON standards conformance.

**RadMapper.ahk:2049** — P2 — Malformed config containers could break menu rendering or migration. Settings, bindings and other collection types are checked before use. MGet now treats non-map inputs as missing values instead of calling an unavailable Has method.

**RadMapper.ahk:12673** — P2 — The preview return backstop used a new bound-function object on each schedule, so callbacks could outlive the preview and reopen settings later. Scheduling and cancellation now share one timer object.

**RadMapper.ahk:8090** — P2 — Blank key actions could be counted as configured commands while doing nothing. Shared validation now asks for a shortcut or Disabled and rejects explicit menu names that do not exist.

**RadMapper.ahk:13549** — P2 — A stale binding editor could save into a row that changed elsewhere. The editor checks object identity and refreshes its reference after upsert. Adding a duplicate assignment asks before replacement.

**RadMapper.ahk:12574** — P2 — Adding or copying a menu left the old menu selected. The newly created menu is now selected for the next edit.

## UX changes in the Windows build

Home now offers radial setup directly and no longer claims nothing is changed by default. The Menus panel presents one sequence: **Edit commands → Assign a button → Practice safely**. Assignment reuses the existing binding editor with the menu and Hold trigger filled in. Four-way editing displays four correctly named rows; eight-way editing displays eight. F1 explains bindings, program scope, optional held inputs, shortcut recording, navigation and recovery. Helper text passes 4.5:1 contrast against all five standard grounds. The primary pink is softer; the incumbent navy/pink/cyan/olive identity is preserved.

## Research and design decisions

1. **Let one gesture serve both learning and fluency.** The original marking-menu work describes waiting for the visible menu as a novice and using the same direction without waiting as an experienced user. Preserve that relationship and keep practice non-executing. The reported performance is not evidence of a clinical productivity benefit in RadMapper. [Kurtenbach & Buxton, CHI 1994](https://www.billbuxton.com/MMUserLearn.html).
2. **Keep direction associations stable.** Learnability depends on spatial memory; growing a menu should insert diagonal gaps instead of rotating existing commands. Four directions are the proposed starting point, with eight available later. This is a design recommendation, not a universal research-backed maximum. [Original marking-menu evaluation](https://www.billbuxton.com/PieMenus.html).
3. **Make controls accessible before making them unusual.** Keyboard operation, readable text, scaling and assistive technology matter in the Windows UI. The existing painted widgets cannot inherit standard-control accessibility automatically. Preserve the classic UI and favor native controls for a future editor replacement. [Microsoft accessibility overview](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/accessibility-overview).
4. **Put help at the point of action.** Short hints explain Program, Hold, Rec and Disabled where users need them. Keep advanced layers and macros available but outside the initial assignment path. This follows the general usability direction of task-appropriate settings and help. [Microsoft usability guidance](https://learn.microsoft.com/en-us/windows/apps/design/usability/).
5. **Use the web checklist only where applicable.** The mockup has semantic controls, visible focus, status announcements, label associations, dialog cancellation, no gesture-only requirement, no external assets and no decorative motion. These browser checks do not prove the native AHK UI accessible. [Web Interface Guidelines](https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md).

The taste profile's contribution is restraint with warmth: a precise dark instrument, familiar language, one clear next action, and no extra features to learn. The mockup explores a visual wheel plus one command editor. **That wheel editor is a proposal, not an implemented Windows screen.** The current AHK direction table was repaired rather than replaced by another untested graphics framework.

## Verification performed on this Mac

- `node tests/mockup.cjs`: passed direction preservation, empty diagonals, draft isolation and unsupported-size rejection using the actual mockup helper.
- `node --check mockup/app.js`: passed JavaScript syntax checking.
- `python3 tests/check_source.py`: passed Atlas/Lumi case-insensitive member collision checks, method-reference checks, shared preview timer identity, and 15 text/background contrast pairs.
- `git diff --check`: passed. These checks do not parse or execute AutoHotkey.
- Browser flow: menu editing, missing-shortcut error and focus, recording, save feedback, four-to-eight growth, populated-diagonal shrink confirmation, cancelled shrink, safe practice, button assignment and navigation were exercised. Desktop and 390px mobile layouts were inspected; the mobile page had no horizontal overflow. A label-layout issue found in the first pass was corrected.

`tests/regression.ahk` exercises actual AHK helpers for JSON, config structure, compass geometry, menu resizing, renaming, paused dispatch, protected recovery and successful/failed saves. **Prepared, not executed.**

## Remaining findings and release gates

**RadMapper.ahk:9835** — P1 — Atlas dropdowns, fields and navigation remain primarily mouse-operated custom graphics, without a complete tab order or UI Automation tree. F1 and the classic window help but do not solve this. The radial editor has no classic equivalent yet. A native-controls editor is the next substantial accessibility task.

**RadMapper.ahk:2090** — P2 — Older settings, macro and classic-dialog callers do not all consume the new save result. Persistent dirty status protects the truth in Atlas, but some transient success messages still need migration. Deep validation of every setting value and imported action payload also remains incomplete.

**RadMapper.ahk:5840** — P2 — The radial wheel intentionally stays centered on the gesture origin and can be clipped at a monitor edge. Moving the visual wheel alone would break direction geometry. Test edge behavior before deciding between shifting both origin and pointer or an alternate preview/list.

**RadMapper.ahk:607** — P2 — The inherited startup code changes the system foreground-lock timeout without restoring it. This pass only prevents that call under RM_TEST. Review whether that system-wide change is needed on a shared workstation before release.

**RadMapper.ahk:10806** — P2 — The existing minimum window size can exceed a small work area. Windows DPI scaling, multiple monitors, display changes, screen readers, GDI rendering, actual input-hook timing and workstation-specific shortcuts remain unverified.

Before release, run the AHK regression script on Windows, then test the actual Menus flow at 100%, 150% and 200% scaling, including resize, rename, recording cancellation, duplicate replacement and a read-only settings folder. Verify Escape/center cancellation, Alt+Tab during an open menu, pause before release, and return from practice without delayed window reopening. Use a nonclinical test context before checking the target viewer and dictation software.

The vendored GpGFX renderer and every historical engine feature have not been exhaustively verified. No bug-free or clinical-readiness claim is made.
