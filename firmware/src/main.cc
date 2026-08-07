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

// --- crash forensics ------------------------------------------------------
//
// Watchdog scratch registers survive a watchdog reset (but not a power
// cycle), so they carry the evidence across the reboot. scratch[4] belongs to
// the SDK — watchdog_enable() stamps its own magic there on every call, which
// is why breadcrumbs must NOT live in it — and scratch[6]/[7] belong to the
// bootrom. What this fork uses:
//
//   scratch[0]  intentional-reboot marker (safe mode / REBOOT command / our
//               own trip to the bootloader). Written ONLY immediately before
//               a reset that cannot be cancelled — see diag_reboot_now(). A
//               marker that outlives the reset it was written for silently
//               swallows the next real crash.
//   scratch[1]  bits 31..16  session liveness magic (DIAG_LIVE_MAGIC16)
//               bits 15..0   live breadcrumb: the phase code now executing
//   scratch[2]  crash record, sticky until the next power cycle:
//                 bits 31..16  phase code at the time of the crash
//                 bit  15      consumed (already read by a later boot)
//                 bits 14..9   crash count since power-on (saturates at 63)
//                 bit  8       a hard fault produced this record
//                 bits  7..0   DIAG_REC_MAGIC8
//   scratch[3]  faulting PC (hard faults only)
//   scratch[5]  MSP at the fault (hard faults only). The bootrom reads
//               scratch[5] only when scratch[4] holds ITS magic (0xb007c0d3),
//               which nothing here ever writes.
//
// The rule the whole scheme rests on: a watchdog reset is NOT by itself
// evidence of a crash. reset_usb_boot(), the bootrom's own restart after a
// UF2 download, picotool and a debugger all reset the chip through the
// watchdog, and on a cold boot every register holds whatever the SRAM came up
// with. So a crash is reported only when a running instance of THIS firmware
// left the liveness magic in scratch[1] — nothing else can put it there — and
// the intentional-reboot markers are subtracted from that. The cases:
//
//   cold power-on      reason == 0, no liveness            -> nothing reported
//   UF2 reflash        liveness cleared before the trip,   -> nothing reported
//                      and the bootrom overwrites
//                      scratch[2]/[3] with its own params
//   BOOTSEL entry      same, plus a CLNR marker for the    -> nothing reported
//                      case where the trip is abandoned
//   tool Reboot        CLNR marker, reset unconditional    -> nothing reported
//   safe-mode gesture  SAFE marker, reset unconditional    -> nothing reported
//   hard fault         isr_hardfault writes the record     -> fault + PC
//   hang               no handler ran; the record is       -> hang + phase
//                      rebuilt here from the breadcrumb
#define CLEAN_REBOOT_MAGIC 0x434c4e52u  // "CLNR" — we asked for this reset
#define DIAG_REC_MAGIC8 0xa7u
#define DIAG_LIVE_MAGIC16 0x11feu  // "LIFE" — this firmware was running here

// scratch[0] as we found it, before the safe-mode check clears it.
static uint32_t boot_marker = 0;

// Declared as an array of unknown bound, not a char: the canary below does
// pointer arithmetic on it, and -Warray-bounds objects to walking off the end
// of a one-byte object.
extern "C" char __StackBottom[];

// Stack canary, painted at every boot and inspected on the next crash. The
// SDK's stack guard is a 32-byte no-access MPU subregion at __StackBottom, so
// the lowest address we may touch is __StackBottom + 32; the canary sits in
// the 32 bytes directly above the guard. Why this exists rather than relying
// on the guard alone: see diag_boot_forensics() and firmware/CMakeLists.txt.
#define DIAG_STACK_CANARY 0x57ac0badu
#define DIAG_STACK_CANARY_WORDS 8
#define DIAG_STACK_CANARY_ADDR ((volatile uint32_t*) (__StackBottom + 32))

static bool diag_stack_canary_intact() {
    for (int i = 0; i < DIAG_STACK_CANARY_WORDS; i++) {
        if (DIAG_STACK_CANARY_ADDR[i] != DIAG_STACK_CANARY) {
            return false;
        }
    }
    return true;
}

