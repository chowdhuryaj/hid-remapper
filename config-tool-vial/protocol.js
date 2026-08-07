// Low-level HID Remapper config protocol.
//
// This is a faithful port of the wire protocol implemented in the stock tool's
// config-tool-web/code.js (send_feature_command / read_config_feature and the
// command constants). It is intentionally UI-agnostic: it knows how to talk to
// a HID Remapper over WebHID feature reports, nothing about the DOM.

import crc32 from './crc.js?v=15';

export const REPORT_ID_CONFIG = 100;
export const REPORT_ID_MONITOR = 101;
export const CONFIG_SIZE = 32;
export const CONFIG_VERSION = 18;        // stock/upstream version — current fork firmware speaks this too
export const FORK_VERSIONS = [101, 100]; // LEGACY fork wire versions (pre-sidecar firmware still in the field)

// The device's negotiated config version. The firmware rejects SET frames
// whose version byte doesn't match its own, so the device layer stores the
// negotiated value here after connecting and every frame uses it by default.
let activeConfigVersion = CONFIG_VERSION;
export function setActiveConfigVersion(v) { activeConfigVersion = v; }
export function getActiveConfigVersion() { return activeConfigVersion; }

// Fork capability is no longer encoded in the wire version (current fork
// firmware deliberately reports stock 18 so remapper.org keeps working as a
// fallback). It is detected by probing GET_POINTER_FX page 2 for the 'PFX'
// signature. Generations: 0 = stock, 1 = legacy fork (wire 100/101),
// 2 = sidecar-era fork (wire 18 + signature).
let forkGeneration = 0;
export function setForkGeneration(g) { forkGeneration = g; }
export function getForkGeneration() { return forkGeneration; }
export function deviceIsFork() { return forkGeneration > 0; }

// HID Remapper's config interface advertises this usage page / usage. We match
// on it (not VID/PID) so the tool works on the Feather, the Pico variants and
// the custom boards alike.
export const CONFIG_USAGE_PAGE = 0xFF00;
export const CONFIG_USAGE = 0x0020;

// Mapping flags.
export const STICKY_FLAG = 1 << 0;
export const TAP_FLAG = 1 << 1;
export const HOLD_FLAG = 1 << 2;

// Global config flags.
export const IGNORE_AUTH_DEV_INPUTS_FLAG = 1 << 4;
export const GPIO_OUTPUT_MODE_FLAG = 1 << 5;
export const NORMALIZE_GAMEPAD_INPUTS_FLAG = 1 << 6;

export const NLAYERS = 8;
export const NMACROS = 32;
export const NEXPRESSIONS = 8;
export const NREGISTERS = 32;
export const MACRO_ITEMS_IN_PACKET = 6;
export const HUB_PORT_NONE = 255;

export const DEFAULT_PARTIAL_SCROLL_TIMEOUT = 1000000;
export const DEFAULT_TAP_HOLD_THRESHOLD = 200000;
export const DEFAULT_GPIO_DEBOUNCE_TIME = 5;
export const DEFAULT_SCALING = 1000;
export const DEFAULT_MACRO_ENTRY_DURATION = 1;

// Usage pages used as inputs/outputs by the remapping engine itself.
export const LAYERS_USAGE_PAGE = 0xFFF10000;
export const MACRO_USAGE_PAGE = 0xFFF20000;
export const EXPR_USAGE_PAGE = 0xFFF30000;
export const GPIO_USAGE_PAGE = 0xFFF40000;
export const REGISTER_USAGE_PAGE = 0xFFF50000;
export const MIDI_USAGE_PAGE = 0xFFF70000;
export const BUTTON_USAGE_PAGE = 0x00090000;
// Fork-only: Pointer FX (see firmware/src/pointer_fx.h for the full map).
export const POINTER_FX_USAGE_PAGE = 0xFFFB0000;

export const QUIRK_FLAG_RELATIVE_MASK = 0b10000000;
export const QUIRK_FLAG_SIGNED_MASK = 0b01000000;
export const QUIRK_SIZE_MASK = 0b00111111;

