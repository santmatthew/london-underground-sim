#!/usr/bin/env python3
"""Ground textures for the scenery of open-air stretches (cuttings, embankments, railway land): grass, earth, gravel.
  build/venv/bin/python tools/gen_ground_textures.py [grass|earth|gravel]
Output: assets/textures/gen/<name>/{Color,NormalGL,Roughness,AO}.png (see gen_textures.save). Then `python3 tools/fix_texture_imports.py` and `godot --headless --path . --import`."""
import os
import sys
import numpy as np
from scipy import ndimage as ndi

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_textures import save, tileable_noise, smoothstep


def grass(name="grass", size=1024, seed=71):
    """2 m tile: rough railway-side grass, tufts and bare patches"""
    rng = np.random.default_rng(seed)
    broad = tileable_noise((size, size), 128, rng, 4)
    mid = tileable_noise((size, size), 24, rng, 3)
    blades = rng.random((size, size)).astype(np.float32)
    blades = ndi.gaussian_filter(blades, (0.6, 0.6))
    blades = (blades - blades.min()) / (blades.max() - blades.min() + 1e-6)
    patch = smoothstep(0.62, 0.78, tileable_noise((size, size), 96, rng, 3))       # dry, yellowish patches
    bare = smoothstep(0.80, 0.90, tileable_noise((size, size), 64, rng, 3))        # a little bare earth
    g = np.stack([0.15 + 0.10 * broad + 0.07 * blades, 0.27 + 0.16 * broad + 0.10 * blades, 0.07 + 0.04 * mid], -1)
    dry = np.stack([0.34 + 0.06 * mid, 0.31 + 0.06 * mid, 0.12 + 0.03 * mid], -1)
    earth = np.stack([0.24 + 0.05 * mid, 0.18 + 0.04 * mid, 0.11 + 0.03 * mid], -1)
    color = g * (1 - patch[..., None]) + dry * patch[..., None]
    color = color * (1 - bare[..., None]) + earth * bare[..., None]
    color *= (0.85 + 0.3 * mid)[..., None]
    rough = 0.88 + 0.1 * blades
    ao = 0.70 + 0.30 * blades
    height = ndi.gaussian_filter(blades * 0.6 + mid * 0.4, 0.8)
    save(name, color, rough, ao, height * 5.0, 2.0, normal_strength=1.8)


def earth(name="earth", size=1024, seed=72):
    """2 m tile: bank of clay and stones"""
    rng = np.random.default_rng(seed)
    broad = tileable_noise((size, size), 96, rng, 4)
    mid = tileable_noise((size, size), 20, rng, 3)
    fine = rng.random((size, size)).astype(np.float32)
    stones = (ndi.gaussian_filter(fine, 1.2) > np.percentile(ndi.gaussian_filter(fine, 1.2), 94)).astype(np.float32)
    stones = ndi.gaussian_filter(stones, 1.0)
    base = np.stack([0.30 + 0.10 * broad, 0.22 + 0.08 * broad, 0.14 + 0.05 * broad], -1)
    color = base * (0.8 + 0.4 * mid)[..., None]
    color = color * (1 - stones[..., None] * 0.6) + np.stack([0.38, 0.35, 0.31], -1) * (stones[..., None] * 0.6)
    rough = 0.93 - 0.1 * stones
    ao = 0.72 + 0.28 * (1 - mid * 0.5)
    height = ndi.gaussian_filter(mid * 0.5 + stones * 0.6 + fine * 0.1, 0.9)
    save(name, color, rough, ao, height * 6.0, 2.0, normal_strength=2.2)


def gravel(name="gravel", size=1024, seed=73):
    """1.5 m tile: path of crushed stone beside the track"""
    rng = np.random.default_rng(seed)
    mid = tileable_noise((size, size), 16, rng, 3)
    fine = rng.random((size, size)).astype(np.float32)
    grains = ndi.gaussian_filter(fine, 0.8)
    grains = (grains - grains.min()) / (grains.max() - grains.min() + 1e-6)
    v = 0.30 + 0.16 * grains + 0.08 * mid
    color = np.stack([v, v * 0.97, v * 0.92], -1)
    rough = 0.9 - 0.1 * grains
    ao = 0.7 + 0.3 * grains
    save(name, color, rough, ao, ndi.gaussian_filter(grains, 0.6) * 5.0, 1.5, normal_strength=2.0)


if __name__ == "__main__":
    only = sys.argv[1:]
    for fn, nm in ((grass, "grass"), (earth, "earth"), (gravel, "gravel")):
        if not only or nm in only:
            fn()
