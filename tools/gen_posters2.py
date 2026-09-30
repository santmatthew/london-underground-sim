#!/usr/bin/env python3
"""Generates the second FICTIONAL poster library -> assets/textures/props/posters2/*.png + manifest.json

Formats (aspect = width/height of the VISIBLE display area, see build/refs_dress/ads_maps/SPEC.md):
  portrait 4/6-sheet   0.66  1024x1552   40 commercial designs
  landscape 16-sheet   1.52  1536x1010   30
  landscape 48/12-sheet 2.03 2048x1008   24
  TfL Double Royal     0.625  768x1229   14 information posters
  TfL Quad Royal       1.25  1280x1024    6 map / engineering panels
All brands, show titles, slogans, prices and phone numbers are INVENTED. TfL / Mayor / roundel marks appear only on the
TfL information posters. Everything is procedural (PIL + numpy): no downloaded imagery.
Run:  build/venv/bin/python tools/gen_posters2.py [--only name,name] [--sheets]   (parallel, ~1-2 min)
"""
import os, sys, math, random, json, time, datetime
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'blender', 'props'))
from gfx import Canvas, ROOT, FONTDIR  # noqa: E402

OUT = os.path.join(ROOT, 'assets', 'textures', 'props', 'posters2')

# ------------------------------------------------------------------------------------------------ colours
WHITE = (255, 255, 255)
BLACK = (10, 10, 12)


def hexc(h):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def rgba(c, a=255):
    c = tuple(c)
    return (int(c[0]), int(c[1]), int(c[2]), int(c[3]) if len(c) > 3 and a == 255 else int(a))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def light(c, t):
    return mix(c, WHITE, t)


def dark(c, t):
    return mix(c, (0, 0, 0), t)


# ------------------------------------------------------------------------------------------------ fonts
FONT_FILES = {
    'bold': 'Barlow-Bold.ttf', 'semi': 'Barlow-SemiBold.ttf', 'reg': 'Barlow-Regular.ttf',
    'cond': 'BarlowCondensed-SemiBold.ttf', 'head': 'HammersmithOne-Regular.ttf',
    'serif': 'LibreBaskerville-Bold.ttf', 'dot': 'DotGothic16.ttf',
}
_fc = {}
_glyph_ok = {}


def font(kind, size):
    key = (kind, int(round(size)))
    if key not in _fc:
        _fc[key] = ImageFont.truetype(os.path.join(FONTDIR, FONT_FILES[kind]), max(1, int(round(size))))
    return _fc[key]


def glyph_missing(kind, txt):
    """characters of txt that the font renders as .notdef"""
    f = font(kind, 48)
    if (kind, '__nd') not in _glyph_ok:
        _glyph_ok[(kind, '__nd')] = bytes(f.getmask('￿'))
    nd = _glyph_ok[(kind, '__nd')]
    bad = []
    for ch in set(txt):
        if ch in ' \n':
            continue
        k = (kind, ch)
        if k not in _glyph_ok:
            _glyph_ok[k] = bytes(f.getmask(ch)) != nd
        if not _glyph_ok[k]:
            bad.append(ch)
    return bad


# ------------------------------------------------------------------------------------------------ poster canvas
class P:
    """A poster being drawn. Coordinates are in FINAL pixels; drawing happens at ss x resolution."""

    def __init__(self, W, H, ss=2, bg=(0, 0, 0), margin=(40, 40), name=''):
        self.W, self.H, self.ss = W, H, ss
        self.c = Canvas(W, H, bg=tuple(bg) + (255,), ss=ss, opaque=True)
        self.margin = margin
        self.name = name
        self.texts = []
        self.warn = []
        self.rng = random.Random(1)

    @property
    def im(self):
        return self.c.im

    # thin wrappers (poster coords)
    def rect(self, x0, y0, x1, y1, fill=None, outline=None, width=1, r=0):
        self.c.rect(x0, y0, x1, y1, fill=None if fill is None else rgba(fill), outline=None if outline is None else rgba(outline), width=width, r=r)

    def circle(self, cx, cy, r, fill=None, outline=None, width=1):
        self.c.circle(cx, cy, r, fill=None if fill is None else rgba(fill), outline=None if outline is None else rgba(outline), width=width)

    def ellipse(self, x0, y0, x1, y1, fill=None, outline=None, width=1):
        self.c.ellipse(x0, y0, x1, y1, fill=None if fill is None else rgba(fill), outline=None if outline is None else rgba(outline), width=width)

    def poly(self, pts, fill=None, outline=None, width=1):
        self.c.poly(pts, fill=None if fill is None else rgba(fill), outline=None if outline is None else rgba(outline), width=width)

    def line(self, pts, fill, width=1, joint='curve'):
        self.c.line(pts, rgba(fill), width, joint)

    def pline(self, pts, w, fill):
        """polyline with round caps and joints"""
        f = rgba(fill)
        self.c.line(pts, f, w, 'curve')
        for (x, y) in pts:
            self.c.circle(x, y, w / 2.0, fill=f)

    def arc(self, cx, cy, r, a0, a1, fill, width=1):
        self.c.arc(cx, cy, r, a0, a1, rgba(fill), width)

    def star(self, cx, cy, r, fill, points=5, inner=0.42, rot=0):
        pts = []
        for k in range(points * 2):
            a = -math.pi / 2 + rot + k * math.pi / points
            rr = r if k % 2 == 0 else r * inner
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        self.poly(pts, fill=fill)


# ------------------------------------------------------------------------------------------------ compositing helpers
def blit(p, img, x, y, alpha=1.0):
    """composite straight-alpha RGBA image (already at ss scale) at ss pixel position"""
    a = img.getchannel('A')
    if alpha != 1.0:
        a = a.point(lambda v: int(v * alpha))
    p.c.im.paste(img.convert('RGB'), (int(x), int(y)), a)


