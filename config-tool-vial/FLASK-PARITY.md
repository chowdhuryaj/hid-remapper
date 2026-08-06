# Flask → HID Remapper feature parity: discovery + design

Written 2026-07-05, from code reading in that session (no prior summaries
trusted). Phase 1 = the two architecture summaries below. Phase 2 = the
integration plan at the end.

**CONFIRMED 2026-07-05 (user):** hybrid fork approved — fork the firmware
(config-tool-vial becomes the only configurator; flashing our own UF2
accepted). Scope expanded beyond the four named features to "as many
QMK-Vial Flask features as we are able", including a more sophisticated
GUI with visual layout mapping. Resolution of the doc's open questions:
1. Fork: YES (reverses the 2026-06-29 stock-firmware decision, knowingly).
2. Scope: accel, smoothing, gestures, drag-scroll+wiggle, **plus autoscroll
   and wheel chords** (same pointer_fx plumbing). Keyboard-observation
   features (custom shift keys, sentence case, num word, leader) stay OUT —
   no keyboard is routed through this remapper, so they'd have no input to
   observe; revisit only if a keyboard ever shares the hub. OS-shortcuts and
   select-word ship as GUI-side macro/mapping presets (Mac/PC mode toggle),
   no firmware needed. DPI-set stays impossible (can't command Elecom CPI).
3. Tuning UI: config-tool-vial (web + pywebview desktop), not a Swift port.

---

## Phase 1a — Project A: "HID Remapper" (this repo)

### What it actually is

- **Not QMK/Vial, not a Quantizer Mini fork.** `~/hid-remapper` is a clean
  clone of `jfedor2/hid-remapper` at upstream commit `51ab8b3`, with exactly
  one addition: the untracked `config-tool-vial/` directory. `git status`
  shows zero modified firmware files — the firmware running on the device is
  **stock upstream HID Remapper**.
- Firmware: C++ on the **Raspberry Pi pico-sdk** (RP2040/RP2350), TinyUSB in
  device role toward the host PC, **Pico-PIO-USB** in host role toward the
  attached device (the Elecom Huge Plus trackball, VID 0x056E PID 0x01AB).
  Board: Adafruit Feather RP2040 USB Host — supported upstream as
  `firmware/src/boards/feather_host.h`, so building a forked UF2 for this
  exact board is a normal, supported build (flash = UF2 drag-and-drop).
- The "custom configurator" (`config-tool-vial/`) **replaces the stock web
  tool's UI only**. It speaks the identical wire protocol: HID **feature
  reports, report ID 100, 32-byte packets, CRC-32 in the last 4 bytes**,
  commands from the `ConfigCommand` enum (`types.h`), config version **18**.
  Its "behaviors" (DPI shift, cursor→keys, chording, scroll-text, tap-dance)
  are a GUI-side compiler: high-level structs compile down to ordinary
  device mappings + RPN expressions. The device never sees a "behavior".
  Desktop variant uses pywebview + hidapi (no Chrome), same protocol.

### The report-processing loop, end to end

All in `firmware/src/` (single-USB build: `remapper_single.cc` + `main.cc` +
`remapper.cc`):

1. A 1 kHz repeating timer drives `pio_usb_host_frame()` and sets a tick
   flag (`remapper_single.cc:14`).
2. Main loop calls `tuh_task()`; each incoming HID report from the trackball
   lands in `do_handle_received_report()` (`remapper.cc:1638`), which walks
   the parsed report descriptor's usages and calls `read_input()`
   (`remapper.cc:1482`). Values go into `input_state[]` slots keyed by HID
   usage (e.g. cursor X = `0x00010030`). **Relative usages accumulate**
   (`+=`, line 1504) across multiple reports arriving within the same tick.
3. Once per 1 ms tick, **`process_mapping()` (`remapper.cc:1090`) — the
   single choke point every input passes through**:
   - tap-hold / sticky state machines update;
   - layer mask recomputed (8 layers, bitmask, layer 0 fallback);
   - **all 8 expressions evaluated** (`eval_expr`, `remapper.cc:748`), in
     order, every tick, results exposed as usages `0xFFF30001..8`;
   - 32 shared registers mirrored to usages `0xFFF50001..32`;
   - triggered macros queued;
   - the **reverse-mapping walk** (line 1213): every mapping's sources are
     read from `input_state`, scaled by the mapping's `scaling` (int32,
     ×1000 fixed point, may be negative), and for relative targets summed
     into `accumulated[target_usage]` — which is drained into the outgoing
     report **with fractional carry** (`truncated = val/1000; val -=
     truncated*1000`, line 1387). Scroll targets additionally get low-res
     partial-tick accumulation with a timeout (`handle_scroll`,
     `remapper.cc:128`, `partial_scroll_timeout`).
   - reports that changed are queued and sent to the host via TinyUSB.
