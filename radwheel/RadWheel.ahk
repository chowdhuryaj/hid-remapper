#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
; ═════════════════════════════════════════════════════════════════════════════
;  RadWheel 1.1  --  radial menus for the reading room
; ═════════════════════════════════════════════════════════════════════════════
;
;  A standalone script: the radial-menu feature of RadMapper on its own, with
;  a Stream-Deck-style editor. One file, no libraries, AutoHotkey v2.
;
;  USING IT
;    Hold the menu button, move toward a command, let go.
;    * Move fast and the wheel is never drawn: it fires on direction alone.
;    * Hold still and the wheel fades in so you can read it.
;    * Let go in the centre, press Esc or click to cancel.
;    * A quick tap does whatever the menu says: the button's normal job
;      (default), open the wheel and keep it open (then click a command or
;      tap again), nothing, or any command.
;    * While a wheel is open, the number keys 1-9 pick slot 1-9.
;
;  SHIPPED SETUP (all editable)
;    In PACS:  HOLD right-click     -> PACS tools wheel (tap = normal menu)
;              HOLD/TAP button 5    -> window presets 1-9
;    In PowerScribe: HOLD button 4  -> Dictate / Next field / Prev field
;
;  SETTINGS WINDOW:  double-click the tray icon, or Ctrl+Alt+Shift+F10.
;  UNSTICK KEYS:     Ctrl+Alt+Shift+F12.
;  Config file:      %APPDATA%\RadWheel\RadWheel.ini (UTF-16, human-editable)
;
;  SPEED NOTES (why the code is shaped the way it is)
;    * Nothing runs between gestures. The click/Esc/digit hotkeys exist only
;      while a wheel is open, so ordinary clicks are never routed through a
;      script callback.
;    * A flick that is released before the show delay never paints anything.
;    * Each ring is rendered ONCE into a cached bitmap (pre-rendered shortly
;      after start). A selection change blits that bitmap and draws only the
;      highlighted slice on top.
;    * The 1 ms system timer is requested only while a wheel is open or a
;      right-click menu is being driven, and released right after.
;    * Commands go to the program in front with a plain SendInput; focus is
;      only switched when a command targets another program.
; ═════════════════════════════════════════════════════════════════════════════

Persistent
; Event mode with no delays, the same as RadMapper. SendInput briefly takes
; the script's own hooks out while it sends (RadMapper avoids it for that
; reason), and while another script's keyboard hook is installed it falls
; back to SendEvent anyway, at the default 10 ms per key.
SendMode "Event"
SetKeyDelay -1, -1
CoordMode "Mouse", "Screen"
CoordMode "ToolTip", "Screen"
SetTitleMatchMode 2
SetWinDelay 10
SetMouseDelay -1
SetDefaultMouseSpeed 0
ListLines False
KeyHistory 0
A_MaxHotkeysPerInterval := 2000
A_HotkeyInterval := 1000
ProcessSetPriority "AboveNormal"

; ── §1  CONSTANTS AND STATE ─────────────────────────────────────────────────

global APP := "RadWheel"
global VER := "1.1"
global CFG_DIR := A_AppData "\RadWheel"
global CFG_FILE := CFG_DIR "\RadWheel.ini"

global Conf := Map()                ; settings
global Menus := []               ; menu objects, in file order
global Cur := 0                  ; the open wheel, or 0
global Held := Map()             ; trigger key -> press info
global Swallow := Map()          ; trigger key -> swallow its next release
global ClickSwallow := Map()     ; mouse button -> swallow its next release
global ClicksLive := false       ; the while-open hotkeys are registered
global HkList := []              ; registered trigger hotkeys
global Paused := false
global Stamp := 0                ; bumps on every config change (cache key)
global Ed := 0                   ; the settings window
global HiResOn := 0
global EatRepeat := Map()        ; key -> tick: auto-repeats of a key press
                                 ;   that already did its job are eaten
global RmOwned := Map()          ; inputs RadMapper has hooked right now
global RmSeen := {running: false, cfg: "", hooks: "", mtime: "", readOk: false}

Held.CaseSense := "Off"
Swallow.CaseSense := "Off"
ClickSwallow.CaseSense := "Off"
EatRepeat.CaseSense := "Off"
RmOwned.CaseSense := "Off"

global SETTING_KEYS := ["Size", "ShowDelay", "SubmenuDelay", "ToggleTimeout",
    "Confirm", "ReturnPointer", "RightClickMethod", "PsExes", "PacsExes",
    "PacsViewerTitle", "ReturnDelay", "TapMs", "YieldToRadMapper"]

DefaultSettings() {
    d := Map()
    d["Size"] := "Medium"            ; Small / Medium / Large
    d["ShowDelay"] := 180            ; ms held still before the wheel is drawn
    d["SubmenuDelay"] := 280         ; ms resting on a submenu before it opens
    d["ToggleTimeout"] := 12         ; s an open (tapped) wheel waits for you
    d["Confirm"] := 1                ; show what ran, bottom of the screen
    d["ReturnPointer"] := 1          ; after a command, pointer back to start
    d["RightClickMethod"] := "click" ; click | action (how menu items are hit)
    d["PsExes"] := "Nuance.PowerScribe360.exe, Nuance.PSOne.exe"
    d["PacsExes"] := "IntelliSpacePACSRadiology.exe"
    d["PacsViewerTitle"] := "VirtualMonitor"
    d["ReturnDelay"] := 60           ; ms before focus goes back after PS/PACS
    d["TapMs"] := 300                ; a press shorter than this, let go in
                                     ;   the centre, is a TAP (normal click)
    d["YieldToRadMapper"] := 1       ; leave RadMapper's buttons to RadMapper
    return d
}

global COLORS := Map("Blue", 0xFF3B82F6, "Teal", 0xFF14B8A6,
    "Green", 0xFF22C55E, "Amber", 0xFFF59E0B, "Red", 0xFFEF4444,
    "Purple", 0xFFA855F7, "Pink", 0xFFEC4899, "Grey", 0xFF8B93A1)
global COLOR_NAMES := ["Blue", "Teal", "Green", "Amber", "Red", "Purple",
    "Pink", "Grey"]

; Every glyph here is in Segoe UI Symbol, so it renders on any Windows 10/11.
global ICONS := ["(first letter)", "▶", "◀", "▲", "▼", "●", "◐", "◑", "◯",
    "□", "✕", "✓", "✎", "↔", "↕", "⌕", "⊕", "⊖", "⟲", "⟳", "⇥", "⇤", "★",
    "⚑", "☰", "⚙", "♪", "⏸", "⌫", "⌖", "1", "2", "3", "4", "5", "6", "7",
    "8", "9"]

global TRIGGERS := [
    ["RButton",  "Right button"],
    ["XButton1", "Mouse button 4 (back thumb button)"],
    ["XButton2", "Mouse button 5 (forward thumb button)"],
    ["MButton",  "Middle button (wheel click)"],
    ["CapsLock", "Caps Lock"],
    ["``",       "`` (backtick key)"],
    ["F13", "F13"], ["F14", "F14"], ["F15", "F15"], ["F16", "F16"],
    ["F17", "F17"], ["F18", "F18"], ["F19", "F19"], ["F20", "F20"],
    ["",         "None (opened only from another wheel)"]]

global SLOT_TYPES := [
    ["none",   "Nothing (empty slot)"],
    ["keys",   "Press a keyboard shortcut"],
    ["rclick", "Pick an item from the right-click menu"],
    ["text",   "Type some text"],
    ["menu",   "Open another wheel"],
    ["run",    "Open a program, file or web page"]]
global TAP_TYPES := [
    ["toggle", "Open this wheel and keep it open"],
    ["native", "Do its normal job (normal click or key)"],
    ["none",   "Nothing"],
    ["keys",   "Press a keyboard shortcut"],
    ["rclick", "Pick an item from the right-click menu"],
    ["text",   "Type some text"],
    ["menu",   "Open another wheel (kept open)"],
    ["run",    "Open a program, file or web page"]]

global TARGETS := [["front", "The program under the pointer / in front"],
    ["ps", "PowerScribe (focus comes back afterwards)"],
    ["pacs", "PACS viewer (focus comes back afterwards)"]]

global DIR4 := ["Up", "Right", "Down", "Left"]
global DIR8 := ["Up", "Up-right", "Right", "Down-right", "Down", "Down-left",
    "Left", "Up-left"]
global COUNTS := [4, 6, 8, 9, 10, 12]

; ── §2  MODEL ───────────────────────────────────────────────────────────────

NewSlot(label := "", type := "none", value := "", icon := "", color := "Blue",
        target := "front") {
    return {label: label, type: type, value: value, icon: icon, color: color,
            target: target}
}

CloneSlot(s) {
    return NewSlot(s.label, s.type, s.value, s.icon, s.color, s.target)
}

; hold: true = holding opens the wheel. tapType: what a quick tap does.
; move: "flick" = moving before the wheel shows picks by direction,
;       "drag"  = moving before the wheel shows is an ordinary drag.
NewMenu(name, trigger := "", programs := "", hold := true, tapType := "native",
        count := 8, move := "flick") {
    m := {name: name, trigger: trigger, programs: programs, hold: hold,
          move: move, count: count, tap: NewSlot("", tapType), slots: []}
    PadSlots(m)
    return m
}

PadSlots(m) {
    while (m.slots.Length < m.count)
        m.slots.Push(NewSlot())
}

FindMenu(name) {
    for m in Menus
        if (m.name = name)
            return m
    return 0
}

LiveCount(m) {
    n := 0
    loop m.count
        if (m.slots[A_Index].type != "none")
            n += 1
    return n
}

; Does this menu actually take its button over? A menu whose hold does
; nothing (or opens an empty wheel) and whose tap is "normal" leaves the
; button native, drags and all.
Claims(m) {
    return m.trigger != "" && ((m.hold && LiveCount(m)) || m.tap.type != "native")
}

ProgramExes(p) {
    if (p = "PACS")
        p := Conf["PacsExes"]
    else if (p = "PowerScribe")
        p := Conf["PsExes"]
    out := []
    for e in StrSplit(p, ",") {
        e := Trim(e)
        if (e != "")
            out.Push(e)
    }
    return out
}

; The exe behind a window. The gate asks this on every press of a menu button
; anywhere, while the hook waits for the answer; opening the process to read
; its name each time is the slow part, so the name is kept per window and
; re-checked only by the (cheap) owning process id.
ExeOf(hwnd) {
    static cache := Map()
    if !hwnd
        return ""
    pid := 0
    DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &pid)
    if !pid
        return ""
    if (cache.Has(hwnd) && cache[hwnd].pid = pid)
        return cache[hwnd].exe
    exe := ""
    try exe := WinGetProcessName("ahk_id " hwnd)
    if (cache.Count > 128)
        cache.Clear()
    cache[hwnd] := {pid: pid, exe: exe}
    return exe
}

ExeIn(exe, list) {
    for e in list
        if (e = exe)
            return true
    return false
}

; The menu for a trigger right now. For a MOUSE trigger the program is the
; one under the pointer (that is what the hand is aiming at, even on an
; inactive monitor); for a key it is the program in front. A menu for that
; program wins over an "every program" menu on the same button.
MenuFor(trig, &win := 0) {
    win := 0
    try {
        if IsMouseKey(KeyOf(trig))
            MouseGetPos(, , &win)
        else
            win := WinExist("A")
    }
    exe := ExeOf(win)
    fallback := 0
    for m in Menus {
        if (m.trigger != trig || !Claims(m))
            continue
        if (m.programs = "") {
            if !IsObject(fallback)
                fallback := m
            continue
        }
        if ExeIn(exe, ProgramExes(m.programs))
            return m
    }
    return fallback
}

; ── §3  CONFIG FILE ─────────────────────────────────────────────────────────
;
; An INI file, UTF-16 so symbols survive. Every value is written in quotes
; (Windows strips one pair on read, so leading spaces survive) with \n for a
; new line and \\ for a backslash. Sections are "[Menu <name>]", in order.

