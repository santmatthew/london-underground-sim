#!/usr/bin/env python3
"""Generates the game's FICTIONAL advertising posters -> assets/textures/props/posters/poster_00..11.png
(8 portrait 1024x1536, 4 landscape 2048x1024) + poster_manifest.json + small placeholder textures for the poster frames.
All brands, logos, slogans and figures are invented. run: build/venv/bin/python tools/blender/props/posters.py [indices]"""
import os, sys, math, random, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gfx import *

OUT = os.path.join(ROOT, 'assets', 'textures', 'props', 'posters')
PH_OUT = os.path.join(ROOT, 'assets', 'textures', 'props', 'decals')
WHITE = (255, 255, 255, 255)
BLACK = (10, 10, 12, 255)


def C(r, g, b, a=255):
    return (r, g, b, a)


def lerpc(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def gradient(c, stops, angle=90.0):
    """fill canvas with a multi-stop linear gradient. stops=[(t,(r,g,b)),...]; angle in degrees (90 = top->bottom)"""
    W, H = c.im.size
    a = math.radians(angle)
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    d = (xs / W - 0.5) * math.cos(a) * (W / max(W, H)) + (ys / H - 0.5) * math.sin(a) * (H / max(W, H))
    d = (d - d.min()) / (d.max() - d.min())
    out = np.zeros((H, W, 3), np.float32)
    ts = [s[0] for s in stops]; cols = np.array([s[1][:3] for s in stops], np.float32)
    for ch in range(3):
        out[..., ch] = np.interp(d, ts, cols[:, ch])
    im = Image.fromarray(out.astype(np.uint8), 'RGB').convert('RGBA')
    c.blit(im, 0, 0)


def glow(c, cx, cy, r, color, alpha=180, blur=None):
    lay, dr = c.layer()
    s = c.ss
    dr.ellipse([(cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s], fill=color[:3] + (alpha,))
    c.composite(lay, blur=blur if blur is not None else r * 0.5)


def spaced(c, x, y, txt, kind, size, fill, spacing=0.0, anchor='m'):
    """letter-spaced text centred/left/right on x. spacing in px."""
    f = font(kind, size * c.ss)
    widths = [f.getlength(ch) / c.ss for ch in txt]
    total = sum(widths) + spacing * (len(txt) - 1)
    if anchor == 'm':
        x0 = x - total / 2
    elif anchor == 'l':
        x0 = x
    else:
        x0 = x - total
    cx = x0
    for ch, w in zip(txt, widths):
        c.text(cx, y, ch, kind, size, fill, anchor='ls')
        cx += w + spacing
    return total


def para(c, x, y, txt, kind, size, fill, width, lh=1.25, anchor='l', align='left'):
    """word-wrapped paragraph starting at (x,y) top-left; returns bottom y"""
    words = txt.split(' ')
    lines = []; cur = ''
    for w in words:
        if c.text_w((cur + ' ' + w).strip(), kind, size) > width and cur:
            lines.append(cur); cur = w
        else:
            cur = (cur + ' ' + w).strip()
    lines.append(cur)
    for i, l in enumerate(lines):
        yy = y + i * size * lh
        if align == 'center':
            c.text(x + width / 2, yy, l, kind, size, fill, anchor='ma')
        elif align == 'right':
            c.text(x + width, yy, l, kind, size, fill, anchor='ra')
        else:
            c.text(x, yy, l, kind, size, fill, anchor='la')
    return y + len(lines) * size * lh


def pill(c, x0, y0, x1, y1, fill, txt, kind, size, tcol):
    c.rect(x0, y0, x1, y1, fill=fill, r=(y1 - y0) / 2)
    c.text((x0 + x1) / 2, (y0 + y1) / 2 + size * 0.04, txt, kind, size, tcol, anchor='mm')


def paper(c, amount=6):
    """faint print grain so posters don't look vector-flat"""
    W, H = c.im.size
    rng = np.random.RandomState(3)
    n = rng.normal(0, amount, (H, W)).astype(np.float32)
    arr = np.asarray(c.im.convert('RGB'), np.float32)
    arr += n[..., None]
    c.im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGB')
    c._redraw()


def fineprint(c, x, y, txt, col, size=15, anchor='la'):
    c.text(x, y, txt, 'reg', size, col, anchor=anchor)


# ================================================================================================ portrait 1024x1536
def p0_streamly(c):
    W, H = 1024, 1536
    gradient(c, [(0, (28, 8, 70)), (0.55, (92, 22, 130)), (1, (200, 40, 110))], 80)
    glow(c, 780, 420, 380, (255, 120, 200), 120)
    glow(c, 200, 1100, 320, (80, 60, 255), 100)
    c.rect(64, 70, 148, 154, fill=(255, 70, 140, 255), r=22)
    c.poly([(93, 96), (93, 128), (122, 112)], fill=WHITE)
    c.text(166, 130, 'streamly', 'bold', 84, WHITE, anchor='ls')
    S = c.ss
    tw, th = 290, 400
    cols = [((255, 120, 60), (255, 40, 100)), ((40, 200, 255), (60, 80, 255)), ((255, 210, 60), (255, 120, 40)),
            ((120, 255, 180), (20, 160, 140)), ((255, 90, 200), (120, 40, 200)), ((250, 250, 255), (140, 160, 230))]
    titles = ['SILENT TIDE', 'MOONRUNNERS', 'THE LONG WINTER', 'HOUSE OF EMBERS', 'NEON HARBOUR', 'MY FAKE WEDDING']
    for i in range(6):
        r, cc = divmod(i, 3)
        a, b = cols[i]
        g = np.linspace(0, 1, th * S)[:, None, None]
        arr = (np.array(a, np.float32)[None, None, :] * (1 - g) + np.array(b, np.float32)[None, None, :] * g)
        arr = np.repeat(arr, tw * S, axis=1).astype(np.uint8)
        tile = Image.fromarray(arr, 'RGB').convert('RGBA')
        td = ImageDraw.Draw(tile, 'RGBA')
        rnd = random.Random(i)
        # key art: sun/moon disc + layered ridge silhouettes
        cx0 = tw * S * rnd.uniform(0.3, 0.7); cy0 = th * S * rnd.uniform(0.22, 0.4)
        td.ellipse([cx0 - 70 * S, cy0 - 70 * S, cx0 + 70 * S, cy0 + 70 * S], fill=(255, 255, 255, 90))
        for k in range(3):
            base = th * S * (0.55 + k * 0.1)
            pts = [(x, base + math.sin(x / (40.0 * S) + i + k) * 18 * S * (1 + k * 0.4)) for x in range(0, tw * S + 20 * S, 20 * S)] + [(tw * S, th * S), (0, th * S)]
            td.polygon(pts, fill=(10, 4, 30, 70 + k * 40))
        td.rectangle([0, th * S * 0.78, tw * S, th * S], fill=(8, 2, 24, 150))
        td.text((18 * S, (th - 62) * S), titles[i], font=font('cond', 34 * S), fill=(255, 255, 255, 255))
        td.text((18 * S, (th - 30) * S), 'NEW SERIES', font=font('reg', 16 * S), fill=(255, 255, 255, 200))
        m = Image.new('L', tile.size, 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, tile.size[0] - 1, tile.size[1] - 1], radius=30 * S, fill=255)
        tile.putalpha(m)
        # soft shadow
        sh = Image.new('RGBA', (tile.size[0] + 80 * S, tile.size[1] + 80 * S), (0, 0, 0, 0))
        sh.paste((0, 0, 0, 120), (40 * S, 48 * S, 40 * S + tile.size[0], 48 * S + tile.size[1]), m)
        sh = sh.filter(ImageFilter.GaussianBlur(16 * S))
        ang = (-5 if (i % 2 == 0) else 4)
        tile = tile.rotate(ang, resample=Image.BICUBIC, expand=True)
        sh = sh.rotate(ang, resample=Image.BICUBIC, expand=True)
        x0 = (56 + cc * 316 + (r % 2) * 26) * S; y0 = (210 + r * 430) * S
        c.blit(sh, x0 - 40 * S, y0 - 32 * S)
        c.blit(tile, x0, y0)
    lay2, d2 = c.layer()
    d2.rectangle([0, 1080 * S, W * S, H * S], fill=(20, 4, 50, 210))
    c.composite(lay2, blur=50)
    c.text(64, 1210, 'Everything', 'bold', 130, WHITE, anchor='ls')
    c.text(64, 1330, 'worth watching.', 'bold', 130, WHITE, anchor='ls')
    pill(c, 64, 1380, 520, 1462, (255, 70, 140, 255), 'First month free', 'bold', 40, WHITE)
    fineprint(c, 64, 1490, 'New customers only. 18+. Then £7.99 a month. Cancel any time. Terms apply.', (230, 200, 240, 255), 18)


def p1_nova(c):
    W, H = 1024, 1536
    gradient(c, [(0, (248, 249, 252)), (1, (222, 228, 240))], 90)
    glow(c, 700, 860, 420, (150, 130, 255), 140)
    glow(c, 860, 1120, 280, (90, 200, 255), 110)
    c.text(72, 150, 'NOVA', 'head', 60, (24, 26, 40, 255), anchor='ls')
    c.text(260, 150, 'X', 'head', 60, (110, 90, 255, 255), anchor='ls')
    c.text(72, 330, 'Two days.', 'bold', 118, (20, 22, 36, 255), anchor='ls')
    c.text(72, 450, 'One charge.', 'bold', 118, (110, 90, 255, 255), anchor='ls')
    px, py, pw, ph = 500, 540, 430, 820
    lay, d = c.layer(); s = c.ss
    d.rounded_rectangle([(px + 24) * s, (py + 40) * s, (px + pw + 24) * s, (py + ph + 40) * s], radius=66 * s, fill=(0, 0, 0, 120))
    c.composite(lay, blur=26)
    c.rect(px, py, px + pw, py + ph, fill=(30, 32, 40, 255), r=66)
    c.rect(px + 7, py + 7, px + pw - 7, py + ph - 7, fill=(74, 78, 92, 255), r=60)
    c.rect(px + 16, py + 16, px + pw - 16, py + ph - 16, fill=(8, 8, 12, 255), r=52)
    sx0, sy0, sx1, sy1 = px + 24, py + 24, px + pw - 24, py + ph - 24
    sw, sh = int((sx1 - sx0) * s), int((sy1 - sy0) * s)
    ys, xs = np.mgrid[0:sh, 0:sw].astype(np.float32)
    arr = np.zeros((sh, sw, 3), np.float32)
    base = np.array([(30, 20, 120), (150, 60, 220), (255, 130, 160)], np.float32)
    t = ys / sh
    arr[...] = base[0] * (1 - t[..., None]) ** 2 + base[1] * (2 * t * (1 - t))[..., None] + base[2] * (t ** 2)[..., None]
    for k in range(5):
        wv = (0.45 + k * 0.1) * sh + np.sin(xs / sw * 6 + k) * sh * 0.04
        arr = np.where((ys > wv)[..., None], arr * 0.86 + np.array([20, 10, 40], np.float32) * (k + 1) * 0.15, arr)
    scr = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')
    m = Image.new('L', scr.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, sw - 1, sh - 1], radius=44 * s, fill=255)
    scr.putalpha(m)
    c.blit(scr, sx0 * s, sy0 * s)
    c.text((sx0 + sx1) / 2, sy0 + 190, '10:08', 'bold', 124, WHITE, anchor='mm')
    c.text((sx0 + sx1) / 2, sy0 + 275, 'Tuesday 29 September', 'reg', 28, (255, 255, 255, 220), anchor='mm')
    c.rect((sx0 + sx1) / 2 - 38, py + 34, (sx0 + sx1) / 2 + 38, py + 56, fill=(0, 0, 0, 255), r=11)
    c.rect((sx0 + sx1) / 2 - 90, sy1 - 30, (sx0 + sx1) / 2 + 90, sy1 - 22, fill=(255, 255, 255, 220), r=4)
    c.text(72, 1130, 'From', 'reg', 40, (70, 74, 96, 255), anchor='ls')
    c.text(72, 1220, '£599', 'bold', 110, (20, 22, 36, 255), anchor='ls')
    para(c, 72, 1250, 'Or £24 a month. Buy at novamobile.example', 'reg', 30, (70, 74, 96, 255), 360, 1.3)
    fineprint(c, 72, 1490, 'Battery life based on typical use. Screen images simulated. Available on selected plans.', (110, 114, 136, 255), 18)


