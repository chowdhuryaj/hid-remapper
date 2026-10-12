#Requires AutoHotkey v2.0
#SingleInstance Force
;==============================================================================
;  ScrollCapture  --  frame-by-frame scrolling captures + annotation bundles
;
;  Shift+F2        Start / stop a scrolling capture on the monitor under the
;                  cursor. Each step grabs the monitor, keeps the frame if it
;                  changed, then sends Shift+Space. It stops by itself after
;                  StopAfterSame identical frames in a row (end of scroll), at
;                  MaxFrames, or on Esc.
;  Ctrl+Shift+F2   Single still of the monitor under the cursor. Goes into the
;                  current capture folder, or a new still folder if none runs.
;  Shift+F3        Annotate the last capture folder: tag frames, add notes, then
;                  "Export bundle" writes annotations.tsv + README.txt and zips
;                  the folder into <OutRoot>\bundles\ for handing back.
;
;  Output:  <OutRoot>\scroll-yyyyMMdd-HHmmss\frame_0001.png ...
;           <OutRoot>\still-yyyyMMdd-HHmmss\still_*.png
;  Tested on: nothing yet -- written on a Linux box. Run it on the workstation
;  once and check the first folder before relying on it.
;==============================================================================

; Per-monitor DPI awareness so MouseGetPos, MonitorGet and BitBlt use the same
; physical pixels on scaled displays.
DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

global Cfg := Map(
    "OutRoot",       A_MyDocuments "\ScrollCaptures",
    "StartDelayMs",  300,   ; after the single Shift+Space, before the first grab
    "IntervalMs",    150,   ; pace: one grab, then one wheel step, every this many ms.
                            ; Raise it if frames show a half-finished scroll; lower it for speed
    "WheelNotches",  3,     ; mouse-wheel notches down per step. More = bigger jump between
                            ; frames; fewer = more overlap (easier to stitch, slower to finish)
    "StopAfterSame", 3,     ; identical frames in a row = end of scroll
    "MaxFrames",     300    ; hard limit per scroll capture
)
global Sess := ""          ; active scroll capture (Map) or ""
global LastDir := ""       ; folder of the most recent capture, for the annotator
global Ann := ""           ; annotator state (Map) or ""
global AnnTags := ["", "start", "end", "duplicate", "bad", "still", "stitch here"]
global AnnTagLabels := ["(none)", "start", "end", "duplicate", "bad", "still", "stitch here"]

; ---- GDI+ (needed to write PNG files) ----
global gdipToken := 0
gdipIn := Buffer(24, 0)
NumPut("uint", 1, gdipIn, 0)                       ; GDI+ version 1
DllCall("gdiplus\GdiplusStartup", "ptr*", &gdipToken, "ptr", gdipIn, "ptr", 0)
OnExit((*) => DllCall("gdiplus\GdiplusShutdown", "ptr", gdipToken))

DirCreate(Cfg["OutRoot"])
TrayTip("Shift+F2 scroll capture`nCtrl+Shift+F2 still`nShift+F3 annotate", "ScrollCapture")

; ---- hotkeys ----
+F2::ToggleScroll()
^+F2::StillCapture()
+F3::OpenAnnotator()

#HotIf IsObject(Sess)
Esc::StopScroll("stopped with Esc")
#HotIf

; ============================================================================
;  Capture
; ============================================================================

