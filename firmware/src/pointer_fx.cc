// Pointer FX — Flask feature parity module. See pointer_fx.h for the
// integration contract and config-tool-vial/FLASK-PARITY.md for design.
//
// Algorithm cores ported from the QMK-Vial Flask modules (GPL-2.0-or-later
// heritage: drashna's pointing_device_accel/smoothing/gestures/wiggle_ball,
// plus the Flask autoscroll and wheel_chords):
//   - accel: generalized sigmoid gain on the report vector
//   - smoothing: per-axis EMA with idle reset
//   - gestures: swallow-and-ratchet 8-way flicks while a set is latched
//   - wiggle: X-direction reversal counting -> trigger pulse
//   - autoscroll: stepped/jog continuous wheel ticks
//   - wheel chords: held-button + ball ratchet, same feel as gestures
//
// QMK-isms translated: keycode tables -> pulse usages fired through
// ordinary mappings; toggle keycodes -> activation usages driven by
// (sticky) mappings; EEPROM datablock -> persist_config; float carries ->
// the engine's own x1000 fractional accumulation.

#include <math.h>
#include <string.h>

#include <unordered_map>

#include "our_descriptor.h"  // RESOLUTION_MULTIPLIER
#include "pointer_fx.h"
#include "remapper.h"

// Engine internals we hook into (defined in remapper.cc; `accumulated` is
// deliberately not in globals.h upstream, declare it ourselves).
extern std::unordered_map<uint32_t, int32_t> accumulated;  // usage -> movement * 1000
extern uint8_t resolution_multiplier;

static const uint32_t CURSOR_X_USAGE = 0x00010030;
static const uint32_t CURSOR_Y_USAGE = 0x00010031;
static const uint32_t PFX_V_SCROLL_USAGE = 0x00010038;
static const uint32_t PFX_H_SCROLL_USAGE = 0x000C0238;
static const uint32_t BUTTON_USAGE_PAGE = 0x00090000;
static const uint8_t PFX_V_RESOLUTION_BITMASK = 1 << 0;  // mirrors remapper.cc (internal linkage there)

pointer_fx_config_t pointer_fx_config;
uint8_t pfx_out_state[2] = { 0, 0 };

// ---------------------------------------------------------------------------
// Config defaults / clamping

struct param_range_t {
    uint16_t min;
    uint16_t max;
};