Esc(v) {
    v := StrReplace(String(v), "\", "\\")
    v := StrReplace(v, "`r", "")
    return StrReplace(v, "`n", "\n")
}

Unesc(v) {
    v := StrReplace(v, "\\", Chr(1))
    v := StrReplace(v, "\n", "`n")
    return StrReplace(v, Chr(1), "\")
}

Q(v) => '"' Esc(v) '"'

IniGet(sec, key, def := "") {
    try return Unesc(IniRead(CFG_FILE, sec, key, def))
    return def
}

ToInt(v, def) => IsInteger(v) ? Integer(v) : def

LoadConfig() {
    global Conf, Menus
    Conf := DefaultSettings()
    Menus := []
    if !FileExist(CFG_FILE) {
        Menus := SeedMenus()
        SaveConfig()
        return true                          ; first run
    }
    for k in SETTING_KEYS
        Conf[k] := IniGet("Settings", k, Conf[k])
    for k in ["ShowDelay", "SubmenuDelay", "ToggleTimeout", "Confirm",
              "ReturnPointer", "ReturnDelay", "TapMs", "YieldToRadMapper"]
        Conf[k] := ToInt(Conf[k], DefaultSettings()[k])
    secs := ""
    try secs := IniRead(CFG_FILE)
    for sec in StrSplit(secs, "`n") {
        if (SubStr(sec, 1, 5) = "Menu ")
            Menus.Push(ReadMenu(sec))
    }
    if (Menus.Length = 0)
        Menus := SeedMenus()
    return false
}

ReadMenu(sec) {
    count := ToInt(IniGet(sec, "Slots", "8"), 8)
    count := Max(2, Min(12, count))
    move := IniGet(sec, "Move", "flick")
    m := NewMenu(SubStr(sec, 6), IniGet(sec, "Trigger"),
        IniGet(sec, "Programs"), IniGet(sec, "Hold", "1") = "1",
        IniGet(sec, "Tap.Type", "native"), count,
        move = "drag" ? "drag" : "flick")
    m.tap := ReadSlot(sec, "Tap")
    if (m.tap.type = "none" && IniGet(sec, "Tap.Type", "") = "")
        m.tap.type := "native"
    m.slots := []
    loop count
        m.slots.Push(ReadSlot(sec, A_Index))
    return m
}

ReadSlot(sec, p) {
    s := NewSlot(IniGet(sec, p ".Label"), IniGet(sec, p ".Type", "none"),
        IniGet(sec, p ".Value"), IniGet(sec, p ".Icon"),
        IniGet(sec, p ".Color", "Blue"), IniGet(sec, p ".Target", "front"))
    if (s.type = "")
        s.type := "none"
    if !COLORS.Has(s.color)
        s.color := "Blue"
    return s
}

SlotLines(p, s) {
    return p ".Label=" Q(s.label) "`r`n" p ".Type=" Q(s.type) "`r`n"
        . p ".Value=" Q(s.value) "`r`n" p ".Icon=" Q(s.icon) "`r`n"
        . p ".Color=" Q(s.color) "`r`n" p ".Target=" Q(s.target) "`r`n"
}

SaveConfig() {
    t := "; RadWheel settings. Easiest to edit in the RadWheel window (double-click`r`n"
       . "; the tray icon). Values are in quotes; \n is a new line.`r`n`r`n"
       . "[Settings]`r`n"
    for k in SETTING_KEYS
        t .= k "=" Q(Conf[k]) "`r`n"
    for m in Menus {
        t .= "`r`n[Menu " m.name "]`r`n"
           . "Trigger=" Q(m.trigger) "`r`n"
           . "Programs=" Q(m.programs) "`r`n"
           . "Hold=" Q(m.hold ? 1 : 0) "`r`n"
           . "Move=" Q(m.move) "`r`n"
           . "Slots=" Q(m.count) "`r`n"
        t .= SlotLines("Tap", m.tap)
        loop m.count
            t .= SlotLines(A_Index, m.slots[A_Index])
    }
    tmp := CFG_FILE ".tmp"
    try {
        if !DirExist(CFG_DIR)
            DirCreate(CFG_DIR)
        f := FileOpen(tmp, "w", "UTF-16")
        f.Write(t)
        f.Close()
        FileMove(tmp, CFG_FILE, 1)
        return true
    } catch as e {
        Toast("Couldn't save settings: " e.Message, 3000)
        return false
    }
}

; The shipped wheels. The PACS tools wheel replaces a HOLD of the right
; button in PACS; a tap is still the ordinary right-click menu. The two
; most frequent commands (next/previous series) are the two easiest flicks,
; up and down.
SeedMenus() {
    out := []
    m := NewMenu("PACS tools", "RButton", "PACS", true, "native", 8)
    m.slots := [
        NewSlot("Next series", "keys", "{F8}", "▶", "Blue"),
        NewSlot("Ruler", "keys", "r", "↔", "Teal"),
        NewSlot("ROI", "keys", "+r", "◯", "Teal"),
        NewSlot("Magnifying glass", "keys", "y", "⌕", "Purple"),
        NewSlot("Prev series", "keys", "{F7}", "◀", "Blue"),
        NewSlot("Key image", "keys", "{Space}", "★", "Amber"),
        NewSlot("Window presets", "menu", "Window presets", "◐", "Amber"),
        NewSlot("More", "menu", "PACS more", "☰", "Grey")]
    out.Push(m)

    p := NewMenu("Window presets", "XButton2", "PACS", true, "toggle", 9)
    names := ["Soft tissue", "Bone", "Brain", "C-spine soft tissue", "CTA",
              "Infarct", "Liver", "Lung", "Lung wide"]
    p.slots := []
    for i, nm in names
        p.slots.Push(NewSlot(nm, "keys", String(i), String(i), "Amber"))
    out.Push(p)

    ; Items that have no shortcut are reached through the right-click menu
    ; itself: the path is the menu text, submenus separated by ">". A path
    ; that ends on a submenu opens it and leaves it open for you.
    mo := NewMenu("PACS more", "", "", true, "native", 8)
    mo.slots := [
        NewSlot("Scout lines", "keys", "{F11}", "☰", "Teal"),
        NewSlot("Measurements", "rclick", "Measurements", "↕", "Teal"),
        NewSlot("Localizer", "keys", "{F12}", "⌖", "Teal"),
        NewSlot("Flip / rotate", "rclick", "Flip/Rotate/Sort/Split", "⟳", "Purple"),
        NewSlot("Dictate this exam", "rclick", "PowerScribe: Dictate this exam",
            "●", "Red"),
        NewSlot("Unlink all", "rclick", "Unlink All", "✕", "Grey"),
        NewSlot("Annotations", "rclick", "Annotations", "✎", "Purple"),
        NewSlot("Zoom presets", "rclick", "Zoom Presets", "⊕", "Purple")]
    out.Push(mo)

    ps := NewMenu("PowerScribe", "XButton1", "PowerScribe", true, "native", 4)
    ps.slots := [
        NewSlot("Dictate", "keys", "{F4}", "●", "Red", "ps"),
        NewSlot("Next field", "keys", "{Tab}", "⇥", "Blue", "ps"),
        NewSlot("", "none"),
        NewSlot("Prev field", "keys", "+{Tab}", "⇤", "Blue", "ps")]
    out.Push(ps)
    return out
}

; ── §4  TEXT HELPERS ────────────────────────────────────────────────────────

IsMouseKey(k) => RegExMatch(k, "i)^(L|R|M|X)Button") ? true : false

; "^Space" -> "Space". A lone modifier symbol is its own key.
KeyOf(trig) {
    k := RegExReplace(trig, "^[\^!+#<>*~$]+(?=.)", "")
    return k
}

; A Send string as words: "^+r" -> "Ctrl+Shift+R", "{F8}" -> "F8".
KeysText(k) {
    if (k = "")
        return ""
    if !RegExMatch(k, "^([\^!+#]*)(\{[^{}]+\}|[^{}])$", &mm)
        return k
    out := ""
    if InStr(mm[1], "^")
        out .= "Ctrl+"
    if InStr(mm[1], "!")
        out .= "Alt+"
    if InStr(mm[1], "+")
        out .= "Shift+"
    if InStr(mm[1], "#")
        out .= "Win+"
    key := mm[2]
    if (SubStr(key, 1, 1) = "{")
        key := SubStr(key, 2, -1)
    return out (StrLen(key) = 1 ? StrUpper(key) : key)
}

; Hotkey name -> Send string: "^Space" -> "^{Space}".
HotkeyToSend(t) {
    if !RegExMatch(t, "^([\^!+#]*)(.+)$", &mm)
        return t
    return mm[1] (StrLen(mm[2]) = 1 ? mm[2] : "{" mm[2] "}")
}

; Send string -> hotkey name: "^{Space}" -> "^Space".
SendToHotkey(k) {
    if !RegExMatch(k, "^([\^!+#]*)(\{[^{}]+\}|[^{}])$", &mm)
        return ""
    key := mm[2]
    if (SubStr(key, 1, 1) = "{")
        key := SubStr(key, 2, -1)
    return mm[1] key
}

TriggerName(t) {
    for p in TRIGGERS
        if (p[1] = t)
            return p[2]
    return "Key " KeysText(HotkeyToSend(t))
}

ProgramsName(p) {
    if (p = "")
        return "every program"
    return p
}

Describe(s) {
    switch s.type {
        case "keys":   return KeysText(s.value)
        case "text":   return "types “" SubStr(StrReplace(s.value, "`n", " "), 1, 24) "”"
        case "menu":   return s.value
        case "run":    return "opens " RegExReplace(s.value, "^.*[\\/](?=.)", "")
        case "rclick": return "menu › " s.value
        case "toggle": return "opens this wheel"
        case "native": return "normal job"
    }
    return "empty"
}

SlotTitle(s) => (s.label != "") ? s.label : Describe(s)

IconOf(s) {
    if (s.icon != "")
        return s.icon
    return (s.label != "") ? StrUpper(SubStr(s.label, 1, 1)) : "•"
}

PillText(s) => SlotTitle(s) ((s.type = "menu") ? "  ›" : "")

SlotColor(s) => COLORS.Has(s.color) ? COLORS[s.color] : COLORS["Blue"]

Place(n, i) {
    if (n = 4)
        return DIR4[i]
    if (n = 8)
        return DIR8[i]
    if (n = 9)
        return "Number " i
    h := Round((i - 1) * 12 / n)
    return (h = 0 ? 12 : h) " o'clock"
}

; ── §5  GEOMETRY ────────────────────────────────────────────────────────────

ATan2(y, x) {
    static PI := 3.141592653589793
    if (x > 0)
        return ATan(y / x)
    if (x < 0)
        return ATan(y / x) + (y >= 0 ? PI : -PI)
    return (y > 0) ? PI / 2 : ((y < 0) ? -PI / 2 : 0)
}

; Degrees clockwise from north for a screen-space offset.
Bearing(dx, dy) => Mod(ATan2(dx, -dy) * 57.29577951308232 + 360, 360)

; Slot 1 points north, then clockwise; each slot owns its whole sector.
SlotAt(dx, dy, n) => Mod(Round(Bearing(dx, dy) / (360 / n)), n) + 1

WheelScale() {
    static sizes := Map("Small", 0.85, "Medium", 1.0, "Large", 1.2)
    k := sizes.Has(Conf["Size"]) ? sizes[Conf["Size"]] : 1.0
    return k * A_ScreenDPI / 96
}

; Everything about a ring's layout at scale s, measured once and cached.
Geom(m, s) {
    static cache := Map()
    key := Stamp "|" m.name "|" Round(s * 100)
    if cache.Has(key)
        return cache[key]
    if (cache.Count > 64)
        cache.Clear()
    n := m.count
    g := {n: n, s: s, step: 360 / n}
    g.itemR := 24 * s
    g.r := Max(92, n * 10.5) * s
    g.hubR := 30 * s
    g.bgR := g.r + g.itemR * 1.15 + 6 * s
    g.pillH := 22 * s
    g.labelMax := 170 * s
    mw := g.pillH
    loop n {
        sl := m.slots[A_Index]
        if (sl.type != "none")
            mw := Max(mw, Min(g.labelMax, MeasureW(PillText(sl), 12 * s, true) + 16 * s))
    }
    g.half := Ceil(g.bgR + 4 * s + mw + 4 * s)
    cache[key] := g
    return g
}

MonitorAt(x, y) {
    loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (x >= l && x < r && y >= t && y < b)
            return {l: l, t: t, r: r, b: b}
    }
    MonitorGet(MonitorGetPrimary(), &l, &t, &r, &b)
    return {l: l, t: t, r: r, b: b}
}

; Keep an open-and-read wheel on screen. A flicked (hold) root ring is never
; moved: the direction you push has to be the slice you get.
ClampAnchor(R) {
    mon := MonitorAt(R.ax, R.ay)
    mg := R.g.bgR + 4
    R.ax := Round(Min(Max(R.ax, mon.l + mg), mon.r - mg))
    R.ay := Round(Min(Max(R.ay, mon.t + mg), mon.b - mg))
}

; ── §6  GDI+ DRAWING ────────────────────────────────────────────────────────

GdipStart() {
    static token := 0
    if token
        return
    DllCall("LoadLibrary", "str", "gdiplus", "ptr")
    si := Buffer(24, 0)
    NumPut("uint", 1, si)
    DllCall("gdiplus\GdiplusStartup", "ptr*", &token, "ptr", si, "ptr", 0)
}

GfxSetup(gfx) {
    DllCall("gdiplus\GdipSetSmoothingMode", "ptr", gfx, "int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", gfx, "int", 4)
}

Scratch() {
    static gfx := 0, bmp := 0
    if !gfx {
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", 4, "int", 4, "int", 0,
            "int", 0xE200B, "ptr", 0, "ptr*", &bmp)
        DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", bmp, "ptr*", &gfx)
        GfxSetup(gfx)
    }
    return gfx
}

GetFont(face, px, bold) {
    static fonts := Map(), fams := Map()
    key := face "|" Round(px, 1) "|" (bold ? 1 : 0)
    if fonts.Has(key)
        return fonts[key]
    if !fams.Has(face) {
        fam := 0
        if DllCall("gdiplus\GdipCreateFontFamilyFromName", "wstr", face,
            "ptr", 0, "ptr*", &fam) != 0
            DllCall("gdiplus\GdipCreateFontFamilyFromName", "wstr", "Arial",
                "ptr", 0, "ptr*", &fam)
        fams[face] := fam
    }
    f := 0
    DllCall("gdiplus\GdipCreateFont", "ptr", fams[face], "float", px,
        "int", bold ? 1 : 0, "int", 2, "ptr*", &f)
    fonts[key] := f
    return f
}

GetFmt(align) {
    static cache := Map()
    if cache.Has(align)
        return cache[align]
    f := 0
    DllCall("gdiplus\GdipCreateStringFormat", "int", 0x1000, "int", 0, "ptr*", &f)
    DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", f, "int", align)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "ptr", f, "int", 1)
    DllCall("gdiplus\GdipSetStringFormatTrimming", "ptr", f, "int", 3)
    cache[align] := f
    return f
}

MeasureW(str, px, bold := false, face := "Segoe UI") {
    static cache := Map()
    key := face "|" Round(px, 1) "|" (bold ? 1 : 0) "|" str
    if cache.Has(key)
        return cache[key]
    if (cache.Count > 4000)
        cache.Clear()
    rc := Buffer(16, 0)
    NumPut("float", 0, "float", 0, "float", 4000, "float", 400, rc)
    out := Buffer(16, 0)
    DllCall("gdiplus\GdipMeasureString", "ptr", Scratch(), "wstr", str, "int", -1,
        "ptr", GetFont(face, px, bold), "ptr", rc, "ptr", GetFmt(0), "ptr", out,
        "ptr", 0, "ptr", 0)
    w := NumGet(out, 8, "float")
    cache[key] := w
    return w
}

FillCircle(gfx, argb, cx, cy, r) {
    b := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &b)
    DllCall("gdiplus\GdipFillEllipse", "ptr", gfx, "ptr", b, "float", cx - r,
        "float", cy - r, "float", 2 * r, "float", 2 * r)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", b)
}

RingCircle(gfx, argb, cx, cy, r, w := 1) {
    p := 0
    DllCall("gdiplus\GdipCreatePen1", "uint", argb, "float", w, "int", 2, "ptr*", &p)
    DllCall("gdiplus\GdipDrawEllipse", "ptr", gfx, "ptr", p, "float", cx - r,
        "float", cy - r, "float", 2 * r, "float", 2 * r)
    DllCall("gdiplus\GdipDeletePen", "ptr", p)
}

; Angles here are GDI+ angles: degrees clockwise from 3 o'clock.
FillPieDeg(gfx, argb, cx, cy, r, start, sweep) {
    b := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &b)
    DllCall("gdiplus\GdipFillPie", "ptr", gfx, "ptr", b, "float", cx - r,
        "float", cy - r, "float", 2 * r, "float", 2 * r, "float", start,
        "float", sweep)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", b)
}

ArcDeg(gfx, argb, cx, cy, r, start, sweep, w) {
    p := 0
    DllCall("gdiplus\GdipCreatePen1", "uint", argb, "float", w, "int", 2, "ptr*", &p)
    DllCall("gdiplus\GdipSetPenStartCap", "ptr", p, "int", 2)
    DllCall("gdiplus\GdipSetPenEndCap", "ptr", p, "int", 2)
    DllCall("gdiplus\GdipDrawArc", "ptr", gfx, "ptr", p, "float", cx - r,
        "float", cy - r, "float", 2 * r, "float", 2 * r, "float", start,
        "float", sweep)
    DllCall("gdiplus\GdipDeletePen", "ptr", p)
}

Pill(gfx, argb, x, y, w, h) {
    w := Max(w, h)
    p := 0, b := 0
    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &p)
    DllCall("gdiplus\GdipAddPathArc", "ptr", p, "float", x, "float", y,
        "float", h, "float", h, "float", 90, "float", 180)
    DllCall("gdiplus\GdipAddPathArc", "ptr", p, "float", x + w - h, "float", y,
        "float", h, "float", h, "float", 270, "float", 180)
    DllCall("gdiplus\GdipClosePathFigure", "ptr", p)
    DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &b)
    DllCall("gdiplus\GdipFillPath", "ptr", gfx, "ptr", b, "ptr", p)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", b)
    DllCall("gdiplus\GdipDeletePath", "ptr", p)
}

Text(gfx, str, x, y, w, h, argb, px, bold := false, align := 1, face := "Segoe UI") {
    if (str = "")
        return
    rc := Buffer(16)
    NumPut("float", x, "float", y, "float", w, "float", h, rc)
    b := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &b)
    DllCall("gdiplus\GdipDrawString", "ptr", gfx, "wstr", str, "int", -1,
        "ptr", GetFont(face, px, bold), "ptr", rc, "ptr", GetFmt(align), "ptr", b)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", b)
}

