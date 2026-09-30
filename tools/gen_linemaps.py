#!/usr/bin/env python3
"""Line-diagram strips for the carriage interiors (the map above the doors). Output: assets/textures/linemaps/<line>_<dir>.png
The strip is mapped onto a 1.3 x 0.13 m quad (10:1, tools/blender/train/make_train.py), so it is drawn 4096 x 410 and every name is set
vertically under the line, fitted to the space below it: a long name is shrunk, then abbreviated, and only truncated (with an ellipsis,
never clipped mid-letter) as a last resort.
Run: build/venv/bin/python tools/gen_linemaps.py"""
import json
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
net = json.load(open(os.path.join(ROOT, "data", "network.json")))
OUT = os.path.join(ROOT, "assets", "textures", "linemaps")
os.makedirs(OUT, exist_ok=True)
FONT = os.path.join(ROOT, "assets", "fonts", "Barlow-SemiBold.ttf")
FONT_B = os.path.join(ROOT, "assets", "fonts", "Barlow-Bold.ttf")
W, H = 4096, 410
ABBR = [("Street", "St"), ("Road", "Rd"), ("Square", "Sq"), ("Station", "Stn"), ("Park", "Pk"), ("Terminal", "T"), ("Terminals", "T"), ("Junction", "Jn"),
        ("Central", "Ctrl"), ("Broadway", "B'way"), ("Gardens", "Gdns"), ("Market", "Mkt"), ("Hill", "Hl"), ("North", "N"), ("South", "S"), ("West", "W"), ("East", "E")]


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def clean(n):
    return n.replace(" (H&C)", "").replace(" (D&P)", "").replace(" (Circle)", "")


def fit_label(d, name, max_len, max_fs, min_fs=16):
    """(text, font size) such that the vertical text is at most max_len long: shrink, then abbreviate, then truncate with an ellipsis"""
    cands = [name]
    short = name
    for a, b in ABBR:
        if a in short.split():
            short = " ".join(b if w == a else w for w in short.split())
            cands.append(short)
            if d.textlength(short, font=ImageFont.truetype(FONT, min_fs)) <= max_len:
                break
    for text in cands:
        fs = max_fs
        while fs >= min_fs:
            f = ImageFont.truetype(FONT, fs)
            if d.textlength(text, font=f) <= max_len:
                return text, fs
            fs -= 2
    text = cands[-1]
    f = ImageFont.truetype(FONT, min_fs)
    while text and d.textlength(text + "…", font=f) > max_len:
        text = text[:-1]
    return text.rstrip() + "…", min_fs


for lid, line in net["lines"].items():
    svc = max(line["services"], key=lambda s: len(s["stops"]))
    stops = [clean(net["stations"][s]["name"]) for s in svc["stops"]]
    inter = [len(net["stations"][s]["lines"]) > 1 for s in svc["stops"]]
    col = hexrgb(line["color"])
    for direction in (0, 1):
        names = stops if direction == 0 else stops[::-1]
        ints = inter if direction == 0 else inter[::-1]
        img = Image.new("RGB", (W, H), (247, 247, 245))
        d = ImageDraw.Draw(img)
        n = len(names)
        margin = 70
        title_h = 62
        y = title_h + 38                                             # the line
        d.rectangle([margin - 30, y - 9, W - margin + 30, y + 9], fill=col)
        step = (W - 2 * margin) / max(1, n - 1)
        max_fs = max(18, min(40, int(step * 0.56)))
        avail = H - (y + 30) - 10                                    # vertical room below the line for a name
        # title: line name and direction
        title = "%s line" % line["name"]
        d.text((margin - 20, 6), title, font=ImageFont.truetype(FONT_B, 46), fill=col if sum(col) < 560 else (90, 90, 90))
        tw = d.textlength(title, font=ImageFont.truetype(FONT_B, 46))
        d.text((margin - 20 + tw + 40, 14), "towards %s" % names[-1], font=ImageFont.truetype(FONT, 34), fill=(60, 60, 70))
        for i, nm in enumerate(names):
            x = margin + i * step
            r = 17 if ints[i] else 11
            d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255), outline=(20, 20, 20), width=4 if ints[i] else 3)
            text, fs = fit_label(d, nm, avail, max_fs)
            font = ImageFont.truetype(FONT_B if ints[i] else FONT, fs)
            tlen = int(d.textlength(text, font=font))
            lab = Image.new("RGBA", (tlen + 8, fs + 10), (0, 0, 0, 0))
            ImageDraw.Draw(lab).text((4, 2), text, font=font, fill=(0, 0, 0) if ints[i] else (22, 24, 70))
            lab = lab.rotate(-90, expand=True, resample=Image.BICUBIC)        # reads downward from the station dot
            img.paste(lab, (int(x - lab.width / 2), y + 24), lab)
        img.save(os.path.join(OUT, f"{lid}_{direction}.png"))
print("wrote", len([f for f in os.listdir(OUT) if f.endswith(".png")]), "strips", (W, H))
