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
    FileAppend("PASS: JSON, config shape, radial geometry, rename, pause and persistence`n", "*")
    ExitApp(0)
} catch as e {
    FileAppend("FAIL: " e.Message " (line " e.Line ")`n", "**")
    ExitApp(1)
}