static void diag_stack_canary_paint() {
    for (int i = 0; i < DIAG_STACK_CANARY_WORDS; i++) {
        DIAG_STACK_CANARY_ADDR[i] = DIAG_STACK_CANARY;
    }
}

// Arm a reset and never come back. The main loop feeds the watchdog once per
// iteration, and watchdog_update() reloads the counter from the SDK's
// file-static load_value — which watchdog_reboot() has just overwritten with
// its own, much shorter, reboot delay. Returning to the loop after arming a
// reset would therefore refresh that countdown forever: the reset would never
// happen, AND the 2000 ms window would stay shrunk to the reboot delay for the
// rest of the power session, so the next flash erase would reset the chip in
// the middle of a write. Spinning here is also what makes the scratch[0]
// marker unforgeable — it can never outlive the reset it was stamped for.
// USB is still pumped so the ack for the command that asked for this can
// flush during the delay; nothing else runs, so no flash write can start.
static void __attribute__((noreturn)) diag_reboot_now(uint32_t delay_ms) {
    watchdog_reboot(0, 0, delay_ms);
    while (true) {
        tud_task();
    }
}

// M0+ has no fault status registers: the exception frame is all the
// information there is. Record the stacked PC and reset immediately —
// spinning here until the watchdog fires works too, but loses the PC.
// Both halves of the handler live in RAM: remapper_single.ld keeps this
// project's own code in flash, and a fault raised while flash is being
// erased (XIP off) could not fetch a flash-resident handler at all.
extern "C" void __no_inline_not_in_flash_func(hardfault_record)(uint32_t pc, uint32_t sp) {
    uint32_t rec = watchdog_hw->scratch[2];
    uint32_t count =
        (watchdog_hw->reason && ((rec & 0xff) == DIAG_REC_MAGIC8)) ? ((rec >> 9) & 0x3f) : 0;
    if (count < 63) {
        count++;
    }
    watchdog_hw->scratch[3] = pc;
    watchdog_hw->scratch[5] = sp;
    watchdog_hw->scratch[2] =
        ((watchdog_hw->scratch[1] & 0xffff) << 16) | (count << 9) | (1u << 8) | DIAG_REC_MAGIC8;
    watchdog_hw->scratch[0] = 0;  // a fault is never an intentional reboot
    watchdog_reboot(0, 0, 1);
    while (true) {
    }
}

// Naked so the exception frame is still exactly where the hardware left it.
// This build has no RTOS and no core1, so the frame is always at MSP.
extern "C" void __attribute__((naked)) __no_inline_not_in_flash_func(isr_hardfault)(void) {
    __asm volatile(
        "mrs r0, msp         \n"
        "ldr r1, [r0, #24]   \n"  // stacked PC
        "mov r2, r0          \n"
        "mov r0, r1          \n"  // arg 0 = pc
        "mov r1, r2          \n"  // arg 1 = frame base (MSP at fault)
        "bl  hardfault_record\n");
}

