#!/usr/bin/env python3
"""Private contact sheet of reference photos: ref_sheet.py out.png dir pattern-or-files... (6 per sheet, 3x2, filename labels)"""
import sys, os, glob
from PIL import Image, ImageDraw
out, d = sys.argv[1], sys.argv[2]
pats = sys.argv[3:]
files = []
for p in pats:
    files += sorted(glob.glob(os.path.join(d, p)))
files = files[:6]
W, H = 640, 480
sheet = Image.new("RGB", (W * 3, H * 2), (30, 30, 30))
dr = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB")
    im.thumbnail((W, H - 18))
    x, y = (i % 3) * W, (i // 3) * H
    sheet.paste(im, (x, y + 18))
    dr.text((x + 4, y + 3), os.path.basename(f)[:80], fill=(255, 255, 0))
sheet.save(out)
print(len(files), "images")
