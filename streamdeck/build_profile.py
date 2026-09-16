#!/usr/bin/env python3
"""Build the RadMapper Radiology Stream Deck MK.2 profile.

Generates every button icon with Pillow, writes the Stream Deck v2 profile
bundle (top-level manifest + one page manifest per folder) and zips it as
``RadMapper Radiology.streamDeckProfile``.  Also writes ``preview.png``, a
contact sheet of every page, so the layout can be checked without a device.

Keys are taken from RadMapper.ahk (shipped defaults, the PACS radial menu and
the Window-preset ring).  Buttons whose PACS / PowerScribe shortcut is
site-configurable are marked ``needs_setup=True``; they carry a small gear
badge and are listed in README.md with the key they send.

Usage:  python3 build_profile.py [--out DIR]
"""
import argparse
import json
import math
import os
import shutil
import uuid
import zipfile

from PIL import Image, ImageDraw, ImageFont

# ─── key codes ──────────────────────────────────────────────────────────────
# Windows virtual-key codes and Qt key codes for the keys this profile sends.
QT_F1 = 0x01000030
KEYS = {  # name: (VKeyCode, QTKeyCode)
    "tab": (9, 0x01000001), "backspace": (8, 0x01000003), "enter": (13, 0x01000004),
    "delete": (46, 0x01000007), "home": (36, 0x01000010), "end": (35, 0x01000011),
    "left": (37, 0x01000012), "up": (38, 0x01000013), "right": (39, 0x01000014),
    "down": (40, 0x01000015), "escape": (27, 0x01000000), "space": (32, 32),
    "`": (192, 96), "[": (219, 91), "]": (221, 93), "=": (187, 61), "-": (189, 45),
    ".": (190, 46),
}
for i in range(1, 13):
    KEYS[f"f{i}"] = (111 + i, QT_F1 + i - 1)
for c in "abcdefghijklmnopqrstuvwxyz0123456789":
    KEYS[c] = (ord(c.upper()), ord(c.upper()))

MOD_ALT, MOD_CTRL, MOD_SHIFT, MOD_WIN = 1, 2, 4, 8


def hotkey_settings(key, ctrl=False, shift=False, alt=False, win=False):
    vk, qt = KEYS[key]
    mods = (MOD_ALT if alt else 0) | (MOD_CTRL if ctrl else 0) | (MOD_SHIFT if shift else 0) | (MOD_WIN if win else 0)
    # Stream Deck stores four hotkey slots per key; the unused three are blank.
    blank = {"KeyCmd": False, "KeyCtrl": False, "KeyModifiers": 0, "KeyOption": False,
             "KeyShift": False, "NativeCode": -1, "QTKeyCode": 33554431, "VKeyCode": -1}
    return {"Coalesce": True, "Hotkeys": [{
        "KeyCmd": win, "KeyCtrl": ctrl, "KeyModifiers": mods, "KeyOption": alt,
        "KeyShift": shift, "NativeCode": vk, "QTKeyCode": qt, "VKeyCode": vk}]
        + [dict(blank) for _ in range(3)]}


def combo_text(key, ctrl=False, shift=False, alt=False, win=False):
    parts = []
    if win: parts.append("Win")
    if ctrl: parts.append("Ctrl")
    if alt: parts.append("Alt")
    if shift: parts.append("Shift")
    parts.append(key.upper() if len(key) == 1 else key.capitalize())
    return "+".join(parts)


# ─── palette (RadMapper "Lumi Atlas": dark navy, cyan, pink, olive) ─────────
BG = (14, 22, 40)
BG2 = (22, 33, 58)
INK = (232, 238, 248)
DIM = (128, 142, 170)
CYAN = (86, 214, 232)
PINK = (236, 110, 160)
OLIVE = (176, 196, 96)
AMBER = (246, 190, 80)
RED = (232, 88, 88)
MAROON = (122, 0, 25)
GOLD = (255, 204, 51)
ORANGE = (218, 119, 86)
GREEN = (74, 190, 130)

S = 4                      # supersampling factor
PX = 288                   # Stream Deck key image size
W = PX * S
# The first (bold, regular) pair that exists on this machine.  Set FONT_B /
# FONT_R by hand below if your fonts live somewhere else.
FONT_CANDIDATES = [
    ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
     "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    ("C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/segoeui.ttf"),
    ("C:/Windows/Fonts/arialbd.ttf", "C:/Windows/Fonts/arial.ttf"),
    ("/System/Library/Fonts/Supplemental/Arial Bold.ttf",
     "/System/Library/Fonts/Supplemental/Arial.ttf"),
]
FONT_B = FONT_R = None
for _b, _r in FONT_CANDIDATES:
    if os.path.exists(_b) and os.path.exists(_r):
        FONT_B, FONT_R = _b, _r
        break
if FONT_B is None:
    raise SystemExit(
        "No usable font found.  Looked for:\n  "
        + "\n  ".join(f"{b}  +  {r}" for b, r in FONT_CANDIDATES)
        + "\nSet FONT_B / FONT_R at the top of build_profile.py to a bold and a "
          "regular TrueType font that exist on this machine.")


def font(size, bold=True):
    return ImageFont.truetype(FONT_B if bold else FONT_R, int(size * S))