def p2_sunhaven(c):
    W, H = 1024, 1536
    gradient(c, [(0, (32, 60, 150)), (0.35, (200, 90, 140)), (0.62, (255, 170, 70)), (1, (255, 214, 120))], 90)
    glow(c, 512, 900, 380, (255, 240, 180), 200)
    c.circle(512, 940, 190, fill=(255, 246, 200, 255))
    # sea
    for i in range(24):
        y = 960 + i * 24
        t = i / 24
        col = lerpc((255, 190, 100), (20, 100, 170), t ** 0.7)
        c.rect(0, y, W, y + 26, fill=col + (255,))
    # sun reflection
    for i in range(14):
        y = 985 + i * 34
        w = 300 * (1 - i / 16) * (0.6 + 0.4 * math.sin(i * 1.7))
        c.rect(512 - w / 2, y, 512 + w / 2, y + 10, fill=(255, 240, 190, 220), r=5)
    # palm trees (left and right): tapered trunk + curved leaf-shaped fronds
    def frond(x, y, ang, length, droop, col):
        pts = []; n = 14
        for i in range(n + 1):
            t = i / n
            pts.append((x + math.cos(ang) * length * t, y + math.sin(ang) * length * t + droop * t * t * length))
        left = []; right = []
        for i, (px, py) in enumerate(pts):
            t = i / n
            w = 30 * (math.sin(math.pi * min(1.0, t * 1.02)) ** 0.7) * (1 - 0.25 * t) + 2
            j = min(i + 1, n); k = max(i - 1, 0)
            dx = pts[j][0] - pts[k][0]; dy = pts[j][1] - pts[k][1]; l = math.hypot(dx, dy) or 1
            nx, ny = -dy / l, dx / l
            left.append((px + nx * w, py + ny * w)); right.append((px - nx * w, py - ny * w))
        c.poly(left + right[::-1], fill=col)
    def palm(x, base, h, lean):
        col = (26, 18, 40, 255)
        pts = [(x + lean * (t ** 1.6), base - h * t) for t in [i / 12 for i in range(13)]]
        left = [(px - 16 * (1 - 0.45 * i / 12), py) for i, (px, py) in enumerate(pts)]
        right = [(px + 16 * (1 - 0.45 * i / 12), py) for i, (px, py) in enumerate(pts)]
        c.poly(left + right[::-1], fill=col)
        tx, ty = pts[-1]
        for k in range(9):
            a = math.radians(-170 + k * 20)
            frond(tx, ty, a, 230 + 30 * math.sin(k * 1.9), 0.55, col)
        c.circle(tx, ty, 16, col)
    palm(110, 1310, 720, 90); palm(940, 1360, 640, -80)
    c.rect(0, 1300, W, H, fill=(24, 18, 40, 255))
    # logo + headline
    c.circle(96, 110, 34, fill=(255, 210, 60, 255))
    for k in range(10):
        a = k * math.pi / 5
        c.line([(96 + math.cos(a) * 42, 110 + math.sin(a) * 42), (96 + math.cos(a) * 56, 110 + math.sin(a) * 56)], (255, 210, 60, 255), 6)
    c.text(170, 130, 'Sunhaven', 'head', 68, WHITE, anchor='ls')
    c.text(70, 330, 'Escape', 'bold', 170, WHITE, anchor='ls')
    c.text(70, 480, 'the grey.', 'bold', 170, WHITE, anchor='ls')
    c.text(512, 1370, '7 nights in the Algarve', 'semi', 56, WHITE, anchor='mm')
    c.text(512, 1440, 'Flights, transfers and half board included', 'reg', 32, (230, 220, 240, 255), anchor='mm')
    c.circle(830, 700, 130, fill=(255, 215, 60, 255))
    c.text(830, 632, 'from', 'semi', 36, (40, 20, 60, 255), anchor='mm')
    c.text(830, 712, '£399', 'bold', 100, (40, 20, 60, 255), anchor='mm')
    c.text(830, 782, 'per person', 'semi', 32, (40, 20, 60, 255), anchor='mm')
    fineprint(c, 70, 1500, 'Based on 2 sharing, departing Oct-Nov. Subject to availability. sunhaven.example', (200, 190, 210, 255), 18)