static uint16_t clamp_u16(uint16_t v, uint16_t lo, uint16_t hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

void pfx_set_defaults() {
    pointer_fx_config = (pointer_fx_config_t){
        // Everything off, master gate included. A device with blank or
        // corrupt flash must come up as a plain, fast, working mouse — the
        // features are opt-in from the configurator, not opt-out.
        .flags = 0,
        .accel_takeoff_mil = 2000,
        .accel_growth_mil = 250,
        .accel_offset_mil = 2200,
        // Low-speed gain FLOOR, not a ceiling: the sigmoid runs from this
        // value at rest up to 1.0 at speed. Flask shipped 0.2, which is a
        // 5x slowdown on slow, precise movement — fine once deliberately
        // tuned, ruinous as a default. 1000 (= 1.0) makes the curve an
        // identity, so switching accel on can never make the pointer feel
        // broken; lower it to buy low-speed precision.
        .accel_limit_mil = 1000,
        .device_cpi = 1000,
        .smooth_factor_mil = 400,
        .smooth_timeout_ms = 200,
        .gesture_ratchet = 200,
        .wiggle_switch_ms = 150,
        .wiggle_cooldown_ms = 250,
        .wiggle_threshold = 3,
        .reserved0 = 0,
        .asc_speed_x100 = 100,
        .asc_deadzone = 15,
        .asc_range = 300,
        .chord_step = 200,
        .chord_hold_ms = 200,
        .cursor_gain_mil = 1000,
    };
}

bool pfx_enabled() {
    return (pointer_fx_config.flags & PFX_FLAG_MASTER_ENABLE) != 0;
}

void pfx_clamp_config() {
    pointer_fx_config_t* c = &pointer_fx_config;
    c->accel_takeoff_mil = clamp_u16(c->accel_takeoff_mil, 500, 10000);
    c->accel_growth_mil = clamp_u16(c->accel_growth_mil, 0, 2000);
    if (c->accel_offset_mil < -10000) c->accel_offset_mil = -10000;
    if (c->accel_offset_mil > 10000) c->accel_offset_mil = 10000;
    c->accel_limit_mil = clamp_u16(c->accel_limit_mil, 0, 1000);
    c->device_cpi = clamp_u16(c->device_cpi, 100, 8000);
    c->smooth_factor_mil = clamp_u16(c->smooth_factor_mil, 1, 1000);
    c->smooth_timeout_ms = clamp_u16(c->smooth_timeout_ms, 0, 1000);
    c->gesture_ratchet = clamp_u16(c->gesture_ratchet, 50, 2000);
    c->wiggle_switch_ms = clamp_u16(c->wiggle_switch_ms, 10, 2000);
    c->wiggle_cooldown_ms = clamp_u16(c->wiggle_cooldown_ms, 50, 2000);
    if (c->wiggle_threshold > 20) c->wiggle_threshold = 20;
    c->asc_speed_x100 = clamp_u16(c->asc_speed_x100, 25, 400);
    c->asc_deadzone = clamp_u16(c->asc_deadzone, 0, 200);
    c->asc_range = clamp_u16(c->asc_range, 50, 2000);
    c->chord_step = clamp_u16(c->chord_step, 50, 2000);
    c->chord_hold_ms = clamp_u16(c->chord_hold_ms, 0, 2000);
    c->cursor_gain_mil = clamp_u16(c->cursor_gain_mil, 100, 4000);
}

bool pfx_is_activation_target(uint32_t usage) {
    return (usage >= PFX_ACT_FIRST) && (usage <= PFX_ACT_LAST);
}

// ---------------------------------------------------------------------------
// State-slot plumbing

// Cursor delta slots: (raw, scaled) x port 0. For relative usages the engine
// adds the same delta to every existing slot, so reading one is enough, but
// swallowing must zero all of them.
static int32_t* cursor_x_slots[2] = { NULL, NULL };
static int32_t* cursor_y_slots[2] = { NULL, NULL };
static int32_t* wheel_slots[2] = { NULL, NULL };
static int32_t* tilt_slots[2] = { NULL, NULL };
static int32_t* button_slots[PFX_NUM_CHORD_BUTTONS] = { NULL };

struct pulse_slot_t {
    int32_t* state;
    uint8_t pending;
};

static pulse_slot_t gesture_pulses[PFX_NUM_GESTURE_SETS][PFX_NUM_DIRECTIONS];
static pulse_slot_t chord_pulses[PFX_NUM_CHORD_BUTTONS][PFX_NUM_DIRECTIONS];
static pulse_slot_t chord_wheel_pulses[PFX_NUM_CHORD_BUTTONS][PFX_NUM_CHORD_WHEEL_DIRS];
static pulse_slot_t wiggle_pulse;

void pfx_cache_ptrs() {
    for (int raw = 0; raw < 2; raw++) {
        cursor_x_slots[raw] = remapper_get_state_ptr(CURSOR_X_USAGE, 0, false, raw);
        cursor_y_slots[raw] = remapper_get_state_ptr(CURSOR_Y_USAGE, 0, false, raw);
        wheel_slots[raw] = remapper_get_state_ptr(PFX_V_SCROLL_USAGE, 0, false, raw);
        tilt_slots[raw] = remapper_get_state_ptr(PFX_H_SCROLL_USAGE, 0, false, raw);
    }
    for (int b = 0; b < PFX_NUM_CHORD_BUTTONS; b++) {
        button_slots[b] = remapper_get_state_ptr(BUTTON_USAGE_PAGE | (b + 1), 0, false, false);
        if (button_slots[b] == NULL) {
            button_slots[b] = remapper_get_state_ptr(BUTTON_USAGE_PAGE | (b + 1), 0, false, true);
        }
    }
    for (int s = 0; s < PFX_NUM_GESTURE_SETS; s++) {
        for (int d = 0; d < PFX_NUM_DIRECTIONS; d++) {
            gesture_pulses[s][d].state = remapper_get_state_ptr(PFX_PULSE_GESTURE(s, d), 0, false, false);
        }
    }
    for (int b = 0; b < PFX_NUM_CHORD_BUTTONS; b++) {
        for (int d = 0; d < PFX_NUM_DIRECTIONS; d++) {
            chord_pulses[b][d].state = remapper_get_state_ptr(PFX_PULSE_CHORD(b, d), 0, false, false);
        }
        for (int w = 0; w < PFX_NUM_CHORD_WHEEL_DIRS; w++) {
            chord_wheel_pulses[b][w].state = remapper_get_state_ptr(PFX_PULSE_CHORD_WHEEL(b, w), 0, false, false);
        }
    }
    wiggle_pulse.state = remapper_get_state_ptr(PFX_PULSE_WIGGLE, 0, false, false);
}

static int32_t read_cursor_delta(int32_t* slots[2]) {
    if (slots[1] != NULL) {
        return *slots[1];  // raw slot preferred (expressions use it)
    }
    if (slots[0] != NULL) {
        return *slots[0];
    }
    return 0;
}

static void swallow_cursor_deltas() {
    for (int raw = 0; raw < 2; raw++) {
        if (cursor_x_slots[raw] != NULL) {
            *cursor_x_slots[raw] = 0;
        }
        if (cursor_y_slots[raw] != NULL) {
            *cursor_y_slots[raw] = 0;
        }
    }
}

// One-tick press with a guaranteed one-tick gap between repeats, so every
// consumer (key output, macro edge, sticky layer toggle) sees each fire as
// a distinct press. Multi-fire bursts queue in `pending`.
static void pulse_drain(pulse_slot_t* p) {
    if (p->state == NULL) {
        return;
    }
    if (*p->state != 0) {
        *p->state = 0;
    } else if (p->pending > 0) {
        *p->state = 1;
        p->pending--;
    }
}

static void pulse_fire(pulse_slot_t* p) {
    if ((p->state != NULL) && (p->pending < 8)) {  // matches Flask's burst cap
        p->pending++;
    }
}

// ---------------------------------------------------------------------------
// Shared ratchet math (pd_gestures.c / wheel_chords.c, verbatim semantics)

static bool ratchet_reached(int32_t x, int32_t y, uint16_t thresh) {
    int64_t d2 = (int64_t) x * (int64_t) x + (int64_t) y * (int64_t) y;
    int64_t t2 = (int64_t) thresh * (int64_t) thresh;
    return d2 >= t2;
}

// 8-way bin of the accumulated vector, 45 degree sectors, E then clockwise
// (mouse +y = south): 0=E 1=SE 2=S 3=SW 4=W 5=NW 6=N 7=NE.
static uint8_t ratchet_direction(int32_t x, int32_t y) {
    float r = atan2f((float) y, (float) x);
    float d = 180.0f * r / 3.14159265f;
    int16_t id = (int16_t) d;
    const int split = PFX_NUM_DIRECTIONS;
    return ((id + 360 + 360 / split / 2) % 360 / (360 / split)) % split;
}

// Empty-diagonal fallback: an unmapped diagonal fires the nearest cardinal
// by dominant axis, so 4-way sets keep the 90-degree-sector feel.
static pulse_slot_t* resolve_direction_pulse(pulse_slot_t row[PFX_NUM_DIRECTIONS], uint8_t direction, int32_t x, int32_t y) {
    pulse_slot_t* p = &row[direction];
    if ((p->state == NULL) && (direction & 1)) {
        uint8_t cardinal;
        int64_t ax = x < 0 ? -(int64_t) x : (int64_t) x;
        int64_t ay = y < 0 ? -(int64_t) y : (int64_t) y;
        if (ax >= ay) {
            cardinal = (x >= 0) ? 0 : 4;  // E or W
        } else {
            cardinal = (y >= 0) ? 2 : 6;  // S or N
        }
        p = &row[cardinal];
    }
    return (p->state != NULL) ? p : NULL;
}

// Fire one pulse per ratchet step of travel, keeping surplus travel
// (multi-fire), with the same burst cap of 8 as Flask.
static void ratchet_run(int32_t* acc_x, int32_t* acc_y, uint16_t step, pulse_slot_t row[PFX_NUM_DIRECTIONS]) {
    uint8_t burst = 8;
    while (ratchet_reached(*acc_x, *acc_y, step) && burst--) {
        pulse_slot_t* p = resolve_direction_pulse(row, ratchet_direction(*acc_x, *acc_y), *acc_x, *acc_y);
        if (p != NULL) {
            pulse_fire(p);
        }
        float dist = sqrtf((float) *acc_x * (float) *acc_x + (float) *acc_y * (float) *acc_y);
        if (dist <= (float) step) {
            *acc_x = 0;
            *acc_y = 0;
            break;
        }
        float keep = (dist - (float) step) / dist;
        *acc_x = (int32_t) ((float) *acc_x * keep);
        *acc_y = (int32_t) ((float) *acc_y * keep);
    }
}

static bool row_has_any_pulse(pulse_slot_t row[PFX_NUM_DIRECTIONS]) {
    for (int d = 0; d < PFX_NUM_DIRECTIONS; d++) {
        if (row[d].state != NULL) {
            return true;
        }
    }
    return false;
}

// ---------------------------------------------------------------------------
// Runtime state

// activation flags sampled from pfx_out_state (previous tick's walk)
static uint16_t act_flags = 0;
static uint16_t prev_act_flags = 0;

// gestures
static int8_t gesture_active_set = -1;
static int32_t gesture_acc_x = 0;
static int32_t gesture_acc_y = 0;

// wheel chords
static int8_t chord_active_button = -1;
static int32_t chord_acc_x = 0;
static int32_t chord_acc_y = 0;
static uint64_t chord_press_ms = 0;

// wiggle
static uint8_t wiggle_shake_count = 0;
static bool wiggle_last_direction = false;
static uint64_t wiggle_last_toggle_ms = 0;
static uint64_t wiggle_last_switch_ms = 0;

// autoscroll
static int8_t asc_level = 0;
static bool asc_jogging = false;
static int32_t asc_deflection = 0;
static uint64_t asc_last_tick_ms = 0;

// smoothing + accel
static float ema_x = 0.0f;
static float ema_y = 0.0f;
static uint64_t last_motion_ms = 0;
static int32_t stage_x_mil = 0;
static int32_t stage_y_mil = 0;

void pfx_reset_runtime_state() {
    memset(pfx_out_state, 0, sizeof(pfx_out_state));
    act_flags = 0;
    prev_act_flags = 0;
    gesture_active_set = -1;
    gesture_acc_x = 0;
    gesture_acc_y = 0;
    chord_active_button = -1;
    chord_acc_x = 0;
    chord_acc_y = 0;
    wiggle_shake_count = 0;
    wiggle_last_direction = false;
    asc_level = 0;
    asc_jogging = false;
    asc_deflection = 0;
    ema_x = 0.0f;
    ema_y = 0.0f;
    last_motion_ms = 0;
    stage_x_mil = 0;
    stage_y_mil = 0;
    for (int s = 0; s < PFX_NUM_GESTURE_SETS; s++) {
        for (int d = 0; d < PFX_NUM_DIRECTIONS; d++) {
            gesture_pulses[s][d].pending = 0;
        }
    }
    for (int b = 0; b < PFX_NUM_CHORD_BUTTONS; b++) {
        for (int d = 0; d < PFX_NUM_DIRECTIONS; d++) {
            chord_pulses[b][d].pending = 0;
        }
        for (int w = 0; w < PFX_NUM_CHORD_WHEEL_DIRS; w++) {
            chord_wheel_pulses[b][w].pending = 0;
        }
    }
    wiggle_pulse.pending = 0;
}

// ---------------------------------------------------------------------------
// Feature stages

// wiggle_ball.c verbatim, on raw per-tick deltas, ms timers from the engine
static void wiggle_observe(int32_t x, int32_t y, uint64_t now_ms) {
    if (!(pointer_fx_config.flags & PFX_FLAG_WIGGLE_ENABLED) || (wiggle_pulse.state == NULL)) {
        return;
    }
    if (now_ms - wiggle_last_toggle_ms <= pointer_fx_config.wiggle_cooldown_ms) {
        return;
    }
    if (now_ms - wiggle_last_switch_ms > pointer_fx_config.wiggle_switch_ms) {
        wiggle_shake_count = 0;
    }
    if ((x > 1) && (y < pointer_fx_config.wiggle_threshold) && !wiggle_last_direction) {
        wiggle_shake_count++;
        wiggle_last_switch_ms = now_ms;
        wiggle_last_direction = !wiggle_last_direction;
    }
    if ((x < -1) && (y < pointer_fx_config.wiggle_threshold) && wiggle_last_direction) {
        wiggle_shake_count++;
        wiggle_last_switch_ms = now_ms;
        wiggle_last_direction = !wiggle_last_direction;
    }
    if (wiggle_shake_count > 3) {
        pulse_fire(&wiggle_pulse);
        wiggle_shake_count = 0;
        wiggle_last_toggle_ms = now_ms;
        wiggle_last_switch_ms = now_ms;
    }
}

// wheel_chords.c ("mouse chords"): capture target = lowest held button with
// mapped slots, hold-delay before capture, fresh accumulator per chord.
// Beyond the ball's 8 ratchet directions, the scroll wheel and tilt are also
// captured while chording: each detent fires the matching wheel pulse.

static bool chord_row_has_any(uint8_t b) {
    if (row_has_any_pulse(chord_pulses[b])) {
        return true;
    }
    for (int w = 0; w < PFX_NUM_CHORD_WHEEL_DIRS; w++) {
        if (chord_wheel_pulses[b][w].state != NULL) {
            return true;
        }
    }
    return false;
}

static int32_t read_delta_pair(int32_t* slots[2]) {
    if (slots[1] != NULL) return *slots[1];
    if (slots[0] != NULL) return *slots[0];
    return 0;
}

static void swallow_pair(int32_t* slots[2]) {
    if (slots[0] != NULL) *slots[0] = 0;
    if (slots[1] != NULL) *slots[1] = 0;
}

static void chord_fire_wheel(uint8_t button, uint8_t w, int32_t ticks) {
    pulse_slot_t* p = &chord_wheel_pulses[button][w];
    if (p->state == NULL) {
        return;
    }
    for (int32_t i = 0; i < ticks && i < 8; i++) {
        pulse_fire(p);
    }
}

static bool chords_stage(int32_t dx, int32_t dy, uint64_t now_ms) {
    if (!(pointer_fx_config.flags & PFX_FLAG_CHORDS_ENABLED)) {
        chord_active_button = -1;
        return false;
    }
    int8_t previous = chord_active_button;
    chord_active_button = -1;
    for (int b = 0; b < PFX_NUM_CHORD_BUTTONS; b++) {
        if ((button_slots[b] != NULL) && (*button_slots[b] != 0) && chord_row_has_any(b)) {
            chord_active_button = b;
            break;
        }
    }
    if (chord_active_button != previous) {
        chord_acc_x = 0;
        chord_acc_y = 0;
        chord_press_ms = now_ms;
    }
    if (chord_active_button < 0) {
        return false;
    }
    // Hold delay: motion during a quick click-drag passes through as normal
    // cursor movement; only a deliberate hold turns the ball into a chord.
    if ((pointer_fx_config.chord_hold_ms != 0) && (now_ms - chord_press_ms < pointer_fx_config.chord_hold_ms)) {
        return false;
    }
    chord_acc_x += dx;
    chord_acc_y += dy;
    ratchet_run(&chord_acc_x, &chord_acc_y, pointer_fx_config.chord_step, chord_pulses[chord_active_button]);

    // Wheel + tilt while chording: swallow the detents and fire per tick.
    int32_t wv = read_delta_pair(wheel_slots);
    int32_t tv = read_delta_pair(tilt_slots);
    if (wv != 0) {
        chord_fire_wheel(chord_active_button, wv > 0 ? 0 : 1, wv > 0 ? wv : -wv);
        swallow_pair(wheel_slots);
    }
    if (tv != 0) {
        chord_fire_wheel(chord_active_button, tv < 0 ? 2 : 3, tv < 0 ? -tv : tv);
        swallow_pair(tilt_slots);
    }
    return true;
}

// pd_gestures.c: activation flags choose the set (lowest wins); a set with
// no mapped pulses can't capture (would freeze the cursor — same guard as
// Flask's all-KC_NO toggle refusal).
static bool gestures_stage(int32_t dx, int32_t dy) {
    if (!(pointer_fx_config.flags & PFX_FLAG_GESTURES_ENABLED)) {
        gesture_active_set = -1;
        return false;
    }
    int8_t set = -1;
    for (int s = 0; s < PFX_NUM_GESTURE_SETS; s++) {
        if ((act_flags & (1 << s)) && row_has_any_pulse(gesture_pulses[s])) {
            set = s;
            break;
        }
    }
    if (set != gesture_active_set) {
        gesture_acc_x = 0;
        gesture_acc_y = 0;
        gesture_active_set = set;
    }
    if (gesture_active_set < 0) {
        return false;
    }
    gesture_acc_x += dx;
    gesture_acc_y += dy;
    ratchet_run(&gesture_acc_x, &gesture_acc_y, pointer_fx_config.gesture_ratchet, gesture_pulses[gesture_active_set]);
    return true;
}

// autoscroll.c: stepped levels 1..9 map onto tick intervals, jog
// interpolates between the slowest and fastest of those.
static const uint16_t asc_step_intervals[9] = { 1000, 500, 200, 100, 67, 50, 40, 33, 25 };

static uint16_t asc_stepped_interval(uint8_t magnitude) {
    uint32_t base = asc_step_intervals[magnitude - 1];
    uint32_t scaled = base * 100 / pointer_fx_config.asc_speed_x100;
    return scaled < 5 ? 5 : (uint16_t) scaled;
}

static uint16_t asc_jog_interval(uint32_t magnitude) {
    uint32_t slowest = asc_stepped_interval(1);
    uint32_t fastest = asc_stepped_interval(9);
    if (magnitude >= pointer_fx_config.asc_range) {
        return (uint16_t) fastest;
    }
    return (uint16_t) (slowest - (slowest - fastest) * magnitude / pointer_fx_config.asc_range);
}

static void asc_stop() {
    asc_level = 0;
    asc_jogging = false;
    asc_deflection = 0;
}

static void asc_step(int8_t direction, uint64_t now_ms) {
    if (asc_jogging) {
        asc_stop();
    }
    int8_t next = asc_level + direction;
    if (next > 9) next = 9;
    if (next < -9) next = -9;
    asc_level = next;
    asc_last_tick_ms = now_ms;  // full interval before the first tick
}

// Jog activation is level-sensitive (hold or sticky-latch the activation
// usage); steps and stop are edge-sensitive.
static void autoscroll_stage(int32_t dy, bool jog_captured_input, uint64_t now_ms) {
    uint16_t act_bit_jog = 1 << ((PFX_ACT_AUTOSCROLL_JOG & 0xFFFF) - 1);
    uint16_t act_bit_up = 1 << ((PFX_ACT_AUTOSCROLL_UP & 0xFFFF) - 1);
    uint16_t act_bit_down = 1 << ((PFX_ACT_AUTOSCROLL_DOWN & 0xFFFF) - 1);
    uint16_t act_bit_stop = 1 << ((PFX_ACT_AUTOSCROLL_STOP & 0xFFFF) - 1);

    bool jog_active = act_flags & act_bit_jog;
    if (jog_active && !asc_jogging) {
        asc_stop();  // clears any stepped level
        asc_jogging = true;
        asc_last_tick_ms = now_ms;
    } else if (!jog_active && asc_jogging) {
        asc_stop();
    }
    if ((act_flags & act_bit_up) && !(prev_act_flags & act_bit_up)) {
        asc_step(1, now_ms);
    }
    if ((act_flags & act_bit_down) && !(prev_act_flags & act_bit_down)) {
        asc_step(-1, now_ms);
    }
    if ((act_flags & act_bit_stop) && !(prev_act_flags & act_bit_stop)) {
        asc_stop();
    }

    int8_t scroll_dir = 0;
    uint16_t interval = 0;
    if (asc_jogging) {
        if (jog_captured_input) {
            asc_deflection += dy;
        }
        int32_t limit = (int32_t) pointer_fx_config.asc_deadzone + pointer_fx_config.asc_range;
        if (asc_deflection > limit) asc_deflection = limit;
        if (asc_deflection < -limit) asc_deflection = -limit;
        int32_t past = (asc_deflection < 0 ? -asc_deflection : asc_deflection) - pointer_fx_config.asc_deadzone;
        if (past > 0) {
            // Ball down (y+) scrolls down — wheel negative in HID convention.
            scroll_dir = asc_deflection > 0 ? -1 : 1;
            interval = asc_jog_interval((uint32_t) past);
        }
    } else if (asc_level != 0) {
        scroll_dir = asc_level > 0 ? 1 : -1;
        interval = asc_stepped_interval(asc_level > 0 ? asc_level : -asc_level);
    }

    if ((scroll_dir != 0) && (now_ms - asc_last_tick_ms >= interval)) {
        asc_last_tick_ms = now_ms;
        int8_t v = (pointer_fx_config.flags & PFX_FLAG_AUTOSCROLL_INVERTED) ? -scroll_dir : scroll_dir;
        // One wheel detent, in the engine's x1000 units; hi-res hosts get
        // the same distance at RESOLUTION_MULTIPLIER granularity.
        int32_t detent = (resolution_multiplier & PFX_V_RESOLUTION_BITMASK) ? 1000 * RESOLUTION_MULTIPLIER : 1000;
        accumulated[PFX_V_SCROLL_USAGE] += v * detent;
    }
}

// ---------------------------------------------------------------------------
// Per-tick hooks

void pfx_input_stage(uint64_t now_ms) {
    if (!pfx_enabled()) {
        // Master gate clear: do nothing at all. Clear the activation bits the
        // walk may still be writing so no stale state survives into a later
        // enable, then leave the tick exactly as upstream would have run it.
        memset(pfx_out_state, 0, sizeof(pfx_out_state));
        return;
    }

    // Sample last tick's activation bits (written by the reverse-mapping
    // walk into pfx_out_state, GPIO-out style) and clear for this tick.
    prev_act_flags = act_flags;
    act_flags = (uint16_t) pfx_out_state[0] | ((uint16_t) pfx_out_state[1] << 8);
    memset(pfx_out_state, 0, sizeof(pfx_out_state));

    // End the previous tick's pulses / start queued ones.
    for (int s = 0; s < PFX_NUM_GESTURE_SETS; s++) {
        for (int d = 0; d < PFX_NUM_DIRECTIONS; d++) {
            pulse_drain(&gesture_pulses[s][d]);
        }
    }
    for (int b = 0; b < PFX_NUM_CHORD_BUTTONS; b++) {
        for (int d = 0; d < PFX_NUM_DIRECTIONS; d++) {
            pulse_drain(&chord_pulses[b][d]);
        }
        for (int w = 0; w < PFX_NUM_CHORD_WHEEL_DIRS; w++) {
            pulse_drain(&chord_wheel_pulses[b][w]);
        }
    }
    pulse_drain(&wiggle_pulse);

    int32_t dx = read_cursor_delta(cursor_x_slots);
    int32_t dy = read_cursor_delta(cursor_y_slots);

    // Wiggle observes raw deltas FIRST, before any capture zeroes them, so a
    // shake works both to engage an action and to escape one (Flask v10).
    if ((dx != 0) || (dy != 0)) {
        wiggle_observe(dx, dy, now_ms);
    }

    // Capture order matches Flask: chords beat gestures (a held button is a
    // more deliberate intent than a latched set); jog swallows like drag
    // scroll. First captor wins the motion.
    bool captured = chords_stage(dx, dy, now_ms);
    if (!captured) {
        captured = gestures_stage(dx, dy);
    }
    bool jog_wants_input = asc_jogging || (act_flags & (1 << ((PFX_ACT_AUTOSCROLL_JOG & 0xFFFF) - 1)));
    autoscroll_stage(dy, !captured && jog_wants_input, now_ms);
    if (!captured && jog_wants_input) {
        captured = true;
    }

    if (captured && ((dx != 0) || (dy != 0))) {
        swallow_cursor_deltas();
    }
}

static bool pfx_output_active() {
    return pfx_enabled() &&
        ((pointer_fx_config.flags & (PFX_FLAG_SMOOTHING_ENABLED | PFX_FLAG_ACCEL_ENABLED)) ||
            (pointer_fx_config.cursor_gain_mil != 1000));
}

bool pfx_divert_cursor(uint32_t target_usage, int32_t value_mil) {
    if (!pfx_output_active()) {
        return false;
    }
    if (target_usage == CURSOR_X_USAGE) {
        stage_x_mil += value_mil;
        return true;
    }
    if (target_usage == CURSOR_Y_USAGE) {
        stage_y_mil += value_mil;
        return true;
    }
    return false;
}

// Smoothing then accel, matching Flask's pipeline order. Runs on whatever
// the walk routed to Cursor X/Y this tick, in float counts; the result goes
// back into accumulated[] whose x1000 drain keeps the fractional carry that
// the QMK modules maintained by hand.
void pfx_output_stage(uint64_t now_ms) {
    if (!pfx_output_active()) {
        return;
    }

    float in_x = (float) stage_x_mil / 1000.0f;
    float in_y = (float) stage_y_mil / 1000.0f;
    stage_x_mil = 0;
    stage_y_mil = 0;

    if ((in_x == 0.0f) && (in_y == 0.0f)) {
        if (now_ms - last_motion_ms > pointer_fx_config.smooth_timeout_ms) {
            // Stroke over: reset the filter. (Flask discards the EMA tail
            // outright; we decay it out below instead, so no distance is
            // lost — by the time the timeout lands the tail has already
            // been emitted and this is a no-op numerically.)
            ema_x = 0.0f;
            ema_y = 0.0f;
            return;
        }
        // Idle tick inside a stroke's timeout window: keep running the
        // filter on zero input so the EMA tail drains into the report
        // instead of being dropped when the timeout hits. Without this,
        // every short nudge loses (1-alpha) of its final samples — the
        // "small test movement doesn't register" failure mode.
        if ((pointer_fx_config.flags & PFX_FLAG_SMOOTHING_ENABLED) && ((ema_x != 0.0f) || (ema_y != 0.0f))) {
            float f = (float) pointer_fx_config.smooth_factor_mil / 1000.0f;
            ema_x *= 1.0f - f;
            ema_y *= 1.0f - f;
            int32_t tail_x = (int32_t) lroundf(ema_x * 1000.0f);
            int32_t tail_y = (int32_t) lroundf(ema_y * 1000.0f);
            if ((tail_x == 0) && (tail_y == 0)) {
                // Below emission resolution — stop early, nothing to drain.
                ema_x = 0.0f;
                ema_y = 0.0f;
                return;
            }
            float gain = 1.0f;
            if (pointer_fx_config.cursor_gain_mil != 1000) {
                gain = (float) pointer_fx_config.cursor_gain_mil / 1000.0f;
            }
            accumulated[CURSOR_X_USAGE] += (int32_t) lroundf(ema_x * 1000.0f * gain);
            accumulated[CURSOR_Y_USAGE] += (int32_t) lroundf(ema_y * 1000.0f * gain);
        }
        return;
    }

    // dt = ms since the last non-empty tick (Flask's delta_time), so the
    // device's real report cadence (125 Hz vs 1 kHz) normalizes out.
    // Stroke start = first motion after a real pause (fixed 100 ms, NOT
    // smooth_timeout_ms, which may legitimately be 0). Deliberately longer
    // than any sane report interval so mid-stroke gaps never trigger it.
    bool stroke_start = (last_motion_ms == 0) || (now_ms - last_motion_ms > 100);
    uint32_t dt = (uint32_t) (now_ms - last_motion_ms);
    if (dt < 1) dt = 1;
    if (dt > 1000) dt = 1000;
    last_motion_ms = now_ms;

    float out_x = in_x;
    float out_y = in_y;

    if (pointer_fx_config.flags & PFX_FLAG_SMOOTHING_ENABLED) {
        float f = (float) pointer_fx_config.smooth_factor_mil / 1000.0f;
        ema_x = f * in_x + (1.0f - f) * ema_x;
        ema_y = f * in_y + (1.0f - f) * ema_y;
        out_x = ema_x;
        out_y = ema_y;
    }

    if (stroke_start) {
        // First sample after an idle gap: dt is the length of the pause, so
        // "velocity" would compute as ~0 and pin the accel curve to its
        // low-speed floor for exactly the tick the user is watching for a
        // response. There is no honest velocity estimate from one sample —
        // pass it through at unity and let the curve engage from the second
        // sample on.
        if (pointer_fx_config.cursor_gain_mil != 1000) {
            const float gain = (float) pointer_fx_config.cursor_gain_mil / 1000.0f;
            out_x *= gain;
            out_y *= gain;
        }
        accumulated[CURSOR_X_USAGE] += (int32_t) lroundf(out_x * 1000.0f);
        accumulated[CURSOR_Y_USAGE] += (int32_t) lroundf(out_y * 1000.0f);
        return;
    }

    if (pointer_fx_config.flags & PFX_FLAG_ACCEL_ENABLED) {
        const float dpi_correction = 1000.0f / (float) pointer_fx_config.device_cpi;
        const float distance = sqrtf(out_x * out_x + out_y * out_y);
        const float velocity = dpi_correction * distance / (float) dt;
        const float k = (float) pointer_fx_config.accel_takeoff_mil / 1000.0f;
        const float g = (float) pointer_fx_config.accel_growth_mil / 1000.0f;
        const float s = (float) pointer_fx_config.accel_offset_mil / 1000.0f;
        const float m = (float) pointer_fx_config.accel_limit_mil / 1000.0f;
        // Generalised sigmoid: f(v) = 1 - (1 - m) / (1 + e^(k(v-s)))^(g/k)
        const float factor = 1.0f - (1.0f - m) / powf(1.0f + expf(k * (velocity - s)), g / k);
        out_x *= factor;
        out_y *= factor;
    }

    // Software pointer speed, last — a pure output gain so changing it
    // doesn't disturb the accel curve's velocity tuning.
    if (pointer_fx_config.cursor_gain_mil != 1000) {
        const float gain = (float) pointer_fx_config.cursor_gain_mil / 1000.0f;
        out_x *= gain;
        out_y *= gain;
    }

    accumulated[CURSOR_X_USAGE] += (int32_t) lroundf(out_x * 1000.0f);
    accumulated[CURSOR_Y_USAGE] += (int32_t) lroundf(out_y * 1000.0f);
}