def paste_solid(p, col, x, y, mask, alpha=1.0):
    if alpha != 1.0:
        mask = mask.point(lambda v: int(v * alpha))
    p.c.im.paste(tuple(col[:3]), (int(x), int(y), int(x) + mask.width, int(y) + mask.height), mask)


def lin_grad(w, h, stops, angle=90.0):
    """HxWx3 float32 linear gradient. angle 90 = top->bottom, 0 = left->right. stops [(t,(r,g,b)),...]"""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    a = math.radians(angle)
    ca, sa = math.cos(a), math.sin(a)
    L = abs(w * ca) + abs(h * sa)
    t = ((xs - w / 2.0) * ca + (ys - h / 2.0) * sa) / max(L, 1e-6) + 0.5
    ts = [s[0] for s in stops]
    cols = np.array([s[1][:3] for s in stops], np.float32)
    out = np.empty((h, w, 3), np.float32)
    for k in range(3):
        out[..., k] = np.interp(t, ts, cols[:, k])
    return out


def to_img(arr):
    return Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), 'RGB')


def grad(p, stops, angle=90.0, box=None):
    """fill the poster (or box) with a linear gradient"""
    ss = p.ss
    if box is None:
        box = (0, 0, p.W, p.H)
    x0, y0, x1, y1 = [int(round(v * ss)) for v in box]
    arr = lin_grad(x1 - x0, y1 - y0, stops, angle)
    p.c.im.paste(to_img(arr), (x0, y0))


def gshape(p, kind, geom, stops, angle=90.0, alpha=1.0, blur=0):
    """gradient-filled shape. kind: 'rrect' (x0,y0,x1,y1,r) | 'ell' (x0,y0,x1,y1) | 'poly' [(x,y)..]"""
    ss = p.ss
    if kind == 'poly':
        xs = [q[0] for q in geom]; ys = [q[1] for q in geom]
        bx0, by0, bx1, by1 = min(xs), min(ys), max(xs), max(ys)
    else:
        bx0, by0, bx1, by1 = geom[0], geom[1], geom[2], geom[3]
    ix0, iy0 = int(math.floor(bx0 * ss)) - 1, int(math.floor(by0 * ss)) - 1
    ix1, iy1 = int(math.ceil(bx1 * ss)) + 1, int(math.ceil(by1 * ss)) + 1
    w, h = ix1 - ix0, iy1 - iy0
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    if kind == 'poly':
        d.polygon([(q[0] * ss - ix0, q[1] * ss - iy0) for q in geom], fill=255)
    elif kind == 'rrect':
        d.rounded_rectangle([geom[0] * ss - ix0, geom[1] * ss - iy0, geom[2] * ss - ix0, geom[3] * ss - iy0], radius=geom[4] * ss, fill=255)
    else:
        d.ellipse([geom[0] * ss - ix0, geom[1] * ss - iy0, geom[2] * ss - ix0, geom[3] * ss - iy0], fill=255)
    if blur:
        m = m.filter(ImageFilter.GaussianBlur(blur * ss))
    if alpha != 1.0:
        m = m.point(lambda v: int(v * alpha))
    arr = lin_grad(w, h, stops, angle)
    p.c.im.paste(to_img(arr), (ix0, iy0), m)


