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

    ; v0.7.2: radial menus are a separate script. A row that opened one
    ; is dropped on load; a key literally named "0" is an ordinary key.
    g_Cfg := Map("bindings", [NewBinding("*", "*", "", "XButton1", "hold", "radial", "Old"),
        NewBinding("*", "*", "", "0", "tap", "keys", "x")],
        "apps", [], "layouts", [], "settings", Map())
    ValidateCfg()
    Check(g_Cfg["bindings"].Length = 1, "Radial row survived validation")
    Check(g_Cfg["bindings"][1]["button"] == "0", "Key 0 row was dropped")
    Check(IsKeyInput("0") && KeyNameValid("0"), "0 is a valid key input")
    ValidateCfgShape(g_Cfg)
    for bad in [[], Map("bindings", "bad"), Map("bindings", [], "settings", []),
        Map("bindings", [], "apps", "bad")]
        Rejects(() => ValidateCfgShape(bad), "Malformed config accepted")

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
    FileAppend("PASS: JSON, config shape, retired radial rows, key 0, persistence`n", "*")
    ExitApp(0)
} catch as e {
    FileAppend("FAIL: " e.Message " (line " e.Line ")`n", "**")
    ExitApp(1)
}
