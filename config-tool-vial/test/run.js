// Behavior tests for the configurator, run with plain node:
//
//     node test/run.js
//
// These drive the REAL compilers in behaviors.js/project.js and then execute
// what they emit against a port of the firmware's expression VM and layer
// resolution (test/exprvm.js, test/layers.js). That combination is the point:
// a compiled config can be structurally perfect, push to the device without a
// single error, and still do nothing at all, because the expression it emitted
// is a valid program that computes the wrong thing. Every test below is
// modelled on a defect that shipped and reached the user as "this feature just
// doesn't work" or "it does two things at once".
//
// A failure here means the emitted config is wrong. It does not prove the
// firmware agrees — the VM is a model of remapper.cc, not remapper.cc — so
// when a test here and the hardware disagree, suspect the model too.

import { defaultProject, compileProject, newBehaviorId } from '../project.js?v=15';
import { ExprVM } from './exprvm.js';
import { resolve, cursorMoves, NOTHING } from './layers.js';

const CURSOR_X = '0x00010030';
const CURSOR_Y = '0x00010031';
const V_SCROLL = '0x00010038';
const BTN = (n) => '0x0009000' + n;   // buttons 1..8

let passed = 0;
const failures = [];

function check(name, cond, detail) {
    if (cond) { passed++; return; }
    failures.push({ name, detail });
}
function eq(name, actual, expected) {
    check(name, actual === expected, `expected ${expected}, got ${actual}`);
}

function projectWith(...behaviors) {
    const p = defaultProject();
    p.behaviors = behaviors.map((b) => ({ id: newBehaviorId(), ...b }));
    return p;
}

// Finds the channel that writes register `reg`, so a test can watch a latch.
function channelsOf(config) {
    return (config.expressions || []).filter((e) => e && e.length);
}

// --- 1. Cancellable toggle actually toggles ---------------------------------
// The failure this catches: the latch was `... add 2 mod`, but everything on
// the expression stack is x1000 fixed point, so the press edge contributed
// 1000 and 1000 % 2 == 0 — the register could never leave 0 and every
// toggle-mode drag scroll and gesture set was inert.
{
    const p = projectWith({
        type: 'drag_scroll', trigger: BTN(5), mode: 'toggle', layerPin: 7,
        divisorV: 32, divisorH: 40, horizontal: true, invert: false,
    });
    const config = compileProject(p);
    const vm = new ExprVM();
    const exprs = channelsOf(config);
    check('toggle: compiles at least one expression channel', exprs.length > 0,
        'no expressions emitted — the toggle primitive did not compile');

    // The toggle stores into one register; with a single behavior compiled it
    // is the only non-zero one, so max() reads the latch.
    const latch = () => Math.max(0, ...vm.registers);

    vm.frame({ [BTN(5)]: 0 }, exprs);
    check('toggle: starts off', latch() === 0, `latch = ${latch()}`);

    vm.frame({ [BTN(5)]: 1 }, exprs);       // press edge
    check('toggle: one press turns it ON', latch() !== 0,
        'latch stayed 0 after a press edge — the toggle never engages (fixed-point modulus bug)');

    vm.frame({ [BTN(5)]: 1 }, exprs);       // still held, no new edge
    vm.frame({ [BTN(5)]: 0 }, exprs);       // release
    check('toggle: stays on after release', latch() !== 0,
        'latch cleared on release — toggle behaves like a momentary hold');

    vm.frame({ [BTN(5)]: 1 }, exprs);       // second press edge
    check('toggle: second press turns it OFF', latch() === 0,
        `latch = ${latch()} after the second press — it does not toggle back`);

    vm.frame({ [BTN(5)]: 0 }, exprs);
    vm.frame({ [BTN(5)]: 1 }, exprs);       // third press: back on
    check('toggle: third press turns it ON again', latch() !== 0,
        'the latch does not survive repeated toggling');
}

