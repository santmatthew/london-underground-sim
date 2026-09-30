#!/usr/bin/env python3
"""FICTIONAL advertising + TfL-style information posters in the real Tube formats -> assets/textures/props/posters2/*.png + manifest.json
(PosterKit reads the manifest: {file, format, style, aspect, w, h}).  All brands, titles, slogans and prices are invented.

  portrait   4/6-sheet   aspect 0.66   768 x 1164     40 designs
  land16     16-sheet    aspect 1.52  1152 x  758     30 designs
  land48     48-sheet    aspect 2.03  1536 x  756     24 designs
  info       Double Royal aspect 0.625 640 x 1024     12 TfL-style information posters
  infoq      Quad Royal   aspect 1.25 1280 x 1024      6 panels

run: build/venv/bin/python tools/gen_posters3.py [--sheets]      (about a minute)"""
import os, sys, math, json, random
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "textures", "props", "posters2")
FD = os.path.join(ROOT, "assets", "fonts")
os.makedirs(OUT, exist_ok=True)

FONTS = {
    "bold": "Barlow-Bold.ttf", "semi": "Barlow-SemiBold.ttf", "reg": "Barlow-Regular.ttf", "cond": "BarlowCondensed-SemiBold.ttf",
    "serif": "LibreBaskerville-Bold.ttf", "round": "HammersmithOne-Regular.ttf",
}
_fc = {}


def font(kind, size):
    key = (kind, int(size))
    if key not in _fc:
        _fc[key] = ImageFont.truetype(os.path.join(FD, FONTS[kind]), int(max(6, size)))
    return _fc[key]


def tw(txt, kind, size):
    return font(kind, size).getlength(txt)


def fit(txt, kind, w, h=None, start=400):
    s = start
    while s > 8:
        f = font(kind, s)
        if f.getlength(txt) <= w and (h is None or s * 0.75 <= h):
            return s
        s -= 2
    return 8


def wrap(txt, kind, size, w):
    words = txt.split()
    lines, cur = [], ""
    for wd in words:
        t = (cur + " " + wd).strip()
        if tw(t, kind, size) <= w or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = wd
    if cur:
        lines.append(cur)
    return lines


def text_block(d, txt, x, y, w, kind, max_size, fill, h=None, align="l", lh=1.05, upper=False):
    """headline fitted into w x h: wraps to as many lines as needed, largest size that fits. Returns bottom y."""
    if upper:
        txt = txt.upper()
    best = None
    for size in range(int(max_size), 11, -3):
        lines = wrap(txt, kind, size, w)
        hh = len(lines) * size * lh
        if h is None or hh <= h:
            best = (size, lines)
            break
    if best is None:
        size = 12
        best = (size, wrap(txt, kind, size, w))
    size, lines = best
    yy = y
    for ln in lines:
        lw = tw(ln, kind, size)
        xx = x if align == "l" else (x + (w - lw) / 2 if align == "c" else x + w - lw)
        d.text((xx, yy), ln, font=font(kind, size), fill=fill)
        yy += size * lh
    return yy


def grad(W, H, c0, c1, angle=90.0):
    a = math.radians(angle)
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    t = (xs / W - 0.5) * math.cos(a) + (ys / H - 0.5) * math.sin(a)
    t = (t - t.min()) / max(1e-6, (t.max() - t.min()))
    out = np.zeros((H, W, 3), np.float32)
    for i in range(3):
        out[..., i] = c0[i] + (c1[i] - c0[i]) * t
    return Image.fromarray(out.astype(np.uint8), "RGB").convert("RGBA")


def over(img, layer):
    return Image.alpha_composite(img, layer)


def layer(W, H):
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def glow(img, cx, cy, r, col, alpha=180):
    W, H = img.size
    l = layer(W, H)
    d = ImageDraw.Draw(l)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (alpha,))
    l = l.filter(ImageFilter.GaussianBlur(r * 0.45))
    return over(img, l)


