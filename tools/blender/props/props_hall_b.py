"""Ticket-hall information + clutter props ("hall_b"), modelled from the reference photos in build/refs_dress/halls (see SPEC.md sec 6/7):
poster_stand, newspaper_stand, help_point (wall, REDONE), help_point_pole, info_roundel (+ _hung), clock (REDONE), defibrillator_cabinet,
cctv_box, cid_totem, cid_wall_screen, departure_board_dm, tube_map_frame, local_map_frame, leaflet_rack, planter.

Textures: proptex_hall_b.py -> assets/textures/props/decals/hall_b_*_c.png (all invented / generic).
Conventions: metres, Y up, FRONT = -Z. Floor-standing props: origin at floor centre. Wall props: origin on the wall surface (z = 0) at the
centre of the unit, the unit protrudes towards -Z.
"""
import math, random
import propcore
from propcore import prop as _prop, REGISTRY, ORDER
from propmesh import Xf


# ----------------------------------------------------------------------------------------------------------------- infrastructure
def _lin(r, g, b):
    f = lambda v: ((v / 255.0 + 0.055) / 1.055) ** 2.4 if v / 255.0 > 0.04045 else v / 255.0 / 12.92
    return (f(r), f(g), f(b), 1.0)


HB = {      # flat-colour materials (sRGB inputs)
    'mat_hb_alu': dict(color=_lin(190, 193, 197), rough=0.36, metal=0.55),
    'mat_hb_lgrey': dict(color=_lin(150, 154, 158), rough=0.6),
    'mat_hb_white': dict(color=_lin(236, 238, 236), rough=0.42),
    'mat_hb_paper': dict(color=_lin(240, 240, 235), rough=0.85),
    'mat_hb_newsblue': dict(color=_lin(30, 128, 206), rough=0.42),
    'mat_hb_cid': dict(color=_lin(206, 209, 212), rough=0.34, metal=0.35),
    'mat_hb_soil': dict(color=_lin(48, 34, 24), rough=0.95),
    'mat_hb_leaf_a': dict(color=_lin(46, 108, 50), rough=0.7),
    'mat_hb_leaf_b': dict(color=_lin(84, 148, 62), rough=0.7),
    'mat_hb_flower_r': dict(color=_lin(206, 30, 44), rough=0.6),
    'mat_hb_flower_w': dict(color=_lin(238, 236, 226), rough=0.6),
    'mat_hb_btn_red': dict(color=_lin(196, 14, 20), rough=0.3, spec=0.7),
    'mat_hb_btn_green': dict(color=_lin(10, 92, 46), rough=0.3, emit=(0.05, 0.6, 0.22), emit_strength=0.8),
    'mat_hb_btn_dark': dict(color=_lin(20, 22, 30), rough=0.3, spec=0.7),
    'mat_hb_led_green': dict(color=_lin(60, 230, 110), rough=0.3, emit=(0.15, 1.0, 0.35), emit_strength=3.0),
    'mat_hb_defib': dict(color=_lin(246, 196, 20), rough=0.4),
    'mat_hb_glass': dict(color=(0.88, 0.94, 0.96, 1.0), rough=0.03, alpha=0.05, double=True, spec=0.6),
    'mat_hb_leaf1': dict(color=_lin(214, 64, 52), rough=0.8),
    'mat_hb_leaf2': dict(color=_lin(40, 128, 196), rough=0.8),
    'mat_hb_leaf3': dict(color=_lin(240, 200, 40), rough=0.8),
    'mat_hb_lens': dict(color=(0.02, 0.05, 0.08, 1.0), rough=0.03, spec=1.0),
}
# get the shared floor-dirt gradient (vertex colours + grime cuts) for the floor-standing materials
DIRTY_HB = {'mat_hb_alu', 'mat_hb_lgrey', 'mat_hb_white', 'mat_hb_paper', 'mat_hb_newsblue', 'mat_hb_cid', 'mat_hb_soil'}
propcore.DIRTY.update(DIRTY_HB)


def _mats(P, *names):
    for n in names:
        P.mat(n, **HB[n])


def _tex(P, name, tex, emit=None, rough=0.4, **kw):
    spec = dict(c='decals/hall_b_%s_c.png' % tex, rough=rough)
    if emit:
        spec.update(emit=(1, 1, 1), emit_tex=True, emit_strength=emit, spec=0.7)
    spec.update(kw)
    P.mat(name, **spec)


def hprop(name, **info):
    """like @prop but replaces an older definition of the same name (help_point, clock) instead of duplicating it"""
    def deco(fn):
        if name in REGISTRY:
            try:
                ORDER.remove(name)
            except ValueError:
                pass
        def wrapped(P):
            for n, spec in HB.items():          # all flat materials are registered; only the ones a prop actually uses get built
                P.mat(n, **spec)
            fn(P)
        wrapped.__name__ = fn.__name__
        return _prop(name, **info)(wrapped)
    return deco


# hands (and anything else) can carry a rest rotation about the prop's own +Z axis: `mb.rest_rot_z_deg = a` sets the node rotation.
# Positive = clockwise seen from the front (-Z) = Godot rotation.z = +a.
_orig_to_blender = propcore.to_blender


def _to_blender(mb, bpy, mats, name, pivot=(0.0, 0.0, 0.0), mesh_name=None, dirty=()):
    ob = _orig_to_blender(mb, bpy, mats, name, pivot=pivot, mesh_name=mesh_name, dirty=dirty)
    rz = getattr(mb, 'rest_rot_z_deg', None)
    if rz:
        ob.rotation_euler = (0.0, math.radians(-rz), 0.0)
    return ob


propcore.to_blender = _to_blender


def lathe_z(mb, mat, prof, cx=0.0, cy=0.0, z=0.0, seg=32, **kw):
    """revolve profile [(r, d), ...] about a horizontal axis through (cx, cy, z); d grows towards -Z (the front)."""
    with mb.tf(Xf.T(cx, cy, z) * Xf.R('x', -90)):
        mb.lathe(mat, prof, seg=seg, **kw)