def glow(p, cx, cy, r, color, a=0.8, power=2.0, ry=None, mode='over'):
    """soft radial glow. a = peak opacity 0..1; mode 'over' | 'screen' (additive light)"""
    ss = p.ss
    ry = ry or r
    x0 = max(0, int((cx - r) * ss)); x1 = min(p.im.width, int((cx + r) * ss))
    y0 = max(0, int((cy - ry) * ss)); y1 = min(p.im.height, int((cy + ry) * ss))
    if x1 <= x0 or y1 <= y0:
        return
    q = 4
    w, h = max(2, (x1 - x0) // q), max(2, (y1 - y0) // q)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    px = (x0 + xs * q) / ss; py = (y0 + ys * q) / ss
    d = np.sqrt(((px - cx) / r) ** 2 + ((py - cy) / ry) ** 2)
    m = np.clip(1 - d, 0, 1) ** power * a
    mi = Image.fromarray((m * 255).astype(np.uint8), 'L').resize((x1 - x0, y1 - y0), Image.BICUBIC)
    if mode == 'over':
        p.c.im.paste(tuple(color[:3]), (x0, y0, x1, y1), mi)
    else:
        base = np.asarray(p.c.im.crop((x0, y0, x1, y1)), np.float32) / 255.0
        mm = np.asarray(mi, np.float32)[..., None] / 255.0
        col = np.array(color[:3], np.float32)[None, None, :] / 255.0
        out = 1 - (1 - base) * (1 - col * mm)
        p.c.im.paste(Image.fromarray((out * 255).astype(np.uint8), 'RGB'), (x0, y0))


class Soft:
    """low-resolution RGBA layer drawn in poster coordinates; done() blurs it (premultiplied) and composites."""

    def __init__(self, p, box=None, scale=0.25):
        self.p = p
        self.box = box or (0, 0, p.W, p.H)
        self.s = scale
        x0, y0, x1, y1 = self.box
        self.w = max(2, int(math.ceil((x1 - x0) * scale)))
        self.h = max(2, int(math.ceil((y1 - y0) * scale)))
        self.im = Image.new('RGBA', (self.w, self.h), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def _q(self, pts):
        x0, y0 = self.box[0], self.box[1]
        return [((x - x0) * self.s, (y - y0) * self.s) for (x, y) in pts]

    def circle(self, cx, cy, r, fill):
        (a, b), = self._q([(cx, cy)])
        self.d.ellipse([a - r * self.s, b - r * self.s, a + r * self.s, b + r * self.s], fill=rgba(fill))

    def ellipse(self, x0, y0, x1, y1, fill):
        q = self._q([(x0, y0), (x1, y1)])
        self.d.ellipse([q[0][0], q[0][1], q[1][0], q[1][1]], fill=rgba(fill))

    def rect(self, x0, y0, x1, y1, fill, r=0):
        q = self._q([(x0, y0), (x1, y1)])
        if r:
            self.d.rounded_rectangle([q[0][0], q[0][1], q[1][0], q[1][1]], radius=r * self.s, fill=rgba(fill))
        else:
            self.d.rectangle([q[0][0], q[0][1], q[1][0], q[1][1]], fill=rgba(fill))

    def poly(self, pts, fill):
        self.d.polygon(self._q(pts), fill=rgba(fill))

    def line(self, pts, fill, width=1):
        self.d.line(self._q(pts), fill=rgba(fill), width=max(1, int(width * self.s)))

    def done(self, blur=0.0, alpha=1.0):
        im = self.im
        if blur > 0:
            a = np.asarray(im, np.float32)
            al = a[..., 3:4] / 255.0
            chans = [Image.fromarray((a[..., k] * al[..., 0]).astype(np.uint8), 'L') for k in range(3)]
            chans.append(im.getchannel('A'))
            r = blur * self.s
            chans = [c.filter(ImageFilter.GaussianBlur(r)) for c in chans]
            A = np.asarray(chans[3], np.float32) / 255.0
            rgb = np.stack([np.asarray(c, np.float32) for c in chans[:3]], -1) / np.maximum(A[..., None], 1e-3)
            out = np.concatenate([np.clip(rgb, 0, 255), (A * 255)[..., None]], -1).astype(np.uint8)
            im = Image.fromarray(out, 'RGBA')
        ss = self.p.ss
        x0, y0, x1, y1 = self.box
        W, H = int(round((x1 - x0) * ss)), int(round((y1 - y0) * ss))
        up = im.resize((W, H), Image.BICUBIC)
        blit(self.p, up, x0 * ss, y0 * ss, alpha)


def shadow(p, kind, geom, off=(0, 14), blur=18, alpha=0.35, color=(0, 0, 0), pad=None):
    """soft drop shadow. kind 'rrect'(x0,y0,x1,y1,r) | 'ell'(x0,y0,x1,y1) | 'poly'(pts)"""
    pad = pad if pad is not None else blur * 3
    if kind == 'poly':
        xs = [q[0] for q in geom]; ys = [q[1] for q in geom]
        bb = (min(xs), min(ys), max(xs), max(ys))
    else:
        bb = geom[:4]
    box = (bb[0] - pad + off[0], bb[1] - pad + off[1], bb[2] + pad + off[0], bb[3] + pad + off[1])
    s = Soft(p, box, scale=0.5 if blur < 30 else 0.25)
    col = color + (255,)
    if kind == 'rrect':
        s.rect(geom[0] + off[0], geom[1] + off[1], geom[2] + off[0], geom[3] + off[1], col, r=geom[4])
    elif kind == 'ell':
        s.ellipse(geom[0] + off[0], geom[1] + off[1], geom[2] + off[0], geom[3] + off[1], col)
    else:
        s.poly([(x + off[0], y + off[1]) for (x, y) in geom], col)
    s.done(blur=blur, alpha=alpha)


def smooth(pts, n=10, closed=True):
    """Catmull-Rom spline through pts -> dense polyline"""
    N = len(pts)
    out = []
    rng_ = range(N) if closed else range(N - 1)
    for i in rng_:
        p0 = pts[(i - 1) % N] if (closed or i > 0) else pts[i]
        p1 = pts[i]
        p2 = pts[(i + 1) % N]
        p3 = pts[(i + 2) % N] if (closed or i + 2 < N) else pts[(i + 1) % N]
        for k in range(n):
            t = k / float(n)
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    if not closed:
        out.append(pts[-1])
    return out


def rot_pts(pts, cx, cy, ang):
    a = math.radians(ang)
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for (x, y) in pts]


def xform(pts, cx, cy, s=1.0, ang=0.0, flip=False):
    """scale about origin (points are relative to 0,0), optional x flip, rotate by ang, translate to cx,cy"""
    out = []
    a = math.radians(ang)
    ca, sa = math.cos(a), math.sin(a)
    for (x, y) in pts:
        if flip:
            x = -x
        x *= s; y *= s
        out.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    return out


# ------------------------------------------------------------------------------------------------ text engine
def cap_h(kind, size):
    f = font(kind, size * 4)
    return -f.getbbox('H', anchor='ls')[1] / 4.0


def text_w(kind, size, txt, track=0.0, sx=1.0):
    f = font(kind, size * 4)
    if track:
        w = sum(f.getlength(ch) for ch in txt) + track * size * 4 * (len(txt) - 1)
    else:
        w = f.getlength(txt)
    return w / 4.0 * sx


def fit_size(kind, txt, w, track=0.0, sx=1.0, max_size=2000, hmax=None):
    """font size at which txt is w wide (optionally capped so cap height <= hmax)"""
    base = text_w(kind, 100, txt, track, sx)
    s = 100.0 * w / max(base, 1e-6)
    if hmax:
        s = min(s, hmax / (cap_h(kind, 100) / 100.0))
    return min(s, max_size)


def _tf_mask(m, ax, ay, sx, shear, rot, baseline):
    if sx != 1.0:
        m = m.resize((max(1, int(m.width * sx)), m.height), Image.BICUBIC)
        ax *= sx
    if shear:
        h = m.height
        ox = max(0.0, -shear * (baseline - 0), -shear * (baseline - h))
        span = int(abs(shear) * h) + 2
        m = m.transform((m.width + span, h), Image.AFFINE, (1, shear, -shear * baseline - ox, 0, 1, 0), Image.BICUBIC)
        ax = ax + shear * (baseline - ay) + ox
    if rot:
        w0, h0 = m.size
        m = m.rotate(rot, resample=Image.BICUBIC, expand=True)
        a = math.radians(rot)
        dx, dy = ax - w0 / 2.0, ay - h0 / 2.0
        ax = m.width / 2.0 + dx * math.cos(a) + dy * math.sin(a)
        ay = m.height / 2.0 - dx * math.sin(a) + dy * math.cos(a)
    return m, ax, ay


def T(p, txt, x, y, kind='bold', size=40, fill=WHITE, anchor='ls', track=0.0, sx=1.0, shear=0.0, rot=0.0,
      stroke=0, stroke_fill=None, shadow_=None, extrude=None, grad_=None, glow_=None, alpha=1.0, qa=True, over=False,
      hollow=False):
    """Draw text. anchor: h in l/m/r, v in t (cap top) / m (cap middle) / s (baseline).
    track = letter spacing in em. sx = horizontal stretch, shear = italic slant (0.2), rot = degrees CCW.
    shadow_=(dx,dy,blur,(r,g,b),alpha)  extrude=(depth,(r,g,b),dx,dy)  grad_=((c0,c1),angle)  glow_=(radius,color,alpha)
    stroke=px outline of stroke_fill; hollow=True draws only the stroke (outlined type).
    returns bbox (x0,y0,x1,y1) in poster px."""
    ss = p.ss
    bad = glyph_missing(kind, txt)
    if bad:
        p.warn.append('missing glyph %r in %s: %r' % (''.join(bad), kind, txt[:30]))
    f = font(kind, size * ss)
    asc, desc = f.getmetrics()
    ch = -f.getbbox('H', anchor='ls')[1]
    if track:
        adv = [f.getlength(c) for c in txt]
        total = sum(adv) + track * size * ss * (len(txt) - 1)
    else:
        total = f.getlength(txt)
    ext_n = 0
    if extrude:
        ext_n = int(extrude[0] * ss)
    pad = int(max(stroke * ss, 0) + ext_n + (shadow_[2] * ss * 3 + max(abs(shadow_[0]), abs(shadow_[1])) * ss if shadow_ else 0) +
              (glow_[0] * ss * 2.5 if glow_ else 0) + 6 * ss)
    Wm = int(total + 2 * pad + 4)
    Hm = int(asc + desc + 2 * pad)
    base_y = pad + asc

    def draw_mask(stroke_w=0, dx=0, dy=0):
        m = Image.new('L', (Wm, Hm), 0)
        d = ImageDraw.Draw(m)
        if track:
            cx = pad + dx
            for c_, a_ in zip(txt, adv):
                d.text((cx, base_y + dy), c_, font=f, fill=255, anchor='ls', stroke_width=stroke_w)
                cx += a_ + track * size * ss
        else:
            d.text((pad + dx, base_y + dy), txt, font=f, fill=255, anchor='ls', stroke_width=stroke_w)
        return m

    fill_m = draw_mask()
    ah = {'l': 0.0, 'm': 0.5, 'r': 1.0}[anchor[0]]
    ax = pad + total * ah
    av = anchor[1]
    ay = base_y - (ch if av == 't' else ch / 2.0 if av == 'm' else 0)
    stroke_m = draw_mask(int(stroke * ss)) if stroke else None
    tfm = lambda m: _tf_mask(m, ax, ay, sx, shear, rot, base_y)[0]
    fm_t, ax2, ay2 = _tf_mask(fill_m, ax, ay, sx, shear, rot, base_y)
    X0 = int(round(x * ss - ax2)); Y0 = int(round(y * ss - ay2))
    if glow_:
        gm = fm_t.filter(ImageFilter.GaussianBlur(glow_[0] * ss))
        gm = gm.point(lambda v: min(255, int(v * 2.2 * (glow_[2] if len(glow_) > 2 else 1.0))))
        paste_solid(p, glow_[1], X0, Y0, gm, alpha)
    if shadow_:
        sm = tfm(stroke_m) if stroke_m is not None else fm_t
        sm = sm.filter(ImageFilter.GaussianBlur(shadow_[2] * ss)) if shadow_[2] else sm
        paste_solid(p, shadow_[3], X0 + shadow_[0] * ss, Y0 + shadow_[1] * ss, sm, alpha * (shadow_[4] if len(shadow_) > 4 else 0.5))
    if extrude:
        depth, ecol = extrude[0], extrude[1]
        edx = extrude[2] if len(extrude) > 2 else 0.6
        edy = extrude[3] if len(extrude) > 3 else 0.8
        base_m = tfm(stroke_m) if stroke_m is not None else fm_t
        n = max(2, int(depth * ss / 2))
        for i in range(n, 0, -1):
            t = i / float(n)
            cc = ecol if not (isinstance(ecol, list) and len(ecol) == 2) else mix(ecol[0], ecol[1], t)
            paste_solid(p, cc, X0 + int(edx * depth * ss * t), Y0 + int(edy * depth * ss * t), base_m, alpha)
    if stroke_m is not None:
        sm = tfm(stroke_m)
        paste_solid(p, stroke_fill or BLACK, X0, Y0, sm, alpha)
    if not hollow:
        if grad_:
            (c0, c1), ang = grad_[0], grad_[1]
            bb = fm_t.getbbox() or (0, 0, fm_t.width, fm_t.height)
            g = lin_grad(bb[2] - bb[0], bb[3] - bb[1], [(0, c0), (1, c1)], ang) if len(grad_[0]) == 2 else lin_grad(bb[2] - bb[0], bb[3] - bb[1], grad_[0], ang)
            gi = Image.new('RGB', fm_t.size, tuple(c0[:3]) if len(grad_[0]) == 2 else tuple(grad_[0][0][1]))
            gi.paste(to_img(g), (bb[0], bb[1]))
            mm = fm_t.point(lambda v: int(v * alpha)) if alpha != 1 else fm_t
            p.c.im.paste(gi, (X0, Y0), mm)
        else:
            paste_solid(p, fill, X0, Y0, fm_t, alpha)
    bb = fm_t.getbbox()
    if bb is None:
        return (x, y, x, y)
    box = ((X0 + bb[0]) / ss, (Y0 + bb[1]) / ss, (X0 + bb[2]) / ss, (Y0 + bb[3]) / ss)
    if qa:
        p.texts.append((txt, box, over))
    return box


def para(p, x, y, w, txt, kind='reg', size=24, fill=WHITE, lh=1.3, align='l', track=0.0, **kw):
    """word-wrapped paragraph; (x,y) is top-left of the block (y = cap-top of first line). returns bottom y."""
    lines = wrap(txt, kind, size, w, track)
    ch = cap_h(kind, size)
    yy = y + ch
    for i, ln in enumerate(lines):
        if align == 'c':
            T(p, ln, x + w / 2.0, yy + i * size * lh, kind, size, fill, 'ms', track=track, **kw)
        elif align == 'r':
            T(p, ln, x + w, yy + i * size * lh, kind, size, fill, 'rs', track=track, **kw)
        else:
            T(p, ln, x, yy + i * size * lh, kind, size, fill, 'ls', track=track, **kw)
    return y + ch + (len(lines) - 1) * size * lh + size * 0.25


def wrap(txt, kind, size, w, track=0.0):
    out = []
    for para_ in txt.split('\n'):
        cur = ''
        for wd in para_.split(' '):
            trial = (cur + ' ' + wd).strip()
            if cur and text_w(kind, size, trial, track) > w:
                out.append(cur)
                cur = wd
            else:
                cur = trial
        out.append(cur)
    return out


def para_fit(p, box, txt, kind='reg', max_size=40, min_size=12, fill=WHITE, lh=1.3, align='l', track=0.0, **kw):
    """largest size in [min,max] such that wrapped text fits in box (x0,y0,x1,y1); draws it. returns (size, bottom)"""
    x0, y0, x1, y1 = box
    size = max_size
    while size > min_size:
        n = len(wrap(txt, kind, size, x1 - x0, track))
        hh = cap_h(kind, size) + (n - 1) * size * lh
        if hh <= (y1 - y0):
            break
        size -= 1
    return size, para(p, x0, y0, x1 - x0, txt, kind, size, fill, lh, align, track, **kw)


def stack(p, lines, x, y, w, kind='bold', fills=None, gap=0.16, align='l', fit=True, size=None, track=0.0, sx=1.0, max_size=1000,
          anchor_y='t', **kw):
    """stacked headline: each line fitted to width w (fit=True) or at fixed size. (x,y): left edge and cap-top of first line.
    returns (bottom_y, sizes)"""
    if not isinstance(kind, (list, tuple)):
        kind = [kind] * len(lines)
    if fills is None:
        fills = [WHITE]
    yy = y
    sizes = []
    for i, ln in enumerate(lines):
        k = kind[i]
        s = fit_size(k, ln, w, track, sx, max_size) if fit else size
        if size and fit and s > size:
            s = size
        ch = cap_h(k, s)
        f_ = fills[i % len(fills)]
        base = yy + ch
        if align == 'c':
            T(p, ln, x + w / 2.0, base, k, s, f_, 'ms', track=track, sx=sx, **kw)
        elif align == 'r':
            T(p, ln, x + w, base, k, s, f_, 'rs', track=track, sx=sx, **kw)
        else:
            T(p, ln, x, base, k, s, f_, 'ls', track=track, sx=sx, **kw)
        sizes.append(s)
        yy = base + ch * gap
    return yy, sizes


def pill(p, x0, y0, x1, y1, fill, txt, kind='bold', size=34, tcol=WHITE, track=0.0, outline=None, r=None):
    p.rect(x0, y0, x1, y1, fill=fill, outline=outline, width=3, r=(y1 - y0) / 2.0 if r is None else r)
    T(p, txt, (x0 + x1) / 2.0, (y0 + y1) / 2.0, kind, size, tcol, 'mm', track=track)


def small(p, x, y, txt, col, size=15, anchor='ls', kind='reg', w=None, lh=1.25, align='l', **kw):
    if w:
        return para(p, x, y, w, txt, kind, size, col, lh, align, **kw)
    return T(p, txt, x, y, kind, size, col, anchor, **kw)


# ------------------------------------------------------------------------------------------------ finishing
def _overlap(a, b):
    x0, y0 = max(a[0], b[0]), max(a[1], b[1])
    x1, y1 = min(a[2], b[2]), min(a[3], b[3])
    if x1 <= x0 or y1 <= y0:
        return 0.0
    ar = (x1 - x0) * (y1 - y0)
    sm = min((a[2] - a[0]) * (a[3] - a[1]), (b[2] - b[0]) * (b[3] - b[1]))
    return ar / max(sm, 1.0)


def finish(p, grain=2.5, vignette=0.0, seed=7, sharpen=False):
    """downsample, add print grain / vignette, run text QA. returns (PIL RGB, warnings)"""
    im = p.c.out().convert('RGB')
    arr = np.asarray(im, np.float32)
    H, W = arr.shape[:2]
    if vignette:
        ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
        d = np.sqrt(((xs - W / 2) / (W / 2)) ** 2 + ((ys - H / 2) / (H / 2)) ** 2)
        arr *= (1 - vignette * np.clip(d - 0.55, 0, 1) ** 1.6)[..., None]
    if grain:
        rng = np.random.RandomState(seed)
        n = rng.normal(0, grain, (H, W)).astype(np.float32)
        arr += n[..., None]
    im = Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), 'RGB')
    mx, my = p.margin
    for (t, b, ov) in p.texts:
        if b[0] < mx - 2 or b[2] > p.W - mx + 2 or b[1] < my - 2 or b[3] > p.H - my + 2:
            p.warn.append('text out of safe area: %r %s' % (t[:30], tuple(int(v) for v in b)))
    tx = [t for t in p.texts if not t[2]]
    for i in range(len(tx)):
        for j in range(i + 1, len(tx)):
            o = _overlap(tx[i][1], tx[j][1])
            if o > 0.12:
                p.warn.append('text overlap %.0f%%: %r / %r' % (o * 100, tx[i][0][:24], tx[j][0][:24]))
    return im, p.warn


