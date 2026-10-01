#!/usr/bin/env python3
"""Station-character textures (assets/textures/char): the platform name frieze for every station, the "Way out" patches, the giant tile lettering of
the Leslie Green stations, and the Victoria line seat-recess motifs. Driven by data/station_character.json.
  python3 tools/gen_char_textures.py [friezes] [wayout] [giants] [motifs]     (no argument = all)
Run tools/fix_texture_imports.py and `godot --headless --path . --import` afterwards."""
import json
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "textures", "char")
SANS = os.path.join(ROOT, "assets", "fonts", "Barlow-SemiBold.ttf")
SANS_BOLD = os.path.join(ROOT, "assets", "fonts", "Barlow-Bold.ttf")
SERIF = "/usr/share/fonts/opentype/urw-base35/C059-Bold.otf"     # Century Schoolbook Bold: the nearest installed face to the Leslie Green tile lettering
PPM = 400                      # frieze pixels per metre
GIANT_PPM = 300                # giant lettering pixels per metre
CHAR = json.load(open(os.path.join(ROOT, "data", "station_character.json")))


def short_name(name):
    return re.sub(r"\s*\(.*?\)", "", name).strip()


def slug(name):
    return re.sub(r"[^a-z0-9]+", "_", short_name(name).lower()).strip("_")


def col255(c):
    return tuple(int(round(v * 255)) for v in c)


def station_names():
    d = json.load(open(os.path.join(ROOT, "data", "stations_real.json")))
    return sorted(set(short_name(v["name"]) for v in d.values()))


def fit_text(draw, text, font_path, cap_h, max_w, tracking):
    """largest font whose capital height is <= cap_h and whose tracked width fits max_w"""
    size = int(cap_h / 0.70)
    while size > 8:
        f = ImageFont.truetype(font_path, size)
        w = sum(draw.textlength(ch, font=f) for ch in text) + tracking * (len(text) - 1)
        if w <= max_w:
            return f, w
        size -= 2
    f = ImageFont.truetype(font_path, 8)
    return f, sum(draw.textlength(ch, font=f) for ch in text)


def draw_tracked(draw, xy, text, font, fill, tracking):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += draw.textlength(ch, font=font) + tracking


def friezes():
    """3.0 m x 0.30 m white enamel fascia panels carrying the station name in TfL blue capitals (Idiom p.121/130: name every 2-4 m)"""
    d = os.path.join(OUT, "frieze")
    os.makedirs(d, exist_ok=True)
    W, H = int(3.0 * PPM), int(0.30 * PPM)
    for name in station_names():
        im = Image.new("RGB", (W, H), (238, 239, 237))
        dr = ImageDraw.Draw(im)
        # panel shading: faint darker edge top and bottom, vertical seams
        for y in range(H):
            t = abs((y + 0.5) / H - 0.5) * 2
            sh = int(10 * t ** 3)
            dr.line([(0, y), (W, y)], fill=(238 - sh, 239 - sh, 237 - sh))
        dr.line([(0, 0), (0, H)], fill=(190, 192, 192), width=2)
        dr.line([(W - 2, 0), (W - 2, H)], fill=(190, 192, 192), width=2)
        text = name.upper()
        f, w = fit_text(dr, text, SANS, cap_h=int(H * 0.50), max_w=W * 0.86, tracking=int(H * 0.05))
        asc = f.getmetrics()[0]
        # centre on cap height
        bbox = dr.textbbox((0, 0), "H", font=f)
        cap = bbox[3] - bbox[1]
        y0 = (H - cap) / 2 - bbox[1]
        draw_tracked(dr, ((W - w) / 2, y0), text, f, (0, 26, 150), int(H * 0.05))
        im.save(os.path.join(d, slug(name) + ".png"), optimize=True)
    print("wrote %d friezes" % len(station_names()))


