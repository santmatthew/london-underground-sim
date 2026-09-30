"""Ticket-hall props A: ticket_machine_mfm, ticket_machine_tvm, tickets_sign, assistance_booth, crowd_barrier.
(the E2 gates gate_unit / gate_wide live in props_gates.py; textures come from proptex_hall_a.py)

Modelled from the reference photos in build/refs_dress/halls (SPEC.md sec 1, 3): the multi-fare machine as seen in a wall bay
(StaySafe-TicketSales, Cockfosters, Chiswick Park, Wood Lane), the glass-and-blue-steel Assistance cubicle (Morden, Waterloo, Whitechapel)
and the galvanised pedestrian barrier (Arnos Grove, Kentish Town)."""
import math
import propcore
from propcore import prop
from propmesh import Xf, rrect_pts, fillet_poly

# semi-metallic brushed steel (the game has no reflection probes, fully metallic steel would render black)
propcore.TILES['mat_hall_steel'] = (0.5, 0.5)
propcore.DIRTY.add('mat_hall_steel')


def _decal(P, name, tex, emit=None, rough=0.4, **kw):
    spec = dict(c='decals/%s_c.png' % tex, rough=rough)
    if emit:
        spec.update(emit=(1, 1, 1), emit_tex=True, emit_strength=emit, spec=0.7)
    spec.update(kw)
    P.mat(name, **spec)


def _steel_mats(P):
    P.mat('mat_hall_steel', c='tile/steel_c.jpg', n='tile/steel_n.jpg', rough=0.42, metal=0.35, spec=0.6)
    P.mat('mat_hall_chrome', color=(0.78, 0.79, 0.81, 1), rough=0.28, metal=0.5, spec=0.6)


