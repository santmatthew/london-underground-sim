#!/usr/bin/env python3
"""Ticket-hall information / clutter textures ("hall_b") -> assets/textures/props/decals/hall_b_<name>_c.png
Everything is invented/generic (no real brand artwork or third-party names).
run with build/venv/bin/python tools/blender/props/proptex_hall_b.py [names...]"""
import os, sys, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gfx import *

OUT = os.path.join(ROOT, 'assets', 'textures', 'props', 'decals')
REG = {}

WHITE = (247, 248, 246, 255)
PAPER = (250, 250, 247, 255)
TFLBLUE = (16, 10, 158, 255)
NAVY = (12, 26, 96, 255)
SKY = (34, 138, 212, 255)
DARK = (18, 20, 24, 255)
GREY = (96, 100, 108, 255)
LGREY = (206, 210, 216, 255)
RED = (220, 36, 31, 255)
YEL = (255, 209, 0, 255)

LINES = {   # generic line colours (name -> rgb)
    'Bakerloo': (178, 99, 0), 'Central': (220, 36, 31), 'Circle': (255, 211, 0), 'District': (0, 125, 50),
    'Hammersmith & City': (244, 169, 190), 'Jubilee': (134, 143, 152), 'Metropolitan': (155, 0, 88),
    'Northern': (0, 0, 0), 'Piccadilly': (0, 25, 168), 'Victoria': (0, 152, 216), 'Waterloo & City': (118, 208, 189),
    'Elizabeth': (105, 80, 161),
}


def tex(name, w, h, opaque=True, ss=2):
    def deco(fn):
        REG[name] = (w, h, opaque, ss, fn)
        return fn
    return deco


def roundel(c, cx, cy, r, bg=PAPER, ring=RED, bar=TFLBLUE, txt='UNDERGROUND'):
    """generic ring + name bar mark on an opaque canvas"""
    c.circle(cx, cy, r, fill=ring)
    c.circle(cx, cy, r * 0.70, fill=bg)
    bh = r * 0.36
    c.rect(cx - r * 1.14, cy - bh / 2, cx + r * 1.14, cy + bh / 2, fill=bar)
    if txt:
        c.text(cx, cy + r * 0.012, txt, 'bold', max(6, int(bh * 0.62)), WHITE, anchor='mm')


def roundel_alpha(c, cx, cy, r, ring=RED, bar=TFLBLUE, txt='UNDERGROUND'):
    """roundel on a transparent (RGBA) canvas: the ring is cut out with a numpy alpha mask"""
    s = c.ss
    W, H = c.im.size
    yy, xx = np.mgrid[0:H, 0:W]
    rr = np.hypot(xx - cx * s, yy - cy * s)
    a = np.zeros((H, W, 4), np.uint8)
    a[..., 0:3] = np.array(ring[:3], np.uint8)
    a[..., 3] = np.where((rr <= r * s) & (rr >= r * 0.70 * s), 255, 0)
    c.im.alpha_composite(Image.fromarray(a, 'RGBA'))
    c._redraw()
    bh = r * 0.36
    c.rect(cx - r * 1.14, cy - bh / 2, cx + r * 1.14, cy + bh / 2, fill=bar)
    if txt:
        c.text(cx, cy + r * 0.012, txt, 'bold', max(6, int(bh * 0.62)), WHITE, anchor='mm')


def italic_i(c, cx, cy, size, fill):
    """serif italic 'i' (Libre Baskerville Bold sheared) centred at cx,cy"""
    s = c.ss
    f = ImageFont.truetype(os.path.join(FONTDIR, 'LibreBaskerville-Bold.ttf'), int(size * s))
    W = int(size * s * 1.6); H = int(size * s * 1.6)
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).text((W / 2, H / 2), 'i', font=f, fill=255, anchor='mm')
    sh = 0.22
    m = m.transform(m.size, Image.AFFINE, (1, sh, -sh * H / 2, 0, 1, 0), resample=Image.BICUBIC)
    lay = Image.new('RGBA', (W, H), fill[:3] + (0,))
    lay.putalpha(m)
    if c.opaque:
        c.im.paste(Image.new('RGB', (W, H), fill[:3]), (int(cx * s - W / 2), int(cy * s - H / 2)), m)
    else:
        c.im.alpha_composite(lay, (int(cx * s - W / 2), int(cy * s - H / 2)))
    c._redraw()


