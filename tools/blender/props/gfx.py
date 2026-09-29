"""Small PIL drawing helpers shared by decal + poster generators (super-sampled, antialiased)."""
import os, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))
FONTDIR = os.path.join(ROOT, 'assets', 'fonts')
_fc = {}

FONT_FILES = {
    'head': 'HammersmithOne-Regular.ttf',        # Gill-ish humanist: headings
    'bold': 'Barlow-Bold.ttf',
    'semi': 'Barlow-SemiBold.ttf',
    'reg': 'Barlow-Regular.ttf',
    'cond': 'BarlowCondensed-SemiBold.ttf',
    'dot': 'DotGothic16.ttf',
}


def font(kind, size):
    key = (kind, int(size))
    if key not in _fc:
        _fc[key] = ImageFont.truetype(os.path.join(FONTDIR, FONT_FILES[kind]), int(size))
    return _fc[key]


class Canvas:
    """draw at SS x resolution then downsample. coordinates given in final pixels (floats ok)."""
    def __init__(self, w, h, bg=(0, 0, 0, 0), ss=2, opaque=False):
        """opaque=True: RGB canvas whose draw calls alpha-BLEND (translucent fills work as expected)."""
        self.w, self.h, self.ss = w, h, ss
        self.opaque = opaque
        if opaque:
            self.im = Image.new('RGB', (int(w * ss), int(h * ss)), tuple(bg[:3]))
            self.d = ImageDraw.Draw(self.im, 'RGBA')
        else:
            self.im = Image.new('RGBA', (int(w * ss), int(h * ss)), bg)
            self.d = ImageDraw.Draw(self.im)

    def _redraw(self):
        self.d = ImageDraw.Draw(self.im, 'RGBA') if self.opaque else ImageDraw.Draw(self.im)

    def blit(self, img, x, y):
        """composite an RGBA image (already at supersampled scale) at supersampled pixel position (x, y)"""
        if self.opaque:
            self.im.paste(img.convert('RGB'), (int(x), int(y)), img.getchannel('A'))
        else:
            self.im.alpha_composite(img, (int(x), int(y)))
        self._redraw()

    def S(self, v):
        return v * self.ss

    def pts(self, pts):
        return [(x * self.ss, y * self.ss) for (x, y) in pts]

    def rect(self, x0, y0, x1, y1, fill=None, outline=None, width=1, r=0):
        s = self.ss
        if r > 0:
            self.d.rounded_rectangle([x0 * s, y0 * s, x1 * s, y1 * s], radius=r * s, fill=fill, outline=outline, width=int(width * s))
        else:
            self.d.rectangle([x0 * s, y0 * s, x1 * s, y1 * s], fill=fill, outline=outline, width=int(width * s))

    def ellipse(self, x0, y0, x1, y1, fill=None, outline=None, width=1):
        s = self.ss
        self.d.ellipse([x0 * s, y0 * s, x1 * s, y1 * s], fill=fill, outline=outline, width=int(width * s))

    def circle(self, cx, cy, r, fill=None, outline=None, width=1):
        self.ellipse(cx - r, cy - r, cx + r, cy + r, fill, outline, width)

    def poly(self, pts, fill=None, outline=None, width=1):
        self.d.polygon(self.pts(pts), fill=fill, outline=outline, width=int(width * self.ss))

    def line(self, pts, fill, width=1, joint='curve'):
        self.d.line(self.pts(pts), fill=fill, width=max(1, int(width * self.ss)), joint=joint)

    def arc(self, cx, cy, r, a0, a1, fill, width=1):
        s = self.ss
        self.d.arc([(cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s], a0, a1, fill=fill, width=max(1, int(width * s)))

    def text(self, x, y, txt, kind='semi', size=20, fill=(255, 255, 255, 255), anchor='la', spacing=4, align='left', stroke=0, stroke_fill=None):
        f = font(kind, size * self.ss)
        if '\n' in txt:
            self.d.multiline_text((x * self.ss, y * self.ss), txt, font=f, fill=fill, anchor=anchor, spacing=spacing * self.ss, align=align)
        else:
            self.d.text((x * self.ss, y * self.ss), txt, font=f, fill=fill, anchor=anchor, stroke_width=int(stroke * self.ss), stroke_fill=stroke_fill)

    def text_w(self, txt, kind, size):
        f = font(kind, size * self.ss)
        return f.getlength(txt) / self.ss

    def paste(self, im, x, y, mask=None):
        s = self.ss
        im2 = im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS) if im.size != (0, 0) else im
        self.im.alpha_composite(im2, (int(x * s), int(y * s))) if im2.mode == 'RGBA' else self.im.paste(im2, (int(x * s), int(y * s)))

    def layer(self):
        """new transparent layer (same size) with its own draw handle; composite() merges it."""
        l = Image.new('RGBA', self.im.size, (0, 0, 0, 0))
        return l, ImageDraw.Draw(l)

    def composite(self, layer, blur=0.0):
        if blur > 0:
            layer = layer.filter(ImageFilter.GaussianBlur(blur * self.ss))
        self.blit(layer, 0, 0)

    def out(self):
        return self.im.resize((self.w, self.h), Image.LANCZOS)

    def star(self, cx, cy, r, fill, points=5):
        pts = []
        for k in range(points * 2):
            a = -math.pi / 2 + k * math.pi / points
            rr = r if k % 2 == 0 else r * 0.42
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        self.poly(pts, fill=fill)