def frustum(mb, mat, y0, y1, w0, d0, w1, d1, zc0=0.0, zc1=0.0):
    """box whose footprint changes from w0 x d0 (at y0) to w1 x d1 (at y1); hard-shaded faces"""
    def ring(y, w, d, zc):
        return [(-w / 2, y, zc - d / 2), (w / 2, y, zc - d / 2), (w / 2, y, zc + d / 2), (-w / 2, y, zc + d / 2)]
    b = ring(y0, w0, d0, zc0); t = ring(y1, w1, d1, zc1)
    for i in range(4):
        j = (i + 1) % 4
        cen = tuple(sum(p[k] for p in (b[i], b[j], t[i], t[j])) / 4 for k in range(3))
        mb.face(mat, [b[i], b[j], t[j], t[i]], hint=(cen[0], 0.0, cen[2] - (zc0 + zc1) / 2), sg=mb.new_sg())
    mb.face(mat, t, hint=(0, 1, 0), sg=mb.new_sg())
    mb.face(mat, b, hint=(0, -1, 0), sg=mb.new_sg())


# ================================================================================================================ 1. poster stand
@hprop('poster_stand',
       desc='Free-standing grey aluminium information / poster stand: two round uprights, poster panel with thin rails, light-grey moulded wedge base '
            'on a black rubber skirt. Fictional planned-closures poster on its own node.',
       origin='floor_centre', front='poster faces -Z (the back is plain white paper)',
       nodes={'body': 'uprights, rails, base', 'poster': 'poster quad (own node, pivot at its centre) with mat_poster',
              'col_body-convcolonly': 'collision box'},
       slots={'mat_poster': 'the picture: portrait 2:3 (1024x1536), UV 0..1, upright when viewed from -Z. Unlit (no emission). Reuse posters/poster_00..07.'},
       anim={}, mount_height=0.0,
       notes=['Overall 0.86 x 0.50 x 1.88 m. Poster face 0.66 x 0.99 m (exactly 2:3) centred 1.30 m above the floor. Real stands come in clusters of 3-5 '
              'near entrances; yaw them a few degrees each for a natural look.'])
def poster_stand(P):
    _mats(P, 'mat_hb_alu', 'mat_hb_lgrey', 'mat_hb_paper')
    _tex(P, 'mat_poster', 'poster_info', rough=0.42, spec=0.4)
    mb = P.mb('body')
    # black rubber skirt + light-grey wedge
    mb.box('mat_rubber', (-0.43, 0.0, -0.25), (0.43, 0.10, 0.25), bevel=0.045, seg=2)
    frustum(mb, 'mat_hb_lgrey', 0.095, 0.36, 0.78, 0.40, 0.72, 0.22)
    mb.box('mat_hb_lgrey', (-0.36, 0.355, -0.115), (0.36, 0.366, 0.115), bevel=0.004)
    # uprights: round aluminium tubes with collars and caps
    for sx in (-1, 1):
        x = sx * 0.345
        mb.cyl('mat_hb_alu', (x, 0.36, 0.0), (x, 1.87, 0.0), 0.016, seg=12)
        mb.cyl('mat_hb_alu', (x, 0.36, 0.0), (x, 0.43, 0.0), 0.024, seg=12)
        mb.sphere('mat_hb_alu', (x, 1.87, 0.0), 0.017, seg=10, rings=4)
    # poster panel: white backing (also the back face), aluminium rails top and bottom
    mb.box('mat_hb_paper', (-0.33, 0.805, -0.008), (0.33, 1.795, 0.0))
    mb.box('mat_hb_alu', (-0.362, 0.782, -0.014), (0.362, 0.806, 0.010), bevel=0.004)
    mb.box('mat_hb_alu', (-0.362, 1.794, -0.014), (0.362, 1.818, 0.010), bevel=0.004)
    for sx in (-1, 1):
        mb.box('mat_hb_alu', (sx * 0.334 - 0.004 + 0.0, 0.806, -0.011), (sx * 0.334 + 0.004, 1.794, 0.004))
    pm = P.mb('poster', pivot=(0.0, 1.30, -0.0105), dirt=False)
    pm.fdecal('mat_poster', 0.0, 0.805, 0.66, 0.99, -0.0105)
    P.col_box('col_body-convcolonly', (-0.43, 0.0, -0.25), (0.43, 1.88, 0.25))


# ================================================================================================================ 2. newspaper stand
@hprop('newspaper_stand',
       desc='Free-newspaper dispenser / recycling stand: sky-blue steel box with a white brand panel (fictional "Daily Commuter"), '
            'printed side panels and an open pocket holding a stack of papers.',
       origin='floor_centre', front='brand panel and pocket face -Z',
       nodes={'body': 'whole stand', 'col_body-convcolonly': 'collision box'},
       slots={'mat_news_front': 'front panel print 512x656 (0.49 x 0.63 m)', 'mat_news_side': 'side print 256x568 (both sides)',
              'mat_news_paper': 'front page of the stacked papers 256x192'},
       anim={}, mount_height=0.0, notes=['0.50 x 0.32 x 1.00 m.'])