class Icon:
    """A 288x288 canvas drawn at 4x and downsampled; coordinates are in 288-space."""

    def __init__(self, bg=BG):
        self.im = Image.new("RGBA", (W, W), bg + (255,))
        self.d = ImageDraw.Draw(self.im)

    # scaled primitives -------------------------------------------------
    def _s(self, pts):
        # accepts either [x0, y0, x1, y1] boxes or [(x, y), ...] point lists
        if pts and isinstance(pts[0], (int, float)):
            return [v * S for v in pts]
        return [(p[0] * S, p[1] * S) for p in pts]

    def line(self, pts, fill=CYAN, width=10):
        self.d.line(self._s(pts), fill=fill, width=int(width * S), joint="curve")

    def poly(self, pts, fill=None, outline=None, width=8):
        self.d.polygon(self._s(pts), fill=fill, outline=outline, width=int(width * S))

    def rect(self, box, fill=None, outline=None, width=8, radius=0):
        self.d.rounded_rectangle(self._s(box), radius=radius * S, fill=fill, outline=outline, width=int(width * S))

    def ell(self, box, fill=None, outline=None, width=8):
        self.d.ellipse(self._s(box), fill=fill, outline=outline, width=int(width * S))

    def arc(self, box, start, end, fill=CYAN, width=10):
        self.d.arc(self._s(box), start, end, fill=fill, width=int(width * S))

    def dot(self, cx, cy, r, fill=CYAN):
        self.ell([cx - r, cy - r, cx + r, cy + r], fill=fill)

    def text(self, xy, s, size=28, fill=INK, bold=True, anchor="mm"):
        self.d.text((xy[0] * S, xy[1] * S), s, font=font(size, bold), fill=fill, anchor=anchor)

    def label(self, s, fill=DIM, size=30):
        """Small caption along the bottom edge (baked in, so no Stream Deck title is needed)."""
        s = s.upper()
        while size > 28 and self.d.textlength(s, font=font(size)) / S > 248:
            size -= 1  # "dictate + next" is the only caption wide enough to need this
        self.text((144, 262), s, size=size, fill=fill)

    def arrow(self, p0, p1, fill=CYAN, width=12, head=26):
        (x0, y0), (x1, y1) = p0, p1
        self.line([p0, p1], fill=fill, width=width)
        a = math.atan2(y1 - y0, x1 - x0)
        for da in (2.5, -2.5):
            self.line([(x1, y1), (x1 + head * math.cos(a + da), y1 + head * math.sin(a + da))], fill=fill, width=width)

    def chevron(self, cx, cy, size, direction, fill=CYAN, width=14):
        dx = size if direction == "right" else -size if direction == "left" else 0
        dy = size if direction == "down" else -size if direction == "up" else 0
        if dx:
            pts = [(cx - dx / 2, cy - size), (cx + dx / 2, cy), (cx - dx / 2, cy + size)]
        else:
            pts = [(cx - size, cy - dy / 2), (cx, cy + dy / 2), (cx + size, cy - dy / 2)]
        self.line(pts, fill=fill, width=width)

    def dashed_ellipse(self, box, fill=CYAN, width=8, dashes=16):
        x0, y0, x1, y1 = box
        step = 360 / dashes
        for i in range(dashes):
            self.arc(box, i * step, i * step + step * 0.55, fill=fill, width=width)

    def badge_gear(self):
        """Corner marker: this shortcut must be assigned in the app's preferences."""
        cx, cy, r = 250, 38, 20
        self.dot(cx, cy, r + 8, fill=BG)
        for i in range(8):
            a = i * math.pi / 4
            self.line([(cx + (r - 6) * math.cos(a), cy + (r - 6) * math.sin(a)),
                       (cx + (r + 4) * math.cos(a), cy + (r + 4) * math.sin(a))], fill=AMBER, width=7)
        self.ell([cx - r + 6, cy - r + 6, cx + r - 6, cy + r - 6], outline=AMBER, width=6)
        self.dot(cx, cy, 5, fill=AMBER)

    def save(self, path):
        self.im.resize((PX, PX), Image.LANCZOS).convert("RGB").save(path, "PNG")


# ─── icon drawings ──────────────────────────────────────────────────────────
def ic_mic(ic, color=PINK, lbl="dictate"):
    ic.rect([112, 44, 176, 150], fill=color, radius=32)
    ic.arc([84, 84, 204, 194], 0, 180, fill=INK, width=12)
    ic.line([(144, 194), (144, 222)], fill=INK, width=12)
    ic.line([(104, 222), (184, 222)], fill=INK, width=12)
    ic.label(lbl)


def ic_field(ic, direction):
    # two form fields: the highlighted one is where the caret ends up
    prev = direction == "prev"
    ic.rect([44, 72, 204, 128], outline=CYAN if prev else DIM, width=8 if prev else 6, radius=8)
    ic.rect([44, 150, 204, 206], outline=DIM if prev else CYAN, width=6 if prev else 8, radius=8)
    cy = 100 if prev else 178
    ic.line([(68, cy - 16), (68, cy + 16)], fill=INK, width=8)
    if prev:
        ic.arrow((236, 200), (236, 72), fill=PINK, width=14, head=30)
    else:
        ic.arrow((236, 72), (236, 200), fill=PINK, width=14, head=30)
    ic.label("prev field" if prev else "next field")


def ic_doc(ic, highlight_bottom=False, lbl="", arrow=None):
    ic.poly([(70, 40), (180, 40), (218, 78), (218, 236), (70, 236)], outline=INK, width=8)
    ic.line([(180, 40), (180, 78), (218, 78)], fill=INK, width=8)
    for y in (104, 130, 156):
        ic.line([(96, y), (192, y)], fill=DIM, width=8)
    if highlight_bottom:
        ic.rect([90, 180, 198, 214], fill=PINK, radius=6)
        ic.text((144, 197), "IMP", size=22, fill=BG)
    if arrow == "up":
        ic.arrow((250, 200), (250, 70), fill=CYAN)
    if arrow == "down":
        ic.arrow((250, 70), (250, 200), fill=CYAN)
    if lbl:
        ic.label(lbl)


def ic_series(ic, direction):
    # a stack of axial slices, arrow shows direction through the stack
    for i, y in enumerate((70, 100, 130, 160)):
        col = CYAN if (i == 0 and direction == "prev") or (i == 3 and direction == "next") else DIM
        ic.ell([80, y - 18, 208, y + 18], outline=col, width=7)
    if direction == "next":
        ic.arrow((240, 60), (240, 200), fill=PINK)
        ic.label("next series")
    else:
        ic.arrow((240, 200), (240, 60), fill=PINK)
        ic.label("prev series")


def ic_ruler(ic):
    pts = [(48, 208), (208, 48), (240, 80), (80, 240)]
    ic.poly(pts, fill=BG2, outline=AMBER, width=8)
    for t in range(1, 7):
        f = t / 7
        x, y = 48 + (208 - 48) * f, 208 + (48 - 208) * f
        ln = 18 if t % 2 else 30
        ic.line([(x, y), (x + ln * 0.7, y + ln * 0.7)], fill=AMBER, width=6)
    ic.label("ruler")


def ic_roi(ic):
    ic.dashed_ellipse([60, 78, 228, 206], fill=OLIVE, width=9)
    ic.text((144, 142), "ROI", size=40, fill=INK)
    ic.label("roi")


def ic_magnify(ic):
    # a lens held over a small image tile: a loupe, not a zoom level
    ic.rect([40, 96, 164, 220], fill=BG2, outline=DIM, width=6, radius=6)
    ic.arc([56, 140, 148, 232], 200, 340, fill=DIM, width=6)
    ic.ell([100, 40, 236, 176], fill=BG2, outline=CYAN, width=12)
    ic.arc([118, 74, 218, 174], 200, 340, fill=INK, width=9)
    ic.line([(214, 154), (252, 192)], fill=CYAN, width=20)
    ic.label("magnify")


def ic_zoom(ic, sign):
    # a big +/- with one diagonal pair of corner arrows, pulling out or in
    cx, cy, h = 144, 130, 60
    ic.line([(cx - h, cy), (cx + h, cy)], fill=INK, width=22)
    if sign == "+":
        ic.line([(cx, cy - h), (cx, cy + h)], fill=INK, width=22)
    for dx, dy in ((-1, -1), (1, 1)):
        near = (cx + dx * 86, cy + dy * 74)
        far = (cx + dx * 118, cy + dy * 100)
        if sign == "+":
            ic.arrow(near, far, fill=CYAN, width=10, head=22)
        else:
            ic.arrow(far, near, fill=CYAN, width=10, head=22)
    ic.label("zoom in" if sign == "+" else "zoom out")


