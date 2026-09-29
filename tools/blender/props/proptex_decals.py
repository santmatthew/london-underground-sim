#!/usr/bin/env python3
"""Printed / emissive decal textures for the props -> assets/textures/props/decals/<name>_c.png
Everything is invented/generic (no real brand artwork). run with build/venv/bin/python (optionally: names to build)."""
import os, sys, math, random
import numpy as np
from PIL import Image, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gfx import *

OUT = os.path.join(ROOT, 'assets', 'textures', 'props', 'decals')
REG = {}


def decal(name, w, h):
    def deco(fn):
        REG[name] = (w, h, fn)
        return fn
    return deco


def rgba(r, g, b, a=255):
    return (r, g, b, a)


NAVY = (12, 26, 96, 255)
BLUE = (16, 38, 150, 255)
WHITE = (245, 246, 244, 255)
YEL = (255, 209, 0, 255)
RED = (214, 32, 38, 255)
GREEN = (40, 200, 90, 255)
DARK = (18, 20, 24, 255)


# ------------------------------------------------------------------------------------------------ gates
@decal('gate_reader', 256, 256)
def _(c):
    c.rect(0, 0, 256, 256, fill=(14, 15, 18, 255))
    c.circle(128, 128, 92, fill=(24, 26, 32, 255), outline=(60, 64, 72, 255), width=3)
    contactless(c, 128, 128, 70, (222, 226, 232, 255), width=9)


@decal('gate_display', 256, 128)
def _(c):
    c.rect(0, 0, 256, 128, fill=(4, 10, 40, 255))
    c.rect(0, 0, 256, 34, fill=(16, 50, 170, 255))
    c.text(128, 17, 'TAP IN', 'bold', 26, WHITE, anchor='mm')
    contactless(c, 70, 84, 30, WHITE, width=4)
    c.text(178, 84, 'Card or\ndevice', 'semi', 22, (200, 220, 255, 255), anchor='mm', spacing=2, align='center')


@decal('lamp_go', 128, 128)
def _(c):
    c.rect(0, 0, 128, 128, fill=(2, 10, 4, 255))
    arrow(c, 64, 64, 78, 90, (60, 255, 110, 255), shaft=0.34, head=0.78)


@decal('lamp_stop', 128, 128)
def _(c):
    c.rect(0, 0, 128, 128, fill=(12, 2, 2, 255))
    cross(c, 64, 64, 66, (255, 40, 30, 255), 16)


@decal('gate_endwrap', 256, 1024)
def _(c):
    c.rect(0, 0, 256, 1024, fill=(228, 233, 238, 255))
    c.rect(0, 0, 256, 1024, fill=(228, 233, 238, 255))
    c.rect(0, 0, 256, 190, fill=(16, 38, 150, 255))
    c.text(128, 60, 'Have a', 'head', 46, WHITE, anchor='mm')
    c.text(128, 122, 'good trip', 'head', 46, WHITE, anchor='mm')
    contactless(c, 116, 330, 120, (16, 38, 150, 255), width=13)
    c.text(128, 500, 'Tap in.', 'bold', 54, (16, 38, 150, 255), anchor='mm')
    c.text(128, 566, 'Tap out.', 'bold', 54, (16, 38, 150, 255), anchor='mm')
    c.rect(28, 640, 228, 646, fill=(16, 38, 150, 255))
    c.text(128, 720, 'Keep moving\nthrough the gate', 'semi', 30, (60, 66, 84, 255), anchor='mm', align='center', spacing=6)
    c.rect(0, 900, 256, 1024, fill=YEL)
    arrow(c, 128, 962, 110, 90, DARK, shaft=0.3, head=0.75)


@decal('gate_ticketslot', 128, 128)
def _(c):
    c.rect(0, 0, 128, 128, fill=(24, 26, 30, 255))
    c.rect(14, 54, 114, 74, fill=(2, 2, 3, 255), r=6)
    arrow(c, 64, 100, 34, 90, YEL, shaft=0.3, head=0.9)


def main():
    import importlib
    pd = importlib.import_module('proptex_decals')      # the importable twin (so extra modules register into ITS REG)
    os.makedirs(OUT, exist_ok=True)
    for m in ('decals_machines', 'decals_wall', 'decals_retail'):
        try:
            importlib.import_module(m)
        except ModuleNotFoundError as e:
            if e.name != m:
                raise
    want = sys.argv[1:]
    for name, (w, h, fn) in pd.REG.items():
        if want and name not in want:
            continue
        c = Canvas(w, h, bg=(0, 0, 0, 255), opaque=True)
        fn(c)
        c.out().save(os.path.join(OUT, name + '_c.png'), optimize=True)
        print('decal', name, w, h)


if __name__ == '__main__':
    main()
