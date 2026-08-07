#include <set>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <bsp/board_api.h>
#include <tusb.h>

#ifdef ADC_ENABLED
#include <hardware/adc.h>
#endif
#include <hardware/flash.h>
#include <hardware/gpio.h>
#include <pico/bootrom.h>
#include <pico/mutex.h>
#include <pico/platform.h>
#include <pico/stdio.h>
#include <pico/unique_id.h>

#include <hardware/watchdog.h>
#ifdef REMAPPER_SINGLE_EXTRAS
#include <hardware/structs/ioqspi.h>
#include <hardware/structs/sio.h>
#include <hardware/sync.h>
#endif

#include "activity_led.h"
#include "config.h"
#include "crc.h"
#include "descriptor_parser.h"
#include "diagnostics.h"
#include "globals.h"
#include "i2c.h"
#include "mcp4651.h"
#include "our_descriptor.h"
#include "platform.h"
#include "pointer_fx.h"
#include "remapper.h"
#include "tick.h"

// RP2350 UF2s wipe the last sector of flash every time
// because of RP2350-E10 errata mitigation. So we put
// the config one sector down.
#if PICO_RP2350
#define CONFIG_OFFSET_IN_FLASH (PICO_FLASH_SIZE_BYTES - PERSISTED_CONFIG_SIZE - 4096)
#else
#define CONFIG_OFFSET_IN_FLASH (PICO_FLASH_SIZE_BYTES - PERSISTED_CONFIG_SIZE)
#endif

#define FLASH_CONFIG_IN_MEMORY (((uint8_t*) XIP_BASE) + CONFIG_OFFSET_IN_FLASH)

#define ADC_USAGE_PAGE 0xFFF80000

uint64_t next_print = 0;

mutex_t mutexes[(uint8_t) MutexId::N];

uint32_t gpio_valid_pins_mask = 0;
uint32_t gpio_in_mask = 0;
uint32_t gpio_out_mask = 0;
uint32_t prev_gpio_state = 0;
uint64_t last_gpio_change[32] = { 0 };
bool set_gpio_dir_pending = false;

#ifdef ADC_ENABLED
uint16_t prev_adc_state[NADCS] = { 0 };
#endif

void print_stats_maybe() {
    uint64_t now = time_us_64();
    if (now > next_print) {
        print_stats();
        while (next_print < now) {
            next_print += 1000000;
        }
    }
}

void __no_inline_not_in_flash_func(sof_handler)(uint32_t frame_count) {
    sof_callback();
}

bool do_send_report(uint8_t interface, const uint8_t* report_with_id, uint8_t len) {
    if (tud_suspended() &&
        (our_descriptor->should_cause_wakeup != nullptr) &&
        our_descriptor->should_cause_wakeup(report_with_id[0], report_with_id + 1, len - 1)) {
        tud_remote_wakeup();
    } else {
        tud_hid_n_report(interface, report_with_id[0], report_with_id + 1, len - 1);
    }
    return true;  // XXX?
}

void gpio_pins_init() {
    gpio_valid_pins_mask = get_gpio_valid_pins_mask();
    gpio_init_mask(gpio_valid_pins_mask);
}

void set_gpio_inout_masks(uint32_t in_mask, uint32_t out_mask) {
    // if some pin appears as both input and output, input wins
    gpio_out_mask = (out_mask & ~in_mask) & gpio_valid_pins_mask;
    // we treat all pins except the output ones as input so that the monitor works
    gpio_in_mask = gpio_valid_pins_mask & ~gpio_out_mask;
    set_gpio_dir_pending = true;
}

void set_gpio_dir() {
    gpio_set_dir_masked(gpio_in_mask, 0);
    // output pin direction will be set in write_gpio()
    for (uint8_t i = 0; i <= 29; i++) {
        uint32_t bit = 1 << i;
        if (gpio_valid_pins_mask & bit) {
            gpio_set_pulls(i, gpio_in_mask & bit, false);
        }
    }
}

