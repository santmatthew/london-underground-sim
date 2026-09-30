"""Ticket gates: gate_unit, gate_wide, gate_fence.

gate_unit / gate_wide are E2-style cabinets modelled from the reference photos in build/refs_dress/halls (SPEC.md sec 3):
brushed-stainless body on a black plinth, black sloped plastic top with the yellow 95 mm reader pad and a small fare display,
a lit green-arrow / red-cross indicator head on a mast, blue 'go' / red 'no entry' roundels on the cabinet ends, a dark diamond
floor plate in the lane and dark translucent rounded paddles (wide gate: glass leaves with a blue pictogram header).
Runtime contract (scripts/world/Station.gd): nodes body / flap_L / flap_R (door_L / door_R) / lamp_go / lamp_stop,
hinges at (+-lane/2, 0, -0.10), rotation.y +-90 to open, collision col_ped_L / col_ped_R, walk direction -Z."""
import math
import propcore
from propcore import prop
from propmesh import Xf, rrect_pts, fillet_poly, add, mul

# the game has no reflection probes: fully metallic stainless renders black, so the gates use a semi-metallic brushed steel
propcore.TILES['mat_gate_steel'] = (0.5, 0.5)
propcore.DIRTY.add('mat_gate_steel')

PW = 0.16            # pedestal width (x): two neighbouring pedestals form one 0.33 m cabinet
PL = 1.50            # pedestal length (z)
ZE = PL / 2          # +z = entry end (passengers walk toward -z)
ZX = -PL / 2         # -z = exit end
H_PLINTH = 0.125     # black plastic skirt
H_BODY = 0.965       # top of the stainless body
H_CAP = 0.990        # top of the black plastic cap = cabinet top
H_HEAD = 1.085       # top of the reader head
YM = 1.285           # centre of the lit indicator
ZM = 0.29            # z of the indicator mast


def _gate_mats(P):
    P.mat('mat_gate_steel', c='tile/steel_c.jpg', n='tile/steel_n.jpg', rough=0.42, metal=0.35, spec=0.6)
    P.mat('mat_gate_chrome', color=(0.78, 0.79, 0.81, 1), rough=0.28, metal=0.5, spec=0.6)
    P.mat('mat_paddle', color=(0.045, 0.05, 0.055, 1), rough=0.3, alpha=0.8, double=True, spec=0.7)
    P.mat('mat_gate_glass', color=(0.58, 0.75, 0.73, 1), rough=0.05, alpha=0.26, double=True, spec=0.8)
    P.mat('mat_paddle_rim', color=(0.03, 0.033, 0.037, 1), rough=0.4, spec=0.5)
    P.mat('mat_gate_reader', c='decals/hall_a_disc_c.png', emit=(1, 1, 1), emit_tex=True, emit_strength=0.35, rough=0.4, spec=0.35)
    P.mat('mat_gate_display', c='decals/gate_display_c.png', emit=(1, 1, 1), emit_tex=True, emit_strength=1.4, rough=0.15, spec=0.7)
    P.mat('mat_gate_disc_in', c='decals/hall_a_disc_in_c.png', rough=0.35, spec=0.6)
    P.mat('mat_gate_disc_out', c='decals/hall_a_disc_out_c.png', rough=0.35, spec=0.6)
    P.mat('mat_gate_sticker', c='decals/hall_a_sticker_c.png', rough=0.4)
    P.mat('mat_gate_top', color=(0.023, 0.024, 0.027, 1), rough=0.42, spec=0.5)              # E2 top plastic ~#2A2B2D
    P.mat('mat_gate_plinth', color=(0.015, 0.016, 0.019, 1), rough=0.6, spec=0.4)
    P.mat('mat_gate_plate', c='decals/hall_a_plate_c.png', n='decals/hall_a_plate_n.png', rough=0.45, metal=0.55)
    P.mat('mat_lamp_go', c='decals/lamp_go_c.png', emit=(1, 1, 1), emit_tex=True, emit_strength=3.5, rough=0.2)
    P.mat('mat_lamp_stop', c='decals/lamp_stop_c.png', emit=(1, 1, 1), emit_tex=True, emit_strength=3.5, rough=0.2)


