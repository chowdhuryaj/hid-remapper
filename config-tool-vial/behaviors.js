// The behavior compiler: turns high-level, point-and-click behavior definitions
// into ordinary HID Remapper mappings + expressions, so the user never writes
// RPN. Each compiler mirrors a proven example from the stock tool's examples.js.
//
// Resource model: behaviors share 8 expression channels (Expression 1..8 =
// usages 0xFFF3000N), 32 registers (Register 1..32 = usages 0xFFF5000N), and
// the 8 layers. A computed result is stored in a register and surfaced as the
// usage 0xFFF5000N, which a mapping turns into a real keycode — the same
// mechanism the keymap grid uses.
//
// Numeric convention (see EXPRESSIONS.md): on-device values are fixed point
// x1000, so a register *number* N is written `N*1000` as a recall/store operand,
// a value of 1.0 is `1000`, and small raw counters (a glyph index, a chord
// bitmask) are written as-is. regRef() / val() keep this straight.

import { newMapping } from './model.js?v=3';
import {
    pfxGestureSetActiveUsage, pfxGestureFiredUsage, pfxChordFiredUsage,
    pfxChordWheelFiredUsage, PFX_WIGGLE_FIRED_USAGE, PFX_DIRECTIONS,
} from './protocol.js?v=3';

// Slot keys for the wheel/tilt chord directions (index = firmware w).
export const PFX_WHEEL_KEYS = ['WU', 'WD', 'TL', 'TR'];

const ALL_LAYERS = [0, 1, 2, 3, 4, 5, 6, 7];
// Which layers a behavior's outputs/triggers are active on (defaults to all).
const layersOf = (b) => (b.layers && b.layers.length) ? b.layers : ALL_LAYERS;
const CURSOR_X = '0x00010030';
const CURSOR_Y = '0x00010031';
const V_SCROLL = '0x00010038';
const H_SCROLL = '0x000c0238';
const NOTHING = '0x00000000';

const hexUsage = (base, n) => '0x' + (((base + n) >>> 0)).toString(16).padStart(8, '0');
export const layerUsage = (L) => hexUsage(0xFFF10000, L);          // activate layer L
export const exprUsage = (channelIndex) => hexUsage(0xFFF30000, channelIndex + 1); // Expression channelIndex+1
export const registerUsage = (n) => hexUsage(0xFFF50000, n);       // Register n

const regRef = (n) => String(n * 1000);          // operand naming register n
const val = (x) => String(Math.round(x * 1000)); // a fixed-point value

// Allocates the shared engine resources, refusing to overflow them.
function makeAllocator(config) {
    const usedLayers = new Set();
    for (const m of config.mappings) {
        for (const l of m.layers) usedLayers.add(l);
    }
    let nextChannel = 0;
    let nextReg = 1;
    return {
        layer() {
            for (let L = 7; L >= 1; L--) {
                if (!usedLayers.has(L)) { usedLayers.add(L); return L; }
            }
            throw new Error('No free layer available for this behavior.');
        },
        channel() {
            if (nextChannel >= 8) throw new Error('Out of expression channels (max 8).');
            return nextChannel++;
        },
        reg(count = 1) {
            if (nextReg + count - 1 > 32) throw new Error('Out of registers (max 32).');
            const start = nextReg;
            nextReg += count;
            return start;
        },
        // Claims the highest empty macro slot (0-based index), so compiled
        // preset macros stay clear of the user's own low-numbered macros.
        macro() {
            for (let i = 31; i >= 0; i--) {
                if (!config.macros[i] || config.macros[i].length === 0) {
                    config.macros[i] = [];
                    return i;
                }
            }
            throw new Error('Out of macro slots (max 32).');
        },
    };
}

// Compiles a base config (simple keymap + global settings) plus a list of
// behaviors into a single device config. The base config is not mutated.
// projectOs = the project-wide OS ('mac'|'pc') that os_shortcut behaviors
// inherit unless they pin their own.
export function compile(baseConfig, behaviors, projectOs = 'mac') {
    const config = structuredClone(baseConfig);
    config.expressions = (config.expressions || []).slice(0, 8);
    while (config.expressions.length < 8) config.expressions.push('');
    const alloc = makeAllocator(config);
    const ctx = { os: projectOs === 'pc' ? 'pc' : 'mac' };

    for (const b of behaviors || []) {
        if (b.enabled === false) continue;  // per-behavior kill switch
        switch (b.type) {
            case 'dpi_shift': compileDpiShift(b, config, alloc); break;
            case 'cursor_keys': compileCursorKeys(b, config, alloc); break;
            case 'chord_set': compileChordSet(b, config, alloc); break;
            case 'scroll_text': compileScrollText(b, config, alloc); break;
            case 'tap_dance': compileTapDance(b, config, alloc); break;
            case 'drag_scroll': compileDragScroll(b, config, alloc); break;
            case 'gesture_set': compileGestureSet(b, config, alloc); break;
            case 'wheel_chords': compileWheelChords(b, config, alloc); break;
            case 'shake_action': compileShakeAction(b, config, alloc); break;
            case 'os_shortcut': compileOsShortcut(b, config, alloc, ctx); break;
            default: throw new Error('Unknown behavior type: ' + b.type);
        }
    }
    return config;
}

