#!/usr/bin/env python3
"""Make the generated 3D textures import as VRAM-compressed WITH mipmaps (Godot's default for textures loaded only from scripts is lossless, no mipmaps:
4x the memory, slow sampling and aliasing at a distance). Run after generating textures, then `godot --headless --path . --import`.
  python3 tools/fix_texture_imports.py"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DIRS = ["assets/textures/props/posters2", "assets/textures/props/gen2", "assets/textures/props/shops", "assets/textures/props/esc", "assets/textures/linemaps"]
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
        if t != s:
            open(p, "w").write(t)
            changed += 1
print("updated %d .import files" % changed)
