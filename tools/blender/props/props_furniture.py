"""Platform / concourse furniture: bench_platform, perch_seat, bin, bin_recycling, barrier_stanchion, wet_floor_sign, cleaning_trolley."""
import math, random
from propcore import prop
from propmesh import Xf, rrect_pts, fillet_poly, circle_pts, add, mul


def _decal_mat(P, name, tex, rough=0.4, **kw):
    spec = dict(c='decals/%s_c.png' % tex, rough=rough)
    spec.update(kw)
    P.mat(name, **spec)


# ============================================================================================ bench
@prop('bench_platform',
      desc='Platform bench: brushed-steel tube frames (two ends + centre arm-rest divider) with four seat slats and three back slats in worn timber.',
      origin='floor_centre', front='seat faces -Z (backrest on +Z side)',
      nodes={'body': 'whole bench', 'col_body-convcolonly': 'collision box'},
      slots={'mat_timber': 'seat / back slats'}, anim={}, mount_height=0.0,
      notes=['1.8 x 0.5 x 0.86 m. Seat height 0.47 m. Seats 2-3 (centre arm-rest divider).'])
def bench_platform(P):
    mb = P.mb('body')
    L = 1.80
    tr = 0.0175
    fx = [-0.855, 0.0, 0.855]
    for i, x in enumerate(fx):
        # front leg + armrest
        mb.tube('mat_steel', [(x, 0.012, -0.20), (x, 0.655, -0.20), (x, 0.685, -0.17), (x, 0.685, 0.10)], tr, seg=10, swap=True)
        mb.sphere('mat_steel', (x, 0.685, 0.10), tr, seg=10, rings=4)
        # rear leg + raked back post
        mb.tube('mat_steel', [(x, 0.012, 0.235), (x, 0.42, 0.205), (x, 0.85, 0.265)], tr, seg=10, swap=True)
        # seat rail
        mb.tube('mat_steel', [(x, 0.415, -0.20), (x, 0.415, 0.205)], tr * 0.9, seg=8, swap=True)
        # feet
        for z in (-0.20, 0.235):
            mb.cyl('mat_rubber', (x, 0.0, z), (x, 0.014, z), 0.030, seg=12, bevel=0.003)
    # stretchers
    mb.tube('mat_steel', [(fx[0], 0.16, 0.02), (fx[2], 0.16, 0.02)], 0.011, seg=8, swap=True)
    mb.tube('mat_steel', [(fx[0], 0.72, 0.245), (fx[2], 0.72, 0.245)], 0.009, seg=8, swap=True)
    rnd = random.Random(5)
    # seat slats (long axis x = timber grain)
    for k, z in enumerate((-0.155, -0.050, 0.055, 0.160)):
        mb.box('mat_timber', (-L / 2, 0.432, z - 0.045), (L / 2, 0.466, z + 0.045), bevel=0.005, off=(rnd.random(), rnd.random()))
    # back slats, raked 8 degrees
    for k, y in enumerate((0.58, 0.69, 0.80)):
        zc = 0.205 + (y - 0.42) * 0.143 + 0.02
        with mb.tf(Xf.T(0, y, zc) * Xf.R('x', 8.1)):
            mb.box('mat_timber', (-L / 2, -0.045, -0.016), (L / 2, 0.045, 0.016), bevel=0.005, off=(rnd.random(), rnd.random()))
    # bolts / caps on the slats
    for x in fx:
        for z in (-0.155, 0.160):
            mb.cyl('mat_steel_polished', (x, 0.466, z), (x, 0.470, z), 0.008, seg=8)
    P.col_box('col_body-convcolonly', (-L / 2, 0, -0.24), (L / 2, 0.90, 0.30))