#ifdef ADC_ENABLED
void adc_pins_init() {
    adc_init();
    for (int n = 26; n < 26 + NADCS; n++) {
        adc_gpio_init(n);
    }

#ifdef PICO_SMPS_MODE_PIN
    // (This only does anything on a Pico, but won't hurt on custom board v8.)
    gpio_init(PICO_SMPS_MODE_PIN);
    gpio_set_dir(PICO_SMPS_MODE_PIN, GPIO_OUT);
    gpio_put(PICO_SMPS_MODE_PIN, true);
#endif
}
#endif

bool read_gpio(uint64_t now) {
    uint32_t gpio_state = gpio_get_all() & gpio_in_mask;
    uint32_t changed = prev_gpio_state ^ gpio_state;
    if (changed != 0) {
        for (uint8_t i = 0; i <= 29; i++) {
            uint32_t bit = 1 << i;
            if (changed & bit) {
                if (last_gpio_change[i] + gpio_debounce_time <= now) {
                    uint32_t usage = GPIO_USAGE_PAGE | i;
                    int32_t state = !(gpio_state & bit);  // active low
                    set_input_state(usage, state, state);
                    if (monitor_enabled) {
                        monitor_usage(usage, state, 0);
                    }
                    last_gpio_change[i] = now;
                } else {
                    // ignore this change
                    gpio_state ^= bit;
                    changed ^= bit;
                }
            }
        }
        prev_gpio_state = gpio_state;
    }
    return changed != 0;
}

void write_gpio() {
    if (suspended) {
        return;
    }

    uint32_t value = gpio_out_state[0] | (gpio_out_state[1] << 8) | (gpio_out_state[2] << 16) | (gpio_out_state[3] << 24);
    switch (gpio_output_mode) {
        case 0:
            gpio_put_masked(gpio_out_mask, value);
            gpio_set_dir_masked(gpio_out_mask, gpio_out_mask);
            break;
        case 1:
            gpio_put_masked(gpio_out_mask, 0);
            gpio_set_dir_masked(gpio_out_mask, value);
            break;
    }
    memset(gpio_out_state, 0, sizeof(gpio_out_state));
}

#ifdef ADC_ENABLED
bool read_adc() {
    bool changed = false;
    for (int i = 0; i < NADCS; i++) {
        adc_select_input(i);
        uint16_t state = adc_read();
        if (state != prev_adc_state[i]) {
            changed = true;
            prev_adc_state[i] = state;
        }
        uint32_t usage = ADC_USAGE_PAGE | i;
        set_input_state(usage, state, state >> 4);
        if (monitor_enabled) {
            monitor_usage(usage, state, 0);
        }
    }
    return changed;
}
#endif

void do_persist_config(uint8_t* buffer) {
#if !PICO_COPY_TO_RAM
    uint32_t ints = save_and_disable_interrupts();
#endif
    DIAG_BC(0x0311);
    flash_range_erase(CONFIG_OFFSET_IN_FLASH, PERSISTED_CONFIG_SIZE);
    flash_range_program(CONFIG_OFFSET_IN_FLASH, buffer, PERSISTED_CONFIG_SIZE);
    DIAG_BC(0x0312);
#if !PICO_COPY_TO_RAM
    restore_interrupts(ints);
#endif
}

void reset_to_bootloader() {
    reset_usb_boot(0, 0);
}

#ifdef REMAPPER_SINGLE_EXTRAS

// Computer-free recovery (fork addition). Holding BOOTSEL at power-on is
// taken by the bootrom (UF2 mode), so the safe-mode gesture is: plug in
// normally, THEN hold BOOTSEL for ~2 seconds. The firmware reboots itself
// with a magic in a watchdog scratch register (survives the reboot, not a
// power cycle); on the way back up it skips the persisted config entirely
// and enumerates as a factory-default plain mouse — descriptor 0, passthrough
// on, every Pointer FX effect off. Nothing is written to flash: the next
// normal power cycle restores the saved config.
#define SAFE_MODE_MAGIC 0x53414645u  // "SAFE"

