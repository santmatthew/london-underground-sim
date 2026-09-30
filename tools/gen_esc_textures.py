#!/usr/bin/env python3
"""Escalator notices (FICTIONAL layout of the standard TfL notice board; wording after the real one) -> assets/textures/props/esc/
  notice.png   the wall board at the head and foot of an escalator: stand on the right / hold the handrail / children / dogs / no smoking
run: build/venv/bin/python tools/gen_esc_textures.py"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "textures", "props", "esc")
os.makedirs(OUT, exist_ok=True)
FB = os.path.join(ROOT, "assets", "fonts", "Barlow-Bold.ttf")
FS = os.path.join(ROOT, "assets", "fonts", "Barlow-SemiBold.ttf")

BLUE = (23, 32, 128)
WHITE = (245, 245, 245)
RED = (200, 40, 40)
ORANGE = (244, 135, 51)


def notice():
    W, H = 512, 1024
    im = Image.new("RGB", (W, H), (20, 20, 24))
    d = ImageDraw.Draw(im)
    rows = [
        ("Please stand on the right", BLUE, "stand"),
        ("Hold the handrail", BLUE, "hand"),
        ("Keep clear of the edges. Take extra care with children", BLUE, "child"),
        ("Dogs must be carried", BLUE, "dog"),
        ("No smoking", RED, "smoke"),
    ]
    rh = H // len(rows)
    for i, (text, col, kind) in enumerate(rows):
        y0 = i * rh
        d.rectangle([4, y0 + 4, W - 4, y0 + rh - 4], fill=col)
        # pictogram square on the left
        s = rh - 44
        d.rectangle([22, y0 + 22, 22 + s, y0 + 22 + s], outline=WHITE, width=5)
        cx, cy = 22 + s // 2, y0 + 22 + s // 2
        if kind == "stand":
            d.ellipse([cx - 14, cy - 44, cx + 14, cy - 16], fill=WHITE)
            d.rectangle([cx - 12, cy - 12, cx + 12, cy + 44], fill=WHITE)
            d.rectangle([cx + 26, cy - 40, cx + 34, cy + 40], fill=ORANGE)
        elif kind == "hand":
            d.ellipse([cx - 14, cy - 44, cx + 14, cy - 16], fill=WHITE)
            d.rectangle([cx - 12, cy - 12, cx + 12, cy + 44], fill=WHITE)
            d.line([cx + 12, cy - 6, cx + 46, cy - 30], fill=WHITE, width=9)
        elif kind == "child":
            d.ellipse([cx - 28, cy - 44, cx - 6, cy - 22], fill=WHITE)
            d.rectangle([cx - 26, cy - 18, cx - 8, cy + 44], fill=WHITE)
            d.ellipse([cx + 8, cy - 8, cx + 24, cy + 8], fill=WHITE)
            d.rectangle([cx + 8, cy + 10, cx + 24, cy + 44], fill=WHITE)
        elif kind == "dog":
            d.ellipse([cx - 30, cy - 10, cx + 26, cy + 22], fill=WHITE)
            d.ellipse([cx + 14, cy - 30, cx + 44, cy - 4], fill=WHITE)
            for lx in (-22, -6, 10, 22):
                d.rectangle([cx + lx, cy + 18, cx + lx + 6, cy + 42], fill=WHITE)
        else:
            d.ellipse([cx - 40, cy - 40, cx + 40, cy + 40], outline=WHITE, width=7)
            d.line([cx - 28, cy + 28, cx + 28, cy - 28], fill=WHITE, width=7)
            d.rectangle([cx - 30, cy - 4, cx + 18, cy + 6], fill=WHITE)
        # the wording, wrapped
        f = ImageFont.truetype(FB, 30)
        words = text.split()
        lines, cur = [], ""
        for w in words:
            t = (cur + " " + w).strip()
            if d.textlength(t, font=f) < W - s - 78:
                cur = t
            else:
                lines.append(cur)
                cur = w
        lines.append(cur)
        ty = y0 + rh // 2 - len(lines) * 17
        for ln in lines:
            d.text((s + 44, ty), ln, font=f, fill=WHITE)
            ty += 36
    im.save(os.path.join(OUT, "notice.png"))


if __name__ == "__main__":
    notice()
    print("wrote", OUT)