// Runs once at boot, BEFORE the watchdog is re-armed and before anything that
// can fault, so the breadcrumb hook it installs also covers the boot path.
static void diag_boot_forensics() {
    const bool intentional =
        (boot_marker == SAFE_MODE_MAGIC) || (boot_marker == CLEAN_REBOOT_MAGIC);
    const bool wd = watchdog_caused_reboot();
    // Positive proof that a running instance of THIS firmware left the
    // breadcrumb. Without it, any watchdog reset that came from the bootrom
    // (BOOTSEL, UF2 reflash), from picotool or from a debugger gets turned
    // into a crash record fabricated out of stale or foreign scratch — and the
    // tool pins the first crash it sees into localStorage, so a crash that
    // never happened is worse than no report at all.
    const bool live = ((watchdog_hw->scratch[1] >> 16) == DIAG_LIVE_MAGIC16);
    uint32_t rec = watchdog_hw->scratch[2];
    // watchdog_hw->reason is cleared only by a real power-on/RUN reset, so it
    // also gates the record against garbage scratch on a cold boot.
    bool rec_valid = wd && ((rec & 0xff) == DIAG_REC_MAGIC8);
    const bool fault_fresh = rec_valid && (rec & (1u << 8)) && !(rec & (1u << 15));
    const bool crashed_now = wd && live && !intentional;

    if (crashed_now && !fault_fresh) {
        // A hang rather than a fault: no handler ran, so the record has to be
        // built here out of the last breadcrumb.
        uint32_t count = rec_valid ? ((rec >> 9) & 0x3f) : 0;
        if (count < 63) {
            count++;
        }
        rec = ((watchdog_hw->scratch[1] & 0xffff) << 16) | (count << 9) | DIAG_REC_MAGIC8;
        watchdog_hw->scratch[2] = rec;
        watchdog_hw->scratch[3] = 0;
        watchdog_hw->scratch[5] = 0;
        rec_valid = true;
    }

    if (rec_valid) {
        diag_watchdog_boot = true;
        diag_crash_code = (rec >> 16) & 0xffff;
        diag_crash_count = (rec >> 9) & 0x3f;
        diag_crash_flags = crashed_now ? 0 : DIAG_CRASH_FLAG_STICKY;
        if (rec & (1u << 8)) {
            diag_fault_pc = watchdog_hw->scratch[3];
            diag_crash_flags |= DIAG_CRASH_FLAG_FAULT;
            // One shape of stack overflow: a large `sub sp, #N` steps clean
            // over the 32-byte guard and the following store faults inside it.
            // SP is already below the guard, so the exception frame stacks in
            // ordinary SCRATCH_Y and the handler does run — the frame sits at
            // or below the bottom of the core-0 stack instead of inside it.
            if (watchdog_hw->scratch[5] <= (uint32_t) __StackBottom) {
                diag_crash_flags |= DIAG_CRASH_FLAG_STACK;
            }
        }
        // The other, far more common shape reports nothing by itself: a `push`
        // that faults INTO the guard leaves SP just above it, so the hardware
        // stacks the HardFault frame into the guard as well. On ARMv6-M a
        // fault during exception entry is unrecoverable — the core goes to
        // LOCKUP, isr_hardfault never runs, and all we ever see is the
        // watchdog's hang report 2 s later with no PC. No guard placement can
        // avoid that: the exception frame always lands on the stack that just
        // overflowed. What does survive a watchdog reset is SRAM, so instead
        // we look at the canary painted just above the guard at the last boot:
        // if it is gone, the stack descended to within 32 bytes of the guard
        // before we died. Only consulted for a crash proven to be ours — the
        // bootrom uses this same SCRATCH_Y area as its USB workspace, so after
        // a BOOTSEL trip the canary is meaningless.
        if (crashed_now && !diag_stack_canary_intact()) {
            diag_crash_flags |= DIAG_CRASH_FLAG_STACK;
        }
        // Mark consumed so a later boot can tell a fresh fault from this one.
        watchdog_hw->scratch[2] = rec | (1u << 15);
    } else {
        // No crash to report: leave nothing behind that a later boot could
        // mistake for one (scratch survives resets, not just ours).
        watchdog_hw->scratch[2] = 0;
        watchdog_hw->scratch[3] = 0;
        watchdog_hw->scratch[5] = 0;
    }

    diag_stack_canary_paint();
    // Declare this session live, phase 0. Done here rather than at the first
    // DIAG_BC so that a hang before any breadcrumb still reads as a crash.
    watchdog_hw->scratch[1] = DIAG_LIVE_MAGIC16 << 16;
    diag_breadcrumb = [](uint32_t code) {
        watchdog_hw->scratch[1] = (DIAG_LIVE_MAGIC16 << 16) | (code & 0xffff);
    };
}

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
            diag_reboot_now(10);  // does not return
        }
    } else {
        held_since = 0;
    }
}

#endif

