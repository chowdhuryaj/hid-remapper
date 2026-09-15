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
import io
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
    return {"Coalesce": True, "Hotkeys": [{
        "KeyCmd": win, "KeyCtrl": ctrl, "KeyModifiers": mods, "KeyOption": alt,
        "KeyShift": shift, "NativeCode": vk, "QTKeyCode": qt, "VKeyCode": vk}]}


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
FONT_DIR = "/usr/share/fonts/truetype/dejavu/"
FONT_B = FONT_DIR + "DejaVuSans-Bold.ttf"
FONT_R = FONT_DIR + "DejaVuSans.ttf"


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

    def label(self, s, fill=DIM, size=24):
        """Small caption along the bottom edge (baked in, so no Stream Deck title is needed)."""
        self.text((144, 262), s.upper(), size=size, fill=fill)

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
    # a form field with a caret and a chevron showing the travel direction
    ic.rect([48, 150, 240, 206], outline=DIM, width=6, radius=8)
    ic.rect([48, 72, 240, 128], outline=CYAN, width=8, radius=8)
    ic.line([(72, 84), (72, 116)], fill=INK, width=8)
    if direction == "next":
        ic.chevron(228, 140, 20, "down", fill=PINK)
        ic.label("next field")
    else:
        ic.chevron(228, 140, 20, "up", fill=PINK)
        ic.label("prev field")


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


def ic_magnify(ic, sign=None, lbl="magnify"):
    ic.ell([52, 40, 196, 184], fill=BG2, outline=CYAN, width=12)
    ic.line([(180, 168), (244, 232)], fill=CYAN, width=22)
    if sign == "+":
        ic.line([(124, 84), (124, 140)], fill=INK, width=12)
    if sign in ("+", "-"):
        ic.line([(96, 112), (152, 112)], fill=INK, width=12)
    if sign is None:
        # a little "zoomed detail" inside the lens
        ic.arc([80, 68, 168, 156], 200, 340, fill=DIM, width=6)
    ic.label(lbl)


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
    ic.label("delete")


def ic_spine(ic):
    # a column of vertebral bodies with labels beside them
    for i, y in enumerate((44, 92, 140, 188)):
        ic.rect([100, y, 172, y + 36], fill=BG2, outline=INK, width=6, radius=8)
        ic.ell([120, y + 36, 152, y + 50], fill=DIM)
        ic.text((208, y + 18), f"L{i + 1}", size=22, fill=OLIVE)
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


def ic_preset(ic, n, organ):
    """Window preset: big digit on the left, an organ glyph on the right."""
    ic.text((84, 132), str(n), size=120, fill=CYAN)
    gx, gy = 200, 128
    if organ == "soft":     # torso oval with a softer inner oval
        ic.ell([gx - 44, gy - 60, gx + 44, gy + 60], outline=INK, width=7)
        ic.ell([gx - 24, gy - 32, gx + 24, gy + 32], fill=BG2, outline=DIM, width=5)
    elif organ == "bone":   # long bone
        ic.line([(gx, gy - 46), (gx, gy + 46)], fill=INK, width=18)
        for y in (gy - 46, gy + 46):
            ic.dot(gx - 14, y, 14, fill=INK); ic.dot(gx + 14, y, 14, fill=INK)
    elif organ == "brain":
        ic.ell([gx - 48, gy - 50, gx + 48, gy + 42], outline=INK, width=7)
        ic.line([(gx, gy - 50), (gx, gy + 42)], fill=INK, width=6)
        for dx in (-24, 24):
            ic.arc([gx + dx - 18, gy - 26, gx + dx + 18, gy + 6], 0, 360, fill=DIM, width=5)
    elif organ == "cspine":  # small vertebral column
        for y in (gy - 54, gy - 18, gy + 18):
            ic.rect([gx - 24, y, gx + 24, y + 28], outline=INK, width=6, radius=6)
    elif organ == "cta":     # branching vessel
        ic.line([(gx, gy + 60), (gx, gy - 4), (gx - 34, gy - 50)], fill=RED, width=12)
        ic.line([(gx, gy - 4), (gx + 34, gy - 50)], fill=RED, width=12)
        ic.line([(gx, gy + 24), (gx + 30, gy)], fill=RED, width=8)
    elif organ == "infarct":  # brain with a wedge of low density
        ic.ell([gx - 48, gy - 50, gx + 48, gy + 42], outline=INK, width=7)
        ic.d.pieslice([(gx - 48) * S, (gy - 50) * S, (gx + 48) * S, (gy + 42) * S], 300, 350, fill=DIM)
        ic.line([(gx, gy - 50), (gx, gy + 42)], fill=INK, width=6)
    elif organ == "liver":
        ic.poly([(gx - 50, gy - 30), (gx + 20, gy - 44), (gx + 48, gy - 10), (gx + 30, gy + 44), (gx - 30, gy + 30)],
                outline=INK, width=7)
    elif organ in ("lung", "lungwide"):
        gx += 14
        for sx in (-1, 1):
            ic.ell([gx + sx * 26 - 20, gy - 46, gx + sx * 26 + 20, gy + 46],
                   outline=INK, width=7 if organ == "lung" else 5)
        ic.line([(gx, gy - 58), (gx, gy - 24)], fill=INK, width=7)
        if organ == "lungwide":
            ic.line([(gx - 56, gy + 62), (gx + 56, gy + 62)], fill=CYAN, width=6)
            ic.chevron(gx - 50, gy + 62, 9, "left"); ic.chevron(gx + 50, gy + 62, 9, "right")