def p3_bank(c):
    W, H = 1024, 1536
    gradient(c, [(0, (0, 96, 108)), (1, (0, 150, 130))], 70)
    for i in range(5):
        glow(c, 100 + i * 220, 1250 + (i % 2) * 90, 230, (255, 255, 255), 22, blur=60)
    c.circle(96, 110, 40, fill=WHITE)
    c.text(96, 122, 'B', 'head', 56, (0, 110, 110, 255), anchor='mm')
    c.text(160, 128, 'Brightwell', 'bold', 66, WHITE, anchor='ls')
    c.text(70, 300, 'Save', 'bold', 150, WHITE, anchor='ls')
    c.text(70, 430, 'smarter.', 'bold', 150, (255, 226, 90, 255), anchor='ls')
    # big rate
    c.text(70, 800, '4.5%', 'bold', 330, WHITE, anchor='ls')
    c.text(80, 880, 'AER / gross variable', 'semi', 46, (210, 245, 240, 255), anchor='ls')
    # coin stack
    for k in range(6):
        x = 700; y = 1150 - k * 34
        c.ellipse(x - 150, y - 40, x + 150, y + 40, fill=(255, 205, 60, 255), outline=(200, 140, 20, 255), width=6)
        c.rect(x - 150, y, x + 150, y + 34, fill=(240, 180, 40, 255))
        c.ellipse(x - 150, y - 6, x + 150, y + 74, fill=(240, 180, 40, 255), outline=(200, 140, 20, 255), width=6)
        c.ellipse(x - 150, y - 40, x + 150, y + 40, fill=(255, 215, 80, 255), outline=(200, 140, 20, 255), width=6)
    c.text(700, 940, '£', 'bold', 60, (170, 110, 10, 255), anchor='mm')
    pill(c, 70, 1090, 520, 1176, WHITE, 'Open in minutes', 'bold', 42, (0, 100, 108, 255))
    c.text(70, 1290, 'Easy-access. No fees. Withdraw whenever you like.', 'reg', 34, (220, 248, 242, 255), anchor='ls')
    fineprint(c, 70, 1440, 'Rate correct at time of print and may change. Capital at risk is not applicable to savings.', (190, 235, 228, 255), 18)
    fineprint(c, 70, 1466, 'Brightwell Bank plc is a fictional company. brightwell.example', (190, 235, 228, 255), 18)


