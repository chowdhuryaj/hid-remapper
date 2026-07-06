// Keycode picker data and usage-name resolution.
//
// Uses a vendored copy of the stock tool's usage tables (./usages.js) so the
// tool is self-contained, but reorganizes the target usages into categories a Vial
// user expects: Mouse, Keyboard, Media, Layers, Special. "Special" is where the
// engine-level outputs live (Nothing, Registers, Expressions) — these are how
// the advanced behaviors feed their results back into the keymap.

import usages from './usages.js?v=3';
import {
    LAYERS_USAGE_PAGE, MACRO_USAGE_PAGE, REGISTER_USAGE_PAGE, EXPR_USAGE_PAGE,
    BUTTON_USAGE_PAGE, MIDI_USAGE_PAGE, POINTER_FX_USAGE_PAGE, NLAYERS,
    pfxGestureSetActiveUsage, pfxGestureFiredUsage, pfxChordFiredUsage,
    PFX_AUTOSCROLL_JOG_USAGE, PFX_AUTOSCROLL_UP_USAGE, PFX_AUTOSCROLL_DOWN_USAGE,
    PFX_AUTOSCROLL_STOP_USAGE, PFX_WIGGLE_FIRED_USAGE, PFX_DIRECTIONS,
} from './protocol.js?v=3';

export const NMACROS_ASSIGNABLE = 32;
const hexUsage = (base, n) => '0x' + ((base + n) >>> 0).toString(16).padStart(8, '0');
export const macroUsage = (n) => hexUsage(MACRO_USAGE_PAGE, n);

const CLASS_ORDER = ['mouse', 'keyboard', 'media'];
const CLASS_LABEL = { mouse: 'Mouse', keyboard: 'Keyboard', media: 'Media' };

// Returns ordered categories of assignable target keycodes for a given output
// descriptor (0 = the default mouse+keyboard composite the converter uses).
export function targetCategories(descriptorNumber = 0) {
    const table = usages[descriptorNumber] || usages[0];
    const cats = [];

    for (const cls of CLASS_ORDER) {
        const items = Object.entries(table)
            .filter(([, def]) => def.class === cls)
            .map(([usage, def]) => ({ usage, label: def.name }));
        if (items.length) {
            cats.push({ name: CLASS_LABEL[cls], items });
        }
    }

    const layers = [];
    for (let i = 1; i < NLAYERS; i++) {
        layers.push({ usage: '0xfff1000' + i, label: 'Layer ' + i });
    }
    cats.push({ name: 'Layers', items: layers });

    const macros = [];
    for (let i = 1; i <= NMACROS_ASSIGNABLE; i++) {
        macros.push({ usage: macroUsage(i), label: 'Macro ' + i });
    }
    cats.push({ name: 'Macros', items: macros });

    const special = [];
    if ('0x00000000' in table) {
        special.push({ usage: '0x00000000', label: 'Nothing' });
    }
    for (const [usage, def] of Object.entries(table)) {
        if (def.class === 'other' && (usage.startsWith('0xfff5') || usage.startsWith('0xfff3'))) {
            special.push({ usage, label: def.name });
        }
    }
    cats.push({ name: 'Special', items: special });

    // Pointer FX activation targets (Flask-parity fork firmware only; inert
    // on stock firmware). Sticky mapping to a "Gesture set active" toggles
    // the set exactly like Flask's GR#_TOG keycodes.
    const pfx = [];
    for (let s = 0; s < 8; s++) {
        pfx.push({ usage: pfxGestureSetActiveUsage(s), label: 'Gesture set ' + (s + 1) + ' active' });
    }
    pfx.push({ usage: PFX_AUTOSCROLL_JOG_USAGE, label: 'Autoscroll jog' });
    pfx.push({ usage: PFX_AUTOSCROLL_UP_USAGE, label: 'Autoscroll speed +' });
    pfx.push({ usage: PFX_AUTOSCROLL_DOWN_USAGE, label: 'Autoscroll speed −' });
    pfx.push({ usage: PFX_AUTOSCROLL_STOP_USAGE, label: 'Autoscroll stop' });
    cats.push({ name: 'Pointer FX', items: pfx });

    return cats;
}