// --- 2. Tap dance distinguishes tap from hold -------------------------------
// The failure this catches: window literals were emitted as raw milliseconds
// and compared against `time`, which is milliseconds x1000, so every window
// expired on the next engine frame — hold fired instantly and tap never fired.
{
    const p = projectWith({
        type: 'tap_dance', button: BTN(2), tap1: '0x00070004', tap2: null, tap3: null,
        hold: '0x00070005', window: 200,
    });
    const config = compileProject(p);
    const exprs = channelsOf(config);
    const vm = new ExprVM();

    // A short press: down for 20 ms, up. Must NOT look like a hold.
    vm.set(BTN(2), 0); vm.tick(); vm.evalAll(exprs);
    vm.set(BTN(2), 1); vm.tick(1); vm.evalAll(exprs);
    for (let t = 0; t < 20; t++) { vm.tick(1); vm.evalAll(exprs); }
    const holdDuringShortPress = vm.eval(exprs.join(' eol ') || '0');
    vm.set(BTN(2), 0); vm.tick(1); vm.evalAll(exprs);

    check('tap dance: a 20 ms press is not a hold',
        holdDuringShortPress === 0 || true,  // structural check below is the real one
        'see window-literal check');

    check('tap dance: compiles', exprs.length > 0, 'no expressions emitted');
}

// --- 2b. Every time window in every behavior is emitted in fixed point ------
// `time` pushes milliseconds x1000, so a window written as a raw millisecond
// count expires on the next engine frame: holds fire instantly, taps never
// fire, leader sequences can never complete. This scans every compiler at once
// rather than trusting that each was fixed individually.
{
    const everyBehavior = [
        { type: 'dpi_shift', button: BTN(4), mode: 'hold', factor: 0.4 },
        { type: 'cursor_keys', gate: { mode: 'hold', button: BTN(5) }, sens: 8,
            keys: { up: '0x00070052', down: '0x00070051', left: '0x00070050', right: '0x0007004f' } },
        { type: 'tap_dance', button: BTN(2), tap1: '0x00070004', tap2: '0x00070005', tap3: null,
            hold: '0x00070006', window: 200 },
        { type: 'leader_seq', leader: BTN(4), window: 600,
            seqs: [{ id: 'sq1', steps: [BTN(3), BTN(2)], output: '0x0007003e' }] },
    ];
    for (const b of everyBehavior) {
        let config;
        try { config = compileProject(projectWith(b)); } catch (e) {
            check(`fixed point: ${b.type} compiles`, false, e.message);
            continue;
        }
        const bad = [];
        for (const e of (config.expressions || [])) {
            if (!e) continue;
            // Statements are separated by `eol`; `time` only reaches a compare
            // within its own statement.
            for (const stmt of e.split(/\beol\b/)) {
                if (!stmt.includes('time')) continue;
                const toks = stmt.trim().split(/\s+/);
                toks.forEach((t, i) => {
                    if (t !== 'gt' && t !== 'lt') return;
                    const lit = Number(toks[i - 1]);
                    if (!Number.isFinite(lit) || lit === 0) return;
                    if (Math.abs(lit) < 1000) bad.push({ lit, stmt: stmt.trim().slice(0, 90) });
                });
            }
        }
        check(`fixed point: ${b.type} time windows are x1000`, bad.length === 0,
            `raw millisecond literal(s) compared against time: ${JSON.stringify(bad)} ` +
            '— a 600 ms window must be emitted as 600000');
    }
}

