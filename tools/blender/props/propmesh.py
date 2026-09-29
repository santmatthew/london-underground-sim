"""Pure-python mesh builder used by make_props.py (runs inside Blender's python or plain python).

Coordinates here are GODOT coordinates: x right, y up, z back (+z toward the wall/rear, -z = the object's FRONT).
`to_blender()` converts to Blender (x, -z, y) so the glTF exporter (+Y up) reproduces the same numbers.

Features
  * Xf transform stack (`with mb.tf(Xf.R('y', 20)):`) - hints / UVs are computed in LOCAL space, positions in world.
  * bevelled / rounded boxes (ladder construction: proper arcs, flat cells keep flat shading), lathe (revolve),
    tube sweep along a polyline, polygon prisms with bevel, rounded-rect plates, decal quads.
  * per-face smooth groups (`sg`) so flat faces never get 'pillow' shading from adjacent bevels.
  * vertical grime: faces of chosen materials are cut at fixed heights so a per-vertex dirt gradient can be baked
    into COLOR_0 (`colfn`).
  * real-world box UVs: every material has a tile size in metres.
"""
import math

# ----------------------------------------------------------------------------- vector helpers
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def mul(a, s): return (a[0] * s, a[1] * s, a[2] * s)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def length(a): return math.sqrt(dot(a, a))
def norm(a):
    l = length(a)
    return (a[0] / l, a[1] / l, a[2] / l) if l > 1e-12 else (0.0, 1.0, 0.0)
def lerp(a, b, t): return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)
def lerp2(a, b, t): return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def newell(pts):
    n = [0.0, 0.0, 0.0]
    for i in range(len(pts)):
        a = pts[i]; b = pts[(i + 1) % len(pts)]
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    return norm(tuple(n))


# ----------------------------------------------------------------------------- transforms
class Xf:
    """affine transform: p' = M p + t"""
    def __init__(self, m=None, t=(0.0, 0.0, 0.0)):
        self.m = m if m is not None else ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
        self.t = t

    def p(self, v):
        m = self.m
        return (m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2] + self.t[0],
                m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2] + self.t[1],
                m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2] + self.t[2])

    def v(self, v):
        m = self.m
        return (m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
                m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
                m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2])

    def __mul__(self, o):          # (self * o)(p) = self(o(p))
        m = tuple(tuple(sum(self.m[i][k] * o.m[k][j] for k in range(3)) for j in range(3)) for i in range(3))
        return Xf(m, self.p(o.t))

    @staticmethod
    def T(x=0.0, y=0.0, z=0.0):
        if isinstance(x, (tuple, list)):
            x, y, z = x
        return Xf(None, (x, y, z))

    @staticmethod
    def S(sx, sy=None, sz=None):
        sy = sx if sy is None else sy
        sz = sx if sz is None else sz
        return Xf(((sx, 0.0, 0.0), (0.0, sy, 0.0), (0.0, 0.0, sz)))

    @staticmethod
    def R(axis, deg, pivot=(0.0, 0.0, 0.0)):
        c = math.cos(math.radians(deg)); s = math.sin(math.radians(deg))
        if axis == 'x':
            m = ((1, 0, 0), (0, c, -s), (0, s, c))
        elif axis == 'y':
            m = ((c, 0, s), (0, 1, 0), (-s, 0, c))
        else:
            m = ((c, -s, 0), (s, c, 0), (0, 0, 1))
        r = Xf(tuple(tuple(float(x) for x in row) for row in m))
        rp = r.v(pivot)
        r.t = (pivot[0] - rp[0], pivot[1] - rp[1], pivot[2] - rp[2])
        return r

    def det(self):
        m = self.m
        return (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))


IDENT = Xf()


# ----------------------------------------------------------------------------- polygon helpers (2D)
def poly_area(P):
    a = 0.0
    for i in range(len(P)):
        x0, y0 = P[i]; x1, y1 = P[(i + 1) % len(P)]
        a += x0 * y1 - x1 * y0
    return a * 0.5