4. Relative `input_state` slots are zeroed after the walk (line 1371), so an
   expression or mapping sees *this tick's* delta.

**Where per-axis post-processing would plug in:** it doesn't exist today as
firmware code. Two natural insertion points:
- **Config-level:** a mapping whose source is an expression (`0xFFF3000N`)
  — the expression reads raw X/Y via `input_state`, transforms, and the
  mapping routes the result to Cursor X/Y. This is how `config-tool-vial`
  behaviors already work.
- **Firmware-level (fork):** inside `process_mapping()`, on
  `accumulated[0x00010030/31]` right after the reverse-mapping walk and
  before report emission — output-side, already in ×1000 fixed point with
  carry, catches everything routed to the cursor. Input-side (before the
  walk) for anything that must swallow raw motion (gesture capture).

### What persists on-device vs configurator-only

On-device, in one 4096-byte flash sector (`PERSISTED_CONFIG_SIZE`,
`config.cc`): `persist_config_t` v18 (flags, unmapped-passthrough layer
mask, partial scroll timeout, interval override, tap-hold threshold, GPIO
debounce, descriptor number, macro entry duration) + all mappings + all 32
macros + all 8 expressions + quirks + CRC-32. **Everything the configurator
can set is persisted on the device.** GUI-only: the config-tool-vial
"project" (behavior structs, comments, profile metadata) — the device
stores only the compiled result, like Vial's .vil vs compiled flash.

### Current feature set vs what Flask has

Already there: arbitrary usage→usage mappings with scaling/invert, 8 layers
with sticky/tap/hold activation, 32 macros, the 8-slot RPN expression
engine (55 ops incl. `sqrt`/`atan2`/`sin`/`cos`/`ifte`/`store`/`recall`/
`time`; **no `exp`, no `pow`**), quirks, hi-res scroll, polling-interval
override. Config-tool-vial adds the five compiled behaviors listed above.

Explicitly missing that Flask has:
- **pointer acceleration curve** — nothing anywhere;
- **EMA smoothing** — nothing;
- **flick gestures (ball → keys, ratchet)** — `cursor→keys` behavior is a
  related-but-different thing (proportional held-direction, not
  accumulate-swallow-ratchet);
- **drag-scroll toggle** — *mostly already achievable* with stock
  primitives: map Cursor X→H-scroll / Y→V-scroll with fractional scaling on
  a dedicated layer (partial-tick accumulation ≈ divisor+remainder;
  negative scaling = invert), toggled by a sticky-flagged layer mapping.
  What's genuinely missing: shake-to-toggle (wiggle detection) and a
  one-click builder UI;
- **wiggle/shake detection** — nothing.

### Hard resource limits that shape the design

`NEXPRESSIONS = 8` (globals.h:51), `NREGISTERS = 32` (remapper.cc:114),
shared across *everything*. Existing behaviors already consume heavily
(cursor→keys alone: 5 channels + 6 registers; tap-dance: 1 channel + 8
registers). Values are int32 ×1000 — fine for EMA, hostile to exponentials.

---

## Phase 1b — Project B: "Flask"

### What it actually is

"Flask" is two things, and only one of them is portable:

1. **The macOS companion app** (`~/AdeptCompanion`, SwiftUI + IOKit): a full
   Vial editor + live-tuning UI. It speaks (a) stock VIA/Vial protocol and
   (b) a custom raw-HID tuning protocol (v10) — channel/value-id frames
   piggybacked on VIA's custom_set/get/save commands. **None of this app
   transfers**: HID Remapper has its own protocol and config-tool-vial is
   the equivalent UI surface.