; ── §7  THE WHEEL PICTURE ───────────────────────────────────────────────────
;
; DrawBase paints everything that does not depend on the selection; DrawSel
; paints one highlighted slice over it. The live wheel caches DrawBase per
; ring, so moving between slices costs one blit and a handful of shapes.

ItemXY(g, cx, cy, i, radius) {
    a := (i - 1) * g.step * 0.017453292519943295
    return {x: cx + radius * Sin(a), y: cy - radius * Cos(a), sx: Sin(a), cy: Cos(a)}
}

DrawLabel(gfx, g, cx, cy, i, txt, sel, col) {
    s := g.s
    fs := 12 * s
    w := Min(g.labelMax, MeasureW(txt, fs, true) + 16 * s)
    h := g.pillH
    p := ItemXY(g, cx, cy, i, g.bgR + 4 * s)
    if (p.sx > 0.3)
        x := p.x, y := p.y - h / 2
    else if (p.sx < -0.3)
        x := p.x - w, y := p.y - h / 2
    else {
        x := p.x - w / 2
        y := (p.cy > 0) ? p.y - h : p.y
    }
    Pill(gfx, sel ? col : 0xE6161920, x, y, w, h)
    Text(gfx, txt, x + 8 * s, y, w - 16 * s, h, sel ? 0xFFFFFFFF : 0xFFE6E8EB,
        fs, sel)
}

DrawItem(gfx, g, cx, cy, i, sl, sel, editor) {
    s := g.s
    p := ItemXY(g, cx, cy, i, g.r)
    if (sl.type = "none") {
        if editor {
            RingCircle(gfx, sel ? 0xFFFFFFFF : 0x50FFFFFF, p.x, p.y, g.itemR * 0.8,
                sel ? 2 * s : 1)
            Text(gfx, "+", p.x - g.itemR, p.y - g.itemR, 2 * g.itemR, 2 * g.itemR,
                0x80FFFFFF, 16 * s)
        } else if sel {
            RingCircle(gfx, 0xB0FFFFFF, p.x, p.y, g.itemR * 0.6, 2 * s)
        } else
            FillCircle(gfx, 0x40FFFFFF, p.x, p.y, 3 * s)
        return
    }
    col := SlotColor(sl)
    rr := g.itemR * (sel ? 1.15 : 1.0)
    FillCircle(gfx, sel ? col : 0xFF252932, p.x, p.y, rr)
    RingCircle(gfx, sel ? 0xFFFFFFFF : col, p.x, p.y, rr, 2 * s)
    ic := IconOf(sl)
    big := StrLen(ic) <= 2
    Text(gfx, ic, p.x - rr, p.y - rr, 2 * rr, 2 * rr, 0xFFFFFFFF,
        (big ? 17 : 10.5) * s * (sel ? 1.1 : 1), !big, 1,
        big ? "Segoe UI Symbol" : "Segoe UI")
    if (sl.type = "menu") {
        q := ItemXY(g, cx, cy, i, g.r + rr + 5 * s)
        FillCircle(gfx, col, q.x, q.y, 3 * s)
    }
    DrawLabel(gfx, g, cx, cy, i, PillText(sl), sel, col)
}

DrawBase(gfx, cx, cy, g, m, editor := false) {
    s := g.s
    FillCircle(gfx, 0xE6161920, cx, cy, g.bgR)
    RingCircle(gfx, 0x40FFFFFF, cx, cy, g.bgR, 1)
    FillCircle(gfx, 0xFF0F1115, cx, cy, g.hubR)
    RingCircle(gfx, 0x50FFFFFF, cx, cy, g.hubR, 1)
    if editor
        Text(gfx, "TAP", cx - g.hubR, cy - g.hubR, 2 * g.hubR, 2 * g.hubR,
            0xC0FFFFFF, 11 * s, true)
    else
        Text(gfx, "✕", cx - g.hubR, cy - g.hubR, 2 * g.hubR, 2 * g.hubR,
            0x80FFFFFF, 15 * s, false, 1, "Segoe UI Symbol")
    capW := 2 * (g.r - g.itemR) - 16 * s
    Text(gfx, m.name, cx - capW / 2, cy + g.hubR + 3 * s, capW, 16 * s,
        0xA0FFFFFF, 11 * s)
    loop g.n
        DrawItem(gfx, g, cx, cy, A_Index, m.slots[A_Index], false, editor)
}

DrawSel(gfx, cx, cy, g, m, i, editor := false) {
    s := g.s
    sl := m.slots[i]
    col := (sl.type = "none") ? 0xFF8B93A1 : SlotColor(sl)
    a := (i - 1) * g.step
    FillPieDeg(gfx, (col & 0xFFFFFF) | 0x38000000, cx, cy, g.bgR - 1,
        a - 90 - g.step / 2, g.step)
    FillCircle(gfx, 0xFF0F1115, cx, cy, g.hubR)
    RingCircle(gfx, 0x50FFFFFF, cx, cy, g.hubR, 1)
    if editor
        Text(gfx, "TAP", cx - g.hubR, cy - g.hubR, 2 * g.hubR, 2 * g.hubR,
            0xC0FFFFFF, 11 * s, true)
    else
        ArcDeg(gfx, col, cx, cy, g.hubR + 5 * s, a - 90 - 20, 40, 4 * s)
    DrawItem(gfx, g, cx, cy, i, sl, true, editor)
}

; The per-ring cache. A bitmap per (menu, scale, config version).
class RingCache {
    static cache := Map()

    static Get(m, g) {
        key := Stamp "|" m.name "|" Round(g.s * 100)
        if this.cache.Has(key)
            return this.cache[key]
        size := Ceil(g.half * 2)
        bmp := 0, gfx := 0
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", size, "int", size,
            "int", 0, "int", 0xE200B, "ptr", 0, "ptr*", &bmp)
        DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", bmp, "ptr*", &gfx)
        GfxSetup(gfx)
        DllCall("gdiplus\GdipGraphicsClear", "ptr", gfx, "uint", 0)
        DrawBase(gfx, size / 2, size / 2, g, m)
        DllCall("gdiplus\GdipDeleteGraphics", "ptr", gfx)
        this.cache[key] := bmp
        return bmp
    }

    static Clear() {
        for k, bmp in this.cache
            DllCall("gdiplus\GdipDisposeImage", "ptr", bmp)
        this.cache := Map()
    }
}

; The on-screen wheel: one layered, click-through, never-activated window,
; created once and reused. UpdateLayeredWindow with per-pixel alpha.
class Overlay {
    static gui := 0
    static hwnd := 0
    static w := 0
    static h := 0
    static hdc := 0
    static hbm := 0
    static obm := 0
    static gfx := 0
    static visible := false

    static Init() {
        this.gui := Gui("-Caption +E0x80000 +E0x20 +E0x08000000 +AlwaysOnTop"
            . " +ToolWindow -DPIScale")
        this.hwnd := this.gui.Hwnd
    }

    static Ensure(w, h) {
        if (this.hdc && w <= this.w && h <= this.h)
            return
        w := Max(w, this.w), h := Max(h, this.h)
        this.Free()
        bi := Buffer(40, 0)
        NumPut("uint", 40, bi, 0)
        NumPut("int", w, bi, 4)
        NumPut("int", -h, bi, 8)
        NumPut("ushort", 1, bi, 12)
        NumPut("ushort", 32, bi, 14)
        this.hdc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
        bits := 0
        this.hbm := DllCall("CreateDIBSection", "ptr", this.hdc, "ptr", bi,
            "uint", 0, "ptr*", &bits, "ptr", 0, "uint", 0, "ptr")
        this.obm := DllCall("SelectObject", "ptr", this.hdc, "ptr", this.hbm, "ptr")
        gfx := 0
        DllCall("gdiplus\GdipCreateFromHDC", "ptr", this.hdc, "ptr*", &gfx)
        GfxSetup(gfx)
        this.gfx := gfx, this.w := w, this.h := h
    }

    static Free() {
        if this.gfx
            DllCall("gdiplus\GdipDeleteGraphics", "ptr", this.gfx)
        if this.hdc {
            DllCall("SelectObject", "ptr", this.hdc, "ptr", this.obm)
            DllCall("DeleteObject", "ptr", this.hbm)
            DllCall("DeleteDC", "ptr", this.hdc)
        }
        this.gfx := 0, this.hdc := 0, this.hbm := 0, this.obm := 0
        this.w := 0, this.h := 0
    }

    ; Show the top-left size x size of the surface at (x, y).
    static Update(x, y, size, alpha := 255) {
        ; new pixels first, then show: showing first can flash the previous
        ; wheel at the new place for a frame
        pt := Buffer(8), sz := Buffer(8), src := Buffer(8, 0)
        NumPut("int", x, "int", y, pt)
        NumPut("int", size, "int", size, sz)
        DllCall("UpdateLayeredWindow", "ptr", this.hwnd, "ptr", 0, "ptr", pt,
            "ptr", sz, "ptr", this.hdc, "ptr", src, "uint", 0,
            "uint*", (alpha << 16) | (1 << 24), "uint", 2)
        if !this.visible {
            this.gui.Show("NA x" x " y" y " w" size " h" size)
            this.visible := true
        }
    }

    static Hide() {
        if this.visible {
            this.gui.Hide()
            this.visible := false
        }
    }
}

Paint() {
    Critical "On"
    R := Cur
    if !IsObject(R)
        return
    g := R.g
    size := Ceil(g.half * 2)
    Overlay.Ensure(size, size)
    gfx := Overlay.gfx
    DllCall("gdiplus\GdipSetClipRectI", "ptr", gfx, "int", 0, "int", 0,
        "int", size, "int", size, "int", 0)
    DllCall("gdiplus\GdipGraphicsClear", "ptr", gfx, "uint", 0)
    DllCall("gdiplus\GdipDrawImageRectI", "ptr", gfx, "ptr", RingCache.Get(R.menu, g),
        "int", 0, "int", 0, "int", size, "int", size)
    c := size / 2
    if (R.sel > 0)
        DrawSel(gfx, c, c, g, R.menu, R.sel)
    capW := 2 * (g.r - g.itemR) - 16 * g.s
    if R.practice
        Text(gfx, "PRACTICE", c - capW / 2, c - g.hubR - 19 * g.s, capW, 16 * g.s,
            0xFFF5B942, 11 * g.s, true)
    else if (R.mode = "toggle")
        Text(gfx, "click to choose", c - capW / 2, c - g.hubR - 19 * g.s, capW,
            16 * g.s, 0xA0FFFFFF, 10.5 * g.s)
    Overlay.Update(Round(R.ax - c), Round(R.ay - c), size, R.alpha)
}

; Warm the caches shortly after start so the first wheel is as fast as the
; hundredth: fonts, label measurements, ring bitmaps, the overlay surface.
PreWarm() {
    s := WheelScale()
    big := 0
    for m in Menus {
        if (LiveCount(m) = 0)
            continue
        g := Geom(m, s)
        RingCache.Get(m, g)
        big := Max(big, Ceil(g.half * 2))
    }
    if big
        Overlay.Ensure(big, big)
}

; ── §8  THE ENGINE ──────────────────────────────────────────────────────────

HiRes(on) {
    global HiResOn
    if (on && !HiResOn) {
        DllCall("winmm\timeBeginPeriod", "uint", 1)
        HiResOn := 1
    } else if (!on && HiResOn) {
        DllCall("winmm\timeEndPeriod", "uint", 1)
        HiResOn := 0
    }
}

PidOf(hwnd) {
    pid := 0
    if hwnd
        try pid := WinGetPID("ahk_id " hwnd)
    return pid
}

; ── trigger hotkeys ──────────────────────────────────────────────────────

; The gate decides, per press, whether the button is ours right now. Anything
; it says no to stays completely native.
TrigGate(hk) {
    ; a release is checked BEFORE pause: a press that was blocked must never
    ; have its release reach the program (a stray context menu, or "back")
    if RegExMatch(hk, "i) up$") {
        key := SubStr(hk, 2, -3)
        return Held.Has(key) || Swallow.Has(key)
    }
    if Paused
        return false
    trig := SubStr(hk, 2)
    key := KeyOf(trig)
    ; While a wheel is open, left/right/middle belong to the wheel (choose,
    ; back, cancel: ClickGate) unless this press is the open wheel's own
    ; top-level trigger. Hotkey variants made earlier win, so this has to be
    ; decided here rather than left to ClickGate.
    if (IsObject(Cur) && IsClickKey(key))
        return TrigOwnsClick(key)
    if (IsObject(Cur) && Cur.key = key)
        return true
    if (Held.Has(key) || EatRepeat.Has(key))
        return true
    if (RmOwned.Has(key) || !IsObject(MenuFor(trig))) {
        ; a declined click is native, so its release must be too: a swallow
        ; left over from a lost release must not eat it
        if (IsMouseKey(key) && Swallow.Has(key))
            Swallow.Delete(key)
        return false                         ; RadMapper's button, or no wheel
    }
    return true
}

IsClickKey(k) => (k = "LButton" || k = "RButton" || k = "MButton")

TrigOwnsClick(key) {
    R := Cur
    return Held.Has(key) || (IsObject(R) && R.key = key && R.depth = 1)
}

RegisterHotkeys() {
    global HkList
    HotIf(TrigGate)
    try {
        for name in HkList
            try Hotkey(name, "Off")
        HkList := []
        down := Map(), up := Map()
        down.CaseSense := "Off", up.CaseSense := "Off"
        for m in Menus {
            t := m.trigger
            if (t = "" || down.Has(t))
                continue
            down[t] := 1
            k := KeyOf(t)
            try {
                Hotkey("*" t, TrigDown, "On")
                HkList.Push("*" t)
                if !up.Has(k) {
                    Hotkey("*" k " up", TrigUp, "On")
                    HkList.Push("*" k " up")
                    up[k] := 1
                }
            } catch as e {
                Toast("Can't use “" t "” as a menu button: " e.Message, 4000)
            }
        }
    } finally {
        HotIf()
    }
}

TrigDown(hk) {
    trig := SubStr(hk, 2)
    key := KeyOf(trig)
    R := Cur
    if EatRepeat.Has(key) {
        if (A_TickCount - EatRepeat[key] < 1000) {
            EatRepeat[key] := A_TickCount
            return
        }
        EatRepeat.Delete(key)
    }
    if (IsObject(R) && R.mode = "toggle") {
        if (R.key = key) {                   ; tapped again: choose
            Swallow[key] := true
            if !IsMouseKey(key)              ; a key held down past here
                EatRepeat[key] := A_TickCount    ; must not reopen the wheel
            Choose(R.sel)
            return
        }
        CloseMenu()
    }
    ; keyboard auto-repeat: repeats arrive every ~30 ms while held, so a
    ; press after a quiet second is a new press (a lost release can't
    ; leave the key dead)
    if (Held.Has(key) && !IsMouseKey(key) && A_TickCount - Held[key].last < 1000) {
        Held[key].last := A_TickCount
        return
    }
    if Swallow.Has(key)
        Swallow.Delete(key)
    win := 0
    m := MenuFor(trig, &win)
    if !IsObject(m) {
        if Held.Has(key)                     ; a stale press (its release
            Held.Delete(key)                 ;   was lost) must not linger
        Swallow[key] := true                 ; the gate changed its mind: a
        SendNative(key)                      ;   whole native click, and the
        return                               ;   real release is swallowed
    }
    MouseGetPos(&x, &y)
    Held[key] := {menu: m, trig: trig, x: x, y: y, win: win, pass: false,
                  opened: false, t0: A_TickCount, last: A_TickCount}
    if (m.hold && LiveCount(m))
        Held[key].opened := OpenMenu(m, "hold", key, false, win)
}