def grain(img, amt=3.0, seed=1):
    rng = np.random.default_rng(seed)
    a = np.array(img.convert("RGB")).astype(np.float32)
    a += rng.normal(0, amt, a.shape[:2])[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")


def hexc(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


PALETTES = [
    ("#0b1f4d", "#ffd23f", "#ffffff"), ("#e63946", "#fff1e6", "#1d1d1f"), ("#1b998b", "#fff275", "#0b2a26"), ("#6a2c91", "#ff9f1c", "#ffffff"),
    ("#ff6b35", "#1b1b3a", "#fff8ee"), ("#0f3d3e", "#e2c044", "#f4f1de"), ("#2b2d42", "#ef233c", "#edf2f4"), ("#f7d6e0", "#3a0ca3", "#22223b"),
    ("#00509d", "#fdc500", "#ffffff"), ("#1a1a1a", "#00e5a0", "#ffffff"), ("#d62839", "#ffffff", "#111111"), ("#264653", "#e9c46a", "#f4a261"),
    ("#3d348b", "#f7b801", "#ffffff"), ("#ffe8d6", "#6b705c", "#2f2f2f"), ("#0a9396", "#ee9b00", "#001219"), ("#fb5607", "#8338ec", "#ffffff"),
]

BRANDS = ["Aurora Bank", "VoltUp", "Sunhaven", "Greenbridge", "Nimbus Mobile", "Plume", "Orbit Fitness", "Hearth & Co", "Kite", "Bramble", "Cascade",
          "Northlight Cinemas", "Fable Books", "Zest Kitchen", "Tandem Cycles", "Loom", "Pixelplay", "Harbour Hotels", "Lumen Eyecare", "Mosaic Museum",
          "Vela Air", "Copper Coffee", "Halo Health", "Meadow", "Stride", "Quill & Co", "Atlas Car Hire", "Kestrel Insurance", "Mango Mobile", "Ember Grill"]
HEADS = ["Switch and save.", "Fresh start. Fresh you.", "Your city. Your pace.", "Go further for less.", "Zero sugar. All the fizz.", "Book now, pay later.",
         "Everything worth watching.", "Made for the morning.", "Less waiting. More living.", "The smart way to spend.", "Find your quiet.", "Big flavour. Small price.",
         "Home, but better.", "Travel light.", "Feel the difference.", "Because you deserve it.", "Never miss a moment.", "Good things take time.",
         "Breathe easy.", "See more of the world.", "Power your day.", "Mind the savings.", "Taste the season.", "Move your way.", "Play the next level."]
SUBS = ["Terms apply.", "Find out more online.", "Available now.", "Limited time offer.", "Download the app.", "Open every day.", "From 9.99 a month.", "Book today.",
        "New for spring.", "In cinemas soon.", "Free delivery on orders over 25."]
SHOWS = ["The Last Signal", "Midnight in Mayfair", "Paper Moons", "House of Embers", "Glass Harbour", "Neon Orchard", "A Quiet Storm", "The Long Winter", "Velvet Hour", "Salt & Sparrow"]


def pill(d, x0, y0, x1, y1, fill, txt, col, kind="bold"):
    d.rounded_rectangle([x0, y0, x1, y1], radius=(y1 - y0) // 2, fill=fill)
    s = fit(txt, kind, (x1 - x0) * 0.8, (y1 - y0) * 0.55)
    w = tw(txt, kind, s)
    d.text(((x0 + x1) / 2 - w / 2, (y0 + y1) / 2 - s * 0.62), txt, font=font(kind, s), fill=col)


def wordmark(d, x, y, brand, col, size):
    d.text((x, y), brand, font=font("bold", size), fill=col)


# ------------------------------------------------------------------------------------------------ templates
def t_headline(W, H, rng):
    bg, acc, ink = [hexc(c) for c in rng.choice(PALETTES)]
    img = grad(W, H, bg, tuple(int(v * 0.8) for v in bg), 60)
    d = ImageDraw.Draw(img)
    land = W > H
    # big accent shape
    l = layer(W, H)
    ld = ImageDraw.Draw(l)
    if land:
        ld.ellipse([W * 0.55, -H * 0.2, W * 1.25, H * 1.15], fill=acc + (255,))
        ld.ellipse([W * 0.62, H * 0.1, W * 1.05, H * 0.95], fill=tuple(int(v * 0.85) for v in acc) + (255,))
    else:
        ld.ellipse([-W * 0.2, H * 0.52, W * 1.2, H * 1.35], fill=acc + (255,))
    img = over(img, l)
    d = ImageDraw.Draw(img)
    head = rng.choice(HEADS)
    if land:
        text_block(d, head, W * 0.06, H * 0.14, W * 0.44, "bold", H * 0.23, (255, 255, 255) if sum(bg) < 400 else (20, 20, 24), H * 0.58)
        pill(d, W * 0.06, H * 0.76, W * 0.30, H * 0.88, acc, rng.choice(["Find out more", "Get started", "Shop now", "Book today"]), bg)
        wordmark(d, W * 0.06, H * 0.05, rng.choice(BRANDS), (255, 255, 255) if sum(bg) < 400 else (20, 20, 24), int(H * 0.06))
    else:
        text_block(d, head, W * 0.08, H * 0.1, W * 0.84, "bold", W * 0.2, (255, 255, 255) if sum(bg) < 400 else (20, 20, 24), H * 0.36)
        pill(d, W * 0.08, H * 0.55, W * 0.52, H * 0.61, acc, rng.choice(["Find out more", "Get started", "Shop now"]), bg)
        wordmark(d, W * 0.08, H * 0.92, rng.choice(BRANDS), ink if sum(acc) < 450 else (20, 20, 24), int(W * 0.07))
    return img


def t_theatre(W, H, rng):
    bg, acc, ink = [hexc(c) for c in rng.choice([("#140a2b", "#ffcf56", "#ffffff"), ("#0a1930", "#ff5a4f", "#fff3e0"), ("#241010", "#f3c969", "#fff1e0"), ("#0c0c14", "#7be0ff", "#ffffff")])]
    img = grad(W, H, tuple(min(255, v + 25) for v in bg), bg, 90)
    img = glow(img, W * 0.5, H * 0.45, min(W, H) * 0.5, acc, 90)
    d = ImageDraw.Draw(img)
    rng2 = random.Random(rng.random())
    # silhouettes
    for k in range(rng2.randint(2, 4)):
        cx = W * (0.25 + 0.5 * rng2.random()) if W < H else W * (0.3 + 0.4 * rng2.random())
        base = H * 0.78
        hh = H * rng2.uniform(0.25, 0.42)
        d.ellipse([cx - hh * 0.13, base - hh, cx + hh * 0.13, base - hh * 0.74], fill=(6, 6, 10))
        d.polygon([(cx - hh * 0.2, base), (cx - hh * 0.12, base - hh * 0.72), (cx + hh * 0.12, base - hh * 0.72), (cx + hh * 0.2, base)], fill=(6, 6, 10))
    title = rng.choice(SHOWS).upper()
    text_block(d, title, W * 0.06, H * 0.72, W * 0.88, "serif", W * 0.13 if W < H else H * 0.17, acc, H * 0.22, "c", 1.0)
    d.text((W * 0.06, H * 0.05), "★★★★★  'A TRIUMPH'", font=font("semi", int(min(W, H) * 0.045)), fill=ink)
    d.text((W * 0.06, H * 0.94), "BOOK NOW  ·  Royal Lantern Theatre", font=font("semi", int(min(W, H) * 0.04)), fill=ink)
    return img


def t_product(W, H, rng):
    bg, acc, ink = [hexc(c) for c in rng.choice(PALETTES)]
    img = grad(W, H, bg, tuple(int(v * 0.7) for v in bg), 90)
    img = glow(img, W * (0.7 if W > H else 0.5), H * 0.5, min(W, H) * 0.45, acc, 110)
    d = ImageDraw.Draw(img)
    cx = W * (0.68 if W > H else 0.5)
    cy = H * 0.55
    hh = H * (0.62 if W > H else 0.42)
    kind = rng.choice(["can", "bottle", "box"])
    col = acc
    if kind == "can":
        d.rounded_rectangle([cx - hh * 0.22, cy - hh * 0.5, cx + hh * 0.22, cy + hh * 0.5], radius=int(hh * 0.06), fill=col)
        d.rectangle([cx - hh * 0.22, cy - hh * 0.05, cx + hh * 0.22, cy + hh * 0.25], fill=bg)
        d.text((cx - hh * 0.17, cy), rng.choice(BRANDS)[:8].upper(), font=font("bold", int(hh * 0.07)), fill=ink)
    elif kind == "bottle":
        d.rounded_rectangle([cx - hh * 0.17, cy - hh * 0.25, cx + hh * 0.17, cy + hh * 0.5], radius=int(hh * 0.08), fill=col)
        d.rectangle([cx - hh * 0.07, cy - hh * 0.5, cx + hh * 0.07, cy - hh * 0.25], fill=col)
        d.rectangle([cx - hh * 0.09, cy - hh * 0.56, cx + hh * 0.09, cy - hh * 0.5], fill=bg)
        d.rectangle([cx - hh * 0.17, cy + hh * 0.05, cx + hh * 0.17, cy + hh * 0.3], fill=(255, 255, 255))
    else:
        d.rounded_rectangle([cx - hh * 0.28, cy - hh * 0.34, cx + hh * 0.28, cy + hh * 0.42], radius=int(hh * 0.03), fill=col)
        d.rectangle([cx - hh * 0.28, cy - hh * 0.06, cx + hh * 0.28, cy + hh * 0.1], fill=bg)
    d.ellipse([cx - hh * 0.3, cy + hh * 0.5, cx + hh * 0.3, cy + hh * 0.56], fill=(0, 0, 0, 90))
    head = rng.choice(HEADS)
    if W > H:
        text_block(d, head, W * 0.06, H * 0.15, W * 0.42, "bold", H * 0.2, (255, 255, 255) if sum(bg) < 400 else (20, 20, 24), H * 0.55)
    else:
        text_block(d, head, W * 0.08, H * 0.05, W * 0.84, "bold", W * 0.16, (255, 255, 255) if sum(bg) < 400 else (20, 20, 24), H * 0.2)
    d.rectangle([0, H * 0.9, W, H], fill=acc)
    d.text((W * 0.05, H * 0.925), rng.choice(SUBS), font=font("semi", int(H * 0.04)), fill=bg)
    return img


def t_deal(W, H, rng):
    bg, acc, ink = [hexc(c) for c in rng.choice(PALETTES)]
    img = grad(W, H, bg, bg, 0)
    d = ImageDraw.Draw(img)
    # diagonal stripes
    for k in range(-10, 30):
        d.polygon([(k * W * 0.09, 0), (k * W * 0.09 + W * 0.04, 0), (k * W * 0.09 - H * 0.3 + W * 0.04, H), (k * W * 0.09 - H * 0.3, H)], fill=tuple(int(v * 0.92) for v in bg))
    cx, cy = (W * 0.76, H * 0.5) if W > H else (W * 0.5, H * 0.66)
    r = min(W, H) * (0.3 if W > H else 0.32)
    pts = []
    for k in range(40):
        a = k * math.pi / 20
        rr = r * (1.0 if k % 2 == 0 else 0.85)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=acc)
    price = rng.choice(["£9.99", "£4.50", "50% off", "From £19", "£2 a week", "Save £120"])
    s = fit(price, "bold", r * 1.5, r * 0.9)
    d.text((cx - tw(price, "bold", s) / 2, cy - s * 0.6), price, font=font("bold", s), fill=bg)
    head = rng.choice(["Big savings.", "This week only.", "Spring sale.", "Summer deals.", "Half price.", "Mega weekend."])
    if W > H:
        text_block(d, head, W * 0.06, H * 0.16, W * 0.44, "bold", H * 0.26, (255, 255, 255) if sum(bg) < 400 else (20, 20, 24), H * 0.55)
    else:
        text_block(d, head, W * 0.08, H * 0.06, W * 0.84, "bold", W * 0.2, (255, 255, 255) if sum(bg) < 400 else (20, 20, 24), H * 0.3)
    d.text((W * 0.05, H * 0.94), "Terms and conditions apply. " + rng.choice(BRANDS), font=font("reg", int(min(W, H) * 0.028)), fill=ink)
    return img


def t_tourism(W, H, rng):
    sky = rng.choice([((255, 170, 90), (90, 60, 140)), ((120, 200, 255), (20, 100, 200)), ((255, 220, 140), (240, 110, 100)), ((60, 40, 120), (250, 120, 90))])
    img = grad(W, H, sky[1], sky[0], 90)
    d = ImageDraw.Draw(img)
    r = min(W, H) * 0.14
    sx, sy = W * rng.uniform(0.3, 0.7), H * 0.52
    img = glow(img, sx, sy, r * 2.6, (255, 240, 200), 120)
    d = ImageDraw.Draw(img)
    d.ellipse([sx - r, sy - r, sx + r, sy + r], fill=(255, 245, 220))
    rng2 = random.Random(rng.random())
    for layer_i, col in enumerate([(60, 70, 120), (36, 44, 92), (18, 24, 60)]):
        base = H * (0.66 + 0.08 * layer_i)
        pts = [(0, H)]
        x = 0
        while x <= W + 40:
            pts.append((x, base - H * (0.12 + 0.05 * (2 - layer_i)) * abs(math.sin(x / W * (3 + layer_i) + rng2.random()))))
            x += max(10, W // 40)
        pts.append((W, H))
        d.polygon(pts, fill=col)
    head = rng.choice(["Escape the grey.", "Sunny side up.", "Wander further.", "Coast to coast.", "Summer starts here.", "See the north."])
    text_block(d, head, W * 0.06, H * 0.06, W * 0.88, "bold", H * 0.1 if W > H else W * 0.17, (255, 255, 255), H * 0.3, upper=True)
    d.text((W * 0.06, H * 0.94), rng.choice(["7 nights from £499", "Flights, transfers and more", "Book by June"]) + "  ·  " + rng.choice(BRANDS), font=font("semi", int(min(W, H) * 0.04)), fill=(255, 255, 255))
    return img


def t_type(W, H, rng):
    bg, acc, ink = [hexc(c) for c in rng.choice(PALETTES)]
    img = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(img)
    words = rng.choice([("Less", "stress."), ("More", "sleep."), ("Go", "anywhere."), ("Try", "again."), ("Hello", "tomorrow."), ("Just", "add water.")])
    big = fit(max(words, key=len).upper(), "bold", W * 0.88, H * 0.36)
    y = H * 0.12
    d.text((W * 0.06, y), words[0].upper(), font=font("bold", big), fill=(255, 255, 255) if sum(bg) < 400 else (20, 20, 24))
    d.text((W * 0.06, y + big * 0.95), words[1].upper(), font=font("bold", big), fill=acc)
    d.text((W * 0.06, H * 0.9), rng.choice(BRANDS) + "  —  " + rng.choice(SUBS), font=font("semi", int(min(W, H) * 0.04)), fill=(255, 255, 255) if sum(bg) < 400 else (20, 20, 24))
    return img


def t_app(W, H, rng):
    bg, acc, ink = [hexc(c) for c in rng.choice([("#3d348b", "#f7b801", "#ffffff"), ("#0b1f4d", "#00e5a0", "#ffffff"), ("#6a2c91", "#ffd23f", "#ffffff"), ("#0f3d3e", "#ff6b35", "#ffffff")])]
    img = grad(W, H, bg, tuple(int(v * 0.6) for v in bg), 70)
    d = ImageDraw.Draw(img)
    px, py = (W * 0.72, H * 0.52) if W > H else (W * 0.5, H * 0.64)
    ph = H * (0.78 if W > H else 0.46)
    pw = ph * 0.5
    l = layer(W, H)
    ld = ImageDraw.Draw(l)
    ld.rounded_rectangle([px - pw / 2, py - ph / 2, px + pw / 2, py + ph / 2], radius=int(pw * 0.14), fill=(16, 16, 20, 255))
    ld.rounded_rectangle([px - pw / 2 + 8, py - ph / 2 + 8, px + pw / 2 - 8, py + ph / 2 - 8], radius=int(pw * 0.12), fill=acc + (255,))
    for k in range(4):
        ld.rounded_rectangle([px - pw * 0.4, py - ph * 0.4 + k * ph * 0.2, px + pw * 0.4, py - ph * 0.26 + k * ph * 0.2], radius=8, fill=(255, 255, 255, 235 - k * 30))
    l = l.rotate(rng.uniform(-14, 14), center=(px, py), resample=Image.BICUBIC)
    img = over(img, l)
    d = ImageDraw.Draw(img)
    head = rng.choice(["Find quieter times.", "Your money, sorted.", "Everything in one app.", "Order in seconds.", "Plan it. Book it."])
    if W > H:
        text_block(d, head, W * 0.06, H * 0.14, W * 0.44, "bold", H * 0.22, (255, 255, 255), H * 0.55)
    else:
        text_block(d, head, W * 0.08, H * 0.05, W * 0.84, "bold", W * 0.16, (255, 255, 255), H * 0.22)
    pill(d, W * 0.06, H * 0.84 if W < H else H * 0.72, W * 0.06 + min(W * 0.3, 380), (H * 0.92 if W < H else H * 0.86), (255, 255, 255), "Download the app", bg)
    d.text((W * 0.06, H * 0.95 if W < H else H * 0.93), rng.choice(BRANDS), font=font("bold", int(min(W, H) * 0.04)), fill=(255, 255, 255))
    return img


def t_minimal(W, H, rng):
    bg = rng.choice([(245, 242, 235), (20, 20, 22), (244, 214, 204), (214, 232, 226), (255, 230, 120), (38, 60, 120)])
    ink = (20, 20, 22) if sum(bg) > 420 else (255, 255, 255)
    img = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(img)
    sent = rng.choice(["Some of the best days start with nothing planned.", "Kindness costs nothing.", "Slow down. You're nearly there.", "Make today count.", "Someone out there needs to hear from you."])
    text_block(d, sent, W * 0.1, H * 0.25, W * 0.8, "serif", min(W, H) * 0.12, ink, H * 0.5)
    d.text((W * 0.1, H * 0.88), rng.choice(["kindnessweek.example", "moreplease.example", "slowdown.example"]), font=font("semi", int(min(W, H) * 0.04)), fill=ink)
    return img


def t_exhibit(W, H, rng):
    bg = rng.choice([(247, 240, 226), (236, 232, 222), (226, 236, 240)])
    acc = rng.choice([(150, 50, 40), (30, 70, 110), (40, 100, 70), (190, 120, 30)])
    img = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(img)
    rng2 = random.Random(rng.random())
    cols = 4 if W > H else 2
    cw = (W * 0.84) / cols
    rows = 2
    top = H * 0.08 if W > H else H * 0.2
    rh = (H * 0.5) / rows if W > H else (H * 0.52) / 3
    for r_ in range(rows if W > H else 3):
        for c_ in range(cols):
            x0 = W * 0.08 + c_ * cw + 4
            y0 = top + r_ * rh + 4
            tone = tuple(int(v) for v in (np.array(acc) * rng2.uniform(0.4, 1.0) + np.array((255, 255, 255)) * rng2.uniform(0, 0.4)).clip(0, 255))
            d.rectangle([x0, y0, x0 + cw - 8, y0 + rh - 8], fill=tone)
            d.ellipse([x0 + cw * 0.2, y0 + rh * 0.2, x0 + cw * 0.75, y0 + rh * 0.8], fill=tuple(int(v * 0.6) for v in tone))
    title = rng.choice(["Objects of Desire", "The Art of Light", "Clay and Fire", "Machines that Move", "Small Wonders"])
    text_block(d, title, W * 0.08, H * 0.66 if W < H else H * 0.72, W * 0.84, "serif", min(W, H) * 0.11, acc, H * 0.2)
    d.text((W * 0.08, H * 0.93), "Mosaic Museum  ·  Until 14 September  ·  Free entry", font=font("reg", int(min(W, H) * 0.035)), fill=(40, 40, 40))
    return img


def t_film(W, H, rng):
    bg = rng.choice([(8, 10, 18), (20, 8, 10), (6, 18, 20)])
    acc = rng.choice([(255, 120, 80), (120, 200, 255), (255, 210, 90), (200, 120, 255)])
    img = grad(W, H, tuple(v + 30 for v in bg), bg, 90)
    img = glow(img, W * 0.5, H * 0.5, min(W, H) * 0.6, acc, 70)
    d = ImageDraw.Draw(img)
    hx, hy = W * 0.5, H * 0.46
    hh = H * 0.55
    d.ellipse([hx - hh * 0.16, hy - hh * 0.5, hx + hh * 0.16, hy - hh * 0.18], fill=(10, 10, 14))
    d.polygon([(hx - hh * 0.32, hy + hh * 0.5), (hx - hh * 0.18, hy - hh * 0.15), (hx + hh * 0.18, hy - hh * 0.15), (hx + hh * 0.32, hy + hh * 0.5)], fill=(10, 10, 14))
    title = rng.choice(SHOWS).upper()
    text_block(d, title, W * 0.06, H * 0.72, W * 0.88, "cond", min(W, H) * 0.16, acc, H * 0.2, "c", 1.0)
    d.text((W * 0.06, H * 0.93), "IN CINEMAS " + rng.choice(["FRIDAY", "THIS AUTUMN", "NOVEMBER"]) + "   ·   " + rng.choice(BRANDS), font=font("semi", int(min(W, H) * 0.035)), fill=(230, 230, 230))
    return img


TEMPLATES = [t_headline, t_theatre, t_product, t_deal, t_tourism, t_type, t_app, t_minimal, t_exhibit, t_film, t_headline, t_product, t_app, t_deal, t_tourism]
STYLE = {t_headline: "headline", t_theatre: "theatre", t_product: "product", t_deal: "deal", t_tourism: "tourism", t_type: "typographic", t_app: "app", t_minimal: "minimal", t_exhibit: "exhibition", t_film: "film"}


# ------------------------------------------------------------------------------------------------ TfL-style information posters
TFL_BLUE = (16, 6, 159)
RED = (220, 36, 31)
LINES = [("Bakerloo", (178, 99, 0)), ("Central", (220, 36, 31)), ("Circle", (255, 211, 41)), ("District", (0, 125, 50)), ("Jubilee", (131, 141, 147)),
         ("Metropolitan", (155, 0, 88)), ("Northern", (0, 0, 0)), ("Piccadilly", (0, 25, 168)), ("Victoria", (0, 152, 216))]


def roundel(d, cx, cy, r):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=RED, width=int(r * 0.28))
    d.rectangle([cx - r * 1.25, cy - r * 0.24, cx + r * 1.25, cy + r * 0.24], fill=TFL_BLUE)
    s = int(r * 0.26)
    d.text((cx - tw("UNDERGROUND", "bold", s) / 2, cy - s * 0.62), "UNDERGROUND", font=font("bold", s), fill=(255, 255, 255))


def tfl_frame(W, H, title, icon=None, bg=(250, 249, 244)):
    img = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, int(H * 0.085)], fill=TFL_BLUE)
    d.text((W * 0.045, H * 0.018), "Transport for London", font=font("round", int(H * 0.04)), fill=(255, 255, 255))
    d.text((W * 0.045, H * 0.96), "MAYOR OF LONDON", font=font("bold", int(H * 0.018)), fill=(20, 20, 40))
    roundel(d, W * 0.82, H * 0.945, H * 0.022)
    return img, d