def ic_clahe(ic):
    ic.ell([64, 44, 224, 204], outline=INK, width=8)
    ic.d.pieslice([64 * S, 44 * S, 224 * S, 204 * S], 90, 270, fill=INK)
    ic.label("clahe")


def ic_trash(ic):
    ic.rect([84, 84, 204, 232], fill=BG2, outline=RED, width=8, radius=10)
    ic.line([(64, 84), (224, 84)], fill=RED, width=10)
    ic.rect([116, 54, 172, 84], outline=RED, width=8, radius=6)
    for x in (116, 144, 172):
        ic.line([(x, 112), (x, 204)], fill=RED, width=7)
    ic.label("del measure")


def ic_spine(ic):
    # three vertebral bodies with a disc between each: big enough to read at 72 px
    for y in (52, 116, 180):
        ic.rect([106, y, 182, y + 44], fill=BG2, outline=INK, width=7, radius=8)
        ic.ell([118, y + 44, 170, y + 64], fill=DIM)
    ic.label("spine label")


def ic_localizer(ic):
    ic.rect([48, 48, 240, 240], outline=DIM, width=6)
    ic.line([(144, 40), (144, 248)], fill=CYAN, width=6)
    ic.line([(40, 144), (248, 144)], fill=CYAN, width=6)
    ic.ell([116, 116, 172, 172], outline=PINK, width=8)
    ic.label("localizer")


def ic_scout(ic):
    # a sagittal-style outline with horizontal reference lines across it
    ic.ell([76, 40, 212, 232], outline=DIM, width=6)
    for y in (84, 116, 148, 180):
        ic.line([(44, y), (244, y)], fill=CYAN if y == 116 else OLIVE, width=7 if y == 116 else 5)
    ic.label("scout lines")


def ic_invert(ic):
    ic.rect([56, 56, 232, 232], outline=INK, width=8, radius=12)
    ic.d.polygon([(56 * S, 56 * S), (232 * S, 56 * S), (56 * S, 232 * S)], fill=INK)
    ic.label("invert")


def ic_preset(ic, n, organ, name):
    """Window preset: the digit anchors the key, an organ glyph sits beside it."""
    ic.text((66, 120), str(n), size=80, fill=CYAN)
    # every organ is drawn in the same ~96 px optical box with the same stroke
    gx, gy, w = 190, 128, 7
    if organ == "soft":     # torso oval with a softer inner oval
        ic.ell([gx - 36, gy - 48, gx + 36, gy + 48], outline=INK, width=w)
        ic.ell([gx - 19, gy - 26, gx + 19, gy + 26], fill=BG2, outline=DIM, width=w)
    elif organ == "bone":   # long bone with two condyles at each end
        ic.line([(gx, gy - 34), (gx, gy + 34)], fill=INK, width=w)
        for y in (gy - 38, gy + 38):
            ic.ell([gx - 30, y - 12, gx - 4, y + 12], outline=INK, width=w)
            ic.ell([gx + 4, y - 12, gx + 30, y + 12], outline=INK, width=w)
    elif organ == "brain":
        ic.ell([gx - 44, gy - 48, gx + 44, gy + 44], outline=INK, width=w)
        ic.line([(gx, gy - 48), (gx, gy + 44)], fill=INK, width=w)
        for dx in (-22, 22):
            ic.arc([gx + dx - 17, gy - 24, gx + dx + 17, gy + 8], 0, 360, fill=DIM, width=w)
    elif organ == "cspine":  # small vertebral column
        for y in (gy - 48, gy - 12, gy + 24):
            ic.rect([gx - 26, y, gx + 26, y + 26], outline=INK, width=w, radius=6)
    elif organ == "cta":     # branching vessel
        ic.line([(gx, gy + 48), (gx, gy - 6), (gx - 32, gy - 46)], fill=RED, width=w)
        ic.line([(gx, gy - 6), (gx + 32, gy - 46)], fill=RED, width=w)
        ic.line([(gx, gy + 20), (gx + 28, gy - 4)], fill=RED, width=w)
    elif organ == "infarct":  # brain with a solid wedge of low density
        box = [gx - 44, gy - 48, gx + 44, gy + 44]
        ic.ell(box, outline=INK, width=w)
        ic.d.pieslice(ic._s(box), 288, 356, fill=DIM, outline=INK, width=4 * S)
        ic.line([(gx, gy - 48), (gx, gy + 44)], fill=INK, width=w)
    elif organ == "liver":
        ic.poly([(gx - 46, gy - 26), (gx + 18, gy - 42), (gx + 46, gy - 8), (gx + 28, gy + 44), (gx - 28, gy + 28)],
                outline=INK, width=w)
    elif organ in ("lung", "lungwide"):
        for sx in (-1, 1):
            ic.ell([gx + sx * 24 - 19, gy - 46, gx + sx * 24 + 19, gy + 34], outline=INK, width=w)
        ic.line([(gx, gy - 56), (gx, gy - 26)], fill=INK, width=w)
        if organ == "lungwide":  # the same lungs, opened out by a wide double arrow
            ic.line([(gx - 62, gy + 54), (gx + 62, gy + 54)], fill=CYAN, width=w)
            ic.chevron(gx - 56, gy + 54, 12, "left", width=w)
            ic.chevron(gx + 56, gy + 54, 12, "right", width=w)
    ic.label(name)


def ic_digit(ic, s, color=INK):
    if s == ".":
        ic.dot(144, 170, 30, fill=color)
        ic.label("point")
    else:
        ic.text((144, 128), s, size=150 if len(s) == 1 else 90, fill=color)


def ic_backspace(ic, lbl="backspace", forward=False):
    if forward:
        ic.poly([(244, 144), (180, 72), (44, 72), (44, 216), (180, 216)], fill=BG2, outline=INK, width=8)
        cx = 112
    else:
        ic.poly([(44, 144), (108, 72), (244, 72), (244, 216), (108, 216)], fill=BG2, outline=INK, width=8)
        cx = 178
    ic.line([(cx - 28, 116), (cx + 28, 172)], fill=RED, width=10)
    ic.line([(cx + 28, 116), (cx - 28, 172)], fill=RED, width=10)
    ic.label(lbl)


def ic_enter(ic):
    ic.line([(224, 72), (224, 150), (80, 150)], fill=CYAN, width=14)
    ic.chevron(84, 150, 26, "left", fill=CYAN)
    ic.label("enter")