def p4_musical(c):
    W, H = 1024, 1536
    gradient(c, [(0, (8, 10, 40)), (1, (20, 24, 84))], 90)
    gold = (232, 190, 96, 255)
    cx, cy = 512, 860
    for k in range(-9, 10):
        a = math.radians(-90 + k * 10)
        w = math.radians(3.6)
        pts = [(cx, cy), (cx + math.cos(a - w) * 1000, cy + math.sin(a - w) * 1000), (cx + math.cos(a + w) * 1000, cy + math.sin(a + w) * 1000)]
        c.poly(pts, fill=(232, 190, 96, 34 if k % 2 else 16))
    glow(c, 512, 900, 320, (255, 220, 140), 90)
    c.rect(0, 1120, W, H, fill=(6, 6, 22, 255))
    for r in range(4):
        c.ellipse(140 - r * 40, 1090 + r * 26, 884 + r * 40, 1150 + r * 26, outline=(232, 190, 96, 120 - r * 26), width=3)
    dark = (6, 6, 22, 255)
    # male dancer (dipping partner)
    c.circle(430, 800, 30, dark)
    c.line([(430, 835), (445, 960)], dark, 40)
    c.line([(445, 960), (380, 1090)], dark, 28); c.line([(445, 960), (520, 1090)], dark, 28)
    c.line([(430, 850), (500, 900), (560, 860)], dark, 22)
    # female dancer in flared dress, arm raised
    c.circle(640, 760, 32, dark)
    c.poly([(640, 800), (662, 950), (760, 1092), (520, 1092), (618, 950)], fill=dark)
    c.line([(650, 830), (720, 700)], dark, 20)
    c.line([(628, 830), (570, 900)], dark, 20)
    rnd = random.Random(1)
    for k in range(70):
        x = rnd.randint(0, W); y = rnd.randint(0, 700); r = rnd.choice([2, 3, 4])
        c.circle(x, y, r, (255, 240, 200, rnd.randint(120, 255)))
    # title block on a dark fade so it reads over the rays
    lay, d = c.layer(); s = c.ss
    for i in range(60):
        d.rectangle([0, int(i * 6.5 * s), W * s, int((i + 1) * 6.5 * s)], fill=(8, 10, 40, int(235 * (1 - i / 60.0) ** 1.4)))
    c.composite(lay)
    spaced(c, 512, 178, 'THE LANTERN THEATRE PRESENTS', 'head', 30, gold, 5)
    c.rect(200, 206, 824, 210, fill=gold)
    spaced(c, 512, 380, 'MIDNIGHT', 'head', 190, gold, 4)
    spaced(c, 512, 500, 'IN MAYFAIR', 'head', 128, WHITE, 8)
    spaced(c, 512, 1236, 'A NEW MUSICAL', 'head', 52, gold, 12)
    c.text(512, 1296, '"Dazzling. Pure joy from curtain up."', 'semi', 36, WHITE, anchor='mm')
    for k in range(5):
        c.star(372 + k * 34, 1346, 15, gold)
    c.text(700, 1346, 'The Evening Chronicle', 'reg', 28, gold, anchor='mm')
    pill(c, 300, 1390, 724, 1466, gold, 'Book now', 'bold', 40, (10, 12, 44, 255))
    fineprint(c, 512, 1500, 'lantern-theatre.example  |  Tickets from £25  |  Booking fee applies', (170, 176, 210, 255), 18, anchor='ma')