# ================================================================================================ effects / backgrounds
def photo_bg(p, colors, seed=1, n=8, box=None, blur=None, base=None, light_top=None):
    """photo-like out-of-focus colour field: gradient + many big blurred blobs"""
    rnd = random.Random(seed)
    x0, y0, x1, y1 = box or (0, 0, p.W, p.H)
    w, h = x1 - x0, y1 - y0
    grad(p, [(0, base or colors[0]), (1, colors[-1])], rnd.choice([70, 90, 110, 120]), box=(x0, y0, x1, y1))
    s = Soft(p, (x0, y0, x1, y1), scale=0.1)
    for i in range(n):
        c = colors[i % len(colors)]
        r = rnd.uniform(0.18, 0.5) * max(w, h)
        s.circle(x0 + rnd.uniform(-0.1, 1.1) * w, y0 + rnd.uniform(-0.1, 1.1) * h, r, tuple(c[:3]) + (rnd.randint(110, 210),))
    s.done(blur=blur or 0.08 * max(w, h))
    if light_top:
        glow(p, x0 + w * light_top[0], y0 + h * light_top[1], max(w, h) * light_top[2], light_top[3], 0.5, 1.6)


def bokeh(p, colors, n=40, rmin=12, rmax=60, alpha=(40, 120), seed=3, box=None, blur=2.0, ring=False):
    rnd = random.Random(seed)
    x0, y0, x1, y1 = box or (0, 0, p.W, p.H)
    s = Soft(p, (x0, y0, x1, y1), scale=0.5)
    for i in range(n):
        c = colors[rnd.randrange(len(colors))]
        r = rnd.uniform(rmin, rmax)
        s.circle(rnd.uniform(x0, x1), rnd.uniform(y0, y1), r, tuple(c[:3]) + (rnd.randint(*alpha),))
    s.done(blur=blur)


