#!/usr/bin/env python3
"""Line-diagram strips for the carriage interiors (the map above the doors). Output: assets/textures/linemaps/<line>_<dir>.png
Run: build/venv/bin/python tools/gen_linemaps.py"""
import json, os
from PIL import Image, ImageDraw, ImageFont
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
net = json.load(open(os.path.join(ROOT, "data", "network.json")))
OUT = os.path.join(ROOT, "assets", "textures", "linemaps")
os.makedirs(OUT, exist_ok=True)
FONT = os.path.join(ROOT, "assets", "fonts", "Barlow-SemiBold.ttf")
W, H = 2048, 158
def hexrgb(h): h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
for lid, line in net["lines"].items():
    svc = max(line["services"], key=lambda s: len(s["stops"]))
    stops = [net["stations"][s]["name"].replace(" (H&C)", "").replace(" (D&P)", "").replace(" (Circle)", "") for s in svc["stops"]]
    inter = [len(net["stations"][s]["lines"]) > 1 for s in svc["stops"]]
    col = hexrgb(line["color"])
    for direction in (0, 1):
        names = stops if direction == 0 else stops[::-1]
        ints = inter if direction == 0 else inter[::-1]
        img = Image.new("RGB", (W, H), (245, 245, 245))
        d = ImageDraw.Draw(img)
        n = len(names)
        margin = 70
        y = 52
        d.rectangle([margin - 20, y - 6, W - margin + 20, y + 6], fill=col)
        step = (W - 2 * margin) / max(1, n - 1)
        fs = max(13, min(26, int(step * 0.62)))
        font = ImageFont.truetype(FONT, fs)
        for i, nm in enumerate(names):
            x = margin + i * step
            r = 11 if ints[i] else 7
            d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255), outline=(20, 20, 20), width=3)
            # rotated label
            tw = int(d.textlength(nm, font=font))
            lab = Image.new("RGBA", (tw + 6, fs + 8), (0, 0, 0, 0))
            ImageDraw.Draw(lab).text((3, 1), nm, font=font, fill=(20, 20, 60) if not ints[i] else (0, 0, 0))
            lab = lab.rotate(-52, expand=True, resample=Image.BICUBIC)
            img.paste(lab, (int(x - 6), y + 16), lab)
        d.text((10, 6), f"{line['name']} line", font=ImageFont.truetype(FONT, 28), fill=col)
        img.save(os.path.join(OUT, f"{lid}_{direction}.png"))
print("wrote", len(os.listdir(OUT)), "strips")