# ============================================================================================ perch seat
@prop('perch_seat',
      desc='Slanted perch / lean seat: two padded black leatherette boards tilted 18 degrees on tube frames with floor feet.',
      origin='floor_centre', front='seat pad slopes down towards -Z (user leans facing -Z ... backs onto +Z)',
      nodes={'body': 'whole seat', 'col_body-convcolonly': 'collision box'},
      slots={'mat_rubber': 'pad covering'}, anim={}, mount_height=0.0,
      notes=['1.7 x 0.5 x 0.95 m. Pad height 0.68 (front) .. 0.82 (rear).'])
def perch_seat(P):
    mb = P.mb('body')
    tr = 0.018
    fx = [-0.80, 0.0, 0.80]
    for x in fx:
        # base foot (along z) and mast
        mb.tube('mat_steel', [(x, 0.018, -0.24), (x, 0.018, 0.22)], 0.016, seg=10, swap=True)
        mb.tube('mat_steel', [(x, 0.018, 0.10), (x, 0.62, 0.10), (x, 0.80, 0.16)], tr, seg=10, swap=True)
        mb.tube('mat_steel', [(x, 0.66, -0.16), (x, 0.66, 0.10)], 0.014, seg=8, swap=True)
        for z in (-0.24, 0.22):
            mb.cyl('mat_rubber', (x, 0.0, z), (x, 0.02, z), 0.030, seg=12, bevel=0.003)
    for cx in (-0.40, 0.40):
        with mb.tf(Xf.T(cx, 0.745, 0.0) * Xf.R('x', -18)):
            mb.box('mat_rubber', (-0.39, -0.035, -0.17), (0.39, 0.035, 0.17), bevel=0.02, seg=2)
            mb.box('mat_steel', (-0.36, -0.048, -0.10), (0.36, -0.03, 0.10), bevel=0.003)
    P.col_box('col_body-convcolonly', (-0.86, 0, -0.26), (0.86, 0.95, 0.24))


