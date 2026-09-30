#!/usr/bin/env python3
"""Textures for the procedural station props (scripts/world/PropKit.gd) -> assets/textures/props/gen2/
  perforated.png   perforated-steel seat shell tile (Toro-type platform benches)
  timber.png       stained timber slats
  mfm_front.png    front of a multi-fare ticket machine (0.9 x 1.4 m): amber status strip, TfL-blue notice strip, touchscreen, Oyster disc, card block, slots, hopper
  tvm_front.png    the narrow card-only machine (0.5 x 1.4 m)
  tickets_sign.png the lit 'Tickets' sign band (1.6 x 0.22 m)
  newspaper.png    a blue free-newspaper stand's front (invented title)
  helppoint.png    help-point face (white disc, buttons)
All names and wording are generic or invented. run: build/venv/bin/python tools/gen_prop_textures.py"""
import os
import random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "textures", "props", "gen2")
os.makedirs(OUT, exist_ok=True)
FB = os.path.join(ROOT, "assets", "fonts", "Barlow-Bold.ttf")
FS = os.path.join(ROOT, "assets", "fonts", "Barlow-SemiBold.ttf")
FC = os.path.join(ROOT, "assets", "fonts", "BarlowCondensed-SemiBold.ttf")
FD = os.path.join(ROOT, "assets", "fonts", "DotGothic16.ttf")
BLUE = (16, 6, 159)
STEEL = (178, 181, 184)
CHAR = (38, 40, 44)


def F(p, s):
    return ImageFont.truetype(p, s)