def p5_perfume(c):
    W, H = 1024, 1536
    gradient(c, [(0, (250, 226, 226)), (0.6, (226, 150, 160)), (1, (110, 30, 60))], 90)
    rnd = random.Random(2)
    for k in range(26):
        glow(c, rnd.randint(0, W), rnd.randint(0, 1100), rnd.randint(30, 110), (255, 240, 220), rnd.randint(30, 80), blur=18)
    # bottle
    bx, by = 512, 1010
    lay, d = c.layer(); s = c.ss
    d.ellipse([(bx - 260) * s, (by + 300) * s, (bx + 260) * s, (by + 380) * s], fill=(60, 10, 30, 150))
    c.composite(lay, blur=30)
    c.rect(bx - 190, by - 330, bx + 190, by + 330, fill=(255, 235, 236, 170), r=44)
    c.rect(bx - 190, by - 330, bx + 190, by + 330, outline=(255, 255, 255, 230), width=8, r=44)
    c.rect(bx - 168, by - 150, bx + 168, by + 300, fill=(214, 90, 120, 200), r=30)
    c.rect(bx - 168, by + 60, bx + 168, by + 300, fill=(160, 40, 80, 160), r=30)
    c.rect(bx - 150, by - 90, bx + 150, by + 20, fill=(255, 245, 235, 255), r=8)
    spaced(c, bx, by - 30, 'ÉCLAT', 'head', 62, (120, 30, 60, 255), 8)
    c.rect(bx - 70, by - 470, bx + 70, by - 330, fill=(232, 190, 96, 255), r=10)
    c.rect(bx - 90, by - 500, bx + 90, by - 452, fill=(255, 224, 140, 255), r=14)
    c.rect(bx - 150, by - 320, bx - 110, by + 250, fill=(255, 255, 255, 110), r=18)
    spaced(c, 512, 190, 'ÉCLAT', 'head', 170, (120, 20, 55, 255), 30)
    spaced(c, 512, 270, 'N U I T', 'head', 70, (200, 130, 20, 255), 24)
    c.text(512, 1420, 'The new fragrance', 'semi', 46, WHITE, anchor='mm')
    c.text(512, 1470, 'Available now in all good department stores', 'reg', 26, (255, 230, 236, 255), anchor='mm')


def p6_coffee(c):
    W, H = 1024, 1536
    gradient(c, [(0, (226, 176, 120)), (1, (170, 108, 60))], 90)
    for k in range(9):
        c.circle(120 + k * 110, 1300 + (k % 3) * 70, 130, fill=(255, 255, 255, 14))
    glow(c, 512, 820, 330, (255, 220, 170), 110)
    # cup
    cx, cy = 512, 900
    lay, d = c.layer(); s = c.ss
    d.ellipse([(cx - 330) * s, (cy + 260) * s, (cx + 330) * s, (cy + 380) * s], fill=(60, 30, 10, 130))
    c.composite(lay, blur=24)
    c.ellipse(cx - 320, cy + 230, cx + 320, cy + 330, fill=(250, 246, 240, 255), outline=(220, 210, 196, 255), width=4)   # saucer
    c.poly([(cx - 230, cy - 120), (cx + 230, cy - 120), (cx + 170, cy + 250), (cx - 170, cy + 250)], fill=(252, 250, 246, 255))
    c.ellipse(cx - 230, cy - 160, cx + 230, cy - 80, fill=(252, 250, 246, 255), outline=(222, 214, 200, 255), width=4)
    c.ellipse(cx - 200, cy - 148, cx + 200, cy - 92, fill=(96, 52, 24, 255))
    c.ellipse(cx - 120, cy - 138, cx + 40, cy - 104, fill=(214, 160, 100, 200))
    c.line([(cx + 225, cy - 60), (cx + 330, cy - 40), (cx + 336, cy + 70), (cx + 210, cy + 120)], (252, 250, 246, 255), 34)
    c.rect(cx - 210, cy + 20, cx + 210, cy + 100, fill=(200, 60, 40, 255))
    spaced(c, cx, cy + 74, 'KETTLE & CO', 'head', 44, WHITE, 10)
    # steam
    for k, x in enumerate((cx - 90, cx, cx + 90)):
        pts = [(x + math.sin(i * 0.7 + k) * 34, cy - 190 - i * 34) for i in range(11)]
        c.line(pts, (255, 255, 255, 190), 20, joint='curve')
    c.text(70, 190, 'Good morning,', 'bold', 100, (60, 28, 10, 255), anchor='ls')
    c.text(70, 350, 'London.', 'bold', 170, WHITE, anchor='ls')
    c.text(512, 1392, 'Wake up to better coffee.', 'semi', 58, (60, 28, 10, 255), anchor='mm')
    pill(c, 190, 1430, 834, 1504, (60, 28, 10, 255), 'Buy any large, get a pastry free', 'semi', 34, WHITE)