def curved_arrow(ic, cx, cy, r, a0, a1, fill=CYAN, width=14, head=30):
    """Arc from a0 to a1 degrees (PIL: clockwise from +x) with a triangular head at a1."""
    ic.arc([cx - r, cy - r, cx + r, cy + r], a0, a1, fill=fill, width=width)
    t = math.radians(a1)
    tip = (cx + r * math.cos(t), cy + r * math.sin(t))
    # tangent at a1 in the direction of travel (increasing angle)
    tx, ty = -math.sin(t), math.cos(t)
    nx, ny = math.cos(t), math.sin(t)
    base = (tip[0] - tx * head * 0.2, tip[1] - ty * head * 0.2)
    p1 = (base[0] + tx * head, base[1] + ty * head)
    p2 = (base[0] + nx * head * 0.75, base[1] + ny * head * 0.75)
    p3 = (base[0] - nx * head * 0.75, base[1] - ny * head * 0.75)
    ic.poly([p1, p2, p3], fill=fill)


def ic_undo(ic, redo=False):
    # undo: the arc sweeps round to the left and the head lands at 9 o'clock.
    # redo: the arc sweeps round to the right, head at 3 o'clock.  Different
    # arcs, not one image flipped, so the two never read as the same key.
    if redo:
        curved_arrow(ic, 144, 144, 76, 200, 360, fill=OLIVE, width=16, head=36)
    else:
        curved_arrow(ic, 144, 144, 76, 20, 180, fill=CYAN, width=16, head=36)
    ic.label("redo" if redo else "undo")


def ic_paste(ic):
    # a clipboard with its clip, holding one page
    ic.rect([68, 56, 220, 232], fill=BG2, outline=INK, width=8, radius=10)
    ic.rect([108, 40, 180, 76], fill=CYAN, radius=8)
    ic.rect([94, 100, 194, 212], fill=BG, outline=DIM, width=6, radius=6)
    for y in (128, 156, 184):
        ic.line([(114, y), (174, y)], fill=DIM, width=6)
    ic.label("paste")


def ic_sign(ic):
    ic.line([(48, 200), (100, 130), (130, 200), (170, 110), (200, 190), (244, 150)], fill=PINK, width=10)
    ic.line([(40, 226), (248, 226)], fill=DIM, width=6)
    ic.label("sign")


def ic_globe(ic, lbl):
    ic.ell([56, 44, 232, 220], outline=CYAN, width=8)
    ic.ell([112, 44, 176, 220], outline=CYAN, width=6)
    ic.line([(56, 132), (232, 132)], fill=CYAN, width=6)
    ic.arc([56, 80, 232, 184], 0, 360, fill=CYAN, width=5)
    ic.label(lbl)


def ic_mail(ic):
    ic.rect([44, 72, 244, 212], fill=MAROON, outline=GOLD, width=8, radius=10)
    ic.line([(52, 80), (144, 156), (236, 80)], fill=GOLD, width=9)
    ic.label("umn mail", fill=GOLD)


def ic_claude(ic):
    # eight-spoke spark, Claude's terracotta colour
    for i in range(8):
        a = i * math.pi / 4
        ic.line([(144 + 26 * math.cos(a), 132 + 26 * math.sin(a)), (144 + 86 * math.cos(a), 132 + 86 * math.sin(a))],
                fill=ORANGE, width=18)
    ic.dot(144, 132, 22, fill=ORANGE)
    ic.label("claude", fill=ORANGE)


def ic_openevidence(ic):
    ic.ell([52, 40, 236, 224], fill=BG2, outline=GREEN, width=8)
    ic.text((144, 132), "OE", size=72, fill=GREEN)
    ic.label("openev", fill=GREEN)


def ic_umnrad(ic):
    # chest radiograph silhouette in maroon/gold
    ic.rect([56, 40, 232, 224], fill=(44, 48, 60), outline=GOLD, width=8, radius=10)
    for sx in (-1, 1):
        ic.ell([144 + sx * 42 - 28, 76, 144 + sx * 42 + 28, 196], fill=(92, 96, 108))
    ic.line([(144, 60), (144, 210)], fill=(200, 200, 205), width=10)
    for y in (96, 124, 152, 180):
        ic.arc([64, y - 22, 224, y + 22], 190, 350, fill=(200, 200, 205), width=5)
    ic.label("umn rad", fill=GOLD)


def ic_folder(ic, kind, lbl):
    """Folder buttons: a tab with a big glyph, so the destination reads at a glance."""
    ic.rect([36, 40, 252, 232], fill=BG2, outline=INK, width=6, radius=14)
    ic.rect([36, 40, 130, 68], fill=INK, radius=8)
    if kind == "ps":
        # a report page beside a small microphone
        ic.rect([68, 88, 156, 208], outline=DIM, width=6, radius=6)
        for y in (112, 136, 160, 184):
            ic.line([(86, y), (138, y)], fill=DIM, width=5)
        ic.rect([190, 96, 216, 142], outline=DIM, width=6, radius=13)
        ic.arc([176, 108, 230, 162], 0, 180, fill=DIM, width=6)
        ic.line([(203, 162), (203, 184)], fill=DIM, width=6)
        ic.line([(186, 184), (220, 184)], fill=DIM, width=6)
    elif kind == "pacs":
        ic.line([(144, 76), (144, 212)], fill=DIM, width=6)
        ic.line([(76, 144), (212, 144)], fill=DIM, width=6)
        ic.ell([108, 108, 180, 180], outline=DIM, width=8)
        ic.ell([70, 70, 218, 218], outline=DIM, width=4)
    elif kind == "window":
        for i in range(10):
            g = int(30 + i * 22)
            ic.rect([72 + i * 14, 84, 88 + i * 14, 204], fill=(g, g, g))
        ic.rect([72, 84, 216, 204], outline=DIM, width=5)
    elif kind == "numpad":
        for r in range(3):
            for c in range(3):
                ic.dot(100 + c * 44, 100 + r * 44, 14, fill=DIM)
    elif kind == "desktop":
        # a browser window: title bar with three dots and a globe inside
        ic.rect([64, 80, 224, 208], fill=BG, outline=DIM, width=6, radius=6)
        ic.line([(64, 104), (224, 104)], fill=DIM, width=5)
        for x in (80, 96, 112):
            ic.dot(x, 92, 4, fill=DIM)
        ic.ell([116, 122, 172, 178], outline=DIM, width=5)
        ic.line([(116, 150), (172, 150)], fill=DIM, width=4)
        ic.ell([134, 122, 154, 178], outline=DIM, width=4)
    elif kind == "system":
        # a gear: the machine and RadMapper's own settings
        cx, cy, r = 144, 140, 46
        for i in range(8):
            a = i * math.pi / 8 * 2
            ic.line([(cx + (r - 6) * math.cos(a), cy + (r - 6) * math.sin(a)),
                     (cx + (r + 18) * math.cos(a), cy + (r + 18) * math.sin(a))], fill=DIM, width=13)
        ic.ell([cx - r, cy - r, cx + r, cy + r], outline=DIM, width=11)
        ic.ell([cx - 16, cy - 16, cx + 16, cy + 16], outline=DIM, width=8)
    ic.label(lbl)


