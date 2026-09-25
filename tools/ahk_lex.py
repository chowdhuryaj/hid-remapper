"""Minimal AutoHotkey v2 lexer used by build_lite.py and check_lite.py.

Not a parser. It knows exactly enough of the v2 grammar to answer
"what is code on this line?":

  * block comments -- `/*` must start a line (after whitespace); the comment
    ends on a line that starts or ends with `*/` (v2 rule, including a
    one-line `/* ... */`);
  * line comments  -- `;` at the start of a line or preceded by whitespace,
    outside a string;
  * strings        -- "..." and '...' with backtick escapes, single line.

code_lines(text) returns one entry per source line: the line with comments
removed and every string literal's CONTENT blanked (quotes kept, contents
replaced by `_`), so brace counting and identifier searches see only code.
Problems (unterminated string, unterminated block comment) are collected in
the returned `errors` list as (line_no, message).
"""
import re


def code_lines(text):
    lines = text.split("\n")
    out = []
    errors = []
    in_block = False
    block_start = 0
    for no, raw in enumerate(lines, 1):
        s = raw.rstrip("\r")
        st = s.strip()
        if in_block:
            if st.startswith("*/"):
                in_block = False
                rest = st[2:]
                # code after a leading */ is legal but unusual; lex it
                out.append(_strip_line(rest, no, errors))
                continue
            if st.endswith("*/"):
                in_block = False
            out.append("")
            continue
        if st.startswith("/*"):
            if len(st) > 3 and st.endswith("*/"):
                out.append("")          # one-line block comment
                continue
            in_block = True
            block_start = no
            out.append("")
            continue
        out.append(_strip_line(s, no, errors))
    if in_block:
        errors.append((block_start, "unterminated /* block comment (runs to end of file)"))
    return out, errors


def _strip_line(s, no, errors):
    res = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == ";" and (i == 0 or s[i - 1] in " \t"):
            break
        if c == "`":                       # escaped char outside a string (hotkey `;)
            res.append(s[i:i + 2])
            i += 2
            continue
        if c in "\"'":
            q = c
            j = i + 1
            closed = False
            while j < n:
                if s[j] == "`":
                    j += 2
                    continue
                if s[j] == q:
                    closed = True
                    break
                j += 1
            if not closed:
                # A lone quote inside a hotkey label like  '::  is legal; only
                # report when the line is not a hotkey/hotstring definition.
                if "::" not in s:
                    errors.append((no, "unterminated string literal"))
                res.append(s[i:])
                return "".join(res)
            res.append(q + "~" * (j - i - 1) + q)
            i = j + 1
            continue
        res.append(c)
        i += 1
    return "".join(res).rstrip()


def strings_of(line):
    """String literal contents on one raw line (comments excluded)."""
    found = []
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c == ";" and (i == 0 or line[i - 1] in " \t"):
            break
        if c in "\"'":
            j = i + 1
            while j < n and line[j] != c:
                j += 2 if line[j] == "`" else 1
            found.append(line[i + 1:j])
            i = j + 1
            continue
        i += 1
    return found


IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


# ---------------------------------------------------------------------------
# Top-level units
# ---------------------------------------------------------------------------
CONT_START = re.compile(r"^\s*(\{|\.(?!\d)|,|&&|\|\||\?|:(?!:)|\+|-(?!\d)|\*|/|and\b|or\b|else\b|catch\b|finally\b|until\b)", re.I)
BANNER = re.compile(r"^\s*;\s*(──|══|---|===|\*\*\*)")


def _nest_delta(code):
    return (code.count("{") + code.count("(") + code.count("[")
            - code.count("}") - code.count(")") - code.count("]"))


class Unit:
    __slots__ = ("start", "end", "kind", "name", "params")

    def __init__(self, start, end, kind, name, params=""):
        self.start, self.end, self.kind, self.name, self.params = start, end, kind, name, params

    def __repr__(self):
        return f"Unit({self.kind} {self.name} {self.start + 1}-{self.end + 1})"