def rays(p, cx, cy, n=18, col=(255, 255, 255), a=30, a0=0, a1=360, length=None, spread=0.5, alt=True, taper=False):
    """sunburst / spotlight rays: n wedges between angles a0..a1 (deg, 0 = right, 90 = down)"""
    length = length or (p.W + p.H) * 1.2
    step = (a1 - a0) / float(n)
    for k in range(n):
        if alt and k % 2:
            continue
        s0 = math.radians(a0 + k * step)
        s1 = math.radians(a0 + k * step + step * spread * (2 if alt else 1))
        p.poly([(cx, cy), (cx + math.cos(s0) * length, cy + math.sin(s0) * length), (cx + math.cos(s1) * length, cy + math.sin(s1) * length)],
               fill=tuple(col[:3]) + (a,))


def halftone(p, box, color, pitch=22, rmax=9, fade='v', rot=0, invert=False, alpha=255):
    """halftone dot field; radius follows a gradient (fade 'v' top->bottom, 'h', or 'r' radial from centre)"""
    x0, y0, x1, y1 = box
    ca, sa = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    R = math.hypot(x1 - x0, y1 - y0) / 2
    i = -int(R / pitch) - 2
    while i < R / pitch + 2:
        j = -int(R / pitch) - 2
        while j < R / pitch + 2:
            ux, uy = i * pitch, j * pitch + (pitch / 2 if i % 2 else 0)
            x, y = cx + ux * ca - uy * sa, cy + ux * sa + uy * ca
            if x0 <= x <= x1 and y0 <= y <= y1:
                if fade == 'v':
                    t = (y - y0) / (y1 - y0)
                elif fade == 'h':
                    t = (x - x0) / (x1 - x0)
                else:
                    t = min(1.0, math.hypot(x - cx, y - cy) / (R * 0.72))
                if invert:
                    t = 1 - t
                r = rmax * max(0.0, min(1.0, t))
                if r > 0.6:
                    p.circle(x, y, r, tuple(color[:3]) + (alpha,))
            j += 1
        i += 1