2. **The firmware feature modules** — plain C, living in the
   `qmk-flask-modules` shared repo, consumed as `keymaps/vial/shared/` by
   two QMK-Vial keyboards (Ploopy Adept trackball, Svalboard). These hold
   the algorithms this task ports.

### The pipeline being mirrored

QMK calls `pointing_device_task_user(report_mouse_t)` once per sensor read
(PMW3360, ~1 kHz). The Adept keymap chains
(`keyboards/ploopyco/madromys/keymaps/vial/keymap.c:638`):

```
wiggle_ball_observe(raw x,y)      // pure observer, sees deltas first
wheel_chords_apply                // (out of scope here)
pd_gestures_apply                 // swallows motion while a set is latched
pointing_device_smoothing_apply   // EMA
autoscroll_apply                  // (out of scope here)
drag_scroll_apply                 // x/y → wheel while toggled
pd_accel_apply                    // sigmoid accel, last
```

Tunables persist in a QMK EEPROM datablock (`mad_config_t`), live-tuned
over raw HID, toggled by QMK custom keycodes. Keycodes, EEPROM, and the
HID channels are QMK-shaped and do **not** transfer; the algorithm cores do.

### The four algorithm cores (what actually gets ported)

**pd_accel** (`shared/pd_accel.c:75`) — generalized sigmoid gain on the
whole report vector:
- `velocity = (1000/cpi) * sqrt(x²+y²) / dt_ms` (dt = time since last
  nonzero report; CPI read from the sensor driver);
- `factor = 1 − (1 − limit) / (1 + e^(takeoff·(v − offset)))^(growth/takeoff)`
  — **uses `expf` and `powf`**;
- x,y multiplied by factor, with per-axis fractional carry (reset on
  direction flip or after 500 ms idle);
- defaults: takeoff 2.0, growth 0.25, offset 2.2, limit 0.2 (limit here =
  the *low-speed* gain floor; gain →1.0 at high speed). Enabled flag +
  4 params, all runtime-tunable.

**pointing_device_smoothing** (`shared/pointing_device_smoothing.c:101`) —
per-axis EMA: `ema = α·x + (1−α)·ema`, α default 0.4; state resets after
200 ms of no motion; fractional carry with direction-flip reset. Enabled
flag + 2 params.

**pd_gestures** (`shared/pd_gestures.c:122`) — latched "gesture set":
while active, motion is swallowed (x/y/h/v zeroed) and accumulated; each
time accumulated travel ≥ ratchet step (default 200 counts, range 50–1000),
fire the key for the 8-way direction of the accumulated vector
(`atan2` binning, 45° sectors; empty diagonal falls back to dominant-axis
cardinal), then keep the surplus travel (multi-fire burst, cap 8/report).
Firmware holds 8 sets × 8 direction slots of keycodes; toggled by keycodes.

**drag_scroll** (`keymaps/vial/drag_scroll.c:28`) — while toggled: `h =
(x + rem_h)/div_h`, `v = (y + rem_v)/div_v`, remainders keep the modulo,
x/y zeroed, optional final inversion. Divisors default 40/32 (range 1–64).
Toggled by keycode (`DRG_TOG`), by entering a designated layer, or by —

**wiggle_ball** (`shared/wiggle_ball.c:82`) — shake detector: count strict
X-direction reversals (|x|>1, y below quiet threshold 3) where consecutive
reversals arrive within 150 ms; >3 reversals ⇒ trigger, then 250 ms
cooldown. Kill switch + 3 params. In Flask it toggles drag scroll (or other
configured actions).

---

## Phase 2 — Integration plan (proposed, not yet confirmed)

### The core architectural decision

The existing config-tool-vial project deliberately kept firmware **stock**
(GUI-only work). Full Flask parity cannot honor that constraint: the accel
sigmoid needs `exp`/`pow`, which the expression engine does not have, and
approximating it with available ops (sqrt/div rational curves) changes the
feel and defeats "port the algorithm". Gestures/wiggle are *theoretically*
expressible in RPN but would burn most of the 8 shared expression channels
and 32 registers that the existing five behavior builders already compete
for. **Recommendation: hybrid.**

