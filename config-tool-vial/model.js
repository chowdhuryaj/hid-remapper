// Config data model: the in-memory representation of a HID Remapper config.
//
// This is the same JSON shape the stock tool uses and the same shape exported
// to a hid-remapper-config.json file, so configs are interchangeable between
// the two tools. The Vial-style project file (see project.js, later milestone)
// wraps this with extra high-level metadata (chords, behaviors) that compiles
// down into these mappings/expressions.

import {
    CONFIG_VERSION, NMACROS, NEXPRESSIONS,
    DEFAULT_PARTIAL_SCROLL_TIMEOUT, DEFAULT_TAP_HOLD_THRESHOLD,
    DEFAULT_GPIO_DEBOUNCE_TIME, DEFAULT_MACRO_ENTRY_DURATION, DEFAULT_SCALING,
} from './protocol.js?v=11';

export function emptyMacros() {
    return Array.from({ length: NMACROS }, () => []);
}

export function emptyExpressions() {
    return Array.from({ length: NEXPRESSIONS }, () => '');
}

export function defaultConfig() {
    return {
        'version': CONFIG_VERSION,
        'unmapped_passthrough_layers': [0, 1, 2, 3, 4, 5, 6, 7],
        'partial_scroll_timeout': DEFAULT_PARTIAL_SCROLL_TIMEOUT,
        'tap_hold_threshold': DEFAULT_TAP_HOLD_THRESHOLD,
        'gpio_debounce_time_ms': DEFAULT_GPIO_DEBOUNCE_TIME,
        'interval_override': 0,
        'our_descriptor_number': 0,
        'ignore_auth_dev_inputs': false,
        'macro_entry_duration': DEFAULT_MACRO_ENTRY_DURATION,
        'gpio_output_mode': 0,
        'input_labels': 0,
        'normalize_gamepad_inputs': true,
        'mappings': [],
        'macros': emptyMacros(),
        'expressions': emptyExpressions(),
        'quirks': [],
    };
}

export function newMapping(source_usage = '0x00000000', target_usage = '0x00000000', layers = [0]) {
    return {
        'source_usage': source_usage,
        'target_usage': target_usage,
        'layers': layers.slice(),
        'sticky': false,
        'tap': false,
        'hold': false,
        'scaling': DEFAULT_SCALING,
        'source_port': 0,
        'target_port': 0,
    };
}

// Brings an older config up to the current version, mirroring the migration
// steps in the stock tool's set_ui_state(). Returns the (mutated) config.
export function migrateConfig(config) {
    if (config['version'] == 3) {
        config['unmapped_passthrough_layers'] = config['unmapped_passthrough'] ? [0] : [];
        delete config['unmapped_passthrough'];
        for (const mapping of config['mappings']) {
            mapping['layers'] = [mapping['layer']];
            delete mapping['layer'];
        }
        config['macros'] = [[], [], [], [], [], [], [], []];
    }
    if (config['version'] < 5) {
        for (const mapping of config['mappings']) {
            mapping['tap'] = false;
            mapping['hold'] = false;
        }
        config['tap_hold_threshold'] = DEFAULT_TAP_HOLD_THRESHOLD;
    }
    if (config['version'] < 6) {
        config['expressions'] = emptyExpressions().slice(0, 8);
    }
    if (config['version'] < 7) {
        while (config['macros'].length < NMACROS) {
            config['macros'].push([]);
        }
        config['gpio_debounce_time_ms'] = DEFAULT_GPIO_DEBOUNCE_TIME;
    }
    if (config['version'] < 9) {
        config['our_descriptor_number'] = 0;
        config['ignore_auth_dev_inputs'] = false;
    }
    if (config['version'] < 10) {
        config['macro_entry_duration'] = DEFAULT_MACRO_ENTRY_DURATION;
        config['gpio_output_mode'] = 0;
    }
    if (config['version'] < 11) {
        for (const mapping of config['mappings']) {
            mapping['source_port'] = 0;
            mapping['target_port'] = 0;
        }
    }
    if (config['version'] < 12) {
        config['quirks'] = [];
    }
    if (config['version'] < 16) {
        config['input_labels'] = 0;
    }
    if (config['version'] < 18) {
        // normalize_gamepad_inputs defaults to true for new configs, but to
        // preserve old behavior we set it false when loading a pre-18 config.
        config['normalize_gamepad_inputs'] = false;
    }
    if (config['version'] < CONFIG_VERSION) {
        config['version'] = CONFIG_VERSION;
    }
    return config;
}

export function usageToHex(usage) {
    return '0x' + (usage >>> 0).toString(16).padStart(8, '0');
}

export function usagePage(usage) {
    return ((parseInt(usage, 16) & 0xFFFF0000) >>> 0);
}
