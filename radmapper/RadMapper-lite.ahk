;==============================================================================
;  RadMapper v0.7.2 lite  --  the engine without the graphics library
;
;  *** GENERATED FILE -- DO NOT EDIT ***  Built from RadMapper.ahk (sha256
;  29ed733c65b7ade0) by tools/build_lite.py. Change RadMapper.ahk, then run:
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
;==============================================================================

#Requires AutoHotkey v2.0
#Warn All, Off              ; carried over from the removed GpGFX section:
                            ; #Warn applies to the whole script
#SingleInstance Force
#ClipboardTimeout 250       ; a clipboard read (Copy buttons) waits at most
                            ; this long for the owning app (default 1 s)
#UseHook
; A key or button with a context (#HotIf / HotIf) hotkey makes the input hook
; WAIT for this script's main thread on every press, system-wide. The default
; 1000 ms is longer than Windows' own hook timeout, after which Windows
; silently REMOVES the hook -- typing lag, then dead remaps. Past 150 ms the
; press simply goes through natively.
#HotIfTimeout 150
SendMode "Event"            ; Event + zero delays: injected input flows through
SetKeyDelay -1, -1          ; our own hooks (and is ignored by them) without
SetMouseDelay -1            ; SendInput's temporary hook removal
CoordMode "Mouse", "Screen"
CoordMode "ToolTip", "Screen"
SetTitleMatchMode 2

; PER-MONITOR-V2 DPI AWARENESS, BEFORE ANYTHING READS A MONITOR RECTANGLE.
; Without it Windows virtualises MonitorGet/WinGetPos for a process it thinks
; is DPI-unaware, and on the mixed-scaling stations this script exists for (a
; 3 MP greyscale at 100% beside a 4K at 150%) the numbers come back scaled --
; different numbers for the same physical screens. That matters here before
; the GUI is ever drawn: MigrateLayoutSlots derives every legacy slot's
; fractions from the monitor work areas during LoadCfg, and the FIRST
; StationKey() stamps a station identity ("1920x1080|2048x1536|...") that
; every later recognition is compared against. Both must see PHYSICAL pixels,
; or a layout is stamped with one station on a scaled read and never matches
; again. Layer.RegisterClass sets it too (GpGFX needs it for its own window
; class); this call is idempotent and simply gets there first.
try DllCall("user32\SetProcessDpiAwarenessContext", "ptr", -4, "int")

; High-res trackballs fire wheel hotkeys faster than AHK's default rate limit.
A_MaxHotkeysPerInterval := 2000
A_HotkeyInterval := 1000
; ...and faster than ONE thread per hotkey can absorb. The wheel handler runs
; Critical, so a notch arriving while the previous one is still resolving
; cannot interrupt it -- with the default of 1 thread that notch is discarded
; outright rather than queued, which on a fast spin silently drops input.
#MaxThreadsPerHotkey 4

; ── §1  CONSTANTS & GLOBAL STATE ────────────────────────────────────────────

global RM_VERSION := "0.7.2 lite"

; Remove the foreground-lock so WinActivate can pull PowerScribe forward from
; any app (single-user reading station; see PSFire).
;
; SPI_SETFOREGROUNDLOCKTIMEOUT is a PER-USER, PERSISTENT Windows setting: it
; outlives this process, so every program started later on this login inherits
; whatever RadMapper left behind. On a SHARED workstation that is not ours to
; keep, so the previous value is read first (SPI_GETFOREGROUNDLOCKTIMEOUT,
; 0x2000) and Cleanup puts it back; -1 means it was never read and there is
; nothing to restore. The read lives HERE, in the globals section, rather than
; up in the directive block: top-level code runs in file order, so a
; `global g_FgLockSaved := -1` placed below the read would wipe the value.
global g_FgLockSaved := -1
if !IsSet(RM_TEST) {
    try {
        fgLockNow := 0
        if DllCall("SystemParametersInfo", "UInt", 0x2000, "UInt", 0,
            "UInt*", &fgLockNow, "UInt", 0)
            g_FgLockSaved := fgLockNow
    }
    DllCall("SystemParametersInfo", "UInt", 0x2001, "UInt", 0, "Ptr", 0, "UInt", 0)
}

global g_CfgRecoveryBlocked := false
global g_CfgSaveFailed := false   ; last SaveCfg() threw or was blocked
; -- WHERE THE CONFIG LIVES (v0.4.1) -----------------------------------------
;
; It used to live next to the script: A_ScriptDir "\RadMapperConfig.json".
; That is why every new version started with an empty binding set. A new
; RadMapper.ahk arrives in Downloads, or in a new folder, or beside the old
; one under a new name -- and A_ScriptDir is now somewhere the config is not,
; so the script finds nothing and writes fresh defaults over the top. The old
; config was still on disk the whole time, sitting beside whichever copy was
; run last. Nothing was ever lost; it was simply never looked for.
;
; The config now lives in ONE place per user, independent of where the script
; is: %APPDATA%\RadMapper. Every future version finds it with no migration and
; no copying, which is the actual fix -- anything keyed to the script's own
; folder breaks again the moment a file is moved or renamed.
;
; PORTABLE MODE is still available and now has to be asked for: put an empty
; file named "RadMapper.portable" beside the script and it keeps its config
; and its backups in its own folder, for a USB stick or a locked-down machine.
;
; Resolved at startup by ResolveCfgPaths() rather than fixed here, because the
; portable check needs a file test and the adoption sweep needs to run before
; the first load.
global CFG_DIR      := ""
global CFG_PATH     := ""
global BACKUP_DIR   := ""
global CFG_PORTABLE := false
global CFG_ADOPTED  := ""         ; path a config was adopted FROM, for the UI
global CFG_NAME     := "RadMapperConfig.json"
; v0.1 rename: the pre-RadMapper config is adopted once and deliberately LEFT
; ON DISK afterwards as a fallback.
global OLD_CFG_NAME := "RadMouseConfig.json"
; v0.7.1 one-time reset: a config whose "resetEpoch" is below this is set
; aside once (RadMapperConfig.pre-reset-<stamp>.json beside it, a name the
; backup pruning never touches) and replaced with the shipped defaults, so
; the station is set up fresh. Every config the script writes afterwards --
; defaults, imports, restored backups -- is stamped, so it never fires twice.
; Raise this only to force another reset on every station.
global CFG_RESET_EPOCH := 1

global BUTTONS := ["LButton", "RButton", "MButton", "XButton1", "XButton2"]
global WHEELS  := ["WheelUp", "WheelDown", "WheelLeft", "WheelRight"]
; Triggers retired in v0.7 (double-tap, triple-tap, tap-then-hold): a row
; carrying one is dropped on load, with a Diagnostics line saying so.
global RETIRED_EVENTS := ["double", "triple", "taphold"]

; Base-layer selector label (E1 mouse map). MUST be a top-level global defined
; ABOVE the Init() call: anything reading it during Init would find it unset, and
; a stranded assignment lower in the file never runs before Init (auto-exec is
; top-to-bottom, RM_TEST hides this because it skips Init).
global LAYER_BASE_LABEL := "Base (no button held)"
; The DEFAULT layer hosts: the two thumb buttons and CapsLock (it types
; nothing, so holding it is free). v0.7.2: the live list is the config's
; "layerHosts" (LayerHosts()), editable from the Mouse/Keyboard tab strip, so
; a mouse without buttons 4 and 5 can use the middle or right button or a
; key. Left is never allowed: every plain click would wait on the threshold.
global LAYER_HOSTS := ["XButton1", "XButton2", "CapsLock"]
global LAYER_HOSTS_MAX := 6

; Friendly display names for inputs (config/JSON always stores the codes).
global INPUT_LABELS := Map(
    "LButton", "Left Button",
    "RButton", "Right Button",
    "MButton", "Button 3 (wheel click)",
    "XButton1", "Button 4 (thumb, back)",
    "XButton2", "Button 5 (thumb, forward)",
    "WheelUp", "Wheel Up (scroll)",
    "WheelDown", "Wheel Down (scroll)",
    "WheelLeft", "Tilt Wheel Left",
    "WheelRight", "Tilt Wheel Right")

; Event codes <-> the words a person would use. The engine and the config
; only ever see the codes; every list, dropdown and sentence shows these.
global EVENT_LABELS := Map(
    "tap", "Tap it",
    "hold", "Hold it down",
    "turn", "Turn the wheel")

; --- MOUSE BUTTONS AS OUTPUTS (v0.6.3) ---------------------------------------
; Five actions do not take a shortcut or a name: they take an INPUT -- the
; button this one should press, double-click, drag or latch instead. Until now
; that was free text ("type RButton"), which is why "make button 4 lock the
; middle button down" was a sentence in a hint rather than something you could
; pick. The editors show a dropdown built from the lists below, and the codes
; are exactly what the config stores, so nothing about the file format moves.
global INPUT_VALUE_ACTS := ["native", "dblclick", "dragmove", "clicklock",
                            "moddrag"]
; The outputs offered, in the order a hand reaches them. The two tilt
; directions are deliberately absent: a tilt wheel is not on every trackball
; and this list is meant to be read at a glance, not to be complete -- a
; config that names one keeps it (InputValueChoices puts it back in the list).
global INPUT_VALUE_CODES := ["LButton", "RButton", "MButton", "XButton1",
                             "XButton2", "WheelUp", "WheelDown"]
; "Modifier + left-drag" is picked the same way, but the thing it picks is a
; MODIFIER, so it has its own four.
global MODDRAG_CODES := ["LAlt", "LCtrl", "LShift", "LWin"]
; v0.6.5: the two that have a JOB in IntelliSpace say what that job is.
; The codes are unchanged, so nothing about the file format moves -- this is
; the word in the Details dropdown, and it is the word a reader is looking
; for ("how do I put zoom on a thumb button?").
global MODDRAG_LABELS := Map("LAlt", "Alt — zoom in PACS",
                             "LCtrl", "Ctrl — pan in PACS",
                             "LShift", "Shift", "LWin", "Windows key")
; Action type codes <-> GUI labels (parallel arrays; keep in sync)
; v1.0 (E1): the "layer"/"layertoggle" actions are RETIRED -- layers are now
; button-holds (a button hosts a layer just by having rows scoped to it; hold
; arms it). Old configs' layer actions fold to "none" on load (MigrateRow).
; v0.3: "autoscroll" is retired with the scroll engine; old configs' rows
; fold to "none" the same way. ("scrollptr" came back in v0.3.1 as drag
; scroll, so those rows keep working.)
global ACT_CODES := ["keys", "keysrepeat", "text", "native", "stock", "dblclick", "moddrag",
    "dragmove", "ps_dictate", "ps_next", "ps_prev", "ps_keys", "pacs_keys",
    "tele_prev", "tele_next", "parkgo",
    "clicklock", "appswitch",
    "layout",
    "winplace", "warp",
    "macro", "run", "guiopen", "bypass", "pausetgl", "none"]
global ACT_LABELS := ["Send keys", "Send keys (auto-repeat while held)",
    "Type text", "Act like another button", "Pass through — let the app's own binding run",
    "Double-click a button",
    "Hold a modifier with left-drag (Alt = zoom, Ctrl = pan in PACS)",
    "Native drag after move (hold)", "PowerScribe: toggle dictation",
    "PowerScribe: next field", "PowerScribe: previous field",
    "PowerScribe: send keys",
    "PACS: send keys",
    "Teleport cursor: previous monitor", "Teleport cursor: next monitor",
    "Park cursor (this app's spot)",
    "Click lock (hold a button down until pressed again)",
    "Switch window (+1 / -1) — scroll a list, release to pick",
    ; ORDER IS THE CONTRACT: ACT_LABELS[i] must describe ACT_CODES[i].
    "Apply window layout",
    "Window: move / fill the active window",
    "Keyboard pointer (grid + loupe; click and drag by keys)",
    "Run macro", "Run program",
    "Open RadMapper settings",
    "Stand back: every other input native (hold = while held, tap = on / off)",
    "Toggle engine pause",
    "Block it (this button does nothing at all)"]
global ACT_HINTS := Map(
    "keys", "Use Rec to press a shortcut, or Keys to choose one. Typed syntax: ^z = Ctrl+Z; {F5} = F5.",
    "keysrepeat", "AHK Send syntax; fires once on press, repeats while held",
    "text", "Literal text typed as-is",
    "native", "The button or key this one presses instead.",
    "stock", "No value needed — this input reaches the app untouched, so the "
           . "app's own binding runs. Scope it to one app or layer to carve "
           . "an exception out of a broader remap.",
    "dblclick", "The button this one double-clicks.",
    "moddrag", "The modifier held down while the left button drags. In "
             . "IntelliSpace, Alt+drag zooms and Ctrl+drag pans.",
    "dragmove", "The button that starts dragging once the cursor moves.",
    "ps_dictate", "No value needed (uses the dictate key from Settings)",
    "ps_next", "No value needed",
    "ps_prev", "No value needed",
    "ps_keys", "Use Rec or Keys. This shortcut is sent to PowerScribe; typed function keys need braces, e.g. {F6}.",
    "pacs_keys", "Use Rec or Keys. Sent to the PACS viewer from ANY app: PACS is brought forward, the keys land, focus comes back.",
    "tele_prev", "No value needed (monitors are ordered left to right)",
    "tele_next", "No value needed (monitors are ordered left to right)",
    "parkgo", "No value needed (set the spot in the Apps page) (turn on “Show advanced pages” on Home)",
    "clicklock", "The button it holds down until pressed again. There is "
               . "also a global lock key on the Pointer page (turn on “Show "
               . "advanced pages” on Home).",
    "layout", "Leave BLANK to pick from a list at the cursor, or name one "
            . "layout from the Windows page to apply it directly (turn on “Show advanced pages” on Home)",
    "winplace", "A screen and/or a tile, e.g. next, prev, here, 2, max, "
              . "left, right, top, bottom, tl, tr, bl, br. 'next' keeps the "
              . "window's shape on the next screen; 'max' fills the screen it "
              . "is on (again restores); 'here max' fills the screen under "
              . "the pointer",
    "warp", "No value needed — opens the lettered grid on the screen under "
          . "the pointer (again closes it). Space clicks, G drags, N snaps "
          . "to the control under the pointer, Esc closes",
    "appswitch", "+1 or -1. Put it on the wheel inside a layer: the list "
               . "appears while the layer's input is held and stays up while "
               . "you scroll, and releasing switches to the highlighted window.",
    "macro", "Macro name from the Macros page (turn on “Show advanced pages” on Home)",
    "run", "Program or document path / URL",
    "guiopen", "No value needed",
    "bypass", "No value needed. While it is on, every OTHER button, key "
            . "and the wheel does exactly what it does without RadMapper; "
            . "the engine keeps running. Hold it: on while held. Tap it: on "
            . "until tapped again (or 2 minutes).",
    "pausetgl", "No value needed",
    "none", "Suppresses the input entirely")

; Settings keys retired in v0.3 along with the scroll engine, gestures and
; chords. Deleted from the config on load (MigrateCfg) so the file on disk
; stops carrying dead knobs.
global RETIRED_SETTINGS := ["chordWindow", "gestureThreshold", "ringOverlay",
    "tapWindow", "radialRestMs",
    ; v0.7.2: radial menus moved to their own script
    "radialDwellMs", "radialDead", "radialRadius", "radialSubMs",
    "radialAnim", "radialWedges",
    ; v0.7.2: the clipboard history and scratchpad are gone
    "hkClipboard", "hkScratch",
    ; v0.7.2: pointer speed modes, drag scroll/zoom and the W/L dial are gone
    "sniperSpeed", "boostSpeed", "scrollPtrPx", "scrollPtrInvert",
    "scrollPtrPin", "scrollPtrHide", "scrollPtrMax",
    ; v0.3: the old scroll engine
    "sniperScrollMult", "boostScrollMult", "scrollAccel", "scrollAccelGap",
    "scrollAccelRamp", "scrollAccelMax",
    "scrollSmooth", "scrollSmoothMs", "scrollTickMs", "scrollMomentum",
    "scrollMomentumMin", "scrollFriction", "scrollCoastMax",
    "scrollExactApps", "autoScrollDead", "autoScrollRate", "autoScrollInvert",
    "accelMode"]

global DEFAULTS := Map(
    "holdThreshold", 200,      ; ms press duration that becomes a hold
    "dragThreshold", 8,        ; px of travel that commits dragmove to a drag
    "repeatRate", 50,          ; ms between auto-repeat keystrokes
    "hud", 1,                  ; 1 = show tooltip feedback (dial, layer, ...)
    "layoutGuardMs", 1500,     ; how often an armed layout re-checks drift
    "winW", 1120,              ; remembered Atlas window size (>= the design
    "winH", 800,               ;   minimum; the grip and [] button write these)
    "winMax", 0,
    "hudCorner", "bl",         ; bl | br | tl | tr | bc -- where the HUD parks
    "hudFollow", 1,            ; 1 = on the monitor under the cursor
    "psDictateKey", "{F4}",
    "psReturnDelay", 60,       ; ms before focus returns after firing into PS
    "pacsApp", "PACS",         ; the Apps-tab profile "PACS: send keys" targets
    "pacsWindow", "VirtualMonitor", ; preferred window TITLE (substring) of that
                               ;   app: IntelliSpace's viewer, not its worklist.
                               ;   Blank = whichever window was last active
    "theme", "auto",           ; auto = follow Windows apps theme | light | dark
    "ui", "atlas",             ; atlas = the GpGFX Lumi Atlas window
    "uiAdvanced", 0,           ; 0 = Simple: hide Macros/Apps/Windows/
                               ;   Pointer and show the short action list
    "welcomedVer", "",         ; last version that opened the window on
                               ;   launch; "" = never (first run)
    ; v0.6.5 -- WHEEL REPEAT GUARDS. A Razer tilt wheel does not send one
    ; WheelLeft when you tilt it: it sends one every 30-50 ms for as long as
    ; the wheel is held over, exactly like a held keyboard key. Bound to an
    ; action, that is a burst of presses nobody asked for ("the left/right
    ; tilts send multiple repeated inputs"). A notch arriving within this
    ; many ms of the last ACCEPTED notch for the same input is dropped, so a
    ; held tilt is one press. Per input, so left and right never limit each
    ; other. 0 = off. Native (inert) rows are never limited -- plain
    ; scrolling must stay byte-for-byte hardware-native.
    "tiltRepeatMs", 150,       ; WheelLeft / WheelRight
    "wheelRepeatMs", 0,        ; WheelUp / WheelDown (off: a real wheel is
                               ;   meant to repeat)
    "hkDictate", "",           ; PS/teleport hotkeys ship unassigned (v0.3);
    "hkPrevField", "",         ; set them in the Settings tab when wanted
    "hkNextField", "",
    "hkTeleLeft", "",
    "hkTeleRight", "",
    "hkGui", "^!+F9",
    "hkToggle", "^!+F11",
    ; A dedicated PAUSE key. NumLock is chosen because a reading-room numpad
    ; sits under the left hand all day and its own toggle is dead weight
    ; here: RadMapper hooks every numpad row under BOTH NumLock names
    ; (Numpad1 / NumpadEnd), so the lock state no longer changes what the
    ; numpad does to RadMapper. Registering it plainly SUPPRESSES the native
    ; toggle, which is the point -- it becomes a pause key, and the NumLock
    ; state you had is the state you keep.
    ;   Want NumLock to keep toggling the lock as well? Set this to
    ;   "~NumLock". Want the key back entirely? Set it to "".
    "teleportFlash", 1,
    "focusFlash", 1,           ; ring pulse when the cursor lands somewhere
                               ;   new (follow-focus, window switch) -- the
                               ;   teleport ring without the monitor border        ; 1 = flash the monitor the cursor teleports to
    "followFocus", 0,          ; 1 = warp the cursor to a newly focused window
    "followFocusMs", 120,      ; ms between foreground checks while it is on
    ; Follow-focus is about APP switches. A window handle change inside one
    ; process is not one: syngo.via, a PACS viewer and a browser all hand the
    ; foreground back and forth between their own top-level windows without
    ; the user doing anything, and chasing those is what makes the pointer
    ; feel like it is jumping around by itself. Turn this on to follow those
    ; too.
    "followSameApp", 0,
    ; A window must still be in front this long before the cursor commits to
    ; it, so a dialog that flashes up and vanishes never earns a warp.
    "followSettleMs", 220,
    "followCooldownMs", 700,   ; minimum gap between two follow warps
    ; Where follow-focus never moves the pointer, whatever comes to the
    ; front (v0.6.6.1). ";"-separated: "name.exe", "title:part of a title",
    ; "class:WindowClass". Edited on Settings > Behaviour.
    "followExcept", "",
    "hkPause", "NumLock",
    "hkPanic", "^!q",
    ; Never ^!s or ^!l for a default: Epic uses Ctrl+Alt+S to secure the
    ; workstation and Ctrl+Alt+L to log out.
    ; The programmable click-lock button: one key that latches WHATEVER is
    ; being held, so a lock does not have to be bound per input. ^!b for
    ; "button lock"; as with the others, not ^!s or ^!l (Epic).
    "hkClickLock", "^!b",
    "clickLockAutoRelease", 1, ; 1 = the next real keystroke drops the latch
    ; v0.7 -- WHEEL DECK SETTLE. A deck is "hold a button, turn the wheel".
    ; Pressed while the wheel is still turning (mid-way through a CT stack,
    ; say), the notches still arriving belong to the scroll, not the deck:
    ; they stay native until the wheel has been still this long. 0 = off.
    "deckSettleMs", 250,
    ; v0.6.2: stations, window placement, the keyboard pointer
    "stationAuto", 1,          ; apply a station's arrangement when its screens
                               ;   appear (launch, dock, KVM, log-in elsewhere)
    "stationSettleMs", 2500,   ; wait for Windows to finish re-enumerating
    "imagingMons", "auto",     ; which screens are imaging displays, unless the
                               ;   station says: auto | none | "2,3"
    "hkWinNext", "",           ; active window -> next screen (left to right)
    "hkWinPrev", "",           ; active window -> previous screen
    "hkWinMax", "",            ; fill the screen it is on (again = restore)
    "hkWarp", "^!g",           ; the keyboard pointer: grid + loupe
    "warpZoom", 4,             ; loupe magnification 2..12 (+/- while open)
    "warpLoupe", 1,            ; 1 = show the loupe in the fine stage
    "warpCell", 110,           ; target grid cell size, px
    ; Window-switcher hide list. Rules separated by "|", each one
    ;     exe.name:title fragment
    ; with "*" (or an empty side) meaning "any". The title is matched as a
    ; case-insensitive SUBSTRING, so a rule keeps matching whatever the app
    ; appends -- patient name, unread count, " -- Web Message Panel". A bare
    ; name ending in .exe hides that whole process; anything else with no
    ; colon is treated as a title fragment for any process.
    ;
    ; The defaults clear the IntelliSpace satellites that crowded the
    ; switcher on the reading workstation: the dashboard and chat panes it
    ; hosts in WebBrowserHost.exe, and the viewer's own Background and
    ; MHActivationToolbar helper windows (one of each per monitor, so four
    ; tiles of nothing). What is left is what actually gets cycled -- the
    ; PACS worklist and viewers, PowerScribe, Epic, syngo and the browser.
    "switchHide", "WebBrowserHost.exe:My Dashboard"
        . "|WebBrowserHost.exe:IntelliSpace PACS Chat"
        . "|IntelliSpacePACSRadiology.exe:Background"
        . "|IntelliSpacePACSRadiology.exe:MHActivationToolbar")

global g_Cfg := 0              ; whole config (Map), see DefaultCfg()
global g_BS := Map()           ; per-input live state objects
global g_Enabled := true
global g_PollSeq := 0          ; movement-poll generation counter
global g_ClickLock := 0        ; {held, src} while a button is latched down
global g_ClickLockHook := 0    ; InputHook watching for the release keystroke
global g_ClickLockArmed := 0   ; tick the latch engaged (auto-repeat grace)
global g_ClickLockVk := 0      ; vk of the key that armed it -- exempt
global g_TeleSig := 0          ; live teleport signal {edges, ring, frame}
global g_PassThru := Map()     ; hwnds that are ours but must NEVER be claimed
                               ; positionally: click-through overlays that sit
                               ; under the cursor by design (toast, teleport
                               ; flash). Claiming one gates the engine native
                               ; underneath and eats the click.
global TELE_RED := "0xFFFF2B2B"
global g_FollowLast := 0       ; last foreground hwnd the follower acted on
global g_FollowPid  := 0       ; and its process -- the unit a switch is in
global g_FollowCand := 0       ; hwnd waiting out followSettleMs
global g_FollowCandAt := 0     ; tick it first appeared in front
global g_FollowAt := 0         ; tick of the last warp (cooldown)
global g_FollowOn := false     ; the follow-focus timer is armed
global g_TeleAt := 0           ; tick of the last monitor teleport (follow-focus grace)
global g_HookChangedAt := 0    ; tick of the last hook (re)install: physical
                               ;   key state may have been wiped at that moment

; Every place that registers or unregisters a hotkey calls this. AutoHotkey
; zeroes its physical-state table when a hook is (re)installed, so any
; press older than this stamp cannot be judged "physically up" from that
; table (v0.6.6.4).
HookChanged() {
    global g_HookChangedAt
    g_HookChangedAt := A_TickCount
}


global g_LastEvWhat := ""      ; last event; formatted lazily by LastEventText
global g_LastEvBind := 0
global g_LastEvDirty := false
global g_LastEvText := "(none yet)"
global g_FgHwnd := 0           ; foreground-hwnd micro-cache (same-ms reuse)
global g_FgTick := -1
global g_OurHwnds := Map()     ; our own GUI hwnds -> passthrough while active
global g_HookState := Map()    ; input name -> 1 while its hotkeys are On
global g_KbRegistered := []    ; keyboard hotkey strings currently registered
; Binding membership index (see RebuildIndex). Starts as a valid EMPTY index
; so the hot-path lookups never need an existence guard.
global g_Idx := {bind: Map(), layerBind: Map(), anyMods: false,
    anyApp: false, anyNoFollow: false, refd: Map()}
global g_AppCache := {hwnd: 0, tick: 0, name: ""}   ; ActiveAppName cache
global g_MacroBusy := false
; Panic bumps this; RunMacro snapshots it and stops between steps if it moved.
; A macro is a SEQUENCE -- panic released every button, but without this the
; loop kept sending its remaining keys into the study it had just been
; panicked out of.
global g_MacroGen := 0
global g_MouseHkWarned := "" ; last mouse-in-Settings-hotkey set warned about
global g_BadKeyWarned := ""  ; last unhookable-key set warned about
global g_ClashWarned := ""   ; last Settings-hotkey/key-row clash warned about
global g_Problems := []      ; capped in-memory ring of notable events (never
                             ; written to disk; cleared on exit) - Diagnostics
global g_ProblemSeq := 0     ; monotonic change signal (Length stalls at cap)
global g_PSBusy := false     ; a PSDrain loop is mid-delivery
global g_PSQueue := []       ; pending PowerScribe deliveries, FIFO
global g_PSGen := 0          ; panic bumps this; in-flight deliveries abort
global g_PSDefer := 0        ; drain deferrals while the hand is on a button
global g_CfgDirty := false     ; a debounced config save is pending
global g_TestUI := 0           ; the input tester window's controls, while open
global g_RecHook := 0          ; live recording InputHook (stopped on dialog close)
global g_Testing := false      ; Test tab live-monitor active
global g_TestHooks := []       ; "~*X" passthrough hotkeys registered for the tester
global g_TestCounts := Map()   ; input name -> press count shown on the Test tab
global g_TestHeld := Map()     ; input name -> 1 while physically down (tester)
global g_TestLast := Map()     ; input name -> tick of last wheel pulse (tester)

; --- test shim -----------------------------------------------------------
; Production points these at the real implementations; the wine test rig
; (tests/RigMain.ahk) reassigns them to capture output and simulate input.
; Engine logic must never call the underlying builtins directly for synthetic
; output or physical reads -- route through these slots.
global RM_Send     := Send                        ; every synthetic Send funnel
global RM_SendText := SendText
global RM_KeyHeld  := (k) => GetKeyState(k, "P")  ; physical key reads
global RM_GetPos   := RM_GetPosReal               ; pointer position reads
global RM_AppScan  := RM_AppScanReal              ; active-app profile scan
global RM_PSFire   := RM_PSFireReal               ; PowerScribe delivery
global RM_WinAt    := RM_WinAtReal                ; top-level window under cursor

RM_GetPosReal(&x, &y) {
    MouseGetPos(&x, &y)
}

; Top-level window under the cursor. Uses raw WindowFromPoint (not MouseGetPos):
; MouseGetPos does not resolve a DropDownList's popup list (ComboLBox) -- it
; returned the window BEHIND the open list, so the HotIf gate treated a click on
; the dropdown as foreign and the engine ate it. WindowFromPoint resolves the
; popup; GetAncestor(GA_ROOT) normalizes any child to its top-level (the popup
; itself for a ComboLBox, our dialog for a control, the app window otherwise).
RM_WinAtReal() {
    pt := Buffer(8, 0)
    if !DllCall("GetCursorPos", "ptr", pt)
        return 0
    h := DllCall("WindowFromPoint", "int64", NumGet(pt, 0, "int64"), "ptr")
    if h
        h := DllCall("GetAncestor", "ptr", h, "uint", 2, "ptr")   ; GA_ROOT = 2
    return h
}

; Init() USED TO BE CALLED HERE. It is now the last statement in the file --
; see the bottom of the script. AutoHotkey runs top-level code in source
; order, so calling it here brought the clipboard hook, the keyboard hotkeys
; and the 750 ms watchdog live thousands of lines before the globals and the
; class static initialisers they read had been assigned. Anything that
; stalled the rest of the load -- a load-time error dialog, most obviously --
; left those callbacks firing against unassigned variables, which is exactly
; how one error in Atlas.__Init turned into a page of "this variable has not
; been assigned a value" reports from ClipChanged.

; ── §2  JSON (load / dump) ──────────────────────────────────────────────────
; Minimal, dependency-free. Objects -> Map, arrays -> Array, true/false/null
; -> 1/0/"". Dump pretty-prints so the file stays hand-editable.

JsonLoad(s) {
    p := 1
    v := _JVal(s, &p)
    _JWs(s, &p)
    if (p <= StrLen(s))
        throw Error("JSON: unexpected content at " p)
    return v
}

_JWs(s, &p) {
    while (p <= StrLen(s)) {
        c := SubStr(s, p, 1)
        if (c = " " || c = "`t" || c = "`n" || c = "`r")
            p += 1
        else
            break
    }
}

_JVal(s, &p) {
    _JWs(s, &p)
    c := SubStr(s, p, 1)
    if (c = "{") {
        m := Map()
        p += 1
        _JWs(s, &p)
        if (SubStr(s, p, 1) = "}") {
            p += 1
            return m
        }
        loop {
            _JWs(s, &p)
            if (SubStr(s, p, 1) != '"')
                throw Error("JSON: expected key at " p)
            k := _JStr(s, &p)
            _JWs(s, &p)
            if (SubStr(s, p, 1) != ":")
                throw Error("JSON: expected ':' at " p)
            p += 1
            m[k] := _JVal(s, &p)
            _JWs(s, &p)
            c := SubStr(s, p, 1)
            p += 1
            if (c = ",")
                continue
            if (c = "}")
                return m
            throw Error("JSON: expected ',' or '}' at " p)
        }
    }
    if (c = "[") {
        a := []
        p += 1
        _JWs(s, &p)
        if (SubStr(s, p, 1) = "]") {
            p += 1
            return a
        }
        loop {
            a.Push(_JVal(s, &p))
            _JWs(s, &p)
            c := SubStr(s, p, 1)
            p += 1
            if (c = ",")
                continue
            if (c = "]")
                return a
            throw Error("JSON: expected ',' or ']' at " p)
        }
    }
    if (c = '"')
        return _JStr(s, &p)
    ; keywords
    if (SubStr(s, p, 4) = "true") {
        p += 4
        return 1
    }
    if (SubStr(s, p, 5) = "false") {
        p += 5
        return 0
    }
    if (SubStr(s, p, 4) = "null") {
        p += 4
        return ""
    }
    ; \G anchors at the start position, so no per-number SubStr copy of the
    ; rest of the document (that was O(n^2) on a large config).
    if !RegExMatch(s, "\G-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?", &num, p)
        throw Error("JSON: unexpected char at " p)
    p += StrLen(num[0])
    return Number(num[0])
}

_JStr(s, &p) {
    p += 1                                   ; skip opening quote
    out := ""
    loop {
        c := SubStr(s, p, 1)
        if (c = "")
            throw Error("JSON: unterminated string")
        if (c = '"') {
            p += 1
            return out
        }
        if (c = "\") {
            e := SubStr(s, p + 1, 1)
            p += 2
            switch e {
                case '"': out .= '"'
                case "\": out .= "\"
                case "/": out .= "/"
                case "b": out .= Chr(8)
                case "f": out .= Chr(12)
                case "n": out .= "`n"
                case "r": out .= "`r"
                case "t": out .= "`t"
                case "u":
                    out .= Chr(Integer("0x" SubStr(s, p, 4)))
                    p += 4
                default: throw Error("JSON: bad escape \" e)
            }
            continue
        }
        if (Ord(c) < 32)
            throw Error("JSON: unescaped control character at " p)
        out .= c
        p += 1
    }
}

JsonDump(v, indent := "") {
    pad := indent "  "
    if IsObject(v) {
        if (v is Map) {
            if (v.Count = 0)
                return "{}"
            out := "{"
            first := true
            for k, val in v {
                out .= (first ? "" : ",") "`n" pad _JQuote(k) ": " JsonDump(val, pad)
                first := false
            }
            return out "`n" indent "}"
        }
        if (v is Array) {
            if (v.Length = 0)
                return "[]"
            out := "["
            first := true
            for val in v {
                out .= (first ? "" : ",") "`n" pad JsonDump(val, pad)
                first := false
            }
            return out "`n" indent "]"
        }
        return _JQuote(String(v))
    }
    t := Type(v)
    if (t = "Integer" || t = "Float")
        return String(v)
    return _JQuote(v)
}

_JQuote(s) {
    out := '"'
    loop parse s {
        c := A_LoopField
        code := Ord(c)
        if (c = '"')
            out .= '\"'
        else if (c = "\")
            out .= "\\"
        else if (c = "`n")
            out .= "\n"
        else if (c = "`r")
            out .= "\r"
        else if (c = "`t")
            out .= "\t"
        else if (code < 0x20)
            out .= Format("\u{:04X}", code)
        else
            out .= c
    }
    return out '"'
}


; ── §3  CONFIG (defaults / load / save / helpers) ───────────────────────────

; Exact text equality. `=` and `!=` ignore case AND compare numerically when
; both sides look numeric ("1" = "01", "0012345" = "12345"), which is wrong
; for names and clipboard text; `==` still compares numerically.
SameText(a, b) {
    if (IsObject(a) || IsObject(b))
        return false
    return StrCompare(a, b, true) = 0
}

MGet(m, k, d := "") {
    return (m is Map && m.Has(k)) ? m[k] : d
}

; Case-insensitive: hand-edited configs may carry e.g. "xbutton1".
InputLabel(code) {
    for c, l in INPUT_LABELS {
        if (c = code)
            return l
    }
    return code
}

InputCodeFromLabel(label) {
    for code, l in INPUT_LABELS {
        if (l = label)
            return code
    }
    return label
}

; Same pair for the events. Unknown codes pass through unchanged, so a
; hand-edited config never loses a row to a missing label.
EventLabelOf(code) {
    for c, l in EVENT_LABELS {
        if (c = code)
            return l
    }
    return code
}

; --- input-valued action values (v0.3.1) ---------------------------------------
; "Native input" and "Native drag after move" take an INPUT NAME as their
; value -- the input to press instead. v0.2/v0.3 accepted only the internal
; code ("RButton"), which the GUI never shows anywhere: every list, dropdown
; and zone is labelled "Right Button" / "Button 4 (thumb, back)". Typing what the UI
; displays produced Send("{Blind}{Right Button 1}"), which throws -- so the
; source button was suppressed and did nothing at all. That is why remapping
; a mouse button to another mouse button "didn't work". Values are now
; resolved through here on load, on save, and in the picker.
ResolveInputValue(v) {
    static alias := ""
    if !IsObject(alias) {
        alias := Map("lmb", "LButton", "left", "LButton", "leftclick", "LButton",
            "mouse1", "LButton", "button1", "LButton",
            "rmb", "RButton", "right", "RButton", "rightclick", "RButton",
            "mouse2", "RButton", "button2", "RButton",
            "mmb", "MButton", "middle", "MButton", "middleclick", "MButton",
            "wheelclick", "MButton", "mouse3", "MButton", "button3", "MButton",
            "x1", "XButton1", "mouse4", "XButton1", "back", "XButton1",
            "x2", "XButton2", "mouse5", "XButton2", "forward", "XButton2",
            "scrollup", "WheelUp", "scrolldown", "WheelDown",
            "tiltleft", "WheelLeft", "tiltright", "WheelRight")
        alias.CaseSense := "Off"
    }
    v := NormalizeInputName(v)               ; "{RButton}" -> "RButton"
    if (v = "")
        return ""
    code := InputCodeFromLabel(v)            ; "Right Button" -> "RButton"
    if (code != v)
        return code
    if alias.Has(v)
        return alias[v]
    for b in BUTTONS {                       ; fix casing on a hand-typed code
        if (b = v)
            return b
    }
    for w in WHEELS {
        if (w = v)
            return w
    }
    return CanonicalInputName(v)             ; a key name, twin-canonicalized
}

; Something the engine can actually press: one of the nine mouse inputs, or a
; key AutoHotkey can name.
IsInputTarget(v) {
    return (v != "") && (IsMouseInput(v) || KeyNameValid(v))
}

; Valid value for the "Modifier + left-drag" action. Empty is NOT valid: an
; empty one sent "{Blind}{ Down}{LButton Down}", which throws.
IsModifierName(v) {
    for m in ["LAlt", "RAlt", "Alt", "LCtrl", "RCtrl", "Ctrl", "LShift",
        "RShift", "Shift", "LWin", "RWin"] {
        if (m = v)
            return m
    }
    return ""
}

; True for the five actions whose value names an INPUT (or, for moddrag, a
; modifier) rather than free text. Where this is true the editors swap the
; Details field for a dropdown, so a mouse button is never typed by hand.
TakesInputValue(atype) {
    for t in INPUT_VALUE_ACTS {
        if (t = atype)
            return true
    }
    return false
}

; Plain name for one of the four drag modifiers.
ModifierLabel(code) {
    for c, l in MODDRAG_LABELS {
        if (c = code)
            return l
    }
    return code
}

/**
 * The option list for an input-taking action: {labels, codes}, parallel.
 *
 * Blank is a real answer here and it means two different things, so it is
 * said twice: for click lock it is "whichever button is held" and it goes
 * FIRST, because that is the behaviour the action shipped with; everywhere
 * else it is "the same input you pressed" and it goes last, after the
 * explicit buttons. `cur` is the value the row already has -- anything this
 * list does not offer (a key name, a tilt direction, a hand-edited code) is
 * put at the front, so opening the editor can never quietly rewrite it.
 */
InputValueChoices(atype, cur := "") {
    labels := []
    codes := []
    if (atype = "moddrag") {
        for m in MODDRAG_CODES {
            labels.Push(ModifierLabel(m))
            codes.Push(m)
        }
        if (cur = "")                        ; a new row starts on the first
            return {labels: labels, codes: codes}
    } else {
        if (atype = "clicklock") {
            labels.Push("Whichever button is held")
            codes.Push("")
        }
        for c in INPUT_VALUE_CODES {
            labels.Push(InputLabel(c))
            codes.Push(c)
        }
        if (atype != "clicklock") {
            labels.Push("Same as this input")
            codes.Push("")
        }
    }
    for c in codes {
        if (c = cur)
            return {labels: labels, codes: codes}
    }
    labels.InsertAt(1, InputLabel(cur))
    codes.InsertAt(1, cur)
    return {labels: labels, codes: codes}
}

; "*" is stored in the config; the GUI shows it as an explicit Global label.
AppDisp(code) {
    return (code = "*") ? "Global (all apps)" : code
}

AppCodeFromDisp(label) {
    return (label = "Global (all apps)") ? "*" : label
}

IsWheel(code) {
    for wh in WHEELS {
        if (wh = code)
            return true
    }
    return false
}

IsMouseInput(code) {
    for b in BUTTONS {
        if (b = code)
            return true
    }
    return IsWheel(code)
}

; Any referenced input that is not one of the five mouse buttons or four wheel
; directions is a KEYBOARD key (v0.1). Deliberately defined by exclusion: there
; is no enumerable list of keys the way there is for BUTTONS/WHEELS, so the
; config is the only source of truth for which keys exist. Everything the
; engine does with an input -- state machine, resolver, layers, native
; passthrough -- is already input-agnostic, because SendNativeDown emits
; "{Blind}{<name> Down}", which is as valid for CapsLock as for XButton1.
IsKeyInput(code) {
    return (code != "") && !IsMouseInput(code)
}

; Keys that TYPE something. Binding one of these bare (no modifier) means a
; tap/hold binding must suppress and delay the character, which in a dictation
; field reads as dropped or laggy typing. Not forbidden -- the binding dialog
; warns and asks -- but never silent. Modified combos are exempt: Ctrl+J does
; not type a J.
; The alphabet lives in a function STATIC, never a top-level global: a global
; assigned below the Init() call at :282 is the v1.2.0 LAYER_BASE_LABEL crash.
IsBareTypingKey(code) {
    static typing := "abcdefghijklmnopqrstuvwxyz0123456789``-=[]\;',./"
    if (StrLen(code) != 1)
        return false
    return InStr(typing, StrLower(code)) > 0
}

; The mouse counterpart of IsBareTypingKey. To tell a tap from a hold the
; engine must WITHHOLD the physical middle-click until the threshold passes,
; and IntelliSpace uses middle-drag to PAN -- so a hold/tap-hold row on
; MButton, or a layer hosted on MButton (which is a hold by another name),
; makes panning feel dead for holdThreshold and can swallow it outright.
; Warned and confirmed, never blocked: on a trackball the middle button is a
; legitimate place to put a layer, and this is a cost to accept knowingly,
; exactly like the bare typing keys above.
MButtonHoldRisk(btn, event, layer := "*") {
    return (btn = "MButton" && event = "hold")
}

MButtonHoldWarning() {
    return "Holding the middle button withholds the physical middle-click"
        . " until RadMapper can tell a tap from a hold -- and IntelliSpace"
        . " uses middle-drag to pan, so panning will feel dead for the hold"
        . " threshold and a quick pan can be lost.`n`nSet it anyway?"
}

; --- key names (v0.3) --------------------------------------------------------
; THE v0.2 KEYBOARD BUG, in one sentence: an input's stored name has to be a
; HOTKEY name ("Numpad1"), but v0.2's key dialog filled that field from the
; Send-syntax keycode picker, which writes SEND tokens ("{Numpad1}"). Every
; key row therefore reached Hotkey() as "*{Numpad1}", which throws -- so the
; key was never hooked and the remap silently did nothing. Normalization runs
; on load (MigrateRow), on save (KeyOk) and at hook time (SyncHooks), so a
; braced name can never reach Hotkey() again from any path.

; "{Numpad1}" -> "Numpad1", "{ ] }" -> "]", "Numpad1" -> "Numpad1".
; Only a token that is ENTIRELY wrapped in one pair of braces is unwrapped;
; anything else (a combo like "^{c}", junk) is returned untouched for
; KeyNameValid to reject with a message the user can act on.
NormalizeInputName(s) {
    s := Trim(s)
    if (StrLen(s) >= 3 && SubStr(s, 1, 1) = "{" && SubStr(s, -1) = "}") {
        inner := Trim(SubStr(s, 2, StrLen(s) - 2))
        if (inner != "" && !InStr(inner, "{") && !InStr(inner, "}"))
            return inner
    }
    return s
}

; A name AHK can actually build a hotkey from. GetKeyVK/GetKeySC throw on an
; unknown name, which is exactly the test we want -- and unlike a trial
; Hotkey() registration it leaves NO variant behind (a stray disabled global
; variant would shadow the context-scoped one the engine registers later and
; silently un-remap the key).
KeyNameValid(name) {
    if (name = "" || InStr(name, "{") || InStr(name, "}") || InStr(name, " "))
        return false
    try {
        if (GetKeyVK(name) != 0 || GetKeySC(name) != 0)
            return true
    }
    return false
}

; NumLock twin. A numpad key sends a DIFFERENT virtual key depending on
; NumLock: Numpad1 with it on, NumpadEnd with it off -- and a hotkey on one
; never fires for the other. A reading-room numpad is exactly the input this
; matters for, so every numpad row is hooked as BOTH names (SyncHooks) and
; read as both physically (InputHeldPhysical). "" when the name has no twin.
KeyTwin(name) {
    static twins := Map(
        "Numpad0", "NumpadIns", "Numpad1", "NumpadEnd", "Numpad2", "NumpadDown",
        "Numpad3", "NumpadPgDn", "Numpad4", "NumpadLeft", "Numpad5", "NumpadClear",
        "Numpad6", "NumpadRight", "Numpad7", "NumpadHome", "Numpad8", "NumpadUp",
        "Numpad9", "NumpadPgUp", "NumpadDot", "NumpadDel")
    for a, b in twins {
        if (a = name)
            return b
        if (b = name)
            return a
    }
    return ""
}

; The name a twin pair is STORED under, so one physical key is one row
; whichever NumLock state recorded it (the recorder can hand back either).
CanonicalInputName(name) {
    static primary := Map("NumpadIns", "Numpad0", "NumpadEnd", "Numpad1",
        "NumpadDown", "Numpad2", "NumpadPgDn", "Numpad3", "NumpadLeft", "Numpad4",
        "NumpadClear", "Numpad5", "NumpadRight", "Numpad6", "NumpadHome", "Numpad7",
        "NumpadUp", "Numpad8", "NumpadPgUp", "Numpad9", "NumpadDel", "NumpadDot")
    for a, b in primary {
        if (a = name)
            return b
    }
    return name
}

; Every hotkey name one bound input must be registered under.
InputHookNames(name) {
    out := [name]
    tw := KeyTwin(name)
    if (tw != "")
        out.Push(tw)
    return out
}

; Physical-down test that understands the NumLock twin. The watchdog and the
; auto-repeat cap both ask "is this input still physically held?"; asking
; GetKeyState("Numpad1") with NumLock off always answers no, which would kill
; a legitimate key auto-repeat and log a phantom watchdog recovery.
InputHeldPhysical(name) {
    for n in InputHookNames(name) {
        try {
            if RM_KeyHeld(n)
                return true
        }
    }
    return false
}

Cfg(k) {
    s := g_Cfg["settings"]
    return s.Has(k) ? s[k] : DEFAULTS[k]
}

CfgSet(k, v) {
    g_Cfg["settings"][k] := v
}

; v1.0 (E1): rows carry ONE "layer" context = "*" (Base, no held button) or a
; held-button path ("XButton2" or nested "XButton2/XButton1", cap depth 2).
; The old separate "while" field is gone -- a button hosts a layer simply by
; having rows scoped to it, and holding it arms that layer (see MatchScore).
NewBinding(app, layer, mods, button, event, type, value) {
    b := Map()
    b["app"] := app
    b["layer"] := layer
    b["mods"] := mods
    b["button"] := button
    b["event"] := event
    a := Map()
    a["type"] := type
    a["value"] := value
    b["action"] := a
    return b
}

; ── STARTER PACKS ────────────────────────────────────────────────────────
; A pack is a handful of ORDINARY bindings with a name. Applying one writes
; those rows through the same UpsertBinding the editor uses, so what you get
; is exactly what you could have built by hand -- editable, deletable, and
; visible on the Mouse page. There is no pack state to unapply: delete the
; rows. Each row: [app, layer, mods, button, event, type, value].
StarterPacks() {
    return [
        {name: "PowerScribe on the thumb buttons",
         sub:  "button 4 = previous field, button 5 = next field, everywhere",
         rows: [["*", "*", "", "XButton1", "tap", "ps_prev", ""],
                ["*", "*", "", "XButton2", "tap", "ps_next", ""]]},
        {name: "PACS zoom and pan on the thumb buttons",
         sub:  "in PACS: hold 4 to zoom (Alt+drag), hold 5 to pan (Ctrl+drag)",
         ; The left button is deliberately NOT in this pack. A native row
         ; scoped to one app is not an INERT row (InertShape wants app "*"),
         ; so adding one would HOOK the left button inside PACS and turn
         ; every click into an injected resend -- the shape behind the
         ; dead-mouse report. Left stays native there by simply having no
         ; row, which is what it already is. A TAP of either thumb button
         ; still sends the modified left click: that is what moddrag does
         ; on a tap.
         rows: [["PACS", "*", "", "XButton1", "hold", "moddrag", "LAlt"],
                ["PACS", "*", "", "XButton2", "hold", "moddrag", "LCtrl"]]},
        {name: "Monitor hopping on the thumb buttons",
         sub:  "the shipped default: tap 4 / 5 to jump the pointer left / right",
         rows: [["*", "*", "", "XButton1", "tap", "tele_prev", ""],
                ["*", "*", "", "XButton2", "tap", "tele_next", ""]]}]
}

StarterPackByName(name) {
    for pk in StarterPacks() {
        if (pk.name = name)
            return pk
    }
    return 0
}

; Apply a pack by name. Rows that would REPLACE a real (non-inert) binding
; are counted and confirmed first; the shipped defaults count too, because
; "the thumb buttons stopped hopping monitors" would otherwise be a mystery.
StarterPackApply(name) {
    pk := StarterPackByName(name)
    if !IsObject(pk) {
        HUD("No starter pack called " name, "warn")
        return
    }
    rows := []
    replacing := []
    for r in pk.rows {
        ; Packs say "PACS"; the profile may have been renamed since.
        b := NewBinding(r[1] = "PACS" ? PacsAppName() : r[1], r[2], r[3], r[4], r[5], r[6], r[7])
        for d in FindDupBinding(b) {
            old := g_Cfg["bindings"][d]
            if !IsInertRow(old)
                replacing.Push(InputLabel(r[4]) " " r[5] ": " DescribeAction(old["action"]))
        }
        rows.Push(b)
    }
    if (replacing.Length > 0) {
        msg := "Apply “" name "”?`n`nThis replaces what these already do:`n"
        for line in replacing
            msg .= "  • " line "`n"
        ok := IsSet(Atlas) ? Atlas.Confirm(msg)
            : (MsgBox(msg, "RadMapper", "YesNo Icon?") = "Yes")
        if !ok
            return
    }
    for b in rows
        UpsertBinding(b)
    AfterCfgChange()
    saved := IsSet(Atlas) ? Atlas.SaveOrWarn() : SaveCfg()
    if IsSet(Atlas)
        try Atlas.Build()
    if saved
        HUD("Applied “" name "” — " rows.Length " setting"
            . (rows.Length = 1 ? "" : "s") " on the Mouse page", "jade")
    else
        HUD("Applied for now — not written to disk", "danger")
}

; Default config is a clean slate (v0.3): nothing bound, every input fully
; native until the user adds bindings in the GUI. The site's app profiles and
; one demo macro are pre-created because they hook nothing on their own.
DefaultCfg() {
    c := Map()
    c["version"] := 1
    c["resetEpoch"] := CFG_RESET_EPOCH
    c["settings"] := Map()
    for k, v in DEFAULTS
        c["settings"][k] := v
    ; A fresh config already HAS what the seed-once migrations add. Without
    ; these flags the first load after a reset re-added a CapsLock row or
    ; the syngo.via profile that had been deleted in the meantime.
    for f in ["seedSyngo", "seedCapsLock07", "migPanic123"]
        c["settings"][f] := 1

    apps := []
    a1 := Map()
    a1["name"] := "PACS"
    a1["match"] := ["IntelliSpacePACSRadiology.exe"]
    apps.Push(a1)
    a2 := Map()
    a2["name"] := "PowerScribe"
    a2["match"] := ["Nuance.PSOne.exe", "Nuance.PowerScribe360.exe"]
    apps.Push(a2)
    a3 := Map()
    a3["name"] := "Syngo.via"
    a3["match"] := ["syngo.Common.Container.exe"]
    apps.Push(a3)

    c["apps"] := apps

    c["layers"] := ["Base"]
    c["layerHosts"] := LAYER_HOSTS.Clone()
    c["bindings"] := []

    macros := Map()
    demo := []
    s1 := Map()
    s1["type"] := "psdictate"
    s1["value"] := ""
    demo.Push(s1)
    s2 := Map()
    s2["type"] := "sleep"
    s2["value"] := 150
    demo.Push(s2)
    s3 := Map()
    s3["type"] := "psnext"
    s3["value"] := ""
    demo.Push(s3)
    macros["DictateThenNextField"] := demo
    c["macros"] := macros
    c["layouts"] := []
    ; Scratchpad snippets. The clipboard HISTORY is deliberately not here --
    ; see the S14c header: it never touches disk.

    c["psExes"] := ["Nuance.PowerScribe360.exe", "Nuance.PSOne.exe"]
    SeedDefaultBindings(c)
    SeedNativeDefaults(c)
    return c
}

/**
 * The bindings a fresh install ships with (v0.4.1, AJ's set).
 *
 * v0.3 deliberately shipped a clean slate -- nothing bound, every input
 * native -- which was the right call while the engine was still being
 * trusted. It is the wrong call now: a fresh config is something this user
 * hits on every machine, and an empty one means re-mapping the same five
 * things by hand every time.
 *
 * These are added ONLY when the binding list is empty, i.e. on a genuinely
 * new config. They never appear in, or over, a config that already exists --
 * an upgrade path that quietly re-adds rows the user deleted would be worse
 * than the problem it solves.
 *
 * On the backtick: AutoHotkey's own escape character is the backtick, but
 * that is a SOURCE-TEXT rule. The button code stored here is one literal
 * backtick character at runtime, which is what Hotkey() wants as the name of
 * that key. If it ever fails to hook on a non-US layout, the scan-code form
 * "SC029" names the same physical key and KeyNameValid accepts it.
 */
SeedDefaultBindings(cfg) {
    if (cfg["bindings"].Length > 0)
        return
    b := cfg["bindings"]
    ; ` -- dictation, the single most-pressed control in the room
    b.Push(NewBinding("*", "*", "", "``", "tap", "ps_dictate", ""))
    ; CapsLock -- dictation on a tap; held, it opens the CapsLock layer tab
    b.Push(CapsLockDictateRow())
    ; thumb buttons -- monitor teleport, left and right
    b.Push(NewBinding("*", "*", "", "XButton1", "tap", "tele_prev", ""))
    b.Push(NewBinding("*", "*", "", "XButton2", "tap", "tele_next", ""))
    ; Nothing on the keyboard beyond the backtick (v0.7): the [ and ] rows
    ; that used to ship here took two typing keys away and delayed them.
}

; CapsLock ships as dictation on a TAP. Its HOLD is its layer (the "Hold
; CapsLock" tab): while that tab is empty a press fires dictation at once;
; once it has rows, a tap dictates on release and a hold arms the layer.
; Hooking CapsLock suppresses its native toggle, so Caps Lock stays off.
CapsLockDictateRow() {
    return NewBinding("*", "*", "", "CapsLock", "tap", "ps_dictate", "")
}

; The name of the profile that matches the IntelliSpace exe -- "PACS" as
; shipped, whatever it was renamed to since. Rows are scoped by profile NAME,
; so seeding the literal "PACS" into a config whose profile is called
; something else would write rows that never apply.
PacsAppName(apps := 0) {
    if !IsObject(apps)                       ; DefaultCfg builds its own
        apps := MGet(g_Cfg, "apps", [])      ; list before g_Cfg exists
    for app in apps {
        for entry in MGet(app, "match", []) {
            if InStr(entry, "IntelliSpacePACSRadiology.exe")
                return MGet(app, "name", "PACS")
        }
    }
    return "PACS"
}

; Every input ships LISTED in the Mappings view, mapped to its system default
; function -- and those rows are inert (IsInertRow): the engine neither
; indexes nor hooks them, so out of the box every input is byte-for-byte
; hardware-native. Seeds are added only for inputs with no binding rows at
; all, so they can never shadow or fight a real assignment; reloading a
; config re-seeds anything left uncovered.
SeedNativeDefaults(cfg) {
    have := Map()
    have.CaseSense := "Off"
    for row in cfg["bindings"]
        have[MGet(row, "button", "")] := 1
    for btn in BUTTONS {
        if !have.Has(btn)
            cfg["bindings"].Push(NewBinding("*", "*", "", btn, "tap", "native", ""))
    }
    for wh in WHEELS {
        if !have.Has(wh)
            cfg["bindings"].Push(NewBinding("*", "*", "", wh, "turn", "native", ""))
    }
}

; v1.0 (E1) config migration: fold the retired "while" field and named layers
; into the unified button-path "layer". Runs once on every load (back-compat,
; like the v0.7 native-default seeding) so an existing RadMouseConfig.json
; upgrades silently. A row's new layer is:
;   - the old "while" holder, if set   (while=X  ->  layer=X, depth 1)
;   - else "*" if the old layer was Base/empty/"*"   (base context)
;   - else the old named layer kept verbatim -- which names no held button, so
;     it resolves to nothing (opaque): the binding is inert until AJ rebuilds
;     it as a button-hold in the mouse map. Trust-safe: it can never misfire.
; Paths are capped at depth 2. The retired layer/layertoggle ACTIONS become
; "none" (they toggled the old named-layer state, which no longer exists).
MigrateCfg() {
    s := MGet(g_Cfg, "settings", 0)
    if IsObject(s) {
        ; v1.2.3: background PS delivery REMOVED. ControlSend to an unfocused
        ; WPF PowerScribe silently drops keys, so the option was a trap: with
        ; it on, dictate/next/prev only worked when PS was already focused
        ; (workstation finding, 2026-07-24). Drop the stale key on load.
        if s.Has("psBackground")
            s.Delete("psBackground")
        ; v1.2.3: panic hotkey default eased ^!+F12 -> ^!q (bench E2-4).
        ; Migrate only the OLD DEFAULT; a customized binding is kept.
        ; Once only: a user who picks ^!+F12 later must keep it.
        if !s.Has("migPanic123") {
            s["migPanic123"] := 1
            if (MGet(s, "hkPanic", "") = "^!+F12")
                s["hkPanic"] := "^!q"
        }
        ; v0.3: the scroll engine, gestures and chords are gone. Their knobs
        ; are deleted so the saved file stops carrying settings nothing reads.
        for k in RETIRED_SETTINGS {
            if s.Has(k)
                s.Delete(k)
        }
    }
    ; v0.4.8: the syngo.via profile, seeded once into an existing config.
    ; Guarded by a flag rather than by the profile's absence, so deleting it
    ; keeps it deleted. (It used to carry "instant clicks" for MB1-3; since
    ; v0.7 that is the rule in every program and the field is gone.)
    if (IsObject(s) && !s.Has("seedSyngo")) {
        s["seedSyngo"] := 1
        if !AppMatches("syngo.Common.Container.exe") {
            a := Map()
            a["name"] := "Syngo.via"
            ; exe ONLY: the ahk_class carries a per-run token, exactly as
            ; PowerScribe's does.
            a["match"] := ["syngo.Common.Container.exe"]
            g_Cfg["apps"].Push(a)
        }
    }
    ; v0.7: CapsLock = dictate on tap, seeded ONCE into a config with no
    ; CapsLock row at all. Flag-guarded, so deleting it keeps it deleted.
    if (IsObject(s) && !s.Has("seedCapsLock07")) {
        s["seedCapsLock07"] := 1
        free := true
        for row in g_Cfg["bindings"] {
            if (MGet(row, "button", "") = "CapsLock")
                free := false
        }
        if free
            g_Cfg["bindings"].Push(CapsLockDictateRow())
    }
    ; v0.3: chord and gesture ROWS are dropped outright -- there is no engine
    ; left to run them, and a silently-kept row would reappear in no UI.
    if g_Cfg.Has("chords")
        g_Cfg.Delete("chords")
    if g_Cfg.Has("gestures")
        g_Cfg.Delete("gestures")
    for row in g_Cfg["bindings"]
        MigrateRow(row)
}

MigrateRow(row) {
    if !(row is Map)
        return
    w := MGet(row, "while", "")
    if (w != "")
        row["layer"] := w
    else {
        L := MGet(row, "layer", "*")
        if (L = "Base" || L = "")
            row["layer"] := "*"
    }
    if row.Has("while")
        row.Delete("while")
    a := MGet(row, "action", 0)
    if (IsObject(a)) {
        t := MGet(a, "type", "")
        if (t = "layer" || t = "layertoggle" || t = "autoscroll")
            a["type"] := "none"
    }
    ; v0.3.4: "Teleport monitor" took a typed value, which the vector UI has
    ; no field for -- so it became two plain actions. prev/next rows convert;
    ; a row naming a monitor NUMBER is left alone and still runs, it simply is
    ; not offered in the dropdown any more.
    if (IsObject(a) && MGet(a, "type", "") = "teleport") {
        tv := StrLower(Trim(MGet(a, "value", "")))
        if (tv = "prev" || tv = "-1" || tv = "left" || tv = "l") {
            a["type"] := "tele_prev"
            a["value"] := ""
        } else if (tv = "next" || tv = "+1" || tv = "1" || tv = "right"
            || tv = "r" || tv = "") {
            a["type"] := "tele_next"
            a["value"] := ""
        }
    }
    ; v0.3 KEY FIX: a key row's input is a HOTKEY NAME ("Numpad1"), never a
    ; Send token ("{Numpad1}"). v0.2's key dialog filled the field from the
    ; Send-syntax key picker, so every key row landed on disk braced -- and
    ; Hotkey("*{Numpad1}") throws, which is exactly why keyboard remaps did
    ; nothing. Normalize on load so existing configs repair themselves.
    row["button"] := CanonicalInputName(NormalizeInputName(MGet(row, "button", "")))
    ; v0.3.1: the same repair for an action VALUE that names an input, so a row
    ; already saved as "Right Button" or "{RButton}" starts working on load.
    if (IsObject(a) && (MGet(a, "type", "") = "native"
        || MGet(a, "type", "") = "dblclick"
        || MGet(a, "type", "") = "dragmove")) {
        rv := ResolveInputValue(MGet(a, "value", ""))
        if IsInputTarget(rv)
            a["value"] := rv
    }
    parts := []
    for p in LayerParts(row)
        parts.Push(CanonicalInputName(NormalizeInputName(p)))
    if (parts.Length > 0) {
        L := ""
        for p in parts
            L .= (L = "" ? "" : "/") p
        row["layer"] := L
    }
}

; The held-button components a row's layer requires (empty for Base "*"). The
; single funnel every layer-aware site uses so the "*"/"Base" base-context
; spellings are interpreted in exactly one place. ValidateCfg drops any path
; with more than one component, so in practice this is zero or one host.
LayerParts(row) {
    L := MGet(row, "layer", "*")
    if (L = "*" || L = "" || L = "Base")
        return []
    out := []
    for p in StrSplit(L, "/") {
        if (p != "")
            out.Push(p)
    }
    return out
}

; The layer currently ARMED for display: the held layer-host buttons (down,
; unconsumed, and hosting a layer), joined as a path, or "Base". Lets the status
; bar show a layer engaging in real time.
CurrentLayerDisp() {
    parts := ""
    for name, st in g_BS {
        if (st.down && !st.consumed && IsObject(st.spec) && st.spec.layerHost)
            parts .= (parts = "" ? "" : "/") name
    }
    return parts = "" ? "Base" : parts
}

; True if a layer-path code names btn as one of its held components (used by
; the dialogs to reject a row whose own input is also its held layer button).
LayerIncludes(layer, btn) {
    if (layer = "*" || layer = "" || layer = "Base")
        return false
    for p in StrSplit(layer, "/") {
        if (p != "" && p = btn)
            return true
    }
    return false
}

/**
 * Decide where the config lives, and rescue one from an older install.
 *
 * Runs once, before any config I/O. Three outcomes, in order:
 *
 *   1. PORTABLE -- a file named "RadMapper.portable" sits beside the script.
 *      Config and backups stay in the script's folder, as they used to. This
 *      is now opt-in rather than the default, because the default is what
 *      lost the bindings on every upgrade.
 *   2. The per-user home %APPDATA%\RadMapper already has a config. Use it.
 *      This is the steady state, and every future version lands here with
 *      nothing to migrate.
 *   3. Nothing there yet -- so ADOPT the best config we can find from an
 *      older install (AdoptCfg) before falling back to defaults.
 */
ResolveCfgPaths() {
    global CFG_DIR, CFG_PATH, BACKUP_DIR, CFG_PORTABLE
    if FileExist(A_ScriptDir "\RadMapper.portable") {
        CFG_PORTABLE := true
        CFG_DIR := A_ScriptDir
    } else {
        CFG_DIR := A_AppData "\RadMapper"
    }
    CFG_PATH := CFG_DIR "\" CFG_NAME
    BACKUP_DIR := CFG_DIR "\Backups"
    try {
        if !DirExist(CFG_DIR)
            DirCreate(CFG_DIR)
    }
    if (!CFG_PORTABLE && !FileExist(CFG_PATH))
        AdoptCfg()
}

/**
 * Find the newest config belonging to an older install and copy it in.
 *
 * Only ever runs when the per-user home has no config, and only ever COPIES
 * -- the source is left untouched, so a wrong guess costs nothing and the old
 * install keeps working.
 *
 * Where it looks: beside this script first (the classic location, and the
 * strongest signal), then one level down from the handful of folders a
 * downloaded script actually gets run from. That last part is not elegant,
 * but it is the difference between this user re-mapping everything by hand
 * and not: their configs are sitting next to old copies in Downloads.
 *
 * Newest-by-modified wins, because that is the one with the most work in it.
 */
AdoptCfg() {
    global CFG_ADOPTED
    best := ""
    bestT := ""
    ; The script's own folder, both names, checked first and unconditionally.
    for nm in [CFG_NAME, OLD_CFG_NAME] {
        cand := A_ScriptDir "\" nm
        if FileExist(cand) {
            best := cand
            bestT := FileGetTime(cand, "M")
            break
        }
    }
    if (best = "") {
        home := EnvGet("USERPROFILE")
        roots := [home "\Downloads", A_Desktop, A_MyDocuments,
                  home "\OneDrive\Downloads", home "\OneDrive\Desktop",
                  home "\OneDrive\Documents"]
        for root in roots {
            if (root = "" || !DirExist(root))
                continue
            ; The root itself, then ONE level of subfolders. Not recursive:
            ; a full sweep of a user profile at startup is not acceptable on a
            ; shared workstation, and one level covers "Downloads\RadMapper".
            for nm in [CFG_NAME, OLD_CFG_NAME] {
                cand := root "\" nm
                if FileExist(cand) {
                    t := FileGetTime(cand, "M")
                    if (bestT = "" || t > bestT) {
                        best := cand
                        bestT := t
                    }
                }
            }
            loop files root "\*", "D" {
                for nm in [CFG_NAME, OLD_CFG_NAME] {
                    cand := A_LoopFileFullPath "\" nm
                    if FileExist(cand) {
                        t := FileGetTime(cand, "M")
                        if (bestT = "" || t > bestT) {
                            best := cand
                            bestT := t
                        }
                    }
                }
            }
        }
    }
    if (best = "")
        return false
    try {
        FileCopy(best, CFG_PATH, 0)          ; 0 = never overwrite
        CFG_ADOPTED := best
        return true
    }
    return false
}

LoadCfg() {
    global g_Cfg, g_CfgDirty, g_CfgRecoveryBlocked
    g_CfgRecoveryBlocked := false
    g_CfgDirty := false                      ; disk wins over any pending
    SetTimer(CfgFlush, 0)                    ; debounced in-memory save
    if (CFG_PATH = "")
        ResolveCfgPaths()
    if FileExist(CFG_PATH) {
        try {
            txt := FileRead(CFG_PATH, "UTF-8")
            loaded := JsonLoad(txt)
            ValidateCfgShape(loaded)
            if (IsObject(loaded) && loaded.Has("bindings")) {
                if (MGet(loaded, "resetEpoch", 0) < CFG_RESET_EPOCH
                    && ResetCfgOnce())
                    return
                BackupCfg()                  ; pre-migration snapshot (v1.3)
                before := JsonDump(loaded)
                g_Cfg := loaded
                NormalizeCfg()               ; backfill + validate + migrate
                RebuildIndex()
                ; What validation dropped or migration rewrote was only in
                ; memory, so the same rows were dropped (and the same lines
                ; logged) on every start until the next edit. Write it once.
                if (JsonDump(g_Cfg) !== before)
                    SaveCfg()
                return
            }
            throw Error("no bindings array")
        } catch as e {
            ; A corrupt config used to mean "start from defaults", which on a
            ; station where the config IS the workflow is the worst possible
            ; answer. Try the newest backup first; every load takes one, so
            ; there is almost always a good file one step back.
            if RestoreNewestBackup(e.Message)
                return
            preserved := CFG_PATH ".corrupt-" FormatTime(, "yyyyMMdd-HHmmss") "-" A_TickCount
            try FileCopy(CFG_PATH, preserved, 0)
            catch {
                if FileExist(CFG_PATH)       ; gone = already preserved
                    g_CfgRecoveryBlocked := true
            }
            MsgBox(CFG_NAME " could not be parsed (" e.Message ")"
                . " and no usable backup was found.`n`n"
                . (g_CfgRecoveryBlocked
                    ? "The original could not be copied. Saving is blocked to protect it. Copy it to a safe folder, then restart RadMapper."
                    : "Loading defaults. The original has been preserved here:`n" preserved),
                "RadMapper", "Iconx")
            g_Cfg := DefaultCfg()
            RebuildIndex()
            return
        }
    }
    g_Cfg := DefaultCfg()
    SaveCfg()
    RebuildIndex()
}

/**
 * The v0.7.1 one-time reset (see CFG_RESET_EPOCH). Copies the old config
 * aside FIRST and gives up -- loading it as normal -- if that copy fails, so
 * the old setup can never be lost. Returns true when defaults are in place.
 */
ResetCfgOnce() {
    global g_Cfg
    aside := CFG_DIR "\RadMapperConfig.pre-reset-"
        . FormatTime(, "yyyyMMdd-HHmmss") ".json"
    try FileCopy(CFG_PATH, aside, 0)
    catch
        return false
    g_Cfg := DefaultCfg()
    SaveCfg()
    RebuildIndex()
    Problem("config-reset", "Config reset to the shipped defaults for v"
        . RM_VERSION "; the old one is saved as " aside)
    TrayTip("Settings were reset to the shipped defaults. Your old config is"
        . " saved in " CFG_DIR " (Import config… brings it back).",
        "RadMapper", "Iconi")
    return true
}

/**
 * Walk the backups newest-first and load the first one that parses.
 *
 * The bad file is renamed rather than deleted -- on a clinical workstation
 * the corrupt config is evidence, and it costs one file to keep it.
 */
RestoreNewestBackup(why) {
    global g_Cfg
    names := ""
    try {
        loop files BACKUP_DIR "\RadMapperConfig-*.json"
            names .= (names = "" ? "" : "`n") A_LoopFileName
    }
    if (names = "")
        return false
    arr := StrSplit(Sort(names, "R"), "`n")   ; R = reverse: newest first
    for nm in arr {
        path := BACKUP_DIR "\" nm
        try {
            loaded := JsonLoad(FileRead(path, "UTF-8"))
            ValidateCfgShape(loaded)
            if (!IsObject(loaded) || !loaded.Has("bindings"))
                continue
            ; Normalize BEFORE moving the bad file aside: a backup that
            ; throws here must leave the original where it is, or the
            ; caller's preserve-copy fails and saving gets blocked.
            prev := g_Cfg
            try {
                g_Cfg := loaded
                NormalizeCfg()
                RebuildIndex()
            } catch {
                g_Cfg := prev
                continue
            }
            try FileMove(CFG_PATH, CFG_PATH ".corrupt-"
                . FormatTime(, "yyyyMMdd-HHmmss"), 1)
            SaveCfg()
            Problem("config-restored", "Config was unreadable (" why
                . "); restored from " nm)
            TrayTip("Config was unreadable and has been restored from the "
                . FormatTime(FileGetTime(path, "M"), "d MMM HH:mm")
                . " backup.", "RadMapper", "Icon!")
            return true
        }
    }
    return false
}

; Shared load/import funnel: backfill keys added since the file was written,
; then validate rows and run migrations. Operates on g_Cfg in place.
/**
 * imported = this config came from another machine's file. Its layouts were
 * captured on THAT station, so MigrateLayoutSlots must not stamp them with
 * this one.
 */
NormalizeCfg(imported := false) {
    c := g_Cfg
    ValidateCfgShape(c)
    c["resetEpoch"] := CFG_RESET_EPOCH       ; a config kept is a config chosen
    if !c.Has("settings")
        c["settings"] := Map()
    for k in ["apps", "layers"] {
        if !c.Has(k)
            c[k] := (k = "apps") ? DefaultCfg()["apps"] : []
    }
    if !c.Has("layouts")
        c["layouts"] := []
    if !c.Has("stations")
        c["stations"] := []
    ; v0.7.2: radial menus live in their own script now. Their list goes
    ; with them; the rows that opened one are dropped by ValidateCfg.
    if c.Has("menus")
        c.Delete("menus")
    ; v0.7.2: the scratchpad is gone, and its snippets with it
    if c.Has("snippets")
        c.Delete("snippets")
    if !c.Has("macros")
        c["macros"] := Map()
    if !c.Has("psExes")
        c["psExes"] := DefaultCfg()["psExes"]
    if (c["layers"].Length = 0)
        c["layers"] := ["Base"]
    ; v0.7.2: the layer hosts, BEFORE ValidateCfg reads them. A list that
    ; is not a list at all (hand edit) falls back to the default rather than
    ; to "no hosts", which would drop every layer row.
    c["layerHosts"] := (MGet(c, "layerHosts", 0) is Array)
        ? CleanLayerHosts(c["layerHosts"]) : LAYER_HOSTS.Clone()
    ; MigrateRow folds "while" into "layer" and unbraces paths. It must run
    ; BEFORE the first ValidateCfg, which otherwise drops an old-format row
    ; as "can no longer hold a layer" instead of migrating it. Idempotent.
    for row in c["bindings"] {
        if (row is Map && row.Has("button"))  ; a row with no input stays
            MigrateRow(row)                   ; invalid and is dropped
    }
    ValidateCfg()
    MigrateCfg()                             ; v1.0: while + named layers ->
    ValidateCfg()                            ; ...and the v0.7 host rules
                                             ; applied to what migration wrote
    MigrateLayoutSlots(!imported)            ; v0.6.2: layouts learn their screen
    SeedNativeDefaults(c)                  ; unified button-path layer.
}

ValidateCfgShape(c) {
    if !(c is Map) || !(MGet(c, "bindings", 0) is Array)
        throw Error("Expected a settings object with a bindings list")
    for key in ["apps", "layers", "layouts", "psExes",
                "stations"] {
        if (c.Has(key) && !(c[key] is Array))
            throw Error(key " must be a list")
    }
    for key in ["settings", "macros"] {
        if (c.Has(key) && !(c[key] is Map))
            throw Error(key " must be an object")
    }
}

; Drop malformed rows from a hand-edited config file so one bad row cannot
; raise an error on every mouse event or break a GUI refresh.
ValidateCfg() {
    kept := []
    for row in g_Cfg["bindings"] {
        if !(row is Map && row.Has("button") && row.Has("event")
            && MGet(row, "action") is Map && MGet(row, "action").Has("type"))
            continue
        ; v0.7: a double-tap, triple-tap or tap-then-hold row has no engine
        ; left to run it. Dropped here, named in Diagnostics, never silently
        ; kept where no dropdown could show it.
        if IsRetiredEvent(MGet(row, "event", "")) {
            Problem("retired", InputLabel(MGet(row, "button", "")) " "
                . MGet(row, "event", "") " row dropped: that trigger no longer exists")
            continue
        }
        ; v0.7.2: features removed from RadMapper (pointer speed, drag
        ; scroll, the W/L dial, the clipboard shelf, radial menus -- now a
        ; separate script). A row using one has nothing left to run it:
        ; dropped, and named in Diagnostics.
        if (MGet(row, "app", "*") = "")      ; hand edit: "" means everywhere
            row["app"] := "*"
        t0 := MGet(MGet(row, "action", Map()), "type", "")
        if (t0 = "sniper" || t0 = "boost" || t0 = "scrollptr"
            || t0 = "zoomptr" || t0 = "wldial") {
            Problem("retired", InputLabel(MGet(row, "button", "")) " "
                . MGet(row, "event", "") " → " t0 " row dropped: pointer speed,"
                . " drag scroll and the W/L dial were removed in 0.7.2")
            continue
        }
        if (t0 = "clipboard" || t0 = "scratchpad") {
            Problem("retired", InputLabel(MGet(row, "button", "")) " "
                . MGet(row, "event", "") " → " t0 " row dropped: the clipboard "
                . "history and scratchpad were removed in 0.7.2")
            continue
        }
        if (t0 = "radial") {
            Problem("retired", InputLabel(MGet(row, "button", "")) " "
                . MGet(row, "event", "") " → radial menu row dropped: radial "
                . "menus are a separate script now")
            continue
        }
        ; v0.7: a layer is held open by a thumb button or CapsLock, one at
        ; a time; and left / right / middle hold only inside a program.
        if !LayerPathAllowed(MGet(row, "layer", "*")) {
            Problem("retired", InputLabel(MGet(row, "button", "")) " row dropped: "
                . "'" MGet(row, "layer", "*") "' can no longer hold a layer "
                . "(only " LayerHostsText() " can)")
            continue
        }
        if (IsPrimaryButton(MGet(row, "button", "")) && MGet(row, "event", "") = "hold"
            && MGet(row, "app", "*") = "*") {
            Problem("retired", InputLabel(MGet(row, "button", "")) " hold row dropped: "
                . "holding that button only works inside one program now")
            continue
        }
        kept.Push(row)
    }
    g_Cfg["bindings"] := kept
    kept := []
    for app in g_Cfg["apps"] {
        if !(app is Map && app.Has("name") && MGet(app, "match", 0) is Array
            && app["match"].Length > 0)
            continue
        ; v0.7: per-program "instant clicks" is the rule everywhere now,
        ; so the field it lived in is retired from every profile.
        if app.Has("noHold")
            app.Delete("noHold")
        ; A hand edit that gives one of these the wrong SHAPE must cost that
        ; one field, not the whole profile and not a crash in the hook thread:
        ; ParkNow reads park["x"] and throws on the wrong type from inside a
        ; press. Drop the field and the app behaves as if it was never set.
        ; noFollow is a FLAG (0/1), read for truthiness -- any object is
        ; truthy, so a Map here silently turns follow-focus off for the app.
        if (app.Has("noFollow") && IsObject(app["noFollow"]))
            app.Delete("noFollow")
        if (app.Has("park") && !(app["park"] is Map))
            app.Delete("park")
        kept.Push(app)
    }
    g_Cfg["apps"] := kept
    if (g_Cfg.Has("settings") && g_Cfg["settings"] is Map) {
        ; The two wheel repeat guards are read from the WHEEL HOOK, once per
        ; notch, where a hand-edited "fast" or an object would throw inside a
        ; Critical thread. Clamped to 0..1000 ms here; anything unusable
        ; falls back to the shipped value. (v0.6.5)
        for k in ["tiltRepeatMs", "wheelRepeatMs"] {
            if g_Cfg["settings"].Has(k) {
                v := g_Cfg["settings"][k]
                g_Cfg["settings"][k] := ClampInt(IsObject(v) ? "" : v,
                    0, 1000, DEFAULTS[k])
            }
        }
    }
    ValidateLayouts()
}

/**
 * Layouts and stations, coerced to shape (v0.6.2c).
 *
 * These are read from TIMER THREADS -- the guard tick and the station watch
 * -- where an exception is not a message box, it is a thread that dies
 * silently and a feature that has stopped working with nothing on screen to
 * say so. A hand-edited (or hand-merged, or half-written) config must
 * therefore cost the bad field, never the tick. Numbers are the whole risk:
 * JSON gives back a String for "40" and LayoutSlotTarget does arithmetic on
 * fx/fw without asking.
 */
ValidateLayouts() {
    ; String() on a Map throws (no ToString), and so does comparing one with
    ; `=`. Everything below a hand edit can reach goes through this.
    flat(v) => IsObject(v) ? "" : String(v)
    if (g_Cfg.Has("layouts") && g_Cfg["layouts"] is Array) {
        kept := []
        for lay in g_Cfg["layouts"] {
            if !(lay is Map)
                continue
            lay["name"] := flat(MGet(lay, "name", ""))
            g := flat(MGet(lay, "guard", 0))
            lay["guard"] := (g = 1 || g = 2) ? Integer(g) : 0
            lay["station"] := flat(MGet(lay, "station", ""))
            if (!lay.Has("slots") || !(lay["slots"] is Array))
                lay["slots"] := []
            slots := []
            for s in lay["slots"] {
                if !(s is Map)
                    continue
                s["exe"] := flat(MGet(s, "exe", ""))
                s["title"] := flat(MGet(s, "title", ""))
                s["cls"] := flat(MGet(s, "cls", ""))
                s["state"] := (flat(MGet(s, "state", "normal")) = "max")
                    ? "max" : "normal"
                for k in ["mon", "x", "y", "w", "h", "ord"] {
                    if s.Has(k)
                        s[k] := IsNumber(s[k]) ? Integer(s[k]) : 0
                }
                ; A slot with a non-numeric fraction cannot be adapted, and
                ; half a fraction set is worse than none -- the missing one
                ; defaults while the others do not, which places the window
                ; somewhere nobody chose. Drop the whole slot.
                bad := false
                for k in ["fx", "fy", "fw", "fh"] {
                    if !s.Has(k)
                        continue
                    if !IsNumber(s[k]) {
                        bad := true
                        break
                    }
                    s[k] := Float(s[k])
                }
                if bad
                    continue
                slots.Push(s)
            }
            lay["slots"] := slots
            kept.Push(lay)
        }
        g_Cfg["layouts"] := kept
    }
    if (g_Cfg.Has("stations") && g_Cfg["stations"] is Array) {
        kept := []
        for st in g_Cfg["stations"] {
            ; A station with no key is unreachable: StationEntry finds one by
            ; key and nothing else.
            if (!(st is Map) || flat(MGet(st, "key", "")) = "")
                continue
            st["key"] := flat(st["key"])
            st["name"] := flat(MGet(st, "name", ""))
            st["imaging"] := flat(MGet(st, "imaging", ""))
            st["layout"] := flat(MGet(st, "layout", ""))
            kept.Push(st)
        }
        g_Cfg["stations"] := kept
    }
}

SaveCfg() {
    global g_CfgDirty
    global g_CfgSaveFailed
    if g_CfgRecoveryBlocked {
        g_CfgDirty := true
        g_CfgSaveFailed := true
        Problem("save-blocked", "Preserve the corrupt config and restart before saving")
        return false
    }
    SetTimer(CfgFlush, 0)                    ; cancel any pending debounce
    ; Not re-entrant: a timer or hotkey thread saving between FileAppend and
    ; FileMove moved the shared .new away and the outer FileMove threw -- a
    ; false "not saved" on a save that had worked.
    wasCrit := A_IsCritical
    Critical "On"
    try {
        txt := JsonDump(g_Cfg)
        tmp := CFG_PATH ".new"                   ; write-then-rename: the
        if FileExist(tmp)                        ; config file never has a
            FileDelete(tmp)                      ; missing/half-written moment
        FileAppend(txt, tmp, "UTF-8")
        FileMove(tmp, CFG_PATH, 1)
        g_CfgDirty := false
        g_CfgSaveFailed := false
        return true
    } catch as e {
        g_CfgDirty := true                  ; keep edits available for retry
        g_CfgSaveFailed := true
        Problem("save-failed", "Config save failed: " e.Message)
        TrayTip("Changes are not saved. Check the settings folder and retry. "
            . e.Message, "RadMapper", "Iconx")
        return false
    } finally {
        Critical(wasCrit)
    }
}

; Debounced save for high-frequency GUI controls (sliders fire Change on
; every tick of a drag): mark dirty, write once the stream pauses. SaveCfg
; is the single funnel and cancels the pending flush, so explicit saves and
; the debounce can never double-write out of order.
CfgDirty() {
    global g_CfgDirty
    g_CfgDirty := true
    SetTimer(CfgFlush, -400)
}

CfgFlush() {
    if g_CfgDirty
        SaveCfg()
}

; --- config safety net (v1.3) --------------------------------------------------
; The config is real clinical workflow now: snapshot it on every load (pre-
; migration, so a bad upgrade can always be rolled back) and before an import
; replaces it. Newest 10 kept. NOTE (AJ, standing): this script must NEVER
; auto-start with Windows -- it is a personal tool on a SHARED workstation.

BackupCfg() {
    try {                                    ; backups must never block a load
        if !FileExist(CFG_PATH)
            return
        if !DirExist(BACKUP_DIR)
            DirCreate(BACKUP_DIR)
        stamp := FormatTime(, "yyyyMMdd-HHmmss")
        FileCopy(CFG_PATH, BACKUP_DIR "\RadMapperConfig-" stamp ".json", 1)
        PruneBackups(10)
    }
}

; Timestamps embed in the names, so a lexical sort IS chronological.
PruneBackups(keep) {
    names := ""
    loop files BACKUP_DIR "\RadMapperConfig-*.json"
        names .= (names = "" ? "" : "`n") A_LoopFileName
    if (names = "")
        return
    arr := StrSplit(Sort(names), "`n")
    i := 1
    while (arr.Length - i + 1 > keep) {      ; oldest sort first: delete from
        try FileDelete(BACKUP_DIR "\" arr[i]) ; the front until `keep` remain
        i += 1
    }
}

CfgExport() {
    dest := FileSelect("S16", CFG_DIR "\RadMapperConfig-export.json",
        "Export RadMapper config", "JSON (*.json)")
    if (dest = "")
        return
    if !RegExMatch(dest, "i)\.json$")
        dest .= ".json"
    try {
        if FileExist(dest)
            FileDelete(dest)
        FileAppend(JsonDump(g_Cfg), dest, "UTF-8")
        HUD("Config exported")
    } catch as e {
        MsgBox("Export failed: " e.Message, "RadMapper", "Iconx")
    }
}

CfgImport() {
    global g_Cfg, g_CfgDirty, g_CfgSaveFailed
    src := FileSelect(3, , "Import RadMapper config", "JSON (*.json)")
    if (src = "")
        return
    incoming := 0
    try {
        incoming := JsonLoad(FileRead(src, "UTF-8"))
        ValidateCfgShape(incoming)
        if (!IsObject(incoming) || !incoming.Has("bindings")
            || Type(incoming["bindings"]) != "Array")
            throw Error("not a RadMapper config (no `"bindings`" array)")
    } catch as e {
        MsgBox("Import failed: " e.Message "`nThe current config is untouched.",
            "RadMapper", "Iconx")
        return
    }
    BackupCfg()                              ; snapshot what's being replaced
    previous := g_Cfg
    wasDirty := g_CfgDirty
    try {
        g_Cfg := incoming
        NormalizeCfg(true)                   ; imported: never stamp this station
    } catch as e {
        g_Cfg := previous
        MsgBox("Import failed: " e.Message "`nYour current settings are unchanged.",
            "RadMapper", "Iconx")
        return
    }
    if !SaveCfg() {
        g_Cfg := previous
        g_CfgDirty := wasDirty
        g_CfgSaveFailed := false             ; memory and disk agree again
        ; Silence here read as success: the window rebuilt, showed the OLD
        ; bindings, and nothing said the import had been rolled back.
        MsgBox("Import failed: the new settings could not be written to "
            . CFG_PATH ". Your current settings are unchanged.",
            "RadMapper", "Iconx")
        return
    }
    AfterCfgChange()
    HUD("Config imported")
}

; --- theme layer (G0, v1.3) ----------------------------------------------------
; Light/dark for the dim reading room. "auto" follows the Windows apps theme.
; Colors are set through AHK's own c/Background options (its WM_CTLCOLOR
; handling paints statics/checkbox text over the dark BackColor), plus the
; undocumented-but-stable DarkMode_* uxtheme classes for control chrome
; (buttons, dropdowns, scrollbars, list headers) and the DWM immersive-dark
; title bar. Everything is try-wrapped: on wine or an old Windows build the
; chrome simply stays light. G0 caveat: the Tab3 strip themes imperfectly --
; the G1 sidebar replaces it.

ThemeDark() {
    t := Cfg("theme")
    if (t = "dark")
        return 1
    if (t = "light")
        return 0
    try return !RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion"
        . "\Themes\Personalize", "AppsUseLightTheme")
    return 0
}

; SetWindowTheme wrapper: app = "" restores the default theme.
CtlTheme(hwnd, app) {
    try {
        if (app = "")
            DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "ptr", 0, "ptr", 0)
        else
            DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "wstr", app, "ptr", 0)
    }
}

; DISABLE theming for one control (v1.4.2). Note the difference from CtlTheme:
; NULL,NULL restores the default theme, whereas EMPTY STRINGS turn theming off.
; Needed for the status bar, which ignores SB_SETBKCOLOR while it is themed --
; that is why the dark status bar stayed light through v1.4.1.
CtlThemeOff(hwnd) {
    try DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "wstr", "", "wstr", "")
}

; Process-wide dark-mode opt-in (v1.4.1). WITHOUT this, SetWindowTheme with a
; "DarkMode_*" class is silently IGNORED -- uxtheme gates those classes on the
; process having opted in. Edits/ListViews/ListBoxes still looked dark because
; they also get an explicit Background color above; Buttons and DDLs get chrome
; ONLY, which is why they were the controls that stayed light. The chrome was
; never "blocked on this Windows build" -- the opt-in was just missing.
;
; Undocumented uxtheme exports, resolved BY ORDINAL (they have no public names):
;   135 = SetPreferredAppMode(PreferredAppMode) on Win10 1903+
;         AllowDarkModeForApp(BOOL)             on Win10 1809
;   133 = AllowDarkModeForWindow(HWND, BOOL)
;   104 = RefreshImmersiveColorPolicyState()
; We pass ForceDark(2)/Default(0), NOT AllowDark(1): AllowDark means "follow the
; OS", so with Windows in light mode but RadMouse's theme set to Dark the chrome
; would render light again -- the very bug this fixes. 2 and 0 are also correct
; under 1809's AllowDarkModeForApp(BOOL) (2 is simply nonzero = TRUE), so no
; build sniffing is needed -- deliberate, not luck. Residual 1809-only gap:
; there, TRUE still defers to the OS, so OS-light + forced-dark keeps light
; chrome. Unfixable through this API and moot on any current build.
; Everything is try-wrapped and ordinal lookup is cached: on wine, on an older
; build, or if MS ever drops the ordinals, this degrades to the pre-v1.4.1
; behavior (light chrome) and can never raise.
UxOrd() {
    static o := 0                            ; static, NOT a top-level global:
    if (o)                                   ; a global assigned below Init()
        return o                             ; is the v1.2.0 load-crash trap
    r := {p135: 0, p133: 0, p104: 0}
    try {
        h := DllCall("GetModuleHandle", "str", "uxtheme", "ptr")
        if (!h)
            h := DllCall("LoadLibrary", "str", "uxtheme.dll", "ptr")
        if (h) {                             ; ordinal as lpProcName = MAKEINTRESOURCE
            r.p135 := DllCall("GetProcAddress", "ptr", h, "ptr", 135, "ptr")
            r.p133 := DllCall("GetProcAddress", "ptr", h, "ptr", 133, "ptr")
            r.p104 := DllCall("GetProcAddress", "ptr", h, "ptr", 104, "ptr")
        }
    }
    o := r
    return o
}

; Opt the PROCESS in/out. Must run before the SetWindowTheme calls below.
ThemeAppMode(dark) {
    o := UxOrd()
    if (!o.p135)
        return 0
    try {
        DllCall(o.p135, "int", dark ? 2 : 0, "int")   ; ForceDark : Default
        if (o.p104)
            DllCall(o.p104)                  ; flush the cached color policy
    }
    return 1
}

; Opt one top-level WINDOW in/out (per-hwnd half of the same opt-in).
ThemeWindow(hwnd, dark) {
    o := UxOrd()
    if (o.p133)
        try DllCall(o.p133, "ptr", hwnd, "int", dark ? 1 : 0, "int")
}

; Apply the resolved theme to a Gui (main window and every dialog funnel
; through here). Idempotent and reversible: switching back to light restores
; every control to its default colors/theme.
ApplyTheme(g) {
    dark := ThemeDark()
    ThemeAppMode(dark)                       ; v1.4.1: process opt-in FIRST --
    ThemeWindow(g.Hwnd, dark)                ; the DarkMode_* classes below are
                                             ; ignored without it
    v := dark ? 1 : 0                        ; DWM dark title bar: attr 20,
    try {                                    ; 19 on pre-1903 builds
        if DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd,
            "uint", 20, "int*", v, "uint", 4)
            DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd,
                "uint", 19, "int*", v, "uint", 4)
    }
    ; Soft grey palette (AJ: "less extreme, maybe greys"): mid-grey ground
    ; 2B2D30, raised fields 383B3F, text D6D8DA -- not near-black/white.
    g.BackColor := dark ? "2B2D30" : "Default"
    for hwnd, ctl in g {
        switch ctl.Type, "Off" {
            case "Text", "Slider":
                try ctl.Opt(dark ? "cD6D8DA" : "cDefault")
            case "GroupBox":
                ; A themed GroupBox draws its OWN caption in the theme colour
                ; and ignores the c option entirely -- "Click a zone" stayed
                ; near-black on the dark ground. Turning theming off makes the
                ; caption honour the control colour again (it then draws the
                ; classic etched frame, which reads fine on the dark ground).
                if (dark)
                    CtlThemeOff(hwnd)
                else
                    CtlTheme(hwnd, "")
                try ctl.Opt(dark ? "cD6D8DA" : "cDefault")
            case "CheckBox", "Radio":
                try ctl.Opt(dark ? "cD6D8DA" : "cDefault")
                CtlTheme(hwnd, dark ? "DarkMode_Explorer" : "")
            case "Edit":
                try ctl.Opt(dark ? "Background383B3F cDCDEE0"
                    : "BackgroundDefault cDefault")
                CtlTheme(hwnd, dark ? "DarkMode_CFD" : "")
            case "ListView":
                try ctl.Opt(dark ? "Background303336 cDCDEE0"
                    : "BackgroundDefault cDefault")
                CtlTheme(hwnd, dark ? "DarkMode_Explorer" : "")
                hdr := 0
                try hdr := SendMessage(0x101F, 0, 0, , "ahk_id " hwnd)
                if hdr                       ; LVM_GETHEADER -> dark header
                    CtlTheme(hdr, dark ? "DarkMode_Explorer" : "")
            case "ListBox":
                try ctl.Opt(dark ? "Background383B3F cDCDEE0"
                    : "BackgroundDefault cDefault")
                CtlTheme(hwnd, dark ? "DarkMode_Explorer" : "")
            case "Button":
                CtlTheme(hwnd, dark ? "DarkMode_Explorer" : "")
            case "DDL", "ComboBox":
                CtlTheme(hwnd, dark ? "DarkMode_CFD" : "")
            case "StatusBar":
                if (dark)
                    CtlThemeOff(hwnd)        ; themed SBs IGNORE SB_SETBKCOLOR
                else
                    CtlTheme(hwnd, "")       ; re-theme on the way back to light
                try SendMessage(0x2001, 0,   ; 0xFF000000 = CLR_DEFAULT
                    dark ? 0x46423F : 0xFF000000, , "ahk_id " hwnd)
                ; Text colour is handled by SbSetText/SbDrawItem below: a
                ; status bar ignores SetFont's colour entirely.
        }
    }
    try DllCall("RedrawWindow", "ptr", g.Hwnd, "ptr", 0, "ptr", 0,
        "uint", 0x185)                       ; INVALIDATE|ERASE|ALLCHILDREN|NOW
}


; ── §4  CONTEXT RESOLUTION & BINDING LOOKUP ─────────────────────────────────

; Criteria string for one app "match" entry. Bare name = ahk_exe; "title:xyz"
; matches a title substring; anything containing "ahk_" is used verbatim.
MatchCrit(m) {
    if (SubStr(m, 1, 6) = "title:")
        return Trim(SubStr(m, 7))
    if InStr(m, "ahk_")
        return m
    return "ahk_exe " m
}

; Name of the app profile owning the active window, or "". Cached per
; foreground hwnd for 100 ms: a window switch changes the hwnd and misses
; instantly, so app changes resolve exactly; only a title mutation within the
; same window can be stale, bounded at 100 ms. The scan itself goes through
; the RM_AppScan shim slot so the rig can simulate foreground apps.
ActiveAppName() {
    global g_AppCache
    hwnd := FgHwnd()
    now := A_TickCount
    d := now - g_AppCache.tick               ; d >= 0 guards the 49.7-day
    if (hwnd = g_AppCache.hwnd && d >= 0 && d <= 100)   ; A_TickCount wrap
        return g_AppCache.name
    name := RM_AppScan()
    ; write hwnd LAST: it is the cache-validity gate, and a thread switch
    ; between these lines must never pair a new hwnd with a stale name
    g_AppCache.name := name
    g_AppCache.tick := now
    g_AppCache.hwnd := hwnd
    return name
}

/**
 * Is this app profile opted out of follow-focus?
 *
 * An escape hatch for one kind of application: one that
 * spreads itself over several displays and moves its own foreground around.
 * Taking the name as an argument rather than re-reading the foreground keeps
 * it usable from FollowTick, which has already resolved it.
 */
AppNoFollow(name) {
    if (!g_Idx.anyNoFollow || name = "")
        return false
    for app in g_Cfg["apps"] {
        if (MGet(app, "name", "") != name)
            continue
        return MGet(app, "noFollow", 0) ? true : false
    }
    return false
}

/** True when some profile already claims this match string. */
AppMatches(needle) {
    for app in MGet(g_Cfg, "apps", []) {
        for entry in MGet(app, "match", []) {
            if (InStr(entry, needle))
                return true
        }
    }
    return false
}

AppCacheClear() {
    global g_AppCache, g_AppAtCache
    g_AppCache.hwnd := 0
    g_AppCache.tick := 0
    g_AppCache.name := ""
    g_AppAtCache.hwnd := 0
    g_AppAtCache.tick := 0
    g_AppAtCache.name := ""
}

; v0.7.2: the profile owning a given top-level window (the one UNDER THE
; POINTER, for mouse input), or "". A mouse button belongs to the window it
; is pressed over: with PowerScribe focused on one screen and the pointer
; over PACS on another, the PACS rows must apply. Same 100 ms per-hwnd cache
; as ActiveAppName.
global g_AppAtCache := {hwnd: 0, tick: 0, name: ""}
AppNameAt(hwnd) {
    global g_AppAtCache
    if !hwnd
        return ""
    now := A_TickCount
    d := now - g_AppAtCache.tick
    if (hwnd = g_AppAtCache.hwnd && d >= 0 && d <= 100)
        return g_AppAtCache.name
    name := ProfileOf(hwnd)
    ; an owned popup with a title-only match: judge it by its owner
    if (name = "") {
        o := DllCall("GetAncestor", "ptr", hwnd, "uint", 3, "ptr")
        if (o && o != hwnd)
            name := ProfileOf(o)
    }
    g_AppAtCache.name := name
    g_AppAtCache.tick := now
    g_AppAtCache.hwnd := hwnd
    return name
}

; ── §4b  BINDING INDEX ──────────────────────────────────────────────────────
; Membership index over the config. Rebuilt on every config mutation (all
; mutation paths funnel through AfterCfgChange; LoadCfg covers startup and
; reload-from-disk). Resolution still happens at EVENT time against the live
; context -- the index only narrows which rows each lookup scores, preserving
; the live-dispatch design (GUI edits apply with no reload). Rows are stored
; by reference and in config order, so in-place edits stay visible and the
; later-rows-win tiebreak is unchanged. Every Map is CaseSense Off because
; hand-edited configs may carry any casing ("xbutton1").

; A row has the inert SHAPE when it maps an input back onto its own system
; default, unconditionally: "native" action with empty/self value, on the
; input's base event (tap for buttons, turn for wheels), global app/layer,
; no while, no mods.
InertShape(row) {
    a := MGet(row, "action", 0)
    if (!IsObject(a) || !IsNativeAct(a["type"]))
        return false
    v := MGet(a, "value", "")
    btn := MGet(row, "button", "")
    if !(v = "" || v = btn)
        return false
    ev := MGet(row, "event", "")
    if !(ev = (IsWheel(btn) ? "turn" : "tap"))
        return false
    return MGet(row, "app", "*") = "*" && MGet(row, "layer", "*") = "*"
        && MGet(row, "mods", "") = ""
}

; A row is INERT -- behaviorally identical to the input being absent from the
; config -- only when it has the inert shape AND nothing else references its
; input (no other non-shape binding rows, no layer-host references). Inert
; rows exist so the Mappings list can SHOW
; every input mapped to its system default, XMBC-style, without the engine
; hooking or even seeing them -- a v0.7 requirement after the workstation
; dead-mouse report: anything hooked depends on injected resends, which
; elevated apps (UIPI) silently discard. The reference test is what keeps
; the later-rows-win contract intact: a trailing "restore native" row over
; an earlier remap is REFERENCED (by the remap), stays indexed, and wins the
; tie exactly as in v0.6; and a layer holder keeps its explicit tap row so
; release fallbacks still fire. Skipped by RebuildIndex (which computes
; g_Idx.refd first) and SyncHooks; the GUI labels only truly inert rows as
; "(system default)".
IsInertRow(row) {
    return InertShape(row) && !g_Idx.refd.Has(MGet(row, "button", ""))
}

RebuildIndex() {
    global g_Idx
    idx := {bind: Map(), layerBind: Map(), anyMods: false, anyApp: false,
        anyNoFollow: false, refd: Map()}
    ; Cheap gate for AppNoFollow: with no profile asking for it, the hot
    ; path never resolves the foreground app name.
    for app in MGet(g_Cfg, "apps", []) {
        if MGet(app, "noFollow", 0)
            idx.anyNoFollow := true
    }
    idx.bind.CaseSense := "Off"
    idx.layerBind.CaseSense := "Off"
    idx.refd.CaseSense := "Off"
    ; pass 1: every input referenced by anything OTHER than an inert-shaped
    ; row. Only rows on unreferenced inputs may be treated as inert. An input
    ; named in any row's layer path (its layer HOST) counts as referenced.
    for row in g_Cfg["bindings"] {
        if !InertShape(row)
            idx.refd[MGet(row, "button", "")] := 1
        for part in LayerParts(row)
            idx.refd[part] := 1
    }
    ; pass 2: the lookup maps, skipping truly inert rows. layerBind indexes a
    ; row under EACH held-button component of its layer path, so a button's
    ; layer-host lookup finds every row that path arms.
    for row in g_Cfg["bindings"] {
        if (InertShape(row) && !idx.refd.Has(MGet(row, "button", "")))
            continue
        k := MGet(row, "button", "") "|" MGet(row, "event", "")
        if !idx.bind.Has(k)
            idx.bind[k] := []
        idx.bind[k].Push(row)
        for part in LayerParts(row) {
            if !idx.layerBind.Has(part)
                idx.layerBind[part] := []
            idx.layerBind[part].Push(row)
        }
        if (MGet(row, "mods", "") != "")
            idx.anyMods := true
        if (MGet(row, "app", "*") != "*")
            idx.anyApp := true
    }
    g_Idx := idx
    AppCacheClear()
}

; --- per-app park points (v0.3.6) ---------------------------------------------
; A park point is one screen coordinate remembered per app profile: the spot
; the pointer should be at when that app has focus. For PowerScribe that is
; the dictation field; for the viewer it is the middle of the image.
;
; Follow-focus uses it instead of the window centre, and the "Park cursor"
; action jumps there on demand -- which is the one that pays off on a Stream
; Deck or a thumb button, because it costs no travel at all.
;
; Stored ABSOLUTE, per profile, in the config: apps[i]["park"] = {x, y}.
; Absolute rather than window-relative on purpose -- a reading station's
; windows do not move, and a relative point silently rots the moment an app
; is opened on a different monitor, which is worse than being obviously
; wrong once.

ParkOf(name) {
    for app in g_Cfg["apps"] {
        if (app["name"] != name)
            continue
        pk := MGet(app, "park", 0)
        ; a hand-edited {"x":"left"} must not throw in FollowTick
        if (pk is Map && pk.Has("x") && pk.Has("y")
            && IsNumber(pk["x"]) && IsNumber(pk["y"]))
            return {x: Integer(pk["x"]), y: Integer(pk["y"])}
        return 0
    }
    return 0
}

SetPark(name, px, py) {
    for app in g_Cfg["apps"] {
        if (app["name"] != name)
            continue
        pk := Map()
        pk["x"] := px
        pk["y"] := py
        app["park"] := pk
        SaveCfg()
        return true
    }
    return false
}

ClearPark(name) {
    for app in g_Cfg["apps"] {
        if (app["name"] = name && app.Has("park")) {
            app.Delete("park")
            SaveCfg()
            return true
        }
    }
    return false
}

; The "Park cursor" action: go to the active app's spot now.
ParkNow() {
    name := ActiveAppName()
    if (name = "") {
        HUD("No app profile matches this window", "warn")
        return
    }
    pk := ParkOf(name)
    if !IsObject(pk) {
        HUD("No park spot for " name " — set one in the Apps tab", "warn")
        return
    }
    DllCall("SetCursorPos", "int", pk.x, "int", pk.y)
    if Cfg("hud")
        HUD("Parked for " name, "cyan")
}

RM_AppScanReal() {
    return ProfileOf(DllCall("GetForegroundWindow", "ptr"))
}

; The profile a window belongs to. The MOST SPECIFIC match wins (a title
; match beats an exe-only one, a class adds one), config order breaks ties:
; a "PACS viewer" profile matched by title now wins over "PACS" by exe
; instead of never applying because PACS was listed first (v0.7.2).
ProfileOf(hwnd) {
    if !hwnd
        return ""
    best := "", bestSc := -1
    for app in g_Cfg["apps"] {
        for m in MGet(app, "match", []) {
            crit := MatchCrit(m)
            sc := (SubStr(LTrim(crit), 1, 4) != "ahk_" ? 2 : 0)
                + (InStr(crit, "ahk_class") ? 1 : 0)
            if (sc <= bestSc)
                continue
            try {
                if WinExist(crit " ahk_id " hwnd) {
                    best := app["name"]
                    bestSc := sc
                }
            }
        }
    }
    return best
}

; Physically-held keyboard modifiers as a "^!+#" string.
; PHYSICAL modifier state only, on purpose: a modifier a moddrag hold sends
; synthetically is what the application sees, not what a "Also hold" row
; means. Folding it in would change what every modifier-scoped row does for
; the length of a drag.
ModsHeld() {
    if !g_Idx.anyMods
        return ""                            ; no row anywhere uses modifiers
    s := ""
    if RM_KeyHeld("Ctrl")
        s .= "^"
    if RM_KeyHeld("Alt")
        s .= "!"
    if RM_KeyHeld("Shift")
        s .= "+"
    if (RM_KeyHeld("LWin") || RM_KeyHeld("RWin"))
        s .= "#"
    return s
}

; ── PASS-THROUGH (v0.7.2) ────────────────────────────────────────────────
; A temporary "RadMapper, stand back" that is NOT a pause: hooks stay in,
; the watchdog and deliveries keep running, but every press other than the
; pass-through input itself goes out natively (OnPressHK's native path) and
; the wheel scrolls natively. Hold the bound input for while-held; tap it to
; toggle, with a 2-minute safety off so it can never be forgotten on.
global g_Bypass := 0             ; {src, hosts, mom} while on
global BYPASS_MAX_MS := 120000

; The pass-through input itself and the layer host(s) its row lives under
; keep working -- otherwise a pass-through set up inside a layer could never
; be tapped off (its host would go native and arm nothing).
BypassFor(btn) {
    if (!IsObject(g_Bypass) || btn = g_Bypass.src)
        return false
    for h in g_Bypass.hosts {
        if (h = btn)
            return false
    }
    return true
}

BypassOn(src, mom := false, hosts := 0) {
    global g_Bypass
    if (src = "" || IsWheel(src)) {
        HUD("Pass-through belongs on a button or key, not the wheel", "warn")
        return
    }
    if IsObject(g_Bypass) {
        g_Bypass.mom := mom
        return
    }
    g_Bypass := {src: src, mom: mom, hosts: IsObject(hosts) ? hosts : []}
    SetTimer(BypassExpire, mom ? 0 : -BYPASS_MAX_MS)
    HUD("Pass-through ON — everything else is native"
        . (mom ? " while held" : " (tap again to end)"), "warn")
}

BypassOff(quiet := false) {
    global g_Bypass
    SetTimer(BypassExpire, 0)
    if !IsObject(g_Bypass)
        return
    g_Bypass := 0
    if !quiet
        HUD("Pass-through off", "jade")
}

BypassToggle(src, hosts := 0) {
    if IsObject(g_Bypass)
        BypassOff()
    else
        BypassOn(src, false, hosts)
}

BypassExpire(*) {
    if IsObject(g_Bypass) {
        BypassOff(true)
        HUD("Pass-through ended after 2 minutes", "mute")
    }
}

; Inputs whose next release belongs to a pause toggle (see OnReleaseHK).
global g_SwallowUp := Map()

; A "Toggle engine pause" row on this input that applies here, or 0. Read
; straight from the config: while paused, the index is still built but no
; other row may fire, so only this one type is looked for.
PauseTglRowFor(btn) {
    ctx := 0
    for row in g_Cfg["bindings"] {
        if (MGet(MGet(row, "action", Map()), "type", "") != "pausetgl")
            continue
        if (CanonicalInputName(NormalizeInputName(MGet(row, "button", ""))) != btn)
            continue
        if (MGet(row, "event", "") = "turn")
            continue
        ; the engine's own matcher: program, layer and modifiers all count
        ; (a "^!p" row must not resume on a bare P).
        if !IsObject(ctx)
            ctx := CurCtx(btn)
        ; program and modifiers by the matcher; the LAYER physically --
        ; while paused no host has a state, so the matcher's layer test
        ; could never pass and such a row paused but never resumed
        if (MatchScore(row, ctx, false) < 0)
            continue
        ok := true
        for part in LayerParts(row) {
            if !InputHeldPhysical(part)
                ok := false
        }
        if !ok
            continue
        return row
    }
    return 0
}

; Snapshot of everything a lookup needs. held = mapped buttons physically down.
; btn = the input being resolved: a MOUSE input (button or wheel) is scoped
; by the window under the pointer, a key by the foreground window (v0.7.2).
CurCtx(btn := "") {
    held := []
    layApp := ""                             ; the program a held layer host
    layWin := 0                              ; was pressed in (v0.7.2)
    for name, st in g_BS {
        ; only a press that was resolved AS a layer host holds a layer: a
        ; plain passthrough of the same input must not satisfy layer rows
        if (st.down && !st.consumed && IsObject(st.spec) && st.spec.layerHost) {
            held.Push(name)
            if IsObject(st.ctx) {
                layApp := st.ctx.app
                layWin := st.ctx.HasProp("win") ? st.ctx.win : 0
            }
        }
    }
    mouse := (btn != "" && IsMouseInput(btn))
    win := mouse ? RM_WinAt() : 0
    app := !g_Idx.anyApp ? "" : mouse ? AppNameAt(win) : ActiveAppName()
    return {app: app, mods: ModsHeld(), held: held, win: win,
        layApp: layApp, layWin: layWin}
}

; Does this action deliver to the FOREGROUND window (keystrokes, a modifier,
; a key remap) rather than to a fixed target (ps_* / pacs_keys) or the
; pointer (a click)?
FgDelivered(a) {
    t := a["type"]
    if (t = "keys" || t = "keysrepeat" || t = "text" || t = "moddrag")
        return true
    v := MGet(a, "value", "")
    return IsNativeAct(t) && v != "" && IsKeyInput(v)
}

; A PROGRAM-SCOPED row fires in the window that scoped it (v0.7.2). A mouse
; row is scoped by the window under the pointer, but keystrokes go to the
; foreground: with PowerScribe focused and the pointer on PACS, a PACS
; "keys r" row typed "r" into the report. Bring that window forward first
; (a native click would have activated it anyway); if it will not come,
; send nothing. Global rows, and key rows (scoped by the foreground), are
; unchanged.
AimFg(binding, ctx) {
    app := MGet(binding, "app", "*")
    if (app = "*" || !IsObject(ctx))
        return true
    win := (LayerParts(binding).Length && ctx.HasProp("layWin") && ctx.layWin)
        ? ctx.layWin : (ctx.HasProp("win") ? ctx.win : 0)
    if (!win || AppNameAt(win) != app)
        return true
    fg := DllCall("GetForegroundWindow", "ptr")
    if (DllCall("GetAncestor", "ptr", fg, "uint", 2, "ptr") = win)
        return true
    ; the program's own modal is in front of it: that is where keys belong
    if (!DllCall("IsWindowEnabled", "ptr", win)
        && DllCall("GetAncestor", "ptr", fg, "uint", 3, "ptr")
         = DllCall("GetAncestor", "ptr", win, "uint", 3, "ptr"))
        return true
    try WinActivate("ahk_id " win)
    if WinWaitActive("ahk_id " win, , 0.15)
        return true
    Problem("aim", AppDisp(app) " would not come forward; not sent: "
        . DescribeAction(binding["action"]))
    HUD(AppDisp(app) " would not come forward — nothing sent", "warn")
    return false
}

HeldHas(ctx, btn) {
    for b in ctx.held {
        if (b = btn)
            return true
    }
    return false
}

; Specificity score of a binding row against a context, or -1 if it does not
; apply. Each held-input layer component +64 (ANY held layer row outscores
; everything else, v0.6.6.6), each modifier +9 (a modifier row beats a plain
; program row, v0.7.2), app exact +8.
; checkLayer=false skips the held-path requirement AND its score: used by the
; layer-host probe, which asks "could this row apply if the path were held"
; while deciding what a press should arm.
MatchScore(row, ctx, checkLayer := true, checkMods := true) {
    sc := 0
    app := MGet(row, "app", "*")
    if (app != "*") {
        ; a LAYER row's program is the one its host was pressed in, not the
        ; one this member is pressed in (keys follow focus, mouse the
        ; pointer: a PACS layer failed whenever they differed)
        cmp := (checkLayer && ctx.HasProp("layApp") && ctx.held.Length
            && LayerParts(row).Length) ? ctx.layApp : ctx.app
        if (app != cmp)
            return -1
        sc += 8
    }
    if (checkLayer) {
        lay := MGet(row, "layer", "*")
        if (lay != "*" && lay != "" && lay != "Base") {
            for part in StrSplit(lay, "/") {
                if (part = "")
                    continue
                if !HeldHas(ctx, part)
                    return -1
                sc += 64
            }
        }
    }
    mods := MGet(row, "mods", "")
    if (mods != "" && checkMods) {
        loop parse mods {
            if !InStr(ctx.mods, A_LoopField)
                return -1
        }
        ; R10: 9 per modifier, so a modifier row beats a plain program row
        ; (9 > 8) -- a global Ctrl+X row was unreachable wherever a program
        ; row for X existed. Layers stay on top (64 > 4*9 + 8).
        sc += 9 * StrLen(mods)
    }
    return sc
}

; Best binding for (button, event) in ctx, or 0. Later rows win score ties so
; the GUI list order acts as a natural tiebreaker (index arrays keep config
; order, so >= preserves that exactly).
FindBindingFor(btn, event, ctx) {
    k := btn "|" event
    if !g_Idx.bind.Has(k)
        return 0
    best := 0
    bestScore := -1
    for row in g_Idx.bind[k] {
        sc := MatchScore(row, ctx)
        if (sc < 0)
            continue
        if (sc >= bestScore) {
            bestScore := sc
            best := row
        }
    }
    return best
}

; True if btn HOSTS A LAYER in this ctx -- i.e. some binding names btn
; in its layer path and otherwise applies (app/mods; the held-path requirement
; is skipped via checkLayer=false, since btn is the button now being pressed
; and is not yet in ctx.held). Holding btn arms that layer, so its own tap must
; be deferred (it may be a modifier) until we know the layer went unused.
LayerHostExists(btn, ctx) {
    if !g_Idx.layerBind.Has(btn)
        return false
    for row in g_Idx.layerBind[btn] {
        ; modifiers are judged when the layer row fires, not at the host's
        ; press: a Ctrl row in the layer must still make this a host
        if (MatchScore(row, ctx, false, false) >= 0)
            return true
    }
    return false
}

; Everything the state machine needs to know about btn in ctx, precomputed at
; press time so per-event work stays tiny.
SpecFor(btn, ctx) {
    tap     := FindBindingFor(btn, "tap", ctx)
    hold    := FindBindingFor(btn, "hold", ctx)
    ; A MORE SPECIFIC "Pass through" (or a tap "Block it") carves the whole
    ; INPUT out of the less specific rows of the other event: a PACS stock
    ; tap used to leave a global hold live in PACS (v0.7.2).
    if (IsObject(tap) && IsObject(hold)) {
        ts := MatchScore(tap, ctx), hs := MatchScore(hold, ctx)
        tt := tap["action"]["type"], ht := hold["action"]["type"]
        if (ts > hs && (tt = "stock" || tt = "none"))
            hold := 0
        else if (hs > ts && ht = "stock")
            tap := 0
    }
    layerHost := LayerHostExists(btn, ctx)

    ; Left, right and middle are instant everywhere: the only hold the engine
    ; honours on them is one written for the program in front, and they never
    ; host a layer. ValidateCfg and the editors already keep such rows out of
    ; the config; this is the guard for a hand-edited file (v0.7).
    if IsPrimaryButton(btn) {
        if (IsObject(hold) && MGet(hold, "app", "*") = "*")
            hold := 0
        ; v0.7.2: middle or right may host a layer when the user made it one
        if !LayerHostAllowed(btn)
            layerHost := false
    }

    hasAny := IsObject(tap) || IsObject(hold) || layerHost

    pure := !hasAny
    instantTap := false
    remap := ""
    if (!pure && IsObject(tap) && !IsObject(hold) && !layerHost) {
        a := tap["action"]
        v := MGet(a, "value", "")
        if (IsNativeAct(a["type"]) && (v = "" || v = btn))
            pure := true                 ; explicit native = plain passthrough
        else if (a["type"] = "native" && v != "" && !IsWheel(v))
            ; v0.3.1: a lone "native <other input>" row is a straight REMAP, and
            ; a remapped button must BE that button -- down on press, up on
            ; release. v0.2/v0.3 sent a whole click (down+up) at press time
            ; via ActionFire, so the remap fired early and could not drag,
            ; hold, marquee or window/level. Wheel targets keep the one-shot
            ; path below: a notch has no down/up.
            remap := v
        else
            instantTap := true           ; lone remap: fire on press, no waits
    }

    ; A tap row that is an explicit native default (seeded rows become
    ; indexed once their input gains another binding) must behave exactly
    ; like NO tap row for every mode decision -- otherwise adding a hold row
    ; to a seeded button would demote instant hold engagement to the
    ; pending/threshold path (rig S9/S10/S14 caught this).
    tapNative := !IsObject(tap)
    if (!tapNative && IsNativeAct(tap["action"]["type"])) {
        tv := MGet(tap["action"], "value", "")
        tapNative := (tv = "" || tv = btn)
    }

    ; A layer-host must NOT instant-fire its hold at press: holding it ARMS its
    ; layer, and its own hold/tap is deferred to release, firing only if the
    ; layer went unused (the QMK mod-tap rule). So instant hold is gated on the
    ; button not hosting a layer.
    ;
    ; And it is gated on the hold action being STATEFUL (StatefulHoldType --
    ; exactly ActionDown's special cases). A hold row carrying a ONE-SHOT
    ; action -- run a program, a macro, "PowerScribe: toggle dictation", a
    ; radial-free tele_next -- has no down phase to engage: ActionDown falls
    ; through to ActionFire, so instant engagement fired the whole action the
    ; instant the button went down. That is not a hold, it is a tap with a
    ; different name, and on a hold-ONLY row it made the threshold meaningless
    ; (a brush of the button launched the program). One-shots now wait for
    ; HoldTimer like every other hold, which is the only way a hold can be
    ; abandoned by letting go early.
    instantHold := IsObject(hold) && tapNative && !layerHost
        && StatefulHoldType(hold["action"]["type"])

    return {tap: tap, hold: hold, layerHost: layerHost, pure: pure,
        instantTap: instantTap, instantHold: instantHold,
        tapNative: tapNative, remap: remap}
}


; ── §5  ENGINE (press / release / wheel state machine) ──────────────────────
;
; Per-input state object fields:
;   down, consumed, mode, pressTick, gen, pollId, sx, sy,
;   spec, ctx, holdBinding, dragOn, usedAsMod, dial, passBtn, repStart
; Modes: passthru | pending | held | armedmod | fired
;   passthru  a native down is out; the up goes out on release
;   pending   the press is withheld until HoldTimer or the release decides
;   held      a hold action is engaged (ActionDown), ended by ActionUp
;   armedmod  a layer host past the threshold: silent while its layer is used
;   fired     a one-shot tap already went out at press
; st.gen increments on every transition; one-shot timers carry the gen they
; were armed with and abort if it moved on (stale-timer guard).

BS(btn) {
    return g_BS.Has(btn) ? g_BS[btn] : 0
}

ClearBS(btn) {
    ; universal teardown funnel: release, panic, ForceReleaseActive and the
    ; watchdog all land here
    if !g_BS.Has(btn)
        return
    st := g_BS[btn]
    ; A switcher commits when its holder goes up. A holder dropped while
    ; still "down" (lost Up, re-press) left the switcher open, and the
    ; watchdog's sweeps off, until Escape.
    ; Only a holder still DOWN is a lost Up: a normal release has already set
    ; down := false, and AppSwitchWatch reads exactly that as the commit.
    if (IsObject(g_AppSw) && g_AppSw.holder = st && st.down) {
        st.down := false
        AppSwitchClose(false)
    }
    g_BS.Delete(btn)
}

NewBS(btn) {
    global g_PollSeq
    g_PollSeq += 1
    st := {btn: btn, down: false, consumed: false, mode: "", pressTick: 0,
        gen: 0, pollId: g_PollSeq, sx: 0, sy: 0, spec: 0, ctx: 0,
        holdBinding: 0, dragOn: false, usedAsMod: false,
        passBtn: "", repStart: 0, polling: false,
        locked: false, physSeen: true, deckLocked: false}
    g_BS[btn] := st
    return st
}

; The name to SEND for a native passthrough. Rows are stored under the
; NumLock-ON numpad name (Numpad1), but with NumLock off that key physically
; produces NumpadEnd -- and sending Numpad1 there types "1" instead of moving
; the caret. Reproducing an input natively means reproducing the key the user
; actually pressed, so the twin is substituted when NumLock disagrees. Every
; other name passes straight through.
; "stock" is "native" pointed at ITSELF and nothing else: the input is
; re-emitted unchanged so the application's own binding handles it. Every
; engine test that asks "is this row just the input being itself?" has to
; answer yes for both codes, or a stock row would lose the eager first-press
; passthrough that keeps a plain click instant, would not start a late drag,
; and on a wheel would mint a synthetic left click instead of scrolling.
;
; It is a separate CODE rather than a relabelling of "native" because the two
; say different things in the list: "Native input: RButton" is a remap onto
; another button, while "Pass through" is an exception carved out of one.
; A stock row never carries a value, which is what makes them interchangeable
; everywhere below.
IsNativeAct(t) {
    return (t = "native" || t = "stock")
}

NativeName(btn) {
    tw := KeyTwin(btn)
    if (tw = "" || SubStr(btn, 1, 6) != "Numpad")
        return btn
    try {
        if !GetKeyState("NumLock", "T")
            return tw
    }
    return btn
}

; SafeSend, not RM_Send: an unusable input name (the "Right Button" class of
; typo) used to throw out of the hook thread, which killed the press and left
; the physical button suppressed and dead. Now it is a HUD note plus a
; Diagnostics entry, and the engine keeps running.
SendNativeDown(btn) {
    SafeSend("{Blind}{" NativeName(btn) " Down}")
}

SendNativeUp(btn) {
    SafeSend("{Blind}{" NativeName(btn) " Up}")
}

SendNativeClick(btn, n := 1) {
    SafeSend("{Blind}{" NativeName(btn) " " n "}")
}

; Send for user-authored key strings (binding values, macro steps, PS keys).
; A typo like {Bogus} raises an error; in a reading room that must be a quiet
; HUD note, never a modal error dialog. Send parses the whole string before
; sending anything, so a failure sends nothing (no partial Down).
SafeSend(v) {
    global g_SynthAt
    g_SynthAt := A_TickCount                 ; the watchdog's sweeps key off this
    try {
        RM_Send(v)
    } catch as e {
        Problem("send-error", "Send failed: " e.Message)
        HUD("Send error: " e.Message)
    }
}

global g_SynthAt := 0            ; tick of RadMapper's last synthetic input

; Foreground hwnd, reused within the same millisecond: OwnGuiActive and
; ActiveAppName both need it on the same event, and one DllCall is enough.
FgHwnd() {
    global g_FgHwnd, g_FgTick
    now := A_TickCount
    if (now != g_FgTick) {
        g_FgTick := now
        g_FgHwnd := DllCall("GetForegroundWindow", "ptr")
    }
    return g_FgHwnd
}

OwnGuiActive() {
    return g_OurHwnds.Has(FgHwnd())
}

; True if hwnd is one of THIS script's windows: a registered GUI/dialog, or
; any other window the process owns -- critically the open list of a
; DropDownList (class ComboLBox), a separate top-level popup that is NOT in
; g_OurHwnds. Positional test for the hook paths: a click aimed at our own UI
; must never be context-resolved through app profiles, whatever window holds
; the foreground. The HUD tooltip is excluded -- it trails the cursor, and
; claiming it would eat clicks aimed at whatever sits beneath it.
OwnWindowAt(hwnd) {
    if !hwnd
        return false
    ; Click-through overlays of ours -- the toast, the teleport flash -- sit
    ; over other apps by design. Claiming one would gate the engine native
    ; underneath it and eat clicks aimed at whatever is really there.
    if g_PassThru.Has(hwnd)
        return false
    if (IsSet(Lumi) && IsObject(Lumi._toast)) {
        try {
            if (hwnd = Lumi._toast.hwnd)
                return false
        }
    }
    if g_OurHwnds.Has(hwnd)
        return true
    pid := 0
    DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &pid)
    if (pid != DllCall("GetCurrentProcessId", "uint"))
        return false
    cls := ""
    try cls := WinGetClass("ahk_id " hwnd)
    return (cls != "" && cls != "tooltips_class32")
}

WinClassOf(hwnd) {
    c := ""
    try c := WinGetClass("ahk_id " hwnd)
    return c
}

; HotIf gate for the engine's mouse hooks. Returns 0 -> the hotkey is DISABLED
; and the physical click/scroll passes through natively (AHK docs: a hotkey
; disabled via HotIf "performs its native function ... passes through to the
; active window") whenever the cursor is over one of our OWN windows -- the
; settings GUI, its dialogs, and critically a DropDownList's popup list
; (ComboLBox). Suppress-and-reinject over those closed the popup and dropped the
; selection; not hooking at all is the only clean fix. Returns 1 elsewhere so the
; engine still processes clicks over other apps. On any error, default to 1
; (engine active) -- never silently disable the engine everywhere.
; An Up is let through whenever the engine owns a live press of that input:
; a press over PACS released over one of our windows (or a key whose action
; brought ours to the front) otherwise lost its release, leaving the layer
; armed or the state "down" until the watchdog's 30 s cap.
; The input a hotkey name is for: "*XButton1 Up" -> "XButton1".
HkInput(hk) => CanonicalInputName(RegExReplace(hk, "^[*~$]+|\s+Up$"))

UpOwned(hk) {
    if (SubStr(hk, -3) != " Up")
        return false
    s := BS(CanonicalInputName(RegExReplace(hk, "^[*~$]+|\s+Up$")))
    return (s && s.down) ? true : false
}

; A press NO row applies to here goes to Windows untouched -- decided at the
; gate, so it is never suppressed and re-sent (v0.7.2). An input hooked only
; for PACS used to be swallowed and re-injected everywhere else: dead over
; elevated windows (UIPI), invisible to other AutoHotkey scripts, and every
; click re-sent. Same pure-spec lookup OnPressHK makes.
GateNative(btn) {
    global g_WheelLast
    if (!g_Enabled || g_Testing || Warp.active || ClickLockOwns(btn))
        return false
    if ((s := BS(btn)) && s.down)            ; live state: repeats, stale Ups
        return false
    try {
        ctx := CurCtx(btn)
        if IsWheel(btn) {
            if IsObject(FindBindingFor(btn, "turn", ctx))
                return false
            g_WheelLast := A_TickCount       ; deck settle still sees the notch
            return true
        }
        spec := SpecFor(btn, ctx)
        ; a pure row inside a layer must still mark its holder used
        return spec.pure && !(IsObject(spec.tap) && LayerParts(spec.tap).Length)
    }
    return false
}

; An Up the engine has no claim on goes through untouched too.
UpClaimed(hk, inp) {
    return UpOwned(hk) || g_SwallowUp.Has(inp) || Warp.claimed.Has(inp)
        || (Warp.active && IsKeyInput(inp)) || ClickLockHolds(inp)
}

; A click lock latched this input: its physical release must be swallowed
; (it is what keeps the button down), even when its press went through the
; gate natively and left no state behind.
ClickLockHolds(inp) {
    return IsObject(g_ClickLock) && (g_ClickLock.src = inp || g_ClickLock.held = inp)
}

HookActive(hk) {
    inp := HkInput(hk)
    if (SubStr(hk, -3) = " Up")
        return UpClaimed(hk, inp) ? 1 : 0
    ; pass-through: truly native -- except an input already held with a
    ; live state, whose repeats and release must keep reaching the engine
    ; (else its release is claimed by UpOwned while repeats leak: stuck key)
    if (IsObject(g_Bypass) && BypassFor(b := HkInput(hk))
        && !((s := BS(b)) && s.down))
        return 0
    ours := false
    try ours := OwnWindowAt(RM_WinAt())
    if !ours
        return GateNative(inp) ? 0 : 1
    ; A TILT is never gated: nothing of ours scrolls sideways, and a tilt
    ; bound to a monitor hop must hop wherever the pointer is. OnWheelHK
    ; already exempted tilts from its own-window test, but this gate runs
    ; FIRST and passed the tilt straight to the window underneath -- so a
    ; window of ours sitting over the PACS series list (an overlay, a
    ; toast) turned the teleport into a sideways scroll of the list.
    if InStr(hk, "WheelLeft") || InStr(hk, "WheelRight") {
        TiltNote("gate", WinClassOf(RM_WinAt()))
        return 1
    }
    return 0
}

; Diagnostics for a bound tilt that did NOT do its job, once per reason and
; window class per session, so a copy of the list says where it went.
TiltNote(why, cls) {
    static seen := Map()
    k := why "|" cls
    if seen.Has(k)
        return
    seen[k] := 1
    if (why = "gate")
        Problem("tilt", "tilt over a RadMapper window (" cls ") -- now kept"
            . " on its binding instead of passing through")
    else
        Problem("tilt", "tilt passed through natively over " cls
            . " -- no tilt row applies in " (why = "" ? "this program" : why))
}

; HotIf gate for the engine's KEYBOARD hooks (v0.3 fix). The mouse gate above
; is POSITIONAL -- a click belongs to whatever window sits under the cursor --
; but a keystroke belongs to the FOREGROUND window, wherever the pointer
; happens to rest. Registering key hooks under HookActive (v0.2) meant every
; key remap silently stopped working while the pointer was parked over the
; RadMapper window, and typing into our own edit fields was only native by
; accident of where the mouse was. Ours-by-foreground is the correct test:
; it keeps our own Edit controls native and leaves the keys live everywhere
; else. Defaults to 1 (engine active) on any error, like HookActive.
KbHookActive(hk) {
    inp := HkInput(hk)
    if (SubStr(hk, -3) = " Up")
        return UpClaimed(hk, inp) ? 1 : 0
    ; pass-through: truly native -- except an input already held with a
    ; live state, whose repeats and release must keep reaching the engine
    ; (else its release is claimed by UpOwned while repeats leak: stuck key)
    if (IsObject(g_Bypass) && BypassFor(b := HkInput(hk))
        && !((s := BS(b)) && s.down))
        return 0
    try return (OwnGuiActive() || GateNative(inp)) ? 0 : 1
    return 1
}

OnPressHK(btn, *) {
    Critical "On"
    TestNotify(btn, 1)
    ; v0.6.2: while the keyboard pointer is up it owns every key. A bound key
    ; row is a hooked "*key" hotkey and would beat its InputHook to the key,
    ; so the row is bypassed here and the key handed over (and suppressed).
    if (Warp.active && IsKeyInput(btn)) {
        Warp.FromHook(btn)
        return
    }
    ; A real mouse press while the keyboard pointer is up: the pointer stands
    ; down (Close drops a held drag and frees the keyboard) and the press
    ; fires nothing. Running the row instead could open a radial menu or the
    ; chooser UNDER an InputHook that swallows its cancel key -- the mirror
    ; of the refusal in Warp.Open. Wheels are not clicks.
    if (Warp.active && IsMouseInput(btn) && !IsWheel(btn)) {
        Warp.Close(true)
        HUD("Keyboard pointer closed", "mute")
        prev := BS(btn)
        if prev {
            if (prev.down && !prev.consumed) {
                if (prev.mode = "passthru")
                    SendNativeUp(prev.passBtn != "" ? prev.passBtn : btn)
                else if (prev.mode = "held")
                    ActionUp(prev.holdBinding, prev)
            }
            ClearBS(btn)
        }
        st := NewBS(btn)
        st.down := true
        st.consumed := true
        st.pressTick := A_TickCount
        return
    }
    ; A reinjected click can never change which window is the foreground one
    ; (Windows' foreground lock), so the engine must manage activation itself
    ; around its own windows. Ours-ness is POSITIONAL (window under the
    ; cursor, by process identity via OwnWindowAt), not foreground-based:
    ; v0.9.2-0.9.4 keyed "ours" off the g_OurHwnds registry, which missed the
    ; DropDownList popup (ComboLBox) -- the handoff then ACTIVATED the popup,
    ; closing the list so the click fell through onto controls beneath it
    ; (lost selections / phantom clicks), and clicks returning to an inactive
    ; RadMouse window never activated it (title-bar close/minimize dead).
    isKey := IsKeyInput(btn)
    ; The key that toggled pause is still held: these are its OS repeats,
    ; not new presses. Without this a held pause key flipped the engine on
    ; and off every ~30 ms.
    if (isKey && g_SwallowUp.Has(btn) && InputHeldPhysical(btn))
        return
    if g_SwallowUp.Has(btn)                  ; a fresh mouse press: any old
        g_SwallowUp.Delete(btn)              ; claim on its release is stale
    ; an OS key repeat of a press already in hand: the absorber further down
    ; handles it, whatever pass-through says (else CapsLock toggled at the
    ; repeat rate while held)
    prevSt := isKey ? BS(btn) : 0
    rep := isKey && prevSt && prevSt.down && !prevSt.consumed
        && InputHeldPhysical(btn)
    fgOurs := OwnGuiActive()
    ; POSITIONAL ours-ness is a MOUSE question only: a keystroke goes to the
    ; foreground window, so for keys the cursor's location is irrelevant (and
    ; using it made key remaps die whenever the pointer rested on our GUI).
    uw := (g_Enabled && !isKey) ? RM_WinAt() : 0
    ours := (uw != 0) && OwnWindowAt(uw)
    if (ours)                                ; HotIf should have kept this native;
        Problem("hookmiss", "hooked click over our own window ("
            . WinClassOf(uw) ") -- HotIf gate missed it")   ; if we got here it didn't
    ; Paused: the one thing a hooked input can still do is resume.
    if (!g_Enabled && PauseTglRowFor(btn)) {
        ClearBS(btn)
        st := NewBS(btn)
        st.down := true
        st.consumed := true
        st.pressTick := A_TickCount
        g_SwallowUp[btn] := 1
        SetTimer(ToggleEnabled, -1)
        return
    }
    ; Our window in front but the click aims at a FOREIGN window: hand that
    ; window the foreground and resolve normally -- a bound thumb button
    ; over PowerScribe must not go native just because Settings was last
    ; focused.
    if (g_Enabled && fgOurs && !ours && uw && !isKey) {
        try WinActivate("ahk_id " uw)
        fgOurs := false
    }
    if (!g_Enabled || fgOurs || ours || (BypassFor(btn) && !rep)) {
        if (ours && !fgOurs) {
            ; fallback: click on our own window while another app holds the
            ; foreground -- activate ourselves so the reinjected click lands
            try WinActivate("ahk_id " uw)
        } else if (fgOurs && !ours && uw) {
            ; our GUI holds the foreground and the click aims at a FOREIGN
            ; window -- hand it the foreground before reinjecting. Logged so a
            ; workstation Diagnostics copy shows whether this path fires and
            ; what it activates (the "still need Alt-Tab" report lives here).
            try WinActivate("ahk_id " uw)
            Problem("focus", "GUI was foreground; handed focus to " WinClassOf(uw))
        }
        ; A live state here owns a synthetic hold that NOTHING will ever
        ; release: from this press on the input goes native, so the state
        ; machine never sees its release. A bare ClearBS orphaned it -- a
        ; moddrag left LButton down over the image, a sniper left the pointer
        ; slowed, until the watchdog or panic caught it. Release exactly as
        ; the stale-state path below does, THEN clear, THEN go native.
        prev := BS(btn)
        if prev {
            if (prev.down && !prev.consumed) {
                if (prev.mode = "passthru")
                    SendNativeUp(prev.passBtn != "" ? prev.passBtn : btn)
                else if (prev.mode = "held")
                    ActionUp(prev.holdBinding, prev)
            }
            ClearBS(btn)
        }
        SendNativeDown(btn)
        st := NewBS(btn)
        st.down := true
        st.mode := "passthru"
        st.passBtn := btn
        st.pressTick := A_TickCount          ; watchdog age guard needs this
        return
    }
    now := A_TickCount

    ; --- click lock (v0.3.1) --------------------------------------------------
    ; While a button is latched, pressing it (or the input that latched it)
    ; RELEASES the latch and does nothing else -- the Windows ClickLock rule,
    ; and the escape hatch that means a latch can always be undone with the
    ; mouse alone. The state is left down+consumed so the matching physical
    ; release is inert.
    if ClickLockOwns(btn) {
        ClickLockRelease()
        old := BS(btn)
        if old {
            ; same orphan as the not-ours branch above: this press consumes
            ; the input, so the old state's release never arrives
            if (old.down && !old.consumed) {
                if (old.mode = "passthru")
                    SendNativeUp(old.passBtn != "" ? old.passBtn : btn)
                else if (old.mode = "held")
                    ActionUp(old.holdBinding, old)
            }
            ClearBS(btn)
        }
        st := NewBS(btn)
        st.down := true
        st.consumed := true
        st.pressTick := now
        return
    }

    prev := BS(btn)

    ; --- OS keyboard auto-repeat (v0.3) -------------------------------------
    ; Holding a KEY makes Windows resend key-down every ~30 ms with no Up in
    ; between. v0.2 read each repeat as a fresh press whose Up had been lost:
    ; it tore down the live state (releasing a hold mid-hold, logging phantom
    ; "recovered" problems) and rebuilt it, so a held key bounced between
    ; engaging and releasing its hold action instead of holding it. Repeats
    ; are now absorbed: a native passthrough re-sends its down, a REPEAT-SAFE
    ; tap action re-fires at repeatRate (a held key SHOULD repeat, as the
    ; physical key does -- but only for actions that mean the same thing
    ; twice; see RepeatSafeAct), and any in-flight state -- pending, held,
    ; armedmod -- is simply left alone.
    if (isKey && prev && prev.down && !prev.consumed
        && InputHeldPhysical(btn)) {
        if (prev.mode = "fired" && IsObject(prev.spec)
            && IsObject(prev.spec.tap)
            && RepeatSafeAct(prev.spec.tap["action"]["type"])) {
            ; Only a REPEAT-SAFE action re-fires, and never at the OS repeat
            ; rate. Windows resends key-down every ~30 ms, so v0.3 toggled
            ; dictation, opened a radial menu or launched a program dozens of
            ; times for one held key -- the action ran per repeat, not per
            ; press. repStart is the wall clock of the last re-fire, gated by
            ; the same repeatRate the keysrepeat hold uses (it is free here:
            ; a "fired" state never runs the keysrepeat timer that owns it).
            gap := RepeatMs()
            since := now - prev.repStart
            if (prev.repStart = 0 || since < 0 || since >= gap) {
                prev.repStart := now
                ActionFire(prev.spec.tap, prev)
            }
        } else if (prev.mode = "passthru"
            && IsKeyInput(prev.passBtn != "" ? prev.passBtn : btn))
            ; Only a KEY target repeats its down. A key remapped to a MOUSE
            ; button re-sent {LButton Down} every ~30 ms with no Up: Windows
            ; read double-clicks and every drag restarted.
            SendNativeDown(prev.passBtn != "" ? prev.passBtn : btn)
        return
    }

    if prev {
        ; A still-down prev here means the Up event was LOST (hook drop,
        ; modal, focus theft) and the user re-pressed: release whatever the
        ; old state holds before starting fresh, or a synthetic down leaks.
        if (prev.down && !prev.consumed) {
            if (prev.mode = "passthru")
                SendNativeUp(prev.passBtn != "" ? prev.passBtn : btn)
            else if (prev.mode = "held")
                ActionUp(prev.holdBinding, prev)
            Problem("recovered", "re-press of " btn " released its stuck "
                . prev.mode " state")
        }
        ClearBS(btn)                       ; stale state, start fresh
    }

    ctx := CurCtx(btn)
    spec := SpecFor(btn, ctx)
    st := NewBS(btn)
    st.down := true
    st.pressTick := now
    st.ctx := ctx
    st.spec := spec
    ; Pressing an input whose row lives in a layer IS using that layer: mark
    ; the holder now, not when the row fires, so releasing the host first
    ; (ordinary rollover) cannot also fire the host's own tap. A no-op for
    ; Base rows.
    ; Only the TAP: a layer hold row may never engage (released early, the
    ; tap may resolve to Base), and ActionDown/ActionFire mark it when it does.
    if IsObject(spec.tap)
        MarkLayerUsed(spec.tap)
    RM_GetPos(&sx, &sy)
    st.sx := sx
    st.sy := sy
    ; Did this press read as PHYSICAL? A button a mouse driver synthesises
    ; (a software middle click, a remapped thumb button) arrives injected,
    ; and AutoHotkey never marks an injected press as physically held. The
    ; watchdog and the auto-repeat both ask "still physically down?", and
    ; for such a button the honest answer is "no idea": they must not sweep
    ; it on that reading (v0.6.6.2).
    st.physSeen := InputHeldPhysical(btn)
    ; Pressed while the wheel was still turning? Then this host's wheel
    ; rows (a deck) stay out of the way until the wheel has been still for
    ; deckSettleMs -- OnWheelHK clears the lock (v0.7).
    if spec.layerHost {
        gap := now - g_WheelLast
        if (gap >= 0 && gap < DeckSettleMs())
            st.deckLocked := true
    }

    if spec.pure {
        ; a pure row can be LAYER-SCOPED (a native escape-hatch inside a
        ; layer): its native passthrough IS the layer being used, so its
        ; holder(s) must go silent. Passthru bypasses ActionFire's mark,
        ; so mark here (tracer-caught double-fire, v1.0.1). Base rows have
        ; no layer parts and this is a no-op.
        if IsObject(spec.tap)
            MarkLayerUsed(spec.tap)
        st.mode := "passthru"
        st.passBtn := btn
        SendNativeDown(btn)
        return
    }
    if (spec.remap != "") {
        ; Behave exactly like the target input: its down goes out now, its up
        ; goes out when this input is physically released (OnReleaseHK's
        ; passthru path, via passBtn). Drag, hold and double-click all work
        ; because the target sees the real press duration.
        if IsObject(spec.tap)
            MarkLayerUsed(spec.tap)
        st.mode := "passthru"
        st.passBtn := spec.remap
        if (IsKeyInput(spec.remap) && !AimFg(spec.tap, ctx)) {
            st.consumed := true              ; nothing went out: release inert
            return
        }
        SendNativeDown(spec.remap)
        LastEvent(btn " -> " InputLabel(spec.remap), spec.tap)
        return
    }
    if spec.instantTap {
        st.mode := "fired"
        ActionFire(spec.tap, st)
        LastEvent(btn " tap", spec.tap)
        return
    }
    if spec.instantHold {
        st.mode := "held"
        st.holdBinding := spec.hold
        ActionDown(spec.hold, st, true)
        LastEvent(btn " hold", spec.hold)
        StartPollIfNeeded(st)
        return
    }
    st.mode := "pending"
    ; (Until v0.7 the left button could host a layer and a drag watch let a
    ; real left-drag through natively. Left, right and middle no longer host
    ; one -- LayerHostAllowed -- so a pending press here is a thumb button or
    ; a key, and there is nothing to watch for.)
    ArmTimers(st)
}

; The hold threshold, CLAMPED to the same range the Settings page enforces
; (50-2000 ms). A hand-edited config -- or a JSON number that arrived as 0 --
; used to reach SetTimer as `-0`, which in AHK means "run this timer
; repeatedly, as fast as it can", so the hold timer fired continuously and the
; button engaged its hold before the hand had moved. Every timing read of the
; setting goes through here; the GUI keeps its own ClampInt on the way IN,
; this is the guard on the way OUT.
HoldMs() {
    return ClampInt(Cfg("holdThreshold"), 50, 2000, 200)
}

; repeatRate reaches SetTimer: 0 deletes the timer, a string throws in the
; Critical hook thread. Clamped like the hold threshold.
RepeatMs() {
    return ClampInt(Cfg("repeatRate"), 10, 1000, 50)
}

ArmTimers(st) {
    st.gen += 1
    SetTimer(HoldTimer.Bind(st, st.gen), -HoldMs())
    StartPollIfNeeded(st)
}

StartPollIfNeeded(st) {
    ; left/right/middle withheld for a hold or as a layer host: watch for a
    ; drag, which must reach the app (W/L, pan) rather than be swallowed
    needs := IsPrimaryButton(st.btn) && st.mode = "pending"
    if (IsObject(st.spec.hold) && st.spec.hold["action"]["type"] = "dragmove")
        needs := true
    if (!needs && IsObject(st.holdBinding)
        && st.holdBinding["action"]["type"] = "dragmove")
        needs := true
    if (needs && !st.polling) {
        st.polling := true
        SetTimer(MovePoll.Bind(st.btn, st.pollId), 15)
    }
}

; Tap actions that are safe to RE-FIRE on an OS keyboard auto-repeat: the
; physical key would produce the same output again, and repeating that output
; is what the user asked for by holding the key. Names are ACT_CODES entries.
; Everything absent is a ONE-SHOT and must fire once per PRESS: ps_* and
; pacs_keys queue a focus dance, macro/run/guiopen/layout/winplace/warp
; open or launch something, tele_* teleports the pointer, and the toggles
; (clicklock, bypass, pausetgl) would flip on and off at 30 Hz.
RepeatSafeAct(t) {
    return (t = "keys" || t = "keysrepeat" || t = "text" || t = "native"
        || t = "stock")
}

; Hold-action types that ENGAGE state in ActionDown (ended by ActionUp)
; rather than firing one-shot -- exactly ActionDown's special cases. These
; must never be deferred to a release-time ActionFire: bypass would toggle
; instead of holding, dragmove would mint a click that never happened, and
; native/moddrag/keysrepeat would lose their hold phase.
StatefulHoldType(t) {
    return (t = "native" || t = "stock" || t = "moddrag" || t = "keysrepeat"
        || t = "dragmove" || t = "bypass")
}

HoldTimer(st, gen, *) {
    Critical "On"
    ; identity check (BS(btn) != st) kills timers from a previous, cleared
    ; press cycle whose gen counter happens to collide with this one
    if (!IsObject(st) || BS(st.btn) != st || st.gen != gen || !st.down
        || st.consumed || st.mode != "pending")
        return
    spec := st.spec
    btn := st.btn
    b := spec.hold
    ; A layer-host DEFERS a ONE-SHOT hold to release: holding it ARMS its
    ; layer, and the hold fires only if the layer went unused (OnReleaseHK
    ; armedmod -- the QMK mod-tap rule). STATEFUL hold types still engage at
    ; the threshold exactly as pre-v1.0: they are continuous and reversible,
    ; they coexist with layer use (a held-mode button stays in ctx.held, so
    ; layer rows keep resolving), and firing their one-shot form at release
    ; would TOGGLE sniper/boost on with no held anchor -- stuck
    ; state the watchdog deliberately never clears (tracer-caught, v1.0.1).
    ; Either way the holder stays down + unconsumed, so it keeps arming the
    ; layer; a drag-eligible LButton still drags via MovePoll from armedmod.
    if (IsObject(b) && spec.layerHost && !StatefulHoldType(b["action"]["type"])) {
        st.mode := "armedmod"
        return
    }
    ; A STATEFUL hold on a host whose layer was ALREADY used by a nested
    ; press (thumb held, other thumb tapped inside the threshold) must not
    ; then open a menu or start a drag on top of the chord that just fired:
    ; armedmod, where the release keeps a used host silent (v0.7).
    if (IsObject(b) && spec.layerHost && st.usedAsMod) {
        st.mode := "armedmod"
        return
    }
    if IsObject(b) {
        st.mode := "held"
        st.holdBinding := b
        ActionDown(b, st, false)
        LastEvent(btn " hold", b)
        StartPollIfNeeded(st)
        return
    }
    if spec.layerHost {
        st.mode := "armedmod"
        return
    }
    ; no hold binding: if tap is a native remap, start a late native drag
    if (IsObject(spec.tap) && IsNativeAct(spec.tap["action"]["type"])) {
        v := MGet(spec.tap["action"], "value", "")
        MarkLayerUsed(spec.tap)              ; a layer-scoped native remap is
        st.mode := "passthru"                ; the layer being used: holders
        st.passBtn := (v != "") ? v : btn    ; go silent (bypasses ActionFire)
        SendNativeDown(st.passBtn)
        return
    }
    ; no tap binding either (a layer host with no tap row of its own):
    ; fall back to a late native down so a real drag is never swallowed
    if !IsObject(spec.tap) {
        st.mode := "passthru"
        st.passBtn := btn
        SendNativeDown(btn)
        return
    }
    st.mode := "armedmod"                    ; tap-bound: fires on release
}

MovePoll(btn, pollId, *) {
    Critical "On"
    st := BS(btn)
    if (!st || st.pollId != pollId || !st.down || st.consumed) {
        if (st && st.pollId = pollId)
            st.polling := false
        SetTimer(, 0)
        return
    }
    RM_GetPos(&cx, &cy)
    dx := cx - st.sx
    dy := cy - st.sy
    dist := Sqrt(dx * dx + dy * dy)

    if ((st.mode = "pending" || st.mode = "armedmod") && IsPrimaryButton(btn)) {
        if (!st.usedAsMod && dist >= Cfg("dragThreshold")) {
            st.gen += 1                      ; the hold timer stands down
            st.mode := "passthru"            ; ...and the button goes out:
            ; a drag is a drag -- of the dragmove TARGET if the hold is one
            ; (right-drag -> middle-drag pan), else of the button itself
            hv := (IsObject(st.spec) && IsObject(st.spec.hold)
                && st.spec.hold["action"]["type"] = "dragmove")
                ? MGet(st.spec.hold["action"], "value", "") : ""
            st.passBtn := (hv != "") ? hv : btn
            ; a host that became a plain drag no longer holds its layer
            ; (safe: SpecFor builds a fresh spec per press -- never cache it)
            if IsObject(st.spec)
                st.spec.layerHost := false
            SendNativeDown(st.passBtn)
            st.polling := false
            SetTimer(, 0)
        }
        return
    }
    if !(st.mode = "held" && IsObject(st.holdBinding)
        && st.holdBinding["action"]["type"] = "dragmove") {
        if (st.mode = "pending" && IsObject(st.spec) && IsObject(st.spec.hold)
            && st.spec.hold["action"]["type"] = "dragmove")
            return                           ; its hold has not engaged yet
        st.polling := false                  ; nothing left to decide
        SetTimer(, 0)
        return
    }
    if (!st.dragOn && dist >= Cfg("dragThreshold")) {
        st.dragOn := true
        v := MGet(st.holdBinding["action"], "value", "")
        st.passBtn := (v != "") ? v : btn
        SendNativeDown(st.passBtn)
        st.polling := false                  ; the drag is out: nothing left
        SetTimer(, 0)                        ; for this poll to decide
    }
}

OnReleaseHK(btn, *) {
    Critical "On"
    TestNotify(btn, 0)
    if g_SwallowUp.Has(btn) {                ; the release of a pause toggle
        g_SwallowUp.Delete(btn)
        ClearBS(btn)
        return
    }
    ; A key whose PRESS was handed to the keyboard pointer must not emit a
    ; native Up here -- and "is Warp still up?" is the wrong test for that.
    ; The press that CLOSES the overlay (Esc, Space, R/M/F, V) sets
    ; Warp.active false before its own release arrives, so that Up fell
    ; through to the safety SendNativeUp below and a phantom keystroke landed
    ; in whatever the click had just activated. Warp records what it claimed;
    ; the claim is consumed here, whatever Warp is doing now.
    if Warp.claimed.Has(btn) {
        Warp.claimed.Delete(btn)
        return
    }
    st := BS(btn)
    if (Warp.active && IsKeyInput(btn) && !st)
        return                               ; press went to the keyboard pointer
    if (!st && ClickLockHolds(btn))
        return                               ; the latch's own release: keep it down
    if (!st || !st.down) {
        SendNativeUp(btn)                    ; safety: never leave one stuck
        if st
            ClearBS(btn)
        return
    }
    st.down := false
    st.gen += 1                              ; cancels pending one-shot timers

    if st.consumed {                         ; nothing owns a consumed state
        ClearBS(btn)                         ; any more; just drop it
        return
    }
    mode := st.mode
    if (mode = "passthru") {
        if st.locked {                       ; click-locked: the button stays
            ClearBS(btn)                     ; down until the latch is released
            return
        }
        SendNativeUp(st.passBtn != "" ? st.passBtn : btn)
        ClearBS(btn)
        return
    }
    if (mode = "held") {
        ; A "native drag after move" hold engaged at PRESS (instantHold) on an
        ; input whose tap is native: a quick click used to do nothing at all
        ; (Back, the right-click menu lost). Released before the hold time
        ; with nothing dragged, it is a click. Only dragmove: moddrag's own
        ; tap already clicks, and sniper/boost/drag scroll TOGGLE on a tap.
        t := IsObject(st.holdBinding) ? st.holdBinding["action"]["type"] : ""
        quick := IsObject(st.spec) && st.spec.instantHold && (t = "dragmove")
            && !st.dragOn && (A_TickCount - st.pressTick < HoldMs())
        ActionUp(st.holdBinding, st)
        if quick
            FireTap(st)
        ClearBS(btn)
        return
    }
    if (mode = "armedmod") {
        ; A layer-host held past the threshold and now released. If its layer
        ; went UNUSED, its own action fires as a one-shot: the hold if it has
        ; one, else its tap (the seeded native tap makes an unused holder
        ; still click -- S31/S43). If the layer was used (usedAsMod), the
        ; holder stays silent. b here is ONE-SHOT by construction: HoldTimer
        ; only defers a hold to armedmod when !StatefulHoldType (stateful
        ; holds engaged at threshold in held mode instead), so ActionFire's
        ; instant form is always the right delivery and can never toggle
        ; stateful state on (v1.0.1).
        if !st.usedAsMod {
            b := st.spec.hold
            if IsObject(b) {
                ActionFire(b, st)
                LastEvent(st.btn " hold", b)
            } else if (IsObject(st.spec.tap) && !IsKeyInput(st.btn))
                FireTap(st)                  ; no tap row: an unused host
                                             ; stays silent, as before. A
                                             ; KEY host (CapsLock) is silent
                                             ; too: a long press on it is a
                                             ; layer gesture, and firing its
                                             ; tap (dictation) on release
                                             ; would surprise
        }
        ClearBS(btn)
        return
    }
    if (mode = "pending") {
        ; Released before the hold threshold: a tap. (A holder consumed as
        ; a modifier by a nested input stays silent.)
        if !st.usedAsMod
            FireTap(st)
        ClearBS(btn)
        return
    }
    ClearBS(btn)                             ; "fired" and anything else
}

; The tap of a press that was WITHHELD (pending or armedmod): its tap row if
; it has one, else one native click of the button itself -- the press never
; went out, so this is the first the application hears of it.
FireTap(st) {
    b := st.spec.tap
    if IsObject(b) {
        MarkLayerUsed(b)                     ; a layer-scoped row was used:
        ActionFire(b, st)                    ; its holders go silent (v1.0.1)
        LastEvent(st.btn " tap", b)
    } else
        SendNativeClick(st.btn, 1)
}

; --- wheel -------------------------------------------------------------------

; Tick of the last ACCEPTED notch, per wheel input. Not part of the config:
; it is live state, like g_BS.
global g_WheelAt := Map()
; Tick of the last notch of ANY wheel input, accepted or not, native or not:
; "is the wheel still turning?" for the deck settle rule (v0.7).
global g_WheelLast := 0

DeckSettleMs() {
    return ClampInt(Cfg("deckSettleMs"), 0, 1000, 250)
}

/**
 * Should this notch be acted on? (v0.6.5)
 *
 * PURE apart from the map it is handed -- no config, no clock, no hook --
 * so tests/regression.ahk can drive it with a fake clock. `lastMap` is
 * input -> tick of the last accepted notch, and an ACCEPTED notch is the
 * one that restarts the window: holding a Razer wheel over keeps sending
 * notches every 30-50 ms, and every one of them must be measured against
 * the press that was let through, not against the notch before it.
 *
 * A negative gap means A_TickCount has wrapped (49.7 days); accept, so a
 * wrap costs nothing worse than one extra press.
 */
WheelAccept(input, now, lastMap, limitMs) {
    if (limitMs <= 0)
        return true
    if lastMap.Has(input) {
        gap := now - lastMap[input]
        if (gap >= 0 && gap < limitMs)
            return false
    }
    lastMap[input] := now
    return true
}

/** The guard that applies to one wheel input, clamped as stored. */
WheelLimitMs(wh) {
    tilt := (wh = "WheelLeft" || wh = "WheelRight")
    key := tilt ? "tiltRepeatMs" : "wheelRepeatMs"
    return ClampInt(Cfg(key), 0, 1000, DEFAULTS[key])
}

OnWheelHK(wh, *) {
    global g_WheelLast
    Critical "On"
    TestNotify(wh, 2)
    now := A_TickCount
    sinceLast := now - g_WheelLast           ; before THIS notch is counted
    g_WheelLast := now
    ; positional ours-check as in OnPressHK: scrolling over our own (possibly
    ; inactive) windows must stay native, never resolve through app profiles
    ; A TILT (WheelLeft / WheelRight) is exempt from the own-window test:
    ; nothing of ours scrolls sideways, and a tilt bound to a monitor hop
    ; lands the pointer in the middle of the next monitor -- under the
    ; settings window whenever it is open there (v0.6.6.3).
    tilt := (wh = "WheelLeft" || wh = "WheelRight")
    if (!g_Enabled || IsObject(g_Bypass) || (!tilt && OwnWindowAt(RM_WinAt()))) {
        SendWheelRaw(wh, 1)                  ; our own lists scroll natively
        return
    }
    ; Settings in front, pointer over PACS: a bound row's keys go to the
    ; FOREGROUND, so give it to the window being scrolled first (as a press
    ; does), or {Down} lands in a RadMapper list.
    if (!tilt && OwnGuiActive()) {
        uw := RM_WinAt()
        if uw
            try WinActivate("ahk_id " uw)
    }
    ; no turn binding exists for this wheel in ANY context -> nothing to
    ; resolve (v0.3: a wheel is only ever hooked when a row references it,
    ; so this is a belt-and-braces guard, not a hot path)
    if !g_Idx.bind.Has(wh "|turn") {
        SendWheelRaw(wh, 1)
        return
    }
    ctx := CurCtx(wh)
    b := FindBindingFor(wh, "turn", ctx)
    if IsObject(b) {
        if (IsNativeAct(b["action"]["type"])) {
            ; A native row on a wheel means "scroll normally" -- it must NOT
            ; go through ActionFire, whose native case is a BUTTON click with
            ; an LButton fallback (st is 0 for Base rows, the HOLDER for
            ; layered rows). With the default base native wheel rows plus any
            ; layered wheel row (which hooks the wheel), every plain scroll
            ; fired a synthetic LEFT CLICK into the app under the cursor
            ; (workstation E1-2: text selected in the report editor instead
            ; of scrolling). Send the notch itself, and still mark the lay
            ; used so a layered native scroll silences its holder (S50
            ; semantics). An explicit BUTTON value keeps the old click
            ; meaning; a wheel value redirects the notch.
            MarkLayerUsed(b)
            tgt := MGet(b["action"], "value", "")
            if (tgt != "" && !IsWheel(tgt)) {
                ; a held tilt repeats: one click per guard window, not a burst
                if !WheelAccept(wh, now, g_WheelAt, WheelLimitMs(wh))
                    return
                SendNativeClick(tgt)
            } else
                SendWheelRaw(tgt != "" ? tgt : wh, 1)
        } else {
            ; A BOUND wheel direction is rate-limited (v0.6.5). A tilt wheel
            ; repeats while it is held over, so without this one tilt fires
            ; the action four or five times. Dropped outright, not re-sent:
            ; this notch belongs to an action, and passing it through would
            ; scroll the study instead.
            holder := LayerHolderSt(b)       ; deepest held holder (0 at Base)
            ; WHEEL DECK SETTLE (v0.7). The holder was pressed while the
            ; wheel was still turning -- scrolling a stack, thumb lands on
            ; the deck button before the wheel has stopped. Every notch of
            ; that same motion stays NATIVE; the deck only takes over once
            ; the wheel has been still for deckSettleMs. So a key that is
            ; also a deck never turns the tail of a scroll into a command.
            if (IsObject(holder) && holder.deckLocked) {
                if (sinceLast >= 0 && sinceLast < DeckSettleMs()) {
                    holder.usedAsMod := true ; scrolling with it held is not a tap
                    SendWheelRaw(wh, 1)
                    LastEvent(wh " native — still turning when "
                        . InputLabel(holder.btn) " was pressed")
                    return
                }
                holder.deckLocked := false   ; the wheel stopped: deck is live
            }
            if !WheelAccept(wh, now, g_WheelAt, WheelLimitMs(wh)) {
                LastEvent(wh " ignored — within the "
                    . (tilt ? "tilt" : "wheel") " guard (" WheelLimitMs(wh) " ms)")
                return
            }
            ActionFire(b, holder, ctx)       ; marks every lay holder used; ctx
                                             ; is the WHEEL's, not the holder's
        }
        lay := MGet(b, "layer", "*")
        LastEvent(wh (LayerParts(b).Length ? " (layer " lay ")" : ""), b)
        return
    }
    if tilt
        TiltNote(ctx.app, WinClassOf(RM_WinAt()))
    SendWheelRaw(wh, 1)
}

; Whole-notch output -- the only wheel output path in v0.3 (the free-spin
; engine that sat between this and the hook is gone).
SendWheelRaw(wh, n) {
    if (n < 1)
        n := 1
    ; SendInput, not the script-wide Event mode, and only here.
    ;
    ; Every physical notch on a hooked wheel is suppressed and re-emitted by
    ; this line. In Event mode that re-emission is one mouse_event per notch
    ; issued from a Critical hotkey thread, so at trackball speed the notches
    ; reach the application later than they were made and with the gaps
    ; between them stretched -- and both PACS and browsers accelerate
    ; scrolling from exactly those gaps. That is what "normal scrolling gets
    ; weird if I scroll fast" is: not lost input, but re-timed input.
    ;
    ; SendInput delivers atomically and is not subject to the send delays.
    ; It removes AutoHotkey's own hook for the duration, which for a
    ; passthrough is what we want anyway: the notch we are re-emitting must
    ; not come back through our own wheel hotkey.
    try {
        SendInput("{Blind}{" wh " " Round(n) "}")
        return
    }
    RM_Send("{Blind}{" wh " " Round(n) "}")   ; rig/testing fallback
}

; ── §6  ACTION EXECUTOR ─────────────────────────────────────────────────────

DescribeAction(a) {
    t := MGet(a, "type", "none")
    v := MGet(a, "value", "")
    ; input-valued actions are STORED as codes ("RButton") but every other
    ; column shows labels ("Right Button"), so show the label here too
    if ((t = "native" || t = "dblclick" || t = "dragmove"
        || t = "clicklock") && v != "")
        v := InputLabel(v)
    label := t
    for i, code in ACT_CODES {
        if (code = t) {
            label := ACT_LABELS[i]
            break
        }
    }
    return (v != "") ? label ": " v : label
}

; Hot paths only stash raw refs; the formatting (a 22-entry label scan plus
; string builds) happens lazily in LastEventText, sampled by StatusTick at
; 700 ms -- never per wheel notch.
LastEvent(what, binding := 0) {
    global g_LastEvWhat, g_LastEvBind, g_LastEvDirty
    g_LastEvWhat := what
    g_LastEvBind := binding
    g_LastEvDirty := true
}

LastEventText() {
    global g_LastEvDirty, g_LastEvText
    if g_LastEvDirty {
        g_LastEvDirty := false
        desc := IsObject(g_LastEvBind) ? DescribeAction(g_LastEvBind["action"]) : ""
        g_LastEvText := g_LastEvWhat (desc != "" ? "  ->  " desc : "")
    }
    return g_LastEvText
}

; ── CONFLICTS REPORT (v0.6.6.2) ──────────────────────────────────────────
;
; Every place a button's meaning changes, in plain words, so "why did that
; do something else in PACS" has one answer instead of eight pages. Pure
; over the config: nothing here reads the engine's live state.
;
; Returns an array of {kind, text}. kind is "warn" for something likely to
; surprise, "info" for something that is just worth knowing.

ConflictScope(row) {
    app := MGet(row, "app", "*")
    lay := MGet(row, "layer", "*")
    mods := MGet(row, "mods", "")
    out := (app = "*" || app = "") ? "everywhere" : ("in " AppDisp(app))
    if (lay != "*" && lay != "" && lay != "Base")
        out .= " while holding " LayerLabelFromCode(lay)
    if (mods != "")
        out .= " with " mods
    return out
}

ConflictReport(focus := "") {
    out := []
    rows := MGet(g_Cfg, "bindings", [])
    byBtn := Map()
    byBtn.CaseSense := "Off"
    for row in rows {
        b := MGet(row, "button", "")
        if (b = "" || (focus != "" && b != focus))
            continue
        if !byBtn.Has(b)
            byBtn[b] := []
        byBtn[b].Push(row)
    }
    for b, list in byBtn {
        lbl := InputLabel(b)
        ; 1. a program row that beats an everywhere row for the same gesture
        for r1 in list {
            if (MGet(r1, "app", "*") = "*")
                continue
            for r2 in list {
                if (MGet(r2, "app", "*") != "*")
                    continue
                if (MGet(r1, "event", "") != MGet(r2, "event", "")
                    || MGet(r1, "layer", "*") != MGet(r2, "layer", "*")
                    || MGet(r1, "mods", "") != MGet(r2, "mods", ""))
                    continue
                if (MGet(r1["action"], "type", "") = MGet(r2["action"], "type", "")
                    && MGet(r1["action"], "value", "") = MGet(r2["action"], "value", ""))
                    continue
                out.Push({kind: "info", text: "In " AppDisp(MGet(r1, "app", "*"))
                    . ", " lbl " " EventLabelOf(MGet(r1, "event", "")) " does "
                    . DescribeAction(r1["action"]) " instead of "
                    . DescribeAction(r2["action"])
                    . ((MGet(r1, "layer", "*") != "*") ? " (while holding "
                        LayerLabelFromCode(MGet(r1, "layer", "*")) ")" : "") "."})
            }
        }
        ; 1b. while a layer is held, a layer row (from anywhere) beats a
        ;     program's plain row for the same gesture (v0.6.6.6)
        for r1 in list {
            lay := MGet(r1, "layer", "*")
            if (lay = "*" || lay = "" || lay = "Base")
                continue
            for r2 in list {
                if (MGet(r2, "app", "*") = "*" || MGet(r2, "layer", "*") != "*"
                    || MGet(r1, "event", "") != MGet(r2, "event", "")
                    || MGet(r1, "mods", "") != MGet(r2, "mods", ""))
                    continue
                if (MGet(r1, "app", "*") != "*" && MGet(r1, "app", "*") != MGet(r2, "app", "*"))
                    continue
                out.Push({kind: "info", text: "In " AppDisp(MGet(r2, "app", "*"))
                    . " while holding " LayerLabelFromCode(lay) ", " lbl " "
                    . EventLabelOf(MGet(r1, "event", "")) " does "
                    . DescribeAction(r1["action"]) " (the layer row"
                    . (MGet(r1, "app", "*") = "*" ? ", from everywhere," : "")
                    . " beats " AppDisp(MGet(r2, "app", "*")) "'s plain row: "
                    . DescribeAction(r2["action"]) ")."})
            }
        }
        ; 2. two rows for exactly the same thing
        i := 1
        while (i <= list.Length) {
            j := i + 1
            while (j <= list.Length) {
                a := list[i], c := list[j]
                if (MGet(a, "app", "*") = MGet(c, "app", "*")
                    && MGet(a, "event", "") = MGet(c, "event", "")
                    && MGet(a, "layer", "*") = MGet(c, "layer", "*")
                    && MGet(a, "mods", "") = MGet(c, "mods", "")) {
                    out.Push({kind: "warn", text: "Two rows for " lbl " "
                        . EventLabelOf(MGet(a, "event", "")) " " ConflictScope(a)
                        . ": " DescribeAction(a["action"]) " and "
                        . DescribeAction(c["action"]) ". The later one wins; delete one."})
                }
                j += 1
            }
            i += 1
        }
        ; 3. a tap that waits: a hold on the same button in the same scope
        scopes := Map()
        for r in list {
            k := MGet(r, "app", "*") "|" MGet(r, "layer", "*") "|" MGet(r, "mods", "")
            if !scopes.Has(k)
                scopes[k] := {tap: 0, hold: 0, any: r}
            ev := MGet(r, "event", "")
            if scopes[k].HasProp(ev)
                scopes[k].%ev% := r
        }
        for k, sc in scopes {
            where := ConflictScope(sc.any)
            ; SpecFor's test, exactly: a native row is "the input being
            ; itself" only with no value or its own. A tap that REMAPS onto
            ; another input is withheld like any other tap.
            tapNative := !IsObject(sc.tap)
            if (!tapNative && IsNativeAct(sc.tap["action"]["type"])) {
                tv := MGet(sc.tap["action"], "value", "")
                tapNative := (tv = "" || tv = b)
            }
            if (IsObject(sc.hold) && !tapNative)
                out.Push({kind: "info", text: lbl " " where ": the tap fires on "
                    . "release (a hold is bound); holding past " HoldMs()
                    . " ms does " DescribeAction(sc.hold["action"]) "."})
            ; Left, right and middle only -- those are the clicks a delay is
            ; felt on -- and only when the press really WAITS. A native tap
            ; with a STATEFUL hold engages at press (SpecFor.instantHold),
            ; so nothing is withheld and the old line warned about a delay
            ; that does not exist.
            if (IsObject(sc.hold) && IsPrimaryButton(b)
                && !(tapNative && StatefulHoldType(sc.hold["action"]["type"])))
                out.Push({kind: "warn", text: lbl " " where ": the hold "
                    . "withholds the physical click for " HoldMs()
                    . " ms, so a drag starts late."})
        }
    }
    ; 4. layer hosts
    hosts := Map()
    hosts.CaseSense := "Off"
    for row in rows {
        for part in LayerParts(row) {
            if (focus != "" && part != focus && MGet(row, "button", "") != focus)
                continue
            if !hosts.Has(part)
                hosts[part] := []
            hosts[part].Push(row)
        }
    }
    for host, hrows in hosts {
        n := hrows.Length
        txt := InputLabel(host) " hosts a layer with " n " row" (n = 1 ? "" : "s")
            . ": "
        i := 0
        for r in hrows {
            i += 1
            if (i > 4) {
                txt .= "…"
                break
            }
            txt .= (i > 1 ? "; " : "") InputLabel(MGet(r, "button", "")) " → "
                . DescribeAction(r["action"])
        }
        out.Push({kind: "info", text: txt ". While held it is silent; its own "
            . "tap or hold fires on release only if nothing in the layer "
            . "was used."})
    }
    ; 6. the same PowerScribe / pointer action from several places
    ess := Map("ps_dictate", "Dictate", "ps_next", "Next field",
        "ps_prev", "Previous field", "tele_prev", "Pointer left",
        "tele_next", "Pointer right")
    for code, name in ess {
        list := []
        for row in rows {
            a := MGet(row, "action", 0)
            if (IsObject(a) && MGet(a, "type", "") = code
                && (focus = "" || MGet(row, "button", "") = focus))
                list.Push(InputLabel(MGet(row, "button", "")) " "
                    . StrLower(EventLabelOf(MGet(row, "event", ""))) " "
                    . ConflictScope(row))
        }
        if (list.Length > 1) {
            txt := ""
            for one in list
                txt .= (txt = "" ? "" : "; ") one
            out.Push({kind: "info", text: name " is fired by " list.Length
                . " rows: " txt "."})
        }
    }
    if (out.Length = 0)
        out.Push({kind: "info", text: focus = ""
            ? "No conflicts found: every row applies on its own."
            : "No conflicts found for " InputLabel(focus) "."})
    return out
}

ConflictReportText(focus := "") {
    txt := "RadMapper " RM_VERSION " conflicts"
        . (focus != "" ? " for " InputLabel(focus) : "") "`r`n`r`n"
    for one in ConflictReport(focus)
        txt .= (one.kind = "warn" ? "! " : "- ") one.text "`r`n"
    return txt
}

; When a layer-scoped row fires, every holder of its layer path forfeits its
; own output -- the hold was "spent" enabling this action (workstation finding:
; RMB-held + LMB-tap dictate also popped the RMB context menu on release,
; because only the wheel path marked the holder). Both the armedmod
; and pending release paths honor usedAsMod. For a nested (depth-2) row both
; the outer and inner holders are marked, so neither fires on release.
MarkLayerUsed(binding) {
    for part in LayerParts(binding) {
        hs := BS(part)
        if hs
            hs.usedAsMod := true
    }
}

; The deepest currently-held holder of a layer-scoped binding's path, or 0 --
; the state object a wheel turn passes to ActionFire (the window switcher
; hangs off it). Base rows have no holder and return 0.
LayerHolderSt(binding) {
    st := 0
    for part in LayerParts(binding) {
        hs := BS(part)
        if (hs && hs.down)
            st := hs
    }
    return st
}

; One-shot execution (taps, wheel turns).
ActionFire(binding, st, ctx := 0) {
    MarkLayerUsed(binding)
    a := binding["action"]
    if (FgDelivered(a) && !AimFg(binding, IsObject(ctx) ? ctx
        : (IsObject(st) && IsObject(st.ctx) ? st.ctx : 0)))
        return
    t := a["type"]
    v := MGet(a, "value", "")
    switch t {
        case "keys", "keysrepeat":
            SafeSend(v)
        case "text":
            RM_SendText(v)
        case "native", "stock":
            SendNativeClick(v != "" ? v : (IsObject(st) ? st.btn : "LButton"))
        case "dblclick":
            ; Two clicks with no delay between them (SetMouseDelay -1), which
            ; is always inside the system double-click time, so the target app
            ; sees one double-click rather than two singles. Blank defaults to
            ; LButton, not "this input": double-clicking a thumb button means
            ; nothing, and "make this button double-click" is the whole point.
            SendNativeClick(v != "" ? v : "LButton", 2)
        case "moddrag":
            SafeSend("{Blind}{" v " Down}{LButton Down}{LButton Up}{" v " Up}")
        case "dragmove":
            SendNativeClick(v != "" ? v : (IsObject(st) ? st.btn : "LButton"))
        case "ps_dictate":
            PSFire(Cfg("psDictateKey"))
        case "ps_next":
            PSFire("{Tab}")
        case "ps_prev":
            PSFire("+{Tab}")
        case "ps_keys":
            PSFire(v)
        case "pacs_keys":
            PACSFire(v)
        case "tele_prev":
            TeleportMonitor(-1)
        case "tele_next":
            TeleportMonitor(1)
        case "parkgo":
            ParkNow()
        case "teleport":                         ; pre-v0.3.4 value-driven form
            DoTeleport(v)
        case "clicklock":
            ClickLockToggle(v, st)
        case "appswitch":
            h := LayerHolderSt(binding)      ; the host's release commits
            AppSwitchStep(IsObject(h) ? h : st, v)
        case "layout":
            LayoutApply(v)
        case "winplace":
            WinPlace(v)
        case "warp":
            Warp.Toggle()
        case "macro":
            SetTimer(RunMacro.Bind(v), -1)
        case "run":
            try Run(v)
        case "guiopen":
            ShowMain()
        case "bypass":
            BypassToggle(IsObject(st) ? st.btn : "", LayerParts(binding))
        case "pausetgl":
            ; Pausing clears every state, so this press's release would find
            ; none and send a lone native Up (a Back click on button 4).
            ; Only while it is still down: a tap fired AT release has no
            ; release left to swallow, and would eat the next one.
            if (IsObject(st) && st.HasProp("btn") && st.down)
                g_SwallowUp[st.btn] := 1
            ToggleEnabled()
        case "none":
            return
    }
}

; Hold-phase activation. instant = engaged at press (hold-only binding), so
; keysrepeat delays its repeat by the hold threshold to mimic key autorepeat.
ActionDown(binding, st, instant) {
    MarkLayerUsed(binding)
    a := binding["action"]
    if (FgDelivered(a) && !AimFg(binding,
        IsObject(st) && IsObject(st.ctx) ? st.ctx : 0))
        return
    t := a["type"]
    v := MGet(a, "value", "")
    switch t {
        case "native", "stock":
            btn := v != "" ? v : (IsObject(st) ? st.btn : "LButton")
            if IsWheel(btn) {                ; a notch has no down/up: one
                SendWheelRaw(btn, 1)         ; notch when the hold engages
                return
            }
            if IsObject(st)
                st.passBtn := btn
            SendNativeDown(btn)
        case "moddrag":
            SafeSend("{Blind}{" v " Down}{LButton Down}")
        case "keysrepeat":
            SafeSend(v)
            if IsObject(st) {
                st.repStart := A_TickCount   ; wall-clock runaway cap anchor
                delay := instant ? HoldMs() : RepeatMs()
                SetTimer(RepeatKick.Bind(st, st.gen, v), -delay)
            }
        case "bypass":
            BypassOn(IsObject(st) ? st.btn : "", true, LayerParts(binding))
        case "dragmove":
            if IsObject(st)
                st.dragOn := false           ; MovePoll sends the real down
        default:
            ActionFire(binding, st)          ; instant action bound on hold
    }
}

ActionUp(binding, st) {
    if !IsObject(binding)
        return
    a := binding["action"]
    t := a["type"]
    v := MGet(a, "value", "")
    switch t {
        case "native", "stock":
            btn := ""
            if (IsObject(st) && st.passBtn != "")
                btn := st.passBtn
            else
                btn := v != "" ? v : (IsObject(st) ? st.btn : "LButton")
            if !IsWheel(btn)                 ; the notch went out on the down
                SendNativeUp(btn)
        case "moddrag":
            ; TWO sends, not one: Send parses the whole string before it emits
            ; anything, so a value that has become unusable since the hold
            ; began (a config edit mid-drag, a hand-edited row) would throw and
            ; take the LButton Up down with it -- a left button left latched
            ; over an image. The button release must never depend on the
            ; modifier name parsing.
            SafeSend("{Blind}{LButton Up}")
            SafeSend("{Blind}{" v " Up}")
        case "keysrepeat":
            return                           ; repeat timer self-cancels
        case "bypass":
            if (IsObject(g_Bypass) && g_Bypass.mom)
                BypassOff()
        case "dragmove":
            if (IsObject(st) && st.dragOn)
                SendNativeUp(st.passBtn != "" ? st.passBtn : st.btn)
    }
}

RepeatKick(st, gen, v, *) {
    Critical "On"
    if (!IsObject(st) || BS(st.btn) != st || st.gen != gen || !st.down
        || st.mode != "held")
        return
    SetTimer(RepeatTick.Bind(st, gen, v), RepeatMs())
}

RepeatTick(st, gen, v, *) {
    Critical "On"
    ; InputHeldPhysical, not RM_KeyHeld: a numpad key reads as up under its
    ; own name when NumLock is off, which would kill the repeat instantly.
    if (!IsObject(st) || BS(st.btn) != st || st.gen != gen || !st.down
        || (st.physSeen && !InputHeldPhysical(st.btn))) {
        SetTimer(, 0)
        return
    }
    ; Wall-clock runaway cap: the old 400-TICK cap killed a legitimately
    ; held auto-repeat in ~4 s at fast repeatRates. 30 s of continuous
    ; physical holding is the new ceiling regardless of rate (d < 0 = the
    ; 49.7-day A_TickCount wrap: stop conservatively).
    d := A_TickCount - st.repStart
    if (d < 0 || d >= 30000) {
        SetTimer(, 0)
        return
    }
    SafeSend(v)
}

; --- layers -------------------------------------------------------------------
; v1.0 (E1): layers are button-holds now, resolved entirely through the binding
; index (a held layer-host button raises the specificity of its scoped rows in
; MatchScore). There is no standalone named-layer state machine anymore -- the
; old LayerPush/Release/Toggle + g_Layer/g_LayerStack are gone. A layer can
; never "orphan": it is active exactly while its holder button is physically
; held, and the watchdog's stuck-button sweep already reconciles that.


; ── §7  POINTER (click lock, monitor teleport) ──────────────────────────────────

; --- click lock (v0.3.1) ---------------------------------------------------------
; Hold a mouse button, tap the input bound to "Click lock", and the button
; STAYS down after you let go -- for a long window/level sweep, a marquee, or
; a measurement drag without holding the button. It is released by tapping
; the click-lock input again, by clicking the latched button, by the panic
; hotkey, or by anything that tears the engine down (disable, config change,
; exit). Nothing releases it on a timer: a latch is a deliberate user state,
; like the speed toggles.
;
; The latched button MUST be hooked, or its physical release reaches the OS
; and the latch is undone the moment you let go -- SyncHooks therefore hooks
; the buttons a click-lock row can latch (all five when the row's value is
; blank, one when it names an input).

; Which input to latch: the row's value, else the mouse button currently
; down (newest wins), else the one physically held, else LButton.
; skip = the input that fired the lock: "whichever button is held" must
; never pick the lock's own trigger (it is down too, and newest).
ClickLockTarget(v, skip := "") {
    if (v != "")
        return v
    best := ""
    bestTick := -1
    for name, st in g_BS {
        if (name = skip || !IsMouseInput(name) || !st.down || st.consumed)
            continue
        if (st.pressTick >= bestTick) {
            bestTick := st.pressTick
            best := name
        }
    }
    if (best != "")
        return best
    for b in BUTTONS {
        if (b != skip && RM_KeyHeld(b))
            return b
    }
    ; NOTHING is held. This used to fall through to "LButton", which latched
    ; a button the user was not touching -- a synthetic left-button-down out
    ; of nowhere, which on an image is a click, a drag, or a measurement. A
    ; lock with nothing to lock is a no-op, and says so.
    return ""
}

ClickLockToggle(v, self := 0) {
    global g_ClickLock
    if IsObject(g_ClickLock) {
        ClickLockRelease()
        return
    }
    src := ClickLockTarget(ResolveInputValue(v), IsObject(self) ? self.btn : "")
    if (src = "") {
        HUD("Click lock: hold a mouse button first", "warn")
        return
    }
    if !IsInputTarget(src) {
        Problem("clicklock", "not an input that can be latched: " src)
        HUD("Click lock: '" src "' is not an input")
        return
    }
    held := src
    st := BS(src)
    ; An UNHOOKED button's physical release reaches the OS and undoes the
    ; latch at once, leaving g_ClickLock set with nothing held. The Settings
    ; hotkey has no row to make SyncHooks hook the button, so refuse here.
    if (IsMouseInput(src) && !g_HookState.Has(src)) {
        HUD("Click lock: add a Click lock row for " InputLabel(src)
            . " (Mouse page) so RadMapper can hold it", "warn")
        return
    }
    if (st && st.down && !st.consumed && st.mode = "passthru") {
        ; The engine already has a synthetic down out for this button -- latch
        ; THAT (following a remap through passBtn) and withhold its up.
        held := (st.passBtn != "" ? st.passBtn : src)
        st.locked := true
    } else {
        if (st && st.down) {
            ; pending / armedmod / held: no native down has gone out yet, and
            ; whatever this button was going to do on release must not fire
            ; now that it is being latched instead.
            if (st.mode = "held") {
                ; ... unless it is RUNNING something that is not a button
                ; hold (drag scroll, sniper, a radial holder). Tearing that
                ; down and latching a raw synthetic down in its place is not
                ; what the tap asked for -- same rule as "a lock with
                ; nothing to lock is a no-op".
                t := IsObject(st.holdBinding)
                    ? st.holdBinding["action"]["type"] : ""
                if (!IsNativeAct(t) && t != "dragmove") {
                    HUD("Click lock: " InputLabel(src)
                        . " is already doing something else", "warn")
                    return
                }
                ActionUp(st.holdBinding, st)
                if (st.passBtn != "")        ; a remapped hold latches the
                    held := st.passBtn       ; button it was really holding
            }
            st.usedAsMod := true
            st.consumed := true
        }
        SendNativeDown(held)
    }
    g_ClickLock := {held: held, src: src}
    ClickLockWatchStart()
    LastEvent("click lock " InputLabel(held))
    HUD("Click lock: " InputLabel(held) " held — press again to release")
}

ClickLockRelease() {
    global g_ClickLock
    if !IsObject(g_ClickLock)
        return
    lock := g_ClickLock
    g_ClickLock := 0                         ; clear FIRST: the Up below can
    ClickLockWatchStop()                     ; re-enter through our own hooks
    SendNativeUp(lock.held)
    st := BS(lock.src)
    if (st && st.down)                       ; the physical button may still be
        st.consumed := true                  ; down; its release must be inert
    if Cfg("hud")
        HUD("Click lock released")
}

; --- click lock: release on the next keystroke (v0.4.3) -----------------------
; A latch is a deliberate state, so nothing releases it on a timer -- but
; reaching for the keyboard is itself a statement that the sweep is over, and
; having to remember to unlatch first is how a latch turns into a stuck
; button. So while a lock is held, the next real keystroke drops it.
;
; An InputHook, NOT a hotkey: opened "V" it never blocks, it cannot collide
; with the engine's own "*key" registrations (the trap the Test tab
; documents: "~*X" and "*X" are the same hotkey to AutoHotkey), and it costs
; nothing while no lock is held because it only exists while one is.
;
; Two things deliberately do NOT release it:
;
;   * BARE MODIFIERS. Holding Ctrl or Shift to modify a locked drag -- a
;     constrained measurement, an additive selection -- is a normal thing to
;     do mid-sweep, and dropping the button underneath it would be worse than
;     useless.
;   * SYNTHETIC KEYSTROKES. A macro, a W/L dial digit or a PowerScribe key
;     fired BY RadMapper while a sweep is locked is not the user reaching for
;     the keyboard. A key we sent is not physically down at the moment the
;     hook reports it; a key the user pressed is. That physical test is a
;     heuristic rather than a guarantee, but it is the one the OS gives us.
ClickLockWatchStart() {
    global g_ClickLockHook, g_ClickLockArmed, g_ClickLockVk
    ClickLockWatchStop()
    if !Cfg("clickLockAutoRelease")
        return
    g_ClickLockArmed := A_TickCount
    ; The key that TRIGGERED the lock is exempt, and has to be: the hotkey is
    ; still physically down as the watcher starts, so its auto-repeat would
    ; otherwise release the latch a few hundred ms after engaging it. Parsed
    ; off A_ThisHotkey, which is the hotkey we are running inside.
    g_ClickLockVk := 0
    try {
        hk := RegExReplace(A_ThisHotkey, "^[\^!+#<>*~$]+", "")
        if (hk != "")
            g_ClickLockVk := GetKeyVK(hk)
    }
    ; Notify-only, exactly like the calibrator's: no options string, so no
    ; length limit can end a hook that is never meant to end.
    try {
        ih := InputHook()
        ih.VisibleText := true               ; never swallow the keystroke
        ih.VisibleNonText := true
        ih.KeyOpt("{All}", "N")              ; notify only, suppress nothing
        ih.OnKeyDown := ClickLockKeyDown
        ih.Start()
        g_ClickLockHook := ih
    } catch as e {
        Problem("clicklock", "auto-release watcher failed to start: " e.Message)
    }
}

ClickLockWatchStop() {
    global g_ClickLockHook
    if IsObject(g_ClickLockHook) {
        try g_ClickLockHook.Stop()
        g_ClickLockHook := 0
    }
}

ClickLockKeyDown(ih, vk, sc) {
    if !IsObject(g_ClickLock)
        return
    if IsModifierVK(vk)
        return
    if (vk = g_ClickLockVk)                  ; the key that armed the lock
        return
    if (A_TickCount - g_ClickLockArmed < 400)
        return                               ; still letting go of the trigger
    try {
        if !GetKeyState(Format("vk{:X}", vk), "P")
            return                           ; synthetic: not the user
    }
    ClickLockRelease()
}

IsModifierVK(vk) {
    static mods := Map(0x10, 1, 0x11, 1, 0x12, 1,        ; Shift Ctrl Alt
                       0xA0, 1, 0xA1, 1, 0xA2, 1, 0xA3, 1,
                       0xA4, 1, 0xA5, 1, 0x5B, 1, 0x5C, 1)
    return mods.Has(vk)
}

; True while btn is the input a click lock is holding (or the input that
; latched it) -- its next press is the release, not a new press.
ClickLockOwns(btn) {
    return IsObject(g_ClickLock)
        && (btn = g_ClickLock.held || btn = g_ClickLock.src)
}

; --- teleport signal (v0.3.4) -------------------------------------------------
; A teleport moves the cursor to another screen instantly, which is exactly
; the moment a pointer is easiest to lose. So the destination announces
; itself: a red border flashes around that monitor for one second, and a ring
; pulses out from where the cursor landed.
;
; RED on purpose, and deliberately outside the three-hue palette. This is not
; chrome -- it is a transient "look here" that has to win against whatever
; image is on the screen underneath, and it is gone before it can become part
; of the furniture.
;
; Four thin edge strips rather than one monitor-sized layer: a full-screen
; layered window means a full-screen ARGB buffer allocated and freed on every
; teleport, where the strips are a few tens of kilobytes.

; LITE: the red edge flash and landing ring are GpGFX layers. The pointer
; still moves (TeleportMonitor / FollowTick / DoTeleport do that); only the
; signal is gone.
TeleportSignal(mon, cx, cy, showEdges := true) {
    return
}

TeleSigTick(*) {
    SetTimer(TeleSigTick, 0)
}

TeleportSignalStop() {
    global g_TeleSig, g_PassThru
    SetTimer(TeleSigTick, 0)
    if !IsObject(g_TeleSig)
        return
    sig := g_TeleSig
    g_TeleSig := 0
    try {
        for L in sig.edges {
            try g_PassThru.Delete(L.hwnd)
            try L.Dispose()
        }
        try g_PassThru.Delete(sig.ring.hwnd)
        try sig.ring.Dispose()
    }
}

; --- follow focus (v0.3.2) ----------------------------------------------------
; Warp the pointer to the middle of a window when it TAKES the foreground, so
; the cursor is already where the next click is going. On a three-monitor
; reading station the alternative is dragging the pointer across two screens
; every time PowerScribe steals focus.
;
; Polled rather than hooked: a SetWinEventHook callback fires inside another
; process's message pump and is a poor place to be moving the cursor from,
; while a 120 ms poll costs one GetForegroundWindow call and cannot wedge the
; engine. The timer only exists while the option is on.
;
; It refuses to move the cursor in every case where moving it would be wrong,
; which is most of them -- see FollowTick.

SyncFollowFocus() {
    global g_FollowOn, g_FollowLast, g_FollowPid, g_FollowCand, g_FollowAt
    want := (Cfg("followFocus") = 1) && g_Enabled
    if (want = g_FollowOn)
        return
    g_FollowOn := want
    if want {
        g_FollowLast := FgHwnd()             ; adopt the current window without
        g_FollowPid := 0                     ;   jumping to it
        try g_FollowPid := WinGetPID("ahk_id " g_FollowLast)
        g_FollowCand := 0
        g_FollowAt := 0
        SetTimer(FollowTick, Max(Cfg("followFocusMs"), 40))
    } else
        SetTimer(FollowTick, 0)
}

FollowTick(*) {
    global g_FollowLast, g_FollowPid, g_FollowCand, g_FollowCandAt, g_FollowAt
    global g_TeleAt
    if (!g_Enabled || Cfg("followFocus") != 1) {
        SyncFollowFocus()
        return
    }
    hwnd := DllCall("GetForegroundWindow", "ptr")
    if !hwnd
        return
    if (hwnd = g_FollowLast) {
        g_FollowCand := 0                    ; nothing new in front
        return
    }
    ; 0. settle. A window has to hold the foreground for followSettleMs before
    ;    the cursor commits to it. Loading a study, opening a dialog or
    ;    closing one hands the foreground around for a few frames, and every
    ;    one of those frames used to be a warp. This is what stops the pointer
    ;    ping-ponging.
    now := A_TickCount
    if (hwnd != g_FollowCand) {
        g_FollowCand := hwnd
        g_FollowCandAt := now
        return
    }
    if (now - g_FollowCandAt < Max(Cfg("followSettleMs"), 0))
        return
    g_FollowCand := 0
    g_FollowLast := hwnd                     ; claim it FIRST: every early
                                             ; return below is a deliberate
                                             ; skip, not a retry
    pid := 0
    try pid := WinGetPID("ahk_id " hwnd)
    sameApp := (pid && pid = g_FollowPid)
    g_FollowPid := pid                       ; claimed too, for the same reason
    ; 1. a different WINDOW of the same PROCESS is not an app switch. This is
    ;    the syngo.via case: its container hands the foreground between its
    ;    own top-level windows constantly, and none of those transitions is
    ;    the user asking to be somewhere else. Same for a PACS viewer's second
    ;    display and a browser's second window.
    if (sameApp && Cfg("followSameApp") != 1)
        return
    ; 2. never fight the user mid-gesture -- a warp during a window/level
    ;    sweep, a marquee or a click-locked drag would be destructive
    for b in BUTTONS {
        if GetKeyState(b, "P")
            return
    }
    if IsObject(g_ClickLock)
        return
    ; 2b. ... and a gesture whose holder is a KEY is invisible to the loop
    ;     above. The switcher CHOOSES BY POINTER POSITION,
    ;     the keyboard pointer may be holding LButton itself, and a moddrag
    ;     holds it synthetically (which reads as up under "P"). Warping now
    ;     picks the wrong window or throws the drag across the study.
    if IsObject(g_AppSw)
        return
    if (IsSet(Warp) && Warp.active)
        return
    if HandBusy()
        return
    ; A PowerScribe/PACS delivery holds the foreground for a moment and
    ; hands it back: adopt the window instead of warping to it and back.
    if (g_PSBusy || g_PSQueue.Length) {
        g_FollowLast := hwnd
        return
    }
    ; 3. our own windows: the settings GUI and the toast are not destinations
    if (g_OurHwnds.Has(hwnd) || OwnWindowAt(hwnd))
        return
    ; 4. the shell is not a destination either -- clicking the taskbar or
    ;    the desktop should leave the pointer exactly where it is
    cls := WinClassOf(hwnd)
    for skip in ["Shell_TrayWnd", "Progman", "WorkerW", "NotifyIconOverflowWindow",
                 "Windows.UI.Core.CoreWindow", "TaskListThumbnailWnd"] {
        if (cls = skip)
            return
    }
    ; 5. tool windows and untitled top-levels are palettes, tooltips and
    ;    helpers, not places to put the pointer. The window switcher applies
    ;    the same two tests to decide what is switchable at all.
    try {
        if (WinGetExStyle("ahk_id " hwnd) & 0x00000080)   ; WS_EX_TOOLWINDOW
            return
        if (WinGetTitle("ahk_id " hwnd) = "")
            return
    } catch
        return
    ; 6. a window with no usable rect (minimised, cloaked, a zero-size helper)
    try {
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            return
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
    } catch
        return
    if (!IsSet(ww) || ww < 200 || wh < 150)
        return
    ; 7. an app can opt out entirely, the same way it can opt out of holds.
    ;    A profile that drives its own layout across several displays is
    ;    better left alone even between real switches.
    name := ActiveAppName()
    if AppNoFollow(name)
        return
    ; 7b. ... or is on the exceptions list on Settings (v0.6.6.1)
    if FollowExcepted(hwnd)
        return
    ; 8. one warp per followCooldownMs, whatever happens. A burst of app
    ;    switches moves the pointer once, at the end, not once per step.
    if (g_FollowAt && now - g_FollowAt < Max(Cfg("followCooldownMs"), 0)
        && now - g_FollowAt >= 0)
        return
    ; 9. a park point for this app beats the window centre: the middle of a
    ;    PowerScribe window is not where the dictation field is
    cx := wx + ww // 2
    cy := wy + wh // 2
    parked := false
    if (name != "") {
        pk := ParkOf(name)
        if IsObject(pk) {
            cx := pk.x
            cy := pk.y
            parked := true
        }
    }
    ; 10. already where it should be? then the pointer is where the user put
    ;    it -- and that now includes a PARKED program (v0.6.6). The rule
    ;    used to be "inside a small radius of the spot" for a parked app,
    ;    so clicking anywhere in PACS that was not the spot itself focused
    ;    PACS and yanked the pointer to the spot: the mouse was being moved
    ;    constantly while navigating the viewer. The pointer is INSIDE the
    ;    window that just came to the front, which means it was put there
    ;    on purpose (a click, a teleport, a drag), and the spot is for the
    ;    other case: focus arriving with the pointer somewhere else
    ;    entirely, by Alt+Tab, a hotkey, or a dictation command.
    RM_GetPos(&mx, &my)
    if (mx >= wx && mx < wx + ww && my >= wy && my < wy + wh)
        return
    if (parked && Abs(mx - cx) < 40 && Abs(my - cy) < 40)
        return
    ; 11. a monitor teleport a moment ago is the user saying where the
    ;    pointer goes. Whatever comes to the front because of it (the
    ;    program under the new spot, clicked) keeps the pointer there.
    if (g_TeleAt && now - g_TeleAt >= 0 && now - g_TeleAt < 1500)
        return
    g_FollowAt := now
    DllCall("SetCursorPos", "int", cx, "int", cy)
    FocusSignal(cx, cy)
    if Cfg("hud")
        HUD(parked ? ("Parked for " name) : "Cursor followed focus", "cyan")
}

/**
 * Is this window one follow-focus must leave alone? The list is the
 * "Follow focus except in" field on Settings: ";"-separated entries, each
 * a program file name (case-insensitive, "exe:" prefix optional), "title:"
 * plus part of the window title, or "class:" plus the window class.
 */
FollowExcepted(hwnd) {
    raw := Trim(String(Cfg("followExcept")))
    if (raw = "")
        return false
    exe := "", title := "", cls := ""
    try exe := WinGetProcessName("ahk_id " hwnd)
    try title := WinGetTitle("ahk_id " hwnd)
    try cls := WinGetClass("ahk_id " hwnd)
    for one in StrSplit(raw, ";") {
        e := Trim(one)
        if (e = "")
            continue
        if (SubStr(e, 1, 6) = "title:") {
            t := Trim(SubStr(e, 7))
            if (t != "" && InStr(title, t, false))
                return true
        } else if (SubStr(e, 1, 6) = "class:") {
            if (cls != "" && cls = Trim(SubStr(e, 7)))
                return true
        } else {
            if (SubStr(e, 1, 4) = "exe:")
                e := Trim(SubStr(e, 5))
            if (exe != "" && exe = e)
                return true
        }
    }
    return false
}

/**
 * "The cursor is now HERE." Ring only -- see TeleportSignal.
 *
 * Used by follow-focus and by the window switcher, so a switch that moves
 * the pointer says so in the same visual language a teleport does.
 */
FocusSignal(x, y) {
    try TeleportSignal(MonitorAt(x, y), x, y, false)
}

; --- monitor teleport ---------------------------------------------------------
DoTeleport(v) {
    ; SameText on the signed forms: "1" = "+1" (and ==) are NUMERIC, so
    ; screen 1 used to mean "next screen".
    if (v = "prev" || SameText(v, "-1") || v = "left" || v = "l")
        TeleportMonitor(-1)                  ; monitors are ordered by X, so
    else if (v = "next" || SameText(v, "+1") || v = "right" || v = "r")
        TeleportMonitor(1)                   ; prev/next = left/right
    else if IsInteger(v)
        TeleportToIndex(Integer(v))
    else
        TeleportMonitor(1)
}

TeleportMonitor(step) {
    mons := _MonitorsByX()
    n := mons.Length
    if (n < 1)
        return
    RM_GetPos(&mx, &my)
    cur := 1
    loop n {
        m := mons[A_Index]
        if (mx >= m.l && mx < m.r && my >= m.t && my < m.b) {
            cur := A_Index
            break
        }
    }
    tgt := Mod(cur - 1 + step + n, n) + 1
    m := mons[tgt]
    tx := (m.l + m.r) // 2
    ty := (m.t + m.b) // 2
    DllCall("SetCursorPos", "int", tx, "int", ty)
    TeleportSignalLater(m, tx, ty)
    TeleportNoteFollow()
}

/**
 * The flash, off the caller's thread (v0.6.6.3). A teleport is fired from
 * a Critical hotkey thread -- a tilt notch, a thumb button -- and building
 * five overlay windows there held every notch that arrived meanwhile.
 * The pointer has already moved; the picture can follow a moment later.
 */
TeleportSignalLater(mon, cx, cy) {
    SetTimer(() => TeleportSignal(mon, cx, cy), -1)
}

/**
 * A teleport just moved the pointer on purpose. Tell follow-focus, so a
 * foreground change that happens because of it (the program on the new
 * monitor, clicked) does not warp the pointer straight back to that
 * program's pointer spot: adopt whatever is in front now, and hold every
 * warp off for a moment (FollowTick step 11).
 */
TeleportNoteFollow() {
    global g_TeleAt, g_FollowLast, g_FollowCand
    g_TeleAt := A_TickCount
    if g_FollowOn {
        try g_FollowLast := FgHwnd()
        g_FollowCand := 0
    }
}

TeleportToIndex(idx) {
    mons := _MonitorsByX()
    if (idx < 1 || idx > mons.Length)
        return
    m := mons[idx]
    tx := (m.l + m.r) // 2
    ty := (m.t + m.b) // 2
    DllCall("SetCursorPos", "int", tx, "int", ty)
    TeleportSignalLater(m, tx, ty)
    TeleportNoteFollow()
}

; The monitor containing a point, or the primary one if it lies off every
; screen. Used to keep a dropdown on the display it belongs to; A_ScreenWidth
; and A_ScreenHeight describe the PRIMARY monitor only, which is the wrong
; answer on every reading station with more than one.
MonitorAt(px, py) {
    fallback := 0
    loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (A_Index = MonitorGetPrimary())
            fallback := {l: l, t: t, r: r, b: b}
        if (px >= l && px < r && py >= t && py < b)
            return {l: l, t: t, r: r, b: b}
    }
    if IsObject(fallback)
        return fallback
    return {l: 0, t: 0, r: A_ScreenWidth, b: A_ScreenHeight}
}

; Same, but the WORK AREA -- the screen minus the taskbar. The HUD anchors
; to a corner, and a corner that ignores the taskbar is a corner behind it.
MonitorWorkAt(px, py) {
    fallback := 0
    loop MonitorGetCount() {
        MonitorGet(A_Index, &ml, &mt, &mr, &mb)
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        if (A_Index = MonitorGetPrimary())
            fallback := {l: l, t: t, r: r, b: b}
        if (px >= ml && px < mr && py >= mt && py < mb)
            return {l: l, t: t, r: r, b: b}
    }
    if IsObject(fallback)
        return fallback
    return {l: 0, t: 0, r: A_ScreenWidth, b: A_ScreenHeight}
}

_MonitorsByX() {
    ; the same screens, in the same order, as every station feature
    ; (winplace "2", the keyboard pointer): 0x0 panels dropped, left then top
    return StationMons()
}


; ── §7b  APP SWITCHER (hold an input, scroll a list, release to switch) ─────
;
; The built-in use case for the wheel deck, and the one Alt+Tab gets wrong on
; a reading station: Alt+Tab's own list vanishes the moment you let go of a
; key, so picking the fourth window back is a guess. Here the list is raised
; by the HOLD, updated by the wheel, and stays on screen until the hold ends
; -- you scroll, you look, and only then do you commit.
;
; Bound as the "appswitch" action on a wheel row inside a layer, so the layer
; HOST is the hold: e.g. layer XButton1 + WheelUp -> appswitch "-1" and
; WheelDown -> appswitch "+1". The wheel path hands ActionFire the deepest
; held holder, which is the state object this watches for release.
;
; It works at Base too (no holder): then it commits after ~1.2 s of stillness,
; because there is nothing to release.

global g_AppSw := 0        ; {list, idx, lyr, holder, last}

; LITE: the window switcher is a thumbnail grid drawn with GpGFX. The action
; still resolves (a bound wheel is consumed, not passed through) and says so.
AppSwitchStep(st, v) {
    LiteNA("appswitch", "The window switcher")
}


; LITE: the switcher's Delete key is never registered.
AppSwitchBindKeys(on := false) {
    return
}


; LITE: no switcher can be open; callers (panic, teardown, ClearBS) still
; get a closed g_AppSw.
AppSwitchClose(commit) {
    global g_AppSw
    g_AppSw := 0
}


; ── §7c  WINDOW LAYOUTS (multi-monitor, station-aware) ──────────────────────
;
; A reading station is a fixed arrangement of the same six or seven windows
; across three or four displays, and two things keep breaking it: a window
; opens on the wrong screen and has to be dug out, and an application decides
; on its own to resize or re-place a window mid-session. A layout is that
; arrangement captured once, by name, and put back on demand -- and, when it
; is armed, put back again whenever something drifts.
;
; v0.6.2 makes a layout survive a DIFFERENT STATION. A radiologist reads at
; several workstations a week, and no two have the same monitors in the same
; order; the only near-constant is that the diagnostic display shows images
; and nothing else -- and even that is not true everywhere. So:
;
;   * A slot remembers WHICH screen it sat on, counted left to right, and
;     WHERE on that screen as fractions of its work area, next to the
;     absolute rectangle. On the station it was captured on the absolute
;     rectangle is used, pixel for pixel. Anywhere else the slot is ADAPTED:
;     its screen is mapped by relative position onto the screens that exist
;     and its fractions are re-applied there. Maximised stays maximised.
;   * A STATION is the set of monitors the engine can see, identified by
;     their sizes in left-to-right order ("1920x1080|2048x1536|1920x1080").
;     Each station can name the arrangement that belongs on it and which of
;     its screens are IMAGING screens; when the monitor set changes (dock,
;     log-in elsewhere, a display waking late) the engine recognises the
;     station and applies its arrangement.
;   * Imaging screens are RESERVED while adapting: a window that is not the
;     viewer is never placed on one while an unreserved screen exists, and
;     the viewer prefers one. "auto" reserves portrait screens and screens
;     with markedly more pixels than the MEDIAN one; a station can say
;     "none", or list them ("2,3"); when the rule would reserve every screen
;     it narrows to the portrait screens, or to the largest screen, rather
;     than leaving the worklist the whole desk.
;
; SHAPE (config key "layouts", an array):
;     Map("name",    "Reading",
;         "guard",   0|1|2,       0 off, 1 keep in place, 2 place NEW windows only
;         "station", "1920x1080|2048x1536",     the monitor set it was captured on
;         "slots", [ Map("exe","title","ord","x","y","w","h","state",
;                        "mon","fx","fy","fw","fh") ... ])
; state is "normal" | "max"; minimised windows are not captured, because a
; layout that re-minimises windows is a layout nobody wants restored.
;
; SHAPE (config key "stations", an array):
;     Map("key", "1920x1080|2048x1536", "name", "", "imaging", "auto"|"none"|"2,3"|"",
;         "layout", "Reading")
;
; MATCHING is the whole difficulty. Titles on this workstation are not
; stable -- PowerScribe puts the patient in the title, and IntelliSpace runs
; the worklist AND the viewer in ONE process, so the exe alone cannot tell
; them apart. So a slot is matched in four descending steps, and a window is
; claimed once so two slots can never fight over it:
;     1. same exe + identical title            (stable-titled apps)
;     2. same exe + same 12-char title prefix  ("Philips IntelliSpace ...")
;     3. same exe + same ordinal position      (nth window of that process)
;     4. same exe, any window still unclaimed
;
; The guard is opt-in per layout. Mode 1 is deliberately blunt: while armed
; it snaps drifted windows back on a timer. Mode 2 is the gentle one for a
; station's own arrangement: it places a window ONCE, when it first appears,
; and never touches it again -- so PACS opened after RadMapper still lands on
; the right screen, and a window you then move stays moved. Neither runs
; while a mouse button is physically down, so they cannot fight a drag in
; progress, and both ignore minimised windows.

global g_LayoutGuard := ""        ; name of the armed layout, "" = none
global g_LayoutSnaps := 0         ; windows snapped back this session
; layout name -> Map(hwnd -> 1): windows a mode-2 guard has already placed.
; PER LAYOUT, because "has this window been placed?" is only meaningful about
; a particular arrangement: with one flat set, switching the guard from
; "Reading" to "Worklist" found every window already marked and placed
; nothing at all until a restart.
global g_LayoutPlaced := Map()
global g_StationKey := ""         ; monitor set the engine last saw
global g_StationSeen := Map()     ; station keys announced this session
global g_StationStartup := true   ; first StationSettled pass is the launch pass
global g_LayoutAdapted := false   ; last LayoutApplyRows had to adapt to this station

global LAYOUT_TOL := 8            ; px of drift the guard tolerates

LayoutByName(name) {
    for lay in MGet(g_Cfg, "layouts", []) {
        if (MGet(lay, "name", "") = name)
            return lay
    }
    return 0
}

; --- stations -----------------------------------------------------------------

/**
 * Every monitor, LEFT TO RIGHT (then top to bottom), with its bounds and its
 * work area. idx is the position in this order -- the number every station
 * feature means by "screen 2". OS enumeration order is not used anywhere:
 * it changes with cable swaps and driver updates; left-to-right does not.
 */
StationMons() {
    arr := []
    loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        MonitorGetWorkArea(A_Index, &wl, &wt, &wr, &wb)
        ; A MONITOR WITH NO AREA IS A MONITOR MID-HANDSHAKE. Windows reports
        ; a 0x0 display while a panel is waking, while a KVM is switching and
        ; for a second or two after a dock -- and a 0x0 screen in the list
        ; changes the station key ("|0x0"), divides by zero in the fraction
        ; maths, and is a place a window could be "placed" and never seen
        ; again. Drop it; the poll and WM_DISPLAYCHANGE bring us back when
        ; the real numbers arrive.
        if (r - l <= 0 || b - t <= 0)
            continue
        arr.Push({i: A_Index, l: l, t: t, r: r, b: b,
                  wl: wl, wt: wt, wr: wr, wb: wb,
                  w: r - l, h: b - t,
                  primary: (A_Index = MonitorGetPrimary())})
    }
    return StationSort(arr)
}

/** Insertion sort by left edge, then top edge; assigns idx. Pure. */
StationSort(arr) {
    i := 2
    while (i <= arr.Length) {
        key := arr[i]
        j := i - 1
        while (j >= 1 && (arr[j].l > key.l
                          || (arr[j].l = key.l && arr[j].t > key.t))) {
            arr[j + 1] := arr[j]
            j -= 1
        }
        arr[j + 1] := key
        i += 1
    }
    for k, m in arr
        m.idx := k
    return arr
}

/** "1920x1080|2048x1536|1920x1080": the identity of a monitor set. */
StationKey(mons := 0) {
    if !IsObject(mons)
        mons := StationMons()
    s := ""
    for m in mons
        s .= (s = "" ? "" : "|") m.w "x" m.h
    return s
}

/** Number of screens a station key describes. */
StationCount(key) {
    return (key = "") ? 0 : StrSplit(key, "|").Length
}

/** "3 screens · 1920x1080 · 2048x1536 · 1920x1080" */
StationLabel(key) {
    if (key = "")
        return "no screens"
    parts := StrSplit(key, "|")
    s := parts.Length " screen" (parts.Length = 1 ? "" : "s")
    for p in parts
        s .= " · " p
    return s
}

/** The station record for a key ("" = the current station); create on request. */
StationEntry(key := "", create := false) {
    if (key = "")
        key := StationKey()
    for st in MGet(g_Cfg, "stations", []) {
        if (MGet(st, "key", "") = key)
            return st
    }
    if !create
        return 0
    st := Map()
    st["key"] := key
    st["name"] := ""
    st["imaging"] := ""
    st["layout"] := ""
    if !g_Cfg.Has("stations")
        g_Cfg["stations"] := []
    g_Cfg["stations"].Push(st)
    return st
}

/**
 * Which screens (left-to-right idx) are imaging displays, as Map(idx -> 1).
 * rule: "auto" | "none" | "2" | "2,3". Pure: takes the monitor list.
 *
 *   auto  = portrait screens, and screens with at least 35% more pixels than
 *           the MEDIAN screen. The 3 MP and 5 MP greyscale displays a reading
 *           room uses are both; a colour worklist screen next to them is
 *           neither. If the rule would reserve EVERY screen it narrows --
 *           to the portrait screens, else to the largest one -- because
 *           there has to be somewhere for the worklist to go.
 */
ImagingMons(mons, rule := "auto") {
    out := Map()
    n := mons.Length
    if (n < 2)
        return out
    rule := Trim(StrLower(String(rule)))
    if (rule = "none")
        return out
    if (rule = "" || rule = "auto") {
        ; THE PIXEL RULE IS RANKED AGAINST THE MEDIAN, NOT THE SMALLEST.
        ; One outlier used to move the bar for everyone: a 1280x1024 legacy
        ; screen in the corner dropped minA far enough that the two 1920x1080
        ; colour screens beside it cleared 1.35x and were reserved as imaging
        ; displays. The median is the typical screen at this station, which
        ; is what "markedly more pixels than the others" actually means.
        areas := []
        for m in mons
            areas.Push(m.w * m.h)
        medA := StationMedian(areas)
        portrait := Map()
        for m in mons {
            if (m.h > m.w)
                portrait[m.idx] := 1
            if (m.h > m.w || (medA > 0 && m.w * m.h >= medA * 1.35))
                out[m.idx] := 1
        }
        ; NOTHING IS RESERVED WHEN EVERYTHING WOULD BE -- but "reserve none"
        ; is the wrong answer at a station of three portrait diagnostics and
        ; one 4K, where every screen clears a rule and the worklist then has
        ; the whole desk to wander over. Narrow instead of giving up:
        ;   1. the PORTRAIT screens alone, if that is a real subset
        ;   2. failing that, the single largest screen (n >= 2), which is the
        ;      diagnostic display at every station that has an obvious one
        if (out.Count >= n) {
            out := Map()
            if (portrait.Count > 0 && portrait.Count < n) {
                out := portrait
            } else if (n >= 2) {
                big := 1
                bigA := 0
                for m in mons {
                    if (m.w * m.h > bigA) {
                        bigA := m.w * m.h
                        big := m.idx
                    }
                }
                out[big] := 1
            }
        }
    } else {
        for tok in StrSplit(rule, [",", " ", ";"]) {
            tok := Trim(tok)
            if (tok != "" && IsInteger(tok) && Integer(tok) >= 1
                && Integer(tok) <= n)
                out[Integer(tok)] := 1
        }
    }
    if (out.Count >= n)
        out := Map()
    return out
}

/** Median of a list of numbers (insertion sort; the lists here are 1-4 long). */
StationMedian(vals) {
    a := vals.Clone()
    i := 2
    while (i <= a.Length) {
        key := a[i]
        j := i - 1
        while (j >= 1 && a[j] > key) {
            a[j + 1] := a[j]
            j -= 1
        }
        a[j + 1] := key
        i += 1
    }
    n := a.Length
    if (n = 0)
        return 0
    return Mod(n, 2) ? a[(n + 1) // 2] : (a[n // 2] + a[n // 2 + 1]) / 2
}

/** The imaging rule in force for a station: its own, else the global setting. */
StationImagingRule(st := 0) {
    r := IsObject(st) ? Trim(String(MGet(st, "imaging", ""))) : ""
    return (r != "") ? r : Cfg("imagingMons")
}

/** "screen 2" / "screens 2 and 3" / "none" */
ImagingWords(reserved) {
    if (reserved.Count = 0)
        return "none"
    idxs := []
    for k in reserved
        idxs.Push(k)
    ; Map iteration order is insertion order; sort for the sentence
    i := 2
    while (i <= idxs.Length) {
        key := idxs[i]
        j := i - 1
        while (j >= 1 && idxs[j] > key) {
            idxs[j + 1] := idxs[j]
            j -= 1
        }
        idxs[j + 1] := key
        i += 1
    }
    if (idxs.Length = 1)
        return "screen " idxs[1]
    s := "screens "
    for k, v in idxs
        s .= (k = 1 ? "" : (k = idxs.Length ? " and " : ", ")) v
    return s
}

/** Left-to-right index of the monitor containing (or nearest to) a point. */
MonIndexAt(mons, px, py) {
    for m in mons {
        if (px >= m.l && px < m.r && py >= m.t && py < m.b)
            return m.idx
    }
    best := 1
    bestD := 0
    for m in mons {
        dx := (px < m.l) ? m.l - px : (px >= m.r ? px - m.r + 1 : 0)
        dy := (py < m.t) ? m.t - py : (py >= m.b ? py - m.b + 1 : 0)
        d := dx * dx + dy * dy
        if (m.idx = 1 || d < bestD) {
            best := m.idx
            bestD := d
        }
    }
    return best
}

/** Exes the imaging viewer runs as: the PACS app profile's, else IntelliSpace. */
ImagingExes() {
    out := Map()
    for app in MGet(g_Cfg, "apps", []) {
        if (MGet(app, "name", "") != Cfg("pacsApp"))
            continue
        for m in MGet(app, "match", []) {
            s := Trim(String(m))
            if (SubStr(s, 1, 6) = "title:" || s = "")
                continue
            if (SubStr(s, 1, 8) = "ahk_exe ")
                s := Trim(SubStr(s, 9))
            else if InStr(s, "ahk_")
                continue
            out[StrLower(s)] := 1
        }
    }
    if (out.Count = 0)
        out["intellispacepacsradiology.exe"] := 1
    return out
}

/**
 * Is this slot the imaging viewer? Exe says PACS AND the title says viewer
 * (pacsWindow, "VirtualMonitor" by default): IntelliSpace's worklist is the
 * same exe and belongs on the colour screen, not the diagnostic one.
 */
SlotIsImaging(slot, exes := 0) {
    if !IsObject(exes)
        exes := ImagingExes()
    if !exes.Has(StrLower(MGet(slot, "exe", "")))
        return false
    want := Trim(Cfg("pacsWindow"))
    return (want = "") || InStr(MGet(slot, "title", ""), want) ? true : false
}

/**
 * Which current screen a slot lands on. Pure, given the monitor list and the
 * reserved set.
 *
 * Same station as the capture: its own screen. Otherwise the slot's screen
 * (nth of N) maps to the nearest nth of the M screens that exist -- so a
 * four-screen arrangement folds onto three, and a three-screen one spreads
 * over four -- and then the reservation is applied: a viewer slot moves to
 * the nearest reserved screen, anything else moves OFF a reserved screen.
 */
LayoutMonFor(slot, lay, mons, reserved, imaging := -1, key := "") {
    n := mons.Length
    if (n < 1)
        return 1
    ; `key` is the caller's already-computed StationKey(mons): LayoutApplyRows
    ; asks this question once per SLOT, and rebuilding the same string from
    ; the same monitor list every time is work for nothing. Blank = work it
    ; out here, which keeps the direct callers (and the tests) unchanged.
    if (key = "")
        key := StationKey(mons)
    sm := Integer(MGet(slot, "mon", 1))
    sm := Min(Max(sm, 1), 99)
    if (key = MGet(lay, "station", ""))
        return Min(sm, n)
    capN := Max(StationCount(MGet(lay, "station", "")), sm, 1)
    tgt := Round((sm - 0.5) / capN * n + 0.5)
    tgt := Min(Max(tgt, 1), n)
    if (reserved.Count = 0 || reserved.Count >= n)
        return tgt
    if (imaging = -1)
        imaging := SlotIsImaging(slot)
    if (imaging && !reserved.Has(tgt))
        return NearestMon(tgt, n, reserved, true)
    if (!imaging && reserved.Has(tgt))
        return NearestMon(tgt, n, reserved, false)
    return tgt
}

/** Nearest screen index whose reserved-ness matches wantReserved. */
NearestMon(from, n, reserved, wantReserved) {
    best := from
    bestD := 999
    loop n {
        isRes := reserved.Has(A_Index) ? true : false
        if (isRes != wantReserved)
            continue
        d := Abs(A_Index - from)
        if (d < bestD) {
            best := A_Index
            bestD := d
        }
    }
    return best
}

/**
 * The absolute target rectangle for a slot on the current station:
 * {x, y, w, h, mon, adapted}. Exact on the capturing station; adapted from
 * the fractions elsewhere; a pre-0.6.2 slot with no fractions is kept where
 * it was if that is still on some screen, else centred on its mapped screen.
 */
LayoutSlotTarget(slot, lay, mons, reserved, exes := 0, key := "") {
    if (key = "")
        key := StationKey(mons)
    mi := LayoutMonFor(slot, lay, mons, reserved,
        IsObject(exes) ? SlotIsImaging(slot, exes) : -1, key)
    m := mons[mi]
    same := (key = MGet(lay, "station", ""))
    sx := MGet(slot, "x", 0), sy := MGet(slot, "y", 0)
    sw := MGet(slot, "w", 0), sh := MGet(slot, "h", 0)
    ; Sizes alone make the key, so the same screens arranged differently
    ; (primary changed, a twin station) match too: take the stored rect only
    ; when its centre really lies on the screen it was chosen for.
    if (same && slot.Has("x")
        && sx + sw // 2 >= m.l && sx + sw // 2 < m.r
        && sy + sh // 2 >= m.t && sy + sh // 2 < m.b)
        return {x: sx, y: sy, w: sw, h: sh, mon: m, adapted: false}
    ww := Max(m.wr - m.wl, 1)
    wh := Max(m.wb - m.wt, 1)
    if !slot.Has("fx") {
        ; legacy slot: on-screen somewhere? keep it. Else centre it.
        cx := sx + sw // 2, cy := sy + sh // 2
        for om in mons {
            if (cx >= om.l && cx < om.r && cy >= om.t && cy < om.b)
                return {x: sx, y: sy, w: sw, h: sh, mon: om, adapted: true}
        }
        w := Min(Max(sw, 200), ww), h := Min(Max(sh, 120), wh)
        return {x: m.wl + (ww - w) // 2, y: m.wt + (wh - h) // 2,
                w: w, h: h, mon: m, adapted: true}
    }
    ; The floor is 0.005, not 0.1. A tenth of a 4K screen is 384 px, so a
    ; deliberately narrow window -- a dictation bar, a palette, a 200 px tool
    ; strip -- was silently inflated to a tenth of the screen every time the
    ; arrangement was adapted. The absolute floors below (120 x 80 px) are
    ; the real protection against a degenerate rectangle; this one only has
    ; to keep the multiplication away from zero.
    fw := Min(Max(MGet(slot, "fw", 1.0) + 0.0, 0.005), 1.0)
    fh := Min(Max(MGet(slot, "fh", 1.0) + 0.0, 0.005), 1.0)
    w := Max(Round(fw * ww), 120)
    h := Max(Round(fh * wh), 80)
    x := m.wl + Round((MGet(slot, "fx", 0) + 0.0) * ww)
    y := m.wt + Round((MGet(slot, "fy", 0) + 0.0) * wh)
    ; keep it on the screen it was mapped to
    x := Min(Max(x, m.wl), m.wr - w)
    y := Min(Max(y, m.wt), m.wb - h)
    return {x: x, y: y, w: w, h: h, mon: m, adapted: true}
}

/** Fill a slot's screen-relative fields from an absolute rect. */
SlotSetRelative(s, mons, x, y, w, h) {
    mi := MonIndexAt(mons, x + w // 2, y + h // 2)
    m := mons[mi]
    ww := Max(m.wr - m.wl, 1)
    wh := Max(m.wb - m.wt, 1)
    s["mon"] := mi
    ; CLAMP TO THE CHOSEN SCREEN BEFORE DIVIDING. The monitor is picked by
    ; the window's CENTRE, so a window can legitimately overhang it: a
    ; maximised window's rect includes the invisible resize border and
    ; starts a few pixels left of and above the monitor, and a window
    ; straddling two screens has most of itself on one of them. Undivided,
    ; that gave fx = -0.004 and fw = 1.9 -- fractions that mean "start off
    ; the left edge and be twice as wide as the screen", and they were then
    ; re-applied literally at the next station. The overflow is deliberately
    ; DISCARDED rather than spilled onto the neighbour: a slot describes a
    ; place on one screen, and the absolute x/y/w/h alongside it still carry
    ; the exact original rectangle for the station it was captured on.
    x2 := Min(Max(x, m.wl), m.wr)
    y2 := Min(Max(y, m.wt), m.wb)
    w2 := Max(Min(x + w, m.wr) - x2, 1)
    h2 := Max(Min(y + h, m.wb) - y2, 1)
    s["fx"] := Round((x2 - m.wl) / ww, 4)
    s["fy"] := Round((y2 - m.wt) / wh, 4)
    s["fw"] := Round(w2 / ww, 4)
    s["fh"] := Round(h2 / wh, 4)
}

/**
 * Pre-0.6.2 layouts carry absolute rectangles only. They were captured on
 * THIS machine (there was no other way to get one into this config), so
 * their screen and fractions are derived against the current station once,
 * on load, and the layout is stamped with it. Nothing about how they apply
 * here changes; they merely become portable.
 */
MigrateLayoutSlots(stamp := true) {
    mons := 0
    for lay in MGet(g_Cfg, "layouts", []) {
        if !(lay is Map)
            continue
        if (MGet(lay, "station", "") != "")
            continue
        if !IsObject(mons) {
            try mons := StationMons()
            catch
                return
            if (mons.Length = 0)
                return
        }
        ; STAMPING IS A CLAIM, and a wrong one is worse than none: a layout
        ; stamped with this station is applied PIXEL FOR PIXEL here, skipping
        ; the adapt path entirely. It is only true that the layout was
        ; captured here if the windows it describes still fall on screens
        ; this station has. If any slot's centre is off every monitor, the
        ; rectangles came from somewhere else (a copied config, a station
        ; that has since lost a display) -- leave "station" blank so the
        ; layout is treated as foreign and ADAPTED, which is the safe answer.
        onHere := true
        for s in MGet(lay, "slots", []) {
            if !(s is Map)
                continue
            if !s.Has("x") {
                onHere := false
                break
            }
            cx := MGet(s, "x", 0) + MGet(s, "w", 0) // 2
            cy := MGet(s, "y", 0) + MGet(s, "h", 0) // 2
            inside := false
            for m in mons {
                if (cx >= m.l && cx < m.r && cy >= m.t && cy < m.b) {
                    inside := true
                    break
                }
            }
            if !inside {
                onHere := false
                break
            }
        }
        for s in MGet(lay, "slots", []) {
            if (!(s is Map) || s.Has("fx") || !s.Has("x"))
                continue
            try SlotSetRelative(s, mons, s["x"], s["y"], s["w"], s["h"])
        }
        ; An IMPORTED config was captured on the exporting machine by
        ; definition, so its blank stations are never this one's: CfgImport
        ; passes stamp := false and the fractions alone do the work.
        if (stamp && onHere)
            lay["station"] := StationKey(mons)
        g := MGet(lay, "guard", 0)
        lay["guard"] := (g = 1 || g = 2) ? g : 0
    }
}

; --- capture / match / apply --------------------------------------------------

/**
 * Every window a layout could reasonably own, in z-order, with its ordinal
 * position within its own process recorded -- that ordinal is match step 3.
 */
LayoutWindows() {
    out := []
    seen := Map()
    for hwnd in WinGetList() {
        if g_OurHwnds.Has(hwnd)
            continue
        try {
            if !DllCall("user32\IsWindowVisible", "ptr", hwnd)
                continue
            title := WinGetTitle("ahk_id " hwnd)
            if (title = "")
                continue
            cls := WinGetClass("ahk_id " hwnd)
            if (cls = "Shell_TrayWnd" || cls = "Progman" || cls = "WorkerW"
                || cls = "Windows.UI.Core.CoreWindow")
                continue
            if (WinGetExStyle("ahk_id " hwnd) & 0x00000080)   ; WS_EX_TOOLWINDOW
                continue
            ; OWNED WINDOWS ARE DIALOGS, not arrangement members: "Save as",
            ; "Sign report?", PowerScribe's modal prompts. Moving one is
            ; noticeable and useless (it is gone in two seconds), and worse,
            ; it takes a slot's claim away from the real window behind it, so
            ; the arrangement silently stopped placing the editor whenever a
            ; prompt happened to be up. GW_OWNER = 4.
            owner := 0
            try owner := DllCall("user32\GetWindow", "ptr", hwnd, "uint", 4, "ptr")
            if owner
                continue
            ; No thick frame = not resizable = nothing a layout can size.
            ; Splash screens, fixed-size dialogs, some Electron pop-ups.
            ; WS_THICKFRAME = 0x40000.
            if !(WinGetStyle("ahk_id " hwnd) & 0x00040000)
                continue
            cloaked := 0
            try DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd,
                "int", 14, "int*", &cloaked, "int", 4)
            if cloaked
                continue
            exe := WinGetProcessName("ahk_id " hwnd)
            seen[exe] := MGet(seen, exe, 0) + 1
            out.Push({hwnd: hwnd, exe: exe, title: title, cls: cls,
                      ord: seen[exe]})
        }
    }
    return out
}

/** Capture the current arrangement under a name. Returns the slot count. */
LayoutCapture(name) {
    name := Trim(name)
    if (name = "")
        return 0
    mons := StationMons()
    slots := []
    for wnd in LayoutWindows() {
        try {
            mm := WinGetMinMax("ahk_id " wnd.hwnd)
            if (mm = -1)                     ; minimised: not worth restoring
                continue
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " wnd.hwnd)
            s := Map()
            s["exe"] := wnd.exe
            s["title"] := wnd.title
            s["ord"] := wnd.ord
            ; The WINDOW CLASS narrows the loose match steps. PowerScribe's
            ; class carries a per-run GUID and is useless for IDENTIFYING it
            ; (see the skill's §1 rule: match PS by exe, never by class) --
            ; but it is perfectly good for telling two windows of the SAME
            ; process apart, which is the only thing it is used for below.
            ; IntelliSpace runs the worklist and the viewer under one exe
            ; with different classes, and that is exactly the pair steps 3
            ; and 4 used to swap.
            s["cls"] := wnd.cls
            s["state"] := (mm = 1) ? "max" : "normal"
            ; A maximised window's rect is the monitor it is maximised ON, so
            ; storing it is what lets a "max" slot be restored to the RIGHT
            ; screen rather than to whichever one Windows picks.
            s["x"] := wx
            s["y"] := wy
            s["w"] := ww
            s["h"] := wh
            SlotSetRelative(s, mons, wx, wy, ww, wh)
            slots.Push(s)
        }
    }
    if (slots.Length = 0)
        return 0
    lay := LayoutByName(name)
    if IsObject(lay) {
        lay["slots"] := slots
    } else {
        lay := Map()
        lay["name"] := name
        lay["guard"] := 0
        lay["slots"] := slots
        if !g_Cfg.Has("layouts")
            g_Cfg["layouts"] := []
        g_Cfg["layouts"].Push(lay)
    }
    lay["station"] := StationKey(mons)
    ; The first arrangement saved on a station becomes that station's own,
    ; so "save it" is enough for it to come back next time the engine sees
    ; these screens. Change it on the Windows page.
    st := StationEntry(lay["station"], true)
    if (MGet(st, "layout", "") = "" || !IsObject(LayoutByName(st["layout"])))
        st["layout"] := name
    return slots.Length
}

/**
 * Find the window a slot means, claiming it so no later slot can take it.
 * See the four-step rule in the section header.
 */
; A window class with its per-launch GUID removed:
; "HwndWrapper[PS;;7cde...485]" -> "HwndWrapper[PS]".
ClsKey(c) => RegExReplace(c, ";;[0-9A-Fa-f-]{36}\]$", "]")

LayoutMatch(slot, wins, claimed) {
    exe := MGet(slot, "exe", "")
    title := MGet(slot, "title", "")
    pref := SubStr(title, 1, 12)
    ; Steps 1 and 2 are anchored by the title and need no further narrowing.
    ; Steps 3 and 4 are guesses, and a guess inside a multi-window process
    ; should at least land on the same KIND of window: a pre-0.6.2c slot has
    ; no "cls" and behaves exactly as before. PowerScribe's GUID-bearing
    ; class changes every launch, so a stored PS class simply never matches
    ; and those slots fall through to the old exe-only behaviour -- which is
    ; the right outcome, not a regression.
    ; WPF/WinForms classes carry a per-launch GUID; compare without it.
    cls := ClsKey(MGet(slot, "cls", ""))
    ; 1. exe + exact title
    for wnd in wins {
        if (!claimed.Has(wnd.hwnd) && wnd.exe = exe && wnd.title = title)
            return wnd
    }
    ; 2. exe + title prefix -- same class first, so two windows of one exe
    ;    whose titles share a prefix do not swap
    if (pref != "") {
        for wnd in wins {
            if (!claimed.Has(wnd.hwnd) && wnd.exe = exe
                && SubStr(wnd.title, 1, 12) = pref
                && (cls = "" || ClsKey(wnd.cls) = cls))
                return wnd
        }
        for wnd in wins {
            if (!claimed.Has(wnd.hwnd) && wnd.exe = exe
                && SubStr(wnd.title, 1, 12) = pref)
                return wnd
        }
    }
    ; 3. exe + class + ordinal
    for wnd in wins {
        if (!claimed.Has(wnd.hwnd) && wnd.exe = exe
            && (cls = "" || ClsKey(wnd.cls) = cls)
            && wnd.ord = MGet(slot, "ord", 0))
            return wnd
    }
    ; 4. exe + class, anything left
    for wnd in wins {
        if (!claimed.Has(wnd.hwnd) && wnd.exe = exe
            && (cls = "" || ClsKey(wnd.cls) = cls))
            return wnd
    }
    return 0
}

/** Maximise a window ON a given screen (WinMaximize alone keeps its screen). */
WinMaximizeOn(id, m) {
    mm := WinGetMinMax(id)
    if (mm != 0)
        WinRestore(id)
    ; Windows maximises onto the monitor the window's GREATEST AREA is on,
    ; not the one its top-left corner is on. Moving only the corner therefore
    ; failed for a restored window wider or taller than the target screen --
    ; a 2048x1536 PowerScribe restored onto a 1920x1080 secondary still had
    ; most of itself on the neighbour, and WinMaximize sent it straight back.
    ; Shrink it to fit first (20 px of margin each side), then maximise.
    monW := Max(m.wr - m.wl, 1)
    monH := Max(m.wb - m.wt, 1)
    w := monW, h := monH
    try {
        WinGetPos(, , &cw, &ch, id)
        w := cw, h := ch
    }
    WinMove(m.wl + 20, m.wt + 20, Min(w, monW - 40), Min(h, monH - 40), id)
    WinMaximize(id)
}

/**
 * Put a layout back.
 *
 * enforce = the guard's mode: only touch windows that have actually drifted,
 * and leave minimised ones alone (the user minimised them on purpose).
 * newOnly = mode 2: only windows this guard has never placed before.
 * Returns the number of windows moved; g_LayoutAdapted says whether anything
 * had to be adapted to a different station.
 */
LayoutApplyRows(lay, enforce := false, newOnly := false) {
    global g_LayoutAdapted
    g_LayoutAdapted := false
    if !IsObject(lay)
        return 0
    wins := LayoutWindows()
    mons := StationMons()
    if (mons.Length = 0)
        return 0
    ; One StationKey for the whole pass: it is the same string for every
    ; slot, and building it per slot walked the monitor list N times over.
    skey := StationKey(mons)
    st := StationEntry(skey)
    reserved := ImagingMons(mons, StationImagingRule(st))
    exes := ImagingExes()
    claimed := Map()
    ; The mode-2 record is keyed by layout name, so two arrangements never
    ; share one "already placed" answer.
    lname := MGet(lay, "name", "")
    if !g_LayoutPlaced.Has(lname)
        g_LayoutPlaced[lname] := Map()
    placed := g_LayoutPlaced[lname]
    moved := 0
    for slot in MGet(lay, "slots", []) {
        wnd := LayoutMatch(slot, wins, claimed)
        if !IsObject(wnd)
            continue
        claimed[wnd.hwnd] := 1
        if (newOnly && placed.Has(wnd.hwnd))
            continue
        try {
            id := "ahk_id " wnd.hwnd
            ; a hung window would block this thread on every call below
            if (enforce && DllCall("user32\IsHungAppWindow", "ptr", wnd.hwnd))
                continue
            mm := WinGetMinMax(id)
            if (enforce && mm = -1)
                continue
            ; POWERSCRIBE IS NEVER RESTORED OR MOVED FROM HERE WHEN IT IS
            ; MINIMISED OR IS A DIALOG. The skill's standing rule ("do NOT
            ; call WinRestore on PS -- it un-maximizes a full-screen PS
            ; window") is about touching PS incidentally, and this loop is
            ; incidental by definition: it runs off a timer, with no report
            ; open in front of the user's eyes to say what it is about to do.
            ; A minimised PS window is minimised on purpose (the reader is in
            ; the worklist); un-minimising it mid-dictation puts the editor
            ; over the images. An owned PS window is a signing or discard
            ; prompt, and moving one out from under a click is worse than
            ; leaving it where the app put it. LayoutWindows already filters
            ; owned windows, so the owner check here is a second belt: the
            ; window can acquire a dialog between enumeration and this line.
            if IsPSExe(wnd.exe) {
                if (mm = -1)
                    continue
                ; the guard never restores a MAXIMISED PowerScribe (it runs
                ; off a timer; un-maximising PS is the standing rule's case)
                if (enforce && mm = 1)
                    continue
                psOwner := 0
                try psOwner := DllCall("user32\GetWindow", "ptr", wnd.hwnd,
                    "uint", 4, "ptr")                      ; GW_OWNER
                if psOwner
                    continue
            }
            tgt := LayoutSlotTarget(slot, lay, mons, reserved, exes, skey)
            if tgt.adapted
                g_LayoutAdapted := true
            want := MGet(slot, "state", "normal")
            sx := tgt.x, sy := tgt.y, sw := tgt.w, sh := tgt.h
            ; Only mode 2 keeps a record, and only mode 2 reads one. Mode 1
            ; snaps a window back as often as it drifts, so marking it placed
            ; meant nothing; writing on the mode-1 path merely poisoned the
            ; set for a later switch to mode 2.
            if newOnly
                placed[wnd.hwnd] := 1
            if (want = "max") {
                ; Already maximised -- but on the RIGHT screen? A maximised
                ; window that opened on the wrong display is the commonest
                ; way an arrangement is wrong, and the previous check
                ; ("maximised, so done") let exactly that stand.
                onMon := 0
                if (mm = 1) {
                    WinGetPos(&cx, &cy, &cw, &ch, id)
                    onMon := MonIndexAt(mons, cx + cw // 2, cy + ch // 2)
                }
                if (mm != 1 || onMon != tgt.mon.idx) {
                    ; Place it on the target monitor FIRST, then maximise --
                    ; WinMaximize alone maximises onto whichever screen the
                    ; window is already on, which on a four-head station is
                    ; exactly the bug this feature exists to fix.
                    WinMaximizeOn(id, tgt.mon)
                    moved += 1
                }
                continue
            }
            if (mm = 1 || mm = -1) {
                ; The standing "never WinRestore PowerScribe" rule is about
                ; restoring it INCIDENTALLY, while activating it -- doing so
                ; un-maximises a full-screen PS. Here the user captured this
                ; window as a normal-state window and asked for that state
                ; back, so restoring is the instruction, not a side effect.
                WinRestore(id)
                WinMoveSure(sx, sy, sw, sh, id)
                moved += 1
                continue
            }
            WinGetPos(&cx, &cy, &cw, &ch, id)
            if (!enforce
                || Abs(cx - sx) > LAYOUT_TOL || Abs(cy - sy) > LAYOUT_TOL
                || Abs(cw - sw) > LAYOUT_TOL || Abs(ch - sh) > LAYOUT_TOL) {
                ; Three guard moves in a row to the same rect and the window
                ; is still off it: the app refuses that rect (minimum size,
                ; DPI rounding). Moving it every 1.5 s is a fight, not a fix.
                if enforce {
                    tk := sx "," sy "," sw "," sh
                    n0 := (g_LayoutGot.Has(wnd.hwnd) && g_LayoutGot[wnd.hwnd].t = tk)
                        ? g_LayoutGot[wnd.hwnd].n : 0
                    if (n0 >= 3)
                        continue
                    g_LayoutGot[wnd.hwnd] := {t: tk, n: n0 + 1}
                }
                WinMoveSure(sx, sy, sw, sh, id, enforce)
                moved += 1
            } else if (enforce && g_LayoutGot.Has(wnd.hwnd))
                g_LayoutGot.Delete(wnd.hwnd)   ; on target: count afresh
        }
    }
    return moved
}

/**
 * Apply a named layout -- or, with no name, ASK.
 *
 * Binding this used to mean typing a layout name into the value field, which
 * is only discoverable if you already remember what you called it, and gives
 * you one binding per layout. Blank now opens a chooser at the cursor, so a
 * single input reaches every layout.
 */
LayoutApply(name) {
    if (Trim(name) = "") {
        LayoutChoose()
        return
    }
    lay := LayoutByName(name)
    if !IsObject(lay) {
        HUD("No layout named '" name "'", "warn")
        return
    }
    n := LayoutApplyRows(lay, false, false)
    name := MGet(lay, "name", name)          ; the stored spelling keys the guard
    if MGet(lay, "guard", 0)
        LayoutGuardArm(name)
    HUD("Layout '" name "' — " n " window" (n = 1 ? "" : "s") " placed"
        . (g_LayoutAdapted ? " (adapted to this station)" : ""), "cyan")
}

LayoutChoose() {
    items := []
    here := StationKey()
    for lay in MGet(g_Cfg, "layouts", []) {
        nm := MGet(lay, "name", "")
        if (nm = "")
            continue
        cnt := MGet(lay, "slots", []).Length
        g := MGet(lay, "guard", 0)
        items.Push({label: nm, key: nm,
                    sub: cnt " window" (cnt = 1 ? "" : "s")
                       . (MGet(lay, "station", "") = here ? "" : "   ·   other station")
                       . (g = 1 ? "   ·   guard armed" : (g = 2 ? "   ·   places new windows" : ""))})
    }
    if (items.Length = 0) {
        HUD("No layouts saved yet — capture one in the Windows tab", "warn")
        return
    }
    Chooser.Show("Apply window layout",
        "click a layout   ·   scroll for more   ·   Esc cancels",
        items, LayoutApply)
}

; WinMove, then once more if the window did not land where asked. A
; per-monitor-DPI app moved onto a screen with different scaling applies
; Windows' suggested rectangle on WM_DPICHANGED (1.5x the size going from
; 100% to 150%); the second move lands after that rescale.
; async = the guard's timer path: SetWindowPos with SWP_ASYNCWINDOWPOS, so a
; busy PowerScribe/PACS can never hold this thread (and every hotkey waiting
; on it). No second pass there: the next guard tick is the second pass.
WinMoveSure(x, y, w, h, id, async := false) {
    if async {
        try DllCall("user32\SetWindowPos", "ptr", WinExist(id), "ptr", 0,
            "int", x, "int", y, "int", w, "int", h, "uint", 0x4014)
        return
    }
    WinMove(x, y, w, h, id)
    try {
        WinGetPos(&ax, &ay, &aw, &ah, id)
        if (Abs(ax - x) > 2 || Abs(ay - y) > 2 || Abs(aw - w) > 2 || Abs(ah - h) > 2)
            WinMove(x, y, w, h, id)
    }
}

; hwnd -> {t: target rect, n: consecutive guard moves} (see LayoutApplyRows)
global g_LayoutGot := Map()

LayoutGuardArm(name) {
    g_LayoutGot.Clear()
    global g_LayoutGuard
    g_LayoutGuard := name
    ; Arming is a fresh start: "new windows" means new SINCE YOU ARMED IT,
    ; so a window placed during an earlier arming of the same layout is a
    ; candidate again. Without this, disarming and re-arming mode 2 did
    ; nothing at all until the windows were closed and reopened.
    g_LayoutPlaced[name] := Map()
    SetTimer(LayoutGuardTick, ClampInt(Cfg("layoutGuardMs"), 250, 60000, 1500))
}

LayoutGuardDisarm() {
    global g_LayoutGuard
    if (g_LayoutGuard != "" && g_LayoutPlaced.Has(g_LayoutGuard))
        g_LayoutPlaced.Delete(g_LayoutGuard)
    g_LayoutGuard := ""
    SetTimer(LayoutGuardTick, 0)
}

LayoutGuardTick() {
    global g_LayoutGuard, g_LayoutSnaps
    if (g_LayoutGuard = "") {
        SetTimer(LayoutGuardTick, 0)
        return
    }
    ; Never fight a drag that is in progress -- a physical one, or one the
    ; engine holds (moddrag, dragmove, the keyboard pointer's grab), nor the
    ; switcher -- and never while our own window is being resized.
    if (HandBusy() || IsObject(g_AppSw)
        || (IsSet(Warp) && (Warp.active || Warp.grabbing)))
        return
    if Atlas.resizing
        return
    ; Nor while the monitor set is changing: until StationSettled has run,
    ; the layout's screens are not all there and adapting would fold every
    ; window onto the ones that are.
    try {
        if (StationKey() != g_StationKey)
            return
    } catch
        return
    lay := LayoutByName(g_LayoutGuard)
    if !IsObject(lay) {
        LayoutGuardDisarm()
        return
    }
    mode := MGet(lay, "guard", 0)
    if (mode = 0) {
        LayoutGuardDisarm()
        return
    }
    ; The placed-set is by hwnd, and Windows RECYCLES hwnds: a closed window's
    ; handle can come back as a brand-new window, which the guard would then
    ; refuse to place because "it already did". Prune on every tick, not only
    ; past 64 entries -- the old threshold meant a two-window arrangement
    ; never pruned at all, and the recycle window is exactly that small.
    if g_LayoutPlaced.Has(g_LayoutGuard) {
        for h in g_LayoutPlaced[g_LayoutGuard].Clone() {
            if !WinExist("ahk_id " h)
                g_LayoutPlaced[g_LayoutGuard].Delete(h)
        }
    }
    n := LayoutApplyRows(lay, true, mode = 2)
    if (n > 0) {
        g_LayoutSnaps += n
        ; Traceable but silent: a HUD toast every time an application nudges
        ; a window would be its own kind of interruption. Diagnostics has it.
        Problem("layout-guard", (mode = 2 ? "Placed " : "Snapped ") n
            . " window(s) " (mode = 2 ? "into" : "back to") " '"
            . g_LayoutGuard "'")
    }
}

/** Re-arm on load / config change if a layout says it wants the guard. */
SyncLayoutGuard() {
    if (g_LayoutGuard != "") {
        lay := LayoutByName(g_LayoutGuard)
        if (IsObject(lay) && MGet(lay, "guard", 0)) {
            SetTimer(LayoutGuardTick, ClampInt(Cfg("layoutGuardMs"), 250, 60000, 1500))
            return
        }
        LayoutGuardDisarm()
        return
    }
    ; NOTHING ARMED, BUT THE CONFIG SAYS IT SHOULD BE. The guard flag lives
    ; on the layout precisely so it survives a restart -- but g_LayoutGuard
    ; is in-memory only, so after a restart the flag was set, the Windows
    ; page said "always", and nothing was actually watching until the layout
    ; was applied by hand. Arm the first layout that asks for it (only one
    ; can be armed; LayoutGuardSel already clears the others' flags).
    for lay in MGet(g_Cfg, "layouts", []) {
        if !(lay is Map)
            continue
        nm := MGet(lay, "name", "")
        if (nm != "" && MGet(lay, "guard", 0)) {
            LayoutGuardArm(nm)
            return
        }
    }
}

; --- station watch ------------------------------------------------------------
; The monitor set changes when a laptop docks, a display wakes late, a KVM
; switches, or someone logs in at a different station with a roaming profile.
; WM_DISPLAYCHANGE says so (Windows sends it to every top-level window, ours
; included); a slow poll catches the cases where it does not arrive. Either
; way the change is debounced, because Windows re-enumerates in steps and the
; first message describes a half-built desktop.

StationWatchStart() {
    global g_StationKey, g_StationStartup
    g_StationKey := StationKey()
    g_StationStartup := true
    OnMessage(0x007E, OnDisplayChange)       ; WM_DISPLAYCHANGE
    SetTimer(StationPoll, 5000)
    SetTimer(StationSettled, -Max(Cfg("stationSettleMs"), 500))
}

StationWatchStop() {
    SetTimer(StationPoll, 0)
    SetTimer(StationSettled, 0)
    try OnMessage(0x007E, OnDisplayChange, 0)
}

OnDisplayChange(wParam, lParam, msg, hwnd) {
    ; Every Warp layer is sized and positioned from a monitor rectangle that
    ; has just stopped being true, and one of them may be holding the left
    ; button down for a drag. Take it down here rather than leave a grid
    ; drawn across a screen that no longer exists.
    try Warp.Close(true)
    SetTimer(StationSettled, -Max(Cfg("stationSettleMs"), 500))
}

StationPoll() {
    try {
        if (StationKey() != g_StationKey)
            SetTimer(StationSettled, -Max(Cfg("stationSettleMs"), 500))
    }
}

/**
 * The monitor set has held still for stationSettleMs. Recognise the station
 * and apply its arrangement -- on the launch pass too, so logging in at a
 * station puts the windows that are already open where they belong (the
 * ones that open later are the mode-2 guard's job).
 */
StationSettled() {
    global g_StationKey, g_StationStartup
    ; A BOUNDED WAIT. Every interlock below re-arms the timer, and a couple
    ; of them can be true indefinitely -- a genuinely stuck mouse button, a
    ; phantom 0x0 display a driver never retires. After ~20 retries (a
    ; minute at the default settle) the pass runs anyway with the monitors
    ; it can see: deferring for ever is its own failure mode.
    static waits := 0
    ; INTERLOCKS. This pass moves several windows at once; doing that under
    ; the user's hand is the one thing a window feature must never do. Every
    ; condition below means "something is mid-gesture" -- a physical button
    ; down (a drag, a PACS pan), our own resize grip, the keyboard pointer
    ; (which may be holding LButton itself), a live radial menu or app
    ; switcher, the timing calibrator. Re-arm and ask again in a moment
    ; rather than dropping the pass: the station really has changed.
    busy := (GetKeyState("LButton", "P") || GetKeyState("RButton", "P"))
    if (!busy && Atlas.resizing)
        busy := true
    if (!busy && Warp.active)
        busy := true
    if (!busy && IsObject(g_AppSw))
        busy := true
    mons := []
    nMon := -1
    try {
        mons := StationMons()
        nMon := MonitorGetCount()
    }
    ; A zero-area monitor is a display still coming up (StationMons drops it,
    ; so a short list here means the set is still in motion). Wait it out.
    if (!busy && (mons.Length = 0 || mons.Length != nMon))
        busy := true
    if (busy && waits < 20) {
        waits += 1
        SetTimer(StationSettled, -Max(Cfg("stationSettleMs"), 500))
        return
    }
    waits := 0
    if (mons.Length = 0)
        return                               ; nothing to place windows on
    startup := g_StationStartup
    g_StationStartup := false
    key := StationKey(mons)
    changed := (key != g_StationKey)
    g_StationKey := key
    if (!changed && !startup)
        return
    ; The SCREENS CHANGED notice is not conditional on auto-apply. Auto-apply
    ; decides whether windows are moved for you; it does not decide whether
    ; you are told that the desk you are looking at is a different one, which
    ; is the fact that explains why every window is suddenly in the wrong
    ; place. Announced once per station per session, like the "no arrangement
    ; assigned" line below.
    if (changed && !Cfg("stationAuto") && !g_StationSeen.Has(key)) {
        g_StationSeen[key] := 1
        st0 := StationEntry(key)
        nm0 := IsObject(st0) ? MGet(st0, "layout", "") : ""
        HUD("Screens changed (" StationLabel(key) ") — "
            . (nm0 != "" ? ("apply “" nm0 "” on the Windows page")
                         : "auto-apply is off"), "warn")
    }
    if !Cfg("stationAuto")
        return
    st := StationEntry(key)
    name := IsObject(st) ? MGet(st, "layout", "") : ""
    lay := (name != "") ? LayoutByName(name) : 0
    if IsObject(lay) {
        n := LayoutApplyRows(lay, false, false)
        if MGet(lay, "guard", 0)
            LayoutGuardArm(MGet(lay, "name", name))
        if (n > 0 || changed)
            HUD((changed ? "Screens changed: " : "") "'" name "' — " n
                . " window" (n = 1 ? "" : "s") " placed"
                . (g_LayoutAdapted ? " (adapted)" : ""), "cyan")
        return
    }
    if (changed && !g_StationSeen.Has(key)) {
        g_StationSeen[key] := 1
        HUD("New screen setup (" StationLabel(key) ") — no arrangement "
            . "assigned; save one on the Windows page", "warn")
    }
}

; --- window placement by keystroke (v0.6.2) -----------------------------------
; The other half of not dragging windows around: send the ACTIVE window to a
; screen, and fill it. One action, a short grammar in its value:
;
;     screen:  next | prev | here | 1..9     (left to right; here = under the cursor)
;     tile:    max | left | right | top | bottom | tl | tr | bl | br | keep | restore
;
; Any order, both optional. "next" alone keeps the window's shape on the next
; screen; "max" alone fills the screen it is on (and again restores it);
; "here max" fills the screen the pointer is on; "2 left" is the left half of
; screen 2. Unknown words are refused, not guessed.

/** Parse a winplace value into {screen, tile, err}. Pure. */
WinPlaceParse(v) {
    static TILES := Map("max", 1, "fill", 1, "left", 1, "right", 1, "top", 1,
        "bottom", 1, "tl", 1, "tr", 1, "bl", 1, "br", 1, "keep", 1, "restore", 1)
    screen := ""
    tile := ""
    for tok in StrSplit(Trim(StrLower(String(v))), [" ", ",", "/"]) {
        tok := Trim(tok)
        if (tok = "")
            continue
        if (tok = "next" || tok = "prev" || tok = "here"
            || (IsInteger(tok) && Integer(tok) >= 1 && Integer(tok) <= 9)) {
            if (screen != "")
                return {screen: "", tile: "", err: "two screens: " tok}
            screen := tok
            continue
        }
        if !TILES.Has(tok)
            return {screen: "", tile: "", err: "unknown word: " tok}
        if (tile != "")
            return {screen: "", tile: "", err: "two tiles: " tok}
        tile := (tok = "fill") ? "max" : tok
    }
    if (tile = "")
        tile := "keep"
    return {screen: screen, tile: tile, err: ""}
}

/**
 * THE INVISIBLE BORDER. Since Vista a resizable window's WinGetPos rectangle
 * is several pixels larger on the left, right and bottom than the frame you
 * can see -- that margin is the drop shadow and the grab area, and it is not
 * painted. Tile two windows side by side using those numbers and there is a
 * visible ~14 px gutter between them and a strip of desktop down the screen
 * edge, which is exactly the complaint "half screen doesn't actually fill
 * half the screen". DWMWA_EXTENDED_FRAME_BOUNDS (9) reports the VISIBLE
 * bounds; the difference is the slack. Measured once per placement (it is a
 * cross-process DWM call), try-wrapped, and zero on anything that refuses --
 * in which case the behaviour is exactly what it was before.
 */
WinFrameSlack(id) {
    out := {l: 0, t: 0, r: 0, b: 0}
    try {
        hwnd := WinExist(id)
        if !hwnd
            return out
        rc := Buffer(16, 0)
        if (DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "int", 9,
                    "ptr", rc, "int", 16) != 0)
            return out
        WinGetPos(&wx, &wy, &ww, &wh, id)
        el := NumGet(rc, 0, "int"), et := NumGet(rc, 4, "int")
        er := NumGet(rc, 8, "int"), eb := NumGet(rc, 12, "int")
        if (er - el <= 0 || eb - et <= 0)
            return out
        ; Clamped: a cloaked or mid-animation window can report nonsense, and
        ; a 200 px "border" would throw the window off the screen entirely.
        out.l := Min(Max(el - wx, 0), 32)
        out.t := Min(Max(et - wy, 0), 32)
        out.r := Min(Max((wx + ww) - er, 0), 32)
        out.b := Min(Max((wy + wh) - eb, 0), 32)
    }
    return out
}

/**
 * The tile rectangle on a screen's work area. Pure.
 *
 * `slack` (from WinFrameSlack) grows the rectangle outwards by the invisible
 * border, so the VISIBLE edges land on the work area. Omitted = no
 * compensation, which is the old behaviour and what the tests assert.
 */
WinTileRect(m, tile, slack := 0) {
    ww := m.wr - m.wl
    wh := m.wb - m.wt
    hw := ww // 2
    hh := wh // 2
    if IsObject(slack) {
        r := WinTileRect(m, tile)
        return {x: r.x - slack.l, y: r.y - slack.t,
                w: r.w + slack.l + slack.r, h: r.h + slack.t + slack.b}
    }
    switch tile {
        case "left":   return {x: m.wl, y: m.wt, w: hw, h: wh}
        case "right":  return {x: m.wl + hw, y: m.wt, w: ww - hw, h: wh}
        case "top":    return {x: m.wl, y: m.wt, w: ww, h: hh}
        case "bottom": return {x: m.wl, y: m.wt + hh, w: ww, h: wh - hh}
        case "tl":     return {x: m.wl, y: m.wt, w: hw, h: hh}
        case "tr":     return {x: m.wl + hw, y: m.wt, w: ww - hw, h: hh}
        case "bl":     return {x: m.wl, y: m.wt + hh, w: hw, h: wh - hh}
        case "br":     return {x: m.wl + hw, y: m.wt + hh, w: ww - hw, h: wh - hh}
    }
    return {x: m.wl, y: m.wt, w: ww, h: wh}
}

WinPlace(v) {
    p := WinPlaceParse(v)
    if (p.err != "") {
        HUD("Window action: " p.err, "warn")
        return
    }
    hwnd := 0
    try hwnd := WinExist("A")
    if (!hwnd || g_OurHwnds.Has(hwnd)) {
        HUD("No application window is active", "warn")
        return
    }
    id := "ahk_id " hwnd
    try {
        cls := WinGetClass(id)
        if (cls = "Shell_TrayWnd" || cls = "Progman" || cls = "WorkerW") {
            HUD("The desktop is active, not a window", "warn")
            return
        }
        mons := StationMons()
        n := mons.Length
        if (n = 0)
            return
        mm := WinGetMinMax(id)
        if (mm = -1) {                       ; minimised: its rect is -32000
            WinRestore(id)
            mm := WinGetMinMax(id)
        }
        WinGetPos(&x, &y, &w, &h, id)
        cur := MonIndexAt(mons, x + w // 2, y + h // 2)
        switch p.screen {
            case "":     tgt := cur
            case "next": tgt := Mod(cur, n) + 1
            case "prev": tgt := Mod(cur - 2 + n, n) + 1
            case "here":
                RM_GetPos(&cx, &cy)
                tgt := MonIndexAt(mons, cx, cy)
            default:     tgt := Min(Max(Integer(p.screen), 1), n)
        }
        m := mons[tgt]
        tile := p.tile
        if (tile = "restore") {
            if (mm != 0)
                WinRestore(id)
            HUD("Window restored", "cyan")
            return
        }
        if (tile = "max") {
            if (mm = 1 && tgt = cur && p.screen = "") {
                WinRestore(id)                ; "max" again = give it back
                HUD("Window restored", "cyan")
                return
            }
            WinMaximizeOn(id, m)
            HUD("Window fills screen " tgt, "cyan")
            return
        }
        if (tile = "keep") {
            if (tgt = cur) {
                HUD("Already on screen " tgt, "mute")
                return
            }
            if (mm = 1) {                    ; maximised there = maximised here
                WinMaximizeOn(id, m)
                HUD("Window fills screen " tgt, "cyan")
                return
            }
            src := mons[cur]
            sww := Max(src.wr - src.wl, 1)
            swh := Max(src.wb - src.wt, 1)
            dww := m.wr - m.wl
            dwh := m.wb - m.wt
            nw := Min(w, dww)
            nh := Min(h, dwh)
            nx := m.wl + Round((x - src.wl) / sww * dww)
            ny := m.wt + Round((y - src.wt) / swh * dwh)
            nx := Min(Max(nx, m.wl), m.wr - nw)
            ny := Min(Max(ny, m.wt), m.wb - nh)
            if (mm = -1)
                WinRestore(id)
            WinMoveSure(nx, ny, nw, nh, id)
            HUD("Window moved to screen " tgt, "cyan")
            return
        }
        if (mm != 0)
            WinRestore(id)
        ; AFTER the restore: a maximised window's frame slack is not the
        ; restored window's, and the restore is what makes the measurement
        ; true. One DWM call per placement.
        r := WinTileRect(m, tile, WinFrameSlack(id))
        WinMoveSure(r.x, r.y, r.w, r.h, id)
        HUD("Window: " tile " of screen " tgt, "cyan")
    } catch as e {
        Problem("winplace", "window placement failed: " e.Message)
        HUD("Could not move that window", "warn")
    }
}


; ── §8  POWERSCRIBE DELIVERY (proven pattern from radiology_hotkeys) ────────

PSActive() {
    for exe in g_Cfg["psExes"] {
        if WinActive("ahk_exe " exe)
            return true
    }
    return false
}

; Activate PowerScribe BY EXE, never a specific hwnd (skill §2). PowerScribe One
; is multi-window; the report editor that receives {F4}/{Tab}/+{Tab} is whichever
; PS window was LAST active, not the biggest. WinActivate("ahk_exe ...") brings
; that window forward and restores its focused control, so the keystroke lands in
; the editor. The old "largest visible window" heuristic could raise the wrong PS
; window (ribbon, dictation bar, navigator), so keys went nowhere unless PS was
; already focused -- exactly the reported "only works when PS is focused" bug.
; Returns the exe match string for the first running PS exe, or "" if none.
PSMatch() {
    for exe in g_Cfg["psExes"] {
        if WinExist("ahk_exe " exe)
            return "ahk_exe " exe
    }
    return ""
}

/**
 * Is this exe PowerScribe? The same list PSActive() and PSMatch() use, asked
 * about a name rather than about the foreground -- for the window-layout
 * code, which holds an hwnd and its exe and has to know before it touches
 * it. BY EXE, never by class or title: PowerScribe's class carries a
 * per-launch GUID and its title carries the patient.
 */
IsPSExe(exe) {
    exe := StrLower(Trim(String(exe)))
    if (exe = "")
        return false
    for e in MGet(g_Cfg, "psExes", [])
        if (StrLower(Trim(String(e))) = exe)
            return true
    return false
}

PSFire(keys) {
    RM_PSFire(keys)
}

; "PACS: send keys" -- the PowerScribe routing, pointed at the PACS profile.
; Same queue, same drain loop, same rules: if the app is already in front
; the keys just go; otherwise it is brought forward BY ITS PROFILE MATCH
; (exe, never a handle), the keys land, and focus returns to where you
; were. So a radial slice or a thumb button can drive the viewer while the
; report editor keeps the cursor.
PACSFire(keys) {
    global g_PSQueue
    if (g_PSQueue.Length >= 16) {
        ; The cap is a runaway backstop, but a silent drop is a keypress the
        ; reader watched go nowhere with no explanation. Say so.
        Problem("ps-queue", "delivery queue full (16) -- dropped PACS keys: "
            . keys)
        HUD("Too many queued keypresses — that one was dropped", "warn")
        return
    }
    g_PSQueue.Push({app: Cfg("pacsApp"), keys: keys})
    SetTimer(PSDrain, -1)
}

; Every WinTitle criterion that names the app profile, preferred window
; first: the Apps-tab match entries, each optionally narrowed by the title
; substring in pacsWindow (IntelliSpace has a worklist AND a viewer under one
; exe; F7/F8 belong to the viewer).
; Returns {pref, all}: `pref` is only the criteria narrowed by the preferred
; title, `all` is those followed by the bare ones (activation order --
; prefer the viewer, settle for any window of the app). They are SEPARATE
; because "is it already in front?" and "what should I bring forward?" are
; different questions. IntelliSpace's worklist and viewer share one exe, so
; a bare "ahk_exe IntelliSpacePACSRadiology.exe" is TRUE while the worklist
; is focused -- and the already-active fast path then fired F7/F8 straight
; into the worklist, which has its own bindings for them (it renamed a
; column, it did not window/level anything). With a preferred title set, only
; the preferred criteria may take that fast path.
AppCrits(appName, prefer := "") {
    pref := []
    bare := []
    for app in MGet(g_Cfg, "apps", []) {
        if (MGet(app, "name", "") != appName)
            continue
        for m in MGet(app, "match", []) {
            crit := MatchCrit(m)
            if (prefer != "" && SubStr(crit, 1, 4) = "ahk_")
                pref.Push(prefer " " crit)    ; "VirtualMonitor ahk_exe X"
        }
        for m in MGet(app, "match", [])
            bare.Push(MatchCrit(m))
    }
    all := []
    for c in pref
        all.Push(c)
    for c in bare
        all.Push(c)
    return {pref: pref, all: all}
}

; The keystroke itself, and ONLY the keystroke, uninterruptible. A hook thread
; that runs between the "+" and the "{Tab}" of a "+{Tab}" emits its own
; "{Blind}{...Down}" inside our modifier: that is the shift-click, and the
; Shift left logically down behind it. The WinWaitActive and the Sleeps
; around the send stay interruptible on purpose (see the design note above
; RM_PSFireReal). SafeSend swallows its own errors; the finally is there
; because a Critical left ON would cost far more than the two lines.
; (Ported from the 0.6.6.5 line, where it fixed the same dead left click.)
PSSendAtomic(keys) {
    Critical "On"
    try {
        SafeSend(keys)
    } finally {
        Critical "Off"
    }
}

; A delivery must never run THROUGH a click. Field navigation sends "+{Tab}",
; and a mouse button that changes state inside that send goes out carrying
; the Shift the send still has down: the click lands shift-modified, in
; PowerScribe rather than where the pointer is, and its Up arrives after focus
; has gone back to PACS. What is left behind is a Shift that is logically
; down with the key physically up (every later click is a shift-click) and an
; orphan left-button down that the engine's own bookkeeping knows nothing
; about -- clicks "freeze" until Panic. So a delivery WAITS while a mouse
; button is physically held AND its press could still put a native down or
; up on the wire, and the keys go back to the FRONT of the queue so order is
; kept. PSDrain's HandBusy check covers the moment the drain starts; this one
; runs per delivery, so a click that starts between two queued deliveries
; (a ps_next burst) is covered too.
;
; BOUNDED: after PS_DEFER_MS of continuous deferral the keys go out anyway.
PSDeferForButtons(entry) {
    global g_PSQueue
    static since := 0, sinceGen := -1
    static PS_DEFER_MS := 1500
    ; A deferral the queue was dropped under (panic, pause) must not leave
    ; its start time behind: the next delivery during a click would read
    ; it as "waited long enough" and send straight through the click.
    if (sinceGen != g_PSGen) {
        since := 0
        sinceGen := g_PSGen
    }
    gen := g_PSGen
    held := false
    for b in BUTTONS {
        if !GetKeyState(b, "P")
            continue
        ; A press the engine has already SETTLED owes the OS nothing: "held"
        ; and "fired" have delivered, "armedmod" is a silent layer host, and
        ; a consumed state is inert. Counting those would make a hold-bound
        ; field-nav action defer its own keystroke for the full 1.5 s. The
        ; hazards are "pending", "passthru" and NO STATE (the native left
        ; click).
        st := BS(b)
        if (st && (st.consumed || st.mode = "held" || st.mode = "fired"
            || st.mode = "armedmod"))
            continue
        held := true
        break
    }
    if !held {
        since := 0
        return false
    }
    now := A_TickCount
    if (since = 0)
        since := now
    else if (now - since >= PS_DEFER_MS || now < since) {
        since := 0                           ; deliver anyway; fresh window
        Problem("ps-defer", "delivered after " PS_DEFER_MS " ms with a mouse"
            . " button still held")
        return false
    }
    if (g_PSGen != gen)                      ; panic fired: drop these keys
        return true
    g_PSQueue.InsertAt(1, entry)             ; front, not back: FIFO survives
    SetTimer(PSDrain, -100)
    return true
}

AppDeliverNow(appName, keys) {
    if PSDeferForButtons({app: appName, keys: keys})
        return "defer"                       ; re-queued; PSDrain stops draining
    gen := g_PSGen
    prefer := (appName = Cfg("pacsApp")) ? Cfg("pacsWindow") : ""
    cr := AppCrits(appName, prefer)
    crits := cr.all
    if (crits.Length = 0) {
        Problem("app-missing", "No '" appName "' profile on the Apps tab")
        HUD("No " appName " profile on the Apps tab", "warn")
        return
    }
    ; Already-active fast path. When a preferred window title exists, ONLY the
    ; preferred criteria count as "already there": the bare exe match is also
    ; true for the PACS WORKLIST, and sending viewer keys to the worklist is
    ; how F7/F8 ended up editing the list instead of the images. With no
    ; preference set the two lists are identical and nothing changes.
    fast := (prefer != "" && cr.pref.Length > 0) ? cr.pref : crits
    for crit in fast {
        if WinActive(crit) {
            PSSendAtomic(keys)
            return
        }
    }
    win := ""
    ; Activation order is unchanged: the preferred (viewer) criteria first,
    ; then any window of the app -- better to raise the worklist and send
    ; there than to send nothing at all.
    for crit in crits {
        if WinExist(crit) {
            win := crit
            break
        }
    }
    if (win = "") {
        Problem("app-missing", appName " window not found")
        HUD(appName " window not found", "warn")
        return
    }
    prev := WinExist("A")
    try {
        if (WinGetMinMax(win) = -1)              ; only when MINIMIZED
            WinRestore(win)
    }
    try WinActivate(win)
    if !WinWaitActive(win, , 0.5) {
        try WinActivate(win)                     ; foreground lock: one retry
        if !WinWaitActive(win, , 0.5) {
            if (g_PSGen = gen && WinExist(win)) {
                ; No ControlSend fallback: WPF drops posted keys, and a
                ; modifier sent that way can stick in the active window.
                Problem("app-blocked", appName " would not come forward;"
                    . " keys not sent: " keys)
                HUD(appName " would not come forward — press it again", "warn")
            }
            return
        }
    }
    if (g_PSGen != gen) {
        if prev
            try WinActivate("ahk_id " prev)
        return
    }
    Sleep(50)
    ; The thread is interruptible across the waits above: a click back into
    ; the viewer in that moment must not receive the keys.
    Critical "On"
    ok := (g_PSGen = gen) && WinActive(win)
    if ok
        PSSendAtomic(keys)
    Critical "Off"
    if !ok {
        Problem("ps-focus", "focus moved before the keys were sent; not sent: " keys)
        return
    }
    if prev {
        Sleep(Cfg("psReturnDelay"))
        if WinActive(win)                      ; not if the user has moved on
            try WinActivate("ahk_id " prev)
    }
}

; Production delivery is DEFERRED to a timer thread. The engine entry points
; run Critical: doing WinActivate/WinWaitActive inside the hook thread both
; stalls the input pipeline for up to a second and is exactly where Windows'
; foreground lock likes to deny the focus switch (workstation finding: a
; globally bound dictate only fired when PS was already focused, because the
; denied activation hit the silent WinWaitActive-timeout return). The timer
; thread runs interruptible, retries the activation once, and falls back to
; background delivery instead of silently dropping the action.
RM_PSFireReal(keys) {
    global g_PSQueue
    if (g_PSQueue.Length >= 16) {    ; runaway-macro backstop; no human
        Problem("ps-queue", "delivery queue full (16) -- dropped PowerScribe"
            . " keys: " keys)        ; outruns the drain loop, so a full queue
        HUD("Too many queued keypresses — that one was dropped", "warn")
        return                       ; means something is misbehaving: never
    }                                ; drop it silently
    g_PSQueue.Push(keys)
    SetTimer(PSDrain, -1)
}

; Serialize deliveries: rapid presses must all land, in order (dictate toggle
; semantics; ps_next/ps_prev bursts), never interleaving two activation
; dances. One drain loop owns delivery; pushes that arrive mid-delivery are
; picked up by the running loop's next while-check.
; True while the hand is mid-gesture on a button. The physical test alone is
; not enough: a KEY-hosted moddrag or native hold has LButton down
; SYNTHETICALLY, which reads as up under "P". Nothing may send keystrokes or
; steal the foreground while one of these is out.
HandBusy() {
    if (GetKeyState("LButton", "P") || GetKeyState("RButton", "P"))
        return true
    for name, st in g_BS {
        if (!st.down || st.consumed)
            continue
        btn := (st.passBtn != "" ? st.passBtn : name)
        if (st.mode = "passthru" && IsMouseInput(btn))
            return true
        if (st.mode = "held" && IsObject(st.holdBinding)) {
            t := st.holdBinding["action"]["type"]
            if (t = "moddrag" || (t = "dragmove" && st.dragOn)
                || (IsNativeAct(t) && IsMouseInput(btn)))
                return true
        }
    }
    return false
}

PSDrain() {
    global g_PSBusy, g_PSQueue, g_PSDefer, g_PSGen
    if g_PSBusy
        return
    if !g_Enabled {                          ; paused: input is native, and
        g_PSQueue := []                      ; nothing of ours may land in
        g_PSDefer := 0                       ; the study
        g_PSGen += 1
        return
    }
    ; Never activate another window or send keys under the user's hand -- a
    ; W/L sweep, a marquee, a moddrag. Bounded at ~1.5 s: a click lock is a
    ; deliberate indefinite latch and must not strand the queue for ever.
    if (HandBusy() && g_PSDefer < 50) {
        g_PSDefer += 1
        SetTimer(PSDrain, -30)
        return
    }
    g_PSDefer := 0
    g_PSBusy := true
    deferred := false
    try {
        while (g_PSQueue.Length > 0) {
            keys := ""
            try keys := g_PSQueue.RemoveAt(1)
            catch                    ; panic swapped/cleared the queue between
                break                ; the while-check and this line
            if IsObject(keys)                ; an app-targeted delivery
                r := AppDeliverNow(keys.app, keys.keys)
            else
                r := PSDeliverNow(keys)
            ; A deferred delivery put its keys back at the FRONT and re-armed
            ; this timer at 100 ms. Stop, or the loop picks the same entry
            ; straight back up and spins on it until the button comes up.
            if (r = "defer") {
                deferred := true
                break
            }
        }
    } finally {
        g_PSBusy := false
    }
    if (!deferred && g_PSQueue.Length > 0)   ; a push can interleave between
        SetTimer(PSDrain, -1)                ; the last while-check and the
                                             ; unlock above (NOT after a
                                             ; deferral: -1 would replace its
                                             ; 100 ms retry and spin)
}

PSDeliverNow(keys) {
    if PSDeferForButtons(keys)   ; never send through a click -- see the note
        return "defer"           ; on PSDeferForButtons
    gen := g_PSGen               ; panic mid-flight bumps this: abort unsent
    if PSActive() {
        PSSendAtomic(keys)
        return
    }
    psWin := PSMatch()
    if (psWin = "") {
        Problem("ps-missing", "PowerScribe window not found (check Settings > PS process names)")
        HUD("PowerScribe window not found - check Settings > PS process names")
        return
    }
    prev := WinExist("A")
    try {
        if (WinGetMinMax(psWin) = -1)            ; only when MINIMIZED -- never
            WinRestore(psWin)                    ; WinRestore a maximized PS window
    }                                            ; (that would un-maximize it)
    try WinActivate(psWin)
    if !WinWaitActive(psWin, , 0.5) {
        try WinActivate(psWin)                   ; foreground lock: one retry
        if !WinWaitActive(psWin, , 0.5) {
            if (g_PSGen = gen && WinExist(psWin)) {
                ; No ControlSend fallback: WPF drops posted keys, and a
                ; modifier sent that way can stick in the active window.
                Problem("ps-blocked", "PowerScribe would not come forward;"
                    . " keys not sent: " keys)
                HUD("PowerScribe would not come forward — press it again",
                    "warn")
            }
            return
        }
    }
    if (g_PSGen != gen) {            ; panic fired while we were waiting: do
        if prev                      ; not send, just put focus back
            try WinActivate("ahk_id " prev)
        return
    }
    Sleep(50)
    ; The thread is interruptible across the waits above: a click back into
    ; the viewer in that moment must not receive the keys.
    Critical "On"
    ok := (g_PSGen = gen) && WinActive(psWin)
    if ok
        PSSendAtomic(keys)
    Critical "Off"
    if !ok {
        Problem("ps-focus", "focus moved before the keys were sent; not sent: " keys)
        return
    }
    if prev {
        Sleep(Cfg("psReturnDelay"))
        if WinActive(psWin)                  ; not if the user has moved on
            try WinActivate("ahk_id " prev)
    }
}

; Macros need each PS step COMPLETED before the next step runs (v0.5 ran
; delivery synchronously inside the step loop; the v0.6 queue is async).
; The macro thread is interruptible, so PSDrain's timer thread runs during
; these Sleeps; we just wait for it to go idle. Bounded ~3 s. In the rig the
; RM_PSFire shim captures synchronously and the queue stays empty, so this
; returns on the first check.
PSMacroSync() {
    loop 120 {
        if (g_PSQueue.Length = 0 && !g_PSBusy)
            return
        Sleep(25)
    }
}


; ── §9  MACROS ──────────────────────────────────────────────────────────────

FocusApp(name) {
    for app in g_Cfg["apps"] {
        if (app["name"] != name)
            continue
        for m in MGet(app, "match", []) {
            crit := MatchCrit(m)
            if WinExist(crit) {
                try WinActivate(crit)
                return WinWaitActive(crit, , 1) ? true : false
            }
        }
    }
    return false
}

RunMacro(name, *) {
    global g_MacroBusy
    if g_MacroBusy
        return
    macros := g_Cfg["macros"]
    if !macros.Has(name) {
        Problem("macro-missing", "Macro not found: " name)
        HUD("Macro not found: " name)
        return
    }
    g_MacroBusy := true
    gen := g_MacroGen                        ; panic bumps this: stop the rest
    try {
        for step in macros[name] {
            if (g_MacroGen != gen)           ; checked at BOTH ends of the body
                break                        ; so a step that slept is caught
            t := MGet(step, "type", "")
            v := MGet(step, "value", "")
            switch t {
                case "keys":
                    SafeSend(v)
                case "text":
                    RM_SendText(v)
                case "sleep":
                    Sleep(IsInteger(v) ? Min(Max(Integer(v), 0), 5000) : 100)
                case "psdictate":
                    PSFire(Cfg("psDictateKey"))
                    PSMacroSync()            ; step order: PS lands before the
                case "psnext":               ; next step (delivery is async)
                    PSFire("{Tab}")
                    PSMacroSync()
                case "psprev":
                    PSFire("+{Tab}")
                    PSMacroSync()
                case "pskeys":
                    PSFire(v)
                    PSMacroSync()
                case "pacskeys":
                    PACSFire(v)
                    PSMacroSync()
                case "focus":
                    ; the next step would type into whatever IS in front
                    if !FocusApp(v) {
                        Problem("macro-focus", "Macro " name ": could not focus " v)
                        HUD("Macro stopped: " v " would not come forward", "warn")
                        break
                    }
                case "run":
                    try Run(v)
                    catch as e {
                        Problem("run", "Run failed: " v " — " e.Message)
                        HUD("Could not start: " v, "warn")
                    }
                case "teleport":
                    DoTeleport(v)
                case "tooltip":
                    HUD(v)
            }
            ; The macro thread is interruptible: panic can land inside a
            ; Sleep or a PSMacroSync wait, and the switch above returns to
            ; here none the wiser. This is the check that catches that.
            if (g_MacroGen != gen)
                break
        }
    } catch as e {
        Problem("macro-error", "Macro step failed: " e.Message)
        HUD("Macro error: " e.Message)
    } finally {
        g_MacroBusy := false
    }
}


; ── §10  HOOK & KEYBOARD-HOTKEY MANAGEMENT ──────────────────────────────────

; An input is hooked only while something in the config references it, so
; unreferenced buttons (LButton/MButton by default) and every unbound key stay
; completely native.
SyncHooks() {
    global g_BadKeyWarned                    ; declared here, not in the try
    HookChanged()
    needed := Map()
    needed.CaseSense := "Off"                ; hand-edited "xbutton1" must
    if g_Enabled {                           ; still hook XButton1
        for row in g_Cfg["bindings"] {
            if IsInertRow(row)               ; display-only default rows never
                continue                     ; cost a hook
            needed[CanonicalInputName(NormalizeInputName(MGet(row, "button", "")))] := 1
            for part in LayerParts(row)      ; layer-host inputs must be hooked
                needed[CanonicalInputName(NormalizeInputName(part))] := 1  ; so holding arms
            ; A click-lock row has to hook what it can LATCH, not just its own
            ; input: an unhooked button's physical release reaches the OS and
            ; undoes the latch the instant you let go (v0.3.1).
            if (MGet(row["action"], "type", "") = "clicklock") {
                lv := ResolveInputValue(MGet(row["action"], "value", ""))
                if IsMouseInput(lv)
                    needed[lv] := 1
                else {
                    for b in BUTTONS
                        needed[b] := 1
                }
            }
        }                                    ; the layer
    } else {
        ; v0.7.2: a "Toggle engine pause" row is a TOGGLE, so its input stays
        ; hooked while paused -- otherwise it could pause but never resume.
        for row in g_Cfg["bindings"] {
            if (MGet(MGet(row, "action", Map()), "type", "") = "pausetgl")
                needed[CanonicalInputName(NormalizeInputName(MGet(row, "button", "")))] := 1
        }
    }
    ; Each Hotkey toggle is wrapped: a throw mid-reconfigure must never leave an
    ; input SUPPRESSED with no live handler (a dead/frozen click, or a keyboard
    ; that eats a character). On failure we roll back to fully native and keep
    ; g_HookState matching reality, so a later SyncHooks can still repair it --
    ; and the failure is funnelled, not silent. (Workstation: "clicks froze
    ; after I changed an assignment.")
    ; The mouse section runs under HotIf(HookActive) -- the mouse hooks are
    ; POSITIONAL: native over our own windows. The keyboard section runs under
    ; HotIf(KbHookActive) instead, which is FOREGROUND-based (v0.3: see
    ; KbHookActive -- keys have nothing to do with where the pointer is).
    ; On/Off toggles must run under the SAME context they were created in, so
    ; each wraps its own branch; finally clears the context so
    ; RegisterKbHotkeys (next) registers global hotkeys.
    HotIf(HookActive)
    try {
    for btn in BUTTONS {
        want := needed.Has(btn)
        have := g_HookState.Has(btn)
        if (want && !have) {
            try {
                Hotkey("*" btn, OnPressHK.Bind(btn), "On")
                Hotkey("*" btn " Up", OnReleaseHK.Bind(btn), "On")
                g_HookState[btn] := 1
            } catch as e {
                ; roll back to fully native -- never leave *btn suppressing
                ; with no Up handler. g_HookState was never set (its assignment
                ; is the try's last line), so there is nothing to remove and a
                ; Delete here would itself throw (Map.Delete on a missing key).
                try Hotkey("*" btn, "Off")
                try Hotkey("*" btn " Up", "Off")
                Problem("hook-error", "could not hook " btn ": " e.Message)
            }
        } else if (!want && have) {
            try {
                Hotkey("*" btn, "Off")
                Hotkey("*" btn " Up", "Off")
            } catch as e {
                Problem("hook-error", "could not unhook " btn ": " e.Message)
            }
            g_HookState.Delete(btn)
        }
    }
    for wh in WHEELS {
        want := needed.Has(wh)
        have := g_HookState.Has(wh)
        if (want && !have) {
            try {
                ; T4, not the #MaxThreadsPerHotkey directive: that only
                ; reaches hotkeys written into the source, and every hook
                ; here is created at RUNTIME. Without it the wheel keeps
                ; AutoHotkey's default of one thread, and a notch arriving
                ; while the previous is still resolving is discarded.
                Hotkey("*" wh, OnWheelHK.Bind(wh), "On T4")
                g_HookState[wh] := 1
            } catch as e {
                try Hotkey("*" wh, "Off")        ; g_HookState never set (see btn loop)
                Problem("hook-error", "could not hook " wh ": " e.Message)
            }
        } else if (!want && have) {
            try {
                Hotkey("*" wh, "Off")
            } catch as e {
                Problem("hook-error", "could not unhook " wh ": " e.Message)
            }
            g_HookState.Delete(wh)
        }
    }
    } finally {
        HotIf()
    }
    ; --- keyboard keys ------------------------------------------------------
    ; BUTTONS/WHEELS can be reconciled by walking a fixed list; keys cannot --
    ; there is no list. So the WANTED set is read out of `needed` and the HELD
    ; set out of g_HookState. Invariant 1 is unchanged and now matters more: a
    ; key nothing references is never hooked, so a stock config leaves the
    ; keyboard completely untouched and typing keeps its native latency.
    ; Each key is registered under EVERY name it can arrive as (InputHookNames
    ; -- the NumLock twin for numpad keys), all bound to the SAME canonical
    ; name, so one row works whether NumLock is on or off and the state
    ; machine still sees a single input.
    HotIf(KbHookActive)
    try {
    bad := ""
    for name in needed {
        if (!IsKeyInput(name) || g_HookState.Has(name))
            continue
        if !KeyNameValid(name) {             ; braces, a combo, or a typo: say
            bad .= (bad = "" ? "" : ", ") name        ; so, never fail silently
            Problem("bad-key", "'" name "' is not a key AutoHotkey can hook"
                . " -- the row does nothing. Edit it in the Keyboard tab.")
            continue
        }
        done := []
        ok := true
        for hk in InputHookNames(name) {
            try {
                Hotkey("*" hk, OnPressHK.Bind(name), "On")
                Hotkey("*" hk " Up", OnReleaseHK.Bind(name), "On")
                done.Push(hk)
            } catch as e {
                ok := false
                Problem("hook-error", "could not hook key " hk ": " e.Message)
                break
            }
        }
        if ok
            g_HookState[name] := 1
        else {
            for hk in done {                 ; same rollback contract as the
                try Hotkey("*" hk, "Off")    ; button loop: never leave a key
                try Hotkey("*" hk " Up", "Off")   ; suppressed with no handler
            }
            bad .= (bad = "" ? "" : ", ") name
        }
    }
    stale := []                              ; collect first: deleting from a
    for name in g_HookState                  ; Map while iterating it is unsafe
        if (IsKeyInput(name) && !needed.Has(name))
            stale.Push(name)
    for name in stale {
        for hk in InputHookNames(name) {
            try {
                Hotkey("*" hk, "Off")
                Hotkey("*" hk " Up", "Off")
            } catch as e {
                Problem("hook-error", "could not unhook key " hk ": " e.Message)
            }
        }
        g_HookState.Delete(name)
    }
    ; The v0.2 failure mode was SILENT: a key that could not be hooked just
    ; did nothing, with the reason buried in Diagnostics. Say it out loud
    ; once per sync instead.
    if (bad != "" && bad != g_BadKeyWarned) {
        TrayTip("These key bindings could not be hooked and will do nothing: "
            . bad . "`nOpen the Keyboard tab and re-pick the key.",
            "RadMapper", "Iconx")
    }
    g_BadKeyWarned := bad
    } finally {
        HotIf()                              ; clear context: later Hotkey() calls are global
    }
}


; A Settings hotkey naming a mouse input registers a SECOND hotkey on an
; input the engine hooks as "*X" -- two registrations on one physical input,
; with the non-wildcard variant preferred when it matches exactly (observed
; on the workstation: teleport-on-tilt starved every Mappings row on that
; tilt). Mouse inputs belong in Mappings, where context arbitration
; (app / layer / while / mods) works; keyboard combos stay here. Checks each
; side of an "&" custom combo (a mouse PREFIX key loses its native click
; too) and drops any trailing "Up" release suffix before comparing.
IsMouseHotkey(hk) {
    for part in StrSplit(hk, "&") {
        s := part
        for ch in ["*", "~", "$", "<", ">", "^", "!", "+", "#"]
            s := StrReplace(s, ch)
        s := Trim(s)
        if (StrLen(s) > 3 && SubStr(s, -3) = " up")
            s := Trim(SubStr(s, 1, StrLen(s) - 3))
        for b in BUTTONS {
            if (s = b)
                return true
        }
        for w in WHEELS {
            if (s = w)
                return true
        }
    }
    return false
}

; The KEY equivalent of IsMouseHotkey (v0.3). "F13" (a Settings hotkey) and
; "*F13" (an engine hook) are different hotkeys, and AHK prefers the EXACT
; match -- so an unmodified Settings hotkey on a key that Mappings also binds
; starves that row, exactly as teleport-on-tilt starved the tilt rows. Only
; an UNMODIFIED settings hotkey conflicts: "^!q" is more specific than "*q"
; and legitimately wins for that one combo. Returns the clashing input name,
; or "".
KbHotkeyConflict(hk) {
    s := Trim(hk)
    if (s = "" || InStr(s, "&"))             ; a custom combo has its own
        return ""                            ; prefix-key semantics: leave it
    for ch in ["^", "!", "+", "#", "<", ">"] {
        if InStr(s, ch)                      ; modified: cannot starve "*key"
            return ""
    }
    for ch in ["*", "~", "$"]
        s := StrReplace(s, ch)
    s := Trim(s)
    if (StrLen(s) > 3 && SubStr(s, -3) = " up")
        s := Trim(SubStr(s, 1, StrLen(s) - 3))
    s := CanonicalInputName(s)
    return g_HookState.Has(s) ? s : ""
}

global g_BadHkWarned := "|"
RegisterKbHotkeys() {
    global g_KbRegistered
    if IsObject(g_RecHook)
        return                               ; mid-recording; re-armed on finish
    for hk in g_KbRegistered {
        try Hotkey(hk, "Off")
    }
    g_KbRegistered := []
    pairs := [
        [Cfg("hkDictate"),   (*) => PSFire(Cfg("psDictateKey"))],
        [Cfg("hkPrevField"), (*) => PSFire("+{Tab}")],
        [Cfg("hkNextField"), (*) => PSFire("{Tab}")],
        [Cfg("hkTeleLeft"),  (*) => TeleportMonitor(-1)],
        [Cfg("hkTeleRight"), (*) => TeleportMonitor(1)],
        [Cfg("hkGui"),       (*) => ShowMain()],
        [Cfg("hkToggle"),    (*) => ToggleEnabled()],
        [Cfg("hkPause"),     (*) => ToggleEnabled()],
        [Cfg("hkPanic"),     (*) => PanicRelease()],
        [Cfg("hkClickLock"), (*) => ClickLockToggle("")],
        [Cfg("hkWinNext"),   (*) => WinPlace("next")],
        [Cfg("hkWinPrev"),   (*) => WinPlace("prev")],
        [Cfg("hkWinMax"),    (*) => WinPlace("max")],
        [Cfg("hkWarp"),      (*) => Warp.Toggle()]]
    bad := ""
    mouse := ""
    clash := ""
    dup := ""
    seen := Map()
    seen.CaseSense := "Off"
    for pair in pairs {
        hk := pair[1]
        if (hk = "")
            continue
        ; the same combo twice: the later silently replaced the earlier
        if seen.Has(hk) {
            dup .= (dup = "" ? "" : ", ") hk
            continue
        }
        seen[hk] := 1
        if IsMouseHotkey(hk) {
            mouse .= (mouse = "" ? "" : ", ") hk
            continue
        }
        conflict := KbHotkeyConflict(hk)
        if (conflict != "") {                ; registering it would silently
            clash .= (clash = "" ? "" : ", ") hk " (vs " conflict ")"
            continue                         ; kill that key's Mappings rows
        }
        try {
            Hotkey(hk, pair[2], "On")
            g_KbRegistered.Push(hk)
        } catch {
            bad .= (bad = "" ? "" : ", ") hk
        }
    }
    global g_BadHkWarned
    if (bad dup != "" && bad "|" dup != g_BadHkWarned) {   ; once per set
        if (bad != "")
            Problem("bad-hotkey", "Invalid Settings hotkey(s): " bad)
        if (dup != "")
            Problem("dup-hotkey", "Settings hotkey used twice (first kept): " dup)
        TrayTip((bad != "" ? "Invalid hotkey(s): " bad "`n" : "")
            . (dup != "" ? "Used twice, second ignored: " dup : ""),
            "RadMapper", "Iconx")
    }
    g_BadHkWarned := bad "|" dup
    ; warn once per offending set -- RegisterKbHotkeys reruns on EVERY config
    ; change, and re-raising the tip on each unrelated edit would be noise
    global g_MouseHkWarned
    if (mouse != "" && mouse != g_MouseHkWarned) {
        Problem("mouse-hotkey", "Mouse input rejected as Settings hotkey: " mouse)
        TrayTip("Mouse inputs cannot be Settings hotkeys (they would override"
            . " every Mappings row on that input): " mouse
            . "`nBind the action in the Mappings tab instead"
            . " (e.g. Tilt Wheel Left -> Teleport monitor, value left).",
            "RadMapper", "Iconx")
    }
    g_MouseHkWarned := mouse
    global g_ClashWarned
    if (clash != "" && clash != g_ClashWarned) {
        Problem("hotkey-clash", "Settings hotkey not registered -- the same"
            . " key already has Mappings rows: " clash)
        TrayTip("These Settings hotkeys were skipped because the same key is"
            . " bound in the Keyboard tab, and registering both would stop"
            . " the key binding from firing: " clash
            . "`nUse a different key, or bind the action as a key row.",
            "RadMapper", "Iconx")
    }
    g_ClashWarned := clash
}

; Release every in-flight synthetic hold and clear engine state. MUST run
; before any path that can unregister an Up hotkey (disable, config change)
; or the release event is lost and the synthetic input stays down forever.
ForceReleaseActive() {
    BypassOff(true)                          ; pass-through never outlives teardown
    ; BEFORE the g_BS sweep: a held switcher commits on release, and
    ; teardown is not a commit.
    AppSwitchClose(false)
    ClickLockRelease()                       ; a latch must never outlive the
                                             ; hooks that can release it
    for name, st in g_BS.Clone() {
        if (st.down && !st.consumed) {
            if (st.mode = "passthru")
                SendNativeUp(st.passBtn != "" ? st.passBtn : name)
            else if (st.mode = "held")
                ActionUp(st.holdBinding, st)
        }
        st.down := false                     ; watchers holding a reference to
        ClearBS(name)                        ; this state see a release
    }
}

; ── §10b  WATCHDOG (physical-state reconciliation) ──────────────────────────
; ForceReleaseActive and PanicRelease are EVENT-driven; nothing reconciles
; engine-believed held state against physical reality on its own. If an Up
; event is lost (hook drop, modal dialog, focus theft), a synthetic down,
; modifier, momentary layer or speed mod stays stuck until the user panics.
; The watchdog closes that hole: every 750 ms it checks each believed-held
; thing against the physical key state (InputHeldPhysical, which the rig can
; simulate via RIG_Keys) and releases anything whose physical anchor is gone,
; reusing the exact release paths ForceReleaseActive uses. Recoveries are
; recorded via Problem() for the Diagnostics view. TOGGLED states (a speed
; toggle) are deliberate user choices and are NEVER auto-cleared -- panic
; owns those. A 500 ms age guard keeps the watchdog out of legitimate
; in-flight transitions.

Watchdog() {
    Critical "On"
    ; Before the enabled test: a wedged UI count is not an engine state, and
    ; it must clear even while the engine is paused. See Lumi.EditGuard.
    try Lumi.EditGuard()
    if !g_Enabled
        return
    if (IsObject(g_Bypass) && g_Bypass.mom) {
        hs := BS(g_Bypass.src)
        ; an injected holder (physSeen false) never reads as physically
        ; held: trust its state, as the engine does elsewhere
        ; ...nor after a hook reinstall since the press (the physical table
        ; is wiped then, and would read a held button as up)
        if !(hs && hs.down && (!hs.physSeen || (g_HookChangedAt - hs.pressTick) >= 0
            || InputHeldPhysical(g_Bypass.src))) {
            BypassOff()
            Problem("recovered", "pass-through ended: its button is no longer held")
        }
    }
    now := A_TickCount
    ; 1) input states whose physical input is no longer down (lost Up)
    for name, st in g_BS.Clone() {
        if !st.down
            continue
        age := now - st.pressTick
        if (age < 0)                         ; A_TickCount wrapped: be patient
            age := 0
        ; Only a state with a SYNTHETIC down out can leave a button stuck
        ; in the OS if its Up is lost. A pending / armed / waiting state has
        ; sent nothing, so it is never judged on the physical table -- the
        ; table is wiped by every hook (re)install and by SendInput, and
        ; judging a held layer host on it released the layer mid-gesture
        ; (v0.6.6.4). Such a state gets the runaway cap only.
        synthetic := (st.mode = "passthru" || st.mode = "held")
        why := ""
        if !synthetic {
            ; A layer host held through a long scroll (a 40 s CT stack) is
            ; still held: with no hook change since the press a "held"
            ; reading is trustworthy (only the wiped table reads falsely UP),
            ; and sweeping it dropped the layer mid-gesture and later sent a
            ; lone XButton Up (Back).
            if (st.physSeen && (g_HookChangedAt - st.pressTick) < 0
                && InputHeldPhysical(st.btn))
                continue
            if (age < 30000)
                continue
            why := "held 30 s with nothing out"
        } else if (!st.physSeen || (g_HookChangedAt - st.pressTick) >= 0) {
            ; an injected source, or a hook change since the press: the
            ; physical reading is not evidence either way
            if (age < 30000)
                continue
            why := st.physSeen ? "held 30 s, hooks changed since the press"
                : "held 30 s, injected source"
        } else if InputHeldPhysical(st.btn) {
            st.upTicks := 0
            continue
        } else {
            if (age < 500)                   ; too fresh: the real Up event
                continue                     ; may simply not have run yet
            st.upTicks := (st.HasProp("upTicks") ? st.upTicks : 0) + 1
            if (st.upTicks < 2)              ; two ticks in a row, not one
                continue                     ; transient reading
            why := "input physically up"
        }
        if st.consumed {                     ; nothing owns a consumed state
            ClearBS(name)                    ; any more; just drop it
            continue
        }
        ; Recovery is a TEARDOWN, and teardown never commits (same rule as
        ; ForceReleaseActive). Close first: AppSwitchWatch must never see
        ; this holder go up and read it as the commit gesture.
        if (IsObject(g_AppSw) && IsObject(g_AppSw.holder) && g_AppSw.holder = st)
            AppSwitchClose(false)
        if (st.mode = "passthru")
            SendNativeUp(st.passBtn != "" ? st.passBtn : name)
        else if (st.mode = "held")
            ActionUp(st.holdBinding, st)
        st.down := false                     ; watchers of this holder (the
        ClearBS(name)                        ; switcher, a menu) see a release
        Problem("recovered", "released stuck " name " (" st.mode ", " why ")")
        HUD("RadMapper recovered a stuck " name)
    }
    ; 4) and 5) THE OS's OWN STATE, not ours. Part 1 reconciles g_BS, and
    ;    that is exactly what the PowerScribe/PACS click freeze slipped past:
    ;    a click whose Down went out inside a "+{Tab}" delivery leaves a Shift
    ;    logically down and/or an orphan LButton down in the OS while g_BS's
    ;    books balance, so nothing here saw it, nothing reached Diagnostics,
    ;    and only Panic cleared it. These sweeps read the logical/physical
    ;    pair straight from Windows, so they are timid: two consecutive ticks
    ;    (~1.5 s) of the same reading, and only while nothing of ours could
    ;    be holding anything down (WatchdogSweepSafe).
    static modTicks := Map()
    static lbTicks := 0
    ; ...and only when RADMAPPER sent input in the last 10 s. The sweeps exist
    ; for a modifier or button WE left down (a +{Tab} delivery, a moddrag).
    ; With a dead hook, or keys injected by another program, "physically up"
    ; is wrong -- and releasing Ctrl the user is holding turned Ctrl+C into
    ; a bare "c" typed over the selection.
    if (!WatchdogSweepSafe() || A_TickCount - g_SynthAt > 10000) {
        modTicks.Clear()                     ; a count may never survive a
        lbTicks := 0                         ; period when the guard was up
        return
    }
    for k in ["LShift", "RShift", "LCtrl", "RCtrl",
              "LAlt", "RAlt", "LWin", "RWin"] {
        down := false
        try down := (GetKeyState(k) && !GetKeyState(k, "P"))
        if !down {
            modTicks[k] := 0
            continue
        }
        modTicks[k] := (modTicks.Has(k) ? modTicks[k] : 0) + 1
        if (modTicks[k] < 2)                 ; one tick can be mid-keystroke
            continue
        ; NEGATIVE, not zero: if the Up does not take (an elevated window
        ; eats injected input) retry about every 7.5 s, not every tick
        modTicks[k] := -8
        SafeSend("{Blind}{" k " Up}")
        Problem("recovered", "released a stuck " k " (logically down, key"
            . " physically up for two ticks)")
        HUD("RadMapper released a stuck " k)
    }
    ; LButton only: a middle or right button logically down with no physical
    ; anchor is the everyday shape of a DRIVER-INJECTED pan or right-drag,
    ; which AutoHotkey never counts as physically held.
    lbStuck := false
    try lbStuck := (GetKeyState("LButton")
        && !InputHeldPhysical("LButton") && !g_BS.Has("LButton"))
    if !lbStuck
        lbTicks := 0
    else {
        lbTicks += 1
        if (lbTicks >= 2) {
            lbTicks := -8
            SendNativeUp("LButton")
            Problem("recovered", "released an orphan LButton (down in the OS"
                . " with no press of ours and no hand on it)")
            HUD("RadMapper released a stuck left button")
        }
    }
}

; Guard for the two OS-state sweeps in Watchdog: they may run only when
; nothing of ours could legitimately be holding a key or button down -- a
; live press (a moddrag holds "{mod Down}{LButton Down}", a passthrough
; holds its button), a click-lock latch, a drag scroll, the keyboard pointer,
; a delivery mid-flight (its own "+" is down for a moment), a macro, or an
; open menu/switcher.
WatchdogSweepSafe() {
    ; A hook (re)install wipes AutoHotkey's physical-state table, so for a
    ; few seconds "physically up" is not evidence of anything.
    since := A_TickCount - g_HookChangedAt
    if (since >= 0 && since < 5000)
        return false
    for name, st in g_BS {
        if st.down
            return false
    }
    if (IsObject(g_ClickLock)
        || IsObject(g_AppSw) || g_PSBusy || g_MacroBusy)
        return false
    try {
        if (Warp.active || Warp.grabbing)
            return false
    }
    return true
}

; KEEP OUR MOUSE AND KEYBOARD HOOKS AT THE FRONT OF THE CHAIN WHILE PACS
; IS IN FRONT.
; Windows calls low-level mouse hooks newest-first, and any hook may eat an
; event before the older ones see it. IntelliSpace can install its own while
; it runs, AFTER RadMapper started, so over its images and series list it
; got the tilt first and consumed it: RadMapper never saw the notch, the
; list scrolled sideways, the teleport never fired and nothing reached
; Diagnostics. InstallMouseHook(true, true) removes our hook and installs it
; again, which puts it back in front.
;
; Done when a PACS window comes to the front and then every 10 s while it
; stays there -- and ONLY while nothing is held: a reinstall wipes
; AutoHotkey's physical-state table (HookChanged), and a press that
; straddles one would be judged on a reading that means nothing.
HookFrontTick(*) {
    static lastHwnd := 0, lastAt := 0, logged := false
    if !g_Enabled
        return
    fg := FgHwnd()
    exe := ""
    try exe := WinGetProcessName("ahk_id " fg)
    if (exe != "IntelliSpacePACSRadiology.exe") {
        lastHwnd := 0
        return
    }
    now := A_TickCount
    ; ONCE each time PACS comes to the front. Every reinstall drops the
    ; keystrokes in its gap and wipes the physical key table; doing it every
    ; 10 s while PACS stayed in front cost more than it fixed.
    if (fg = lastHwnd)
        return
    for name, st in g_BS {
        if st.down
            return
    }
    for b in BUTTONS {
        if GetKeyState(b)                    ; logically down: a native drag
            return
    }
    ; ...and no modifier down: a Ctrl or Shift held across the keyboard
    ; reinstall would lose its physical reading mid-chord
    for k in ["LShift", "RShift", "LCtrl", "RCtrl", "LAlt", "RAlt",
              "LWin", "RWin"] {
        if GetKeyState(k)
            return
    }
    if (IsObject(g_AppSw) || IsObject(g_ClickLock)
        || IsObject(g_RecHook))
        return
    try {
        if Warp.active
            return
    }
    try {
        ; BOTH hooks: the keyboard one carries CapsLock (dictation), the
        ; bound keys and every Settings hotkey, and a hook PACS installs
        ; after ours can eat a keystroke exactly as it ate the tilt.
        InstallMouseHook(true, true)
        InstallKeybdHook(true, true)
        HookChanged()
        lastHwnd := fg
        lastAt := now
        if !logged {                         ; once per session: proof it ran
            logged := true
            Problem("hook", "mouse and keyboard hooks moved back to the front"
                . " of the chain (PACS in front)")
        }
    } catch as e {
        Problem("hook-error", "could not reinstall the input hooks: " e.Message)
        lastHwnd := fg
        lastAt := now
    }
}

; Evidence for Diagnostics, taken the moment Panic is pressed and BEFORE it
; clears anything: which keys/buttons Windows thinks are down without a hand
; on them, what the engine believes is held, and what else was live. A
; freeze that only Panic fixes used to leave no trace at all.
PanicSnapshot() {
    stuck := ""
    for k in ["LButton", "RButton", "MButton", "XButton1", "XButton2",
              "LShift", "RShift", "LCtrl", "RCtrl", "LAlt", "RAlt",
              "LWin", "RWin"] {
        try {
            if (GetKeyState(k) && !GetKeyState(k, "P"))
                stuck .= (stuck = "" ? "" : " ") k
        }
    }
    held := ""
    for name, st in g_BS
        held .= (held = "" ? "" : " ") name "=" st.mode
            . (st.down ? "" : "/up") (st.consumed ? "/consumed" : "")
    live := ""
    if IsObject(g_ClickLock)
        live .= " clicklock"
    if IsObject(g_AppSw)
        live .= " switcher"
    try {
        if Warp.active
            live .= " kbpointer"
    }
    if g_PSBusy
        live .= " delivering"
    if g_PSQueue.Length
        live .= " queued=" g_PSQueue.Length
    if g_MacroBusy
        live .= " macro"
    fg := ""
    try fg := WinGetProcessName("A")
    return "logically down, no hand: " (stuck = "" ? "none" : stuck)
        . " | engine: " (held = "" ? "none" : held)
        . " | live:" (live = "" ? " none" : live)
        . " | fg: " (fg = "" ? "?" : fg)
}

ToggleEnabled() {
    global g_Enabled, g_PSQueue, g_PSGen, g_MacroGen, g_MacroBusy
    g_Enabled := !g_Enabled
    if !g_Enabled {
        g_MacroGen += 1                      ; a running macro stops too
        g_MacroBusy := false
        ForceReleaseActive()                 ; nothing may stay down once hooks drop
        ; "input is native" must be true: the keyboard pointer's InputHook
        ; would otherwise outlive the pause with its off switch unhooked.
        try Warp.Close(true)
        g_PSQueue := []                      ; and nothing may still be on its
        g_PSGen += 1                         ; way into the study: queued
    }                                        ; deliveries die, the in-flight
                                             ; one aborts unsent (as panic does)
    SetTimer(Watchdog, 750)                  ; keeps ticking while PAUSED: the
    SyncFollowFocus()                        ; block above its own !g_Enabled
    AppCacheClear()                          ; test (EditGuard, a hidden system
                                             ; cursor) is explicitly meant to
                                             ; run then, and stopping the timer
                                             ; made it unreachable. The inner
                                             ; test still gates reconciliation.
    wasTesting := g_Testing                  ; tester off BEFORE SyncHooks: "~*X"
    if wasTesting                            ; and "*X" are the same hotkey
        TestStop()
    SyncHooks()
    RegisterKbHotkeys()                      ; its clash check reads the hooks
    UpdateTray()
    if wasTesting
        TestStart()
    ; Pause is now one keystroke away (NumLock by default), so it has to
    ; announce itself: a tray balloon alone is missed mid-study.
    HUD(g_Enabled ? "RadMapper running" : "RadMapper PAUSED — input is native",
        g_Enabled ? "jade" : "warn")
    TrayTip(g_Enabled ? "Engine ENABLED" : "Engine PAUSED (mouse fully native)", "RadMapper")
}

PanicRelease() {
    global g_PSQueue, g_PSGen, g_ClickLock
    global g_MacroBusy, g_MacroGen
    g_PSQueue := []                          ; queued PS deliveries die, and
    g_PSGen += 1                             ; the in-flight one aborts unsent
    ; A running macro is a SEQUENCE, and panic has to stop the rest of it:
    ; releasing every button meant nothing while the macro thread kept
    ; sending its remaining steps into the study. RunMacro snapshots this
    ; generation and breaks as soon as it moves. g_MacroBusy is cleared too,
    ; so the next macro is not refused by a loop that is on its way out.
    try Problem("panic", PanicSnapshot())   ; BEFORE anything is cleared
    g_MacroGen += 1
    g_MacroBusy := false
    RM_Send("{LButton Up}{RButton Up}{MButton Up}{XButton1 Up}{XButton2 Up}"
        . "{LCtrl Up}{RCtrl Up}{LAlt Up}{RAlt Up}{LShift Up}{RShift Up}{LWin Up}{RWin Up}")
    for name, st in g_BS.Clone() {           ; v0.3: a KEY held down by our own
        tgt := st.passBtn != "" ? st.passBtn : name   ; passthrough needs its
        if (st.down && IsKeyInput(tgt))      ; own Up -- judged on the TARGET,
            try SendNativeUp(tgt)            ; so XButton2 -> Enter is released
    }                                        ; the blanket list above is mouse
                                             ; + modifiers only
    AppSwitchClose(false)                    ; panic never commits a switch, and
    for name, st in g_BS.Clone() {           ; a switcher left up would disable
        st.down := false                     ; the watchdog until Esc
        ClearBS(name)
    }
    g_ClickLock := 0                         ; the blanket Up above released it
    ClickLockWatchStop()                     ; and its watcher must not outlive it
    try Warp.Close(true)                     ; the keyboard comes back, too
    BypassOff(true)
    HUD("PANIC: everything released & reset")
}

; Failure funnel: every notable problem (failed send, PS delivery trouble,
; dropped action, watchdog recovery) is recorded here so the Diagnostics view
; can show it and AJ can copy the trail to a session. In-memory ring only --
; never touches disk, never records dictated text or clipboard content, and
; is cleared on exit. Recording only: each call site keeps its own HUD or
; TrayTip notification.
Problem(kind, detail) {
    global g_Problems, g_ProblemSeq
    g_Problems.Push({time: FormatTime(, "HH:mm:ss"), kind: kind, detail: detail})
    if (g_Problems.Length > 200)
        g_Problems.RemoveAt(1)
    g_ProblemSeq += 1
}

; Shape dispatch used to wrap every handler in a bare try, erasing the only
; evidence for a broken button. Keep the UI alive, but record the failure.
RadUiCall(callback, args*) {
    try return callback(args*)
    catch as e {
        detail := e.Message
        try detail .= " (line " e.Line ")"
        try Problem("ui-event", detail)
        try OutputDebug("[RadMapper ui-event] " detail "`n")
    }
    return 0
}

; A modal AutoHotkey error box over a study is itself a clinical failure.
; Return 1 suppresses the dialog and ends only the failing thread; the error
; remains in the in-memory Diagnostics ring and in OutputDebug.
RadUnhandledError(err, mode) {
    detail := "Unhandled error"
    try detail := err.Message
    try detail .= " (line " err.Line ", " mode ")"
    try Problem("unhandled", detail)
    try OutputDebug("[RadMapper unhandled] " detail "`n")
    try DllCall("user32\ReleaseCapture")
    return 1
}

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


; Top-left corner for a HUD box of roughly the given size, in the corner the
; user picked, on the work area of the monitor under the cursor (or primary).
HUDCorner(bw := 260, bh := 34) {
    if Cfg("hudFollow") {
        MouseGetPos(&cx, &cy)
        m := MonitorWorkAt(cx, cy)
    } else {
        MonitorGetWorkArea(MonitorGetPrimary(), &pl, &pt, &pr, &pb)
        m := {l: pl, t: pt, r: pr, b: pb}
    }
    p := 24
    switch Cfg("hudCorner") {
        case "br": return {x: m.r - bw - p, y: m.b - bh - p}
        case "tl": return {x: m.l + p,      y: m.t + p}
        case "tr": return {x: m.r - bw - p, y: m.t + p}
        case "bc": return {x: m.l + (m.r - m.l - bw) // 2, y: m.b - bh - p}
    }
    return {x: m.l + p, y: m.b - bh - p}
}

HUDOff() {
    ToolTip()
}

; --- Test tab live input monitor ----------------------------------------------
; Engine-hooked inputs report via TestNotify from the hot paths (deferred out
; of Critical sections). Inputs the engine does NOT hook get temporary "~*"
; passthrough hotkeys while the tab is open -- native behavior never blocked.

; Hot-path side is DATA ONLY (no allocation, no timers, no control writes):
; a trackball spin at hundreds of notches/sec must not flood the GUI thread.
; The single TestTick timer repaints all rows at ~20 Hz while testing.
TestNotify(name, state) {                    ; state: 1 down, 0 up, 2 pulse
    if !g_Testing
        return
    if (state = 0) {
        if g_TestHeld.Has(name)
            g_TestHeld.Delete(name)
        return
    }
    g_TestCounts[name] := MGet(g_TestCounts, name, 0) + 1
    if (state = 1)
        g_TestHeld[name] := 1
    else
        g_TestLast[name] := A_TickCount      ; wheels have no release: pulse
}

; The input tester's own small window (it used to be a tab of the classic
; window). Nothing pressed here is blocked; closing it stops the monitor.
TesterShow() {
    global g_TestUI
    if IsObject(g_TestUI) {
        try {
            g_TestUI.g.Show()
            return
        }
    }
    g := Gui(DlgOwner() " -MinimizeBox", "RadMapper — test my mouse")
    StyleDlg(g)
    g.AddText("x16 y12 w460", "Press any mouse input: its bar lights and its"
        . " count goes up (a count that jumps by two is a double-fire)."
        . " Nothing is blocked while this is open.")
    ui := {g: g, testBars: Map(), testCounts: Map()}
    ty := 64
    for name in ["LButton", "RButton", "MButton", "XButton1", "XButton2",
        "WheelUp", "WheelDown", "WheelLeft", "WheelRight"] {
        g.AddText("x16 y" ty " w170 h18 +0x200", InputLabel(name))
        ui.testBars[name] := g.AddProgress("x190 y" ty " w220 h18 Smooth c2E7D32 BackgroundE3E6EA", 0)
        ui.testCounts[name] := g.AddText("x+12 y" ty " w60 h18 +0x200", "0")
        ty += 28
    }
    close := (*) => TesterClose()
    g.AddButton("x16 y" (ty + 8) " w100 Default", "Close").OnEvent("Click", close)
    g.OnEvent("Close", close)
    g.OnEvent("Escape", close)
    g_TestUI := ui
    g_OurHwnds[g.Hwnd] := 1
    ApplyTheme(g)
    g.Show()
    TestStart()
}

TesterClose() {
    global g_TestUI
    TestStop()
    if !IsObject(g_TestUI)
        return
    g := g_TestUI.g
    g_TestUI := 0
    if g_OurHwnds.Has(g.Hwnd)
        g_OurHwnds.Delete(g.Hwnd)
    try g.Destroy()
}

TestTick(*) {
    if (!g_Testing || !IsObject(g_TestUI))
        return
    now := A_TickCount
    for name, bar in g_TestUI.testBars {
        lit := g_TestHeld.Has(name)
            || (g_TestLast.Has(name) && now - g_TestLast[name] < 160)
        v := lit ? 100 : 0
        if (bar.Value != v)
            bar.Value := v
        n := String(MGet(g_TestCounts, name, 0))
        cnt := g_TestUI.testCounts[name]
        if !(cnt.Text = n)
            cnt.Text := n
    }
}

TestStart() {
    global g_Testing, g_TestHooks, g_TestCounts, g_TestHeld, g_TestLast
    if (g_Testing || !IsObject(g_TestUI))
        return
    g_Testing := true
    g_TestCounts := Map()
    g_TestHeld := Map()
    g_TestLast := Map()
    for name, bar in g_TestUI.testBars
        bar.Value := 0
    for name, cnt in g_TestUI.testCounts
        cnt.Text := "0"
    SetTimer(TestTick, 50)
    ; Passive "~*" reporters are registered for EVERY input, hooked or not.
    ; Since v0.9.6 the engine's own hotkeys live in a HotIf(HookActive)
    ; VARIANT while these are the global variant of the same hotkey -- AHK
    ; fires exactly one variant per event, so over foreign windows the engine
    ; variant wins (its handlers call TestNotify themselves) and these never
    ; double-report; over OUR windows the engine variant is gated off (native
    ; clicks) and without a global reporter the tester bars went dead for
    ; hooked buttons -- the cursor is usually over the GUI while watching them.
    HookChanged()
    for btn in BUTTONS {
        try {
            Hotkey("~*" btn, TestNotifyHK.Bind(btn, 1), "On")
            g_TestHooks.Push("~*" btn)
            Hotkey("~*" btn " Up", TestNotifyHK.Bind(btn, 0), "On")
            g_TestHooks.Push("~*" btn " Up")
        }
    }
    for wh in WHEELS {
        try {
            Hotkey("~*" wh, TestNotifyHK.Bind(wh, 2), "On")
            g_TestHooks.Push("~*" wh)
        }
    }
}

TestStop() {
    global g_Testing, g_TestHooks
    if !g_Testing
        return
    g_Testing := false
    SetTimer(TestTick, 0)
    HookChanged()
    for hk in g_TestHooks
        try Hotkey(hk, "Off")
    g_TestHooks := []
}

TestNotifyHK(name, state, *) {
    TestNotify(name, state)
}

; The no-file way to hand the trail to a debugging session.
ProblemsCopy() {
    ; A pasted list is useless without the machine it came from -- every
    ; question we ask back ("which version? did it save? which app?") is
    ; answered by this header, so it always rides along.
    app := ActiveAppName()
    txt := "RadMapper " RM_VERSION "  ·  AutoHotkey " A_AhkVersion
        . "  ·  Windows " A_OSVersion "`r`n"
        . "Config: " CFG_PATH (g_CfgSaveFailed ? "   (NOT SAVED TO DISK)" : "") "`r`n"
        . "Engine: " (g_Enabled ? "running" : "PAUSED")
        . "   ·  In front: " (app != "" ? app : "(no profile)")
        . "   ·  Layer: " CurrentLayerDisp() "`r`n"
        . "Copied: " FormatTime(, "yyyy-MM-dd HH:mm") "`r`n"
        . "----------------------------------------------------------`r`n"
    for p in g_Problems
        txt .= p.time "  [" p.kind "]  " p.detail "`r`n"
    if (g_Problems.Length = 0)
        txt .= "(no problems this session)`r`n"
    A_Clipboard := txt
}

ProblemsClear() {
    global g_Problems
    g_Problems := []
}

; --- sidebar nav (G1, v1.4: replaces the Tab3 strip) ---------------------------
; Panels are recorded at build time by hwnd-diffing the Gui between PanelNext
; marks -- the legacy tab-relative coordinates are kept verbatim, and every
; collected control is shifted +150 px into the content column, so none of the
; seven sections needed re-anchoring. Nav items are plain Text controls, which
; take full theme colors (the old Tab3 strip could not).


; ── §11  GUI ────────────────────────────────────────────────────────────────

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


RestoreDefaults(confirmed := false) {
    global g_Cfg
    if (!confirmed && MsgBox("Restore the shipped defaults?"
        . " Your assignments will be replaced, including the dictation and monitor-switching defaults.", "RadMapper", "YesNo Icon?") != "Yes")
        return
    try BackupCfg()                          ; edits since launch stay recoverable
    g_Cfg := DefaultCfg()
    SaveCfg()
    AfterCfgChange()
}

AfterCfgChange() {
    RebuildIndex()                           ; every config mutation funnels here
    ForceReleaseActive()                     ; a hook may be about to turn Off
    ; "~*X" (tester) and "*X" (engine) are the SAME hotkey to AHK -- the tilde
    ; is a mutable flag, not identity. The tester must release its hotkeys
    ; BEFORE SyncHooks reconfigures them, or TestStop would turn freshly
    ; enabled engine hooks back Off.
    wasTesting := g_Testing
    if wasTesting
        TestStop()
    SyncHooks()
    RegisterKbHotkeys()
    SyncFollowFocus()
    SyncHudPlacement()
    SyncLayoutGuard()
    if wasTesting
        TestStart()
}

; Lumi is a self-contained kit and does not read our config; RadMapper pushes
; the two placement values into it whenever they change.
SyncHudPlacement() {
    try {
        Lumi.toastCorner := Cfg("hudCorner")
        Lumi.toastFollow := Cfg("hudFollow") ? true : false
    }
}

; --- list refresh helpers ------------------------------------------------------

; ---- Mouse-map view (G4): the schematic front-end for button-layers.
; Everything is scoped to the App + Layer (hold) selectors; a zone click aims
; the right-hand panel at that input. ---------------------------------------

; --- duplicate-context dedup (upsert on Add) ------------------------------------
; Two rows with the same input and the same context (app/layer/while/mods)
; can never both fire -- the later one silently shadows the earlier, which
; reads as "my mapping got cancelled" in the shared Mappings list. Adding
; such a row UPSERTS: the replacement lands at the LAST duplicate's position
; (the row arbitration was already honoring -- later rows win ties) and any
; shadowed earlier duplicates, including legacy remap+restore-native stacks
; and seeded defaults, are pruned so exactly one row remains. Replacing the
; FIRST match instead would leave the old later row still winning while the
; HUD claimed success (adversarial-tracer finding). Rows that differ in ANY
; context field coexist and are arbitrated by specificity at event time.

FindDupBinding(b) {
    dups := []
    for i, row in g_Cfg["bindings"] {
        if (MGet(row, "button", "") = b["button"]
            && MGet(row, "event", "") = b["event"]
            && MGet(row, "app", "*") = MGet(b, "app", "*")
            && MGet(row, "layer", "*") = MGet(b, "layer", "*")
            && MGet(row, "mods", "") = MGet(b, "mods", ""))
            dups.Push(i)
    }
    return dups
}

; Shared upsert: replace the last duplicate in cfg[key], prune the rest
; (descending, so remaining indexes stay valid), or push when no duplicate.
; Returns true if anything was replaced.
UpsertRow(key, newRow, dups) {
    if (dups.Length = 0) {
        g_Cfg[key].Push(newRow)
        return false
    }
    g_Cfg[key][dups[dups.Length]] := newRow
    i := dups.Length - 1
    while (i >= 1) {
        g_Cfg[key].RemoveAt(dups[i])
        i -= 1
    }
    return true
}

; Edit-path variant: the edited row keeps its own position (that row IS the
; user's intent); any OTHER row with the same input+context is pruned -- it
; could only shadow or be shadowed. Without this, editing a row's context
; onto another row's key minted a hidden duplicate that persisted until the
; next Add. dups must be computed BEFORE the write (against the old row).
; Descending removal keeps the remaining indexes valid.
UpsertRowEdit(key, newRow, dups, editRow) {
    g_Cfg[key][editRow] := newRow
    pruned := false
    i := dups.Length
    while (i >= 1) {
        if (dups[i] != editRow) {
            g_Cfg[key].RemoveAt(dups[i])
            pruned := true
        }
        i -= 1
    }
    return pruned
}

UpsertBinding(b) {
    return UpsertRow("bindings", b, FindDupBinding(b))
}

; --- shared dialog plumbing ----------------------------------------------------

ModalOpen(dlg) {
    g_OurHwnds[dlg.Hwnd] := 1
    dlg.OnEvent("Close", (*) => ModalClose(dlg))
    dlg.OnEvent("Escape", (*) => ModalClose(dlg))
    ApplyTheme(dlg)                          ; every dialog matches the theme
    dlg.Show()
}

ModalClose(dlg) {
    if IsObject(g_RecHook)
        try g_RecHook.Stop()                 ; never leave a capture running headless
    if g_OurHwnds.Has(dlg.Hwnd)
        g_OurHwnds.Delete(dlg.Hwnd)
    dlg.Destroy()
}

; "+Owner<hwnd>" for a native dialog: the settings window when it is up,
; so the dialog stays in front of it; nothing otherwise.
DlgOwner() {
    try {
        if (IsObject(Atlas.lyr) && WinExist("ahk_id " Atlas.lyr.hwnd))
            return "+Owner" Atlas.lyr.hwnd
    }
    return ""
}


AppChoices() {
    out := ["Global (all apps)"]
    for app in g_Cfg["apps"]
        out.Push(app["name"])
    return out
}

; v1.0 (E1): one "Layer (hold to arm)" selector replaces the old Layer + While
; dropdowns. Choices: Base, each single button (depth-1), and each unordered
; button pair (depth-2 nesting). Matching treats a path as an unordered set of
; held buttons, so one presentation order per pair suffices.
; LAYER_BASE_LABEL is a top-level global (defined near BUTTONS, above Init()).
LayerChoices() {
    out := [LAYER_BASE_LABEL]
    for b in LayerHosts()
        out.Push("Hold " InputLabel(b))
    return out
}

; The inputs that may hold a layer open (v0.7.2: a setting). Everything else
; is refused by the editors and dropped on load (ValidateCfg).
LayerHosts() {
    h := IsSet(g_Cfg) ? MGet(g_Cfg, "layerHosts", 0) : 0
    return (h is Array) ? h : LAYER_HOSTS
}

LayerHostAllowed(inp) {
    for b in LayerHosts() {
        if (b = inp)
            return true
    }
    return false
}

; Could this input host a layer at all? Any mouse button but left (and no
; wheel direction), or any key AutoHotkey can hook.
LayerHostOk(inp) {
    if (inp = "" || inp = "LButton" || IsWheel(inp))
        return false
    return IsMouseInput(inp) || KeyNameValid(inp)
}

; A hand-edited or stale host list, cleaned: canonical names, valid hosts
; only, no duplicates, at most LAYER_HOSTS_MAX.
CleanLayerHosts(list) {
    out := []
    for v in list {
        if IsObject(v)
            continue
        n := CanonicalInputName(NormalizeInputName(String(v)))
        for b in BUTTONS {                   ; "mbutton" -> "MButton"
            if (b = n)
                n := b
        }
        if !LayerHostOk(n)
            continue
        dup := false
        for o in out {
            if (o = n)
                dup := true
        }
        if (!dup && out.Length < LAYER_HOSTS_MAX)
            out.Push(n)
    }
    return out
}

; Short words for a host list: "button 4, button 5 or CapsLock".
LayerHostsText() {
    hs := LayerHosts()
    if (hs.Length = 0)
        return "no input (add one with “Layer buttons…”)"
    out := ""
    for i, h in hs {
        w := IsMouseInput(h) ? StrLower(InputLabel(h)) : h
        out .= (i = 1 ? "" : (i = hs.Length ? " or " : ", ")) w
    }
    return out
}

; A row's layer path is usable when every component may host a layer and
; there is only one of them: nesting went with the pairs (v0.7).
LayerPathAllowed(layer) {
    parts := 0
    for p in StrSplit(layer, "/") {
        if (p = "" || p = "*" || p = "Base")
            continue
        parts += 1
        if (!LayerHostAllowed(p) || parts > 1)
            return false
    }
    return true
}

; Left, right and middle: the three buttons every application already owns.
; A hold on one of them is only honoured when written FOR one program
; (v0.7); an everywhere hold row is refused by the editors and dropped on
; load, so a plain click is never withheld outside the program that asked.
IsPrimaryButton(btn) {
    return (btn = "LButton" || btn = "RButton" || btn = "MButton")
}

; Every key already used as an input somewhere in the config, in config
; order, de-duplicated. Keys have no enumerable list, so the config is the
; only source for "which keys exist" (the Keyboard page's tiles).
KeyInputsInUse() {
    seen := Map()
    seen.CaseSense := "Off"
    out := []
    for row in g_Cfg["bindings"] {
        b := MGet(row, "button", "")
        if (IsKeyInput(b) && !seen.Has(b)) {
            seen[b] := 1
            out.Push(b)
        }
        for prt in LayerParts(row) {
            if (IsKeyInput(prt) && !seen.Has(prt)) {
                seen[prt] := 1
                out.Push(prt)
            }
        }
    }
    return out
}

; Selector label -> stored layer code ("*" or "BTN" or "BTN1/BTN2").
LayerCodeFromLabel(label) {
    if (label = "" || label = LAYER_BASE_LABEL)
        return "*"
    s := (SubStr(label, 1, 5) = "Hold ") ? SubStr(label, 6) : label
    codes := []
    for p in StrSplit(s, " + ")
        codes.Push(InputCodeFromLabel(Trim(p)))
    out := ""
    for c in codes
        out .= (out = "" ? "" : "/") c
    return out = "" ? "*" : out
}

; Stored layer code -> selector label.
LayerLabelFromCode(code) {
    if (code = "*" || code = "" || code = "Base")
        return LAYER_BASE_LABEL
    labs := ""
    for p in StrSplit(code, "/") {
        if (p != "")
            labs .= (labs = "" ? "" : " + ") InputLabel(p)
    }
    return labs = "" ? LAYER_BASE_LABEL : "Hold " labs
}

; Shared look for all pop-up dialogs.
StyleDlg(dlg) {
    dlg.BackColor := "F5F6F8"
    dlg.SetFont("s10", "Segoe UI")
}


IsRetiredEvent(ev) {
    for r in RETIRED_EVENTS {
        if (r = ev)
            return true
    }
    return false
}

ActIndexOf(code) {
    for i, c in ACT_CODES {
        if (c = code)
            return i
    }
    return ACT_CODES.Length                  ; "none"
}

/** The dropdown label for an action code -- a readable fallback name. */
ActLabelOf(code) {
    i := ActIndexOf(code)
    return ACT_LABELS.Has(i) ? ACT_LABELS[i] : code
}

; --- binding dialog --------------------------------------------------------------

; --- key binding dialog ------------------------------------------------------
; Keyboard rows are ordinary `bindings` rows -- the key name simply lives in the
; same "button" field a mouse input would. That is the whole reason keyboard
; support is small: the resolver, layers, app scoping, tap-dance and the native
; passthrough are already input-agnostic. Only INPUT SELECTION differs, because
; keys cannot be a dropdown of nine choices, so this dialog swaps that one
; control for an Edit plus a KEY NAME picker.
;
; v0.3, and the whole reason keyboard remaps did nothing in v0.2: the Key
; field must hold a HOTKEY NAME ("Numpad1"), while the Value field holds SEND
; syntax ("{Numpad1}"). v0.2 wired both to the same Send-token picker, so the
; Key field filled with braces and every key row died at Hotkey(). The two
; now have separate pickers -- KeyNamePicker here, KeyPicker for values --
; and the Key field is normalized and validated before it is ever saved.


; --- chord dialog -----------------------------------------------------------------

; --- gesture dialog ----------------------------------------------------------------

; --- macro dialogs -----------------------------------------------------------------

; --- app dialogs -------------------------------------------------------------------


; --- pointer / settings apply -------------------------------------------------------

ClampInt(v, lo, hi, dflt) {
    if !IsInteger(v)
        return dflt
    n := Integer(v)
    return Min(Max(n, lo), hi)
}


; ── §12  TRAY, LIFECYCLE ────────────────────────────────────────────────────

UpdateTray() {
    A_IconTip := "RadMapper " RM_VERSION " — " (g_Enabled ? "running" : "PAUSED")
    try {
        if g_Enabled
            A_TrayMenu.Check("Enabled")
        else
            A_TrayMenu.Uncheck("Enabled")
    }
}

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

Cleanup(*) {
    global g_Problems, g_FgLockSaved
    SetTimer(Watchdog, 0)
    SetTimer(HookFrontTick, 0)
    SetTimer(FollowTick, 0)
    try StationWatchStop()
    try Warp.Close(true)                     ; drops a held drag, frees the keyboard
    TeleportSignalStop()
    g_Problems := []                         ; in-memory only, dies with us
    if g_CfgDirty
        SaveCfg()                            ; never drop a debounced slider value
    ForceReleaseActive()
    ; Put the user's foreground-lock timeout back. It is a per-user Windows
    ; setting, not ours to leave changed on a shared login. -1 = never read.
    if (g_FgLockSaved >= 0) {
        try DllCall("SystemParametersInfo", "UInt", 0x2001,
            "UInt", g_FgLockSaved, "Ptr", 0, "UInt", 0)
        g_FgLockSaved := -1
    }
    return 0
}

Init() {
    ; The error hook is registered by GpGFX's static __New as well, but that
    ; call sits INSIDE its try, after Gdip.Startup() -- so on a machine where
    ; the graphics stack fails to start (exactly when errors are most likely)
    ; it never runs, and an unhandled error raises a modal AutoHotkey dialog
    ; over the study. Registering it here too is idempotent (v2 moves an
    ; already-registered callback rather than adding it twice) and does not
    ; depend on the bundle.
    OnError(RadUnhandledError, -1)
    if !SingleCopyGuard()
        ExitApp(0)
    ResolveCfgPaths()                        ; must precede any config I/O
    LoadCfg()
    SyncLayoutGuard()                        ; a layout whose guard flag is
                                             ; set was armed BEFORE the last
                                             ; exit; arm it again now

    BuildTray()
    SyncHooks()
    RegisterKbHotkeys()
    AppSwitchBindKeys(false)                 ; AFTER RegisterKbHotkeys, and
                                             ; here rather than lazily on the
                                             ; wheel thread that opens the
                                             ; switcher: both set a HotIf
                                             ; context, and doing it there
                                             ; could clear theirs mid-register
    SyncFollowFocus()
    StationWatchStart()                      ; recognise the screens, place windows
    OnExit(Cleanup)
    SetTimer(Watchdog, 750)                  ; physical-state reconciliation
    SetTimer(HookFrontTick, 2000)            ; keep our input hooks first in line
    ; TrayTip is (Text, Title, Options) in v2 -- Text first. (The old
    ; not-admin UIPI warning is gone: AJ's whole stack runs standard-user,
    ; so it was a false alarm on every launch.)
    TrayTip("Running (lite build). Double-click the tray icon or press "
        . Cfg("hkGui") " to edit the config file.", "RadMapper " RM_VERSION)
    ; LITE: no first-run window (the full build's welcomedVer is left alone).
}


; ONE RADMAPPER PER MACHINE, whatever the file is called or where it lives.
; #SingleInstance only recognises the SAME script path, so RadMapper.ahk in
; Downloads and RadMapper.ahk on the desktop run side by side -- and two
; copies both hook the wheel: each one suppresses a notch and re-emits it,
; the OTHER copy's hook catches the re-emission and re-emits it again, and
; fast scrolling turns into lag and stalls (reported on 0.6.0.2, cause: an
; older copy still running). A named mutex is per machine, not per path.
global g_InstanceMutex := 0
SingleCopyGuard() {
    global g_InstanceMutex
    ; Keep the handle for the life of the process; the mutex dies with us.
    g_InstanceMutex := DllCall("CreateMutexW", "ptr", 0, "int", 0,
        "wstr", "Local\RadMapper-single-copy", "ptr")
    if (!g_InstanceMutex || A_LastError != 183)   ; 183 = ERROR_ALREADY_EXISTS
        return true
    ; Another copy owns the mutex. Do NOT try to kill it: it may be mid-hold
    ; with a button latched, and only its own exit path releases cleanly.
    MsgBox("Another RadMapper is already running, probably an older copy in "
        . "a different folder.`n`nTwo copies fight over the mouse wheel and "
        . "make scrolling lag.`n`nThis copy will now close. Right-click the "
        . "other RadMapper tray icon, choose Exit, then start this one again.",
        "RadMapper is already running", "Iconi")
    return false
}


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


; ── SCRIPT ENTRY POINT ──────────────────────────────────────────────────────
; LAST statement in the file, deliberately. Everything above -- every global,
; every class static initialiser, every alias -- has been assigned by the time
; this runs, so the hooks, hotkeys and timers Init() starts can never observe
; a half-built script.
;
; The rig sets RM_TEST := true before #Include'ing this file, so the GUI,
; tray, hooks and hotkeys never start under the test harness.
if !IsSet(RM_TEST)
    Init()