// Config commands.
export const RESET_INTO_BOOTSEL = 1;
export const SET_CONFIG = 2;
export const GET_CONFIG = 3;
export const CLEAR_MAPPING = 4;
export const ADD_MAPPING = 5;
export const GET_MAPPING = 6;
export const PERSIST_CONFIG = 7;
export const GET_OUR_USAGES = 8;
export const GET_THEIR_USAGES = 9;
export const SUSPEND = 10;
export const RESUME = 11;
export const PAIR_NEW_DEVICE = 12;
export const CLEAR_BONDS = 13;
export const FLASH_B_SIDE = 14;
export const CLEAR_MACROS = 15;
export const APPEND_TO_MACRO = 16;
export const GET_MACRO = 17;
export const INVALID_COMMAND = 18;
export const CLEAR_EXPRESSIONS = 19;
export const APPEND_TO_EXPRESSION = 20;
export const GET_EXPRESSION = 21;
export const SET_MONITOR_ENABLED = 22;
export const CLEAR_QUIRKS = 23;
export const ADD_QUIRK = 24;
export const GET_QUIRK = 25;
// Fork-only commands (Flask-parity firmware). Stock firmware answers these
// with an all-0xFF payload (INVALID_COMMAND), which is how the fork probe
// distinguishes the two.
export const GET_POINTER_FX = 26;
export const SET_POINTER_FX = 27;
export const REBOOT = 28;

export const PERSIST_CONFIG_SUCCESS = 1;
export const PERSIST_CONFIG_CONFIG_TOO_BIG = 2;
// Fork: persist refused because the device is in safe mode (recovery boot).
export const PERSIST_CONFIG_SAFE_MODE = 3;

// Field type tags for (de)serializing the 32-byte config packets.
export const UINT8 = Symbol('uint8');
export const UINT16 = Symbol('uint16');
export const UINT32 = Symbol('uint32');
export const INT32 = Symbol('int32');
export const INT16 = Symbol('int16');

function add_crc(dataview) {
    dataview.setUint32(CONFIG_SIZE - 4, crc32(dataview, CONFIG_SIZE - 4), true);
}

function check_crc(data) {
    if (data.getUint32(CONFIG_SIZE - 4, true) != crc32(data, CONFIG_SIZE - 4)) {
        throw new Error('CRC error.');
    }
}

export async function sendFeatureCommand(device, command, fields = [], version = null) {
    const buffer = new ArrayBuffer(CONFIG_SIZE);
    const dataview = new DataView(buffer);
    dataview.setUint8(0, version == null ? activeConfigVersion : version);
    dataview.setUint8(1, command);
    let pos = 2;
    for (const [type, value] of fields) {
        switch (type) {
            case UINT8: dataview.setUint8(pos, value); pos += 1; break;
            case UINT16: dataview.setUint16(pos, value, true); pos += 2; break;
            case UINT32: dataview.setUint32(pos, value, true); pos += 4; break;
            case INT32: dataview.setInt32(pos, value, true); pos += 4; break;
            case INT16: dataview.setInt16(pos, value, true); pos += 2; break;
        }
    }
    add_crc(dataview);
    await device.sendFeatureReport(REPORT_ID_CONFIG, buffer);
}

export async function readConfigFeature(device, fields = []) {
    let attempts_left = 10;
    let delay = 2;
    let data;
    while (true) {
        const data_with_report_id = await device.receiveFeatureReport(REPORT_ID_CONFIG);
        data = new DataView(data_with_report_id.buffer, 1);
        if (data.byteLength > 0) {
            break;
        }
        if ((--attempts_left) > 0) {
            await new Promise((resolve) => setTimeout(resolve, delay));
            delay *= 2;
            continue;
        }
        throw new Error('Error in readConfigFeature (given up retrying).');
    }
    check_crc(data);
    const ret = [];
    let pos = 0;
    for (const type of fields) {
        switch (type) {
            case UINT8: ret.push(data.getUint8(pos)); pos += 1; break;
            case UINT16: ret.push(data.getUint16(pos, true)); pos += 2; break;
            case UINT32: ret.push(data.getUint32(pos, true)); pos += 4; break;
            case INT32: ret.push(data.getInt32(pos, true)); pos += 4; break;
            case INT16: ret.push(data.getInt16(pos, true)); pos += 2; break;
        }
    }
    return ret;
}

// --- Pointer FX (fork firmware only) ----------------------------------------
// Two SET/GET pages mirroring firmware/src/pointer_fx.h's packed struct
// (38 bytes total, static_asserted in firmware/src/config.cc).
// Page 0 (PFX_PAGE0_SIZE = 16): flags u16, accel takeoff/growth u16,
//         offset i16, limit u16, device_cpi u16, smooth factor/timeout u16
// Page 1 (PFX_PAGE1_SIZE = struct - 16, so it GREW as fields were appended):
//         gesture_ratchet u16, wiggle switch/cooldown u16, threshold u8,
//         reserved u8, asc speed/deadzone/range u16, chord step/hold u16
//         (18 bytes, v100), + cursor_gain u16 (20 bytes, v101),
//         + tilt_debounce u16 (22 bytes, sidecar era / fork generation 2).
// Read and write must use the SAME field list for a given firmware: decoding
// one field short silently returns undefined, which the tool then writes back
// as 0 and destroys the device's setting.