def p7_gym(c):
    W, H = 1024, 1536
    c.rect(0, 0, W, H, fill=(12, 12, 14, 255))
    lime = (196, 255, 0, 255)
    for k in range(-4, 14):
        x = k * 150
        c.poly([(x, H), (x + 60, H), (x + 60 + 900, 0), (x + 900, 0)], fill=(196, 255, 0, 34 if k % 2 else 14))
    glow(c, 780, 500, 300, (196, 255, 0), 70)
    # dumbbell
    def bar(cx, cy, ang):
        a = math.radians(ang); ca, sa = math.cos(a), math.sin(a)
        def P(x, y): return (cx + x * ca - y * sa, cy + x * sa + y * ca)
        c.poly([P(-300, -18), P(300, -18), P(300, 18), P(-300, 18)], fill=(190, 194, 200, 255))
        for sx in (-1, 1):
            for (w, h, col) in ((60, 250, (30, 32, 38, 255)), (44, 190, (50, 54, 62, 255)), (30, 320, (196, 255, 0, 255))):
                pass
            c.poly([P(sx * 200, -170), P(sx * 260, -170), P(sx * 260, 170), P(sx * 200, 170)], fill=(30, 32, 38, 255))
            c.poly([P(sx * 260, -120), P(sx * 300, -120), P(sx * 300, 120), P(sx * 260, 120)], fill=(70, 74, 84, 255))
            c.poly([P(sx * 200, -170), P(sx * 210, -170), P(sx * 210, 170), P(sx * 200, 170)], fill=(196, 255, 0, 255))
            c.poly([P(sx * 150, -110), P(sx * 200, -110), P(sx * 200, 110), P(sx * 150, 110)], fill=(50, 54, 62, 255))
    bar(560, 860, -22)
    c.text(60, 150, 'PULSE', 'cond', 92, WHITE, anchor='ls')
    c.text(280, 150, 'FIT', 'cond', 92, lime, anchor='ls')
    c.text(56, 420, 'NO', 'cond', 300, WHITE, anchor='ls')
    c.text(56, 690, 'EXCUSES.', 'cond', 300, lime, anchor='ls')
    c.text(60, 1210, 'JOIN TODAY.', 'cond', 130, WHITE, anchor='ls')
    c.text(60, 1290, 'No joining fee. Cancel any time.', 'semi', 44, (210, 214, 220, 255), anchor='ls')
    pill(c, 60, 1330, 600, 1430, lime, 'From £14.99 a month', 'bold', 46, (12, 12, 14, 255))
    fineprint(c, 60, 1480, 'Off-peak membership. 12-month minimum term on some plans. pulsefit.example', (150, 154, 160, 255), 18)


# ================================================================================================ landscape 2048x1024
def p8_charity(c):
    W, H = 2048, 1024
    gradient(c, [(0, (14, 20, 60)), (1, (44, 40, 100))], 90)
    rnd = random.Random(9)
    for k in range(120):
        c.circle(rnd.randint(0, 1100), rnd.randint(0, 700), rnd.choice([2, 3, 4]), (255, 244, 210, rnd.randint(100, 255)))
    c.circle(900, 210, 70, (255, 244, 210, 255)); c.circle(930, 196, 62, (34, 32, 88, 255))
    # hills + house
    c.poly([(0, 1024), (0, 800), (300, 740), (700, 800), (1170, 760), (1170, 1024)], fill=(10, 12, 40, 255))
    hx, hy = 520, 780
    glow(c, hx + 40, hy - 100, 260, (255, 190, 90), 90)
    c.poly([(hx - 190, hy), (hx + 270, hy), (hx + 270, hy - 220), (hx + 40, hy - 380), (hx - 190, hy - 220)], fill=(38, 30, 70, 255))
    c.poly([(hx - 230, hy - 210), (hx + 40, hy - 410), (hx + 310, hy - 210), (hx + 270, hy - 200), (hx + 40, hy - 360), (hx - 190, hy - 200)], fill=(20, 16, 44, 255))
    c.rect(hx - 100, hy - 190, hx + 40, hy - 70, fill=(255, 196, 100, 255))
    c.rect(hx + 90, hy - 190, hx + 200, hy - 70, fill=(255, 196, 100, 255))
    c.line([(hx - 30, hy - 190), (hx - 30, hy - 70)], (38, 30, 70, 255), 6); c.line([(hx - 100, hy - 130), (hx + 40, hy - 130)], (38, 30, 70, 255), 6)
    c.rect(hx - 190, hy, hx + 270, hy + 14, fill=(20, 16, 44, 255))
    # child silhouette in window
    c.circle(hx + 145, hy - 130, 20, (60, 40, 70, 255)); c.poly([(hx + 120, hy - 70), (hx + 170, hy - 70), (hx + 160, hy - 112), (hx + 130, hy - 112)], fill=(60, 40, 70, 255))
    # text
    c.rect(1160, 0, W, H, fill=(255, 244, 226, 255))
    c.circle(1240, 130, 40, fill=(232, 96, 60, 255))
    c.poly([(1216, 138), (1240, 112), (1264, 138), (1264, 156), (1216, 156)], fill=WHITE)
    c.text(1300, 146, 'HomeSafe', 'bold', 66, (40, 30, 60, 255), anchor='ls')
    para(c, 1160 + 80, 250, 'Some children have nowhere safe to sleep tonight.', 'bold', 84, (40, 30, 60, 255), 760, 1.1)
    para(c, 1160 + 80, 640, 'Just £5 a month gives a child a warm bed, a hot meal and someone to talk to.', 'reg', 44, (70, 60, 90, 255), 780, 1.3)
    pill(c, 1240, 830, 1780, 920, (232, 96, 60, 255), 'Donate at homesafe.example', 'bold', 40, WHITE)
    fineprint(c, 1240, 970, 'HomeSafe is a fictional charity. Registered nowhere. This is a game prop.', (120, 110, 140, 255), 20)