def tfl_poster(W, H, rng, kind):
    img, d = tfl_frame(W, H, "")
    if kind == "update":
        d.text((W * 0.06, H * 0.12), "Travel information", font=font("round", int(H * 0.035)), fill=TFL_BLUE)
        d.rounded_rectangle([W * 0.8, H * 0.11, W * 0.94, H * 0.16], radius=6, fill=TFL_BLUE)
        d.text((W * 0.855, H * 0.113), "i", font=font("bold", int(H * 0.04)), fill=(255, 255, 255))
        text_block(d, rng.choice(["No service between Green Park and Bank", "Minor delays on the Northern line", "Station closed until further notice", "Lift out of service"]), W * 0.06, H * 0.2, W * 0.88, "bold", H * 0.058, (10, 10, 60), H * 0.25)
        text_block(d, "Please use alternative routes. Check before you travel at tfl.example or ask a member of staff.", W * 0.06, H * 0.5, W * 0.88, "reg", H * 0.03, (20, 20, 50), H * 0.2)
    elif kind == "closures":
        d.text((W * 0.06, H * 0.12), "Planned closures", font=font("round", int(H * 0.04)), fill=TFL_BLUE)
        d.polygon([(W * 0.86, H * 0.18), (W * 0.93, H * 0.1), (W * 0.79, H * 0.1)], fill=(255, 205, 0), outline=(0, 0, 0))
        d.rectangle([0, H * 0.2, W, H * 0.27], fill=TFL_BLUE)
        d.text((W * 0.06, H * 0.212), "Sat 14 and Sun 15 March", font=font("bold", int(H * 0.04)), fill=(255, 255, 255))
        y = H * 0.3
        for name, col in rng.sample(LINES, 5):
            d.rectangle([W * 0.06, y, W * 0.94, y + H * 0.05], fill=col)
            d.text((W * 0.08, y + H * 0.006), name, font=font("bold", int(H * 0.034)), fill=(255, 255, 255) if sum(col) < 500 else (0, 0, 0))
            d.text((W * 0.06, y + H * 0.055), "No service between two stations. Replacement buses run.", font=font("reg", int(H * 0.02)), fill=(30, 30, 50))
            y += H * 0.115
    elif kind == "handrail":
        img = grad(W, H, (10, 20, 120), (40, 90, 200), 90)
        d = ImageDraw.Draw(img)
        text_block(d, "Hold the handrail", W * 0.06, H * 0.12, W * 0.88, "bold", H * 0.12, (255, 255, 255), H * 0.4)
        text_block(d, "Stay safe on the escalators. Stand on the right, walk on the left.", W * 0.06, H * 0.55, W * 0.88, "reg", H * 0.035, (235, 240, 255), H * 0.2)
        d.text((W * 0.06, H * 0.96), "MAYOR OF LONDON", font=font("bold", int(H * 0.018)), fill=(255, 255, 255))
        roundel(d, W * 0.82, H * 0.945, H * 0.022)
    elif kind == "safety":
        img = Image.new("RGBA", (W, H), (200, 200, 205, 255))
        d = ImageDraw.Draw(img)
        d.ellipse([W * 0.06, H * 0.08, W * 0.7, H * 0.4], fill=TFL_BLUE)
        text_block(d, "See it. Say it. Sorted.", W * 0.12, H * 0.14, W * 0.52, "bold", H * 0.06, (255, 255, 255), H * 0.2)
        d.rectangle([0, H * 0.82, W, H], fill=TFL_BLUE)
        d.text((W * 0.06, H * 0.86), "Text 61016 or call 0800 40 50 40", font=font("bold", int(H * 0.028)), fill=(255, 255, 255))
    elif kind == "stepfree":
        d.text((W * 0.06, H * 0.12), "Step-free access", font=font("round", int(H * 0.04)), fill=TFL_BLUE)
        d.ellipse([W * 0.06, H * 0.2, W * 0.42, H * 0.2 + W * 0.36], fill=TFL_BLUE)
        d.text((W * 0.17, H * 0.2 + W * 0.05), "♿", font=font("bold", int(W * 0.2)), fill=(255, 255, 255))
        text_block(d, "Lifts to all platforms. Ask staff for help or use the help point.", W * 0.06, H * 0.52, W * 0.88, "bold", H * 0.04, (10, 10, 60), H * 0.25)
    elif kind == "trains":
        d.text((W * 0.06, H * 0.12), "First and last trains", font=font("round", int(H * 0.037)), fill=TFL_BLUE)
        y = H * 0.2
        for name, col in LINES[:7]:
            d.rectangle([W * 0.06, y, W * 0.94, y + H * 0.04], fill=col)
            d.text((W * 0.08, y + H * 0.004), name, font=font("bold", int(H * 0.028)), fill=(255, 255, 255) if sum(col) < 500 else (0, 0, 0))
            d.text((W * 0.06, y + H * 0.046), "Mon-Fri  05:32 · 00:14      Sat  05:40 · 00:08", font=font("reg", int(H * 0.02)), fill=(20, 20, 50))
            y += H * 0.105
    elif kind == "fares":
        d.text((W * 0.06, H * 0.12), "Penalty fares", font=font("round", int(H * 0.04)), fill=TFL_BLUE)
        text_block(d, "You must touch in and out with a valid ticket or contactless card.", W * 0.06, H * 0.2, W * 0.88, "bold", H * 0.055, (10, 10, 60), H * 0.3)
        text_block(d, "Penalty fares may be charged if you cannot show a valid ticket. Fares apply under the railway byelaws.", W * 0.06, H * 0.55, W * 0.88, "reg", H * 0.028, (20, 20, 50), H * 0.2)
    else:
        img = Image.new("RGBA", (W, H), (250, 250, 250, 255))
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, W, H * 0.1], fill=(255, 255, 255))
        d.rectangle([W * 0.04, H * 0.04, W * 0.96, H * 0.94], outline=(40, 40, 40), width=3)
        text_block(d, "Service update", W * 0.08, H * 0.08, W * 0.8, "bold", H * 0.06, TFL_BLUE, H * 0.12)
        d.text((W * 0.08, H * 0.24), "Handwritten notice", font=font("reg", int(H * 0.028)), fill=(20, 40, 160))
        for k in range(6):
            d.line([W * 0.08, H * 0.34 + k * H * 0.07, W * 0.9 - (k % 3) * W * 0.12, H * 0.34 + k * H * 0.07], fill=(30, 50, 170), width=4)
    return img