def newspaper_stand(P):
    _mats(P, 'mat_hb_newsblue', 'mat_hb_paper')
    _tex(P, 'mat_news_front', 'news_front', rough=0.4)
    _tex(P, 'mat_news_side', 'news_side', rough=0.4)
    _tex(P, 'mat_news_paper', 'news_paper', rough=0.8)
    mb = P.mb('body')
    W, D, H = 0.50, 0.32, 1.00
    hx, hz = W / 2, D / 2
    B = 'mat_hb_newsblue'
    mb.box('mat_charcoal', (-hx - 0.005, 0.0, -hz - 0.005), (hx + 0.005, 0.035, hz + 0.005), bevel=0.006)
    mb.box(B, (-hx, 0.035, hz - 0.012), (hx, H, hz), bevel=0.004)                        # back
    for sx in (-1, 1):
        mb.box(B, (min(sx * hx, sx * (hx - 0.012)), 0.035, -hz), (max(sx * hx, sx * (hx - 0.012)), H, hz), bevel=0.004)     # sides
    mb.box(B, (-hx, H - 0.012, -hz), (hx, H, hz), bevel=0.004)                            # top
    mb.box(B, (-hx, 0.335, -hz), (hx, H - 0.012, -hz + 0.012), bevel=0.004)               # printed upper front panel
    mb.box(B, (-hx, 0.035, -hz), (hx, 0.085, -hz + 0.014), bevel=0.004)                   # sill under the pocket
    for sx in (-1, 1):
        mb.box(B, (min(sx * hx, sx * (hx - 0.05)), 0.085, -hz), (max(sx * hx, sx * (hx - 0.05)), 0.335, -hz + 0.014), bevel=0.003)
    # pocket interior + newspaper stack
    mb.box('mat_black_plastic', (-hx + 0.012, 0.085, hz - 0.03), (hx - 0.012, 0.335, hz - 0.012))       # pocket back
    mb.box(B, (-hx + 0.012, 0.335, -hz + 0.012), (hx - 0.012, 0.347, hz - 0.012))                          # pocket ceiling
    mb.box('mat_black_plastic', (-hx + 0.012, 0.075, -hz + 0.012), (hx - 0.012, 0.085, hz - 0.012))       # pocket floor
    mb.box('mat_hb_paper', (-0.16, 0.085, -hz + 0.055), (0.16, 0.33, hz - 0.05))
    mb.fdecal('mat_news_paper', 0.0, 0.088, 0.32, 0.24, -hz + 0.0545)
    # printed panels
    mb.fdecal('mat_news_front', 0.0, 0.352, 0.49, 0.49 * 656 / 512, -hz - 0.0015)
    sw = 0.28; sh = sw * 568 / 256
    mb.qdecal('mat_news_side', (hx + 0.0015, 0.36, sw / 2), (0, 0, -1), (0, 1, 0), sw, sh, hint=(1, 0, 0))
    mb.qdecal('mat_news_side', (-hx - 0.0015, 0.36, -sw / 2), (0, 0, 1), (0, 1, 0), sw, sh, hint=(-1, 0, 0))
    # small details: lock + top lip
    mb.box('mat_hb_alu', (-hx + 0.02, H - 0.004, -hz + 0.02), (hx - 0.02, H + 0.003, hz - 0.02), bevel=0.002)
    P.col_box('col_body-convcolonly', (-hx, 0, -hz), (hx, H, hz))


# ================================================================================================================ 3. help point
R_HP = 0.21


def _help_dish(P, mb, cx, cy, zb, depth=0.105):
    """round Help Point unit, axis along -Z from z=zb (rear) to zb-depth; dish + blue ring + printed face + buttons. Returns the printed face z."""
    R = R_HP
    lathe_z(mb, 'mat_hb_white', [(0.0, 0.0), (R - 0.01, 0.0), (R, 0.010), (R, depth - 0.030), (0.0, depth - 0.030)], cx, cy, zb, seg=32)
    lathe_z(mb, 'mat_blue', [(R, depth - 0.030), (R, depth - 0.010), (R - 0.010, depth), (R - 0.024, depth), (R - 0.024, depth - 0.012)], cx, cy, zb, seg=32)
    zf = zb - (depth - 0.012)
    mb.disc('mat_hp_face', R - 0.024, z=zf, seg=32, facing=-1, cx=cx, cy=cy)
    k = 2 * (R - 0.024) / 512.0            # metres per texture pixel; texture x grows towards +X? No: image-left = world +X

    def pos(tx, ty):
        return (cx + (256 - tx) * k, cy + (256 - ty) * k)
    x, y = pos(182, 214)          # fire-alarm button (red square)
    mb.box('mat_hb_btn_red', (x - 0.019, y - 0.019, zf - 0.010), (x + 0.019, y + 0.019, zf), bevel=0.003)
    for ty, m in ((292, 'mat_hb_btn_green'), (360, 'mat_hb_btn_dark')):
        x, y = pos(182, ty)
        with mb.tf(Xf.T(x, y, zf) * Xf.R('x', -90)):
            mb.lathe('mat_steel_polished', [(0.026, 0.0), (0.026, 0.004), (0.022, 0.004), (0.022, 0.0)], seg=20)
            mb.lathe(m, [(0.021, 0.0), (0.021, 0.006), (0.016, 0.011), (0.0, 0.012)], seg=20)
    return zf


def _help_mats(P):
    _tex(P, 'mat_hp_face', 'help_face', rough=0.38)
    P.mat('mat_help_lamp', color=(0.1, 0.9, 0.25, 1), emit=(0.1, 1.0, 0.25), emit_strength=4.0, rough=0.3)
    _mats(P, 'mat_hb_white', 'mat_hb_btn_red', 'mat_hb_btn_green', 'mat_hb_btn_dark')


@hprop('help_point',
       desc='Wall-mounted Help Point: round white dish (0.42 m) with a blue front ring, printed "Help Point" face, red fire-alarm button, '
            'green-ringed Emergency button, Information button, speaker grille and a status lamp.',
       origin='wall_surface_centre', origin_note='centre of the dish on the wall plane z=0; the unit protrudes 0.105 m towards -Z',
       front='face faces -Z',
       nodes={'body': 'dish, ring, face, buttons', 'lamp_status': 'small emissive status lamp (own material mat_help_lamp)'},
       slots={'mat_hp_face': 'printed face 512x512 (disc UV)', 'mat_help_lamp': 'emissive status lamp'},
       anim={}, mount_height=1.30,
       notes=['REDONE: was a floor pillar, now the wall dish seen at Bank/Lambeth North/Waterloo. 0.42 dia x 0.105 deep; mount its CENTRE 1.30 m above the floor. '
              'No collision (wall mounted). Use help_point_pole for a free-standing one at gatelines.'])
def help_point(P):
    _help_mats(P)
    mb = P.mb('body', dirt=False)
    zf = _help_dish(P, mb, 0.0, 0.0, 0.0)
    lm = P.mb('lamp_status', pivot=(0.0, 0.142, zf), dirt=False, extras={'kind': 'status_lamp'})
    lm.cyl('mat_help_lamp', (0.0, 0.142, zf), (0.0, 0.142, zf - 0.005), 0.0055, seg=10)


@hprop('help_point_pole',
       desc='Free-standing Help Point on a slim white pole with a square base plate: the round dish, buttons and a green hand-and-i sign on top (seen at gatelines, Boston Manor).',
       origin='floor_centre', front='dish faces -Z',
       nodes={'body': 'base, pole, dish, sign', 'lamp_status': 'status lamp', 'col_base-convcolonly': 'base + pole collision', 'col_head-convcolonly': 'dish + sign collision'},
       slots={'mat_hp_face': 'printed face', 'mat_hp_sign': 'green pictogram plate', 'mat_help_lamp': 'emissive status lamp'},
       anim={}, mount_height=0.0, notes=['0.42 x 0.28 x 1.75 m (dish centre 1.30 m; base plate 0.28 square). Pole is 0.07 square, base plate 0.28 square.'])
