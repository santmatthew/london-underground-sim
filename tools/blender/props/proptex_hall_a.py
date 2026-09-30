#!/usr/bin/env python3
"""Ticket-hall textures (gates, ticket machines, sign bands, assistance booth) -> assets/textures/props/decals/hall_a_*.png
Standalone: build/venv/bin/python tools/blender/props/proptex_hall_a.py [names...]
Everything is generic artwork (no real brand marks); colours follow the reference notes: TfL blue ~#10069F, reader yellow ~#FFCD00."""
import os, sys, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gfx import *

OUT = os.path.join(ROOT, 'assets', 'textures', 'props', 'decals')
REG = {}

TFL = (16, 6, 159, 255)
WHITE = (245, 246, 244, 255)
YELLOW = (255, 205, 0, 255)
DARK = (18, 20, 24, 255)
AMBER = (255, 150, 24, 255)


def tex(name, w, h):
    def deco(fn):
        REG[name] = (w, h, fn)
        return fn
    return deco


# ============================================================================================ gates
@tex('hall_a_disc', 256, 256)
def _(c):
    """yellow 95 mm reader pad with a generic 'card + swoosh' pictogram (opaque square; used as a circular lathe cap)"""
    c.rect(0, 0, 256, 256, fill=YELLOW)
    # card, tilted, upper left
    cx, cy = 112, 100
    w, h = 96, 62
    a = math.radians(-28)
    pts = []
    for (x, y) in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)):
        pts.append((cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)))
    c.poly(pts, fill=(250, 250, 246, 255), outline=(140, 146, 154, 255), width=3)
    # tapered swoosh running under the card, lower left to right
    N = 24
    top, bot = [], []
    for k in range(N + 1):
        t = k / N
        x = 52 + 156 * t
        y = 168 + 26 * math.sin(math.pi * (t * 0.85 + 0.05)) - 78 * (t ** 2.2)
        wd = 3 + 15 * math.sin(math.pi * t)
        top.append((x, y - wd / 2)); bot.append((x, y + wd / 2))
    c.poly(top + bot[::-1], fill=(112, 118, 126, 255))


@tex('hall_a_disc_in', 128, 128)
def _(c):
    """blue 'go' roundel with a white up arrow (gate entry end)"""
    c.rect(0, 0, 128, 128, fill=(0, 82, 170, 255))
    arrow(c, 64, 66, 76, -90, WHITE, shaft=0.34, head=0.86)


@tex('hall_a_disc_out', 128, 128)
def _(c):
    """red 'no entry' roundel (gate exit end seen from the wrong side)"""
    c.rect(0, 0, 128, 128, fill=(206, 24, 34, 255))
    c.rect(22, 54, 106, 74, fill=WHITE)


@tex('hall_a_sticker', 128, 64)
def _(c):
    c.rect(0, 0, 128, 64, fill=TFL)
    c.text(64, 14, 'Penalty fare', 'bold', 15, WHITE, anchor='mm')
    c.rect(10, 26, 118, 28, fill=(150, 160, 230, 255))
    c.text(64, 40, 'Touch in and', 'reg', 12, (215, 222, 250, 255), anchor='mm')
    c.text(64, 53, 'touch out', 'reg', 12, (215, 222, 250, 255), anchor='mm')


@tex('hall_a_wide_sign', 512, 192)
def _(c):
    """blue header panel of the wide-aisle gate leaf: wheelchair + pushchair pictograms"""
    c.rect(0, 0, 512, 192, fill=TFL)
    wheelchair(c, 150, 100, 130, WHITE)
    # pushchair
    c.circle(388, 58, 15, WHITE)
    c.poly([(352, 90), (426, 90), (426, 122), (384, 136), (352, 122)], fill=WHITE)
    c.line([(352, 96), (322, 58)], WHITE, 10)
    c.line([(322, 58), (302, 58)], WHITE, 10)
    c.line([(392, 136), (368, 162)], WHITE, 9)
    c.circle(366, 164, 17, outline=WHITE, width=7)
    c.circle(424, 158, 13, outline=WHITE, width=6)
    c.rect(0, 0, 512, 192, outline=(140, 150, 240, 255), width=4)


# diamond tread plate (albedo + normal)
def _plate_height(n=256, cells=8):
    im = Image.new('L', (n, n), 0)
    d = ImageDraw.Draw(im)
    cs = n // cells
    for i in range(cells):
        for j in range(cells):
            cx, cy = i * cs + cs / 2, j * cs + cs / 2
            a = math.radians(45 if (i + j) % 2 == 0 else -45)
            L, W = cs * 0.62, cs * 0.17
            ca, sa = math.cos(a), math.sin(a)
            pts = [(cx + x * ca - y * sa, cy + x * sa + y * ca) for (x, y) in ((-L / 2, -W / 2), (L / 2, -W / 2), (L / 2, W / 2), (-L / 2, W / 2))]
            d.polygon(pts, fill=255)
    return np.asarray(im.filter(ImageFilter.GaussianBlur(1.1)), np.float32) / 255.0


