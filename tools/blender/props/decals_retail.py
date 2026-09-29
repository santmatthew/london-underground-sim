"""Decals for vending machine and station newsstand kiosk (all brands invented)."""
import math, random
from gfx import *
from proptex_decals import decal, NAVY, BLUE, WHITE, YEL, RED, GREEN, DARK


def _can(c, x, y, w, h, col, label, txt=(255, 255, 255, 255)):
    c.rect(x, y, x + w, y + h, fill=col, r=w * 0.18)
    c.rect(x, y, x + w, y + h * 0.08, fill=(190, 194, 200, 255), r=w * 0.15)
    c.rect(x + w * 0.14, y + h * 0.16, x + w * 0.24, y + h * 0.9, fill=(255, 255, 255, 60), r=3)
    c.text(x + w / 2, y + h * 0.55, label, 'cond', max(12, int(w * 0.40)), txt, anchor='mm')


def _bottle(c, x, y, w, h, col, label, cap=(230, 230, 230, 255)):
    c.rect(x + w * 0.34, y, x + w * 0.66, y + h * 0.12, fill=cap, r=3)
    c.poly([(x + w * 0.36, y + h * 0.1), (x + w * 0.64, y + h * 0.1), (x + w * 0.96, y + h * 0.3), (x + w * 0.96, y + h), (x + w * 0.04, y + h), (x + w * 0.04, y + h * 0.3)], fill=col)
    c.rect(x + w * 0.04, y + h * 0.5, x + w * 0.96, y + h * 0.78, fill=(255, 255, 255, 230))
    c.text(x + w / 2, y + h * 0.64, label, 'cond', max(11, int(w * 0.30)), (30, 34, 50, 255), anchor='mm')
    c.rect(x + w * 0.14, y + h * 0.32, x + w * 0.24, y + h * 0.48, fill=(255, 255, 255, 70), r=3)


def _bar(c, x, y, w, h, col, label):
    c.rect(x, y, x + w, y + h, fill=col, r=6)
    c.rect(x, y + h * 0.3, x + w, y + h * 0.7, fill=(255, 255, 255, 220))
    c.text(x + w / 2, y + h * 0.5, label, 'cond', max(11, int(w * 0.2)), (30, 30, 40, 255), anchor='mm')
    c.poly([(x, y), (x + w * 0.1, y + h * 0.5), (x, y + h)], fill=(0, 0, 0, 40))


@decal('vend_front', 480, 1024)
def _(c):
    W, H = 480, 1024
    c.rect(0, 0, W, H, fill=(226, 232, 240, 255))
    for r in range(6):
        y0 = 20 + r * 165
        c.rect(0, y0 + 128, W, y0 + 140, fill=(150, 156, 166, 255))       # shelf
        c.rect(0, y0 + 140, W, y0 + 160, fill=(190, 196, 206, 255))
        # price tags
        for k in range(5):
            c.rect(8 + k * 94, y0 + 141, 8 + k * 94 + 70, y0 + 158, fill=(250, 250, 250, 255))
            c.text(8 + k * 94 + 35, y0 + 150, '%d%d' % (r + 1, k + 1) + '  £%.2f' % (1.2 + r * 0.3 + k * 0.1), 'cond', 13, (30, 30, 40, 255), anchor='mm')
        rnd = random.Random(r * 7 + 3)
        if r < 2:
            cols = [((30, 90, 200), 'FIZZO'), ((220, 40, 40), 'COLA'), ((250, 180, 30), 'ZEST'), ((40, 170, 90), 'LIME'), ((120, 60, 180), 'BERRY')]
            for k in range(5):
                col, lab = cols[(k + r) % 5]
                for j in range(2):
                    _can(c, 8 + k * 94 + j * 4, y0 + 30, 62, 98, col, lab)
        elif r < 4:
            cols = [((60, 180, 220), 'AQUA'), ((240, 240, 240), 'PURE'), ((250, 150, 30), 'ORANGE'), ((60, 190, 110), 'SPARK'), ((220, 60, 120), 'PEACH')]
            for k in range(5):
                col, lab = cols[(k + r) % 5]
                _bottle(c, 12 + k * 94, y0 + 4, 60, 124, col, lab)
        else:
            cols = [(220, 60, 50), (240, 170, 40), (60, 150, 90), (90, 70, 170), (40, 120, 200)]
            labs = ['CRISPS', 'NUTS', 'BAR', 'CHOC', 'MINTS']
            for k in range(5):
                for j in range(3):
                    _bar(c, 8 + k * 94, y0 + 12 + j * 38, 78, 34, cols[(k + j + r) % 5], labs[(k + j) % 5])


@decal('vend_header', 1024, 241)
def _(c):
    c.rect(0, 0, 1024, 241, fill=(20, 80, 190, 255))
    c.rect(0, 0, 1024, 241, fill=(20, 80, 190, 255))
    for k in range(6):
        c.circle(140 + k * 170, 120, 90, fill=(255, 255, 255, 14))
    c.text(60, 108, 'FIZZO', 'head', 128, WHITE, anchor='lm')
    c.text(64, 190, 'Drinks & snacks', 'semi', 48, (200, 225, 255, 255), anchor='lm')
    c.rect(560, 40, 980, 200, fill=(250, 200, 30, 255), r=24)
    c.text(770, 96, 'Ice cold', 'bold', 60, (20, 40, 100, 255), anchor='mm')
    c.text(770, 156, 'Refreshing', 'bold', 60, (20, 40, 100, 255), anchor='mm')