def help_point_pole(P):
    _help_mats(P)
    _tex(P, 'mat_hp_sign', 'help_sign', rough=0.4)
    mb = P.mb('body')
    mb.box('mat_hb_white', (-0.14, 0.0, -0.14), (0.14, 0.022, 0.14), bevel=0.006)
    mb.box('mat_hb_white', (-0.035, 0.022, -0.035), (0.035, 1.75, 0.035), bevel=0.006)
    zf = _help_dish(P, mb, 0.0, 1.30, -0.035)
    mb.box('mat_hb_white', (-0.085, 1.56, -0.046), (0.085, 1.74, -0.035), bevel=0.004)
    mb.fdecal('mat_hp_sign', 0.0, 1.57, 0.16, 0.16, -0.0465)
    lm = P.mb('lamp_status', pivot=(0.0, 1.442, zf), dirt=False, extras={'kind': 'status_lamp'})
    lm.cyl('mat_help_lamp', (0.0, 1.442, zf), (0.0, 1.442, zf - 0.005), 0.0055, seg=10)
    P.col_box('col_base-convcolonly', (-0.14, 0.0, -0.14), (0.14, 1.0, 0.14))
    P.col_box('col_head-convcolonly', (-0.21, 1.0, -0.15), (0.21, 1.75, 0.05))


# ================================================================================================================ 4. info roundel
def _roundel_body(P, mb, cy, two_sided=False):
    """lit disc sign: steel bezel + printed emissive face(s). Disc axis along Z, centre (0, cy). One-sided: rear plane at z=0, face towards -Z.
    Two-sided: 0.092 thick, centred on z=0."""
    if not two_sided:
        lathe_z(mb, 'mat_hb_white', [(0.0, 0.0), (0.224, 0.0), (0.228, 0.006), (0.228, 0.038), (0.221, 0.046), (0.214, 0.046), (0.214, 0.040), (0.0, 0.040)],
                0.0, cy, 0.0, seg=36)
        mb.disc('mat_roundel', 0.214, z=-0.0445, seg=36, facing=-1, cx=0.0, cy=cy)
    else:
        lathe_z(mb, 'mat_hb_white', [(0.214, 0.0), (0.224, 0.0), (0.228, 0.006), (0.228, 0.086), (0.224, 0.092), (0.214, 0.092)], 0.0, cy, 0.046, seg=36)
        mb.disc('mat_roundel', 0.214, z=-0.0445, seg=36, facing=-1, cx=0.0, cy=cy)
        mb.disc('mat_roundel', 0.214, z=0.0445, seg=36, facing=+1, cx=0.0, cy=cy)


@hprop('info_roundel',
       desc='Wall-mounted lit information roundel: white disc with a blue ring and a blue serif italic "i" (0.46 m).',
       origin='wall_surface_centre', origin_note='centre of the disc on the wall plane z=0; protrudes 0.046 m towards -Z', front='face faces -Z',
       nodes={'body': 'bezel + face'}, slots={'mat_roundel': 'emissive face 512x512 (disc UV); emission_energy_multiplier ~1.0'},
       anim={}, mount_height=2.4, notes=['0.456 dia x 0.046. Mount centre at 2.2-2.6 m above the information zone.'])
def info_roundel(P):
    _tex(P, 'mat_roundel', 'roundel_i', emit=1.0, rough=0.3)
    mb = P.mb('body', dirt=False)
    _roundel_body(P, mb, 0.0)


@hprop('info_roundel_hung',
       desc='Ceiling-hung double-sided lit information roundel on a short rod.',
       origin='ceiling_point', origin_note='point on the ceiling; the rod hangs 0.60 m, the disc centre is 0.83 m below the origin', front='both faces (-Z and +Z) show the "i"',
       nodes={'body': 'rod, bracket, disc'}, slots={'mat_roundel': 'emissive face (both sides)'},
       anim={}, mount_height=3.4, notes=['Disc 0.456 dia x 0.092 thick. Origin is the ceiling attachment.'])
def info_roundel_hung(P):
    _tex(P, 'mat_roundel', 'roundel_i', emit=1.0, rough=0.3)
    mb = P.mb('body', dirt=False)
    cy = -0.83
    mb.cyl('mat_steel_polished', (0.0, 0.0, 0.0), (0.0, -0.60, 0.0), 0.007, seg=8)
    mb.cyl('mat_steel', (0.0, 0.0, 0.0), (0.0, -0.012, 0.0), 0.04, seg=12)
    mb.box('mat_steel', (-0.02, cy + 0.228, -0.014), (0.02, -0.59, 0.014), bevel=0.003)
    _roundel_body(P, mb, cy, two_sided=True)


# ================================================================================================================ 5. clock
@hprop('clock',
       desc='Round station clock: black rim, white dial with black numerals and minute ticks, glass, small top bracket; separate hour / minute / second '
            'hands pivoting at the dial centre (posed at 10:09:42).',
       origin='wall_surface_centre', origin_note='dial centre on the wall plane z=0; the clock protrudes 0.107 m towards -Z', front='dial faces -Z',
       nodes={'body': 'case, dial, glass, bracket', 'hand_h': 'hour hand, pivot = dial centre (0,0,-0.076)', 'hand_m': 'minute hand, same pivot',
              'hand_s': 'thin red second hand, same pivot'},
       slots={'mat_clock_face': 'dial print 1024x1024 (disc UV)'},
       anim={'hand_h': {'axis': 'z', 'rotation_z_rad': 'TAU*((h%12)+m/60)/12'}, 'hand_m': {'axis': 'z', 'rotation_z_rad': 'TAU*(m+s/60)/60'},
             'hand_s': {'axis': 'z', 'rotation_z_rad': 'TAU*s/60'}},
       mount_height=2.7,
       notes=['REDONE. Meshes are modelled pointing at 12; each hand NODE carries a rest rotation.z (10:09:42) so the static clock shows a plausible time. '
              'To animate SET (not add) node.rotation.z = angle; positive = clockwise seen from the front (-Z). Case 0.50 dia, dial 0.436, 0.107 deep.'])
