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

    ; ── wedges (v0.6.4, tolerance fixed in v0.6.4a) ─────────────────────
    ; A ROOT ring gives every slice its whole sector -- there is no way back
    ; for a leftover bearing to mean, so leaving one would only lose the
    ; press. A CHILD ring keeps half the gap and hands the rest to `back`.
    ; Pure arithmetic -- no cursor, no layer, no config.
    w4 := RadialWedges(4)
    Check(w4.slices.Length = 4 && !IsObject(w4.back),
        "A root ring has four wedges and no way back")
    for i, want in [0, 90, 180, 270] {
        nxt := Mod(i, 4) + 1
        Check(Abs(w4.slices[i].center - want) < 0.01, "4-way slice " i " moved")
        Check(RadialPickIn(w4, want) = i, "4-way centre picks its own slice")
        Check(RadialPickIn(w4, Mod(want + 30 + 360, 360)) = i,
            "A 4-way slice owns its whole sector")
        Check(RadialPickIn(w4, Mod(want + 46 + 360, 360)) = nxt,
            "Past the boundary is the next 4-way slice")
        Check(RadialPickIn(w4, Mod(want - 22.4 + 360, 360)) = i,
            "A 4-way slice owns its whole sector on the other side too")
    }
    w8 := RadialWedges(8)
    for i, want in [0, 45, 90, 135, 180, 225, 270, 315] {
        nxt := Mod(i, 8) + 1
        Check(Abs(w8.slices[i].center - want) < 0.01, "8-way slice " i " moved")
        Check(RadialPickIn(w8, want) = i, "8-way centre picks its own slice")
        Check(RadialPickIn(w8, Mod(want + 22.4 + 360, 360)) = i,
            "An 8-way slice owns everything up to the boundary")
        Check(RadialPickIn(w8, Mod(want + 22.6 + 360, 360)) = nxt,
            "Just past the boundary is the next 8-way slice")
    }
    ; No bearing at the root may select nothing: a root ring is a partition.
    loop 360 {
        Check(RadialPickIn(w4, A_Index - 1) > 0, "A 4-way root bearing chose nothing")
        Check(RadialPickIn(w8, A_Index - 1) > 0, "An 8-way root bearing chose nothing")
    }
    ; A CHILD ring is spaced 360/(n+1) from one step past the parent, so the
    ; way back keeps a slot and every leftover bearing selects it.
    wc := RadialWedges(8, 180)
    Check(IsObject(wc.back), "A child ring must have a way back")
    for i, sl in wc.slices {
        d := Mod(Mod(sl.center - 180, 360) + 360, 360)
        if (d > 180)
            d := 360 - d
        Check(d > 39.9, "A child slice sits on the parent direction")
    }
    Check(RadialPickIn(wc, 180) = -1, "The parent direction must go back")
    Check(RadialPickIn(wc, 220) = 1, "The first child slice is one step past")
    Check(RadialPickIn(wc, 200) = -1, "Dead space beside the parent goes back")
    Check(RadialAngleIn(180, wc.back.start, wc.back.end),
        "The back arc must contain the parent direction")
    Check(Abs(Mod(Mod(wc.back.end - wc.back.start, 360) + 360, 360) - 60) < 0.01,
        "The back arc is the parent slot plus the dead space flanking it")
    ; The numbered preset ring keeps its numbers where they are, parent or no
    ; parent: the slot IS the number. It is a FULL ring even as a child --
    ; all nine numbers have to be reachable -- so its `back` is a zero-span
    ; marker that only exists so the parent node and connector are drawn.
    for i, a in RadialSliceAngles(9, 180, true)
        Check(Abs(a - (i - 1) * 40) < 0.01, "A preset number moved")
    wn := RadialWedges(9, 180, true)
    Check(IsObject(wn.back), "A numbered child ring keeps a parent marker")
    Check(Abs(wn.back.center - 180) < 0.01 && wn.back.start = wn.back.end,
        "The numbered ring's back marker is the parent direction, zero span")
    for want, slice in Map(200, 6, 215, 6, 219, 6, 221, 7)
        Check(RadialPickIn(wn, want) = slice,
            "Numbered child bearing " want " must pick " slice)
    loop 360
        Check(RadialPickIn(wn, A_Index - 1) > 0,
            "A numbered child ring may never select back")
    Check(RadialAngleIn(5, 355, 15) && !RadialAngleIn(20, 355, 15),
        "An arc that wraps past north")

    ; ── the corner detector (v0.6.4) ────────────────────────────────────
    ; Kando's GestureDetector over a synthetic stroke: 120 px east, then
    ; south. The corner is the point where the hand turned, not where it is.
    straight := []
    loop 13
        straight.Push({x: (A_Index - 1) * 10, y: 0})
    Check(RadialCornerAt(straight) = 0, "A straight stroke has no corner")
    turned := straight.Clone()
    turned.Push({x: 120, y: 12})
    turned.Push({x: 120, y: 24})
    Check(RadialCornerAt(turned) = 13, "The corner is the point that turned")
    wobble := straight.Clone()
    wobble.Push({x: 126, y: 6})
    wobble.Push({x: 132, y: 12})
    Check(RadialCornerAt(wobble) = 0, "A wobble under the jitter floor is not a corner")
    short := []
    loop 6
        short.Push({x: (A_Index - 1) * 10, y: 0})
    short.Push({x: 50, y: 20})
    short.Push({x: 50, y: 40})
    Check(RadialCornerAt(short) = 0, "A turn before 90 px is not a corner")
    Check(RadialHoverScale(0, 0, true) = 1.15
        && Abs(RadialHoverScale(180, 0) - 1.0) < 0.001
        && RadialHoverScale(90, -1) = 1.0,
        "Hover scale peaks at the pointer and rests opposite it")
    Check(RadialEaseTo(1.0, 1.15, 999, 250) = 1.15
        && RadialEaseTo(1.0, 1.15, 16, 250) > 1.0
        && RadialEaseTo(1.0, 1.15, 16, 250) < 1.15,
        "The ease must move toward the target and land on it")

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

    ; ── v0.6.2c ────────────────────────────────────────────────────────────
    ; FRACTIONS MUST SURVIVE THE FILE. A slot's fx/fy/fw/fh are the whole of
    ; the station-adaptive feature, and they go through JsonDump/JsonLoad on
    ; every save. An fw of 1.0 written as "1" and read back as the INTEGER 1
    ; would still compare equal -- and then Round(fw * ww) would be right by
    ; accident while "0.25" turned into something else entirely. Assert the
    ; type, not just the value.
    rt := JsonLoad(JsonDump(Map("fx", 0.25, "fw", 1.0)))
    Check(rt["fx"] = 0.25 && Type(rt["fx"]) = "Float", "fx did not round-trip as a Float")
    Check(rt["fw"] = 1.0 && Type(rt["fw"]) = "Float", "fw 1.0 collapsed to an Integer")

    ; MigrateLayoutSlots only stamps a layout with THIS station when every
    ; slot centre lands on a real monitor. Far-off-screen rectangles came
    ; from somewhere else and must stay unstamped, or they are re-applied
    ; pixel for pixel here. (No monitor shim needed: -99000 is off every
    ; desktop, and 0,0 10x10 is on the primary at every station.)
    g_Cfg := Map("bindings", [], "apps", [], "layouts", [
        Map("name", "Elsewhere", "slots",
            [Map("exe", "a.exe", "title", "t", "x", -99000, "y", -99000,
                 "w", 800, "h", 600)]),
        Map("name", "Here", "slots",
            [Map("exe", "a.exe", "title", "t", "x", 0, "y", 0,
                 "w", 10, "h", 10)])])
    MigrateLayoutSlots()
    Check(MGet(g_Cfg["layouts"][1], "station", "") = "",
        "An off-screen layout must not be stamped with this station")
    Check(g_Cfg["layouts"][1]["slots"][1].Has("fx"),
        "Fractions are derived even when the station is not stamped")
    Check(MGet(g_Cfg["layouts"][2], "station", "") != "",
        "An on-screen layout should be stamped with this station")
    g_Cfg := Map("bindings", [], "apps", [], "layouts", [
        Map("name", "NoStamp", "slots",
            [Map("exe", "a.exe", "title", "t", "x", 0, "y", 0, "w", 10, "h", 10)])])
    MigrateLayoutSlots(false)                ; the CfgImport path
    Check(MGet(g_Cfg["layouts"][1], "station", "") = "",
        "An imported layout must never be stamped with the importing station")

    ; ValidateCfg coerces the layouts/stations trees, because the guard tick
    ; and the station watch read them from TIMER threads where a thrown
    ; error is a silently dead feature.
    g_Cfg := Map("bindings", [], "apps", [],
        "layouts", ["x", Map("slots", "x"),
                    Map("name", "G", "guard", 7, "slots", [
                        Map("exe", "a.exe", "fx", "abc", "fy", 0.1, "fw", 0.2, "fh", 0.3),
                        Map("exe", "b.exe", "fx", "0.5", "x", "40")])],
        "stations", [Map("name", "keyless"), Map("key", "1920x1080")])
    ValidateCfg()
    Check(g_Cfg["layouts"].Length = 2, "A non-Map layout survived validation")
    Check(g_Cfg["layouts"][1]["slots"] is Array && g_Cfg["layouts"][1]["slots"].Length = 0,
        "A non-Array slots list must become []")
    Check(g_Cfg["layouts"][2]["guard"] = 0, "guard 7 must coerce to 0")
    Check(g_Cfg["layouts"][2]["slots"].Length = 1, "A non-numeric fx must drop its slot")
    kept := g_Cfg["layouts"][2]["slots"][1]
    Check(kept["exe"] = "b.exe" && Type(kept["fx"]) = "Float" && kept["fx"] = 0.5,
        "A numeric string fx must become a Float")
    Check(Type(kept["x"]) = "Integer" && kept["x"] = 40, "x must become an Integer")
    Check(g_Cfg["stations"].Length = 1 && g_Cfg["stations"][1]["key"] = "1920x1080",
        "A station with no key is unreachable and must be dropped")

    ; auto imaging when EVERY screen clears the rule: three portrait
    ; diagnostics beside a 4K used to reserve nothing at all, which put the
    ; worklist on the diagnostic displays. Narrow to the portrait screens.
    port := StationSort([
        {l: 0, t: 0, r: 1200, b: 1600, wl: 0, wt: 0, wr: 1200, wb: 1600, w: 1200, h: 1600},
        {l: 1200, t: 0, r: 2400, b: 1600, wl: 1200, wt: 0, wr: 2400, wb: 1600, w: 1200, h: 1600},
        {l: 2400, t: 0, r: 6240, b: 2160, wl: 2400, wt: 0, wr: 6240, wb: 2160, w: 3840, h: 2160}])
    res := ImagingMons(port, "auto")
    Check(res.Count = 2 && res.Has(1) && res.Has(2),
        "Two portraits beside a 4K: the portraits are the imaging screens")
    ; and the median, not the minimum, is what the pixel rule ranks against:
    ; a small legacy screen in the corner must not promote the colour ones.
    mixed := StationSort([
        {l: 0, t: 0, r: 1280, b: 1024, wl: 0, wt: 0, wr: 1280, wb: 1024, w: 1280, h: 1024},
        {l: 1280, t: 0, r: 3200, b: 1080, wl: 1280, wt: 0, wr: 3200, wb: 1080, w: 1920, h: 1080},
        {l: 3200, t: 0, r: 5120, b: 1080, wl: 3200, wt: 0, wr: 5120, wb: 1080, w: 1920, h: 1080}])
    Check(ImagingMons(mixed, "auto").Count = 0,
        "A small legacy screen must not make the colour screens imaging screens")

    Warp.claimed["a"] := true
    Warp.Close(true)
    Check(Warp.claimed.Count = 0, "Warp.Close must not leave a stale key claim")

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

    ; v0.6.2b: the event vocabulary is a two-way map -- the "When you" list
    ; shows the words and the save path writes the code back, so a label that
    ; does not round-trip silently rewrites the row's trigger.
    for code in ["tap", "double", "triple", "hold", "taphold", "turn"]
        Check(EventCodeOf(EventLabelOf(code)) = code, "Event round trip lost " code)
    Check(EventLabelOf("tap") = "Tap it" && EventLabelOf("turn") = "Turn the wheel",
        "Event labels are the words on screen")
    Check(EventLabelOf("weird") = "weird" && EventCodeOf("weird") = "weird",
        "An unknown event passes through unchanged")

    ; v0.6.3: the input-taking actions. The Details dropdown shows LABELS and
    ; the save path writes CODES, so a label that does not round-trip rewrites
    ; the button a row presses -- silently, and into a config file.
    for t in ["native", "dblclick", "dragmove", "clicklock", "moddrag"]
        Check(TakesInputValue(t), "Input-taking action lost " t)
    for t in ["keys", "text", "radial", "winplace", "stock", "none"]
        Check(!TakesInputValue(t), "Free-text action " t " must keep its field")
    for code in INPUT_VALUE_CODES
        Check(InputCodeFromLabel(InputLabel(code)) = code,
            "Input label round trip lost " code)
    for code in MODDRAG_CODES
        Check(ModifierCodeFromLabel(ModifierLabel(code)) = code,
            "Modifier label round trip lost " code)
    ; Blank is an answer, and it is a DIFFERENT answer in each list: click
    ; lock offers it first ("whichever button is held"), everything else last
    ; ("same as this input"), and moddrag does not offer it at all.
    lock := InputValueChoices("clicklock", "")
    Check(lock.codes[1] = "" && lock.labels[1] = "Whichever button is held",
        "Click lock must offer the held button first")
    nat := InputValueChoices("native", "")
    Check(nat.codes[nat.codes.Length] = ""
        && nat.labels[nat.labels.Length] = "Same as this input",
        "Every other input list ends on “same as this input”")
    for ch in [lock, nat] {
        Check(ch.codes.Length = ch.labels.Length, "Labels and codes must pair up")
        for i, code in ch.codes
            Check(code = "" || InputLabel(code) = ch.labels[i],
                "Input option " i " does not name its own code")
    }
    Check(Atlas.IndexOfText(lock.codes, "MButton") > 1
        && lock.codes[Atlas.IndexOfText(lock.codes, "MButton")] = "MButton",
        "The middle button must be selectable as a click-lock output")
    md := InputValueChoices("moddrag", "")
    Check(md.codes.Length = 4 && md.codes[1] = "LAlt",
        "Modifier + left-drag takes modifiers, and starts on one")
    ; A value the list does not offer (a key name, a tilt, a hand-edited
    ; code) is added at the front rather than quietly replaced.
    odd := InputValueChoices("native", "Numpad1")
    Check(odd.codes[1] = "Numpad1", "An unlisted value must survive the editor")
    Check(InputValueChoices("native", "RButton").codes[1] != "RButton",
        "A value the list already offers is not duplicated")

    ; The wizard's seven tiles: label -> action + value, and the sentence
    ; each one produces. "Click lock" is the one that asks a fourth question,
    ; so its value is the answer to that question, not the tile's. The last
    ; two are v0.6.5's PACS gestures -- the existing moddrag action with its
    ; modifier filled in, never a new action type.
    for tile in [["native", "LButton"], ["native", "RButton"],
                 ["native", "MButton"], ["dblclick", "LButton"],
                 ["clicklock", "MButton"], ["moddrag", "LAlt"],
                 ["moddrag", "LCtrl"]] {
        Check(ACT_CODES[ActIndexOf(tile[1])] = tile[1],
            "Wizard tile names a real action: " tile[1])
        Check(Atlas.HasCode(Atlas.SIMPLE_ACTS, tile[1]),
            "Simple mode must offer " tile[1] ", the wizard sets it")
        ok := true
        Check(ValidateActionValue(0, tile[1], tile[2], &ok) = tile[2] && ok,
            "Wizard tile value rejected: " tile[1] " " tile[2])
    }
    ; The three labels a person reads when choosing one of these.
    Check(ActLabelOf("native") = "Act like another button"
        && ActLabelOf("dblclick") = "Double-click a button"
        && ActLabelOf("clicklock")
            = "Click lock (hold a button down until pressed again)",
        "The mouse-output actions must say what they do in plain words")
    Check(Atlas.DefaultValueFor("clicklock") = "MButton",
        "Click lock defaults to the middle button")
    Check(Atlas.WizWhat({act: "clicklock", value: "MButton"})
        = "lock the middle button down until pressed again",
        "The click-lock summary must be a sentence")
    Check(Atlas.WizWhat({act: "clicklock", value: ""})
        = "lock whichever button you are holding down until pressed again",
        "A blank click lock still says what it does")
    Check(Atlas.WizWhat({act: "native", value: "MButton"})
        = "act like the middle button", "The native summary must be a sentence")
    Check(Atlas.WizWhat({act: "keys", value: "^c"}) = "",
        "Everything else falls back to the action table")
    ; Which Details WIDGET an action wants. Two actions share one only when
    ; this matches; anything else has to rebuild the dialog around it.
    Check(Atlas.ValueFamily("keys") = "text"
        && Atlas.ValueFamily("native") = "input"
        && Atlas.ValueFamily("dblclick") = "input"
        && Atlas.ValueFamily("moddrag") = "mod"
        && Atlas.ValueFamily("clicklock") = "lock",
        "An action must ask for the right Details widget")
    ; A click-lock OUTPUT is not a middle-button hold: the warning is about
    ; what you PRESS, not about what the action presses for you.
    Check(!MButtonHoldRisk("XButton1", "tap"),
        "Locking the middle button from button 4 must not warn")

    ; ── v0.6.5 ──────────────────────────────────────────────────────────
    ; Zoom and pan are moddrag rows, said as sentences, and the starter pack
    ; that puts them on the thumb buttons is two ordinary PACS-scoped rows.
    Check(Atlas.WizWhat({act: "moddrag", value: "LAlt"})
        = "zoom (Alt held with a left-drag) while held",
        "Alt+drag must be described as zoom")
    Check(Atlas.WizWhat({act: "moddrag", value: "LCtrl"})
        = "pan (Ctrl held with a left-drag) while held",
        "Ctrl+drag must be described as pan")
    Check(InStr(ModifierLabel("LAlt"), "zoom")
        && InStr(ModifierLabel("LCtrl"), "pan"),
        "The Details dropdown must name what Alt and Ctrl do in PACS")
    pack := StarterPackByName("PACS zoom and pan on the thumb buttons")
    Check(IsObject(pack) && pack.rows.Length = 2,
        "The zoom/pan starter pack must exist")
    for r in pack.rows {
        ok := true
        Check(r[1] = "PACS" && r[5] = "hold" && r[6] = "moddrag",
            "A zoom/pan pack row is a PACS-scoped moddrag hold")
        Check(ValidateActionValue(0, r[6], r[7], &ok) = r[7] && ok,
            "Pack row value rejected: " r[7])
    }
    ; The Home card's sentences. WizSummary drops these into "..., when you
    ; tap it, will X - in every program", so each one has to BE a verb
    ; phrase; the fallback (the action table's own words) is not.
    Check(Atlas.WizWhat({act: "ps_dictate", value: ""})
        = "start or stop dictation in PowerScribe", "Dictate sentence")
    Check(Atlas.WizWhat({act: "tele_prev", value: ""})
        = "send the pointer to the monitor on the left", "Teleport sentence")
    Check(InStr(Atlas.WizWhat({act: "radial", value: "PACS"}), "PACS")
        && InStr(Atlas.WizWhat({act: "radial", value: ""}), "matches"),
        "A radial menu is named in the summary, or said to be automatic")
    ; Every essential the Home card lists must name a real action, and the
    ; two menu rows must name menus that actually ship.
    for e in Atlas.ESSENTIALS {
        Check(ActIndexOf(e[2]) > 0, "Essential names a real action: " e[2])
        Check(e[4] = "" || DEFAULTS.Has(e[4]),
            "Essential names a real setting: " e[4])
    }

    ; THE WHEEL REPEAT GUARD (v0.6.5). Pure: a fake clock and a map of its
    ; own, so the Razer tilt can be replayed without a mouse. A notch is
    ; measured against the last ACCEPTED notch, never against the last notch
    ; seen -- a wheel held over sends one every 30-50 ms, and measuring
    ; against the previous drop would let every one of them through the
    ; moment the burst outlasted the window.
    seen := Map()
    Check(WheelAccept("WheelLeft", 1000, seen, 150), "The first notch is let through")
    Check(!WheelAccept("WheelLeft", 1040, seen, 150), "A repeat 40 ms later is dropped")
    Check(!WheelAccept("WheelLeft", 1080, seen, 150), "So is the next one")
    Check(!WheelAccept("WheelLeft", 1149, seen, 150), "And the one just inside the window")
    Check(WheelAccept("WheelLeft", 1150, seen, 150), "A notch at the window edge is a new press")
    ; The two directions are counted separately: a flick left then right is
    ; two presses, however fast the hand is.
    Check(WheelAccept("WheelRight", 1155, seen, 150), "Left never limits right")
    ; 0 turns it off completely, and nothing is recorded while it is off.
    Check(WheelAccept("WheelUp", 2000, seen, 0) && WheelAccept("WheelUp", 2001, seen, 0),
        "A guard of 0 lets every notch through")
    Check(!seen.Has("WheelUp"), "A guard of 0 records nothing")
    ; A_TickCount wraps every 49.7 days; a negative gap must not swallow
    ; input for the next 150 ms.
    Check(WheelAccept("WheelLeft", 900, seen, 150), "A wrapped clock accepts")
    Check(WheelLimitMs("WheelLeft") = WheelLimitMs("WheelRight"),
        "Both tilts share the tilt guard")
    Check(WheelLimitMs("WheelUp") = WheelLimitMs("WheelDown"),
        "Both wheel directions share the wheel guard")
    Check(DEFAULTS["tiltRepeatMs"] = 150 && DEFAULTS["wheelRepeatMs"] = 0,
        "The shipped guards are 150 ms on tilt, off on the wheel")

    ; Elide is pure arithmetic over Lumi.Size -- no layer, no GpGFX.
    Check(Lumi.Elide("short", 400, "body") = "short", "Elide cut a string that fits")
    long := "PowerScribe: previous field, in every program"
    Check(StrLen(Lumi.Elide(long, 60, "small")) < StrLen(long),
        "Elide must trim a string that cannot fit")
    Check(SubStr(Lumi.Elide(long, 60, "small"), -1) = "…",
        "A trimmed string ends in an ellipsis")
    Check(Lumi.Elide(long, 4, "body") = long,
        "A width with no room for two characters is left alone")

    ; AHK property names are case-INSENSITIVE, so `static grab` next to
    ; `static Grab()` is a duplicate declaration and the script does not
    ; load at all (v0.6.4a). check_source.py catches the collision; this
    ; catches the other half of the rename -- a member quietly renamed back,
    ; or a reference left pointing at a name that no longer exists.
    Check(Warp.HasOwnProp("grabbing") && Warp.HasOwnProp("Grab"),
        "Warp.grabbing must not collide with Warp.Grab()")
    Check(Warp.HasOwnProp("NINTH") && Warp.HasOwnProp("Sub"),
        "Warp.NINTH must not collide with Warp.Sub()")

    FileAppend("PASS: JSON, config shape, radial geometry, wedges, corners, rename, pause, persistence, "
        . "hover scale, stations, adaptive layouts, imaging fallbacks, layout validation, "
        . "float round-trip, window placement, keyboard pointer geometry, "
        . "clamped thresholds, hold/repeat action classes, MButton hold risk, "
        . "event labels, elision, "
        . "input-value options, wizard tiles, Details widget families, "
        . "wheel repeat guard, PACS zoom/pan pack, reading-room essentials`n", "*")
    ExitApp(0)
} catch as e {
    FileAppend("FAIL: " e.Message " (line " e.Line ")`n", "**")
    ExitApp(1)
}