@decal('vend_display', 256, 96)
def _(c):
    c.rect(0, 0, 256, 96, fill=(10, 24, 12, 255))
    c.text(128, 34, 'SELECT', 'dot', 32, (110, 255, 130, 255), anchor='mm')
    c.text(128, 70, 'Card or coins', 'dot', 20, (110, 255, 130, 255), anchor='mm')


@decal('kiosk_sign', 1024, 128)
def _(c):
    c.rect(0, 0, 1024, 128, fill=(14, 20, 56, 255))
    c.rect(6, 6, 1018, 122, outline=(240, 200, 60, 255), width=4, r=10)
    c.text(512, 48, 'THE CORNER KIOSK', 'head', 62, (250, 214, 70, 255), anchor='mm')
    c.text(512, 100, 'NEWS  -  SNACKS  -  DRINKS  -  TRAVEL ESSENTIALS', 'semi', 26, WHITE, anchor='mm')


@decal('kiosk_goods', 512, 512)
def _(c):
    rnd = random.Random(21)
    c.rect(0, 0, 512, 512, fill=(230, 230, 226, 255))
    pal = [(220, 50, 50), (250, 180, 30), (40, 120, 200), (60, 170, 90), (150, 70, 170), (240, 120, 40), (250, 250, 250), (30, 30, 40), (240, 90, 140), (60, 190, 200)]
    words = ['CRISPS', 'CHOC', 'MINTS', 'GUM', 'NUTS', 'WATER', 'JUICE', 'TEA', 'SWEETS', 'BISCUITS', 'BAR', 'FRUIT', 'COLA', 'SNACK']
    y = 0
    while y < 512:
        h = rnd.choice([64, 96, 128])
        x = 0
        while x < 512:
            w = rnd.choice([64, 96, 128])
            col = rnd.choice(pal)
            c.rect(x, y, x + w, y + h, fill=col + (255,), outline=(20, 20, 24, 255), width=2)
            c.rect(x, y + h * 0.35, x + w, y + h * 0.68, fill=(255, 255, 255, 235))
            c.text(x + w / 2, y + h * 0.52, rnd.choice(words), 'cond', int(min(w * 0.22, 24)), (20, 20, 30, 255), anchor='mm')
            c.circle(x + w * 0.2, y + h * 0.16, h * 0.08, fill=(255, 255, 255, 160))
            x += w
        y += h


@decal('kiosk_mags', 512, 512)
def _(c):
    rnd = random.Random(33)
    titles = ['MOTOR WORLD', 'Garden Weekly', 'The Business Post', 'PUZZLE MAX', 'Hello Homes', 'GAMER', 'Cook & Bake', 'TECH TODAY',
              'Football Monthly', 'TRAVEL', 'Mind & Body', 'FASHION 24', 'Wildlife', 'The Week Ahead', 'History Now', 'CINEMA']
    for i in range(16):
        r, k = divmod(i, 4)
        x0, y0 = k * 128 + 4, r * 128 + 2
        col = (rnd.randint(30, 240), rnd.randint(30, 240), rnd.randint(30, 240))
        c.rect(x0, y0, x0 + 120, y0 + 124, fill=col + (255,))
        c.rect(x0, y0, x0 + 120, y0 + 34, fill=(255, 255, 255, 235))
        c.text(x0 + 60, y0 + 18, titles[i], 'cond', 17, (20, 20, 30, 255), anchor='mm')
        c.circle(x0 + 60, y0 + 78, 30, fill=(255, 255, 255, 110))
        c.rect(x0 + 8, y0 + 108, x0 + 100, y0 + 114, fill=(255, 255, 255, 220))


@decal('shutter', 256, 256)
def _(c):
    c.rect(0, 0, 256, 256, fill=(150, 156, 164, 255))
    for k in range(16):
        y = k * 16
        c.rect(0, y, 256, y + 14, fill=(176, 182, 190, 255))
        c.rect(0, y + 14, 256, y + 16, fill=(70, 74, 82, 255))
        c.rect(0, y, 256, y + 2, fill=(210, 214, 220, 255))
        for j in range(4):
            c.rect(10 + j * 64, y + 5, 26 + j * 64, y + 9, fill=(120, 126, 134, 255), r=2)


@decal('vend_side', 512, 768)
def _(c):
    W, H = 512, 768
    c.rect(0, 0, W, H, fill=(20, 80, 190, 255))
    for k in range(8):
        c.circle(60 + k * 60, 700 - (k % 3) * 40, 120, fill=(255, 255, 255, 12))
    c.text(W / 2, 150, 'FIZZO', 'head', 150, WHITE, anchor='mm')
    _can(c, 196, 240, 120, 300, (250, 200, 30, 255), 'ZEST', (20, 40, 100, 255))
    c.text(W / 2, 640, 'Ice cold. Always.', 'bold', 52, (250, 214, 70, 255), anchor='mm')
    c.text(W / 2, 700, 'fizzo.example', 'reg', 30, (200, 225, 255, 255), anchor='mm')