export const PFX_FLAG_SMOOTHING = 1 << 0;
export const PFX_FLAG_ACCEL = 1 << 1;
export const PFX_FLAG_WIGGLE = 1 << 2;
export const PFX_FLAG_ASC_INVERTED = 1 << 3;
export const PFX_FLAG_CHORDS = 1 << 4;
export const PFX_FLAG_GESTURES = 1 << 5;
// Master gate (sidecar-era firmware): with this clear the firmware runs the
// exact upstream code path — no divert, no float math. The tool derives it
// automatically (see vial.js) so users never manage it by hand.
export const PFX_FLAG_MASTER = 1 << 15;
// Effect bits that imply the module is in use.
export const PFX_EFFECT_FLAGS =
    PFX_FLAG_SMOOTHING | PFX_FLAG_ACCEL | PFX_FLAG_WIGGLE | PFX_FLAG_CHORDS | PFX_FLAG_GESTURES;

const PFX_PAGE0_FIELDS = [UINT16, UINT16, UINT16, INT16, UINT16, UINT16, UINT16, UINT16];
const PFX_PAGE1_FIELDS = [UINT16, UINT16, UINT16, UINT8, UINT8, UINT16, UINT16, UINT16, UINT16, UINT16];
// v101 appended cursor_gain to page 1; on a v100 device the field is absent.
const PFX_PAGE1_FIELDS_V101 = [...PFX_PAGE1_FIELDS, UINT16];
// Sidecar-era firmware appended tilt_debounce after cursor_gain. Keyed on the
// fork generation, not on the wire version: current fork firmware reports
// stock version 18, and legacy wire-101 firmware has no tilt field at all.
const PFX_PAGE1_FIELDS_GEN2 = [...PFX_PAGE1_FIELDS_V101, UINT16];

// cursor_gain exists on legacy v101 and on every sidecar-era firmware.
function pfxHasCursorGain() {
    return getForkGeneration() >= 2 || getActiveConfigVersion() >= 101;
}

// tilt_debounce only exists on sidecar-era firmware (page 1 = 22 bytes there,
// 20 on legacy v101, 18 on v100).
function pfxHasTiltDebounce() {
    return getForkGeneration() >= 2;
}

function pfxPage1Fields() {
    if (pfxHasTiltDebounce()) return PFX_PAGE1_FIELDS_GEN2;
    return pfxHasCursorGain() ? PFX_PAGE1_FIELDS_V101 : PFX_PAGE1_FIELDS;
}

export async function readPointerFx(device) {
    await sendFeatureCommand(device, GET_POINTER_FX, [[UINT32, 0]]);
    const [flags, accel_takeoff, accel_growth, accel_offset, accel_limit,
        device_cpi, smooth_factor, smooth_timeout] =
        await readConfigFeature(device, PFX_PAGE0_FIELDS);
    await sendFeatureCommand(device, GET_POINTER_FX, [[UINT32, 1]]);
    const [gesture_ratchet, wiggle_switch, wiggle_cooldown, wiggle_threshold, ,
        asc_speed, asc_deadzone, asc_range, chord_step, chord_hold, cursor_gain, tilt_debounce] =
        await readConfigFeature(device, pfxPage1Fields());
    return {
        flags, accel_takeoff, accel_growth, accel_offset, accel_limit,
        device_cpi, smooth_factor, smooth_timeout,
        gesture_ratchet, wiggle_switch, wiggle_cooldown, wiggle_threshold,
        asc_speed, asc_deadzone, asc_range, chord_step, chord_hold,
        cursor_gain: cursor_gain == null ? 1000 : cursor_gain,
        // gen-2 firmware only; older fork firmware leaves it undefined -> 0
        tilt_debounce: tilt_debounce == null ? 0 : tilt_debounce,
    };
}

