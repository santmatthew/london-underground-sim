"""Procedural London-Underground-style train cars -> assets/models/train/*.glb   (Blender 5.2, headless)

    blender -b --factory-startup -P tools/blender/train/make_train.py -- [deep_mid deep_cab ss_mid ss_cab] [--tris]

Needs the textures from make_textures.py in assets/textures/train/.  All geometry is built in GODOT axes
(x along train, y up, +z = R side, front of a cab car = +x, y=0 = rail head) and converted on the way into Blender.
"""
import bpy, sys, os, math, json, random

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib
import meshlib
importlib.reload(meshlib)
from meshlib import MB, Rot, to_blender, sub, add, mul, norm, cross, dot, length

ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
TEXDIR = os.path.join(ROOT, 'assets', 'textures', 'train')
OUTDIR = os.path.join(ROOT, 'assets', 'models', 'train')
os.makedirs(OUTDIR, exist_ok=True)

# ============================================================================================ configuration
DEEP = dict(
    kind='deep', a=1.31, wt=0.11, floor=0.88, door_top=2.70, cant=2.75, top=3.02, i_cant=2.72, i_top=2.88,
    sill=1.80, head=2.40, door_w=1.30, pocket=1.35, ybot=0.60, roof_n=2.5,
    seat_d=0.45, seat_h=0.45, bogie=5.3, wheelbase=2.1, wheel_r=0.39, coupler=0.22,
    rail_y=2.72, rail_z=0.52, pole_z=0.70, moq='mat_moquette', gang=False,
    band=(2.45, 2.68), light_rows=(-0.30, 0.30), win_w=1.15, cab_len=2.55,
    front_win=(1.80, 2.60), front_z=(0.44, 1.14), cdoor_w=0.80,
)
SS = dict(
    kind='ss', a=1.50, wt=0.11, floor=1.00, door_top=2.95, cant=3.15, top=3.55, i_cant=3.02, i_top=3.30,
    sill=1.95, head=2.66, door_w=1.30, pocket=1.35, ybot=0.66, roof_n=2.6,
    seat_d=0.45, seat_h=0.45, bogie=6.2, wheelbase=2.2, wheel_r=0.39, coupler=0.12,
    rail_y=3.00, rail_z=0.70, pole_z=0.85, moq='mat_moquette', gang=True,
    band=(2.72, 2.98), light_rows=(-0.45, 0.45), win_w=1.5, cab_len=2.70,
    front_win=(1.98, 2.95), front_z=(0.40, 1.30), cdoor_w=0.85,
)
VARIANTS = {
    'deep_mid': dict(DEEP, name='tube_car_deep_mid', L=16.0, cab=False, doors=[-5.0, 0.0, 5.0]),
    'deep_cab': dict(DEEP, name='tube_car_deep_cab', L=16.5, cab=True, doors=[-5.4, -0.9, 3.6]),
    'ss_mid': dict(SS, name='tube_car_ss_mid', L=18.0, cab=False, doors=[-6.6, -2.2, 2.2, 6.6]),
    'ss_cab': dict(SS, name='tube_car_ss_cab', L=19.0, cab=True, doors=[-6.9, -2.5, 1.9]),
}
# The 1972 (Bakerloo) and 1973 (Piccadilly) stock: the same bodyshell and doors as the other tubes here, but a MIXED seating layout (transverse bays at the car ends, longitudinal seats between the doors) and
# an older interior (red moquette). The newer tube stock (Central, Northern, Jubilee, Victoria, Waterloo & City) and the sub-surface S stock keep their longitudinal seating.
DEEP72 = dict(DEEP, stock='deep72', seating='mixed', moq_file='moquette_red_c.jpg', roof_n=3.7, cant=2.88, i_cant=2.84)         # (a boxy body: nearly flat roof, tight corners, flat front)
# The 1992 stock (Central, Waterloo & City): a rounded body - the roof starts curving lower down and is much fuller (a near-elliptical section) - and a blunt, rounded nose in plan.
DEEP92 = dict(DEEP, stock='deep92', roof_n=1.8, cant=2.72, door_top=2.70, i_cant=2.68, band=(2.42, 2.64), front_round=0.52)          # (the doors stay as tall as the other tubes': the player's capsule is 1.72 m and the doorway 1.82 m above the floor, see door_clearance_test)
VARIANTS['deep92_mid'] = dict(DEEP92, name='tube_car_deep92_mid', L=16.0, cab=False, doors=[-5.0, 0.0, 5.0])
VARIANTS['deep92_cab'] = dict(DEEP92, name='tube_car_deep92_cab', L=16.5, cab=True, doors=[-5.4, -0.9, 3.6])
VARIANTS['deep72_mid'] = dict(DEEP72, name='tube_car_deep72_mid', L=16.0, cab=False, doors=[-5.0, 0.0, 5.0])
VARIANTS['deep72_cab'] = dict(DEEP72, name='tube_car_deep72_cab', L=16.5, cab=True, doors=[-5.4, -0.9, 3.6])
OPEN_OFFSET = 0.66     # door leaf slide distance (m)


# ============================================================================================ noise for vertex-colour grime
def _h(ix, iy):
    n = math.sin(ix * 127.1 + iy * 311.7) * 43758.5453
    return n - math.floor(n)


def vn(x, y):
    ix = math.floor(x); iy = math.floor(y)
    fx = x - ix; fy = y - iy
    fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
    a = _h(ix, iy); b = _h(ix + 1, iy); c = _h(ix, iy + 1); d = _h(ix + 1, iy + 1)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def sstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


# ============================================================================================ materials
def make_glTF_group():
    ng = bpy.data.node_groups.get('glTF Material Output')
    if ng is None:
        ng = bpy.data.node_groups.new('glTF Material Output', 'ShaderNodeTree')
        ng.interface.new_socket('Occlusion', in_out='INPUT', socket_type='NodeSocketFloat')
    return ng


_imgcache = {}


def load_img(fn, noncolor=False):
    key = (fn, noncolor)
    if key in _imgcache:
        return _imgcache[key]
    path = os.path.join(TEXDIR, fn)
    im = bpy.data.images.load(path, check_existing=True)
    im.colorspace_settings.name = 'Non-Color' if noncolor else 'sRGB'
    _imgcache[key] = im
    return im