def stripes(p, box, angle, w, gap, colors, alpha=255):
    """diagonal stripes clipped to box (drawn as polygons then box-clipped by clamping via mask)"""
    x0, y0, x1, y1 = box
    ss = p.ss
    lay = Image.new('L', (int((x1 - x0) * ss), int((y1 - y0) * ss)), 0)
    out = Image.new('RGB', lay.size, (0, 0, 0))
    d = ImageDraw.Draw(out)
    a = math.radians(angle)
    ca, sa = math.cos(a), math.sin(a)
    R = math.hypot(x1 - x0, y1 - y0)
    k = 0
    t = -R
    while t < R:
        col = colors[k % len(colors)]
        pts = []
        for (u, v) in ((t, -R), (t + w, -R), (t + w, R), (t, R)):
            pts.append(((x1 - x0) / 2 + u * ca - v * sa, (y1 - y0) / 2 + u * sa + v * ca))
        d.polygon([(x * ss, y * ss) for (x, y) in pts], fill=tuple(col[:3]))
        t += w + gap
        k += 1
    m = Image.new('L', out.size, 255) if gap == 0 else None
    if gap:
        mm = Image.new('L', out.size, 0)
        dm = ImageDraw.Draw(mm)
        t = -R
        while t < R:
            pts = []
            for (u, v) in ((t, -R), (t + w, -R), (t + w, R), (t, R)):
                pts.append(((x1 - x0) / 2 + u * ca - v * sa, (y1 - y0) / 2 + u * sa + v * ca))
            dm.polygon([(x * ss, y * ss) for (x, y) in pts], fill=alpha)
            t += w + gap
        m = mm
    elif alpha != 255:
        m = m.point(lambda v: alpha)
    p.c.im.paste(out, (int(x0 * ss), int(y0 * ss)), m)


