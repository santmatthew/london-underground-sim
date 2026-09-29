"""Decals for ticket machine, info totem maps, journey planner screen."""
import math, random
from PIL import Image, ImageDraw, ImageFilter
from gfx import *
from proptex_decals import decal, NAVY, BLUE, WHITE, YEL, RED, GREEN, DARK


def _btn(c, x0, y0, x1, y1, label, sub=None, fill=(16, 60, 170, 255), icon=None):
    c.rect(x0 + 4, y0 + 6, x1 + 4, y1 + 6, fill=(0, 0, 0, 40), r=18)
    c.rect(x0, y0, x1, y1, fill=fill, r=18)
    cx = (x0 + x1) / 2
    ih = (y1 - y0)
    if icon:
        icon(c, x0 + 58, (y0 + y1) / 2, 46)
        c.text(x0 + 110, (y0 + y1) / 2 - (12 if sub else 0), label, 'bold', 34, WHITE, anchor='lm')
        if sub:
            c.text(x0 + 110, (y0 + y1) / 2 + 26, sub, 'reg', 22, (200, 215, 255, 255), anchor='lm')
    else:
        c.text(cx, (y0 + y1) / 2 - (12 if sub else 0), label, 'bold', 34, WHITE, anchor='mm')
        if sub:
            c.text(cx, (y0 + y1) / 2 + 26, sub, 'reg', 22, (200, 215, 255, 255), anchor='mm')


def _ic_ticket(c, x, y, s):
    c.rect(x - s * .5, y - s * .3, x + s * .5, y + s * .3, fill=WHITE, r=6)
    c.circle(x - s * .5, y, s * .09, fill=(16, 60, 170, 255)); c.circle(x + s * .5, y, s * .09, fill=(16, 60, 170, 255))
    c.rect(x - s * .3, y - s * .1, x + s * .3, y - s * .04, fill=(16, 60, 170, 255)); c.rect(x - s * .3, y + s * .06, x + s * .1, y + s * .12, fill=(16, 60, 170, 255))


def _ic_card(c, x, y, s):
    c.rect(x - s * .5, y - s * .32, x + s * .5, y + s * .32, fill=WHITE, r=6)
    c.rect(x - s * .5, y - s * .16, x + s * .5, y - s * .04, fill=(16, 60, 170, 255))
    c.rect(x - s * .38, y + s * .08, x - s * .1, y + s * .2, fill=(16, 60, 170, 255), r=2)


def _ic_sun(c, x, y, s):
    c.circle(x, y, s * .22, fill=WHITE)
    for k in range(8):
        a = k * math.pi / 4
        c.line([(x + math.cos(a) * s * .32, y + math.sin(a) * s * .32), (x + math.cos(a) * s * .5, y + math.sin(a) * s * .5)], WHITE, s * .07)


def _ic_cal(c, x, y, s):
    c.rect(x - s * .45, y - s * .4, x + s * .45, y + s * .42, fill=WHITE, r=5)
    c.rect(x - s * .45, y - s * .4, x + s * .45, y - s * .16, fill=(210, 60, 60, 255), r=5)
    for i in range(3):
        for j in range(3):
            c.rect(x - s * .32 + i * s * .26, y - s * .06 + j * s * .16, x - s * .2 + i * s * .26, y + s * .04 + j * s * .16, fill=(16, 60, 170, 255))


def _ic_q(c, x, y, s):
    c.circle(x, y, s * .45, fill=WHITE)
    c.text(x, y + 2, '?', 'bold', int(s * .8), (16, 60, 170, 255), anchor='mm')


def _ic_coll(c, x, y, s):
    c.rect(x - s * .4, y - s * .4, x + s * .4, y + s * .4, fill=WHITE, r=5)
    arrow(c, x, y, s * .6, 90, (16, 60, 170, 255), 0.3, 0.8)


