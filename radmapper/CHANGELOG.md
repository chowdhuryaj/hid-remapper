# RadMapper changelog

History moved out of the script header in 0.7.2 (verbatim).

```
  v0.7.2 -- RADIAL MENUS ARE THEIR OWN SCRIPT.
    * The radial menu engine, the Menus page, the menu editor, the
      "Radial menu" action and its settings are gone from RadMapper.
      On load, a row that opened a menu is dropped and named in
      Diagnostics, and the "menus" list leaves the config file.
    * A label that is exactly "0" (the 0 key, a zero count) drew blank:
      GpGFX tested text for emptiness with `== 0` / `!== 0`, which are
      numeric. Braces in Send syntax are no longer read as text markup
      ("^{c}" drew as "^", "{Del}" struck through).
    * THE CLIPBOARD HISTORY AND SCRATCHPAD ARE GONE, and with them the
      OnClipboardChange hook that ran on every copy/cut (the freezes).
      Their actions, hotkeys (^!c, ^!n), tray entries and saved snippets
      are removed; old rows are dropped and named in Diagnostics.
    * SIMPLER: sniper/boost pointer speed, drag scroll / drag zoom (and
      the hidden-cursor machinery behind them) and the W/L dial are
      removed. Old rows are dropped and named in Diagnostics; their
      settings are retired. The Pointer page keeps the wheel repeat
      guards and click lock.
    * MOUSE INPUT FOLLOWS THE POINTER. Program-scoped rows for a mouse
      button or the wheel match the window under the pointer; keys still
      match the foreground window.
    * LAYER BUTTONS ARE A SETTING ("Layer buttons…" on the tab strip):
      up to six of middle, right, button 4/5 or any key; never left.
    * "Toggle engine pause" on an input resumes as well as pauses.
    * PASS-THROUGH action: hold (or tap to toggle, 2-minute safety) and
      every other input is native, without pausing the engine.
    * FREEZE FIXES: the watchdog only releases modifiers/LButton after
      RadMapper's own input (a dead hook made it drop a held Ctrl mid
      Ctrl+C); #HotIfTimeout 150; settings/chooser/switcher context keys
      are live only while their window is up; hooks reinstall once per
      PACS focus, not every 10 s; the layout guard moves windows async and
      skips hung ones; toasts are built off the input thread.
    * Bug sweep (engine, config, delivery, GUI). Among the fixes: a key
      remapped to a mouse button no longer re-sends its Down on key
      repeat; a release over RadMapper's own window is no longer lost; a
      layer host held past 30 s stays held; PowerScribe/PACS keys are
      re-checked against the foreground right before sending and never
      sent in the background; panic/pause stop macros and close the
      window switcher; Rec on Settings is no longer overwritten by the
      field; seed-once defaults stay deleted after a reset; renaming the
      PACS profile keeps "PACS: send keys" working; saving is atomic.

  v0.7 (later) -- CAPSLOCK DICTATES; THREE LAYERS, NO MORE.
    * Layers are held open by button 4, button 5 or CapsLock only. Rows
      under any other host are dropped on load and named in Diagnostics;
      the hidden Layers page is gone (the tabs are the layers page).
    * CapsLock ships as dictation on a tap (seeded once into an existing
      config with no CapsLock row); its hold is the "Hold CapsLock" tab.
      A long press on it that uses nothing in the layer is silent.
    * PowerScribe/PACS keystrokes no longer leave Shift or the left button
      stuck: deliveries wait out a click, the watchdog releases an orphan,
      and Panic records what it found in Diagnostics.

  v0.7 -- FEWER WAYS FOR A BUTTON TO SURPRISE YOU.
    * LAYERS ARE TABS. The Mouse and Keyboard pages carry one tab strip:
      Base, Hold Button 4, Hold Button 5 and Hold CapsLock -- the QMK/ZMK
      picture of a keymap. A tab shows what every
      part of the mouse does WHILE that button is held; the editor no
      longer asks "Only while holding", it takes the layer from the tab.
    * SLOTS, NOT ROWS. Click a part of the mouse and the right side shows
      its two slots -- Tap it, Hold it down (Turn, for the wheel) -- each
      with what it does, Set/Change and Clear. Rows that need a modifier
      held keep a short list underneath.
    * THE MOUSE IS REDRAWN with nothing overlapping: a sunk channel down
      the middle holds the wheel column (up, tilt-left, click, tilt-right,
      down), the main buttons stop either side of it, and the thumb
      buttons sit on their own shelf.
    (Three review rounds -- Sonnet reviewers, Opus verifying each finding
    against the source -- closed 30-odd holes along the way: the pause
    hotkey now also drops queued PowerScribe keystrokes, keystroke delivery
    waits while a button is down, follow-focus never warps mid-gesture,
    watchdog recovery never commits a menu or a window switch, the
    clipboard hook never blocks, a cancelled shelf drag never pastes, a
    stale clipboard never reaches disk, tilt notches are dropped while a
    menu is open, and the Conflicts report warns only about delays that
    really happen.)
    Colleagues trying 0.6.6.5 found tap-holds and held-button chords
    getting in the way of ordinary mouse work. This release removes the
    machinery behind that and points what is left at the radial menu.
    * TAP AND HOLD ARE THE ONLY TRIGGERS. Double-tap, triple-tap and
      tap-then-hold are gone from the lists, the editors and the engine
      (no eager first press, no tap window, no wait mode); a row that
      carried one is dropped on load and named in Diagnostics. A withheld
      press now resolves to exactly one of tap or hold (FireTap).
    * ONE TIMING NUMBER. The tap window and the calibrator are gone; the
      hold threshold is a single field on Settings with a sentence.
    * LAYERS ON THE THUMB BUTTONS AND CAPSLOCK ONLY, one at a time. The pairs, the CapsLock reservation and right / middle as
      hosts are gone: a host is silent while held, and those buttons are
      window/level and pan. "Only while holding" and the Layer selectors
      are Advanced-mode controls.
    * LEFT, RIGHT AND MIDDLE ARE INSTANT EVERYWHERE. A hold on them is
      honoured only when written for one program; an everywhere hold row
      is refused by the editors and dropped on load. The per-program
      "instant clicks" switch, its config field and the Apps-page button
      are retired -- it is the rule now, not an exception.
    * RADIAL MENUS OPEN ON HOLD ONLY. The tap-opened, rest-to-fire menu
      (its 6 s timeout, second-tap cancel and radialRestMs) is gone; a tap
      row that opened a menu becomes a hold row on load. Releasing on a
      door fires nothing and says how the door works.
    * THE WHEEL AND THE PRESETS SHIP ON THE THUMB BUTTONS IN PACS: hold 4
      for the PACS wheel, hold 5 for the numbered window presets -- one
      gesture, no door. Seeded once into an existing config that has no
      radial row and nothing held on either thumb button in PACS.
    * WHEEL DECK SETTLE (deckSettleMs, 250). A deck button pressed while
      the wheel is still turning -- thumb lands mid-stack -- leaves every
      notch of that motion native; the deck takes over once the wheel has
      been still for the settle time. Settings > Timing.
    * Simple mode's action list is eleven entries, and wheel decks (the
      "Scroll wheel…" button, the deck settle setting) are Advanced, as
      the Layers page already was. Fresh configs no longer ship the [ and
      ] rows.

  v0.6.6.6 -- A HELD LAYER OUTRANKS A PROGRAM'S PLAIN ROW.
    * MatchScore: each held layer component is worth 16, a program match
      8, a modifier 1. It was 2 / 8 / 1, so in PACS "button 4 = F7"
      (program row, no layer) beat "hold right + button 4 = previous
      field" (everywhere, layer) -- the layer only worked once the same
      row was copied into PACS. Now: the layer row wins wherever it was
      written; a PACS layer row still beats an everywhere layer row; and
      with nothing held, PACS's plain row beats the everywhere plain row
      exactly as before. The Conflicts report says which row wins while
      a layer is held.
    * A live text field ends its own edit when the guard has given up on
      it, or after ten minutes with no keystroke, instead of running on
      with the program believing no field is open -- the way a dialog
      left open for a long time could stop taking clicks.

  v0.6.6.5 -- CAPS LOCK HOSTS A LAYER.
    "Hold CapsLock" is always in the "Only while holding" list, on the
    Mouse page and the Keyboard page alike, whether or not CapsLock has
    a row of its own. Its HOLD is reserved for that layer: a key row on
    CapsLock cannot be given the "Hold it down" trigger (the binding
    editor and the classic dialog both refuse it), while tap, double-tap,
    triple-tap and tap-then-hold rows on CapsLock work exactly as before.
    A quick tap of a CapsLock that hosts a layer and has no tap row of
    its own still toggles Caps Lock natively; a hold that arms the layer
    and goes unused does nothing, as a layer host's hold should.

  v0.6.6.4 -- THE WATCHDOG STOPS KILLING HELD LAYERS.
    "Hold button 4, scroll to switch windows": the switcher appeared and
    vanished, with "RadMapper recovered a stuck XButton1". The watchdog
    swept any state whose input no longer read as physically held, and
    AutoHotkey's physical-state table is WIPED whenever a hook is
    (re)installed -- which the switcher itself does the first time it
    binds its Delete key, and which SendInput, the tester and the radial
    cancel hooks do too. A held layer host then read as "up" and was
    released mid-gesture.
    * The sweep now applies ONLY to states that hold a SYNTHETIC button
      down (passthru, eager1, held): those are the ones a lost Up can
      leave stuck in the OS. A pending / armed layer host has nothing
      out, so a lost Up costs nothing; it gets the 30 s runaway cap only.
    * For the states it does sweep, a hook change since the press makes
      the physical reading untrustworthy (HookChanged stamps it), and an
      "up" reading has to persist for two ticks in a row.
    * A swept state is marked released (down := false) before it is
      cleared, so a switcher or a menu watching that holder commits
      cleanly instead of hanging on a state that no longer exists.

  v0.6.6.3 -- TILT WHEEL RELIABILITY.
    * A tilt over one of RadMapper's own windows went native. Every wheel
      notch over our own window is re-sent natively so our lists scroll --
      right for WheelUp / WheelDown, wrong for a tilt bound to a monitor
      hop: the pointer lands in the MIDDLE of the next monitor, which is
      exactly where the settings window sits while you are testing, and
      the next tilt then did nothing. Tilts resolve through the bindings
      wherever the pointer is; only the vertical wheel stays native over
      our windows.
    * The teleport flash (five overlay windows) was built INSIDE the
      wheel's Critical hotkey thread, so every notch arriving during the
      build queued behind it. It is deferred to a timer now; the hop
      itself is immediate.
    * A notch the tilt guard drops says so in the status bar ("ignored,
      within the tilt guard"), so a guard set too high is visible.

  v0.6.6.2 -- CHORDING FIXES and a CONFLICTS report.
    * A BUTTON THE DRIVER INJECTS. Trackball and mouse drivers that remap
      or chord a button (a middle click made by software, a thumb button
      turned into "middle") deliver it as an INJECTED event, and
      AutoHotkey never counts an injected press as physically held. The
      watchdog's "input physically up" sweep then released every hold of
      such a button ~750 ms in -- "recovered a stuck MButton", the native
      middle-drag ended, a held right button lost its layer mid-chord.
      A press now records whether it read as physical at all (st.physSeen);
      one that did not is never swept on physical state, only by the 30 s
      runaway cap. Key auto-repeat applies the same rule.
    * A USED LAYER HOST NEVER FIRES ITS OWN DANCE. Holding the right
      button and working the thumb buttons could still end in the right
      button's double-tap (a radial menu): CommitTaps now refuses to fire
      for a holder whose layer was used, and an eager first press that
      was used as a modifier does not arm a tap dance on release.
    * AN EXPLICIT HOLD BEATS "INSTANT CLICKS". A program profile with
      instant clicks dropped EVERY hold on L/R/M there, including a hold
      row written for that very program. A hold or tap-hold row scoped
      to the program in front is kept; only rows from everywhere are
      dropped.
    * CONFLICTS. Mouse, Keyboard and Diagnostics have "Conflicts…": one
      report of every place a button's meaning changes -- a program row
      that beats an everywhere row, a tap that waits because a double-tap
      or a hold is bound, a button that hosts a layer, a program with
      instant clicks, two rows for the same thing, a menu row with no
      menu. Copy it to send.

  v0.6.6.1 -- FOLLOW-FOCUS EXCEPTIONS. Settings > Behaviour has a "Follow
  focus except in" field: programs and windows where the cursor is never
  moved, however they come to the front. Entries are separated by ";" --
  a program file name (IntelliSpacePACSRadiology.exe), "title:" and part
  of a window title, or "class:" and a window class. "Grab window in
  front" adds the program that is in front three seconds after the click.
  This is on top of the per-program "No pointer jump" switch on the
  Programs page, which Simple mode hides.

  v0.6.6 -- the wizard is gone, the macro editor is native, the radial
  editor has a wheel you can drag, and deleting a row takes one key:
    * THE "SET A BUTTON" WIZARD IS REMOVED. Home, the Mouse page and the
      Keyboard page open the ordinary binding editor directly, in Simple
      mode as in Advanced. "Set..." on a Home essential opens that editor
      with the action already chosen.
    * Home's essentials card lists the five PowerScribe / pointer jobs;
      the PACS wheel and Window presets rows are gone from it (they are
      set up on the Menus page).
    * RADIAL EDITOR: "Program" and "Size" sit on the same row as "Name"
      with room to read, the Icon column is wide enough to show its name,
      and a live wheel on the right shows the menu as it will look. DRAG
      one wedge onto another to swap the two commands (the rows follow).
    * MACRO EDITOR: native. The Macros page lists macros on the left and
      the selected macro's steps on the right, with Add / Edit / Delete /
      Move up / Move down, a step dialog with Rec for key steps, and a
      Test run. The classic window is no longer opened for it.
    * DELETE A ROW FROM THE KEYBOARD: pick a row on the Mouse, Keyboard,
      Menus or Macros page and press Delete or Backspace. Right-click a
      row for Edit / Delete.
    * STUCK HIGHLIGHTS: the one-tick hover floor (LeaveCheck) now covers
      the open dialog and the open option list as well as the main window,
      and a rebuilt layer forgets the shape it thought was hovered.
    * TELEPORT vs FOLLOW FOCUS: a monitor teleport adopts the window it
      lands on and holds follow-focus off for a moment, so clicking there
      no longer bounces the pointer back to that program's pointer spot;
      and a pointer spot on ANOTHER monitor than the pointer is never
      warped to when the pointer is already inside the focused window.

  v0.6.5 -- the reading room on the front page, a rate limiter for tilt
  wheels, and the row buttons that could not be pressed:
    * BUG (workstation): "the button rows are not always able to be edited
      from the main panel and cannot be deleted at all." ROOT CAUSE, and it
      is three lines in three places. (1) Lumi.__ListDo writes view.sel and
      calls the list's onPick; the Mouse and Keyboard pages passed
      `(i, dbl) => (dbl ? Atlas.EditRow(i) : 0)`, so a SINGLE click painted
      the row and did nothing else, and the Apps page passed 0. (2) Edit and
      Delete are drawn once per frame with `Atlas.HasSel(rows.Length)`, and
      HasSel reads Atlas.savedSel, which is only refreshed at the top of
      Build(). (3) Build() runs from Tick() ONLY when the status signature
      changes. So after clicking a row nothing rebuilt the buttons, they
      kept the "muted" kind they were born with, and Lumi.Btn's muted case
      sets onClick := 0 -- a button with no handler at all. Delete could
      therefore never be pressed, and Edit only after something unrelated
      (an app switch, a new problem, a scope dropdown) happened to rebuild
      the frame: "not always able to be edited". Nothing was wrong with
      DeleteSel, SelectedRef or the confirm.
      FIX: Atlas.Picker(mode) is the onPick every panel list now hands to
      Lumi.List. It records the pick in the new Atlas.selWant and rebuilds,
      so the buttons wake up in the same frame; a double click still opens
      the row. Build() prefers selWant over the outgoing list's own sel,
      which is what lets the mouse map and the key tiles select a row too:
      PickZone and PickKeyTile ask for row 1, so clicking a part of the
      mouse that HAS rows leaves Edit and Delete usable, instead of
      inheriting the previous input's selection index. Deleting a row
      selects nothing afterwards rather than whichever row slid up into its
      place. check_source.py now asserts that no page can mute its row
      buttons without handing its list a picker.
    * RAZER TILT WHEELS FIRED FOUR TIMES. A tilt wheel does not send one
      WheelLeft when you tilt it; it sends one every 30-50 ms for as long as
      the wheel is held over, exactly like a held keyboard key, so a bound
      tilt produced "multiple repeated inputs causing unpredictable
      outputs". New settings tiltRepeatMs (150 ms) and wheelRepeatMs (0 =
      off), clamped 0..1000 in ValidateCfg: a notch arriving within the
      guard of the last ACCEPTED notch for the SAME input is dropped, so a
      held tilt is one press and a flick left then right is still two. The
      decision is WheelAccept(input, now, lastMap, limitMs) -- pure apart
      from the map, replayed against a fake clock in regression.ahk,
      including the 49.7-day A_TickCount wrap. Only BOUND (non-native)
      directions are limited: an inert row is plain scrolling and stays
      byte-for-byte hardware-native. Both fields are on the Pointer page;
      Simple mode, which hides that page, gets the tilt one on Settings.
    * HOME SHOWS THE READING ROOM. A new first card, "Reading room
      essentials", lists the seven things this program is for -- dictate on
      and off, next field, previous field, pointer to the left monitor,
      pointer to the right monitor, the PACS wheel and the window presets --
      with every trigger each one has today (buttons, keys and the Settings
      hotkey, in plain words, joined by "or", or "not set"), a Set button
      that opens the wizard with question 3 already answered, and a Clear
      button that removes them after asking. The five hotkey rows added to
      Settings in v0.6.2b (hkDictate, hkNextField, hkPrevField, hkTeleLeft,
      hkTeleRight) are gone from that page -- the settings themselves are
      untouched and still registered; they are set from the card now, where
      the key sits next to the button that does the same job. Settings
      keeps the four keys that are about RadMapper itself. WizWhat learned
      to say these actions as sentences, so the wizard's summary reads
      "Button 4, when you tap it, will start or stop dictation in
      PowerScribe" rather than quoting the action table at itself.
    * ZOOM AND PAN AS NAMED OUTPUTS. In IntelliSpace, Alt held with a
      left-drag is zoom and Ctrl held with a left-drag is pan -- which the
      engine has always been able to do (moddrag) and nothing ever said out
      loud. No new action type: the wizard's question 3 grew two tiles,
      "Zoom (Alt+drag)" and "Pan (Ctrl+drag)", that set moddrag with LAlt or
      LCtrl (seven tiles, four to a row, which is why everything below them
      on that dialog sits 46 px lower); the Details dropdown says "Alt --
      zoom in PACS" and "Ctrl -- pan in PACS"; moddrag is on the Simple
      action list; and a starter pack, "PACS zoom and pan on the thumb
      buttons", puts both on buttons 4 and 5 scoped to the PACS profile.
      The pack deliberately adds NO left-button row: a native row scoped to
      one app is not an inert row, so it would hook the left button inside
      PACS and turn every click into an injected resend.

  v0.6.4a (review pass 4) -- every item here is a fix to code that has
  still never run on Windows:
    * LOAD FIX (first workstation run): RadialIcon(name, x, y, ...) declared
      nested closures X/Y/S; AHK v2 treats X and the parameter x as one name
      and refuses to load ("conflicts with an existing parameter"). Renamed to
      gX/gY/gS. tests/check_source.py now asserts no nested function shares a
      name with an enclosing parameter.
    * LOAD FIX 2: Warp.Back had `if` / `try` / `else`; a try (braced or
      not) takes the else as its own clause. The if/else own the braces
      now. FIRST-RUN FIXES: names are case-insensitive -- RadialPaint used
      W and w as one variable (WD now), PanelPointer/PanelSettings used B
      and b (bands now), Warp.__Grid's local `line` shadowed the Line
      class it then called (hair now). check_source.py asserts all four
      shapes are absent file-wide.

    * THE SCRIPT DID NOT LOAD. `class Warp` declared `static grab` beside
      `static Grab()` and `static SUB` beside `static Sub()`. AHK property
      names are case-INSENSITIVE, so each pair is ONE member declared
      twice: a duplicate-declaration error at load time, before a single
      hotkey is registered. Renamed to `grabbing` and `NINTH` (the methods
      keep their names -- they are what the rest of the code calls), and
      check_source.py now runs its case-insensitive collision check over
      EVERY top-level class this file declares, not just Lumi and Atlas,
      finding each class body by brace depth with comments and string
      literals stripped first. regression.ahk asserts the two members exist
      so a rename back shows up as a test failure rather than as a script
      that will not start.
    * A DIRECTION BELONGS TO ONE SLICE WENT TOO FAR. v0.6.4 gave every
      ring Kando's half-gap wedges, so at the ROOT a flick 30 degrees off
      north in a 4-way menu selected nothing and the press was simply
      lost -- and in the 9-way preset ring, where the whole circle is
      numbers, 20 degrees of the 40 belonged to nobody. Dead space is only
      worth having where a bearing that lands in it MEANS something, and
      the only ring where it does is a child ring, where it means back.
      So: a root ring and a numbered preset ring are PARTITIONS -- every
      slice owns its whole sector, a bearing on a shared edge going to the
      lower-numbered slice -- and only a child ring keeps half the gap and
      hands the rest to `back`. A numbered child ring keeps a zero-span
      `back` marker, purely so the parent node and its connector are still
      drawn; no bearing selects it. Cancelling is still the hub, Escape,
      or a click. The hairline loop now draws each boundary ONCE (on a
      full ring every edge is shared, and a 1 px line drawn twice is 2 px).
    * A WHEEL CANNOT BE LEFT BEHIND. Layer() creates a window and Draw()
      blits one, and both pump messages, so a hotkey thread could close or
      replace the menu while a paint was inside the constructor -- leaving
      a click-through, top-most layer over the study with nothing holding a
      reference to it. RadialPaint and RadialRing are Critical, the paint
      checks that the menu it started on is still the live one and disposes
      the layer if not, and every layer is registered in g_RadialLayers,
      which RadialClose, PanicRelease and Cleanup sweep.
    * A CLICK CANCELS A PRACTICE WHEEL. The trial exemption in the
      click-cancel gate, in RadialCancelActive and in RadialCancelHit meant
      a practice wheel could only be closed by Escape or by waiting out its
      20 s floor -- the one window in RadMapper you had to sit through.
      Cancelling is as much a part of the gesture as the flick is, so it is
      a thing to practise. It returns to the settings window through
      RadialClose's trial branch, exactly as Escape already did.
    * THE FOCUS KEYS AND THE KEYBOARD POINTER STOP FIGHTING. Warp owns Tab,
      Space, Enter and the arrows while it is up -- they are how it is
      driven -- so Atlas.DoFocusKey stands down while it is active, the way
      it already does for a Rec capture and a live Field. And Warp refuses
      to open over the settings window, which is the fourth thing (after a
      menu, the switcher and the calibrator) that drives itself from those
      same keys.
    * TAB SURVIVES A WIZARD ANSWER. Every wizard tile rebuilds the dialog
      on a new layer, and a new layer meant a new focus ring: Tab, Tab, Tab,
      Space and the ring jumped back to control 1. The position and whether
      the ring is showing at all now travel on the draft (Atlas.WizRefocus
      -> Lumi.Focus.Reset's new idx), clamped to whatever ring the rebuild
      produced. Closing a dialog that was being driven from the keyboard
      re-arms the page behind it. A mouse user still never sees a ring.
    * STEPPING THE ACTION DROPDOWN WITH THE ARROWS REOPENS THE WIZARD ONCE.
      Left/Right fire onChange on every press, so walking the sixteen
      actions crossed the Details-widget family line four or five times and
      tried to rebuild the dialog each time -- each rebuild disposing the
      dropdown the next arrow press was aimed at. Lumi.SelectNudge marks
      itself while it calls onChange and the rebuild is debounced 400 ms
      behind a cached BoundFunc; the hint still follows every press.
    * Atlas.IsFront IS THE #HotIf CONTEXT FOR ESCAPE, F1, FOUR RESIZE
      COMBOS AND ALL EIGHT FOCUS KEYS, so it is asked on every press of
      Tab, Space, Enter and the arrows anywhere in Windows -- while
      dictating, while typing a report. It answers 0 without a WinActive
      call when there is no settings window or it is hidden.
    * THE RADIAL SAFETY FLOORS MEASURE THE WHOLE MENU. The 15 s held floor
      and the 6 s / 20 s latched floors were measured from R.t0, which
      RadialRing restarts on every walk-in and walk-back -- so a gesture
      that kept opening rings never aged. R.openedAt is set once, in
      RadialOpen; t0 stays the per-ring dwell clock.
    * A CORNER INSIDE THE HUB OPENS NOTHING. The marking-mode corner path
      read a bearing from the turn point without checking it was outside
      the dead zone, so a stroke that curled back through the centre could
      open whichever door lay that way, or walk back out of the ring.
    * F1's MsgBox is wrapped in StopTick/StartTick, as Atlas.Confirm
      already was: the 700 ms status tick does not stop for a blocking box,
      and a Build() landing while it is up disposes the layer that owns it.
      Its radial paragraph, and the README's, are rewritten to say what the
      wedges now do; the wizard's hint moves up into the Details row's
      place when question 4 hides it.

  v0.6.4 (radial menus: Kando-inspired):

    * A DIRECTION BELONGS TO ONE SLICE, OR TO NOBODY. Selection was "the
      nearest slice centre", which hands every bearing to somebody: in the
      9-way preset ring a flick 20 degrees off north fired the NEIGHBOUR.
      Each slice now owns only the inner half of the gap to each neighbour
      (Kando's scaleWedge 0.5), it is DRAWN as that arc, hairlines mark the
      boundaries, and the hovered arc is washed in pink. Everything left
      over is nobody's: at the root it selects nothing (release = cancel),
      and in a second ring it -- together with the whole direction that ring
      was entered from -- is the way BACK, which commits nothing. Slice
      DIRECTIONS did not move: a root ring is the same fixed compass.
    * A SECOND RING OPENS WHERE THE GESTURE TURNED. Holding and flicking
      through a door no longer needs a pause: a sharp turn (90 px of
      straight stroke, then more than 20 degrees, past a 10 px jitter
      floor) or 100 ms of stillness opens it, re-centred on the CORNER and
      clamped onto the monitor with a 120 px margin. Resting on a door
      still works. Leaves are unchanged and still fire on release only, so
      no gesture can send a command mid-flight. The pointer is never
      warped: the button is physically down.
    * THE CHILD RING LEAVES THE WAY BACK A SLOT OF ITS OWN -- 360/(n+1)
      spacing starting one step past the parent direction (Kando
      computeItemAngles), with the parent drawn as a small node in its true
      direction and a connector line to it. The numbered preset ring is
      exempt: there the slot IS the number.
    * THE HUB SAYS WHAT IS ARMED AND WHAT IT SENDS: the hovered command's
      name, and under it its keys in the muted style; the menu's own name
      when nothing is hovered; "practice -- nothing is sent" as before.
    * THE WHEEL MOVES WITH THE HAND. What the pointer is near grows to
      1.15 over 250 ms and its neighbours ease back by angular distance,
      the ring fades in over 75 ms, icons sit in discs with the word
      outside them on the ring, a door wears one dot per command behind it,
      and the stroke is drawn back at you from the ring's origin, fading
      toward the tail. Two switches on the Menus page -- "Animate the
      wheel" and "Show wedges" -- turn the movement and the arcs off; with
      animation off the tick repaints on selection changes alone, exactly
      as it did before. There is no fade OUT: a closing wheel may not leave
      a timer behind it, and a blocking fade would sit between the release
      and the command.

  v0.6.3 (setup by keyboard, mouse buttons as outputs):

    * THE WHOLE SETTINGS WINDOW WORKS FROM THE KEYBOARD. The widget kit
      keeps a focus ring per layer (Lumi.Focus): every button, switch,
      field, dropdown, slider and list registers itself as it is built, in
      the order it was built. Tab and Shift+Tab walk it and draw a 2 px cyan
      ring around what is focused, Enter or Space presses it, Left/Right
      steps a dropdown, nudges a slider and flips a switch, Up/Down moves a
      list's selection, and Escape keeps the meaning it always had. The ring
      is not drawn until Tab is pressed, so nothing changes for a mouse; a
      dialog opens with its first control focused. Muted (nothing-selected)
      buttons are skipped. The keys are `~`-prefixed and inert while a Field
      owns the keyboard, while an option list is open and while Rec is
      capturing -- typing a space types a space, and the key you record is
      never also the key that pressed Rec.
    * MOUSE BUTTONS ARE OUTPUTS. The wizard's third question gained five
      one-click answers -- Left click, Right click, Middle click,
      Double-click, Click lock -- and the Simple action list gained the
      three actions behind them, so "make button 4 the middle button" is
      two clicks rather than a typed code.
    * CLICK LOCK IS PROGRAMMABLE FROM THE UI. The five actions that take an
      INPUT as their value (native, dblclick, dragmove, clicklock, moddrag)
      no longer show a free-text Details field: the binding editor shows a
      dropdown of plain names, and the wizard asks a fourth question --
      "Which button should it hold?" -- when Click lock is chosen. Blank
      still means what it always meant, and it is spelled out: "Whichever
      button is held" for the lock, "Same as this input" for the rest.
      Nothing changed in the engine: ClickLockToggle has always resolved a
      named input through ResolveInputValue, and the middle-button warning
      is about middle-button TRIGGERS, not middle-button outputs.

  v0.6.2c (review pass 3, stations + keyboard pointer) -- everything here
  is a fix to v0.6.2 code that has still never run on Windows:
    * UIA SNAP WAS READING THE WRONG VTABLE SLOT. 43 is get_CurrentLabeledBy,
      not get_CurrentBoundingRectangle (42) -- N snapped to a rectangle made
      of the low and high halves of a leaked element pointer. The name BSTR
      is freed in a `finally`, and a failed call now drops the cached
      IUIAutomation so the next press rebuilds it instead of failing for the
      rest of the session.
    * THE LOUPE IS ALIGNED WITH ITS OWN PICTURE. The magnified bitmap is
      scaled to the box by the kit ("w320 h320") rather than nudged there
      with four bmp* offsets, and every overlay inside it (region box,
      thirds, letters, crosshair) is drawn at the TRUE ratio LW / sw, not at
      the requested zoom -- which differ, because sw is rounded.
    * PER-MONITOR-V2 DPI AWARENESS IS SET AT STARTUP, before the config is
      read. MigrateLayoutSlots derives every legacy slot's fractions from the
      monitor work areas and the first StationKey() stamps a station
      identity; on a mixed-scaling desk both were reading virtualised pixels.
    * A LAYOUT IS ONLY STAMPED WITH THIS STATION IF IT PLAUSIBLY BELONGS TO
      IT -- every slot centre on a real monitor -- and an IMPORTED config is
      never stamped at all. A wrong stamp means "apply pixel for pixel",
      which is the one thing a foreign layout must not do.
    * WINDOWS THAT ARE NOT ARRANGEMENT MEMBERS ARE LEFT ALONE: owned windows
      (dialogs, PowerScribe's signing prompts) and windows with no
      WS_THICKFRAME. Each slot remembers its window CLASS, and the two loose
      match steps stay within it, so the IntelliSpace worklist and viewer
      stop swapping places. A minimised or owned PowerScribe window is never
      restored or moved from the guard tick (skill §2's standing rule).
    * WARP CLICKS NO LONGER INHERIT CTRL+ALT. The pointer is reached by a
      modifier chord and the InputHook leaves modifiers visible, so Space
      was sending Ctrl+click into the study. Every click, grab and wheel
      puts the modifiers up first (Warp.ClearMods). The wheel is POSTED to
      the window under the crosshair rather than sent to the focused one.
    * THE GUARD IS RE-ARMED AFTER A RESTART: the flag lives on the layout,
      but nothing read it back at startup, so "always" was a label with no
      timer behind it until the layout was applied by hand.
    * "Place NEW windows" keeps its record PER LAYOUT, writes it only on the
      mode-2 path, forgets it when the guard is armed or disarmed, and
      prunes dead hwnds every tick (Windows recycles handles).
    * IMAGING SCREENS: the pixel rule is ranked against the MEDIAN screen,
      not the smallest, and when every screen would be reserved the rule
      narrows to the portrait screens, or to the largest one, instead of
      giving up and reserving none.
    * THE WINDOWS PAGE FITS AT 940 px. The three window hotkeys use the
      stacked row form in three 220 px columns; the arithmetic is in a
      comment and check_source.py asserts it. "Saved on" names the station
      instead of counting its screens, and the Keep button says which state
      the selected arrangement is IN, with the next one underneath.
    * STATION WATCH INTERLOCKS: the settle pass refuses while a mouse button
      is physically down, while our own resize grip, the keyboard pointer, a
      radial menu, the app switcher or the calibrator is live, and while any
      monitor still reports zero area. WM_DISPLAYCHANGE closes the keyboard
      pointer. "Screens changed" is announced even when auto-apply is off.
    * ValidateCfg validates LAYOUTS AND STATIONS too (guard to 0/1/2, rects
      to Integer, fractions to Float or the slot goes, keyless stations
      dropped) -- they are read from timer threads, where a thrown error is
      a feature that stops working with nothing on screen to say so.
    * Captured fractions are clamped to their own screen (an invisible
      resize border used to give fx = -0.004), and the fw/fh floor is 0.005
      instead of 0.1 -- a tenth of a 4K screen is 384 px, which was
      inflating every narrow tool window on every adapt.
    * Smaller: WinMaximizeOn sizes the window to fit before maximising;
      tiling compensates the DWM invisible border; the no-affinity loupe
      fallback hides only the layers that intersect the capture (the HUD
      included) and the affinity probe is answered once, not per open;
      Warp refuses to open over a menu, the switcher or the calibrator;
      StationKey is computed once per apply, not once per slot.

  v0.6.2b (review pass 2, settings UI) -- wording, honesty and reach:
    * ONE VOCABULARY for the buttons: "Button 4 (thumb, back)", "Button 5
      (thumb, forward)", "Button 3 (wheel click)" everywhere, and the mouse
      map's caps are the same numbers. Events are words too -- "Tap it",
      "Hold it down", "Turn the wheel" -- through EVENT_LABELS.
    * NO FALSE SUCCESS. The wheel deck, the timing calibrator, the
      scratchpad, the starter packs and the wizard all report "Applied for
      now - not written to disk" when the save failed, instead of "Saved".
    * The DUPLICATE-ROW question is asked for edits too, not only for new
      rows, and it says the existing assignment will be deleted.
    * CONFIRMATIONS on the three buttons that threw work away silently:
      Reload from disk, Import config (which names the count and the backup
      folder) and deleting a scratchpad snippet. A failed import now says
      so instead of rolling back in silence.
    * SETTINGS HOTKEYS are usable: every row has a Rec button and its value
      spelled out underneath ("Ctrl + Alt + Shift + F9"), the PowerScribe
      rows are named after PowerScribe, and the two pointer teleports have
      keyboard rows at last.
    * PRACTICE is practice: the cancel keys are bound in trial mode too,
      the hub says "practice - nothing is sent", the latched auto-commit
      cannot fire, and the wheel stays up for 20 s.
    * Adding or duplicating a menu no longer leaves the new menu alive in
      memory and invisible on screen when the file cannot be written.
    * CONTRAST: "danger" is border-only now; its label uses the new
      dangerInk token. check_source.py checks eight more text/ground pairs.
    * Keyboard operability, minimally: Up/Down/Enter in the Chooser and in
      an open dropdown; F1 says where full keyboard operation lives.
    * Simple mode no longer offers actions whose editors it hides (macro,
      layout); the Keyboard page gets the same wizard the Mouse page has;
      buttons that need a selected row are drawn inert until there is one.

  v0.6.2a (review pass 1) -- correctness fixes, no new features:
    * A held action is RELEASED, not orphaned, when a press falls through to
      the native path (engine paused, our own GUI, a click-lock latch).
    * OS keyboard auto-repeat re-fires only repeat-safe tap actions, rate
      limited by repeatRate; dictation, macros, Run and radial menus no
      longer fire dozens of times for one held key.
    * "Focus blocked - key delivered in background" now says the window
      would not come forward: ControlSend into WPF is best effort at best.
    * PACS "already active" no longer counts the WORKLIST as the viewer, so
      viewer keys stop landing in the work list.
    * A full delivery queue reports the dropped keypress instead of
      dropping it silently.
    * A click cancels a live radial menu instead of falling through it into
      the study; the three mouse buttons are hooked for the menu's lifetime.
    * The watchdog restores the system cursor if it is hidden with no drag
      scroll running, and OnError restores it too.
    * A hold-only row fires at the threshold, not at press, unless its
      action actually has a hold phase (StatefulHoldType).
    * Panic stops a running macro between steps.
    * Teardown CANCELS an open radial menu instead of committing a slice.
    * MButton hold / tap-hold / layer-host rows warn before saving (middle
      drag is how IntelliSpace pans).
    * The Up of a key claimed by the keyboard pointer is swallowed even
      after the overlay has closed.
    * holdThreshold and tapWindow are clamped at every timing read
      (HoldMs / TapMs), so a hand-edited 0 cannot spin a timer.
    * ValidateCfg drops wrong-shaped app noHold / noFollow / park fields.
    * The foreground-lock timeout is saved at startup and restored on exit.
    * Five HotIf binders clear their context in `finally`.

  v0.6.0.2-preview (Codex second pass; Windows verification pending):
    Guided radial setup, four/eight-way direction preservation, reference-safe
    rename, explicit shortcut validation, foreground cancellation, reliable
    preview return timer, retained failed-save state and transactional import.
    F1 quick help, clearer Home defaults, readable hints and softer pink.

  v0.6.2: WINDOWS THAT FOLLOW YOU BETWEEN STATIONS, and a KEYBOARD POINTER.

    * STATION-AWARE ARRANGEMENTS. A saved window arrangement used to be a
      list of absolute rectangles, which is meaningless at any station but
      the one it was captured on. Every slot now also remembers its SCREEN
      (counted left to right) and its place on that screen as fractions of
      the work area. On the capturing station it applies pixel for pixel;
      anywhere else it ADAPTS: screens are mapped by relative position onto
      the screens that exist, imaging screens (portrait, or markedly more
      pixels than the smallest -- or listed by hand) are kept for the
      viewer and refused to everything else, and maximised stays maximised
      on the mapped screen. A maximised window on the WRONG screen is now
      corrected, too; it used to count as done.
    * STATIONS. The monitor set is the station's identity
      ("1920x1080|2048x1536|1920x1080"). Each station names the arrangement
      that belongs on it (the first one saved there, by default) and which
      screens are imaging screens. When the monitor set changes -- dock,
      KVM, a display waking late, logging in elsewhere -- the engine
      recognises the station and applies its arrangement; on launch too.
      "Keep in place" gained a gentle third mode, NEW WINDOWS: a window is
      placed once, when it first appears, and never touched again, so PACS
      opened after RadMapper lands on the right screen and a window you
      then move stays moved.
    * WINDOW BY KEYSTROKE. The action "Window: move / fill" sends the ACTIVE
      window to a screen (next, prev, here, 1-9) and/or a tile (max, left,
      right, top, bottom, corners). Three Settings hotkeys for the common
      three, unassigned by default; the Windows page has the fields.
    * KEYBOARD POINTER (Ctrl+Alt+G). The keyboard version of "mouseless": a
      lettered grid over the screen under the pointer (column letter, then
      row letter), then Q W E / A S D / Z X C zoom into ninths down to the
      pixel, with a LOUPE beside the pointer showing the region magnified
      and the same nine letters drawn over it -- a 14 px PACS toolbar
      button is picked by reading a letter off a picture of it. Space
      clicks, R / M / F right, middle, double; G grabs so the next moves
      DRAG; N snaps onto the control under the pointer (UI Automation);
      Tab and 1-9 change screen; arrows nudge; Esc closes. An invisible
      InputHook owns the keyboard while it is up (nothing typed reaches the
      viewer), modifiers stay live for the panic key, engine key rows are
      gated, and a 45 s idle timeout guarantees the keyboard comes back.

  v0.6.1f: THE "SET A BUTTON" WIZARD. One dialog, three numbered
  questions -- which button (tiles: Button 4, Button 5, Button 3, or record
  a key), when (Tap / Hold), what (the short action list, a Details field
  with Rec and Keys, and a program). Save writes an ordinary row through
  the same validator and UpsertBinding the editor uses and lands on the
  page that shows it. "All options…" hands the same draft to the full
  editor. In Simple mode it is what Home's "Change what a mouse button
  does" and the Mouse page's "Set a button…" open; Advanced mode keeps
  the full editor there.

  v0.6.1e: STARTER PACKS. Home > "Apply a starter pack" lists five named
  sets of ordinary bindings -- PowerScribe on the thumb buttons, the PACS
  wheel on button 4, Window presets on button 5, drag scroll on button 5,
  and the shipped monitor hopping -- and applies one in a click through
  the same UpsertBinding the editor uses. Anything a pack would replace is
  listed and confirmed first. There is no pack state: the result is rows
  on the Mouse page, editable and deletable like any other. "Test my
  mouse" moved off Home; it lives on the Diagnostics page.

  v0.6.1d: SIMPLE MODE, on by default. The rail shows Home, Mouse,
  Keyboard, Menus, Settings and Diagnostics; the action dropdown shows the
  sixteen things a radiologist actually binds (plus whatever a row already
  uses). One switch on Home ("Show advanced pages and every action") adds
  Layers, Macros, Apps, Windows, Pointer and the full 32-entry table.
  Nothing is removed and no config changes: hidden pages keep their slot,
  and each dropdown carries its own code list so a row's meaning never
  depends on which list drew it (Atlas.ActSelect / Atlas.ActCode).

  v0.6.1c: two things that looked broken and were.
    * THE RADIAL MENU BLINKED while held. Every repaint (each slice
      change) re-applied the window's extended styles and re-inserted it
      topmost; on a visible layered window that is a flash. Styles are
      set once when the wheel's window is created.
    * DRAG SCROLL "JUMPED BETWEEN TWO POINTS". That was the pin: the
      cursor is warped back to the anchor every 10 ms, and the hand moves
      it a few pixels first, so the eye sees it flicker between the two.
      While pinned the pointer is now HIDDEN and a small ring marks the
      anchor (scrollPtrHide; the ring says where the scroll is held).
      The system cursors are restored on stop, on panic and on exit.

  v0.6.1b: the shipped PACS wheel now REPLACES an edited "PACS" menu too.
  The edited one is kept as "PACS (previous)", opened only by that name,
  so nothing is lost and the button that opened "PACS" opens the new one.

  v0.6.1-preview also adds "PACS: SEND KEYS", the PowerScribe routing
  pointed at the viewer: from any app, PACS is brought forward by its
  Apps-tab profile (exe, never a handle), the keys land, and focus returns
  to where you were. It prefers the window whose title contains pacsWindow
  ("VirtualMonitor": IntelliSpace's viewer rather than its worklist), and
  falls back to whichever PACS window was last active. Same serialized
  queue as PowerScribe, so bursts land in order and panic aborts them.
  Available as an action, a radial slice and a macro step (pacskeys).

  v0.6.1-preview: radial menus you can get OUT of, get INTO, and read.
    * SECOND TAP CANCELS. A tap-opened (latched) menu could only be left
      by Escape or a 6 s timeout; a hand on the mouse has neither. Tapping
      the same button again closes it, and a press while any menu is up
      closes that menu instead of stacking another.
    * HOLD, MOVE, RELEASE is the gesture when the menu is bound on HOLD
      (which "Assign a button" does). Release in the hub, or Escape, fires
      nothing. Bound on TAP, the menu latches and fires by resting.
    * MENUS INSIDE MENUS, depth two. A slice whose action is "Radial menu"
      is a door: rest on it while holding (radialSubMs, 340 ms) and that
      menu takes the wheel's place, re-centred under the cursor, still
      held -- hold, "Windowing", pause, "3", release. Releasing ON the
      door opens the same menu latched, so both habits work. Doors show
      a wheel glyph and a › after their name.
    * A 9-SLOT NUMBERED RING for window presets: the slot number is the
      key it sends (1-9), printed large, the preset name small beneath.
      It is the one exception to the 8-way limit and exists for this job.
    * ICONS. A slice can carry an icon name (Icon column in the editor):
      next, prev, delete, ruler, roi, clahe, window, magnify, series,
      menu, zoom, invert, reset, dictate -- vector glyphs drawn with the
      wheel's own primitives, recoloured with the slice state.
    * THE PACS MENU SHIPS FILLED: Next series F8 (up), Ruler R, ROI
      Shift+R, Magnify Y, Prev series F7 (down), Delete, Windowing (a
      door to "Window presets"), CLAHE Shift+C. The "Window presets" ring:
      1 Soft tissue, 2 Bone, 3 Brain, 4 C-spine soft tissue, 5 CTA,
      6 Infarct, 7 Liver, 8 Lung, 9 Lung wide. An existing config whose
      PACS menu is still the untouched eight-blank template gets the new
      one once; a PACS menu you have edited is left alone.

  v0.6.0.2-preview review pass (on top of the Codex second pass):
    * Radial menus cancel when the foreground moves to another PROCESS,
      not another window handle. syngo.via, PACS viewers and browsers hand
      the foreground between their own top-level windows unprompted (the
      v0.4.9 follow-focus lesson), and a handle compare cancelled gestures
      exactly where the menu is wanted. Our own layers never count.
    * "Not saved" in the header now means a save FAILED (or is blocked),
      not that a 400 ms slider debounce is pending -- g_CfgSaveFailed.
    * Placeholder / helper ink is 9A9FBE: >= 4.5:1 on every ground and
      still dimmer than secondary text, so the hierarchy reads.
    * JSON numbers are matched in place (\G at the position) instead of
      copying the rest of the document per number.
    * Home's "Test my mouse" lands on the classic Diagnostics tab, which
      is where the live input monitor is; the config path has its label.
    * The UTF-8 byte-order mark that the second pass introduced at byte 0
      is removed again, so the file diffs cleanly.

  v0.3 was a DELIBERATE SIMPLIFICATION of v0.2. Everything that made the
  engine hard to reason about -- the free-spin scroll engine (smoothing,
  acceleration, momentum, coasting), autoscroll, OS pointer-acceleration
  forcing, 8-way gestures + the ring overlay, and two-button chords -- was
  removed, and keyboard remapping (which never fired in v0.2) was fixed.
  v0.3.1 fixes input-to-input remapping, and adds click lock, drag scroll
  and a double-click output. v0.3.2 adds NumLock pause and follow-focus,
  and clears the load-time warnings the GpGFX bundle exposed. v0.3.3
  fixes the white-out and moves to the three-hue palette. v0.3.4 strips
  the gradients and the other generic tells, splits monitor teleport into
  two plain actions, and flashes the monitor the cursor lands on. v0.3.5
  makes the dropdowns scroll (they were truncating at 12 items and hiding
  half the action list) and redraws the mouse schematic to match the
  hardware. v0.3.6 adds per-app park points (a captured screen spot the
  cursor returns to, per application) and a Layers panel that shows which
  buttons host a hold layer and how many rows each one arms.

  v0.3.7 is a UI repair release. Every widget now records the LAYER IT WAS
  BUILT INTO instead of reading the global active layer when a click
  arrives, which is the single root cause of both reported failures: the
  binding dialog's Value field would not accept a keystroke (its edit loop
  asked the wrong window whether it still had focus and quit on the first
  pass), and dropdowns inside the dialog opened at MAIN-WINDOW coordinates,
  detached from the control that opened them, then redrew the wrong window
  when picked. Only one option list can be open at a time now, it closes on
  focus loss or Escape, and every teardown path disposes it -- a list left
  floating over a rebuilt panel was a live window still writing into dead
  state, which is how picks landed on unrelated buttons. The three value
  tools the classic dialog always had -- Rec, Keys, Input -- are back in the
  vector dialog, alongside a live action hint. The Keyboard panel is now the
  Mouse panel: same App and Layer scope selectors in the same place, a key
  picker where the mouse map goes, the same row list, the same buttons,
  inert rows shown rather than hidden, and key layer hosts routed to the
  Keyboard tab from the Layers panel. And the mouse schematic derives its
  main buttons from the body outline instead of guessing at them, so they
  no longer hang over the shell, with the wheel and tilt column sitting on
  top of the L/R seam where the hardware puts it.

  v0.3.8 makes the dropdowns SCROLL, which they have never actually done.
  The scroll code added in v0.3.5 was correct and simply never ran: the
  bundled GpGFX hit-tests WM_MOUSEWHEEL using lParam as client coordinates,
  but that one message carries SCREEN coordinates, so the search for a
  shape under the pointer always came up empty and no wheel handler fired.
  Fixed in place (GpGFX modification #2, §15). Popups are now also sized to
  the monitor rather than to a fixed 14 rows, so the 24-item action list
  opens whole -- which is what actually hid "Sniper speed", "Boost speed"
  and "Drag scroll": they are items 15, 16 and 17, the first three past the
  old window, and the wheel that was supposed to reach them did nothing.

  v0.4.0 is a feature release, and the first since v0.3.5 that is not
  mostly UI repair.

    * WHEEL DECKS. Hold an input, scroll for an output -- programmed in one
      dialog with all four directions (up, down, tilt left, tilt right) on
      screen at once, on both the Mouse and Keyboard panels. It writes
      ordinary layer-scoped wheel rows, so a deck stays editable as rows.
    * WINDOW SWITCHER. The built-in use for a deck: hold, scroll a list of
      windows that STAYS UP while you scroll (which is the thing Alt+Tab
      will not do), release to switch.
    * WINDOW LAYOUTS. Capture where every window sits across the monitors,
      put the whole arrangement back by name or by binding, and optionally
      ARM a guard that snaps windows back when an application moves or
      resizes them on its own. New "Windows" panel.
    * PASS THROUGH. An action that lets the application's own binding run,
      for carving one app or layer out of a broader remap.
    * TAP-HOLD CALIBRATOR. Measures your own taps, holds and double-taps and
      sets the two timing numbers from them instead of from a default.
    * The HUD no longer appears at the cursor. It parks in a corner --
      bottom-left by default -- of the monitor under the pointer.
    * The window can be RESIZED (corner grip, maximise toggle, size
      remembered) and the binding dialog can be MOVED. The Settings panel's
      overlapping controls are laid out on declared bands.
    * The design gallery is now an interactive, closeable rendering and
      input self-test with a live event log, and says plainly that it
      changes nothing.

  v0.4.1 fixes the thing that made every previous release feel like starting
  over, and adds two shelves.

    * THE CONFIG NO LONGER LIVES NEXT TO THE SCRIPT. It lived in
      A_ScriptDir, so a new RadMapper.ahk in a new folder found no config and
      wrote fresh defaults -- which is why the bindings appeared to be lost
      on every upgrade. Nothing ever was: the old file is still beside the
      old copy. It now lives in %APPDATA%\RadMapper, one place per user,
      found by every future version with no migration. On first run it
      ADOPTS the newest config it can find from an older install, a corrupt
      file is recovered from the newest good backup instead of being replaced
      by defaults, and the Settings panel shows the path at all times.
      Portable mode is still available: drop a file named
      "RadMapper.portable" beside the script.
    * CLIPBOARD SHELF and SCRATCHPAD, summoned to the cursor (Ctrl+Alt+C,
      Ctrl+Alt+N, both rebindable and bindable to any input). Click a row to
      paste it back where you came from, or drag a row onto any window to
      drop it there. The clipboard history is MEMORY ONLY and never written
      to disk -- this is a shared workstation and a clipboard here holds PHI.
      The scratchpad is saved, because saved phrases are its whole point.
    * DRAG ZOOM, the drag-scroll engine emitting Ctrl+wheel.
    * A fresh config now SHIPS WITH BINDINGS instead of a clean slate:
      ` dictates, the thumb buttons teleport between monitors, and [ / ]
      step report fields on tap with drag scroll / drag zoom on hold.

  v0.4.2 is a one-bug crash fix. Teleporting between monitors could kill the
  script outright with "Critical Error: Invalid memory read/write" -- an
  error AutoHotkey does not let you catch. The fault was in the bundled
  GpGFX: LayerStack.ActiveLayer keeps an UNOWNED raw pointer, and its getter
  resurrected that pointer without checking it was still a live layer while
  its setter immediately dereferenced it. Any code that saved the active
  layer, created or disposed layers, then put the saved one back could
  therefore read freed memory -- and that idiom appears about sixty times
  here plus inside GpGFX. v0.4.1 made it near-certain rather than rare: a
  teleport builds and tears down FIVE layers, and v0.4.1 put teleport on the
  thumb buttons by default. Fixed at the source as GpGFX modification #3;
  the teleport code itself was never wrong.

  v0.4.3 finishes click lock.

    * A PROGRAMMABLE LOCK KEY (Ctrl+Alt+B by default, edited in the Pointer
      tab). It latches WHATEVER is being held, so a lock no longer has to be
      bound per button. The clicklock action still exists, unchanged.
    * THE NEXT KEYSTROKE RELEASES IT. Reaching for the keyboard is itself a
      statement that the sweep is over. Bare modifiers are exempt, so Ctrl
      or Shift can still modify a locked drag; keystrokes RadMapper itself
      sent are exempt, so a macro or a W/L digit does not drop it; and the
      key that ARMED the lock is exempt, or its own auto-repeat would.
    * A LOCK WITH NOTHING HELD IS A NO-OP. It used to fall through to
      LButton and latch a button the user was not touching -- a synthetic
      left-button-down out of nowhere, which on an image is a click, a drag
      or a measurement.

  v0.4.4 is three reported bugs and two follow-ons.

    * "APPLY WINDOW LAYOUT" OPENED THE CLIPBOARD. ACT_LABELS had drifted out
      of order against ACT_CODES: "layout" went into CODES before the two
      shelf codes but its LABEL went in after them, so entries 23-25 carried
      each other's names and picking one saved a different action. Order is
      the contract between those two arrays and nothing was checking it;
      tools/check-actions.py now does.
    * THE SNIPER AND BOOST SLIDERS WOULD NOT MOVE. A slider mutates the
      shapes it was built with as the pointer moves, and the 700 ms status
      tick rebuilds the panel -- disposing exactly those shapes mid-drag.
      Atlas.Build() now defers while the left button is physically down,
      which covers every drag, not just sliders.
    * THE CALIBRATOR DID NOTHING. Its InputHook was built as
      InputHook("V L0"), copied from RecordCombo -- a different kind of hook,
      one that collects and ends. "L" is a length limit, and a length limit
      on a notify-only hook ends it before a single key is seen. The window
      drew and the hook feeding it was already over. The same construction
      bug was in the v0.4.3 click-lock watcher; both are fixed, and neither
      swallows a start-up failure silently any more.
    * LAYOUTS CAN BE PICKED FROM A LIST. Bind "Apply window layout" with a
      BLANK value and it opens a chooser at the cursor instead of requiring
      the layout's name typed into the value field. One input, every layout.
    * The window switcher now opens AT THE CURSOR, like the shelves and the
      new chooser, rather than in the HUD corner.

  v0.4.5 is window chrome and the wheel.

    * MINIMISE EXISTS, and the three window buttons are aligned. They sat at
      y=44 with a height of 24 in a 64 px header, so they hung THROUGH the
      rule closing the header, on a different baseline from the status chips
      whose corner they shared. One centred row now: minimise, maximise,
      close.
    * THE RESIZE AFFORDANCE IS VISIBLE AND THE EDGES WORK. It was three
      hairlines in the dimmest colour in the palette, hit-tested through an
      invisible Container. It is now a raised corner tile you can see, plus
      the whole right and bottom edge, all on real drawn shapes.
      NOTE: the design size is the MINIMUM. The window grows; it does not
      shrink below 1120x720, because every panel lays out downward on a
      fixed grid.
    * FAST SCROLLING. On a hooked wheel every physical notch is suppressed
      and re-emitted. That re-emission ran in the script-wide Event mode,
      one mouse_event per notch from a Critical thread, so at trackball
      speed notches reached the application late and with the gaps between
      them stretched -- and PACS and browsers accelerate scrolling from
      exactly those gaps. The passthrough now uses SendInput, atomically.
      The wheel hotkey also gets T4: it was registered at runtime, where the
      #MaxThreadsPerHotkey directive does not reach, so it kept the default
      of one thread and DISCARDED any notch arriving mid-resolve.

  v0.4.6 makes the window an actual window.

    * RESIZE REALLY WORKS NOW. v0.4.5 made the grip visible, which was not
      the problem. The size outline was ONE LAYER THE SIZE OF THE MONITOR --
      a ~33 MB ARGB surface on a 4K display, reallocated and pushed through
      UpdateLayeredWindow every frame -- and it was built inside the drag
      loop's own try, so when it crawled or threw, the drag was skipped
      entirely and the window silently refused to resize. It is now four
      3 px strips, the trick TeleportSignal already used, and the outline is
      treated as optional feedback that cannot take the resize down with it.
    * ALT+TAB AND A TASKBAR BUTTON. Every GpGFX layer is created
      WS_EX_TOOLWINDOW -- correct for toasts and overlays, and exactly the
      style that hides a window from the taskbar and Alt+Tab. Layers after
      the first are also given an OWNER, and an owned window is excluded
      whatever its style says. The settings window is now disowned and
      marked WS_EX_APPWINDOW, with a real title. Main window only: the
      shelves, chooser, switcher and toasts stay tool windows.

  v0.4.7 lets the window SHRINK, and gives the pointer a landing signal
  wherever it lands.

    * THE PANELS REFLOW. Mouse, Keyboard, Layers, Macros, Apps, Windows and
      Diagnostics were always height-relative and reflowed for free.
      Settings and Pointer were built on hand-picked absolute offsets that
      assumed one window size, which is the whole reason the floor could not
      come down. They now allocate ELASTIC BANDS (Atlas.Bands: scale by
      ratio, clamp to a legible minimum, take the excess back from whichever
      band has the most slack) and derive every column and row pitch from
      the actual width and height. Minimum is now 940x640, from 1120x720.
    * THE LANDING RING follows the cursor everywhere it lands, not only on a
      monitor teleport: follow-focus warping into a newly focused window,
      and the window switcher committing a choice, now pulse the same ring.
      RING ONLY for those two -- outlining a whole monitor in red every time
      the foreground changes would be intolerable, and the ring is the part
      that answers "where did my pointer just go". Separate toggle
      (focusFlash / "Landing flash") because it fires far more often.

  v0.4.8 adds PER-APP NO-HOLD INPUTS, for applications that run their own
  press-and-hold gestures on the mouse buttons.

  syngo.via is the reported case: give MB1-3 any hold binding and it becomes
  unusable there. This cannot be fixed with a binding, and that is the point.
  The cost is the ARBITRATION, not the action -- to tell a tap from a hold
  the engine must WITHHOLD the press until the hold threshold elapses, so an
  app that begins a drag on button-DOWN sees a 200 ms dead zone at the start
  of every gesture, and even a row resolving to "pass through" still has to
  wait before it knows that is the answer.

  So a profile can now list inputs whose hold, tap-hold and layer-host
  behaviour is DROPPED while it is in front, returning them to the engine's
  eager path: first press out natively and instantly. Taps, double-taps and
  triple-taps still work, because the eager path already delivers the first
  press natively and only the extras need a timer.

  A Syngo.via profile with MB1-3 listed is seeded once into existing configs
  (and ships in new ones), and the Apps tab has a "Toggle MB1-3 no-hold"
  button so the same fix is one click for any other application that turns
  out to need it. Matched by EXE only: syngo.via's ahk_class carries a
  per-run token, exactly as PowerScribe's does.

  v0.4.9 is a settings window that cannot wedge, a follow-focus that follows
  APPS, and a window switcher you recognise instead of read.

    * THE SETTINGS WINDOW COULD GET STUCK SHOWING DUPLICATED, SLIGHTLY
      OFFSET TEXT WITH NOTHING CLICKABLE, and closing and reopening it did
      not help. Three separate faults, all fixed:
        - Build() runs from a 700 ms timer, and an uncaught error in a timer
          thread dies on the spot -- after lyr.Clear() has destroyed the old
          frame and before lyr.Draw() shows the new one. What is left on
          screen is the last good frame's PIXELS over the failed frame's
          half-built SHAPES, so clicks land nowhere near what you see. The
          panel build is now caught: the failure is drawn, named and logged
          to Diagnostics, and the header and nav still work so you can move
          off the broken panel.
        - GpGFX erases only the previous frame's bounding box, and Text is
          exempt from the clipping that would keep it inside its own box.
          A string wider than the width it was given paints outside the
          erase region and is never cleaned up, so it accumulates rebuild
          after rebuild. Every panel that rebuilds in place now forces a
          full-surface erase first (Lumi.FullErase).
        - Lumi.editing is held above zero for the length of a field edit and
          every rebuild defers while it is. A thread that died without
          unwinding left it pinned forever, and the window is HIDDEN rather
          than destroyed, so reopening inherited the same stuck count. The
          edit loop now stamps a heartbeat and Lumi.EditGuard drops a count
          nobody is going to decrement. Reopening the window is a repair.
    * FOLLOW FOCUS FOLLOWS APPLICATIONS, NOT WINDOW HANDLES. syngo.via, a
      PACS viewer and a browser all hand the foreground back and forth
      between their own top-level windows with nobody touching anything,
      and chasing every one of those was the "jumping around by itself".
      A switch now has to change PROCESS (followSameApp opts back in), the
      new window has to hold the foreground for followSettleMs before the
      cursor commits to it, tool windows and untitled helpers are not
      destinations, there is one warp per followCooldownMs at most, and a
      profile can opt out entirely ("No follow-focus" on the Apps tab).
    * THE WINDOW SWITCHER SHOWS THUMBNAILS. A row of names is a reading
      task; a wall of pictures is a recognition task, and recognition wins
      by a wide margin. Four across, twelve at most, captured with
      PrintWindow (PW_RENDERFULLCONTENT) so an occluded window still comes
      out right and our own overlay never appears in the picture. Captured
      one per tick, selection outwards, so the panel opens instantly and
      fills in; minimised, hung or uncapturable windows fall back to their
      icon. The thumbnails are memory-only and freed the moment the panel
      closes -- a thumbnail of a reading station is a picture of a patient.

  v0.5.0 adds RADIAL MENUS: eight commands around the cursor, chosen by
  direction.

  The problem a radial menu solves is POINTER TRAVEL, which on a reading
  station is measured rather than theoretical -- an eight-hour shift is
  roughly a mile and a half of mouse. Arranged around the cursor, every item
  is the same short distance away and the DIRECTION is constant, which is
  what makes it learnable as a gesture; a gesture costs no travel at all.

  The design is not open. Kurtenbach and Buxton measured marking-menu error
  rates staying under 10% at a breadth of 8 and a depth of 2, rising sharply
  past either. For a reading room 10% is already too high, so: EIGHT SLICES,
  ONE LEVEL, and nesting deliberately not built.

    * NOVICE AND EXPERT ARE THE SAME GESTURE. The wheel is NOT drawn on
      press. Flick a direction and release and it fires with nothing ever
      drawn; hold still past the dwell and it fades in so you can look.
      Because both are one physical action, using the slow form teaches the
      fast one. This is the property most implementations lose by always
      drawing, and losing it turns a marking menu back into a toolbar.
    * ALWAYS ABORTABLE. Releasing inside the dead zone fires nothing, and
      Escape cancels. A gesture that cannot be called off mid-flight will
      eventually fire the wrong thing into a report.
    * AT THE CURSOR -- the one deliberate exception to the v0.4.0 rule that
      moved every HUD off the pointer. That rule is about passive
      notifications sitting over a finding. This is modal, it lives for a few
      hundred milliseconds, it is there because you asked for it, and putting
      it anywhere else would destroy the only reason to build it.

  A slice is an ordinary {type, value} action, so the whole action table is
  available with no new executor cases -- and PowerScribe slices route
  through PSFire automatically, because ps_* actions already do.

  Three menus ship. Browser (4) and PowerScribe (4) are complete. PACS is
  eight LABELLED BLANKS on purpose: IntelliSpace shortcuts are
  user-configurable, so shipping guessed keys would ship wrong ones. Epic and
  syngo.via are not seeded at all, one step further, because their tables are
  site-remapped. The Menus tab is where those get filled in.

  v0.5.1 is four reported faults, and they share one root.

    * TYPING INTO A FIELD DID NOTHING, THE WINDOW FROZE MID-ALIGNMENT, AND
      CLICKS LANDED NOWHERE. All three are one bug: a dialog builder sets
      LayerStack.ActiveLayer to its own layer and restores nothing, because
      on success the dialog IS where new shapes belong. Every shape
      constructor reads that one global -- so an error part-way through a
      build leaves it pointing at a layer that was never drawn, and from
      then on Lumi.Own() hands that dead layer to every field built
      afterwards as its OWNER. __FieldMine compares the owner's hwnd against
      the foreground window, never matches, and the edit loop exits before
      the first keystroke: letters go nowhere. Meanwhile Atlas.dlg is set,
      so the status tick returns early forever and the main window stops
      repainting, and the half-built dialog window is real, on top, and not
      click-through, so it silently eats the clicks aimed underneath it.
      Every dialog now builds through Atlas.OpenDlg(), which restores the
      construction target in a `finally`, tears down a half-built dialog and
      names the error in Diagnostics. The status tick also drops a dialog
      whose window has gone.
    * THE HOVER HIGHLIGHT STAYED LIT after the pointer moved away, on the
      sidebar and in the panel. TrackMouseEvent's TME_LEAVE is a ONE-SHOT
      request; GpGFX armed it only while a flag was false and cleared that
      flag only in the WM_MOUSELEAVE handler. Any leave that never arrived
      -- window hidden and reshown, cursor leaving during a modal drag or a
      blocking field edit -- left tracking unarmed for the rest of the
      session. Re-armed on every move now (idempotent, one DllCall), with a
      per-tick position check as the floor under it.
    * CROSSED-OUT TEXT while typing. Same erase rule as v0.4.9, one layer
      down: the field repaint went through the shape's own RedrawLayer,
      which erases only the previous frame's bounding box, and Text is
      exempt from the clipping that keeps a shape inside its box. Text that
      outgrew the field painted outside the erase region, and the caret
      blinked over the leftovers twice a second. Field repaints now force a
      full-surface erase.
    * STILL COULD NOT RESIZE, third report. Three changes: Atlas.W/H are now
      taken BACK from the layer after a resize instead of being set before
      one and assumed -- a single failed Resize used to move the grip
      permanently outside the visible window; the edges went from 6 px to 14
      and the corner from 18 to 26; and every stage of the drag writes a
      line to Diagnostics, so the next report says where it stopped.
      There are also now TWO resize paths that do not go through a shape
      hit-test at all: a size button in the window chrome, and Ctrl+Alt+
      arrows while the window is in front.
    * "TRY IT NOW" hid the settings window to show a menu over something
      real and never brought it back -- indistinguishable from a freeze. It
      returns now, and a trial menu FIRES NOTHING: it says what it would
      have fired. A W/L preset or a close-tab going into a study because you
      paused on a slice is not an acceptable cost of previewing a layout.

  v0.5.2 hardens the shared UI failure paths. Resize captures the mouse and
  reads Win32 asynchronous button state instead of trusting a delayed AHK
  state poll. RadMapper-owned vector layers erase their full surface by
  policy, active-layer swaps restore in finally blocks, and shape-handler
  failures are recorded in Diagnostics. The global error hook suppresses
  modal dialogs while preserving the failure record.

  v0.6.0.1a is a PROTOTYPE for colleagues who are not technical, and a
  bug-fix release underneath it. The UI is the same window with a front
  door added; the engine is the same engine with six faults closed.

    * HOME PAGE. The window now opens on "Start here": one sentence on
      what RadMapper does, whether it is on or off IN WORDS, and four
      large buttons for the four jobs people actually come for -- change
      a mouse button, change a key, test my mouse, fix a stuck button --
      followed by the three hotkeys that always work, spelled out
      ("Ctrl + Alt + Q", not "^!q"), and the path the settings are saved
      at. The first launch of each version opens the window on this page
      by itself, so nobody has to find the tray icon.
    * PLAIN WORDS. "Binding" is a setting, an "input" is a button or key,
      a "profile" is a program, "layer host" is "hold this", "park spot"
      is "pointer spot", the guard "keeps windows in place", "no-hold" is
      "instant clicks", "Panic release" is "Unstick my buttons" and it
      says so in a toast when it has done it. List headers read "When
      you / It does / Also hold". Config keys, action codes and the
      ACT_* tables are untouched: this is a copy change, not a schema one.
    * DELETING ASKS FIRST. A setting, a menu, a layout or a pointer spot
      is not removed until a Yes/No box says so. The status tick is
      paused around the box so the 700 ms rebuild cannot dispose the
      button whose handler is waiting on the answer.
    * LEGIBILITY. Body text 11 -> 13 px, small 10 -> 11, tiny 9 -> 10,
      checked against every fixed box height; the disabled/placeholder
      ink lifted from 2.6:1 to >= 3:1 on every surface (WCAG); toggles
      52x28 instead of 44x22; toasts stay up 2.6 s instead of 1.6.
    * TWO LAYOUT FAULTS FIXED. The Mouse and Keyboard panels placed four
      buttons summing to 486 px in a 384 px column at the minimum window
      size, so "Delete" and "Wheel deck..." hung off the right edge,
      unreachable; button rows are now sized to the column they sit in
      (Atlas.BtnRow). And the nav rail stepped a fixed 44 px per entry,
      which with eleven entries ran through the engine switch on any
      window under about 780 px tall -- the minimum is 640; the pitch is
      now derived from the space that is there.
    * PANELS DISPATCH BY NAME, not by number, so inserting Home at the
      front of the list could not open the wrong panel silently; the two
      places that hard-coded an index now look the name up.

  ENGINE FIXES
    * The global error hook was only registered inside GpGFX's static
      init, after Gdip.Startup() and inside its try -- so on a machine
      where the graphics stack fails to start, every unhandled error
      raised a modal AutoHotkey dialog over the study. Registered first
      thing in Init() as well.
    * "Modifier + left-drag" released the button and the modifier in ONE
      Send; Send parses the whole string before emitting anything, so an
      unusable modifier value threw and the LButton Up was never sent --
      a latched left button over an image. Released in two calls, the
      button first.
    * Radial menus were missing from the list of hold actions that stay
      engaged until release. On a button that also hosts a layer, the
      menu therefore opened AT RELEASE in latched mode, with nothing
      held, and committed a slice by dwell. Listed.
    * The classic binding and key dialogs looked up an action hint with
      no guard; a retired action type still on disk threw mid-build and
      left a half-built modal over the reading screen. Guarded.
    * The empty membership index omitted two flags the hot path reads
      unguarded, so a hook thread could throw before the first rebuild.
    * Importing a config whose "bindings" was not an array replaced the
      live config and then failed outside the try. Rejected up front.
    * The calibrator, the shelves and the chooser restored the active
      construction layer only on the success path; a failed build or
      repaint left a dead layer as the target for every later widget
      (the v0.5.1 "typing does nothing" failure, in three more places).
      All restore in finally now. A shelf drag that threw left the shelf
      permanently marked busy; guarded the same way.

  NOT DONE YET (v0.6.0 proper)
    * The nav entry names other than Home still use engine vocabulary
      (Layers, Macros, Pointer).
    * The classic Win32 window did not get the copy pass.
    * None of this has run on a workstation: this build was checked for
      syntax balance and by reading, not by execution. Report anything
      odd from the Diagnostics page.

  FEATURES
    * RADIAL MENUS: hold, flick a direction, release. Eight slices, one
      level, dwell before drawing, always abortable
    * CLICK LOCK: one programmable key latches whatever button is held, and
      the next real keystroke releases it
    * WHEEL DECKS: hold an input, scroll for an output. One dialog per
      deck, all four wheel directions at once, on both the Mouse and the
      Keyboard panel. Writes plain layer-scoped "turn" rows.
    * WINDOW SWITCHER: hold, scroll a list that stays up, release to switch
    * WINDOW LAYOUTS: capture / restore window placement across monitors,
      with an optional guard that undoes an app's own moves and resizes
    * TAP-HOLD CALIBRATOR: sets tapWindow and holdThreshold from your hand
    * Buttons 1-5 (LButton, RButton, MButton, XButton1, XButton2) plus
      WheelUp / WheelDown and Tilt Wheel Left / Right as bindable inputs
    * KEYBOARD keys as bindable inputs, in the same rows as the mouse: any
      key AHK can hook (Numpad1, F8, CapsLock, ], ...), with the same app /
      layer / modifier scoping and the same tap dance
    * Key-combo recorder ("Rec"), a visual keycode picker ("Keys") and an
      input picker ("Input") in every action dialog, classic and vector --
      no Send-syntax memorization needed
    * Diagnostics tab: live input monitor -- every button/wheel/tilt lights a
      bar and counts presses; native behavior is never blocked while testing
    * Eager first-press passthrough: a button whose extras are only
      double / triple / taphold keeps its FIRST press fully native and
      instant (click, drag, hold), so tap dance costs no drag latency
    * Tap dance per input: tap, double-tap, triple-tap, hold, tap-hold
      (tap window default 100 ms, hold threshold default 200 ms, both live)
    * Button-layers: an input HOSTS a layer just by having a mapping whose
      "Layer (hold)" names it. Holding it arms that layer (deepest of a
      2-deep nest wins); its own hold action fires only if the layer went
      unused (the QMK mod-tap rule).
    * App profiles: per-app bindings override global ("*") bindings
    * Keyboard modifiers (Ctrl/Alt/Shift/Win) as binding conditions
    * Any input can be remapped to any OTHER input (a button to a button, a
      button to a key, a key to a button) and it behaves like that input --
      down on press, up on release, so drags and holds work (v0.3.1)
    * CLICK LOCK (v0.3.1): hold a mouse button, tap the click-lock input, and
      the button stays latched down until you press it again -- long
      window/level sweeps and measurements without holding the button
    * DRAG SCROLL (v0.3.1): hold the bound input and move the mouse to scroll,
      like a PDF hand tool; the cursor can be pinned so travel is unlimited
    * PAUSE ON NUMLOCK (v0.3.2): one key pauses the engine to fully native
    * FOLLOW FOCUS (v0.3.2, off by default): the pointer jumps to the middle
      of a window when it takes the foreground -- never mid-drag, never onto
      the shell, never when the pointer is already inside it
    * PARK POINTS (v0.3.6): capture one screen spot per app ("Capture park
      spot" on the Apps tab, 3-second countdown while the window hides).
      The "Park cursor (this app's spot)" action sends the pointer there,
      and follow-focus uses it instead of the window centre when one is set
    * LAYERS PANEL (v0.3.6): every input that hosts a hold layer, with the
      row count it arms; click one to scope its tab to that layer. Layer
      hosts are ringed in the mouse schematic and on the key tiles
    * KEYBOARD PANEL (v0.3.7): the Mouse panel for keys -- App and Layer
      scope selectors, a tile per key in use, per-key row lists. The engine
      never distinguished mouse from keyboard; now the UI does not either
    * Actions: send keys, auto-repeat keys, type text, native input, double
      click, modifier +left-drag, drag-after-move, PowerScribe dictate /
      next field / prev field / custom, monitor teleport, sniper / boost
      pointer speed, click lock, drag scroll, W/L dial step, macros, run, ...
    * Macros: multi-step (keys / text / sleep / focus-app / PS actions /
      teleport / run) with app-focus steps for app-aware sequences

  PERFORMANCE DESIGN
    * An input is only hooked while at least one binding references it.
      With nothing bound to LButton, left click-drag is NOT intercepted at
      all -- it is byte-for-byte native. The same holds per KEY: a keyboard
      with no rows is never touched, so typing keeps its native latency.
    * A hooked input whose resolved context has only a plain native action
      takes a zero-wait fast path (synthetic down on press, up on release).
    * Disambiguation delays are only ever introduced by features you actually
      configured in that context (a double-tap row makes tap wait one tap
      window; nothing else does).
    * Event-time lookups run against a membership INDEX (g_Idx, rebuilt on
      every config change -- all mutations must funnel through
      AfterCfgChange). Resolution still happens live per event, so GUI
      edits keep applying instantly. Active-app detection is cached per
      foreground hwnd for 100 ms; modifier keys are only read when some row
      actually uses modifiers. Slider config saves are debounced.

  HOTKEYS (all editable in Settings tab)
    Ctrl+Alt+Shift+F9     Open the RadMapper settings GUI
    Ctrl+Alt+Shift+F11    Enable / disable the whole engine
    Ctrl+Alt+Q            PANIC: force-release all buttons and modifiers
    PowerScribe dictate / prev field / next field and monitor-teleport
    hotkeys exist but ship UNASSIGNED; set them in the Settings tab.

  FILES
    RadMapperConfig.json  created next to this script on first run; a
                          pre-v0.1 RadMouseConfig.json is adopted once; the GUI
                          is the intended editor but it is hand-editable

  FIRST RUN ON THE WORKSTATION
    1. Install AutoHotkey v2 (https://www.autohotkey.com)
    2. Double-click RadMapper.ahk -- tray icon appears; every input ships
       UNASSIGNED, so the mouse and keyboard stay fully native until you add
       bindings
    3. Double-click the tray icon (or Ctrl+Alt+Shift+F9) to open the GUI

  Requires AutoHotkey v2.0+. Windows 10/11.
==============================================================================

```