def ic_home(ic):
    ic.poly([(144, 56), (48, 140), (76, 140), (76, 224), (212, 224), (212, 140), (240, 140)], fill=BG2, outline=CYAN, width=8)
    ic.rect([124, 168, 164, 224], fill=CYAN, radius=4)
    ic.label("home")


def ic_snap(ic, side):
    ic.rect([40, 56, 248, 216], outline=DIM, width=6, radius=6)
    box = [48, 64, 144, 208] if side == "left" else [144, 64, 240, 208]
    ic.rect(box, fill=CYAN, radius=4)
    ic.label(f"snap {side}")


def ic_maxmin(ic, maximize=True):
    ic.rect([40, 56, 248, 216], outline=DIM, width=6, radius=6)
    if maximize:
        ic.rect([48, 64, 240, 208], fill=CYAN, radius=4)
        ic.label("maximize")
    else:
        ic.rect([64, 176, 224, 208], fill=CYAN, radius=4)
        ic.label("minimize")


def ic_move_monitor(ic, direction):
    for x in (28, 156):
        ic.rect([x, 76, x + 104, 152], outline=DIM, width=6, radius=6)
        ic.line([(x + 52, 152), (x + 52, 176)], fill=DIM, width=6)
        ic.line([(x + 24, 176), (x + 80, 176)], fill=DIM, width=6)
    if direction == "right":
        ic.rect([40, 88, 84, 140], fill=CYAN, radius=4)
        ic.arrow((100, 114), (200, 114), fill=PINK)
        ic.label("screen right")
    else:
        ic.rect([204, 88, 248, 140], fill=CYAN, radius=4)
        ic.arrow((188, 114), (88, 114), fill=PINK)
        ic.label("screen left")


def ic_taskview(ic):
    for x, y, w, h in ((44, 76, 90, 70), (154, 76, 90, 70), (44, 158, 90, 70), (154, 158, 90, 70)):
        ic.rect([x, y, x + w, y + h], fill=BG2, outline=CYAN, width=6, radius=6)
    ic.label("task view")


def ic_alttab(ic):
    ic.rect([44, 96, 176, 196], fill=BG2, outline=DIM, width=6, radius=6)
    ic.rect([100, 64, 240, 164], fill=BG2, outline=CYAN, width=8, radius=6)
    ic.chevron(72, 224, 14, "left"); ic.chevron(216, 224, 14, "right")
    ic.label("switch app")


def ic_desktop(ic):
    ic.rect([44, 56, 244, 190], outline=CYAN, width=8, radius=8)
    ic.line([(144, 190), (144, 214)], fill=CYAN, width=8)
    ic.line([(96, 214), (192, 214)], fill=CYAN, width=8)
    ic.label("desktop")


def ic_close(ic):
    ic.rect([44, 56, 244, 216], outline=DIM, width=6, radius=8)
    ic.line([(96, 92), (192, 180)], fill=RED, width=16)
    ic.line([(192, 92), (96, 180)], fill=RED, width=16)
    ic.label("close")


def ic_radmapper(ic):
    # a mouse with a cyan wheel and a gear: RadMapper settings
    ic.rect([84, 52, 204, 232], fill=BG2, outline=INK, width=8, radius=60)
    ic.line([(144, 52), (144, 132)], fill=INK, width=6)
    ic.line([(84, 132), (204, 132)], fill=INK, width=6)
    ic.rect([132, 76, 156, 112], fill=CYAN, radius=10)
    ic.label("radmapper")


def ic_pause(ic):
    ic.ell([52, 44, 236, 228], outline=AMBER, width=8)
    ic.rect([108, 92, 132, 180], fill=AMBER, radius=4)
    ic.rect([156, 92, 180, 180], fill=AMBER, radius=4)
    ic.label("pause")


def ic_unstick(ic):
    # an open hand: release everything
    ic.rect([96, 120, 196, 220], fill=BG2, outline=OLIVE, width=8, radius=30)
    for i, x in enumerate((104, 132, 160, 188)):
        ic.rect([x - 12, 60 + (0 if 0 < i < 3 else 20), x + 12, 140], fill=BG2, outline=OLIVE, width=8, radius=12)
    ic.label("unstick")


def ic_clipboard(ic):
    # two stacked sheets, offset, with a clock: older clips kept around
    ic.rect([52, 40, 180, 196], fill=BG2, outline=DIM, width=6, radius=8)
    ic.rect([96, 76, 224, 232], fill=BG2, outline=OLIVE, width=8, radius=8)
    for y in (112, 142, 172):
        ic.line([(118, y), (202, y)], fill=DIM, width=6)
    ic.ell([188, 164, 250, 226], fill=BG, outline=OLIVE, width=7)
    ic.line([(219, 180), (219, 196), (236, 196)], fill=OLIVE, width=7)
    ic.label("clip history")


def ic_field_dictate(ic):
    # the same field grammar as ic_field, plus a mic: two steps in one press
    ic.rect([28, 76, 140, 128], outline=DIM, width=6, radius=8)
    ic.rect([28, 150, 140, 202], outline=CYAN, width=8, radius=8)
    ic.line([(50, 160), (50, 192)], fill=INK, width=8)
    ic.arrow((236, 72), (236, 200), fill=PINK, width=14, head=30)
    ic.rect([173, 60, 199, 110], fill=PINK, radius=13)
    ic.arc([159, 70, 213, 124], 0, 180, fill=INK, width=7)
    ic.line([(186, 124), (186, 146)], fill=INK, width=7)
    ic.line([(169, 146), (203, 146)], fill=INK, width=7)
    ic.label("dictate + next")


def ic_copy_all(ic):
    ic.rect([56, 44, 176, 196], outline=DIM, width=7, radius=8)
    ic.rect([104, 92, 232, 236], fill=BG, outline=INK, width=8, radius=8)
    for y in (128, 156, 184, 212):
        ic.line([(128, y), (208, y)], fill=CYAN, width=6)
    ic.label("copy all")


def ic_open_all(ic):
    for i, (x, y) in enumerate(((60, 52), (150, 52), (60, 132), (150, 132))):
        ic.rect([x, y, x + 78, y + 66], fill=BG2, outline=(CYAN, ORANGE, GREEN, GOLD)[i], width=6, radius=6)
        ic.line([(x, y + 16), (x + 78, y + 16)], fill=(CYAN, ORANGE, GREEN, GOLD)[i], width=4)
    ic.label("all sites")


def ic_scratch(ic):
    # a page with a pencil lying diagonally across it
    ic.rect([60, 44, 228, 228], fill=BG2, outline=INK, width=8, radius=10)
    for y in (84, 114, 144, 174, 204):
        ic.line([(84, y), (204, y)], fill=DIM, width=6)
    ic.line([(96, 204), (208, 80)], fill=AMBER, width=20)
    ic.poly([(70, 232), (100, 220), (86, 194)], fill=INK)
    ic.line([(210, 78), (226, 60)], fill=DIM, width=18)
    ic.label("scratchpad")