def wayout():
    """black "Way out" patches with yellow lettering and an arrow (left / right), 0.50 x 0.15 m"""
    d = os.path.join(OUT, "frieze")
    os.makedirs(d, exist_ok=True)
    W, H = int(0.50 * PPM), int(0.15 * PPM)
    for side in ("l", "r"):
        im = Image.new("RGBA", (W, H), (14, 14, 15, 255))
        dr = ImageDraw.Draw(im)
        f = ImageFont.truetype(SANS_BOLD, int(H * 0.52))
        txt = "Way out"
        tw = dr.textlength(txt, font=f)
        ah = H * 0.36                       # arrow
        gap = H * 0.18
        total = tw + gap + ah * 1.2
        x = (W - total) / 2
        ty = (H - f.size) / 2 - f.getbbox("W")[1] * 0.35
        yel = (255, 205, 0)
        cy = H / 2
        if side == "l":
            ax = x
            dr.polygon([(ax, cy), (ax + ah * 0.6, cy - ah * 0.55), (ax + ah * 0.6, cy - ah * 0.2), (ax + ah * 1.2, cy - ah * 0.2),
                        (ax + ah * 1.2, cy + ah * 0.2), (ax + ah * 0.6, cy + ah * 0.2), (ax + ah * 0.6, cy + ah * 0.55)], fill=yel)
            dr.text((x + ah * 1.2 + gap, ty), txt, font=f, fill=yel)
        else:
            dr.text((x, ty), txt, font=f, fill=yel)
            ax = x + tw + gap
            dr.polygon([(ax + ah * 1.2, cy), (ax + ah * 0.6, cy - ah * 0.55), (ax + ah * 0.6, cy - ah * 0.2), (ax, cy - ah * 0.2),
                        (ax, cy + ah * 0.2), (ax + ah * 0.6, cy + ah * 0.2), (ax + ah * 0.6, cy + ah * 0.55)], fill=yel)
        im.convert("RGB").save(os.path.join(d, "wayout_%s.png" % side), optimize=True)
    print("wrote way-out patches")


def giants():
    """tile-lettering station names (RGBA, GIANT_PPM px/m, letters 0.42 m tall) with the tile joints cut through them"""
    d = os.path.join(OUT, "giant")
    os.makedirs(d, exist_ok=True)
    n = 0
    for key, st in CHAR["stations"].items():
        g = st.get("giant")
        if not g:
            continue
        name = key.split("|")[0]
        text = g["text"]
        ink = col255(CHAR["palette"][g["ink"]])
        cap_px = int(0.42 * GIANT_PPM)
        size = int(cap_px / 0.70)
        f = ImageFont.truetype(SERIF, size)
        tmp = Image.new("L", (10, 10))
        dr0 = ImageDraw.Draw(tmp)
        track = int(0.04 * GIANT_PPM)
        widths = [dr0.textlength(ch, font=f) * (0.55 if ch == " " else 1.0) for ch in text]
        w = int(sum(widths) + track * (len(text) - 1) + 0.2 * GIANT_PPM)
        h = int(0.54 * GIANT_PPM)
        mask = Image.new("L", (w, h), 0)
        dm = ImageDraw.Draw(mask)
        cap = dm.textbbox((0, 0), "H", font=f)
        y0 = (h - (cap[3] - cap[1])) / 2 - cap[1]
        x = 0.1 * GIANT_PPM
        for ch, cw in zip(text, widths):
            if ch != " ":
                dm.text((x, y0), ch, font=f, fill=255)
            x += cw + track
        # tile joints (75 x 150 mm stretcher bond) as thin pale lines inside the letters
        joints = Image.new("L", (w, h), 0)
        dj = ImageDraw.Draw(joints)
        th, tw_ = int(0.075 * GIANT_PPM), int(0.15 * GIANT_PPM)
        for r in range(h // th + 1):
            yy = r * th
            dj.line([(0, yy), (w, yy)], fill=255, width=2)
            off = (r % 2) * (tw_ // 2)
            for cx in range(-tw_, w + tw_, tw_):
                dj.line([(cx + off, yy), (cx + off, yy + th)], fill=255, width=2)
        rgba = Image.new("RGBA", (w, h), ink + (0,))
        px_m = mask.load()
        px_j = joints.load()
        out = rgba.load()
        for yy in range(h):
            for xx in range(w):
                a = px_m[xx, yy]
                if a:
                    j = px_j[xx, yy]
                    c = tuple(int(ink[i] * (1 - 0.38 * j / 255) + 190 * 0.38 * j / 255) for i in range(3))
                    out[xx, yy] = c + (a,)
        rgba.save(os.path.join(d, slug(name) + ".png"), optimize=True)
        n += 1
    print("wrote %d giant names" % n)


def motifs():
    try:
        import char_motifs
    except ImportError:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import char_motifs
    char_motifs.run(OUT, CHAR)


if __name__ == "__main__":
    what = sys.argv[1:] or ["friezes", "wayout", "giants", "motifs"]
    for w in what:
        {"friezes": friezes, "wayout": wayout, "giants": giants, "motifs": motifs}[w]()