ToggleScroll() {
    global Sess
    if IsObject(Sess) {
        StopScroll("stopped by hotkey")
        return
    }
    KeyWait("Shift")   ; let go of the Shift from Shift+F2 so it doesn't mix into Shift+Space
    KeyWait("Ctrl")
    ToolTip()          ; no tooltip on screen during the before/after check
    try {
        mon := MonitorUnderCursor()
        hwnd := PressStartKey(mon)   ; throws -- and nothing is saved -- unless the screen changed
    } catch as err {
        ToolTip("Scroll capture NOT started (nothing saved):`n" err.Message)
        SetTimer(() => ToolTip(), -5000)
        return
    }
    ; The pixel check only proves SOMETHING changed. You confirm the PHI is gone.
    if !ConfirmPhiHidden(mon, hwnd) {
        ToolTip("Scroll capture cancelled (nothing saved)")
        SetTimer(() => ToolTip(), -3000)
        return
    }
    dir := NewCaptureDir("scroll")   ; only now does anything get written to disk
    Sess := Map("dir", dir, "mon", mon, "n", 0, "same", 0, "last", "")
    ToolTip("Scroll capture on monitor " mon["n"] "  (Esc to stop)")
    SetTimer(CaptureTick, -1)        ; first grab now; the switch to IntervalMs happens after it
}

; Focuses the viewer under the cursor, sends Shift+Space there, and checks the
; monitor actually changed. If the key didn't land (wrong window focused, key
; dropped), the screen is unchanged and this throws, so no capture starts.
; Both comparison grabs stay in memory and are never written to disk.
PressStartKey(mon) {
    CoordMode("Mouse", "Screen")
    MouseGetPos(, , &hwnd)
    if !hwnd
        throw Error("No window under the cursor to send Shift+Space to")
    WinActivate("ahk_id " hwnd)
    if !WinWaitActive("ahk_id " hwnd, , 1)
        throw Error("Could not focus the window under the cursor")
    Sleep(250)   ; let the focus change finish repainting before the "before" grab
    before := GrabPixels(mon["l"], mon["t"], mon["w"], mon["h"])
    ; held key presses: some viewers ignore an instant down/up
    SendEvent("{Shift down}")
    Sleep(30)
    SendEvent("{Space down}")
    Sleep(50)
    SendEvent("{Space up}")
    Sleep(30)
    SendEvent("{Shift up}")
    Sleep(Cfg["StartDelayMs"])
    after := GrabPixels(mon["l"], mon["t"], mon["w"], mon["h"])
    if SameBuffer(before, after)
        throw Error("Shift+Space did not change the screen. Click the image viewer, then try again.")
    return hwnd
}

; Asks you to confirm, by eye, that no PHI is showing on the monitor about to
; be captured. Default is No, so Enter cancels. Nothing has been saved yet
; when this runs. Refocuses the viewer afterwards so the wheel lands there.
ConfirmPhiHidden(mon, hwnd := 0) {
    answer := MsgBox("Look at monitor " mon["n"] " now.`n`n"
        . "Is ALL PHI hidden (name, MRN, DOB, accession, dates)?`n`n"
        . "Yes = capture it`nNo = cancel, nothing is saved"
        , "ScrollCapture: confirm PHI hidden", "YesNo Icon! Default2 262144")   ; 262144 = always on top
    if (answer != "Yes")
        return false
    if hwnd {
        WinActivate("ahk_id " hwnd)
        WinWaitActive("ahk_id " hwnd, , 1)
    }
    Sleep(150)   ; let the dialog vanish from the screen before any grab
    return true
}

CaptureTick() {
    global Sess, Cfg
    Critical()          ; hotkeys (Esc, Shift+F2) wait until this step is finished
    s := Sess           ; work on a snapshot so a stop elsewhere can't clear it mid-step
    if !IsObject(s) {
        SetTimer(CaptureTick, 0)
        return
    }
    try {
        mon := s["mon"]
        tmp := s["dir"] "\_tmp.png"
        if !SaveRegion(mon["l"], mon["t"], mon["w"], mon["h"], tmp) {
            StopScroll("capture failed")
            return
        }
        if (s["n"] > 0 && SameFile(tmp, s["last"])) {
            FileDelete(tmp)
            s["same"] += 1
        } else {
            s["n"] += 1
            s["same"] := 0
            s["last"] := s["dir"] "\frame_" SubStr("0000" s["n"], -4) ".png"
            FileMove(tmp, s["last"], true)
        }
        if (s["same"] >= Cfg["StopAfterSame"]) {
            StopScroll("end of scroll (screen stopped changing)")
            return
        }
        if (s["n"] >= Cfg["MaxFrames"]) {
            StopScroll("reached MaxFrames")
            return
        }
        Loop Cfg["WheelNotches"]
            Click("WheelDown")   ; scroll the stack down for the next frame, one notch at a time
        if (s["n"] = 1)
            SetTimer(CaptureTick, Cfg["IntervalMs"])   ; switch from the start delay to the steady pace
    } catch as err {
        ; stop instead of letting the timer re-raise the same error every tick
        StopScroll("error: " err.Message)
    }
}