void reset_to_bootloader() {
#ifdef REMAPPER_SINGLE_EXTRAS
    // The trip to the bootrom is itself a watchdog reset, and so is the
    // restart the bootrom performs after a UF2 download — neither is a crash.
    // Leave nothing behind that the boot on the far side could turn into one.
    // Dropping the liveness magic is the load-bearing part (the bootrom cannot
    // forge it); the CLNR marker only helps if the trip is abandoned without a
    // reflash, since the bootrom is free to reuse the low scratch registers —
    // it overwrites scratch[2] and [3] with the reset_usb_boot parameters —
    // and nothing here is trusted to survive it.
    watchdog_hw->scratch[0] = CLEAN_REBOOT_MAGIC;
    watchdog_hw->scratch[1] = 0;
    watchdog_hw->scratch[2] = 0;
    watchdog_hw->scratch[3] = 0;
    watchdog_hw->scratch[5] = 0;
#endif
    reset_usb_boot(0, 0);
}

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
    boot_marker = watchdog_hw->scratch[0];
    watchdog_hw->scratch[0] = 0;
    if (watchdog_caused_reboot() && (boot_marker == SAFE_MODE_MAGIC)) {
        diag_safe_mode = true;
    }
    // Boot forensics: did the watchdog cause this boot, where did it die, and
    // was it a fault or a hang? Surfaced on the fork status page so "it keeps
    // disconnecting" reports can distinguish firmware crashes from host-side
    // USB resets. It must run before watchdog_enable() (which overwrites
    // scratch[4] with its own magic), and it runs HERE, before anything that
    // can fault, because it is also what installs the breadcrumb hook: run it
    // after load_config()/parse_our_descriptor()/set_mapping_from_config() and
    // a fault in any of them is stamped with the previous session's last
    // phase. It only touches watchdog_hw and the stack canary, so it has no
    // dependency on board_init() or tusb_init().
    diag_boot_forensics();
#endif
    if (diag_safe_mode) {
        // Factory-default boot, nothing loaded from flash: descriptor 0,
        // unmapped passthrough on, Pointer FX off — a plain working mouse.
        pfx_set_defaults();
    } else {
        DIAG_BC(0x0341);
        load_config(FLASH_CONFIG_IN_MEMORY);
        DIAG_BC(0x0342);
    }
    our_descriptor = &our_descriptors[our_descriptor_number];
    // Boot-time codes are distinct from the live-apply ones (0x0321/0x0301)
    // for the same work: "crashed while parsing the descriptor" means a bad
    // SAVED config that will crash again on every boot, which is a different
    // and much worse situation than crashing on a config the user just pushed
    // and can undo.
    DIAG_BC(0x0361);
    parse_our_descriptor();
    DIAG_BC(0x0362);
    DIAG_BC(0x0351);
    set_mapping_from_config();
    DIAG_BC(0x0352);
    board_init();
    extra_init();
    tusb_init();
    stdio_init_all();
#ifdef REMAPPER_SINGLE_EXTRAS
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
#ifdef REMAPPER_SINGLE_EXTRAS
            // Mark it ours, or the next boot reports this as a crash (the
            // watchdog cannot tell who asked) and buries the real record. The
            // marker is only safe because diag_reboot_now() never returns: the
            // reset it arms cannot be cancelled, so the marker cannot outlive
            // it. Builds without the fork watchdog fall through to the plain
            // upstream call, which has nothing feeding it.
            watchdog_hw->scratch[0] = CLEAN_REBOOT_MAGIC;
            diag_reboot_now(100);  // does not return
#else
            watchdog_reboot(0, 0, 100);
#endif
        }
#ifdef REMAPPER_SINGLE_EXTRAS
        // Nothing above may arm a reset and then reach this line: it reloads
        // the counter from the SDK's file-static load_value, which
        // watchdog_reboot() overwrites with its own short delay. See
        // diag_reboot_now().
        watchdog_update();
#endif

        print_stats_maybe();

        activity_led_task();
    }

    return 0;
}