| Feature | Recommended home | Why |
|---|---|---|
| Drag-scroll (toggle, divisors, invert) | **Pure config** — new behavior builder, stock firmware primitives | Layer + sticky toggle + fractional scaling + `handle_scroll` accumulation already implement it; zero firmware risk; works even with the stock web tool |
| Accel curve | **Firmware (fork)** | No exp/pow in expressions; needs float math + velocity state |
| EMA smoothing | **Firmware (fork)** | Expressible in RPN (2 channels + 2 registers) but channel budget is scarce; native is exact and free of that pressure |
| Gestures (ratchet flicks) | **Firmware (fork)** | Needs swallow-motion + atan2 binning + multi-fire + surplus retention; RPN version would be enormous |
| Wiggle/shake detect | **Firmware (fork)** | Small C state machine; RPN version gnarly |

### Firmware fork shape (new module `firmware/src/pointer_fx.cc/.h`)

Fork stays in-tree on the existing clone (branch off `51ab8b3`), board
target `feather_host`, normal cmake/pico-sdk build, UF2 drag-and-drop flash.

Processing (all inside `process_mapping()`, per 1 ms tick):
1. **Gesture + wiggle stage (input side, before the reverse-mapping walk):**
   read this tick's raw deltas from the cursor X/Y `input_state` slots.
   Wiggle observes them always. If a gesture set is active, zero those
   slots (swallow) and run the ratchet accumulator.