def tfl_panel(W, H, rng, kind):
    img = Image.new("RGBA", (W, H), (250, 249, 244, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, int(H * 0.11)], fill=TFL_BLUE)
    d.text((W * 0.03, H * 0.022), {"map": "Tube services at this station", "works": "Engineering works"}.get(kind, "Customer information"), font=font("round", int(H * 0.05)), fill=(255, 255, 255))
    if kind == "map":
        y = H * 0.18
        for name, col in rng.sample(LINES, 6):
            d.rounded_rectangle([W * 0.04, y, W * 0.5, y + H * 0.08], radius=12, fill=col)
            d.text((W * 0.06, y + H * 0.012), name, font=font("bold", int(H * 0.05)), fill=(255, 255, 255) if sum(col) < 500 else (0, 0, 0))
            d.text((W * 0.54, y + H * 0.02), "Trains every 3-5 minutes", font=font("reg", int(H * 0.04)), fill=(20, 20, 50))
            y += H * 0.12
    else:
        text_block(d, "Weekend engineering works. Some lines part-suspended. Plan your journey.", W * 0.04, H * 0.2, W * 0.92, "bold", H * 0.08, (10, 10, 60), H * 0.4)
        d.rectangle([W * 0.04, H * 0.66, W * 0.96, H * 0.8], fill=RED)
        d.text((W * 0.06, H * 0.69), "Check before you travel", font=font("bold", int(H * 0.07)), fill=(255, 255, 255))
    d.text((W * 0.03, H * 0.93), "MAYOR OF LONDON", font=font("bold", int(H * 0.03)), fill=(20, 20, 40))
    roundel(d, W * 0.9, H * 0.9, H * 0.05)
    return img