// Reads the BOOTSEL button state. Standard RP2040 technique: briefly float
// the flash CS line and sample it. Safe here because this build runs
// entirely from RAM (copy_to_ram) so nothing touches flash concurrently.
// Interrupts are off for the sample, which delays the 1 kHz PIO-USB SOF
// timer if one lands in the window — so the settle loop is kept short
// (~150 iterations ≈ 5 µs; the pad needs ~1 µs) and the caller runs only
// right after a tick was serviced, when the next SOF is ~1 ms away. A
// full-speed gaming mouse at 1000 Hz drops off the bus if SOF timing is
// repeatedly disturbed; the original 30 µs sample at a random loop phase
// did exactly that.
static bool __no_inline_not_in_flash_func(get_bootsel_button)() {
    const uint CS_PIN_INDEX = 1;
    uint32_t flags = save_and_disable_interrupts();
    hw_write_masked(&ioqspi_hw->io[CS_PIN_INDEX].ctrl,
        GPIO_OVERRIDE_LOW << IO_QSPI_GPIO_QSPI_SS_CTRL_OEOVER_LSB,
        IO_QSPI_GPIO_QSPI_SS_CTRL_OEOVER_BITS);
    for (volatile int i = 0; i < 150; ++i) {
    }
    bool button_state = !(sio_hw->gpio_hi_in & (1u << CS_PIN_INDEX));
    hw_write_masked(&ioqspi_hw->io[CS_PIN_INDEX].ctrl,
        GPIO_OVERRIDE_NORMAL << IO_QSPI_GPIO_QSPI_SS_CTRL_OEOVER_LSB,
        IO_QSPI_GPIO_QSPI_SS_CTRL_OEOVER_BITS);
    restore_interrupts(flags);
    return button_state;
}

// Polled at ~2 Hz, and ONLY right after a tick was processed (i.e. just
// after a SOF, maximally far from the next one). Two consecutive seconds
// of held button trigger the safe-mode reboot.
static void safe_mode_button_task() {
    static uint64_t next_check = 0;
    static uint64_t held_since = 0;
    uint64_t now = time_us_64();
    if (now < next_check) {
        return;
    }
    next_check = now + 500000;
    if (get_bootsel_button()) {
        if (held_since == 0) {
            held_since = now;
        } else if (now - held_since > 2000000) {
            watchdog_hw->scratch[0] = SAFE_MODE_MAGIC;
            watchdog_reboot(0, 0, 10);
        }
    } else {
        held_since = 0;
    }
}

#endif

void pair_new_device() {
}

void clear_bonds() {
}

void my_mutexes_init() {
    for (int i = 0; i < (int8_t) MutexId::N; i++) {
        mutex_init(&mutexes[i]);
    }
}

void my_mutex_enter(MutexId id) {
    mutex_enter_blocking(&mutexes[(uint8_t) id]);
}

void my_mutex_exit(MutexId id) {
    mutex_exit(&mutexes[(uint8_t) id]);
}

uint64_t get_time() {
    return time_us_64();
}

uint64_t get_unique_id() {
    pico_unique_board_id_t unique_id;
    pico_get_unique_board_id(&unique_id);
    uint64_t ret = 0;
    for (int i = 0; i < 8; i++) {
        ret |= (uint64_t) unique_id.id[7 - i] << (8 * i);
    }
    return ret;
}