TrigUp(hk) {
    key := SubStr(hk, 2, -3)
    if EatRepeat.Has(key)
        EatRepeat.Delete(key)
    if Swallow.Has(key) {
        Swallow.Delete(key)
        return
    }
    ReleaseKey(key)
}

ReleaseKey(key) {
    if !Held.Has(key)
        return
    h := Held.Delete(key)
    if h.pass {                              ; it became an ordinary drag
        Send("{Blind}{" key " up}")
        return
    }
    R := Cur
    if (IsObject(R) && R.key = key && R.mode = "hold") {
        if (R.sel = 0) {
            tap := R.depth = 1
                && (!R.shown || A_TickCount - R.t0 < Conf["TapMs"])
            CloseMenu()
            if tap
                DoTap(h, key)
            return
        }
        Choose(R.sel)
        return
    }
    ; a wheel that never opened (tap-only, or an empty one) is a tap
    if (!h.menu.hold || !h.opened)
        DoTap(h, key)
}

DoTap(h, key) {
    t := h.menu.tap
    switch t.type {
        case "native":
            SendNative(key)
        case "none":
        case "toggle":
            OpenMenu(h.menu, "toggle", key, false, h.win)
        case "menu":
            sub := FindMenu(t.value)
            if IsObject(sub)
                OpenMenu(sub, "toggle", key, false, h.win)
            else
                Toast("No wheel named “" t.value "”")
        default:
            SetTimer(FireSlot.Bind(t, h.win, h.x, h.y), -1)
    }
}

SendNative(key) {
    if (key = "CapsLock") {
        SetCapsLockState(GetKeyState("CapsLock", "T") ? "Off" : "On")
        return
    }
    Send("{Blind}{" key "}")
}

; ── open / tick / choose / close ─────────────────────────────────────────

OpenMenu(m, mode, key := "", practice := false, win := 0) {
    global Cur
    if IsObject(Cur)
        CloseMenu()
    if !IsObject(m)
        return false
    if (LiveCount(m) = 0) {
        Toast("The “" m.name "” wheel is empty. Add commands in the RadWheel window.")
        return false
    }
    MouseGetPos(&x, &y)
    now := A_TickCount
    fg := WinExist("A")
    R := {menu: m, mode: mode, key: key, practice: practice,
          ax: x, ay: y, rootX: x, rootY: y, lx: x, ly: y,
          t0: now, openedAt: now, lastMove: now, restAt: now,
          sel: 0, shown: false, alpha: 120, depth: 1, stack: [], upMiss: 0,
          phys: (key != "" && GetKeyState(key, "P")),
          win: win ? win : fg, fg: fg, fgPid: PidOf(fg),
          g: Geom(m, WheelScale())}
    if (mode = "toggle") {
        R.shown := true
        R.alpha := 255
        ClampAnchor(R)
    }
    Cur := R
    HiRes(true)
    ClicksOn()
    SetTimer(Tick, 10)
    if R.shown
        Paint()
    return true
}

CloseMenu() {
    global Cur
    Cur := 0
    SetTimer(Tick, 0)
    Overlay.Hide()
    HiRes(false)
    ClicksOff()
}

; True when the foreground moved to another program while the wheel was up.
FocusMoved(R) {
    fg := WinExist("A")
    if (fg = R.fg || !R.fg)
        return false
    pid := PidOf(fg)
    return pid != R.fgPid && pid != DllCall("GetCurrentProcessId", "uint")
}

Tick() {
    R := Cur
    if !IsObject(R) {
        SetTimer(Tick, 0)
        return
    }
    now := A_TickCount
    if ((Paused && !R.practice) || FocusMoved(R)) {
        CloseMenu()
        return
    }
    if (R.mode = "hold") {
        ; the release is the real commit; this is the floor under a lost one
        if (R.phys && !GetKeyState(R.key, "P")) {
            R.upMiss += 1
            if (R.upMiss >= 3) {
                Swallow[R.key] := true
                ReleaseKey(R.key)
                return
            }
        } else
            R.upMiss := 0
        if (now - R.openedAt > 30000) {
            CloseMenu()
            return
        }
    } else if (now - R.lastMove > Conf["ToggleTimeout"] * 1000) {
        CloseMenu()
        return
    }
    MouseGetPos(&mx, &my)
    if (Abs(mx - R.lx) + Abs(my - R.ly) > 2) {
        R.lx := mx, R.ly := my
        R.lastMove := now
    }
    g := R.g
    dx := mx - R.ax, dy := my - R.ay
    dist := Sqrt(dx * dx + dy * dy)
    ; "Drag as normal": moving before the wheel is up hands the press back
    if (R.mode = "hold" && !R.shown && R.depth = 1 && R.menu.move = "drag"
        && IsMouseKey(R.key) && dist > 6 * g.s) {
        PassThrough(R)
        return
    }
    sel := (dist < g.hubR) ? 0 : SlotAt(dx, dy, g.n)
    dirty := false
    if (sel != R.sel) {
        R.sel := sel
        R.restAt := now
        dirty := true
    }
    if (!R.shown && now - R.t0 >= Conf["ShowDelay"]) {
        R.shown := true
        dirty := true
    }
    ; a submenu opens when the hand crosses the ring on it, or rests on it
    if (R.mode = "hold" && sel > 0 && R.menu.slots[sel].type = "menu"
        && (dist >= g.r + g.itemR || now - R.restAt >= Conf["SubmenuDelay"])) {
        EnterSub(R, sel, mx, my)
        return
    }
    if R.shown {
        if (R.alpha < 255) {
            R.alpha := Min(255, R.alpha + 90)
            dirty := true
        }
        if dirty
            Paint()
    }
}

EnterSub(R, i, x, y) {
    name := R.menu.slots[i].value
    sub := FindMenu(name)
    if (!IsObject(sub) || LiveCount(sub) = 0 || R.depth >= 6) {
        CloseMenu()
        Toast("The wheel “" name "” is missing or empty")
        return false
    }
    R.stack.Push({menu: R.menu, ax: R.ax, ay: R.ay, g: R.g})
    R.menu := sub
    R.g := Geom(sub, WheelScale())
    R.ax := x, R.ay := y
    ClampAnchor(R)
    R.sel := 0
    R.restAt := A_TickCount
    R.lastMove := A_TickCount
    R.shown := true
    R.alpha := 255
    R.depth += 1
    Paint()
    return true
}

Back(R) {
    if (R.stack.Length = 0) {
        CloseMenu()
        return
    }
    p := R.stack.Pop()
    R.menu := p.menu, R.ax := p.ax, R.ay := p.ay, R.g := p.g
    R.depth -= 1
    R.sel := 0
    R.lastMove := A_TickCount
    Paint()
}

Choose(sel) {
    R := Cur
    if !IsObject(R)
        return
    if (sel < 1 || sel > R.menu.count) {
        CloseMenu()
        return
    }
    sl := R.menu.slots[sel]
    if (sl.type = "menu") {
        ; let go (or click) on a submenu: it opens and stays open
        MouseGetPos(&mx, &my)
        if EnterSub(R, sel, mx, my)
            R.mode := "toggle"
        return
    }
    CloseMenu()
    if (sl.type = "none")
        return
    if R.practice {
        Toast("Practice: would run “" SlotTitle(sl) "”")
        return
    }
    if (Conf["ReturnPointer"] && sl.type != "rclick")
        DllCall("SetCursorPos", "int", R.rootX, "int", R.rootY)
    SetTimer(FireSlot.Bind(sl, R.win, R.rootX, R.rootY), -1)
}

; The press started moving before the wheel showed, on a "drag as normal"
; menu: give the application the button down where it really happened, then
; put the pointer back where the hand is. The release goes out on the real
; release (ReleaseKey), with a watchdog under it.
PassThrough(R) {
    key := R.key, ax := R.ax, ay := R.ay
    CloseMenu()
    if !Held.Has(key)
        return
    Held[key].pass := true
    MouseGetPos(&mx, &my)
    DllCall("SetCursorPos", "int", ax, "int", ay)
    Send("{Blind}{" key " down}")
    DllCall("SetCursorPos", "int", mx, "int", my)
    SetTimer(PassWatch, 50)
}

PassWatch() {
    any := false
    for key, h in Held.Clone() {
        if !h.pass
            continue
        if GetKeyState(key, "P")
            any := true
        else {
            Held.Delete(key)
            Swallow[key] := true
            Send("{Blind}{" key " up}")
        }
    }
    if !any
        SetTimer(PassWatch, 0)
}

; ── while a wheel is open: clicks, Esc, digits ───────────────────────────

ClickGate(hk) {
    if RegExMatch(hk, "i) up$")
        return ClickSwallow.Has(SubStr(hk, 2, -3))
    b := SubStr(hk, 2)
    if !IsObject(Cur)
        return false
    return !TrigOwnsClick(b)                 ; the trigger handles itself
}

OpenGate(*) => IsObject(Cur)

ClicksOn() {
    global ClicksLive
    if ClicksLive
        return
    try {
        HotIf(ClickGate)
        for b in ["LButton", "RButton", "MButton"] {
            Hotkey("*" b, ClickDown, "On")
            Hotkey("*" b " up", ClickUp, "On")
        }
        HotIf(OpenGate)
        Hotkey("*Escape", EscHit, "On")
        loop 9
            Hotkey("*" A_Index, DigitHit, "On")
        ClicksLive := true
    } finally {
        HotIf()
    }
}

ClicksOff() {
    global ClicksLive
    if (!ClicksLive || ClickSwallow.Count)
        return                               ; a release is still owed
    try {
        HotIf(ClickGate)
        for b in ["LButton", "RButton", "MButton"] {
            Hotkey("*" b, "Off")
            Hotkey("*" b " up", "Off")
        }
        HotIf(OpenGate)
        Hotkey("*Escape", "Off")
        loop 9
            Hotkey("*" A_Index, "Off")
        ClicksLive := false
    } finally {
        HotIf()
    }
}

ClickDown(hk) {
    b := SubStr(hk, 2)
    ClickSwallow[b] := true
    R := Cur
    if !IsObject(R)
        return
    if (R.mode = "toggle") {
        if (b = "LButton") {
            Choose(R.sel)
            return
        }
        if (b = "RButton" && R.depth > 1) {
            Back(R)
            return
        }
    }
    CloseMenu()                              ; a click during a hold cancels
}

ClickUp(hk) {
    b := SubStr(hk, 2, -3)
    if ClickSwallow.Has(b)
        ClickSwallow.Delete(b)
    if !IsObject(Cur)
        ClicksOff()
}

EscHit(*) {
    R := Cur
    if (IsObject(R) && R.mode = "toggle" && R.depth > 1)
        Back(R)
    else
        CloseMenu()
}

DigitHit(hk) {
    n := Integer(SubStr(hk, 2))
    R := Cur
    if (IsObject(R) && n <= R.menu.count && R.menu.slots[n].type != "none")
        Choose(n)
}

; ── §9  DOING THE COMMAND ───────────────────────────────────────────────────

FireSlot(sl, win := 0, ax := 0, ay := 0, *) {
    if Paused
        return
    try {
        switch sl.type {
            case "keys":
                if (sl.value = "")
                    return
                Deliver(sl.target, sl.value, win)
            case "text":
                if (sl.value = "")
                    return
                Deliver(sl.target, "{Text}" sl.value, win)
            case "run":
                Run(sl.value)
            case "rclick":
                if !CtxRun(sl.value, ax, ay)
                    return
            case "menu":
                OpenMenu(FindMenu(sl.value), "toggle", "", false, win)
                return
            default:
                return
        }
        if Conf["Confirm"]
            Toast("✓ " SlotTitle(sl), 900)
    } catch as e {
        Toast("Couldn't run “" SlotTitle(sl) "”: " e.Message, 3000)
    }
}

; The keystroke itself is uninterruptible: a hotkey thread landing between
; the "+" and the "{Tab}" of "+{Tab}" would leave Shift logically down.
SendAtomic(keys) {
    Critical "On"
    try Send(keys)
    Critical "Off"
}

; A keystroke must never go out THROUGH a held mouse button (it would be a
; shift-click); wait for the hand, briefly.
WaitButtonsUp() {
    loop 75 {
        if !(GetKeyState("LButton", "P") || GetKeyState("RButton", "P")
            || GetKeyState("MButton", "P"))
            return
        Sleep(20)
    }
}

Deliver(kind, keys, win) {
    WaitButtonsUp()
    switch kind {
        case "", "front":
            ; the program under the pointer when the wheel opened; bring it
            ; forward only if it is not already (the common case costs nothing)
            if (win && !WinActive("ahk_id " win) && WinExist("ahk_id " win)) {
                try WinActivate("ahk_id " win)
                WinWaitActive("ahk_id " win, , 0.5)
            }
            SendAtomic(keys)
        case "ps":
            SendToApp(ProgramExes("PowerScribe"), "", keys, "PowerScribe")
        case "pacs":
            SendToApp(ProgramExes("PACS"), Conf["PacsViewerTitle"], keys, "PACS")
        default:
            SendToApp(ProgramExes(kind), "", keys, kind)
    }
}

; Activate by EXE (PowerScribe is multi-window; a specific hwnd is the
; classic "taskbar flashes, key goes nowhere" bug), send, return focus.
SendToApp(exes, prefer, keys, nice) {
    pref := [], all := []
    for e in exes
        if (prefer != "")
            pref.Push(prefer " ahk_exe " e)
    for c in pref
        all.Push(c)
    for e in exes
        all.Push("ahk_exe " e)
    for c in (pref.Length ? pref : all) {
        if WinActive(c) {
            SendAtomic(keys)
            return
        }
    }
    win := ""
    for c in all {
        if WinExist(c) {
            win := c
            break
        }
    }
    if (win = "") {
        Toast(nice " isn't running", 2000)
        return
    }
    prev := WinExist("A")
    try {
        if (WinGetMinMax(win) = -1)
            WinRestore(win)
    }
    try WinActivate(win)
    if !WinWaitActive(win, , 0.6) {
        try WinActivate(win)
        if !WinWaitActive(win, , 0.6) {
            Toast(nice " would not come to the front. Try again.", 2500)
            return
        }
    }
    Sleep(40)
    SendAtomic(keys)
    if prev {
        Sleep(Conf["ReturnDelay"])
        try WinActivate("ahk_id " prev)
    }
}

; ── §10  RIGHT-CLICK MENU COMMANDS ──────────────────────────────────────────
;
; "Pick an item from the right-click menu" reaches the commands a program
; only offers in its context menu (the PACS menu has many with no shortcut).
; RadWheel right-clicks where the wheel was opened, finds each item BY ITS
; TEXT through Windows accessibility (MSAA: works for Win32, WinForms and
; WPF menus), and clicks it. "Measurements > Ellipse" walks a submenu. A
; path that ends on a submenu opens it and leaves it open for you.
; Fallback for menus that cannot be read: "#3 > #2" presses Down/Right/Enter
; by position (separators are skipped when counting).

global IID_IAccessible := 0

AccFromWindow(hwnd) {
    global IID_IAccessible
    if !IID_IAccessible {
        IID_IAccessible := Buffer(16)
        DllCall("ole32\CLSIDFromString", "wstr",
            "{618736E0-3C3D-11CF-810C-00AA00389B71}", "ptr", IID_IAccessible)
    }
    pacc := 0
    if (DllCall("oleacc\AccessibleObjectFromWindow", "ptr", hwnd,
        "uint", 0xFFFFFFFC, "ptr", IID_IAccessible, "ptr*", &pacc) = 0 && pacc)
        return ComObjFromPtr(pacc)
    return 0
}

