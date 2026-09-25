#!/usr/bin/env python3
"""Generate radmapper/RadMapper-lite.ahk from radmapper/RadMapper.ahk.

The lite build is the RadMapper engine WITHOUT the vendored GpGFX graphics
library and everything drawn with it (the Lumi widget kit, the Atlas settings
window, Chooser, Warp, the window switcher overlay, the teleport flash, the
rendering self-test). See the "Lite build" section of radmapper/README.md.

Every edit is ANCHORED: a top-level function or class found by its exact
name, a section banner found by its exact text, a statement found by a
regular expression. Each anchor must match exactly once, and the build stops
with a message naming the anchor when one is missing or ambiguous -- so a
change to RadMapper.ahk that the lite build has not been taught about fails
loudly here instead of producing a broken script.

After writing the output it runs tools/check_lite.py (reference, balance,
stub-member and entry-point checks) and exits non-zero if that fails.

    python3 tools/build_lite.py            # build + check
    python3 tools/build_lite.py --no-check # build only
"""
import hashlib
import pathlib
import re
import sys

sys.dont_write_bytecode = True               # no tools/__pycache__ litter
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ahk_lex import code_lines, top_units, BANNER  # noqa: E402

ROOT = HERE.parent
SRC = ROOT / "radmapper" / "RadMapper.ahk"
DST = ROOT / "radmapper" / "RadMapper-lite.ahk"


class BuildError(Exception):
    pass


def fail(msg):
    raise BuildError(msg)


# ---------------------------------------------------------------------------
# Anchors
# ---------------------------------------------------------------------------
# The bundled GUI + graphics region: from the §13 banner to the entry point.
REGION_START = ";  §13  BUNDLED: Lumi Atlas design system"   # a banner line
REGION_END = "; ── SCRIPT ENTRY POINT"                        # line prefix
# Classes that MUST be in that region (proves the anchors still bracket it).
REGION_MUST_HOLD = ["Lumi", "Atlas", "Chooser", "Warp", "GpGFX", "Layer",
                    "LayerStack", "Shape", "Text", "Rectangle", "Gdip"]
# Directives allowed in the region; #Warn lines are carried over (they apply
# to the whole script wherever they appear), the rest are the library's own.
REGION_DIRECTIVES_KEEP = ("#warn",)
REGION_DIRECTIVES_DROP = ("#requires", "#dllload")

VERSION_RE = re.compile(r'^global RM_VERSION := "([^"]+)"', re.M)
REQUIRES_LINE = "#Requires AutoHotkey v2.0"

# Engine-region units that only draw, or only serve something that draws.
# Each is removed together with the comment block directly above it.
REMOVE_UNITS = [
    # §7b window switcher: list, thumbnails, painting, its Delete key
    ("func", "AppSwitchOpen"),
    ("func", "AppSwitchHidden"),
    ("func", "AppSwitchList"),
    ("func", "AppSwitchDelKey"),
    ("func", "AppSwitchCloseWindow"),
    ("func", "AppSwitchWatch"),
    ("class", "AppSwitchGeom"),
    ("func", "AppSwitchShotTick"),
    ("func", "AppSwitchShot"),
    ("func", "AppSwitchIcon"),
    ("func", "AppSwitchEllip"),
    ("func", "AppSwitchPaint"),
    # §11: GpGFX panels and the self-test
    ("func", "PlaceAtCursor"),
    ("func", "ShowGallery"),
    ("func", "AtlasRefresh"),
    # §11: native pickers/dialogs whose only callers were in Atlas
    ("func", "RecordCombo"),
    ("func", "InsertToken"),
    ("func", "KeyPicker"),
    ("func", "KPClose"),
    ("func", "ValueHostHwnd"),
    ("class", "FieldEdit"),
    ("func", "KPSection"),
    ("func", "InputPicker"),
    ("func", "ValidateActionValue"),
    ("func", "RecordKeyName"),
    ("func", "KeyNamePicker"),
    ("func", "AppDlg"),
    ("func", "AppOk"),
    ("func", "AppDelete"),
    # §12: the first-run welcome opened the settings window
    ("func", "FirstRunOpen"),
]