def clock(P):
    _tex(P, 'mat_clock_face', 'clock_face', rough=0.35)
    P.mat('mat_clock_glass', color=(0.9, 0.95, 1.0, 1), rough=0.02, alpha=0.06, spec=1.0)
    mb = P.mb('body', dirt=False)
    zb = -0.045
    lathe_z(mb, 'mat_black_plastic', [(0.0, 0.0), (0.244, 0.0), (0.25, 0.008), (0.25, 0.050), (0.236, 0.062), (0.218, 0.062), (0.218, 0.012), (0.0, 0.012)], 0.0, 0.0, zb, seg=32)
    mb.disc('mat_clock_face', 0.218, z=zb - 0.0165, seg=32, facing=-1)
    mb.disc('mat_clock_glass', 0.216, z=zb - 0.0585, seg=32, facing=-1)
    # wall plate + centre boss + top bracket
    mb.box('mat_steel', (-0.05, -0.05, -0.008), (0.05, 0.05, 0.0))
    mb.box('mat_steel', (-0.03, -0.03, zb), (0.03, 0.03, -0.008))
    mb.box('mat_steel', (-0.03, 0.235, -0.052), (0.03, 0.292, -0.0))
    mb.box('mat_steel', (-0.045, 0.28, -0.008), (0.045, 0.30, 0.0))
    zc = -0.076

    def hand(name, length, tail, wid, z, mat, rest, tip=0.0):
        hm = P.mb(name, pivot=(0.0, 0.0, zc), dirt=False)
        poly = [(-wid * 0.55, -tail), (wid * 0.55, -tail), (wid * 0.5, length * 0.72), (tip if tip else wid * 0.14, length), (-(tip if tip else wid * 0.14), length), (-wid * 0.5, length * 0.72)]
        hm.prism(mat, poly, 'z', z - 0.004, z, bevel=0.0)
        hm.rest_rot_z_deg = rest
        return hm
    hour_deg = 30.0 * (10 + 9.7 / 60)
    min_deg = 6.0 * 9.7
    sec_deg = 6.0 * 42
    hand('hand_h', 0.118, 0.03, 0.028, -0.0700, 'mat_black_plastic', hour_deg)
    hm = hand('hand_m', 0.196, 0.04, 0.019, -0.0770, 'mat_black_plastic', min_deg)
    hm.cyl('mat_black_plastic', (0, 0, -0.0770), (0, 0, -0.0800), 0.014, seg=12)
    hs = P.mb('hand_s', pivot=(0.0, 0.0, zc), dirt=False)
    hs.prism('mat_red', [(-0.0028, -0.05), (0.0028, -0.05), (0.0022, 0.205), (-0.0022, 0.205)], 'z', -0.0830, -0.0810)
    hs.cyl('mat_red', (0, 0, -0.0810), (0, 0, -0.0845), 0.008, seg=10)
    hs.cyl('mat_red', (0, -0.05, -0.0810), (0, -0.05, -0.0830), 0.008, seg=8)
    hs.rest_rot_z_deg = sec_deg


# ================================================================================================================ 6. defibrillator + cctv
@hprop('defibrillator_cabinet',
       desc='Wall-mounted public-access defibrillator cabinet: white body, window showing a yellow unit, status display, label and the green heart sign above.',
       origin='wall_surface_centre', origin_note='centre of the CABINET on the wall plane z=0; the green sign sits 0.235-0.41 m above the origin', front='door faces -Z',
       nodes={'body': 'cabinet, unit, sign'},
       slots={'mat_defib_sign': 'green heart sign 256x256', 'mat_defib_label': 'door label 256x96', 'mat_hb_led_green': 'emissive status LED strip'},
       anim={}, mount_height=1.25, notes=['Cabinet 0.32 x 0.42 x 0.16 m; sign 0.175 m square above it (overall 0.32 x 0.62). Put beside the gateline at hip-chest height.'])
def defibrillator_cabinet(P):
    _tex(P, 'mat_defib_sign', 'defib_sign', rough=0.4)
    _tex(P, 'mat_defib_label', 'defib_label', rough=0.4)
    mb = P.mb('body', dirt=False)
    W, H, D = 0.32, 0.42, 0.16
    mb.box('mat_hb_white', (-W / 2, -H / 2, -D), (W / 2, H / 2, 0.0), bevel=0.012, seg=1)
    # door + window recess (black panel, yellow unit in front of it, thin glass in front of that)
    mb.box('mat_hb_lgrey', (-0.135, -0.155, -D - 0.004), (0.135, 0.125, -D + 0.002), bevel=0.004)
    mb.box('mat_black_gloss', (-0.115, -0.09, -D - 0.005), (0.115, 0.115, -D - 0.003))
    mb.box('mat_hb_defib', (-0.075, -0.075, -D - 0.020), (0.075, 0.075, -D - 0.005), bevel=0.008)
    mb.box('mat_black_plastic', (-0.05, 0.0, -D - 0.0205), (0.05, 0.06, -D - 0.0195))
    mb.box('mat_hb_led_green', (-0.012, -0.055, -D - 0.0205), (0.012, -0.045, -D - 0.0195))
    mb.box('mat_hb_btn_red', (0.03, -0.06, -D - 0.0205), (0.06, -0.035, -D - 0.0195))
    mb.box('mat_hb_glass', (-0.115, -0.09, -D - 0.024), (0.115, 0.115, -D - 0.0235))
    mb.fdecal('mat_defib_label', 0.0, -0.152, 0.20, 0.20 * 96 / 256, -D - 0.0045)
    # status display strip on top
    mb.box('mat_black_gloss', (-0.09, 0.14, -D - 0.003), (0.09, 0.185, -D + 0.002))
    mb.box('mat_hb_led_green', (-0.07, 0.155, -D - 0.0035), (-0.04, 0.17, -D - 0.003))
    mb.box('mat_hb_alu', (0.145, -0.02, -D - 0.014), (0.152, 0.10, -D - 0.004), bevel=0.002)     # handle
    # sign plate above
    mb.box('mat_hb_white', (-0.09, 0.235, -0.014), (0.09, 0.41, 0.0))
    mb.fdecal('mat_defib_sign', 0.0, 0.2375, 0.175, 0.175, -0.0145)


@hprop('cctv_box',
       desc='Box CCTV camera on a wall bracket: light-grey housing with sun shield, dark lens window, roundel sticker, short arm with ball joint; pitched 15 degrees down.',
       origin='wall_surface_centre', origin_note='centre of the wall plate at z=0; camera extends towards -Z (front = the lens end)', front='lens faces -Z (and down)',
       nodes={'body': 'plate, arm, housing'}, slots={'mat_cctv_sticker': 'roundel sticker on the +X side (RGBA, alpha)'},
       anim={}, mount_height=2.7, notes=['0.10 x 0.18 x 0.43 m incl. arm. Yaw the whole prop about Y to aim it along the hall; ~2.5-3.0 m above the floor.'])