def confetti(p, box, colors, n=80, seed=5, smin=8, smax=26, alpha=255):
    rnd = random.Random(seed)
    x0, y0, x1, y1 = box
    for i in range(n):
        x, y = rnd.uniform(x0, x1), rnd.uniform(y0, y1)
        s = rnd.uniform(smin, smax)
        a = rnd.uniform(0, 360)
        col = tuple(colors[rnd.randrange(len(colors))][:3]) + (alpha,)
        k = rnd.random()
        if k < 0.45:
            p.poly(rot_pts([(x - s, y - s * 0.35), (x + s, y - s * 0.35), (x + s, y + s * 0.35), (x - s, y + s * 0.35)], x, y, a), fill=col)
        elif k < 0.75:
            p.circle(x, y, s * 0.45, fill=col)
        else:
            p.poly(rot_pts([(x, y - s * 0.6), (x + s * 0.6, y + s * 0.5), (x - s * 0.6, y + s * 0.5)], x, y, a), fill=col)


def star_field(p, box, n=100, seed=2, rmin=1.2, rmax=3.6, col=(255, 244, 214), amin=90):
    rnd = random.Random(seed)
    x0, y0, x1, y1 = box
    for i in range(n):
        p.circle(rnd.uniform(x0, x1), rnd.uniform(y0, y1), rnd.uniform(rmin, rmax), tuple(col[:3]) + (rnd.randint(amin, 255),))


def sparkle(p, cx, cy, r, col, a=255):
    """4-point twinkle"""
    pts = []
    for k in range(8):
        ang = k * math.pi / 4
        rr = r if k % 2 == 0 else r * 0.16
        pts.append((cx + math.cos(ang) * rr, cy + math.sin(ang) * rr))
    p.poly(pts, fill=tuple(col[:3]) + (a,))


def ridge(p, base_y, amp, wl, col, ph=0.0, x0=None, x1=None, bottom=None, seed=None, octaves=3, step=12):
    """layered ridgeline / hills polygon down to `bottom`"""
    x0 = 0 if x0 is None else x0
    x1 = p.W if x1 is None else x1
    bottom = p.H if bottom is None else bottom
    rnd = random.Random(seed if seed is not None else int(ph * 100))
    ph_ = [rnd.uniform(0, 6.3) for _ in range(octaves)]
    pts = []
    x = x0
    while x <= x1 + step:
        y = base_y
        for o in range(octaves):
            y += math.sin(x / (wl / (o + 1.0)) + ph_[o] + ph) * amp / (o * 1.4 + 1.0)
        pts.append((x, y))
        x += step
    p.poly(pts + [(x1 + step, bottom), (x0, bottom)], fill=col)
    return pts


def mountains(p, base_y, h, col, seed=1, x0=0, x1=None, peaks=5, snow=None, bottom=None, jag=0.35):
    x1 = p.W if x1 is None else x1
    bottom = p.H if bottom is None else bottom
    rnd = random.Random(seed)
    xs = [x0 + (x1 - x0) * (i / float(peaks)) for i in range(peaks + 1)]
    pts = [(x0 - 20, base_y)]
    tops = []
    for i in range(peaks):
        xm = (xs[i] + xs[i + 1]) / 2 + rnd.uniform(-0.1, 0.1) * (xs[1] - xs[0])
        hh = h * rnd.uniform(0.55, 1.0)
        ym = base_y - hh
        pts.append((xs[i] + (xm - xs[i]) * 0.55, base_y - hh * (0.5 + rnd.uniform(-jag, jag) * 0.4)))
        pts.append((xm, ym))
        tops.append((xm, ym, hh))
        pts.append((xm + (xs[i + 1] - xm) * 0.45, base_y - hh * (0.45 + rnd.uniform(-jag, jag) * 0.4)))
        pts.append((xs[i + 1], base_y - hh * 0.12 * rnd.random()))
    pts.append((x1 + 20, base_y))
    p.poly(pts + [(x1 + 20, bottom), (x0 - 20, bottom)], fill=col)
    if snow:
        for (xm, ym, hh) in tops:
            s = hh * 0.28
            p.poly([(xm, ym), (xm + s * 0.62, ym + s), (xm + s * 0.2, ym + s * 0.82), (xm, ym + s * 1.12), (xm - s * 0.25, ym + s * 0.8), (xm - s * 0.6, ym + s)], fill=snow)
    return tops


def cloud(p, cx, cy, s, col=(255, 255, 255), a=255):
    c = tuple(col[:3]) + (a,)
    for (dx, dy, r) in ((-0.9, 0.1, 0.55), (-0.35, -0.25, 0.75), (0.35, -0.1, 0.65), (0.9, 0.12, 0.5)):
        p.circle(cx + dx * s, cy + dy * s, r * s, fill=c)
    p.rect(cx - 0.9 * s, cy + 0.1 * s, cx + 0.9 * s, cy + 0.62 * s, fill=c, r=0.25 * s)


def sun_disc(p, cx, cy, r, col=(255, 224, 120), halo=(255, 200, 100), rays_n=0):
    glow(p, cx, cy, r * 3.2, halo, 0.55, 1.8)
    p.circle(cx, cy, r, fill=col)
    if rays_n:
        for k in range(rays_n):
            a = k * 2 * math.pi / rays_n
            p.line([(cx + math.cos(a) * r * 1.2, cy + math.sin(a) * r * 1.2), (cx + math.cos(a) * r * 1.5, cy + math.sin(a) * r * 1.5)], col, max(3, r * 0.08))


def waves(p, y, amp, wl, col, ph=0.0, x0=0, x1=None, bottom=None, step=8):
    x1 = p.W if x1 is None else x1
    bottom = p.H if bottom is None else bottom
    pts = []
    x = x0
    while x <= x1 + step:
        pts.append((x, y + math.sin(x / wl * 2 * math.pi + ph) * amp))
        x += step
    p.poly(pts + [(x1 + step, bottom), (x0, bottom)], fill=col)