def vgradient(w, h, top, bottom):
    import numpy as np
    t = np.linspace(0, 1, h)[:, None, None]
    a = np.array(top, np.float32)[None, None, :]; b = np.array(bottom, np.float32)[None, None, :]
    arr = (a * (1 - t) + b * t)
    arr = np.repeat(arr, w, axis=1)
    return Image.fromarray(arr.astype('uint8'), 'RGBA' if arr.shape[2] == 4 else 'RGB')


def arrow(c, cx, cy, size, angle_deg, fill, shaft=0.22, head=0.5):
    """block arrow centred at (cx,cy), length `size`, pointing at angle (0 = right, 90 = down)"""
    L = size; sw = size * shaft; hw = size * head
    hl = size * 0.5
    pts = [(-L / 2, -sw / 2), (L / 2 - hl, -sw / 2), (L / 2 - hl, -hw / 2), (L / 2, 0), (L / 2 - hl, hw / 2), (L / 2 - hl, sw / 2), (-L / 2, sw / 2)]
    a = math.radians(angle_deg)
    ca, sa = math.cos(a), math.sin(a)
    c.poly([(cx + x * ca - y * sa, cy + x * sa + y * ca) for (x, y) in pts], fill=fill)


def contactless(c, cx, cy, r, fill, width=None, rot=0):
    """generic 'waves' symbol (four arcs) - not a reproduction of any scheme mark"""
    width = width or r * 0.12
    for k in range(4):
        rr = r * (0.28 + 0.24 * k)
        c.arc(cx - r * 0.35, cy, rr, -40 + rot, 40 + rot, fill, width)
    c.circle(cx - r * 0.35 - r * 0.0, cy, r * 0.05, fill)


def tick(c, cx, cy, s, fill, width):
    c.line([(cx - s * 0.5, cy), (cx - s * 0.15, cy + s * 0.38), (cx + s * 0.55, cy - s * 0.42)], fill, width)


def cross(c, cx, cy, s, fill, width):
    c.line([(cx - s / 2, cy - s / 2), (cx + s / 2, cy + s / 2)], fill, width)
    c.line([(cx - s / 2, cy + s / 2), (cx + s / 2, cy - s / 2)], fill, width)


def wheelchair(c, cx, cy, s, fill):
    """generic accessibility pictogram (ISA-like, simplified)"""
    w = s * 0.09
    c.circle(cx - s * 0.05, cy - s * 0.38, s * 0.09, fill)
    c.line([(cx - s * 0.05, cy - s * 0.26), (cx - s * 0.05, cy + s * 0.05), (cx + s * 0.28, cy + s * 0.05), (cx + s * 0.36, cy + s * 0.38)], fill, w)
    c.line([(cx - s * 0.05, cy - s * 0.12), (cx + s * 0.22, cy - s * 0.12)], fill, w)
    c.arc(cx - s * 0.08, cy + s * 0.14, s * 0.30, 40, 250, fill, w)


def person(c, cx, cy, s, fill):
    c.circle(cx, cy - s * 0.36, s * 0.10, fill)
    c.rect(cx - s * 0.13, cy - s * 0.22, cx + s * 0.13, cy + s * 0.12, fill, r=s * 0.06)
    c.rect(cx - s * 0.11, cy + s * 0.08, cx - s * 0.02, cy + s * 0.42, fill, r=s * 0.03)
    c.rect(cx + s * 0.02, cy + s * 0.08, cx + s * 0.11, cy + s * 0.42, fill, r=s * 0.03)
