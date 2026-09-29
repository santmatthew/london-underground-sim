#!/usr/bin/env python3
"""Generate the procedural train textures (moquette, body panels, laminate, ceiling, floor, ...).

Run with a python that has numpy + pillow, e.g.
    build/venv_train/bin/python tools/blender/train/make_textures.py
Writes to assets/textures/train/ (<= 1K each, body 2K x 512).  Conventions:
    <name>_c.jpg   albedo (sRGB)
    <name>_n.jpg   normal map (OpenGL / Y+ up)
    <name>_orm.jpg R=ambient occlusion, G=roughness, B=metalness
"""
import os, sys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SRC = os.path.join(ROOT, 'assets', 'textures')
OUT = os.path.join(ROOT, 'assets', 'textures', 'train')
os.makedirs(OUT, exist_ok=True)
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
FONT_R = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'


# ----------------------------------------------------------------- helpers
def save(arr, name, q=90):
    a = np.clip(arr, 0, 1)
    if a.ndim == 2:
        a = np.stack([a] * 3, -1)
    Image.fromarray((a * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name), quality=q, subsampling=0)


def load(setname, mapname, size=None, gray=False):
    im = Image.open(os.path.join(SRC, setname, mapname + '.jpg'))
    im = im.convert('L' if gray else 'RGB')
    if size:
        im = im.resize(size, Image.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255.0


def noise_tile(h, w, cy, cx, seed):
    """periodic value noise with cy x cx cells (bicubic-ish smooth)."""
    rng = np.random.RandomState(seed)
    g = rng.rand(cy, cx).astype(np.float32)
    ys = (np.arange(h) / h) * cy
    xs = (np.arange(w) / w) * cx
    y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
    fy = ys - y0; fx = xs - x0
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    y1 = (y0 + 1) % cy; x1 = (x0 + 1) % cx
    y0 %= cy; x0 %= cx
    a = g[y0][:, x0]; b = g[y0][:, x1]; c = g[y1][:, x0]; d = g[y1][:, x1]
    fx = fx[None, :]; fy = fy[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(h, w, cy, cx, octaves, seed, gain=0.5):
    out = np.zeros((h, w), np.float32); amp = 1.0; tot = 0
    for o in range(octaves):
        out += amp * noise_tile(h, w, cy * 2 ** o, cx * 2 ** o, seed + o * 17)
        tot += amp; amp *= gain
    return out / tot


def normal_from_height(hm, strength=2.0):
    dx = (np.roll(hm, -1, 1) - np.roll(hm, 1, 1)) * 0.5
    dy = (np.roll(hm, -1, 0) - np.roll(hm, 1, 0)) * 0.5
    nx = -dx * strength; ny = dy * strength; nz = np.ones_like(hm)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / l * .5 + .5, ny / l * .5 + .5, nz / l * .5 + .5], -1)


def blend_normals(n1, n2):
    a = n1 * 2 - 1; b = n2 * 2 - 1
    r = np.stack([a[..., 0] + b[..., 0], a[..., 1] + b[..., 1], a[..., 2] * b[..., 2]], -1)
    r /= np.linalg.norm(r, axis=-1, keepdims=True)
    return r * .5 + .5


def orm(ao, rough, metal):
    return np.stack([ao, rough, metal], -1)


def lum(rgb):
    return rgb[..., 0] * .2126 + rgb[..., 1] * .7152 + rgb[..., 2] * .0722


def voronoi(size, n, seed, metric='cheb'):
    """periodic voronoi; returns (cell id, edge distance) at size x size"""
    rng = np.random.RandomState(seed)
    pts = (np.stack(np.meshgrid(np.arange(n), np.arange(n), indexing='ij'), -1).reshape(-1, 2) + rng.rand(n * n, 2) * 0.9) / n
    ys = (np.arange(size) + .5) / size
    yy, xx = np.meshgrid(ys, ys, indexing='ij')
    best = np.full((size, size), 9., np.float32); second = best.copy(); idx = np.zeros((size, size), np.int32)
    for i, (py, px) in enumerate(pts):
        best_d = None
        for oy in (-1, 0, 1):
            for ox in (-1, 0, 1):
                dy = yy - (py + oy); dx = xx - (px + ox)
                if metric == 'cheb':
                    d = np.maximum(np.abs(dy), np.abs(dx)) * .75 + (np.abs(dy) + np.abs(dx)) * .35
                else:
                    d = np.sqrt(dy * dy + dx * dx)
                best_d = d if best_d is None else np.minimum(best_d, d)
        m = best_d < best
        second = np.where(m, best, np.minimum(second, best_d))
        idx = np.where(m, i, idx)
        best = np.where(m, best_d, best)
    return idx, (second - best) * n