# ============================================================================================ ticket machines
def _machine(P, W, big):
    """multi-fare machine (big) or narrow card-only machine. Origin: floor, centre, FRONT-PLATE plane (z=0); body 0.35 m toward +Z.
    All positions below are in u = viewer's-right coordinate (x = -u) because the front faces -Z."""
    _steel_mats(P)
    _decal(P, 'mat_tm_head', 'hall_a_mfm_head' if big else 'hall_a_tvm_head', rough=0.5)
    _decal(P, 'mat_tm_led', 'hall_a_led' if big else 'hall_a_led_small', emit=2.2, rough=0.3)
    _decal(P, 'mat_screen', 'hall_a_mfm_ui', emit=0.9, rough=0.08, spec=0.7)
    _decal(P, 'mat_tm_pin', 'hall_a_mfm_pin', rough=0.45)
    _decal(P, 'mat_tm_notice', 'hall_a_mfm_notice' if big else 'hall_a_tvm_notice', rough=0.4)
    _decal(P, 'mat_tm_slots', 'hall_a_mfm_slots', rough=0.45)
    _decal(P, 'mat_tm_band', 'hall_a_mfm_band', rough=0.45)
    P.mat('mat_reader', c='decals/hall_a_disc_c.png', emit=(1, 1, 1), emit_tex=True, emit_strength=0.35, rough=0.4, spec=0.35)
    P.mat('mat_tm_red', color=(0.75, 0.05, 0.06, 1), rough=0.35)
    hw = W / 2
    mb = P.mb('body')
    ZF = -0.014                                    # fascia face

    def X(u):
        return -u

    def bx(mat, u0, u1, y0, y1, z0, z1, **kw):
        mb.box(mat, (X(u1), y0, z0), (X(u0), y1, z1), **kw)

    def dq(mat, uc, y0, w, h, z):
        mb.fdecal(mat, X(uc), y0, w, h, z, facing=-1)

    # ---- housing, plinth, stainless fascia block
    bx('mat_charcoal', -hw + 0.012, hw - 0.012, 0.05, 1.37, 0.0, 0.35, bevel=0.008)
    bx('mat_charcoal', -hw, hw, 0.04, 0.47, 0.004, 0.10, bevel=0.005)                       # dark plinth ('cash box' section)
    bx('mat_hall_steel', -hw, hw, 0.46, 1.36, ZF, 0.10, bevel=0.006)
    # ---- glossy black panel behind the screen and disc, diagonal stainless edge on its right (as on the photographed machines)
    if big:
        poly = [(X(-hw + 0.012), 0.692), (X(0.155), 0.692), (X(0.075), 0.985), (X(-hw + 0.012), 0.985)]
    else:
        poly = [(X(-hw + 0.012), 0.712), (X(0.005), 0.712), (X(-0.005), 0.975), (X(-hw + 0.012), 0.975)]
    mb.prism('mat_black_plastic', poly, 'z', ZF - 0.0016, ZF, bevel=0.0)
    # ---- black head panel with louvres + zone label (decal, flush)
    hh = 0.15 if big else W * 170 / 512
    dq('mat_tm_head', 0.0, 1.10, W - 0.02, min(hh, 0.152) if big else hh, ZF - 0.0005)
    # ---- amber status strip in a dark recess
    sw = 0.31 if big else 0.20
    su = -0.03 if big else 0.0
    bx('mat_black_gloss', su - sw / 2 - 0.02, su + sw / 2 + 0.02, 1.272, 1.334, ZF - 0.0009, ZF, bevel=0.0)
    dq('mat_tm_led', su, 1.2835, sw, sw / (8.0 if big else 4.0), ZF - 0.0011)
    # ---- printed band on the stainless above the screen
    dq('mat_tm_band', 0.14 if big else 0.0, 1.005, 0.26 if big else 0.20, 0.26 / 8.0 if big else 0.20 / 8.0, ZF - 0.0005)

    # ---- screen bay
    if big:
        s_u0, s_u1, s_y0, s_y1 = -0.395, -0.05, 0.715, 0.965
        sc_w = 0.255
    else:
        s_u0, s_u1, s_y0, s_y1 = -0.235, -0.015, 0.735, 0.955
        sc_w = 0.170
    bx('mat_black_plastic', s_u0, s_u1, s_y0, s_y1, ZF - 0.020, ZF + 0.004, bevel=0.007)
    scu = (s_u0 + s_u1) / 2
    sc_h = sc_w * 480 / 640
    dq('mat_screen', scu, (s_y0 + s_y1) / 2 - sc_h / 2, sc_w, sc_h, ZF - 0.0206)
    # ---- card / PIN block
    p_w = 0.16 if big else 0.13
    p_u1 = 0.385 if big else 0.215
    p_u0 = p_u1 - p_w
    bx('mat_black_plastic', p_u0, p_u1, 0.735, 0.945, ZF - 0.034, ZF + 0.004, bevel=0.006)
    dq('mat_tm_pin', (p_u0 + p_u1) / 2, 0.762, p_w - 0.012, p_w - 0.012, ZF - 0.0345)
    # ---- yellow contactless disc: beside the screen on the big machine, low right on the small one
    du, dy = (0.03, 0.765) if big else (0.135, 0.555)
    with mb.tf(Xf.T(X(du), dy, ZF) * Xf.R('x', -90)):
        mb.tile('mat_reader', -0.095, 0.095)
        mb.lathe('mat_black_gloss', [(0.0, 0.0), (0.0585, 0.0), (0.0585, 0.0075), (0.0, 0.0075)], seg=22)
        mb.lathe('mat_reader', [(0.0475, 0.0079), (0.0, 0.0079)], seg=22)
    # ---- delivery hopper + note / coin slots + labels (lower stainless section)
    hu0, hu1 = (-0.075, 0.115) if big else (-0.215, -0.04)
    bx('mat_black_gloss', hu0, hu1, 0.522, 0.592, ZF - 0.0012, ZF, bevel=0.0)
    bx('mat_hall_chrome', hu0 - 0.008, hu1 + 0.008, 0.512, 0.522, ZF - 0.024, ZF + 0.002, bevel=0.003)    # lip
    bx('mat_black_gloss', hu0 + 0.01, hu1 - 0.01, 0.526, 0.532, ZF - 0.0016, ZF - 0.0012)
    if big:
        bx('mat_hall_chrome', 0.15, 0.30, 0.585, 0.675, ZF - 0.006, ZF + 0.002, bevel=0.003)
        bx('mat_black_gloss', 0.17, 0.28, 0.640, 0.652, ZF - 0.0068, ZF - 0.006)
        bx('mat_black_gloss', 0.17, 0.28, 0.603, 0.611, ZF - 0.0068, ZF - 0.006)
        mb.cyl('mat_tm_red', (X(0.325), 0.63, ZF), (X(0.325), 0.63, ZF - 0.010), 0.011, seg=12)
        dq('mat_tm_slots', 0.21, 0.500, 0.14, 0.035, ZF - 0.0006)
    else:
        bx('mat_hall_chrome', -0.02, 0.055, 0.60, 0.665, ZF - 0.006, ZF + 0.002, bevel=0.003)
        bx('mat_black_gloss', -0.005, 0.04, 0.62, 0.63, ZF - 0.0068, ZF - 0.006)
        dq('mat_tm_slots', 0.125, 0.478, 0.12, 0.030, ZF - 0.0006)

    # ---- notice header above the machine (blue board) + trim
    bx('mat_charcoal', -hw, hw, 1.36, 1.405, -0.006, 0.06, bevel=0.003)
    bx('mat_blue', -hw, hw, 1.402, 1.402 + (0.150 if big else W * 170 / 512), -0.024, 0.03, bevel=0.004)
    nh = 0.146 if big else (W - 0.02) * 170 / 512
    dq('mat_tm_notice', 0.0, 1.404, W - 0.02, nh, -0.0245)
    top = 1.402 + (0.150 if big else W * 170 / 512)
    # ---- side vents on the housing (visible only if the bay is open)
    for k in range(5):
        for sx in (-1, 1):
            xx = sx * (hw - 0.012)
            mb.box('mat_black_plastic', (min(xx, xx + sx * 0.0012), 0.55 + k * 0.03, 0.08), (max(xx, xx + sx * 0.0012), 0.562 + k * 0.03, 0.26))
    P.col_box('col_body-convcolonly', (-hw, 0.0, -0.05), (hw, top, 0.35))
    return top


