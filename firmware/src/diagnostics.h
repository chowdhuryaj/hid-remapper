// Diagnostics + recovery (fork addition, not upstream).
//
// The Windows failure that motivated this was a black box: no way to tell
// "downstream device never enumerated" from "firmware hung" from "config
// ate the cursor" without a working configurator. This module keeps a few
// always-on counters, drives the LED status patterns, and carries the
// safe-mode / reboot plumbing. Everything here is cheap enough to leave on.
//
// Exposure: GET_POINTER_FX page 3 (see config.cc), so any tool that speaks
// the fork protocol can read it; the LED works with no tools at all.

#ifndef _DIAGNOSTICS_H_
#define _DIAGNOSTICS_H_

#include <stdint.h>

// Counters. Updated from the USB host callbacks (single build) and the
// main loop; read from the config protocol. Plain globals, single-core use.
extern uint8_t diag_hid_itf_count;   // downstream HID interfaces currently mounted
extern uint32_t diag_umounts;        // cumulative downstream unmounts since boot — the "keeps disconnecting" meter
extern uint32_t diag_reports_in;     // input reports received since boot
extern uint32_t diag_ticks;          // 1 kHz ticks processed since boot
extern uint32_t diag_max_tick_us;    // slowest process_mapping() tick, us (high-water)

// True on builds that actually maintain diag_hid_itf_count (the single-chip
// build sets this in extra_init). Gates the "no device" LED pattern so the
// dual/serial variants keep their upstream LED behavior untouched.
extern bool diag_downstream_tracking;
extern bool diag_watchdog_boot;      // this boot was a watchdog reset (crash or stall last session)

// Safe mode: booted via the BOOTSEL escape hatch, persisted config skipped.
extern bool diag_safe_mode;

// Set by ConfigCommand::REBOOT; the platform main loop acts on it.
extern bool need_to_reboot;

#endif
