// A faithful JS port of the firmware's expression VM (firmware/src/remapper.cc,
// the Op switch in eval_expr) and of its layer / unmapped-passthrough
// resolution (set_mapping_from_config + process_mapping).
//
// Why this exists: the compilers in behaviors.js emit expression strings that
// look plausible and push to the device without error, and the device runs them
// without error — and the behavior still does nothing, because a literal was
// written in the wrong unit. Every value on the expression stack is x1000 fixed
// point; integer literals in the config are RAW on-device values (see expr.js).
// "2 mod" and "2000 mod" are both valid programs and only one of them toggles.
// Nothing short of executing the emitted program catches that class of bug, and
// executing it on the device costs a reflash and a hardware repro.
//
// Ported semantics that matter (all from remapper.cc):
//   input_state_binary / prev_input_state_binary  push 0 or 1000
//   time                                          pushes (ms * 1000) & 0x7fffffff
//   mul                                           (a * b) / 1000
//   mod                                           raw C++ %  (NOT fixed point)
//   eq / gt / not                                 push 0 or 1000
//   store / recall                                register number = value/1000 - 1
//
// This is a model, not the firmware. It is exact for the ops the behavior
// compilers actually emit; ops the compilers never emit throw rather than
// silently returning a wrong answer.

import { exprToElems, ops } from '../expr.js?v=15';

const NREGISTERS = 32;
const OP = Object.fromEntries(Object.entries(ops).map(([k, v]) => [k, v]));
const NAME = Object.fromEntries(Object.entries(ops).map(([k, v]) => [v, k]));

// C++ integer division/modulo truncate toward zero; JS / does not.
const idiv = (a, b) => Math.trunc(a / b);

export class ExprVM {
    constructor() {
        this.registers = new Array(NREGISTERS).fill(0);
        this.state = new Map();      // usage -> raw current value
        this.prevState = new Map();  // usage -> raw value as of the previous tick
        this.nowMs = 0;
        this.layerStateMask = 1;
        this.autoRepeat = false;
    }

    // Inputs are addressed by the same hex-usage strings the compilers emit.
    set(usage, value) { this.state.set(String(usage).toLowerCase(), value); }
    get(usage) { return this.state.get(String(usage).toLowerCase()) || 0; }
    reg(n) { return this.registers[n] || 0; }

    // One engine tick: current state becomes previous state, clock advances.
    // Inputs for the new frame must be applied AFTER this, or the edge
    // detectors (input_state_binary vs prev_input_state_binary) see no edge —
    // the firmware snapshots the previous frame before reading new reports.
    tick(deltaMs = 1) {
        this.prevState = new Map(this.state);
        this.nowMs += deltaMs;
    }

    // The safe way to drive a test: advance one frame, apply this frame's
    // inputs, then run every channel. `inputs` is {usage: rawValue}.
    frame(inputs = {}, expressions = [], deltaMs = 1) {
        this.tick(deltaMs);
        for (const [usage, value] of Object.entries(inputs)) {
            this.set(usage, value);
        }
        return this.evalAll(expressions);
    }

    eval(expr) {
        const elems = exprToElems(expr);
        const st = [];
        const pop = () => {
            if (!st.length) throw new Error('expression underflow in: ' + expr);
            return st.pop();
        };
        for (const [op, val] of elems) {
            switch (op) {
                case OP.PUSH: st.push(val | 0); break;
                case OP.PUSH_USAGE: st.push(val >>> 0); break;
                case OP.INPUT_STATE: {
                    const u = pop();
                    st.push(this.get('0x' + (u >>> 0).toString(16).padStart(8, '0')) * 1000);
                    break;
                }
                case OP.INPUT_STATE_BINARY: {
                    const u = pop();
                    st.push(this.get('0x' + (u >>> 0).toString(16).padStart(8, '0')) ? 1000 : 0);
                    break;
                }
                case OP.PREV_INPUT_STATE_BINARY: {
                    const u = pop();
                    const key = '0x' + (u >>> 0).toString(16).padStart(8, '0');
                    st.push(this.prevState.get(key) ? 1000 : 0);
                    break;
                }
                case OP.PREV_INPUT_STATE: {
                    const u = pop();
                    const key = '0x' + (u >>> 0).toString(16).padStart(8, '0');
                    st.push((this.prevState.get(key) || 0) * 1000);
                    break;
                }
                case OP.ADD: { const b = pop(), a = pop(); st.push(a + b); break; }
                case OP.SUB: { const b = pop(), a = pop(); st.push(a - b); break; }
                case OP.MUL: { const b = pop(), a = pop(); st.push(idiv(a * b, 1000)); break; }
                case OP.DIV: { const b = pop(), a = pop(); st.push(b === 0 ? 0 : idiv(a * 1000, b)); break; }
                case OP.MOD: { const b = pop(), a = pop(); st.push(b === 0 ? 0 : a % b); break; }
                case OP.EQ: { const b = pop(), a = pop(); st.push((a === b) * 1000); break; }
                case OP.GT: { const b = pop(), a = pop(); st.push((a > b) * 1000); break; }
                case OP.LT: { const b = pop(), a = pop(); st.push((a < b) * 1000); break; }
                case OP.NOT: st.push((!pop()) * 1000); break;
                case OP.TIME: st.push((this.nowMs * 1000) & 0x7fffffff); break;
                case OP.DUP: { const a = pop(); st.push(a, a); break; }
                case OP.SWAP: { const b = pop(), a = pop(); st.push(b, a); break; }
                case OP.ABS: st.push(Math.abs(pop())); break;
                case OP.RELU: { const a = pop(); st.push(a < 0 ? 0 : a); break; }
                case OP.SCALING: st.push(1000); break;
                case OP.AUTO_REPEAT: st.push(this.autoRepeat ? 1000 : 0); break;
                case OP.LAYER_STATE: st.push(this.layerStateMask); break;
                case OP.BITWISE_OR: { const b = pop(), a = pop(); st.push(a | b); break; }
                case OP.BITWISE_AND: { const b = pop(), a = pop(); st.push(a & b); break; }
                case OP.BITWISE_NOT: st.push(~pop()); break;
                case OP.CLAMP: { const hi = pop(), lo = pop(); let a = pop();
                    if (a < lo) a = lo; if (a > hi) a = hi; st.push(a); break; }
                case OP.STORE: {
                    const n = idiv(pop(), 1000) - 1;
                    const v = pop();
                    if (n >= 0 && n < NREGISTERS) this.registers[n] = v;
                    break;
                }
                case OP.RECALL: {
                    const n = idiv(pop(), 1000) - 1;
                    st.push(n >= 0 && n < NREGISTERS ? (this.registers[n] || 0) : 0);
                    break;
                }
                case OP.EOL: st.length = 0; break;  // end of line: firmware discards the stack
                default:
                    throw new Error('exprvm does not model op ' + (NAME[op] || op) +
                        ' — port it from remapper.cc before relying on this test');
            }
        }
        return st.length ? st[st.length - 1] : 0;
    }

    // Runs every channel of a compiled config once, in channel order, the way
    // the firmware evaluates expressions each tick.
    evalAll(expressions) {
        const out = [];
        for (let i = 0; i < expressions.length; i++) {
            out[i] = expressions[i] ? this.eval(expressions[i]) : 0;
        }
        return out;
    }
}