# ================================================================================================ poster stand default
@tex('poster_info', 1024, 1536)
def _(c):
    W, H = 1024, 1536
    c.rect(0, 0, W, H, fill=PAPER)
    c.rect(0, 0, W, 250, fill=TFLBLUE)
    c.text(56, 92, 'Planned closures', 'bold', 104, WHITE, anchor='lm')
    c.text(56, 190, 'Check before you travel this weekend', 'semi', 44, (190, 200, 255, 255), anchor='lm')
    c.rect(56, 290, W - 56, 380, fill=YEL, r=14)
    c.text(W / 2, 336, 'Saturday 3 and Sunday 4 May', 'bold', 54, DARK, anchor='mm')
    rows = [('Central', 'No service between the two eastern termini', 'Replacement buses run'),
            ('District', 'Part closure. Trains run every 12 minutes', 'Allow 20 extra minutes'),
            ('Jubilee', 'Minor delays until 11:00 on Saturday', 'Expect crowding'),
            ('Northern', 'Good service on both branches', 'Lift out of service at one station'),
            ('Victoria', 'Suspended after 22:00 on Saturday', 'Use the alternative route')]
    y = 420
    for (nm, l1, l2) in rows:
        col = LINES[nm] + (255,)
        c.rect(56, y, W - 56, y + 158, fill=(240, 242, 246, 255), r=14)
        c.rect(56, y, 84, y + 158, fill=col)
        c.text(112, y + 36, nm + ' line', 'bold', 48, DARK, anchor='lm')
        c.text(112, y + 92, l1, 'reg', 34, (52, 56, 66, 255), anchor='lm')
        c.text(112, y + 130, l2, 'reg', 30, (96, 100, 110, 255), anchor='lm')
        y += 178
    c.rect(56, y + 12, W - 56, y + 16, fill=LGREY)
    c.text(56, y + 70, 'Plan your journey', 'bold', 52, TFLBLUE, anchor='lm')
    c.text(56, y + 122, 'Ask a member of staff, or use the journey planner', 'reg', 32, (60, 64, 74, 255), anchor='lm')
    c.text(56, y + 166, 'planner.example/weekend', 'semi', 32, TFLBLUE, anchor='lm')
    rnd = random.Random(4)
    qx, qy, qs = W - 250, y + 46, 170
    c.rect(qx, qy, qx + qs, qy + qs, fill=WHITE, outline=DARK, width=4)
    for i in range(17):
        for j in range(17):
            if rnd.random() < 0.5:
                c.rect(qx + 8 + i * 9, qy + 8 + j * 9, qx + 8 + i * 9 + 9, qy + 8 + j * 9 + 9, fill=DARK)


# ================================================================================================ newspaper stand
@tex('news_front', 512, 656)
def _(c):
    W, H = 512, 656
    c.rect(0, 0, W, H, fill=SKY)
    c.rect(22, 22, W - 22, 178, fill=WHITE, r=14)
    c.circle(88, 100, 44, fill=(232, 62, 46, 255))
    c.text(88, 104, 'DC', 'head', 42, WHITE, anchor='mm')
    c.text(160, 82, 'DAILY', 'head', 62, NAVY, anchor='lm')
    c.text(160, 136, 'COMMUTER', 'head', 46, (232, 62, 46, 255), anchor='lm')
    c.text(W / 2, 226, 'PICK UP YOUR', 'bold', 38, WHITE, anchor='mm')
    c.text(W / 2, 320, 'FREE', 'head', 132, YEL, anchor='mm')
    c.text(W / 2, 410, 'NEWSPAPER', 'bold', 60, WHITE, anchor='mm')
    c.text(W / 2, 458, 'HERE', 'bold', 40, WHITE, anchor='mm')
    c.rect(60, 500, W - 60, 504, fill=(255, 255, 255, 180))
    for k in range(3):
        a = k * 2 * math.pi / 3 - math.pi / 2
        arrow(c, 96 + math.cos(a) * 24, 566 + math.sin(a) * 24, 30, math.degrees(a) + 150, WHITE, .3, .8)
    c.text(316, 552, 'Please recycle', 'semi', 30, WHITE, anchor='mm')
    c.text(316, 588, 'after reading', 'semi', 30, WHITE, anchor='mm')


