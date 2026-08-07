// A model of how the firmware decides, for one input usage, where that input
// ends up — ported from firmware/src/remapper.cc (set_mapping_from_config's
// mapped_on_layers / unmapped-passthrough source construction, and
// process_mapping's layer_state_mask handling).
//
// The rules that matter, and that no amount of reading the tool's own code will
// tell you:
//   - layer_state_mask is a pure OR of every active layer. There is no layer
//     priority: two active layers both apply.
//   - Layer 0 is active only when nothing else is (remapper.cc: if the computed
//     mask is 0 it is forced to 1).
//   - Unmapped passthrough builds, per usage, a source whose layer_mask is
//     `passthrough_mask & ~mapped_on_layers[usage]` — live on every layer where
//     that usage is NOT explicitly mapped.
//   - suppress_layer_mask (this fork) additionally kills a passthrough source
//     while the usage is mapped on any currently active layer.
//
// Together those produce the non-obvious result this model exists to test: a
// behavior that swallows the cursor on its own layer stops swallowing it the
// moment a second layer is also on, because the passthrough source for the
// cursor is alive on that second layer.

// Which sinks a given source usage reaches, given a set of active layers.
// Returns { targets: [...], passthrough: bool }.
export function resolve(config, sourceUsage, activeLayers, opts = {}) {
    const suppressSupported = opts.suppressLayerMask !== false;
    const src = String(sourceUsage).toLowerCase();
    const passthroughMask = layersToMask(config.unmapped_passthrough_layers || []);

    let mappedOnLayers = 0;
    const targets = [];
    for (const m of config.mappings || []) {
        if (String(m.source_usage).toLowerCase() !== src) continue;
        mappedOnLayers |= layersToMask(m.layers || []);
    }

    const stateMask = activeMask(activeLayers);

    for (const m of config.mappings || []) {
        if (String(m.source_usage).toLowerCase() !== src) continue;
        if (layersToMask(m.layers || []) & stateMask) {
            targets.push(String(m.target_usage).toLowerCase());
        }
    }

    // The unmapped-passthrough source for this usage.
    const ptLayerMask = passthroughMask & ~mappedOnLayers;
    const ptSuppress = suppressSupported ? mappedOnLayers : 0;
    const passthrough = !!(stateMask & ptLayerMask) && !(stateMask & ptSuppress);

    return { targets, passthrough, mappedOnLayers, stateMask };
}

export function layersToMask(layers) {
    let m = 0;
    for (const l of layers) m |= 1 << l;
    return m & 0xff;
}

// remapper.cc: an empty computed layer mask falls back to layer 0.
export function activeMask(activeLayers) {
    const m = layersToMask(activeLayers);
    return m === 0 ? 1 : m;
}

// NOTHING is the tool's "swallow this input" target.
export const NOTHING = '0x00000000';

// True if the cursor still physically moves — i.e. the raw cursor usage reaches
// the host either through an explicit identity mapping or through passthrough.
export function cursorMoves(config, cursorUsage, activeLayers, opts) {
    const r = resolve(config, cursorUsage, activeLayers, opts);
    if (r.passthrough) return true;
    return r.targets.some((t) => t === String(cursorUsage).toLowerCase());
}