function scaled(source, target, layers, factor) {
    return { ...newMapping(source, target, layers), scaling: Math.max(1, Math.round(factor * 1000)) };
}

// --- DPI shift: hold/sticky a button to change cursor speed -----------------
// Mirrors "middle button cycles DPI": a spare layer carries scaled cursor
// passthrough; the button activates that layer (momentary, or sticky toggle).
function compileDpiShift(b, config, alloc) {
    const L = alloc.layer();
    config.mappings.push({ ...newMapping(b.button, layerUsage(L), layersOf(b)), sticky: b.mode === 'sticky' });
    config.mappings.push(scaled(CURSOR_X, CURSOR_X, [L], b.factor));
    config.mappings.push(scaled(CURSOR_Y, CURSOR_Y, [L], b.factor));
}

// --- Cursor -> arrow keys, proportional to distance -------------------------
// Mirrors "mouse movement to arrow keys...": an accumulator register per axis
// builds up with movement; per-direction channels emit pulses and drain the
// accumulator, so the number of keypresses is proportional to distance.
function posChannelExpr(a, flag) {
    return `${regRef(a)} recall 1000 gt ${regRef(flag)} store ` +
        `${regRef(a)} recall -1000 add 0 1000000 clamp ${regRef(flag)} recall mul ` +
        `${regRef(a)} recall ${regRef(flag)} recall not mul add ${regRef(a)} store ` +
        `time 2000 mod ${regRef(flag)} recall mul`;
}
function negChannelExpr(a, flag) {
    return `${regRef(a)} recall -1000 gt not ${regRef(flag)} store ` +
        `${regRef(a)} recall 1000 add -1000000 0 clamp ${regRef(flag)} recall mul ` +
        `${regRef(a)} recall ${regRef(flag)} recall not mul add ${regRef(a)} store ` +
        `time 2000 mod ${regRef(flag)} recall mul`;
}

function compileCursorKeys(b, config, alloc) {
    const multRaw = Math.max(1, Math.round(b.sens * 12));
    let gate = '';
    if (b.gate.mode === 'hold' || b.gate.mode === 'sticky') {
        const L = alloc.layer();
        config.mappings.push({ ...newMapping(b.gate.button, layerUsage(L), layersOf(b)), sticky: b.gate.mode === 'sticky' });
        // suppress real pointer motion while the gesture is active
        config.mappings.push(newMapping(CURSOR_X, NOTHING, [L]));
        config.mappings.push(newMapping(CURSOR_Y, NOTHING, [L]));
        gate = `layer_state 0x${(1 << L).toString(16)} bitwise_and not not mul `;
    }

    const aX = alloc.reg(), pX = alloc.reg(), nX = alloc.reg();
    const aY = alloc.reg(), pY = alloc.reg(), nY = alloc.reg();

    const accCh = alloc.channel();
    config.expressions[accCh] =
        `${CURSOR_X} input_state ${gate}${multRaw} mul ${regRef(aX)} recall add ${regRef(aX)} store eol ` +
        `${CURSOR_Y} input_state ${gate}${multRaw} mul ${regRef(aY)} recall add ${regRef(aY)} store`;

    const right = alloc.channel(); config.expressions[right] = posChannelExpr(aX, pX);
    const left = alloc.channel(); config.expressions[left] = negChannelExpr(aX, nX);
    const down = alloc.channel(); config.expressions[down] = posChannelExpr(aY, pY);
    const up = alloc.channel(); config.expressions[up] = negChannelExpr(aY, nY);

    config.mappings.push(newMapping(exprUsage(right), b.keys.right, layersOf(b)));
    config.mappings.push(newMapping(exprUsage(left), b.keys.left, layersOf(b)));
    config.mappings.push(newMapping(exprUsage(down), b.keys.down, layersOf(b)));
    config.mappings.push(newMapping(exprUsage(up), b.keys.up, layersOf(b)));
}