export async function writePointerFx(device, p) {
    await sendFeatureCommand(device, SET_POINTER_FX, [
        [UINT8, 0],
        [UINT16, p.flags], [UINT16, p.accel_takeoff], [UINT16, p.accel_growth],
        [INT16, p.accel_offset], [UINT16, p.accel_limit], [UINT16, p.device_cpi],
        [UINT16, p.smooth_factor], [UINT16, p.smooth_timeout],
    ]);
    const page1 = [
        [UINT8, 1],
        [UINT16, p.gesture_ratchet], [UINT16, p.wiggle_switch], [UINT16, p.wiggle_cooldown],
        [UINT8, p.wiggle_threshold], [UINT8, 0],
        [UINT16, p.asc_speed], [UINT16, p.asc_deadzone], [UINT16, p.asc_range],
        [UINT16, p.chord_step], [UINT16, p.chord_hold],
    ];
    // Mirrors pfxPage1Fields() exactly — the read/write asymmetry is what hid
    // the missing tilt_debounce decoder.
    if (pfxHasCursorGain()) page1.push([UINT16, p.cursor_gain == null ? 1000 : p.cursor_gain]);
    if (pfxHasTiltDebounce()) page1.push([UINT16, p.tilt_debounce == null ? 0 : p.tilt_debounce]);
    await sendFeatureCommand(device, SET_POINTER_FX, page1);
}

export function defaultPointerFx() {
    // Mirrors the firmware's pfx_set_defaults(): everything OFF, and the
    // accel low-speed floor at 1.00 so switching accel on is an identity
    // until deliberately tuned. (The old force-enabled defaults with a 0.20
    // floor slowed the cursor ~5x out of the box — the prime suspect for
    // the dead-cursor-on-Windows failure.)
    return {
        flags: 0,
        accel_takeoff: 2000, accel_growth: 250, accel_offset: 2200, accel_limit: 1000,
        device_cpi: 1000, smooth_factor: 400, smooth_timeout: 200,
        gesture_ratchet: 200, wiggle_switch: 150, wiggle_cooldown: 250, wiggle_threshold: 3,
        asc_speed: 100, asc_deadzone: 15, asc_range: 300, chord_step: 200, chord_hold: 200,
        cursor_gain: 1000,
        tilt_debounce: 0,
    };
}

// Reads the fork status page (GET_POINTER_FX page 2). On sidecar-era fork
// firmware this carries a 'PFX' signature; on stock firmware the response is
// INVALID_COMMAND's all-0xFF payload, so the signature check cleanly returns
// null. Also used as the capability probe right after version negotiation.
export async function readForkStatus(device) {
    await sendFeatureCommand(device, GET_POINTER_FX, [[UINT32, 2]]);
    const [layerMask, s0, s1, s2, generation, descriptorPending, safeMode, watchdogBoot] =
        await readConfigFeature(device, [UINT8, UINT8, UINT8, UINT8, UINT8, UINT8, UINT8, UINT8]);
    if (s0 != 0x50 || s1 != 0x46 || s2 != 0x58) {  // 'P','F','X'
        return null;
    }
    return { layerMask, generation, descriptorPending: !!descriptorPending, safeMode: !!safeMode,
        // pre-forensics firmware sends 0 here anyway
        watchdogBoot: !!watchdogBoot };
}

// Diagnostics counters (GET_POINTER_FX page 3, sidecar-era firmware).
// The crash record is sticky in the firmware: it survives our own reboots and
// clears only on a power cycle, so it can actually be read after the fact.
// Older firmware sends zeros in the tail fields, which read as "no crash".
export async function readDiagnostics(device) {
    await sendFeatureCommand(device, GET_POINTER_FX, [[UINT32, 3]]);
    const [hidItfCount, tracking, reportsIn, ticks, maxTickUs, umounts, crashCode,
        faultPc, crashFlags, crashCount] =
        await readConfigFeature(device,
            [UINT8, UINT8, UINT32, UINT32, UINT32, UINT32, UINT32, UINT32, UINT8, UINT8]);
    return { hidItfCount, tracking: !!tracking, reportsIn, ticks, maxTickUs, umounts, crashCode,
        faultPc, crashCount,
        hardFault: !!(crashFlags & 0x01),     // faultPc is meaningful
        stackOverflow: !!(crashFlags & 0x02), // faulted at/below the stack bottom
        stickyCrash: !!(crashFlags & 0x04) }; // from an earlier boot this power session
}

