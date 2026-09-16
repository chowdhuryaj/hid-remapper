"""Portable structural checks; not an AutoHotkey parser or runtime test."""
from pathlib import Path
from collections import Counter
import re
s = (Path(__file__).parents[1] / 'RadMapper.ahk').read_text(encoding='utf-8-sig')
# CASE-INSENSITIVE MEMBER COLLISIONS, for every top-level class the script
# itself declares (everything before the vendored `class GpGFX {`). AHK
# property names are case-INSENSITIVE, so `static grab := false` and
# `static Grab()` in one class are the SAME member: the second declaration
# wins at load time and the script dies with a duplicate-declaration error
# before a single hotkey is registered. Nothing about the collision is
# visible by reading either line on its own, which is why it is checked here
# rather than trusted to review. Class bodies are found by BRACE DEPTH, with
# comments and string literals stripped first so a `{` inside either cannot
# close a class early. GpGFX and its own classes are vendored verbatim and
# are deliberately out of scope.
def strip_ahk(text):
    """Blank out comments and string literals, keeping every offset.

    Block comments come FIRST: `/** ... */` headers are full of apostrophes
    and braces, and a scanner that reads them as code loses track of both.
    """
    out = []
    quote = ''      # the closing character of the literal we are inside
    block = False   # inside a /* ... */ comment
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if block:
            if text.startswith('*/', i):
                block = False
                out.append('  ')
                i += 2
                continue
            out.append(c if c == '\n' else ' ')
            i += 1
            continue
        if quote:
            out.append(' ' if c != '\n' else c)
            if c == '`':                 # AHK escapes the next character
                out.append(' ' if i + 1 < n and text[i+1] != '\n' else '\n')
                i += 2
                continue
            if c == quote:
                quote = ''
            i += 1
            continue
        if text.startswith('/*', i) and (not out or out[-1] in ' \t\n'):
            block = True
            out.append('  ')
            i += 2
            continue
        if c in '"\'':
            quote = c
            out.append(' ')
            i += 1
            continue
        if c == ';' and (not out or out[-1] in ' \t\n'):
            while i < n and text[i] != '\n':
                out.append(' ')
                i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)

_bare = strip_ahk(s)
_limit = s.index('class GpGFX {')
for _m in re.finditer(r'^class (\w+)[^\n{]*\{', s, re.M):
    if _m.start() >= _limit:
        break
    name = _m.group(1)
    depth, j = 0, _m.end() - 1
    while j < _limit:
        if _bare[j] == '{':
            depth += 1
        elif _bare[j] == '}':
            depth -= 1
            if depth == 0:
                break
        j += 1
    assert depth == 0, ('Unbalanced class body', name)
    part = s[_m.start():j + 1]
    members = re.findall(r'^    static (\w+)\s*(?:\(|:=)', part, re.M)
    dupes = [n for n, count in Counter(m.lower() for m in members).items() if count > 1]
    assert not dupes, ('Case-insensitive member collision', name, dupes)
# The two UI classes are also checked the other way round: every Lumi.X() /
# Atlas.X() the script calls has to BE one of those members.
for name, end in [('Lumi', 'Atlas'), ('Atlas', 'Calib')]:
    part = s[s.index('class ' + name + ' {'):s.index('class ' + end + ' {')]
    members = re.findall(r'^    static (\w+)\s*(?:\(|:=)', part, re.M)
    calls = set(re.findall(r'\b' + name + r'\.(\w+)\(', s[:_limit]))
    assert calls <= set(members), (name, calls - set(members))
# TIMER IDENTITY. SetTimer keys on the function OBJECT, so a fresh
# ObjBindMethod for the same method is a DIFFERENT timer: it cannot be
# cancelled by a later SetTimer(fn, 0) and two of them run side by side.
# Every repeating/cancellable bound-method timer keeps its BoundFunc in a
# static (Atlas.menuTryFn, Atlas.wizReopenFn, Warp.idleFn,
# Warp.redrawFn).
for bad in ['SetTimer(ObjBindMethod(Atlas, "MenuTryDone")',
            'SetTimer(ObjBindMethod(Warp, "IdleClose")',
            'SetTimer(ObjBindMethod(Warp, "DrawFine")',
            'SetTimer(ObjBindMethod(Atlas, "WizReopenDue")']:
    assert bad not in s, 'Timer must reuse its function object: ' + bad