# Units whose whole text (and comment block above) is replaced. The new
# text must define the same name with the SAME parameter list, so every
# caller in the engine stays valid; a signature change upstream fails here.
REPLACE_UNITS = {
    ("func", "AppSwitchStep"): r'''
; LITE: the window switcher is a thumbnail grid drawn with GpGFX. The action
; still resolves (a bound wheel is consumed, not passed through) and says so.
AppSwitchStep(st, v) {
    LiteNA("appswitch", "The window switcher")
}
''',
    ("func", "AppSwitchClose"): r'''
; LITE: no switcher can be open; callers (panic, teardown, ClearBS) still
; get a closed g_AppSw.
AppSwitchClose(commit) {
    global g_AppSw
    g_AppSw := 0
}
''',
    ("func", "AppSwitchBindKeys"): r'''
; LITE: the switcher's Delete key is never registered.
AppSwitchBindKeys(on := false) {
    return
}
''',
    ("func", "TeleportSignal"): r'''
; LITE: the red edge flash and landing ring are GpGFX layers. The pointer
; still moves (TeleportMonitor / FollowTick / DoTeleport do that); only the
; signal is gone.
TeleportSignal(mon, cx, cy, showEdges := true) {
    return
}
''',
    ("func", "TeleSigTick"): r'''
TeleSigTick(*) {
    SetTimer(TeleSigTick, 0)
}
''',
    ("func", "HUD"): r'''
; LITE: the HUD is the classic corner-anchored tooltip (never AT the cursor,
; on top of whatever is being read). One stable function object (HUDOff) is
; re-armed on every call, so a burst of HUDs never hides the newest early.
HUD(msg, tone := "cyan") {
    m := HUDCorner()
    CoordMode("ToolTip", "Screen")
    ToolTip(HUDMark(tone) msg, m.x, m.y)
    SetTimer(HUDOff, -1500)
}

HUDMark(tone) {
    switch tone {
        case "danger": return "⚠  "
        case "warn", "pink": return "!  "
        case "jade", "ok": return "✓  "
    }
    return ""
}
''',
    ("func", "ShowMain"): r'''
; LITE: there is no settings window. Settings (tray, the Settings hotkey, a
; "guiopen" action) open the config file in Notepad on a thread of its own
; -- this can be called from a Critical hotkey thread, which must not sit in
; a MsgBox.
ShowMain() {
    SetTimer(LiteOpenConfig, -1)
}

LiteOpenConfig(*) {
    static busy := false
    if busy
        return
    busy := true
    try {
        try CfgFlush()                       ; the file shows what is live
        if (CFG_PATH = "" || !FileExist(CFG_PATH))
            try SaveCfg()
        try {
            Run('notepad.exe "' CFG_PATH '"')
        } catch as e {
            Problem("ui-error", "Could not open the config in Notepad: " e.Message)
            MsgBox("Could not open Notepad:`n`n" e.Message "`n`nThe config file is:`n"
                . CFG_PATH, "RadMapper " RM_VERSION, "Iconx")
            return
        }
        MsgBox("This is the lite build: settings are edited in the config file,"
            . " which is now open in Notepad.`n`n"
            . "1. Edit it and save it (keep it valid JSON).`n"
            . "2. Tray icon > Reload config.`n`n"
            . "A file with a mistake is not loaded: the engine keeps its"
            . " current settings and tells you what is wrong. Every load keeps"
            . " a backup in:`n" BACKUP_DIR "`n`n"
            . "For the full settings window, run RadMapper.ahk instead"
            . " (exit this one first).", "RadMapper " RM_VERSION, "Iconi")
    } finally {
        busy := false
    }
}

; Tray > Reload config. The file is parsed and shape-checked FIRST: LoadCfg
; treats an unreadable file as corruption (backup restore, defaults), which
; is right at startup but wrong for a typo made a minute ago in Notepad.
LiteReloadCfg(*) {
    static busy := false
    if busy
        return
    busy := true
    try {
        if (CFG_PATH = "" || !FileExist(CFG_PATH)) {
            MsgBox("There is no config file to load:`n" CFG_PATH,
                "RadMapper " RM_VERSION, "Iconx")
            return
        }
        try {
            chk := JsonLoad(FileRead(CFG_PATH, "UTF-8"))
            ValidateCfgShape(chk)
        } catch as e {
            Problem("reload", "Config not reloaded: " e.Message)
            MsgBox("The config file has a mistake and was NOT loaded:`n`n"
                . e.Message "`n`nThe engine keeps the settings it had. Fix the"
                . " file, save it, then choose Reload config again.`n`n" CFG_PATH,
                "RadMapper " RM_VERSION, "Iconx")
            return
        }
        LoadCfg()
        AfterCfgChange()
        HUD("Config reloaded", "jade")
    } catch as e {
        Problem("reload", "Reload failed: " e.Message)
        HUD("Reload failed: " e.Message, "danger")
    } finally {
        busy := false
    }
}

LiteCopyDiagnostics(*) {
    try {
        ProblemsCopy()
        HUD("Diagnostics copied to the clipboard", "jade")
    } catch as e {
        HUD("Could not copy diagnostics: " e.Message, "danger")
    }
}
''',
    ("func", "BuildTray"): r'''
; LITE tray. "Enabled" is the pause/resume toggle (UpdateTray ticks it).
BuildTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Open config file…", (*) => ShowMain())
    A_TrayMenu.Add("Reload config", (*) => LiteReloadCfg())
    A_TrayMenu.Add("Copy diagnostics", (*) => LiteCopyDiagnostics())
    A_TrayMenu.Add("Test my mouse…", (*) => TesterShow())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Enabled", (*) => ToggleEnabled())
    A_TrayMenu.Add("Panic release", (*) => PanicRelease())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Reload script", (*) => Reload())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := "Open config file…"
    UpdateTray()
}
''',
}

