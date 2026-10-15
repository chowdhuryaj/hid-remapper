"""Portable structural checks; not an AutoHotkey parser or runtime test."""
from pathlib import Path
from collections import Counter
import re
s = (Path(__file__).parents[1] / 'RadMapper.ahk').read_text(encoding='utf-8-sig')
for name, end in [('Lumi', 'Atlas'), ('Atlas', 'Chooser')]:
    part = s[s.index('class ' + name + ' {'):s.index('class ' + end + ' {')]
    members = re.findall(r'^    static (\w+)\s*(?:\(|:=)', part, re.M)
    assert not [n for n, count in Counter(m.lower() for m in members).items() if count > 1], name
    calls = set(re.findall(r'\b' + name + r'\.(\w+)\(', s[:s.index('class GpGFX {')]))
    assert calls <= set(members), (name, calls - set(members))
assert 'SetTimer(ObjBindMethod(Atlas, "MenuTryDone")' not in s, 'Preview timer must reuse its function object'
# A label of exactly "0" must draw: `str == 0` is a numeric compare in AHK v2.
assert not re.search(r'str\s*!?==?\s*0\b', s), 'text emptiness must not compare against 0'
# All helper text must be readable on every standard background.
def luminance(h):
    rgb = [int(h[i:i+2], 16)/255 for i in (0, 2, 4)]
    rgb = [v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    return sum(v*w for v,w in zip(rgb,[.2126,.7152,.0722]))
tokens = dict(re.findall(r'"(\w+)",\s+"0xFF([0-9A-F]{6})"', s[s.index('class Lumi {'):s.index('class Atlas {')]))
for ink in ['ink', 'inkDim', 'inkMute']:
    for ground in ['abyss', 'surface', 'raised', 'raised2', 'sunk']:
        a,b = sorted([luminance(tokens[ink]),luminance(tokens[ground])])
        assert (b+.05)/(a+.05) >= 4.5, (ink, ground)
# CaseSense can only be set on an EMPTY Map ("Map must be empty" at runtime).
lines = s.split('\n')
for i, l in enumerate(lines):
    m = re.search(r'(\w+)\.CaseSense\s*:=', l)
    if not m:
        continue
    for j in range(i - 1, max(i - 30, 0), -1):
        a = re.search(r'\b' + re.escape(m.group(1)) + r'\s*:=\s*(.*)', lines[j])
        if a:
            assert re.match(r'(Map\(\s*\)|IMap\(\)|0\b|"")', a.group(1).strip()), \
                ('CaseSense on a non-empty Map', i + 1)
            break
# Member names are case-insensitive in AHK v2: a method and a property that
# differ only in case collide ("Property is read-only" at load). Every app
# class is checked at class-body depth (braces matched, strings stripped).
def class_body(src, name):
    i = src.index('class ' + name + ' ')
    i = src.index('{', i) + 1
    depth, j = 1, i
    while depth:
        c = src[j]
        if c == '"':
            j = src.index('"', j + 1)
        elif c == ';' and src[j-1] in ' \t\n':
            j = src.index('\n', j)
            continue
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
        j += 1
    return src[i:j-1]
app = s[:s.index('class GpGFX {')]
for cname in re.findall(r'^class (\w+)', app, re.M):
    members = re.findall(r'^    (?:static )?(\w+)\s*(?:\(|:=)', class_body(app, cname), re.M)
    dup = [n for n, k in Counter(m.lower() for m in members).items() if k > 1]
    assert not dup, (cname, dup)
print('PASS: UI member references, "0" labels draw, case-insensitive collisions, timer identity, 15 text/background contrast pairs, CaseSense on empty Maps, member-name collisions in every app class')