AccChildren(acc) {
    out := []
    cnt := 0
    try cnt := acc.accChildCount
    if (cnt < 1)
        return out
    sz := 8 + 2 * A_PtrSize
    buf := Buffer(cnt * sz, 0)
    got := 0
    hr := DllCall("oleacc\AccessibleChildren", "ptr", ComObjValue(acc),
        "int", 0, "int", cnt, "ptr", buf, "int*", &got)
    if (hr != 0 && hr != 1)
        return out
    loop got {
        off := (A_Index - 1) * sz
        vt := NumGet(buf, off, "ushort")
        if (vt = 9) {
            p := NumGet(buf, off + 8, "ptr")
            if p
                out.Push({acc: ComObjFromPtr(p), id: 0})
        } else if (vt = 3)
            out.Push({acc: acc, id: NumGet(buf, off + 8, "int")})
    }
    return out
}

AccWalk(acc, items, depth) {
    for c in AccChildren(acc) {
        role := 0, name := "", st := 0
        try role := c.acc.accRole[c.id]
        try name := c.acc.accName[c.id]
        try st := c.acc.accState[c.id]
        if (role = 12) {                     ; ROLE_SYSTEM_MENUITEM
            if (!(st & 0x8000) && name != "")    ; not invisible
                items.Push({acc: c.acc, id: c.id, name: name,
                            popup: (st & 0x40000000) != 0,
                            off: (st & 0x1) != 0})
        } else if (c.id = 0 && depth < 4)
            AccWalk(c.acc, items, depth + 1)
    }
}

; A menu's items, retried briefly: a freshly opened menu may not have laid
; out its items on the first frame.
MenuItems(hwnd, ms := 400) {
    end := A_TickCount + ms
    loop {
        items := []
        acc := AccFromWindow(hwnd)
        if IsObject(acc)
            AccWalk(acc, items, 0)
        if (items.Length || A_TickCount > end)
            return items
        Sleep(15)
    }
}

CleanName(n) {
    n := StrReplace(n, "&", "")
    if (p := InStr(n, "`t"))
        n := SubStr(n, 1, p - 1)
    return Trim(RegExReplace(n, "\s+", " "))
}

MatchItem(items, want) {
    want := StrLower(CleanName(want))
    for it in items
        if (StrLower(CleanName(it.name)) = want)
            return it
    for it in items
        if (SubStr(StrLower(CleanName(it.name)), 1, StrLen(want)) = want)
            return it
    return 0
}

AccRect(acc, id) {
    x := Buffer(4, 0), y := Buffer(4, 0), w := Buffer(4, 0), h := Buffer(4, 0)
    try acc.accLocation(ComValue(0x4003, x.Ptr), ComValue(0x4003, y.Ptr),
        ComValue(0x4003, w.Ptr), ComValue(0x4003, h.Ptr), id)
    catch
        return 0
    return {x: NumGet(x, "int"), y: NumGet(y, "int"), w: NumGet(w, "int"),
            h: NumGet(h, "int")}
}

AccHit(it) {
    if (Conf["RightClickMethod"] = "action") {
        try {
            it.acc.accDoDefaultAction(it.id)
            return true
        }
    }
    r := AccRect(it.acc, it.id)
    if (!IsObject(r) || r.w <= 0 || r.h <= 0)
        return false
    Click(r.x + r.w // 2, r.y + r.h // 2)
    return true
}

ProcWindows(pid) {
    m := Map()
    for h in WinGetList("ahk_pid " pid)
        m[h] := 1
    return m
}

; The first new visible window of the process: the menu (or submenu) that
; just opened. Shadows and tooltips are not menus.
WaitPopup(pid, known, ms) {
    end := A_TickCount + ms
    loop {
        for h in WinGetList("ahk_pid " pid) {
            if known.Has(h)
                continue
            cls := ""
            try cls := WinGetClass("ahk_id " h)
            if (cls = "SysShadow" || InStr(cls, "tooltips"))
                continue
            return h
        }
        if (A_TickCount > end)
            return 0
        Sleep(10)
    }
}

; mode "run": do the item. mode "list": return the menu's item tree (two
; levels of submenus) for the picker in the settings window.
CtxRun(path, x, y, mode := "run") {
    segs := []
    for p in StrSplit(path, ">") {
        p := Trim(p)
        if (p != "")
            segs.Push(p)
    }
    if (mode = "run" && !segs.Length)
        return 0
    MouseGetPos(&ox, &oy)
    keep := false
    HiRes(true)
    try {
        WaitButtonsUp()
        DllCall("SetCursorPos", "int", x, "int", y)
        MouseGetPos(, , &root)
        pid := PidOf(root)
        if !pid
            return 0
        known := ProcWindows(pid)
        Send("{Blind}{RButton}")
        pop := WaitPopup(pid, known, 1000)
        if !pop {
            Toast("The right-click menu didn't open", 2000)
            return 0
        }
        if (segs.Length && RegExMatch(segs[1], "^#\d+$"))
            return CtxKeys(segs)
        for i, seg in segs {
            items := MenuItems(pop)
            it := MatchItem(items, seg)
            if !IsObject(it) {
                Send("{Escape " i "}")
                Toast(items.Length ? "No “" seg "” in the right-click menu"
                    : "Couldn't read the right-click menu. Try a #number path.", 3000)
                return 0
            }
            known := ProcWindows(pid)
            if !AccHit(it) {
                Send("{Escape " i "}")
                Toast("Couldn't click “" seg "”", 2000)
                return 0
            }
            if (i = segs.Length && mode = "run") {
                keep := it.popup             ; ended on a submenu: leave it
                break                        ;   open, pointer beside it
            }
            sub := WaitPopup(pid, known, 700)
            if !sub {
                Send("{Escape " i "}")
                Toast("“" seg "” didn't open a submenu", 2000)
                return 0
            }
            pop := sub
        }
        if (mode = "list") {
            tree := CtxTree(pop, pid, 0)
            Send("{Escape " (segs.Length + 1) "}")
            return tree
        }
        return 1
    } finally {
        HiRes(IsObject(Cur))
        if !keep {
            if (mode = "list" || !Conf["ReturnPointer"])
                DllCall("SetCursorPos", "int", ox, "int", oy)
            else
                DllCall("SetCursorPos", "int", x, "int", y)
        }
    }
}

; Down to the Nth item, Right into a submenu, Enter on the last. A freshly
; mouse-opened menu has nothing selected; a submenu opens on its first item.
CtxKeys(segs) {
    for i, seg in segs {
        n := Integer(SubStr(seg, 2))
        k := (i = 1) ? n : n - 1
        if (k > 0)
            Send("{Down " k "}")
        if (i < segs.Length) {
            Send("{Right}")
            Sleep(80)
        } else
            Send("{Enter}")
    }
    return 1
}

CtxTree(pop, pid, depth) {
    out := []
    for it in MenuItems(pop) {
        node := {name: CleanName(it.name), popup: it.popup, kids: []}
        if (it.popup && !it.off && depth < 2) {
            known := ProcWindows(pid)
            if AccHit(it) {
                sub := WaitPopup(pid, known, 600)
                if sub {
                    node.kids := CtxTree(sub, pid, depth + 1)
                    Send("{Escape}")
                    WinWaitClose("ahk_id " sub, , 0.4)
                }
            }
        }
        out.Push(node)
    }
    return out
}

; ── §11  SMALL THINGS ───────────────────────────────────────────────────────

