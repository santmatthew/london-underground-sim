"""Decals: wet floor sign, belts, help point, fire cabinet, clock, signal plates, emergency stop, lift panels, PA grille."""
import math, random
from PIL import Image
from gfx import *
from proptex_decals import decal, NAVY, BLUE, WHITE, YEL, RED, GREEN, DARK


def _slip_figure(c, cx, cy, s, fill=DARK):
    """generic wet-floor pictogram: falling person + puddle wave"""
    c.circle(cx - s * .10, cy - s * .36, s * .09, fill)
    c.line([(cx - s * .05, cy - s * .24), (cx + s * .08, cy + s * .04)], fill, s * .12)          # torso leaning back
    c.line([(cx + s * .08, cy + s * .04), (cx + s * .30, cy + s * .22), (cx + s * .38, cy + s * .40)], fill, s * .09)   # leg 1
    c.line([(cx + s * .08, cy + s * .04), (cx - s * .12, cy + s * .24), (cx - s * .10, cy + s * .42)], fill, s * .09)   # leg 2
    c.line([(cx - s * .02, cy - s * .18), (cx - s * .28, cy - s * .02)], fill, s * .07)         # arm 1
    c.line([(cx - s * .02, cy - s * .18), (cx + s * .22, cy - s * .26)], fill, s * .07)         # arm 2
    for k in range(3):
        y = cy + s * .50 + k * s * .06
        pts = [(cx - s * .5 + i * s * .05, y + math.sin(i * 0.9 + k) * s * .018) for i in range(21)]
        c.line(pts, fill, s * .025)


@decal('wetfloor', 400, 850)
def _(c):
    W, H = 400, 850
    c.rect(0, 0, W, H, fill=(252, 204, 8, 255))
    c.rect(14, 14, W - 14, H - 14, outline=DARK, width=6, r=22)
    c.text(W / 2, 70, 'CAUTION', 'head', 74, DARK, anchor='mm')
    # warning triangle
    c.poly([(W / 2, 128), (W - 52, 470), (52, 470)], fill=YEL, outline=DARK, width=12)
    _slip_figure(c, W / 2, 335, 190)
    c.text(W / 2, 560, 'WET', 'head', 100, DARK, anchor='mm')
    c.text(W / 2, 668, 'FLOOR', 'head', 100, DARK, anchor='mm')
    c.rect(52, 732, W - 52, 738, fill=DARK)
    c.text(W / 2, 782, 'Slippery when wet', 'semi', 30, DARK, anchor='mm')


@decal('belt', 256, 64)
def _(c):
    c.rect(0, 0, 256, 64, fill=(250, 200, 10, 255))
    for k in range(-2, 9):
        x = k * 64
        c.poly([(x, 0), (x + 32, 0), (x + 32 + 64, 64), (x + 64, 64)], fill=(24, 24, 26, 255))
    c.rect(0, 0, 256, 4, fill=(40, 40, 40, 255)); c.rect(0, 60, 256, 64, fill=(40, 40, 40, 255))


@decal('bin_recycle', 256, 128)
def _(c):
    c.rect(0, 0, 256, 128, fill=(24, 120, 70, 255))
    c.text(158, 64, 'RECYCLING', 'bold', 32, WHITE, anchor='mm')
    for k in range(3):
        a = k * 2 * math.pi / 3 - math.pi / 2
        x = 44 + math.cos(a) * 20; y = 64 + math.sin(a) * 20
        arrow(c, x, y, 26, math.degrees(a) + 150, WHITE, .3, .8)


@decal('help_panel', 384, 1024)
def _(c):
    W, H = 384, 1024
    c.rect(0, 0, W, H, fill=(196, 200, 206, 255))
    # speaker grille (dot grid)
    for r in range(8):
        for k in range(11):
            c.circle(56 + k * 27, 70 + r * 26 + (13 if k % 2 else 0) * 0, 7, fill=(30, 32, 38, 255))
    c.circle(W / 2, 312, 8, fill=(30, 32, 38, 255))
    c.rect(40, 350, W - 40, 420, fill=RED, r=10)
    c.text(W / 2, 385, 'EMERGENCY', 'bold', 40, WHITE, anchor='mm')
    c.circle(W / 2, 555, 106, fill=(70, 74, 80, 255))     # ring behind the red button
    c.circle(W / 2, 555, 96, fill=(150, 12, 14, 255))
    c.text(W / 2, 705, 'Press and speak', 'semi', 30, DARK, anchor='mm')
    c.rect(60, 760, W - 60, 764, fill=(120, 124, 130, 255))
    c.circle(W / 2, 850, 46, fill=(16, 38, 150, 255))
    c.text(W / 2, 852, 'i', 'head', 64, WHITE, anchor='mm')
    c.text(W / 2, 935, 'Information', 'semi', 28, DARK, anchor='mm')
    c.text(W / 2, 980, 'Staff will respond', 'reg', 22, (70, 74, 84, 255), anchor='mm')