# ------------------------------------------------------------------------------------------------ main
def make(fmt, W, H, count, seed0, manifest):
    for i in range(count):
        rng = random.Random(seed0 + i * 7919)
        tpl = TEMPLATES[i % len(TEMPLATES)]
        img = tpl(W, H, rng)
        img = grain(img, 2.4, seed0 + i)
        name = "%s_%02d.png" % (fmt, i)
        img.save(os.path.join(OUT, name), optimize=True)
        manifest.append({"file": name, "format": fmt, "style": STYLE[tpl], "aspect": round(W / H, 3), "w": W, "h": H})


def make_info(manifest):
    kinds = ["update", "closures", "handrail", "safety", "stepfree", "trains", "fares", "whiteboard", "update", "closures", "handrail", "safety"]
    for i, k in enumerate(kinds):
        rng = random.Random(500 + i)
        W, H = 640, 1024
        img = grain(tfl_poster(W, H, rng, k), 1.5, i)
        name = "info_%02d.png" % i
        img.save(os.path.join(OUT, name), optimize=True)
        manifest.append({"file": name, "format": "info", "style": "tfl_" + k, "aspect": round(W / H, 3), "w": W, "h": H})
    for i, k in enumerate(["map", "works", "map", "works", "map", "works"]):
        rng = random.Random(700 + i)
        W, H = 1280, 1024
        img = grain(tfl_panel(W, H, rng, k), 1.5, i)
        name = "infoq_%02d.png" % i
        img.save(os.path.join(OUT, name), optimize=True)
        manifest.append({"file": name, "format": "infoq", "style": "tfl_" + k, "aspect": round(W / H, 3), "w": W, "h": H})