assert 'static redrawFn := 0' in s, 'Warp.redrawFn static is missing'
assert 'static wizReopenFn := 0' in s, 'Atlas.wizReopenFn static is missing'

# WINDOWS PAGE FIT at the 940 px minimum width. The content column is
#   pw = 940 - NAVW(188) - SP["xl"](24) - SP["xl"](24) = 704
# and a stacked HkRow is cw (220) wide from its own x, so the furthest
# offset a HkRow may be given there is 704 - 220 - 24 of slack = 460.
_win = s[s.index('static PanelWindows('):s.index('static StationLayoutPick(')]
_offs = [int(n) for n in re.findall(r'Atlas\.HkRow\(x \+ (\d+),', _win)]
assert _offs, 'Windows page HkRow offsets not found'
assert max(_offs) <= 460, ('Windows page HkRow runs past the panel', _offs)
# MUTED ROW BUTTONS NEED A LIVE SELECTION (v0.6.5). Edit and Delete are drawn
# once per frame from Atlas.HasSel(), which reads savedSel, which only moves
# when Build() runs -- and Lumi.Btn's "muted" kind throws the click handler
# away. So a page whose buttons mute themselves MUST hand its list an onPick
# that records the pick and rebuilds (Atlas.Picker); with the old
# `(i, dbl) => (dbl ? ... : 0)` a single click changed nothing on screen and
# Delete could never be pressed at all.
_src = (Path(__file__).parents[1] / 'RadMapper.ahk').read_text(encoding='utf-8-sig')
_pan = re.compile(r'\n    static (Panel\w+)\(x, y, w, h\) \{')
_hits = list(_pan.finditer(_src))
_bad = []
for _i, _m in enumerate(_hits):
    _end = _hits[_i + 1].start() if _i + 1 < len(_hits) else len(_src)
    _body = _src[_m.start():_end]
    # a panel body ends at its own closing brace, not at the next panel
    _body = _body[:_body.index('\n    }') + 6] if '\n    }' in _body else _body
    if 'Atlas.HasSel(' in _body and 'Atlas.Picker(' not in _body:
        _bad.append(_m.group(1))
assert not _bad, ('A page mutes its row buttons but never records a pick', _bad)
assert 'static Picker(mode := "")' in s, 'Atlas.Picker is missing'

# THE HOME CARD FITS AT 940 px. The panel is 704 wide there (as above), the
# card keeps 16 px gutters, and one row is
#   name 210 + 10 + triggers + 10 + Set 74 + 8 + Clear 64
# so the triggers column is w - 408 and everything sums to 704 - 32 = 672.
_home = _src[_src.index('static PanelHome('):_src.index('; ── PANEL: MOUSE')]
assert 'w - 408' in _home, 'Home essentials row width is no longer derived from w'
assert 210 + 10 + (704 - 408) + 10 + 74 + 8 + 64 == 704 - 32, 'Home row arithmetic'