// --- Chording: 2-4 buttons pressed together fire one output -----------------
// Mirrors "5-key chording keyboard": one register accumulates a bitmask of the
// member buttons; when the chord is released, the completed mask is pulsed for a
// single frame and matched against each defined chord, whose output register
// drives a mapping.
export function chordMask(members, memberSources) {
    let mask = 0;
    for (const m of members) {
        const i = memberSources.indexOf(m);
        if (i >= 0) mask |= (1 << i);
    }
    return mask;
}

function compileChordSet(b, config, alloc) {
    const members = b.members;
    const regAccum = alloc.reg();
    const regDone = alloc.reg();
    const ch = alloc.channel();

    let e = `${regRef(regAccum)} recall`;
    members.forEach((m, i) => { e += ` ${m} input_state_binary ${1 << i} mul bitwise_or`; });
    e += ` ${regRef(regAccum)} store`;
    e += ' ' + members.map((m, i) => i === 0 ? `${m} prev_input_state_binary` : `${m} prev_input_state_binary bitwise_or`).join(' ');
    e += ' ' + members.map((m, i) => i === 0 ? `${m} input_state_binary` : `${m} input_state_binary bitwise_or`).join(' ');
    e += ' gt';
    e += ` dup ${regRef(regAccum)} recall mul ${regRef(regDone)} store`;
    e += ` not ${regRef(regAccum)} recall mul ${regRef(regAccum)} store`;

    for (const c of b.chords) {
        const mask = chordMask(c.members, members);
        const rOut = alloc.reg();
        e += ` ${regRef(regDone)} recall ${mask} eq ${regRef(rOut)} store`;
        config.mappings.push(newMapping(registerUsage(rOut), c.output, layersOf(b)));
    }
    config.expressions[ch] = e;
}

// --- Scroll-wheel text input ------------------------------------------------
// Scroll cycles a glyph index. Confirm modes:
//   'dwell' (default): the glyph types after a configurable quiet period with
//     no scrolling, or immediately when any device button is pressed;
//   'button': legacy — only an explicit accept button types it.
function compileScrollText(b, config, alloc) {
    const glyphs = b.glyphs;
    const n = glyphs.length;
    const regIdx = alloc.reg();
    const regFire = alloc.reg();

    const idxCh = alloc.channel();
    config.expressions[idxCh] =
        `${regRef(regIdx)} recall ${b.scroll} input_state add ${n} add ${n} mod ${regRef(regIdx)} store`;

    const dispCh = alloc.channel();
    const lines = [];
    if (b.confirm === 'button') {
        lines.push(`${b.accept} input_state_binary ${b.accept} prev_input_state_binary not mul ${regRef(regFire)} store`);
    } else {
        const regT = alloc.reg();
        const regDirty = alloc.reg();
        const timeout = Math.max(50, Math.round(b.timeout || 200));
        const moved = `${b.scroll} input_state abs 0 gt`;
        // T = moved ? now : T  (last scroll activity)
        lines.push(`${moved} dup time mul swap not ${regRef(regT)} recall mul add ${regRef(regT)} store`);
        // dirty = max(dirty, moved)  (a glyph is pending)
        lines.push(`${moved} ${regRef(regDirty)} recall max ${regRef(regDirty)} store`);
        // fire = dirty AND (any-button press edge OR quiet > timeout)
        const btns = (b.confirmButtons || []).slice(0, 8);
        let cond = btns.map((u, i) =>
            `${u} input_state_binary ${u} prev_input_state_binary not mul` + (i > 0 ? ' max' : '')).join(' ');
        cond += (cond ? ' ' : '') + `time ${regRef(regT)} recall sub ${timeout} gt` + (cond ? ' max' : '');
        lines.push(`${cond} ${regRef(regDirty)} recall mul ${regRef(regFire)} store`);
        // consume the pending glyph once fired
        lines.push(`${regRef(regDirty)} recall ${regRef(regFire)} recall not mul ${regRef(regDirty)} store`);
    }
    const outRegs = [];
    for (let i = 0; i < n; i++) {
        const r = alloc.reg();
        outRegs.push(r);
        lines.push(`${regRef(regIdx)} recall ${i} eq ${regRef(regFire)} recall mul ${regRef(r)} store`);
    }
    config.expressions[dispCh] = lines.join(' eol ');
    for (let i = 0; i < n; i++) {
        config.mappings.push(newMapping(registerUsage(outRegs[i]), glyphs[i], layersOf(b)));
    }
}

