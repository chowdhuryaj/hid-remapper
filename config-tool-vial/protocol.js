// Low-level HID Remapper config protocol.
//
// This is a faithful port of the wire protocol implemented in the stock tool's
// config-tool-web/code.js (send_feature_command / read_config_feature and the
// command constants). It is intentionally UI-agnostic: it knows how to talk to
// a HID Remapper over WebHID feature reports, nothing about the DOM.

import crc32 from './crc.js';

export const REPORT_ID_CONFIG = 100;
export const REPORT_ID_MONITOR = 101;
export const CONFIG_SIZE = 32;
export const CONFIG_VERSION = 18;

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

export const PERSIST_CONFIG_SUCCESS = 1;
export const PERSIST_CONFIG_CONFIG_TOO_BIG = 2;

// Field type tags for (de)serializing the 32-byte config packets.
export const UINT8 = Symbol('uint8');
export const UINT16 = Symbol('uint16');
export const UINT32 = Symbol('uint32');
export const INT32 = Symbol('int32');

function add_crc(dataview) {
    dataview.setUint32(CONFIG_SIZE - 4, crc32(dataview, CONFIG_SIZE - 4), true);
}

function check_crc(data) {
    if (data.getUint32(CONFIG_SIZE - 4, true) != crc32(data, CONFIG_SIZE - 4)) {
        throw new Error('CRC error.');
    }
}

export async function sendFeatureCommand(device, command, fields = [], version = CONFIG_VERSION) {
    const buffer = new ArrayBuffer(CONFIG_SIZE);
    const dataview = new DataView(buffer);
    dataview.setUint8(0, version);
    dataview.setUint8(1, command);
    let pos = 2;
    for (const [type, value] of fields) {
        switch (type) {
            case UINT8: dataview.setUint8(pos, value); pos += 1; break;
            case UINT16: dataview.setUint16(pos, value, true); pos += 2; break;
            case UINT32: dataview.setUint32(pos, value, true); pos += 4; break;
            case INT32: dataview.setInt32(pos, value, true); pos += 4; break;
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
        }
    }
    return ret;
}

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