def _xspan(x_in, depth, side):
    """x-range of a thin feature that protrudes `depth` from the pedestal inner face (lane is toward -side)."""
    a = x_in; b = x_in - side * depth
    return (min(a, b), max(a, b))


def _seam(mb, xface, out, z, y0, y1):
    """hairline dark panel joint on a vertical side face (out = +1/-1: outward normal along x)"""
    a, b = xface, xface + out * 0.0009
    skip = tuple(k for k in ('+x', '-x', '+y', '-y', '+z', '-z') if k != ('+x' if out > 0 else '-x'))
    mb.box('mat_black_plastic', (min(a, b), y0, z - 0.0018), (max(a, b), y1, z + 0.0018), skip=skip)


def pedestal(mb, cx, side, lane_lamp=False, sensor_z=(0.56, 0.22, -0.60), flap_z=-0.10, wrap=None):
    """one pedestal centred at x=cx. side=+1: lane on its -x side (inner face at cx-PW/2); side=-1 mirrored.
    lane_lamp=True: this pedestal carries the reader head, indicator mast and the end roundels.
    wrap: name of a printed advert material for the entry-end front face (replaces the blue roundel)."""
    xlo, xhi = cx - PW / 2, cx + PW / 2
    x_in = cx - side * PW / 2
    xs_in = x_in + side * 0.004               # brushed-steel face on the lane side
    xs_out = cx + side * PW / 2 - side * 0.004   # steel face on the outer side
    # ---- plinth, stainless body, black plastic cap
    mb.box('mat_gate_plinth', (xlo, 0.0, ZX), (xhi, H_PLINTH, ZE), bevel=0.012)
    mb.box('mat_gate_steel', (xlo + 0.004, H_PLINTH - 0.004, ZX + 0.005), (xhi - 0.004, H_BODY, ZE - 0.005), bevel=0.013, seg=2)
    mb.box('mat_gate_top', (xlo - 0.002, H_BODY - 0.002, ZX - 0.002), (xhi + 0.002, H_CAP, ZE + 0.002), bevel=0.010)
    # panel joints: end posts separated from the service panel
    for xf, out in ((xs_in, -side), (xs_out, side)):
        for z in (0.44, -0.44):
            _seam(mb, xf, out, z, H_PLINTH + 0.012, H_BODY - 0.014)

    # horizontal joint of the service panel + lock barrel on the outer face
    for xf, out in ((xs_in, -side), (xs_out, side)):
        a, b = xf, xf + out * 0.0009
        skip = tuple(k for k in ('+x', '-x', '+y', '-y', '+z', '-z') if k != ('+x' if out > 0 else '-x'))
        mb.box('mat_black_plastic', (min(a, b), 0.585, -0.44), (max(a, b), 0.5885, 0.44), skip=skip)
    with mb.tf(Xf.T(xs_out, 0.80, -0.20) * Xf.R('z', -90 * side)):
        mb.cyl('mat_gate_chrome', (0, 0, 0), (0, 0.0035, 0), 0.009, seg=10)
        mb.cyl('mat_black_plastic', (0, 0.0030, 0), (0, 0.0040, 0), 0.0035, seg=6)

    # ---- inner (lane) face: hinge boss, photo-eyes, sticker
    lo, hi = _xspan(xs_in, 0.010, side)
    mb.box('mat_black_plastic', (lo, 0.34, flap_z - 0.016), (hi, 1.10, flap_z + 0.016), bevel=0.0035)
    for zz in sensor_z:
        for yy in (0.30, 0.62):
            lo2, hi2 = _xspan(xs_in, 0.0025, side)
            mb.box('mat_black_gloss', (lo2, yy - 0.006, zz - 0.014), (hi2, yy + 0.006, zz + 0.014), bevel=0.0)
    # small blue sticker near the reader end (reads from inside the lane)
    xf = xs_in - side * 0.0006
    if side > 0:
        mb.qdecal('mat_gate_sticker', (xf, 0.78, 0.50), (0, 0, 1), (0, 1, 0), 0.10, 0.05, hint=(-1, 0, 0))
    else:
        mb.qdecal('mat_gate_sticker', (xf, 0.78, 0.60), (0, 0, -1), (0, 1, 0), 0.10, 0.05, hint=(1, 0, 0))

    if wrap:
        # advert wrap on the recessed steel front of the entry end (0.14 x 0.82 m)
        mb.qdecal(wrap, (cx - 0.07, H_PLINTH + 0.010, ZE - 0.0035), (1, 0, 0), (0, 1, 0), 0.14, 0.82, hint=(0, 0, 1))
    if not lane_lamp:
        return
    # ---- end roundels: blue 'go' at the entry end, red 'no entry' at the exit end
    xd = cx + 0.005
    for (z, mat, fac) in ((ZE, 'mat_gate_disc_in', +1), (ZX, 'mat_gate_disc_out', -1)):
        if wrap and fac > 0:
            continue
        with mb.tf(Xf.T(xd, 0.58, z) * Xf.R('x', 90 * fac)):
            mb.tile(mat, 0.104, -0.104) if fac > 0 else mb.tile(mat, -0.104, 0.104)
            mb.lathe('mat_gate_chrome', [(0.056, 0.0), (0.056, 0.0035), (0.052, 0.0035), (0.052, 0.0)], seg=24)
            mb.lathe(mat, [(0.052, 0.0032), (0.0, 0.0032)], seg=24)

    # ---- sloped reader head
    zf, z1 = ZE - 0.02, ZE - 0.20
    zb = ZE - 0.46
    yf = 1.030
    y0 = H_CAP - 0.002
    prof = fillet_poly([(zf, y0), (zb, y0), (zb, H_HEAD), (z1, H_HEAD), (zf, yf)], 0.010, 3)
    mb.prism('mat_gate_top', prof, 'x', cx - 0.072, cx + 0.072, bevel=0.005)
    alpha = math.degrees(math.atan2(H_HEAD - yf, zf - z1))
    zm = (zf + z1) / 2
    ym = (yf + H_HEAD) / 2 + 0.001
    with mb.tf(Xf.T(cx, ym, zm) * Xf.R('x', alpha)):
        mb.tile('mat_gate_reader', 0.095, -0.095)
        mb.lathe('mat_black_gloss', [(0.0, 0.0), (0.0585, 0.0), (0.0585, 0.0048), (0.0, 0.0048)], seg=22)
        mb.lathe('mat_gate_reader', [(0.0475, 0.0052), (0.0, 0.0052)], seg=22)
    # small fare display on the flat rear part of the head
    dz = 0.43
    mb.box('mat_black_gloss', (cx - 0.052, H_HEAD - 0.001, dz - 0.032), (cx + 0.052, H_HEAD + 0.0028, dz + 0.032), bevel=0.0)
    mb.qdecal('mat_gate_display', (cx - 0.046, H_HEAD + 0.0031, dz + 0.023), (1, 0, 0), (0, 0, -1), 0.092, 0.046, hint=(0, 1, 0))
    # ---- indicator mast + head (green arrow / red cross plates are the separate lamp nodes)
    mb.box('mat_black_plastic', (cx - 0.020, H_HEAD - 0.004, ZM - 0.020), (cx + 0.020, 1.215, ZM + 0.020), bevel=0.0)
    mb.box('mat_gate_top', (cx - 0.040, 1.205, ZM - 0.030), (cx + 0.040, 1.365, ZM + 0.030), bevel=0.010)
    # exit-side face of the indicator: permanently red cross (wrong way)
    mb.qdecal('mat_lamp_stop', (cx + 0.029, YM - 0.029, ZM - 0.0303), (-1, 0, 0), (0, 1, 0), 0.058, 0.058, hint=(0, 0, -1))