# All helper text must be readable on every standard background.
def luminance(h):
    rgb = [int(h[i:i+2], 16)/255 for i in (0, 2, 4)]
    rgb = [v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    return sum(v*w for v,w in zip(rgb,[.2126,.7152,.0722]))
tokens = dict(re.findall(r'"(\w+)",\s+"0xFF([0-9A-F]{6})"', s[s.index('class Lumi {'):s.index('class Atlas {')]))
pairs = [(ink, ground) for ink in ['ink', 'inkDim', 'inkMute']
         for ground in ['abyss', 'surface', 'raised', 'raised2', 'sunk']]
# Accent tokens that are also painted AS TEXT have to clear the same bar on
# the two control/row grounds. `danger` is deliberately not on this list: it
# fails (3.8:1 on raised), which is exactly why Lumi.Btn's "danger" case
# paints its label with `dangerInk` and keeps `danger` for the border only.
pairs += [(ink, ground) for ink in ['dangerInk', 'magenta', 'jade', 'cyan']
          for ground in ['raised', 'raised2']]
for ink, ground in pairs:
    a,b = sorted([luminance(tokens[ink]),luminance(tokens[ground])])
    assert (b+.05)/(a+.05) >= 4.5, (ink, ground, round((b+.05)/(a+.05), 2))
# ---- nested function names vs enclosing parameters -------------------------
# AHK v2 refuses to load when a nested function (including a fat-arrow
# closure) has the same name, case-insensitively, as a parameter of the
# function it sits in: "This function declaration conflicts with an existing
# parameter". RadialIcon(name, x, y, ...) once declared X(d) => ... inside
# itself; the workstation refused to start. Passing a nested function by name
# (KPSection(..., ins)) is fine and is not what this checks.
_head = re.compile(r'^\s*(?:static\s+)?([A-Za-z_]\w*)\(([^)]*)\)\s*\{\s*$')
_nest = re.compile(r'^\s+([A-Za-z_]\w*)\(([^)]*)\)\s*(?:=>|\{\s*$)')
_kw = {'if', 'while', 'for', 'loop', 'switch', 'case', 'try', 'catch',
       'return', 'else', 'finally', 'until', 'throw'}
_lines = s.split('\n')
_clashes = []
_i = 0
while _i < len(_lines):
    _m = _head.match(_lines[_i])
    if not _m:
        _i += 1
        continue
    _indent = len(_lines[_i]) - len(_lines[_i].lstrip())
    _params = {p.strip().lstrip('&').split(':=')[0].split(' ')[0].strip().lower()
               for p in _m.group(2).split(',') if p.strip()}
    _depth = 0
    _j = _i
    while _j < len(_lines):
        _depth += _lines[_j].count('{') - _lines[_j].count('}')
        if _j > _i:
            _n = _nest.match(_lines[_j])
            if _n and (len(_lines[_j]) - len(_lines[_j].lstrip())) > _indent \
                    and _n.group(1).lower() in _params and _n.group(1).lower() not in _kw:
                _clashes.append((_j + 1, _m.group(1), _n.group(1)))
        if _depth <= 0 and _j > _i:
            break
        _j += 1
    _i = _j + 1
assert not _clashes, ('Nested function name conflicts with an enclosing parameter', _clashes)


# ---- variables that differ only by case inside one function -----------------
# AHK v2 variable names are case-insensitive: `W := R.wedges` then
# `w := W.slices[i]` overwrite the SAME variable. Parses fine, throws on the
# first run. Flag any function whose assigned / parameter / for-loop names
# collide case-insensitively. (Block comments, line comments and strings are
# blanked first, keeping newlines so line numbers stay right.)
def _blank(txt):
    out = []; i = 0; n = len(txt)
    while i < n:
        c = txt[i]
        if txt.startswith('/*', i):
            j = txt.find('*/', i); j = n if j < 0 else j + 2
            out.append(''.join('\n' if ch == '\n' else ' ' for ch in txt[i:j])); i = j
        elif c == ';' and (i == 0 or txt[i-1] in ' \t\n'):
            j = txt.find('\n', i); j = n if j < 0 else j
            out.append(' ' * (j - i)); i = j
        elif c in '"\'':
            q = c; j = i + 1
            while j < n and txt[j] != q and txt[j] != '\n':
                j += 2 if txt[j] == '`' else 1
            j = min(j + 1, n); out.append(' ' * (j - i)); i = j
        else:
            out.append(c); i += 1
    return ''.join(out)
_B = _blank(s).split('\n')
_assign = re.compile(r'(?<![\w.])([A-Za-z_]\w*)\s*(?::=|\+=|-=|\.=|\*=|/=)')
_forvar = re.compile(r'^\s*for\s+([A-Za-z_]\w*)(?:\s*,\s*([A-Za-z_]\w*))?\s+in\b')
_ctl = {'if', 'while', 'for', 'loop', 'switch', 'case', 'try', 'catch', 'return',
        'else', 'finally', 'until', 'throw', 'static', 'global', 'local'}
_casevars = []
_i = 0
while _i < len(_B):
    _m = _head.match(_B[_i])
    if not _m:
        _i += 1
        continue
    _names = {}
    for _p in _m.group(2).split(','):
        _p = _p.strip().lstrip('&').split(':=')[0].split(' ')[0].strip()
        if _p:
            _names.setdefault(_p.lower(), set()).add(_p)
    _depth = 0; _j = _i
    while _j < len(_B):
        _depth += _B[_j].count('{') - _B[_j].count('}')
        if _j > _i:
            for _a in _assign.findall(_B[_j]):
                if _a.lower() not in _ctl:
                    _names.setdefault(_a.lower(), set()).add(_a)
            _fm = _forvar.match(_B[_j])
            if _fm:
                for _a in _fm.groups():
                    if _a:
                        _names.setdefault(_a.lower(), set()).add(_a)
        if _depth <= 0 and _j > _i:
            break
        _j += 1
    for _low, _forms in _names.items():
        if len(_forms) > 1:
            _casevars.append((_m.group(1), _i + 1, sorted(_forms)))
    _i = _j + 1
assert not _casevars, ('Variables differing only by case in one function', _casevars)
# ---- a try (any form) between an if and its else ----------------------------
# `if x` / `try ...` / `else`: the try (braced or not; v2 try has its own
# else clause) takes the else, and the if is left dangling -> "Unexpected
# Else" at load, or DrawGrid-on-success if a build tolerates it. Put the
# braces on the if/else and the one-line try inside.
_tryelse = []
for _k in range(len(_B) - 1):
    if re.match(r'^\s*(if|else if)\b.*[^{]\s*$', _B[_k]) and re.match(r'^\s*try\b', _B[_k + 1]):
        _d = 0; _e = _k + 1
        while _e < len(_B):
            _d += _B[_e].count('{') - _B[_e].count('}')
            if _d <= 0 and (_e > _k + 1 or not _B[_k + 1].rstrip().endswith('{')):
                break
            _e += 1
        if _e + 1 < len(_B) and re.match(r'^\s*else\b', _B[_e + 1]):
            _tryelse.append(_k + 2)
assert not _tryelse, ('A try between an if and its else', _tryelse)

# ---- a local that shadows a class or function the same body calls ----------
# `line := ...` then `Line(x, y, ...)`: Line is a GpGFX class, i.e. a variable
# holding a Class object, and names are case-insensitive, so the call goes
# through the local integer -> "This value of type Integer is not callable".
_classes = {m.group(1) for m in re.finditer(r'^class\s+([A-Za-z_]\w*)', s, re.M)}
_funcs = {m.group(1) for m in re.finditer(r'^([A-Za-z_]\w*)\([^)]*\)\s*\{', s, re.M)}
_callables = {c.lower(): c for c in _classes | _funcs}
_shadow = []
_i = 0
while _i < len(_B):
    _m = _head.match(_B[_i])
    if not _m:
        _i += 1
        continue
    _names = {p.strip().lstrip('&').split(':=')[0].split(' ')[0].strip().lower()
              for p in _m.group(2).split(',') if p.strip()}
    _depth = 0; _j = _i; _body = []
    while _j < len(_B):
        _depth += _B[_j].count('{') - _B[_j].count('}')
        _body.append(_B[_j])
        if _j > _i:
            _names.update(a.lower() for a in _assign.findall(_B[_j]))
            _fm = _forvar.match(_B[_j])
            if _fm:
                _names.update(a.lower() for a in _fm.groups() if a)
        if _depth <= 0 and _j > _i:
            break
        _j += 1
    _text = '\n'.join(_body)
    for _n in _names:
        if _n in _callables and re.search(r'(?<![\w.])' + re.escape(_callables[_n]) + r'\s*\(', _text, re.I):
            _shadow.append((_m.group(1), _i + 1, _callables[_n]))
    _i = _j + 1
assert not _shadow, ('A local shadows a class/function the same body calls', _shadow)

print('PASS: UI member references, case-insensitive collisions, nested-name clashes, try/else binding, case-variant variables, class-name shadowing, timer identity, '
      f'Windows page fit (max HkRow offset {max(_offs)} <= 460), row-button pickers, Home card fit, '
      f'{len(pairs)} text/background contrast pairs')
