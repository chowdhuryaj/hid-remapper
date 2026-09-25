#!/usr/bin/env python3
"""Portable checks for radmapper/RadMapper-lite.ahk (no AutoHotkey needed).

Not an AutoHotkey parser; it lexes comments and strings away and reasons about
top-level units and identifiers. Checks:

  (a) references -- no executable reference in the lite file to a function,
      class or global that the full file defines and the lite file does not
      (comments and strings stripped, identifiers compared case-insensitively,
      `.member` accesses, object-literal keys and function locals ignored).
      Any other name that resolves to nothing is reported too; "built-in"
      means "used unresolved by the full file's engine code" (MsgBox,
      A_TickCount, ...) plus a short list below.
  (b) balance -- no lexer errors (unterminated string or /* block), every
      top-level unit balanced in (), [] and {} separately, no definition
      header swallowed by an unclosed unit, whole file balanced.
  (c) stubs -- every Atlas./Lumi./Chooser./Warp. member the lite code uses
      is defined on the stub, as the right kind (method vs value); members
      that only the static __Call/__Get catch-all answers are listed.
  (d) entry point -- the last code is `if !IsSet(RM_TEST)` / `Init()`.
  (e) engine intact -- every top-level unit of the full file's engine region
      is in the lite file verbatim, except the ones build_lite.py removes or
      replaces on purpose (listed).
  (f) reachability (information) -- lite functions nothing reaches.

    python3 tools/check_lite.py
"""
import pathlib
import re
import sys

sys.dont_write_bytecode = True               # no tools/__pycache__ litter
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ahk_lex import (code_lines, top_units, swallowed_headers, unit_scope,  # noqa: E402
                     references, _decl_names, _split_top, _match_paren, ASSIGN)

ROOT = HERE.parent
SRC = ROOT / "radmapper" / "RadMapper.ahk"
LITE = ROOT / "radmapper" / "RadMapper-lite.ahk"

STUBS = ["Atlas", "Lumi", "Chooser", "Warp"]
# Built-ins the lite build's own code uses that the full engine never did.
EXTRA_BUILTINS = set()


class Model:
    def __init__(self, text):
        if text.startswith("﻿"):
            text = text[1:]
        self.raw = text.split("\n")
        self.code, self.lex_errors = code_lines(text)
        self.units, self.unit_errors = top_units(self.code)
        self.defs = {}                        # lower name -> unit
        self.globals = set()
        for u in self.units:
            if u.kind in ("func", "class"):
                self.defs.setdefault(u.name.lower(), u)
            elif u.kind == "global":
                body = "\n".join(self.code[u.start:u.end + 1])
                rest = re.match(r"^global\s+(.*)", body, re.S | re.I).group(1)
                self.globals |= _decl_names(rest)
            elif u.kind in ("assign", "stmt"):
                for k in range(u.start, u.end + 1):
                    for m in ASSIGN.finditer(self.code[k]):
                        self.globals.add(m.group(1).lower())
        self.scopes = {}
        for u in self.units:
            if u.kind in ("func", "class"):
                loc, glob = unit_scope(self.code, u)
                self.scopes[id(u)] = loc
                self.globals |= glob
            else:
                self.scopes[id(u)] = set()

    def text_of(self, u):
        return "\n".join(self.raw[u.start:u.end + 1])

    def unresolved(self, units, known):
        """(unit, line, name, as_call) for references to nothing in `known`."""
        out = []
        for u in units:
            loc = self.scopes[id(u)]
            for ln, name, call in references(self.code, u):
                low = name.lower()
                if low in loc or low in known:
                    continue
                out.append((u, ln, name, call))
        return out


def region_bounds(full):
    import build_lite
    rs = [i for i, l in enumerate(full.raw) if l.rstrip() == build_lite.REGION_START]
    re_ = [i for i, l in enumerate(full.raw) if l.startswith(build_lite.REGION_END)]
    if len(rs) != 1 or len(re_) != 1:
        raise SystemExit("check_lite: cannot find the bundled region in RadMapper.ahk")
    return rs[0] - 1, re_[0]


def stub_members(lite, name):
    u = lite.defs.get(name.lower())
    if not u or u.kind != "class":
        return None
    members = {}
    for k in range(u.start + 1, u.end):
        m = re.match(r"^\s*static\s+(\w+)\s*(\(|:=)", lite.code[k])
        if m:
            members[m.group(1).lower()] = "method" if m.group(2) == "(" else "value"
    return members


def param_counts(params):
    """(min, max) arguments for a parameter list; max None = variadic."""
    parts = [p.strip() for p in _split_top(params) if p.strip()]
    lo = hi = 0
    for p in parts:
        if p.endswith("*"):
            return lo, None
        hi += 1
        if ":=" not in p and not p.endswith("?"):
            lo = hi
    return lo, hi


