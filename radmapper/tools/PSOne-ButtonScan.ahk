#Requires AutoHotkey v2.0
#SingleInstance Force
; PSOne-ButtonScan.ahk -- one-time scan, changes nothing.
;
; Lists the buttons PowerScribe One exposes to Windows UI Automation (the
; accessibility interface), so we can tell whether dictate and next/previous
; field can be pressed directly, without bringing PowerScribe to the front.
;
; Only BUTTON-like elements are listed (buttons, toggle/split buttons, check
; boxes, menu items), never text: the report and the patient banner are not
; read. Still, look the result over before pasting it anywhere.
;
; Use: open PowerScribe One with a report open (so the dictation controls are
; showing), double-click this file, wait for the "done" box. The result is in
; the clipboard and in PSOne-ButtonScan.txt next to this file.

PS_EXES := ["Nuance.PSOne.exe", "Nuance.PowerScribe360.exe"]
WANT := Map(50000, "Button", 50002, "CheckBox", 50011, "MenuItem",
    50031, "SplitButton", 50005, "Hyperlink", 50019, "TabItem")
UIA_InvokePatternId := 10000
UIA_TogglePatternId := 10015

try uia := ComObject("{ff48dba4-60ef-4201-aa87-54103eef594e}",
    "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
catch as e {
    MsgBox("UI Automation is not available: " e.Message, "PS button scan", "Iconx")
    ExitApp
}
cond := 0
ComCall(21, uia, "ptr*", &cond)               ; CreateTrueCondition

out := "PowerScribe button scan  -  AutoHotkey " A_AhkVersion
    . "  -  " FormatTime(, "yyyy-MM-dd HH:mm") "`n"
    . "type | name | automationId | class | enabled | invoke | toggle`n"
    . "------------------------------------------------------------------`n"
; PowerScribe windows: by the known exe names, and also any window whose exe
; or title says PowerScribe / PSOne / Nuance, in case this site's exe differs.
targets := []
seenHwnd := Map()
for hwnd in WinGetList() {
    exe := "", title := ""
    try exe := WinGetProcessName("ahk_id " hwnd)
    try title := WinGetTitle("ahk_id " hwnd)
    isPs := false
    for e in PS_EXES
        isPs := isPs || (exe = e)
    isPs := isPs || RegExMatch(exe, "i)powerscribe|psone|nuance")
        || RegExMatch(title, "i)powerscribe")
    if (isPs && !seenHwnd.Has(hwnd)) {
        seenHwnd[hwnd] := true
        targets.Push({hwnd: hwnd, exe: exe})
    }
}
found := 0
for t in targets {
    hwnd := t.hwnd, exe := t.exe
    {
        cls := ""
        try cls := WinGetClass("ahk_id " hwnd)
        out .= "`n== window " Format("0x{:X}", hwnd) " (" exe ", class "
            . cls ")`n"
        found += 1
        root := 0
        try ComCall(6, uia, "ptr", hwnd, "ptr*", &root)   ; ElementFromHandle
        if !root {
            out .= "   (not readable)`n"
            continue
        }
        arr := 0
        try ComCall(6, root, "int", 4, "ptr", cond, "ptr*", &arr) ; FindAll, descendants
        n := 0
        if arr
            ComCall(3, arr, "int*", &n)                ; get_Length
        shown := 0
        loop n {
            el := 0
            ComCall(4, arr, "int", A_Index - 1, "ptr*", &el)  ; GetElement
            if !el
                continue
            ct := 0
            try ComCall(21, el, "int*", &ct)           ; get_CurrentControlType
            if WANT.Has(ct) {
                en := 0
                try ComCall(28, el, "int*", &en)       ; get_CurrentIsEnabled
                out .= WANT[ct] " | " Clip(BStrProp(el, 23)) " | "
                    . BStrProp(el, 29) " | " BStrProp(el, 30) " | "
                    . (en ? "yes" : "no") " | "
                    . (HasPattern(el, UIA_InvokePatternId) ? "yes" : "no") " | "
                    . (HasPattern(el, UIA_TogglePatternId) ? "yes" : "no") "`n"
                shown += 1
            }
            ObjRelease(el)
        }
        out .= "   (" shown " of " n " elements listed)`n"
        if arr
            ObjRelease(arr)
        ObjRelease(root)
    }
}
ObjRelease(cond)
if !found {
    ; Name the running programs, so the right one can be added. Exe names
    ; only, no window titles (those can carry patient names).
    exes := Map()
    for hwnd in WinGetList() {
        try exes[WinGetProcessName("ahk_id " hwnd)] := true
    }
    out .= "`nNo PowerScribe window found. Programs with a window open now:`n"
    for e in exes
        out .= "   " e "`n"
}

outFile := A_ScriptDir "\PSOne-ButtonScan.txt"
try FileDelete(outFile)
FileAppend(out, outFile, "UTF-8")
A_Clipboard := out
MsgBox("Done. " found " PowerScribe window(s) scanned.`n`nThe result is in the "
    . "clipboard and in`n" outFile "`n`nLook it over, then paste it to Claude.",
    "PS button scan", "Iconi")
ExitApp

; A BSTR property of an element (23 name, 29 automation id, 30 class).
BStrProp(el, idx) {
    b := 0
    try ComCall(idx, el, "ptr*", &b)
    if !b
        return ""
    s := StrGet(b, "UTF-16")
    DllCall("OleAut32\SysFreeString", "ptr", b)
    return StrReplace(StrReplace(s, "`n", " "), "`r", " ")
}

HasPattern(el, id) {
    p := 0
    try ComCall(16, el, "int", id, "ptr*", &p)   ; GetCurrentPattern
    if p {
        ObjRelease(p)
        return true
    }
    return false
}

Clip(s) => StrLen(s) > 60 ? SubStr(s, 1, 57) "..." : s