@tex('news_side', 256, 568)
def _(c):
    W, H = 256, 568
    c.rect(0, 0, W, H, fill=SKY)
    c.circle(W / 2, 62, 40, fill=(232, 62, 46, 255))
    c.text(W / 2, 66, 'DC', 'head', 38, WHITE, anchor='mm')
    c.text(W / 2, 140, 'PICK UP', 'bold', 40, WHITE, anchor='mm')
    c.text(W / 2, 184, 'OUR', 'bold', 40, WHITE, anchor='mm')
    c.text(W / 2, 270, 'FREE', 'head', 90, YEL, anchor='mm')
    c.text(W / 2, 340, 'NEWSPAPER', 'bold', 36, WHITE, anchor='mm')
    c.text(W / 2, 470, 'Daily Commuter', 'head', 30, NAVY, anchor='mm')
    c.text(W / 2, 505, 'free every weekday', 'reg', 22, WHITE, anchor='mm')


@tex('news_paper', 256, 192)
def _(c):
    W, H = 256, 192
    c.rect(0, 0, W, H, fill=(238, 236, 228, 255))
    c.rect(0, 0, W, 56, fill=(232, 62, 46, 255))
    c.text(W / 2, 30, 'DAILY COMMUTER', 'head', 26, WHITE, anchor='mm')
    c.rect(14, 68, W - 14, 118, fill=(60, 64, 72, 255))
    rnd = random.Random(2)
    for k in range(6):
        c.rect(14, 128 + k * 10, 14 + rnd.randint(90, 226), 132 + k * 10, fill=(150, 150, 146, 255))


# ================================================================================================ help point
@tex('help_face', 512, 512)
def _(c):
    """white dish face. Centre (256,256) = disc centre; 1 px = 0.42 m / 512. Button rows: fire y=214, emergency y=292, info y=360 (x=182)"""
    c.rect(0, 0, 512, 512, fill=(0, 0, 0, 255))
    c.circle(256, 256, 256, fill=(236, 238, 238, 255))
    c.circle(256, 256, 244, fill=(244, 245, 244, 255))
    c.text(256, 112, 'Help Point', 'bold', 74, (30, 34, 74, 255), anchor='mm')
    # labels to the right of the buttons
    c.text(222, 214, 'Fire alarm', 'semi', 36, DARK, anchor='lm')
    c.text(222, 292, 'Emergency', 'semi', 36, DARK, anchor='lm')
    c.text(222, 360, 'Information', 'semi', 36, DARK, anchor='lm')
    # icons
    c.circle(440, 360, 15, fill=TFLBLUE)
    c.text(440, 361, 'i', 'head', 24, WHITE, anchor='mm')
    # speaker grille: dot cluster at the bottom
    for r in range(3):
        for k in range(9):
            c.circle(256 + (k - 4) * 16 + (8 if r % 2 else 0), 424 + r * 15, 4.3, fill=(120, 124, 130, 255))
    # tiny compliance legend


@tex('help_sign', 128, 128)
def _(c):
    c.rect(0, 0, 128, 128, fill=(0, 132, 78, 255), r=8)
    c.rect(6, 6, 122, 122, outline=WHITE, width=3, r=6)
    # pointing hand (index finger up, three curled knuckles, thumb) + i
    c.rect(38, 24, 50, 66, fill=WHITE, r=6)             # index finger
    c.rect(26, 56, 66, 100, fill=WHITE, r=10)           # palm
    for k in range(3):
        c.rect(52 + k * 5, 50 + k * 3, 60 + k * 5, 66, fill=WHITE, r=3)
    c.poly([(26, 74), (14, 84), (24, 94), (32, 88)], fill=WHITE)      # thumb
    c.circle(95, 38, 8, fill=WHITE)
    c.rect(89, 52, 101, 96, fill=WHITE, r=3)
    c.rect(84, 90, 106, 98, fill=WHITE)


