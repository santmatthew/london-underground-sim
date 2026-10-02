#!/usr/bin/env python3
"""Textures of the open-air (surface) platforms: ballast, London stock and red brick, the scalloped valance of the platform canopies, a palisade fence, and the
two backdrop strips seen beyond the cutting (a belt of trees and a row of suburban house backs).
  python3 tools/gen_open_textures.py        then tools/fix_texture_imports.py + godot --headless --import"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_textures as gt          # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "textures", "char", "open")
os.makedirs(OUT, exist_ok=True)


def ballast(name="ballast", size=1024, seed=61):
    """crushed granite ballast: tileable grey-brown gravel"""
    rng = np.random.default_rng(seed)
    n1 = gt.tileable_noise((size, size), 6, rng, 3)
    n2 = gt.tileable_noise((size, size), 18, rng, 3)
    n3 = gt.tileable_noise((size, size), 40, rng, 2)
    stones = np.clip((n1 * 0.5 + n2 * 0.9 + n3 * 0.6), 0, None)
    stones = (stones - stones.min()) / (stones.max() - stones.min() + 1e-6)
    shade = 0.30 + 0.55 * stones
    tint = 0.5 + 0.5 * gt.tileable_noise((size, size), 90, rng, 3)
    col = np.stack([shade * (0.80 + 0.12 * tint), shade * (0.78 + 0.08 * tint), shade * (0.74 + 0.04 * tint)], -1)
    rough = np.full((size, size), 0.95, np.float32)
    ao = 0.45 + 0.55 * stones
    gt.save(name, col, rough, ao, stones * 3.0, 2.0, normal_strength=3.5)


def valance(name="valance", W=1024, H=160):
    """a 2.0 m x 0.31 m canopy valance: white board with a scalloped lower edge and a dark-blue keyline; RGBA"""
    S = 2
    im = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    scallops = 8
    sw = W * S / scallops
    base = int(H * S * 0.58)
    d.rectangle([0, 0, W * S, base], fill=(238, 238, 232, 255))
    for k in range(scallops):
        x0 = k * sw
        d.ellipse([x0, base - sw * 0.28, x0 + sw, base + sw * 0.28 + (H * S - base) * 0.2], fill=(238, 238, 232, 255))
    # keyline following the scallops
    for k in range(scallops):
        x0 = k * sw
        d.arc([x0 + 6, base - sw * 0.28 + 6, x0 + sw - 6, base + sw * 0.28 + (H * S - base) * 0.2 - 6], 0, 180, fill=(20, 40, 120, 255), width=5 * S)
    d.rectangle([0, 0, W * S, 8 * S], fill=(20, 40, 120, 255))
    im = im.resize((W, H), Image.LANCZOS)
    # alpha cut-out of the scallops
    a = np.array(im)[..., 3]
    a = np.where(a > 100, 255, 0).astype(np.uint8)
    arr = np.array(im)
    arr[..., 3] = a
    Image.fromarray(arr).save(os.path.join(OUT, name + ".png"), optimize=True)
    print("wrote", name)


def valance_saw(name="valance_saw", W=1024, H=200):
    """a 2.0 m x 0.39 m timber canopy valance: white boards with a deep saw-tooth lower edge (Boston Manor), a row of nail heads along the upper third; RGBA"""
    S = 2
    im = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    teeth = 13
    tw = W * S / teeth
    base = int(H * S * 0.62)
    paint = (240, 240, 235, 255)
    d.rectangle([0, 0, W * S, base], fill=paint)
    for k in range(teeth):
        x0 = k * tw
        d.polygon([(x0, base - 2), (x0 + tw, base - 2), (x0 + tw * 0.5, H * S - 4)], fill=paint)
    # board joints, a grey shadow line under the top edge, nail heads
    for k in range(1, 8):
        x = k * W * S / 8
        d.line([(x, 0), (x, base)], fill=(205, 205, 200, 255), width=3)
    d.rectangle([0, 0, W * S, 6 * S], fill=(196, 198, 196, 255))
    for k in range(teeth * 2):
        x = (k + 0.5) * tw * 0.5
        d.ellipse([x - 3 * S, base * 0.42 - 3 * S, x + 3 * S, base * 0.42 + 3 * S], fill=(120, 118, 112, 255))
    im = im.resize((W, H), Image.LANCZOS)
    a = np.array(im)
    a[..., 3] = np.where(a[..., 3] > 100, 255, 0)
    Image.fromarray(a).save(os.path.join(OUT, name + ".png"), optimize=True)
    print("wrote", name)


def bridge_panel(name="bridge_panel", W=512, H=640, seed=17):
    """2.0 m x 2.5 m of the side of a white-painted concrete footbridge girder (Kew Gardens): a row of blind panels with cusped heads between pilasters,
    a plain band below with the projecting cornice at the bottom; weathered, with rain streaks"""
    rnd = random.Random(seed)
    S = 3
    w, h = W * S, H * S
    im = Image.new("RGB", (w, h), (228, 228, 222))
    d = ImageDraw.Draw(im)
    ppm = W / 2.0 * S                      # pixels per metre
    # panel: 1.4 m wide, from 0.70 m to 2.15 m above the bottom, head cusped (an ogee)
    px0, px1 = int(0.30 * ppm), int(1.70 * ppm)
    y_bot = h - int(0.70 * ppm)
    y_top = h - int(2.15 * ppm)
    head = int(0.30 * ppm)
    mid = (px0 + px1) // 2
    half = (px1 - px0) / 2
    pts = [(px0, y_bot), (px0, y_top + head)]
    for k in range(1, 24):                       # the head: a round shoulder each side meeting in a small point at the centre
        u = k / 24.0
        x = px0 + half * u
        y = y_top + head * (1.0 - math.sin(u * math.pi / 2.0) ** 1.25) + (0.05 * ppm) * (1.0 - u) ** 6
        pts.append((x, y))
    pts.append((mid, y_top))
    for k in range(23, 0, -1):
        u = k / 24.0
        x = px1 - half * u
        y = y_top + head * (1.0 - math.sin(u * math.pi / 2.0) ** 1.25) + (0.05 * ppm) * (1.0 - u) ** 6
        pts.append((x, y))
    pts += [(px1, y_top + head), (px1, y_bot)]
    # the recess: darker, with a lit lower/left edge and a shadowed upper/right edge
    d.polygon(pts, fill=(214, 214, 208))
    d.line(pts + [pts[0]], fill=(176, 176, 170), width=int(0.035 * ppm), joint="curve")
    off = int(0.02 * ppm)
    d.line([(x + off, y + off) for x, y in pts[1:len(pts) // 2 + 1]], fill=(160, 160, 154), width=int(0.02 * ppm))
    # the cornice: a projecting moulded band at the bottom, shadow under it
    cy = h - int(0.30 * ppm)
    d.rectangle([0, cy, w, h], fill=(236, 236, 230))
    d.rectangle([0, cy, w, cy + int(0.03 * ppm)], fill=(150, 150, 146))
    d.rectangle([0, h - int(0.04 * ppm), w, h], fill=(172, 172, 168))
    im = im.resize((W, H), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32)
    # weathering: soft mottling and vertical rain streaks, darker at the foot of each panel joint
    rng = np.random.default_rng(seed)
    mott = gt.tileable_noise((H, W), 9, rng, 3)
    mott = (mott - mott.min()) / (mott.max() - mott.min() + 1e-6)
    streak = np.zeros((H, W), np.float32)
    for _ in range(26):
        x = rnd.randrange(W)
        ln = rnd.randint(60, 300)
        y0 = rnd.randrange(0, H - 40)
        streak[y0:y0 + ln, max(0, x - 1):x + 2] += rnd.uniform(0.03, 0.09)
    streak = np.clip(streak, 0, 0.14)
    shade = 1.0 - 0.07 * mott - streak
    a = a * shade[..., None]
    a[..., 2] *= 0.985
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name + ".png"), optimize=True)
    print("wrote", name)


def palisade(name="fence", W=512, H=512):
    """steel palisade fence, one metre of it: 12 pointed pickets between two rails; RGBA"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    n = 12
    pw = W / n
    for i in range(n):
        x = i * pw + pw * 0.5
        d.polygon([(x - pw * 0.16, H * 0.97), (x - pw * 0.16, H * 0.14), (x, 0), (x + pw * 0.16, H * 0.14), (x + pw * 0.16, H * 0.97)], fill=(26, 40, 34, 255))
    for y in (H * 0.30, H * 0.80):
        d.rectangle([0, y, W, y + H * 0.045], fill=(20, 30, 26, 255))
    im.save(os.path.join(OUT, name + ".png"), optimize=True)
    print("wrote", name)