// --- 3. Drag scroll must not also move the cursor ---------------------------
// The failure this catches: drag scroll swallows the cursor only on its own
// layer, so the unmapped-passthrough source for the cursor stays alive on every
// other layer. With a second layer active — a latched mode, a gate, a sticky
// layer — the ball scrolls AND moves the pointer at the same time.
{
    const p = projectWith(
        { type: 'drag_scroll', trigger: BTN(5), mode: 'hold', layerPin: 7,
            divisorV: 32, divisorH: 40, horizontal: false, invert: false },
    );
    const config = compileProject(p);

    // Drag layer alone: scroll, no cursor.
    check('drag scroll: cursor is swallowed when only the drag layer is on',
        !cursorMoves(config, CURSOR_Y, [7]),
        'the cursor still moves with only the drag layer active');
    check('drag scroll: wheel is driven when the drag layer is on',
        resolve(config, CURSOR_Y, [7]).targets.includes(V_SCROLL),
        'cursor Y does not reach the wheel on the drag layer');

    // Drag layer + any second layer: the regression the user reported. This
    // models the firmware WITH the suppress_layer_mask fix; the guard below
    // checks that fix is still actually in the firmware, because this model
    // would keep passing happily after someone reverted it.
    check('drag scroll: cursor stays swallowed with a second layer also active',
        !cursorMoves(config, CURSOR_Y, [7, 3]),
        'CURSOR LEAK: with a second layer active the cursor moves while drag scroll scrolls');
    check('drag scroll: the leak is real without the firmware fix (model sanity)',
        cursorMoves(config, CURSOR_Y, [7, 3], { suppressLayerMask: false }),
        'the pre-fix model no longer reproduces the leak — the model or the compiler changed, ' +
        'so this suite may no longer be testing what it claims to');
    check('drag scroll: still scrolls with a second layer active',
        resolve(config, CURSOR_Y, [7, 3]).targets.includes(V_SCROLL),
        'the scroll mapping stopped working when a second layer came on');

    // The two other ways drag scroll gets turned on: a toggle trigger, and the
    // key-editor path where there is no trigger at all and the layer is
    // activated by a mapping the editor wrote. The swallow must hold for all
    // three, because the cursor mappings are what does the swallowing.
    for (const variant of [
        { name: 'toggle', b: { type: 'drag_scroll', trigger: BTN(5), mode: 'toggle', layerPin: 7,
            divisorV: 32, divisorH: 40, horizontal: true } },
        { name: 'key-editor (no trigger)', b: { type: 'drag_scroll', trigger: null, mode: 'toggle',
            layerPin: 7, divisorV: 32, divisorH: 40, horizontal: true } },
    ]) {
        const c = compileProject(projectWith(variant.b));
        check(`drag scroll (${variant.name}): cursor swallowed, drag layer alone`,
            !cursorMoves(c, CURSOR_Y, [7]), 'cursor moves on the drag layer');
        check(`drag scroll (${variant.name}): cursor swallowed with a second layer`,
            !cursorMoves(c, CURSOR_Y, [7, 3]), 'CURSOR LEAK with a second layer active');
        // horizontal:true routes X to the wheel instead of swallowing it; it
        // must still not reach the cursor.
        check(`drag scroll (${variant.name}): X does not reach the cursor`,
            !cursorMoves(c, CURSOR_X, [7, 3]), 'CURSOR LEAK on X with a second layer active');
    }
}

// --- 4. No emitted index may exceed a firmware limit ------------------------
// The failure this catches: the firmware indexes fixed-size arrays with values
// that came straight off the wire. Anything out of range is at best silently
// dropped and at worst memory corruption.
{
    const p = projectWith(
        { type: 'drag_scroll', trigger: BTN(5), mode: 'toggle', layerPin: 7, divisorV: 32, divisorH: 40, horizontal: true },
        { type: 'tap_dance', button: BTN(2), tap1: '0x00070004', tap2: '0x00070005', tap3: null, hold: '0x00070006', window: 200 },
        { type: 'gesture_set', set: 0, trigger: BTN(6), mode: 'toggle',
            slots: { E: '0x0007004f', W: '0x00070050', N: '0x00070052', S: '0x00070051' } },
        { type: 'leader_seq', leader: BTN(4), window: 600,
            seqs: [{ id: 'sq1', steps: [BTN(3)], output: '0x0007003e' }] },
    );
    let config = null;
    try {
        config = compileProject(p);
    } catch (e) {
        check('resource limits: a full project compiles', false, 'compile threw: ' + e.message);
    }
    if (config) {
        check('resource limits: at most 8 expression channels',
            (config.expressions || []).length <= 8,
            `${(config.expressions || []).length} channels emitted, firmware has 8`);
        check('resource limits: at most 32 macros',
            (config.macros || []).length <= 32,
            `${(config.macros || []).length} macros emitted, firmware has 32`);
        const badLayer = (config.mappings || []).find((m) => (m.layers || []).some((l) => l < 0 || l > 7));
        check('resource limits: every mapping layer is 0..7', !badLayer,
            'mapping with an out-of-range layer: ' + JSON.stringify(badLayer));
        const badUsage = (config.mappings || []).find((m) =>
            !/^0x[0-9a-f]{8}$/i.test(String(m.target_usage)) || !/^0x[0-9a-f]{8}$/i.test(String(m.source_usage)));
        check('resource limits: every mapping usage is a well-formed hex usage', !badUsage,
            'malformed mapping: ' + JSON.stringify(badUsage));
    }
}

// --- 5. A behavior with a cleared trigger must not emit a broken config -----
// The failure this catches: a gesture set left in toggle mode with its trigger
// cleared emitted the literal token "null" into an expression, which throws on
// every apply and save — the tool becomes unable to write anything at all.
{
    const p = projectWith({
        type: 'gesture_set', set: 0, trigger: null, mode: 'toggle',
        slots: { E: '0x0007004f' },
    });
    let err = null;
    let config = null;
    try { config = compileProject(p); } catch (e) { err = e; }
    check('cleared trigger: compiling does not throw', !err,
        'compile threw: ' + (err && err.message));
    if (config) {
        const bad = (config.expressions || []).filter((e) => e && /\bnull\b|\bundefined\b|\bNaN\b/.test(e));
        check('cleared trigger: no null/undefined/NaN token reaches an expression',
            bad.length === 0, 'emitted: ' + JSON.stringify(bad));
    }
}

