#!/usr/bin/env python3
"""Joins build/sweep_<station>_<1-4>.png (tests/split_sweep_test.gd) into build/sweep_<station>.png, a 2 x 2 sheet at half size.  usage: tools/sweep_montage.py Station_Name [...]"""
import sys, os
from PIL import Image
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build")
for tag in sys.argv[1:]:
    ims = []
    for n in range(1, 5):
        p = os.path.join(root, "sweep_%s_%d.png" % (tag, n))
        if os.path.exists(p):
            ims.append(Image.open(p).convert("RGB"))
    if not ims:
        continue
    w, h = ims[0].size
    sheet = Image.new("RGB", (w, h))
    for i, im in enumerate(ims):
        sheet.paste(im.resize((w // 2, h // 2)), ((i % 2) * (w // 2), (i // 2) * (h // 2)))
    sheet.save(os.path.join(root, "sweep_%s.png" % tag))
    print("wrote", tag)