def cctv_box(P):
    _tex(P, 'mat_cctv_sticker', 'cctv_sticker', rough=0.4, alpha=1.0)
    _mats(P, 'mat_hb_alu', 'mat_hb_lgrey', 'mat_hb_lens')
    mb = P.mb('body', dirt=False)
    mb.box('mat_hb_lgrey', (-0.04, -0.04, -0.008), (0.04, 0.04, 0.0))
    mb.cyl('mat_hb_alu', (0.0, 0.0, -0.008), (0.0, 0.0, -0.105), 0.014, seg=10)
    mb.sphere('mat_hb_alu', (0.0, 0.0, -0.115), 0.024, seg=10, rings=5)
    with mb.tf(Xf.T(0.0, -0.030, -0.125) * Xf.R('x', -15)):
        # housing: local -Z is the lens end. body z from 0.0 (rear) .. -0.28
        mb.box('mat_hb_alu', (-0.042, -0.040, -0.28), (0.042, 0.040, 0.02), bevel=0.010, seg=1)
        mb.box('mat_hb_lgrey', (-0.050, 0.038, -0.30), (0.050, 0.046, 0.02), bevel=0.002)       # sun shield
        mb.box('mat_hb_lens', (-0.034, -0.030, -0.2815), (0.034, 0.030, -0.279))                 # front window
        mb.box('mat_black_plastic', (-0.012, -0.012, 0.02), (0.012, 0.012, 0.045))                # cable gland
        mb.qdecal('mat_cctv_sticker', (0.0432, -0.02, -0.07), (0, 0, -1), (0, 1, 0), 0.06, 0.06, hint=(1, 0, 0))


# ================================================================================================================ 7. CID totem / wall screen / departure board
def _cid_head(P, mb, y0, zf):
    """housing (0.76 x 1.45) whose bottom is at y0 and whose front plane is at zf; bezel + screen node + logo + blue trim. Screen 0.62 x 1.10."""
    D = 0.10
    mb.box('mat_hb_cid', (-0.38, y0, zf), (0.38, y0 + 1.45, zf + D), bevel=0.022, seg=2)
    mb.box('mat_blue', (-0.385, y0 + 0.02, zf - 0.002), (-0.352, y0 + 1.43, zf + D), bevel=0.004)          # blue trim on the viewer's right edge
    mb.box('mat_black_gloss', (-0.33, y0 + 0.28, zf - 0.010), (0.33, y0 + 1.42, zf + 0.004), bevel=0.005)  # bezel
    sm = P.mb('screen', pivot=(0.0, y0 + 0.85, zf - 0.0105), dirt=False)
    sm.fdecal('mat_cid_screen', 0.0, y0 + 0.30, 0.62, 1.10, zf - 0.0105)
    lm = P.mb('logo', pivot=(0.0, y0 + 0.15, zf - 0.002), dirt=False)
    lm.fdecal('mat_cid_logo', 0.0, y0 + 0.075, 0.15, 0.15, zf - 0.0025)
    mb.box('mat_black_gloss', (-0.02, y0 + 1.435, zf - 0.002), (0.02, y0 + 1.445, zf + 0.002))          # sensor slit


def _cid_mats(P):
    _tex(P, 'mat_cid_screen', 'cid_screen', emit=0.9, rough=0.15)
    _tex(P, 'mat_cid_logo', 'cid_logo', emit=1.0, rough=0.3, alpha=1.0)
    _mats(P, 'mat_hb_cid', 'mat_hb_white')


@hprop('cid_totem',
       desc='Customer-information display totem: white/silver housing with blue side trim and a lit roundel, portrait screen showing service-status bars '
            '(emissive), on a slim pole with a round foot.',
       origin='floor_centre', front='screen faces -Z',
       nodes={'body': 'foot, pole, housing, bezel', 'screen': 'emissive screen quad (own node)', 'logo': 'lit roundel (own node, RGBA)',
              'col_foot-convcolonly': 'foot + pole collision', 'col_head-convcolonly': 'housing collision'},
       slots={'mat_cid_screen': 'emissive portrait screen 640x1136, 0.62 x 1.10 m, UV 0..1 upright from -Z; retarget albedo AND emission', 'mat_cid_logo': 'lit roundel (RGBA)'},
       anim={}, mount_height=0.0, notes=['0.76 x 0.32 (foot) x 2.07 m. Housing 0.62-2.07 m, screen 0.92-2.02 m. Visible screen 0.62 x 1.10 (smaller than the 0.65x1.2 of the brief so the housing keeps a real bezel).'])
def cid_totem(P):
    _cid_mats(P)
    mb = P.mb('body')
    mb.lathe('mat_hb_white', [(0.0, 0.0), (0.16, 0.0), (0.16, 0.010), (0.10, 0.030), (0.034, 0.060), (0.034, 0.64), (0.0, 0.64)], seg=24)
    _cid_head(P, mb, 0.62, -0.05)
    P.col_box('col_foot-convcolonly', (-0.16, 0.0, -0.16), (0.16, 0.64, 0.16))
    P.col_box('col_head-convcolonly', (-0.38, 0.62, -0.06), (0.38, 2.07, 0.06))


@hprop('cid_wall_screen',
       desc='Flush wall-mounted portrait customer-information display: silver housing with blue trim, black bezel, emissive status screen and lit roundel.',
       origin='wall_surface_centre', origin_note='centre of the housing on the wall plane z=0; protrudes 0.10 m towards -Z', front='screen faces -Z',
       nodes={'body': 'housing + bezel', 'screen': 'emissive screen quad', 'logo': 'lit roundel'},
       slots={'mat_cid_screen': 'emissive portrait screen 640x1136, 0.62 x 1.10 m', 'mat_cid_logo': 'lit roundel (RGBA)'},
       anim={}, mount_height=1.45, notes=['0.76 x 1.45 x 0.10 m. Centre 1.45 m above the floor (bottom edge 0.73, top 2.18). No collision.'])
def cid_wall_screen(P):
    _cid_mats(P)
    mb = P.mb('body', dirt=False)
    _cid_head(P, mb, -0.725, -0.10)


