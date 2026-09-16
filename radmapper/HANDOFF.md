# Handoff — RadMapper 0.6.2-preview: station-aware layouts + keyboard pointer

**Objective.** (1) Window arrangements that survive a different workstation
monitor set, with imaging screens kept for the viewer and windows placed
automatically when a station is recognised. (2) A keyboard "mouseless"
pointer: lettered grid, ninths refinement, loupe, click/drag/snap by keys.

**State.** Implemented in `radmapper/RadMapper.ahk`, documented, portable
checks pass. **Not run on Windows** (no AutoHotkey here). Branch
`claude/gallant-lamport-hiv2cu`.

**Done.**
- §7c rewritten: `StationMons/StationKey/StationEntry`, `ImagingMons` (auto
  = portrait or ≥1.35× the smallest screen's pixels; never all), slots carry
  `mon/fx/fy/fw/fh` next to `x/y/w/h`, `LayoutSlotTarget` (exact on the
  capturing station, adapted elsewhere), maximised-on-wrong-screen fixed,
  guard mode 2 (place new windows once, `g_LayoutPlaced`), station watch
  (`WM_DISPLAYCHANGE` + 5 s poll, debounced `StationSettled`, launch pass),
  `WinPlace` grammar (`next|prev|here|1-9` × `max|left|right|top|bottom|
  tl|tr|bl|br|keep|restore`). `MigrateLayoutSlots` stamps pre-0.6.2 layouts
  with the current station on load.
- §14e `class Warp`: invisible InputHook (modifiers visible), grid layer +
  column highlight + region outline + loupe (`GdipBitmap.FromScreen`, layers
  excluded from capture via `SetWindowDisplayAffinity 0x11`, hide/show
  fallback), UIA `ElementFromPoint` snap (vtable 7 / 43 / 23, 64-bit only),
  drag via `SendMode Input` `MouseMove`, 45 s idle close. Engine key rows
  gated in `OnPressHK`/`OnReleaseHK`.
- Actions `winplace`, `warp` (also in Simple mode); settings `stationAuto`,
  `stationSettleMs`, `imagingMons`, `hkWinNext/Prev/Max` (blank),
  `hkWarp` (`^!g`), `warpZoom/Loupe/Cell`; config key `stations`.
- Windows page: "Saved on" column, This station block (arrangement Select,
  imaging Field, Auto-apply Toggle), four shortcut fields, three-state keep
  button. F1 help and README updated. `tests/regression.ahk` covers the
  pure helpers with a made-up 3-screen station.

**Decisions.** Station identity = sizes in left-to-right order (arrangement
order matters, OS enumeration order does not). First arrangement saved on a
station becomes its own. Grid keys: column then row letter; fine stage
Q W E / A S D / Z X C; commands R M F G N V L on the right hand. Loupe uses
GpGFX's bicubic scaling (crisp-enough; nearest-neighbour would need a
Picture draw-path change).

**Verification.** `python3 radmapper/tests/check_source.py` PASS; bracket
balance of every inserted block checked; `git diff --check` clean. Pending
on Windows: `AutoHotkey64.exe /ErrorStdOut tests\regression.ahk`, then a
live pass: Ctrl+Alt+G on a multi-monitor PC (grid, Tab, letters, loupe, N
on a toolbar button, G drag), save an arrangement, unplug/replug a monitor.

**Risks to check first on Windows.** (1) `SetWindowDisplayAffinity` on a
layered window (falls back to hide/show if it refuses). (2) Hotkeys vs the
invisible InputHook: confirm Ctrl+Alt+G and Ctrl+Alt+Q still fire while the
grid is up (Esc and the idle timeout are the safety net). (3) UIA vtable
indices for `get_CurrentBoundingRectangle` (43) and `get_CurrentName` (23).
(4) Windows page fits at the 940 px minimum width (positions are absolute
from `x`; `w` is ~704 there).

**Next.** Run on Windows; if the grid layer is slow on a 4K screen, drop
in-cell labels for edge headers; consider a numpad-only key set for the
fine stage; per-station names (`stations[i].name`) have no UI yet.

**Key files.** `radmapper/RadMapper.ahk` (§7c ~line 5700, §14e before §15),
`radmapper/tests/regression.ahk`, `radmapper/README.md`.