# ============================================================================================ bins
def _bin(P, recycling):
    mb = P.mb('body')
    P.mat('mat_sack', color=(0.86, 0.9, 0.92, 1), rough=0.16, alpha=0.30, double=True, spec=0.8)
    P.mat('mat_sack_blue', color=(0.55, 0.72, 0.95, 1), rough=0.16, alpha=0.32, double=True, spec=0.8)
    P.mat('mat_paper', color=(0.82, 0.80, 0.72, 1), rough=0.85)
    P.mat('mat_can', color=(0.75, 0.10, 0.08, 1), rough=0.3, metal=0.8)
    P.mat('mat_cup', color=(0.86, 0.84, 0.78, 1), rough=0.55)
    P.mat('mat_bottle', color=(0.55, 0.85, 0.95, 1), rough=0.1, alpha=0.5, double=True)
    P.mat('mat_newsprint', color=(0.62, 0.62, 0.6, 1), rough=0.9)
    P.mat('mat_crisp', color=(0.9, 0.45, 0.1, 1), rough=0.25, metal=0.6)
    P.mat('mat_can_b', color=(0.1, 0.25, 0.7, 1), rough=0.3, metal=0.8)
    P.mat('mat_cup_brown', color=(0.35, 0.2, 0.1, 1), rough=0.6)
    frame = 'mat_blue' if recycling else 'mat_steel'
    sack = 'mat_sack_blue' if recycling else 'mat_sack'
    hx, hz = 0.25, 0.20
    mb.box('mat_charcoal', (-hx, 0.0, -hz), (hx, 0.035, hz), bevel=0.008)
    px, pz = hx - 0.028, hz - 0.028
    for sx in (-1, 1):
        for sz in (-1, 1):
            mb.tube(frame, [(sx * px, 0.03, sz * pz), (sx * px, 0.885, sz * pz)], 0.012, seg=10, swap=True)
    for y in (0.885, 0.46):
        mb.tube(frame, [(-px, y, -pz), (px, y, -pz), (px, y, pz), (-px, y, pz)], 0.011, seg=8, closed=True, swap=True)
    mb.tube(frame, [(-px, 0.20, -pz), (px, 0.20, -pz), (px, 0.20, pz), (-px, 0.20, pz)], 0.009, seg=8, closed=True, swap=True)
    # the sack: open translucent bag hanging inside the frame, folded over the top rail
    sx0, sz0 = px - 0.012, pz - 0.012
    mb.box(sack, (-sx0, 0.06, -sz0), (sx0, 0.90, sz0), bevel=0.05, seg=2, skip=('+y',))
    mb.box(sack, (-px - 0.02, 0.84, -pz - 0.02), (px + 0.02, 0.905, pz + 0.02), bevel=0.0, skip=('+y', '-y'))
    # contents
    rnd = random.Random(7 if not recycling else 9)
    mats = (['mat_paper', 'mat_cup', 'mat_can', 'mat_newsprint', 'mat_bottle', 'mat_crisp', 'mat_can_b', 'mat_cup_brown']
            if not recycling else ['mat_paper', 'mat_bottle', 'mat_can', 'mat_newsprint', 'mat_can_b', 'mat_bottle'])
    y = 0.085
    for k in range(18):
        c = (rnd.uniform(-sx0 + 0.06, sx0 - 0.06), y + rnd.uniform(0, 0.03), rnd.uniform(-sz0 + 0.06, sz0 - 0.06))
        r = rnd.uniform(0.028, 0.055)
        mb.blob(rnd.choice(mats), c, r, rnd, seg=7, rings=4, jitter=0.32, scale=(rnd.uniform(0.8, 1.3), rnd.uniform(0.6, 1.1), rnd.uniform(0.8, 1.3)))
        y += rnd.uniform(0.02, 0.04)
    # a cup lying on top
    mb.cyl('mat_cup', (-0.06, y + 0.02, 0.02), (0.06, y - 0.02, -0.02), 0.032, seg=10, r1=0.024)
    if recycling:
        # top lid ring + label
        _decal_mat(P, 'mat_bin_label', 'bin_recycle', rough=0.35)
        mb.box('mat_blue', (-hx, 0.84, -hz), (hx, 0.905, hz), bevel=0.01, seg=1, skip=('+y', '-y'))
        mb.fdecal('mat_bin_label', 0.0, 0.70, 0.30, 0.15, -hz - 0.0015)
    else:
        mb.box('mat_black_plastic', (-hx + 0.02, 0.898, -hz + 0.02), (hx - 0.02, 0.905, hz - 0.02), skip=('+y', '-y'))
    P.col_box('col_body-convcolonly', (-hx, 0, -hz), (hx, 0.90, hz))


@prop('bin',
      desc='Steel-frame litter bin with a clear sack (translucent) holding crumpled litter.',
      origin='floor_centre', front='either long face', nodes={'body': 'frame + sack + contents'},
      slots={'mat_sack': 'translucent bag (alpha)', 'mat_steel': 'frame'}, anim={}, mount_height=0.0,
      notes=['0.50 x 0.40 x 0.90 m.'])
def bin_(P):
    _bin(P, False)


@prop('bin_recycling',
      desc='Recycling variant of the litter bin: blue painted frame, blue-tinted clear sack, green label.',
      origin='floor_centre', front='label faces -Z', nodes={'body': 'frame + sack + contents'},
      slots={'mat_sack_blue': 'translucent bag', 'mat_bin_label': 'label'}, anim={}, mount_height=0.0,
      notes=['0.50 x 0.40 x 0.90 m.'])
def bin_recycling(P):
    _bin(P, True)


# ============================================================================================ stanchion
@prop('barrier_stanchion',
      desc='Retractable belt crowd-control stanchion: polished-steel post on a heavy round base with a belt cassette and a hazard-stripe belt with clip.',
      origin='floor_centre', front='belt runs along +X',
      nodes={'body': 'post + base + cassette', 'belt': 'flat belt strip, origin at the cassette outlet (x=+0.045,y=0.925). Modelled 2.0 m long along +X: '
             'set scale.x = length/2.0', 'belt_hook': 'end clip; origin at the belt end - keep at x = 2.0*belt.scale.x relative to belt'},
      slots={'mat_belt': 'belt webbing'}, anim={'belt': {'scale_x': 'length/2.0'}, 'belt_hook': {'position_x': 'length'}}, mount_height=0.0,
      notes=['Post height 0.99 m, base diameter 0.34 m. Rotate the whole prop about Y to aim the belt.'])