def ic_digit(ic, s, color=INK):
    ic.text((144, 138), s, size=150 if len(s) == 1 else 90, fill=color)


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


def ic_undo(ic, redo=False):
    if redo:
        ic.arc([64, 70, 224, 230], 200, 400, fill=CYAN, width=14)
        ic.poly([(198, 62), (244, 104), (188, 118)], fill=CYAN)
        ic.label("redo")
    else:
        ic.arc([64, 70, 224, 230], 140, 340, fill=CYAN, width=14)
        ic.poly([(90, 62), (44, 104), (100, 118)], fill=CYAN)
        ic.label("undo")


def ic_select_all(ic):
    for i in range(12):
        x = 48 + i * 16
        ic.line([(x, 60), (x + 8, 60)], fill=CYAN, width=6); ic.line([(x, 228), (x + 8, 228)], fill=CYAN, width=6)
        y = 60 + i * 14
        ic.line([(48, y), (48, y + 7)], fill=CYAN, width=6); ic.line([(240, y), (240, y + 7)], fill=CYAN, width=6)
    for y in (100, 130, 160, 190):
        ic.line([(76, y), (212, y)], fill=INK, width=8)
    ic.label("select all")


def ic_copy(ic):
    ic.rect([60, 48, 176, 176], outline=DIM, width=7, radius=8)
    ic.rect([104, 92, 228, 232], fill=BG, outline=INK, width=8, radius=8)
    for y in (128, 156, 184):
        ic.line([(128, y), (204, y)], fill=DIM, width=6)
    ic.label("copy")


def ic_paste(ic):
    ic.rect([68, 60, 220, 236], fill=BG2, outline=INK, width=8, radius=10)
    ic.rect([108, 44, 180, 80], fill=CYAN, radius=8)
    for y in (120, 150, 180):
        ic.line([(96, y), (192, y)], fill=DIM, width=6)
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
    ic.label("openevidence", fill=GREEN, size=20)


def ic_umnrad(ic):
    # chest radiograph silhouette in maroon/gold
    ic.rect([56, 40, 232, 224], fill=(30, 30, 34), outline=MAROON, width=8, radius=10)
    for sx in (-1, 1):
        ic.ell([144 + sx * 42 - 28, 76, 144 + sx * 42 + 28, 196], fill=(60, 60, 66))
    ic.line([(144, 60), (144, 210)], fill=(200, 200, 205), width=10)
    for y in (96, 124, 152, 180):
        ic.arc([64, y - 22, 224, y + 22], 190, 350, fill=(170, 170, 176), width=5)
    ic.label("umn radiology", fill=GOLD, size=20)