@prop('ticket_machine_mfm',
      desc='Multi-fare ticket machine as seen in a wall bay: brushed-stainless front frame around a charcoal fascia, amber dot-matrix status strip, '
           'black louvred head with zone label, 15-inch class touchscreen, yellow 95 mm contactless disc, card / PIN block, note and coin slots, '
           'ticket delivery hopper, dark plinth and a blue notice strip above.',
      origin='floor_at_front_plane', front='fascia faces -Z; the front-plate plane is z=0 and the 0.35 m deep housing extends toward +Z (put it in a recess or in front of a wall with its back at z=+0.35)',
      nodes={'body': 'housing, fascia, screen, disc, hopper, notice board', 'col_body-convcolonly': 'collision box (whole machine)'},
      slots={'mat_screen': 'emissive touch screen (640x480 placeholder UI) - retarget to a ViewportTexture / any texture',
             'mat_tm_notice': 'blue notice strip above the machine', 'mat_tm_head': 'louvre + zone label print', 'mat_tm_led': 'emissive status strip',
             'mat_reader': 'yellow contactless pad'},
      anim={}, mount_height=0.0,
      notes=['0.90 wide x 1.55 high (notice strip top) x 0.35 deep (+0.036 of protruding hardware). Stainless section top 1.36 m, plinth 0.04..0.46 m, '
             'screen centre 0.84 m, yellow disc centre 0.765 m, hopper 0.52..0.59 m. Real machines carry a "Tickets" sign band on the wall above: use tickets_sign.'])
def ticket_machine_mfm(P):
    _machine(P, 0.90, True)


@prop('ticket_machine_tvm',
      desc='Narrow (0.50 m) card-only ticket / pay-as-you-go top-up machine: same language as the multi-fare machine, smaller screen, '
           'yellow contactless disc low on the right beside the delivery hopper, no note slot.',
      origin='floor_at_front_plane', front='fascia faces -Z; front-plate plane z=0, housing extends 0.35 m toward +Z',
      nodes={'body': 'housing, fascia, screen, disc, hopper, notice board', 'col_body-convcolonly': 'collision box (whole machine)'},
      slots={'mat_screen': 'emissive touch screen', 'mat_tm_notice': 'blue notice strip', 'mat_tm_head': 'louvre + zone label print',
             'mat_tm_led': 'emissive status strip', 'mat_reader': 'yellow contactless pad'},
      anim={}, mount_height=0.0,
      notes=['0.50 wide x 1.57 high x 0.35 deep. Pair it with ticket_machine_mfm 0.02 m apart (as at Cockfosters / StaySafe photo).'])
