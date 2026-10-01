"""Victoria line seat-recess motifs (one per station, data/station_character.json "victoria_motifs"): flat 1960s-style graphics laid out on the
150 mm tile grid. Each image is the back wall of a recess, 2.0 x 1.75 m at 512 px/m; the lowest 0.45 m is hidden behind the timber slab.
Drawn after the subjects named in the Victoria line tile-motif list (Brixton bricks, Stockwell swan, Vauxhall gardens, Pimlico op-art, Victoria cameo, Green
Park leaves, Oxford Circus interchange lines, Warren Street maze, Euston arch, King's Cross crowns, Highbury castle, Finsbury Park pistols, Seven Sisters
trees, Tottenham Hale ferry, Blackhorse Road horse, Walthamstow Morris design): these are simplified redrawings, not copies of the artists' tiles."""
import math
import os
import random

from PIL import Image, ImageDraw

W, H = 1024, 896
S = 2                      # supersampling
PPM = 512


def canvas(bg):
    im = Image.new("RGB", (W * S, H * S), bg)
    return im, ImageDraw.Draw(im)


def P(pts):
    return [(x * S, y * S) for x, y in pts]


def ell(d, cx, cy, rx, ry, fill, outline=None, width=0):
    d.ellipse([(cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S], fill=fill, outline=outline, width=width * S)


def rect(d, x0, y0, x1, y1, fill):
    d.rectangle([x0 * S, y0 * S, x1 * S, y1 * S], fill=fill)


def poly(d, pts, fill):
    d.polygon(P(pts), fill=fill)


def line(d, pts, fill, w):
    d.line(P(pts), fill=fill, width=int(w * S), joint="curve")
    for (x, y) in (pts[0], pts[-1]):
        ell(d, x, y, w / 2, w / 2, fill)


def bez(p0, p1, p2, p3, n=24):
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return out


def tile_grid(im):
    """the 150 mm tile joints over the finished picture, and a faint glaze sheen"""
    d = ImageDraw.Draw(im, "RGBA")
    step = 0.15 * PPM * S
    x = 0.0
    while x < im.width:
        d.line([(x, 0), (x, im.height)], fill=(60, 60, 60, 70), width=3)
        x += step
    y = 0.0
    while y < im.height:
        d.line([(0, y), (im.width, y)], fill=(60, 60, 60, 70), width=3)
        y += step
    return im


ZOOM = 1.4                 # the drawings are composed small; the real motifs fill most of the niche


def finish(im, path):
    z = ZOOM
    big = im.resize((int(im.width * z), int(im.height * z)), Image.LANCZOS)
    cx, cy = 512 * S, 335 * S
    left = int(cx * z - cx)
    top = int(cy * z - cy)
    im = big.crop((left, top, left + W * S, top + H * S))
    im = tile_grid(im)
    im = im.resize((W, H), Image.LANCZOS)
    im.save(path, optimize=True)


# --- the motifs. The picture area is roughly x 150..874, y 60..610 (above the slab) ---------------------------------------------

def bricks():
    im, d = canvas((226, 214, 190))
    rows = [7, 6, 5, 4, 3, 2, 1]
    bw, bh = 96, 52
    y = 560
    cols = [(158, 62, 44), (176, 78, 52), (140, 52, 40), (190, 96, 60)]
    random.seed(3)
    for i, n in enumerate(rows):
        total = n * bw + (n - 1) * 6
        x = 512 - total / 2
        for k in range(n):
            rect(d, x, y - bh, x + bw, y, random.choice(cols))
            x += bw + 6
        y -= bh + 6
    rect(d, 150, 560, 874, 584, (90, 70, 56))
    return im


def swan():
    im, d = canvas((40, 78, 138))
    for k in range(5):                                    # water ripples
        yy = 520 + k * 22
        line(d, [(170 + k * 20, yy), (260 + k * 20, yy - 8), (350 + k * 20, yy), (440 + k * 20, yy - 8)], (96, 140, 200), 8)
        line(d, [(600 - k * 10, yy), (690 - k * 10, yy - 8), (780 - k * 10, yy)], (96, 140, 200), 8)
    ell(d, 480, 440, 215, 110, (246, 246, 242))          # body
    poly(d, [(640, 400), (730, 330), (720, 420), (650, 470)], (246, 246, 242))      # tail
    line(d, bez((330, 400), (250, 330), (330, 230), (340, 150)), (246, 246, 242), 58)  # neck
    ell(d, 345, 135, 44, 34, (246, 246, 242))
    poly(d, [(372, 118), (450, 140), (372, 158)], (232, 120, 30))                         # beak
    ell(d, 352, 128, 7, 7, (20, 20, 20))
    ell(d, 500, 420, 120, 55, (214, 222, 232))                                        # wing
    line(d, [(420, 420), (560, 420)], (170, 184, 204), 6)
    return im


def gardens():
    im, d = canvas((22, 56, 56))
    for i, cx in enumerate([250, 512, 774]):
        rect(d, cx - 110, 300, cx + 110, 590, (226, 206, 150))
        ell(d, cx, 300, 110, 110, (226, 206, 150))
        ell(d, cx, 330, 76, 92, (22, 56, 56))
        rect(d, cx - 76, 330, cx + 76, 590, (22, 56, 56))
        line(d, [(cx, 140), (cx, 250)], (200, 200, 190), 4)
        ell(d, cx, 262, 22, 28, (250, 210, 70))                                       # lantern
        for k in range(-2, 3):
            ell(d, cx + k * 60, 200 + abs(k) * 12, 8, 8, (250, 220, 120))
    for tx in (140, 884):
        rect(d, tx - 8, 400, tx + 8, 590, (90, 60, 40))
        ell(d, tx, 380, 70, 90, (50, 130, 70))
    return im


def opart():
    im, d = canvas((240, 236, 226))
    cols = [(20, 20, 24), (236, 120, 30), (240, 236, 226), (30, 80, 150)]
    cx, cy = 512, 335
    for i in range(18):
        r = 18 - i
        rx, ry = 40 * r, 30 * r
        sq = [(cx - rx, cy - ry), (cx + rx, cy - ry), (cx + rx, cy + ry), (cx - rx, cy + ry)]
        poly(d, [(x + 6 * math.sin(i * 0.7), y) for x, y in sq], cols[i % 4])
    ell(d, cx, cy, 36, 28, (20, 20, 24))
    return im


def cameo():
    im, d = canvas((232, 182, 190))
    ell(d, 512, 330, 250, 290, (30, 60, 130))                                         # blue oval
    ell(d, 512, 330, 232, 272, (40, 78, 160))
    prof = [(470, 130), (520, 120), (560, 135), (585, 180), (596, 230), (612, 268), (590, 280), (598, 300), (584, 316), (592, 336), (574, 352),
            (584, 372), (560, 400), (570, 450), (610, 520), (330, 560), (352, 480), (400, 440), (396, 380), (380, 330), (372, 260), (390, 190)]
    poly(d, prof, (246, 244, 240))
    ell(d, 400, 270, 78, 96, (246, 244, 240))                                         # hair / bun
    ell(d, 380, 330, 52, 66, (246, 244, 240))
    ell(d, 530, 222, 7, 6, (40, 78, 160))
    line(d, [(448, 150), (500, 128), (556, 140)], (200, 198, 196), 8)                 # diadem
    return im


def leaves():
    im, d = canvas((232, 222, 190))
    random.seed(5)
    greens = [(40, 120, 60), (70, 150, 70), (28, 96, 52), (110, 170, 80)]
    for i in range(46):
        x = random.uniform(190, 840)
        y = random.uniform(90, 570)
        a = random.uniform(0, math.tau)
        l = random.uniform(70, 120)
        wd = l * 0.34
        pts = []
        for t in range(0, 21):
            u = t / 20
            off = math.sin(u * math.pi) * wd
            pts.append((u * l, off))
        for t in range(20, -1, -1):
            u = t / 20
            off = -math.sin(u * math.pi) * wd
            pts.append((u * l, off))
        rot = [(x + px * math.cos(a) - py * math.sin(a), y + px * math.sin(a) + py * math.cos(a)) for px, py in pts]
        c = random.choice(greens)
        poly(d, rot, c)
        line(d, [(x, y), (x + l * math.cos(a), y + l * math.sin(a))], (230, 236, 200), 3)
    return im


def interchange():
    im, d = canvas((238, 238, 232))
    cols = [(220, 36, 31), (0, 25, 168), (0, 125, 50), (155, 85, 20), (0, 160, 224), (232, 160, 20), (60, 60, 60), (220, 120, 170)]
    cx, cy = 512, 330
    for i, c in enumerate(cols):
        a = i * math.pi / 4 + 0.2
        for k in (-1, 1):
            line(d, [(cx + math.cos(a) * 420 + k * 6, cy + math.sin(a) * 300), (cx - math.cos(a) * 420 + k * 6, cy - math.sin(a) * 300)], c, 20)
    ell(d, cx, cy, 70, 70, (238, 238, 232))
    ell(d, cx, cy, 70, 70, None, (30, 30, 40), 14)
    return im


def maze():
    im, d = canvas((226, 220, 200))
    random.seed(11)
    n, m = 12, 9
    cell = 62
    x0, y0 = 512 - n * cell / 2, 330 - m * cell / 2
    walls_h = [[True] * n for _ in range(m + 1)]
    walls_v = [[True] * (n + 1) for _ in range(m)]
    seen = [[False] * n for _ in range(m)]
    stack = [(0, 0)]
    seen[0][0] = True
    while stack:
        cx, cy = stack[-1]
        nb = [(cx + dx, cy + dy, dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if 0 <= cx + dx < n and 0 <= cy + dy < m and not seen[cy + dy][cx + dx]]
        if not nb:
            stack.pop()
            continue
        nx, ny, dx, dy = random.choice(nb)
        if dx == 1: walls_v[cy][cx + 1] = False
        if dx == -1: walls_v[cy][cx] = False
        if dy == 1: walls_h[cy + 1][cx] = False
        if dy == -1: walls_h[cy][cx] = False
        seen[ny][nx] = True
        stack.append((nx, ny))
    for r in range(m + 1):
        for c in range(n):
            if walls_h[r][c]:
                line(d, [(x0 + c * cell, y0 + r * cell), (x0 + (c + 1) * cell, y0 + r * cell)], (24, 24, 28), 12)
    for r in range(m):
        for c in range(n + 1):
            if walls_v[r][c]:
                line(d, [(x0 + c * cell, y0 + r * cell), (x0 + c * cell, y0 + (r + 1) * cell)], (24, 24, 28), 12)
    return im


def arch():
    im, d = canvas((228, 218, 196))
    stone = (70, 56, 46)
    rect(d, 200, 548, 824, 584, stone)
    rect(d, 222, 520, 802, 548, stone)
    for cx in (290, 734):
        rect(d, cx - 52, 250, cx + 52, 520, stone)
        for k in range(-2, 3):
            line(d, [(cx + k * 20, 262), (cx + k * 20, 508)], (228, 218, 196), 5)
        rect(d, cx - 66, 232, cx + 66, 256, stone)
    rect(d, 230, 182, 794, 236, stone)
    poly(d, [(210, 182), (512, 80), (814, 182)], stone)
    poly(d, [(290, 176), (512, 108), (734, 176)], (228, 218, 196))
    rect(d, 400, 250, 624, 520, (190, 176, 150))
    return im


def crown(d, cx, cy, sc, col, dark):
    rect(d, cx - 60 * sc, cy, cx + 60 * sc, cy + 28 * sc, col)
    poly(d, [(cx - 60 * sc, cy), (cx - 60 * sc, cy - 64 * sc), (cx - 30 * sc, cy - 26 * sc), (cx, cy - 78 * sc), (cx + 30 * sc, cy - 26 * sc),
             (cx + 60 * sc, cy - 64 * sc), (cx + 60 * sc, cy)], col)
    for px, py in ((-60, -64), (0, -78), (60, -64)):
        ell(d, cx + px * sc, cy + py * sc - 8 * sc, 9 * sc, 9 * sc, col)
    for k in (-36, 0, 36):
        ell(d, cx + k * sc, cy + 14 * sc, 7 * sc, 7 * sc, dark)


def crowns():
    im, d = canvas((24, 50, 110))
    gold = (232, 182, 40)
    dark = (140, 40, 40)
    crown(d, 270, 300, 1.6, gold, dark)
    crown(d, 754, 300, 1.6, gold, dark)
    crown(d, 512, 480, 1.4, gold, dark)
    rect(d, 498, 90, 526, 300, (230, 230, 226))
    rect(d, 450, 140, 574, 168, (230, 230, 226))
    return im


def castle():
    im, d = canvas((150, 196, 226))
    grey = (92, 94, 100)
    light = (150, 152, 158)
    rect(d, 150, 560, 874, 590, (70, 130, 70))
    rect(d, 330, 300, 700, 560, grey)
    for x in range(330, 700, 56):
        rect(d, x, 270, x + 34, 302, grey)
    for tx in (300, 730):
        rect(d, tx - 56, 200, tx + 56, 560, light)
        for x in range(int(tx - 56), int(tx + 56), 38):
            rect(d, x, 168, x + 22, 202, light)
        rect(d, tx - 12, 280, tx + 12, 340, (30, 30, 40))
    ell(d, 515, 500, 62, 62, (40, 30, 30))
    rect(d, 453, 500, 577, 560, (40, 30, 30))
    line(d, [(515, 200), (515, 120)], (60, 60, 60), 6)
    poly(d, [(518, 120), (590, 138), (518, 158)], (200, 40, 40))
    return im


def pistols():
    im, d = canvas((226, 214, 186))
    steel = (58, 60, 68)
    wood = (118, 70, 38)
    brass = (196, 160, 64)
    for m in (1, -1):
        cx, cy = 512, 340
        a = m * 0.42
        ca, sa = math.cos(a), math.sin(a)

        def T(x, y):
            x *= m                                  # the second pistol is the mirror image
            return (cx + x * ca - y * sa, cy + x * sa + y * ca)
        poly(d, [T(-300, -15), T(70, -19), T(70, 19), T(-300, 15)], steel)                       # barrel
        poly(d, [T(-300, -22), T(-276, -22), T(-276, 22), T(-300, 22)], steel)                    # muzzle swell
        for bx in (-210, -130, -50):
            poly(d, [T(bx, -21), T(bx + 14, -21), T(bx + 14, 21), T(bx, 21)], brass)              # barrel bands
        poly(d, [T(70, -26), T(170, -22), T(176, 16), T(70, 22)], steel)                          # lock plate
        poly(d, [T(120, -22), T(150, -64), T(170, -60), T(150, -20)], steel)                      # hammer
        poly(d, [T(60, 8), T(200, 8), T(262, 120), T(236, 190), T(196, 182), T(188, 110), T(110, 40), T(60, 34)], wood)   # stock and grip
        poly(d, [T(236, 190), T(262, 120), T(272, 124), T(246, 198)], brass)                      # butt cap
        pts = bez(T(120, 34), T(120, 90), T(168, 100), T(176, 56), 12)
        line(d, pts, steel, 7)                                                                    # trigger guard
    return im


def trees():
    im, d = canvas((190, 214, 232))
    rect(d, 150, 560, 874, 590, (90, 150, 80))
    for i in range(7):
        cx = 190 + i * 107
        rect(d, cx - 9, 400, cx + 9, 560, (110, 74, 44))
        ell(d, cx, 340 - (i % 2) * 24, 46, 78, (40, 120, 60) if i % 2 == 0 else (60, 150, 70))
    return im


def ferry():
    im, d = canvas((200, 224, 236))
    for k in range(6):
        yy = 470 + k * 24
        pts = [(150 + x, yy + 10 * math.sin(x / 38.0 + k)) for x in range(0, 730, 12)]
        line(d, pts, (60, 110, 170), 8)
    poly(d, [(250, 400), (780, 400), (720, 480), (310, 480)], (30, 50, 100))
    rect(d, 330, 330, 650, 400, (240, 240, 236))
    for x in range(350, 640, 56):
        rect(d, x, 345, x + 34, 372, (60, 90, 150))
    rect(d, 450, 270, 520, 330, (240, 240, 236))
    rect(d, 468, 200, 506, 270, (200, 50, 40))
    for k in range(3):
        ell(d, 520 + k * 50, 180 - k * 36, 28 + k * 8, 20 + k * 6, (230, 230, 232))
    line(d, [(250, 400), (250, 330), (320, 330)], (60, 60, 60), 6)
    return im


def horse():
    im, d = canvas((226, 218, 200))
    blk = (22, 22, 26)
    ell(d, 500, 330, 175, 88, blk)                                                    # body
    poly(d, [(620, 290), (690, 200), (760, 150), (810, 170), (830, 215), (800, 232), (760, 218), (720, 280), (680, 360)], blk)   # neck + head
    poly(d, [(770, 148), (788, 100), (806, 150)], blk)                                # ear
    for lx, ly, bx in ((380, 380, 360), (440, 392, 430), (580, 392, 600), (640, 380, 660)):
        line(d, [(lx, ly), (bx, 540)], blk, 30)
        rect(d, bx - 22, 536, bx + 24, 560, blk)
    line(d, bez((330, 290), (250, 300), (240, 400), (280, 470)), blk, 30)             # tail
    line(d, bez((660, 230), (640, 200), (680, 170), (720, 150)), (70, 70, 80), 10)    # mane highlight
    ell(d, 790, 190, 6, 6, (230, 230, 230))
    return im


def morris():
    im, d = canvas((222, 218, 190))
    blue = (36, 78, 118)
    green = (70, 118, 80)
    rose = (176, 84, 76)
    for ox in (-1, 1):
        for k in range(3):
            pts = bez((512, 600), (512 + ox * 120, 520 - k * 30), (512 - ox * 160, 380 - k * 20), (512 + ox * 40, 100 + k * 60), 40)
            line(d, pts, green if k != 1 else blue, 14)
            for i in range(4, 40, 5):
                x, y = pts[i]
                a = ox * (0.8 + 0.1 * (i % 3))
                lf = [(x, y), (x + ox * 80, y - 36), (x + ox * 150, y - 6), (x + ox * 84, y + 24)]
                poly(d, lf, green if (i // 5) % 2 == 0 else blue)
    for x, y in ((512, 330), (360, 240), (664, 240), (400, 470), (624, 470)):
        for k in range(8):
            a = k * math.tau / 8
            ell(d, x + 34 * math.cos(a), y + 34 * math.sin(a), 20, 14, rose)
        ell(d, x, y, 16, 16, (240, 214, 120))
    return im


MOTIFS = {"bricks": bricks, "swan": swan, "gardens": gardens, "opart": opart, "cameo": cameo, "leaves": leaves, "interchange": interchange,
          "maze": maze, "arch": arch, "crowns": crowns, "castle": castle, "pistols": pistols, "trees": trees, "ferry": ferry, "horse": horse,
          "morris": morris}


def run(out_dir, char):
    d = os.path.join(out_dir, "motif")
    os.makedirs(d, exist_ok=True)
    used = set(char.get("victoria_motifs", {}).values())
    for key, fn in MOTIFS.items():
        if key in used:
            finish(fn(), os.path.join(d, key + ".png"))
    print("wrote %d motifs" % len(used))
