"""Tiny pure-python mesh builder used by make_train.py.

Coordinates here are GODOT coordinates: x along the train, y up, z across (+z = R side).
`to_blender()` converts to Blender (x, -z, y) so that the glTF exporter (+Y up) gives the same numbers back.
Real-world UVs: every material has a tile size in metres; faces are box-mapped (dominant normal axis).
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


def newell(pts):
    n = [0.0, 0.0, 0.0]
    for i in range(len(pts)):
        a = pts[i]; b = pts[(i + 1) % len(pts)]
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    return norm(tuple(n))


class Rot:
    """rotation about an axis then translation (used for tilted seat backs etc.)"""
    def __init__(self, axis='z', deg=0.0, t=(0, 0, 0), pivot=(0, 0, 0)):
        self.c = math.cos(math.radians(deg)); self.s = math.sin(math.radians(deg))
        self.axis = axis; self.t = t; self.pivot = pivot

    def __call__(self, p):
        x, y, z = sub(p, self.pivot)
        c, s = self.c, self.s
        if self.axis == 'z': x, y = x * c - y * s, x * s + y * c
        elif self.axis == 'y': x, z = x * c + z * s, -x * s + z * c
        else: y, z = y * c - z * s, y * s + z * c
        return add(add((x, y, z), self.pivot), self.t)


class MB:
    """mesh builder: shared positions (for smooth shading), per-corner uv / colour, material per face"""
    def __init__(self, name, smooth_deg=38.0):
        self.name = name
        self.P = []
        self.pmap = {}
        self.F = []          # (mat, [vidx...], [uv...], [col...])
        self.smooth_deg = smooth_deg
        self.xf = None       # optional point transform
        self.tiles = {}      # mat -> (tile_u, tile_v) metres for box uv
        self.colfn = None    # colfn(mat, pos, normal) -> (r,g,b)
        self.offs = {}       # per-material uv offset counter (to break repetition)

    # ---- basics
    def vid(self, p):
        k = (round(p[0] * 20000), round(p[1] * 20000), round(p[2] * 20000))
        i = self.pmap.get(k)
        if i is None:
            i = len(self.P); self.P.append(p); self.pmap[k] = i
        return i

    def tile(self, mat, u, v=None):
        self.tiles[mat] = (u, v if v is not None else u)

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

    def face(self, mat, pts, hint=None, uvs=None, off=(0.0, 0.0), cols=None):
        """pts: CCW as seen from the front (or use `hint`, a desired outward normal, to auto-flip)."""
        if self.xf is not None:
            pts = [self.xf(p) for p in pts]
        n = newell(pts)
        if hint is not None and dot(n, hint) < 0:
            pts = pts[::-1]
            if uvs is not None:
                uvs = uvs[::-1]
            if cols is not None:
                cols = cols[::-1]
            n = mul(n, -1)
        if uvs is None:
            uvs = [self.boxuv(p, n, mat, off) for p in pts]
        idx = [self.vid(p) for p in pts]
        if cols is None:
            cols = [None] * len(pts)
        # drop consecutive duplicate corners (degenerate polygon edges)
        keep = [i for i in range(len(idx)) if idx[i] != idx[i - 1]]
        if len(keep) != len(idx):
            idx = [idx[i] for i in keep]; uvs = [uvs[i] for i in keep]; cols = [cols[i] for i in keep]
        if len(set(idx)) < 3 or len(idx) < 3:
            return
        self.F.append((mat, idx, uvs, cols))

    def quad(self, mat, a, b, c, d, **kw):
        self.face(mat, [a, b, c, d], **kw)

    # ---- primitives
    def box(self, mat, lo, hi, bevel=0.0, skip=(), mats=None, off=(0.0, 0.0), uvs=None):
        """axis aligned box. `skip`: subset of {'+x','-x','+y','-y','+z','-z'}; `mats`: per-face material dict"""
        x0, y0, z0 = lo; x1, y1, z1 = hi
        m = lambda k: (mats or {}).get(k, mat)
        b = min(bevel, (x1 - x0) / 2.01, (y1 - y0) / 2.01, (z1 - z0) / 2.01)
        if b <= 1e-5:
            P = {}
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
        # bevelled: inset faces + chamfer strips + corner triangles
        xs = [x0, x0 + b, x1 - b, x1]; ys = [y0, y0 + b, y1 - b, y1]; zs = [z0, z0 + b, z1 - b, z1]
        def P(i, j, k): return (xs[i], ys[j], zs[k])
        def f(k, pts, hint):
            if k not in skip:
                self.face(m(k), pts, hint=hint, off=off)
        # main faces
        f('+x', [P(3, 1, 1), P(3, 2, 1), P(3, 2, 2), P(3, 1, 2)], (1, 0, 0))
        f('-x', [P(0, 1, 1), P(0, 2, 1), P(0, 2, 2), P(0, 1, 2)], (-1, 0, 0))
        f('+y', [P(1, 3, 1), P(2, 3, 1), P(2, 3, 2), P(1, 3, 2)], (0, 1, 0))
        f('-y', [P(1, 0, 1), P(2, 0, 1), P(2, 0, 2), P(1, 0, 2)], (0, -1, 0))
        f('+z', [P(1, 1, 3), P(2, 1, 3), P(2, 2, 3), P(1, 2, 3)], (0, 0, 1))
        f('-z', [P(1, 1, 0), P(2, 1, 0), P(2, 2, 0), P(1, 2, 0)], (0, 0, -1))
        # edge chamfers (12)
        e = lambda k1, k2, pts, hint: (self.face(m(k1), pts, hint=hint, off=off) if (k1 not in skip) else None)
        for sx, ix in ((1, 3), (-1, 0)):
            for sy, jy in ((1, 3), (-1, 0)):     # edges parallel to z
                jy_in = 2 if sy > 0 else 1; ix_in = 2 if sx > 0 else 1
                k = '+x' if sx > 0 else '-x'
                self.face(m(k), [P(ix, jy_in, 1), P(ix_in, jy, 1), P(ix_in, jy, 2), P(ix, jy_in, 2)], hint=(sx, sy, 0), off=off)
            for sz, kz in ((1, 3), (-1, 0)):     # edges parallel to y
                kz_in = 2 if sz > 0 else 1; ix_in = 2 if sx > 0 else 1
                k = '+x' if sx > 0 else '-x'
                self.face(m(k), [P(ix, 1, kz_in), P(ix_in, 1, kz), P(ix_in, 2, kz), P(ix, 2, kz_in)], hint=(sx, 0, sz), off=off)
        for sy, jy in ((1, 3), (-1, 0)):
            for sz, kz in ((1, 3), (-1, 0)):     # edges parallel to x
                jy_in = 2 if sy > 0 else 1; kz_in = 2 if sz > 0 else 1
                k = '+y' if sy > 0 else '-y'
                self.face(m(k), [P(1, jy, kz_in), P(1, jy_in, kz), P(2, jy_in, kz), P(2, jy, kz_in)], hint=(0, sy, sz), off=off)
        # corners
        for sx, ix in ((1, 3), (-1, 0)):
            for sy, jy in ((1, 3), (-1, 0)):
                for sz, kz in ((1, 3), (-1, 0)):
                    ix_in = 2 if sx > 0 else 1; jy_in = 2 if sy > 0 else 1; kz_in = 2 if sz > 0 else 1
                    k = '+x' if sx > 0 else '-x'
                    self.face(m(k), [P(ix, jy_in, kz_in), P(ix_in, jy, kz_in), P(ix_in, jy_in, kz)], hint=(sx, sy, sz), off=off)

    def cyl(self, mat, p0, p1, r, seg=12, caps=True, r1=None, vtile=None, smooth_caps=False, start_ang=0.0, off=(0.0, 0.0)):
        """cylinder / cone frustum between two points (axis arbitrary)."""
        r1 = r if r1 is None else r1
        ax = norm(sub(p1, p0)); L = length(sub(p1, p0))
        ref = (0, 1, 0) if abs(ax[1]) < .9 else (1, 0, 0)
        u = norm(cross(ax, ref)); v = cross(ax, u)
        tu, tv = self.tiles.get(mat, (1.0, 1.0))
        circ = 2 * math.pi * max(r, r1)
        ring0 = []; ring1 = []
        for i in range(seg):
            a = start_ang + 2 * math.pi * i / seg
            d = add(mul(u, math.cos(a)), mul(v, math.sin(a)))
            ring0.append(add(p0, mul(d, r))); ring1.append(add(p1, mul(d, r1)))
        for i in range(seg):
            j = (i + 1) % seg
            u0 = i / seg * circ / tu + off[0]; u1 = (i + 1) / seg * circ / tu + off[0]
            v1 = L / tv + off[1]
            outward = add(sub(ring0[i], p0), sub(ring0[j], p0))
            self.face(mat, [ring0[i], ring0[j], ring1[j], ring1[i]], hint=outward,
                      uvs=[(u0, off[1]), (u1, off[1]), (u1, v1), (u0, v1)])
        if caps:
            if r > 1e-4:
                self.face(mat, ring0, hint=mul(ax, -1), uvs=[self._capuv(p, p0, u, v, mat) for p in ring0])
            if r1 > 1e-4:
                self.face(mat, ring1, hint=ax, uvs=[self._capuv(p, p1, u, v, mat) for p in ring1])

    def _capuv(self, p, c, u, v, mat):
        tu, tv = self.tiles.get(mat, (1.0, 1.0))
        d = sub(p, c)
        return (dot(d, u) / tu + .5, dot(d, v) / tv + .5)

    def grid(self, mat, o, du, dv, nu, nv, hint, uv_o=(0, 0), uv_scale=None, cols=None):
        """subdivided quad: origin o, spanning vectors du, dv (full extents). uv is box-mapped per-vertex."""
        for i in range(nu):
            for j in range(nv):
                a = add(o, add(mul(du, i / nu), mul(dv, j / nv)))
                b = add(o, add(mul(du, (i + 1) / nu), mul(dv, j / nv)))
                c = add(o, add(mul(du, (i + 1) / nu), mul(dv, (j + 1) / nv)))
                d = add(o, add(mul(du, i / nu), mul(dv, (j + 1) / nv)))
                self.face(mat, [a, b, c, d], hint=hint, off=uv_o)

    def sweep(self, mat, profiles, uv_u, uv_v, closed=False, around=None, inward=False):
        """connect consecutive polylines (lists of pts, all same length) into quads with explicit uvs.
        profiles[k][i] = point i of ring k; uv_u[k], uv_v[i] = uv coords. `around=(y,z)`: the surface faces away from
        that point in the yz plane (or towards it if inward)."""
        for k in range(len(profiles) - 1):
            A = profiles[k]; B = profiles[k + 1]
            n = len(A)
            for i in range(n - 1 + (1 if closed else 0)):
                j = (i + 1) % n
                pts = [A[i], B[i], B[j], A[j]]
                uv = [(uv_u[k], uv_v[i]), (uv_u[k + 1], uv_v[i]), (uv_u[k + 1], uv_v[j]), (uv_u[k], uv_v[j])]
                hint = None
                if around is not None:
                    cy = sum(p[1] for p in pts) / 4 - around[0]; cz = sum(p[2] for p in pts) / 4 - around[1]
                    hint = (0.0, cy, cz) if not inward else (0.0, -cy, -cz)
                self.face(mat, pts, uvs=uv, hint=hint)

    # ---- finalise into blender
    def stats(self):
        t = 0
        for f in self.F:
            t += len(f[1]) - 2
        return t


def face_normals_smooth_edges(mb):
    """returns set of edge keys (min,max vertex idx) that are SHARP (> smooth angle) or open"""
    edge_faces = {}
    fn = []
    for fi, (mat, idx, uvs, cols) in enumerate(mb.F):
        pts = [mb.P[i] for i in idx]
        fn.append(newell(pts))
        for a in range(len(idx)):
            e = (min(idx[a], idx[(a + 1) % len(idx)]), max(idx[a], idx[(a + 1) % len(idx)]))
            edge_faces.setdefault(e, []).append(fi)
    thr = math.cos(math.radians(mb.smooth_deg))
    sharp = set()
    for e, fl in edge_faces.items():
        if len(fl) != 2:
            sharp.add(e); continue
        if dot(fn[fl[0]], fn[fl[1]]) < thr:
            sharp.add(e)
    return sharp, fn


def to_blender(mb, bpy, mats_by_name, obj_name, mesh_name=None, tri_smooth=True):
    """create a Blender mesh object from the builder; returns the object."""
    me = bpy.data.meshes.new(mesh_name or obj_name)
    V = [(p[0], -p[2], p[1]) for p in mb.P]
    faces = [f[1] for f in mb.F]
    me.from_pydata(V, [], faces)
    # materials
    used = []
    for f in mb.F:
        if f[0] not in used:
            used.append(f[0])
    for m in used:
        me.materials.append(mats_by_name[m])
    mi = [used.index(f[0]) for f in mb.F]
    me.polygons.foreach_set('material_index', mi)
    me.polygons.foreach_set('use_smooth', [True] * len(mb.F))
    # sharp edges
    sharp, fn = face_normals_smooth_edges(mb)
    if hasattr(me.edges, 'foreach_set'):
        flags = []
        for e in me.edges:
            v = e.vertices
            flags.append((min(v[0], v[1]), max(v[0], v[1])) in sharp)
        try:
            me.edges.foreach_set('use_edge_sharp', flags)
        except Exception:
            pass
    # uv
    uvl = me.uv_layers.new(name='UVMap')
    flat = []
    for f in mb.F:
        for uv in f[2]:
            flat.extend(uv)
    uvl.data.foreach_set('uv', flat)
    # colours (corner domain, float)
    ca = me.color_attributes.new(name='Col', type='FLOAT_COLOR', domain='CORNER')
    cols = []
    for fi, f in enumerate(mb.F):
        n = fn[fi]
        for k, vi in enumerate(f[1]):
            c = f[3][k]
            if c is None:
                c = mb.colfn(f[0], mb.P[vi], n) if mb.colfn else (1.0, 1.0, 1.0)
            cols.extend((c[0], c[1], c[2], 1.0))
    ca.data.foreach_set('color', cols)
    me.update()
    if me.validate(verbose=False):
        print('  (mesh %s: validate() fixed problems)' % obj_name)
    ob = bpy.data.objects.new(obj_name, me)
    return ob