def barrier_stanchion(P):
    _decal_mat(P, 'mat_belt', 'belt', rough=0.6)
    mb = P.mb('body')
    prof = [(0.0, 0.0), (0.168, 0.0), (0.172, 0.006), (0.172, 0.014), (0.16, 0.028), (0.10, 0.038), (0.05, 0.048), (0.0, 0.05)]
    mb.lathe('mat_steel_polished', prof, seg=32)
    mb.lathe('mat_rubber', [(0.0, -0.001), (0.166, -0.001), (0.166, 0.004)], seg=32)
    mb.cyl('mat_steel_polished', (0, 0.048, 0), (0, 0.90, 0), 0.0255, seg=20)
    mb.lathe('mat_steel_polished', [(0.0, 0.84), (0.048, 0.84), (0.050, 0.86), (0.050, 0.955), (0.042, 0.985), (0.0, 0.995)], seg=24)
    mb.cyl('mat_steel_polished', (0, 0.83, 0), (0, 0.845, 0), 0.034, seg=20)
    mb.box('mat_black_gloss', (0.044, 0.900, -0.032), (0.052, 0.950, 0.032), bevel=0.0)     # belt outlet slot
    # belt
    bm = P.mb('belt', pivot=(0.048, 0.925, 0.0), dirt=False, extras={'length': 2.0})
    bm.tile('mat_belt', 0.2, 0.05)
    bm.box('mat_belt', (0.048, 0.90, -0.0016), (2.048, 0.95, 0.0016), off=(0.0, 0.0))
    hm = P.mb('belt_hook', pivot=(2.048, 0.925, 0.0), dirt=False)
    hm.box('mat_steel_polished', (2.048, 0.895, -0.006), (2.075, 0.955, 0.006), bevel=0.003)
    hm.tube('mat_steel_polished', [(2.075, 0.925, 0.0), (2.11, 0.925, 0.0), (2.11, 0.90, 0.0)], 0.005, seg=8)
    P.col_box('col_body-convcolonly', (-0.17, 0, -0.17), (0.17, 1.0, 0.17))


# ============================================================================================ wet floor sign
@prop('wet_floor_sign',
      desc='Yellow folding A-frame "wet floor" sign with printed pictogram on both faces.',
      origin='floor_centre', front='front panel faces -Z, back panel +Z', nodes={'body': 'whole sign'},
      slots={'mat_wetfloor': 'printed decal (both faces)', 'mat_yellow': 'plastic'}, anim={}, mount_height=0.0,
      notes=['0.29 wide x 0.32 deep x 0.62 high.'])
def wet_floor_sign(P):
    _decal_mat(P, 'mat_wetfloor', 'wetfloor', rough=0.35)
    mb = P.mb('body')
    ang = 14.0
    Hh = 0.61
    for s in (1, -1):
        with mb.tf(Xf.T(0, Hh, 0) * Xf.R('x', ang * s)):
            mb.box('mat_yellow', (-0.145, -Hh + 0.0, -0.007), (0.145, 0.0, 0.007), bevel=0.005)
            zf = -0.0072 if s > 0 else 0.0072
            mb.fdecal('mat_wetfloor', 0.0, -Hh + 0.025, 0.262, 0.262 * 850 / 400, zf, facing=-1 if s > 0 else +1)
            mb.box('mat_black_plastic', (-0.05, -0.030, zf - 0.001), (0.05, -0.012, zf + 0.001))
            mb.box('mat_rubber', (-0.14, -Hh - 0.004, -0.010), (0.14, -Hh + 0.012, 0.010), bevel=0.003)
    mb.cyl('mat_steel_polished', (-0.148, Hh + 0.004, 0), (0.148, Hh + 0.004, 0), 0.008, seg=10)
    P.col_box('col_body-convcolonly', (-0.15, 0, -0.17), (0.15, 0.62, 0.17))


