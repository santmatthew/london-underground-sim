#!/usr/bin/env python3
"""Tileable PBR texture sets for the station props (512 px, JPEG): assets/textures/props/tile/<set>_{c,n,orm}.jpg
run with build/venv/bin/python.   c = sRGB albedo, n = OpenGL normal, orm = R:AO G:roughness B:metal (glTF packing)."""
import os, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
OUT = os.path.join(ROOT, 'assets', 'textures', 'props', 'tile')
S = 512


def u8(a):
    return (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)


def save(name, color, normal, orm, size=None):
    os.makedirs(OUT, exist_ok=True)
    def im(a):
        i = Image.fromarray(u8(a))
        return i.resize((size, size), Image.LANCZOS) if size else i
    im(color).save(os.path.join(OUT, name + '_c.jpg'), quality=90, subsampling=0)
    im(normal).save(os.path.join(OUT, name + '_n.jpg'), quality=92, subsampling=0)
    im(orm).save(os.path.join(OUT, name + '_orm.jpg'), quality=90, subsampling=0)
    print('wrote tile set', name)


def blur(a, sy, sx):
    return ndi.gaussian_filter(a, (sy, sx), mode='wrap')


def noise(rng, sy, sx, size=S):
    """tileable gaussian-blurred white noise normalised to 0..1"""
    a = blur(rng.rand(size, size).astype(np.float32), sy, sx)
    a -= a.min(); a /= max(a.max(), 1e-6)
    return a


def fbm(rng, base, octaves=4, size=S, aniso=1.0):
    out = np.zeros((size, size), np.float32); amp = 1.0; tot = 0.0
    for o in range(octaves):
        s = base / (2 ** o)
        out += amp * (noise(rng, s, s * aniso, size) - 0.5)
        tot += amp; amp *= 0.5
    out /= tot
    out -= out.min(); out /= max(out.max(), 1e-6)
    return out


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx = -dx * strength; ny = dy * strength; nz = np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / l * .5 + .5, ny / l * .5 + .5, nz / l * .5 + .5], -1)


def scratches(rng, n, length_px, width=1.0, angle_spread=0.35, base_angle=0.0, size=S):
    """tileable random thin line scratches -> 0..1 mask"""
    m = Image.new('L', (size * 3, size * 3), 0)
    from PIL import ImageDraw
    d = ImageDraw.Draw(m)
    for _ in range(n):
        x = rng.uniform(0, size * 3); y = rng.uniform(0, size * 3)
        a = base_angle + rng.normal(0, angle_spread)
        l = rng.uniform(0.3, 1.0) * length_px
        d.line([(x, y), (x + np.cos(a) * l, y + np.sin(a) * l)], fill=int(rng.uniform(80, 255)), width=max(1, int(width)))
    a = np.asarray(m, np.float32) / 255.0
    # fold 3x3 into tile
    t = np.zeros((size, size), np.float32)
    for i in range(3):
        for j in range(3):
            t = np.maximum(t, a[i * size:(i + 1) * size, j * size:(j + 1) * size])
    return t


def rgb(r, g, b):
    return np.array([r, g, b], np.float32) / 255.0


