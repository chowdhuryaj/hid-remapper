# Troubleshooting (AlooMapper fork)

The device is deliberately diagnosable with **no software installed** on the
computer. Start here before reflashing anything.

## Read the LED first (red LED, D13 on the Feather)

| Pattern | Meaning | What it tells you |
|---|---|---|
| Flashes while you roll the ball / press buttons | Normal: reports are flowing | Trackball is enumerated and alive. If the cursor still doesn't move, the fault is between the firmware's output and the computer (config, suspend, host). |
| Slow blink (short flash every second) | **No downstream device mounted** | The trackball never enumerated on the converter's USB host port. Think power, cable, the trackball itself — not the computer, not the config. |
| Fast blink (5 per second) | **Safe mode** | Booted with factory defaults; saved config untouched and write-protected. Power-cycle to return to the saved config. |
| Dark, no response at all | No power / firmware not running | Different port/cable; reflash if it persists. |

## Safe mode (computer-free recovery)

If a bad configuration ever leaves you without a working cursor:

1. Plug the device in normally (do **not** hold any button while plugging —
   that's the bootloader).
2. **Hold the BOOTSEL button for about 2 seconds.**
3. The device reboots itself into safe mode (fast-blinking LED) and
   re-enumerates as a factory-default plain mouse: passthrough on, all
   pointer effects off, standard mouse/keyboard descriptor.
4. Nothing is written to flash. Fix the config with any configurator, or just
   power-cycle to return to the saved config as it was.

While in safe mode the firmware refuses to persist, so no tool can
accidentally overwrite the saved config during recovery.

## Cursor dead on one specific computer (the 2-minute discriminators)

Run these at the desk, in order. Each isolates a different mechanism:

1. **Watch the LED while rolling the ball.**
   Dark = downstream power/enumeration problem → try a rear (motherboard)
   USB port, then a powered hub. Front-panel ports and monitor hubs are the
   usual suspects.
   Flashing = the input side is fine; continue.
2. **Click a button.** If the cursor springs to life after a click, the
   device was in USB selective suspend and the host only woke on buttons.
   Current fork firmware wakes on motion too — update the firmware if you
   see this on an older build.
3. **Unplug and replug.** If that fixes it, the device had been switched to
   boot protocol (some BIOS/legacy USB layers do this and never switch back);
   replugging resets it.
4. **Check Windows pointer settings.** With "Enhance pointer precision" off
   and a low slider, Windows applies no software gain — firmware-side
   attenuation (old force-enabled accel defaults) shows up here far more
   than on a Mac. Current firmware ships all effects off.
5. **Try the stock firmware as a control** — flash upstream
   [`remapper_feather.uf2`](https://github.com/jfedor2/hid-remapper/releases/latest/download/remapper_feather.uf2).
   If stock is also dead on that machine, the fault is hardware/power/host,
   not this fork.

## Diagnostics in the configurator

With the fork firmware, the config tool can read live counters (Pointer FX
page 3): downstream interfaces mounted, input reports received, engine
ticks, and the slowest 1 ms tick observed. A tick time approaching 1000 µs
means the processing budget is being blown — report it with your config
attached.

## Serial telemetry (optional, for deep debugging)

The firmware prints once-per-second stats on UART TX (GPIO 0) at **921600
baud**: reports received/sent and processing time. Any USB-serial adapter
shows it live.

## Firmware / configurator compatibility

- Current fork firmware speaks the **stock v18 protocol**. The official
  tool at [remapper.org/config](https://www.remapper.org/config/) works as a
  full-featured fallback from any Chrome/Edge browser — mappings, macros,
  expressions, factory reset, bootloader entry. It just doesn't show the
  fork-only Pointer tab.
- The fork configurator detects fork features by probing, not by version,
  and works against stock firmware too (Pointer tab hidden).
- Flashing **stock upstream firmware** over the fork keeps all mappings,
  macros and expressions (the persisted blob is upstream-v18); only the
  Pointer FX parameters are ignored, and they reset to defaults (off) if
  stock firmware saves over them.
- Old fork firmware (config versions 100/101) is still readable: on first
  boot the new firmware loads its tuning numbers but starts with every
  effect **off** (the old builds force-enabled them by default, which is
  what broke slow cursor movement). Re-enable in the Pointer tab.