def ic_folder(ic, kind, lbl):
    """Folder buttons: a tab with a big glyph, so the destination reads at a glance."""
    ic.rect([36, 40, 252, 232], fill=BG2, outline=DIM, width=6, radius=14)
    ic.rect([36, 40, 130, 68], fill=DIM, radius=8)
    if kind == "ps":
        ic.rect([124, 84, 164, 156], fill=PINK, radius=20)
        ic.arc([104, 112, 184, 184], 0, 180, fill=INK, width=9)
        ic.line([(144, 184), (144, 204)], fill=INK, width=9)
    elif kind == "pacs":
        ic.line([(144, 76), (144, 212)], fill=CYAN, width=6)
        ic.line([(76, 144), (212, 144)], fill=CYAN, width=6)
        ic.ell([108, 108, 180, 180], outline=CYAN, width=8)
        ic.ell([70, 70, 218, 218], outline=DIM, width=4)
    elif kind == "window":
        for i in range(10):
            g = int(30 + i * 22)
            ic.rect([72 + i * 14, 84, 88 + i * 14, 204], fill=(g, g, g))
        ic.rect([72, 84, 216, 204], outline=INK, width=5)
    elif kind == "numpad":
        for r in range(3):
            for c in range(3):
                ic.dot(100 + c * 44, 100 + r * 44, 14, fill=CYAN)
    elif kind == "web":
        ic.ell([84, 80, 204, 200], outline=CYAN, width=7)
        ic.ell([120, 80, 168, 200], outline=CYAN, width=5)
        ic.line([(84, 140), (204, 140)], fill=CYAN, width=5)
    elif kind == "windows":
        for x, y in ((80, 84), (150, 84), (80, 150), (150, 150)):
            ic.rect([x, y, x + 58, y + 54], fill=BG, outline=CYAN, width=6, radius=4)
    ic.label(lbl)


def ic_back(ic):
    ic.arrow((216, 144), (72, 144), fill=DIM, width=16, head=40)
    ic.label("back")


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
        ic.label("to right screen", size=20)
    else:
        ic.rect([204, 88, 248, 140], fill=CYAN, radius=4)
        ic.arrow((188, 114), (88, 114), fill=PINK)
        ic.label("to left screen", size=20)


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
    ic.label("show desktop")


def ic_close(ic):
    ic.rect([44, 56, 244, 216], outline=DIM, width=6, radius=8)
    ic.line([(96, 92), (192, 180)], fill=RED, width=16)
    ic.line([(192, 92), (96, 180)], fill=RED, width=16)
    ic.label("close window")


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
    ic.label("pause engine")


def ic_unstick(ic):
    # an open hand: release everything
    ic.rect([96, 120, 196, 220], fill=BG2, outline=OLIVE, width=8, radius=30)
    for i, x in enumerate((104, 132, 160, 188)):
        ic.rect([x - 12, 60 + (0 if 0 < i < 3 else 20), x + 12, 140], fill=BG2, outline=OLIVE, width=8, radius=12)
    ic.label("unstick keys")


def ic_clipboard(ic):
    ic.rect([68, 60, 220, 236], fill=BG2, outline=INK, width=8, radius=10)
    ic.rect([108, 44, 180, 80], fill=OLIVE, radius=8)
    for y in (116, 146, 176, 206):
        ic.line([(96, y), (192, y)], fill=DIM, width=6)
    ic.label("clip history")


def ic_topend(ic, top=True):
    ic_doc(ic, arrow="up" if top else "down", lbl="report top" if top else "report end")


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


def site(name, draw, url):
    b = Btn(name, draw, ("com.elgato.streamdeck.system.website", {"openInBrowser": True, "path": url}))
    b.combo = url
    return b


def folder(name, kind, lbl, page_key):
    b = Btn(name, lambda ic: ic_folder(ic, kind, lbl), ("folder", page_key))
    b.combo = "opens folder"
    return b


def back():
    b = Btn("Back", ic_back, ("com.elgato.streamdeck.profile.backtoparent", {}))
    b.combo = "back to home"
    return b


# Shared buttons (same key everywhere they appear) -----------------------------
# PowerScribe: these three keys are RadMapper's shipped GLOBAL bindings
# (` = ps_dictate, [ = ps_next, ] = ps_prev).  RadMapper routes them to
# PowerScribe from any window and returns focus, so they work while PACS has
# the cursor.
DICTATE = hk("Dictate on/off", ic_mic, "`", note="RadMapper ` -> PowerScribe F4 (psDictateKey)")
PREV_FIELD = hk("Previous field", lambda ic: ic_field(ic, "prev"), "]", note="RadMapper ] -> Shift+Tab in PowerScribe")
NEXT_FIELD = hk("Next field", lambda ic: ic_field(ic, "next"), "[", note="RadMapper [ -> Tab in PowerScribe")
IMPRESSION = hk("Impression", lambda ic: ic_doc(ic, True, "impression"), "1", ctrl=True, shift=True,
                note="PowerScribe menu slice in RadMapper; PowerScribe must be in front")