def _lamps(P, cx):
    """green arrow (lamp_go) & red cross (lamp_stop) plates on the indicator head: same spot, only one is visible at a time"""
    for nm, mat, dz in (('lamp_go', 'mat_lamp_go', 0.0), ('lamp_stop', 'mat_lamp_stop', 0.0006)):
        z = ZM + 0.0303 + dz
        mb = P.mb(nm, pivot=(cx, YM, z), dirt=False, extras={'kind': 'status_lamp'})
        mb.qdecal(mat, (cx - 0.029, YM - 0.029, z), (1, 0, 0), (0, 1, 0), 0.058, 0.058, hint=(0, 0, 1))


def _floor_plate(mb, lane):
    """dark diamond tread plate between the cabinets (visual only, 10 mm high)"""
    mb.tile('mat_gate_plate', 0.256, 0.256)
    mb.box('mat_gate_plate', (-lane / 2 + 0.003, 0.0, ZX + 0.06), (lane / 2 - 0.003, 0.010, ZE - 0.06), bevel=0.0)


def _ring_z(mb, mat, outer, inner, z0, z1):
    """flat frame between two matching convex polygons (same vertex count), extruded along z from z0 to z1"""
    n = len(outer)
    cx = sum(p[0] for p in outer) / n
    cy = sum(p[1] for p in outer) / n
    for i in range(n):
        j = (i + 1) % n
        oi, oj, ii, ij = outer[i], outer[j], inner[i], inner[j]
        for (z, h) in ((z0, (0, 0, -1)), (z1, (0, 0, 1))):
            mb.face(mat, [(oi[0], oi[1], z), (oj[0], oj[1], z), (ij[0], ij[1], z), (ii[0], ii[1], z)], hint=h)
        mb.face(mat, [(oi[0], oi[1], z0), (oj[0], oj[1], z0), (oj[0], oj[1], z1), (oi[0], oi[1], z1)],
                hint=((oi[0] + oj[0]) / 2 - cx, (oi[1] + oj[1]) / 2 - cy, 0))
        mb.face(mat, [(ii[0], ii[1], z0), (ij[0], ij[1], z0), (ij[0], ij[1], z1), (ii[0], ii[1], z1)],
                hint=(cx - (ii[0] + ij[0]) / 2, cy - (ii[1] + ij[1]) / 2, 0))


