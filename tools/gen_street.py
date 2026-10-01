#!/usr/bin/env python3
"""The street seen through the glass doors at the end of each station's way-out passage: a generic London street (a brick terrace across a road, a
bus, a lamp post), three times of day. 3.0 x 2.9 m panel at 512 px/m. Output: assets/textures/char/street_{day,dusk,night}.png
  python3 tools/gen_street.py     then tools/fix_texture_imports.py + godot --import"""
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "textures", "char")
W, H = 1536, 1485
S = 2


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def scene(mode):
    rnd = random.Random(7)
    im = Image.new("RGB", (W * S, H * S))
    d = ImageDraw.Draw(im)
    if mode == "day":
        sky_t, sky_b, brick, window, win_lit, road, kerb, haze = (150, 190, 232), (226, 236, 244), [(150, 80, 62), (170, 94, 70), (138, 72, 58)], (60, 70, 86), (220, 228, 236), (96, 98, 102), (170, 170, 168), 0.32
    elif mode == "dusk":
        sky_t, sky_b, brick, window, win_lit, road, kerb, haze = (70, 84, 140), (240, 160, 110), [(104, 58, 50), (118, 68, 56), (96, 54, 48)], (40, 44, 62), (255, 214, 130), (60, 60, 68), (120, 118, 120), 0.10
    else:
        sky_t, sky_b, brick, window, win_lit, road, kerb, haze = (8, 12, 30), (30, 36, 62), [(54, 34, 34), (62, 38, 36), (48, 30, 32)], (20, 22, 34), (255, 206, 120), (28, 28, 34), (70, 70, 76), 0.05
    for y in range(H * S):
        d.line([(0, y), (W * S, y)], fill=lerp(sky_t, sky_b, min(1.0, y / (H * S * 0.55))))
    horizon = int(H * S * 0.64)
    # the terrace across the road
    x = -40 * S
    while x < W * S:
        bw = rnd.randint(190, 300) * S
        bh = rnd.randint(520, 760) * S
        top = horizon - bh
        col = rnd.choice(brick)
        d.rectangle([x, top, x + bw, horizon], fill=col)
        d.rectangle([x, top, x + bw, top + 16 * S], fill=lerp(col, (30, 30, 30), 0.4))                 # cornice
        d.polygon([(x, top), (x + bw, top), (x + bw - 18 * S, top - 40 * S), (x + 18 * S, top - 40 * S)], fill=lerp(col, (40, 40, 44), 0.6))   # mansard
        for cx in (x + bw * 0.25, x + bw * 0.7):
            d.rectangle([cx, top - 80 * S, cx + 26 * S, top - 36 * S], fill=lerp(col, (30, 30, 30), 0.3))                              # chimney
        rows = max(3, bh // (130 * S))
        cols = max(2, bw // (80 * S))
        for r in range(rows - 1):
            for c in range(cols):
                wx = x + (c + 0.5) * bw / cols - 16 * S
                wy = top + 50 * S + r * 120 * S
                lit = (mode != "day") and rnd.random() < 0.45
                d.rectangle([wx - 3 * S, wy - 3 * S, wx + 35 * S, wy + 74 * S], fill=(224, 220, 210) if mode == "day" else lerp(col, (200, 190, 170), 0.25))
                d.rectangle([wx, wy, wx + 32 * S, wy + 70 * S], fill=win_lit if lit else window)
                d.line([(wx + 16 * S, wy), (wx + 16 * S, wy + 70 * S)], fill=(230, 226, 216), width=2 * S)
                d.line([(wx, wy + 34 * S), (wx + 32 * S, wy + 34 * S)], fill=(230, 226, 216), width=2 * S)
        # shopfront at street level
        sh = 92 * S
        d.rectangle([x + 8 * S, horizon - sh, x + bw - 8 * S, horizon], fill=lerp((40, 44, 52), col, 0.15))
        d.rectangle([x + 20 * S, horizon - sh + 22 * S, x + bw - 20 * S, horizon - 6 * S], fill=win_lit if (mode != "day" or rnd.random() < 0.5) else (150, 170, 182))
        d.rectangle([x + 8 * S, horizon - sh, x + bw - 8 * S, horizon - sh + 18 * S], fill=rnd.choice([(30, 60, 96), (96, 30, 36), (24, 70, 50), (40, 40, 44)]))
        x += bw
    # pavement, kerb, road
    d.rectangle([0, horizon, W * S, int(H * S * 0.72)], fill=lerp(kerb, (210, 208, 200), 0.3 if mode == "day" else 0.0))
    d.rectangle([0, int(H * S * 0.72), W * S, int(H * S * 0.735)], fill=lerp(kerb, (255, 255, 255), 0.25))
    d.rectangle([0, int(H * S * 0.735), W * S, H * S], fill=road)
    for k in range(7):
        xx = (k * 260 + 40) * S
        d.rectangle([xx, int(H * S * 0.86), xx + 120 * S, int(H * S * 0.872)], fill=(220, 220, 214))
    d.rectangle([0, int(H * S * 0.745), W * S, int(H * S * 0.752)], fill=(214, 186, 40))
    d.rectangle([0, int(H * S * 0.757), W * S, int(H * S * 0.764)], fill=(214, 186, 40))
    # a red double-decker, most of the way across
    bx0, bx1 = 420 * S, 1180 * S
    by1 = int(H * S * 0.84)
    by0 = by1 - 330 * S
    d.rounded_rectangle([bx0, by0, bx1, by1], radius=18 * S, fill=(196, 28, 34) if mode != "night" else (130, 20, 26))
    for r, wy in enumerate((by0 + 40 * S, by0 + 190 * S)):
        for k in range(8):
            wx = bx0 + 34 * S + k * 92 * S
            d.rectangle([wx, wy, wx + 74 * S, wy + 90 * S], fill=(win_lit if mode != "day" else (170, 190, 206)))
    d.rectangle([bx0, by0 + 150 * S, bx1, by0 + 168 * S], fill=(230, 220, 210))
    for wxc in (bx0 + 130 * S, bx1 - 150 * S):
        d.ellipse([wxc - 52 * S, by1 - 50 * S, wxc + 52 * S, by1 + 54 * S], fill=(20, 20, 22))
    # lamp posts
    for lx in (120 * S, 1380 * S):
        d.rectangle([lx - 5 * S, int(H * S * 0.32), lx + 5 * S, int(H * S * 0.72)], fill=(40, 60, 50))
        d.ellipse([lx - 24 * S, int(H * S * 0.30), lx + 24 * S, int(H * S * 0.34)], fill=(250, 230, 160) if mode != "day" else (200, 200, 190))
    im = im.resize((W, H), Image.LANCZOS)
    if mode != "day":
        glow = Image.new("RGB", (W, H))
        gd = ImageDraw.Draw(glow)
        for lx in (120, 1380):
            gd.ellipse([lx - 90, int(H * 0.32) - 70, lx + 90, int(H * 0.32) + 110], fill=(255, 220, 140))
        glow = glow.filter(ImageFilter.GaussianBlur(40))
        im = Image.blend(im, Image.composite(glow, im, glow.convert("L")), 0.55)
    # atmosphere: a touch of haze toward the horizon
    hz = Image.new("RGB", (W, H), (236, 240, 244) if mode == "day" else (90, 90, 110))
    mask = Image.new("L", (W, H))
    md = ImageDraw.Draw(mask)
    for y in range(H):
        t = max(0.0, 1.0 - abs(y - H * 0.55) / (H * 0.35))
        md.line([(0, y), (W, y)], fill=int(255 * haze * t))
    out = Image.composite(hz, im, mask).filter(ImageFilter.GaussianBlur(2.2))      # seen through glass from a dim passage: soft, washed out
    grey = out.convert("L").convert("RGB")
    return Image.blend(out, grey, 0.22)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for mode in ("day", "dusk", "night"):
        scene(mode).save(os.path.join(OUT, "street_%s.png" % mode), optimize=True)
        print("wrote street_%s" % mode)
