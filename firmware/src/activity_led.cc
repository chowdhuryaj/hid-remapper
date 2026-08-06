#include "activity_led.h"

#include <bsp/board_api.h>

#include <hardware/timer.h>

#include "diagnostics.h"

static bool led_state = false;
static uint64_t turn_led_off_after = 0;

void activity_led_on() {
    led_state = true;
    board_led_write(true);
    turn_led_off_after = time_us_64() + 50000;
}

void activity_led_off_maybe() {
    if (led_state && (time_us_64() > turn_led_off_after)) {
        led_state = false;
        board_led_write(false);
    }
}

static void blink(uint32_t on_us, uint32_t period_us) {
    bool on = (time_us_64() % period_us) < on_us;
    if (on != led_state) {
        led_state = on;
        board_led_write(on);
    }
}

void activity_led_task() {
    if (diag_safe_mode) {
        // Fast blink: safe mode active, persisted config skipped.
        blink(100000, 200000);
    } else if (diag_downstream_tracking && (diag_hid_itf_count == 0)) {
        // Slow blink: powered and enumerated upstream, but no downstream
        // device mounted — the "is it the trackball or the computer?"
        // question, answered with no tools.
        blink(100000, 1000000);
    } else {
        activity_led_off_maybe();
    }
}