# ─── button definitions ─────────────────────────────────────────────────────
class Btn:
    def __init__(self, name, draw, action=None, needs_setup=False, note=""):
        self.name, self.draw, self.needs_setup, self.note = name, draw, needs_setup, note
        self.action = action  # (uuid, settings) or callable(profile ids)

    def image(self):
        ic = Icon()
        self.draw(ic)
        if self.needs_setup:
            ic.badge_gear()
        return ic


def hk(name, draw, key, ctrl=False, shift=False, alt=False, win=False, needs_setup=False, note=""):
    b = Btn(name, draw, ("com.elgato.streamdeck.system.hotkey", hotkey_settings(key, ctrl, shift, alt, win)),
            needs_setup, note)
    b.combo = combo_text(key, ctrl, shift, alt, win)
    return b


def multi(name, draw, steps, combo, note=""):
    """A Stream Deck Multi Action: steps is a list of (uuid, settings), run in order."""
    b = Btn(name, draw, ("multi", steps), note=note)
    b.combo = combo
    return b


def site(name, draw, url):
    b = Btn(name, draw, ("com.elgato.streamdeck.system.website", {"openInBrowser": True, "path": url}))
    b.combo = url
    return b


def folder(name, kind, lbl, page_key):
    b = Btn(name, lambda ic: ic_folder(ic, kind, lbl), ("folder", page_key))
    b.combo = "opens folder"
    return b


def home():
    # Switch Profile back to this profile's root page, so it works from any depth
    b = Btn("Home", ic_home, ("root", None))
    b.combo = "switch to profile root"
    return b


# ─── key routing ────────────────────────────────────────────────────────────
# Native: the buttons send PowerScribe's own keys (F4 / Tab / Shift+Tab), so
# they work whenever PowerScribe has focus, with no dependency on RadMapper.
# Set ROUTE_PS_VIA_RADMAPPER = True to send RadMapper's global ` [ ] bindings
# instead: RadMapper then brings PowerScribe forward, delivers the key and
# returns focus, so the same buttons work while the PACS viewer has the cursor.
ROUTE_PS_VIA_RADMAPPER = False

if ROUTE_PS_VIA_RADMAPPER:
    DICTATE = hk("Dictate on/off", ic_mic, "`", note="RadMapper ` -> PowerScribe F4 from any window")
    PREV_FIELD = hk("Previous field", lambda ic: ic_field(ic, "prev"), "]", note="RadMapper ] -> Shift+Tab from any window")
    NEXT_FIELD = hk("Next field", lambda ic: ic_field(ic, "next"), "[", note="RadMapper [ -> Tab from any window")
else:
    DICTATE = hk("Dictate on/off", ic_mic, "f4", note="PowerScribe dictation toggle (its default key; PS must be in front)")
    PREV_FIELD = hk("Previous field", lambda ic: ic_field(ic, "prev"), "tab", shift=True, note="PowerScribe")
    NEXT_FIELD = hk("Next field", lambda ic: ic_field(ic, "next"), "tab", note="PowerScribe")

IMPRESSION = hk("Impression", lambda ic: ic_doc(ic, True, "impression"), "1", ctrl=True, shift=True,
                note="PowerScribe menu slice in RadMapper; PowerScribe must be in front")
PREV_SERIES = hk("Previous series", lambda ic: ic_series(ic, "prev"), "f7", note="RadMapper PACS wheel")
NEXT_SERIES = hk("Next series", lambda ic: ic_series(ic, "next"), "f8", note="RadMapper PACS wheel")
RULER = hk("Ruler", ic_ruler, "r", note="RadMapper PACS wheel")
ROI = hk("ROI", ic_roi, "r", shift=True, note="RadMapper PACS wheel")
MAGNIFY = hk("Magnifying glass", ic_magnify, "y", note="RadMapper PACS wheel")
UNDO = hk("Undo", ic_undo, "z", ctrl=True)
REDO = hk("Redo", lambda ic: ic_undo(ic, True), "y", ctrl=True)
CLAHE = hk("CLAHE", ic_clahe, "c", shift=True, note="RadMapper PACS wheel")
DELETE = hk("Delete measurement", ic_trash, "delete", note="RadMapper PACS wheel")
INVERT = hk("Invert", ic_invert, "i", shift=True, needs_setup=True, note="Assign Shift+I to Invert in IntelliSpace preferences")

SWITCH_APP = hk("Switch app", ic_alttab, "tab", alt=True)
SHOW_DESKTOP = hk("Show desktop", ic_desktop, "d", win=True)
TO_LEFT_SCREEN = hk("Move to left monitor", lambda ic: ic_move_monitor(ic, "left"), "left", win=True, shift=True)
TO_RIGHT_SCREEN = hk("Move to right monitor", lambda ic: ic_move_monitor(ic, "right"), "right", win=True, shift=True)

PRESETS = [  # (name, organ glyph, caption)
    ("Soft tissue", "soft", "soft tissue"), ("Bone", "bone", "bone"), ("Brain", "brain", "brain"),
    ("C-spine soft tissue", "cspine", "c-spine"), ("CTA", "cta", "cta"), ("Infarct", "infarct", "infarct"),
    ("Liver", "liver", "liver"), ("Lung", "lung", "lung"), ("Lung wide", "lungwide", "lung wide")]


def preset_btn(i):
    name, organ, cap = PRESETS[i - 1]
    return hk(f"W/L {i} {name}", lambda ic, i=i, organ=organ, cap=cap: ic_preset(ic, i, organ, cap), str(i),
              note="RadMapper Window presets ring")


def numpad(s):
    return hk(f"Numpad {s}", lambda ic, s=s: ic_digit(ic, s), s)


HK = "com.elgato.streamdeck.system.hotkey"
WEB = "com.elgato.streamdeck.system.website"

SITES = [("UMN Mail", ic_mail, "https://mail.umn.edu"), ("Claude", ic_claude, "https://claude.ai"),
         ("OpenEvidence", ic_openevidence, "https://www.openevidence.com"),
         ("UMN Radiology", ic_umnrad, "https://umnradiology.com")]

# Multi Actions (Stream Deck native, several steps per press) ------------------
FIELD_AND_DICTATE = multi("Dictate + next field", ic_field_dictate,
                          [(HK, DICTATE.action[1]), (HK, NEXT_FIELD.action[1])],
                          "Dictate, then Next field",
                          note="stop dictation, then jump to the next field; RadMapper's macro adds a 150 ms pause "
                               "between the two, which a Stream Deck Multi Action does not")
COPY_REPORT = multi("Copy whole report", ic_copy_all,
                    [(HK, hotkey_settings("a", ctrl=True)), (HK, hotkey_settings("c", ctrl=True)),
                     (HK, hotkey_settings("end", ctrl=True))],
                    "Ctrl+A, Ctrl+C, Ctrl+End",
                    note="select the whole report, copy it (e.g. to paste into Claude), then drop the "
                         "selection so the next keystroke cannot overwrite the report")