StopScroll(reason) {
    global Sess
    SetTimer(CaptureTick, 0)
    if !IsObject(Sess)
        return
    dir := Sess["dir"]
    frames := Sess["n"]
    mon := Sess["mon"]
    Sess := ""
    WriteText(dir "\session.txt"
        , "type: scroll`n"
        . "frames: " frames "`n"
        . "stopped: " reason "`n"
        . "monitor: " mon["n"] " (" mon["w"] "x" mon["h"] " at " mon["l"] "," mon["t"] ")`n"
        . "interval_ms: " Cfg["IntervalMs"] "`n"
        . "wheel_notches: " Cfg["WheelNotches"] "`n")
    ToolTip("Scroll capture done: " frames " frames`n" dir)
    SetTimer(() => ToolTip(), -3000)
}

StillCapture() {
    global Sess
    try {
        if IsObject(Sess) {
            mon := Sess["mon"]
            dir := Sess["dir"]
        } else {
            mon := MonitorUnderCursor()      ; before creating a folder, so a failure leaves nothing behind
            CoordMode("Mouse", "Screen")
            MouseGetPos(, , &hwnd)
            if !ConfirmPhiHidden(mon, hwnd) {
                ToolTip("Still cancelled (nothing saved)")
                SetTimer(() => ToolTip(), -2000)
                return
            }
            dir := NewCaptureDir("still")
        }
        file := dir "\still_" FormatTime(A_Now, "yyyyMMdd-HHmmss") "-" A_MSec ".png"
        ok := SaveRegion(mon["l"], mon["t"], mon["w"], mon["h"], file)
        ToolTip(ok ? "Still saved: " file : "Still FAILED")
    } catch as err {
        ToolTip("Still NOT saved: " err.Message)
    }
    SetTimer(() => ToolTip(), -2000)
}

NewCaptureDir(kind) {
    global LastDir, Cfg
    dir := Cfg["OutRoot"] "\" kind "-" FormatTime(A_Now, "yyyyMMdd-HHmmss")
    DirCreate(dir)
    LastDir := dir
    return dir
}

; The monitor under the cursor, straight from Win32 (GetCursorPos ->
; MonitorFromPoint -> GetMonitorInfo). The earlier MouseGetPos version used
; AHK's default CoordMode (relative to the active window, not the screen), so
; it could pick the wrong monitor. Everything here and in SaveRegion runs in
; the same per-monitor DPI context, so the rectangle is in the same physical
; pixels BitBlt uses.
MonitorUnderCursor() {
    DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "ptr", pt)
    if (A_PtrSize = 8)
        hMon := DllCall("MonitorFromPoint", "int64", NumGet(pt, 0, "int64"), "uint", 2, "ptr")  ; MONITOR_DEFAULTTONEAREST
    else
        hMon := DllCall("MonitorFromPoint", "int", NumGet(pt, 0, "int"), "int", NumGet(pt, 4, "int"), "uint", 2, "ptr")
    rc := MonitorRect(hMon)
    if !rc
        throw Error("Could not read the monitor under the cursor")
    return Map("n", MonitorIndexOf(rc), "l", rc[1], "t", rc[2], "w", rc[3] - rc[1], "h", rc[4] - rc[2])
}

