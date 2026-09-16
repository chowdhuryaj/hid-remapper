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
print('PASS: UI member references, case-insensitive collisions, timer identity, '
      f'Windows page fit (max HkRow offset {max(_offs)} <= 460), '
      f'{len(pairs)} text/background contrast pairs')
