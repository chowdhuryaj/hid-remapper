#Requires AutoHotkey v2.0
#SingleInstance Force
; PSOne-DictateTest.ahk -- try PowerScribe One's own record button.
;
; Ctrl+Alt+D  presses PowerScribe One's record button (the same button the
;             mic's record key works) WITHOUT bringing PowerScribe forward.
;             Click into PACS first, then press it: dictation should start
;             and PACS should stay in front. Press again to stop.
; Ctrl+Alt+F  lists elements of the field navigator / field pane (no report
;             text is read), to
;             see whether next/previous field can be done the same way.
;             The list goes to the clipboard.
; Esc         exits this test.
;
; Nothing else is touched. Run it next to RadMapper; it uses its own keys.

PS_EXES := ["Nuance.PSOne.exe"]
REC_ID := "AutId_FieldTabPane_RecordingButton"

uia := ComObject("{ff48dba4-60ef-4201-aa87-54103eef594e}",
    "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
cond := 0
ComCall(21, uia, "ptr*", &cond)              ; CreateTrueCondition
TrayTip("Ctrl+Alt+D = record button, Ctrl+Alt+F = list fields, Esc = exit",
    "PS One dictate test")

^!d:: {
    t0 := A_TickCount
    el := FindByAutomationId(REC_ID)
    if !el {
        Tip("Record button not found (is a report open in PowerScribe One?)")
        return
    }
    before := ToggleState(el)
    ok := ToggleIt(el)
    Sleep(150)
    after := ToggleState(el)
    ObjRelease(el)
    Tip((ok ? "Pressed" : "Could not press") " the record button in "
        . (A_TickCount - t0) " ms. State " StateName(before) " -> "
        . StateName(after) ". PowerScribe in front: "
        . (WinActive("ahk_exe Nuance.PSOne.exe") ? "yes" : "no"))
}

^!f:: {
    list := ""
    for hwnd in PsWindows() {
        root := 0
        try ComCall(6, uia, "ptr", hwnd, "ptr*", &root)
        if !root
            continue
        arr := 0, n := 0
        try ComCall(6, root, "int", 4, "ptr", cond, "ptr*", &arr)
        if arr
            ComCall(3, arr, "int*", &n)
        loop n {
            el := 0
            ComCall(4, arr, "int", A_Index - 1, "ptr*", &el)
            if !el
                continue
            ct := 0
            try ComCall(21, el, "int*", &ct)
            aid := BStrProp(el, 29), cls := BStrProp(el, 30)
            ; Anything that looks like part of the field navigator or the
            ; field tab pane, whatever its control type.
            if RegExMatch(aid " " cls, "i)field|navig|section|tabpane|merge|pick") {
                ; Names only for non-text elements: report text and the
                ; patient banner are never copied.
                nm := (ct = 50020 || ct = 50004 || ct = 50030) ? "-" : Clip(BStrProp(el, 23))
                list .= ct " | " nm " | " aid " | " cls
                    . " | invoke " (HasPattern(el, 10000) ? "y" : "n")
                    . " select " (HasPattern(el, 10010) ? "y" : "n")
                    . " toggle " (HasPattern(el, 10015) ? "y" : "n")
                    . " expand " (HasPattern(el, 10005) ? "y" : "n") "`n"
            }
            ObjRelease(el)
        }
        if arr
            ObjRelease(arr)
        ObjRelease(root)
    }
    A_Clipboard := (list = "") ? "(no field elements found)" : list
    MsgBox("Field list copied to the clipboard ("
        . StrSplit(Trim(list, "`n"), "`n").Length " entries). Look it over,"
        . " then paste it to Claude.", "PS One dictate test", "Iconi")
}

Esc::ExitApp

PsWindows() {
    out := []
    for exe in PS_EXES
        for hwnd in WinGetList("ahk_exe " exe)
            out.Push(hwnd)
    return out
}

; The first element (in any PowerScribe window) with this AutomationId, as a
; raw pointer the caller releases; 0 if none.
FindByAutomationId(aid) {
    for hwnd in PsWindows() {
        root := 0
        try ComCall(6, uia, "ptr", hwnd, "ptr*", &root)  ; ElementFromHandle
        if !root
            continue
        arr := 0, n := 0, hit := 0
        try ComCall(6, root, "int", 4, "ptr", cond, "ptr*", &arr) ; FindAll
        if arr
            ComCall(3, arr, "int*", &n)
        loop n {
            el := 0
            ComCall(4, arr, "int", A_Index - 1, "ptr*", &el)
            if !el
                continue
            if (!hit && BStrProp(el, 29) = aid) {
                hit := el
                continue
            }
            ObjRelease(el)
        }
        if arr
            ObjRelease(arr)
        ObjRelease(root)
        if hit
            return hit
    }
    return 0
}

TogglePat(el) {
    p := 0
    try ComCall(16, el, "int", 10015, "ptr*", &p)   ; GetCurrentPattern(Toggle)
    if !p
        return 0
    try {
        tp := ComObjQuery(p, "{94cf8058-9b8d-4ab9-8bfd-4cd0a33c8c70}")
    } catch {
        tp := 0
    }
    ObjRelease(p)
    return tp
}

ToggleIt(el) {
    tp := TogglePat(el)
    if !tp
        return false
    try {
        ComCall(3, tp)                               ; Toggle()
        return true
    }
    return false
}

ToggleState(el) {
    tp := TogglePat(el)
    if !tp
        return -1
    st := -1
    try ComCall(4, tp, "int*", &st)                  ; get_CurrentToggleState
    return st
}

StateName(s) => s = 0 ? "off" : s = 1 ? "on" : s = 2 ? "mixed" : "?"

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
    try ComCall(16, el, "int", id, "ptr*", &p)
    if p {
        ObjRelease(p)
        return true
    }
    return false
}

Clip(s) => StrLen(s) > 60 ? SubStr(s, 1, 57) "..." : s

Tip(msg) {
    ToolTip(msg)
    SetTimer(() => ToolTip(), -4000)
}
