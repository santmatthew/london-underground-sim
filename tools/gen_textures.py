#!/usr/bin/env python3
"""Procedural PBR textures for the station: run with build/venv/bin/python tools/gen_textures.py
Output: assets/textures/gen/<name>/{Color,NormalGL,Roughness,AO}.png (+ info.txt with physical size in metres).
"""
import math
import os, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "textures", "gen")


def save(name, color, rough, ao, height, size_m, normal_strength=2.0, metal=None):
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    def u8(a): return (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(u8(color)).save(os.path.join(d, "Color.png"))
    Image.fromarray(u8(rough)).save(os.path.join(d, "Roughness.png"))
    Image.fromarray(u8(ao)).save(os.path.join(d, "AO.png"))
    # normal from height (OpenGL: +Y up)
    gy, gx = np.gradient(height)
    nx, ny, nz = -gx * normal_strength, gy * normal_strength, np.ones_like(height)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / l, ny / l, nz / l], -1) * 0.5 + 0.5
    Image.fromarray(u8(n)).save(os.path.join(d, "NormalGL.png"))
    if metal is not None:
        Image.fromarray(u8(metal)).save(os.path.join(d, "Metalness.png"))
    open(os.path.join(d, "info.txt"), "w").write(f"size_m={size_m}\n")
    print("wrote", name)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def tileable_noise(shape, scale, rng, octaves=4):
    """cheap tileable fractal noise via FFT-filtered random field"""
    h, w = shape
    out = np.zeros(shape, np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(1, int(scale / (2 ** o)))
        small = rng.random((max(2, h // s), max(2, w // s))).astype(np.float32)
        big = ndi.zoom(small, (h / small.shape[0], w / small.shape[1]), order=3, mode="wrap")[:h, :w]
        out += big * amp
        tot += amp
        amp *= 0.5
    out /= tot
    return (out - out.min()) / (out.max() - out.min() + 1e-6)


def metro_tile(name, base_rgb, size=2048, tile_w=256, tile_h=128, grout=3, seed=1, size_m=1.2, dirt=0.10, bond=True, gloss=0.16):
    """Glazed rectangular 'metro' tiles in brick bond (the classic London Underground wall)."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size]
    row = yy // tile_h
    xs = xx + (row % 2) * (tile_w // 2 if bond else 0)
    col = (xs // tile_w) % (size // tile_w)
    u = (xs % tile_w).astype(np.float32)
    v = (yy % tile_h).astype(np.float32)
    dist = np.minimum.reduce([u, tile_w - 1 - u, v, tile_h - 1 - v])          # px to tile edge
    bevel = smoothstep(grout * 0.5, grout * 0.5 + 9, dist)                     # 0 in grout, ramps to 1
    inside = smoothstep(grout * 0.5 - 0.5, grout * 0.5 + 1.0, dist)
    # per-tile variation
    ntile_r, ntile_c = size // tile_h, size // tile_w
    tv = rng.normal(0, 0.014, (ntile_r, ntile_c)).astype(np.float32)
    tt = rng.normal(0, 0.003, (ntile_r, ntile_c, 3)).astype(np.float32)
    tile_id_r, tile_id_c = row % ntile_r, col
    var = tv[tile_id_r, tile_id_c][..., None] + tt[tile_id_r, tile_id_c]
    base = np.array(base_rgb, np.float32)[None, None, :]
    glaze = base + var
    # glaze pooling: darker toward bevel edge, slight gradient across tile
    glaze *= (0.95 + 0.05 * bevel[..., None])
    # crazing / fine dirt specks + soft mottling
    mott = tileable_noise((size, size), 96, rng, 4)
    glaze *= (0.965 + 0.07 * mott[..., None])
    speck = (rng.random((size, size)) > 0.99985).astype(np.float32)
    speck = ndi.gaussian_filter(speck, 1.0) * 6
    glaze -= speck[..., None] * 0.12
    grout_col = np.array([0.60, 0.59, 0.55], np.float32)[None, None, :] * (0.85 + 0.3 * tileable_noise((size, size), 24, rng, 3))[..., None]
    color = glaze * inside[..., None] + grout_col * (1 - inside[..., None])
    # general grime (subtle): more in grout & random cloud
    cloud = tileable_noise((size, size), 256, rng, 5)
    color *= (1.0 - dirt * (cloud[..., None] ** 2))
    rough = gloss + 0.05 * mott + (1 - inside) * 0.65
    rough = np.clip(rough + 0.10 * (cloud ** 3), 0, 1)
    ao = 0.55 + 0.45 * smoothstep(0, grout * 1.6 + 3, dist)
    height = bevel * 0.9 + 0.1 * mott
    height = ndi.gaussian_filter(height, 0.8)
    save(name, color, rough, ao, height * 6.0, size_m, normal_strength=1.4)


def panel_cladding(name, base_rgb, size=2048, panel=(1024, 1024), gap=6, seed=2, size_m=2.0):
    """Large flat enamel panels with recessed joints (modern refit)."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size]
    pw, ph = panel
    u, v = (xx % pw).astype(np.float32), (yy % ph).astype(np.float32)
    dist = np.minimum.reduce([u, pw - 1 - u, v, ph - 1 - v])
    inside = smoothstep(gap * 0.4, gap * 0.4 + 2, dist)
    r, c = yy // ph, xx // pw
    tv = rng.normal(0, 0.012, (size // ph + 1, size // pw + 1)).astype(np.float32)
    mott = tileable_noise((size, size), 200, rng, 4)
    base = np.array(base_rgb, np.float32)[None, None, :]
    col = (base + tv[r, c][..., None]) * (0.975 + 0.05 * mott[..., None])
    joint = np.array([0.18, 0.18, 0.18], np.float32)[None, None, :]
    color = col * inside[..., None] + joint * (1 - inside[..., None])
    rough = 0.32 + 0.08 * mott + (1 - inside) * 0.5
    ao = 0.6 + 0.4 * smoothstep(0, gap * 1.5, dist)
    height = smoothstep(0, gap, dist) * 0.5
    save(name, color, rough, ao, ndi.gaussian_filter(height, 0.7) * 4, size_m, normal_strength=1.2)


def tactile_paving(name, size=1024, seed=3, size_m=0.6):
    """Yellow blister paving for the platform edge (dots on a 60 cm x 60 cm slab)"""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    pitch = size / 12.0
    cx = (xx % pitch) - pitch / 2
    cy = (yy % pitch) - pitch / 2
    r = np.sqrt(cx * cx + cy * cy)
    dome = np.clip(1 - (r / (pitch * 0.32)) ** 2, 0, 1) ** 0.5
    dome[r > pitch * 0.32] = 0
    mott = tileable_noise((size, size), 64, rng, 4)
    yellow = np.array([0.92, 0.72, 0.05], np.float32)
    color = yellow[None, None, :] * (0.85 + 0.2 * mott[..., None])
    color *= (1.0 - 0.35 * (tileable_noise((size, size), 16, rng, 3)[..., None] > 0.8))   # wear speckle
    color *= (0.75 + 0.25 * dome[..., None])
    rough = 0.55 + 0.25 * mott - 0.15 * dome
    ao = 1.0 - 0.3 * (1 - dome)
    save(name, color, rough, ao, ndi.gaussian_filter(dome, 1.0) * 5, size_m, normal_strength=2.5)


def trackbed_sleepers(name, size=1024, seed=6):
    """1.3 m x 1.3 m tile: ballast with two concrete sleepers (run across u; repeat along v every 0.65 m)"""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    v = (yy / size) % 1.0
    # sleeper bands: 0.25 m wide every 0.65 m  (tile = 1.3 m)
    per = 0.65 / 1.3
    ph = (v % per) / per
    band = smoothstep(0.02, 0.06, ph) * (1 - smoothstep(0.38, 0.42, ph))     # 0.4*0.65 = 0.26 m
    noise = tileable_noise((size, size), 24, rng, 4)
    fine = rng.random((size, size)).astype(np.float32)
    ballast = 0.10 + 0.14 * noise + 0.10 * (fine > 0.86)
    conc = 0.34 + 0.10 * tileable_noise((size, size), 64, rng, 3)
    val = ballast * (1 - band) + conc * band
    color = np.stack([val * 1.0, val * 0.98, val * 0.94], -1)
    rough = 0.9 - 0.15 * band
    ao = 0.75 + 0.25 * band
    height = ndi.gaussian_filter(band * 0.35 + 0.25 * fine * (1 - band), 1.0)
    save(name, color, rough, ao, height * 6.0, 1.3, normal_strength=1.6)


def decals(size=512, seed=11):
    """RGBA decals: stains, gum, scuffs, wall runs -> assets/textures/gen/decals/<name>.png"""
    rng = np.random.default_rng(seed)
    d = os.path.join(OUT, "decals")
    os.makedirs(d, exist_ok=True)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size
    def save_rgba(name, rgb, a):
        img = np.zeros((size, size, 4), np.uint8)
        img[..., :3] = (np.clip(rgb, 0, 1) * 255).astype(np.uint8)
        img[..., 3] = (np.clip(a, 0, 1) * 255).astype(np.uint8)
        Image.fromarray(img, "RGBA").save(os.path.join(d, name + ".png"))
    # stains: soft blotches
    for i in range(4):
        n = tileable_noise((size, size), 96 + i * 20, np.random.default_rng(seed + i), 4)
        r = np.sqrt((xx - 0.5) ** 2 + (yy - 0.5) ** 2)
        blob = np.clip((n - 0.45) * 4.0, 0, 1) * np.clip(1.0 - r * 2.0, 0, 1) ** 0.6
        base = np.array([0.10, 0.085, 0.07], np.float32)
        rgb = np.broadcast_to(base, (size, size, 3)) * (0.7 + 0.6 * n[..., None])
        save_rgba(f"stain_{i}", rgb, blob * (0.35 + 0.15 * i))
    # gum spots: many small discs
    a = np.zeros((size, size), np.float32)
    rgb = np.zeros((size, size, 3), np.float32)
    for k in range(70):
        cx, cy = rng.random(2)
        rad = rng.uniform(0.006, 0.014)
        m = ((xx - cx) ** 2 + (yy - cy) ** 2) < rad ** 2
        tone = rng.choice([0.62, 0.45, 0.78, 0.30])
        a[m] = 0.85
        rgb[m] = np.array([tone, tone * 0.98, tone * 0.95], np.float32)
    a = ndi.gaussian_filter(a, 1.0)
    save_rgba("gum", rgb, a)
    # scuffs: long thin dark streaks
    a = np.zeros((size, size), np.float32)
    for k in range(26):
        cx, cy = rng.random(2)
        ang = rng.uniform(-0.5, 0.5)
        ln = rng.uniform(0.05, 0.18)
        t = np.linspace(-ln, ln, 60)
        for tt in t:
            px = int((cx + tt * np.cos(ang)) * size) % size
            py = int((cy + tt * np.sin(ang)) * size) % size
            a[py, px] = 0.5 * (1 - abs(tt) / ln)
    a = ndi.gaussian_filter(a, 1.6) * 3.0
    save_rgba("scuff", np.full((size, size, 3), 0.06, np.float32), a)
    # wall run: vertical drips fading downward
    n = tileable_noise((size, size), 40, rng, 3)
    streak = ndi.gaussian_filter(n, (30, 1.2), mode="wrap")
    streak = (streak - streak.min()) / (streak.max() - streak.min())
    fade = np.clip(1.0 - yy * 1.1, 0, 1) ** 1.4
    a = np.clip((streak - 0.55) * 3.0, 0, 1) * fade * 0.55
    save_rgba("wall_run", np.broadcast_to(np.array([0.16, 0.14, 0.11], np.float32), (size, size, 3)), a)
    print("wrote decals")


def grime_mask(name, size=1024, seed=4):
    """tileable greyscale grime (vertical streaks + blotches) used by the surface shader"""
    rng = np.random.default_rng(seed)
    streak = tileable_noise((size, size), 48, rng, 3)
    streak = ndi.gaussian_filter(streak, (28, 1.5), mode="wrap")
    streak = (streak - streak.min()) / (streak.max() - streak.min())
    blot = tileable_noise((size, size), 160, rng, 5)
    m = np.clip(0.55 * streak + 0.45 * blot, 0, 1)
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    Image.fromarray((m * 255).astype(np.uint8)).save(os.path.join(d, "Grime.png"))
    print("wrote", name)


def chequer_tile(name, a_rgb, b_rgb, size=2048, tile=512, grout=4, seed=21, size_m=1.2):
    """black/white chequer floor (Brent Cross, many 1930s halls): square tiles alternating two colours"""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size]
    cx, cy = xx // tile, yy // tile
    odd = ((cx + cy) % 2).astype(np.float32)
    u = (xx % tile).astype(np.float32)
    v = (yy % tile).astype(np.float32)
    dist = np.minimum.reduce([u, tile - 1 - u, v, tile - 1 - v])
    inside = smoothstep(grout * 0.5 - 0.5, grout * 0.5 + 1.0, dist)
    mott = tileable_noise((size, size), 96, rng, 4)
    a = np.array(a_rgb, np.float32)[None, None, :]
    b = np.array(b_rgb, np.float32)[None, None, :]
    glaze = (a * (1 - odd[..., None]) + b * odd[..., None]) * (0.95 + 0.1 * mott[..., None])
    grout_col = np.array([0.45, 0.44, 0.42], np.float32)[None, None, :]
    color = glaze * inside[..., None] + grout_col * (1 - inside[..., None])
    cloud = tileable_noise((size, size), 256, rng, 5)
    color *= (1.0 - 0.10 * cloud[..., None] ** 2)
    rough = 0.28 + 0.1 * mott + (1 - inside) * 0.6
    ao = 0.6 + 0.4 * smoothstep(0, grout * 1.6 + 3, dist)
    save(name, color, np.clip(rough, 0, 1), ao, ndi.gaussian_filter(inside, 0.8) * 3, size_m, normal_strength=1.0)


def brick_wall(name, base_rgb, size=2048, brick_w=256, brick_h=89, mortar=8, seed=31, size_m=1.72):
    """facing brick in stretcher bond (215 x 65 mm bricks, 10 mm joints): the exposed brick of 1930s Holden halls"""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size]
    row = yy // brick_h
    xs = xx + (row % 2) * (brick_w // 2)
    col = xs // brick_w
    u = (xs % brick_w).astype(np.float32)
    v = (yy % brick_h).astype(np.float32)
    dist = np.minimum.reduce([u, brick_w - 1 - u, v, brick_h - 1 - v])
    inside = smoothstep(mortar * 0.5 - 0.5, mortar * 0.5 + 1.0, dist)
    nr, nc = size // brick_h + 2, size // brick_w + 2
    tv = rng.normal(0, 0.06, (nr, nc)).astype(np.float32)
    tt = rng.normal(0, 0.02, (nr, nc, 3)).astype(np.float32)
    r_i, c_i = row % nr, col % nc
    base = np.array(base_rgb, np.float32)[None, None, :]
    mott = tileable_noise((size, size), 40, rng, 4)
    face = (base + tv[r_i, c_i][..., None] + tt[r_i, c_i]) * (0.9 + 0.2 * mott[..., None])
    mortar_col = np.array([0.66, 0.64, 0.58], np.float32)[None, None, :]
    color = face * inside[..., None] + mortar_col * (1 - inside[..., None])
    cloud = tileable_noise((size, size), 256, rng, 5)
    color *= (1.0 - 0.12 * cloud[..., None] ** 2)
    rough = 0.75 + 0.15 * mott
    ao = 0.5 + 0.5 * smoothstep(0, mortar * 1.6 + 3, dist)
    height = smoothstep(0, mortar * 1.2, dist) * 0.8 + 0.2 * mott
    save(name, color, np.clip(rough, 0, 1), ao, ndi.gaussian_filter(height, 0.8) * 8.0, size_m, normal_strength=1.6)


def _hall_set():
    # hall and corridor finishes by era (halls/SPEC.md section 8): cream ceramic 300 mm, terracotta quarry 150 mm, grey stone 600 x 300, dark slate 600 x 300, brick, metal ceiling
    metro_tile("floor_cream", (0.86, 0.82, 0.68), tile_w=512, tile_h=512, grout=5, seed=41, dirt=0.10, bond=False, gloss=0.30)
    metro_tile("floor_terracotta", (0.68, 0.40, 0.30), tile_w=256, tile_h=256, grout=5, seed=42, dirt=0.12, bond=False, gloss=0.35)
    chequer_tile("floor_chequer", (0.10, 0.10, 0.11), (0.88, 0.86, 0.80))
    metro_tile("floor_stone", (0.66, 0.66, 0.67), tile_w=1024, tile_h=512, grout=4, seed=43, dirt=0.08, bond=True, gloss=0.25)
    metro_tile("floor_slate", (0.52, 0.53, 0.55), tile_w=1024, tile_h=512, grout=4, seed=44, dirt=0.08, bond=True, gloss=0.30)
    brick_wall("brick_buff", (0.76, 0.66, 0.48))
    panel_cladding("ceiling_metal", (0.62, 0.63, 0.65), panel=(512, 512), gap=5, seed=45, size_m=1.2)


def _all():
    metro_tile("metro_white", (0.93, 0.93, 0.91), seed=1, dirt=0.05)
    metro_tile("metro_cream", (0.90, 0.86, 0.74), seed=5, dirt=0.06)
    # Victoria line (1968-71): 150 mm square pale-grey glazed tile in stack bond (Idiom p.217)
    metro_tile("metro_sq_grey", (0.80, 0.81, 0.82), tile_w=256, tile_h=256, grout=4, seed=7, dirt=0.05, bond=False)
    panel_cladding("panel_white", (0.88, 0.89, 0.88))
    tactile_paving("tactile_yellow")
    trackbed_sleepers("trackbed_sleepers")
    _hall_set()
    decals()
    grime_mask("grime")


def oxford_circus_tile(name="metro_oxford"):
    """Oxford Circus Central line platforms: white glazed tile with a dark-blue interlace of braided outlined ribbons flowing up the wall.
    Re-uses the plain white tile's normal / roughness / AO and paints the ribbons into the colour map (period 1.2 m = one texture)."""
    import shutil
    from PIL import ImageDraw
    src = os.path.join(OUT, "metro_white")
    dst = os.path.join(OUT, name)
    os.makedirs(dst, exist_ok=True)
    for f in ("NormalGL.png", "Roughness.png", "AO.png"):
        shutil.copy(os.path.join(src, f), os.path.join(dst, f))
    open(os.path.join(dst, "info.txt"), "w").write("size_m=1.2\n")
    base = Image.open(os.path.join(src, "Color.png")).convert("RGB")
    size = base.width
    SS = 2
    layer = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ink = (22, 40, 130, 255)
    white = (255, 255, 255, 0)
    ncol = 3                                   # braids across the 1.2 m period
    lam = size * SS / 1.0                      # braid wavelength (px): two full turns per 1.2 m
    amp = size * SS / ncol * 0.22
    rw = size * SS / ncol * 0.085              # ribbon half width
    steps = 160
    for c in range(ncol):
        cx = (c + 0.5) * size * SS / ncol
        for seg in range(6):                   # sixth-wavelength segments: the strand on top rotates (a three-strand braid)
            y0 = seg * lam / 3.0
            order = [(seg + k) % 3 for k in range(3)]
            for strand in order:
                pts_l, pts_r = [], []
                for i in range(steps + 1):
                    t = i / steps
                    y = y0 + t * lam / 3.0
                    ph = 2 * math.pi * y / lam + strand * 2.0 * math.pi / 3.0
                    x = cx + amp * math.sin(ph)
                    pts_l.append((x - rw, y))
                    pts_r.append((x + rw, y))
                poly_pts = pts_l + pts_r[::-1]
                d.polygon(poly_pts, fill=(255, 255, 255, 255))             # ribbon body masks what lies under it
                d.line(pts_l, fill=ink, width=int(size * SS * 0.0075))
                d.line(pts_r, fill=ink, width=int(size * SS * 0.0075))
    layer = layer.resize((size, size), Image.LANCZOS)
    # keep the tile joints visible through the ribbons: only the ink is composited, the white body just hides nothing (base is white already)
    out = base.convert("RGBA")
    ink_only = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    la = np.array(layer).astype(np.float32)
    ink_mask = (np.abs(la[..., 0] - 22) + np.abs(la[..., 1] - 40) + np.abs(la[..., 2] - 130)) < 150
    arr = np.array(out)
    arr[ink_mask] = (np.array([20, 38, 128, 255]) * 0.9 + arr[ink_mask] * 0.1).astype(np.uint8)
    Image.fromarray(arr).convert("RGB").save(os.path.join(dst, "Color.png"))
    print("wrote", name)


if __name__ == "__main__":
    only = sys.argv[1:]
    if not only:
        _all()
    elif "oxford" in only:
        oxford_circus_tile()
    elif "halls" in only:
        _hall_set()
    elif "metro_sq_grey" in only:
        metro_tile("metro_sq_grey", (0.80, 0.81, 0.82), tile_w=256, tile_h=256, grout=4, seed=7, dirt=0.05, bond=False)