// Ordered categories of assignable *source* usages (inputs) for behavior
// triggers: the device's own buttons and axes, keyboard keys, and whatever a
// connected device actually reports (extraSource, from GET_THEIR_USAGES).
export function sourceCategories(profile, extraSource = []) {
    const cats = [];
    cats.push({ name: 'Buttons', items: profile.buttons.map((b) => ({ usage: b.source, label: b.label })) });

    const pointer = [];
    for (const a of profile.axes || []) {
        if (a.kind === 'cursor' && a.dirs) {
            for (const d of a.dirs) pointer.push({ usage: d.axis, label: d.label });
        } else if (a.axis) {
            pointer.push({ usage: a.axis, label: a.label });
        }
    }
    if (pointer.length) cats.push({ name: 'Pointer', items: pointer });

    const kb = Object.entries(usages['source'] || {})
        .filter(([, d]) => d.class === 'keyboard')
        .map(([u, d]) => ({ usage: u, label: d.name }));
    if (kb.length) cats.push({ name: 'Keyboard', items: kb });

    const known = new Set([...profile.buttons.map((b) => b.source), ...pointer.map((p) => p.usage)]);
    const detected = (extraSource || []).filter((u) => !known.has(u)).map((u) => ({ usage: u, label: readableSourceName(u) }));
    if (detected.length) cats.push({ name: 'Detected', items: detected });

    // Pointer FX fired pulses (fork firmware): map these like buttons — to
    // keys, macros, or sticky layer toggles (e.g. wiggle → scroll layer).
    const pfx = [{ usage: PFX_WIGGLE_FIRED_USAGE, label: 'Wiggle triggered' }];
    for (let s = 0; s < 8; s++) {
        for (let d = 0; d < 8; d++) {
            pfx.push({ usage: pfxGestureFiredUsage(s, d), label: 'Gesture ' + (s + 1) + ' fired ' + PFX_DIRECTIONS[d] });
        }
    }
    for (let b = 0; b < 8; b++) {
        for (let d = 0; d < 8; d++) {
            pfx.push({ usage: pfxChordFiredUsage(b, d), label: 'Chord B' + (b + 1) + ' fired ' + PFX_DIRECTIONS[d] });
        }
    }
    cats.push({ name: 'Pointer FX', items: pfx });

    return cats;
}

function pageOf(usage) {
    return ((parseInt(usage, 16) & 0xFFFF0000) >>> 0);
}

// Human-readable name for a target usage (what a key is mapped to).
export function readableTargetName(usage, descriptorNumber = 0) {
    const table = usages[descriptorNumber] || usages[0];
    if (usage in table) {
        return table[usage].name;
    }
    if (pageOf(usage) === LAYERS_USAGE_PAGE) {
        return 'Layer ' + (parseInt(usage, 16) & 0xFFFF);
    }
    if (pageOf(usage) === MACRO_USAGE_PAGE) {
        return 'Macro ' + (parseInt(usage, 16) & 0xFFFF);
    }
    if (pageOf(usage) === REGISTER_USAGE_PAGE) {
        return 'Register ' + (parseInt(usage, 16) & 0xFFFF);
    }
    if (pageOf(usage) === EXPR_USAGE_PAGE) {
        return 'Expression ' + (parseInt(usage, 16) & 0xFFFF);
    }
    if (pageOf(usage) === POINTER_FX_USAGE_PAGE) {
        return pfxName(usage);
    }
    return usage;
}

// Names for the Pointer FX usage page, both directions.
function pfxName(usage) {
    const n = parseInt(usage, 16) & 0xFFFF;
    if (n >= 0x01 && n <= 0x08) return 'Gesture set ' + n + ' active';
    if (n === 0x09) return 'Autoscroll jog';
    if (n === 0x0a) return 'Autoscroll speed +';
    if (n === 0x0b) return 'Autoscroll speed −';
    if (n === 0x0c) return 'Autoscroll stop';
    if (n >= 0x20 && n < 0x60) {
        const i = n - 0x20;
        return 'Gesture ' + (Math.floor(i / 8) + 1) + ' fired ' + PFX_DIRECTIONS[i % 8];
    }
    if (n === 0x70) return 'Wiggle triggered';
    if (n >= 0x80 && n < 0xC0) {
        const i = n - 0x80;
        return 'Chord B' + (Math.floor(i / 8) + 1) + ' fired ' + PFX_DIRECTIONS[i % 8];
    }
    return 'Pointer FX ' + n;
}

// Human-readable name for a source usage (an input from the upstream device).
export function readableSourceName(usage, inputLabels = 0) {
    const src0 = usages['source_' + inputLabels] || usages['source_0'];
    if (usage in src0) return src0[usage].name;
    if (usage in usages['source']) return usages['source'][usage].name;
    if (usage in usages['source_extra']) return usages['source_extra'][usage].name;
    if (pageOf(usage) === BUTTON_USAGE_PAGE) return 'Button ' + (parseInt(usage, 16) & 0xFFFF);
    if (pageOf(usage) === REGISTER_USAGE_PAGE) return 'Register ' + (parseInt(usage, 16) & 0xFFFF);
    if (pageOf(usage) === MIDI_USAGE_PAGE) return 'MIDI ' + usage;
    if (pageOf(usage) === POINTER_FX_USAGE_PAGE) return pfxName(usage);
    return usage;
}

export const NOTHING_USAGE = '0x00000000';
