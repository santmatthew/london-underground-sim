#!/usr/bin/env python3
"""Generates the FICTIONAL retail textures used by the ticket-hall kiosks (scripts/world/ShopKit.gd) -> assets/textures/props/shops/
  shelf_<type>.png   back-wall product displays (1024 x 512, drawn as they would look lit from inside)
  menu_<type>.png    a small lit menu / price board (512 x 256)
  chiller.png        a glass-fronted chiller full of drinks and sandwiches (256 x 512)
All names, prices and products are invented. run: build/venv/bin/python tools/gen_shop_textures.py
"""
import os
import random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "textures", "props", "shops")
FONT_B = os.path.join(ROOT, "assets", "fonts", "Barlow-Bold.ttf")
FONT_C = os.path.join(ROOT, "assets", "fonts", "BarlowCondensed-SemiBold.ttf")
os.makedirs(OUT, exist_ok=True)


def font(path, size):
    return ImageFont.truetype(path, size)


PALETTES = {
    "news": [(200, 40, 50), (30, 90, 170), (250, 200, 40), (40, 40, 45), (240, 240, 240), (60, 150, 90), (220, 110, 30)],
    "coffee": [(110, 70, 45), (235, 220, 195), (60, 40, 30), (200, 150, 90), (245, 245, 240), (150, 40, 40)],
    "bakery": [(215, 165, 95), (235, 200, 140), (170, 100, 55), (245, 230, 200), (120, 60, 40), (250, 245, 235)],
    "convenience": [(220, 50, 45), (245, 200, 40), (40, 120, 200), (60, 160, 80), (250, 250, 250), (240, 120, 30), (150, 60, 160)],
    "pharmacy": [(250, 250, 250), (60, 150, 200), (60, 170, 110), (230, 240, 245), (240, 90, 90), (210, 220, 225)],
    "phones": [(25, 25, 30), (60, 60, 70), (230, 60, 60), (60, 120, 230), (240, 240, 240), (120, 200, 90)],
}


