"""Portable structural checks; not an AutoHotkey parser or runtime test."""
from pathlib import Path
from collections import Counter
import re
s = (Path(__file__).parents[1] / 'RadMapper.ahk').read_text(encoding='utf-8-sig')
for name, end in [('Lumi', 'Atlas'), ('Atlas', 'Calib')]:
    part = s[s.index('class ' + name + ' {'):s.index('class ' + end + ' {')]
    members = re.findall(r'^    static (\w+)\s*(?:\(|:=)', part, re.M)
    assert not [n for n, count in Counter(m.lower() for m in members).items() if count > 1], name
    calls = set(re.findall(r'\b' + name + r'\.(\w+)\(', s[:s.index('class GpGFX {')]))
    assert calls <= set(members), (name, calls - set(members))
# TIMER IDENTITY. SetTimer keys on the function OBJECT, so a fresh
# ObjBindMethod for the same method is a DIFFERENT timer: it cannot be
# cancelled by a later SetTimer(fn, 0) and two of them run side by side.
# Every repeating/cancellable bound-method timer keeps its BoundFunc in a
# static (Atlas.menuTryFn, Warp.idleFn, Warp.redrawFn).
for bad in ['SetTimer(ObjBindMethod(Atlas, "MenuTryDone")',
            'SetTimer(ObjBindMethod(Warp, "IdleClose")',
            'SetTimer(ObjBindMethod(Warp, "DrawFine")']:
    assert bad not in s, 'Timer must reuse its function object: ' + bad
assert 'static redrawFn := 0' in s, 'Warp.redrawFn static is missing'

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