# Exact-text edits inside kept units: (unique old text, new text).
TEXT_EDITS = [
    ('TrayTip("Running. Double-click the tray icon or press " Cfg("hkGui")\n'
     '        . " for settings.", "RadMapper " RM_VERSION)',
     'TrayTip("Running (lite build). Double-click the tray icon or press "\n'
     '        . Cfg("hkGui") " to edit the config file.", "RadMapper " RM_VERSION)'),
    # no welcome window, and welcomedVer stays the full build's business (a
    # lite stamp "x.y.z lite" would make the full build welcome again)
    ('    ; FIRST RUN (v0.6): a colleague who was handed this file should not have\n'
     '    ; to find the tray icon. The first launch of each version opens the\n'
     '    ; settings window on its Home page; every later launch stays quiet.\n'
     '    if (Cfg("welcomedVer") != RM_VERSION) {\n'
     '        CfgSet("welcomedVer", RM_VERSION)\n'
     '        try SaveCfg()\n'
     '        SetTimer(FirstRunOpen, -800)\n'
     '    }\n',
     '    ; LITE: no first-run window (the full build\'s welcomedVer is left alone).\n'),
]

LITE_SECTION = r'''
; ══════════════════════════════════════════════════════════════════════════════
;  §13  LITE BUILD -- stand-ins for the GUI classes (generated section)
; ══════════════════════════════════════════════════════════════════════════════
;  The full build's Lumi / Atlas / Chooser / Warp classes and the GpGFX
;  library are not in this file. The engine still names those classes in a
;  few places (guards such as `Warp.active`, `Atlas.resizing`, a Confirm
;  prompt, a pause that closes the keyboard pointer), so each keeps a small
;  stand-in here: every member the engine touches is defined explicitly with
;  the value it has when that window is not open, and a static __Call /
;  __Get catch-all answers "" for anything else instead of throwing.

; A feature that needs drawing was asked for: say so on the HUD (at most once
; a second per feature -- a wheel spin bound to the switcher would otherwise
; redraw the tooltip on every notch from the wheel's Critical thread), and
; log it to Diagnostics once per feature per session.
LiteNA(key, what) {
    static told := Map(), shown := Map()
    now := A_TickCount
    if (!shown.Has(key) || now - shown[key] > 1000 || now < shown[key]) {
        shown[key] := now
        HUD(what " is not available in the lite build", "warn")
    }
    if !told.Has(key) {
        told[key] := 1
        Problem("lite", what " was requested; it needs the graphics library,"
            . " which the lite build does not include (run RadMapper.ahk).")
    }
    return 0
}

class Atlas {                                ; the settings window
    static lyr := 0                          ; never open
    static resizing := false
    static appIdx := 1                       ; picker positions (AppDelete)
    static kbAppIdx := 1
    static Show(*) => ShowMain()
    static Build(*) => 0
    static SaveOrWarn(*) => SaveCfg()
    static Confirm(msg, *) => (MsgBox(msg, "RadMapper", "YesNo Icon?") = "Yes")
    static __Call(name, args) => ""
    static __Get(name, params) => ""
}

class Lumi {                                 ; the widget kit
    static _toast := 0                       ; no toast window: HUD is a ToolTip
    static editing := false
    static toastCorner := "bl"
    static toastFollow := false
    static EditGuard(*) => 0
    static ToneMark(tone) => HUDMark(tone)
    static Toast(msg, tone := "cyan", *) => HUD(msg, tone)
    static __Call(name, args) => ""
    static __Get(name, params) => ""
}

class Chooser {                              ; a list at the cursor
    static Show(*) => LiteNA("chooser", "The layout chooser (a layout action with no name)")
    static Close(*) => 0
    static __Call(name, args) => ""
    static __Get(name, params) => ""
}

class Warp {                                 ; the keyboard pointer
    static active := false
    static grabbing := false
    static claimed := Map()                  ; releases Warp claimed: none
    static Toggle(*) => LiteNA("warp", "The keyboard pointer")
    static Open(*) => LiteNA("warp", "The keyboard pointer")
    static Close(*) => 0
    static FromHook(*) => 0
    static __Call(name, args) => ""
    static __Get(name, params) => ""
}

'''