; [left, top, right, bottom] of a monitor handle, or 0 on failure.
MonitorRect(hMon) {
    if !hMon
        return 0
    mi := Buffer(40, 0)
    NumPut("uint", 40, mi, 0)              ; MONITORINFO.cbSize
    if !DllCall("GetMonitorInfoW", "ptr", hMon, "ptr", mi)
        return 0
    return [NumGet(mi, 4, "int"), NumGet(mi, 8, "int"), NumGet(mi, 12, "int"), NumGet(mi, 16, "int")]
}

; AHK's monitor number for a rectangle, for the tooltip and session.txt only.
MonitorIndexOf(rc) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (l = rc[1] && t = rc[2] && r = rc[3] && b = rc[4])
            return A_Index
    }
    return "?"
}

; True only when the rectangle lies entirely inside ONE monitor. SaveRegion
; refuses anything else, so a capture can never include a second screen.
RectOnOneMonitor(x, y, w, h) {
    if (w <= 0 || h <= 0)
        return false
    rect := Buffer(16, 0)
    NumPut("int", x, "int", y, "int", x + w, "int", y + h, rect)
    hMon := DllCall("MonitorFromRect", "ptr", rect, "uint", 0, "ptr")   ; MONITOR_DEFAULTTONULL
    rc := MonitorRect(hMon)
    return rc && x >= rc[1] && y >= rc[2] && x + w <= rc[3] && y + h <= rc[4]
}

; Copies a screen rectangle and writes it as PNG. Returns true on success.
SaveRegion(x, y, w, h, path) {
    DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")   ; same pixel space as MonitorUnderCursor
    if !RectOnOneMonitor(x, y, w, h)
        throw Error("Capture refused: the area is not entirely on one monitor")
    hdc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0)     ; biSize
    NumPut("int", w, bi, 4)       ; biWidth
    NumPut("int", -h, bi, 8)      ; negative height = top-down rows
    NumPut("ushort", 1, bi, 12)   ; biPlanes
    NumPut("ushort", 32, bi, 14)  ; biBitCount
    pBits := 0
    hbm := DllCall("CreateDIBSection", "ptr", hdc, "ptr", bi, "uint", 0, "ptr*", &pBits, "ptr", 0, "uint", 0, "ptr")
    obm := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")
    sdc := DllCall("GetDC", "ptr", 0, "ptr")
    DllCall("gdi32\BitBlt"
        , "ptr", hdc, "int", 0, "int", 0, "int", w, "int", h
        , "ptr", sdc, "int", x, "int", y, "uint", 0x00CC0020 | 0x40000000)  ; SRCCOPY | CAPTUREBLT
    DllCall("ReleaseDC", "ptr", 0, "ptr", sdc)
    pBmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "ptr", hbm, "ptr", 0, "ptr*", &pBmp)
    DllCall("SelectObject", "ptr", hdc, "ptr", obm)
    DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", hdc)
    if !pBmp
        return false
    pCodec := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "wstr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "ptr", pCodec)  ; PNG encoder
    st := DllCall("gdiplus\GdipSaveImageToFile", "ptr", pBmp, "wstr", path, "ptr", pCodec, "ptr", 0, "int")
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBmp)
    return st = 0
}