// Human-readable crash point. Mirrors the DIAG_BC codes in diagnostics.h.
const CONFIG_COMMAND_NAMES = {
    1: 'RESET_INTO_BOOTSEL', 2: 'SET_CONFIG', 3: 'GET_CONFIG', 4: 'CLEAR_MAPPING',
    5: 'ADD_MAPPING', 6: 'GET_MAPPING', 7: 'PERSIST_CONFIG', 8: 'GET_OUR_USAGES',
    9: 'GET_THEIR_USAGES', 10: 'SUSPEND', 11: 'RESUME', 12: 'PAIR_NEW_DEVICE',
    13: 'CLEAR_BONDS', 14: 'FLASH_B_SIDE', 15: 'CLEAR_MACROS', 16: 'APPEND_TO_MACRO',
    17: 'GET_MACRO', 19: 'CLEAR_EXPRESSIONS', 20: 'APPEND_TO_EXPRESSION',
    21: 'GET_EXPRESSION', 22: 'SET_MONITOR_ENABLED', 23: 'CLEAR_QUIRKS', 24: 'ADD_QUIRK',
    25: 'GET_QUIRK', 26: 'GET_POINTER_FX', 27: 'SET_POINTER_FX', 28: 'REBOOT',
};
const CRASH_PHASES = {
    0x0301: 'building the mapping table', 0x0302: 'just after building the mapping table',
    0x0311: 'erasing/writing flash (save)', 0x0312: 'just after writing flash (save)',
    0x0321: 'parsing our descriptor', 0x0322: 'just after parsing our descriptor',
    0x0331: 'processing the device descriptor', 0x0332: 'just after the device descriptor',
    // Boot path. These mean the SAVED config is what crashed, so it will crash
    // again on the next power-on — the recovery is the BOOTSEL safe-mode
    // gesture (hold BOOTSEL ~2 s after plugging in), not another save.
    0x0341: 'loading the saved config at boot', 0x0342: 'just after loading the saved config',
    0x0351: 'building the mapping table at boot (saved config)',
    0x0352: 'just after building the mapping table at boot',
    0x0361: 'parsing our descriptor at boot (saved config)',
    0x0362: 'just after parsing our descriptor at boot',
};
// True for the boot-path phases above: the persisted config is implicated, so
// the tool can say so instead of suggesting a retry that cannot help.
export const crashIsBootPhase = (code) => code >= 0x0341 && code <= 0x0362;
export function crashPointLabel(code) {
    if (!code) return 'unknown (no breadcrumb)';
    if (CRASH_PHASES[code]) return CRASH_PHASES[code];
    const cmd = CONFIG_COMMAND_NAMES[code & 0xff] || ('command ' + (code & 0xff));
    if ((code & 0xff00) === 0x0100) return 'handling ' + cmd;
    if ((code & 0xff00) === 0x0200) return 'after ' + cmd + ' (idle main loop)';
    return 'unrecognized phase';
}

// Pointer FX usage helpers (hex-string usages, GUI convention).
const pfxHex = (n) => '0x' + ((POINTER_FX_USAGE_PAGE + n) >>> 0).toString(16).padStart(8, '0');
export const pfxGestureSetActiveUsage = (set) => pfxHex(0x01 + set);      // set 0..7, target
export const PFX_AUTOSCROLL_JOG_USAGE = pfxHex(0x09);                     // target
export const PFX_AUTOSCROLL_UP_USAGE = pfxHex(0x0a);                      // target, edge
export const PFX_AUTOSCROLL_DOWN_USAGE = pfxHex(0x0b);                    // target, edge
export const PFX_AUTOSCROLL_STOP_USAGE = pfxHex(0x0c);                    // target, edge
export const pfxGestureFiredUsage = (set, dir) => pfxHex(0x20 + set * 8 + dir);  // source
export const PFX_WIGGLE_FIRED_USAGE = pfxHex(0x70);                       // source
export const pfxChordFiredUsage = (btn, dir) => pfxHex(0x80 + btn * 8 + dir);    // source
// Mouse chords also capture the wheel: w = 0 wheel-up, 1 wheel-down,
// 2 tilt-left, 3 tilt-right (firmware v101+).
export const pfxChordWheelFiredUsage = (btn, w) => pfxHex(0xC0 + btn * 4 + w);   // source

// Direction order used by the firmware (mouse +y = south): index 0..7.
export const PFX_DIRECTIONS = ['E', 'SE', 'S', 'SW', 'W', 'NW', 'N', 'NE'];
export const PFX_WHEEL_DIRS = ['Wheel ↑', 'Wheel ↓', 'Tilt ←', 'Tilt →'];

export function maskToLayerList(layer_mask) {
    const layers = [];
    for (let i = 0; i < NLAYERS; i++) {
        if ((layer_mask & (1 << i)) != 0) {
            layers.push(i);
        }
    }
    return layers;
}

export function layerListToMask(layers) {
    let layer_mask = 0;
    for (const layer of layers) {
        layer_mask |= (1 << layer);
    }
    return layer_mask;
}
