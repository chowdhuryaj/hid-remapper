# RadMapper 0.6.4-preview

A single-file mouse and keyboard remapper for the reading room (PowerScribe +
IntelliSpace). Everything is in `RadMapper.ahk`: no installer, no folders.

**This is a review build.** It has been checked for syntax balance, by reading,
and by the portable checks below, but it has not yet run on a Windows
workstation. Treat it as a candidate for testing.

## Try it in two minutes (Windows)

1. Install **AutoHotkey v2** from https://www.autohotkey.com (the v2 installer, not v1).
2. Double-click `RadMapper.ahk`. A tray icon appears and the settings window
   opens on **Home** the first time each version runs.
3. Home opens on **Reading room essentials**: one row for each of the seven
   things this program is for — *dictate on/off*, *next field*, *previous
   field*, *pointer to the left monitor*, *pointer to the right monitor*, the
   *PACS wheel* and the *window presets*. Each row shows what fires it today
   (a button, a key, a hotkey, or several, joined by "or"), a **Set…** button
   that opens the three-question wizard with the answer to "what should it
   do?" already filled in, and a **Clear** button that removes every trigger
   for it. Below the card, pick a bigger job:
   - **Change what a mouse button does** (a three-question wizard: which
     button, tap or hold, what it should do; "All options" opens the full editor)
   - **Change what a keyboard key does**
   - **Set up a radial menu** (commands around the pointer, picked by direction)
   - **Apply a starter pack** (one click sets up a common arrangement, such as
     PowerScribe on the thumb buttons or the PACS wheel on button 4; anything
     it would replace is listed first, and the result is ordinary settings you
     can edit or delete on the Mouse page)

To watch every button light up as you press it, use **Test my mouse and
keyboard…** on the Diagnostics page.

**Shipped defaults are active.** Seven rows ship turned on:

- **`** (backtick) toggles PowerScribe dictation.
- **Button 4 / Button 5** (the thumb buttons) jump the pointer to the previous
  and next monitor.
- **`[`** tap = PowerScribe *next field*, **`[`** hold = drag scroll.
- **`]`** tap = PowerScribe *previous field*, **`]`** hold = drag zoom.

The four bracket rows have a cost worth knowing about before you dictate with
them: the **tap** rows *replace* the character, so pressing `[` or `]` no
longer types a bracket at all, and the **hold** rows make every press wait the
hold threshold (200 ms by default) before it resolves, which is noticeable in
a report field. Dictating a bracket is unaffected.

The buttons are named the same way everywhere: **Button 3** is the wheel
click, **Button 4** is the back thumb button and **Button 5** is the forward
one — on the mouse map, in every list and in every message.

To remove any of them, open the **Keyboard** page (or **Mouse** for the thumb
buttons), select the row, and choose **Delete**. Deleting only the two `[` /
`]` **hold** rows removes the latency and keeps field navigation; deleting all
four gives the bracket keys back to the keyboard. Nothing else is remapped
until you add it.

The window opens in **Simple** view: Home, Mouse, Keyboard, Menus, Settings and
Diagnostics, with a short list of actions. The switch on Home, "Show advanced
pages and every action", adds Layers, Macros, Apps, Windows and Pointer and the
full action list. Nothing is lost either way.

In Simple view the add button is **Set a button…** on the Mouse page and
**Set a key…** on the Keyboard page; both open the three-question wizard. In
Advanced view both become **Add new** and open the full editor. Settings ▸
**Restore shipped defaults…** puts everything back the way it arrived (it
asks first, and it cannot be undone).

A mouse button can also be a **PACS gesture**: the wizard's *Zoom (Alt+drag)*
and *Pan (Ctrl+drag)* tiles hold Alt or Ctrl with a left-drag while the button
is down, which is zoom and pan in IntelliSpace; the starter pack **PACS zoom
and pan on the thumb buttons** puts both on buttons 4 and 5 inside PACS only.

A mouse button can be **another mouse button**: choose *Left click*, *Right
click*, *Middle click*, *Double-click* or *Click lock* in the wizard, or pick
the action in the full editor and take the button out of the **Details**
dropdown — no codes to type. For a latch, choose **Click lock**, then choose
the button it should hold (middle, by default); "Whichever button is held"
keeps the original behaviour of latching whatever is already down.

## Setting up without the mouse

The settings window can be driven from the keyboard alone. **Tab** and
**Shift+Tab** move between controls and draw a cyan ring around the one you
are on, **Enter** or **Space** presses it, **Left** and **Right** step a
dropdown, nudge a slider and flip a switch, **Up** and **Down** move a list's
selection, and **Escape** closes the current popup, dialog or window — one
level at a time. A dialog opens with its first control already focused; a page
shows no ring until you press Tab, so nothing changes if you only ever click.
Typing into a field is never interrupted: while the caret is in one, the keys
above are just keys, and Enter commits what you typed and moves on.

Press **F1** in the settings window for quick help. Open the window at any time
with **Ctrl+Alt+Shift+F9** or by double-clicking the tray icon.

## Radial menus

A **PACS** menu ships ready to use: Next series (F8) up, Prev series (F7) down,
Ruler (R), ROI (Shift+R), Magnify (Y), Delete, CLAHE (Shift+C), and
**Windowing**, which opens a second ring of numbered window presets (1 Soft
tissue, 2 Bone, 3 Brain, 4 C-spine soft tissue, 5 CTA, 6 Infarct, 7 Liver,
8 Lung, 9 Lung wide). Rename any of these on the Menus page to match your site.

1. **Menus → select PACS → Assign a button.** The Hold trigger is prefilled;
   pick the button, then save.
2. **Hold** that button, **move** toward a command, **release**. Release in
   the centre hub, press Escape, or **click** — any of the three fires
   nothing.
3. For a preset: hold, **flick** to **Windowing** and **turn a corner** toward
   the number you want — the preset ring opens at the corner, still held, and
   the number fires when you release. Pausing on **Windowing** opens it too,
   and so does releasing on it (the ring then stays open).
4. In that second ring, the direction you came from — and the space either
   side of it — is **back**: turn or pause there and the first ring returns,
   having sent nothing.
5. If the menu is bound to a **tap** instead, it stays open: rest on a command
   to fire it, or **tap the button again to close it**.
6. **Practice safely** on the Menus page shows the wheel without sending anything.

**What you are looking at.** On the first wheel **every direction belongs to a
command**: each one owns its whole slice of the circle, drawn as that arc with
a hairline at each edge, so a flick that is a little off centre still picks the
one you aimed at rather than nothing. The numbered **preset ring** is the same
— all nine numbers have to be reachable, so it has no gaps either, and you
leave it with Escape or a click. Only a **second ring opened from a command**
has gaps, and there they mean one thing: **back**. The direction you walked in
from and the space flanking it return you to the first wheel, sending nothing.

**A click cancels a live menu**, wherever you are and whatever it is over —
**practice included** — and sends nothing. The hub prints the command that is
armed and the keys it will send, or the menu's name when nothing is. The stroke
you are making is drawn back at you, a door wears one dot per command behind
it, and the wheel grows whatever the pointer is near. **Animate the wheel** and
**Show wedges** on the Menus page turn the movement and the drawn arcs off;
neither changes what a direction does.

**Sending keys to PACS from anywhere:** the action **PACS: send keys** works
like the PowerScribe actions. Bind it to any button in any program and the
viewer is brought forward, receives the shortcut, and focus returns to where
you were. It targets the PACS profile on the Apps page and prefers the window
whose title contains "VirtualMonitor" (the IntelliSpace viewer); both are
settings if your PACS differs.

To edit a menu, use **Edit commands**: each row has a label, an action, the
recorded shortcut, and an icon. A row set to "Radial menu" opens another menu
inside this one. Size 9 is the numbered ring for presets.

## Window arrangements that follow you between stations

The **Windows** page (turn on "Show advanced pages" on Home) saves where every
window sits and puts it back: in one click, on any button ("Apply window
layout"), or automatically. Since 0.6.2 an arrangement is not tied to the
station it was saved on:

- Each window remembers its **screen, counted left to right**, and its place
  on that screen as a fraction of the work area. On the saving station it is
  restored pixel for pixel. On any other station it is **adapted**: screens
  are mapped by position onto the screens that exist (a four-screen
  arrangement folds onto three), and maximised stays maximised.
- **Imaging screens are reserved.** "auto" treats portrait screens, and
  screens with clearly more pixels than the smallest one, as imaging
  screens: the viewer goes there, nothing else does. A station whose
  screens are all alike reserves nothing. Type `none` or `2,3` in **Imaging
  screens** to overrule it for the station in front of you.
- **Stations are recognised.** The monitor set is the station's identity.
  The first arrangement saved on a station becomes its own (change it in
  **Arrangement here**); with **Auto-apply** on, the arrangement is applied
  when RadMapper starts and whenever the screens change (docking, a KVM,
  a display waking late).
- **Keep in place** has three settings per arrangement: off; **always**
  (a program that moves or resizes a window is undone); **new windows**
  (a window is placed once, the first time it appears, and never touched
  again, so PACS opened after RadMapper lands on the right screen and a
  window you then move stays moved). Neither runs while a mouse button is
  down.

Two shortcuts move the **active window** without dragging: "Window → next
screen" / "previous screen" (keeps its shape, or stays maximised) and
"Fill screen" (maximise on the screen it is on; again restores). Both are
unassigned until you type a key on the Windows page. The same thing is
available as the action **Window: move / fill** on any button, with a value
such as `next`, `here max`, `2 left`, `br`.

## Keyboard pointer (Ctrl+Alt+G)

A keyboard-driven pointer for reaching small controls across several
screens without the mouse, in the spirit of "mouseless":

1. **Ctrl+Alt+G** covers the screen under the pointer with a lettered grid.
   Type a cell: **column letter, then row letter**. The pointer jumps there.
   **Tab** / **Shift+Tab** or **1-9** move the grid to another screen.
2. The cell becomes the **region**, and a **loupe** appears beside the
   pointer showing the region magnified with nine letters over it.
   **Q W E / A S D / Z X C** zoom into that ninth, again and again, down to
   the pixel. **Arrow keys** nudge by 1 px (Shift 10, Ctrl 40).
   **Backspace** goes back a step; **Home** starts over; **+ / -** change the
   magnification; **L** hides the loupe.
3. **Space** or **Enter** clicks. **R** right-clicks, **M** middle-clicks,
   **F** double-clicks. **G** grabs (holds the left button) so the next moves
   drag; Space or G drops. **N** snaps the pointer onto the control under it
   (UI Automation, so toolbars and dialogs; not buttons painted inside an
   image canvas). **V** leaves the pointer where it is. **Esc** closes.
   **PgUp / PgDn** scroll under the pointer.

While it is open nothing you type reaches the application. The panic key
(Ctrl+Alt+Q) closes it too, and it closes itself after 45 s without a key.
The hotkey is on the Windows page; the action **Keyboard pointer** can also
go on any mouse button.

## If something feels wrong

| Problem | Do this |
|---|---|
| A button or modifier seems stuck | Press **Ctrl+Alt+Q**, or **Unstick my buttons** at the bottom of the settings window |
| I want everything native right now | **Ctrl+Alt+Shift+F11** pauses the whole engine; press again to resume. NumLock also pauses. |
| The settings window will not open | Tray icon > *Settings (classic)…* opens the plain Windows version |
| I lost my bindings after updating | You did not. Config lives in `%APPDATA%\RadMapper\RadMapperConfig.json`; the path is shown on Home. |
| The header says "Not saved to disk" | A write to the settings folder failed. Your edits still work in memory; fix access to the folder and make any edit to retry. Details are on the Diagnostics page. |
| A corrupt config was found on start | It was copied next to the original with a `.corrupt-` suffix and defaults were loaded. If that copy could not be made, saving is blocked until you move the file and restart. |

These are the default hotkeys; Home shows the ones actually configured.

The **Settings** page keeps the keys that are about RadMapper itself — *open
settings*, *pause (combo)*, *pause (single key)* and *panic release* — plus the
click-lock key on Pointer, the clipboard and scratchpad keys, and the keyboard
pointer key on Windows. The five reading-room functions that used to have rows
there (dictation, the two fields, the two teleports) are set from the Home card
instead, where the key sits next to the buttons and menus that also fire it.

### Razer tilt wheels

A tilt wheel sends *WheelLeft* or *WheelRight* every 30-50 ms for as long as it
is held over, so one tilt used to fire a bound action four or five times.
**Tilt guard** (Pointer page, or Settings in Simple view) drops repeats that
arrive within 150 ms of the last accepted one, per direction, which turns a
held tilt into one press; **Wheel guard** does the same for wheel up/down and
ships off. Set either to 0 to turn it off. Plain scrolling — a wheel direction
with no assignment — is never touched.

## Sharing feedback

The **Diagnostics** page lists anything that went wrong and has a **Copy this
list** button. Paste it into your message with what you pressed and what you
expected. **Test my mouse and keyboard…** on that page opens the live input monitor.

## Preview on a Mac

`RadMapper-preview.html` opens in Safari or Chrome, works offline with sample
data, and cannot remap anything. It is a design prototype of a possible next
interface (a visual wheel editor); the Windows build uses a direction table with
the same setup sequence.

## Checks

- Anywhere: `python3 tests/check_source.py` (structural checks and text contrast)
  and `node tests/mockup.cjs`. Neither parses or runs AutoHotkey.
- Windows with AutoHotkey v2:

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut tests\regression.ahk
```

The regression script sets `RM_TEST` so RadMapper's startup (tray, hooks,
hotkeys) is skipped, then exercises the real JSON, config, menu and save helpers
with a temporary config, plus the station, layout-adaptation, window-placement
and keyboard-pointer geometry helpers with a made-up three-screen station. It
installs no bindings and opens no overlay.

See `SECOND-PASS.md` for the second-pass findings and remaining Windows checks,
and the changelog at the top of `RadMapper.ahk` for everything since 0.5.2.