; True when two files have identical bytes (PNG output is deterministic, so
; an unchanged screen gives an identical file).
; Raw 32-bit pixels of a screen rectangle, in memory only (nothing on disk).
; Same single-monitor guard as SaveRegion.
GrabPixels(x, y, w, h) {
    DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    if !RectOnOneMonitor(x, y, w, h)
        throw Error("Capture refused: the area is not entirely on one monitor")
    hdc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0)
    NumPut("int", w, bi, 4)
    NumPut("int", -h, bi, 8)
    NumPut("ushort", 1, bi, 12)
    NumPut("ushort", 32, bi, 14)
    pBits := 0
    hbm := DllCall("CreateDIBSection", "ptr", hdc, "ptr", bi, "uint", 0, "ptr*", &pBits, "ptr", 0, "uint", 0, "ptr")
    obm := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")
    sdc := DllCall("GetDC", "ptr", 0, "ptr")
    DllCall("gdi32\BitBlt"
        , "ptr", hdc, "int", 0, "int", 0, "int", w, "int", h
        , "ptr", sdc, "int", x, "int", y, "uint", 0x00CC0020 | 0x40000000)
    DllCall("ReleaseDC", "ptr", 0, "ptr", sdc)
    n := w * h * 4
    buf := Buffer(n)
    if pBits
        DllCall("msvcrt\memcpy", "ptr", buf, "ptr", pBits, "uptr", n, "cdecl ptr")
    DllCall("SelectObject", "ptr", hdc, "ptr", obm)
    DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", hdc)
    if !pBits
        throw Error("Screen grab failed")
    return buf
}

SameBuffer(a, b) {
    return a.Size = b.Size && DllCall("msvcrt\memcmp", "ptr", a, "ptr", b, "uptr", a.Size, "int") = 0
}

SameFile(a, b) {
    if (FileGetSize(a) != FileGetSize(b))
        return false
    fa := FileOpen(a, "r")
    fb := FileOpen(b, "r")
    n := fa.Length
    ba := Buffer(n)
    bb := Buffer(n)
    fa.RawRead(ba, n)
    fb.RawRead(bb, n)
    fa.Close()
    fb.Close()
    return DllCall("msvcrt\memcmp", "ptr", ba, "ptr", bb, "uptr", n, "int") = 0
}

WriteText(path, text) {
    f := FileOpen(path, "w", "UTF-8")
    f.Write(text)
    f.Close()
}

; ============================================================================
;  Annotator
; ============================================================================

OpenAnnotator() {
    global LastDir, Cfg
    dir := LastDir
    if !(dir && DirExist(dir)) {
        dir := DirSelect(Cfg["OutRoot"], 1, "Pick a capture folder to annotate")
        if !dir
            return
    }
    AnnotatorShow(dir)
}

AnnotatorShow(dir) {
    global Ann, AnnTags, AnnTagLabels
    AnnClose()

    text := ""
    Loop Files, dir "\*.png"
        text .= A_LoopFileName "`n"
    if (text = "") {
        MsgBox("No .png frames in:`n" dir)
        return
    }
    text := Sort(text)
    names := StrSplit(Trim(text, "`n"), "`n")

    ; read annotations already saved in this folder
    data := Map()
    tsv := dir "\annotations.tsv"
    if FileExist(tsv) {
        for line in StrSplit(FileRead(tsv, "UTF-8"), "`n", "`r") {
            p := StrSplit(line, "`t")
            if (p.Length >= 1 && p[1] != "" && p[1] != "frame")
                data[p[1]] := Map("tag", p.Length >= 2 ? p[2] : "", "note", p.Length >= 3 ? p[3] : "")
        }
    }

    g := Gui(, "Annotate")
    g.SetFont("s10", "Segoe UI")
    lb := g.Add("ListBox", "x10 y10 w260 h470", names)
    pic := g.Add("Picture", "x290 y10 w640 h380")          ; preview only, scaled to this box
    g.Add("Text", "x290 y405", "Tag")
    tagCtl := g.Add("DropDownList", "x330 y401 w200", AnnTagLabels)
    g.Add("Text", "x290 y440", "Note")
    noteCtl := g.Add("Edit", "x330 y437 w600")
    btnPrev := g.Add("Button", "x290 y475 w90", "< Prev")
    btnNext := g.Add("Button", "x390 y475 w90", "Next >")
    btnExport := g.Add("Button", "x490 y475 w200", "Export bundle")
    status := g.Add("Text", "x10 y490 w920", "")

    Ann := Map("g", g, "lb", lb, "pic", pic, "tag", tagCtl, "note", noteCtl, "status", status,
               "names", names, "data", data, "dir", dir, "idx", 0)

    lb.OnEvent("Change", (*) => AnnSelect(lb.Value))
    btnPrev.OnEvent("Click", (*) => AnnStep(-1))
    btnNext.OnEvent("Click", (*) => AnnStep(1))
    btnExport.OnEvent("Click", (*) => AnnExport())
    g.OnEvent("Close", (*) => AnnClose())
    g.Show()
    lb.Choose(1)
    AnnSelect(1)
}