2. **Smoothing + accel stage (output side, after the walk):** transform
   `accumulated[0x00010030/31]` in ×1000 fixed-point space (float math
   internally, results written back ×1000 — the existing fractional-carry
   drain replaces both modules' hand-rolled carries). Order: smoothing →
   accel, matching Flask. Skips when the value is untouched/zero, so
   non-pointer configs pay nothing.
3. Velocity for accel = distance / ms-since-last-nonzero-tick (mirrors
   Flask's `delta_time`), with a **configurable "device CPI" parameter**
   replacing `pointing_device_get_cpi()` — HID Remapper cannot ask the
   Elecom its CPI, so the DPI-normalization constant must be user-set
   (default 1000 ⇒ correction factor 1.0).

**Triggering — the QMK-keycode problem, solved the HID Remapper way:**
Flask's toggle keycodes (`GR1_TOG`, `DRG_TOG`) and gesture output keycodes
have no direct equivalent, and none is needed. New vendor usage page
`0xFFFB0000` ("Pointer FX"):
- **Output usages** (mapping *targets*, written by the walk, consumed by the
  module): "Gesture set N active" (N=1..4), "Smoothing on", "Accel on" —
  so any button, chord, tap/hold/sticky flag, or expression can drive them.
  A *sticky* mapping to "Gesture set 1 active" reproduces `GR1_TOG`'s
  latch exactly, using stock UI semantics.
- **Input usages** (mapping *sources*, set by the module): "Gesture N fired
  E/SE/S/SW/W/NW/N/NE" one-tick pulses (aggregate-relative queueing already
  handles burst multi-fire), "Wiggle triggered" pulse. The user maps these
  to any key/macro/layer action in the normal picker — including mapping
  "Wiggle triggered" to the sticky drag-scroll layer toggle, which
  recreates shake-to-toggle without the module knowing what it toggles.
  This is strictly more flexible than Flask's fixed keycode tables.

**Config/persistence:** new `ConfigCommand`s (`GET_POINTER_FX = 26`,
`SET_POINTER_FX = 27`) carrying a packed params struct (enables + accel
takeoff/growth/offset/limit ×1000 + device-CPI + smoothing factor ×1000 /
reset-timeout + ratchet step + wiggle thresholds — fits one 26-byte
payload, or two value-id'd frames if it outgrows that). Persisted by
appending the struct to the flash layout; `CONFIG_VERSION` bumps 18 → a
fork-local value (proposal: 100+ to never collide with upstream's 19).
Consequence to accept: **the stock web configurator will refuse the forked
device** (strict version checks) — config-tool-vial becomes the only tool,
which matches how it's already used. Older persisted v18 configs load fine
(loader accepts 3..current), params seed to defaults.

### Configurator work (config-tool-vial)

- **New "Pointer" tab**: sliders/steppers for every param above with live
  SET on change + explicit persist, mirroring Flask's Mouse-tab feel.
  GET on connect; hide the tab (or show read-only) when the device reports
  a stock config version, so the tool still works with unforked firmware.
- **keycodes.js**: add the 0xFFFB usages — outputs ("Gesture set 1
  active"…) in target categories, inputs ("Gesture fired E"…, "Wiggle
  triggered") in source categories.
- **New behavior builder: "Drag scroll"** (pure config, ships regardless of
  the firmware decision): claims a layer; emits Cursor X→H-scroll and
  Y→V-scroll mappings with scaling = 1000/divisor (negated for invert) on
  that layer; trigger button gets a sticky (toggle) or plain (momentary)
  layer mapping; passthrough for buttons preserved. UI: trigger picker,
  H/V divisor fields, invert checkbox, hold-vs-toggle radio.
- **New behavior builder: "Gestures"** (thin UI over the firmware feature):
  per-set direction slots rendered as 8 picker fields that compile to plain
  mappings from the 0xFFFB fired-pulse usages, plus the activation trigger
  (compiles to a sticky/held mapping targeting "Gesture set N active").
- **project.js format**: append new behavior kinds (format stays 1 —
  additive), so exported JSON round-trips.

### Sampling-rate caveat (explicit, per the task)

Flask's constants were tuned against the Adept's PMW3360 task at ~1 kHz
with dt measured per-report. On HID Remapper the mapping engine runs at
1 kHz, but **deltas arrive at the Elecom's own USB report rate** — likely
125 Hz (8 ms bInterval, unmeasured; the Monitor tab or `print_stats` can
confirm on hardware). Two mitigations built into the plan: (a) velocity
uses ms-since-last-motion, so burstiness normalizes out the way Flask's
`delta_time` does; (b) HID Remapper's existing `interval_override` setting
can force 1 ms host polling of the trackball. Even so: **accel
takeoff/offset and smoothing α should be treated as needing on-hardware
retune, not copied blind** — the doc's defaults (takeoff 2.0, growth 0.25,
offset 2.2, limit 0.2, α 0.4, ratchet 200) are starting points. Smoothing α
in particular is rate-sensitive: at a true 125 Hz input cadence, α=0.4
"per event" behaves differently than at 1 kHz — retune on device.

### Features that don't transfer cleanly (flagged, not planned)

- Flask's **DPI channel** (PMW3360 CPI set): HID Remapper cannot set the
  Elecom's hardware CPI at all. Closest analog = global cursor scaling
  mapping; the accel "device CPI" param covers normalization only.
- **Autoscroll / wheel chords / leader / custom shift keys / sentence
  case** etc.: out of scope per the task's named feature list (accel,
  smoothing, gestures, drag-scroll). Several would be natural follow-ups
  on the same 0xFFFB plumbing.
- Flask's **status report** (types settings as text): skip — the
  configurator displays live values instead.

### Implementation status (2026-07-05 — Phase 3 built, hardware pass pending)

Branch `flask-parity`: commit `c4dab8c` (firmware) + `3b8cf15` (GUI).

**Firmware (done, builds clean, NOT hardware-tested):**
`firmware/src/pointer_fx.cc/.h` carries all six features (accel, smoothing,
gestures, wiggle, autoscroll, wheel chords). Hooks in `process_mapping()`:
`pfx_input_stage()` at the top (activation-flag sampling, pulse cadence,
wiggle observe, chord/gesture/jog capture + swallow), `pfx_divert_cursor()`
in the relative walk branch, `pfx_output_stage()` (smoothing→accel) before
the `accumulated[]` drain; `pfx_cache_ptrs()` at the end of
`update_their_descriptor_derivates()`. Config: `GET/SET_POINTER_FX` (26/27,
2 pages), `CONFIG_VERSION` 100, params inline in `persist_config_v100_t`
(v18 header + block); unknown upstream 19–99 rejected on load. Build:
`cd firmware/build && PICO_BOARD=feather_host cmake .. && make -j8 remapper`.

**GUI (done, browser-verified):** Pointer tab (live debounced SET, re-read,
persist; hides behind a hint on stock firmware), version negotiation
100→18→…, new builders — Drag scroll (pure stock primitives + optional
wiggle toggle), Gestures, Wheel chords, Shake action, OS shortcut presets
(Mac ⌘ / PC Ctrl, incl. select word/line, compiled into top macro slots) —
Pointer FX picker categories both directions, and a clickable top-view SVG
device diagram on the Keymap tab (geometry in `profiles.js` `layout`).
Dev server: use `serve.py` (adds `Cache-Control: no-cache`) — the default
`http.server` let the browser heuristically cache edited ES modules for
hours (`vial.js` imports `./profiles.js?v=2` to bust one poisoned entry).

### Round 2 (2026-07-05 evening, commits 9dd8886 + 39079a6)

Hardware-confirmed by the user: remapping + Pointer FX protocol work live.
Added since: firmware v101 `cursor_gain_mil` (software pointer speed; v100
flash blobs still load), Vial-style live apply (RAM push, debounced+diffed;
Save persists), project-wide OS for shortcut presets, full-palette themes +
zoom, undo/redo (snapshot stack, ⌘Z/⇧⌘Z), and the new-device profile wizard
(auto-detect from GET_THEIR_USAGES, press-to-identify via Monitor, generic
grid layout, localStorage + project-embedded custom profiles). All module
imports carry `?v=3` — the browser held cache entries from before serve.py
sent no-cache and served stale modules without revalidating (bit us three
times; bump the stamp if it ever recurs).

### Round 3 (2026-08-05 — reliability rework after the Windows failure)

The device failed completely ("no cursor at all") on a Windows machine and
there was no way to diagnose or recover in the field. Root-cause candidates
identified by analysis (accel floor 0.20 force-enabled by default; USB
selective suspend waking only on buttons; boot-protocol lock; downstream
power) — see TROUBLESHOOTING.md for the desk discriminators. The rework
(commit on this branch) reverses two earlier architectural decisions,
knowingly:

1. **CONFIG_VERSION 101 → 18.** The wire protocol and persisted blob are
   upstream-v18 again; Pointer FX persists in a self-validating sidecar at
   the end of the config sector and rides commands 26/27 only. remapper.org
   works again as a fallback; stock firmware flashed over the fork keeps all
   mappings. Fork detection = 'PFX' signature probe on GET_POINTER_FX page 2.
2. **Force-enabled effects → master-gated, default OFF** (flag bit 15,
   derived automatically by the GUI). Fresh flash = upstream behavior
   exactly. Accel low-speed floor default 0.20 → 1.00. Legacy v100/101
   configs keep tuning but load with effects off.

New: BOOTSEL safe mode (hold ~2 s at runtime → factory-defaults boot, flash
untouched + persist refused), watchdog, LED status patterns (slow blink = no
downstream device, fast = safe mode), diagnostics page 3, REBOOT command 28,
motion-triggered remote wakeup, EMA tail drain + stroke-start accel fix,
hosted configurator at https://chowdhuryaj.github.io/hid-remapper/ (GitHub
Pages, repo forked to chowdhuryaj/hid-remapper).

### Hardware pass (remaining)

1. Flash `firmware/build/remapper.uf2` (hold BOOTSEL on the Feather while
   plugging in, drag the UF2).
2. Connect config-tool-vial — status should read "(Flask fork)"; Pointer
   tab should populate.
3. Measure the Elecom's real report rate (Monitor tab / `print_stats`);
   try Settings → polling-rate override at 1000 Hz.
4. Retune accel takeoff/offset + smoothing α on hardware (doc'd defaults
   are Flask's, tuned at ~1 kHz PMW3360 — treat as starting points).
5. Per-param verification, madromys pattern: get → set in-range → set
   out-of-range expecting clamp → persist → power-cycle → re-get.
6. Feel-check each feature: drag scroll (incl. shake toggle), a gesture
   set (arrows), a wheel chord, autoscroll jog + stepped, an OS shortcut.

### Open questions (need answers before Phase 3)

1. **Forking the firmware is now in scope — confirm.** It reverses the
   2026-06-29 "GUI only, stock firmware" decision; the device stops being
   compatible with the stock web configurator, and upstream updates become
   manual rebases. (The task prompt assumes porting into firmware, so this
   looks intended — confirming because it contradicts the recorded earlier
   decision.)
2. **Scope = the four named features** (accel, smoothing, gestures,
   drag-scroll incl. wiggle-toggle)? Or should autoscroll/wheel-chords ride
   along in the same firmware fork?
3. **Tuning UI lives in config-tool-vial** (web/pywebview), not a Swift
   Flask port — assumed yes, confirm.