def _paddle(P, name, hinge_x, hinge_z, dirx, length, y0, y1, extras):
    """E2 paddle: rounded dark rim with a smoked translucent centre. origin = hinge axis on the pedestal inner face.
    The plate sits 16 mm to the +z side of the hinge so that, folded open (+-90 deg), it stands proud of the pedestal face."""
    mb = P.mb(name, pivot=(hinge_x, 0.0, hinge_z), dirt=False, extras=extras)
    zc = hinge_z + 0.016
    xa = hinge_x + dirx * 0.012
    xb = hinge_x + dirx * (length - 0.010)
    w = abs(xb - xa)
    cxp = (xa + xb) / 2
    cy = (y0 + y1) / 2
    h = y1 - y0
    r = min(0.105, w * 0.45)
    t = 0.024
    outer = rrect_pts(cxp, cy, w, h, r, 4)
    inner = rrect_pts(cxp, cy, w - 2 * t, h - 2 * t, r - t, 4)
    _ring_z(mb, 'mat_paddle_rim', outer, inner, zc - 0.011, zc + 0.011)
    mb.face('mat_paddle', [(p[0], p[1], zc) for p in inner], hint=(0, 0, -1))
    # hinge spindle and hub
    mb.cyl('mat_paddle_rim', (hinge_x + dirx * 0.004, y0 - 0.03, zc), (hinge_x + dirx * 0.004, y1 + 0.02, zc), 0.0115, seg=10)
    return mb


