// Keycode picker data and usage-name resolution.
//
// Uses a vendored copy of the stock tool's usage tables (./usages.js) so the
// tool is self-contained, but reorganizes the target usages into categories a Vial
// user expects: Mouse, Keyboard, Media, Layers, Special. "Special" is where the
// engine-level outputs live (Nothing, Registers, Expressions) — these are how
// the advanced behaviors feed their results back into the keymap.

import usages from './usages.js';
import { LAYERS_USAGE_PAGE, MACRO_USAGE_PAGE, REGISTER_USAGE_PAGE, EXPR_USAGE_PAGE, BUTTON_USAGE_PAGE, MIDI_USAGE_PAGE, NLAYERS } from './protocol.js';

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
    return usage;
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
    return usage;
}

export const NOTHING_USAGE = '0x00000000';
