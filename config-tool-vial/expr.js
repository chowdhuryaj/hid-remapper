// Expression (RPN) opcodes and serialization.
//
// Expressions are stored in the config as a single space-separated string in
// "json form": integer literals are the raw on-device values (the x1000 fixed
// point is just how the stock UI presents them), hex literals are usage codes,
// everything else is a lowercase opcode name. Comments (/* ... */) are allowed
// and preserved in exported JSON but dropped when serialized to the device.
//
// The behavior compiler (behaviors.js) emits strings in exactly this form, so
// the same encoder feeds both hand-written and generated expressions.

export const ops = {
    "PUSH": 0, "PUSH_USAGE": 1, "INPUT_STATE": 2, "ADD": 3, "MUL": 4, "EQ": 5,
    "TIME": 6, "MOD": 7, "GT": 8, "NOT": 9, "INPUT_STATE_BINARY": 10, "ABS": 11,
    "DUP": 12, "SIN": 13, "COS": 14, "DEBUG": 15, "AUTO_REPEAT": 16, "RELU": 17,
    "CLAMP": 18, "SCALING": 19, "LAYER_STATE": 20, "STICKY_STATE": 21,
    "TAP_STATE": 22, "HOLD_STATE": 23, "BITWISE_OR": 24, "BITWISE_AND": 25,
    "BITWISE_NOT": 26, "PREV_INPUT_STATE": 27, "PREV_INPUT_STATE_BINARY": 28,
    "STORE": 29, "RECALL": 30, "SQRT": 31, "ATAN2": 32, "ROUND": 33, "PORT": 34,
    "DPAD": 35, "EOL": 36, "INPUT_STATE_FP32": 37, "PREV_INPUT_STATE_FP32": 38,
    "MIN": 39, "MAX": 40, "IFTE": 41, "DIV": 42, "SWAP": 43, "MONITOR": 44,
    "SIGN": 45, "SUB": 46, "PRINT_IF": 47, "TIME_SEC": 48, "LT": 49,
    "PLUGGED_IN": 50, "INPUT_STATE_SCALED": 51, "PREV_INPUT_STATE_SCALED": 52,
    "DEADZONE": 53, "DEADZONE2": 54,
};

export const opcodes = Object.fromEntries(
    Object.entries(ops).map(([key, value]) => [value, key]));

export const OP_PUSH = ops['PUSH'];
export const OP_PUSH_USAGE = ops['PUSH_USAGE'];

// Splits the string into (comment, code) pairs so comments can be skipped.
export const EXPR_RE = /((?:\/\*.*?\*\/)?)((?:(?!\/\*).)*)/gs;

// Converts a json-form expression string into a list of elements, where each
// element is [op] or [PUSH|PUSH_USAGE, value]. Throws on an unknown token.
export function exprToElems(expr) {
    const convert_elem = function (elem) {
        if (elem.toLowerCase().startsWith('0x')) {
            return [OP_PUSH_USAGE, parseInt(elem, 16)];
        }
        if (/^[0-9-]/.test(elem)) {
            return [OP_PUSH, parseInt(elem, 10)];
        }
        if (elem.toUpperCase() in ops) {
            return [ops[elem.toUpperCase()]];
        }
        throw new Error('Invalid expression token: "' + elem + '"');
    };

    return [...expr.matchAll(EXPR_RE)].map((x) => x[2]).join('')
        .split(/\s+/)
        .filter((x) => x.length > 0)
        .map(convert_elem);
}

// Turns a single decoded element back into its json-form token (used when
// reading expressions back from the device).
export function elemToToken(elem, val) {
    if (elem === OP_PUSH) {
        return val.toString();
    }
    if (elem === OP_PUSH_USAGE) {
        return '0x' + (val >>> 0).toString(16).padStart(8, '0');
    }
    return opcodes[elem].toLowerCase();
}