def shelf_rows(d, W, H, pal, rng, rows, item_w, item_h, kind):
    y = 0
    rh = H // rows
    for r in range(rows):
        # the shelf board and a dark back
        d.rectangle([0, y, W, y + rh], fill=(28, 28, 32))
        d.rectangle([0, y + rh - 10, W, y + rh], fill=(200, 202, 205))
        x = rng.randint(4, 20)
        while x < W - 30:
            w = int(item_w * rng.uniform(0.75, 1.3))
            h = int(min(rh - 22, item_h * rng.uniform(0.75, 1.15)))
            col = rng.choice(pal)
            top = y + rh - 10 - h
            if kind == "bottle":
                bw = max(10, w // 2)
                bx = x + (w - bw) // 2
                d.rounded_rectangle([bx, top + h // 4, bx + bw, y + rh - 10], radius=bw // 3, fill=col)
                d.rectangle([bx + bw // 4, top, bx + 3 * bw // 4, top + h // 3], fill=col)
                d.rectangle([bx + 2, top + h // 2, bx + bw - 2, top + h // 2 + h // 5], fill=(245, 245, 245))
            elif kind == "mag":
                d.rectangle([x, top, x + w, y + rh - 10], fill=col)
                d.rectangle([x + 3, top + 3, x + w - 3, top + 3 + h // 5], fill=rng.choice(pal))
                for k in range(3):
                    yy = top + h // 3 + k * (h // 6)
                    d.rectangle([x + 5, yy, x + w - 5 - rng.randint(0, w // 3), yy + 4], fill=(255, 255, 255))
            else:
                d.rounded_rectangle([x, top, x + w, y + rh - 10], radius=4, fill=col)
                d.rectangle([x + 3, top + h // 3, x + w - 3, top + h // 3 + h // 4], fill=(250, 250, 250))
                d.ellipse([x + w // 3, top + h // 3 + 2, x + w // 3 + h // 5, top + h // 3 + 2 + h // 5], fill=rng.choice(pal))
            x += w + rng.randint(2, 8)
        y += rh


def make_shelf(kind, seed):
    rng = random.Random(seed)
    W, H = 1024, 512
    im = Image.new("RGB", (W, H), (30, 30, 34))
    d = ImageDraw.Draw(im)
    pal = PALETTES[kind]
    if kind == "news":
        shelf_rows(d, W, H, pal, rng, 4, 70, 92, "mag")
    elif kind == "convenience":
        shelf_rows(d, W, H, pal, rng, 5, 58, 78, "box")
    elif kind == "pharmacy":
        shelf_rows(d, W, H, pal, rng, 5, 52, 70, "box")
    elif kind == "phones":
        shelf_rows(d, W, H, pal, rng, 6, 40, 70, "box")
    elif kind == "coffee":
        d.rectangle([0, 0, W, H], fill=(52, 38, 30))
        shelf_rows(d, W, H // 2, pal, rng, 2, 60, 74, "box")
        # menu boards
        for k in range(3):
            x0 = 60 + k * 320
            d.rectangle([x0, H // 2 + 20, x0 + 290, H - 30], fill=(20, 20, 22))
            f = font(FONT_C, 26)
            for j, item in enumerate(["ESPRESSO", "AMERICANO", "LATTE", "FLAT WHITE", "CAPPUCCINO", "HOT CHOCOLATE"]):
                d.text((x0 + 16, H // 2 + 30 + j * 32), item, font=f, fill=(245, 235, 215))
                d.text((x0 + 230, H // 2 + 30 + j * 32), "%d.%02d" % (2 + j // 3, rng.choice([20, 40, 60, 80])), font=f, fill=(245, 200, 90))
    elif kind == "bakery":
        d.rectangle([0, 0, W, H], fill=(60, 40, 30))
        for r in range(3):
            y = 20 + r * 160
            d.rectangle([20, y + 110, W - 20, y + 130], fill=(190, 190, 195))
            x = 40
            while x < W - 90:
                w = rng.randint(60, 110)
                col = rng.choice(pal)
                d.ellipse([x, y + 30, x + w, y + 112], fill=col)
                d.arc([x + 8, y + 36, x + w - 8, y + 106], 200, 340, fill=tuple(max(0, c - 50) for c in col), width=4)
                x += w + rng.randint(6, 18)
    im = im.filter(ImageFilter.GaussianBlur(0.6))
    # a light top-down falloff, as if lit from a strip above
    px = im.load()
    for y in range(H):
        f = 1.0 - 0.28 * (y / H)
        for x in range(0, W):
            r, g, b = px[x, y]
            px[x, y] = (int(r * f), int(g * f), int(b * f))
    im.save(os.path.join(OUT, "shelf_%s.png" % kind))


def make_menu(kind, title, seed):
    rng = random.Random(seed)
    W, H = 512, 256
    im = Image.new("RGB", (W, H), (18, 18, 20))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W, 54], fill=rng.choice(PALETTES[kind]))
    d.text((16, 6), title, font=font(FONT_B, 40), fill=(255, 255, 255))
    f = font(FONT_C, 28)
    items = {"news": ["NEWSPAPERS", "MAGAZINES", "CONFECTIONERY", "TRAVEL ESSENTIALS", "DRINKS"],
             "coffee": ["ESPRESSO", "LATTE", "FLAT WHITE", "TEA", "PASTRIES"],
             "bakery": ["SAUSAGE ROLL", "CHEESE & ONION", "CORNISH PASTY", "DOUGHNUT", "COFFEE"],
             "convenience": ["MEAL DEAL", "SANDWICHES", "SNACKS", "DRINKS", "MILK & BREAD"],
             "pharmacy": ["PRESCRIPTIONS", "TRAVEL HEALTH", "TOILETRIES", "VITAMINS"],
             "phones": ["CHARGERS", "CABLES", "CASES", "SCREEN REPAIR"]}[kind]
    for j, it in enumerate(items):
        d.text((20, 68 + j * 36), it, font=f, fill=(245, 235, 215))
        d.text((400, 68 + j * 36), "%d.%02d" % (1 + j, rng.choice([0, 50, 95, 99])), font=f, fill=(245, 200, 90))
    im.save(os.path.join(OUT, "menu_%s.png" % kind))


def make_chiller(seed):
    rng = random.Random(seed)
    W, H = 256, 512
    im = Image.new("RGB", (W, H), (210, 230, 240))
    d = ImageDraw.Draw(im)
    pal = PALETTES["convenience"]
    shelf_rows(d, W, H, pal, rng, 5, 34, 70, "bottle")
    px = im.load()
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            px[x, y] = (min(255, int(r * 0.85 + 30)), min(255, int(g * 0.9 + 40)), min(255, int(b * 0.95 + 55)))
    d.rectangle([0, 0, W, 10], fill=(60, 140, 200))
    im.save(os.path.join(OUT, "chiller.png"))


if __name__ == "__main__":
    for i, k in enumerate(PALETTES):
        make_shelf(k, 100 + i)
    make_menu("news", "NEWS", 1)
    make_menu("coffee", "COFFEE", 2)
    make_menu("bakery", "BAKERY", 3)
    make_menu("convenience", "FRESH FOOD", 4)
    make_menu("pharmacy", "HEALTH", 5)
    make_menu("phones", "PHONE ACCESSORIES", 6)
    make_chiller(9)
    print("wrote", len(os.listdir(OUT)), "textures to", OUT)