# ================================================================================================ info roundel / clock
@tex('roundel_i', 512, 512, opaque=True)
def _(c):
    c.rect(0, 0, 512, 512, fill=(255, 255, 255, 255))
    c.circle(256, 256, 256, fill=(252, 252, 250, 255))
    c.circle(256, 256, 236, outline=TFLBLUE, width=14)
    italic_i(c, 256, 262, 360, TFLBLUE)


@tex('clock_face', 1024, 1024)
def _(c):
    R = 512
    c.rect(0, 0, 1024, 1024, fill=(20, 22, 26, 255))
    c.circle(512, 512, R, fill=(247, 247, 243, 255))
    for k in range(60):
        a = k * math.pi / 30
        big = (k % 5 == 0)
        r0 = 484 - (52 if big else 24); r1 = 484
        c.line([(512 + math.sin(a) * r0, 512 - math.cos(a) * r0), (512 + math.sin(a) * r1, 512 - math.cos(a) * r1)], (20, 20, 24, 255), 14 if big else 5)
    for h in range(1, 13):
        a = h * math.pi / 6
        r = 358
        c.text(512 + math.sin(a) * r, 512 - math.cos(a) * r + 8, str(h), 'bold', 138, (16, 16, 20, 255), anchor='mm')


# ================================================================================================ CID
@tex('cid_screen', 640, 1136)
def _(c):
    W, H = 640, 1136
    c.rect(0, 0, W, H, fill=(0, 22, 168, 255))
    # top: status list on light blue
    c.rect(0, 0, W, 470, fill=(196, 216, 244, 255))
    c.text(24, 34, 'Service status', 'bold', 34, TFLBLUE, anchor='lm')
    rows = [('Central', 'Minor delays'), ('District', 'Part closure'), ('Northern', 'Good service'),
            ('Piccadilly', 'Minor delays'), ('Waterloo & City', 'Planned closure')]
    y = 68
    for (nm, st) in rows:
        c.rect(14, y, W - 14, y + 74, fill=(232, 240, 252, 255), r=6)
        c.rect(14, y, 34, y + 74, fill=LINES[nm] + (255,))
        c.text(50, y + 26, nm, 'bold', 30, DARK, anchor='lm')
        c.text(50, y + 54, 'All stations' if 'Good' not in st else 'Both branches', 'reg', 20, GREY, anchor='lm')
        col = (170, 20, 20, 255) if ('closure' in st) else ((20, 20, 24, 255) if 'Minor' in st else (0, 90, 40, 255))
        c.text(W - 28, y + 37, st, 'bold', 28, col, anchor='rm')
        y += 80
    # middle: big message
    c.text(40, 560, 'Good service on', 'bold', 64, WHITE, anchor='lm')
    c.text(40, 640, 'all other lines', 'bold', 64, WHITE, anchor='lm')
    c.rect(40, 690, 140, 696, fill=YEL)
    c.text(40, 752, 'Ask a member of staff', 'reg', 30, (200, 214, 255, 255), anchor='lm')
    c.text(40, 792, 'for help with your journey', 'reg', 30, (200, 214, 255, 255), anchor='lm')
    # step-free block
    c.rect(24, 850, W - 24, 960, fill=(0, 12, 120, 255), r=10)
    wheelchair(c, 82, 905, 64, WHITE)
    c.text(140, 885, 'Step-free access', 'semi', 30, WHITE, anchor='lm')
    c.text(140, 928, 'Lift to all platforms', 'reg', 26, (190, 206, 255, 255), anchor='lm')
    # footer: next trains
    c.rect(0, 990, W, H, fill=(196, 216, 244, 255))
    c.text(24, 1030, 'Northern line Southbound', 'semi', 28, TFLBLUE, anchor='lm')
    c.text(24, 1070, 'Next train  2 min', 'bold', 34, DARK, anchor='lm')
    c.text(W - 24, 1070, '14:57', 'bold', 34, DARK, anchor='rm')


@tex('cid_logo', 256, 256, opaque=False)
def _(c):
    roundel_alpha(c, 128, 128, 84, txt='UNDERGROUND')


@tex('cctv_sticker', 64, 64, opaque=False)
def _(c):
    roundel_alpha(c, 32, 32, 25, txt='')