def check_arity(model):
    """AutoHotkey v2 rejects, at load time, a direct call to a known function
    with too few or too many arguments. Check every such call."""
    sig = {n: param_counts(u.params) for n, u in model.defs.items() if u.kind == "func"}
    problems = []
    count = 0
    for u in model.units:
        loc = model.scopes[id(u)]
        joined = "\n".join(model.code[u.start:u.end + 1])
        first = True
        for m in re.finditer(r"(?<![\w.$#@%])([A-Za-z_]\w*)\(", joined):
            low = m.group(1).lower()
            if low not in sig or low in loc:
                continue
            if first and u.kind == "func" and low == u.name.lower() and m.start() == 0:
                first = False                # the definition header itself
                continue
            end = _match_paren(joined, m.end() - 1)
            if end < 0:
                continue
            inner = joined[m.end():end]
            args = [a for a in _split_top(inner)]
            if len(args) == 1 and not args[0].strip():
                args = []
            if any(a.strip().endswith("*") for a in args):
                continue                     # spread call: unknown count
            after = joined[end + 1:].lstrip()
            if after.startswith("{") or after.startswith("=>"):
                continue                     # a nested definition, not a call
            lo, hi = sig[low]
            count += 1
            n = len(args)
            if n < lo or (hi is not None and n > hi):
                line = u.start + joined[:m.start()].count("\n") + 1
                problems.append(f"line {line}: {m.group(1)}() called with {n} argument(s); "
                                f"it takes {lo}-{'any' if hi is None else hi}")
    return problems, count