def _match_paren(s, i):
    """s[i] == '(' -> index of the matching ')' or -1."""
    d = 0
    for j in range(i, len(s)):
        if s[j] in "([{":
            d += 1
        elif s[j] in ")]}":
            d -= 1
            if d == 0:
                return j
    return -1


def top_units(code):
    """Split code lines (from code_lines) into top-level units.

    A unit is a run of lines that starts at nesting depth 0 and ends when
    (), [] and {} are all closed again and the next code line does not
    continue it. Returns (units, errors)."""
    units = []
    errors = []
    n = len(code)
    i = 0
    while i < n:
        if not code[i].strip():
            i += 1
            continue
        start = i
        depth = 0
        j = i
        while True:
            depth += _nest_delta(code[j])
            if depth < 0:
                errors.append((j + 1, "more closing than opening brackets"))
                depth = 0
            if depth == 0:
                # does the next code line continue this statement?
                k = j + 1
                while k < n and not code[k].strip():
                    k += 1
                if k < n and CONT_START.match(code[k]):
                    j = k
                    continue
                break
            j += 1
            if j >= n:
                errors.append((start + 1, "unit never closes (runs to end of file)"))
                j = n - 1
                break
        units.append(_classify(code, start, j))
        i = j + 1
    return units, errors


def _classify(code, start, end):
    first = code[start]
    m = re.match(r"^class\s+(\w+)", first, re.I)
    if m:
        return Unit(start, end, "class", m.group(1))
    m = re.match(r"^(\w+)\(", first)
    if m:
        joined = "\n".join(code[start:end + 1])
        p = joined.index("(")
        q = _match_paren(joined, p)
        if q > 0:
            rest = joined[q + 1:].lstrip()
            if rest.startswith("{") or rest.startswith("=>"):
                return Unit(start, end, "func", m.group(1), joined[p + 1:q])
    m = re.match(r"^global\s+(\w+)", first, re.I)
    if m:
        return Unit(start, end, "global", m.group(1))
    m = re.match(r"^(\w+)\s*:=", first)
    if m:
        return Unit(start, end, "assign", m.group(1))
    if first.startswith("#"):
        return Unit(start, end, "directive", first.split()[0])
    return Unit(start, end, "stmt", None)


def swallowed_headers(code, units):
    """Column-0 definition headers found INSIDE another unit: the sign of an
    unbalanced brace that made one unit swallow the next."""
    bad = []
    for u in units:
        for k in range(u.start + 1, u.end + 1):
            c = code[k]
            if re.match(r"^(class\s+\w+|\w+\([^)]*\)\s*(\{|=>))", c):
                bad.append((k + 1, f"definition header inside {u.kind} {u.name} "
                                   f"(line {u.start + 1}) -- unbalanced braces?"))
    return bad


# ---------------------------------------------------------------------------
# Name resolution (approximate scope analysis)
# ---------------------------------------------------------------------------
TOKEN = re.compile(r"(?<![\w.$#@])([A-Za-z_]\w*)")
ASSIGN = re.compile(r"(?<![\w.\]\)%])([A-Za-z_]\w*)\s*(?::=|\+=|-=|\*=|/=|//=|\.=|\|=|&=|\^=|>>=|<<=|>>>=|\?\?=)")
BYREF = re.compile(r"(?<![&\w)\]])&(?!&)\s*([A-Za-z_]\w*)")
FORVARS = re.compile(r"^\s*for\s+([\w\s,]+?)\s+in\b", re.I)
CATCHAS = re.compile(r"\bcatch\b[^\n]*?\bas\s+(\w+)", re.I)
DECL = re.compile(r"^\s*(global|local|static)\b\s*(.*)$", re.I)
ARROW_PARAMS = re.compile(r"\(([^()]*)\)\s*=>|(?<![\w.])([A-Za-z_]\w*)\s*=>")
NESTED_FUNC = re.compile(r"^\s*([A-Za-z_]\w*)\(([^()]*)\)\s*(\{|=>)")
MEMBER_DEF = re.compile(r"^\s*(?:static\s+)?([A-Za-z_]\w*)\s*(\(|\[|:=|=>|\{|$)", re.I)