# ------------------------------------------------------------------------------------------------ sets
def steel_brushed():
    """brushed stainless: fine streaks along U (x), fingerprints / grime, light scratches"""
    rng = np.random.RandomState(11)
    streak = blur(rng.rand(S, S).astype(np.float32), 0.5, 26)
    streak = (streak - streak.mean()) / streak.std()
    streak2 = blur(rng.rand(S, S).astype(np.float32), 0.35, 8)
    streak2 = (streak2 - streak2.mean()) / streak2.std()
    grime = fbm(rng, 90, 4)
    smudge = np.clip((fbm(rng, 24, 3, aniso=1.6) - 0.5) * 3.0 + 0.5, 0, 1)
    sc = scratches(rng, 90, 120, 1, 0.08, 0.0)
    height = 0.55 * streak + 0.35 * streak2 + 1.2 * sc
    n = normal_from_height(height * 0.02, 5.0)
    base = rgb(198, 200, 204)
    lum = 1.0 + 0.070 * streak + 0.045 * streak2 - 0.05 * (grime - 0.5) - 0.02 * smudge
    col = base[None, None, :] * lum[..., None]
    col = col * (1 - 0.12 * smudge[..., None] * np.array([0.0, 0.05, 0.12], np.float32)[None, None, :])
    col += sc[..., None] * 0.10
    rough = 0.27 + 0.06 * streak + 0.04 * streak2 + 0.035 * smudge + 0.03 * (grime - 0.5) + 0.08 * sc
    metal = np.clip(1.0 - 0.28 * np.clip((grime - 0.62) * 4, 0, 1), 0, 1)
    ao = np.ones((S, S), np.float32) * 0.98
    save('steel', col, n, np.stack([ao, np.clip(rough, 0.12, 0.9), metal], -1))


def charcoal():
    """charcoal powder coat: fine speckle, orange peel, scuffs revealing bright metal"""
    rng = np.random.RandomState(21)
    peel = fbm(rng, 5, 3)
    speck = rng.rand(S, S).astype(np.float32)
    speck = (speck > 0.985).astype(np.float32) * rng.rand(S, S).astype(np.float32)
    speck = blur(speck, 0.6, 0.6) * 3
    grime = fbm(rng, 70, 4)
    sc = scratches(rng, 60, 60, 1, 1.5, 0.0)
    sc = np.clip(sc * (rng.rand(S, S) > 0.4), 0, 1)
    sc = blur(sc, 0.5, 0.5) * 1.5
    height = 0.6 * peel + 0.3 * blur(rng.rand(S, S).astype(np.float32), 0.6, 0.6) - 0.6 * sc
    n = normal_from_height(height * 0.05, 3.0)
    base = rgb(48, 50, 54)
    lum = 1.0 + 0.16 * (peel - 0.5) + 0.35 * speck + 0.25 * (grime - 0.5)
    col = base[None, None, :] * lum[..., None] + sc[..., None] * 0.20
    rough = 0.52 + 0.10 * (peel - 0.5) + 0.12 * (grime - 0.5) - 0.18 * sc
    metal = np.clip(sc * 0.9, 0, 1)
    ao = np.ones((S, S), np.float32)
    save('charcoal', col, n, np.stack([ao, np.clip(rough, 0.2, 0.95), metal], -1), size=256)


def paint(name, rgb255, seed, wear=0.6, grime_amt=0.10, rough=0.34, peel_amt=1.0, shared=False):
    """glossy/satin enamel paint with orange peel, small chips and grime. shares normal/orm between colours."""
    rng = np.random.RandomState(seed)
    peel = fbm(rng, 6, 3)
    fine = blur(rng.rand(S, S).astype(np.float32), 0.8, 0.8)
    fine = (fine - fine.mean()) / fine.std()
    grime = fbm(rng, 60, 4)
    sc = scratches(rng, 50, 70, 1, 1.5, 0.0)
    sc = blur(sc, 0.5, 0.5) * 1.4
    chips = (rng.rand(S, S) > 0.9988).astype(np.float32)
    chips = np.clip(blur(chips, 1.6, 1.6) * 40, 0, 1)
    chips = chips * (fbm(rng, 40, 3) > 0.35)
    base = rgb(*rgb255)
    lum = 1.0 + 0.06 * (peel - 0.5) - grime_amt * (grime - 0.4) * 1.6
    col = base[None, None, :] * lum[..., None]
    col = col * (1 - 0.5 * wear * chips[..., None]) + 0.30 * wear * chips[..., None] * np.array([0.6, 0.6, 0.62], np.float32)
    col += sc[..., None] * 0.10 * wear
    height = 0.3 * peel_amt * peel + 0.08 * peel_amt * fine - 0.4 * chips - 0.2 * sc
    n = normal_from_height(height * 0.03, 3.0)
    rgh = rough + 0.05 * (peel - 0.5) * peel_amt + 0.12 * (grime - 0.4) + 0.12 * chips + 0.06 * sc
    ao = np.ones((S, S), np.float32)
    metal = np.clip(chips * 0.5, 0, 1)
    orm = np.stack([ao, np.clip(rgh, 0.1, 0.95), metal], -1)
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(u8(col)).resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, name + '_c.jpg'), quality=90, subsampling=0)
    if shared:
        Image.fromarray(u8(n)).resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, 'paint_n.jpg'), quality=92, subsampling=0)
        Image.fromarray(u8(orm)).resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, 'paint_orm.jpg'), quality=90, subsampling=0)
    print('wrote paint', name)