OPEN_ALL_SITES = multi("Open all sites", ic_open_all,
                       [(WEB, {"openInBrowser": True, "path": url}) for _, _, url in SITES],
                       "opens all four sites", note="")

# ─── folder strip ───────────────────────────────────────────────────────────
FOLDERS = {
    "ps":    ("PowerScribe editing", "ps",      "editing"),
    "pacs":  ("PACS tools",          "pacs",    "pacs tools"),
    "pacs2": ("PACS more",           "pacs",    "more tools"),
    "wl":    ("Windowing",           "window",  "windowing"),
    "num":   ("Number pad",          "numpad",  "number pad"),
    "web":   ("Web & windows",       "desktop", "web"),
    "sys":   ("System",              "system",  "system"),
}


def go(key):
    name, kind, lbl = FOLDERS[key]
    return folder(name, kind, lbl, key)


# Fixed strip columns, so a section always sits under the same finger.  On a
# page that is itself one of these sections, its own column holds Number pad.
STRIP_SLOTS = ["ps", "pacs", "wl", "web"]


def strip(page_key):
    """Bottom-row navigation: Home, Editing, PACS tools, Windowing, Web & windows."""
    return [home()] + [go("num" if k == page_key else k) for k in STRIP_SLOTS]


PAGES = {}  # key -> (name, 3x5 grid)

# Home: the five every-case keys, the four edit keys used in every report, and
# the folder strip. Every folder page ends in a strip too, so any section is
# one press from any other.
PAGES["home"] = ("RadMapper Radiology", [
    [DICTATE, PREV_FIELD, NEXT_FIELD, SWITCH_APP, IMPRESSION],
    [PREV_SERIES, NEXT_SERIES, UNDO, REDO, go("num")],
    [go("sys"), go("ps"), go("pacs"), go("wl"), go("web")],
])

PAGES["ps"] = ("PowerScribe editing", [
    [DICTATE, PREV_FIELD, NEXT_FIELD, FIELD_AND_DICTATE, IMPRESSION],
    [UNDO, REDO, COPY_REPORT,
     hk("Sign report", ic_sign, "s", ctrl=True, shift=True, needs_setup=True,
        note="Assign Ctrl+Shift+S to Sign in PowerScribe One > Settings > Quick Keys"),
     hk("Paste", ic_paste, "v", ctrl=True)],
    strip("ps"),
])

PAGES["pacs"] = ("PACS tools", [
    [RULER, ROI, MAGNIFY, CLAHE, DELETE],
    [PREV_SERIES, NEXT_SERIES,
     hk("Zoom in", lambda ic: ic_zoom(ic, "+"), "=", needs_setup=True, note="Assign = (plus key) to Zoom In in IntelliSpace preferences"),
     hk("Zoom out", lambda ic: ic_zoom(ic, "-"), "-", needs_setup=True, note="Assign - to Zoom Out in IntelliSpace preferences"),
     go("pacs2")],
    strip("pacs"),
])

PAGES["pacs2"] = ("PACS more", [
    [hk("Spine labeling", ic_spine, "s", shift=True, needs_setup=True, note="Assign Shift+S to Spine Labeling in IntelliSpace > Preferences > Keyboard shortcuts"),
     hk("Localizer mode", ic_localizer, "l", needs_setup=True, note="Assign L to Localizer Mode in IntelliSpace preferences"),
     hk("Scout line mode", ic_scout, "l", shift=True, needs_setup=True, note="Assign Shift+L to Scout Lines in IntelliSpace preferences"),
     INVERT, preset_btn(8)],
    [preset_btn(1), preset_btn(2), preset_btn(3), PREV_SERIES, NEXT_SERIES],
    strip("pacs"),
])

PAGES["wl"] = ("Windowing", [
    [preset_btn(1), preset_btn(2), preset_btn(3), preset_btn(4), preset_btn(5)],
    [preset_btn(6), preset_btn(7), preset_btn(8), preset_btn(9), INVERT],
    strip("wl"),
])

# Number pad: a 3x3 digit block in the middle three columns, with the keys that
# go with typing numbers down the outside.
PAGES["num"] = ("Number pad", [
    [hk("Backspace", ic_backspace, "backspace"), numpad("7"), numpad("8"), numpad("9"), hk("Enter", ic_enter, "enter")],
    [numpad("."), numpad("4"), numpad("5"), numpad("6"), numpad("0")],
    [home(), numpad("1"), numpad("2"), numpad("3"), go("ps")],
])

PAGES["web"] = ("Web & windows", [
    [site(n, d, u) for n, d, u in SITES] + [hk("Close window", ic_close, "f4", alt=True)],
    [hk("Snap left", lambda ic: ic_snap(ic, "left"), "left", win=True), hk("Snap right", lambda ic: ic_snap(ic, "right"), "right", win=True),
     hk("Maximize", ic_maxmin, "up", win=True), hk("Minimize", lambda ic: ic_maxmin(ic, False), "down", win=True),
     OPEN_ALL_SITES],
    strip("web"),
])

PAGES["sys"] = ("System", [
    [hk("RadMapper settings", ic_radmapper, "f9", ctrl=True, alt=True, shift=True, note="RadMapper hkGui"),
     hk("RadMapper pause/resume", ic_pause, "f11", ctrl=True, alt=True, shift=True, note="RadMapper hkToggle"),
     hk("Unstick buttons", ic_unstick, "q", ctrl=True, alt=True, note="RadMapper hkPanic"),
     hk("Clipboard history", ic_clipboard, "c", ctrl=True, alt=True, note="RadMapper hkClipboard shelf"),
     hk("Scratchpad", ic_scratch, "n", ctrl=True, alt=True, note="RadMapper hkScratch shelf")],
    [hk("Task view", ic_taskview, "tab", win=True), TO_LEFT_SCREEN, TO_RIGHT_SCREEN, SHOW_DESKTOP, SWITCH_APP],
    strip("sys"),
])


# ─── profile writer ─────────────────────────────────────────────────────────
def page_folder_id(u):
    """Stream Deck names page folders with a base32-ish encoding of the UUID plus 'Z'."""
    hexs = u.replace("-", "") + "000"
    groups = [hexs[i:i + 5] for i in range(0, len(hexs), 5)]
    s = "".join(_b32(int(g, 16)) for g in groups)[:26].upper()
    return s.replace("V", "W").replace("U", "V") + "Z"


def _b32(n):
    digits = "0123456789abcdefghijklmnopqrstuv"
    out = ""
    for _ in range(4):
        out = digits[n % 32] + out
        n //= 32
    return out