def param_names(params):
    out = set()
    for part in _split_top(params):
        part = part.strip()
        if not part:
            continue
        part = part.split(":=")[0]
        m = re.search(r"([A-Za-z_]\w*)", part)
        if m:
            out.add(m.group(1).lower())
    return out


def _split_top(s):
    parts, d, cur = [], 0, ""
    for ch in s:
        if ch in "([{":
            d += 1
        elif ch in ")]}":
            d -= 1
        if ch == "," and d == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    return parts


def _decl_names(rest):
    names = set()
    for part in _split_top(rest):
        m = re.match(r"\s*([A-Za-z_]\w*)", part)
        if m:
            names.add(m.group(1).lower())
    return names


def unit_scope(code, u):
    """(locals, declared_globals) for a function or class unit."""
    loc, glob = set(), set()
    if u.kind == "func":
        loc |= param_names(u.params)
    if u.kind == "class":
        loc |= {"this", "super", "value", "params", "args", "name"}
    for k in range(u.start, u.end + 1):
        c = code[k]
        m = DECL.match(c)
        if m:
            kw = m.group(1).lower()
            names = _decl_names(m.group(2))
            if kw == "global":
                glob |= names
            else:
                loc |= names
        for m in ASSIGN.finditer(c):
            loc.add(m.group(1).lower())
        for m in BYREF.finditer(c):
            loc.add(m.group(1).lower())
        m = FORVARS.match(c)
        if m:
            loc |= {x.strip().lower() for x in m.group(1).split(",") if x.strip()}
        for m in CATCHAS.finditer(c):
            loc.add(m.group(1).lower())
        for m in ARROW_PARAMS.finditer(c):
            if m.group(1) is not None:
                loc |= param_names(m.group(1))
            else:
                loc.add(m.group(2).lower())
        if u.kind == "class":
            m = re.match(r"^\s*(?:static\s+)?[A-Za-z_]\w*\(([^()]*)\)", c)
            if m:
                loc |= param_names(m.group(1))
        if k > u.start:
            m = NESTED_FUNC.match(c)
            if m and u.kind == "func":
                loc.add(m.group(1).lower())
                loc |= param_names(m.group(2))
    loc -= glob
    return loc, glob


def references(code, u, member_skip=True):
    """Yield (line_no, name, as_call) for identifier references in a unit
    that are not member accesses, object-literal keys or definitions."""
    depth = 0
    for k in range(u.start, u.end + 1):
        c = code[k]
        line = c
        st = line.lstrip()
        if st.startswith("#"):
            if re.match(r"#hotif\b", st, re.I):
                line = st[6:]
            else:
                depth += _nest_delta(c)
                continue
        skip_first = None
        if k == u.start and u.kind in ("func", "class"):
            # the definition's own name (and the class/extends keywords)
            skip_first = u.name.lower()
        if u.kind == "class" and depth == 1 and member_skip:
            m = MEMBER_DEF.match(line)
            if m:
                skip_first = m.group(1).lower()
        m = DECL.match(line)
        if m and m.group(1).lower() in ("global", "local"):
            # a declaration names variables; only initialisers are references
            rest = m.group(2)
            line = " ".join(p.split(":=", 1)[1] if ":=" in p else "" for p in _split_top(rest))
        skipped = False
        for m in TOKEN.finditer(line):
            name = m.group(1)
            low = name.lower()
            if skip_first == low and not skipped:
                skipped = True
                continue
            after = line[m.end():]
            before = line[:m.start()].rstrip()
            if re.match(r"\s*:(?![=:])", after) and (before == "" or before[-1] in "{,"):
                continue                     # object-literal key
            as_call = bool(re.match(r"\(", after))
            yield (k + 1, name, as_call)
        depth += _nest_delta(c)