def timber():
    """oak/iroko-ish slat: long grain along U (x)"""
    rng = np.random.RandomState(31)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    warp = fbm(rng, 26, 3, aniso=8.0)
    rings = np.sin((yy / S * 30 + warp * 2.2) * 2 * np.pi)
    rings = 0.5 + 0.5 * rings
    rings = rings ** 1.6
    fibre = blur(rng.rand(S, S).astype(np.float32), 0.6, 30)
    fibre = (fibre - fibre.mean()) / fibre.std()
    pores = (blur(rng.rand(S, S).astype(np.float32), 0.5, 5) > 0.545).astype(np.float32)
    pores = blur(pores, 0.4, 1.2)
    stain = fbm(rng, 80, 3)
    light = rgb(176, 122, 72); dark = rgb(112, 68, 36)
    t = np.clip(0.55 * rings + 0.25 * (fibre * 0.3 + 0.5) + 0.3 * (stain - 0.5), 0, 1)
    col = dark[None, None, :] * (1 - t[..., None]) + light[None, None, :] * t[..., None]
    col *= (1.0 - 0.28 * pores[..., None])
    col *= (1.0 - 0.18 * (stain[..., None] - 0.4))
    height = 0.5 * fibre + 0.5 * rings - 1.2 * pores
    n = normal_from_height(height * 0.03, 4.0)
    rough = 0.58 + 0.08 * (fibre * 0.3) + 0.12 * (stain - 0.4) + 0.1 * pores
    ao = 1.0 - 0.5 * pores
    save('timber', col, n, np.stack([ao, np.clip(rough, 0.3, 0.95), np.zeros((S, S), np.float32)], -1))


def rubber():
    rng = np.random.RandomState(41)
    fine = blur(rng.rand(S, S).astype(np.float32), 0.7, 0.7)
    fine = (fine - fine.mean()) / fine.std()
    grime = fbm(rng, 60, 4)
    base = rgb(30, 31, 33)
    col = base[None, None, :] * (1.0 + 0.10 * fine[..., None] + 0.5 * (grime[..., None] - 0.5))
    n = normal_from_height(fine * 0.02, 3.0)
    rough = 0.80 + 0.06 * fine + 0.1 * (grime - 0.5)
    ao = np.ones((S, S), np.float32)
    save('rubber', col, n, np.stack([ao, np.clip(rough, 0.5, 1.0), np.zeros((S, S), np.float32)], -1), size=256)


def galv_perf():
    """not used tile: placeholder kept for future"""
    pass


def main():
    steel_brushed()
    charcoal()
    # paints share gloss maps (n/orm written by the last call under its own name; we then copy to shared names)
    paint('paint_blue', (16, 38, 150), 51, shared=True)
    paint('paint_white', (232, 232, 226), 52, grime_amt=0.16)
    paint('paint_red', (176, 20, 22), 53)
    paint('paint_yellow', (240, 190, 20), 54)
    paint('paint_grey', (120, 124, 130), 55, rough=0.45)
    paint('paint_navy', (14, 24, 62), 56, rough=0.4)
    timber()
    rubber()


if __name__ == '__main__':
    main()