def header(version, digest):
    return f''';==============================================================================
;  RadMapper v{version}  --  the engine without the graphics library
;
;  *** GENERATED FILE -- DO NOT EDIT ***  Built from RadMapper.ahk (sha256
;  {digest}) by tools/build_lite.py. Change RadMapper.ahk, then run:
;      python3 tools/build_lite.py
;
;  WHAT IT IS: RadMapper's whole engine -- config load/save/migration, the
;  mouse and keyboard hooks, layers, every action that does not draw,
;  PowerScribe/PACS delivery, macros, window layouts/stations/placement,
;  follow focus/park, click lock, pass-through, watchdog, panic, pause, the
;  Settings hotkeys and the Diagnostics log -- with the vendored GpGFX library
;  and everything drawn with it taken out: the Lumi widget kit, the Atlas
;  settings window, the chooser, the keyboard pointer, the window switcher,
;  the teleport flash and the rendering self-test.
;
;  WHAT IS DIFFERENT
;    * Settings (tray, the Settings hotkey, a "guiopen" action) open the
;      config JSON in Notepad. Edit, save, then tray > Reload config.
;    * Messages are a small tooltip in the HUD corner (about 1.5 s).
;    * The keyboard pointer, the window switcher and a layout action with no
;      layout name show "not available in the lite build" (logged once in
;      Diagnostics). Teleport still moves the pointer, without the flash.
;    * Tray: Open config file, Reload config, Copy diagnostics, Test my
;      mouse, Enabled (pause/resume), Panic release, Reload script, Exit.
;
;  Same config file and the same one-copy lock as RadMapper.ahk: run one of
;  the two, not both.
;=============================================================================='''.split("\n")


