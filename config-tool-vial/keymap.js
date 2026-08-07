// Keymap logic: the assignments for one input on one layer, expressed as HID
// Remapper mappings. No DOM — unit-testable.
//
// A given (source, layer) can have several "actions" (mappings), each with its
// own target and sticky/tap/hold flags — this is exactly HID Remapper's model,
// and it's how tap-hold works (one action flagged Tap, another flagged Hold).
// No actions at all = transparent, so the engine's unmapped-passthrough applies.

import { newMapping } from './model.js?v=11';

// Splits any multi-layer mapping into single-layer copies so the editor can
// mutate a mapping in place without touching other layers. Call after loading
// or importing a config.
export function explodeLayers(config) {
    const out = [];
    for (const m of config.mappings) {
        if (!m.layers || m.layers.length <= 1) { out.push(m); continue; }
        for (const l of m.layers) out.push({ ...m, layers: [l] });
    }
    config.mappings = out;
}

// All mappings governing (source, layer), in array order.
export function getActions(config, source, layer) {
    return config.mappings.filter((m) => m.source_usage === source && m.layers.includes(layer));
}

export function addAction(config, source, layer, target = '0x00000000') {
    const m = newMapping(source, target, [layer]);
    config.mappings.push(m);
    return m;
}

export function removeAction(config, mapping) {
    config.mappings = config.mappings.filter((m) => m !== mapping);
}

// Removes every action for (source, layer) — i.e. make it transparent.
export function clearActions(config, source, layer) {
    config.mappings = config.mappings.filter((m) => !(m.source_usage === source && m.layers.includes(layer)));
}
