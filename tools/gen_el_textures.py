#!/usr/bin/env python3
"""Wall cladding of the Elizabeth line's platforms (photographs: Bond Street, Tottenham Court Road, Farringdon, Liverpool Street, Paddington, Woolwich) -> assets/textures/gen/el_panel, el_dark.
  el_panel  cream curved wall-and-ceiling panels with a fine round perforation (1.2 m wide panels, seams between them)           2.4 m a tile
  el_dark   dark bronze-black wall panels of the box stations (Paddington, Woolwich ...), with the vertical seams between them     2.4 m a tile
  python3 tools/gen_el_textures.py      then tools/fix_texture_imports.py + godot --headless --import"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_textures as gt          # noqa: E402


def panel(name="el_panel", size=1024, seed=81):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    pw = size // 2                                   # a panel is 1.2 m wide
    u = xx % pw
    seam = (np.minimum(u, pw - 1 - u) < 4) | ((yy % size) < 4)
    # perforation: a grid of small round holes (pitch about 2.2 cm), only on every other panel and only inside a 6 cm margin
    pitch = 9.4
    gx = (xx % pitch) - pitch / 2
    gy = (yy % pitch) - pitch / 2
    hole = (gx * gx + gy * gy) < (2.7 ** 2)
    perf_panel = ((xx // pw) % 2 == 0)
    margin = (np.minimum(u, pw - 1 - u) > 26) & (yy > 26) & (yy < size - 26)
    holes = hole & perf_panel & margin
    n1 = gt.tileable_noise((size, size), 60, rng, 3)
    base = 0.86 + 0.05 * n1
    col = np.stack([base * 1.0, base * 0.975, base * 0.90], -1)
    col = np.where(holes[..., None], col * 0.38, col)
    col = np.where(seam[..., None], col * 0.55, col)
    rough = np.where(holes, 0.9, 0.48).astype(np.float32)
    ao = np.where(holes, 0.45, np.where(seam, 0.55, 1.0)).astype(np.float32)
    height = np.where(holes, -1.0, 0.0) + np.where(seam, -0.7, 0.0)
    gt.save(name, col.astype(np.float32), rough, ao, height.astype(np.float32), 2.4, normal_strength=2.2)


def dark(name="el_dark", size=1024, seed=83):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    pw = size // 2
    u = xx % pw
    seam = (np.minimum(u, pw - 1 - u) < 3)
    seam_h = ((yy % (size // 2)) < 3)
    n1 = gt.tileable_noise((size, size), 50, rng, 3)
    n2 = gt.tileable_noise((size, size), 8, rng, 2)
    base = 0.055 + 0.03 * n1 + 0.012 * n2
    col = np.stack([base * 1.06, base * 1.0, base * 0.94], -1)
    col = np.where((seam | seam_h)[..., None], col * 0.4, col)
    rough = (0.42 + 0.2 * n2).astype(np.float32)
    ao = np.where(seam | seam_h, 0.6, 1.0).astype(np.float32)
    height = np.where(seam | seam_h, -0.8, 0.0) + 0.1 * n2
    gt.save(name, col.astype(np.float32), rough, ao, height.astype(np.float32), 2.4, normal_strength=1.4)


if __name__ == "__main__":
    panel()
    dark()