@hprop('departure_board_dm',
       desc='Amber dot-matrix departure board (0.90 x 0.50 m): black bezel, emissive amber text on black, hung from the ceiling on two rods with clamps.',
       origin='ceiling_point', origin_note='point on the ceiling, centred on the board; the rods hang 0.70 m and the board top is 0.70 m below the origin', front='screen faces -Z',
       nodes={'rods': 'two rods + ceiling plates; pivot = origin, modelled 0.70 m long (scale.y = L/0.70)', 'body': 'housing, clamps; pivot at the rod bottom (0,-0.70,0) - move to y=-L',
              'screen': 'emissive text quad; pivot (0,-0.95,-0.0465) - move together with body'},
       slots={'mat_dm_text': 'emissive amber dot-matrix picture 1024x536, 0.84 x 0.44 m, UV 0..1 upright from -Z; retarget albedo AND emission'},
       anim={}, mount_height=3.2,
       notes=['Board 0.90 x 0.50 x 0.09 m. Default hang: board centre 0.95 m below the ceiling. Change the hang by scaling node "rods" in Y and translating "body"/"screen" by the same amount.'])
def departure_board_dm(P):
    _tex(P, 'mat_dm_text', 'dm_board', emit=1.5, rough=0.3)
    L = 0.70
    rm = P.mb('rods', pivot=(0.0, 0.0, 0.0), dirt=False, extras={'rod_length': L})
    for sx in (-1, 1):
        rm.cyl('mat_steel_polished', (sx * 0.33, 0.0, 0.0), (sx * 0.33, -L, 0.0), 0.006, seg=8)
        rm.cyl('mat_steel', (sx * 0.33, 0.0, 0.0), (sx * 0.33, -0.008, 0.0), 0.028, seg=12)
    mb = P.mb('body', pivot=(0.0, -L, 0.0), dirt=False)
    mb.box('mat_black_plastic', (-0.45, -L - 0.50, -0.045), (0.45, -L, 0.045), bevel=0.012, seg=1)
    mb.box('mat_black_gloss', (-0.43, -L - 0.48, -0.050), (0.43, -L - 0.02, -0.040), bevel=0.003)
    for sx in (-1, 1):
        mb.box('mat_steel', (sx * 0.33 - 0.02, -L - 0.03, -0.028), (sx * 0.33 + 0.02, -L + 0.012, 0.028), bevel=0.004)
    sm = P.mb('screen', pivot=(0.0, -L - 0.25, -0.0465), dirt=False)
    sm.fdecal('mat_dm_text', 0.0, -L - 0.47, 0.84, 0.44, -0.0505)


# ================================================================================================================ 8. framed maps
def _map_frame(P, W, H, bar, tex_name, desc_name):
    D = 0.038
    P.mat('mat_map', c='decals/hall_b_%s_c.png' % tex_name, rough=0.5, spec=0.3)
    _mats(P, 'mat_hb_glass')
    mb = P.mb('body', dirt=False)
    pw, ph = W - 2 * bar, H - 2 * bar
    mb.box('mat_charcoal', (-pw / 2, -ph / 2, -0.006), (pw / 2, ph / 2, 0.0))
    for (lo, hi) in (((-W / 2, -H / 2, -D), (-W / 2 + bar, H / 2, 0.0)), ((W / 2 - bar, -H / 2, -D), (W / 2, H / 2, 0.0)),
                     ((-W / 2 + bar, -H / 2, -D), (W / 2 - bar, -H / 2 + bar, 0.0)), ((-W / 2 + bar, H / 2 - bar, -D), (W / 2 - bar, H / 2, 0.0))):
        mb.box('mat_hb_alu', lo, hi, bevel=0.004, seg=1)
    # inner black lip so the picture reads as recessed
    mb.box('mat_black_plastic', (-pw / 2, ph / 2 - 0.006, -D + 0.004), (pw / 2, ph / 2, -0.010))
    mb.box('mat_black_plastic', (-pw / 2, -ph / 2, -D + 0.004), (pw / 2, -ph / 2 + 0.006, -0.010))
    mb.plate('mat_hb_glass', pw, ph, 0.0, z=-D + 0.006, facing=-1)
    mp = P.mb('map', pivot=(0.0, 0.0, -0.014), dirt=False)
    mp.fdecal('mat_map', 0.0, -ph / 2, pw, ph, -0.014)
    return pw, ph


@hprop('tube_map_frame',
       desc='Framed network map: brushed-aluminium frame, glazed front, picture on its own node / material slot (mat_map) - retarget with the rendered Tube diagram.',
       origin='wall_surface_centre', origin_note='centre of the frame on the wall plane z=0; protrudes 0.038 m towards -Z', front='picture faces -Z',
       nodes={'body': 'frame, back, glazing', 'map': 'picture quad (own node, pivot at its centre) with mat_map'},
       slots={'mat_map': 'picture 1.044 x 0.744 m (aspect 1.403), UV 0..1: u = left->right, v = bottom->top as seen from -Z; placeholder 1436x1024 fictional network. Unlit.'},
       anim={}, mount_height=1.55, notes=['Outer 1.10 x 0.80 x 0.038 m, frame bar 0.028. Mount the centre 1.2-1.9 m above the floor. No collision.'])
def tube_map_frame(P):
    _map_frame(P, 1.10, 0.80, 0.028, 'map_tube', 'tube')


@hprop('local_map_frame',
       desc='Framed local-area map (larger than the network map): brushed-aluminium frame, glazed front, picture on its own node (mat_map).',
       origin='wall_surface_centre', origin_note='centre of the frame on the wall plane z=0; protrudes 0.038 m towards -Z', front='picture faces -Z',
       nodes={'body': 'frame, back, glazing', 'map': 'picture quad (own node) with mat_map'},
       slots={'mat_map': 'picture 1.144 x 0.844 m (aspect 1.355), UV 0..1 upright from -Z; placeholder 1040x768 street map. Unlit.'},
       anim={}, mount_height=1.55, notes=['Outer 1.20 x 0.90 x 0.038 m, frame bar 0.028.'])
def local_map_frame(P):
    _map_frame(P, 1.20, 0.90, 0.028, 'map_local', 'local')