PREV_SERIES = hk("Previous series", lambda ic: ic_series(ic, "prev"), "f7", note="RadMapper PACS wheel")
NEXT_SERIES = hk("Next series", lambda ic: ic_series(ic, "next"), "f8", note="RadMapper PACS wheel")
RULER = hk("Ruler", ic_ruler, "r", note="RadMapper PACS wheel")
ROI = hk("ROI", ic_roi, "r", shift=True, note="RadMapper PACS wheel")
MAGNIFY = hk("Magnifying glass", ic_magnify, "y", note="RadMapper PACS wheel")
CLAHE = hk("CLAHE", ic_clahe, "c", shift=True, note="RadMapper PACS wheel")
DELETE = hk("Delete measurement", ic_trash, "delete", note="RadMapper PACS wheel")

PRESETS = [("Soft tissue", "soft"), ("Bone", "bone"), ("Brain", "brain"), ("C-spine soft tissue", "cspine"),
           ("CTA", "cta"), ("Infarct", "infarct"), ("Liver", "liver"), ("Lung", "lung"), ("Lung wide", "lungwide")]


def preset_btn(i):
    name, organ = PRESETS[i - 1]
    return hk(f"W/L {i} {name}", lambda ic, i=i, organ=organ: ic_preset(ic, i, organ), str(i),
              note="RadMapper Window presets ring")


def numpad(s):
    key = {".": ".", "-": "-"}.get(s, s)
    return hk(f"Numpad {s}", lambda ic, s=s: ic_digit(ic, s), key)


PAGES = {}  # key -> (name, 3x5 grid)

PAGES["home"] = ("RadMapper Radiology", [
    [DICTATE, PREV_FIELD, NEXT_FIELD, folder("PowerScribe", "ps", "powerscribe", "ps"), folder("Websites", "web", "websites", "web")],
    [PREV_SERIES, NEXT_SERIES, folder("PACS tools", "pacs", "pacs tools", "pacs"), folder("Windowing", "window", "windowing", "wl"), folder("Number pad", "numpad", "number pad", "num")],
    [RULER, ROI, MAGNIFY, DELETE, folder("Windows", "windows", "windows", "win")],
])

PAGES["ps"] = ("PowerScribe", [
    [back(), DICTATE, PREV_FIELD, NEXT_FIELD, IMPRESSION],
    [hk("Undo", ic_undo, "z", ctrl=True), hk("Redo", lambda ic: ic_undo(ic, True), "y", ctrl=True),
     hk("Select all", ic_select_all, "a", ctrl=True), hk("Copy", ic_copy, "c", ctrl=True), hk("Paste", ic_paste, "v", ctrl=True)],
    [hk("Backspace", ic_backspace, "backspace"), hk("Delete forward", lambda ic: ic_backspace(ic, "delete fwd", True), "delete"),
     hk("Top of report", ic_topend, "home", ctrl=True), hk("End of report", lambda ic: ic_topend(ic, False), "end", ctrl=True),
     hk("Sign report", ic_sign, "s", ctrl=True, shift=True, needs_setup=True,
        note="Assign Ctrl+Shift+S to Sign in PowerScribe One > Settings > Quick Keys")],
])

PAGES["pacs"] = ("PACS tools", [
    [back(), RULER, ROI, MAGNIFY, CLAHE],
    [hk("Spine labeling", ic_spine, "s", shift=True, needs_setup=True, note="Assign Shift+S to Spine Labeling in IntelliSpace > Preferences > Keyboard shortcuts"),
     hk("Localizer mode", ic_localizer, "l", needs_setup=True, note="Assign L to Localizer Mode in IntelliSpace preferences"),
     hk("Scout line mode", ic_scout, "l", shift=True, needs_setup=True, note="Assign Shift+L to Scout Lines in IntelliSpace preferences"),
     hk("Zoom in", lambda ic: ic_magnify(ic, "+", "zoom in"), "=", needs_setup=True, note="Assign = (plus key) to Zoom In in IntelliSpace preferences"),
     hk("Zoom out", lambda ic: ic_magnify(ic, "-", "zoom out"), "-", needs_setup=True, note="Assign - to Zoom Out in IntelliSpace preferences")],
    [PREV_SERIES, NEXT_SERIES, DELETE,
     hk("Invert", ic_invert, "i", shift=True, needs_setup=True, note="Assign Shift+I to Invert in IntelliSpace preferences"),
     folder("Windowing", "window", "windowing", "wl")],
])