@decal('ticket_ui', 1024, 880)
def _(c):
    W, H = 1024, 880
    c.rect(0, 0, W, H, fill=(238, 241, 246, 255))
    c.rect(0, 0, W, 96, fill=(10, 26, 100, 255))
    c.text(36, 48, 'Buy a ticket', 'head', 46, WHITE, anchor='lm')
    c.text(W - 36, 48, 'Touch to start', 'reg', 30, (170, 195, 255, 255), anchor='rm')
    # tabs
    labels = [('Pay as you go', 'Single fares & top-up', _ic_card), ('Single & return', 'Any two stations', _ic_ticket),
              ('Day tickets', 'Anytime & off-peak', _ic_sun), ('Weekly / monthly', 'Season tickets', _ic_cal),
              ('Collect tickets', 'Pre-paid & online', _ic_coll), ('Help & languages', 'Touch for assistance', _ic_q)]
    bw, bh = 460, 196
    for i, (a, b, ic) in enumerate(labels):
        x = 36 + (i % 2) * (bw + 32); y = 130 + (i // 2) * (bh + 26)
        _btn(c, x, y, x + bw, y + bh, a, b, fill=(16, 56, 165, 255) if i < 5 else (60, 70, 96, 255), icon=ic)
    c.rect(0, H - 60, W, H, fill=(220, 225, 234, 255))
    c.text(36, H - 30, 'Contactless cards, coins & notes accepted', 'semi', 26, (30, 40, 80, 255), anchor='lm')
    contactless(c, W - 60, H - 30, 20, (30, 40, 80, 255), width=3)


@decal('ticket_header', 1024, 186)
def _(c):
    c.rect(0, 0, 1024, 186, fill=(246, 247, 245, 255))
    c.rect(0, 0, 1024, 14, fill=(16, 38, 150, 255))
    c.text(46, 98, 'Tickets', 'head', 96, (16, 38, 150, 255), anchor='lm')
    c.text(1000, 74, 'Card, coins & notes', 'semi', 34, (60, 66, 84, 255), anchor='rm')
    c.text(1000, 122, 'Tap here to start', 'reg', 30, (60, 66, 84, 255), anchor='rm')
    c.rect(0, 172, 1024, 186, fill=(16, 38, 150, 255))


@decal('ticket_instr', 1024, 528)
def _(c):
    c.rect(0, 0, 1024, 528, fill=(16, 38, 150, 255))
    c.text(40, 58, 'How to buy a ticket', 'head', 50, WHITE, anchor='lm')
    steps = [('1', 'Choose', 'Touch the screen and pick your ticket'),
             ('2', 'Pay', 'Contactless card, coins or notes'),
             ('3', 'Collect', 'Take your ticket and change')]
    for i, (n, t, d) in enumerate(steps):
        x0 = 40 + i * 326
        c.rect(x0, 120, x0 + 300, 430, fill=(240, 243, 250, 255), r=16)
        c.circle(x0 + 52, 176, 32, fill=(16, 38, 150, 255))
        c.text(x0 + 52, 178, n, 'bold', 40, WHITE, anchor='mm')
        c.text(x0 + 102, 176, t, 'head', 42, (16, 38, 150, 255), anchor='lm')
        c.text(x0 + 24, 300, d, 'semi', 27, (40, 46, 70, 255), anchor='lm') if len(d) < 22 else None
        # wrap description
        words = d.split(' ')
        lines = []; cur = ''
        for w in words:
            if c.text_w(cur + ' ' + w, 'semi', 27) > 250 and cur:
                lines.append(cur); cur = w
            else:
                cur = (cur + ' ' + w).strip()
        lines.append(cur)
        c.rect(x0 + 10, 272, x0 + 290, 420, fill=(240, 243, 250, 255))
        for k, l in enumerate(lines):
            c.text(x0 + 26, 292 + k * 34, l, 'semi', 27, (40, 46, 70, 255), anchor='lm')
        if i == 0:
            c.rect(x0 + 205, 350, x0 + 275, 400, fill=(16, 60, 170, 255), r=6)
            c.rect(x0 + 212, 357, x0 + 268, 393, fill=(230, 236, 250, 255), r=3)
        elif i == 1:
            contactless(c, x0 + 240, 372, 30, (16, 60, 170, 255), width=5)
        else:
            _ic_ticket(c, x0 + 240, 372, 50)
            c.rect(x0 + 216, 359, x0 + 264, 385, fill=None, outline=(16, 60, 170, 255), width=4, r=4)
    c.text(40, 480, 'Need help? Use the help point or ask a member of staff.', 'reg', 28, (190, 205, 245, 255), anchor='lm')


@decal('ticket_slots', 1024, 300)
def _(c):
    c.rect(0, 0, 1024, 300, fill=(24, 26, 32, 255))
    # coin
    c.text(170, 40, 'Coins', 'bold', 40, WHITE, anchor='mm')
    c.circle(170, 118, 40, fill=(206, 176, 90, 255)); c.circle(170, 118, 30, outline=(150, 122, 50, 255), width=3)
    c.text(170, 118, '£', 'bold', 36, (120, 96, 30, 255), anchor='mm')
    # notes
    c.text(512, 40, 'Notes', 'bold', 40, WHITE, anchor='mm')
    c.rect(432, 84, 592, 154, fill=(90, 160, 120, 255), r=6)
    c.rect(444, 96, 580, 142, outline=(50, 110, 80, 255), width=3, r=4)
    c.text(512, 119, '£', 'bold', 34, (40, 100, 70, 255), anchor='mm')
    arrow(c, 512, 205, 56, 90, YEL, 0.3, 0.85)
    # tickets
    c.text(854, 40, 'Tickets & change', 'bold', 34, WHITE, anchor='mm')
    arrow(c, 854, 110, 70, 90, YEL, 0.3, 0.85)
    c.text(170, 232, 'Insert coins', 'reg', 26, (190, 195, 205, 255), anchor='mm')
    c.text(512, 268, 'Insert note face up', 'reg', 26, (190, 195, 205, 255), anchor='mm')
    c.text(854, 232, 'Take here', 'reg', 26, (190, 195, 205, 255), anchor='mm')


# ------------------------------------------------------------------------------------------------ maps
def _streets_map(c, W, H, seed, title, sub):
    rnd = random.Random(seed)
    c.rect(0, 0, W, H, fill=(241, 236, 222, 255))
    c.rect(0, 0, W, 110, fill=(16, 38, 150, 255))
    c.text(36, 46, title, 'head', 48, WHITE, anchor='lm')
    c.text(36, 86, sub, 'reg', 25, (190, 205, 245, 255), anchor='lm')
    # city blocks via jittered road grid
    top, bot = 130, H - 90
    ang = math.radians(rnd.uniform(-14, 14))
    ca, sa = math.cos(ang), math.sin(ang)
    cx, cy = W / 2, (top + bot) / 2
    def rot(x, y):
        return (cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca)
    lay, dr = c.layer()
    S = c.ss
    # parks / water first
    for (px, py, pw, ph, col) in [(rnd.uniform(60, 300), rnd.uniform(200, 500), rnd.uniform(140, 220), rnd.uniform(120, 200), (192, 222, 170, 255)),
                                   (rnd.uniform(300, 500), rnd.uniform(560, 800), rnd.uniform(120, 180), rnd.uniform(100, 170), (192, 222, 170, 255))]:
        dr.rounded_rectangle([px * S, py * S, (px + pw) * S, (py + ph) * S], radius=30 * S, fill=col)
    # river
    pts = [(x, 640 + 120 * math.sin(x / 130.0) + x * 0.15) for x in range(-20, W + 40, 20)]
    dr.line([(x * S, y * S) for (x, y) in pts], fill=(170, 205, 232, 255), width=int(56 * S), joint='curve')
    c.composite(lay)
    # roads
    n_maj = 5
    for i in range(-1, n_maj + 2):
        y = top + (bot - top) * i / n_maj + rnd.uniform(-16, 16)
        a = rot(-40, y); b = rot(W + 40, y + rnd.uniform(-30, 30))
        c.line([a, b], (255, 255, 255, 255), 22 if i % 2 == 0 else 14)
    for i in range(-1, 6):
        x = 40 + (W - 80) * i / 5 + rnd.uniform(-24, 24)
        a = rot(x, top - 40); b = rot(x + rnd.uniform(-40, 40), bot + 40)
        c.line([a, b], (255, 255, 255, 255), 20 if i % 2 else 12)
    # thin minor streets
    for k in range(18):
        x = rnd.uniform(0, W); y = rnd.uniform(top, bot)
        l = rnd.uniform(60, 180)
        a = rnd.choice([0, math.pi / 2]) + ang
        c.line([(x, y), (x + math.cos(a) * l, y + math.sin(a) * l)], (250, 250, 246, 255), 6)
    # header/footer re-cover overflow
    c.rect(0, 0, W, 110, fill=(16, 38, 150, 255))
    c.text(36, 46, title, 'head', 48, WHITE, anchor='lm')
    c.text(36, 86, sub, 'reg', 25, (190, 205, 245, 255), anchor='lm')
    c.rect(0, bot + 10, W, H, fill=(241, 236, 222, 255))
    names = ['Marlow Rd', 'Kestrel St', 'Orchard Way', 'Canal Walk', 'High St', 'Mill Lane', 'Priory Rd', 'Ashby Gdns', 'Station Rd']
    for i, nme in enumerate(names):
        x = rnd.uniform(90, W - 160); y = top + 40 + i * (bot - top - 60) / len(names)
        c.text(x, y, nme, 'semi', 21, (110, 106, 96, 255), anchor='lm')
    c.text(W * 0.24, 290, 'Riverside Park', 'semi', 22, (80, 130, 70, 255), anchor='mm')
    # station marker
    sx, sy = W * 0.52, (top + bot) / 2 - 20
    c.circle(sx, sy, 34, fill=WHITE, outline=(16, 38, 150, 255), width=9)
    c.rect(sx - 96, sy + 44, sx + 96, sy + 84, fill=(16, 38, 150, 255), r=6)
    c.text(sx, sy + 64, 'You are here', 'bold', 26, WHITE, anchor='mm')
    # compass + scale
    c.circle(W - 90, bot - 24, 40, fill=(250, 248, 240, 255), outline=(110, 106, 96, 255), width=3)
    c.poly([(W - 90, bot - 60), (W - 78, bot - 20), (W - 102, bot - 20)], fill=(16, 38, 150, 255))
    c.text(W - 90, bot - 10, 'N', 'bold', 22, (60, 60, 60, 255), anchor='mm')
    c.rect(40, bot - 20, 200, bot - 14, fill=(80, 80, 80, 255)); c.text(40, bot, '250 m', 'reg', 20, (80, 80, 80, 255), anchor='lm')
    c.rect(0, H - 76, W, H, fill=(16, 38, 150, 255))
    c.text(36, H - 38, 'Walking times shown are approximate', 'reg', 24, (190, 205, 245, 255), anchor='lm')


@decal('map_A', 650, 1024)
def _(c):
    _streets_map(c, 650, 1024, 4, 'Local area map', 'Streets within 10 minutes\' walk')


@decal('map_B', 650, 1024)
def _(c):
    W, H = 650, 1024
    c.rect(0, 0, W, H, fill=(250, 250, 247, 255))
    c.rect(0, 0, W, 110, fill=(16, 38, 150, 255))
    c.text(36, 46, 'Rail network map', 'head', 48, WHITE, anchor='lm')
    c.text(36, 86, 'Lines & interchanges (simplified)', 'reg', 25, (190, 205, 245, 255), anchor='lm')
    lines = [((214, 60, 60, 255), [(90, 220), (210, 300), (330, 380), (450, 420), (570, 400)]),
             ((30, 120, 200, 255), [(70, 700), (200, 620), (330, 540), (330, 380), (300, 250), (300, 170)]),
             ((60, 160, 90, 255), [(110, 860), (250, 780), (330, 700), (330, 540), (470, 500), (590, 470)]),
             ((236, 170, 30, 255), [(560, 820), (470, 720), (330, 700), (200, 640), (90, 560)]),
             ((140, 80, 160, 255), [(60, 420), (180, 470), (330, 540), (450, 620), (590, 650)])]
    stations = ['Ashford', 'Brookmere', 'Castlegate', 'Dunmore', 'Eastwick', 'Fairlight', 'Grange Hill', 'Hollins',
                'Ivybridge', 'Junction Rd', 'Kelham', 'Lowfield', 'Mereside', 'Northcote', 'Oakhurst', 'Pinner Green', 'Queens Cross',
                'Ravenscourt', 'Stanmore Vale', 'Thornbury', 'Upper Wold', 'Vale Park', 'Westgate', 'Yarrow', 'Zennor Rd']
    lines = [(col, [(int(50 + x * 0.68), y) for (x, y) in pts]) for col, pts in lines]
    rnd = random.Random(3)
    k = 0
    for col, pts in lines:
        c.line(pts, col, 14, joint='curve')
        for (x, y) in pts:
            c.circle(x, y, 9, fill=WHITE, outline=(30, 30, 40, 255), width=4)
    seen = set()
    for col, pts in lines:
        for (x, y) in pts:
            if (x, y) in seen:
                continue
            seen.add((x, y))
            nm = stations[k % len(stations)]; k += 1
            c.text(x + 16, y - 16, nm, 'semi', 21, (30, 30, 40, 255), anchor='lm')
    for (x, y) in [(int(50 + 330 * 0.68), 540), (int(50 + 330 * 0.68), 380), (int(50 + 330 * 0.68), 700)]:
        c.circle(x, y, 15, fill=WHITE, outline=(0, 0, 0, 255), width=6)
    c.rect(0, H - 130, W, H, fill=(238, 240, 245, 255))
    for i, (col, _) in enumerate(lines):
        c.rect(36, H - 112 + i * 20, 90, H - 100 + i * 20, fill=col)
        c.text(104, H - 106 + i * 20, ['Red line', 'Blue line', 'Green line', 'Amber line', 'Violet line'][i], 'reg', 18, (30, 30, 40, 255), anchor='lm')
    c.circle(W - 150, H - 74, 14, fill=WHITE, outline=(0, 0, 0, 255), width=5)
    c.text(W - 126, H - 74, 'Interchange', 'reg', 20, (30, 30, 40, 255), anchor='lm')


@decal('journey_ui', 592, 1024)
def _(c):
    W, H = 592, 1024
    c.rect(0, 0, W, H, fill=(14, 20, 44, 255))
    c.rect(0, 0, W, 96, fill=(16, 38, 150, 255))
    c.text(28, 48, 'Journey planner', 'head', 42, WHITE, anchor='lm')
    c.text(W - 24, 48, '10:08', 'bold', 34, WHITE, anchor='rm')
    c.rect(24, 118, W - 24, 196, fill=(30, 38, 70, 255), r=12)
    c.text(46, 143, 'FROM', 'reg', 18, (140, 160, 220, 255), anchor='lm'); c.text(46, 172, 'This station', 'semi', 28, WHITE, anchor='lm')
    c.rect(24, 208, W - 24, 286, fill=(30, 38, 70, 255), r=12)
    c.text(46, 233, 'TO', 'reg', 18, (140, 160, 220, 255), anchor='lm'); c.text(46, 262, 'Touch to choose destination', 'reg', 24, (170, 180, 210, 255), anchor='lm')
    routes = [('Fastest', '24 min', [(60, 160, 90), (30, 120, 200)], 'Change at Castlegate'),
              ('Fewest changes', '27 min', [(30, 120, 200)], 'Direct - no changes'),
              ('Step-free', '31 min', [(214, 60, 60), (140, 80, 160)], 'Lifts at all stations'),
              ('Least walking', '29 min', [(236, 170, 30), (60, 160, 90)], 'Change at Junction Rd')]
    y = 314
    for (a, b, cols, d) in routes:
        c.rect(24, y, W - 24, y + 156, fill=(24, 32, 62, 255), r=14)
        c.text(46, y + 32, a, 'bold', 28, WHITE, anchor='lm')
        c.text(W - 46, y + 32, b, 'bold', 32, (120, 230, 150, 255), anchor='rm')
        x = 46
        for col in cols:
            c.rect(x, y + 70, x + 150, y + 84, fill=col + (255,), r=7)
            c.circle(x, y + 77, 10, fill=WHITE); x += 170
        c.circle(x - 20, y + 77, 10, fill=WHITE)
        c.text(46, y + 122, d, 'reg', 22, (170, 180, 210, 255), anchor='lm')
        y += 176
    c.rect(0, H - 76, W, H, fill=(16, 38, 150, 255))
    c.text(28, H - 38, 'Live service updates  |  Good service', 'semi', 24, WHITE, anchor='lm')