def _wide_leaf(P, name, hinge_x, hinge_z, dirx, length, y0, y1, extras):
    """wide-aisle leaf: dark rim, clear glass, blue pictogram header panel (both faces)"""
    mb = P.mb(name, pivot=(hinge_x, 0.0, hinge_z), dirt=False, extras=extras)
    zc = hinge_z + 0.016
    xa = hinge_x + dirx * 0.012
    xb = hinge_x + dirx * (length - 0.010)
    w = abs(xb - xa)
    cxp = (xa + xb) / 2
    cy = (y0 + y1) / 2
    h = y1 - y0
    r = 0.05
    t = 0.028
    outer = rrect_pts(cxp, cy, w, h, r, 3)
    inner = rrect_pts(cxp, cy, w - 2 * t, h - 2 * t, r - 0.02, 3)
    _ring_z(mb, 'mat_gate_steel', outer, inner, zc - 0.011, zc + 0.011)
    mb.face('mat_gate_glass', [(p[0], p[1], zc) for p in inner], hint=(0, 0, -1))
    # blue header with pictograms
    hw = w - 2 * t
    hh = 0.245
    hy1 = y1 - t
    xl = cxp - hw / 2
    xr = cxp + hw / 2
    mb.qdecal('mat_gate_widesign', (xl, hy1 - hh, zc + 0.0125), (1, 0, 0), (0, 1, 0), hw, hh, hint=(0, 0, 1))
    mb.qdecal('mat_gate_widesign', (xr, hy1 - hh, zc - 0.0125), (-1, 0, 0), (0, 1, 0), hw, hh, hint=(0, 0, -1))
    # push bars on the free edge, spindle
    hx = hinge_x + dirx * (length - 0.05)
    for zz in (zc + 0.030, zc - 0.030):
        mb.cyl('mat_gate_chrome', (hx, 0.60, zz), (hx, 0.98, zz), 0.008, seg=8)
    mb.cyl('mat_paddle_rim', (hinge_x + dirx * 0.004, y0 - 0.03, zc), (hinge_x + dirx * 0.004, y1 + 0.02, zc), 0.0115, seg=10)
    return mb


@prop('gate_unit',
      desc='One E2-style ticket-gate lane module: two brushed-stainless cabinets on black plinths with black sloped tops, yellow contactless '
           'reader pad and fare display, lit green-arrow / red-cross indicator head, blue go / red no-entry roundels on the cabinet ends, '
           'dark diamond floor plate and two dark translucent rounded paddles that close the lane.',
      origin='floor_centre', front='passenger travel direction is -Z (entry end +Z with reader, indicator and blue roundel facing +Z; exit end -Z has the red no-entry roundel)',
      nodes={'body': 'static cabinets, floor plate, reader, display, decals',
             'flap_L': 'left paddle (x<0). origin = hinge on pedestal inner face at x=-0.30,z=-0.10',
             'flap_R': 'right paddle (x>0). origin = hinge on pedestal inner face at x=+0.30,z=-0.10',
             'lamp_go': 'emissive green arrow plate on the indicator head (own material mat_lamp_go), mast on the +x cabinet, faces +Z',
             'lamp_stop': 'emissive red cross plate, same spot 0.6 mm in front of lamp_go (own material mat_lamp_stop)',
             'col_ped_L/col_ped_R': 'convex collision boxes (StaticBody3D on import) - the lane between them stays free'},
      slots={'mat_gate_reader': 'yellow 95 mm reader pad', 'mat_gate_disc_in': 'blue entry roundel', 'mat_gate_disc_out': 'red no-entry roundel',
             'mat_lamp_go': 'emissive - toggle node visibility or emission_energy', 'mat_lamp_stop': 'emissive',
             'mat_gate_display': 'emissive small display next to the reader', 'mat_paddle': 'paddle centre (alpha blend)',
             'mat_gate_plate': 'diamond floor plate'},
      anim={'flap_L': {'closed_rotation_y_deg': 0.0, 'open_rotation_y_deg': 90.0, 'alt_open_scale': [0.04, 1, 1]},
            'flap_R': {'closed_rotation_y_deg': 0.0, 'open_rotation_y_deg': -90.0, 'alt_open_scale': [0.04, 1, 1]}},
      notes=['Paddles OPEN by swinging about the vertical hinge: flap_L rotation.y = +90 deg, flap_R rotation.y = -90 deg '
             '(each paddle folds flat against its cabinet, towards the exit). Alternative visual: tween scale.x 1 -> 0.04 (extras alt_open_scale).',
             'Lane clear width 0.60 m (x -0.30..+0.30). Unit footprint 0.93 x 1.50 m: place lanes at 0.93 m pitch '
             '(neighbouring pedestals touch, giving a double-width dividing cabinet). Cabinet top 0.99 m, reader head 1.085 m, indicator head 1.365 m.',
             'lamp_go and lamp_stop overlap at the indicator head: show exactly one of them (Station.gd already does).'])