def _save_rgb(arr, path):
    Image.fromarray(np.clip(arr, 0, 255).astype('uint8'), 'RGB').save(path, optimize=True)


def _plate(out):
    h = _plate_height()
    # tile-safe blur already wraps poorly; fine at this scale
    base = np.array([54, 56, 60], np.float32)
    alb = base[None, None, :] + h[:, :, None] * np.array([46, 46, 48], np.float32)[None, None, :]
    rnd = np.random.RandomState(4)
    alb += rnd.normal(0, 3.0, h.shape)[:, :, None]
    _save_rgb(alb, os.path.join(out, 'hall_a_plate_c.png'))
    gx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
    gy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    s = 2.4
    n = np.stack([-gx * s, gy * s, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    _save_rgb((n * 0.5 + 0.5) * 255.0, os.path.join(out, 'hall_a_plate_n.png'))


def _vtext(c, cx, cy, txt, kind, size, fill, bottom_to_top=True):
    """text rotated by 90 degrees, centred on (cx, cy) (final-pixel coordinates)"""
    f = font(kind, size * c.ss)
    w = int(f.getlength(txt)) + 8
    h = int(size * c.ss * 1.4)
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((w / 2, h / 2), txt, font=f, fill=fill, anchor='mm')
    im = im.rotate(90 if bottom_to_top else -90, expand=True)
    c.blit(im, cx * c.ss - im.width / 2, cy * c.ss - im.height / 2)


# advert wraps for the gate cabinet entry ends (154 x 900 = 0.14 x 0.82 m). Invented brands, generic artwork.
@tex('hall_a_gate_ad_a', 154, 900)
def _(c):
    c.rect(0, 0, 154, 900, fill=(250, 190, 20, 255))
    c.rect(0, 0, 154, 120, fill=(20, 18, 22, 255))
    c.rect(0, 780, 154, 900, fill=(20, 18, 22, 255))
    for k in range(6):                         # sun rays
        a = math.radians(200 + k * 28)
        c.line([(77, 400), (77 + 160 * math.cos(a), 400 + 160 * math.sin(a))], (20, 18, 22, 255), 9)
    c.circle(77, 400, 46, fill=(20, 18, 22, 255))
    _vtext(c, 77, 610, 'STARLIGHT', 'head', 62, (20, 18, 22, 255))
    c.text(77, 60, 'THE', 'head', 34, (250, 190, 20, 255), anchor='mm')
    c.text(77, 840, 'LIVE NOW', 'bold', 28, (250, 190, 20, 255), anchor='mm')


@tex('hall_a_gate_ad_b', 154, 900)
def _(c):
    c.rect(0, 0, 154, 900, fill=(20, 110, 200, 255))
    c.rect(0, 0, 154, 150, fill=(245, 246, 244, 255))
    c.text(77, 75, 'SALE', 'head', 56, (20, 110, 200, 255), anchor='mm')
    _vtext(c, 77, 470, 'Kestrel & Co', 'head', 64, (245, 246, 244, 255))
    c.rect(20, 700, 134, 860, fill=(255, 205, 0, 255), r=10)
    c.text(77, 745, 'up to', 'bold', 24, (20, 30, 90, 255), anchor='mm')
    c.text(77, 802, '50%', 'head', 42, (20, 30, 90, 255), anchor='mm')


@tex('hall_a_gate_ad_c', 154, 900)
def _(c):
    c.rect(0, 0, 154, 900, fill=(238, 240, 244, 255))
    cols = [(230, 60, 90, 255), (250, 160, 30, 255), (60, 180, 110, 255), (60, 130, 230, 255)]
    for k, col in enumerate(cols):
        c.rect(0, 40 + k * 60, 154, 90 + k * 60, fill=col)
    _vtext(c, 77, 520, 'nova phones', 'bold', 58, (30, 34, 48, 255))
    c.text(77, 820, 'Tap. Pay. Go.', 'semi', 24, (30, 34, 48, 255), anchor='mm')


# ============================================================================================ ticket machines
def _dots(c, x, y, txt, size, fill, anchor='mm'):
    c.text(x, y, txt, 'dot', size, fill, anchor=anchor)


@tex('hall_a_led', 512, 64)
def _(c):
    c.rect(0, 0, 512, 64, fill=(10, 6, 2, 255))
    _dots(c, 256, 34, 'Cards Accepted', 40, AMBER)
    # dot-matrix feel: dark grid lines
    for x in range(0, 512, 4):
        c.rect(x, 0, x + 1, 64, fill=(10, 6, 2, 120))
    for y in range(0, 64, 4):
        c.rect(0, y, 512, y + 1, fill=(10, 6, 2, 120))


@tex('hall_a_led_small', 256, 64)
def _(c):
    c.rect(0, 0, 256, 64, fill=(10, 6, 2, 255))
    _dots(c, 128, 34, 'Cards Only', 38, AMBER)
    for x in range(0, 256, 4):
        c.rect(x, 0, x + 1, 64, fill=(10, 6, 2, 120))
    for y in range(0, 64, 4):
        c.rect(0, y, 256, y + 1, fill=(10, 6, 2, 120))


def _zone_label(c, x0, y0, x1, y1, txt='Zone 4'):
    c.rect(x0, y0, x1, y1, fill=(238, 240, 246, 255), r=5)
    c.rect(x0 + 5, y0 + 5, x1 - 5, y1 - 5, fill=TFL, r=3)
    c.text((x0 + x1) / 2, (y0 + y1) / 2 + 1, txt, 'bold', int((y1 - y0) * 0.62), WHITE, anchor='mm')


@tex('hall_a_mfm_head', 1024, 170)
def _(c):
    c.rect(0, 0, 1024, 170, fill=(15, 16, 19, 255))
    # louvre slats
    for k in range(6):
        y = 8 + k * 9
        c.rect(30, y, 994, y + 4, fill=(38, 40, 46, 255))
        c.rect(30, y + 4, 994, y + 5, fill=(6, 6, 8, 255))
    _zone_label(c, 172, 80, 384, 152)
    # small unit sticker, device number
    c.text(70, 116, '29', 'bold', 26, (150, 154, 162, 255), anchor='mm')
    c.rect(700, 104, 840, 120, fill=(28, 30, 36, 255))
    c.rect(860, 100, 990, 128, fill=(28, 30, 36, 255), r=4)


@tex('hall_a_tvm_head', 512, 170)
def _(c):
    c.rect(0, 0, 512, 170, fill=(15, 16, 19, 255))
    for k in range(6):
        y = 8 + k * 9
        c.rect(20, y, 492, y + 4, fill=(38, 40, 46, 255))
        c.rect(20, y + 4, 492, y + 5, fill=(6, 6, 8, 255))
    _zone_label(c, 132, 80, 372, 152)
    c.text(50, 116, '29', 'bold', 24, (150, 154, 162, 255), anchor='mm')


@tex('hall_a_mfm_ui', 640, 480)
def _(c):
    W, H = 640, 480
    c.rect(0, 0, W, H, fill=(232, 237, 245, 255))
    c.rect(0, 0, W, 60, fill=(8, 30, 130, 255))
    c.text(24, 31, 'Pay as you go', 'head', 32, WHITE, anchor='lm')
    c.text(W - 24, 31, 'Touch to start', 'reg', 22, (170, 195, 255, 255), anchor='rm')
    labels = [('Top up', 'Add credit'), ('Day ticket', 'Anytime / off-peak'), ('Weekly', 'Seven day'),
              ('Monthly', 'Season ticket'), ('Collect', 'Pre-paid tickets'), ('Refund', 'Remaining credit')]
    bw, bh = 290, 88
    for i, (a, b) in enumerate(labels):
        x = 20 + (i % 2) * (bw + 20)
        y = 84 + (i // 2) * (bh + 14)
        c.rect(x + 3, y + 4, x + bw + 3, y + bh + 4, fill=(0, 0, 0, 40), r=10)
        c.rect(x, y, x + bw, y + bh, fill=(18, 62, 176, 255) if i != 5 else (70, 82, 110, 255), r=10)
        c.text(x + 18, y + 34, a, 'bold', 28, WHITE, anchor='lm')
        c.text(x + 18, y + 64, b, 'reg', 19, (196, 212, 255, 255), anchor='lm')
    c.rect(0, H - 52, W, H, fill=(210, 217, 230, 255))
    c.text(20, H - 26, 'Bank cards, notes and coins accepted', 'semi', 22, (30, 40, 80, 255), anchor='lm')
    contactless(c, W - 40, H - 26, 16, (30, 40, 80, 255), width=3)


@tex('hall_a_mfm_pin', 256, 256)
def _(c):
    """card reader + PIN pad block face (0.16 x 0.16 m)"""
    c.rect(0, 0, 256, 256, fill=(20, 21, 25, 255))
    # card slot plate
    c.rect(34, 12, 222, 62, fill=(176, 179, 184, 255), r=6)
    c.rect(48, 30, 208, 42, fill=(4, 4, 6, 255), r=4)
    # keypad
    labels = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '']
    for k in range(12):
        col, row = k % 3, k // 3
        x = 40 + col * 60
        y = 72 + row * 32
        fill = (196, 199, 203, 255)
        if k == 9:
            fill = (206, 40, 46, 255)
        if k == 11:
            fill = (60, 170, 80, 255)
        c.rect(x, y, x + 50, y + 26, fill=fill, r=4)
        if labels[k]:
            c.text(x + 25, y + 14, labels[k], 'bold', 20, (20, 22, 26, 255), anchor='mm')
    c.rect(4, 214, 252, 252, fill=TFL, r=3)
    c.text(128, 233, 'Always protect your PIN', 'semi', 16, WHITE, anchor='mm')


@tex('hall_a_mfm_notice', 1024, 170)
def _(c):
    c.rect(0, 0, 1024, 170, fill=TFL)
    c.text(40, 56, 'Pay as you go: buy, top up and refund', 'semi', 50, WHITE, anchor='lm')
    c.text(40, 118, 'Bank cards, notes and coins accepted', 'semi', 50, WHITE, anchor='lm')


@tex('hall_a_tvm_notice', 512, 170)
def _(c):
    c.rect(0, 0, 512, 170, fill=TFL)
    c.text(24, 34, 'Pay as you go:', 'semi', 34, WHITE, anchor='lm')
    c.text(24, 84, 'buy and top up', 'semi', 34, WHITE, anchor='lm')
    c.text(24, 134, 'Bank cards and coins only', 'semi', 30, WHITE, anchor='lm')


@tex('hall_a_mfm_slots', 256, 64)
def _(c):
    """'Tickets / Change' delivery label on the stainless"""
    c.rect(0, 0, 256, 64, fill=(196, 199, 203, 255))
    arrow(c, 34, 32, 34, 180, (30, 34, 42, 255), shaft=0.36, head=0.92)
    c.text(62, 20, 'Tickets', 'semi', 22, (30, 34, 42, 255), anchor='lm')
    c.text(62, 46, 'Change', 'semi', 22, (30, 34, 42, 255), anchor='lm')


@tex('hall_a_mfm_band', 512, 64)
def _(c):
    """printed band on the stainless above the screen"""
    c.rect(0, 0, 512, 64, fill=(196, 199, 203, 255))
    c.text(256, 22, 'Touch screen', 'semi', 24, (30, 34, 82, 255), anchor='mm')
    c.text(256, 46, 'to buy tickets', 'semi', 24, (30, 34, 82, 255), anchor='mm')


@tex('hall_a_tickets_sign', 1536, 211)
def _(c):
    W, H = 1536, 211
    c.rect(0, 0, W, H, fill=TFL)
    c.rect(6, 6, W - 6, H - 6, outline=(60, 50, 200, 255), width=3, r=6)
    # ticket icon (circle with a ticket) left, card icon right
    c.circle(150, H / 2, 70, fill=WHITE)
    c.circle(150, H / 2, 58, fill=TFL)
    with_ticket = [(112, 84), (188, 84), (188, 126), (112, 126)]
    c.poly(with_ticket, fill=WHITE)
    c.circle(112, 105, 8, fill=TFL); c.circle(188, 105, 8, fill=TFL)
    c.rect(124, 96, 176, 102, fill=TFL); c.rect(124, 109, 160, 115, fill=TFL)
    c.text(W / 2 - 30, H / 2 + 8, 'TICKETS', 'head', 148, WHITE, anchor='mm')
    # card
    c.rect(W - 300, 62, W - 130, 150, fill=WHITE, r=12)
    c.rect(W - 300, 84, W - 130, 104, fill=TFL)
    c.rect(W - 280, 120, W - 220, 134, fill=TFL, r=3)
    arrow(c, W - 62, H / 2, 60, 0, WHITE, shaft=0.34, head=0.9)


@tex('hall_a_assist_sign', 1024, 160)
def _(c):
    c.rect(0, 0, 1024, 160, fill=TFL)
    c.rect(5, 5, 1019, 155, outline=(60, 50, 200, 255), width=3, r=6)
    c.text(512, 84, 'Assistance', 'head', 108, WHITE, anchor='mm')


@tex('hall_a_assist_side', 1024, 160)
def _(c):
    c.rect(0, 0, 1024, 160, fill=TFL)
    c.rect(5, 5, 1019, 155, outline=(60, 50, 200, 255), width=3, r=6)
    c.text(512, 84, 'Assistance', 'head', 108, WHITE, anchor='mm')


# ============================================================================================ main
def main():
    os.makedirs(OUT, exist_ok=True)
    want = sys.argv[1:]
    for name, (w, h, fn) in REG.items():
        if want and name not in want:
            continue
        c = Canvas(w, h, bg=(0, 0, 0, 255), opaque=True)
        fn(c)
        c.out().save(os.path.join(OUT, name + '_c.png'), optimize=True)
        print('decal', name, w, h)
    if not want or 'hall_a_plate' in want:
        _plate(OUT)
        print('plate hall_a_plate_c/_n')


if __name__ == '__main__':
    main()
