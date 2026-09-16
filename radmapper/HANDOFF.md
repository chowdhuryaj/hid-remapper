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
  = portrait or ≥1.35× the MEDIAN screen's pixels; when that would reserve
  every screen it narrows to the portraits, else to the largest), slots carry
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
  fallback), UIA `ElementFromPoint` snap (vtable 7 / 42 / 23, 64-bit only),
  drag via `SendMode Input` `MouseMove`, 45 s idle close. Engine key rows
  gated in `OnPressHK`/`OnReleaseHK`.
- Actions `winplace`, `warp` (also in Simple mode); settings `stationAuto`,
  `stationSettleMs`, `imagingMons`, `hkWinNext/Prev/Max` (blank),
  `hkWarp` (`^!g`), `warpZoom/Loupe/Cell`; config key `stations`.
- Windows page: "Saved on" column, This station block (arrangement Select,
  imaging Field, Auto-apply Toggle), four stacked shortcut rows, three-state
  keep button labelled with the selection's CURRENT state. F1 help and README updated. `tests/regression.ahk` covers the
  pure helpers with a made-up 3-screen station.

**Decisions.** Station identity = sizes in left-to-right order (arrangement
order matters, OS enumeration order does not). First arrangement saved on a
station becomes its own. Grid keys: column then row letter; fine stage
Q W E / A S D / Z X C; commands R M F G N V L on the right hand. Loupe uses
GpGFX's bicubic scaling (crisp-enough; nearest-neighbour would need a
Picture draw-path change).

**Verification.** `python3 radmapper/tests/check_source.py` PASS (it now also
asserts the Windows-page HkRow offsets and the Warp timer-identity statics);
`node radmapper/tests/mockup.cjs` PASS; bracket
balance of every inserted block checked; `git diff --check` clean. Pending
on Windows: `AutoHotkey64.exe /ErrorStdOut tests\regression.ahk`, then a
live pass: Ctrl+Alt+G on a multi-monitor PC (grid, Tab, letters, loupe, N
on a toolbar button, G drag), save an arrangement, unplug/replug a monitor.

**Risks to check first on Windows.** (1) `SetWindowDisplayAffinity` on a
layered window — STILL OPEN. If it refuses, the loupe falls back to hiding
overlays for the BitBlt; that path is now narrower (only the layers whose
rects intersect the capture square, the Lumi toast included) and waits 40 ms
instead of 15, and the probe result is cached across opens instead of being
re-learned every time. Nothing here can be proved without a machine that
refuses. (2) Hotkeys vs the invisible InputHook — SETTLED as far as static
review can: modifiers stay `V`isible, `hkWarp` is bound to `Warp.Toggle()` so
a second Ctrl+Alt+G closes the overlay, and `Warp.Open()` now refuses while a
radial menu, the app switcher or the calibrator owns the keyboard ("Close the
menu first"). Esc and the 45 s idle timeout are still the safety net.
(3) UIA vtable indices — SETTLED: 43 was wrong. 42 is
`get_CurrentBoundingRectangle`; 43 is `get_CurrentLabeledBy`, which returns an
IUIAutomationElement, so the old code read a leaked pointer's halves as a
rectangle. 23 (`get_CurrentName`) is unchanged and its BSTR is now freed in a
`finally`. A failed call drops the cached automation object. (4) Windows page
at 940 px — SETTLED: the three window hotkeys use the stacked `HkRow` form in
three 220 px columns at `x`, `x+230`, `x+460` (right edge 680 ≤ pw 704); the
arithmetic is written out in a comment in `PanelWindows` and
`tests/check_source.py` asserts no HkRow offset there exceeds 460.

**Try these first on Windows (v0.6.2c).**
1. **Loupe alignment.** Ctrl+Alt+G, pick a cell, then `+` to zoom to 10-12×
   (where `Round(LW / z)` rounds hardest) and check that the magenta region
   box and the nine letters sit exactly over the magnified pixels, not a few
   px off toward the far corner. That is the `zr := LW / sw` fix.
2. **N snap.** Hover a 14 px toolbar button in PowerScribe or IntelliSpace
   and press N. It should snap to that control and name it. Before the vtable
   fix it snapped to nonsense or refused.
3. **Imaging reservation on a 3-head station.** Windows page → "This station"
   should say which screens are imaging. Try the portrait + 4K case: the
   portraits should be reserved, not "none".
4. **Guard mode 2 after a restart.** Set an arrangement to "new windows",
   exit RadMapper, start it again, then open PACS: it should land in place
   without touching the Windows page. Then disarm and re-arm and open another
   window — it should be placed again (the record is cleared on arming).
5. **Warp click with Ctrl+Alt still held.** Hold Ctrl+Alt, press G, keep both
   held, type a cell and press Space. The click must land unmodified — no
   Ctrl+click tool change in the viewer.
6. Unplug a monitor while the grid is up: the overlay should close and the
   "screens changed" HUD should appear even with auto-apply off.
7. A window arrangement with a maximised PowerScribe: applying it must not
   un-minimise a minimised PS window or move a signing prompt.

**Next.** Run on Windows; if the grid layer is slow on a 4K screen, drop
in-cell labels for edge headers; consider a numpad-only key set for the
fine stage; per-station names (`stations[i].name`) have no UI yet.

**Key files.** `radmapper/RadMapper.ahk` (§7c ~line 6050, §14e ~line 18590,
Atlas Windows page `PanelWindows` ~line 15720),
`radmapper/tests/regression.ahk`, `radmapper/README.md`.