def make_mat(name, tex=None, color=(1, 1, 1, 1), rough=0.5, metal=0.0, emit=None, emit_strength=0.0, alpha=None,
             double=False, orm=True, normal=True, emit_tex=False, albedo_file=None, spec=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    bsdf.inputs['Base Color'].default_value = color
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    if 'Specular IOR Level' in bsdf.inputs:
        bsdf.inputs['Specular IOR Level'].default_value = spec
    x = -700
    if tex or albedo_file:
        c = nt.nodes.new('ShaderNodeTexImage'); c.location = (x, 300)
        c.image = load_img(albedo_file or (tex + '_c.jpg'))
        nt.links.new(c.outputs['Color'], bsdf.inputs['Base Color'])
        if emit_tex:
            nt.links.new(c.outputs['Color'], bsdf.inputs['Emission Color'])
    if tex and normal:
        n = nt.nodes.new('ShaderNodeTexImage'); n.location = (x, 0)
        n.image = load_img(tex + '_n.jpg', True)
        nm = nt.nodes.new('ShaderNodeNormalMap'); nm.location = (x + 300, 0)
        nt.links.new(n.outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    if tex and orm:
        o = nt.nodes.new('ShaderNodeTexImage'); o.location = (x, -300)
        o.image = load_img(tex + '_orm.jpg', True)
        sep = nt.nodes.new('ShaderNodeSeparateColor'); sep.location = (x + 300, -300)
        nt.links.new(o.outputs['Color'], sep.inputs['Color'])
        nt.links.new(sep.outputs['Green'], bsdf.inputs['Roughness'])
        nt.links.new(sep.outputs['Blue'], bsdf.inputs['Metallic'])
        g = nt.nodes.new('ShaderNodeGroup'); g.node_tree = make_glTF_group(); g.location = (x + 600, -500)
        nt.links.new(sep.outputs['Red'], g.inputs['Occlusion'])
    if emit is not None:
        bsdf.inputs['Emission Color'].default_value = emit
        bsdf.inputs['Emission Strength'].default_value = emit_strength
    if alpha is not None:
        bsdf.inputs['Alpha'].default_value = alpha
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            pass
        try:
            m.blend_method = 'BLEND'
        except Exception:
            pass
    m.use_backface_culling = not double
    return m


def build_materials(kind='deep', cfg=None):
    cfg = cfg or {}
    M = {}
    M['mat_body_paint'] = make_mat('mat_body_paint', tex='body' if kind == 'deep' else 'body_ss', metal=0.2)
    M['mat_livery'] = make_mat('mat_livery', color=(0.70, 0.045, 0.06, 1), rough=0.36, metal=0.0, spec=0.6)
    M['mat_roof'] = make_mat('mat_roof', tex='roof')
    M['mat_trim'] = make_mat('mat_trim', color=(0.025, 0.026, 0.028, 1), rough=0.62, metal=0.0)
    M['mat_underframe'] = make_mat('mat_underframe', tex='under')
    M['mat_wheel'] = make_mat('mat_wheel', color=(0.32, 0.32, 0.33, 1), rough=0.5, metal=0.7)
    M['mat_glass'] = make_mat('mat_glass', color=(0.62, 0.72, 0.76, 1), rough=0.04, metal=0.0, alpha=0.16, double=True, spec=0.9)
    M['mat_frame'] = make_mat('mat_frame', color=(0.78, 0.79, 0.81, 1), rough=0.32, metal=0.6)
    M['mat_pole'] = make_mat('mat_pole', color=(0.88, 0.89, 0.92, 1), rough=0.22, metal=0.6)
    M['mat_floor'] = make_mat('mat_floor', tex='floor')
    M['mat_wall'] = make_mat('mat_wall', tex='laminate')
    M['mat_ceiling'] = make_mat('mat_ceiling', tex='ceiling', emit=(1, 1, 1, 1), emit_strength=0.14, emit_tex=True)   # faint self-illumination = bounce light from the LED strips
    M['mat_moquette'] = make_mat('mat_moquette', tex='moquette', albedo_file=cfg.get('moq_file'))
    M['mat_moquette_prio'] = make_mat('mat_moquette_prio', tex='moquette', albedo_file='moquette_prio_c.jpg')
    M['mat_plastic'] = make_mat('mat_plastic', color=(0.05, 0.055, 0.06, 1), rough=0.55, metal=0.0)
    M['mat_light_emissive'] = make_mat('mat_light_emissive', color=(0.9, 0.9, 0.88, 1), rough=0.4, emit=(1.0, 0.96, 0.88, 1),
                                       emit_strength=5.0)
    M['mat_linemap'] = make_mat('mat_linemap', tex='linemap', orm=False, normal=False, rough=0.45)
    for i in range(4):
        M['mat_advert_%d' % i] = make_mat('mat_advert_%d' % i, albedo_file='advert_%d_c.jpg' % i, rough=0.32)
    M['mat_priority_sign'] = make_mat('mat_priority_sign', albedo_file='priority_sign_c.jpg', rough=0.4)
    M['mat_safety'] = make_mat('mat_safety', tex='safety', rough=0.55)
    M['mat_door_inner'] = make_mat('mat_door_inner', tex='door_inner')
    M['mat_dest_display'] = make_mat('mat_dest_display', albedo_file='dest_c.jpg', color=(1, 1, 1, 1), rough=0.3,
                                     emit=(1, 1, 1, 1), emit_strength=3.0, emit_tex=True)
    M['mat_headlight'] = make_mat('mat_headlight', color=(0.9, 0.9, 0.85, 1), rough=0.1, emit=(1.0, 0.97, 0.88, 1), emit_strength=25.0)
    M['mat_taillight'] = make_mat('mat_taillight', color=(0.5, 0.02, 0.02, 1), rough=0.15, emit=(1.0, 0.03, 0.02, 1), emit_strength=6.0)
    M['mat_cab_screen'] = make_mat('mat_cab_screen', color=(0.02, 0.04, 0.05, 1), rough=0.2, emit=(0.15, 0.55, 0.9, 1), emit_strength=2.0)
    M['mat_cab_desk'] = make_mat('mat_cab_desk', color=(0.11, 0.115, 0.12, 1), rough=0.5, metal=0.0)
    return M


TILES = {
    'mat_body_paint': (8.0, 2.0), 'mat_roof': (2.0, 2.0), 'mat_underframe': (1.5, 1.5), 'mat_floor': (0.9, 0.9),
    'mat_wall': (1.0, 1.0), 'mat_ceiling': (1.0, 1.0), 'mat_moquette': (0.5, 0.5), 'mat_moquette_prio': (0.5, 0.5),
    'mat_safety': (0.25, 0.25), 'mat_plastic': (1, 1), 'mat_frame': (1, 1), 'mat_pole': (1, 1), 'mat_trim': (1, 1),
    'mat_livery': (1, 1), 'mat_glass': (1, 1), 'mat_wheel': (1, 1),
}


def new_mb(name, smooth=38.0):
    mb = MB(name, smooth)
    mb.tiles.update(TILES)
    return mb


# ============================================================================================ profile helpers
def prof(a, yc, b, n=2.5, N=14):
    """right half cross-section arc: (z, y) from the side (a, yc) to the crown (0, yc+b)"""
    pts = []
    for i in range(N + 1):
        t = (math.pi / 2) * (i / N)
        c = math.cos(t); s = math.sin(t)
        pts.append((a * (max(c, 0.0) ** (2.0 / n)), yc + b * (s ** (2.0 / n))))
    return pts


def prof_full(a, yc, b, n=2.5, N=14):
    h = prof(a, yc, b, n, N)
    return h + [(-z, y) for (z, y) in h[-2::-1]]     # +a side -> over the crown -> -a side


def arc_lengths(p):
    out = [0.0]
    for i in range(1, len(p)):
        out.append(out[-1] + math.hypot(p[i][0] - p[i - 1][0], p[i][1] - p[i - 1][1]))
    return out


# ============================================================================================ generic geometry helpers
def wall_cells(mb, matfn, x0, x1, y0, y1, zp, s, holes, xbreaks=(), ybreaks=(), inward=False, off=(0.0, 0.0)):
    """rectangular wall plane at z = s*zp with rectangular holes [(x0,x1,y0,y1)]"""
    xs = sorted(set([x0, x1] + [v for h in holes for v in (h[0], h[1])] + [x for x in xbreaks if x0 < x < x1]))
    ys = sorted(set([y0, y1] + [v for h in holes for v in (h[2], h[3])] + [y for y in ybreaks if y0 < y < y1]))
    xs = [x for x in xs if x0 - 1e-9 <= x <= x1 + 1e-9]
    ys = [y for y in ys if y0 - 1e-9 <= y <= y1 + 1e-9]
    hint = (0, 0, -s if inward else s)
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            xa, xb, ya, yb = xs[i], xs[i + 1], ys[j], ys[j + 1]
            cx = (xa + xb) / 2; cy = (ya + yb) / 2
            if any(h[0] < cx < h[1] and h[2] < cy < h[3] for h in holes):
                continue
            mb.face(matfn(ya, yb), [(xa, ya, s * zp), (xb, ya, s * zp), (xb, yb, s * zp), (xa, yb, s * zp)], hint=hint, off=off)


def reveal(mb, mat, x0, x1, y0, y1, zo, zi, s, sides='blrt'):
    zo *= s; zi *= s
    if 'b' in sides: mb.face(mat, [(x0, y0, zo), (x1, y0, zo), (x1, y0, zi), (x0, y0, zi)], hint=(0, 1, 0))
    if 't' in sides: mb.face(mat, [(x0, y1, zo), (x1, y1, zo), (x1, y1, zi), (x0, y1, zi)], hint=(0, -1, 0))
    if 'l' in sides: mb.face(mat, [(x0, y0, zo), (x0, y1, zo), (x0, y1, zi), (x0, y0, zi)], hint=(1, 0, 0))
    if 'r' in sides: mb.face(mat, [(x1, y0, zo), (x1, y1, zo), (x1, y1, zi), (x1, y0, zi)], hint=(-1, 0, 0))


def quad_xy(mb, mat, x0, x1, y0, y1, z, hint, uv=None, off=(0, 0)):
    """axis aligned quad in an xy plane (facing along hint z). uv=((u0,v0),(u1,v1)) maps the extent to a custom uv rect"""
    pts = [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]
    uvs = None
    if uv is not None:
        (u0, v0), (u1, v1) = uv
        uvs = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
        # keep uv orientation when face is flipped: `face` reverses uvs together with pts
        n = (0, 0, 1)
        if hint[2] < 0:
            # viewed from -z the x axis is mirrored: mirror u so the image reads correctly
            uvs = [(u1, v0), (u0, v0), (u0, v1), (u1, v1)]
    mb.face(mat, pts, hint=hint, uvs=uvs, off=off)


def quad_zy(mb, mat, z0, z1, y0, y1, x, hint, uv=None):
    pts = [(x, y0, z0), (x, y0, z1), (x, y1, z1), (x, y1, z0)]
    uvs = None
    if uv is not None:
        (u0, v0), (u1, v1) = uv
        uvs = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    mb.face(mat, pts, hint=hint, uvs=uvs)


def vpole(mb, mat, x, z, y0, y1, r=0.019, seg=10, flange=True):
    mb.cyl(mat, (x, y0, z), (x, y1, z), r, seg, caps=False)
    if flange:
        mb.cyl('mat_frame', (x, y0, z), (x, y0 + 0.014, z), 0.055, 12, caps=True)
        mb.cyl('mat_frame', (x, y1 - 0.014, z), (x, y1, z), 0.055, 12, caps=True)


# ============================================================================================ car builder
class Car:
    def __init__(self, cfg, M):
        self.c = cfg
        self.M = M
        c = cfg
        self.L = c['L']; self.x0 = -c['L'] / 2; self.x1 = c['L'] / 2
        self.a = c['a']; self.ai = c['a'] - c['wt']; self.fl = c['floor']
        self.cab = c['cab']
        self.markers = []      # dicts
        self.objs = []         # blender objects
        self.doorlist = []
        # interior extents
        self.endt = 0.15
        self.xi0 = self.x0 + self.endt
        if self.cab:
            self.x_part = self.x1 - c['cab_len']            # partition (passenger side face)
            self.xi1 = self.x_part - 0.06
        else:
            self.xi1 = self.x1 - self.endt
        self.doors = list(c['doors'])
        self.xe = self.x1 - 0.14 if self.cab else self.x1        # end of the straight skin/roof (cab: rolled lip follows)
        self.compute_layout()

    # ---------------------------------------------------------------- layout: windows, seat runs
    def compute_layout(self):
        c = self.c
        hw = c['door_w'] / 2
        pk = c['pocket']
        bounds = [(self.xi0, 'end')] + [(xd, 'door') for xd in self.doors] + [(self.xi1, 'end')]
        self.wins = []
        self.runs = []      # (xa, xb, n)
        for i in range(len(bounds) - 1):
            (xa, ta), (xb, tb) = bounds[i], bounds[i + 1]
            wa = xa + (pk if ta == 'door' else 0.10)
            wb = xb - (pk if tb == 'door' else 0.10)
            if c['gang'] and ta == 'end':
                wa = xa + 0.10
            ln = wb - wa
            if ln > 0.75:
                nw = max(1, int(round((ln + 0.22) / (c['win_w'] + 0.22))))
                pw = 0.22
                w = (ln - (nw - 1) * pw) / nw
                for k in range(nw):
                    self.wins.append((wa + k * (w + pw), wa + k * (w + pw) + w))
            sa = xa + (hw + 0.13 if ta == 'door' else 0.0)
            sb = xb - (hw + 0.13 if tb == 'door' else 0.0)
            if ta == 'end': sa = xa + (0.05 if not c['gang'] else 0.0)
            if tb == 'end': sb = xb - (0.05 if not c['gang'] else 0.0)
            n = int(round((sb - sa) / 0.47))
            if n >= 2:
                self.runs.append((sa, sb, n, ta, tb))
        # cab door / windows (cab car)
        self.cab_holes = []
        if self.cab:
            xf = self.x1
            cw = c['cdoor_w']
            self.cdoor = (xf - 1.85, xf - 1.85 + cw)
            self.cwin = (xf - 0.92, xf - 0.22)
        else:
            self.cdoor = None

    # ---------------------------------------------------------------- grime functions
    def col_ext(self, mat, p, n):
        x, y, z = p
        t = 1.0 - sstep(0.4, 1.9, y)
        g = 1.0 - 0.55 * t ** 1.4
        g *= 0.93 + 0.10 * vn(x * 0.9 + 3.0, y * 0.5) + 0.05 * vn(x * 7.0, 0.5 + y * 0.15)
        if mat == 'mat_roof':
            g = 0.75 + 0.25 * vn(x * 0.7, z * 1.2)
        # extra dirt below/around door frames and window sills
        return (g, g * 0.975, g * 0.94)

    def col_int(self, mat, p, n):
        x, y, z = p
        yy = y - self.fl
        g = 1.0
        if mat == 'mat_floor':
            zz = abs(z)
            aisle = 1.0 - sstep(0.35, 0.85, zz)             # worn centre
            g = 0.50 + 0.38 * aisle
            # scuffed lighter patches around each doorway
            for xd in self.doors:
                d = abs(x - xd)
                g += 0.16 * (1 - sstep(0.6, 1.4, d)) * (0.4 + 0.6 * aisle)
            g *= 0.86 + 0.28 * vn(x * 2.3, z * 2.3)
            g = min(g, 1.0)
            return (g, g, g * 1.02)
        if mat in ('mat_wall', 'mat_door_inner', 'mat_frame'):
            g = 0.70 + 0.30 * sstep(0.0, 0.7, yy)
            g *= 0.90 + 0.10 * vn(x * 1.3, y * 3.0) + 0.04 * vn(x * 9.0, y * 0.6)
            for xd in self.doors:                       # hand-marks / grime beside door edges
                g *= 1.0 - 0.10 * (1 - sstep(0.0, 0.5, abs(abs(x - xd) - self.c['door_w'] / 2))) * sstep(0.7, 1.0, yy) * (1 - sstep(1.2, 1.6, yy))
            return (g, g, g * 0.98)
        if mat in ('mat_moquette', 'mat_moquette_prio'):
            g = 0.62 + 0.38 * n[1] * 0.5 + 0.2 if n[1] > 0.3 else 0.55 + 0.2 * (1 - abs(n[1]))
            g *= 0.9 + 0.1 * vn(x * 4.0, z * 4.0)
            return (min(g, 1), min(g, 1), min(g, 1))
        if mat == 'mat_plastic':
            return (0.9, 0.9, 0.9)
        if mat == 'mat_ceiling':
            g = 0.85 + 0.15 * vn(x * 0.5, z * 2.0)
            return (g, g, g)
        return (1.0, 1.0, 1.0)

    # ---------------------------------------------------------------- top-level build
    def build(self):
        c = self.c; M = self.M
        self.ext = new_mb('Exterior'); self.ext.colfn = self.col_ext
        self.int = new_mb('Interior'); self.int.colfn = self.col_int
        self.gl = new_mb('Glass')
        self.und = new_mb('Underframe'); self.und.colfn = lambda m, p, n: (0.8, 0.8, 0.8)
        self.col = {}       # collision meshes
        self.leaves = []    # (name, MB, location(godot), extras)
        self.build_exterior()
        self.build_roof_and_ceiling()
        self.build_doors()
        self.build_interior_shell()
        self.build_seating()
        self.build_poles_rails()
        self.build_lighting_and_signage()
        self.build_ends()
        if self.cab:
            self.build_cab()
        self.build_underframe()
        self.build_collision()
        self.build_markers()

    # ============================================================ exterior skin, windows, frames
    def ext_holes(self):
        c = self.c
        holes = []
        for xd in self.doors:
            holes.append((xd - c['door_w'] / 2, xd + c['door_w'] / 2, self.fl, c['door_top']))
        for (wa, wb) in self.wins:
            holes.append((wa, wb, c['sill'], c['head']))
        if self.cab:
            holes.append((self.cdoor[0], self.cdoor[1], self.fl, c['door_top']))
            holes.append((self.cwin[0], self.cwin[1], c['sill'] - 0.02, c['head'] + 0.06))
        return holes

    def build_exterior(self):
        c = self.c; a = self.a; ai = self.ai; fl = self.fl
        ext = self.ext
        holes = self.ext_holes()
        stripe = (c['sill'] - 0.20, c['sill'] - 0.08)
        ybreaks = [c['ybot'] + 0.15, c['ybot'] + 0.35, fl + 0.05, fl + 0.3, fl + 0.6, 1.5, stripe[0], stripe[1], c['sill'] + 0.3,
                   c['head'] - 0.3, c['head']]
        xbreaks = [self.x0 + 1.5 * k for k in range(1, int(self.L / 1.5))]

        def matfn(ya, yb):
            return 'mat_body_paint'
        for s in (1, -1):
            off = (0.37 if s > 0 else 0.0, 0.0)
            wall_cells(ext, matfn, self.x0, self.xe, c['ybot'], c['cant'], a, s, holes, xbreaks, ybreaks, off=off)
            # door / window reveals + frames
            for xd in self.doors:
                x0 = xd - c['door_w'] / 2; x1 = xd + c['door_w'] / 2
                reveal(ext, 'mat_frame', x0, x1, fl, c['door_top'], a, ai, s, 'lrt')
                # bright ribbed sill plate
                ext.box('mat_frame', (x0, fl - 0.03, s * ai if s > 0 else -a), (x1, fl, a if s > 0 else -ai))
                # frame surround proud of the skin
                fw = 0.05; pr = 0.012
                zlo, zhi = (a, a + pr) if s > 0 else (-a - pr, -a)
                ext.box('mat_trim', (x0 - fw, fl - 0.02, zlo), (x0, c['door_top'] + 0.02, zhi))
                ext.box('mat_trim', (x1, fl - 0.02, zlo), (x1 + fw, c['door_top'] + 0.02, zhi))
                ext.box('mat_trim', (x0 - fw, c['door_top'], zlo), (x1 + fw, c['door_top'] + 0.05, zhi))
                # roll-up gutter above door
                ext.box('mat_trim', (x0 - 0.15, c['cant'] - 0.055, zlo), (x1 + 0.15, c['cant'] - 0.03, zhi + 0.012), bevel=0.006)
            for (wa, wb) in self.wins:
                reveal(ext, 'mat_trim', wa, wb, c['sill'], c['head'], a, ai, s)
                fw = 0.035; pr = 0.010
                zlo, zhi = (a, a + pr) if s > 0 else (-a - pr, -a)
                ext.box('mat_trim', (wa - fw, c['sill'] - fw, zlo), (wb + fw, c['sill'], zhi))
                ext.box('mat_trim', (wa - fw, c['head'], zlo), (wb + fw, c['head'] + fw, zhi))
                ext.box('mat_trim', (wa - fw, c['sill'], zlo), (wa, c['head'], zhi))
                ext.box('mat_trim', (wb, c['sill'], zlo), (wb + fw, c['head'], zhi))
                # glass
                zg = s * (a - 0.045)
                self.gl.face('mat_glass', [(wa, c['sill'], zg), (wb, c['sill'], zg), (wb, c['head'], zg), (wa, c['head'], zg)], hint=(0, 0, s))
                # sill drip rail
            # raised livery stripe between the door frames
            dh = sorted([(xd - c['door_w'] / 2 - 0.05, xd + c['door_w'] / 2 + 0.05) for xd in self.doors] +
                        ([(self.cdoor[0] - 0.05, self.cdoor[1] + 0.05)] if self.cab else []))
            prev = self.x0 + 0.03
            zlo, zhi = (a, a + 0.005) if s > 0 else (-a - 0.005, -a)
            for (h0, h1) in dh + [(self.xe - 0.03, self.xe)]:
                if h0 - prev > 0.1:
                    ext.box('mat_livery', (prev, stripe[0], zlo), (h0, stripe[1], zhi), bevel=0.002, skip=('-z' if s > 0 else '+z',))
                prev = h1
            # lower skirt (recessed dark), with cut-outs for the bogies
            self.build_skirt(s)
            # body sill rail
            zlo, zhi = (a - 0.02, a + 0.015) if s > 0 else (-a - 0.015, -a + 0.02)
            ext.box('mat_trim', (self.x0 + 0.05, c['ybot'] - 0.04, zlo), (self.xe - 0.02, c['ybot'] + 0.02, zhi), bevel=0.008)
        # cab windows glass handled in build_cab

    def build_skirt(self, s):
        c = self.c; a = self.a
        zs = a - 0.05
        # segments between bogies
        gaps = []
        for bx in (-c['bogie'], c['bogie']):
            gaps.append((bx - c['wheelbase'] / 2 - 0.55, bx + c['wheelbase'] / 2 + 0.55))
        xa = self.x0 + 0.05
        segs = []
        cur = xa
        for g0, g1 in gaps:
            if g0 > cur: segs.append((cur, g0))
            cur = g1
        if cur < self.xe - 0.05: segs.append((cur, self.xe - 0.05))
        y0 = 0.30; y1 = c['ybot']
        for (p, q) in segs:
            n = max(1, int((q - p) / 1.2))
            self.ext.grid('mat_underframe', (p, y0, s * zs), (q - p, 0, 0), (0, y1 - y0, 0), n, 2, (0, 0, s))
            # end caps of the skirt segment (so they look closed)
            for xx, hx in ((p, -1), (q, 1)):
                pass
            self.ext.face('mat_underframe', [(p, y0, s * zs), (p, y1, s * zs), (p, y1, s * a), (p, y0, s * a)], hint=(-1, 0, 0))
            self.ext.face('mat_underframe', [(q, y0, s * zs), (q, y1, s * zs), (q, y1, s * a), (q, y0, s * a)], hint=(1, 0, 0))
            self.ext.face('mat_underframe', [(p, y0, s * zs), (q, y0, s * zs), (q, y0, s * a), (p, y0, s * a)], hint=(0, -1, 0))
            # step from skirt to body: small ledge
        # note: skirt top meets the body sill at ybot

    # ============================================================ roof + ceiling
    def build_roof_and_ceiling(self):
        c = self.c; ext = self.ext
        xa, xb = self.x0, self.xe
        outer = prof_full(self.a, c['cant'], c['top'] - c['cant'], c['roof_n'])
        sv = arc_lengths(outer)
        v = [q / 2.0 for q in sv]
        rings = [[(xa, y, z) for (z, y) in outer], [(xb, y, z) for (z, y) in outer]]
        # subdivide roof in x for a bit of vertex-colour variation
        nseg = 4
        xs = [xa + (xb - xa) * k / nseg for k in range(nseg + 1)]
        rings = [[(x, y, z) for (z, y) in outer] for x in xs]
        ext.sweep('mat_roof', rings, [x / 2.0 for x in xs], v, around=(c['cant'] - 0.6, 0.0))
        # rain gutters along the eaves
        for s in (1, -1):
            zlo = s * (self.a - 0.02)
            ext.box('mat_trim', (xa + 0.05, c['cant'] - 0.02, min(zlo, zlo + s * 0.05)), (xb - 0.02, c['cant'] + 0.03, max(zlo, zlo + s * 0.05)), bevel=0.01)
        # roof hoop straps (raised strips following the curve)
        ro = prof_full(self.a + 0.010, c['cant'], c['top'] - c['cant'] + 0.010, c['roof_n'])
        rv = arc_lengths(ro)
        xk = xa + 1.0
        while xk < xb - 0.6:
            ext.sweep('mat_trim', [[(xk, y, z) for (z, y) in ro], [(xk + 0.05, y, z) for (z, y) in ro]], [0.0, 0.05], rv, around=(c['cant'] - 0.6, 0.0))
            xk += 2.0
        # roof furniture
        top = c['top']
        if c['kind'] == 'deep':
            for vx in (-4.3, 3.6):
                ext.box('mat_roof', (vx - 0.55, top - 0.02, -0.42), (vx + 0.55, top + 0.085, 0.42), bevel=0.03)
                for k in range(5):
                    ext.box('mat_trim', (vx - 0.45 + k * 0.2, top + 0.083, -0.34), (vx - 0.37 + k * 0.2, top + 0.092, 0.34))
            for rx in [x for x in (-6.9, -2.6, 2.4, 6.9) if self.x0 + 0.5 < x < self.x1 - 0.5]:
                ext.box('mat_trim', (rx - 0.03, top - 0.02, -0.25), (rx + 0.03, top + 0.03, 0.25), bevel=0.01)
        else:
            for vx in [x for x in (-5.2, 0.0, 5.2) if self.x0 + 1.2 < x < self.x1 - 1.2]:
                ext.box('mat_roof', (vx - 1.1, top - 0.02, -0.6), (vx + 1.1, top + 0.17, 0.6), bevel=0.05)
                for k in range(7):
                    ext.box('mat_trim', (vx - 0.95 + k * 0.28, top + 0.165, -0.5), (vx - 0.85 + k * 0.28, top + 0.178, 0.5))
        # interior ceiling
        inner = prof_full(self.ai, c['i_cant'], c['i_top'] - c['i_cant'], c['roof_n'])
        sv = arc_lengths(inner)
        self.ceil_profile = inner
        xs = [self.xi0 + (self.xi1 + (self.x1 - 0.05 - self.xi1 if self.cab else 0) - self.xi0) * k / 8 for k in range(9)]
        xe = self.x1 - 0.05 if self.cab else self.xi1
        xs = [self.xi0 + (xe - self.xi0) * k / 8 for k in range(9)]
        rings = [[(x, y, z) for (z, y) in inner] for x in xs]
        self.int.sweep('mat_ceiling', rings, [x for x in xs], [q for q in sv], around=(c['i_cant'] - 0.7, 0.0), inward=True)
        self.ceil_x = (self.xi0, xe)

    def ceil_y(self, z):
        """interior ceiling height at |z|"""
        c = self.c
        pts = self.ceil_profile
        z = abs(z)
        best = c['i_top']
        for i in range(len(pts) - 1):
            z0, y0 = pts[i]; z1, y1 = pts[i + 1]
            if z1 <= z <= z0:
                t = (z0 - z) / max(z0 - z1, 1e-9)
                return y0 + (y1 - y0) * t
        return best

    # ============================================================ door leaves
    def build_doors(self):
        c = self.c; a = self.a; fl = self.fl
        H = c['door_top'] - fl - 0.012
        W = OPEN_OFFSET
        zin, zout = a - 0.0925, a - 0.0575         # |z| of inner / outer face
        zmid = (zin + zout) / 2
        WX = (0.12, 0.60)
        WY = (0.66, min(1.56, H - 0.14))
        if c['kind'] == 'ss':
            WY = (0.70, H - 0.16)
        for s in (1, -1):
            side = 'R' if s > 0 else 'L'
            for di, xd in enumerate(self.doors):
                for leaf in ('a', 'b'):
                    d = -1 if leaf == 'a' else 1        # direction of leaf extent from origin (a: -x)
                    mb = new_mb('door_%s%d_%s' % (side, di, leaf))
                    mb.tiles.update(TILES)
                    mb.colfn = self.leaf_col(xd, s * zmid)
                    self.make_leaf(mb, s, d, W, H, zin, zout, zmid, WX, WY)
                    name = 'door_%s%d_%s' % (side, di, leaf)
                    self.leaves.append((name, mb, (xd, fl + 0.006, s * zmid),
                                        dict(kind='door', slide_dir=d, open_offset=OPEN_OFFSET, side=side, index=di)))
                self.doorlist.append(dict(id='%s%d' % (side, di), side=side, x=xd, z=s * zmid,
                                          leaves=['door_%s%d_a' % (side, di), 'door_%s%d_b' % (side, di)],
                                          open_offset=OPEN_OFFSET, width=c['door_w']))

    def leaf_col(self, xd, zc):
        fl = self.fl
        def f(m, p, n):
            q = (p[0] + xd, p[1] + fl + 0.006, p[2] + zc)
            if m in ('mat_livery', 'mat_glass'):
                return self.col_ext(m, q, n)
            return self.col_int(m, q, n)
        return f

    def make_leaf(self, mb, s, d, W, H, zin, zout, zmid, WX, WY):
        """leaf local frame: origin at (xd, floor+.006, s*zmid); leaf extends from x=0 to x=d*W (meeting edge at 0)"""
        lz = lambda z: s * (z - zmid)        # local z of a |z| value
        ho = (0, 0, s)                       # outward
        hi = (0, 0, -s)
        # x mapping: |x| in [0,W] -> x = d*|x|
        X = lambda t: d * t
        win = (WX[0], WX[1], WY[0], WY[1])
        xs = sorted(set([0.0, W, win[0], win[1]])); ys = sorted(set([0.0, H, win[2], win[3]]))
        zo_l = lz(zout); zi_l = lz(zin)
        for i in range(len(xs) - 1):
            for j in range(len(ys) - 1):
                t0, t1 = xs[i], xs[i + 1]; y0, y1 = ys[j], ys[j + 1]
                if win[0] < (t0 + t1) / 2 < win[1] and win[2] < (y0 + y1) / 2 < win[3]:
                    continue
                # outer skin (livery)
                pts = [(X(t0), y0, zo_l), (X(t1), y0, zo_l), (X(t1), y1, zo_l), (X(t0), y1, zo_l)]
                mb.face('mat_livery', pts, hint=ho)
                # inner face: uv into unique door_inner texture, hazard band at the meeting edge (u = 1 - t/W)
                pts = [(X(t0), y0, zi_l), (X(t1), y0, zi_l), (X(t1), y1, zi_l), (X(t0), y1, zi_l)]
                uvs = [(1 - t0 / W, y0 / H), (1 - t1 / W, y0 / H), (1 - t1 / W, y1 / H), (1 - t0 / W, y1 / H)]
                mb.face('mat_door_inner', pts, hint=hi, uvs=uvs)
        # window reveal (thin) + glass
        wx0, wx1, wy0, wy1 = win
        for (pa, pb, hnt) in (
                ((X(wx0), wy0), (X(wx1), wy0), (0, 1, 0)), ((X(wx0), wy1), (X(wx1), wy1), (0, -1, 0))):
            mb.face('mat_livery', [(pa[0], pa[1], zo_l), (pb[0], pb[1], zo_l), (pb[0], pb[1], zi_l), (pa[0], pa[1], zi_l)], hint=hnt)
        # vertical reveal sides: face towards the window centre
        xc_w = (X(wx0) + X(wx1)) / 2
        for xx in (X(wx0), X(wx1)):
            mb.face('mat_livery', [(xx, wy0, zo_l), (xx, wy1, zo_l), (xx, wy1, zi_l), (xx, wy0, zi_l)], hint=(xc_w - xx, 0, 0))
        zg = 0.0
        mb.face('mat_glass', [(X(wx0), wy0, zg), (X(wx1), wy0, zg), (X(wx1), wy1, zg), (X(wx0), wy1, zg)], hint=ho)
        # edges: meeting edge (hazard), far edge, top, bottom
        mb.face('mat_door_inner', [(0, 0, zo_l), (0, H, zo_l), (0, H, zi_l), (0, 0, zi_l)], hint=(-d, 0, 0),
                uvs=[(0.96, 0.5), (0.96, 0.6), (0.98, 0.6), (0.98, 0.5)])
        mb.face('mat_livery', [(X(W), 0, zo_l), (X(W), H, zo_l), (X(W), H, zi_l), (X(W), 0, zi_l)], hint=(d, 0, 0))
        mb.face('mat_livery', [(0, H, zo_l), (X(W), H, zo_l), (X(W), H, zi_l), (0, H, zi_l)], hint=(0, 1, 0))
        mb.face('mat_livery', [(0, 0, zo_l), (X(W), 0, zo_l), (X(W), 0, zi_l), (0, 0, zi_l)], hint=(0, -1, 0))
        # handle bar on the inner face near the meeting edge? (kept simple)

    # ============================================================ interior shell (lining, floor, ends)
    def build_interior_shell(self):
        c = self.c; a = self.a; ai = self.ai; fl = self.fl
        it = self.int
        holes = []
        for xd in self.doors:
            holes.append((xd - c['door_w'] / 2, xd + c['door_w'] / 2, fl, c['door_top']))
        for (wa, wb) in self.wins:
            holes.append((wa, wb, c['sill'], c['head']))
        xe = self.xi1
        if self.cab:
            xe = self.x1 - 0.05
            holes.append((self.cdoor[0], self.cdoor[1], fl, c['door_top']))
            holes.append((self.cwin[0], self.cwin[1], c['sill'] - 0.02, c['head'] + 0.06))
        ybreaks = [fl + 0.15, fl + 0.4, fl + 0.8, c['sill'] - 0.2, c['head'] + 0.1]
        xbreaks = [self.xi0 + 1.5 * k for k in range(1, int(self.L / 1.5))]
        for s in (1, -1):
            off = (0.13 * s, 0.0)
            wall_cells(it, lambda ya, yb: 'mat_wall', self.xi0, xe, fl, c['i_cant'], ai, s, holes, xbreaks, ybreaks, inward=True, off=off)
            for xd in self.doors:
                x0 = xd - c['door_w'] / 2; x1 = xd + c['door_w'] / 2
                # bright frame around the doorway inside
                fw = 0.04; pr = 0.012
                zlo, zhi = (ai - pr, ai) if s > 0 else (-ai, -ai + pr)
                it.box('mat_frame', (x0 - fw, fl, zlo), (x0, c['door_top'] + 0.02, zhi))
                it.box('mat_frame', (x1, fl, zlo), (x1 + fw, c['door_top'] + 0.02, zhi))
                it.box('mat_frame', (x0 - fw, c['door_top'], zlo), (x1 + fw, c['door_top'] + 0.02, zhi))
                # yellow/black safety edging on the threshold
                it.face('mat_safety', [(x0, fl + 0.001, s * (ai - 0.10)), (x1, fl + 0.001, s * (ai - 0.10)), (x1, fl + 0.001, s * (ai - 0.02)), (x0, fl + 0.001, s * (ai - 0.02))], hint=(0, 1, 0))
            for (wa, wb) in self.wins:
                # frame reveals seen from inside are part of the exterior mesh (reveal) ; add proud inner frame
                fw = 0.03; pr = 0.008
                zlo, zhi = (ai - pr, ai) if s > 0 else (-ai, -ai + pr)
                it.box('mat_frame', (wa - fw, c['sill'] - fw, zlo), (wb + fw, c['sill'], zhi))
                it.box('mat_frame', (wa - fw, c['head'], zlo), (wb + fw, c['head'] + fw, zhi))
                it.box('mat_frame', (wa - fw, c['sill'], zlo), (wa, c['head'], zhi))
                it.box('mat_frame', (wb, c['sill'], zlo), (wb + fw, c['head'], zhi))
        # floor: subdivided grid for vertex-colour wear
        nx = max(1, int((xe - self.xi0) / 0.5)); nz = 10
        it.grid('mat_floor', (self.xi0, fl, -ai), (xe - self.xi0, 0, 0), (0, 0, 2 * ai), nx, nz, (0, 1, 0))
        # floor thickness edge at doors is covered by sills

    # ============================================================ ends (bulkheads / gangway)
    def build_ends(self):
        c = self.c; ai = self.ai; fl = self.fl; a = self.a
        it = self.int; ext = self.ext
        outer = prof_full(a, c['cant'], c['top'] - c['cant'], c['roof_n'])
        inner = prof_full(ai, c['i_cant'], c['i_top'] - c['i_cant'], c['roof_n'])
        ends = [(-1, self.xi0, self.x0)]
        if not self.cab:
            ends.append((1, self.xi1, self.x1))
        for (sx, xi, xo) in ends:
            if c['gang']:
                self.build_gangway_end(sx, xi, xo)
                continue
            # interior bulkhead polygon
            poly = [(xi, fl, ai)] + [(xi, y, z) for (z, y) in inner] + [(xi, fl, -ai)]
            it.face('mat_wall', poly, hint=(-sx, 0, 0))
            # closed inter-car door: frame + panel + window (proud of the bulkhead, facing the saloon)
            dh = c['door_top'] - fl - 0.06
            def px(d0, d1):
                return tuple(sorted((xi - sx * d0, xi - sx * d1)))
            xa, xb = px(0.0, 0.03)
            it.box('mat_frame', (xa, fl, -0.44), (xb, fl + dh, 0.44), skip=('+x' if sx > 0 else '-x',))
            xa, xb = px(0.03, 0.05)
            it.box('mat_door_inner', (xa, fl + 0.03, -0.38), (xb, fl + dh - 0.05, 0.38), skip=('+x' if sx > 0 else '-x',))
            xg = xi - sx * 0.052
            self.gl.face('mat_glass', [(xg, fl + 1.05, -0.24), (xg, fl + 1.05, 0.24), (xg, fl + 1.72, 0.24), (xg, fl + 1.72, -0.24)], hint=(-sx, 0, 0))
            # exterior end plate (dark: seen only in the gap between coupled cars)
            poly = [(xo, c['ybot'], a)] + [(xo, y, z) for (z, y) in outer] + [(xo, c['ybot'], -a)]
            ext.face('mat_trim', poly, hint=(sx, 0, 0))
            self.markers.append(dict(name='enddoor_%s' % ('F' if sx > 0 else 'B'), pos=(xi - sx * 0.6, fl, 0), yaw=0 if sx < 0 else 180, kind='enddoor'))

    def build_gangway_end(self, sx, xi, xo):
        c = self.c; ai = self.ai; fl = self.fl; a = self.a
        it = self.int; ext = self.ext
        inner = prof_full(ai, c['i_cant'], c['i_top'] - c['i_cant'], c['roof_n'])
        outer = prof_full(a, c['cant'], c['top'] - c['cant'], c['roof_n'])
        gw = 0.78; gh = fl + 2.12
        h = (-sx, 0, 0)
        # ---- interior end wall around the opening: two side slabs (floor->ceiling profile) and a lintel
        for s in (1, -1):
            seg = [(z, y) for (z, y) in inner if z * s >= gw - 1e-6]
            seg = seg if s > 0 else seg[::-1]
            poly = [(xi, fl, s * gw), (xi, fl, s * ai), (xi, c['i_cant'], s * ai)] + [(xi, y, z) for (z, y) in seg[1:]]
            yg = self.ceil_y(gw)
            poly.append((xi, yg, s * gw))
            it.face('mat_wall', poly, hint=h)
        yg = self.ceil_y(gw)
        seg = [(z, y) for (z, y) in inner if abs(z) < gw]
        it.face('mat_wall', [(xi, gh, -gw), (xi, gh, gw), (xi, yg, gw)] + [(xi, y, z) for (z, y) in seg] + [(xi, yg, -gw)], hint=h)
        # frame ring around the opening
        fw = 0.05
        it.box('mat_frame', (min(xi, xi - sx * 0.02), fl, -gw - fw), (max(xi, xi - sx * 0.02), gh + fw, -gw))
        it.box('mat_frame', (min(xi, xi - sx * 0.02), fl, gw), (max(xi, xi - sx * 0.02), gh + fw, gw + fw))
        it.box('mat_frame', (min(xi, xi - sx * 0.02), gh, -gw - fw), (max(xi, xi - sx * 0.02), gh + fw, gw + fw))
        # ---- bellows: rectangular pleated tube from the end wall to 0.25 m beyond the body end
        ext_len = 0.25
        xe = xo + sx * ext_len
        bw = gw + 0.05; bh = gh + 0.05; bb = fl - 0.03
        nrib = 9
        xsr = [xi + (xe - xi) * k / nrib for k in range(nrib + 1)]
        for face_in, dr in ((True, 0.0), (False, 0.008)):
            rings = []
            for k, x in enumerate(xsr):
                r = (0.0 if k % 2 == 0 else 0.045) + dr
                rings.append([(x, bb - dr, -bw - r), (x, bb - dr, bw + r), (x, bh + r, bw + r), (x, bh + r, -bw - r), (x, bb - dr, -bw - r)])
            for k in range(nrib):
                for e in range(4):
                    A = rings[k]; B = rings[k + 1]
                    pts = [A[e], B[e], B[e + 1], A[e + 1]]
                    mx = sum(p[1] for p in pts) / 4; mz = sum(p[2] for p in pts) / 4
                    hint = (0, (mx - (bb + bh) / 2) * (-1 if face_in else 1), mz * (-1 if face_in else 1))
                    it.face('mat_trim', pts, hint=hint, uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
        # walkable gangway plate
        it.box('mat_underframe', (min(xi - sx * 0.05, xe), fl - 0.03, -bw), (max(xi - sx * 0.05, xe), fl, bw), skip=('-y',))
        # ---- exterior end plate around the bellows
        for s in (1, -1):
            seg = [(z, y) for (z, y) in outer if z * s >= bw - 1e-6]
            seg = seg if s > 0 else seg[::-1]
            poly = [(xo, c['ybot'], s * bw), (xo, c['ybot'], s * a), (xo, c['cant'], s * a)] + [(xo, y, z) for (z, y) in seg[1:]]
            yo = None
            # close to the bellows top edge
            zt = s * bw
            # ceiling height of outer profile at |z|=bw
            yo = c['top']
            for i in range(len(outer) - 1):
                z0, y0_ = outer[i]; z1, y1_ = outer[i + 1]
                if z1 <= bw <= z0:
                    yo = y0_ + (y1_ - y0_) * (z0 - bw) / max(z0 - z1, 1e-9)
            poly.append((xo, yo, s * bw))
            ext.face('mat_trim', poly, hint=(sx, 0, 0))
        yo = c['top']
        for i in range(len(outer) - 1):
            z0, y0_ = outer[i]; z1, y1_ = outer[i + 1]
            if z1 <= bw <= z0:
                yo = y0_ + (y1_ - y0_) * (z0 - bw) / max(z0 - z1, 1e-9)
        seg = [(z, y) for (z, y) in outer if abs(z) < bw]
        ext.face('mat_trim', [(xo, bh, -bw), (xo, bh, bw), (xo, yo, bw)] + [(xo, y, z) for (z, y) in seg] + [(xo, yo, -bw)], hint=(sx, 0, 0))
        self.markers.append(dict(name='gangway_%s' % ('F' if sx > 0 else 'B'), pos=(xi - sx * 0.3, fl, 0), yaw=0, kind='gangway'))

    # ============================================================ seating
    def build_seating(self):
        c = self.c; ai = self.ai; fl = self.fl
        it = self.int
        sd = c['seat_d']
        self.seat_pos = {1: [], -1: []}              # (x, y, z[, yaw]) of every seat; no yaw: facing across the car
        self.seat_colliders = {1: [], -1: []}
        self.seat_boxes = {1: [], -1: []}            # transverse seats: (x0, x1, z0, z1, top)
        self.trans_bays = []                         # (xa, xb) of the bays with transverse seating
        self.run_mixed = set()
        n_prio = 2
        for s in (1, -1):
            for (sa, sb, n, ta, tb) in self.runs:
                if c.get('seating') == 'mixed' and (ta == 'end' or tb == 'end') and (sb - sa) >= 1.75:
                    # a bay at the end of the car: two double seats facing each other across the bay
                    self.run_mixed.add((sa, sb, n, ta, tb))
                    self.transverse_bay(s, sa, sb)
                    continue
                w = (sb - sa) / n
                # base box (dark plastic) with heater-grille slots
                zb0 = s * (ai - sd + 0.03); zb1 = s * ai
                it.box('mat_plastic', (sa, fl, min(zb0, zb1)), (sb, fl + 0.36, max(zb0, zb1)), bevel=0.008, skip=('-y',))
                zf = zb0
                for gx in range(int((sb - sa) / 0.9)):
                    gx0 = sa + 0.15 + gx * 0.9
                    for k in range(5):
                        it.box('mat_trim', (gx0 + k * 0.12, fl + 0.08, min(zf, zf - s * 0.004)), (gx0 + k * 0.12 + 0.06, fl + 0.26, max(zf, zf - s * 0.004)), skip=('-x', '+x'))
                for i in range(n):
                    xc = sa + (i + 0.5) * w
                    prio = (i < n_prio and ta == 'door') or (i >= n - n_prio and tb == 'door')
                    mat = 'mat_moquette_prio' if prio else c['moq']
                    off = (random.random(), random.random())
                    zc0 = s * (ai - 0.04); zc1 = s * (ai - 0.04 - sd)
                    it.box(mat, (xc - w / 2 + 0.005, fl + 0.33, min(zc0, zc1)), (xc + w / 2 - 0.005, fl + c['seat_h'], max(zc0, zc1)), bevel=0.028, off=off)
                    # backrest, tilted about x (top leans towards the wall)
                    old = it.xf
                    piv = (xc, fl + c['seat_h'], s * (ai - 0.055))
                    it.xf = Rot('x', 7.0 * s, pivot=piv)
                    zr0 = s * (ai - 0.125); zr1 = s * (ai - 0.055)
                    it.box(mat, (xc - w / 2 + 0.005, fl + c['seat_h'] + 0.005, min(zr0, zr1)), (xc + w / 2 - 0.005, fl + 0.92, max(zr0, zr1)), bevel=0.03, off=off)
                    it.xf = old
                    self.seat_pos[s].append((xc, fl + c['seat_h'], s * (ai - 0.04 - sd * 0.5)))
                # armrests between groups of three and at the door-side ends
                arm_x = [sa + i * w for i in range(3, n, 3)]
                if ta == 'door': arm_x.append(sa + 0.02)
                if tb == 'door': arm_x.append(sb - 0.02)
                for ax in arm_x:
                    za = s * (ai - 0.08); zb_ = s * (ai - 0.04 - sd + 0.02)
                    it.box('mat_plastic', (ax - 0.018, fl + c['seat_h'] - 0.02, min(za, zb_)), (ax + 0.018, fl + c['seat_h'] + 0.17, max(za, zb_)), bevel=0.012)
                self.seat_colliders[s].append((sa, sb, s))
                # glass screens + steel frame at the door-side run ends
                for (xg, sign, is_door) in ((sa, -1, ta == 'door'), (sb, 1, tb == 'door')):
                    if not is_door:
                        continue
                    z_a = s * (ai - 0.02); z_b = s * (ai - 0.03 - 0.41)
                    hh = fl + 1.32
                    xg2 = xg + sign * 0.0
                    self.gl.face('mat_glass', [(xg2, fl + 0.46, z_a), (xg2, fl + 0.46, z_b), (xg2, hh, z_b), (xg2, hh, z_a)], hint=(sign, 0, 0))
                    it.cyl('mat_pole', (xg2, hh, z_a), (xg2, hh, z_b), 0.013, 8, caps=True)
                    it.cyl('mat_pole', (xg2, fl + 0.46, z_b), (xg2, hh, z_b), 0.013, 8, caps=True)
                    it.cyl('mat_pole', (xg2, fl + 0.46, z_a), (xg2, fl + 0.46, z_b), 0.010, 8, caps=True)

    def transverse_bay(self, s, xa, xb):
        """a bay of transverse seating on the side s: a double seat at each end of the bay, the two facing each other, the aisle left free"""
        c = self.c; ai = self.ai; fl = self.fl
        it = self.int
        depth = 0.45
        span = 0.95                     # two seats across, wall to aisle
        if s > 0 and not any(abs(b[0] - xa) < 0.01 for b in self.trans_bays):
            self.trans_bays.append((xa, xb))
        z_wall = s * ai
        z_aisle = s * (ai - span)
        zlo, zhi = min(z_wall, z_aisle), max(z_wall, z_aisle)
        for (x0, fx) in ((xa, 1), (xb - depth, -1)):          # fx: the way the seats face along the car
            x1 = x0 + depth
            mat = c['moq']
            off = (random.random(), random.random())
            # pedestal on the wall side, cushion, tilted high back
            it.box('mat_plastic', (x0 + 0.02, fl, min(z_wall, z_wall - s * 0.22)), (x1 - 0.02, fl + 0.34, max(z_wall, z_wall - s * 0.22)), bevel=0.008, skip=('-y',))
            it.box(mat, (x0 + 0.005, fl + 0.33, zlo + 0.005), (x1 - 0.005, fl + c['seat_h'], zhi - 0.005), bevel=0.028, off=off)
            xb_back0, xb_back1 = (x0, x0 + 0.09) if fx > 0 else (x1 - 0.09, x1)
            old = it.xf
            xp = x0 if fx > 0 else x1
            it.xf = Rot('z', 7.0 * fx, pivot=(xp, fl + c['seat_h'], 0.0))
            it.box(mat, (xb_back0, fl + c['seat_h'] + 0.005, zlo + 0.005), (xb_back1, fl + 0.98, zhi - 0.005), bevel=0.03, off=off)
            it.xf = old
            # the aisle-end stanchion on the back of the seat
            xs = xb_back0 + 0.045
            it.cyl('mat_pole', (xs, fl + 0.90, z_aisle), (xs, fl + 1.36, z_aisle), 0.014, 8, caps=True)
            # a divider/armrest between the two seats and at the aisle end
            xm = (x0 + x1) / 2
            for zz in (s * (ai - span * 0.5), z_aisle):
                it.box('mat_plastic', (xm - 0.17, fl + c['seat_h'] - 0.02, zz - 0.012), (xm + 0.17, fl + c['seat_h'] + 0.15, zz + 0.012), bevel=0.01)
            yaw = -90 if fx > 0 else 90          # a marker looks along its -Z: -90 turns that to +X
            for k in range(2):
                zc = s * (ai - span * (0.25 + 0.5 * k))
                self.seat_pos[s].append((xm, fl + c['seat_h'], zc, yaw))
            self.seat_boxes[s].append((x0, x1, zlo, zhi, fl + c['seat_h'] + 0.02, xb_back0, xb_back1))

    # ============================================================ poles, rails
    def build_poles_rails(self):
        c = self.c; fl = self.fl; ai = self.ai
        it = self.int
        ytop = self.ceil_y(c['pole_z']) - 0.005
        self.poles = []
        for xd in self.doors:
            for sx in (-1, 1):
                for s in (1, -1):
                    px = xd + sx * (c['door_w'] / 2 + 0.135)
                    pz = s * c['pole_z']
                    if self.xi0 + 0.1 < px < self.xi1 - 0.1:
                        self.poles.append((px, pz))
        for (px, pz) in self.poles:
            vpole(it, 'mat_pole', px, pz, fl, self.ceil_y(pz) - 0.005)
        # overhead rails (both sides) with ceiling brackets
        rx0 = self.xi0 + 0.25; rx1 = (self.xi1 if not self.cab else self.xi1) - 0.25
        self.rails = []
        for s in (1, -1):
            zr = s * c['rail_z']
            it.cyl('mat_pole', (rx0, c['rail_y'], zr), (rx1, c['rail_y'], zr), 0.017, 8, caps=True)
            self.rails.append((rx0, rx1, s * c['rail_z'], c['rail_y']))
            nb = int((rx1 - rx0) / 1.3) + 1
            for k in range(nb + 1):
                bx = rx0 + (rx1 - rx0) * k / nb
                yc = self.ceil_y(zr)
                it.cyl('mat_pole', (bx, c['rail_y'], zr), (bx, yc, zr), 0.011, 6, caps=False)
                it.cyl('mat_frame', (bx, yc - 0.012, zr), (bx, yc, zr), 0.03, 8, caps=True)
        # hanging grab handles (loops) at door zones: small torus-ish D handle made of 3 cylinders
        for xd in self.doors:
            for s in (1, -1):
                zr = s * c['rail_z']
                for dx in (-0.35, 0.35):
                    hx = xd + dx
                    yb = c['rail_y'] - 0.20
                    it.cyl('mat_plastic', (hx - 0.05, yb, zr), (hx + 0.05, yb, zr), 0.012, 6, caps=True)
                    it.cyl('mat_plastic', (hx - 0.05, yb, zr), (hx - 0.05, c['rail_y'], zr), 0.004, 4, caps=False)
                    it.cyl('mat_plastic', (hx + 0.05, yb, zr), (hx + 0.05, c['rail_y'], zr), 0.004, 4, caps=False)

    # ============================================================ lighting fixtures, adverts, linemap
    def build_lighting_and_signage(self):
        c = self.c; it = self.int; fl = self.fl; ai = self.ai
        xa, xb = self.xi0 + 0.3, (self.x1 - 2.2 if self.cab else self.xi1 - 0.3)
        # LED light strips in the ceiling (frame + emissive diffuser)
        seglen = 1.5; gap = 0.22
        n = int((xb - xa + gap) / (seglen + gap))
        x_start = xa + ((xb - xa) - (n * seglen + (n - 1) * gap)) / 2
        self.light_x = []
        for zr in c['light_rows']:
            yc = self.ceil_y(zr)
            for k in range(n):
                x0 = x_start + k * (seglen + gap)
                it.box('mat_frame', (x0, yc - 0.03, zr - 0.075), (x0 + seglen, yc - 0.006, zr + 0.075), bevel=0.006)
                it.face('mat_light_emissive', [(x0 + 0.03, yc - 0.0305, zr - 0.05), (x0 + seglen - 0.03, yc - 0.0305, zr - 0.05), (x0 + seglen - 0.03, yc - 0.0305, zr + 0.05), (x0 + 0.03, yc - 0.0305, zr + 0.05)], hint=(0, -1, 0),
                        uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
                if zr == c['light_rows'][0]:
                    self.light_x.append(x0 + seglen / 2)
        # ceiling fittings: PA speaker grilles + CCTV domes at the saloon ends
        xspk0 = self.xi0 + 1.6; xspk1 = (self.x1 - 3.5) if self.cab else self.xi1 - 1.6
        k = 0; xk = xspk0
        while xk < xspk1:
            zk = (0.80 if k % 2 == 0 else -0.80) * (c['a'] / 1.31)
            yk = self.ceil_y(zk)
            it.cyl('mat_frame', (xk, yk - 0.012, zk), (xk, yk, zk), 0.065, 14, caps=True)
            xk += 3.2; k += 1
        for xk, dirn in ((self.xi0 + 0.35, 1), ((self.xi1 - 0.35) if not self.cab else None, -1)):
            if xk is None:
                continue
            yk = self.ceil_y(0.0)
            it.cyl('mat_trim', (xk, yk - 0.015, 0.0), (xk, yk, 0.0), 0.085, 12, caps=True)
            it.cyl('mat_trim', (xk, yk - 0.06, 0.0), (xk, yk - 0.015, 0.0), 0.05, 12, caps=True, r1=0.075)
        # wall band above the windows: line-diagram strip + advert frames (poster 4:1)
        y0, y1 = c['band']
        adv = 0
        hwd = c['door_w'] / 2 + 0.08
        for s in (1, -1):
            for bi in range(len(self.doors) + 1):
                xa_ = self.xi0 + 0.05 if bi == 0 else self.doors[bi - 1] + hwd
                xb_ = (self.xi1 - 0.05) if bi == len(self.doors) else self.doors[bi] - hwd
                ln = xb_ - xa_ - 0.1
                if ln < 1.2:
                    continue
                zw = s * (ai - 0.003)
                ym = (y0 + y1) / 2
                ph = y1 - y0 - 0.04; pw = 4.0 * ph
                lh = 0.13; lw = 1.30 if ln > 2 * (pw + 0.12) + 1.3 else 1.0
                gap = 0.12
                items = []
                if ln >= 2 * pw + lw + 2 * gap:
                    items = [('ad', pw), ('map', lw), ('ad', pw)]
                elif ln >= pw + lw + gap:
                    items = [('map', lw), ('ad', pw)] if (bi % 2) else [('ad', pw), ('map', lw)]
                else:
                    items = [('map', min(lw, ln))]
                tot = sum(w for _, w in items) + gap * (len(items) - 1)
                xcur = (xa_ + xb_) / 2 - tot / 2
                for kind, w in items:
                    xm = xcur + w / 2
                    if kind == 'map':
                        self.quad_wall('mat_linemap', xm - w / 2, xm + w / 2, ym - lh / 2, ym + lh / 2, zw, s, uv=((0, 0), (1, 1)))
                    else:
                        self.quad_wall('mat_advert_%d' % (adv % 4), xm - w / 2, xm + w / 2, ym - ph / 2, ym + ph / 2, zw, s, uv=((0, 0), (1, 1)))
                        adv += 1
                        fz0 = min(zw, zw - s * 0.006); fz1 = max(zw, zw - s * 0.006)
                        f = 0.012
                        it.box('mat_frame', (xm - w / 2 - f, ym - ph / 2 - f, fz0), (xm + w / 2 + f, ym - ph / 2, fz1))
                        it.box('mat_frame', (xm - w / 2 - f, ym + ph / 2, fz0), (xm + w / 2 + f, ym + ph / 2 + f, fz1))
                        it.box('mat_frame', (xm - w / 2 - f, ym - ph / 2, fz0), (xm - w / 2, ym + ph / 2, fz1))
                        it.box('mat_frame', (xm + w / 2, ym - ph / 2, fz0), (xm + w / 2 + f, ym + ph / 2, fz1))
                    xcur += w + gap
        # priority signs above priority seats
        for s in (1, -1):
            for (sa, sb, n, ta, tb) in self.runs:
                if (sa, sb, n, ta, tb) in self.run_mixed:
                    continue
                w = (sb - sa) / n
                zw = s * (ai - 0.003)
                for (cond, xc) in ((ta == 'door', sa + 0.55 * w), (tb == 'door', sb - 0.55 * w)):
                    if cond:
                        self.quad_wall('mat_priority_sign', xc - 0.11, xc + 0.11, fl + 1.15, fl + 1.37, zw, s, uv=((0, 0), (1, 1)))

    def quad_wall(self, mat, x0, x1, y0, y1, z, s, uv=None):
        quad_xy(self.int, mat, x0, x1, y0, y1, z, (0, 0, -s), uv=uv)

    # ============================================================ cab
    def build_cab(self):
        c = self.c; a = self.a; ai = self.ai; fl = self.fl
        it = self.int; ext = self.ext
        xf = self.x1
        xp = self.x_part
        # partition wall with door
        it.box('mat_wall', (xp, fl, -ai), (xp + 0.10, c['i_cant'], ai), skip=('-y', '+y'))
        # sketch of cab interior : floor, ceiling done ; desk
        # exterior front
        a2 = a - 0.10; cant2 = c['cant'] - 0.02; top2 = c['top'] - 0.07; yb2 = c['ybot'] + 0.05
        outer = prof_full(a, c['cant'], c['top'] - c['cant'], c['roof_n'])
        inner2 = prof_full(a2, cant2, top2 - cant2, c['roof_n'])
        # extrude body: main shell ends at xf-0.12 (rolled lip)
        lip = 0.14
        xl = xf - lip
        fr = c.get('front_round', 0.0)
        if fr > 0.0:
            # a rounded nose: everything on the front plane (and what is proud of or just behind it) is pushed forward by a dome in plan (full at the middle, none at the sides) that is fullest at window height
            a_f = a2
            def bulge(p, fr=fr, xf=xf, a_f=a_f, top=cant2 + 0.1):
                x, y, z = p
                if x < xf - 0.12:
                    return p
                k = max(0.0, 1.0 - (z / a_f) ** 2)
                r = 0.35 + 0.65 * sstep(0.5, 1.2, y) - 0.55 * sstep(2.1, top, y)
                return (x + fr * k * r, y, z)
            ext.xf = bulge
            self.gl.xf = bulge
        # lip ring: outer profile at xl -> inset profile at xf
        ring_a = [(xl, c['ybot'], a)] + [(xl, y, z) for (z, y) in outer] + [(xl, c['ybot'], -a)]
        ring_b = [(xf, yb2, a2)] + [(xf, y, z) for (z, y) in inner2] + [(xf, yb2, -a2)]
        # build lip with polylines connected consecutively
        uvv = arc_lengths([(p[2], p[1]) for p in ring_a])
        ext.sweep('mat_body_paint', [ring_a, ring_b], [0.0, lip], [q / 2.0 for q in uvv], around=(1.8, 0.0))
        # lip's lower edge: dark trim under
        ext.face('mat_trim', [(xl, c['ybot'], a), (xf, yb2, a2), (xf, yb2, -a2), (xl, c['ybot'], -a)], hint=(0, -1, 0))
        # roof/shell hole: the roof sweep already runs the full length; trim it back at xl? -> roof extends to xf; make the roof end at xl by not building past. (roof built to x1; the lip overlaps. acceptable)
        # ---- front face
        fw = c['front_win']; fz = c['front_z']
        yb_face = yb2
        holes = [(fz[0], fz[1], fw[0], fw[1]), (-fz[1], -fz[0], fw[0], fw[1]),
                 (-0.24, 0.24, fw[0] + 0.05, fw[1] - 0.15)]
        zs_ = sorted(set([-a2, a2] + [h[0] for h in holes] + [h[1] for h in holes] + [-0.34, 0.34]))
        ys_ = sorted(set([yb_face, cant2] + [h[2] for h in holes] + [h[3] for h in holes] + [1.1, 1.45, 1.6, 0.95]))
        if fr > 0.0:
            zs_ = sorted(set(zs_ + [round(-a2 + k * a2 / 8.0, 3) for k in range(17)]))
            ys_ = sorted(set(ys_ + [round(yb_face + k * (cant2 - yb_face) / 8.0, 3) for k in range(9)]))
        face_h = (1, 0, 0)

        def fmat(ya, yb, za, zb):
            if yb <= 1.46: return 'mat_livery'
            return 'mat_body_paint'
        for i in range(len(zs_) - 1):
            for j in range(len(ys_) - 1):
                za, zb, ya, yb = zs_[i], zs_[i + 1], ys_[j], ys_[j + 1]
                cz = (za + zb) / 2; cy = (ya + yb) / 2
                if any(h[0] < cz < h[1] and h[2] < cy < h[3] for h in holes):
                    continue
                ext.face(fmat(ya, yb, za, zb), [(xf, ya, za), (xf, ya, zb), (xf, yb, zb), (xf, yb, za)], hint=face_h)
        # roof cap of the face
        poly = [(xf, cant2, a2)] + [(xf, y, z) for (z, y) in inner2[1:-1]] + [(xf, cant2, -a2)]
        ext.face('mat_body_paint', poly, hint=face_h)
        # window reveals + glass
        for (z0, z1, y0, y1) in [(fz[0], fz[1], fw[0], fw[1]), (-fz[1], -fz[0], fw[0], fw[1])]:
            zc = (z0 + z1) / 2
            ext.face('mat_trim', [(xf, y0, z0), (xf, y0, z1), (xf - 0.10, y0, z1), (xf - 0.10, y0, z0)], hint=(0, 1, 0))
            ext.face('mat_trim', [(xf, y1, z0), (xf, y1, z1), (xf - 0.10, y1, z1), (xf - 0.10, y1, z0)], hint=(0, -1, 0))
            ext.face('mat_trim', [(xf, y0, z0), (xf, y1, z0), (xf - 0.10, y1, z0), (xf - 0.10, y0, z0)], hint=(0, 0, 1))
            ext.face('mat_trim', [(xf, y0, z1), (xf, y1, z1), (xf - 0.10, y1, z1), (xf - 0.10, y0, z1)], hint=(0, 0, -1))
            self.gl.face('mat_glass', [(xf - 0.03, y0, z0), (xf - 0.03, y0, z1), (xf - 0.03, y1, z1), (xf - 0.03, y1, z0)], hint=(1, 0, 0))
            # wiper: arm + blade
            zw0, zw1 = (z1 - 0.06, z0 + 0.10) if zc > 0 else (z0 + 0.06, z1 - 0.10)
            ext.cyl('mat_trim', (xf + 0.022, y0 + 0.035, zw0), (xf + 0.022, y0 + 0.36, zw1), 0.006, 6, caps=True)
            # frame proud
            f = 0.04; p = 0.012
            ext.box('mat_trim', (xf, y0 - f, z0 - f), (xf + p, y0, z1 + f))
            ext.box('mat_trim', (xf, y1, z0 - f), (xf + p, y1 + f, z1 + f))
            ext.box('mat_trim', (xf, y0, z0 - f), (xf + p, y1, z0))
            ext.box('mat_trim', (xf, y0, z1), (xf + p, y1, z1 + f))
        # central emergency door: window glass + door frame
        hz = 0.24; hy0 = fw[0] + 0.05; hy1 = fw[1] - 0.15
        ext.face('mat_trim', [(xf, hy0, -hz), (xf, hy0, hz), (xf - 0.06, hy0, hz), (xf - 0.06, hy0, -hz)], hint=(0, 1, 0))
        ext.face('mat_trim', [(xf, hy1, -hz), (xf, hy1, hz), (xf - 0.06, hy1, hz), (xf - 0.06, hy1, -hz)], hint=(0, -1, 0))
        ext.face('mat_trim', [(xf, hy0, -hz), (xf, hy1, -hz), (xf - 0.06, hy1, -hz), (xf - 0.06, hy0, -hz)], hint=(0, 0, 1))
        ext.face('mat_trim', [(xf, hy0, hz), (xf, hy1, hz), (xf - 0.06, hy1, hz), (xf - 0.06, hy0, hz)], hint=(0, 0, -1))
        self.gl.face('mat_glass', [(xf - 0.03, hy0, -hz), (xf - 0.03, hy0, hz), (xf - 0.03, hy1, hz), (xf - 0.03, hy1, -hz)], hint=(1, 0, 0))
        # door outline (frame strips)
        for zz in (-0.345, 0.335):
            ext.box('mat_trim', (xf, 0.95, zz), (xf + 0.008, fw[1], zz + 0.01), skip=())
        ext.box('mat_trim', (xf, fw[1], -0.345), (xf + 0.008, fw[1] + 0.01, 0.345))
        ext.box('mat_trim', (xf, 0.95, -0.345), (xf + 0.008, 0.96, 0.345))
        ext.box('mat_frame', (xf, 1.35, 0.26), (xf + 0.02, 1.42, 0.31), bevel=0.006)      # door handle
        # lamps
        for zz in (-0.95, 0.95):
            ext.cyl('mat_headlight', (xf, 1.05, zz), (xf + 0.03, 1.05, zz), 0.075, 16, caps=True)
            ext.cyl('mat_trim', (xf - 0.01, 1.05, zz), (xf + 0.015, 1.05, zz), 0.095, 16, caps=True)
            ext.cyl('mat_taillight', (xf, 1.28, zz), (xf + 0.02, 1.28, zz), 0.05, 12, caps=True)
        ext.cyl('mat_headlight', (xf, 2.66, 0.0), (xf + 0.02, 2.66, 0.0), 0.04, 12, caps=True)
        # destination display box
        yd0 = cant2 + 0.02; yd1 = yd0 + 0.13
        ext.box('mat_trim', (xf, yd0 - 0.02, -0.56), (xf + 0.045, yd1 + 0.02, 0.56), bevel=0.01)
        ext.face('mat_dest_display', [(xf + 0.046, yd0, 0.52), (xf + 0.046, yd0, -0.52), (xf + 0.046, yd1, -0.52), (xf + 0.046, yd1, 0.52)], hint=(1, 0, 0),
                 uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
        ext.xf = None
        self.gl.xf = None
        # side window + cab door on each side
        # (skin holes were made in ext_holes; add door leaf + glass + reveals)
        for s in (1, -1):
            x0, x1 = self.cdoor
            reveal(ext, 'mat_frame', x0, x1, fl, c['door_top'], a, ai, s, 'lrt')
            ext.box('mat_frame', (x0, fl - 0.03, s * ai if s > 0 else -a), (x1, fl, a if s > 0 else -ai))
            wa, wb = self.cwin
            reveal(ext, 'mat_trim', wa, wb, c['sill'] - 0.02, c['head'] + 0.06, a, ai, s)
            zg = s * (a - 0.045)
            self.gl.face('mat_glass', [(wa, c['sill'] - 0.02, zg), (wb, c['sill'] - 0.02, zg), (wb, c['head'] + 0.06, zg), (wa, c['head'] + 0.06, zg)], hint=(0, 0, s))
            fwid = 0.035; pr = 0.010
            zlo, zhi = (a, a + pr) if s > 0 else (-a - pr, -a)
            for (bx0, bx1, by0, by1) in ((x0 - 0.05, x0, fl - 0.02, c['door_top'] + 0.02), (x1, x1 + 0.05, fl - 0.02, c['door_top'] + 0.02), (x0 - 0.05, x1 + 0.05, c['door_top'], c['door_top'] + 0.05)):
                ext.box('mat_trim', (bx0, by0, zlo), (bx1, by1, zhi))
            # cab door leaf
            mb = new_mb('cabdoor_%s' % ('R' if s > 0 else 'L'))
            zin, zout = a - 0.0925, a - 0.0575
            zmid = (zin + zout) / 2
            mb.colfn = self.leaf_col((x0 + x1) / 2, s * zmid)
            lw = x1 - x0 - 0.01; H = c['door_top'] - fl - 0.012
            lz = lambda z: s * (z - zmid)
            # leaf spans x in [-lw/2, +lw/2] around origin (hole centre)
            hx = lw / 2
            wx0, wx1 = -hx + 0.12, hx - 0.12; wy0, wy1 = 0.75, H - 0.15
            xs = [-hx, wx0, wx1, hx]; ys = [0, wy0, wy1, H]
            for i in range(3):
                for j in range(3):
                    if i == 1 and j == 1: continue
                    pts = [(xs[i], ys[j], lz(zout)), (xs[i + 1], ys[j], lz(zout)), (xs[i + 1], ys[j + 1], lz(zout)), (xs[i], ys[j + 1], lz(zout))]
                    mb.face('mat_livery', pts, hint=(0, 0, s))
                    pts = [(xs[i], ys[j], lz(zin)), (xs[i + 1], ys[j], lz(zin)), (xs[i + 1], ys[j + 1], lz(zin)), (xs[i], ys[j + 1], lz(zin))]
                    uvs = [((xs[i] + hx) / lw, ys[j] / H), ((xs[i + 1] + hx) / lw, ys[j] / H), ((xs[i + 1] + hx) / lw, ys[j + 1] / H), ((xs[i] + hx) / lw, ys[j + 1] / H)]
                    mb.face('mat_door_inner', pts, hint=(0, 0, -s), uvs=uvs)
            mb.face('mat_glass', [(wx0, wy0, 0), (wx1, wy0, 0), (wx1, wy1, 0), (wx0, wy1, 0)], hint=(0, 0, s))
            for (p0, p1, hnt) in (((-hx, 0), (hx, 0), (0, -1, 0)), ((-hx, H), (hx, H), (0, 1, 0))):
                mb.face('mat_livery', [(p0[0], p0[1], lz(zout)), (p1[0], p1[1], lz(zout)), (p1[0], p1[1], lz(zin)), (p0[0], p0[1], lz(zin))], hint=hnt)
            for xx, hnt in ((-hx, (-1, 0, 0)), (hx, (1, 0, 0))):
                mb.face('mat_livery', [(xx, 0, lz(zout)), (xx, H, lz(zout)), (xx, H, lz(zin)), (xx, 0, lz(zin))], hint=hnt)
            self.leaves.append(('cabdoor_%s' % ('R' if s > 0 else 'L'), mb, ((x0 + x1) / 2, fl + 0.006, s * zmid),
                                dict(kind='cabdoor', slide_dir=-1, open_offset=0.82, side='R' if s > 0 else 'L')))
        # ---- cab interior: driver console, seat, front panel
        cx0 = xf - 0.95
        it.box('mat_cab_desk', (cx0, fl, -ai + 0.02), (xf - 0.06, fl + 0.85, ai - 0.02), bevel=0.02, skip=('+x', '-y'))
        # sloped console top with screens
        it.box('mat_cab_desk', (xf - 0.75, fl + 0.85, -0.55), (xf - 0.25, fl + 0.93, 0.55), bevel=0.02)
        for k, zz in enumerate((-0.35, 0.0, 0.35)):
            self.int.face('mat_cab_screen', [(xf - 0.60, fl + 0.936, zz - 0.12), (xf - 0.60, fl + 0.936, zz + 0.12), (xf - 0.42, fl + 0.936, zz + 0.12), (xf - 0.42, fl + 0.936, zz - 0.12)], hint=(0, 1, 0), uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
        it.cyl('mat_frame', (xf - 0.50, fl + 0.94, 0.45), (xf - 0.50, fl + 1.02, 0.45), 0.012, 8, caps=True)
        it.box('mat_plastic', (xf - 0.62, fl + 0.94, 0.38), (xf - 0.52, fl + 0.97, 0.52), bevel=0.01)
        # driver seat (behind the console)
        sx0 = xf - 1.55
        it.box('mat_plastic', (sx0, fl + 0.05, -0.35), (sx0 + 0.45, fl + 0.45, 0.10), bevel=0.03)
        it.box('mat_plastic', (sx0 - 0.09, fl + 0.45, -0.33), (sx0 - 0.03, fl + 1.10, 0.08), bevel=0.03)
        # back panels under the windscreen / side panels
        # front interior wall (grid with the window holes)
        zs_ = sorted(set([-ai, ai] + [h[0] for h in holes] + [h[1] for h in holes]))
        ys_ = sorted(set([fl, c['i_cant']] + [h[2] for h in holes] + [h[3] for h in holes]))
        xw = xf - 0.06
        for i in range(len(zs_) - 1):
            for j in range(len(ys_) - 1):
                za, zb, ya, yb = zs_[i], zs_[i + 1], ys_[j], ys_[j + 1]
                cz = (za + zb) / 2; cy = (ya + yb) / 2
                if any(h[0] < cz < h[1] and h[2] < cy < h[3] for h in holes):
                    continue
                it.face('mat_wall', [(xw, ya, za), (xw, ya, zb), (xw, yb, zb), (xw, yb, za)], hint=(-1, 0, 0))
        # cab ceiling cap above cant on the front wall
        inner = prof_full(ai, c['i_cant'], c['i_top'] - c['i_cant'], c['roof_n'])
        it.face('mat_wall', [(xw, c['i_cant'], ai)] + [(xw, y, z) for (z, y) in inner[1:-1]] + [(xw, c['i_cant'], -ai)], hint=(-1, 0, 0))
        # partition door (closed) in the middle-left (driver side offset)
        pz = 0.0
        # partition door on passenger side face
        it.box('mat_frame', (xp - 0.03, fl, -0.45), (xp, fl + c['door_top'] - fl - 0.15, 0.45), skip=('+x',))
        it.box('mat_door_inner', (xp - 0.045, fl + 0.02, -0.39), (xp - 0.03, fl + c['door_top'] - fl - 0.17, 0.39))
        self.gl.face('mat_glass', [(xp - 0.047, fl + 1.02, -0.22), (xp - 0.047, fl + 1.02, 0.22), (xp - 0.047, fl + 1.60, 0.22), (xp - 0.047, fl + 1.60, -0.22)], hint=(-1, 0, 0))
        self.markers.append(dict(name='cab_seat', pos=(sx0 + 0.22, fl + 0.45, -0.12), yaw=-90, kind='cab_seat'))
        self.markers.append(dict(name='cab_eye', pos=(sx0 + 0.15, fl + 1.20, -0.12), yaw=-90, kind='cab_eye'))

    # ============================================================ underframe: bogies, equipment, couplers
    def build_underframe(self):
        c = self.c; a = self.a
        u = self.und
        # underside plate
        u.box('mat_underframe', (self.x0 + 0.05, c['ybot'] - 0.06, -a + 0.06), (self.x1 - 0.05, c['ybot'] + 0.0, a - 0.06))
        # equipment boxes between bogies
        eq = [(-2.9, 1.6, 0.75), (0.0, 1.3, 0.85), (2.9, 1.6, 0.75)] if c['kind'] == 'deep' else [(-3.4, 2.0, 0.8), (0.0, 1.4, 0.9), (3.4, 2.0, 0.8)]
        for (ex, el, ew) in eq:
            u.box('mat_underframe', (ex - el / 2, c['ybot'] - 0.34, -ew), (ex + el / 2, c['ybot'] - 0.06, ew), bevel=0.02)
            for k in range(3):
                u.box('mat_wheel', (ex - el / 2 + 0.1 + k * (el - 0.3) / 2, c['ybot'] - 0.34, -ew - 0.006), (ex - el / 2 + 0.16 + k * (el - 0.3) / 2, c['ybot'] - 0.10, ew + 0.006), skip=('-y',))
        # pipes
        u.cyl('mat_wheel', (self.x0 + 0.3, c['ybot'] - 0.12, 0.95), (self.x1 - 0.3, c['ybot'] - 0.12, 0.95), 0.03, 8)
        u.cyl('mat_wheel', (self.x0 + 0.3, c['ybot'] - 0.15, -0.95), (self.x1 - 0.3, c['ybot'] - 0.15, -0.95), 0.025, 8)
        # bogies
        for bx in (-c['bogie'], c['bogie']):
            self.bogie(u, bx)
        # couplers at both ends
        for sx in (-1, 1):
            xe = sx * (self.x1)
            if self.cab and sx > 0:
                # cab end: a shorter coupler/ headstock
                pass
            u.box('mat_underframe', (min(xe, xe + sx * 0.06), 0.42, -0.42), (max(xe, xe + sx * 0.06), 0.80, 0.42), bevel=0.01)
            u.cyl('mat_wheel', (xe, 0.60, 0.0), (xe + sx * c['coupler'], 0.60, 0.0), 0.055, 10)
            u.box('mat_wheel', (min(xe + sx * c['coupler'], xe + sx * (c['coupler'] + 0.10)), 0.52, -0.11), (max(xe + sx * c['coupler'], xe + sx * (c['coupler'] + 0.10)), 0.68, 0.11), bevel=0.02)

    def bogie(self, u, bx):
        c = self.c
        wr = c['wheel_r']; wb = c['wheelbase'] / 2
        zw = 0.72
        for dx in (-wb, wb):
            # axle + wheels
            u.cyl('mat_wheel', (bx + dx, wr, -zw - 0.05), (bx + dx, wr, zw + 0.05), 0.055, 10, caps=False)
            for s in (1, -1):
                zc = s * zw
                u.cyl('mat_wheel', (bx + dx, wr, zc - 0.065), (bx + dx, wr, zc + 0.065), wr, 28, caps=True)
                # flange (inner side)
                zf = zc - s * 0.065
                u.cyl('mat_wheel', (bx + dx, wr, zf), (bx + dx, wr, zf - s * 0.028), wr + 0.03, 28, caps=True)
                # hub cap
                u.cyl('mat_underframe', (bx + dx, wr, zc + s * 0.06), (bx + dx, wr, zc + s * 0.10), 0.09, 12, caps=True)
                # brake disc / drum
                u.cyl('mat_underframe', (bx + dx, wr, zc - s * 0.075), (bx + dx, wr, zc - s * 0.16), 0.22, 16, caps=True)
            # traction motor / gearbox on one axle
        u.cyl('mat_underframe', (bx - wb, wr + 0.03, -0.45), (bx - wb, wr + 0.03, 0.45), 0.17, 14, caps=True)
        u.cyl('mat_underframe', (bx + wb, wr + 0.03, -0.45), (bx + wb, wr + 0.03, 0.45), 0.17, 14, caps=True)
        # frame: side beams, cross beam, springs
        for s in (1, -1):
            u.box('mat_underframe', (bx - wb - 0.35, 0.56, s * 0.62 - 0.07), (bx + wb + 0.35, 0.70, s * 0.62 + 0.07), bevel=0.02)
            for dx in (-wb, wb):
                u.cyl('mat_wheel', (bx + dx, wr + 0.30, s * 0.62), (bx + dx, 0.58, s * 0.62), 0.06, 10, caps=True)
        u.box('mat_underframe', (bx - 0.14, 0.55, -0.68), (bx + 0.14, 0.72, 0.68), bevel=0.02)

    # ============================================================ collision meshes (Godot -colonly)
    def build_collision(self):
        c = self.c; a = self.a; ai = self.ai; fl = self.fl
        col = {}
        def cm(name):
            mb = new_mb(name); col[name] = mb; return mb
        xe = self.xi1
        floor_x1 = self.x1 - 0.05 if self.cab else self.xi1
        f = cm('Floor')
        fx0 = self.xi0 - (0.42 if c['gang'] else 0.0)
        fx1 = floor_x1 + (0.42 if (c['gang'] and not self.cab) else 0.0)
        f.box('mat_plastic', (fx0, fl - 0.25, -ai - 0.02), (fx1, fl, ai + 0.02))
        # doorway sills extend the floor to the outside edge of the body
        for xd in self.doors:
            f.box('mat_plastic', (xd - c['door_w'] / 2, fl - 0.25, -a - 0.05), (xd + c['door_w'] / 2, fl, a + 0.05))
        for s, nm in ((1, 'WallR'), (-1, 'WallL')):
            w = cm(nm)
            edges = [self.xi0 - 0.02]
            bounds = []
            x_prev = self.xi0 - 0.02
            xend = (self.x1 - 0.02) if self.cab else self.xi1 + 0.02
            for xd in self.doors:
                bounds.append((x_prev, xd - c['door_w'] / 2)); x_prev = xd + c['door_w'] / 2
            if self.cab:
                bounds.append((x_prev, self.cdoor[0])); bounds.append((self.cdoor[1], xend))
            else:
                bounds.append((x_prev, xend))
            for (p, q) in bounds:
                if q - p > 0.01:
                    w.box('mat_plastic', (p, fl - 0.1, min(s * (ai - 0.03), s * (a + 0.02))), (q, c['cant'], max(s * (ai - 0.03), s * (a + 0.02))))
            # lintel above door openings
            dl = list(self.doors)
            for xd in dl:
                w.box('mat_plastic', (xd - c['door_w'] / 2 - 0.02, c['door_top'], min(s * (ai - 0.03), s * (a + 0.02))), (xd + c['door_w'] / 2 + 0.02, c['cant'], max(s * (ai - 0.03), s * (a + 0.02))))
            if self.cab:
                w.box('mat_plastic', (self.cdoor[0], c['door_top'], min(s * (ai - 0.03), s * (a + 0.02))), (self.cdoor[1], c['cant'], max(s * (ai - 0.03), s * (a + 0.02))))
            # door blockers as separate objects
            for di, xd in enumerate(self.doors):
                b = cm('DoorBlock_%s%d' % ('R' if s > 0 else 'L', di))
                b.box('mat_plastic', (xd - c['door_w'] / 2, fl, min(s * (ai + 0.02), s * (a - 0.03))), (xd + c['door_w'] / 2, c['door_top'], max(s * (ai + 0.02), s * (a - 0.03))))
            if self.cab:
                b = cm('DoorBlock_cab%s' % ('R' if s > 0 else 'L'))
                b.box('mat_plastic', (self.cdoor[0], fl, min(s * (ai + 0.02), s * (a - 0.03))), (self.cdoor[1], c['door_top'], max(s * (ai + 0.02), s * (a - 0.03))))
        r = cm('Roof')
        r.box('mat_plastic', (self.x0, c['i_top'], -a), (self.x1, c['top'] + 0.1, a))
        # roof collision only above the ceiling line (flat top approx.); keep interior clear
        # end walls
        if c['gang']:
            gw = 0.80
            for (sx, xi, nm) in ((-1, self.xi0, 'EndWallB'), (1, self.xi1, 'EndWallF')):
                if sx > 0 and self.cab:
                    continue
                e = cm(nm)
                for s in (1, -1):
                    e.box('mat_plastic', (min(xi, xi + sx * 0.15), fl, min(s * gw, s * ai)), (max(xi, xi + sx * 0.15), c['i_cant'], max(s * gw, s * ai)))
                e.box('mat_plastic', (min(xi, xi + sx * 0.15), fl + 2.14, -gw), (max(xi, xi + sx * 0.15), c['i_cant'], gw))
                # bellows side walls to walk through
                for s in (1, -1):
                    e.box('mat_plastic', (min(xi, xi + sx * 0.55), fl - 0.1, min(s * (gw + 0.02), s * (gw + 0.10))), (max(xi, xi + sx * 0.55), fl + 2.2, max(s * (gw + 0.02), s * (gw + 0.10))))
        else:
            for (sx, xi, nm) in ((-1, self.xi0, 'EndWallB'), (1, self.xi1, 'EndWallF')):
                if sx > 0 and self.cab:
                    continue
                e = cm(nm)
                e.box('mat_plastic', (min(xi, xi + sx * 0.15), fl, -ai), (max(xi, xi + sx * 0.15), c['i_cant'], ai))
        if self.cab:
            e = cm('EndWallF')
            e.box('mat_plastic', (self.x_part - 0.02, fl, -ai), (self.x_part + 0.12, c['i_cant'], ai))         # partition
            d = cm('CabDesk')
            xf = self.x1
            d.box('mat_plastic', (xf - 0.95, fl, -ai), (xf, fl + 0.95, ai))
            d.box('mat_plastic', (xf - 1.65, fl, -0.38), (xf - 1.05, fl + 0.5, 0.14))
        # seats
        for s, nm in ((1, 'SeatsR'), (-1, 'SeatsL')):
            sc = cm(nm)
            for (sa, sb, sgn) in self.seat_colliders[s]:
                z0 = s * ai; z1 = s * (ai - c['seat_d'] - 0.02)
                sc.box('mat_plastic', (sa, fl, min(z0, z1)), (sb, fl + c['seat_h'] + 0.02, max(z0, z1)))
                z2 = s * (ai - 0.16)
                sc.box('mat_plastic', (sa, fl, min(z0, z2)), (sb, fl + 0.95, max(z0, z2)))
            for (bx0, bx1, bz0, bz1, btop, br0, br1) in self.seat_boxes[s]:
                sc.box('mat_plastic', (bx0, fl, bz0), (bx1, btop, bz1))                        # cushion and pedestal
                sc.box('mat_plastic', (br0, fl, bz0), (br1, fl + 0.98, bz1))                  # the high back
        for i, (px, pz) in enumerate(self.poles):
            p = cm('Pole_%02d' % i)
            p.cyl('mat_plastic', (px, fl, pz), (px, self.ceil_y(pz), pz), 0.035, 8, caps=True)
        self.col = col

    # ============================================================ markers
    def build_markers(self):
        c = self.c; fl = self.fl; ai = self.ai
        M = self.markers
        # seats
        for s in (1, -1):
            name = 'R' if s > 0 else 'L'
            for i, p in enumerate(sorted(self.seat_pos[s], key=lambda q: q[0])):
                M.append(dict(name='seat_%s_%02d' % (name, i), pos=p[:3], yaw=p[3] if len(p) > 3 else (0 if s > 0 else 180), kind='seat', side=name))
        # standing spots: aisle grid, staggered
        xa, xb = self.xi0 + 0.7, self.xi1 - 0.7
        k = 0
        x = xa
        row = 0
        while x <= xb:
            zs = (-0.32, 0.32) if row % 2 == 0 else (0.0,)
            for z in zs:
                if abs(z) > 0.2 and any(ba - 0.1 <= x <= bb + 0.1 for (ba, bb) in self.trans_bays):
                    continue                     # (the aisle between the transverse seats is narrow: one line of standing spots down its middle)
                near_door = min(abs(x - xd) for xd in self.doors) < 0.85
                M.append(dict(name='stand_%02d' % k, pos=(x, fl, z), yaw=(90 if (k % 3) else 0) * (1 if k % 2 else -1), kind='stand_door' if near_door else 'stand'))
                k += 1
            x += 0.95
            row += 1
        # near poles
        for (px, pz) in self.poles[::2]:
            if any(ba - 0.1 <= px + 0.30 <= bb + 0.1 for (ba, bb) in self.trans_bays):
                continue
            zz = pz * 0.55
            M.append(dict(name='stand_%02d' % k, pos=(px + 0.30, fl, zz), yaw=180 if pz > 0 else 0, kind='stand_pole'))
            k += 1
        # holds
        h = 0
        for (px, pz) in self.poles:
            M.append(dict(name='hold_%02d' % h, pos=(px, fl + 1.25, pz), yaw=0, kind='pole'))
            h += 1
        for (rx0, rx1, rz, ry) in self.rails:
            n = int((rx1 - rx0) / 1.1)
            for i in range(n + 1):
                x = rx0 + (rx1 - rx0) * i / n
                M.append(dict(name='hold_%02d' % h, pos=(x, ry, rz), yaw=0, kind='rail'))
                h += 1
        # doorways (floor position just inside each door) + light + cameras
        for s in (1, -1):
            nm = 'R' if s > 0 else 'L'
            for di, xd in enumerate(self.doors):
                M.append(dict(name='doorway_%s%d' % (nm, di), pos=(xd, fl, s * (ai - 0.40)), yaw=0 if s > 0 else 180, kind='doorway'))
        lx = self.light_x[::2] if len(self.light_x) > 8 else self.light_x
        for i, x in enumerate(lx):
            M.append(dict(name='light_%02d' % i, pos=(x, c['i_top'] - 0.16, 0.0), yaw=0, kind='light'))
        # camera markers
        mids = [p for p in sorted(self.seat_pos[1], key=lambda q: q[0])]
        sp = mids[len(mids) // 2]
        M.append(dict(name='cam_seat', pos=(sp[0], fl + 1.20, sp[2] - 0.05), yaw=0, kind='camera'))
        M.append(dict(name='cam_stand', pos=(0.5, fl + 1.65, 0.0), yaw=0, kind='camera'))


# ============================================================================================ scene assembly
def clear_scene():
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.node_groups):
        for x in list(coll):
            coll.remove(x)
    _imgcache.clear()


def link(ob):
    bpy.context.scene.collection.objects.link(ob)


def make_empty(name, pos, yaw_deg, extras=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = 'ARROWS'
    e.empty_display_size = 0.15
    e.location = (pos[0], -pos[2], pos[1])
    e.rotation_euler = (0, 0, math.radians(yaw_deg))
    if extras:
        for k, v in extras.items():
            e[k] = v
    link(e)
    return e


def build_variant(key, want_tris=False):
    cfg = VARIANTS[key]
    random.seed(7)
    clear_scene()
    M = build_materials(cfg['kind'], cfg)
    car = Car(cfg, M)
    car.build()
    stats = {}
    # meshes
    for mb in (car.ext, car.int, car.gl, car.und):
        ob = to_blender(mb, bpy, M, mb.name)
        link(ob)
        stats[mb.name] = mb.stats()
    for name, mb in car.col.items():
        ob = to_blender(mb, bpy, M, name + '-colonly')
        link(ob)
    for (name, mb, loc, ex) in car.leaves:
        ob = to_blender(mb, bpy, M, name)
        ob.location = (loc[0], -loc[2], loc[1])
        for k, v in ex.items():
            ob[k] = v
        link(ob)
        stats[name] = mb.stats()
    for m in car.markers:
        make_empty(m['name'], m['pos'], m['yaw'], dict(kind=m['kind']))
    # export
    path = os.path.join(OUTDIR, cfg['name'] + '.glb')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_yup=True, export_apply=False, export_extras=True,
                              export_image_format='AUTO', export_materials='EXPORT', export_texcoords=True,
                              export_normals=True, export_cameras=False, export_lights=False, export_animations=False,
                              export_skins=False, export_vertex_color='ACTIVE', use_selection=False)
    tot = sum(v for k, v in stats.items())
    print('BUILT %s tris=%d  %s' % (cfg['name'], tot, {k: v for k, v in stats.items() if not k.startswith('door_')}))
    # side-car
    dims = dict(length=cfg['L'], width=cfg['W'] if 'W' in cfg else 2 * cfg['a'], height=cfg['top'], floor_height=cfg['floor'],
                interior_width=2 * car.ai, ceiling_height=cfg['i_top'], door_clear_width=cfg['door_w'],
                door_open_offset=OPEN_OFFSET, car_pitch=cfg['L'] + (0.5 if cfg['kind'] == 'ss' else 0.64),
                cab='+x' if cfg['cab'] else None, kind=cfg['kind'])
    marks = {}
    for m in car.markers:
        marks[m['name']] = dict(pos=[round(v, 4) for v in m['pos']], yaw_deg=m['yaw'], kind=m['kind'])
    used = set()
    for mb in [car.ext, car.int, car.gl, car.und] + [l[1] for l in car.leaves]:
        used.update(f[0] for f in mb.F)
    js = dict(name=cfg['name'], dims=dims, doors=car.doorlist, markers=marks,
              collision=[n + '-colonly' for n in car.col.keys()], materials=sorted(used),
              tris=stats)
    with open(os.path.join(OUTDIR, cfg['name'] + '.markers.json'), 'w') as f:
        json.dump(js, f, indent=1)
    return car


def main():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    keys = [a for a in args if a in VARIANTS] or list(VARIANTS.keys())
    for k in keys:
        build_variant(k)


if __name__ == '__main__':
    main()
