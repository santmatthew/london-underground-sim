"""Ticket gates: gate_unit, gate_wide, gate_fence."""
import math
from propcore import prop
from propmesh import Xf, rrect_pts, fillet_poly, add, mul

PW = 0.16            # pedestal width (x)
PL = 1.50            # pedestal length (z)
ZE = PL / 2          # +z = entry end (passengers walk toward -z)
ZX = -PL / 2         # -z = exit end
H_BODY = 0.945
H_CAP = 0.985


def _gate_mats(P):
    P.mat('mat_gate_reader', c='decals/gate_reader_c.png', rough=0.22, spec=0.6)
    P.mat('mat_gate_display', c='decals/gate_display_c.png', emit=(1, 1, 1), emit_tex=True, emit_strength=1.4, rough=0.15, spec=0.7)
    P.mat('mat_endwrap', c='decals/gate_endwrap_c.png', rough=0.38, spec=0.4)
    P.mat('mat_gate_slot', c='decals/gate_ticketslot_c.png', rough=0.4)
    P.mat('mat_lamp_go', c='decals/lamp_go_c.png', emit=(1, 1, 1), emit_tex=True, emit_strength=3.5, rough=0.2)
    P.mat('mat_lamp_stop', c='decals/lamp_stop_c.png', emit=(1, 1, 1), emit_tex=True, emit_strength=3.5, rough=0.2)


def _xspan(x_in, depth, side):
    """x-range of a thin feature that protrudes `depth` from the pedestal inner face (lane is toward -side)."""
    a = x_in; b = x_in - side * depth
    return (min(a, b), max(a, b))


def pedestal(mb, cx, side, lane_lamp=False, wide=False, sensor_z=(0.52, 0.10, -0.32, -0.62), flap_z=-0.10, flap_h=(0.12, 0.90)):
    """one pedestal centred at x=cx. side=+1: lane on its -x side (inner face at cx-PW/2); side=-1 mirrored."""
    xlo, xhi = cx - PW / 2, cx + PW / 2
    x_in = cx - side * PW / 2
    # ---- plinth + body + cap
    mb.box('mat_charcoal', (xlo + 0.008, 0.0, ZX + 0.035), (xhi - 0.008, 0.075, ZE - 0.035), bevel=0.006)
    # dark core + brushed-steel cladding panels with real gaps (panel breaks at z = +0.30 / -0.30)
    mb.box('mat_charcoal', (xlo + 0.003, 0.07, ZX), (xhi - 0.003, H_BODY, ZE), bevel=0.010, mats={})
    for (za, zb) in ((ZE - 0.006, 0.303), (0.297, -0.297), (-0.303, ZX + 0.006)):
        for (xa, xb) in ((xlo, xlo + 0.007), (xhi - 0.007, xhi)):
            mb.box('mat_steel', (xa, 0.078, zb), (xb, H_BODY - 0.006, za), bevel=0.0, off=(za * 1.7, 0.0))
    mb.box('mat_charcoal', (xlo - 0.004, H_BODY, ZX - 0.004), (xhi + 0.004, H_CAP, ZE + 0.004), bevel=0.014, seg=2)
    # thin steel kick-plate reveal line at bottom of body (dark gap)
    mb.box('mat_black_plastic', (xlo + 0.004, 0.066, ZX + 0.01), (xhi - 0.004, 0.074, ZE - 0.01))

    # ---- reader head (sloped)
    zf, zb = ZE - 0.05, ZE - 0.47
    yf, yb = 1.040, 1.125
    prof = fillet_poly([(zf, H_CAP - 0.002), (zb, H_CAP - 0.002), (zb, yb), (zf, yf)], 0.012, 3)
    mb.prism('mat_charcoal', prof, 'x', cx - 0.072, cx + 0.072, bevel=0.006)
    alpha = math.degrees(math.atan2(yb - yf, zf - zb))
    zm = (zf + zb) / 2; ym = (yf + yb) / 2 + 0.0004
    with mb.tf(Xf.T(cx, ym, zm) * Xf.R('x', alpha)):
        # contactless reader
        rz = 0.075
        with mb.tf(Xf.T(0, 0, rz)):
            mb.lathe('mat_steel_polished', [(0.050, 0.0), (0.050, 0.0045), (0.042, 0.0045), (0.042, 0.0)], seg=28)
            mb.lathe('mat_yellow', [(0.042, 0.0), (0.042, 0.0038), (0.0345, 0.0038), (0.0345, 0.0)], seg=28)
            mb.tile('mat_gate_reader', 0.069, -0.069)
            mb.lathe('mat_gate_reader', [(0.0345, 0.0012), (0.0, 0.0012)], seg=28)
        # small display
        dz = -0.035
        mb.box('mat_black_gloss', (-0.050, -0.0005, dz - 0.030), (0.050, 0.0025, dz + 0.030), bevel=0.0)
        mb.qdecal('mat_gate_display', (-0.043, 0.0028, dz + 0.0235), (1, 0, 0), (0, 0, -1), 0.086, 0.047, hint=(0, 1, 0))
        # ticket slot
        sz = -0.135
        mb.box('mat_steel_polished', (-0.030, -0.0005, sz - 0.030), (0.030, 0.0022, sz + 0.030), bevel=0.0)
        mb.qdecal('mat_gate_slot', (-0.026, 0.0026, sz + 0.026), (1, 0, 0), (0, 0, -1), 0.052, 0.052, hint=(0, 1, 0))

    # ---- entry end wrap (replaceable print)
    ex = 0.010
    mb.qdecal('mat_endwrap', (cx - PW / 2 + ex, 0.13, ZE + 0.0015), (1, 0, 0), (0, 1, 0), PW - 2 * ex, 0.78, hint=(0, 0, 1))

    # ---- inner face details: flap gasket + lane sensors
    lo, hi = _xspan(x_in, 0.004, side)
    mb.box('mat_black_gloss', (lo, flap_h[0] - 0.02, flap_z - 0.028), (hi, flap_h[1] + 0.02, flap_z + 0.028), bevel=0.0015)
    for zz in sensor_z:
        for yy in (0.28, 0.72):
            lo2, hi2 = _xspan(x_in, 0.0025, side)
            mb.box('mat_black_gloss', (lo2, yy - 0.006, zz - 0.014), (hi2, yy + 0.006, zz + 0.014), bevel=0.0)

    # ---- lamp mast (green arrow / red cross plates are separate nodes)
    if lane_lamp:
        mb.box('mat_charcoal', (cx - 0.036, H_CAP - 0.002, 0.06), (cx + 0.036, 1.335, 0.135), bevel=0.008)
        for yy in (1.265, 1.185):
            mb.box('mat_black_gloss', (cx - 0.030, yy - 0.033, 0.13), (cx + 0.030, yy + 0.033, 0.1395), bevel=0.004)