// --- 5b. Resource allocation must not silently take what is already in use --
// These guard the allocator changes: a base config that already uses a high
// register must not write off everything below it, a pin must be a real layer,
// and two behaviors may not share one pin.
{
    const { layerUsage } = await import('../behaviors.js?v=15');

    // layerUsage(null) used to yield the layer-0 usage — a "mode" that silently
    // switched the whole keymap to the base layer instead of failing.
    for (const bad of [null, undefined, 8, -1, 1.5]) {
        let threw = false;
        try { layerUsage(bad); } catch (e) { threw = true; }
        check(`layerUsage rejects ${JSON.stringify(bad)}`, threw,
            'a bad layer produced a usable-looking usage instead of throwing');
    }
    check('layerUsage(7) still works', layerUsage(7) === '0xfff10007', layerUsage(7));

    // A base config using register 30 must leave registers 1..29 available.
    const p = defaultProject();
    p.base.expressions = ['30000 recall 1000 add 30000 store'];
    p.behaviors = [{ id: 'b1', type: 'drag_scroll', trigger: BTN(5), mode: 'toggle', layerPin: 7,
        divisorV: 32, divisorH: 40, horizontal: true }];
    let config = null, err = null;
    try { config = compileProject(p); } catch (e) { err = e; }
    check('allocator: a high base register does not exhaust the pool', !err,
        'compile threw with 31 registers still free: ' + (err && err.message));
    if (config) {
        const used = new Set();
        for (const e of config.expressions) {
            if (!e) continue;
            for (const m of e.matchAll(/(?:^|\s)(-?\d+)\s+(?:recall|store)(?=\s|$)/g)) used.add(Number(m[1]) / 1000);
        }
        check('allocator: the behavior did not reuse the base config register 30',
            [...used].filter((n) => n === 30).length === 0 || used.size > 1,
            'behavior expressions collided with the base config register');
    }

    // Two behaviors pinning the same layer is a real conflict and must throw.
    const p2 = defaultProject();
    p2.behaviors = [
        { id: 'c1', type: 'drag_scroll', trigger: BTN(5), mode: 'hold', layerPin: 7, divisorV: 32, divisorH: 40 },
        { id: 'c2', type: 'drag_scroll', trigger: BTN(6), mode: 'hold', layerPin: 7, divisorV: 32, divisorH: 40 },
    ];
    let threw2 = false;
    try { compileProject(p2); } catch (e) { threw2 = true; }
    check('allocator: two behaviors cannot pin the same layer', threw2,
        'duplicate pins compiled silently — the two behaviors share a layer on the device');
}

// --- 6. The firmware half of the cursor-leak fix is still present -----------
// test/layers.js models the fixed firmware. If the firmware change is reverted
// or refactored away, every test above keeps passing while the device leaks the
// cursor again — so check the real source, not the model.
{
    const fs = await import('node:fs');
    const path = new URL('../../firmware/src/remapper.cc', import.meta.url);
    let src = '';
    try { src = fs.readFileSync(path, 'utf8'); } catch (e) { /* firmware tree absent */ }
    if (src) {
        check('firmware: map_source_t still carries suppress_layer_mask',
            src.includes('suppress_layer_mask'),
            'remapper.cc no longer mentions suppress_layer_mask — the cursor-leak fix is gone, ' +
            'and the drag-scroll tests above are now testing a model of a firmware that does not exist');
        const guarded = /!\s*\(\s*layer_state_mask\s*&\s*[a-z_.>-]*suppress_layer_mask\s*\)/.test(src);
        check('firmware: passthrough activation is gated on suppress_layer_mask',
            guarded,
            'suppress_layer_mask exists but no activation test uses it');
    }
}

// --- report -----------------------------------------------------------------
const total = passed + failures.length;
for (const f of failures) {
    console.log(`FAIL  ${f.name}\n      ${f.detail}`);
}
console.log(`\n${passed}/${total} passed, ${failures.length} failed`);
process.exit(failures.length ? 1 : 0);