def gate_unit(P):
    _build_gate_unit(P)


def _build_gate_unit(P, wrap=None):
    LANE = 0.60
    _gate_mats(P)
    if wrap:
        P.mat('mat_endwrap', c='decals/%s_c.png' % wrap, rough=0.4, spec=0.4)
    cx = LANE / 2 + PW / 2
    body = P.mb('body')
    w = 'mat_endwrap' if wrap else None
    pedestal(body, cx, +1, lane_lamp=True, wrap=w)
    pedestal(body, -cx, -1, lane_lamp=False, wrap=w)
    _floor_plate(body, LANE)
    _lamps(P, cx)
    lf = (LANE - 0.02) / 2
    _paddle(P, 'flap_L', -LANE / 2, -0.10, +1, lf, 0.40, 1.08, {'open_rotation_y_deg': 90.0, 'alt_open_scale': [0.04, 1.0, 1.0]})
    _paddle(P, 'flap_R', +LANE / 2, -0.10, -1, lf, 0.40, 1.08, {'open_rotation_y_deg': -90.0, 'alt_open_scale': [0.04, 1.0, 1.0]})
    P.col_box('col_ped_R-convcolonly', (cx - PW / 2, 0, ZX), (cx + PW / 2, 1.0, ZE))
    P.col_box('col_ped_L-convcolonly', (-cx - PW / 2, 0, ZX), (-cx + PW / 2, 1.0, ZE))


def _ad_variant(suffix, tex, what):
    @prop('gate_unit_ad_' + suffix,
          desc='gate_unit with a printed advert wrap (%s) on the entry-end front of both cabinets (no blue roundel there). Same nodes, hinges, '
               'animation and collision as gate_unit.' % what,
          origin='floor_centre', front='passenger travel direction is -Z (entry end +Z)',
          nodes={'body': 'cabinets, floor plate, reader, wraps', 'flap_L': 'as gate_unit', 'flap_R': 'as gate_unit',
                 'lamp_go': 'as gate_unit', 'lamp_stop': 'as gate_unit', 'col_ped_L/col_ped_R': 'as gate_unit'},
          slots={'mat_endwrap': 'advert print on the cabinet entry ends (154 x 900 px = 0.14 x 0.82 m)'},
          anim={'flap_L': {'closed_rotation_y_deg': 0.0, 'open_rotation_y_deg': 90.0, 'alt_open_scale': [0.04, 1, 1]},
                'flap_R': {'closed_rotation_y_deg': 0.0, 'open_rotation_y_deg': -90.0, 'alt_open_scale': [0.04, 1, 1]}},
          notes=['Drop-in replacement for gate_unit (identical footprint / contract); use a few in a gateline for variety. Invented brands only.'])
    def _f(P):
        _build_gate_unit(P, tex)
    return _f


gate_unit_ad_a = _ad_variant('a', 'hall_a_gate_ad_a', 'yellow / black theatre poster')
gate_unit_ad_b = _ad_variant('b', 'hall_a_gate_ad_b', 'blue retail sale')
gate_unit_ad_c = _ad_variant('c', 'hall_a_gate_ad_c', 'phone shop, colour bars')