def inner_action(uuid_, settings, title=""):
    name = {"com.elgato.streamdeck.system.hotkey": "Hotkey", "com.elgato.streamdeck.system.website": "Website"}[uuid_]
    return {"ActionID": str(uuid.uuid4()), "LinkedTitle": True, "Name": name,
            "Plugin": {"Name": name, "UUID": uuid_, "Version": "1.0"},
            "Resources": None, "Settings": settings,
            "State": 0, "States": [{"Title": title}], "UUID": uuid_}


def action_json(btn, page_ids, bundle_uuid, image_rel):
    kind, payload = btn.action
    if kind == "multi":
        # Stream Deck 6.x nests every step in Actions[0]; the outer list is
        # per-state, so state 1 is present and empty.
        steps = [inner_action(u, st, btn.name) for u, st in payload]
        return {
            "ActionID": str(uuid.uuid4()), "LinkedTitle": True, "Name": "Multi Action",
            "Plugin": {"Name": "Multi Action", "UUID": "com.elgato.streamdeck.multiactions", "Version": "1.0"},
            "Settings": {},
            "Actions": [{"Actions": steps}, {"Actions": []}],
            "State": 0,
            "States": [{"FontFamily": "", "FontSize": 9, "FontStyle": "", "FontUnderline": False, "Image": image_rel,
                        "OutlineThickness": 2, "ShowTitle": False, "Title": btn.name, "TitleAlignment": "bottom",
                        "TitleColor": "#ffffff"}],
            "UUID": "com.elgato.streamdeck.multiactions.routine",
        }
    if kind == "folder":
        uuid_, settings = "com.elgato.streamdeck.profile.openchild", {"ProfileUUID": page_ids[payload]}
        name = "Create Folder"
    elif kind == "root":
        uuid_ = "com.elgato.streamdeck.profile.rotate"
        settings = {"DeviceUUID": "", "PageIndex": 0, "ProfileUUID": bundle_uuid}
        name = "Switch Profile"
    else:
        uuid_, settings = kind, payload
        name = {"com.elgato.streamdeck.system.hotkey": "Hotkey",
                "com.elgato.streamdeck.system.website": "Website"}[uuid_]
    return {
        "ActionID": str(uuid.uuid4()), "LinkedTitle": True, "Name": name, "Settings": settings, "State": 0,
        "States": [{"FontFamily": "", "FontSize": 9, "FontStyle": "", "FontUnderline": False, "Image": image_rel,
                    "OutlineThickness": 2, "ShowTitle": False, "Title": btn.name, "TitleAlignment": "bottom",
                    "TitleColor": "#ffffff"}],
        "UUID": uuid_,
    }


def build(out_dir):
    bundle_uuid = str(uuid.uuid4()).upper()
    page_ids = {k: str(uuid.uuid4()).upper() for k in PAGES}
    stage = os.path.join(out_dir, "_stage")
    shutil.rmtree(stage, ignore_errors=True)
    root = os.path.join(stage, f"{bundle_uuid}.sdProfile")
    os.makedirs(root)

    preview_pages = []
    setup_rows, all_rows = [], []
    try:
        for key, (name, grid) in PAGES.items():
            pdir = os.path.join(root, "Profiles", page_folder_id(page_ids[key]))
            os.makedirs(os.path.join(pdir, "Images"))
            actions = {}
            sheet = Image.new("RGB", (5 * (PX + 12) + 12, 3 * (PX + 12) + 12 + 60), (8, 12, 24))
            ImageDraw.Draw(sheet).text((16, 14), name, font=ImageFont.truetype(FONT_B, 34), fill=INK)
            for r, row in enumerate(grid):
                for c, btn in enumerate(row):
                    if btn is None:
                        continue
                    fname = f"{c}_{r}_{btn.name.lower().replace(' ', '_').replace('/', '')}.png"
                    fname = "".join(ch for ch in fname if ch.isalnum() or ch in "._")
                    ic = btn.image()
                    ic.save(os.path.join(pdir, "Images", fname))
                    actions[f"{c},{r}"] = action_json(btn, page_ids, bundle_uuid, f"Images/{fname}")
                    sheet.paste(Image.open(os.path.join(pdir, "Images", fname)), (12 + c * (PX + 12), 72 + r * (PX + 12)))
                    row_ = (name, f"{c},{r}", btn.name, btn.combo, btn.note)
                    all_rows.append(row_)
                    if btn.needs_setup:
                        setup_rows.append(row_)
            with open(os.path.join(pdir, "manifest.json"), "w") as f:
                json.dump({"Controllers": [{"Actions": actions, "Type": "Keypad"}], "Icon": "", "Name": name}, f, indent=1)
            preview_pages.append(sheet)

        with open(os.path.join(root, "manifest.json"), "w") as f:
            json.dump({"AppIdentifier": "*", "Name": "RadMapper Radiology",
                       # child pages are reached by openchild, so only home is listed
                       "Pages": {"Current": page_ids["home"], "Default": page_ids["home"], "Pages": [page_ids["home"]]},
                       "Version": "2.0"}, f, indent=1)

        out_file = os.path.join(out_dir, "RadMapper Radiology.streamDeckProfile")
        # fixed timestamps and a stable walk order: two rebuilds of the same
        # layout differ only in the UUIDs they generate.
        with zipfile.ZipFile(out_file, "w", zipfile.ZIP_DEFLATED) as z:
            for dp, _, fns in sorted(os.walk(stage)):
                for fn in sorted(fns):
                    full = os.path.join(dp, fn)
                    info = zipfile.ZipInfo(os.path.relpath(full, stage), date_time=(2026, 1, 1, 0, 0, 0))
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.external_attr = 0o644 << 16
                    with open(full, "rb") as fh:
                        z.writestr(info, fh.read())
    finally:
        shutil.rmtree(stage, ignore_errors=True)

    # contact sheet: pages stacked vertically
    h = sum(p.height for p in preview_pages)
    sheet = Image.new("RGB", (preview_pages[0].width, h), (8, 12, 24))
    y = 0
    for p in preview_pages:
        sheet.paste(p, (0, y)); y += p.height
    sheet.save(os.path.join(out_dir, "preview.png"))

    with open(os.path.join(out_dir, "keymap.md"), "w") as f:
        f.write("# Every button and the key it sends\n\nGenerated by build_profile.py.\n\n")
        f.write("| Page | Key | Button | Sends | Note |\n|---|---|---|---|---|\n")
        for row in all_rows:
            f.write("| " + " | ".join(str(x).replace("|", "\\|") for x in row) + " |\n")
        f.write("\n## Buttons that need a shortcut assigned in the app (gear badge)\n\n")
        f.write("| Page | Key | Button | Sends | Do this |\n|---|---|---|---|---|\n")
        for row in setup_rows:
            f.write("| " + " | ".join(str(x).replace("|", "\\|") for x in row) + " |\n")
    return out_file


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.dirname(os.path.abspath(__file__)))
    a = ap.parse_args()
    print("wrote", build(a.out))