# ================================================================================================ dot-matrix departure board
def _dots(rows, gw, gh, scale, font_px=16):
    """rows: list of (x, y, text, brightness) drawn with the pixel font on a gw x gh grid, then rendered as round amber dots."""
    f = ImageFont.truetype(os.path.join(FONTDIR, 'DotGothic16.ttf'), font_px)
    m = Image.new('L', (gw, gh), 0)
    d = ImageDraw.Draw(m)
    for (x, y, t, b) in rows:
        if x is None:      # right aligned to margin
            wtxt = d.textlength(t, font=f)
            x = gw - 6 - wtxt
        d.text((x, y), t, font=f, fill=int(255 * b))
    a = np.asarray(m, np.float32) / 255.0
    a = (a > 0.35) * np.clip(a * 1.2, 0, 1)
    out = np.zeros((gh * scale, gw * scale, 3), np.float32)
    # dot sprite
    sp = np.zeros((scale, scale), np.float32)
    yy, xx = np.mgrid[0:scale, 0:scale]
    rr = np.hypot(xx - (scale - 1) / 2, yy - (scale - 1) / 2)
    sp = np.clip(1.15 - rr / (scale * 0.46), 0, 1) ** 0.8
    off = np.array([46, 22, 2], np.float32) / 255.0     # unlit dot
    on = np.array([255, 176, 24], np.float32) / 255.0
    for gy in range(gh):
        for gx in range(gw):
            v = a[gy, gx]
            col = off * (1 - v) + on * v
            out[gy * scale:(gy + 1) * scale, gx * scale:(gx + 1) * scale, :] = col[None, None, :] * sp[..., None] * (0.35 + 0.65 * v) if v > 0 else off[None, None, :] * sp[..., None] * 0.55
    return Image.fromarray(np.clip(out * 255, 0, 255).astype(np.uint8), 'RGB')


@tex('dm_board', 1024, 536)
def _(c):
    gw, gh, sc = 256, 134, 4
    rows = [(6, 4, 'Piccadilly line  Departures', 1.0),
            (6, 30, '1  Heathrow T5', 1.0), (None, 30, 'P2   2 min', 1.0),
            (6, 48, '2  Heathrow T5', 1.0), (None, 48, 'P2   8 min', 1.0),
            (6, 66, '3  Rayners Lane', 1.0), (None, 66, 'P1   9 min', 1.0),
            (6, 84, '4  Uxbridge', 1.0), (None, 84, 'P1  12 min', 1.0),
            (None, 112, '11:52:00', 1.0)]
    img = _dots(rows, gw, gh, sc)
    c.im = img.resize((c.im.size[0], c.im.size[1]), Image.LANCZOS)
    c._redraw()


# ================================================================================================ defibrillator sign
@tex('defib_sign', 256, 256)
def _(c):
    c.rect(0, 0, 256, 256, fill=(0, 140, 74, 255), r=18)
    c.rect(10, 10, 246, 246, outline=WHITE, width=5, r=12)
    c.circle(96, 96, 46, fill=WHITE)
    c.circle(160, 96, 46, fill=WHITE)
    c.poly([(52, 118), (204, 118), (128, 214)], fill=WHITE)
    c.poly([(140, 58), (100, 128), (126, 128), (114, 190), (166, 108), (138, 108), (152, 58)], fill=(0, 140, 74, 255))


@tex('defib_label', 256, 96, opaque=True)
def _(c):
    c.rect(0, 0, 256, 96, fill=(246, 246, 242, 255))
    c.text(128, 34, 'DEFIBRILLATOR', 'bold', 30, DARK, anchor='mm')
    c.text(128, 68, 'Emergency use. Call for help first', 'reg', 15, GREY, anchor='mm')


# ================================================================================================ leaflet rack header
@tex('leaflet_header', 512, 128)
def _(c):
    c.rect(0, 0, 512, 128, fill=TFLBLUE)
    c.circle(64, 64, 40, fill=WHITE)
    italic_i(c, 64, 68, 62, TFLBLUE)
    c.text(128, 46, 'Information', 'bold', 48, WHITE, anchor='lm')
    c.text(128, 92, 'Take a leaflet', 'reg', 32, (190, 200, 255, 255), anchor='lm')


