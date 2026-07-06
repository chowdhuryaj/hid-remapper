// Pointer FX — Flask feature parity module (fork addition, not upstream).
//
// Ports the algorithm cores of the QMK-Vial "Flask" firmware modules
// (pd_accel, pointing_device_smoothing, pd_gestures, wiggle_ball,
// autoscroll, wheel_chords) onto HID Remapper's mapping engine. See
// config-tool-vial/FLASK-PARITY.md for the full design.
//
// Integration contract with remapper.cc:
//   - pfx_input_stage()  runs at the top of process_mapping(), before the
//     tap-hold/sticky/layer logic. It consumes raw cursor X/Y deltas
//     (swallowing them when a gesture set / wheel chord / jog is capturing),
//     runs the wiggle detector, and drives the one-tick pulse usages.
//   - The reverse-mapping walk diverts relative contributions targeting
//     Cursor X/Y into pfx via pfx_divert_cursor() when smoothing or accel
//     is enabled; pfx_output_stage() (after the walk, before the
//     accumulated[] drain) transforms them and adds the result back.
//   - Mappings may target the activation usages below (compiled like GPIO
//     out pins into pfx_out_state); the module samples them once per tick.
//   - Mappings may use the pulse usages below as sources; the module fires
//     them as one-tick presses with a one-tick gap (multi-fire queued).
//   - pfx_cache_ptrs() must be called after set_mapping_from_config() /
//     update_their_descriptor_derivates() rebuild the state-slot table.

#ifndef _POINTER_FX_H_
#define _POINTER_FX_H_

#include <stdint.h>

#define POINTER_FX_USAGE_PAGE 0xFFFB0000

// Activation usages (mapping TARGETS, level- or edge-sensitive).
// bitpos in pfx_out_state = (usage & 0xFFFF) - 1; keep them <= 0x10.
#define PFX_ACT_GESTURE_SET(n) (POINTER_FX_USAGE_PAGE | (0x01 + (n)))  // n = 0..7, level
#define PFX_ACT_AUTOSCROLL_JOG (POINTER_FX_USAGE_PAGE | 0x09)          // level
#define PFX_ACT_AUTOSCROLL_UP (POINTER_FX_USAGE_PAGE | 0x0A)           // edge
#define PFX_ACT_AUTOSCROLL_DOWN (POINTER_FX_USAGE_PAGE | 0x0B)         // edge
#define PFX_ACT_AUTOSCROLL_STOP (POINTER_FX_USAGE_PAGE | 0x0C)         // edge
#define PFX_ACT_FIRST (POINTER_FX_USAGE_PAGE | 0x01)
#define PFX_ACT_LAST (POINTER_FX_USAGE_PAGE | 0x0C)

// Pulse usages (mapping SOURCES, one-tick presses fired by the module).
#define PFX_PULSE_GESTURE(set, dir) (POINTER_FX_USAGE_PAGE | (0x20 + (set) * 8 + (dir)))
#define PFX_PULSE_WIGGLE (POINTER_FX_USAGE_PAGE | 0x70)
#define PFX_PULSE_CHORD(btn, dir) (POINTER_FX_USAGE_PAGE | (0x80 + (btn) * 8 + (dir)))

#define PFX_NUM_GESTURE_SETS 8
#define PFX_NUM_CHORD_BUTTONS 8
#define PFX_NUM_DIRECTIONS 8  // E SE S SW W NW N NE (mouse +y = south)

// Tunable parameters, wire and persist format. All multi-byte fields
// little-endian (RP2040 native). Values ending in _mil are x1000
// fixed-point. Split across two SET/GET pages at PFX_PAGE0_SIZE.
struct __attribute__((packed)) pointer_fx_config_t {
    uint16_t flags;              // PFX_FLAG_*
    uint16_t accel_takeoff_mil;  // sigmoid k, 500..10000 (Flask 2.0)
    uint16_t accel_growth_mil;   // sigmoid g, 0..2000 (Flask 0.25)
    int16_t accel_offset_mil;    // sigmoid s, -10000..10000 (Flask 2.2)
    uint16_t accel_limit_mil;    // low-speed gain floor m, 0..1000 (Flask 0.2)
    uint16_t device_cpi;         // 100..8000, velocity normalization (no way to query the trackball)
    uint16_t smooth_factor_mil;  // EMA alpha, 1..1000 (Flask 0.4)
    uint16_t smooth_timeout_ms;  // EMA idle reset, 0..1000 (Flask 200)
    uint16_t gesture_ratchet;    // counts per fire, 50..2000 (Flask 200)
    uint16_t wiggle_switch_ms;   // reversal window, 10..2000 (Flask 150)
    uint16_t wiggle_cooldown_ms; // post-trigger, 50..2000 (Flask 250)
    uint8_t wiggle_threshold;    // y-quiet counts, 0..20 (Flask 3)
    uint8_t reserved0;
    uint16_t asc_speed_x100;   // autoscroll speed scale, 25..400 (Flask 100)
    uint16_t asc_deadzone;     // jog deadzone counts, 0..200 (Flask 15)
    uint16_t asc_range;        // jog range counts, 50..2000 (Flask 300)
    uint16_t chord_step;       // counts per fire, 50..2000 (Flask 200)
    uint16_t chord_hold_ms;    // capture delay, 0..2000 (Flask 200)
    // v101: software pointer speed ("DPI"), pure output gain applied after
    // accel — the attached device's real sensor CPI can't be commanded.
    uint16_t cursor_gain_mil;  // x1000, 100..4000, 1000 = unchanged
};

// Size of the parameter block as persisted by config version 100 (before
// cursor_gain_mil); used to load legacy flash contents.
#define PFX_V100_BLOCK_SIZE 34

#define PFX_FLAG_SMOOTHING_ENABLED (1 << 0)
#define PFX_FLAG_ACCEL_ENABLED (1 << 1)
#define PFX_FLAG_WIGGLE_ENABLED (1 << 2)
#define PFX_FLAG_AUTOSCROLL_INVERTED (1 << 3)
#define PFX_FLAG_CHORDS_ENABLED (1 << 4)
#define PFX_FLAG_GESTURES_ENABLED (1 << 5)

#define PFX_PAGE0_SIZE 16
#define PFX_PAGE1_SIZE (sizeof(pointer_fx_config_t) - PFX_PAGE0_SIZE)
#define PFX_NUM_PAGES 2

extern pointer_fx_config_t pointer_fx_config;

// Activation flag bits written by the reverse-mapping walk (GPIO-out
// pattern); (usage & 0xFFFF) - 1 = bit position. Cleared by
// pfx_input_stage() after sampling.
extern uint8_t pfx_out_state[2];

void pfx_set_defaults();
void pfx_clamp_config();          // enforce all ranges on pointer_fx_config
void pfx_reset_runtime_state();   // on config change / reset_state()
void pfx_cache_ptrs();            // re-resolve state-slot pointers
bool pfx_is_activation_target(uint32_t usage);

// Per-tick hooks, in call order within process_mapping().
void pfx_input_stage(uint64_t now_ms);
bool pfx_divert_cursor(uint32_t target_usage, int32_t value_mil);  // true = value taken
void pfx_output_stage(uint64_t now_ms);

#endif