def perforated():
    n = 128
    im = Image.new("RGB", (n, n), (120, 124, 130))
    d = ImageDraw.Draw(im)
    step = 16
    for j in range(n // step):
        for i in range(n // step):
            ox = step // 2 if j % 2 else 0
            cx, cy = i * step + ox + step // 2, j * step + step // 2
            d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(28, 29, 32))
    im.save(os.path.join(OUT, "perforated.png"))


def timber():
    rng = random.Random(3)
    W, H = 256, 256
    im = Image.new("RGB", (W, H), (96, 62, 38))
    d = ImageDraw.Draw(im)
    for y in range(0, H, 2):
        shade = rng.randint(-14, 14)
        d.line([0, y, W, y], fill=(96 + shade, 62 + shade // 2, 38 + shade // 3))
    for _ in range(60):
        y = rng.randint(0, H - 1)
        x0 = rng.randint(0, W)
        d.line([x0, y, x0 + rng.randint(30, 120), y], fill=(70, 44, 26))
    im = im.filter(ImageFilter.GaussianBlur(0.4))
    im.save(os.path.join(OUT, "timber.png"))


def machine(name, w_px, h_px, big):
    im = Image.new("RGB", (w_px, h_px), STEEL)
    d = ImageDraw.Draw(im)
    m = int(w_px * 0.05)
    # charcoal fascia inside a stainless frame
    d.rectangle([m, m, w_px - m, h_px - m], fill=CHAR)
    y = m + 6
    # amber status strip
    sh = int(h_px * 0.05)
    d.rectangle([m + 6, y, w_px - m - 6, y + sh], fill=(12, 10, 6))
    d.text((m + 14, y + 2), "CARDS ACCEPTED   CHANGE GIVEN" if big else "CARDS ONLY", font=F(FD, int(sh * 0.7)), fill=(255, 176, 30))
    y += sh + 10
    # blue notice strip
    nh = int(h_px * 0.085)
    d.rectangle([m + 6, y, w_px - m - 6, y + nh], fill=BLUE)
    d.text((m + 14, y + 4), "Oyster: buy, top up and refund" if big else "Oyster top-up", font=F(FS, int(nh * 0.36)), fill=(255, 255, 255))
    d.text((m + 14, y + nh * 0.55), "Bank cards, notes and coins" if big else "Bank cards only", font=F(FS, int(nh * 0.3)), fill=(225, 230, 255))
    y += nh + 12
    # touchscreen
    scr_h = int(h_px * 0.27)
    d.rounded_rectangle([m + 8, y, w_px - m - 8, y + scr_h], radius=8, fill=(6, 8, 14))
    d.rectangle([m + 16, y + 10, w_px - m - 16, y + 10 + int(scr_h * 0.13)], fill=(0, 52, 160))
    d.text((m + 22, y + 11), "Choose a ticket", font=F(FB, int(scr_h * 0.1)), fill=(255, 255, 255))
    bw = (w_px - 2 * m - 48) // 2
    for r in range(3):
        for c in range(2):
            x0 = m + 18 + c * (bw + 10)
            y0 = y + 12 + int(scr_h * 0.18) + r * int(scr_h * 0.26)
            d.rounded_rectangle([x0, y0, x0 + bw, y0 + int(scr_h * 0.22)], radius=5, fill=(24, 86, 210))
    y += scr_h + 16
    # Oyster yellow disc and card / PIN block
    disc = int(w_px * 0.2)
    d.ellipse([m + 16, y, m + 16 + disc, y + disc], fill=(255, 205, 0), outline=(90, 90, 96), width=4)
    d.ellipse([m + 16 + disc * 0.3, y + disc * 0.3, m + 16 + disc * 0.7, y + disc * 0.7], outline=(70, 70, 76), width=3)
    if big:
        d.rectangle([w_px - m - 16 - int(w_px * 0.3), y, w_px - m - 16, y + int(disc * 0.6)], fill=(22, 24, 28), outline=(90, 92, 98))
        for r in range(3):
            for c in range(3):
                d.rectangle([w_px - m - 16 - int(w_px * 0.27) + c * int(w_px * 0.085), y + 6 + r * 14, w_px - m - 16 - int(w_px * 0.27) + c * int(w_px * 0.085) + 18, y + 16 + r * 14], fill=(150, 152, 158))
        d.rectangle([w_px - m - 16 - int(w_px * 0.3), y + int(disc * 0.7), w_px - m - 16, y + int(disc * 0.78)], fill=(190, 30, 30))
    y += disc + 18
    # note and coin slots, hopper
    if big:
        d.rectangle([m + 20, y, w_px - m - 20, y + 10], fill=(8, 8, 10))
        d.rectangle([m + 20, y + 22, w_px // 2, y + 30], fill=(8, 8, 10))
        y += 50
    d.rectangle([m + 10, y, w_px - m - 10, h_px - m - 10], fill=(14, 15, 18), outline=(120, 122, 126), width=3)
    d.text((m + 22, y + 8), "Tickets  Change" if big else "Tickets", font=F(FS, 22), fill=(200, 202, 206))
    im.save(os.path.join(OUT, name))


def tickets_sign():
    im = Image.new("RGB", (800, 110), BLUE)
    d = ImageDraw.Draw(im)
    d.text((34, 10), "Tickets", font=F(FB, 88), fill=(255, 255, 255))
    d.ellipse([690, 22, 762, 94], outline=(255, 255, 255), width=6)
    d.text((718, 26), "i", font=F(FB, 52), fill=(255, 255, 255))
    im.save(os.path.join(OUT, "tickets_sign.png"))


def newspaper():
    im = Image.new("RGB", (256, 512), (20, 54, 160))
    d = ImageDraw.Draw(im)
    d.rectangle([20, 40, 236, 250], fill=(245, 245, 240))
    d.text((34, 60), "THE", font=F(FB, 34), fill=(20, 20, 26))
    d.text((34, 92), "DAILY", font=F(FB, 54), fill=(200, 30, 40))
    d.text((34, 146), "LONDONER", font=F(FB, 38), fill=(20, 20, 26))
    d.text((34, 196), "Free. Take one.", font=F(FS, 24), fill=(60, 60, 66))
    d.rectangle([20, 300, 236, 470], fill=(12, 36, 120))
    d.text((34, 320), "Please recycle", font=F(FS, 30), fill=(255, 255, 255))
    d.text((34, 360), "your paper here", font=F(FS, 30), fill=(255, 255, 255))
    im.save(os.path.join(OUT, "newspaper.png"))


def helppoint():
    im = Image.new("RGB", (512, 512), (242, 243, 244))
    d = ImageDraw.Draw(im)
    d.ellipse([16, 16, 496, 496], outline=(20, 40, 160), width=22)
    d.ellipse([196, 70, 316, 190], fill=(24, 86, 210))
    d.text((240, 76), "i", font=F(FB, 100), fill=(255, 255, 255))
    d.ellipse([196, 210, 316, 330], fill=(30, 150, 70))
    d.text((222, 228), "!", font=F(FB, 100), fill=(255, 255, 255))
    d.rectangle([216, 352, 296, 412], fill=(200, 35, 35))
    d.text((150, 425), "HELP POINT", font=F(FB, 44), fill=(20, 40, 160))
    im.save(os.path.join(OUT, "helppoint.png"))


if __name__ == "__main__":
    perforated()
    timber()
    machine("mfm_front.png", 576, 896, True)
    machine("tvm_front.png", 320, 896, False)
    tickets_sign()
    newspaper()
    helppoint()
    print("wrote", sorted(os.listdir(OUT)))