@hprop('leaflet_rack',
       desc='Wall-mounted leaflet rack: white board in a grey frame with a blue "Information" header, three rows of shelf pockets holding coloured leaflets.',
       origin='wall_surface_centre', origin_note='centre of the board on the wall plane z=0; protrudes 0.06 m towards -Z', front='faces -Z',
       nodes={'body': 'board, shelves, leaflets'}, slots={'mat_leaflet_header': 'header 512x128', 'mat_leaflet_card': 'leaflet print 128x128'},
       anim={}, mount_height=1.35, notes=['0.46 x 0.72 x 0.06 m. Sits next to the local map (Golders Green).'])
def leaflet_rack(P):
    _tex(P, 'mat_leaflet_header', 'leaflet_header', rough=0.4)
    _tex(P, 'mat_leaflet_card', 'leaflet_card', rough=0.6)
    _mats(P, 'mat_hb_white', 'mat_hb_lgrey', 'mat_hb_leaf1', 'mat_hb_leaf2', 'mat_hb_leaf3')
    mb = P.mb('body', dirt=False)
    W, H, D = 0.46, 0.72, 0.06
    mb.box('mat_hb_lgrey', (-W / 2, -H / 2, -0.03), (W / 2, H / 2, 0.0), bevel=0.006, seg=1)
    mb.box('mat_hb_white', (-W / 2 + 0.02, -H / 2 + 0.02, -0.033), (W / 2 - 0.02, H / 2 - 0.02, -0.03))
    mb.fdecal('mat_leaflet_header', 0.0, H / 2 - 0.02 - 0.10, 0.42, 0.42 * 128 / 512, -0.0335)
    mats = ['mat_hb_leaf1', 'mat_hb_leaf2', 'mat_hb_leaf3']
    rnd = random.Random(3)
    for r, y in enumerate((-0.30, -0.12, 0.06)):
        mb.box('mat_hb_lgrey', (-W / 2 + 0.02, y, -D), (W / 2 - 0.02, y + 0.012, -0.03), bevel=0.003)            # shelf
        mb.box('mat_hb_lgrey', (-W / 2 + 0.02, y, -D), (W / 2 - 0.02, y + 0.030, -D + 0.008), bevel=0.003)      # front lip
        for k in range(3):
            x = -0.135 + k * 0.135
            h = rnd.uniform(0.11, 0.15)
            m = mats[(k + r) % 3]
            mb.box(m, (x - 0.052, y + 0.012, -0.055), (x + 0.052, y + 0.012 + h, -0.047))
            if (k + r) % 2 == 0:
                mb.fdecal('mat_leaflet_card', x, y + 0.012, 0.104, 0.104, -0.0555)


# ================================================================================================================ 9. planter
@hprop('planter',
       desc='Dark-stained timber trough planter (crate style, steel corner straps) with soil and a mass of green foliage with red and white flowers.',
       origin='floor_centre', front='either long side', nodes={'body': 'trough, soil, plants', 'col_body-convcolonly': 'collision'},
       slots={'mat_timber': 'trough timber', 'mat_hb_leaf_a': 'foliage', 'mat_hb_flower_r': 'flowers'},
       anim={}, mount_height=0.0, notes=['0.90 x 0.36 x 0.32 m trough, plants reach 0.62 m and overhang to 1.0 x 0.42.'])
def planter(P):
    mb = P.mb('body', smooth=75.0)
    hx, hz, H = 0.45, 0.18, 0.32
    mb.box('mat_timber', (-hx + 0.03, 0.03, -hz + 0.02), (hx - 0.03, 0.05, hz - 0.02))                     # base board
    for sz in (-1, 1):                                                                                      # long sides: 3 slats
        for k in range(3):
            y0 = 0.035 + k * 0.095
            mb.box('mat_timber', (-hx, y0, min(sz * hz, sz * (hz - 0.016))), (hx, y0 + 0.088, max(sz * hz, sz * (hz - 0.016))), off=(k * 0.31, sz * 0.2))
    for sx in (-1, 1):                                                                                      # end boards
        mb.box('mat_timber', (min(sx * hx, sx * (hx - 0.016)), 0.035, -hz + 0.02), (max(sx * hx, sx * (hx - 0.016)), H, hz - 0.02))
    for sx in (-1, 1):                                                                                      # corner posts
        for sz in (-1, 1):
            mb.box('mat_timber', (sx * (hx - 0.02) - 0.02, 0.0, sz * (hz - 0.02) - 0.02), (sx * (hx - 0.02) + 0.02, H + 0.005, sz * (hz - 0.02) + 0.02))
    for y in (0.10, 0.25):
        mb.box('mat_steel', (-hx - 0.003, y, -hz - 0.003), (hx + 0.003, y + 0.012, -hz + 0.001))
        mb.box('mat_steel', (-hx - 0.003, y, hz - 0.001), (hx + 0.003, y + 0.012, hz + 0.003))
    mb.box('mat_hb_soil', (-hx + 0.03, H - 0.03, -hz + 0.03), (hx - 0.03, H - 0.012, hz - 0.03))
    rnd = random.Random(21)
    for i in range(8):
        x = -0.36 + i * 0.103 + rnd.uniform(-0.02, 0.02)
        z = rnd.uniform(-0.06, 0.06)
        r = rnd.uniform(0.085, 0.115)
        mb.blob('mat_hb_leaf_a' if i % 2 == 0 else 'mat_hb_leaf_b', (x, 0.40 + rnd.uniform(0, 0.04), z), r, rnd, seg=9, rings=4, jitter=0.26,
                scale=(1.15, 0.85, 1.0))
    for i in range(4):
        x = -0.30 + i * 0.20 + rnd.uniform(-0.03, 0.03)
        mb.blob('mat_hb_leaf_b', (x, 0.50 + rnd.uniform(0, 0.03), rnd.uniform(-0.05, 0.05)), rnd.uniform(0.07, 0.09), rnd, seg=8, rings=4, jitter=0.3)
    for i in range(10):
        x = -0.40 + i * 0.089 + rnd.uniform(-0.02, 0.02)
        z = rnd.uniform(-0.09, 0.09)
        y = rnd.uniform(0.52, 0.60)
        m = 'mat_hb_flower_r' if (i % 3) else 'mat_hb_flower_w'
        mb.blob(m, (x, y, z), rnd.uniform(0.034, 0.048), rnd, seg=6, rings=3, jitter=0.2)
        mb.cyl('mat_hb_leaf_a', (x, 0.44, z), (x, y - 0.02, z), 0.004, seg=5)
    P.col_box('col_body-convcolonly', (-hx, 0.0, -hz), (hx, 0.40, hz))