@decal('help_sign', 512, 256)
def _(c):
    c.rect(0, 0, 512, 256, fill=(16, 38, 150, 255))
    c.rect(10, 10, 502, 246, outline=WHITE, width=6, r=14)
    c.circle(96, 128, 58, fill=WHITE)
    c.text(96, 132, 'i', 'head', 96, (16, 38, 150, 255), anchor='mm')
    c.text(300, 96, 'Help', 'head', 88, WHITE, anchor='mm')
    c.text(300, 180, 'point', 'head', 88, WHITE, anchor='mm')


@decal('fire_label_top', 512, 128)
def _(c):
    c.rect(0, 0, 512, 128, fill=(200, 24, 24, 255))
    c.text(256, 66, 'FIRE', 'head', 100, WHITE, anchor='mm')


@decal('fire_label_bottom', 512, 192)
def _(c):
    c.rect(0, 0, 512, 192, fill=(244, 244, 240, 255))
    c.rect(0, 0, 512, 192, outline=(200, 24, 24, 255), width=8)
    c.text(256, 40, 'FIRE EXTINGUISHER', 'bold', 40, (200, 24, 24, 255), anchor='mm')
    c.text(256, 100, 'Break glass panel or\nlift extinguisher from bracket', 'semi', 28, DARK, anchor='mm', align='center', spacing=4)
    c.text(256, 158, 'Do not use on electrical fires', 'reg', 24, (90, 90, 90, 255), anchor='mm')


@decal('clock_face', 1024, 1024)
def _(c):
    W = 1024
    c.circle(512, 512, 512, fill=(20, 22, 26, 255))
    c.circle(512, 512, 490, fill=(246, 246, 242, 255))
    c.circle(512, 512, 470, outline=(30, 30, 34, 255), width=6)
    for k in range(60):
        a = k * math.pi / 30
        big = (k % 5 == 0)
        r0 = 470 - (58 if big else 26); r1 = 462
        c.line([(512 + math.sin(a) * r0, 512 - math.cos(a) * r0), (512 + math.sin(a) * r1, 512 - math.cos(a) * r1)], (24, 24, 28, 255), 14 if big else 5)
    for h in range(1, 13):
        a = h * math.pi / 6
        r = 328
        c.text(512 + math.sin(a) * r, 512 - math.cos(a) * r + 6, str(h), 'bold', 104, (22, 22, 26, 255), anchor='mm')


@decal('signal_plate', 256, 128)
def _(c):
    c.rect(0, 0, 256, 128, fill=(246, 246, 240, 255))
    c.rect(4, 4, 252, 124, outline=DARK, width=5, r=6)
    c.text(128, 66, 'S 214', 'bold', 74, DARK, anchor='mm')


@decal('signal_route', 128, 128)
def _(c):
    c.rect(0, 0, 128, 128, fill=(10, 10, 12, 255))
    for k in range(5):
        c.circle(64 + (k - 2) * 20, 64 - abs(k - 2) * 0, 6, fill=(250, 250, 240, 255))


@decal('estop_label', 256, 192)
def _(c):
    c.rect(0, 0, 256, 192, fill=(250, 204, 10, 255))
    c.rect(6, 6, 250, 186, outline=DARK, width=6, r=8)
    c.text(128, 46, 'EMERGENCY', 'head', 42, DARK, anchor='mm')
    c.text(128, 92, 'TRAIN STOP', 'head', 42, DARK, anchor='mm')
    c.text(128, 154, 'Push to stop trains', 'semi', 22, DARK, anchor='mm')


@decal('lift_call', 192, 384)
def _(c):
    c.rect(0, 0, 192, 384, fill=(196, 200, 206, 255))
    c.rect(0, 0, 192, 384, outline=(120, 124, 130, 255), width=4)
    wheelchair(c, 96, 54, 70, DARK)
    c.text(96, 118, 'LIFT', 'bold', 34, DARK, anchor='mm')
    arrow(c, 96, 190, 60, -90, DARK, .3, .8)
    arrow(c, 96, 292, 60, 90, DARK, .3, .8)
    c.text(96, 360, 'Push to call', 'reg', 20, (60, 64, 70, 255), anchor='mm')


@decal('lift_indicator', 256, 128)
def _(c):
    c.rect(0, 0, 256, 128, fill=(4, 6, 8, 255))
    c.text(90, 64, '1', 'bold', 96, (255, 90, 30, 255), anchor='mm')
    arrow(c, 190, 64, 80, -90, (255, 90, 30, 255), .3, .8)


@decal('pa_grille', 256, 256)
def _(c):
    c.rect(0, 0, 256, 256, fill=(110, 116, 124, 255))
    for r in range(14):
        for k in range(14):
            c.circle(18 + k * 17.5 + (8 if r % 2 else 0), 18 + r * 17.5, 5.2, fill=(16, 18, 22, 255))


@decal('cctv_notice', 128, 64)
def _(c):
    c.rect(0, 0, 128, 64, fill=(16, 38, 150, 255))
    c.text(64, 32, 'CCTV', 'bold', 36, WHITE, anchor='mm')


@decal('marker_chevron', 128, 256)
def _(c):
    c.rect(0, 0, 128, 256, fill=(250, 200, 10, 255))
    for k in range(-1, 6):
        y = k * 64
        c.poly([(0, y), (64, y + 32), (128, y), (128, y + 30), (64, y + 62), (0, y + 30)], fill=(24, 24, 26, 255))
