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
// A crash (watchdog reset that we did not ask for) happened at some point
// since the last POWER-ON — not necessarily this boot. The record is sticky
// across our own clean reboots on purpose: a crash report that vanishes the
// moment you press Reboot is a crash report nobody ever gets to read.
extern bool diag_watchdog_boot;
extern uint32_t diag_crash_code;     // breadcrumb phase captured before that reset (0 = none)
extern uint32_t diag_fault_pc;       // faulting PC, hard faults only (0 = hang, not a fault)
extern uint8_t diag_crash_count;     // crashes since power-on, saturates at 63
extern uint8_t diag_crash_flags;     // DIAG_CRASH_FLAG_*

#define DIAG_CRASH_FLAG_FAULT 0x01   // a hard fault, and diag_fault_pc says where
#define DIAG_CRASH_FLAG_STACK 0x02   // the fault frame was at/below the stack bottom: overflow
#define DIAG_CRASH_FLAG_STICKY 0x04  // carried over from an earlier boot in this power session

// Crash breadcrumbs: shared code stamps a phase code via this hook; the
// single-chip build points it at a watchdog scratch register (survives
// watchdog resets), other builds leave it null. A hard fault records the
// faulting PC directly (see main.cc), so the phase code only has to localize
// hangs. Codes:
//   0x0100|cmd  entering the config SET handler for command `cmd`
//   0x0200|cmd  finished that command
//   0x0301/2    set_mapping_from_config begin/end
//   0x0311/2    flash persist begin/end
//   0x0321/2    parse_our_descriptor begin/end
//   0x0331/2    update_their_descriptor_derivates begin/end
extern void (*diag_breadcrumb)(uint32_t code);
#define DIAG_BC(code) do { if (diag_breadcrumb) diag_breadcrumb(code); } while (0)

// Safe mode: booted via the BOOTSEL escape hatch, persisted config skipped.
extern bool diag_safe_mode;

// Set by ConfigCommand::REBOOT; the platform main loop acts on it.
extern bool need_to_reboot;

#endif