def _wrap_ellipse(d, W, cx, cy, rx, ry, fill):
    for off in (-W, 0, W):
        d.ellipse([cx - rx + off, cy - ry, cx + rx + off, cy + ry], fill=fill)


def trees(name="trees", W=4096, H=1536, seed=71):
    """a belt of deciduous trees, seamless in x: each crown is built of hundreds of small leaf clumps, shaded light from above and dark inside, with a
    speckle of leaf highlights; RGBA, base at the bottom edge (100 px per metre when 40 m wide)"""
    rnd = random.Random(seed)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    greens = [(46, 76, 40), (58, 92, 46), (40, 66, 36), (72, 104, 52), (52, 84, 44), (88, 112, 58), (36, 60, 34)]

    def clump(cx, cy, rad, base, lift):
        col = tuple(max(0, min(255, int(c * 0.78 + lift))) for c in base)
        for off in (-W, 0, W):
            d.ellipse([cx - rad + off, cy - rad * 0.85, cx + rad + off, cy + rad * 0.85], fill=col + (255,))

    x = 0
    while x < W:
        tw = rnd.randint(300, 640)
        th = rnd.randint(620, 1250)
        cx = x + tw / 2
        # dark core first, then lit clumps toward the top and outer edge
        for k in range(520):
            ang = rnd.uniform(0, math.tau)
            rr = rnd.uniform(0, 1) ** 0.55
            ccx = cx + math.cos(ang) * tw * 0.5 * rr
            ccy = H - th * 0.60 + math.sin(ang) * th * 0.36 * rr
            rad = rnd.uniform(12, 34)
            base = rnd.choice(greens)
            up = 1.0 - (ccy - (H - th)) / th
            clump(ccx, ccy, rad, base, 38 * up * rr + (-10 if rr < 0.4 else 8))
        # leaf glints
        for k in range(160):
            ang = rnd.uniform(0, math.tau)
            rr = rnd.uniform(0.3, 1.0)
            gx = cx + math.cos(ang) * tw * 0.5 * rr
            gy = H - th * 0.60 + math.sin(ang) * th * 0.36 * rr
            r = rnd.uniform(3, 7)
            for off in (-W, 0, W):
                d.ellipse([gx - r + off, gy - r, gx + r + off, gy + r], fill=(122, 148, 76, 255))
        x += int(tw * rnd.uniform(0.5, 0.8))
    # undergrowth: dense shrubs hide the trunks and give the belt a base
    for k in range(700):
        bx = rnd.uniform(0, W)
        by = H - rnd.uniform(0, 300)
        br = rnd.uniform(24, 70)
        col = tuple(int(c * rnd.uniform(0.62, 0.9)) for c in rnd.choice(greens))
        for off in (-W, 0, W):
            d.ellipse([bx - br + off, by - br * 0.8, bx + br + off, by + br * 0.8], fill=col + (255,))
    im = im.filter(ImageFilter.GaussianBlur(1.0))
    a = np.array(im)
    a[..., 3] = np.where(a[..., 3] > 110, 255, 0)
    Image.fromarray(a).save(os.path.join(OUT, name + ".png"), optimize=True)
    print("wrote", name)


