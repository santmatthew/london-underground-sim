#!/usr/bin/env python3
"""Make the generated 3D textures import as VRAM-compressed WITH mipmaps (Godot's default for textures loaded only from scripts is lossless, no mipmaps:
4x the memory, slow sampling and aliasing at a distance). Run after generating textures, then `godot --headless --path . --import`.
  python3 tools/fix_texture_imports.py"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DIRS = ["assets/textures/props/posters2", "assets/textures/props/gen2", "assets/textures/props/shops", "assets/textures/props/esc", "assets/textures/linemaps", "assets/textures/char/frieze", "assets/textures/char/giant", "assets/textures/char/motif", "assets/textures/char/open", "assets/textures/gen/ballast", "assets/textures/gen/brick_stock", "assets/textures/gen/brick_red", "assets/textures/gen/brick_blue", "assets/textures/char", "assets/textures/gen/metro_sq_grey", "assets/textures/gen/metro_oxford", "assets/textures/gen/floor_lozenge", "assets/textures/gen/floor_diamond_grey", "assets/textures/gen/floor_diamond_bw", "assets/textures/gen/floor_slab", "assets/textures/gen/floor_cream", "assets/textures/gen/floor_terracotta", "assets/textures/gen/floor_chequer", "assets/textures/gen/floor_stone", "assets/textures/gen/floor_slate", "assets/textures/gen/brick_buff", "assets/textures/gen/ceiling_metal"]
changed = 0
for d in DIRS:
    base = os.path.join(ROOT, d)
    if not os.path.isdir(base):
        continue
    for f in os.listdir(base):
        if not f.endswith(".png.import"):
            continue
        p = os.path.join(base, f)
        s = open(p).read()
        t = re.sub(r"compress/mode=\d+", "compress/mode=2", s)
        t = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", t)
        if f.startswith("NormalGL"):
            t = re.sub(r"compress/normal_map=\d+", "compress/normal_map=1", t)
        if t != s:
            open(p, "w").write(t)
            changed += 1
print("updated %d .import files" % changed)
