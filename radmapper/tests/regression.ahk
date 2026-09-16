#Requires AutoHotkey v2.0
#SingleInstance Off
RM_TEST := true
#Include ../RadMapper.ahk

Check(value, message) {
    if !value
        throw Error(message)
}
Rejects(fn, message) {
    rejected := false
    try fn()
    catch
        rejected := true
    Check(rejected, message)
}

try {
    Check(JsonLoad('{"name":"PACS","n":-1.25e2}')["n"] = -125, "JSON number")
    for bad in ['{} garbage', '01', '1.', '[1,]', '{"a":1,}', '"line`nbreak"']
        Rejects(() => JsonLoad(bad), "Invalid JSON accepted: " bad)
    Check(MGet([], "missing", 7) = 7, "Non-map lookup must use fallback")
    Check(MGet({name: "object"}, "name", 7) = 7, "Plain object is not a config map")

    four := []
    for name in ["Up", "Right", "Down", "Left"]
        four.Push(MenuSlice(name, "keys", name))
    eight := ResizeMenuSlices(four, 8)
    for i, name in ["Up", "Right", "Down", "Left"]
        Check(eight[2 * i - 1]["label"] = name, "Growing moved " name)
    for i in [2, 4, 6, 8]
        Check(eight[i]["action"]["type"] = "none", "New diagonal is not empty")
    back := ResizeMenuSlices(eight, 4)
    for i, sl in four
        Check(back[i]["label"] = sl["label"], "Round trip moved a direction")
    for i, delta in [[0,-100], [100,0], [0,100], [-100,0]]
        Check(Abs(RadialAngle(delta[1], delta[2]) - (i - 1) * 90) < 0.01, "Compass angle")

    g_Cfg := Map("bindings", [NewBinding("*", "*", "", "XButton1", "hold", "radial", "Old"),
        NewBinding("*", "*", "", "XButton2", "hold", "radial", "")],
        "menus", [Map("name", "Nested", "slices", [MenuSlice("Open", "radial", "Old")])])
    RenameMenuBindings("Old", "New")
    Check(g_Cfg["bindings"][1]["action"]["value"] = "New", "Rename broke a binding")
    Check(g_Cfg["bindings"][2]["action"]["value"] = "", "Rename changed auto selection")
    Check(g_Cfg["menus"][1]["slices"][1]["action"]["value"] = "New", "Nested rename")
    ValidateCfgShape(g_Cfg)
    for bad in [[], Map("bindings", "bad"), Map("bindings", [], "settings", []),
        Map("bindings", [], "menus", [Map("name", "Bad", "slices", "bad")])]
        Rejects(() => ValidateCfgShape(bad), "Malformed config accepted")

    g_Enabled := false
    RM_Send := (*) => Check(false, "Paused radial menu sent input")
    RadialFireSlice(Map("type", "keys", "value", "x"), "Test", 0)

    g_CfgRecoveryBlocked := true
    Check(!SaveCfg() && g_CfgDirty, "Recovery block must prevent saving")
    g_CfgRecoveryBlocked := false

    testDir := A_Temp "\RadMapper-regression-" A_TickCount
    DirCreate(testDir)
    CFG_PATH := testDir "\config.json"
    Check(SaveCfg(), "Valid save failed")
    Check(!g_CfgDirty && FileExist(CFG_PATH), "Successful save state")
    CFG_PATH := testDir "\missing\config.json"
    Check(!SaveCfg(), "Invalid save unexpectedly succeeded")
    Check(g_CfgDirty, "Failed save lost dirty state")
    FileDelete(testDir "\config.json")
    DirDelete(testDir)
    ; v0.6.2: stations, adaptive layouts, window placement grammar, keyboard pointer geometry
    mons := StationSort([
        {l: 1920, t: 0, r: 3968, b: 1536, wl: 1920, wt: 0, wr: 3968, wb: 1536, w: 2048, h: 1536},
        {l: 0, t: 0, r: 1920, b: 1080, wl: 0, wt: 0, wr: 1920, wb: 1040, w: 1920, h: 1080},
        {l: 3968, t: 0, r: 5888, b: 1080, wl: 3968, wt: 0, wr: 5888, wb: 1080, w: 1920, h: 1080}])
    Check(mons[1].w = 1920 && mons[2].w = 2048 && mons[3].idx = 3, "Monitors sort left to right")
    Check(StationKey(mons) = "1920x1080|2048x1536|1920x1080", "Station key")
    Check(StationCount(StationKey(mons)) = 3, "Station count")
    res := ImagingMons(mons, "auto")
    Check(res.Count = 1 && res.Has(2), "Auto imaging = the 3 MP screen")
    Check(ImagingMons(mons, "none").Count = 0, "Imaging none")
    res := ImagingMons(mons, "1, 3")
    Check(res.Count = 2 && res.Has(1) && res.Has(3), "Imaging list")
    Check(ImagingMons(mons, "1,2,3").Count = 0, "Never reserve every screen")
    same := StationSort([
        {l: 0, t: 0, r: 1920, b: 1080, wl: 0, wt: 0, wr: 1920, wb: 1040, w: 1920, h: 1080},
        {l: 1920, t: 0, r: 3840, b: 1080, wl: 1920, wt: 0, wr: 3840, wb: 1040, w: 1920, h: 1080}])
    Check(ImagingMons(same, "auto").Count = 0, "Equal screens reserve nothing")
    Check(ImagingWords(ImagingMons(mons, "3,1")) = "screens 1 and 3", "Imaging words")
    Check(MonIndexAt(mons, 2000, 100) = 2 && MonIndexAt(mons, -50, 100) = 1
       && MonIndexAt(mons, 9000, 100) = 3, "Monitor at a point, nearest off-screen")

    four := Map("name", "Reading", "station", "1920x1080|2048x1536|1920x1080|1920x1080", "slots", [])
    s1 := Map("mon", 1), s2 := Map("mon", 2), s3 := Map("mon", 3), s4 := Map("mon", 4)
    none := Map()
    Check(LayoutMonFor(s1, four, mons, none, false) = 1 && LayoutMonFor(s2, four, mons, none, false) = 2
       && LayoutMonFor(s3, four, mons, none, false) = 2 && LayoutMonFor(s4, four, mons, none, false) = 3,
       "Fold four screens onto three")
    res := ImagingMons(mons, "auto")
    Check(LayoutMonFor(s3, four, mons, res, false) != 2, "A non-viewer slot leaves the imaging screen")
    Check(LayoutMonFor(s1, four, mons, res, true) = 2, "The viewer slot prefers the imaging screen")
    here := Map("name", "Here", "station", StationKey(mons), "slots", [])
    Check(LayoutMonFor(s3, here, mons, res, false) = 3, "Same station keeps the screen")
    slot := Map("mon", 1, "fx", 0.25, "fy", 0.5, "fw", 0.5, "fh", 0.5, "state", "normal",
        "exe", "x.exe", "title", "t")
    one := Map("name", "One", "station", "1920x1080", "slots", [slot])
    t := LayoutSlotTarget(slot, one, mons, none, Map())
    ; a one-screen arrangement lands on the middle of three; fractions of
    ; that screen's work area (2048x1536 at x=1920)
    Check(t.adapted && t.mon.idx = 2 && t.x = 2432 && t.y = 768 && t.w = 1024 && t.h = 768,
        "Fractions re-applied to the mapped screen's work area")
    res := ImagingMons(mons, "auto")
    t := LayoutSlotTarget(slot, one, mons, res, Map())
    Check(t.mon.idx = 1 && t.x = 480 && t.y = 520 && t.w = 960 && t.h = 520,
        "Pushed off the imaging screen onto the colour one")
    exact := Map("mon", 3, "x", 4000, "y", 10, "w", 800, "h", 600, "fx", 0.1, "fy", 0.1,
        "fw", 0.4, "fh", 0.5, "exe", "x.exe", "title", "t")
    lay4 := Map("name", "Same", "station", StationKey(mons), "slots", [exact])
    t := LayoutSlotTarget(exact, lay4, mons, none, Map())
    Check(!t.adapted && t.x = 4000 && t.w = 800, "Same station: pixel for pixel")
    rel := Map()
    SlotSetRelative(rel, mons, 1920 + 512, 384, 1024, 768)
    Check(rel["mon"] = 2 && rel["fx"] = 0.25 && rel["fy"] = 0.25 && rel["fw"] = 0.5, "Relative capture")

    p := WinPlaceParse("next")
    Check(p.err = "" && p.screen = "next" && p.tile = "keep", "next alone keeps the shape")
    p := WinPlaceParse("here max")
    Check(p.screen = "here" && p.tile = "max", "here max")
    p := WinPlaceParse("2 left")
    Check(p.screen = "2" && p.tile = "left", "2 left")
    p := WinPlaceParse("fill")
    Check(p.screen = "" && p.tile = "max", "fill is max")
    Check(WinPlaceParse("sideways").err != "", "Unknown word refused")
    Check(WinPlaceParse("next prev").err != "", "Two screens refused")
    r := WinTileRect(mons[1], "right")
    Check(r.x = 960 && r.y = 0 && r.w = 960 && r.h = 1040, "Right half of the work area")
    r := WinTileRect(mons[1], "br")
    Check(r.x = 960 && r.y = 520 && r.w = 960 && r.h = 520, "Bottom-right quarter")

    d := Warp.GridDims(2048, 1536, 110)
    Check(d.cols = 19 && d.rows = 14, "Grid dims for a 3 MP screen")
    d := Warp.GridDims(3840, 2160, 110)
    Check(d.cols = 24 && d.rows = 18, "Grid dims are capped")
    c := Warp.CellRect(mons[2], 19, 14, 1, 1)
    Check(c.x = 1920 && c.y = 0 && c.w = 108 && c.h = 110, "First cell")
    c := Warp.CellRect(mons[2], 19, 14, 19, 14)
    Check(c.x + c.w = 3968 && c.y + c.h = 1536, "Last cell ends at the screen edge")
    sub := Warp.SubRect({x: 100, y: 100, w: 90, h: 60}, 3, 3)
    Check(sub.x = 160 && sub.y = 140 && sub.w = 30 && sub.h = 20, "Bottom-right ninth")
    Check(Warp.LetterIndex("a") = 1 && Warp.LetterIndex("Z") = 26 && Warp.LetterIndex("1") = 0,
        "Letter index")
    p := Warp.LoupePlace(mons[2], {x: 2000, y: 700, w: 100, h: 100}, 2050, 750, 44, 332)
    Check(p.x = 2116 && p.y = 584, "Loupe sits beside the region")
    p := Warp.LoupePlace(mons[2], {x: 3900, y: 700, w: 60, h: 60}, 3930, 730, 44, 332)
    Check(p.x = 3538, "Loupe flips to the left at the edge")
    Check(!Warp.active, "Keyboard pointer is closed under the rig")

    ; v0.6.2a: clamped timing reads, and the two action-class predicates the
    ; press path gates on. g_Cfg is replaced wholesale here -- these are the
    ; last checks in the file.
    g_Cfg := Map("bindings", [], "settings", Map())
    Check(HoldMs() = 200 && TapMs() = 100, "Unset thresholds fall back to the defaults")
    CfgSet("holdThreshold", 0)
    CfgSet("tapWindow", 0)
    Check(HoldMs() = 50 && TapMs() = 30, "A zero threshold clamps up, never to 0")
    CfgSet("holdThreshold", 99999)
    CfgSet("tapWindow", 99999)
    Check(HoldMs() = 2000 && TapMs() = 1000, "A huge threshold clamps down")
    CfgSet("holdThreshold", "soon")
    CfgSet("tapWindow", "")
    Check(HoldMs() = 200 && TapMs() = 100, "A non-numeric threshold falls back")
    for t in ["radial", "scrollptr", "zoomptr", "moddrag", "keysrepeat",
        "native", "stock", "dragmove", "sniper", "boost"]
        Check(StatefulHoldType(t), "Stateful hold type lost " t)
    for t in ["ps_dictate", "pacs_keys", "macro", "run", "guiopen", "layout",
        "winplace", "warp", "tele_next", "clicklock", "none"]
        Check(!StatefulHoldType(t), "One-shot " t " must not engage at press")
    for t in ["keys", "keysrepeat", "text", "native", "stock", "wldial"]
        Check(RepeatSafeAct(t), "Repeat-safe action lost " t)
    for t in ["ps_dictate", "ps_next", "pacs_keys", "macro", "run", "guiopen",
        "radial", "tele_next", "sniper", "clicklock", "none"]
        Check(!RepeatSafeAct(t), "Auto-repeat must not re-fire " t)
    Check(MButtonHoldRisk("MButton", "hold") && MButtonHoldRisk("MButton", "taphold"),
        "A middle-button hold must warn")
    Check(!MButtonHoldRisk("MButton", "tap") && !MButtonHoldRisk("XButton1", "hold"),
        "Only a middle-button hold warns")
    Check(MButtonHoldRisk("XButton1", "tap", "MButton"),
        "A layer hosted on MButton is a middle-button hold")

    FileAppend("PASS: JSON, config shape, radial geometry, rename, pause, persistence, "
        . "stations, adaptive layouts, window placement, keyboard pointer geometry, "
        . "clamped thresholds, hold/repeat action classes`n", "*")
    ExitApp(0)
} catch as e {
    FileAppend("FAIL: " e.Message " (line " e.Line ")`n", "**")
    ExitApp(1)
}