# ============================================================================================ cleaning trolley
@prop('cleaning_trolley',
      desc='Cleaner\'s janitorial trolley: grey plastic tray, yellow mop bucket with wringer, sprays and cloths, black rubbish sack on a frame, '
           'mop, push bar, four castors.',
      origin='floor_centre', front='push bar on +Z; work side faces -Z', nodes={'body': 'whole trolley'},
      slots={'mat_yellow': 'bucket', 'mat_grey': 'trolley plastic'}, anim={}, mount_height=0.0,
      notes=['1.10 x 0.58 x 1.30 m (mop tip). Push bar at z=+0.27.'])
def cleaning_trolley(P):
    P.mat('mat_bag', color=(0.02, 0.02, 0.025, 1), rough=0.28, spec=0.7)
    P.mat('mat_bottle_a', color=(0.1, 0.5, 0.9, 1), rough=0.25)
    P.mat('mat_bottle_b', color=(0.9, 0.85, 0.1, 1), rough=0.25)
    P.mat('mat_bottle_c', color=(0.85, 0.15, 0.15, 1), rough=0.25)
    P.mat('mat_cloth_r', color=(0.75, 0.1, 0.1, 1), rough=0.95)
    P.mat('mat_cloth_b', color=(0.1, 0.25, 0.75, 1), rough=0.95)
    P.mat('mat_mop', color=(0.78, 0.76, 0.70, 1), rough=0.95)
    mb = P.mb('body')
    rnd = random.Random(11)
    # tray platform + rim
    mb.box('mat_grey', (-0.50, 0.12, -0.26), (0.50, 0.17, 0.26), bevel=0.012, seg=1)
    for (a, b) in (((-0.50, -0.26), (0.50, -0.235)), ((-0.50, 0.235), (0.50, 0.26)), ((-0.50, -0.26), (-0.475, 0.26)), ((0.475, -0.26), (0.50, 0.26))):
        mb.box('mat_grey', (a[0], 0.17, a[1]), (b[0], 0.26, b[1]), bevel=0.006)
    # castors
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * 0.44, sz * 0.20
            mb.box('mat_steel_polished', (x - 0.03, 0.085, z - 0.025), (x + 0.03, 0.12, z + 0.025), bevel=0.003)
            mb.box('mat_steel_polished', (x - 0.028, 0.03, z - 0.004 - 0.02), (x - 0.024, 0.09, z + 0.024))
            mb.box('mat_steel_polished', (x + 0.024, 0.03, z - 0.004 - 0.02), (x + 0.028, 0.09, z + 0.024))
            with mb.tf(Xf.T(x, 0.05, z) * Xf.R('z', 90)):
                mb.cyl('mat_rubber', (0, -0.013, 0), (0, 0.013, 0), 0.05, seg=16, bevel=0.004)
    # bucket (right, +x) with wringer
    bx, bz = 0.27, -0.02
    mb.lathe('mat_yellow', [(0.0, 0.18), (0.120, 0.18), (0.168, 0.46), (0.176, 0.462), (0.176, 0.475), (0.166, 0.475), (0.160, 0.46), (0.112, 0.20), (0.0, 0.20)], seg=28, cx=bx, cz=bz)
    mb.tube('mat_steel_polished', [(bx - 0.17, 0.46, bz), (bx - 0.10, 0.62, bz), (bx + 0.10, 0.62, bz), (bx + 0.17, 0.46, bz)], 0.006, seg=8)
    mb.box('mat_blue', (bx - 0.10, 0.475, bz - 0.13), (bx + 0.10, 0.535, bz + 0.13), bevel=0.012, seg=1)   # wringer press
    mb.box('mat_blue', (bx - 0.07, 0.535, bz - 0.11), (bx + 0.07, 0.575, bz + 0.11), bevel=0.01, seg=1)
    # mop leaning in the bucket
    mb.tube('mat_steel_polished', [(bx - 0.03, 0.27, bz + 0.03), (bx + 0.13, 1.26, bz + 0.20)], 0.0115, seg=10)
    mb.cyl('mat_rubber', (bx + 0.13, 1.16, bz + 0.20), (bx + 0.13, 1.26, bz + 0.20), 0.016, seg=10)
    with mb.tf(Xf.T(bx - 0.03, 0.30, bz + 0.03)):
        mb.lathe('mat_mop', [(0.0, -0.10), (0.05, -0.10), (0.055, -0.04), (0.035, 0.05), (0.0, 0.05)], seg=12)
    # centre: bottles + cloths on the tray
    for k, (m, x) in enumerate((('mat_bottle_a', -0.12), ('mat_bottle_b', -0.04), ('mat_bottle_c', 0.04), ('mat_bottle_a', 0.10))):
        z = -0.10 + (k % 2) * 0.10
        mb.lathe(m, [(0.0, 0.17), (0.034, 0.17), (0.036, 0.19), (0.036, 0.34), (0.026, 0.37), (0.012, 0.385), (0.012, 0.40), (0.0, 0.40)], seg=12, cx=x, cz=z)
        mb.box('mat_black_plastic', (x - 0.012, 0.395, z - 0.05), (x + 0.012, 0.425, z + 0.012), bevel=0.004)
    for k, m in enumerate(('mat_cloth_r', 'mat_cloth_b', 'mat_cloth_r')):
        mb.box(m, (-0.20, 0.17 + k * 0.03, 0.10 - k * 0.01), (-0.02, 0.20 + k * 0.03, 0.22 - k * 0.01), bevel=0.008, off=(rnd.random(), rnd.random()))
    # rubbish sack frame + bag (left, -x)
    mb.tube('mat_steel_polished', [(-0.47, 0.26, -0.15), (-0.47, 0.90, -0.15), (-0.47, 0.90, 0.15), (-0.47, 0.26, 0.15)], 0.008, seg=8)
    mb.tube('mat_steel_polished', [(-0.28, 0.26, -0.15), (-0.28, 0.90, -0.15), (-0.28, 0.90, 0.15), (-0.28, 0.26, 0.15)], 0.008, seg=8)
    bag = [(0.0, 0.30), (0.09, 0.30), (0.16, 0.36), (0.205, 0.50), (0.20, 0.66), (0.14, 0.80), (0.06, 0.885), (0.025, 0.93), (0.0, 0.935)]
    with mb.tf(Xf.T(-0.375, 0.0, 0.0) * Xf.S(0.55, 1.0, 0.85)):
        mb.lathe('mat_bag', bag, seg=14)
    mb.blob('mat_bag', (-0.375, 0.945, 0.0), 0.03, rnd, seg=8, rings=4, jitter=0.2)
    mb.box('mat_steel_polished', (-0.42, 0.90, -0.02), (-0.33, 0.915, 0.02))
    # push bar
    for sx in (-1, 1):
        mb.tube('mat_steel_polished', [(sx * 0.46, 0.17, 0.25), (sx * 0.46, 1.00, 0.27)], 0.014, seg=10)
    mb.tube('mat_steel_polished', [(-0.46, 1.0, 0.27), (0.46, 1.0, 0.27)], 0.014, seg=10)
    mb.cyl('mat_rubber', (-0.30, 1.0, 0.27), (0.30, 1.0, 0.27), 0.019, seg=12, bevel=0.003)
    # caution card
    P.col_box('col_body-convcolonly', (-0.55, 0, -0.30), (0.55, 1.0, 0.30))