def fillet_poly(P, r, n=3):
    """round every corner of polygon P (list of (x,y), any winding) with radius r (clamped per corner), n segments."""
    out = []
    N = len(P)
    for i in range(N):
        p0 = P[i - 1]; p1 = P[i]; p2 = P[(i + 1) % N]
        a = (p0[0] - p1[0], p0[1] - p1[1]); b = (p2[0] - p1[0], p2[1] - p1[1])
        la = math.hypot(*a); lb = math.hypot(*b)
        if la < 1e-9 or lb < 1e-9:
            continue
        a = (a[0] / la, a[1] / la); b = (b[0] / lb, b[1] / lb)
        cosang = max(-1.0, min(1.0, a[0] * b[0] + a[1] * b[1]))
        ang = math.acos(cosang)
        if ang > math.pi - 1e-3 or ang < 1e-3:
            out.append(p1); continue
        t = r / math.tan(ang / 2)
        t = min(t, la * 0.5, lb * 0.5)
        rr = t * math.tan(ang / 2)
        pa = (p1[0] + a[0] * t, p1[1] + a[1] * t)
        pb = (p1[0] + b[0] * t, p1[1] + b[1] * t)
        bis = (a[0] + b[0], a[1] + b[1]); lb2 = math.hypot(*bis)
        bis = (bis[0] / lb2, bis[1] / lb2)
        dc = rr / math.sin(ang / 2)
        c = (p1[0] + bis[0] * dc, p1[1] + bis[1] * dc)
        a0 = math.atan2(pa[1] - c[1], pa[0] - c[0]); a1 = math.atan2(pb[1] - c[1], pb[0] - c[0])
        da = a1 - a0
        while da > math.pi: da -= 2 * math.pi
        while da < -math.pi: da += 2 * math.pi
        for k in range(n + 1):
            aa = a0 + da * k / n
            out.append((c[0] + rr * math.cos(aa), c[1] + rr * math.sin(aa)))
    return out


def inset_poly(P, d):
    """offset polygon inwards by d (mitre joins). works for CCW or CW input."""
    N = len(P)
    sgn = 1.0 if poly_area(P) > 0 else -1.0
    lines = []
    for i in range(N):
        p0 = P[i]; p1 = P[(i + 1) % N]
        dx = p1[0] - p0[0]; dy = p1[1] - p0[1]
        l = math.hypot(dx, dy)
        if l < 1e-9:
            continue
        nx = -dy / l * sgn; ny = dx / l * sgn        # inward normal for CCW
        lines.append(((p0[0] + nx * d, p0[1] + ny * d), (dx / l, dy / l)))
    out = []
    M = len(lines)
    for i in range(M):
        (p, u) = lines[i - 1]; (q, v) = lines[i]
        den = u[0] * v[1] - u[1] * v[0]
        if abs(den) < 1e-9:
            out.append(q); continue
        t = ((q[0] - p[0]) * v[1] - (q[1] - p[1]) * v[0]) / den
        out.append((p[0] + u[0] * t, p[1] + u[1] * t))
    return out


def circle_pts(cx, cy, r, n=24, a0=0.0):
    return [(cx + r * math.cos(a0 + 2 * math.pi * i / n), cy + r * math.sin(a0 + 2 * math.pi * i / n)) for i in range(n)]


def rrect_pts(cx, cy, w, h, r, n=3):
    hw, hh = w / 2, h / 2
    base = [(cx - hw, cy - hh), (cx + hw, cy - hh), (cx + hw, cy + hh), (cx - hw, cy + hh)]
    return fillet_poly(base, r, n) if r > 1e-5 else base


