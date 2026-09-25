"""Portable structural checks for RadWheel.ahk (not an AutoHotkey parser).

Checks: UTF-8 BOM, balanced brackets outside strings/comments, every
called user function is defined, no function defined twice, no v1-only
commands, and every `global X := ...` assignment target declared global in
the functions that assign it.
"""
from pathlib import Path
import re, sys

raw = (Path(__file__).parents[1] / 'RadWheel.ahk').read_bytes()
assert raw.startswith(b'\xef\xbb\xbf'), 'RadWheel.ahk must be UTF-8 with BOM'
src = raw.decode('utf-8-sig')

# strip comments and strings (AHK v2: "..." and '...', ` escapes)
def strip(line):
    out, q, i = [], None, 0
    while i < len(line):
        c = line[i]
        if q:
            if c == '`':
                i += 2; continue
            if c == q:
                q = None
            out.append(' ')
        else:
            if c in '"\'':
                q = c; out.append(' ')
            elif c == ';' and (i == 0 or line[i-1] in ' \t'):
                break
            else:
                out.append(c)
        i += 1
    return ''.join(out)

code_lines, in_block = [], False
for ln in src.splitlines():
    t = ln.strip()
    if in_block:
        code_lines.append('')
        if t.startswith('*/') or t.endswith('*/'):
            in_block = False
        continue
    if t.startswith('/*'):
        in_block = not t.endswith('*/')
        code_lines.append('')
        continue
    code_lines.append(strip(ln))
code = '\n'.join(code_lines)

for a, b in ['()', '[]', '{}']:
    assert code.count(a) == code.count(b), f'unbalanced {a}{b}: {code.count(a)} vs {code.count(b)}'

defs = re.findall(r'^[ \t]*(?:static[ \t]+)?([A-Za-z_]\w*)\((?:[^()]|\([^()]*\))*\)\s*(?:\{|=>)', code, re.M)
top = re.findall(r'^([A-Za-z_]\w*)\((?:[^()]|\([^()]*\))*\)\s*(?:\{|=>)', code, re.M)
dups = {d for d in top if top.count(d) > 1}
assert not dups, f'duplicate functions: {dups}'

builtins = set('''Abs ATan ACos Ceil Chr Click ComObjFromPtr ComObjValue ComValue Critical
CoordMode DirCreate DirExist DllCall FileCreateShortcut FileDelete FileExist FileMove FileOpen
FileSelect Floor Gui HotIf Hotkey IniRead InputBox InputHook InStr Integer IsInteger IsObject
KeyWait ListLines KeyHistory Loop Map Max Min Mod MonitorGet MonitorGetCount MonitorGetPrimary
MouseGetPos MsgBox NumGet NumPut OnExit ProcessSetPriority Reload Round Run Send SendMode SetCapsLockState
SetDefaultMouseSpeed SetMouseDelay SetTimer SetTitleMatchMode SetWinDelay Sin Cos Sleep Sqrt StrLen StrLower
StrReplace StrSplit StrUpper String SubStr ToolTip TraySetIcon TrayTip Trim WinActivate WinActive
WinExist WinGetClass WinGetList WinGetMinMax WinGetPID WinGetPos WinGetProcessName WinGetTitle
WinRestore WinWaitActive WinWaitClose RegExMatch RegExReplace InstallKeybdHook InstallMouseHook
GetKeyState Buffer ExitApp Persistent Round DetectHiddenWindows Error FileGetTime FileRead SetKeyDelay'''.split())
methods_ok = set('''Add Delete Push Pop Has Clone RemoveAt OnEvent Show Hide Destroy SetFont Opt
Choose GetSelection GetText Start Wait KeyOpt Bind Get Clear Init Ensure Free Update Close Write
accDoDefaultAction accLocation ToggleCheck'''.split())
keywords = {'if', 'while', 'for', 'switch', 'return', 'loop', 'catch', 'until', 'not', 'and', 'or', 'Loop', 'global', 'static', 'super'}
called = set()
for m in re.finditer(r'(?<![\w.])([A-Za-z_]\w*)\(', code):
    called.add(m.group(1))
nested_ok = {'row', 'fld', 'Ok', 'Save', 'AddNodes'}
missing = sorted(c for c in called if c not in defs and c not in builtins and c not in keywords and c not in nested_ok)
assert not missing, f'called but not defined: {missing}'

for v1 in [r'^\s*IfWinActive', r'^\s*#IfWinActive', r'%\w+%', r'^\s*Gui,', r'^\s*GuiControl']:
    assert not re.search(v1, code, re.M), f'v1 syntax: {v1}'

# functions that assign a script global must declare it (v2 assume-local)
globals_ = set(re.findall(r'^global ([A-Za-z_]\w*) :=', src, re.M))
fn_re = re.compile(r'^([A-Za-z_]\w*)\([^\n]*\)\s*\{\n(.*?)^\}', re.M | re.S)
for fm in fn_re.finditer(code):
    name, body = fm.group(1), fm.group(2)
    declared = set()
    for g in re.findall(r'^\s*global ([^\n]+)', body, re.M):
        declared |= {x.strip() for x in g.split(',')}
    for v in globals_:
        if re.search(r'(?<![\w.])' + v + r'\s*(?::=|\+=|-=|\.=)', body) and v not in declared:
            sys.exit(f'FAIL: {name} assigns global {v} without declaring it')

# AHK variable names are case-insensitive: `G` and `g`, `Ed` and `ed`,
# `COUNTS` and `counts` are ONE variable. Flag any function whose body (or
# parameter list) spells one name two ways, and any local that shadows a
# script global under a different spelling.
glob_lower = {g.lower(): g for g in re.findall(r'^global ([A-Za-z_]\w*)', src, re.M)}
# function bodies by brace matching (a regex stops at the first nested `}`)
def functions(text):
    head = re.compile(r'^[ \t]*(?:static[ \t]+)?([A-Za-z_]\w*)\(([^\n]*)\)\s*\{', re.M)
    for hm in head.finditer(text):
        if hm.group(1).lower() in {'if', 'while', 'for', 'switch', 'loop', 'catch'}:
            continue
        depth, i = 1, hm.end()
        while depth and i < len(text):
            depth += {'{': 1, '}': -1}.get(text[i], 0)
            i += 1
        yield hm.group(1), hm.group(2), text[hm.end():i - 1]
clashes = []
for name, params, body in functions(code):
    text = params + '\n' + body
    spell = {}
    for m in re.finditer(r'(?<![\w.])([A-Za-z_]\w*)(?![\w(])', text):
        w = m.group(1)
        spell.setdefault(w.lower(), set()).add(w)
    for low, forms in spell.items():
        if low in {'if', 'else', 'return', 'for', 'in', 'loop', 'while', 'try',
                   'catch', 'finally', 'switch', 'case', 'default', 'global',
                   'static', 'and', 'or', 'not', 'is', 'true', 'false', 'as', 'break', 'continue'}:
            continue
        if len(forms) > 1:
            clashes.append(f'{name}: {sorted(forms)}')
        elif low in glob_lower and glob_lower[low] not in forms:
            clashes.append(f'{name}: {sorted(forms)} vs global {glob_lower[low]}')
assert not clashes, 'case-insensitive name clashes:\n  ' + '\n  '.join(clashes)

print(f'PASS: no case clashes, BOM, bracket balance, {len(set(defs))} functions defined, '
      f'{len(called)} names called all resolve, no v1 syntax, global assignments declared')
