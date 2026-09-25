# RadWheel 1.1

Radial menus for the reading room: hold a button, move toward a command, let
go. It's RadMapper's radial-menu feature as a separate, standalone
AutoHotkey v2 script (`RadWheel.ahk`). It has no libraries and no installer.

**Review build.** This version was checked by reading and by
`tests/check_source.py`. It hasn't run on Windows yet. See *First run
checks* below.

## Start

1. Install **AutoHotkey v2** (autohotkey.com).
2. Double-click `RadWheel.ahk`. On the first run, the settings window opens.
3. Later, open it by double-clicking the tray icon or pressing
   **Ctrl+Alt+Shift+F10**.

## Using a wheel

| Do this | What happens |
|---|---|
| Hold the button, flick toward a command, let go | Runs the command. If you're quick, the wheel is never drawn. |
| Hold still | The wheel fades in (after 180 ms) so you can read it. |
| Let go in the centre, press Esc, or click | Cancels. Nothing is sent. |
| Rest on (or move across) a slot marked › | That wheel opens in its place. |
| Let go on a slot marked › | That wheel stays open. Click a command in it. |
| Quick tap (under 300 ms, no movement) | Does what the wheel's **Tap it** setting says (see below). For PACS tools this is the normal right-click menu. |
| Keys 1–9 while a wheel is open | Picks slot 1–9. |

## Shipped setup

| In | Button | Wheel |
|---|---|---|
| PACS | **hold right-click** | **PACS tools**: Next series (up), Prev series (down), Ruler, ROI, Magnifying glass, Key image, Window presets ›, More › |
| PACS | quick right-click | The normal PACS right-click menu, unchanged |
| PACS | hold **or tap** button 5 | **Window presets** 1–9. A tap keeps the ring open until you click. |
| PowerScribe | hold button 4 | Dictate (up), Next field (right), Prev field (left) |

**More ›** holds Scout lines (F11), Localizer (F12), and six items taken
straight from the PACS right-click menu: Measurements, Annotations,
Flip/Rotate, Zoom presets, Unlink all, and *PowerScribe: Dictate this
exam*. Check the shortcut letters against your site's PACS keyboard
settings.

## Setting up (the settings window)

It works like Stream Deck: a picture of the wheel sits on the left. Click a
slot to edit it, or click the centre (**TAP**) to set the quick tap. Every
change saves immediately.

**How it opens.** Each wheel has these settings:

- **Button or key**: right, middle, button 4 or 5, Caps Lock, backtick,
  F13–F20, or **Record key…** for any key or combination. Choose *None* for
  a wheel that only opens from inside another wheel.
- **Hold it**: opens the wheel (flick and let go), or does the same as a
  tap.
- **Tap it**: opens the wheel and keeps it open (click a command, or tap
  again), does the button's normal job, does nothing, or runs any command.
- **Moving at once**: *picks by direction* (fastest), or *drags as normal*.
  With *drags as normal*, a drag that starts straight away stays a real
  drag, and you hold still to open the wheel. Use it if your PACS relies on
  right-button drags.
- **Works in**: every program, PACS, PowerScribe, or any running program.
  For a mouse button, this is the program **under the pointer**. For a
  keyboard key, it's the program in front.

**What a slot does:**

- **Press a keyboard shortcut**: click Record and press the shortcut.
- **Pick an item from the right-click menu**: RadWheel right-clicks where
  the wheel opened and clicks the item by its text. Write submenus with
  `>`, for example `Measurements > Ellipse`. A path that ends on a submenu
  opens that submenu and leaves it open. **Read menu…** reads your PACS's
  real menu and lets you pick an item from a tree. If a menu can't be read,
  use positions instead, for example `#2 > #3` (count items down, skipping
  separator lines).
- **Type some text**, **Open another wheel**, or **Open a program, file or
  web page**.
- **Send to**: the program under the pointer (the default), PowerScribe,
  or the PACS viewer. The last two bring that program forward, send the
  keys, then return focus to where you were. They match programs by exe
  (the PACS viewer by its "VirtualMonitor" title), set under Programs….

**Practice ▶** shows the wheel and sends nothing. **Try it in 3 s** runs
the selected slot for real, after a countdown.

## Speed

- A flick that ends before the show delay draws nothing. The command is
  sent as soon as you let go.