def _lamps(P, cx):
    """green arrow (lamp_go) & red cross (lamp_stop) plates on the mast"""
    for nm, mat, yy in (('lamp_go', 'mat_lamp_go', 1.265), ('lamp_stop', 'mat_lamp_stop', 1.185)):
        mb = P.mb(nm, pivot=(cx, yy, 0.1405), dirt=False, extras={'kind': 'status_lamp'})
        mb.qdecal(mat, (cx - 0.025, yy - 0.025, 0.1405), (1, 0, 0), (0, 1, 0), 0.05, 0.05, hint=(0, 0, 1))


def _glass_flap(P, name, hinge_x, hinge_z, dirx, length, y0, y1, extras):
    """glass flap: origin at the hinge (pedestal inner face). panel extends toward dirx (-1 = toward -x)."""
    mb = P.mb(name, pivot=(hinge_x, 0.0, hinge_z), dirt=False, extras=extras)
    ya, yb = y0, y1
    x0 = hinge_x + dirx * 0.009
    x1 = hinge_x + dirx * (length - 0.013)
    lo, hi = min(x0, x1), max(x0, x1)
    mb.box('mat_glass', (lo, ya, hinge_z - 0.006), (hi, yb, hinge_z + 0.006), bevel=0.0)
    # steel channels top / bottom, rubber leading edge, hinge barrel
    mb.box('mat_steel', (lo - 0.0, ya - 0.012, hinge_z - 0.009), (hi + 0.0, ya + 0.010, hinge_z + 0.009), bevel=0.003)
    mb.box('mat_steel', (lo - 0.0, yb - 0.010, hinge_z - 0.009), (hi + 0.0, yb + 0.012, hinge_z + 0.009), bevel=0.003)
    tip_lo = hinge_x + dirx * (length - 0.013); tip_hi = hinge_x + dirx * length
    mb.box('mat_rubber', (min(tip_lo, tip_hi), ya - 0.012, hinge_z - 0.010), (max(tip_lo, tip_hi), yb + 0.012, hinge_z + 0.010), bevel=0.004)
    mb.cyl('mat_steel_polished', (hinge_x + dirx * 0.005, ya - 0.012, hinge_z), (hinge_x + dirx * 0.005, yb + 0.012, hinge_z), 0.0085, seg=12)
    return mb


