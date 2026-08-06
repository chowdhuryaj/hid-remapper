// The project model: the tool's source-of-truth document, analogous to Vial's
// .vil file. It holds the base keymap (a plain HID Remapper config with the
// simple per-layer mappings) plus the high-level behaviors that can't be
// reverse-engineered from a compiled device config. Saving to the device
// compiles base + behaviors together (see behaviors.compile).

import { defaultConfig, migrateConfig } from './model.js?v=4';
import { compile } from './behaviors.js?v=4';

export const PROJECT_FORMAT = 1;

export function defaultProject() {
    return {
        format: PROJECT_FORMAT,
        profile: 'elecom_huge_plus',
        os: 'mac',  // project-wide OS for os_shortcut behaviors set to 'inherit'
        ports: {},  // renamable hub-port labels for multi-device setups
        base: defaultConfig(),
        behaviors: [],
    };
}

// Compiles the project into the config that gets written to the device.
export function compileProject(project) {
    return compile(project.base, project.behaviors, project.os);
}

// Recognizes whether an imported JSON is a Vial-tool project (has behaviors) or
// a plain HID Remapper config, and returns a normalized project either way.
export function projectFromJson(json) {
    if (json && typeof json === 'object' && 'base' in json && 'behaviors' in json) {
        const p = defaultProject();
        p.profile = json.profile || p.profile;
        p.os = (json.os === 'pc' || json.os === 'mac') ? json.os : p.os;
        p.ports = (json.ports && typeof json.ports === 'object') ? json.ports : {};
        p.base = migrateConfig(json.base);
        p.behaviors = Array.isArray(json.behaviors) ? json.behaviors : [];
        return p;
    }
    // Plain HID Remapper config: adopt it as the base, no behaviors.
    const p = defaultProject();
    p.base = migrateConfig(json);
    return p;
}

let nextId = 1;
export function newBehaviorId() {
    return 'bh' + (nextId++);
}