@prop('gate_wide',
      desc='Accessible E2 wide-aisle ticket-gate lane (0.90 m clear): same cabinets as gate_unit with taller glass swing leaves that carry a blue '
           'wheelchair / pushchair pictogram header.',
      origin='floor_centre', front='passenger travel direction is -Z (entry end +Z)',
      nodes={'body': 'static cabinets, floor plate', 'door_L': 'left glass leaf, origin = hinge at x=-0.45,z=-0.10',
             'door_R': 'right glass leaf, origin = hinge at x=+0.45,z=-0.10',
             'lamp_go': 'emissive green arrow', 'lamp_stop': 'emissive red cross', 'col_ped_L/col_ped_R': 'collision'},
      slots={'mat_gate_widesign': 'pictogram header print (both faces)', 'mat_lamp_go': 'emissive', 'mat_lamp_stop': 'emissive',
             'mat_gate_glass': 'leaf glass', 'mat_gate_display': 'emissive'},
      anim={'door_L': {'open_rotation_y_deg': 90.0, 'alt_open_scale': [0.04, 1, 1]}, 'door_R': {'open_rotation_y_deg': -90.0, 'alt_open_scale': [0.04, 1, 1]}},
      notes=['Leaves swing about the vertical hinge: door_L rotation.y = +90 deg, door_R = -90 deg (fold against the cabinets, '
             'towards the exit). Lane clear width 0.90 m. Leaves are 1.02 m tall (0.22..1.24).'])
def gate_wide(P):
    LANE = 0.90
    _gate_mats(P)
    P.mat('mat_gate_widesign', c='decals/hall_a_wide_sign_c.png', rough=0.4, spec=0.5)
    cx = LANE / 2 + PW / 2
    body = P.mb('body')
    pedestal(body, cx, +1, lane_lamp=True)
    pedestal(body, -cx, -1, lane_lamp=False)
    _floor_plate(body, LANE)
    _lamps(P, cx)
    lf = (LANE - 0.02) / 2
    for nm, side in (('door_L', -1), ('door_R', +1)):
        _wide_leaf(P, nm, side * LANE / 2, -0.10, -side, lf, 0.22, 1.24, {'open_rotation_y_deg': -90.0 * side, 'alt_open_scale': [0.04, 1.0, 1.0]})
    P.col_box('col_ped_R-convcolonly', (cx - PW / 2, 0, ZX), (cx + PW / 2, 1.0, ZE))
    P.col_box('col_ped_L-convcolonly', (-cx - PW / 2, 0, ZX), (-cx + PW / 2, 1.0, ZE))


@prop('gate_fence',
      desc='2 m fixed barrier section matching the gates: steel pedestal-style base, charcoal cap, glass infill panel and steel posts.',
      origin='floor_centre', front='either long face; symmetric',
      nodes={'body': 'whole section', 'col_fence-convcolonly': 'collision'},
      slots={'mat_glass': 'infill glass'}, anim={},
      notes=['Length 2.0 m along X, depth 0.16 m, height 1.12 m. Place end to end at 2.0 m pitch.'])
def gate_fence(P):
    body = P.mb('body')
    hl = 1.0
    body.box('mat_charcoal', (-hl + 0.02, 0.0, -PW / 2 + 0.008), (hl - 0.02, 0.075, PW / 2 - 0.008), bevel=0.006)
    body.box('mat_steel', (-hl, 0.07, -PW / 2), (hl, 0.62, PW / 2), bevel=0.012, mats={'+x': 'mat_charcoal', '-x': 'mat_charcoal'})
    body.box('mat_charcoal', (-hl - 0.004, 0.62, -PW / 2 - 0.004), (hl + 0.004, 0.66, PW / 2 + 0.004), bevel=0.014, seg=2)
    body.box('mat_black_plastic', (-hl + 0.01, 0.066, -PW / 2 + 0.004), (hl - 0.01, 0.074, PW / 2 - 0.004))
    # glass infill between posts
    body.box('mat_glass', (-hl + 0.05, 0.665, -0.006), (hl - 0.05, 1.10, 0.006), bevel=0.0)
    for x in (-hl + 0.03, 0.0, hl - 0.03):
        body.box('mat_steel', (x - 0.024, 0.66, -0.028), (x + 0.024, 1.12, 0.028), bevel=0.006)
    body.tile('mat_steel_polished', 1.0)
    body.tube('mat_steel_polished', [(-hl + 0.01, 1.105, 0.0), (hl - 0.01, 1.105, 0.0)], 0.014, seg=12)
    body.box('mat_steel', (-hl + 0.05, 0.660, -0.014), (hl - 0.05, 0.672, 0.014), bevel=0.002)
    P.col_box('col_fence-convcolonly', (-hl, 0, -PW / 2), (hl, 1.12, PW / 2))