def skyline(p, base_y, x0, x1, hmin, hmax, col, seed=1, win=None, wmin=40, wmax=110, lit=0.35, roofs=True):
    rnd = random.Random(seed)
    x = x0
    while x < x1:
        w = rnd.uniform(wmin, wmax)
        h = rnd.uniform(hmin, hmax)
        p.rect(x, base_y - h, x + w, base_y + 2, fill=col)
        k = rnd.random()
        if roofs and k < 0.25:
            p.poly([(x + w * 0.5, base_y - h - w * 0.5), (x + w, base_y - h), (x, base_y - h)], fill=col)
        elif roofs and k < 0.4:
            p.rect(x + w * 0.44, base_y - h - w * 0.7, x + w * 0.5, base_y - h, fill=col)
        elif roofs and k < 0.5:
            p.rect(x + w * 0.1, base_y - h - w * 0.15, x + w * 0.9, base_y - h, fill=col)
        if win:
            wy = base_y - h + 14
            while wy < base_y - 16:
                wx = x + 8
                while wx < x + w - 10:
                    if rnd.random() < lit:
                        p.rect(wx, wy, wx + 7, wy + 10, fill=win)
                    wx += 16
                wy += 22
        x += w + rnd.uniform(-6, 8)


def treeline(p, base_y, x0, x1, hmin, hmax, col, seed=1, kind='pine', gap=0.5):
    rnd = random.Random(seed)
    x = x0
    while x < x1:
        h = rnd.uniform(hmin, hmax)
        w = h * (0.42 if kind == 'pine' else 0.7)
        if kind == 'pine':
            for k in range(4):
                yt = base_y - h + k * h * 0.22
                p.poly([(x, yt), (x + w * (0.5 + k * 0.14), yt + h * 0.32), (x - w * (0.5 + k * 0.14), yt + h * 0.32)], fill=col)
            p.rect(x - 3, base_y - h * 0.12, x + 3, base_y + 2, fill=col)
        else:
            p.circle(x, base_y - h * 0.62, w * 0.55, fill=col)
            p.circle(x - w * 0.3, base_y - h * 0.45, w * 0.4, fill=col)
            p.circle(x + w * 0.3, base_y - h * 0.45, w * 0.4, fill=col)
            p.rect(x - 3, base_y - h * 0.5, x + 3, base_y + 2, fill=col)
        x += w * gap + rnd.uniform(4, 20)


def palm_tree(p, x, base, h, lean, col, frond_col=None, fronds=9, flen=None):
    frond_col = frond_col or col
    flen = flen or h * 0.36
    pts = [(x + lean * (t ** 1.6), base - h * t) for t in [i / 12.0 for i in range(13)]]
    w0 = h * 0.028
    left = [(px - w0 * (1 - 0.45 * i / 12), py) for i, (px, py) in enumerate(pts)]
    right = [(px + w0 * (1 - 0.45 * i / 12), py) for i, (px, py) in enumerate(pts)]
    p.poly(left + right[::-1], fill=col)
    tx, ty = pts[-1]
    for k in range(fronds):
        ang = math.radians(-172 + k * (164.0 / max(1, fronds - 1)))
        L = flen * (1 + 0.14 * math.sin(k * 1.9))
        n = 14
        pp = [(tx + math.cos(ang) * L * t, ty + math.sin(ang) * L * t + 0.55 * t * t * L) for t in [i / float(n) for i in range(n + 1)]]
        lf, rt = [], []
        for i, (px, py) in enumerate(pp):
            t = i / float(n)
            ww = L * 0.11 * (math.sin(math.pi * min(1.0, t * 1.02)) ** 0.7) * (1 - 0.25 * t) + 1.5
            j, k2 = min(i + 1, n), max(i - 1, 0)
            dx, dy = pp[j][0] - pp[k2][0], pp[j][1] - pp[k2][1]
            ln = math.hypot(dx, dy) or 1
            nx, ny = -dy / ln, dx / ln
            lf.append((px + nx * ww, py + ny * ww)); rt.append((px - nx * ww, py - ny * ww))
        p.poly(lf + rt[::-1], fill=frond_col)
    p.circle(tx, ty, h * 0.022, fill=col)


def lens_flare(p, cx, cy, r, col=(255, 240, 200)):
    glow(p, cx, cy, r, col, 0.9, 2.2, mode='screen')
    glow(p, cx, cy, r * 2.4, col, 0.35, 1.5, mode='screen')


# ================================================================================================ local-transform helper
class Xf:
    """local object coordinates -> poster coordinates (scale, rotate, optional mirror). local origin = object centre."""

    def __init__(self, cx, cy, s=1.0, ang=0.0, flip=False):
        self.cx, self.cy, self.s, self.ang, self.flip = cx, cy, s, ang, flip
        a = math.radians(ang)
        self.ca, self.sa = math.cos(a), math.sin(a)

    def pt(self, x, y):
        if self.flip:
            x = -x
        x *= self.s; y *= self.s
        return (self.cx + x * self.ca - y * self.sa, self.cy + x * self.sa + y * self.ca)

    def pts(self, pl):
        return [self.pt(x, y) for (x, y) in pl]

    def rr(self, x0, y0, x1, y1, r, n=7):
        r = min(r, (x1 - x0) / 2.0, (y1 - y0) / 2.0)
        out = []
        for (cx, cy, a0) in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
            for k in range(n + 1):
                a = math.radians(a0 + 90.0 * k / n)
                out.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
        return self.pts(out)

    def ell(self, cx, cy, rx, ry, n=48, a0=0, a1=360):
        return self.pts([(cx + math.cos(math.radians(a0 + (a1 - a0) * k / float(n))) * rx, cy + math.sin(math.radians(a0 + (a1 - a0) * k / float(n))) * ry) for k in range(n + 1)])

    @property
    def rot(self):
        return self.ang * (-1 if self.flip else 1)

    def text(self, p, txt, x, y, kind, size, fill, anchor='mm', **kw):
        X, Y = self.pt(x, y)
        return T(p, txt, X, Y, kind, size * self.s, fill, anchor, rot=-self.ang * (-1 if self.flip else 1), **kw)