def ticket_machine_tvm(P):
    _machine(P, 0.50, False)


# ============================================================================================ TICKETS sign band
@prop('tickets_sign',
      desc='Lit "TICKETS" sign band above a machine bay: white lettering with ticket and card pictograms on TfL blue, emissive, in a stainless '
           'edged box with a wall-mounting flange.',
      origin='wall_back_bottom_centre', front='sign faces -Z; back plane (wall) at z=0, object extends toward -Z',
      nodes={'body': 'box, flange, print', 'col_body-convcolonly': 'collision box (thin)'},
      slots={'mat_sign': 'emissive print (1536x211)'}, anim={}, mount_height=1.62,
      notes=['1.66 x 0.26 x 0.075 m including the flange; the lit face is 1.60 x 0.22. Recommended bottom edge 1.62 m (just above the 1.55 m notice strip '
             'of ticket_machine_mfm / _tvm). Machines 0.9 + 0.02 + 0.5 m wide fit under one sign.'])
def tickets_sign(P):
    _steel_mats(P)
    _decal(P, 'mat_sign', 'hall_a_tickets_sign', emit=1.25, rough=0.35, spec=0.6)
    mb = P.mb('body')
    W, H = 1.60, 0.22
    # wall flange (thin plate slightly larger than the box) + box + lit face
    mb.box('mat_hall_steel', (-0.83, 0.0, -0.010), (0.83, 0.26, 0.0), bevel=0.004)
    mb.box('mat_hall_steel', (-0.81, 0.02, -0.075), (0.81, 0.24, -0.010), bevel=0.006)
    # lit face inset in the box front
    mb.fdecal('mat_sign', 0.0, 0.02 + 0.01, W, H - 0.0, -0.0757)
    # steel border strips around the lit face
    mb.box('mat_hall_steel', (-0.81, 0.02, -0.0765), (0.81, 0.03, -0.0745), bevel=0.0)
    mb.box('mat_hall_steel', (-0.81, 0.23, -0.0765), (0.81, 0.24, -0.0745), bevel=0.0)
    mb.box('mat_hall_steel', (-0.81, 0.03, -0.0765), (-0.80, 0.23, -0.0745), bevel=0.0)
    mb.box('mat_hall_steel', (0.80, 0.03, -0.0765), (0.81, 0.23, -0.0745), bevel=0.0)
    P.col_box('col_body-convcolonly', (-0.83, 0.0, -0.075), (0.83, 0.26, 0.0))


# ============================================================================================ assistance booth
@prop('assistance_booth',
      desc='Assistance cubicle at the end of a gateline: blue painted-steel lower body, stainless sill, glazed upper walls in dark steel posts, '
           'a lit "Assistance" fascia sign on the front and both sides, flat grey roof, door frame on the +x side, monitor and stool inside.',
      origin='floor_centre', front='the counter window and the "Assistance" sign face -Z; the door is on the +x side',
      nodes={'body': 'whole booth (glass and sign are materials of the same mesh)', 'col_body-convcolonly': 'collision box'},
      slots={'mat_assist_sign': 'emissive sign print (1024x160)', 'mat_glass': 'glazing (alpha)', 'mat_blue': 'painted steel'},
      anim={}, mount_height=0.0,
      notes=['1.20 x 1.20 x 2.20 m (roof 2.21 m). Blue base 0.08..0.95 m, glazing 0.97..1.98 m, sign band 1.98..2.16 m.'])