AnnSelect(i) {
    global Ann, AnnTags
    if (!IsObject(Ann) || i < 1)
        return
    AnnSaveCurrent()
    Ann["idx"] := i
    name := Ann["names"][i]
    Ann["pic"].Value := Ann["dir"] "\" name
    rec := Ann["data"].Has(name) ? Ann["data"][name] : Map("tag", "", "note", "")
    ti := 1
    for k, t in AnnTags {
        if (t = rec["tag"])
            ti := k
    }
    Ann["tag"].Choose(ti)
    Ann["note"].Value := rec["note"]
    Ann["g"].Title := Format("Annotate  {1}/{2}  {3}", i, Ann["names"].Length, name)
}

AnnStep(d) {
    global Ann
    if !IsObject(Ann)
        return
    i := Min(Max(Ann["idx"] + d, 1), Ann["names"].Length)
    Ann["lb"].Choose(i)
    AnnSelect(i)
}

AnnSaveCurrent() {
    global Ann, AnnTags
    if (!IsObject(Ann) || Ann["idx"] < 1)
        return
    name := Ann["names"][Ann["idx"]]
    Ann["data"][name] := Map("tag", AnnTags[Ann["tag"].Value], "note", CleanField(Ann["note"].Value))
}

CleanField(s) {
    return StrReplace(StrReplace(StrReplace(s, "`t", " "), "`r", " "), "`n", " ")
}

; Writes annotations.tsv for the open annotator (one row per frame).
AnnWriteTsv() {
    global Ann
    AnnSaveCurrent()
    tsv := "frame`ttag`tnote`n"
    for name in Ann["names"] {
        rec := Ann["data"].Has(name) ? Ann["data"][name] : Map("tag", "", "note", "")
        tsv .= name "`t" rec["tag"] "`t" rec["note"] "`n"
    }
    WriteText(Ann["dir"] "\annotations.tsv", tsv)
}

AnnExport() {
    global Ann, Cfg
    if !IsObject(Ann)
        return
    AnnWriteTsv()
    dir := Ann["dir"]
    WriteText(dir "\README.txt"
        , "ScrollCapture bundle`n"
        . "frames: " Ann["names"].Length " (PNG, in capture order: frame_0001 is the first grab)`n"
        . "annotations.tsv: one row per frame -- frame, tag, note`n"
        . "tags: start / end = top and bottom of the wanted content; duplicate = repeat frame;`n"
        . "      bad = unusable frame; still = single screenshot; stitch here = join point`n"
        . "session.txt: how the capture ended and which monitor was used`n")

    SplitPath(dir, &base)
    bundles := Cfg["OutRoot"] "\bundles"
    DirCreate(bundles)
    zip := bundles "\" base ".zip"
    if FileExist(zip)
        FileDelete(zip)
    ps := "Compress-Archive -Path '" dir "\*' -DestinationPath '" zip "' -Force"
    cmd := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "' ps '"'
    RunWait(cmd, , "Hide")
    if FileExist(zip) {
        Ann["status"].Value := "Bundle written: " zip
        Run(Format('explorer.exe /select,"{1}"', zip))
    } else {
        Ann["status"].Value := "Zip failed -- annotations.tsv is still in the folder."
    }
}

; Closing (or reopening on another folder) keeps the notes: they are written to
; annotations.tsv first, so nothing typed in the annotator is lost.
AnnClose() {
    global Ann
    if IsObject(Ann) {
        AnnWriteTsv()
        Ann["g"].Destroy()
    }
    Ann := ""
}