@prop('gate_unit',
      desc='One ticket-gate lane module in modern London Underground style: two brushed-steel/charcoal pedestals with contactless '
           'reader, small display and ticket slot, glass flaps that close the lane, status lamp mast.',
      origin='floor_centre', front='passenger travel direction is -Z (entry end +Z with readers/lamps facing +Z, exit end -Z)',
      nodes={'body': 'static pedestals (steel, charcoal, readers, decals)',
             'flap_L': 'left glass flap (x<0). origin = hinge on pedestal inner face at x=-0.30,z=-0.10',
             'flap_R': 'right glass flap (x>0). origin = hinge on pedestal inner face at x=+0.30,z=-0.10',
             'lamp_go': 'emissive green arrow plate (own material mat_lamp_go), mast on +x pedestal, faces +Z',
             'lamp_stop': 'emissive red cross plate (own material mat_lamp_stop)',
             'col_ped_L/col_ped_R': 'convex collision boxes (StaticBody3D on import) - the lane between them stays free'},
      slots={'mat_endwrap': 'printed vinyl wrap on both pedestal entry ends (retarget for adverts)',
             'mat_lamp_go': 'emissive - toggle node visibility or emission_energy', 'mat_lamp_stop': 'emissive',
             'mat_gate_display': 'emissive small display next to the reader', 'mat_glass': 'flap glass (alpha blend)'},
      anim={'flap_L': {'closed_rotation_y_deg': 0.0, 'open_rotation_y_deg': 90.0, 'alt_open_scale': [0.04, 1, 1]},
            'flap_R': {'closed_rotation_y_deg': 0.0, 'open_rotation_y_deg': -90.0, 'alt_open_scale': [0.04, 1, 1]}},
      notes=['Flaps OPEN by swinging about the vertical hinge: flap_L rotation.y = +90 deg, flap_R rotation.y = -90 deg '
             '(each panel folds flat against its pedestal, towards the exit). Alternative visual: tween scale.x 1 -> 0.04 (panel '
             'collapses into the pedestal slot; extras alt_open_scale). A pure translation cannot hide a 0.29 m panel in a 0.16 m pedestal.',
             'Lane clear width 0.60 m (x -0.30..+0.30). Unit footprint 0.93 x 1.50 m: place lanes at 0.93 m pitch '
             '(neighbouring pedestals touch, giving a double-width dividing pedestal).'])
def gate_unit(P):
    LANE = 0.60
    _gate_mats(P)
    cx = LANE / 2 + PW / 2
    body = P.mb('body')
    pedestal(body, cx, +1, lane_lamp=True)
    pedestal(body, -cx, -1, lane_lamp=False)
    _lamps(P, cx)
    lf = (LANE - 0.02) / 2
    _glass_flap(P, 'flap_L', -LANE / 2, -0.10, +1, lf, 0.12, 0.90, {'open_rotation_y_deg': 90.0, 'alt_open_scale': [0.04, 1.0, 1.0]})
    _glass_flap(P, 'flap_R', +LANE / 2, -0.10, -1, lf, 0.12, 0.90, {'open_rotation_y_deg': -90.0, 'alt_open_scale': [0.04, 1.0, 1.0]})
    P.col_box('col_ped_R-convcolonly', (cx - PW / 2, 0, ZX), (cx + PW / 2, 1.0, ZE))
    P.col_box('col_ped_L-convcolonly', (-cx - PW / 2, 0, ZX), (-cx + PW / 2, 1.0, ZE))


@prop('gate_wide',
      desc='Accessible wide ticket-gate lane (0.90 m clear) with taller glass swing doors.',
      origin='floor_centre', front='passenger travel direction is -Z (entry end +Z)',
      nodes={'body': 'static pedestals', 'door_L': 'left glass swing door, origin = hinge at x=-0.45,z=-0.10',
             'door_R': 'right glass swing door, origin = hinge at x=+0.45,z=-0.10',
             'lamp_go': 'emissive green arrow', 'lamp_stop': 'emissive red cross', 'col_ped_L/col_ped_R': 'collision'},
      slots={'mat_endwrap': 'entry-end print', 'mat_lamp_go': 'emissive', 'mat_lamp_stop': 'emissive',
             'mat_glass': 'door glass', 'mat_gate_display': 'emissive'},
      anim={'door_L': {'open_rotation_y_deg': 90.0, 'alt_open_scale': [0.04, 1, 1]}, 'door_R': {'open_rotation_y_deg': -90.0, 'alt_open_scale': [0.04, 1, 1]}},
      notes=['Doors swing about the vertical hinge: door_L rotation.y = +90 deg, door_R = -90 deg (fold against pedestals, '
             'towards the exit). Lane clear width 0.90 m. Doors are 1.25 m tall.'])
def gate_wide(P):
    LANE = 0.90
    _gate_mats(P)
    cx = LANE / 2 + PW / 2
    body = P.mb('body')
    pedestal(body, cx, +1, lane_lamp=True, flap_h=(0.12, 1.28))
    pedestal(body, -cx, -1, lane_lamp=False, flap_h=(0.12, 1.28))
    _lamps(P, cx)
    lf = (LANE - 0.02) / 2
    for nm, side in (('door_L', -1), ('door_R', +1)):
        mb = _glass_flap(P, nm, side * LANE / 2, -0.10, -side, lf, 0.12, 1.28, {'open_rotation_y_deg': -90.0 * side, 'alt_open_scale': [0.04, 1.0, 1.0]})
        # push handle bar on the free end
        hx = side * LANE / 2 - side * (lf - 0.05)
        mb.cyl('mat_steel_polished', (hx, 0.86, -0.10 - 0.02), (hx, 1.14, -0.10 - 0.02), 0.009, seg=10)
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