def assistance_booth(P):
    _steel_mats(P)
    _decal(P, 'mat_assist_sign', 'hall_a_assist_sign', emit=1.2, rough=0.35, spec=0.6)
    P.mat('mat_booth_light', color=(0.95, 0.96, 1.0, 1), emit=(1.0, 1.0, 1.0), emit_strength=2.2, rough=0.5)
    mb = P.mb('body')
    h = 0.60
    # base: dark kick, blue painted body, stainless sill
    mb.box('mat_charcoal', (-h, 0.0, -h), (h, 0.09, h), bevel=0.008)
    mb.box('mat_blue', (-h + 0.004, 0.08, -h + 0.004), (h - 0.004, 0.955, h - 0.004), bevel=0.012, seg=2)
    mb.box('mat_hall_steel', (-h - 0.012, 0.950, -h - 0.012), (h + 0.012, 0.972, h + 0.012), bevel=0.006)
    # counter ledge and speak-through grille on the front window
    mb.box('mat_hall_steel', (-0.40, 0.972, -h - 0.10), (0.40, 0.992, -h + 0.005), bevel=0.006)
    mb.box('mat_black_plastic', (-0.10, 1.10, -h - 0.004), (0.10, 1.19, -h + 0.006))
    for k in range(5):
        mb.box('mat_hall_chrome', (-0.085 + k * 0.0425, 1.115, -h - 0.006), (-0.075 + k * 0.0425, 1.175, -h - 0.004))
    # glazing: four panes, corner posts
    g0, g1 = 0.972, 1.985
    e = h - 0.020
    mb.box('mat_glass', (-e, g0, -e), (e, g1, -e + 0.006), bevel=0.0)
    mb.box('mat_glass', (-e, g0, e - 0.006), (e, g1, e), bevel=0.0)
    mb.box('mat_glass', (-e, g0, -e), (-e + 0.006, g1, e), bevel=0.0)
    mb.box('mat_glass', (e - 0.006, g0, -e), (e, g1, e), bevel=0.0)
    for sx in (-1, 1):
        for sz in (-1, 1):
            mb.box('mat_charcoal', (sx * h - 0.028, g0, sz * h - 0.028), (sx * h + 0.028, g1 + 0.002, sz * h + 0.028), bevel=0.004)
    # rails top and mid (thin) so the glass reads as framed panes
    for y in (g0, 1.50, g1 - 0.02):
        for (a, b) in (((-h, -h - 0.004), (h, -h + 0.024)), ((-h, h - 0.024), (h, h + 0.004))):
            mb.box('mat_charcoal', (a[0], y, a[1]), (b[0], y + 0.024, b[1]), bevel=0.0)
        for (a, b) in (((-h - 0.004, -h), (-h + 0.024, h)), ((h - 0.024, -h), (h + 0.004, h))):
            mb.box('mat_charcoal', (a[0], y, a[1]), (b[0], y + 0.024, b[1]), bevel=0.0)
    # door on the +x side: frame + handle
    for zz in (-0.28, 0.28):
        mb.box('mat_charcoal', (h - 0.032, g0, zz - 0.016), (h + 0.010, g1 - 0.03, zz + 0.016), bevel=0.003)
    mb.box('mat_charcoal', (h - 0.032, 1.93, -0.28), (h + 0.010, 1.965, 0.28), bevel=0.0)
    mb.cyl('mat_hall_chrome', (h + 0.014, 1.02, 0.22), (h + 0.014, 1.30, 0.22), 0.011, seg=8)
    mb.cyl('mat_hall_chrome', (h + 0.002, 1.05, 0.22), (h + 0.014, 1.05, 0.22), 0.007, seg=8)
    mb.cyl('mat_hall_chrome', (h + 0.002, 1.27, 0.22), (h + 0.014, 1.27, 0.22), 0.007, seg=8)
    # sign fascia band (blue box) with lit prints front / both sides
    mb.box('mat_blue', (-h - 0.006, 1.985, -h - 0.006), (h + 0.006, 2.155, h + 0.006), bevel=0.006)
    sw, sh = 1.10, 1.10 * 160 / 1024
    mb.fdecal('mat_assist_sign', 0.0, 1.985 + (0.170 - sh) / 2, sw, sh, -h - 0.0068, facing=-1)
    for sgn in (-1, 1):
        # side prints: viewed from outside the +x / -x face
        xf = sgn * (h + 0.0068)
        z0 = sgn * sw / 2                              # viewer's-right side: for +x face viewer looks -x: right = -z ... solved with hint
        if sgn > 0:
            mb.qdecal('mat_assist_sign', (xf, 1.985 + (0.170 - sh) / 2, sw / 2), (0, 0, -1), (0, 1, 0), sw, sh, hint=(1, 0, 0))
        else:
            mb.qdecal('mat_assist_sign', (xf, 1.985 + (0.170 - sh) / 2, -sw / 2), (0, 0, 1), (0, 1, 0), sw, sh, hint=(-1, 0, 0))
    # roof slab + light strip under it
    mb.box('mat_hall_steel', (-h - 0.05, 2.155, -h - 0.05), (h + 0.05, 2.205, h + 0.05), bevel=0.010)
    mb.box('mat_booth_light', (-0.35, 1.965, -0.10), (0.35, 1.978, 0.10))
    # interior: monitor on a stand, stool, wall phone
    mb.box('mat_black_gloss', (-0.20, 1.14, 0.30), (0.20, 1.40, 0.335), bevel=0.006)
    mb.box('mat_charcoal', (-0.03, 0.99, 0.32), (0.03, 1.15, 0.36), bevel=0.0)
    mb.cyl('mat_black_plastic', (-0.30, 0.55, -0.05), (-0.30, 0.60, -0.05), 0.15, seg=14)
    mb.box('mat_hall_steel', (-0.315, 0.10, -0.065), (-0.285, 0.55, -0.035))
    mb.cyl('mat_black_plastic', (0.32, 1.30, 0.55), (0.32, 1.48, 0.55), 0.03, seg=8)
    P.col_box('col_body-convcolonly', (-h - 0.01, 0.0, -h - 0.01), (h + 0.01, 2.21, h + 0.01))