// --- Drag scroll: toggle/hold a button, ball becomes the scroll wheel -------
// Pure stock primitives — a spare layer carries Cursor X/Y -> H/V scroll
// mappings with fractional scaling (the engine's partial-tick accumulation
// plays the role of Flask's divisor remainders); the trigger activates the
// layer momentarily (hold) or sticky (toggle). Optionally the fork firmware's
// wiggle pulse also toggles the layer — Flask's shake-to-toggle.
function compileDragScroll(b, config, alloc) {
    const L = alloc.layer();
    config.mappings.push({ ...newMapping(b.trigger, layerUsage(L), layersOf(b)), sticky: b.mode === 'sticky' });
    if (b.wiggleToggle) {
        config.mappings.push({ ...newMapping(PFX_WIGGLE_FIRED_USAGE, layerUsage(L), layersOf(b)), sticky: true });
    }
    const sign = b.invert ? 1 : -1;  // default: ball down = scroll down (wheel negative)
    const divV = Math.max(1, b.divisorV || 32);
    const divH = Math.max(1, b.divisorH || 40);
    config.mappings.push({ ...newMapping(CURSOR_Y, V_SCROLL, [L]), scaling: Math.round(sign * 1000 / divV) });
    if (b.horizontal) {
        config.mappings.push({ ...newMapping(CURSOR_X, H_SCROLL, [L]), scaling: Math.round(-sign * 1000 / divH) });
    } else {
        config.mappings.push(newMapping(CURSOR_X, NOTHING, [L]));  // swallow X so the cursor stays put
    }
}

// --- Gesture set: latch a set, flick the ball to fire keys (fork firmware) --
// The heavy lifting (swallow, ratchet, 8-way binning) is the fork firmware's
// pointer_fx module; this compiles to one activation mapping (sticky = toggle,
// like Flask's GR#_TOG) plus one mapping per configured direction pulse.
function compileGestureSet(b, config, alloc) {
    config.mappings.push({ ...newMapping(b.trigger, pfxGestureSetActiveUsage(b.set), layersOf(b)), sticky: b.mode === 'sticky' });
    PFX_DIRECTIONS.forEach((dir, d) => {
        const out = b.slots && b.slots[dir];
        if (out) config.mappings.push(newMapping(pfxGestureFiredUsage(b.set, d), out, layersOf(b)));
    });
}

// --- Mouse chords: hold a physical button + roll ball / turn wheel ----------
// (fork firmware) No trigger mapping needed — the firmware watches the
// physical button and captures motion only when at least one pulse is mapped.
// Ball = 8 ratchet directions; scroll wheel and tilt fire per detent.
function compileWheelChords(b, config, alloc) {
    PFX_DIRECTIONS.forEach((dir, d) => {
        const out = b.slots && b.slots[dir];
        if (out) config.mappings.push(newMapping(pfxChordFiredUsage(b.button, d), out, layersOf(b)));
    });
    PFX_WHEEL_KEYS.forEach((k, w) => {
        const out = b.slots && b.slots[k];
        if (out) config.mappings.push(newMapping(pfxChordWheelFiredUsage(b.button, w), out, layersOf(b)));
    });
}

// --- Shake action: wiggle the ball to fire any output (fork firmware) -------
function compileShakeAction(b, config, alloc) {
    config.mappings.push({ ...newMapping(PFX_WIGGLE_FIRED_USAGE, b.action, layersOf(b)), sticky: !!b.sticky });
}

// --- OS shortcut presets (Flask os_shortcuts / select_word equivalents) -----
// Pure stock primitives: each preset fills a high macro slot with the right
// modifier chords for the chosen OS, and maps the trigger to that macro.
// Works on stock firmware; nothing OS-detection based (pick Mac or PC here).
const KEY = (code) => '0x000700' + code.toString(16).padStart(2, '0');
const LCTL = KEY(0xe0), LSFT = KEY(0xe1), LALT = KEY(0xe2), LGUI = KEY(0xe3);
const OS_SHORTCUTS = {
    cut: { label: 'Cut', mac: [[LGUI, KEY(0x1b)]], pc: [[LCTL, KEY(0x1b)]] },
    copy: { label: 'Copy', mac: [[LGUI, KEY(0x06)]], pc: [[LCTL, KEY(0x06)]] },
    paste: { label: 'Paste', mac: [[LGUI, KEY(0x19)]], pc: [[LCTL, KEY(0x19)]] },
    undo: { label: 'Undo', mac: [[LGUI, KEY(0x1d)]], pc: [[LCTL, KEY(0x1d)]] },
    redo: { label: 'Redo', mac: [[LSFT, LGUI, KEY(0x1d)]], pc: [[LCTL, KEY(0x1c)]] },
    select_all: { label: 'Select all', mac: [[LGUI, KEY(0x04)]], pc: [[LCTL, KEY(0x04)]] },
    app_switch: { label: 'App switcher', mac: [[LGUI, KEY(0x2b)]], pc: [[LALT, KEY(0x2b)]] },
    new_tab: { label: 'New tab', mac: [[LGUI, KEY(0x17)]], pc: [[LCTL, KEY(0x17)]] },
    close: { label: 'Close window/tab', mac: [[LGUI, KEY(0x1a)]], pc: [[LCTL, KEY(0x1a)]] },
    select_word: {
        label: 'Select word',
        mac: [[LALT, KEY(0x50)], [LALT, LSFT, KEY(0x4f)]],   // ⌥← then ⌥⇧→
        pc: [[LCTL, KEY(0x50)], [LCTL, LSFT, KEY(0x4f)]],    // ^← then ^⇧→
    },
    select_line: {
        label: 'Select line',
        mac: [[LGUI, KEY(0x50)], [LGUI, LSFT, KEY(0x4f)]],   // ⌘← then ⌘⇧→
        pc: [[KEY(0x4a)], [LSFT, KEY(0x4d)]],                // Home then ⇧End
    },
};
export const OS_SHORTCUT_CHOICES = Object.entries(OS_SHORTCUTS).map(([k, v]) => [k, v.label]);

