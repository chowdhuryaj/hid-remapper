# ScrollCapture

A single AutoHotkey v2 script (`ScrollCapture.ahk`) for capturing scrolling
image stacks frame by frame, annotating them, and bundling them up.

## Hotkeys

| Key | Action |
| --- | --- |
| **Shift+F2** | Start a scroll capture on the monitor under the cursor. Focuses the window under the cursor and sends Shift+Space once; if the screen does not change, nothing is captured or saved. Then each step grabs that one monitor, keeps the frame if it changed, and scrolls the mouse wheel down. Press again or Esc to stop. Stops itself after 3 identical frames in a row. |
| **Ctrl+Shift+F2** | Single still of the monitor under the cursor. Saved into the current capture folder, or a new `still-…` folder if none is running. |
| **Shift+F3** | Open the annotator on the last capture; step to any other capture from there. |

## Output

```
%USERPROFILE%\Documents\ScrollCaptures\
  scroll-20260101-120000\
    frame_0001.png ... frame_0042.png   (capture order, top of scroll first)
    session.txt                          (how it stopped, monitor used)
    annotation.txt                       (title, tags, notes for the capture) <- after annotating
    README.txt                           <- after Export bundle
  still-20260101-121500\
    still_20260101-121502-431.png
  bundles\
    scroll-20260101-120000.zip           <- give this back for reconstruction
```

## Annotator

- **Captures:** `< Prev capture` / `Next capture >`, the capture drop-down, or
  Ctrl+PgUp / Ctrl+PgDn move between every capture folder (oldest to newest).
  Annotated captures are marked `[annotated]` in the drop-down.
- **Frames:** the list, the arrow keys, or `< Prev frame` / `Next frame >` step
  through the current capture. The preview is scaled to fit; files are untouched.
- **Annotation is per capture:** Title, Tags and Notes (multi-line). Saved to
  `annotation.txt` when you switch capture, close the window, or export.
- **Export bundle** writes `README.txt`, then zips the current capture into
  `bundles\` and opens it in Explorer.

## Settings

Edit the `Cfg` map at the top of the script:

- `StartDelayMs` (300): after the single Shift+Space that starts the stack, wait this
  long before the first grab.
- `IntervalMs` (150): pace. Each step grabs a frame, then scrolls the mouse wheel down.
  Raise it if frames show a half-finished scroll; lower it for speed.
- `WheelNotches` (3): wheel notches per step. More = bigger jump between frames (less
  overlap); fewer = more overlap but slower to reach the end.
- `StopAfterSame` (3): identical frames in a row that end a scroll capture.
- `MaxFrames` (300): hard cap per scroll capture.
- `OutRoot`: where folders go.

## Requirements and caveats

- **Only one monitor is ever captured.** The monitor under the cursor is read from
  Windows directly, and every capture is checked to lie entirely inside a single
  monitor; anything else is refused and the capture stops. Whatever is on that
  monitor (including any PHI overlays) is still captured, so check frames before
  bundling.
- **You confirm PHI is hidden before anything is saved.** After Shift+Space (scroll)
  or before a still, a dialog asks whether all PHI is hidden on that monitor. The
  default is No; nothing is written to disk unless you answer Yes.
- **Pointer and tooltips stay out of the frames.** For every grab the pointer is
  parked on another monitor (or the far bottom-right pixel with one monitor) and
  only comes back over the image for the wheel step; no tooltip is shown while a
  capture runs. Don't move the mouse during a capture.
- **Shift+Space is a toggle.** The script only checks that the screen changed after
  it, not which way it toggled. Start each capture with the PHI overlay *showing*;
  if it was already hidden, Shift+Space will turn it back on.
- Windows, AutoHotkey v2.0+. No other dependencies (GDI+ is in Windows).
- Bundling uses PowerShell `Compress-Archive`, which is built into Windows.
- Esc only stops a scroll capture while one is running; otherwise it passes through.
- Shift+F2 waits for Shift to be released before the first grab, so the key
  combo doesn't leak into Shift+Space.
- Check the first capture folder after any settings change before relying on it.