PAGES["wl"] = ("Windowing", [
    [back(), preset_btn(1), preset_btn(2), preset_btn(3), preset_btn(4)],
    [preset_btn(5), preset_btn(6), preset_btn(7), preset_btn(8), preset_btn(9)],
    [hk("W/L 0 (spare preset)", lambda ic: (ic_digit(ic, "0", CYAN), ic.label("spare preset")), "0",
        note="RadMapper's W/L dial ring also sends 0; assign a tenth preset in IntelliSpace if wanted"),
     hk("Invert", ic_invert, "i", shift=True, needs_setup=True, note="Assign Shift+I to Invert in IntelliSpace preferences"),
     MAGNIFY, CLAHE, folder("PACS tools", "pacs", "pacs tools", "pacs")],
])

PAGES["num"] = ("Number pad", [
    [back(), numpad("7"), numpad("8"), numpad("9"), hk("Backspace", ic_backspace, "backspace")],
    [numpad("-"), numpad("4"), numpad("5"), numpad("6"), numpad(".")],
    [numpad("0"), numpad("1"), numpad("2"), numpad("3"), hk("Enter", ic_enter, "enter")],
])

PAGES["web"] = ("Websites", [
    [back(), site("UMN Mail", ic_mail, "https://mail.umn.edu"), site("Claude", ic_claude, "https://claude.ai"),
     site("OpenEvidence", ic_openevidence, "https://www.openevidence.com"), site("UMN Radiology", ic_umnrad, "https://umnradiology.com")],
    [None, None, None, None, None],
    [None, None, None, None, None],
])

PAGES["win"] = ("Windows", [
    [back(), hk("Snap left", lambda ic: ic_snap(ic, "left"), "left", win=True), hk("Snap right", lambda ic: ic_snap(ic, "right"), "right", win=True),
     hk("Maximize", ic_maxmin, "up", win=True), hk("Minimize", lambda ic: ic_maxmin(ic, False), "down", win=True)],
    [hk("Move to left monitor", lambda ic: ic_move_monitor(ic, "left"), "left", win=True, shift=True),
     hk("Move to right monitor", lambda ic: ic_move_monitor(ic, "right"), "right", win=True, shift=True),
     hk("Task view", ic_taskview, "tab", win=True), hk("Switch app", ic_alttab, "tab", alt=True), hk("Show desktop", ic_desktop, "d", win=True)],
    [hk("Close window", ic_close, "f4", alt=True),
     hk("RadMapper settings", ic_radmapper, "f9", ctrl=True, alt=True, shift=True, note="RadMapper hkGui"),
     hk("RadMapper pause/resume", ic_pause, "f11", ctrl=True, alt=True, shift=True, note="RadMapper hkToggle"),
     hk("Unstick buttons", ic_unstick, "q", ctrl=True, alt=True, note="RadMapper hkPanic"),
     hk("Clipboard history", ic_clipboard, "c", ctrl=True, alt=True, note="RadMapper hkClipboard shelf")],
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


def action_json(btn, page_ids, image_rel):
    kind, payload = btn.action
    if kind == "folder":
        uuid_, settings = "com.elgato.streamdeck.profile.openchild", {"ProfileUUID": page_ids[payload]}
        name = "Create Folder"
    else:
        uuid_, settings = kind, payload
        name = {"com.elgato.streamdeck.system.hotkey": "Hotkey", "com.elgato.streamdeck.system.website": "Website",
                "com.elgato.streamdeck.profile.backtoparent": "Parent Folder"}[uuid_]
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
                actions[f"{c},{r}"] = action_json(btn, page_ids, f"Images/{fname}")
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
                   "Pages": {"Current": page_ids["home"], "Default": page_ids["home"], "Pages": list(page_ids.values())},
                   "Version": "2.0"}, f, indent=1)

    out_file = os.path.join(out_dir, "RadMapper Radiology.streamDeckProfile")
    with zipfile.ZipFile(out_file, "w", zipfile.ZIP_DEFLATED) as z:
        for dp, _, fns in os.walk(stage):
            for fn in fns:
                full = os.path.join(dp, fn)
                z.write(full, os.path.relpath(full, stage))
    shutil.rmtree(stage)

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