# ---------------------------------------------------------------------------
# Source model
# ---------------------------------------------------------------------------
class Src:
    def __init__(self, lines):
        self.lines = lines
        self.refresh()

    def refresh(self):
        self.code, errs = code_lines("\n".join(self.lines))
        if errs:
            fail("lexer: " + "; ".join(f"line {n}: {m}" for n, m in errs[:5]))
        self.units, errs = top_units(self.code)
        if errs:
            fail("structure: " + "; ".join(f"line {n}: {m}" for n, m in errs[:5]))

    def unit(self, kind, name):
        hits = [u for u in self.units if u.kind == kind and u.name.lower() == name.lower()]
        if len(hits) != 1:
            fail(f"anchor {kind} {name}: expected exactly one top-level definition, "
                 f"found {len(hits)}" + (f" (lines {[u.start + 1 for u in hits]})" if hits else ""))
        return hits[0]

    def doc_start(self, u):
        """First line of the comment block directly above unit u (no blank
        line between), never crossing a section banner or splitting a
        /* ... */ block."""
        s = u.start
        while s > 0:
            raw = self.lines[s - 1]
            st = raw.strip()
            if st.endswith("*/") and not st.startswith("/*"):
                k = s - 1                    # walk to the block's opening /*
                while k >= 0 and not self.lines[k].strip().startswith("/*"):
                    k -= 1
                if k < 0:
                    fail(f"unmatched */ above line {u.start + 1}")
                s = k
                continue
            if not st or self.code[s - 1].strip() or BANNER.match(raw):
                break
            s -= 1
        return s

    def find_line(self, pred, what):
        hits = [i for i, l in enumerate(self.lines) if pred(l)]
        if len(hits) != 1:
            fail(f"anchor {what}: expected exactly one line, found {len(hits)}"
                 + (f" (lines {[h + 1 for h in hits[:10]]})" if hits else ""))
        return hits[0]

    def splice(self, s, e, new):
        self.lines[s:e + 1] = new
        self.refresh()