Toast(msg, ms := 1200) {
    MouseGetPos(&x, &y)
    mon := MonitorAt(x, y)
    ToolTip(msg, (mon.l + mon.r) // 2 - 120, mon.b - 90, 19)
    SetTimer(ToastOff, -ms)
}

ToastOff() => ToolTip(, , , 19)

TogglePause(*) {
    global Paused
    Paused := !Paused
    CloseMenu()
    DropHeld()
    try A_TrayMenu.ToggleCheck("Pause RadWheel")
    if IsObject(Ed)
        try Ed.btnPause.Text := Paused ? "Resume" : "Pause"
    Toast(Paused ? "RadWheel paused: every button is normal" : "RadWheel on")
}

; Forget every held trigger, but keep swallowing the release of any that is
; still physically down: its press was blocked, so its release must be too.
; A press that became a real drag keeps its native release.
DropHeld() {
    for key, h in Held.Clone()
        if (!h.pass && GetKeyState(key, "P"))
            Swallow[key] := true
    Held.Clear()
}

Unstick(*) {
    CloseMenu()
    DropHeld()
    ClickSwallow.Clear()
    ClicksOff()
    ; only what is logically down: a lone right-button or thumb-button UP
    ; would open a context menu or go "back"
    for k in ["LButton", "RButton", "MButton", "XButton1", "XButton2", "LCtrl",
              "RCtrl", "LAlt", "RAlt", "LShift", "RShift", "LWin", "RWin"]
        if GetKeyState(k)
            Send("{" k " Up}")
    Toast("Buttons and keys released")
}

Cleanup(*) {
    CloseMenu()
    HiRes(false)
    RingCache.Clear()
    Overlay.Free()
}

; ── §11b  LIVING WITH RADMAPPER ─────────────────────────────────────────────
;
; RadMapper and RadWheel can run together, but never on the same button. Both
; hook the mouse, Windows asks the newest hook first, and RadMapper puts its
; hook back in front every 10 s while PACS is in front. Two scripts owning
; one button would take turns winning it. So RadWheel leaves every input
; RadMapper has hooked to RadMapper. RadMapper publishes that set itself in
; RadMapperHooks.txt beside its config (empty while paused); for an older
; RadMapper without it, the set is worked out from its config the way its
; SyncHooks does (every live row's button and layer host).
; Neither script reacts to the other's Send: both stay at SendLevel 0.
; Setting YieldToRadMapper="0" in the settings file turns this off.

RadMapperRunning() {
    ; the single-copy mutex RadMapper holds for its whole life
    h := DllCall("OpenMutexW", "uint", 0x00100000, "int", 0,
        "wstr", "Local\RadMapper-single-copy", "ptr")
    if !h                                    ; denied = it exists (RadMapper
        return A_LastError = 5               ;   running elevated)
    DllCall("CloseHandle", "ptr", h)
    return true
}

; %APPDATA%\RadMapper, unless the running copy is portable (its config then
; sits beside the script, found from its hidden main window's title).
RadMapperCfgPath() {
    dir := A_AppData "\RadMapper"
    dhw := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    try {
        for h in WinGetList("ahk_class AutoHotkey") {
            t := ""
            try t := WinGetTitle("ahk_id " h)
            if RegExMatch(t, "i)^(.*)\\[^\\]*RadMapper[^\\]*\.(ahk|exe)\b", &mm) {
                if FileExist(mm[1] "\RadMapper.portable")
                    dir := mm[1]
                break
            }
        }
    }
    DetectHiddenWindows(dhw)
    return dir "\RadMapperConfig.json"
}

RmCheck() {
    global RmSeen
    if !(Conf["YieldToRadMapper"] && RadMapperRunning()) {
        if RmSeen.running {
            RmSeen.running := false
            RmSeen.mtime := ""
            RmSeen.readOk := false
            RmSetOwned(RmEmpty())
        }
        return
    }
    if !RmSeen.running {
        RmSeen.running := true
        RmSeen.cfg := RadMapperCfgPath()
        RmSeen.hooks := RegExReplace(RmSeen.cfg, "[^\\]*$", "RadMapperHooks.txt")
        RmSeen.mtime := ""
    }
    ; time + size of both files (size catches a second save in the same second)
    mt := RmStamp(RmSeen.hooks) "|" RmStamp(RmSeen.cfg)
    if (mt = RmSeen.mtime)
        return
    try {
        owned := ""
        try owned := RmReadHooks(RmSeen.hooks)
        if !IsObject(owned)
            owned := RmReadOwned(RmSeen.cfg)
        RmSeen.mtime := mt
        RmSeen.readOk := true
    } catch {
        ; mid-save or unreadable: try again next time; until the first good
        ; read, assume RadMapper's shipped buttons
        if RmSeen.readOk
            return
        owned := RmEmpty()
        for k in ["XButton1", "XButton2", "CapsLock", "``"]
            owned[k] := 1
    }
    RmSetOwned(owned)
}

RmStamp(f) {
    try return FileGetTime(f, "M") "/" FileGetSize(f)
    return ""
}

; RadMapperHooks.txt: comment lines, pid=, enabled=, then one input per line.
; A file left behind by a RadMapper that is gone (a crash) is not trusted.
RmReadHooks(path) {
    owned := RmEmpty()
    pid := 0
    loop parse FileRead(path, "UTF-8"), "`n", "`r" {
        ln := Trim(A_LoopField)
        if (ln = "" || SubStr(ln, 1, 1) = ";" || SubStr(ln, 1, 8) = "enabled=")
            continue
        if (SubStr(ln, 1, 4) = "pid=")
            pid := ToInt(SubStr(ln, 5), 0)
        else
            owned[ln] := 1
    }
    if !(pid && ProcessExist(pid))
        throw Error("stale hooks file")
    return owned
}

RmEmpty() {
    m := Map()
    m.CaseSense := "Off"
    return m
}

RmGet(m, k, def := "") => (m is Map && m.Has(k)) ? m[k] : def

RmName(s) {
    s := Trim(String(s))
    if RegExMatch(s, "^\{([^{}]+)\}$", &mm)
        s := Trim(mm[1])
    return s
}

; The inputs RadMapper hooks for this config. A row is display-only when it
; is a plain native tap on its own button, everywhere, on the base layer.
RmReadOwned(path) {
    cfg := JsonParse(FileRead(path, "UTF-8"))
    owned := RmEmpty()
    for row in RmGet(cfg, "bindings", []) {
        if !(row is Map)
            continue
        btn := RmName(RmGet(row, "button"))
        act := RmGet(row, "action", 0)
        typ := RmGet(act, "type")
        val := RmName(RmGet(act, "value"))
        ev := RmGet(row, "event")
        inert := (typ = "native" || typ = "stock") && (val = "" || val = btn)
            && ev = (RegExMatch(btn, "i)^Wheel") ? "turn" : "tap")
            && RmGet(row, "app", "*") = "*" && RmGet(row, "layer", "*") = "*"
            && RmGet(row, "mods") = ""
        if (!inert && btn != "")
            owned[btn] := 1
        L := RmGet(row, "layer", "*")
        if !(L = "*" || L = "" || L = "Base") {
            for part in StrSplit(L, "/")
                if (Trim(part) != "")
                    owned[RmName(part)] := 1
        }
        if (typ = "clicklock") {
            if IsMouseKey(val)
                owned[val] := 1
            else
                for b in ["LButton", "RButton", "MButton", "XButton1", "XButton2"]
                    owned[b] := 1
        }
    }
    return owned
}

RmSetOwned(owned) {
    global RmOwned
    before := RmYielded()
    RmOwned := owned
    after := RmYielded()
    if (after != before) {
        if (after != "")
            Toast("RadMapper is running and uses " after ". RadWheel leaves "
                . "that to RadMapper.", 4000)
        else
            Toast("RadWheel has " before " back.", 2500)
    }
    if IsObject(Ed)
        try EdSummary()
}

; RadWheel's own buttons that RadMapper holds right now, in words.
RmYielded() {
    out := "", seen := RmEmpty()
    for m in Menus {
        k := KeyOf(m.trigger)
        if (m.trigger = "" || !Claims(m) || seen.Has(k) || !RmOwned.Has(k))
            continue
        seen[k] := 1
        out .= (out = "" ? "" : ", ") RegExReplace(TriggerName(m.trigger), "\s*\(.*\)$")
    }
    return out
}

; A small JSON reader: objects -> Map (case-insensitive), arrays -> Array,
; true/false -> 1/0, null -> "", numbers stay text.
JsonParse(t) {
    i := 1
    v := JsonVal(t, &i)
    if RegExMatch(t, "\G\s*\S", , i)
        throw Error("JSON: trailing text at " i)
    return v
}

JsonWs(t, &i) {
    if RegExMatch(t, "\G\s+", &w, i)
        i += w.Len
}

JsonVal(t, &i) {
    JsonWs(t, &i)
    c := SubStr(t, i, 1)
    if (c = "{" || c = "[") {
        obj := (c = "{")
        out := obj ? RmEmpty() : []
        close := obj ? "}" : "]"
        i += 1
        JsonWs(t, &i)
        if (SubStr(t, i, 1) = close) {
            i += 1
            return out
        }
        loop {
            if obj {
                JsonWs(t, &i)
                k := JsonStr(t, &i)
                if !RegExMatch(t, "\G\s*:", &w, i)
                    throw Error("JSON: ':' expected at " i)
                i += w.Len
                out[k] := JsonVal(t, &i)
            } else
                out.Push(JsonVal(t, &i))
            if !RegExMatch(t, "\G\s*([,\]}])", &w, i) || (w[1] != "," && w[1] != close)
                throw Error("JSON: ',' or '" close "' expected at " i)
            i += w.Len
            if (w[1] = close)
                return out
        }
    }
    if (c = '"')
        return JsonStr(t, &i)
    if !RegExMatch(t, "\G(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?|true|false|null)", &mm, i)
        throw Error("JSON: value expected at " i)
    i += mm.Len
    switch mm[1], true {
        case "true":  return 1
        case "false": return 0
        case "null":  return ""
    }
    return mm[1]
}

JsonStr(t, &i) {
    if !RegExMatch(t, '\G"((?:[^"\\]++|\\.)*+)"', &mm, i)
        throw Error("JSON: string expected at " i)
    i += mm.Len
    s := mm[1]
    if !InStr(s, "\")
        return s
    out := "", p := 1
    while RegExMatch(s, "\\(u[0-9A-Fa-f]{4}|.)", &e, p) {
        out .= SubStr(s, p, e.Pos - p)
        c := e[1]
        if (StrLen(c) = 5)
            out .= Chr(Integer("0x" SubStr(c, 2)))
        else
            out .= (c == "n") ? "`n" : (c == "t") ? "`t" : (c == "r") ? "`r"
                 : (c == "b") ? "`b" : (c == "f") ? "`f" : c
        p := e.Pos + e.Len
    }
    return out SubStr(s, p)
}

; Record a shortcut: the next key pressed, with whatever modifiers are held.
RecordKeys(prompt := "Press the shortcut now") {
    rg := Gui("+AlwaysOnTop +ToolWindow -SysMenu", APP)
    rg.BackColor := "1F2128"
    rg.SetFont("s11 cE6E8EB", "Segoe UI")
    rg.Add("Text", "w340 Center", prompt "`n`n(Esc to cancel)")
    rg.Show()
    ih := InputHook("L0 T15")
    ih.KeyOpt("{All}", "ES")
    ih.KeyOpt("{LCtrl}{RCtrl}{LShift}{RShift}{LAlt}{RAlt}{LWin}{RWin}", "-ES")
    ih.Start()
    ih.Wait()
    rg.Destroy()
    if (ih.EndReason != "EndKey")
        return ""
    key := ih.EndKey
    mods := ih.EndMods
    if (key = "Escape" && !RegExMatch(mods, "[\^!+#]"))
        return ""
    out := ""
    for pair in [["^", "Ctrl"], ["!", "Alt"], ["+", "Shift"], ["#", "LWin"]]
        if (InStr(mods, pair[1]) || GetKeyState(pair[2], "P")
            || (pair[1] = "#" && GetKeyState("RWin", "P")))
            out .= pair[1]
    if (StrLen(key) = 1 && !InStr("!#^+{}", key))
        out .= StrLower(key)
    else
        out .= "{" key "}"
    return out
}

; ── §12  THE SETTINGS WINDOW ────────────────────────────────────────────────
;
; Stream-Deck style: a live picture of the wheel on the left, click a slot
; (or its centre, for the tap), edit it on the right. Every change is saved
; at once; there is no Save button to forget.

EdShow(*) {
    global Ed
    if IsObject(Ed) {
        Ed.gui.Show()
        return
    }
    Ed := {menu: 1, slot: 1, loading: false, picW: 0, picH: 0}
    g := Gui("-MaximizeBox", APP " " VER ": radial menus")
    Ed.gui := g
    g.BackColor := "1F2128"
    g.MarginX := 16, g.MarginY := 12
    g.SetFont("s10 cE6E8EB", "Segoe UI")
    g.OnEvent("Close", (*) => g.Hide())

    ; ── which wheel ──
    g.SetFont("s10 bold")
    g.Add("Text", "x16 y16 w60 h28 +0x200", "Wheel")
    g.SetFont("s10 norm")
    Ed.ddMenu := InField(g.Add("DropDownList", "x80 y16 w240", []))
    Ed.ddMenu.OnEvent("Change", EdPickMenu)
    g.Add("Button", "x330 y15 w64 h30", "New").OnEvent("Click", EdNewMenu)
    g.Add("Button", "x398 y15 w80 h30", "Rename").OnEvent("Click", EdRename)
    g.Add("Button", "x482 y15 w80 h30", "Copy").OnEvent("Click", EdCopy)
    g.Add("Button", "x566 y15 w70 h30", "Delete").OnEvent("Click", EdDelete)
    g.Add("Button", "x740 y15 w124 h30", "Practice ▶").OnEvent("Click", EdPractice)
    Ed.btnPause := g.Add("Button", "x870 y15 w114 h30", Paused ? "Resume" : "Pause")
    Ed.btnPause.OnEvent("Click", TogglePause)

    ; ── how it opens ──
    row(y, label) => g.Add("Text", "x16 y" y " w112 h28 +0x200", label)
    row(58, "Button or key")
    Ed.ddTrig := InField(g.Add("DropDownList", "x130 y58 w270", []))
    Ed.ddTrig.OnEvent("Change", EdTrigger)
    g.Add("Button", "x406 y57 w100 h30", "Record key…").OnEvent("Click", EdRecordTrigger)
    row(92, "Hold it")
    Ed.ddHold := InField(g.Add("DropDownList", "x130 y92 w376",
        ["Opens the wheel: move toward a command, let go",
         "Does the same as a tap"]))
    Ed.ddHold.OnEvent("Change", EdHold)
    row(126, "Tap it")
    Ed.ddTap := InField(g.Add("DropDownList", "x130 y126 w376",
        ["Opens the wheel and keeps it open: click a command",
         "Does its normal job (normal click or key)",
         "Does nothing",
         "Runs a command (set it in the centre of the wheel)"]))
    Ed.ddTap.OnEvent("Change", EdTap)
    row(160, "Moving at once")
    Ed.ddMove := InField(g.Add("DropDownList", "x130 y160 w376",
        ["Picks by direction (fastest: flick and let go)",
         "Drags as normal (hold still to open the wheel)"]))
    Ed.ddMove.OnEvent("Change", EdMove)
    row(194, "Works in")
    Ed.ddProg := InField(g.Add("DropDownList", "x130 y194 w270", []))
    Ed.ddProg.OnEvent("Change", EdPrograms)

    g.Add("Text", "x530 y58 w110 h28 +0x200", "Commands")
    Ed.ddCount := InField(g.Add("DropDownList", "x640 y58 w70", ["4", "6", "8", "9", "10", "12"]))
    Ed.ddCount.OnEvent("Change", EdCount)
    g.SetFont("s9 cA9B1BD")
    Ed.summary := g.Add("Text", "x530 y96 w454 h126", "")
    g.SetFont("s10 cE6E8EB")
    g.Add("Text", "x16 y232 w968 h1 +0x10")

    ; ── the wheel ──
    hbm := DllCall("CreateBitmap", "int", 1, "int", 1, "uint", 1, "uint", 32,
        "ptr", 0, "ptr")
    Ed.pic := g.Add("Picture", "x16 y244 w464 h440 +0x100", "HBITMAP:*" hbm)
    DllCall("DeleteObject", "ptr", hbm)
    Ed.pic.OnEvent("Click", EdPicClick)
    Ed.pic.OnEvent("DoubleClick", EdPicDouble)

    ; ── the selected slot ──
    g.SetFont("s12 bold")
    Ed.slotTitle := g.Add("Text", "x500 y244 w290 h28 +0x200", "")
    g.SetFont("s10 norm")
    Ed.ddSlot := InField(g.Add("DropDownList", "x796 y244 w188", []))
    Ed.ddSlot.OnEvent("Change", (*) => EdSelectSlot(Ed.ddSlot.Value - 1))
    fld(y, label) => g.Add("Text", "x500 y" y " w96 h28 +0x200", label)
    Ed.lName := fld(282, "Name")
    Ed.eLabel := InField(g.Add("Edit", "x600 y282 w384 h28"))
    Ed.eLabel.OnEvent("Change", EdLabel)
    Ed.lIcon := fld(316, "Icon")
    Ed.eIcon := InField(g.Add("Edit", "x600 y316 w60 h28"))
    Ed.eIcon.OnEvent("Change", EdIcon)
    Ed.ddIcon := InField(g.Add("DropDownList", "x666 y316 w130", ICONS))
    Ed.ddIcon.OnEvent("Change", EdIconPick)
    Ed.lColor := g.Add("Text", "x806 y316 w56 h28 +0x200", "Colour")
    Ed.ddColor := InField(g.Add("DropDownList", "x864 y316 w120", COLOR_NAMES))
    Ed.ddColor.OnEvent("Change", EdColor)
    fld(350, "Does")
    Ed.ddType := InField(g.Add("DropDownList", "x600 y350 w384", []))
    Ed.ddType.OnEvent("Change", EdType)
    Ed.lVal := fld(384, "")
    Ed.eVal := InField(g.Add("Edit", "x600 y384 w270 h28"))
    Ed.eVal.OnEvent("Change", EdValue)
    Ed.eText := InField(g.Add("Edit", "x600 y384 w384 h64 Multi"))
    Ed.eText.OnEvent("Change", EdValue)
    Ed.ddSub := InField(g.Add("DropDownList", "x600 y384 w270", []))
    Ed.ddSub.OnEvent("Change", EdSub)
    Ed.btnVal := g.Add("Button", "x876 y383 w108 h30", "Record…")
    Ed.btnVal.OnEvent("Click", EdValButton)
    g.SetFont("s9 cA9B1BD")
    Ed.hint := g.Add("Text", "x600 y452 w384 h48", "")
    g.SetFont("s10 cE6E8EB")
    Ed.lTarget := fld(504, "Send to")
    Ed.ddTarget := InField(g.Add("DropDownList", "x600 y504 w384", []))
    Ed.ddTarget.OnEvent("Change", EdTarget)
    Ed.btnTry := g.Add("Button", "x600 y546 w118 h30", "Try it in 3 s")
    Ed.btnTry.OnEvent("Click", EdTry)
    Ed.btnLeft := g.Add("Button", "x724 y546 w84 h30", "◀ Move")
    Ed.btnLeft.OnEvent("Click", (*) => EdMoveSlot(-1))
    Ed.btnRight := g.Add("Button", "x812 y546 w84 h30", "Move ▶")
    Ed.btnRight.OnEvent("Click", (*) => EdMoveSlot(1))
    Ed.btnClear := g.Add("Button", "x900 y546 w84 h30", "Clear")
    Ed.btnClear.OnEvent("Click", EdClear)
    g.SetFont("s9 cA9B1BD")
    Ed.tip := g.Add("Text", "x500 y590 w484 h94", "")
    g.SetFont("s10 cE6E8EB")
    g.Add("Text", "x16 y696 w968 h1 +0x10")

    ; ── everything else ──
    g.Add("Text", "x16 y708 w80 h28 +0x200", "Wheel size")
    Ed.ddSize := InField(g.Add("DropDownList", "x96 y708 w96", ["Small", "Medium", "Large"]))
    Ed.ddSize.OnEvent("Change", EdSetting)
    g.Add("Text", "x206 y708 w150 h28 +0x200", "Wheel appears after")
    Ed.eDelay := InField(g.Add("Edit", "x356 y708 w56 h28 Number"))
    Ed.eDelay.OnEvent("Change", EdSetting)
    g.Add("Text", "x416 y708 w30 h28 +0x200", "ms")
    Ed.cConfirm := g.Add("CheckBox", "x456 y714 w16 h16")
    Ed.cConfirm.OnEvent("Click", EdSetting)
    g.Add("Text", "x476 y708 w130 h28 +0x200", "Show what ran")
    Ed.cReturn := g.Add("CheckBox", "x610 y714 w16 h16")
    Ed.cReturn.OnEvent("Click", EdSetting)
    g.Add("Text", "x630 y708 w190 h28 +0x200", "Pointer back to start")
    Ed.cStartup := g.Add("CheckBox", "x16 y750 w16 h16")
    Ed.cStartup.OnEvent("Click", EdStartup)
    g.Add("Text", "x36 y744 w170 h28 +0x200", "Start with Windows")
    g.Add("Button", "x220 y743 w110 h30", "Programs…").OnEvent("Click", EdProgramsDlg)
    g.Add("Button", "x336 y743 w120 h30", "Settings file").OnEvent("Click",
        (*) => Run('explorer.exe /select,"' CFG_FILE '"'))
    g.Add("Button", "x462 y743 w70 h30", "Help").OnEvent("Click", EdHelp)
    Ed.status := g.Add("Text", "x560 y744 w424 h28 +0x200 Right", "")

    g.Show("w1000 h788")
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "int", 20,
        "int*", 1, "int", 4)
    WinGetPos(, , &pw, &ph, "ahk_id " Ed.pic.Hwnd)
    Ed.picW := pw, Ed.picH := ph
    EdLoadSettings()
    EdFillMenus()
    EdLoadMenu()
}

; Edits and lists keep dark text on their white ground.
InField(ctrl) {
    ctrl.SetFont("c111318")
    return ctrl
}

CurMenu() => Menus[Ed.menu]
CurSlot() => (Ed.slot = 0) ? CurMenu().tap : CurMenu().slots[Ed.slot]

MenuNames() {
    out := []
    for m in Menus
        out.Push(m.name)
    return out
}

EdFillMenus() {
    Ed.loading := true
    Ed.ddMenu.Delete()
    Ed.ddMenu.Add(MenuNames())
    Ed.menu := Max(1, Min(Ed.menu, Menus.Length))
    Ed.ddMenu.Value := Ed.menu
    Ed.loading := false
}

EdLoadSettings() {
    Ed.loading := true
    Ed.ddSize.Value := (Conf["Size"] = "Small") ? 1 : (Conf["Size"] = "Large") ? 3 : 2
    Ed.eDelay.Value := Conf["ShowDelay"]
    Ed.cConfirm.Value := Conf["Confirm"] ? 1 : 0
    Ed.cReturn.Value := Conf["ReturnPointer"] ? 1 : 0
    Ed.cStartup.Value := FileExist(A_Startup "\RadWheel.lnk") ? 1 : 0
    Ed.loading := false
}

EdLoadMenu() {
    m := CurMenu()
    Ed.loading := true
    ; the button list: the standard ones, plus a recorded key if there is one
    items := []
    idx := 0
    for i, p in TRIGGERS {
        items.Push(p[2])
        if (p[1] = m.trigger)
            idx := i
    }
    if !idx {
        items.Push(TriggerName(m.trigger))
        idx := items.Length
    }
    Ed.trigItems := items
    Ed.ddTrig.Delete()
    Ed.ddTrig.Add(items)
    Ed.ddTrig.Value := idx
    Ed.ddHold.Value := m.hold ? 1 : 2
    Ed.ddMove.Value := (m.move = "drag") ? 2 : 1
    EdSyncTap()
    progs := ["Every program", "PACS", "PowerScribe", "Choose a program…"]
    pidx := (m.programs = "") ? 1 : (m.programs = "PACS") ? 2
          : (m.programs = "PowerScribe") ? 3 : 0
    if !pidx {
        progs.Push("Only in " m.programs)
        pidx := 5
    }
    Ed.ddProg.Delete()
    Ed.ddProg.Add(progs)
    Ed.ddProg.Value := pidx
    cnts := [], ci := 0
    for i, c in COUNTS {
        cnts.Push(String(c))
        if (c = m.count)
            ci := i
    }
    if !ci {
        cnts.Push(String(m.count))         ; a hand-edited count
        ci := cnts.Length
    }
    Ed.ddCount.Delete()
    Ed.ddCount.Add(cnts)
    Ed.ddCount.Value := ci
    Ed.loading := false
    if (Ed.slot > m.count)
        Ed.slot := 1
    EdSummary()
    EdSelectSlot(Ed.slot)
}

EdSyncTap() {
    t := CurMenu().tap.type
    Ed.ddTap.Value := (t = "toggle") ? 1 : (t = "native") ? 2 : (t = "none") ? 3 : 4
}

EdSummary() {
    m := CurMenu()
    if (m.trigger = "") {
        txt := "This wheel has no button of its own. Open it from another "
             . "wheel with “Open another wheel”."
    } else {
        b := TriggerName(m.trigger)
        where := (m.programs = "") ? "in every program" : "in " m.programs
        txt := ""
        if m.hold
            txt .= "HOLD " b " " where ", move toward a command, let go. "
                 . "Let go in the centre to cancel.`n"
        t := m.tap
        switch t.type {
            case "toggle": txt .= "TAP it to open the wheel and leave it open: "
                . "click a command, or tap again.`n"
            case "native": txt .= m.hold ? "A quick TAP still does its normal job.`n" : ""
            case "none":   txt .= "A TAP does nothing.`n"
            default:       txt .= "A TAP runs: " SlotTitle(t) ".`n"
        }
        if !Claims(m)
            txt .= "⚠ This wheel doesn't use its button yet: add a command, "
                 . "or set what a tap does.`n"
        if (m.move = "drag" && m.hold)
            txt .= "Moving straight away drags as normal; hold still to open.`n"
        for o in Menus {
            if (o != m && o.trigger = m.trigger && o.programs = m.programs && Claims(o)) {
                txt .= "⚠ “" o.name "” uses the same button in the same "
                     . "programs; the one higher in the list wins.`n"
                break
            }
        }
        if (Claims(m) && RmOwned.Has(KeyOf(m.trigger)))
            txt .= "⚠ RadMapper is running and uses this button, so RadWheel "
                 . "leaves it alone. Pick another button here, or free it in "
                 . "RadMapper.`n"
        if (m.trigger = "RButton" && m.hold && m.tap.type = "native")
            txt .= "The normal right-click menu still opens on a quick tap."
    }
    Ed.summary.Value := txt
}

EdPreview() {
    if (!IsObject(Ed) || !Ed.picW)
        return
    m := CurMenu()
    w := Ed.picW, h := Ed.picH
    g1 := Geom(m, 1.0)
    s := Min(1.35, (Min(w, h) / 2 - 2) / g1.half)
    g := Geom(m, s)
    bmp := 0, gfx := 0, hbm := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", w, "int", h, "int", 0,
        "int", 0x26200A, "ptr", 0, "ptr*", &bmp)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", bmp, "ptr*", &gfx)
    GfxSetup(gfx)
    DllCall("gdiplus\GdipGraphicsClear", "ptr", gfx, "uint", 0xFF1F2128)
    DrawBase(gfx, w / 2, h / 2, g, m, true)
    if (Ed.slot > 0)
        DrawSel(gfx, w / 2, h / 2, g, m, Ed.slot, true)
    else {
        RingCircle(gfx, 0xFFFFFFFF, w / 2, h / 2, g.hubR, 2.5 * s)
    }
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gfx)
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "ptr", bmp, "ptr*", &hbm,
        "uint", 0xFF1F2128)
    DllCall("gdiplus\GdipDisposeImage", "ptr", bmp)
    Ed.pic.Value := "HBITMAP:*" hbm
    DllCall("DeleteObject", "ptr", hbm)
    Ed.geom := g
}

