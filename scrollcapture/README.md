# ScrollCapture

A single AutoHotkey v2 script (`ScrollCapture.ahk`) for capturing scrolling
image stacks frame by frame, annotating them, and bundling them up.

## Hotkeys

| Key | Action |
| --- | --- |
| **Shift+F2** | Start a scroll capture on the monitor under the cursor. Each step: grab the monitor, keep the frame if it changed, send Shift+Space. Press again or Esc to stop. Stops itself after 3 identical frames in a row. |
| **Ctrl+Shift+F2** | Single still of the monitor under the cursor. Saved into the current capture folder, or a new `still-…` folder if none is running. |
| **Shift+F3** | Open the annotator for the last capture folder (or pick one). |

## Output

```
%USERPROFILE%\Documents\ScrollCaptures\
  scroll-20260101-120000\
    frame_0001.png ... frame_0042.png   (capture order, top of scroll first)
    session.txt                          (how it stopped, monitor used)
    annotations.tsv                      (frame, tag, note)   <- after annotating
    README.txt                           <- after Export bundle
  still-20260101-121500\
    still_20260101-121502-431.png
  bundles\
    scroll-20260101-120000.zip           <- give this back for reconstruction
```

## Annotator

- Pick a frame in the list; the preview is scaled to fit (originals are untouched).
- **Tag**: `start`, `end`, `duplicate`, `bad`, `still`, `stitch here`.
- **Note**: free text (tabs and newlines are flattened to spaces).
- **Prev / Next** step through frames. Notes are saved when you change frames,
  when you close the window, and on export.
- **Export bundle** writes `annotations.tsv` and `README.txt`, then zips the folder
  into `bundles\` and opens it in Explorer.

## Settings

Edit the `Cfg` map at the top of the script:

- `IntervalMs` (300): auto-scroll pace. The script sends Shift+Space and grabs a
  frame every this many ms, so it scrolls by itself. Lower it to go faster. Raise it if
  frames show a half-finished scroll.
- `StopAfterSame` (3): identical frames in a row that end a scroll capture.
- `MaxFrames` (300): hard cap per scroll capture.
- `OutRoot`: where folders go.

## Requirements and caveats

- Windows, AutoHotkey v2.0+. No other dependencies (GDI+ is in Windows).
- Bundling uses PowerShell `Compress-Archive`, which is built into Windows.
- Esc only stops a scroll capture while one is running; otherwise it passes through.
- Shift+F2 waits for Shift to be released before the first grab, so the key
  combo doesn't leak into Shift+Space.
- Not yet run on a Windows workstation. Check the first capture folder before
  relying on it.
