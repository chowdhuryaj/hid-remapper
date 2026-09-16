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
assert 'SetTimer(ObjBindMethod(Atlas, "MenuTryDone")' not in s, 'Preview timer must reuse its function object'
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
      f'{len(pairs)} text/background contrast pairs')