function compileOsShortcut(b, config, alloc, ctx) {
    const def = OS_SHORTCUTS[b.action];
    if (!def) throw new Error('Unknown OS shortcut: ' + b.action);
    // 'inherit' (or anything unrecognized) follows the project-wide OS.
    const os = (b.os === 'pc' || b.os === 'mac') ? b.os : (ctx ? ctx.os : 'mac');
    const slot = alloc.macro();
    config.macros[slot] = def[os].map((step) => [...step]);
    config.mappings.push(newMapping(b.trigger, hexUsage(0xFFF20000, slot + 1), layersOf(b)));
}

// --- Tap dance: 1 / 2 / 3 taps + hold on one button -------------------------
// HID Remapper has native tap and hold flags, but only one of each. Multi-tap
// needs a small state machine: count press edges, and after a quiet "window"
// fire the action for the final count (or the hold action if the button is held
// past the window). The button's native output is suppressed — tap dance takes
// it over. One expression channel; the fire registers pulse for one frame each.
function compileTapDance(b, config, alloc) {
    const btn = b.button;
    const win = Math.max(50, Math.round(b.window || 200)); // raw ms
    const r = regRef;
    const PE = alloc.reg(), C = alloc.reg(), T = alloc.reg(), HOLD = alloc.reg(), TAP = alloc.reg();
    const F1 = alloc.reg(), F2 = alloc.reg(), F3 = alloc.reg();
    const ch = alloc.channel();

    config.expressions[ch] = [
        // press edge -> PE
        `${btn} input_state_binary ${btn} prev_input_state_binary not mul ${r(PE)} store`,
        // count += press edge
        `${r(C)} recall ${r(PE)} recall add ${r(C)} store`,
        // remember time of last press: T = PE ? time : T
        `${r(PE)} recall time mul ${r(PE)} recall not ${r(T)} recall mul add ${r(T)} store`,
        // hold active = held AND (now - T) > window
        `${btn} input_state_binary time ${r(T)} recall sub ${win} gt mul ${r(HOLD)} store`,
        // holding consumes the tap count so a tap doesn't also fire on release
        `${r(C)} recall ${r(HOLD)} recall not mul ${r(C)} store`,
        // tap fire = released AND count>=1 AND quiet for > window
        `${btn} input_state_binary not ${r(C)} recall 0 gt mul time ${r(T)} recall sub ${win} gt mul ${r(TAP)} store`,
        // dispatch by count
        `${r(TAP)} recall ${r(C)} recall 1 eq mul ${r(F1)} store`,
        `${r(TAP)} recall ${r(C)} recall 2 eq mul ${r(F2)} store`,
        `${r(TAP)} recall ${r(C)} recall 2 gt mul ${r(F3)} store`,
        // clear count once a tap has fired
        `${r(C)} recall ${r(TAP)} recall not mul ${r(C)} store`,
    ].join(' eol ');

    config.mappings.push(newMapping(btn, NOTHING, layersOf(b))); // suppress native button
    if (b.tap1) config.mappings.push(newMapping(registerUsage(F1), b.tap1, layersOf(b)));
    if (b.tap2) config.mappings.push(newMapping(registerUsage(F2), b.tap2, layersOf(b)));
    if (b.tap3) config.mappings.push(newMapping(registerUsage(F3), b.tap3, layersOf(b)));
    if (b.hold) config.mappings.push(newMapping(registerUsage(HOLD), b.hold, layersOf(b)));
}

export { val };