; Where on the picture was clicked: 0 = the centre (tap), -1 = nowhere.
EdHit() {
    if !Ed.HasProp("geom")
        return -1
    MouseGetPos(&mx, &my)
    WinGetPos(&px, &py, , , "ahk_id " Ed.pic.Hwnd)
    dx := mx - (px + Ed.picW / 2)
    dy := my - (py + Ed.picH / 2)
    g := Ed.geom
    d := Sqrt(dx * dx + dy * dy)
    if (d < g.hubR * 1.3)
        return 0
    if (d > g.half)
        return -1
    return SlotAt(dx, dy, g.n)
}

EdPicClick(*) {
    i := EdHit()
    if (i >= 0)
        EdSelectSlot(i)
}

EdPicDouble(*) {
    i := EdHit()
    if (i < 1)
        return
    sl := CurMenu().slots[i]
    if (sl.type = "menu" && IsObject(FindMenu(sl.value))) {
        for k, m in Menus
            if (m.name = sl.value)
                Ed.menu := k
        Ed.slot := 1
        EdFillMenus()
        EdLoadMenu()
    }
}

EdSelectSlot(i) {
    Ed.slot := i
    EdLoadSlot()
    EdPreview()
}

EdLoadSlot() {
    m := CurMenu()
    isTap := (Ed.slot = 0)
    sl := CurSlot()
    Ed.loading := true
    Ed.slotTitle.Value := isTap ? "Centre: a quick tap" : Place(m.count, Ed.slot)
    items := ["Centre: a quick tap"]
    loop m.count
        items.Push(Place(m.count, A_Index) ": " SlotTitle(m.slots[A_Index]))
    Ed.ddSlot.Delete()
    Ed.ddSlot.Add(items)
    Ed.ddSlot.Value := Ed.slot + 1
    for c in [Ed.lName, Ed.eLabel, Ed.lIcon, Ed.eIcon, Ed.ddIcon, Ed.lColor,
              Ed.ddColor, Ed.btnLeft, Ed.btnRight]
        c.Visible := !isTap
    Ed.eLabel.Value := sl.label
    Ed.eIcon.Value := sl.icon
    ii := 1
    for k, v in ICONS
        if (v = sl.icon && k > 1)
            ii := k
    Ed.ddIcon.Value := ii
    ci := 1
    for k, v in COLOR_NAMES
        if (v = sl.color)
            ci := k
    Ed.ddColor.Value := ci
    types := isTap ? TAP_TYPES : SLOT_TYPES
    names := [], ti := 1
    for k, p in types {
        names.Push(p[2])
        if (p[1] = sl.type)
            ti := k
    }
    Ed.ddType.Delete()
    Ed.ddType.Add(names)
    Ed.ddType.Value := ti
    Ed.loading := false
    EdValueRow()
}

; The value controls for the slot's type: only the ones that mean something.
EdValueRow() {
    sl := CurSlot()
    t := sl.type
    Ed.loading := true
    Ed.eVal.Visible := (t = "keys" || t = "run" || t = "rclick")
    Ed.eText.Visible := (t = "text")
    Ed.ddSub.Visible := (t = "menu")
    Ed.btnVal.Visible := (t = "keys" || t = "run" || t = "menu" || t = "rclick")
    Ed.lVal.Value := (t = "keys") ? "Shortcut" : (t = "text") ? "Text"
        : (t = "menu") ? "Wheel" : (t = "run") ? "Open" : (t = "rclick") ? "Menu item" : ""
    Ed.btnVal.Text := (t = "keys") ? "Record…" : (t = "run") ? "Browse…"
        : (t = "rclick") ? "Read menu…" : "New wheel…"
    if Ed.eVal.Visible
        Ed.eVal.Value := sl.value
    if Ed.eText.Visible
        Ed.eText.Value := sl.value
    if Ed.ddSub.Visible {
        names := [], si := 0
        for m in Menus {
            if (m = CurMenu())
                continue
            names.Push(m.name)
            if (m.name = sl.value)
                si := names.Length
        }
        Ed.ddSub.Delete()
        Ed.ddSub.Add(names)
        if si
            Ed.ddSub.Value := si
    }
    showT := (t = "keys" || t = "text")
    Ed.lTarget.Visible := showT
    Ed.ddTarget.Visible := showT
    if showT {
        items := [], ix := 0
        for k, p in TARGETS {
            items.Push(p[2])
            if (p[1] = sl.target)
                ix := k
        }
        items.Push("Another program…")
        if !ix {
            items.Push("Program: " sl.target)
            ix := items.Length
        }
        Ed.ddTarget.Delete()
        Ed.ddTarget.Add(items)
        Ed.ddTarget.Value := ix
    }
    Ed.btnTry.Enabled := !(t = "none" || t = "toggle" || t = "native" || t = "menu")
    Ed.loading := false
    EdHint()
}

EdHint() {
    sl := CurSlot()
    switch sl.type {
        case "keys":
            h := (sl.value = "") ? "Click Record… and press the shortcut."
               : "Sends " KeysText(sl.value) ". (Advanced: any AutoHotkey Send text works here.)"
        case "text":   h := "Typed exactly as written. New lines are allowed."
        case "menu":   h := "Rest on this slot (or let go on it) and that wheel "
                          . "opens in its place. Double-click it in the picture to edit it."
        case "run":    h := "A program, file, folder or web address."
        case "rclick": h := "The menu text, exactly as shown; submenus with >, e.g. "
                          . "Measurements > Ellipse. End on a submenu to leave it open. "
                          . "Read menu… fills this in for you."
        case "toggle": h := "Tap to open the wheel; it stays open until you click a "
                          . "command, tap again, press Esc or wait."
        case "native": h := "The button does exactly what it did without RadWheel."
        default:       h := (Ed.slot = 0) ? "" : "An empty slot: nothing happens in this direction."
    }
    Ed.hint.Value := h
    if (Ed.slot = 0)
        tip := "The CENTRE of the wheel is the quick tap: what happens when you "
             . "press and release the button without moving."
    else
        tip := "Click a slot in the wheel to edit it, or the centre for the tap. "
             . "Double-click a submenu to open it. ◀ Move / Move ▶ swaps a "
             . "command with its neighbour. Changes are saved as you go."
    Ed.tip.Value := tip
}

; Every edit ends here: save (debounced), rebuild caches, hotkeys, picture.
Changed(rehook := false, relist := false) {
    global Stamp
    Stamp += 1
    RingCache.Clear()
    if rehook
        RegisterHotkeys()
    if relist
        EdFillMenus()
    SetTimer(SaveNow, -400)
    Ed.status.Value := "Saving…"
    EdSummary()
    EdPreview()
}

SaveNow() {
    if SaveConfig()
        try Ed.status.Value := "Saved ✓"
    SetTimer(PreWarm, -300)
}

; ── menu-level handlers ──

EdPickMenu(*) {
    if Ed.loading
        return
    Ed.menu := Ed.ddMenu.Value
    Ed.slot := 1
    EdLoadMenu()
}

AskName(prompt, def := "") {
    loop {
        r := InputBox(prompt, APP, "w340 h130", def)
        if (r.Result != "OK")
            return ""
        n := Trim(r.Value)
        if (n = "" || InStr(n, "]") || InStr(n, "[")) {
            MsgBox("Please use a name without [ or ].", APP, "Icon!")
            continue
        }
        if IsObject(FindMenu(n)) && n != def {
            MsgBox("There is already a wheel called “" n "”.", APP, "Icon!")
            continue
        }
        return n
    }
}

EdNewMenu(*) {
    n := AskName("Name for the new wheel:")
    if (n = "")
        return
    Menus.Push(NewMenu(n, "", "", true, "native", 8))
    Ed.menu := Menus.Length
    Ed.slot := 1
    Changed(true, true)
    EdLoadMenu()
}

EdRename(*) {
    m := CurMenu()
    old := m.name
    n := AskName("New name for “" old "”:", old)
    if (n = "" || n == old)
        return
    m.name := n
    for o in Menus {
        for sl in o.slots
            if (sl.type = "menu" && sl.value = old)
                sl.value := n
        if (o.tap.type = "menu" && o.tap.value = old)
            o.tap.value := n
    }
    Changed(false, true)
    EdLoadMenu()
}

EdCopy(*) {
    m := CurMenu()
    n := AskName("Name for the copy:", m.name " copy")
    if (n = "")
        return
    c := NewMenu(n, "", m.programs, m.hold, m.tap.type, m.count, m.move)
    c.tap := CloneSlot(m.tap)
    c.slots := []
    for sl in m.slots
        c.slots.Push(CloneSlot(sl))
    Menus.Push(c)
    Ed.menu := Menus.Length
    Changed(false, true)
    EdLoadMenu()
}

EdDelete(*) {
    m := CurMenu()
    if (MsgBox("Delete the wheel “" m.name "”?", APP, "YesNo Icon?") != "Yes")
        return
    Menus.RemoveAt(Ed.menu)
    for o in Menus {
        for sl in o.slots
            if (sl.type = "menu" && sl.value = m.name)
                sl.type := "none", sl.value := ""
        if (o.tap.type = "menu" && o.tap.value = m.name)
            o.tap.type := "native", o.tap.value := ""
    }
    if (Menus.Length = 0)
        Menus.Push(NewMenu("New wheel"))
    Ed.menu := 1
    Ed.slot := 1
    Changed(true, true)
    EdLoadMenu()
}

EdPractice(*) {
    m := CurMenu()
    Toast("Practice: move toward a command and click. Nothing is sent.", 2000)
    OpenMenu(m, "toggle", "", true)
}

EdTrigger(*) {
    if Ed.loading
        return
    i := Ed.ddTrig.Value
    if (i > TRIGGERS.Length)
        return                               ; the recorded key, unchanged
    m := CurMenu()
    t := TRIGGERS[i][1]
    if (t = "RButton" && m.programs = "" && m.hold) {
        if (MsgBox("Take over the right button in EVERY program?`n`n"
            . "A quick tap still right-clicks, but right-button drags stop "
            . "working unless you also set “Moving at once” to “Drags as normal”."
            . "`n`nTip: set “Works in” to PACS first.", APP, "OKCancel Icon!") != "OK") {
            EdLoadMenu()
            return
        }
    }
    m.trigger := t
    Changed(true)
}

EdRecordTrigger(*) {
    k := RecordKeys("Press the key (or key combination) that should open this wheel")
    if (k = "")
        return
    t := SendToHotkey(k)
    if (t = "")
        return
    if (StrLen(t) = 1 && MsgBox("“" t "” is a typing key: it will stop typing "
        . "normally wherever this wheel works. Use it anyway?", APP, "YesNo Icon!") != "Yes")
        return
    CurMenu().trigger := t
    Changed(true)
    EdLoadMenu()
}