# ----------------------------------------------------------------- moquette
def moquette(name, base, accents, seed, S=1024, save_maps=True):
    """abstract tone-on-tone angular ground + small accent shards (original pattern, not a copy of any real design)."""
    rng = np.random.RandomState(seed)
    idx, edge = voronoi(S, 5, seed)
    bp = np.array(base, np.float32) / 255.0
    cid = rng.randint(0, len(bp), size=25)
    col = bp[cid[idx]]
    line = np.clip(1.0 - edge * 14.0, 0, 1)[..., None]
    col = col * (1 - line * .5) + bp[0] * 1.7 * line * .5
    im = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    acc = [tuple(int(v) for v in c) for c, w in accents for _ in range(w)]
    N = 9
    cell = S / N
    for gy in range(N):
        for gx in range(N):
            if rng.rand() > 0.62:
                continue
            cx = (gx + rng.rand()) * cell; cy = (gy + rng.rand()) * cell
            r = rng.uniform(.20, .36) * cell
            kind = rng.randint(0, 3)
            ang = rng.randint(0, 12) * math.pi / 6
            c = acc[rng.randint(0, len(acc))]
            if kind == 0:      # triangle
                pts = [(cx + r * math.cos(ang + k * 2.094), cy + r * math.sin(ang + k * 2.094)) for k in range(3)]
            elif kind == 1:    # diamond
                pts = [(cx + r * math.cos(ang), cy + r * math.sin(ang) * .6), (cx + r * .55 * math.cos(ang + 1.57), cy + r * .55 * math.sin(ang + 1.57)),
                       (cx - r * math.cos(ang), cy - r * math.sin(ang) * .6), (cx - r * .55 * math.cos(ang + 1.57), cy - r * .55 * math.sin(ang + 1.57))]
            else:              # bar
                ux, uy = math.cos(ang), math.sin(ang); vx, vy = -uy, ux
                pts = [(cx + ux * r * 1.3 + vx * r * .28, cy + uy * r * 1.3 + vy * r * .28), (cx + ux * r * 1.3 - vx * r * .28, cy + uy * r * 1.3 - vy * r * .28),
                       (cx - ux * r * 1.3 - vx * r * .28, cy - uy * r * 1.3 - vy * r * .28), (cx - ux * r * 1.3 + vx * r * .28, cy - uy * r * 1.3 + vy * r * .28)]
            for ox in (-S, 0, S):
                for oy in (-S, 0, S):
                    d.polygon([(px + ox, py + oy) for px, py in pts], fill=c)
            # tiny dots around
            for k in range(2):
                dx = cx + rng.uniform(-1, 1) * cell * .45; dy = cy + rng.uniform(-1, 1) * cell * .45
                rr = rng.uniform(2.5, 5)
                c2 = acc[rng.randint(0, len(acc))]
                for ox in (-S, 0, S):
                    for oy in (-S, 0, S):
                        d.ellipse((dx - rr + ox, dy - rr + oy, dx + rr + ox, dy + rr + oy), fill=c2)
    col = np.asarray(im, np.float32) / 255.0
    # weave detail from Fabric030 (repeated 2x so the weave reads at 0.25 m)
    fc = load('Fabric030', 'Color', (S // 2, S // 2))
    fc = np.tile(fc, (2, 2, 1))
    detail = lum(fc); detail = detail / detail.mean()
    col = col * np.clip(0.60 + 0.40 * detail, 0, 1.6)[..., None]
    col *= (0.9 + 0.2 * fbm(S, S, 64, 64, 2, seed + 9))[..., None]
    save(col, name + '_c.jpg')
    if save_maps:
        n = np.tile(load('Fabric030', 'NormalGL', (S // 2, S // 2)), (2, 2, 1))
        ao = np.tile(load('Fabric030', 'AmbientOcclusion', (S // 2, S // 2), gray=True), (2, 2))
        save(n, name + '_n.jpg', 84)
        save(orm(ao * .5 + .5, np.full((S, S), .92, np.float32), np.zeros((S, S), np.float32)), name + '_orm.jpg')
    return col


def gen_moquette():
    navy = [(20, 30, 72), (28, 42, 92), (36, 56, 108), (24, 36, 84)]
    acc_blue = [((150, 34, 46), 3), ((30, 100, 72), 2), ((196, 180, 146), 3), ((200, 122, 40), 1), ((110, 150, 196), 2)]
    moquette('moquette', navy, acc_blue, 11)
    plum = [(56, 26, 78), (70, 34, 92), (46, 24, 70), (80, 40, 100)]
    moquette('moquette_prio', plum, [((214, 120, 150), 3), ((214, 176, 70), 2), ((200, 190, 200), 3), ((60, 110, 170), 1)], 23, save_maps=False)
    # alternative palettes (not embedded by default; the game can swap the albedo of mat_moquette at runtime)
    moquette('moquette_red', [(94, 20, 30), (112, 26, 36), (80, 18, 28), (126, 34, 42)], [((210, 176, 90), 3), ((28, 50, 110), 2), ((196, 190, 170), 3), ((30, 96, 66), 1)], 31, save_maps=False)
    moquette('moquette_green', [(20, 66, 48), (28, 80, 58), (16, 54, 40), (36, 92, 66)], [((190, 176, 120), 3), ((150, 38, 44), 2), ((196, 200, 190), 3), ((30, 60, 120), 1)], 47, save_maps=False)


# ----------------------------------------------------------------- exterior body (8 m x 2 m tile, 2048 x 512)
def gen_body(name='body', base=(.80, .81, .83), seam_step=2.0, rivets=False, seed=5):
    W, H = 2048, 512
    xs = np.arange(W)[None, :] / W * 8.0     # metres
    ys = np.arange(H)[:, None] / H * 2.0
    alb = np.ones((H, W, 3), np.float32) * np.array(base)
    streak = noise_tile(H, W, 240, 3, seed) * .6 + noise_tile(H, W, 90, 5, seed + 1) * .4
    mott = fbm(H, W, 3, 12, 4, seed + 2)
    alb *= (0.965 + 0.05 * streak + 0.07 * (mott - .5))[..., None]
    height = 0.012 * streak
    seam = np.zeros((H, W), np.float32)
    nseam = int(round(8.0 / seam_step))
    for k in range(nseam):
        d = np.abs(((xs - k * seam_step + 4) % 8) - 4)
        seam = np.maximum(seam, np.clip(1 - d / 0.0045, 0, 1) * np.ones((H, 1)))
    for sy in (0.62, 1.42):
        d = np.abs(ys - sy)
        seam = np.maximum(seam, np.clip(1 - d / 0.003, 0, 1) * np.ones((1, W)) * 0.6)
    riv = np.zeros((H, W), np.float32)
    if rivets:
        rimg = Image.new('L', (W, H), 0)
        dr = ImageDraw.Draw(rimg)
        for k in range(nseam):
            for off in (-0.022, 0.022):
                cx = ((k * seam_step + off) / 8.0) * W
                for ry in np.arange(0.04, 2.0, 0.12):
                    cy = ry / 2.0 * H
                    dr.ellipse((cx - 1.2, cy - 1.2, cx + 1.2, cy + 1.2), fill=255)
        riv = np.asarray(rimg.filter(ImageFilter.GaussianBlur(0.7)), np.float32) / 255.0
    alb = alb * (1 - .30 * seam[..., None]) + .03 * riv[..., None]
    rain = noise_tile(H, W, 2, 400, seed + 21) * noise_tile(H, W, 4, 30, seed + 22)
    alb *= (1 - .06 * np.clip(rain - .35, 0, 1) * 3)[..., None]
    blot = fbm(H, W, 4, 16, 5, seed + 41)
    alb *= (1 - .14 * np.clip(blot - .55, 0, 1) * 3)[..., None]
    hm = height - .35 * gaussian(seam, 1.0) + .05 * riv + 0.02 * (mott - .5)
    n = normal_from_height(hm, 6.0)
    rough = np.clip(.40 + .10 * streak + .12 * np.clip(blot - .5, 0, 1) * 2 + .15 * seam, 0, 1)
    ao = 1 - .5 * gaussian(seam, 1.6)
    save(alb, name + '_c.jpg', 88); save(n, name + '_n.jpg', 90)
    save(orm(ao, rough, np.full((H, W), .22, np.float32)), name + '_orm.jpg', 88)


def gaussian(a, r):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r))
    return np.asarray(im, np.float32) / 255.0


# ----------------------------------------------------------------- metals reused (roof/underframe)
def gen_metals():
    S = 1024
    c = load('Metal061B', 'Color', (S, S)) * np.array([.70, .72, .74])
    c = np.clip(c * 1.15, 0, 1)
    dirt = fbm(S, S, 3, 3, 4, 88)
    c *= (0.85 + 0.25 * dirt)[..., None]
    save(c, 'roof_c.jpg'); save(load('Metal061B', 'NormalGL', (S, S)), 'roof_n.jpg', 92)
    r = load('Metal061B', 'Roughness', (S, S), gray=True)
    save(orm(np.ones((S, S), np.float32), np.clip(r * .4 + .5, 0, 1), np.full((S, S), .05, np.float32)), 'roof_orm.jpg')
    c = load('Metal063', 'Color', (S, S)) * np.array([.42, .40, .38])
    dirt = fbm(S, S, 4, 4, 5, 77)
    c *= (0.75 + 0.5 * dirt)[..., None]
    save(c, 'under_c.jpg'); save(load('Metal063', 'NormalGL', (S, S)), 'under_n.jpg', 92)
    r = load('Metal063', 'Roughness', (S, S), gray=True)
    mt = load('Metal063', 'Metalness', (S, S), gray=True)
    save(orm(np.ones((S, S), np.float32), np.clip(r * .8 + .25, 0, 1), mt * .8), 'under_orm.jpg')


# ----------------------------------------------------------------- floor
def gen_floor():
    S = 1024
    c = load('Rubber001', 'Color', (S, S))
    c = np.clip(c * 1.9 + .07, 0, 1) * np.array([.86, .90, .98])     # dark speckled lino, blue-grey
    # subtle ribs (fine longitudinal grooves every 12 mm) for the tread look
    ys = np.arange(S)[:, None] / S * 1.0
    ribs = (np.sin(ys * 2 * np.pi * 83) * .5 + .5)
    c *= (0.93 + 0.07 * ribs)[..., None]
    hm = load('Rubber001', 'Roughness', (S, S), gray=True) * .15 + ribs * .06
    n = blend_normals(load('Rubber001', 'NormalGL', (S, S)), normal_from_height(hm + 0 * np.zeros((S, S)), 3.0))
    save(c, 'floor_c.jpg'); save(n, 'floor_n.jpg', 82)
    r = load('Rubber001', 'Roughness', (S, S), gray=True)
    save(orm(np.ones((S, S), np.float32), np.clip(r * .6 + .35, 0, 1), np.zeros((S, S), np.float32)), 'floor_orm.jpg')


# ----------------------------------------------------------------- laminate wall lining (1 m tile)
def gen_laminate():
    S = 1024
    base = np.array([.80, .79, .74])
    sp = noise_tile(S, S, 200, 200, 3)
    grain = noise_tile(S, S, 4, 300, 4) * .5 + noise_tile(S, S, 8, 120, 8) * .5
    c = base[None, None] * (0.95 + .06 * sp[..., None] + .05 * grain[..., None])
    mott = fbm(S, S, 3, 3, 3, 12)
    c *= (0.96 + .08 * mott)[..., None]
    # thin panel seams at 0.5 m
    seam = np.zeros((S, S), np.float32)
    for k in (0, S // 2):
        seam[:, k:k + 2] = 1
    seam = np.maximum(seam, seam.T)
    c *= (1 - .35 * seam)[..., None]
    hm = grain * .03 + sp * .01 - seam * .04
    save(c, 'laminate_c.jpg'); save(normal_from_height(hm, 5), 'laminate_n.jpg', 90)
    save(orm(1 - .5 * seam, np.clip(.42 + .12 * sp, 0, 1), np.zeros((S, S), np.float32)), 'laminate_orm.jpg')


# ----------------------------------------------------------------- ceiling panels (1 m x 1 m)
def gen_ceiling():
    S = 1024
    c = np.ones((S, S, 3), np.float32) * np.array([.86, .86, .84])
    mott = fbm(S, S, 3, 3, 3, 31)
    c *= (0.96 + .07 * mott)[..., None]
    hm = np.zeros((S, S), np.float32)
    mask = np.zeros((S, S), np.float32)
    # panel seams
    for k in (0, 1):
        mask[:, k * (S - 3): k * (S - 3) + 3] = 1
        mask[k * (S - 3): k * (S - 3) + 3, :] = 1
    # perforated vent band: v in [0.30,0.62]
    img = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(img)
    for row in range(8):
        y = int(S * .28 + row * S * .045)
        for col in range(0, 24):
            x = int(S * .06 + col * S * .04)
            d.rounded_rectangle((x, y, x + int(S * .025), y + int(S * .012)), 3, fill=255)
    vents = np.asarray(img, np.float32) / 255.0
    c = c * (1 - .75 * vents[..., None]) * (1 - .35 * mask[..., None])
    hm = -0.6 * vents - .25 * mask
    save(c, 'ceiling_c.jpg'); save(normal_from_height(gaussian(hm * -1, .8) * -1, 4), 'ceiling_n.jpg', 90)
    save(orm(1 - .7 * vents - .3 * mask, np.clip(.5 + .25 * vents, 0, 1), np.zeros((S, S), np.float32)), 'ceiling_orm.jpg')


# ----------------------------------------------------------------- hazard stripe, door inner
def gen_safety():
    S = 256
    yy, xx = np.mgrid[0:S, 0:S]
    st = (((xx + yy) // 32) % 2).astype(np.float32)
    c = np.zeros((S, S, 3), np.float32)
    c[st > .5] = (.95, .78, .05); c[st <= .5] = (.05, .05, .05)
    save(c * np.array([1, 1, 1]), 'safety_c.jpg')
    save(np.full((S, S, 3), (.5, .5, 1.0), np.float32), 'safety_n.jpg', 90)
    save(orm(np.ones((S, S), np.float32), np.full((S, S), .55, np.float32), np.zeros((S, S), np.float32)), 'safety_orm.jpg')


def gen_door_inner():
    """unique per-leaf texture: 0.66 m x 1.8 m, 512 x 1024. Meeting edge (hazard band) at u = 1.0 (right)"""
    W, H = 512, 1024
    base = np.array([.72, .72, .70])
    n = fbm(H, W, 6, 3, 4, 91)
    c = np.ones((H, W, 3), np.float32) * base * (0.95 + .08 * n[..., None])
    # darker kick plate at the bottom, scuffs
    yy = np.arange(H)[:, None] / H
    c *= (1 - .25 * np.clip(1 - yy / .10, 0, 1))[..., None] if False else 1
    kick = np.clip((yy - .90) / .05, 0, 1)
    c = c * (1 - .28 * kick[..., None])
    scuff = fbm(H, W, 10, 6, 4, 92)
    c *= (1 - .18 * np.clip(scuff - .55, 0, 1) * 3 * (yy > .55))[..., None]
    # hazard band at the meeting edge (u > 0.90), and a thin one on the leading top edge omitted
    im = Image.fromarray((np.clip(c, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    x0 = int(W * .90)
    band = Image.new('RGB', (W - x0, H))
    bd = ImageDraw.Draw(band)
    bd.rectangle((0, 0, W - x0, H), fill=(240, 200, 10))
    for k in range(-2, H // 24 + 2):
        bd.polygon([(0, k * 48), (W - x0, k * 48 - (W - x0)), (W - x0, k * 48 - (W - x0) + 24), (0, k * 48 + 24)], fill=(15, 15, 15))
    im.paste(band, (x0, 0))
    # window frame outline (black), window at u .12-.80, v .16-.62 (matches make_train leaf)
    d.rounded_rectangle((int(W * .08), int(H * .12), int(W * .82), int(H * .64)), 12, outline=(30, 30, 32), width=8)
    arr = np.asarray(im, np.float32) / 255.0
    save(arr, 'door_inner_c.jpg')
    save(normal_from_height(scuff * .02, 3), 'door_inner_n.jpg', 90)
    save(orm(np.ones((H, W), np.float32), np.clip(.45 + .2 * scuff, 0, 1), np.zeros((H, W), np.float32)), 'door_inner_orm.jpg')


# ----------------------------------------------------------------- line diagram strip (3.0 m x 0.19 m -> 2048 x 128)
def gen_linemap():
    W, H = 2048, 128
    im = Image.new('RGB', (W, H), (245, 245, 240))
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(FONT_R, 15)
    fb = ImageFont.truetype(FONT, 17)
    d.rectangle((0, 0, W - 1, H - 1), outline=(200, 200, 195), width=3)
    linecol = (0, 114, 188)
    yl = 68
    d.rectangle((60, yl - 8, W - 60, yl + 8), fill=linecol)
    names = ['Northgate', 'Kings Row', 'Marlow', 'Elm Jct', 'Harbour', 'Westbrook', 'Oakfield',
             'Cannon Hill', 'Riverside', 'St Aldwyn', 'Brook Grn', 'Southfld', 'Lea Bridge', 'Abbots Xg']
    n = len(names)
    for i, nm in enumerate(names):
        x = 100 + i * (W - 200) / (n - 1)
        d.ellipse((x - 10, yl - 10, x + 10, yl + 10), fill=(255, 255, 255), outline=(20, 20, 20), width=3)
        if i in (3, 8):   # interchange
            d.ellipse((x - 13, yl - 13, x + 13, yl + 13), outline=(20, 20, 20), width=3)
        tw = d.textlength(nm, font=f)
        txt = Image.new('RGBA', (int(tw) + 4, 30), (0, 0, 0, 0))
        ImageDraw.Draw(txt).text((2, 0), nm, font=f, fill=(20, 20, 20, 255))
        txt = txt.rotate(22 if i % 2 == 0 else -22, expand=True, resample=Image.BICUBIC)
        px = int(x - 4) if i % 2 == 0 else int(x - 4)
        py = int(yl - 12 - txt.height) if i % 2 == 0 else int(yl + 10)
        im.paste(txt, (px, py), txt)
    d.text((16, 10), 'LINE', font=fb, fill=linecol)
    arr = np.asarray(im, np.float32) / 255.0
    save(arr, 'linemap_c.jpg', 92)
    save(np.full((H, W, 3), (.5, .5, 1), np.float32), 'linemap_n.jpg', 80)
    save(orm(np.ones((H, W), np.float32), np.full((H, W), .5, np.float32), np.zeros((H, W), np.float32)), 'linemap_orm.jpg', 80)


# ----------------------------------------------------------------- priority sign
def gen_priority_sign():
    S = 256
    im = Image.new('RGBA', (S, S), (235, 235, 232, 255))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((4, 4, S - 5, S - 5), 26, fill=(30, 70, 150, 255), outline=(240, 240, 240, 255), width=5)
    W = (245, 245, 245, 255)

    def person(cx, cy, s, cane=False, bump=False, bend=False):
        d.ellipse((cx - 11 * s, cy - 58 * s, cx + 11 * s, cy - 36 * s), fill=W)
        body = [(cx - 13 * s, cy - 32 * s), (cx + 13 * s, cy - 32 * s), (cx + 15 * s, cy + 8 * s), (cx - 15 * s, cy + 8 * s)]
        d.polygon(body, fill=W)
        d.rectangle((cx - 12 * s, cy + 6 * s, cx - 3 * s, cy + 46 * s), fill=W)
        d.rectangle((cx + 3 * s, cy + 6 * s, cx + 12 * s, cy + 46 * s), fill=W)
        if cane:
            d.line((cx + 30 * s, cy - 8 * s, cx + 30 * s, cy + 48 * s), fill=W, width=int(5 * s))
            d.arc((cx + 22 * s, cy - 18 * s, cx + 38 * s, cy - 2 * s), 180, 360, fill=W, width=int(5 * s))
            d.line((cx + 15 * s, cy - 24 * s, cx + 30 * s, cy - 8 * s), fill=W, width=int(6 * s))
        if bump:
            d.ellipse((cx - 4 * s, cy - 24 * s, cx + 26 * s, cy + 6 * s), fill=W)
    person(72, 100, 1.05, cane=True)
    person(180, 100, 1.05, bump=True)
    d.text((S // 2, 218), 'PLEASE OFFER THIS SEAT', font=ImageFont.truetype(FONT, 15), fill=W, anchor='mm')
    im.convert('RGB').save(os.path.join(OUT, 'priority_sign_c.jpg'), quality=92)


# ----------------------------------------------------------------- adverts (abstract, unbranded placeholders)
def gen_adverts():
    W, H = 1024, 256
    rng = np.random.RandomState(4)
    for i, (a, b, acc) in enumerate([((250, 190, 60), (220, 80, 60), (40, 40, 80)),
                                      ((60, 150, 200), (20, 60, 120), (250, 240, 200)),
                                      ((110, 180, 120), (30, 100, 90), (250, 230, 120)),
                                      ((230, 120, 150), (120, 40, 110), (255, 245, 235))]):
        yy, xx = np.mgrid[0:H, 0:W]
        t = (xx / W * .7 + yy / H * .3)[..., None]
        c = (np.array(a) * (1 - t) + np.array(b) * t) / 255.0
        im = Image.fromarray((c * 255).astype(np.uint8))
        d = ImageDraw.Draw(im)
        for k in range(9):
            r = rng.randint(30, 150); cx = rng.randint(0, W); cy = rng.randint(0, H)
            col = tuple(int(v * rng.uniform(.7, 1.1)) for v in acc)
            d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=col + (0,), width=6) if False else d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=tuple(min(255, v) for v in col), width=5)
        d.rectangle((0, H - 52, W, H), fill=tuple(int(v * .35) for v in b))
        d.text((W // 2, H - 26), 'ADVERT SPACE %d' % i, font=ImageFont.truetype(FONT, 30), fill=(250, 250, 250), anchor='mm')
        im.save(os.path.join(OUT, 'advert_%d_c.jpg' % i), quality=88)


# ----------------------------------------------------------------- destination display (emissive, dot-matrix look)
def gen_dest():
    W, H = 512, 96
    im = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(im)
    d.text((W // 2, H // 2), 'NOT IN SERVICE', font=ImageFont.truetype(FONT, 42), fill=255, anchor='mm')
    a = np.asarray(im.resize((-(-W // 3), -(-H // 3)), Image.BILINEAR), np.float32) / 255.0
    # dot matrix: each source pixel -> 3x3 cell with a round dot
    dot = np.zeros((3, 3), np.float32); dot[1, 1] = 1; dot[0, 1] = dot[1, 0] = dot[2, 1] = dot[1, 2] = .5
    big = np.kron(a, dot)
    big = big[:H, :W]
    col = np.zeros((H, W, 3), np.float32)
    col[..., 0] = big * 1.0; col[..., 1] = big * .62; col[..., 2] = big * .08
    col += .015
    save(col, 'dest_c.jpg', 92)


# ----------------------------------------------------------------- pole / grime overlay: none needed (plain materials)
if __name__ == '__main__':
    todo = sys.argv[1:] or ['moquette', 'body', 'body_ss', 'metals', 'floor', 'laminate', 'ceiling', 'safety', 'door_inner',
                            'linemap', 'priority', 'adverts', 'dest']
    fns = dict(moquette=gen_moquette, body=gen_body, body_ss=lambda: gen_body('body_ss', (.86, .87, .88), 2.66, False, 15), metals=gen_metals, floor=gen_floor, laminate=gen_laminate,
               ceiling=gen_ceiling, safety=gen_safety, door_inner=gen_door_inner, linemap=gen_linemap,
               priority=gen_priority_sign, adverts=gen_adverts, dest=gen_dest)
    for t in todo:
        print('gen', t, flush=True)
        fns[t]()
    print('done ->', OUT)
