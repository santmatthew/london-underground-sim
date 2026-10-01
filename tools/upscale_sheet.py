#!/usr/bin/env python3
"""Comparison sheets from tools/upscale_shots.sh: for each view and crop, the five upscaler settings side by side at 1:1 pixels (3 x 2 grid, labelled).
  python3 tools/upscale_sheet.py   -> build/up/sheet_<view>_<crop>.png """
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
UP = os.path.join(ROOT, "build", "up")
MODES = [("native_1.0", "Native 4K (TAA)"), ("fsr1_0.538", "FSR 1 @ 54%: what the game does now at 4K"), ("fsr2_0.667", "FSR 2 @ 67% (DLSS Quality scale)"),
         ("fsr2_0.58", "FSR 2 @ 58% (DLSS Balanced scale)"), ("fsr2_0.5", "FSR 2 @ 50% (DLSS Performance scale)")]
# view -> {crop name: (x, y, w, h) in 4K pixels}
CROPS = {
    "acton_open": {"sign_fence": (0, 600, 960, 540), "brick_fence": (2400, 560, 960, 540), "columns": (1050, 560, 960, 540)},
    "covent_wall": {"lettering": (900, 360, 960, 540)},
    "edgware_plat": {"far": (1500, 560, 960, 540)},
    "oxford_hall": {"gates": (1300, 700, 960, 540)},
}
FONT = None
for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",):
    if os.path.exists(f):
        FONT = ImageFont.truetype(f, 22)


def load(view, key):
    p = os.path.join(UP, "%s__%s.png" % (view, key))
    return Image.open(p).convert("RGB") if os.path.exists(p) else None


def label(im, text):
    d = ImageDraw.Draw(im)
    w = d.textlength(text, font=FONT) + 16
    d.rectangle([0, 0, w, 34], fill=(0, 0, 0))
    d.text((8, 5), text, font=FONT, fill=(255, 230, 80))


for view, crops in CROPS.items():
    imgs = [(load(view, k), t) for k, t in MODES]
    if not any(i for i, _ in imgs):
        continue
    for cname, (x, y, w, h) in crops.items():
        sheet = Image.new("RGB", (w * 3, h * 2), (20, 20, 20))
        for n, (im, t) in enumerate(imgs):
            if im is None:
                continue
            c = im.crop((x, y, x + w, y + h))
            label(c, t)
            sheet.paste(c, ((n % 3) * w, (n // 3) * h))
        out = os.path.join(UP, "sheet_%s_%s.png" % (view, cname))
        sheet.save(out)
        print(out)