# ============================================================================================ crowd barrier
@prop('crowd_barrier',
      desc='Galvanised steel pedestrian crowd barrier (Heras / pedestrian-barrier style): round-tube frame, bowed-free vertical infill bars, '
           'flat-bar feet at both ends, coupling hooks; used on the unpaid side of gatelines to channel queues.',
      origin='floor_centre', front='either long face; symmetric (long axis X, feet run along Z)',
      nodes={'body': 'whole panel', 'col_body-convcolonly': 'collision box (panel plane, feet excluded)'},
      slots={'mat_galv': 'galvanised steel'}, anim={}, mount_height=0.0,
      notes=['2.00 m long (x) x 1.10 m high, feet 0.60 m across (z). Place end to end at 2.0 m pitch; rotate about Y to angle a run.'])
def crowd_barrier(P):
    P.mat('mat_galv', color=(0.52, 0.54, 0.55, 1), rough=0.5, metal=0.3, spec=0.5)
    P.mat('mat_galv_rubber', color=(0.02, 0.02, 0.022, 1), rough=0.8)
    mb = P.mb('body', dirt=False)
    L, H = 2.0, 1.10
    hl = L / 2
    ur = 0.0185
    for sx in (-1, 1):
        x = sx * (hl - 0.045)
        mb.cyl('mat_galv', (x, 0.03, 0.0), (x, H - 0.01, 0.0), ur, seg=10)
        mb.sphere('mat_galv', (x, H - 0.01, 0.0), ur, seg=10, rings=3)
        # flat-bar foot across the panel
        mb.box('mat_galv', (x - 0.022, 0.0, -0.30), (x + 0.022, 0.028, 0.30), bevel=0.003)
        for z in (-0.30, 0.30):
            mb.box('mat_galv_rubber', (x - 0.024, 0.0, z - 0.02 if z < 0 else z - 0.03), (x + 0.024, 0.032, z + 0.03 if z > 0 else z + 0.02), bevel=0.003)
        # coupling hook at the top outer end
        mb.tube('mat_galv', [(sx * hl, H - 0.16, 0.0), (sx * (hl + 0.03), H - 0.16, 0.0), (sx * (hl + 0.03), H - 0.25, 0.0), (sx * hl, H - 0.25, 0.0)], 0.008, seg=6)
    # top, second and bottom rails
    xa, xb = -hl + 0.045, hl - 0.045
    for y, r in ((H - 0.02, 0.0165), (0.12, 0.0140)):
        mb.tube('mat_galv', [(xa, y, 0.0), (xb, y, 0.0)], r, seg=10)
    # vertical infill bars
    n = 17
    for k in range(n):
        x = xa + 0.04 + (xb - xa - 0.08) * k / (n - 1)
        mb.cyl('mat_galv', (x, 0.12, 0.0), (x, H - 0.02, 0.0), 0.0065, seg=6, caps=False)
    # diagonal-free: a mid rail at 0.60 m
    mb.tube('mat_galv', [(xa, 0.62, 0.0), (xb, 0.62, 0.0)], 0.009, seg=8)
    P.col_box('col_body-convcolonly', (-hl, 0.0, -0.05), (hl, H, 0.05))