int main() {
    my_mutexes_init();
    gpio_pins_init();
#ifdef I2C_ENABLED
    our_i2c_init();
#endif
#ifdef ADC_ENABLED
    adc_pins_init();
#endif
    tick_init();
#ifdef REMAPPER_SINGLE_EXTRAS
    // Safe-mode handshake left by safe_mode_button_task() before its reboot.
    // Scratch registers survive a watchdog reboot but not a power cycle, so
    // unplugging always returns to the saved config.
    if (watchdog_caused_reboot() && (watchdog_hw->scratch[0] == SAFE_MODE_MAGIC)) {
        watchdog_hw->scratch[0] = 0;
        diag_safe_mode = true;
    }
#endif
    if (diag_safe_mode) {
        // Factory-default boot, nothing loaded from flash: descriptor 0,
        // unmapped passthrough on, Pointer FX off — a plain working mouse.
        pfx_set_defaults();
    } else {
        load_config(FLASH_CONFIG_IN_MEMORY);
    }
    our_descriptor = &our_descriptors[our_descriptor_number];
    parse_our_descriptor();
    set_mapping_from_config();
    board_init();
    extra_init();
    tusb_init();
    stdio_init_all();
#ifdef REMAPPER_SINGLE_EXTRAS
    // Boot forensics BEFORE re-arming: did the watchdog cause this boot?
    // Surfaced on the fork status page so "it keeps disconnecting" reports
    // can distinguish firmware crashes/stalls from host-side USB resets.
    diag_watchdog_boot = watchdog_caused_reboot();
    if (diag_watchdog_boot) {
        // The last breadcrumb before the reset — where it died.
        diag_crash_code = watchdog_hw->scratch[4];
    }
    watchdog_hw->scratch[4] = 0;
    diag_breadcrumb = [](uint32_t code) { watchdog_hw->scratch[4] = code; };
    // Watchdog: a hang anywhere in the loop becomes a 2-second outage
    // instead of a dead dongle. Enabled after USB init so a slow first
    // enumeration can't trip it; fed once per loop iteration below.
    watchdog_enable(2000, 1);
#endif

    tud_sof_isr_set(sof_handler);

    next_print = time_us_64() + 1000000;

    while (true) {
        bool tick;
        bool new_report;
        read_report(&new_report, &tick);
        if (new_report) {
            activity_led_on();
        }
        if (their_descriptor_updated) {
            DIAG_BC(0x0331);
            update_their_descriptor_derivates();
            DIAG_BC(0x0332);
            their_descriptor_updated = false;
        }
        if (tick) {
            bool gpio_state_changed = read_gpio(time_us_64());
            if (gpio_state_changed) {
                activity_led_on();
            }
#ifdef ADC_ENABLED
            read_adc();
#endif
            uint64_t tick_t0 = time_us_64();
            process_mapping(true);
            uint32_t tick_us = (uint32_t) (time_us_64() - tick_t0);
            if (tick_us > diag_max_tick_us) {
                diag_max_tick_us = tick_us;
            }
            diag_ticks++;
#ifdef REMAPPER_SINGLE_EXTRAS
            // Right after a tick = just after a SOF fired, so the brief
            // IRQ-off window inside the BOOTSEL sample is as far from the
            // next SOF as it can get. Never sample at a random loop phase —
            // 1000 Hz full-speed devices drop off the bus over SOF jitter.
            safe_mode_button_task();
#endif
            write_gpio();
#ifdef MCP4651_ENABLED
            mcp4651_write();
#endif
        }
        tud_task();
        if (boot_protocol_updated) {
            DIAG_BC(0x0321);
            parse_our_descriptor();
            DIAG_BC(0x0322);
            boot_protocol_updated = false;
            config_updated = true;
        }
        if (resume_pending) {
            resume_pending = false;
            suspended = false;
        }
        if (config_updated) {
            DIAG_BC(0x0301);
            set_mapping_from_config();
            DIAG_BC(0x0302);
            config_updated = false;
        }
        if (set_gpio_dir_pending && !suspended) {
            set_gpio_dir();
            set_gpio_dir_pending = false;
        }
        if (tud_hid_n_ready(0) || tud_suspended()) {
            send_report(do_send_report);
        }
        if (monitor_enabled && tud_hid_n_ready(1)) {
            send_monitor_report(do_send_report);
        }
        if (our_descriptor->main_loop_task != nullptr) {
            our_descriptor->main_loop_task();
        }
        send_out_report();
        if (need_to_persist_config) {
            persist_config_return_code = persist_config();
            need_to_persist_config = false;
        }
        if (need_to_reboot) {
            // ConfigCommand::REBOOT: give the ack a moment to flush, then a
            // clean watchdog reset — the host re-enumerates us fresh.
            need_to_reboot = false;
            watchdog_reboot(0, 0, 100);
        }
#ifdef REMAPPER_SINGLE_EXTRAS
        watchdog_update();
#endif

        print_stats_maybe();

        activity_led_task();
    }

    return 0;
}