def main(argv):
    full = Model(SRC.read_text(encoding="utf-8"))
    lite_text = LITE.read_text(encoding="utf-8")
    lite = Model(lite_text)
    problems = []
    info = []

    def bad(section, msg):
        problems.append(f"({section}) {msg}")

    # (b) balance ----------------------------------------------------------
    for n, m in lite.lex_errors:
        bad("b", f"line {n}: {m}")
    for n, m in lite.unit_errors:
        bad("b", f"line {n}: {m}")
    for n, m in swallowed_headers(lite.code, lite.units):
        bad("b", f"line {n}: {m}")
    for u in lite.units:
        seg = "\n".join(lite.code[u.start:u.end + 1])
        for o, c in ("{}", "()", "[]"):
            if seg.count(o) != seg.count(c):
                bad("b", f"{u}: {o}{c} unbalanced ({seg.count(o)} vs {seg.count(c)})")
    whole = "\n".join(lite.code)
    for o, c in ("{}", "()", "[]"):
        if whole.count(o) != whole.count(c):
            bad("b", f"whole file: {o}{c} unbalanced")
    nfunc = sum(1 for u in lite.units if u.kind == "func")
    info.append(f"(b) {len(lite.units)} top-level units ({nfunc} functions) balanced")

    # builtins: what the full file's ENGINE code uses without defining
    rs, re_ = region_bounds(full)
    engine_units = [u for u in full.units if not (rs <= u.start < re_)]
    full_known = set(full.defs) | full.globals
    builtins = {name.lower() for _, _, name, _ in full.unresolved(engine_units, full_known)}
    builtins |= EXTRA_BUILTINS

    # (a) references ---------------------------------------------------------
    lite_known = set(lite.defs) | lite.globals | builtins
    removed = (set(full.defs) | full.globals) - set(lite.defs) - lite.globals
    for u, ln, name, call in lite.unresolved(lite.units, lite_known):
        where = f"line {ln} in {u.kind} {u.name or ''}".rstrip()
        if name.lower() in removed:
            bad("a", f"{where}: reference to removed {'function' if call else 'name'} {name}")
        else:
            bad("a", f"{where}: unknown name {name}")
    # dynamic lookups the name check cannot see
    for i, c in enumerate(lite.code, 1):
        if re.search(r"(?<![.\w])%\w+%\s*\(", c):
            bad("a", f"line {i}: dynamic function call -- verify by hand: {c.strip()}")
    info.append(f"(a) {len(removed)} names the full build defines are absent; "
                f"no live reference to any of them" if not any(p.startswith("(a)") for p in problems)
                else "(a) see problems")

    # (c) stubs ----------------------------------------------------------------
    catch_all = {}
    stub_units = {id(lite.defs[s.lower()]) for s in STUBS if s.lower() in lite.defs}
    for s in STUBS:
        members = stub_members(lite, s)
        if members is None:
            bad("c", f"stub class {s} is missing")
            continue
        for meta in ("__call", "__get"):
            if meta not in members:
                bad("c", f"stub {s} has no static {meta} catch-all")
        pat = re.compile(r"(?<![\w.])" + s + r"\.(%?\w+%?)(\s*\()?", re.I)
        for u in lite.units:
            if id(u) in stub_units:
                continue
            for k in range(u.start, u.end + 1):
                for m in pat.finditer(lite.code[k]):
                    mem = m.group(1)
                    call = bool(m.group(2))
                    if mem.startswith("%"):
                        catch_all.setdefault(s, set()).add(f"{mem} (dynamic, line {k + 1})")
                        continue
                    kind = members.get(mem.lower())
                    if kind is None:
                        catch_all.setdefault(s, set()).add(f"{mem}{'()' if call else ''} (line {k + 1})")
                    elif call and kind != "method":
                        bad("c", f"line {k + 1}: {s}.{mem}() is called but the stub defines a value")
                    elif not call and kind == "method":
                        after = lite.code[k][m.end():]
                        if not re.match(r"\s*:=", after):
                            bad("c", f"line {k + 1}: {s}.{mem} is read as a value but the stub"
                                     " defines a method (it would be a truthy Func)")
        # ObjBindMethod(Stub, "Name") names a method in a string
        for i, raw in enumerate(lite.raw, 1):
            if not lite.code[i - 1].strip():
                continue
            for m in re.finditer(r"ObjBindMethod\(\s*" + s + r'\s*,\s*"(\w+)"', raw, re.I):
                if m.group(1).lower() not in members:
                    catch_all.setdefault(s, set()).add(f"{m.group(1)} via ObjBindMethod (line {i})")
    if catch_all:
        for s, ms in catch_all.items():
            info.append(f"(c) {s}: answered only by the catch-all: {sorted(ms)}")
    else:
        info.append("(c) every stub member the lite code uses is defined explicitly"
                    " (the __Call/__Get catch-alls are a safety net only)")

    # (g) load-time rules AutoHotkey v2 enforces --------------------------
    seen_defs = {}
    for u in lite.units:
        if u.kind in ("func", "class"):
            low = u.name.lower()
            if low in seen_defs:
                bad("g", f"{u.name} defined twice (lines {seen_defs[low] + 1} and {u.start + 1})")
            seen_defs[low] = u.start
    for g in sorted(lite.globals & set(lite.defs)):
        if any(u.kind in ("global", "assign") and (u.name or "").lower() == g for u in lite.units):
            bad("g", f"global variable {g} has the name of a function/class")
    arity_bad, ncalls = check_arity(lite)
    for msg in arity_bad:
        bad("g", msg)
    info.append(f"(g) no duplicate definitions; {ncalls} direct calls to script functions"
                " match the parameter counts")

    # (d) entry point ------------------------------------------------------
    tail = [c.strip() for c in lite.code if c.strip()][-2:]
    if tail != ["if !IsSet(RM_TEST)", "Init()"]:
        bad("d", f"file does not end with the Init() entry point: {tail}")
    else:
        info.append("(d) ends with `if !IsSet(RM_TEST)` / `Init()`")

    # (e) engine intact ------------------------------------------------------
    import build_lite
    intended = {n.lower() for _, n in build_lite.REMOVE_UNITS}
    intended |= {n.lower() for (_, n) in build_lite.REPLACE_UNITS}
    edited = set()
    lite_texts = {}
    for u in lite.units:
        lite_texts.setdefault(lite.text_of(u), u)
    missing = []
    for u in engine_units:
        t = full.text_of(u)
        if t in lite_texts:
            continue
        nm = (u.name or "").lower()
        if nm in intended:
            continue
        if u.kind == "global" and nm == "rm_version":
            edited.add("RM_VERSION")
            continue
        if any(old in t for old, _ in build_lite.TEXT_EDITS):
            edited.add(u.name or f"line {u.start + 1}")
            continue
        if u.kind == "directive":
            continue
        missing.append(u)
    for u in missing:
        bad("e", f"engine unit changed or missing in the lite file: {u}")
    kept = len(engine_units) - len(missing)
    info.append(f"(e) {kept} of {len(engine_units)} engine-region units verbatim or intentionally"
                f" changed; edited in place: {sorted(edited)}; removed/replaced by design:"
                f" {len(intended)}")

    # (f) reachability -------------------------------------------------------
    roots = [u for u in lite.units if u.kind not in ("func", "class")]
    seen = set()
    todo = list(roots)
    if "init" in lite.defs:
        todo.append(lite.defs["init"])
    while todo:
        u = todo.pop()
        if id(u) in seen:
            continue
        seen.add(id(u))
        loc = lite.scopes[id(u)]
        for _, name, _ in references(lite.code, u):
            t = lite.defs.get(name.lower())
            if t is not None and name.lower() not in loc and id(t) not in seen:
                todo.append(t)
    dead = sorted(u.name for u in lite.units if u.kind in ("func", "class") and id(u) not in seen)
    info.append(f"(f) {len(dead)} lite functions/classes nothing reaches (engine helpers the"
                f" GUI used to call; harmless): {', '.join(dead)}")

    lines = lite_text.count("\n")
    print(f"check_lite: {LITE.name}: {lines} lines "
          f"(full build {SRC.read_text(encoding='utf-8').count(chr(10))})")
    for i in info:
        print("check_lite:", i)
    if problems:
        print(f"check_lite: FAIL ({len(problems)} problems)")
        for p in problems:
            print("  ", p)
        return 1
    print("check_lite: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