def p9_energydrink(c):
    W, H = 2048, 1024
    gradient(c, [(0, (8, 8, 12)), (1, (30, 30, 40))], 20)
    yel = (255, 224, 0, 255)
    for k in range(-2, 12):
        x = k * 220
        c.poly([(x, H), (x + 100, H), (x + 100 + 500, 0), (x + 500, 0)], fill=(255, 224, 0, 22))
    glow(c, 1380, 520, 480, (255, 224, 0), 110)
    # lightning bolts
    def bolt(x, y, s, col):
        pts = [(0, -1), (0.42, -0.1), (0.1, -0.1), (0.55, 1), (-0.35, 0.05), (0.0, 0.05), (-0.42, -0.6)]
        c.poly([(x + px * s, y + py * s) for px, py in pts], fill=col)
    bolt(1130, 560, 300, (255, 224, 0, 45)); bolt(1780, 500, 330, (255, 224, 0, 70)); bolt(1620, 110, 170, (255, 224, 0, 110))
    # can
    cx, cy = 1400, 500
    lay, d = c.layer(); s = c.ss
    d.ellipse([(cx - 170) * s, (cy + 400) * s, (cx + 170) * s, (cy + 450) * s], fill=(0, 0, 0, 200))
    c.composite(lay, blur=18)
    c.rect(cx - 140, cy - 380, cx + 140, cy + 420, fill=(14, 14, 18, 255), r=40)
    c.rect(cx - 140, cy - 380, cx + 140, cy - 330, fill=(150, 154, 160, 255), r=20)
    c.rect(cx - 140, cy + 380, cx + 140, cy + 420, fill=(120, 124, 130, 255), r=18)
    c.rect(cx - 126, cy - 300, cx - 96, cy + 340, fill=(255, 255, 255, 40), r=12)
    c.poly([(cx - 140, cy - 100), (cx + 140, cy - 200), (cx + 140, cy + 60), (cx - 140, cy + 160)], fill=yel)
    bolt(cx, cy - 35, 92, (14, 14, 18, 255))
    spaced(c, cx, cy + 250, 'VOLTUP', 'cond', 76, yel, 6)
    c.text(cx, cy - 250, '250 ml', 'semi', 30, (200, 204, 210, 255), anchor='mm')
    c.text(90, 320, 'CHARGE', 'cond', 270, WHITE, anchor='ls')
    c.text(90, 590, 'YOUR DAY.', 'cond', 270, yel, anchor='ls')
    c.text(96, 720, 'The new energy drink. Zero sugar. 100% volt.', 'semi', 52, (220, 224, 230, 255), anchor='ls')
    pill(c, 96, 780, 620, 870, yel, 'Try VoltUp today', 'bold', 46, (12, 12, 16, 255))
    fineprint(c, 96, 960, 'High caffeine content (150mg per 500ml). Not suitable for children or pregnant women.', (150, 154, 162, 255), 20)


def p10_green(c):
    W, H = 2048, 1024
    gradient(c, [(0, (110, 190, 240)), (0.7, (214, 240, 250)), (1, (240, 252, 235))], 90)
    glow(c, 1600, 220, 220, (255, 255, 230), 200)
    c.circle(1600, 220, 110, fill=(255, 250, 220, 255))
    # hills
    for (col, base, amp, ph) in (((150, 210, 140, 255), 700, 60, 0.0), ((96, 176, 96, 255), 800, 70, 1.4), ((50, 130, 80, 255), 900, 60, 2.6)):
        pts = [(x, base + math.sin(x / 260.0 + ph) * amp) for x in range(0, W + 40, 40)] + [(W, H), (0, H)]
        c.poly(pts, fill=col)
    def turbine(x, y, h, ang):
        c.poly([(x - h * 0.015, y), (x + h * 0.015, y), (x + h * 0.006, y - h), (x - h * 0.006, y - h)], fill=(250, 252, 252, 255))
        for k in range(3):
            a = math.radians(ang + k * 120 - 90)
            L = h * 0.42
            px, py = x + math.cos(a) * L, y - h + math.sin(a) * L
            nx, ny = -math.sin(a), math.cos(a)
            c.poly([(x, y - h), (px + nx * h * 0.028, py + ny * h * 0.028), (px - nx * h * 0.006, py - ny * h * 0.006)], fill=(250, 252, 252, 255))
        c.circle(x, y - h, h * 0.03, fill=(230, 234, 236, 255))
    turbine(1250, 790, 420, 20); turbine(1550, 810, 520, 55); turbine(1860, 780, 380, 100); turbine(1050, 800, 300, 80)
    c.circle(96, 108, 44, fill=(30, 140, 80, 255))
    c.poly([(74, 122), (96, 84), (118, 122)], fill=WHITE)
    c.text(160, 126, 'GreenGrid', 'bold', 76, (16, 90, 60, 255), anchor='ls')
    para(c, 90, 230, 'Power your home with 100% renewable energy.', 'bold', 100, (16, 60, 60, 255), 1020, 1.08)
    c.text(94, 690, 'Switch in five minutes and save on average £180 a year.', 'reg', 44, (16, 70, 70, 255), anchor='ls')
    pill(c, 90, 740, 640, 830, (30, 140, 80, 255), 'Get a quote', 'bold', 46, WHITE)
    fineprint(c, 90, 960, 'Savings based on a typical dual-fuel customer switching from a standard variable tariff. greengrid.example', (30, 90, 70, 255), 20)


