#!/usr/bin/env python3
"""The lining of a running tunnel (the bore between stations): cast-iron segmental rings painted dark, 0.61 m wide, with raised flanges and bolts, the longitudinal joints staggered ring to ring,
rust and soot. One tile is 2.44 m (four rings) along the tunnel and 2.44 m round it -> assets/textures/gen/tunnel_lining/.
  python3 tools/gen_tunnel_textures.py      then tools/fix_texture_imports.py + godot --headless --import"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_textures as gt          # noqa: E402


def lining(name="tunnel_lining", size=1024, seed=71):
    rng = np.random.default_rng(seed)
    S = 2
    n = size * S
    ring = n // 4                         # 0.61 m
    seg = n // 2                          # 1.22 m of arc per segment
    flange = int(n * 0.030)               # 7.3 cm
    height = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(height)
    bolts = []
    # ring flanges: a raised strip along each ring joint (vertical in the texture: u runs along the tunnel)
    for k in range(4):
        x = k * ring
        d.rectangle([x - flange // 2, 0, x + flange // 2, n], fill=255)
        for j in range(0, n, n // 24):
            bolts.append((x, j + n // 48))
    # longitudinal joints, staggered ring by ring
    stag = [0.0, 0.5, 0.25, 0.75]
    for k in range(4):
        x0 = k * ring
        for m in range(2):
            y = int(((m + stag[k]) * seg) % n)
            d.rectangle([x0, y - flange // 2, x0 + ring, y + flange // 2], fill=255)
            for i in range(0, ring, ring // 6):
                bolts.append((x0 + i + ring // 12, y))
    # the panel face is slightly dished
    h = np.array(height, np.float32) / 255.0
    yy, xx = np.mgrid[0:n, 0:n]
    dish = np.zeros((n, n), np.float32)
    for k in range(4):
        x0 = k * ring
        for m in range(2):
            pass
    bolt_img = Image.new("L", (n, n), 0)
    bd = ImageDraw.Draw(bolt_img)
    for (bx, by) in bolts:
        r = int(n * 0.0085)
        bd.ellipse([bx - r, by - r, bx + r, by + r], fill=255)
    b = np.array(bolt_img, np.float32) / 255.0
    flat = (h > 0.5).astype(np.float32)
    # down to the final size
    def ds(a):
        im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)
        return np.array(im, np.float32) / 255.0
    flat = ds(flat)
    b = ds(b)
    n1 = gt.tileable_noise((size, size), 40, rng, 4)
    n2 = gt.tileable_noise((size, size), 10, rng, 3)
    streak = gt.tileable_noise((size, size), 120, rng, 2)
    streaks = np.clip((np.repeat(streak[:, :1] * 0 + 0, size, axis=1) + gt.tileable_noise((size, 1), 30, rng, 3).repeat(size, axis=1)), 0, 1)
    # paint: dark grey-brown, flanges a touch lighter (worn), rust where the paint has gone
    base = 0.20 + 0.08 * n1
    rust_mask = np.clip((n2 - 0.62) * 4.0, 0, 1) * (0.5 + 0.5 * streaks)
    soot = 0.55 + 0.45 * n1
    r = base * (1.0 + 0.45 * flat) * soot + rust_mask * 0.22
    g = base * (1.0 + 0.45 * flat) * soot * 0.97 + rust_mask * 0.10
    bl = base * (1.0 + 0.45 * flat) * soot * 0.92 + rust_mask * 0.04
    r = r + b * 0.08
    g = g + b * 0.08
    bl = bl + b * 0.08
    col = np.stack([r, g, bl], -1)
    rough = np.clip(0.82 - 0.2 * flat + 0.1 * rust_mask, 0, 1).astype(np.float32)
    ao = np.clip(0.55 + 0.45 * np.maximum(flat, 0.25) - 0.1 * (1 - n1), 0, 1).astype(np.float32)
    ht = flat * 1.0 + b * 0.6 + n2 * 0.15
    gt.save(name, col, rough, ao, ht, 2.44, normal_strength=3.0)


if __name__ == "__main__":
    lining()