def norm_params(p):
    return re.sub(r"\s+", "", p).lower()


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
def build(src_text):
    digest = hashlib.sha256(src_text.encode("utf-8")).hexdigest()[:16]
    had_bom = src_text.startswith("﻿")
    body = src_text[1:] if had_bom else src_text
    if "\r\n" in body:
        fail("source has CRLF line endings; the build expects LF")
    src = Src(body.split("\n"))
    report = []

    # 1. the bundled GUI + graphics region ---------------------------------
    rs = src.find_line(lambda l: l.rstrip() == REGION_START, f"region start {REGION_START!r}")
    if rs == 0 or not src.lines[rs - 1].startswith("; ═"):
        fail("region start: the line above the §13 title is not its ═ banner")
    rs -= 1
    re_ = src.find_line(lambda l: l.startswith(REGION_END), f"region end {REGION_END!r}")
    if re_ <= rs:
        fail("region end comes before region start")
    inside = [u for u in src.units if rs <= u.start < re_]
    straddle = [u for u in src.units if u.start < rs <= u.end or u.start < re_ <= u.end]
    if straddle:
        fail(f"region boundary splits a unit: {straddle}")
    names = {u.name.lower() for u in inside if u.name}
    missing = [n for n in REGION_MUST_HOLD if n.lower() not in names]
    if missing:
        fail(f"region {rs + 1}-{re_}: expected classes not found there: {missing}")
    if any(u.kind == "stmt" for u in inside):
        fail("region holds a top-level statement: " +
             str([u for u in inside if u.kind == "stmt"]))
    carry = []
    for u in inside:
        if u.kind != "directive":
            continue
        d = u.name.lower()
        if d in REGION_DIRECTIVES_KEEP:
            carry.append(src.code[u.start].strip())
        elif d not in REGION_DIRECTIVES_DROP:
            fail(f"unknown directive {u.name} in the removed region (line {u.start + 1}); "
                 "teach build_lite.py whether the lite build needs it")
    region_classes = sorted(u.name for u in inside if u.kind == "class")
    region_funcs = sorted(u.name for u in inside if u.kind == "func")
    report.append(f"removed region lines {rs + 1}-{re_}: {re_ - rs} lines, "
                  f"{len(region_classes)} classes, {len(region_funcs)} functions")
    src.splice(rs, re_ - 1, LITE_SECTION.strip("\n").split("\n") + ["", ""])

    # 2. engine-region removals --------------------------------------------
    for kind, name in REMOVE_UNITS:
        u = src.unit(kind, name)
        s = src.doc_start(u)
        src.splice(s, u.end, [])
    report.append(f"removed {len(REMOVE_UNITS)} GUI-only units from the engine region")

    # 3. replacements -------------------------------------------------------
    for (kind, name), text in REPLACE_UNITS.items():
        u = src.unit(kind, name)
        new = text.strip("\n").split("\n")
        # the replacement must define `name` with the same parameters
        nc, _ = code_lines("\n".join(new))
        nu, _ = top_units(nc)
        mine = [x for x in nu if x.kind == kind and x.name.lower() == name.lower()]
        if len(mine) != 1:
            fail(f"replacement for {name} does not define it exactly once")
        if norm_params(mine[0].params) != norm_params(u.params):
            fail(f"{name}: parameters changed upstream ({u.params!r}); "
                 f"the lite replacement has ({mine[0].params!r}) -- update build_lite.py")
        s = src.doc_start(u)
        src.splice(s, u.end, new)
    report.append(f"replaced {len(REPLACE_UNITS)} units")

    # 4. exact-text edits ---------------------------------------------------
    text = "\n".join(src.lines)
    for old, new in TEXT_EDITS:
        c = text.count(old)
        if c != 1:
            fail(f"text anchor found {c} times (need 1): {old[:60]!r}...")
        text = text.replace(old, new)
    src = Src(text.split("\n"))

    # 5. version + header + carried directives ------------------------------
    text = "\n".join(src.lines)
    vm = VERSION_RE.findall(text)
    if len(vm) != 1:
        fail(f"RM_VERSION anchor: expected one `global RM_VERSION := \"...\"`, found {len(vm)}")
    version = vm[0] + " lite"
    text = VERSION_RE.sub(f'global RM_VERSION := "{version}"', text)
    lines = text.split("\n")
    rq = [i for i, l in enumerate(lines) if l.rstrip() == REQUIRES_LINE]
    if len(rq) != 1:
        fail(f"anchor {REQUIRES_LINE!r}: expected one line, found {len(rq)}")
    rq = rq[0]
    if any(l.strip() and not l.lstrip().startswith(";") for l in lines[:rq]):
        fail("code found above #Requires; the header block is not comments only")
    warn = [f"{d}{' ' * max(1, 28 - len(d))}; carried over from the removed GpGFX"
            " section:" for d in carry]
    if warn:
        warn.append("                            ; #Warn applies to the whole script")
    lines = header(version, digest) + [""] + [lines[rq]] + warn + lines[rq + 1:]

    # tidy: no runs of more than two blank lines
    out = []
    blank = 0
    for l in lines:
        blank = blank + 1 if not l.strip() else 0
        if blank <= 2:
            out.append(l)
    while out and not out[-1].strip():
        out.pop()
    result = "\n".join(out) + "\n"
    if had_bom:
        result = "﻿" + result
    report.append(f"version {version!r}; carried directives: {carry or 'none'}")
    return result, report


def main(argv):
    try:
        src_text = SRC.read_text(encoding="utf-8")
        result, report = build(src_text)
    except BuildError as e:
        print(f"build_lite: FAILED: {e}", file=sys.stderr)
        return 2
    DST.write_text(result, encoding="utf-8", newline="\n")
    for r in report:
        print("build_lite:", r)
    n = result.count("\n")
    print(f"build_lite: wrote {DST.relative_to(ROOT)} ({n} lines, "
          f"from {src_text.count(chr(10))} lines)")
    if "--no-check" in argv:
        return 0
    import check_lite
    return check_lite.main([])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