def p11_movie(c):
    W, H = 2048, 1024
    gradient(c, [(0, (6, 26, 36)), (0.65, (20, 80, 90)), (1, (232, 130, 50))], 90)
    glow(c, 1300, 760, 500, (255, 170, 80), 160)
    rnd = random.Random(4)
    for k in range(160):
        c.circle(rnd.randint(0, W), rnd.randint(0, 560), rnd.choice([1, 2, 3]), (230, 250, 255, rnd.randint(80, 220)))
    # horizon and desert
    pts = [(x, 800 + math.sin(x / 300.0) * 24 + math.sin(x / 90.0) * 8) for x in range(0, W + 40, 40)] + [(W, H), (0, H)]
    c.poly(pts, fill=(8, 12, 20, 255))
    # radio tower
    tx, ty = 1830, 800
    c.poly([(tx - 60, ty), (tx + 60, ty), (tx + 8, ty - 560), (tx - 8, ty - 560)], fill=(8, 12, 20, 255), outline=None)
    for k in range(1, 9):
        y = ty - k * 62
        w = 60 * (1 - k / 9.5)
        c.line([(tx - w, y), (tx + w, y - 62 * 0.6)], (8, 12, 20, 255), 5); c.line([(tx + w, y), (tx - w, y - 62 * 0.6)], (8, 12, 20, 255), 5)
    c.circle(tx, ty - 570, 16, fill=(255, 60, 40, 255))
    for r in (50, 90, 130):
        c.arc(tx, ty - 570, r, -60, 60, (255, 90, 60, 180 - r), 5)
        c.arc(tx, ty - 570, r, 120, 240, (255, 90, 60, 180 - r), 5)
    # lone figure
    fx, fy = 760, 830
    c.circle(fx, fy - 180, 22, (8, 12, 20, 255))
    c.poly([(fx - 26, fy - 156), (fx + 26, fy - 156), (fx + 34, fy - 60), (fx - 34, fy - 60)], fill=(8, 12, 20, 255))
    c.line([(fx - 16, fy - 60), (fx - 30, fy)], (8, 12, 20, 255), 22); c.line([(fx + 16, fy - 60), (fx + 40, fy)], (8, 12, 20, 255), 22)
    lay, d = c.layer(); s = c.ss
    d.polygon([(fx * s, (fy - 8) * s), ((fx + 700) * s, (fy + 30) * s), ((fx + 700) * s, (fy + 120) * s)], fill=(8, 12, 20, 150))
    c.composite(lay, blur=10)
    spaced(c, 1024, 250, 'THE LAST', 'head', 240, WHITE, 40)
    spaced(c, 1024, 420, 'S I G N A L', 'head', 150, (255, 150, 70, 255), 20)
    c.text(1024, 560, 'Some things are worth answering.', 'reg', 48, (220, 236, 240, 255), anchor='mm')
    spaced(c, 1024, 930, 'IN CINEMAS 14 NOVEMBER', 'head', 64, WHITE, 16)
    fineprint(c, 1024, 985, 'A Northlight Pictures film. Rated 12A. Fictional film for a video game.', (150, 190, 200, 255), 22, anchor='ma')


DESIGNS = [
    ('poster_00', 'portrait', 1024, 1536, 'Streamly (streaming service)', p0_streamly),
    ('poster_01', 'portrait', 1024, 1536, 'Nova X (phone brand)', p1_nova),
    ('poster_02', 'portrait', 1024, 1536, 'Sunhaven (holidays)', p2_sunhaven),
    ('poster_03', 'portrait', 1024, 1536, 'Brightwell Bank (savings)', p3_bank),
    ('poster_04', 'portrait', 1024, 1536, 'Midnight in Mayfair (musical)', p4_musical),
    ('poster_05', 'portrait', 1024, 1536, 'Eclat Nuit (perfume)', p5_perfume),
    ('poster_06', 'portrait', 1024, 1536, 'Kettle & Co (coffee)', p6_coffee),
    ('poster_07', 'portrait', 1024, 1536, 'PulseFit (gym)', p7_gym),
    ('poster_08', 'landscape', 2048, 1024, 'HomeSafe (charity)', p8_charity),
    ('poster_09', 'landscape', 2048, 1024, 'VoltUp (energy drink)', p9_energydrink),
    ('poster_10', 'landscape', 2048, 1024, 'GreenGrid (renewable energy)', p10_green),
    ('poster_11', 'landscape', 2048, 1024, 'The Last Signal (film)', p11_movie),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(PH_OUT, exist_ok=True)
    want = set(int(a) for a in sys.argv[1:] if a.isdigit())
    manifest = []
    for i, (name, orient, w, h, brand, fn) in enumerate(DESIGNS):
        manifest.append(dict(file='%s.png' % name, orientation=orient, width=w, height=h, brand=brand,
                             fits=('poster_frame_6sheet / poster_frame_4sheet' if orient == 'portrait' else 'poster_frame_48sheet')))
        if want and i not in want:
            continue
        c = Canvas(w, h, bg=(0, 0, 0, 255), ss=2, opaque=True)
        fn(c)
        paper(c, 3)
        out = c.out().convert('RGB')
        out.save(os.path.join(OUT, name + '.png'), optimize=True)
        print('poster', name, orient, w, h, brand)
        if i == 0:
            out.resize((512, 768), Image.LANCZOS).save(os.path.join(PH_OUT, 'poster_ph_portrait_c.jpg'), quality=88)
        if i == 11:
            out.resize((1024, 512), Image.LANCZOS).save(os.path.join(PH_OUT, 'poster_ph_landscape_c.jpg'), quality=88)
    json.dump(manifest, open(os.path.join(OUT, 'poster_manifest.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