@tex('leaflet_card', 128, 128)
def _(c):
    c.rect(0, 0, 128, 128, fill=(240, 240, 236, 255))
    c.rect(0, 0, 128, 44, fill=SKY)
    c.rect(10, 60, 118, 66, fill=(130, 130, 130, 255))
    c.rect(10, 80, 90, 86, fill=(160, 160, 160, 255))
    c.rect(10, 100, 100, 106, fill=(160, 160, 160, 255))


# ================================================================================================ maps (placeholders: the coordinator retargets mat_map at runtime)
def _river(c, W, H, col):
    pts = []
    for i in range(0, 41):
        x = W * i / 40
        y = H * (0.60 + 0.10 * math.sin(i / 40 * 2 * math.pi * 1.1 + 0.6) - 0.16 * (i / 40))
        pts.append((x, y))
    c.line(pts, col, H * 0.045)


@tex('map_tube', 1436, 1024)
def _(c):
    W, H = 1436, 1024
    c.rect(0, 0, W, H, fill=(250, 248, 242, 255))
    _river(c, W, H, (196, 226, 244, 255))
    c.rect(0, 0, W, 64, fill=TFLBLUE)
    c.text(28, 32, 'Tube map', 'bold', 34, WHITE, anchor='lm')
    c.text(W - 28, 32, 'Placeholder diagram - replaced at runtime', 'reg', 22, (190, 200, 255, 255), anchor='rm')
    S = lambda x, y: (W * x, 64 + (H - 64 - 112) * y)
    routes = [
        ('Central', [(0.04, 0.42), (0.30, 0.42), (0.36, 0.48), (0.64, 0.48), (0.72, 0.40), (0.96, 0.40)]),
        ('Northern', [(0.44, 0.05), (0.44, 0.30), (0.52, 0.38), (0.52, 0.66), (0.44, 0.74), (0.44, 0.96)]),
        ('Victoria', [(0.18, 0.10), (0.36, 0.28), (0.52, 0.44), (0.66, 0.58), (0.86, 0.78)]),
        ('Jubilee', [(0.10, 0.20), (0.30, 0.20), (0.46, 0.36), (0.60, 0.52), (0.60, 0.72), (0.78, 0.90)]),
        ('District', [(0.06, 0.76), (0.28, 0.76), (0.40, 0.62), (0.58, 0.62), (0.74, 0.50), (0.94, 0.50)]),
        ('Piccadilly', [(0.06, 0.60), (0.24, 0.60), (0.34, 0.50), (0.56, 0.32), (0.84, 0.32), (0.96, 0.22)]),
        ('Circle', [(0.34, 0.44), (0.34, 0.60), (0.44, 0.68), (0.62, 0.68), (0.70, 0.58), (0.70, 0.44), (0.62, 0.34), (0.44, 0.34), (0.34, 0.44)]),
        ('Elizabeth', [(0.10, 0.90), (0.30, 0.90), (0.52, 0.56), (0.80, 0.56), (0.98, 0.66)]),
    ]
    for nm, pts in routes:
        col = LINES[nm] + (255,)
        c.line([S(*p) for p in pts], col, 12)
    rnd = random.Random(8)
    names = ['Ashby', 'Barrow Hill', 'Castle Cross', 'Dunmore', 'Eastgate', 'Fenwick', 'Grange Park', 'Hollins', 'Ivybridge', 'Junction Rd',
             'Kingsmere', 'Lambourne', 'Marston', 'Northfield', 'Orchard', 'Pemberton', 'Queens Gate', 'Redwood', 'Stoneleigh', 'Thornbury']
    n = 0
    for nm, pts in routes:
        for i, p in enumerate(pts):
            x, y = S(*p)
            c.circle(x, y, 9, fill=WHITE, outline=(30, 30, 40, 255), width=3)
            if i % 2 == 0 and n < len(names) and nm != 'Circle':
                c.text(x + 14, y - 14, names[n], 'semi', 18, (40, 44, 56, 255), anchor='lm')
                n += 1
        for i in range(len(pts) - 1):
            mx = (pts[i][0] + pts[i + 1][0]) / 2; my = (pts[i][1] + pts[i + 1][1]) / 2
            x, y = S(mx, my)
            c.circle(x, y, 4, fill=(30, 30, 40, 255))
    # bottom key
    c.rect(0, H - 112, W, H, fill=(255, 244, 190, 255))
    x = 28
    for nm in ['Central', 'Northern', 'Victoria', 'Jubilee', 'District', 'Piccadilly', 'Circle', 'Elizabeth']:
        c.rect(x, H - 82, x + 44, H - 70, fill=LINES[nm] + (255,))
        c.text(x + 52, H - 76, nm, 'semi', 20, DARK, anchor='lm')
        x += 52 + int(c.text_w(nm, 'semi', 20)) + 30
    c.text(28, H - 36, 'Fictional placeholder network. Fares zones and step-free access not shown.', 'reg', 20, (80, 70, 30, 255), anchor='lm')


