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


def suburban(mode):
    """a suburban road: semi-detached houses behind front gardens and hedges, trees, a parked car, a red pillar box; same palette per time of day as scene()"""
    rnd = random.Random(11)
    im = Image.new("RGB", (W * S, H * S))
    d = ImageDraw.Draw(im)
    if mode == "day":
        sky_t, sky_b, brick, roof, window, win_lit, road, kerb, grass = (140, 184, 232), (224, 234, 244), [(168, 100, 72), (186, 120, 84), (154, 92, 68), (196, 168, 120)], (92, 70, 66), (58, 66, 84), (210, 222, 232), (92, 94, 98), (170, 170, 166), (92, 140, 70)
    elif mode == "dusk":
        sky_t, sky_b, brick, roof, window, win_lit, road, kerb, grass = (70, 84, 140), (236, 156, 108), [(112, 66, 54), (126, 78, 60), (102, 62, 52), (130, 112, 84)], (60, 50, 54), (40, 44, 62), (255, 214, 130), (58, 58, 66), (118, 116, 118), (50, 74, 52)
    else:
        sky_t, sky_b, brick, roof, window, win_lit, road, kerb, grass = (8, 12, 30), (28, 34, 60), [(56, 36, 34), (62, 40, 36), (50, 32, 32), (60, 54, 44)], (30, 28, 34), (18, 20, 32), (255, 206, 120), (28, 28, 34), (68, 68, 74), (22, 34, 26)
    for y in range(H * S):
        d.line([(0, y), (W * S, y)], fill=lerp(sky_t, sky_b, min(1.0, y / (H * S * 0.55))))
    horizon = int(H * S * 0.66)
    # a belt of trees behind the roofs
    for k in range(34):
        tx = rnd.uniform(0, W * S)
        th = rnd.uniform(260, 420) * S
        c = lerp(grass, (30, 60, 34), rnd.random() * 0.5)
        d.ellipse([tx - 130 * S, horizon - 200 * S - th * 0.3, tx + 130 * S, horizon - 60 * S + th * 0.2], fill=c)
    x = -20 * S
    while x < W * S:
        hw = rnd.choice([360, 400, 440]) * S           # a semi: two bays under one roof
        hh = rnd.randint(250, 300) * S
        col = rnd.choice(brick)
        top = horizon - hh
        d.rectangle([x, top, x + hw, horizon - 60 * S], fill=col)
        d.polygon([(x - 14 * S, top), (x + hw + 14 * S, top), (x + hw * 0.5 + 60 * S, top - 150 * S), (x + hw * 0.5 - 60 * S, top - 150 * S)], fill=roof)
        # tudor-style gable on the left bay
        d.polygon([(x + 10 * S, top), (x + hw * 0.5 - 10 * S, top), (x + hw * 0.25, top - 130 * S)], fill=(226, 218, 200) if mode == "day" else lerp(col, (200, 190, 170), 0.35))
        for bay in range(2):
            bx = x + bay * hw * 0.5
            for wx in (bx + hw * 0.08, bx + hw * 0.30):
                for wy in (top + 40 * S, top + 140 * S):
                    lit = (mode != "day") and rnd.random() < 0.5
                    d.rectangle([wx, wy, wx + 62 * S, wy + 70 * S], fill=(230, 226, 214))
                    d.rectangle([wx + 4 * S, wy + 4 * S, wx + 58 * S, wy + 66 * S], fill=win_lit if lit else window)
                    d.line([(wx + 31 * S, wy), (wx + 31 * S, wy + 70 * S)], fill=(230, 226, 214), width=3 * S)
        d.rectangle([x + hw * 0.44, top + 150 * S, x + hw * 0.56, horizon - 60 * S], fill=lerp(col, (30, 40, 90), 0.5))     # door
        # front garden: hedge and path
        d.rectangle([x, horizon - 60 * S, x + hw, horizon], fill=lerp(grass, (20, 70, 30), 0.3))
        d.rounded_rectangle([x + 6 * S, horizon - 92 * S, x + hw - 6 * S, horizon - 44 * S], radius=18 * S, fill=lerp(grass, (24, 70, 30), 0.6))
        x += hw + rnd.choice([6, 14, 22]) * S
    # pavement, kerb, road
    d.rectangle([0, horizon, W * S, int(H * S * 0.72)], fill=lerp(kerb, (200, 198, 192), 0.2))
    d.rectangle([0, int(H * S * 0.72), W * S, int(H * S * 0.735)], fill=lerp(kerb, (255, 255, 255), 0.25))
    d.rectangle([0, int(H * S * 0.735), W * S, H * S], fill=road)
    d.rectangle([0, int(H * S * 0.84), W * S, int(H * S * 0.85)], fill=(214, 214, 206))
    # a parked car, hatchback silhouette
    cx0 = 900 * S
    cy1 = int(H * S * 0.78)
    body = (60, 90, 140) if mode == "day" else (36, 50, 76)
    d.rounded_rectangle([cx0, cy1 - 120 * S, cx0 + 420 * S, cy1], radius=26 * S, fill=body)
    d.polygon([(cx0 + 90 * S, cy1 - 120 * S), (cx0 + 150 * S, cy1 - 210 * S), (cx0 + 300 * S, cy1 - 210 * S), (cx0 + 360 * S, cy1 - 120 * S)], fill=body)
    d.polygon([(cx0 + 110 * S, cy1 - 124 * S), (cx0 + 160 * S, cy1 - 196 * S), (cx0 + 290 * S, cy1 - 196 * S), (cx0 + 340 * S, cy1 - 124 * S)], fill=(150, 176, 196) if mode == "day" else (30, 38, 54))
    for wx in (cx0 + 90 * S, cx0 + 330 * S):
        d.ellipse([wx - 40 * S, cy1 - 40 * S, wx + 40 * S, cy1 + 40 * S], fill=(18, 18, 20))
    # pillar box and lamp posts
    d.rounded_rectangle([200 * S, int(H * S * 0.64), 250 * S, int(H * S * 0.73)], radius=10 * S, fill=(180, 24, 30))
    for lx in (120 * S, 1380 * S):
        d.rectangle([lx - 5 * S, int(H * S * 0.34), lx + 5 * S, int(H * S * 0.72)], fill=(60, 64, 62))
        d.ellipse([lx - 22 * S, int(H * S * 0.32), lx + 22 * S, int(H * S * 0.36)], fill=(250, 230, 160) if mode != "day" else (200, 200, 190))
    im = im.resize((W, H), Image.LANCZOS)
    hz = Image.new("RGB", (W, H), (236, 240, 244) if mode == "day" else (90, 90, 110))
    mask = Image.new("L", (W, H))
    md = ImageDraw.Draw(mask)
    for y in range(H):
        t = max(0.0, 1.0 - abs(y - H * 0.55) / (H * 0.35))
        md.line([(0, y), (W, y)], fill=int(255 * 0.30 * t))
    out = Image.composite(hz, im, mask).filter(ImageFilter.GaussianBlur(2.2))
    grey = out.convert("L").convert("RGB")
    return Image.blend(out, grey, 0.22)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for mode in ("day", "dusk", "night"):
        scene(mode).save(os.path.join(OUT, "street_%s.png" % mode), optimize=True)
        print("wrote street_%s" % mode)
        suburban(mode).save(os.path.join(OUT, "street_sub_%s.png" % mode), optimize=True)
        print("wrote street_sub_%s" % mode)