def houses(name="houses", W=2048, H=512, seed=81):
    """the backs of a street of terraced houses, seamless in x; RGBA, base at the bottom edge"""
    rnd = random.Random(seed)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x = 0
    bricks = [(146, 84, 64), (160, 96, 70), (134, 78, 62), (172, 110, 80), (120, 92, 72)]
    roofs = [(70, 66, 72), (88, 62, 56), (60, 60, 66)]
    while x < W:
        bw = rnd.choice([150, 170, 190])
        bh = rnd.randint(250, 340)
        col = rnd.choice(bricks)
        d.rectangle([x, H - bh, x + bw, H], fill=col + (255,))
        # slate roof (hip)
        rc = rnd.choice(roofs)
        d.polygon([(x - 6, H - bh), (x + bw + 6, H - bh), (x + bw - 26, H - bh - 74), (x + 26, H - bh - 74)], fill=rc + (255,))
        # chimney
        cx = x + rnd.choice([bw * 0.2, bw * 0.75])
        d.rectangle([cx, H - bh - 112, cx + 24, H - bh - 60], fill=tuple(int(c * 0.85) for c in col) + (255,))
        d.rectangle([cx - 3, H - bh - 118, cx + 27, H - bh - 108], fill=(110, 100, 94, 255))
        # windows: two rows
        for row in range(2):
            wy = H - bh + 38 + row * 112
            for wx in (x + bw * 0.22, x + bw * 0.62):
                d.rectangle([wx, wy, wx + 34, wy + 62], fill=(226, 222, 212, 255))
                d.rectangle([wx + 4, wy + 4, wx + 30, wy + 58], fill=(52, 58, 72, 255))
                d.line([(wx + 17, wy + 4), (wx + 17, wy + 58)], fill=(226, 222, 212, 255), width=3)
        # garden wall and a fence line
        d.rectangle([x, H - 44, x + bw, H], fill=tuple(int(c * 0.9) for c in col) + (255,))
        x += bw + rnd.choice([0, 0, 8])
    im.save(os.path.join(OUT, name + ".png"), optimize=True)
    print("wrote", name)


def bricks():
    gt.brick_wall("brick_stock", (0.58, 0.52, 0.38), seed=91)
    gt.brick_wall("brick_red", (0.58, 0.26, 0.19), seed=92)
    gt.brick_wall("brick_blue", (0.30, 0.31, 0.36), seed=93)
    # the three PBR sets go to gen/ like the other surface textures
    print("wrote bricks")


if __name__ == "__main__":
    what = sys.argv[1:] or ["ballast", "valance", "valance_saw", "bridge_panel", "fence", "trees", "houses", "bricks"]
    for w in what:
        {"ballast": ballast, "valance": valance, "valance_saw": valance_saw, "bridge_panel": bridge_panel, "fence": palisade, "trees": trees, "houses": houses, "bricks": bricks}[w]()