@tex("map_local", 1040, 768)
def _(c):
    W, H = 1040, 768
    c.rect(0, 0, W, H, fill=(232, 226, 208, 255))
    rnd = random.Random(12)
    # blocks first, then parks, river, then streets on top
    for k in range(70):
        x, y = rnd.randint(10, W - 90), rnd.randint(70, H - 60)
        c.rect(x, y, x + rnd.randint(36, 96), y + rnd.randint(24, 56), fill=(214, 204, 184, 255), outline=(190, 180, 160, 255), width=2)
    for (x, y, w, h) in ((60, 120, 200, 150), (700, 500, 240, 170), (420, 76, 150, 110), (120, 520, 170, 140)):
        c.rect(x, y, x + w, y + h, fill=(150, 200, 120, 255), outline=(110, 160, 90, 255), width=3, r=26)
    _river(c, W, H, (120, 178, 220, 255))
    for k in range(9):
        y = 90 + k * 80 + rnd.randint(-10, 10)
        y2 = y + rnd.randint(-40, 40)
        c.line([(0, y), (W, y2)], (150, 146, 136, 255), 20)
        c.line([(0, y), (W, y2)], (255, 253, 246, 255), 15)
    for k in range(12):
        x = 40 + k * 88 + rnd.randint(-14, 14)
        x2 = x + rnd.randint(-50, 50)
        c.line([(x, 0), (x2, H)], (150, 146, 136, 255), 18)
        c.line([(x, 0), (x2, H)], (255, 253, 246, 255), 13)
    c.rect(0, 0, W, 62, fill=TFLBLUE)
    c.text(24, 31, 'Local area map', 'bold', 32, WHITE, anchor='lm')
    c.text(W - 24, 31, 'Placeholder - replaced at runtime', 'reg', 20, (190, 200, 255, 255), anchor='rm')
    c.circle(W / 2, H / 2 + 20, 22, fill=RED, outline=WHITE, width=4)
    c.circle(W / 2, H / 2 + 20, 8, fill=WHITE)
    c.rect(W / 2 - 66, H / 2 + 54, W / 2 + 66, H / 2 + 86, fill=TFLBLUE, r=6)
    c.text(W / 2, H / 2 + 70, 'You are here', 'semi', 22, WHITE, anchor='mm')
    for (x, y, t) in ((160, 195, 'Common'), (820, 585, 'Gardens'), (495, 130, 'Green'), (205, 590, 'Fields')):
        c.text(x, y, t, 'bold', 24, (40, 96, 40, 255), anchor='mm')
    c.rect(0, H - 40, W, H, fill=(255, 244, 190, 255))
    c.text(24, H - 20, 'Walking times shown are approximate. Fictional placeholder map.', 'reg', 18, (80, 70, 30, 255), anchor='lm')


def main():
    os.makedirs(OUT, exist_ok=True)
    want = set(sys.argv[1:])
    for name, (w, h, opaque, ss, fn) in REG.items():
        if want and name not in want:
            continue
        c = Canvas(w, h, bg=(0, 0, 0, 255) if opaque else (0, 0, 0, 0), ss=ss, opaque=opaque)
        fn(c)
        out = c.out()
        out.save(os.path.join(OUT, 'hall_b_%s_c.png' % name), optimize=True)
        print('hall_b tex', name, w, h)


if __name__ == '__main__':
    main()