EdHold(*) {
    if Ed.loading
        return
    CurMenu().hold := (Ed.ddHold.Value = 1)
    Changed(true)
}

EdMove(*) {
    if Ed.loading
        return
    CurMenu().move := (Ed.ddMove.Value = 2) ? "drag" : "flick"
    Changed()
}

EdTap(*) {
    if Ed.loading
        return
    t := CurMenu().tap
    switch Ed.ddTap.Value {
        case 1: t.type := "toggle"
        case 2: t.type := "native"
        case 3: t.type := "none"
        case 4:
            if (t.type = "toggle" || t.type = "native" || t.type = "none") {
                t.type := "keys"
                t.value := ""
            }
            Changed(true)
            EdSelectSlot(0)
            return
    }
    Changed(true)
    if (Ed.slot = 0)
        EdLoadSlot()
}

EdPrograms(*) {
    if Ed.loading
        return
    m := CurMenu()
    switch Ed.ddProg.Value {
        case 1: m.programs := ""
        case 2: m.programs := "PACS"
        case 3: m.programs := "PowerScribe"
        case 4:
            exe := PickProgram()
            if (exe = "") {
                EdLoadMenu()
                return
            }
            m.programs := exe
            Changed(true)
            EdLoadMenu()
            return
        default:
            return
    }
    Changed(true)
}

; 4 <-> 8 keeps Up/Right/Down/Left where they are (slot i of 4 is slot
; 2i-1 of 8), so a growing wheel never moves a learned direction.
EdCount(*) {
    if Ed.loading
        return
    m := CurMenu()
    n := Integer(Ed.ddCount.Text)
    old := m.count
    if (n = old)
        return
    ; 8 -> 4 parks the diagonals in slots 5-8 (kept, not shown, not saved
    ; past the count), so 4 -> 8 in the same session puts them back.
    if (old = 4 && n = 8) {
        s := m.slots
        ns := []
        loop 4 {
            ns.Push(s[A_Index])
            ns.Push(s.Length >= 4 + A_Index ? s[4 + A_Index] : NewSlot())
        }
        loop Max(0, s.Length - 8)
            ns.Push(s[8 + A_Index])
        m.slots := ns
    } else if (old = 8 && n = 4) {
        s := m.slots
        ns := [s[1], s[3], s[5], s[7], s[2], s[4], s[6], s[8]]
        loop Max(0, s.Length - 8)
            ns.Push(s[8 + A_Index])
        m.slots := ns
    }
    m.count := n
    PadSlots(m)
    if (Ed.slot > n)
        Ed.slot := 1
    Changed()
    EdLoadMenu()
}

; ── slot handlers ──

EdLabel(*) {
    if Ed.loading
        return
    sl := CurSlot()
    if (sl.label == Ed.eLabel.Value)
        return
    sl.label := Ed.eLabel.Value
    Changed()
    EdRefreshSlotList()
}

EdRefreshSlotList() {
    m := CurMenu()
    Ed.loading := true
    items := ["Centre: a quick tap"]
    loop m.count
        items.Push(Place(m.count, A_Index) ": " SlotTitle(m.slots[A_Index]))
    Ed.ddSlot.Delete()
    Ed.ddSlot.Add(items)
    Ed.ddSlot.Value := Ed.slot + 1
    Ed.loading := false
}

EdIcon(*) {
    if Ed.loading
        return
    sl := CurSlot()
    if (sl.icon == Ed.eIcon.Value)
        return
    sl.icon := Ed.eIcon.Value
    Changed()
}

EdIconPick(*) {
    if Ed.loading
        return
    v := (Ed.ddIcon.Value = 1) ? "" : Ed.ddIcon.Text
    CurSlot().icon := v
    Ed.loading := true
    Ed.eIcon.Value := v
    Ed.loading := false
    Changed()
}

EdColor(*) {
    if Ed.loading
        return
    CurSlot().color := Ed.ddColor.Text
    Changed()
}

EdType(*) {
    if Ed.loading
        return
    sl := CurSlot()
    types := (Ed.slot = 0) ? TAP_TYPES : SLOT_TYPES
    t := types[Ed.ddType.Value][1]
    if (t = sl.type)
        return
    sl.type := t
    sl.value := ""
    if (Ed.slot = 0)
        EdSyncTap()
    EdValueRow()
    Changed(Ed.slot = 0)
    EdRefreshSlotList()
    if (t = "keys")
        EdValButton()                        ; straight to recording
}

EdValue(ctrl, *) {
    if Ed.loading
        return
    sl := CurSlot()
    if (sl.value == ctrl.Value)
        return
    sl.value := ctrl.Value
    EdHint()
    Changed()
}

EdSub(*) {
    if Ed.loading
        return
    CurSlot().value := Ed.ddSub.Text
    Changed()
    EdRefreshSlotList()
}

EdValButton(*) {
    sl := CurSlot()
    switch sl.type {
        case "keys":
            k := RecordKeys()
            if (k = "")
                return
            sl.value := k
            if (sl.label = "" && Ed.slot > 0)
                sl.label := KeysText(k)
        case "run":
            f := FileSelect(3, , "Choose a program or file")
            if (f = "")
                return
            sl.value := f
        case "menu":
            n := AskName("Name for the new wheel:")
            if (n = "")
                return
            Menus.Push(NewMenu(n, "", "", true, "native", 8))
            sl.value := n
            if (sl.label = "")
                sl.label := n
            Changed(false, true)
        case "rclick":
            p := EdReadMenu()
            if (p = "")
                return
            sl.value := p
            if (sl.label = "" && Ed.slot > 0) {
                parts := StrSplit(p, ">")
                sl.label := Trim(parts[parts.Length])
            }
        default:
            return
    }
    Changed()
    EdLoadSlot()
}

EdTarget(*) {
    if Ed.loading
        return
    sl := CurSlot()
    i := Ed.ddTarget.Value
    if (i <= TARGETS.Length)
        sl.target := TARGETS[i][1]
    else if (i = TARGETS.Length + 1) {
        exe := PickProgram()
        if (exe != "")
            sl.target := exe
        EdValueRow()
    } else
        return
    Changed()
}

EdTry(*) {
    sl := CloneSlot(CurSlot())
    loop 3 {
        Toast("Running “" SlotTitle(sl) "” in " (4 - A_Index) "… (put the pointer where it should happen)", 1100)
        Sleep(1000)
    }
    MouseGetPos(&x, &y, &win)
    FireSlot(sl, win, x, y)
}

EdMoveSlot(dir) {
    m := CurMenu()
    i := Ed.slot
    if (i < 1)
        return
    j := Mod(i - 1 + dir + m.count, m.count) + 1
    t := m.slots[i]
    m.slots[i] := m.slots[j]
    m.slots[j] := t
    Ed.slot := j
    Changed()
    EdLoadSlot()
}

EdClear(*) {
    if (Ed.slot = 0) {
        CurMenu().tap := NewSlot("", "native")
        EdSyncTap()
        Changed(true)
    } else {
        CurMenu().slots[Ed.slot] := NewSlot()
        Changed()
    }
    EdLoadSlot()
}

; ── settings handlers ──

EdSetting(*) {
    if Ed.loading
        return
    Conf["Size"] := Ed.ddSize.Text
    Conf["ShowDelay"] := ToInt(Ed.eDelay.Value, 180)
    Conf["Confirm"] := Ed.cConfirm.Value
    Conf["ReturnPointer"] := Ed.cReturn.Value
    Changed()
}

EdStartup(*) {
    lnk := A_Startup "\RadWheel.lnk"
    try {
        if Ed.cStartup.Value
            FileCreateShortcut(A_ScriptFullPath, lnk, A_ScriptDir)
        else if FileExist(lnk)
            FileDelete(lnk)
    } catch as e
        MsgBox("Couldn't change the startup shortcut: " e.Message, APP, "Icon!")
}

EdProgramsDlg(*) {
    pg := Gui("+Owner" Ed.gui.Hwnd " +ToolWindow", "Programs")
    pg.BackColor := "1F2128"
    pg.SetFont("s10 cE6E8EB", "Segoe UI")
    pg.Add("Text", "w460", "PowerScribe program(s), separated by commas:")
    e1 := InField(pg.Add("Edit", "w460", Conf["PsExes"]))
    pg.Add("Text", "w460", "PACS program(s):")
    e2 := InField(pg.Add("Edit", "w460", Conf["PacsExes"]))
    pg.Add("Text", "w460", "PACS viewer window title contains (so keys go to the "
        . "viewer, not the worklist; blank = any PACS window):")
    e3 := InField(pg.Add("Edit", "w460", Conf["PacsViewerTitle"]))
    pg.Add("Text", "w460 cA9B1BD", "Tip: hover a window and use the tray icon's "
        . "Window Spy to read its program (ahk_exe).")
    ok := pg.Add("Button", "w100 Default", "OK")
    ok.OnEvent("Click", Save)
    pg.Add("Button", "x+10 w100", "Cancel").OnEvent("Click", (*) => pg.Destroy())
    pg.Show()
    Save(*) {
        Conf["PsExes"] := Trim(e1.Value)
        Conf["PacsExes"] := Trim(e2.Value)
        Conf["PacsViewerTitle"] := Trim(e3.Value)
        pg.Destroy()
        Changed(true)
    }
}

EdHelp(*) {
    MsgBox("USING A WHEEL`n"
        . "• Hold the button, move toward a command, let go. Fast = fires on "
        . "direction alone, no drawing.`n"
        . "• Hold still and the wheel appears so you can read it.`n"
        . "• Let go in the centre, press Esc or click to cancel.`n"
        . "• A slot with › opens another wheel: rest on it, or move straight "
        . "across it. Letting go on it keeps that wheel open for a click.`n"
        . "• While a wheel is open, keys 1-9 pick slot 1-9.`n`n"
        . "SETTING UP`n"
        . "• Pick a wheel at the top, choose its button, how holding and "
        . "tapping behave, and where it works.`n"
        . "• Click a slot in the picture (or the centre, for the tap) and "
        . "choose what it does on the right.`n"
        . "• “Pick an item from the right-click menu” reaches PACS commands "
        . "that have no shortcut. Use Read menu… to choose from a list.`n"
        . "• Practice ▶ shows the wheel without sending anything.`n`n"
        . "IF SOMETHING GOES WRONG`n"
        . "• Ctrl+Alt+Shift+F12 releases every button and key.`n"
        . "• Pause (here or in the tray) makes every button normal.`n"
        . "• Open this window: Ctrl+Alt+Shift+F10 or double-click the tray icon.",
        APP " help", "Iconi")
}

; The running programs with a window, for "Works in" and "Send to".
PickProgram() {
    seen := Map(), list := []
    seen.CaseSense := "Off"
    for h in WinGetList() {
        try {
            if (WinGetTitle("ahk_id " h) = "")
                continue
            exe := WinGetProcessName("ahk_id " h)
            if (!seen.Has(exe) && exe != "explorer.exe") {
                seen[exe] := 1
                list.Push(exe)
            }
        }
    }
    res := {v: ""}
    pg := Gui("+Owner" Ed.gui.Hwnd " +ToolWindow", "Choose a program")
    pg.BackColor := "1F2128"
    pg.SetFont("s10 cE6E8EB", "Segoe UI")
    pg.Add("Text", "w340", "Pick a running program, or type its .exe name:")
    lb := InField(pg.Add("ListBox", "w340 r12", list))
    edt := InField(pg.Add("Edit", "w340"))
    lb.OnEvent("Change", (*) => edt.Value := lb.Text)
    lb.OnEvent("DoubleClick", Ok)
    pg.Add("Button", "w100 Default", "OK").OnEvent("Click", Ok)
    pg.Add("Button", "x+10 w100", "Cancel").OnEvent("Click", (*) => pg.Destroy())
    hwnd := pg.Hwnd
    pg.Show()
    WinWaitClose("ahk_id " hwnd)
    return res.v
    Ok(*) {
        res.v := Trim(edt.Value)
        pg.Destroy()
    }
}

; Read the real right-click menu (and two levels of submenus) and let the
; user pick an item from a tree. Returns "A > B" or "".
EdReadMenu() {
    if (MsgBox("After you press OK, point at a PACS image (or wherever you "
        . "would right-click) and keep still.`n`nIn 3 seconds RadWheel "
        . "right-clicks there and reads the menu and its submenus. The menu "
        . "flashes open and closed for a moment; nothing is chosen.",
        APP, "OKCancel Iconi") != "OK")
        return ""
    loop 3 {
        Toast("Reading the right-click menu in " (4 - A_Index) "…", 1100)
        Sleep(1000)
    }
    MouseGetPos(&x, &y)
    tree := CtxRun("", x, y, "list")
    if (!IsObject(tree) || !tree.Length) {
        MsgBox("Couldn't read a menu there. You can still type the item's text "
            . "(e.g. Measurements > Ellipse), or a position path like #2 > #3.",
            APP, "Icon!")
        return ""
    }
    res := {v: ""}
    paths := Map()
    pg := Gui("+Owner" Ed.gui.Hwnd, "Pick a menu item")
    pg.BackColor := "1F2128"
    pg.SetFont("s10 cE6E8EB", "Segoe UI")
    pg.Add("Text", "w420", "Double-click an item (or pick a submenu to open it "
        . "and leave it open):")
    tv := pg.Add("TreeView", "w420 h380 Background161920 cE6E8EB")
    AddNodes(tree, 0, "")
    pg.Add("Button", "w110 Default", "Use this").OnEvent("Click", Ok)
    pg.Add("Button", "x+10 w100", "Cancel").OnEvent("Click", (*) => pg.Destroy())
    tv.OnEvent("DoubleClick", Ok)
    hwnd := pg.Hwnd
    pg.Show()
    WinWaitClose("ahk_id " hwnd)
    return res.v

    AddNodes(nodes, parent, prefix) {
        for n in nodes {
            p := (prefix = "") ? n.name : prefix " > " n.name
            id := tv.Add(n.name (n.popup ? "  ›" : ""), parent)
            paths[id] := p
            if n.kids.Length
                AddNodes(n.kids, id, p)
        }
    }
    Ok(*) {
        id := tv.GetSelection()
        if (id && paths.Has(id)) {
            res.v := paths[id]
            pg.Destroy()
        }
    }
}

; ── §13  START ──────────────────────────────────────────────────────────────

if !A_IsCompiled && FileExist(A_ScriptDir "\radwheel.ico")
    TraySetIcon(A_ScriptDir "\radwheel.ico")
A_IconTip := APP ": hold your menu button"
A_TrayMenu.Delete()
A_TrayMenu.Add("Set up radial menus…", EdShow)
A_TrayMenu.Add("Pause RadWheel", TogglePause)
A_TrayMenu.Add("Release stuck keys", Unstick)
A_TrayMenu.Add()
A_TrayMenu.Add("Reload", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Set up radial menus…"

DllCall("LoadLibrary", "str", "oleacc", "ptr")
GdipStart()
Overlay.Init()
InstallKeybdHook()
InstallMouseHook()
firstRun := LoadConfig()
RmCheck()
RegisterHotkeys()
SetTimer(RmCheck, 3000)
OnExit(Cleanup)
SetTimer(PreWarm, -700)

Hotkey("^!+F10", EdShow)
Hotkey("^!+F12", Unstick)

if firstRun
    EdShow()
else
    TrayTip("Hold your menu button and flick. Double-click the tray icon to set up.",
        APP " is running", "Mute")