# ----------------------------------------------------------------------------- mesh builder
class MB:
    """mesh builder: shared positions, per-corner uv, material per face, smooth groups"""

    def __init__(self, name, smooth_deg=40.0):
        self.name = name
        self.P = []
        self.pmap = {}
        self.F = []            # dict(mat, idx, uv, sg)
        self.smooth_deg = smooth_deg
        self.xf = IDENT
        self._stack = []
        self.tiles = {}        # mat -> (tile_u, tile_v) metres per texture repeat
        self.colfn = None      # colfn(mat, world_pos, world_normal) -> (r,g,b) multiplier
        self.grime_levels = ()
        self.grime_mats = set()
        self._sg = 0

    # ---- transform stack
    def tf(self, xf):
        mb = self
        class _C:
            def __enter__(s):
                mb._stack.append(mb.xf); mb.xf = mb.xf * xf
            def __exit__(s, *a):
                mb.xf = mb._stack.pop()
        return _C()

    def tile(self, mat, u, v=None):
        self.tiles[mat] = (u, v if v is not None else u)

    def new_sg(self):
        self._sg += 1
        return self._sg

    def vid(self, p):
        k = (round(p[0] * 20000), round(p[1] * 20000), round(p[2] * 20000))
        i = self.pmap.get(k)
        if i is None:
            i = len(self.P); self.P.append(p); self.pmap[k] = i
        return i

    def boxuv(self, p, n, mat, off=(0.0, 0.0)):
        tu, tv = self.tiles.get(mat, (1.0, 1.0))
        ax, ay, az = abs(n[0]), abs(n[1]), abs(n[2])
        if ax >= ay and ax >= az:
            u, v = p[2] * (1 if n[0] > 0 else -1), p[1]
        elif ay >= az:
            u, v = p[0], p[2] * (1 if n[1] > 0 else -1)
        else:
            u, v = p[0] * (1 if n[2] < 0 else -1), p[1]
        return (u / tu + off[0], v / tv + off[1])

    # ---- core face
    def face(self, mat, pts, hint=None, uvs=None, off=(0.0, 0.0), sg=None):
        """pts in LOCAL space. `hint` = desired outward normal (local) to auto-fix winding."""
        pts = list(pts)
        n = newell(pts)
        if hint is not None and dot(n, hint) < 0:
            pts.reverse()
            if uvs is not None:
                uvs = list(uvs)[::-1]
            n = mul(n, -1)
        if uvs is None:
            uvs = [self.boxuv(p, n, mat, off) for p in pts]
        xf = self.xf
        wp = [xf.p(p) for p in pts]
        wn = xf.v(n)
        polys = [(wp, list(uvs))]
        if self.grime_levels and mat in self.grime_mats:
            for y in self.grime_levels:
                np_ = []
                for (pp, uu) in polys:
                    np_.extend(_split_y(pp, uu, y))
                polys = np_
        for (pp, uu) in polys:
            if len(pp) < 3:
                continue
            nn = newell(pp)
            if dot(nn, wn) < 0:
                pp = pp[::-1]; uu = uu[::-1]
            idx = [self.vid(p) for p in pp]
            keep = [i for i in range(len(idx)) if idx[i] != idx[i - 1]]
            if len(keep) != len(idx):
                idx = [idx[i] for i in keep]; uu = [uu[i] for i in keep]
            if len(set(idx)) < 3 or len(idx) < 3:
                continue
            self.F.append(dict(mat=mat, idx=idx, uv=uu, sg=sg))

    def quad(self, mat, a, b, c, d, **kw):
        self.face(mat, [a, b, c, d], **kw)

    # ---- flat plate / decal (local XY plane, normal -Z by default, u right(+x), v up(+y))
    def plate(self, mat, w, h, r=0.0, z=0.0, n=3, uvrect=(0.0, 0.0, 1.0, 1.0), facing=-1, cx=0.0, cy=0.0, mirror_u=False):
        """rounded rectangle centred at (cx,cy) facing -Z (facing=-1) or +Z; UV spans uvrect over the bbox."""
        pts = rrect_pts(cx, cy, w, h, r, n)
        u0, v0, u1, v1 = uvrect
        uvs = []
        for (x, y) in pts:
            fu = (x - (cx - w / 2)) / w; fv = (y - (cy - h / 2)) / h
            if facing < 0:
                fu_ = 1 - fu if not mirror_u else fu
            else:
                fu_ = fu if not mirror_u else 1 - fu
            uvs.append((u0 + (u1 - u0) * fu_, v0 + (v1 - v0) * fv))
        self.face(mat, [(x, y, z) for (x, y) in pts], hint=(0, 0, facing), uvs=uvs)

    def qdecal(self, mat, o, u, v, w, h, uvrect=(0.0, 0.0, 1.0, 1.0), hint=None):
        """flat quad: corner o, spanning unit vectors u (width w) and v (height h). UV maps uvrect (v up).
        Viewed from the side the normal points to (u x v) the image reads upright (u = viewer's right, v = up)."""
        u0, v0, u1, v1 = uvrect
        p0 = o; p1 = add(o, mul(u, w)); p2 = add(p1, mul(v, h)); p3 = add(o, mul(v, h))
        self.face(mat, [p0, p1, p2, p3], hint=hint if hint is not None else cross(u, v),
                  uvs=[(u0, v0), (u1, v0), (u1, v1), (u0, v1)])

    def fdecal(self, mat, cx, y0, w, h, z, facing=-1, uvrect=(0.0, 0.0, 1.0, 1.0)):
        """upright decal on a vertical plane at depth z, centred on x=cx, bottom y0. facing=-1: front (-Z) side, image
        reads correctly for a viewer at -Z; facing=+1: back side."""
        if facing < 0:
            self.qdecal(mat, (cx + w / 2, y0, z), (-1, 0, 0), (0, 1, 0), w, h, uvrect, hint=(0, 0, -1))
        else:
            self.qdecal(mat, (cx - w / 2, y0, z), (1, 0, 0), (0, 1, 0), w, h, uvrect, hint=(0, 0, 1))

    def disc(self, mat, r, z=0.0, seg=24, facing=-1, cx=0.0, cy=0.0, uvrect=(0.0, 0.0, 1.0, 1.0)):
        pts = circle_pts(cx, cy, r, seg)
        u0, v0, u1, v1 = uvrect
        uvs = []
        for (x, y) in pts:
            fu = (x - cx) / (2 * r) + 0.5; fv = (y - cy) / (2 * r) + 0.5
            fu = 1 - fu if facing < 0 else fu
            uvs.append((u0 + (u1 - u0) * fu, v0 + (v1 - v0) * fv))
        self.face(mat, [(x, y, z) for (x, y) in pts], hint=(0, 0, facing), uvs=uvs)

    # ---- boxes
    def box(self, mat, lo, hi, bevel=0.0, seg=1, skip=(), mats=None, off=(0.0, 0.0)):
        """axis-aligned box in local space. bevel>0 -> rounded edges (seg=1: 45deg chamfer arcs, 2: smoother).
        skip: subset of {'+x','-x','+y','-y','+z','-z'}; mats: per-face material dict."""
        x0, y0, z0 = lo; x1, y1, z1 = hi
        m = lambda k: (mats or {}).get(k, mat)
        b = min(bevel, (x1 - x0) / 2.02, (y1 - y0) / 2.02, (z1 - z0) / 2.02)
        if b <= 1e-5:
            def f(k, pts, hint):
                if k not in skip:
                    self.face(m(k), pts, hint=hint, off=off)
            f('+x', [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], (1, 0, 0))
            f('-x', [(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)], (-1, 0, 0))
            f('+y', [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (0, 1, 0))
            f('-y', [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0))
            f('+z', [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1))
            f('-z', [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], (0, 0, -1))
            return
        if seg == 1:
            L = [(-1.0, 0.0), (0.0, 0.0), (0.0, 1.0), (1.0, 1.0)]          # (d, which end centre: 0=lo 1=hi)
        elif seg == 2:
            L = [(-1.0, 0), (-0.5, 0), (0.0, 0), (0.0, 1), (0.5, 1), (1.0, 1)]
        else:
            L = [(-1.0, 0), (-0.6, 0), (-0.25, 0), (0.0, 0), (0.0, 1), (0.25, 1), (0.6, 1), (1.0, 1)]
        nL = len(L)
        last = nL - 1
        lo3 = (x0 + b, y0 + b, z0 + b); hi3 = (x1 - b, y1 - b, z1 - b)

        def pos(i, j, k):
            d = (L[i][0], L[j][0], L[k][0])
            c = (hi3[0] if L[i][1] else lo3[0], hi3[1] if L[j][1] else lo3[1], hi3[2] if L[k][1] else lo3[2])
            n = norm(d)
            return (c[0] + b * n[0], c[1] + b * n[1], c[2] + b * n[2]), n

        sg_arc = self.new_sg()
        flat_i = {(nL // 2 - 1), (nL // 2)}         # ladder indices of the flat span (both d == 0)
        for axis in range(3):
            for side in (0, last):
                key = ('-' if side == 0 else '+') + 'xyz'[axis]
                if key in skip:
                    continue
                o1, o2 = [a for a in range(3) if a != axis]
                for a in range(nL - 1):
                    for c_ in range(nL - 1):
                        idx = []
                        for (da, dc) in ((0, 0), (1, 0), (1, 1), (0, 1)):
                            ijk = [0, 0, 0]
                            ijk[axis] = side; ijk[o1] = a + da; ijk[o2] = c_ + dc
                            idx.append(pos(*ijk))
                        pts = [p for (p, n) in idx]
                        hn = norm(tuple(sum(n[t] for (p, n) in idx) for t in range(3)))
                        is_flat = (a == nL // 2 - 1) and (c_ == nL // 2 - 1)
                        self.face(m(key), pts, hint=hn, off=off, sg=(self.new_sg() if is_flat else sg_arc))

    # ---- revolve
    def lathe(self, mat, prof, seg=24, cx=0.0, cz=0.0, off=(0.0, 0.0), sg=None, planar_caps=True, start=0.0, sweep=360.0, swap=False):
        """revolve profile [(r, y), ...] (bottom->top around the OUTSIDE of the solid) about the vertical axis at (cx, cz).
        Use with mb.tf(Xf.R(...)) for other axes."""
        tu, tv = self.tiles.get(mat, (1.0, 1.0))
        rmax = max(p[0] for p in prof) or 1.0
        circ = 2 * math.pi * rmax * (sweep / 360.0)
        arc = [0.0]
        for k in range(1, len(prof)):
            arc.append(arc[-1] + math.hypot(prof[k][0] - prof[k - 1][0], prof[k][1] - prof[k - 1][1]))
        full = abs(sweep - 360.0) < 1e-6
        nseg = seg
        for k in range(len(prof) - 1):
            r0, y0 = prof[k]; r1, y1 = prof[k + 1]
            dr = r1 - r0; dy = y1 - y0
            if abs(dr) < 1e-9 and abs(dy) < 1e-9:
                continue
            horiz = abs(dy) < abs(dr) * 0.5
            for i in range(nseg):
                a0 = math.radians(start + sweep * i / nseg); a1 = math.radians(start + sweep * (i + 1) / nseg)
                p00 = (cx + r0 * math.cos(a0), y0, cz + r0 * math.sin(a0))
                p01 = (cx + r0 * math.cos(a1), y0, cz + r0 * math.sin(a1))
                p11 = (cx + r1 * math.cos(a1), y1, cz + r1 * math.sin(a1))
                p10 = (cx + r1 * math.cos(a0), y1, cz + r1 * math.sin(a0))
                am = 0.5 * (a0 + a1)
                nr = dy; ny = -dr
                hint = (nr * math.cos(am), ny, nr * math.sin(am))
                if hint == (0, 0, 0):
                    continue
                if horiz and planar_caps:
                    def puv(p):
                        return ((p[0] - cx) / tu + 0.5 + off[0], (p[2] - cz) / tv + 0.5 + off[1])
                    uvs = [puv(p00), puv(p01), puv(p11), puv(p10)]
                else:
                    u0 = i / nseg * circ / tu + off[0]; u1 = (i + 1) / nseg * circ / tu + off[0]
                    uvs = [(u0, arc[k] / tv + off[1]), (u1, arc[k] / tv + off[1]), (u1, arc[k + 1] / tv + off[1]), (u0, arc[k + 1] / tv + off[1])]
                    if swap:
                        uvs = [(b, a) for (a, b) in uvs]
                self.face(mat, [p00, p01, p11, p10], hint=hint, uvs=uvs, sg=sg)

    def cyl(self, mat, p0, p1, r, seg=16, caps=True, r1=None, bevel=0.0, off=(0.0, 0.0), sg=None, swap=False):
        """cylinder / frustum between two points (axis arbitrary) built with lathe + transform. bevel chamfers both ends."""
        r1 = r if r1 is None else r1
        a = sub(p1, p0); L = length(a)
        if L < 1e-9:
            return
        ax = norm(a)
        # rotation taking +Y to ax
        yv = (0.0, 1.0, 0.0)
        c = dot(yv, ax)
        if c > 0.999999:
            xf = Xf.T(p0)
        elif c < -0.999999:
            xf = Xf.T(p0) * Xf.R('x', 180)
        else:
            axis = norm(cross(yv, ax))
            ang = math.degrees(math.acos(max(-1, min(1, c))))
            xf = Xf.T(p0) * _axis_angle(axis, ang)
        prof = []
        b = min(bevel, r * 0.9, r1 * 0.9, L * 0.4) if bevel > 0 else 0.0
        if caps:
            prof.append((0.0, 0.0))
        if b > 0:
            prof.append((r - b, 0.0)); prof.append((r, b)); prof.append((r1, L - b)); prof.append((r1 - b, L))
        else:
            prof.append((r, 0.0)); prof.append((r1, L))
        if caps:
            prof.append((0.0, L))
        with self.tf(xf):
            self.lathe(mat, prof, seg=seg, off=off, sg=sg, swap=swap)

    def sphere(self, mat, c, r, seg=12, rings=6, sg=None):
        prof = [(0.0, -r)]
        for k in range(1, rings):
            a = -math.pi / 2 + math.pi * k / rings
            prof.append((r * math.cos(a), r * math.sin(a)))
        prof.append((0.0, r))
        with self.tf(Xf.T(c)):
            self.lathe(mat, prof, seg=seg, sg=sg)

    def torus_h(self, mat, c, R, r, seg=24, tseg=8):
        """horizontal ring (axis Y) major radius R minor r centred at c"""
        prof = []
        for k in range(tseg + 1):
            a = -math.pi / 2 + 2 * math.pi * k / tseg
            prof.append((R + r * math.cos(a), r * math.sin(a)))
        # ensure profile runs outside-in: start at bottom (a=-90) go counter clockwise -> outside first
        with self.tf(Xf.T(c)):
            self.lathe(mat, prof, seg=seg)

    # ---- tube sweep
    def tube(self, mat, path, r, seg=8, closed=False, caps=True, off=(0.0, 0.0), sg=None, swap=False):
        """circular tube swept along polyline `path` with mitred joints (radius kept constant through bends)."""
        N = len(path)
        if N < 2:
            return
        tu, tv = self.tiles.get(mat, (1.0, 1.0))
        nd = N if closed else N - 1
        dirs = [norm(sub(path[(i + 1) % N], path[i])) for i in range(nd)]
        tang = []
        for i in range(N):
            if closed:
                tang.append(norm(add(dirs[(i - 1) % nd], dirs[i % nd])))
            elif i == 0:
                tang.append(dirs[0])
            elif i == N - 1:
                tang.append(dirs[-1])
            else:
                tang.append(norm(add(dirs[i - 1], dirs[i])))
        t0 = tang[0]
        ref = (0, 1, 0) if abs(t0[1]) < 0.9 else (1, 0, 0)
        u = norm(cross(t0, ref)); v = cross(t0, u)
        rings = []
        dist = [0.0]
        for i in range(N):
            t = tang[i]
            if i > 0:
                tp = tang[i - 1]
                ax_ = cross(tp, t)
                if length(ax_) > 1e-6:
                    ax_ = norm(ax_)
                    ang = math.degrees(math.acos(max(-1.0, min(1.0, dot(tp, t)))))
                    rot = _axis_angle(ax_, ang)
                    u = norm(rot.v(u)); v = norm(rot.v(v))
                dist.append(dist[-1] + length(sub(path[i], path[i - 1])))
            d0 = dirs[min(i, nd - 1)] if not closed else dirs[i % nd]
            ring = []
            for k in range(seg):
                a = 2 * math.pi * k / seg
                d = add(mul(u, math.cos(a)), mul(v, math.sin(a)))
                dd = dot(d, d0)
                kk = r / math.sqrt(max(0.05, 1.0 - dd * dd))
                ring.append(add(path[i], mul(d, kk)))
            rings.append(ring)
        circ = 2 * math.pi * r
        for i in range(N - 1 + (1 if closed else 0)):
            j = (i + 1) % N
            A = rings[i]; B = rings[j]
            for k in range(seg):
                k2 = (k + 1) % seg
                pts = [A[k], A[k2], B[k2], B[k]]
                cen = tuple(sum(p[t] for p in pts) / 4 for t in range(3))
                hint = sub(cen, lerp(path[i], path[j], 0.5))
                u0 = k / seg * circ / tu + off[0]; u1 = (k + 1) / seg * circ / tu + off[0]
                v0 = dist[i] / tv + off[1]; v1 = (dist[j] if not (closed and j == 0) else dist[-1] + length(sub(path[0], path[-1]))) / tv + off[1]
                uvq = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
                if swap:
                    uvq = [(b, a) for (a, b) in uvq]
                self.face(mat, pts, hint=hint, uvs=uvq, sg=sg)
        if caps and not closed:
            self.face(mat, rings[0], hint=mul(tang[0], -1), sg=self.new_sg())
            self.face(mat, rings[-1], hint=tang[-1], sg=self.new_sg())

    # ---- irregular blob (crumpled litter, bags)
    def blob(self, mat, c, r, rnd, seg=8, rings=5, jitter=0.25, scale=(1.0, 1.0, 1.0), sg=None):
        grid = []
        for i in range(rings + 1):
            a = -math.pi / 2 + math.pi * i / rings
            row = []
            if i in (0, rings):
                rr = r * (1 + jitter * (rnd.random() * 2 - 1) * 0.5)
                p = (c[0], c[1] + math.sin(a) * rr * scale[1], c[2])
                row = [p] * seg
            else:
                for j in range(seg):
                    b = 2 * math.pi * j / seg
                    rr = r * (1 + jitter * (rnd.random() * 2 - 1))
                    row.append((c[0] + math.cos(a) * math.cos(b) * rr * scale[0], c[1] + math.sin(a) * rr * scale[1],
                                c[2] + math.cos(a) * math.sin(b) * rr * scale[2]))
            grid.append(row)
        for i in range(rings):
            for j in range(seg):
                j2 = (j + 1) % seg
                pts = [grid[i][j], grid[i][j2], grid[i + 1][j2], grid[i + 1][j]]
                cen = tuple(sum(p[t] for p in pts) / 4 for t in range(3))
                self.face(mat, pts, hint=sub(cen, c), sg=sg)

    # ---- polygon prism
    def prism(self, mat, poly, axis, a0, a1, bevel=0.0, off=(0.0, 0.0), sg=True):
        """extrude polygon `poly` (2D). axis 'x': poly is (z,y) ; 'z': (x,y) ; 'y': (x,z). bevel chamfers both ends."""
        def m3(p, a):
            if axis == 'x': return (a, p[1], p[0])
            if axis == 'z': return (p[0], p[1], a)
            return (p[0], a, p[1])
        if poly_area(poly) < 0:
            poly = poly[::-1]
        dirv = {'x': (1, 0, 0), 'y': (0, 1, 0), 'z': (0, 0, 1)}[axis]
        N = len(poly)
        layers = []
        if bevel > 1e-6:
            ins = inset_poly(poly, bevel)
            layers = [(ins, a0), (poly, a0 + bevel), (poly, a1 - bevel), (ins, a1)]
        else:
            layers = [(poly, a0), (poly, a1)]
        sgid = self.new_sg() if sg else None
        # caps
        cap0 = [m3(p, layers[0][1]) for p in layers[0][0]]
        cap1 = [m3(p, layers[-1][1]) for p in layers[-1][0]]
        self.face(mat, cap0, hint=mul(dirv, -1), off=off, sg=self.new_sg())
        self.face(mat, cap1, hint=dirv, off=off, sg=self.new_sg())
        for l in range(len(layers) - 1):
            (pa, aa) = layers[l]; (pb, ab) = layers[l + 1]
            for i in range(N):
                j = (i + 1) % N
                q = [m3(pa[i], aa), m3(pa[j], aa), m3(pb[j], ab), m3(pb[i], ab)]
                # outward hint: direction from polygon centroid in the plane
                cx = sum(p[0] for p in poly) / N; cy = sum(p[1] for p in poly) / N
                mid = ((pa[i][0] + pa[j][0]) * 0.5, (pa[i][1] + pa[j][1]) * 0.5)
                e = (pa[j][0] - pa[i][0], pa[j][1] - pa[i][1])
                nrm2 = (e[1], -e[0])            # CCW polygon: outward normal is (dy,-dx)
                h = m3(nrm2, 0.0)
                h = (h[0], h[1], h[2])
                hh = add(h, mul(dirv, 0.0))
                if l == 0 and bevel > 1e-6:
                    hh = add(hh, mul(dirv, -length(hh) * 0.8))
                if l == len(layers) - 2 and bevel > 1e-6:
                    hh = add(hh, mul(dirv, length(hh) * 0.8))
                self.face(mat, q, hint=hh, off=off, sg=None)

    # ---- finish
    def stats(self):
        return sum(len(f['idx']) - 2 for f in self.F)

    def bbox(self):
        if not self.P:
            return (0, 0, 0), (0, 0, 0)
        xs = [p[0] for p in self.P]; ys = [p[1] for p in self.P]; zs = [p[2] for p in self.P]
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

    def materials_used(self):
        u = []
        for f in self.F:
            if f['mat'] not in u:
                u.append(f['mat'])
        return u


def _axis_angle(axis, deg):
    """rotation about an arbitrary unit axis through origin (Rodrigues)"""
    c = math.cos(math.radians(deg)); s = math.sin(math.radians(deg)); t = 1 - c
    x, y, z = axis
    m = ((t * x * x + c, t * x * y - s * z, t * x * z + s * y),
         (t * x * y + s * z, t * y * y + c, t * y * z - s * x),
         (t * x * z - s * y, t * y * z + s * x, t * z * z + c))
    return Xf(m)


def _split_y(pts, uvs, y):
    """split convex-ish polygon by plane Y=y; returns list of polygons (pts, uvs). No-op if it doesn't cross."""
    below = []; above = []
    N = len(pts)
    crossed = False
    for i in range(N):
        a = pts[i]; b = pts[(i + 1) % N]
        ua = uvs[i]; ub = uvs[(i + 1) % N]
        da = a[1] - y; db = b[1] - y
        (above if da >= 0 else below).append((a, ua))
        if (da > 1e-7 and db < -1e-7) or (da < -1e-7 and db > 1e-7):
            t = da / (da - db)
            q = lerp(a, b, t); uq = lerp2(ua, ub, t)
            above.append((q, uq)); below.append((q, uq))
            crossed = True
    if not crossed:
        return [(pts, uvs)]
    out = []
    for poly in (below, above):
        if len(poly) >= 3:
            out.append(([p for p, u in poly], [u for p, u in poly]))
    return out


# ----------------------------------------------------------------------------- smooth-edge analysis
def sharp_edges(mb):
    """returns (set of sharp edge keys, face normals). Sharp: open edge, angle > smooth_deg, or different sg groups."""
    edge_faces = {}
    fn = []
    for fi, f in enumerate(mb.F):
        idx = f['idx']
        pts = [mb.P[i] for i in idx]
        fn.append(newell(pts))
        for a in range(len(idx)):
            e = (min(idx[a], idx[(a + 1) % len(idx)]), max(idx[a], idx[(a + 1) % len(idx)]))
            edge_faces.setdefault(e, []).append(fi)
    thr = math.cos(math.radians(mb.smooth_deg))
    thr_hard = math.cos(math.radians(75))
    sharp = set()
    for e, fl in edge_faces.items():
        if len(fl) != 2:
            sharp.add(e); continue
        fa, fb = mb.F[fl[0]], mb.F[fl[1]]
        d = dot(fn[fl[0]], fn[fl[1]])
        if fa['sg'] is not None and fb['sg'] is not None:
            if fa['sg'] != fb['sg'] or d < thr_hard:
                sharp.add(e)
        else:
            if d < thr:
                sharp.add(e)
    return sharp, fn


def to_blender(mb, bpy, mats_by_name, obj_name, pivot=(0.0, 0.0, 0.0), mesh_name=None):
    """create a Blender mesh object from the builder. Vertices are stored relative to `pivot` (Godot coords) and the
    object is located at the pivot."""
    me = bpy.data.meshes.new(mesh_name or obj_name)
    V = [(p[0] - pivot[0], -(p[2] - pivot[2]), p[1] - pivot[1]) for p in mb.P]
    faces = [f['idx'] for f in mb.F]
    me.from_pydata(V, [], faces)
    used = mb.materials_used()
    for m in used:
        me.materials.append(mats_by_name[m])
    mi = [used.index(f['mat']) for f in mb.F]
    me.polygons.foreach_set('material_index', mi)
    me.polygons.foreach_set('use_smooth', [True] * len(mb.F))
    sharp, fn = sharp_edges(mb)
    flags = []
    for e in me.edges:
        v = e.vertices
        flags.append((min(v[0], v[1]), max(v[0], v[1])) in sharp)
    try:
        me.edges.foreach_set('use_edge_sharp', flags)
    except Exception:
        pass
    uvl = me.uv_layers.new(name='UVMap')
    flat = []
    for f in mb.F:
        for uv in f['uv']:
            flat.extend(uv)
    uvl.data.foreach_set('uv', flat)
    if mb.colfn is not None:
        ca = me.color_attributes.new(name='Col', type='FLOAT_COLOR', domain='CORNER')
        cols = []
        for fi, f in enumerate(mb.F):
            n = fn[fi]
            for vi in f['idx']:
                c = mb.colfn(f['mat'], mb.P[vi], n)
                if c is None:
                    c = (1.0, 1.0, 1.0)
                cols.extend((c[0], c[1], c[2], 1.0))
        ca.data.foreach_set('color', cols)
    me.update()
    me.validate(verbose=False)
    ob = bpy.data.objects.new(obj_name, me)
    ob.location = (pivot[0], -pivot[2], pivot[1])
    return ob