- Each wheel is drawn once into a cached image, and the cache is filled
  just after start. After that, moving between slices only redraws the
  highlighted slice.
- Click, Esc, and 1–9 are only intercepted while a wheel is open. The rest
  of the time, clicks don't go through the script at all.
- The 1 ms Windows timer is switched on only while a wheel is open.
- Keys go straight to the program under the pointer. Focus switches only
  when a command targets another program.
- To make wheels appear sooner, lower **Wheel appears after** at the bottom
  of the window (0 draws it at once).

## If something goes wrong

| Problem | Fix |
|---|---|
| A button or key seems stuck | **Ctrl+Alt+Shift+F12**, or tray › *Release stuck keys* |
| Everything should be normal right now | **Pause**, in the window or the tray |
| A right-click menu item isn't found | Use **Read menu…** to get the exact text, or a `#number` path |
| Keys go to the PACS worklist instead of the viewer | Programs… › set the viewer's title text |
| Menu items are hit in the wrong place | In the settings file, set `RightClickMethod="action"` |
| A slow right-click cancels instead of opening the PACS menu | Raise `TapMs` in the settings file (default 300) |
| A right-drag in PACS fires a command | Set **Moving at once** to *Drags as normal* on the PACS tools wheel |

The settings live in `%APPDATA%\RadWheel\RadWheel.ini`, a plain UTF-16 INI
file. You can edit it by hand, copy it to a colleague, or back it up.

## Running alongside RadMapper

RadWheel and RadMapper can run at the same time, but never on the same
button. Both scripts hook the mouse, and Windows asks the newest hook first.
RadMapper also moves its hook back to the front every 10 s while PACS is in
front. If both scripts owned one button, they would take turns winning it.

So RadWheel steps aside on its own. Every 3 s it checks whether RadMapper is
running. If it is, RadWheel reads `RadMapperHooks.txt`, the list of buttons
and keys RadMapper has hooked right now (RadMapper writes it beside its
settings), and leaves every one of them alone. An older RadMapper without
that file is handled from its settings file instead: any button with a real
assignment, and any button that holds a layer. A toast names the buttons it
gave up, and the RadWheel window shows ⚠ on any wheel whose button is taken.
When RadMapper exits, or frees the button, RadWheel takes it back.

With RadMapper's shipped setup, RadMapper keeps button 4, button 5, Caps Lock
and backtick. RadWheel keeps the right button, so **PACS tools** on
hold right-click works alongside RadMapper. The **Window presets** (button 5)
and **PowerScribe** (button 4) wheels stay off while RadMapper runs. You can
move them to another button (for example the middle button, or F13–F20 on a
programmable mouse), or clear those buttons in RadMapper.

Details:

- Pausing RadMapper gives its buttons to RadWheel within 3 s; resuming
  takes them back. (With an older RadMapper, a paused one still counts as
  running: exit it instead.)
- The two scripts ignore each other's keystrokes and clicks, so a key that
  RadWheel sends never sets off a RadMapper shortcut, and a RadMapper click
  never opens a wheel.
- Set `YieldToRadMapper="0"` in the settings file to turn this off.

## First run checks (Windows)

1. The script loads without an error and the settings window opens. The
   wheel picture shows PACS tools.
2. In PACS, a quick right-click opens the normal menu. Hold right-click and
   flick up: next series. Hold still and the wheel appears. Let go in the
   centre: nothing happens.
3. Tap button 5 in PACS: the preset ring stays open. Click 3. Or press 3.
4. Hold right-click › More › Measurements: the PACS Measurements submenu is
   left open at the spot where you started.
5. Read menu… on a Measurements slot lists the PACS menu as a tree.
6. Right-drag in another program still works (the wheel is PACS-only).
7. Start RadMapper as well. Within 3 s a toast says RadWheel leaves
   button 4 and button 5 to it. Hold button 5 in PACS: RadMapper's own
   wheel opens, not RadWheel's. Hold right-click in PACS: the RadWheel PACS
   tools wheel still opens. Pause RadMapper, then exit it: each time a toast
   says RadWheel has the buttons back.

## Checks

```
python3 tests/check_source.py
```

This checks the BOM, bracket balance, that every called function exists,
that no v1 syntax slipped in, that global assignments are declared, and
that no function spells one variable two ways (`G`/`g` are one name in
AutoHotkey). It
doesn't run AutoHotkey.