def sheets(manifest):
    bdir = os.path.join(ROOT, "build")
    for fmt in ["portrait", "land16", "land48", "info", "infoq"]:
        ents = [e for e in manifest if e["format"] == fmt]
        if not ents:
            continue
        cols = 8 if fmt in ("portrait", "info") else (5 if fmt == "land16" else 4)
        th = 280 if fmt in ("portrait", "info") else 190
        ims = []
        for e in ents:
            im = Image.open(os.path.join(OUT, e["file"])).convert("RGB")
            ims.append(im.resize((int(th * e["aspect"]), th)))
        tw_ = max(i.width for i in ims)
        rows = (len(ims) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * (tw_ + 6), rows * (th + 6)), (60, 60, 60))
        for k, im in enumerate(ims):
            sheet.paste(im, ((k % cols) * (tw_ + 6), (k // cols) * (th + 6)))
        sheet.save(os.path.join(bdir, "posters_sheet_%s.png" % fmt))


if __name__ == "__main__":
    manifest = []
    make("portrait", 768, 1164, 40, 1000, manifest)
    make("land16", 1152, 758, 30, 2000, manifest)
    make("land48", 1536, 756, 24, 3000, manifest)
    make_info(manifest)
    json.dump(manifest, open(os.path.join(OUT, "manifest.json"), "w"), indent=1)
    print("wrote", len(manifest), "posters to", OUT)
    if "--sheets" in sys.argv:
        sheets(manifest)
