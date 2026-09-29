"""Machines and wall / ceiling furniture: ticket_machine, info_totem, journey_planner_screen, help_point, fire_cabinet,
cctv_dome, pa_speaker, clock, emergency_stop_plunger, signal_lamp, lift_doors, platform_edge_marker."""
import math
from propcore import prop
from propmesh import Xf, rrect_pts, fillet_poly, circle_pts, add, mul


def _decal_mat(P, name, tex, emit=None, rough=0.4, **kw):
    spec = dict(c='decals/%s_c.png' % tex, rough=rough)
    if emit:
        spec.update(emit=(1, 1, 1), emit_tex=True, emit_strength=emit, spec=0.7)
    spec.update(kw)
    P.mat(name, **spec)


def _reader(mb, r=0.045):
    """contactless reader (bezel + yellow ring + pad) in the current local frame (axis +Y outwards)"""
    mb.lathe('mat_steel_polished', [(r + 0.008, 0.0), (r + 0.008, 0.0045), (r, 0.0045), (r, 0.0)], seg=28)
    mb.lathe('mat_yellow', [(r, 0.0), (r, 0.0038), (r - 0.0075, 0.0038), (r - 0.0075, 0.0)], seg=28)
    mb.lathe('mat_gate_reader', [(r - 0.0075, 0.0012), (0.0, 0.0012)], seg=28)


# ============================================================================================ ticket machine
@prop('ticket_machine',
      desc='TfL-style self-service ticket machine: blue enamel cabinet, white header, touch screen, contactless reader, card slot, '
           'coin slot, note acceptor, delivery tray and printed instruction panel.',
      origin='floor_centre', front='front (screen side) faces -Z',
      nodes={'body': 'cabinet, hardware', 'col_body-convcolonly': 'collision box'},
      slots={'mat_screen': 'emissive touch screen (1024x880 placeholder UI) - retarget to a ViewportTexture / any texture',
             'mat_ticket_header': 'printed header sign', 'mat_instructions': 'printed how-to panel',
             'mat_slots_label': 'printed label strip above the slots'},
      anim={}, mount_height=0.0)
def ticket_machine(P):
    _decal_mat(P, 'mat_screen', 'ticket_ui', emit=0.85, rough=0.08)
    _decal_mat(P, 'mat_ticket_header', 'ticket_header', rough=0.35)
    _decal_mat(P, 'mat_instructions', 'ticket_instr', rough=0.35)
    _decal_mat(P, 'mat_slots_label', 'ticket_slots', rough=0.4)
    P.mat('mat_gate_reader', c='decals/gate_reader_c.png', rough=0.22, spec=0.6)
    P.mat('mat_led_amber', color=(1, 0.6, 0.1, 1), emit=(1.0, 0.55, 0.05), emit_strength=3.0, rough=0.3)
    P.mat('mat_led_green', color=(0.1, 0.9, 0.3, 1), emit=(0.1, 1.0, 0.3), emit_strength=3.0, rough=0.3)
    mb = P.mb('body')
    W, D, Hh = 0.75, 0.45, 1.70
    hx, hz = W / 2, D / 2
    zf = -hz
    mb.box('mat_charcoal', (-hx + 0.012, 0, -hz + 0.012), (hx - 0.012, 0.085, hz - 0.012), bevel=0.006)
    mb.box('mat_blue', (-hx, 0.08, -hz), (hx, 1.685, hz), bevel=0.016, seg=2)
    mb.box('mat_white', (-hx - 0.003, 1.68, -hz - 0.003), (hx + 0.003, 1.70, hz + 0.003), bevel=0.008)
    # white bands on the sides + header sign
    for sx in (-1, 1):
        x = sx * (hx + 0.001)
        mb.box('mat_white', (min(x, x + sx * 0.002), 1.545, -hz + 0.02), (max(x, x + sx * 0.002), 1.665, hz - 0.02))
    mb.fdecal('mat_ticket_header', 0.0, 1.548, 0.66, 0.66 * 186 / 1024, zf - 0.0015)
    # screen
    mb.box('mat_black_gloss', (-0.335, 1.065, zf - 0.014), (0.115, 1.495, zf + 0.004), bevel=0.007)
    sw = 0.41
    mb.fdecal('mat_screen', -0.11, 1.105, sw, sw * 880 / 1024, zf - 0.0143)
    # right column: contactless reader, chip slot, help button, speaker
    with mb.tf(Xf.T(0.245, 1.385, zf) * Xf.R('x', -90)):
        mb.tile('mat_gate_reader', -0.106, 0.106)
        _reader(mb, 0.046)
    mb.box('mat_charcoal', (0.16, 1.225, zf - 0.010), (0.33, 1.305, zf + 0.002), bevel=0.004)
    mb.box('mat_black_gloss', (0.19, 1.255, zf - 0.0115), (0.30, 1.272, zf - 0.008))
    mb.box('mat_steel_polished', (0.19, 1.240, zf - 0.0112), (0.30, 1.243, zf - 0.0100))
    mb.box('mat_led_green', (0.31, 1.291, zf - 0.0115), (0.322, 1.297, zf - 0.010))
    # speaker grille dots (help)
    for r in range(3):
        for cc in range(7):
            mb.box('mat_black_gloss', (0.175 + cc * 0.0215, 1.115 + r * 0.02, zf - 0.0025), (0.183 + cc * 0.0215, 1.123 + r * 0.02, zf))
    mb.cyl('mat_steel_polished', (0.25, 1.08, zf), (0.25, 1.08, zf - 0.010), 0.012, seg=14)
    # instructions panel with frame
    mb.box('mat_steel', (-0.338, 0.675, zf - 0.004), (0.338, 1.025, zf + 0.002), bevel=0.003)
    mb.fdecal('mat_instructions', 0.0, 0.68, 0.66, 0.66 * 528 / 1024, zf - 0.0042)
    # lower fascia: label strip + hardware
    mb.box('mat_charcoal', (-0.338, 0.455, zf - 0.004), (0.338, 0.665, zf + 0.002), bevel=0.003)
    mb.fdecal('mat_slots_label', 0.0, 0.465, 0.66, 0.66 * 300 / 1024, zf - 0.0042)
    # coin unit (viewer's left = +x)
    mb.box('mat_steel', (0.155, 0.235, zf - 0.016), (0.295, 0.44, zf + 0.002), bevel=0.006)
    mb.box('mat_black_gloss', (0.2205, 0.34, zf - 0.0175), (0.2295, 0.415, zf - 0.014))
    mb.box('mat_black_gloss', (0.19, 0.25, zf - 0.030), (0.26, 0.30, zf - 0.010), bevel=0.006)          # coin return cup
    # note acceptor
    mb.box('mat_charcoal', (-0.105, 0.30, zf - 0.030), (0.105, 0.385, zf + 0.002), bevel=0.006)
    mb.box('mat_yellow', (-0.085, 0.331, zf - 0.0315), (0.085, 0.352, zf - 0.028), bevel=0.0)
    mb.box('mat_black_gloss', (-0.075, 0.3375, zf - 0.0322), (0.075, 0.3455, zf - 0.030))
    # delivery tray (recessed look)
    mb.box('mat_steel', (-0.295, 0.245, zf - 0.012), (-0.135, 0.405, zf + 0.002), bevel=0.005)
    mb.box('mat_black_gloss', (-0.28, 0.26, zf - 0.0135), (-0.15, 0.35, zf - 0.004))
    mb.box('mat_steel_polished', (-0.285, 0.252, zf - 0.020), (-0.145, 0.262, zf - 0.010), bevel=0.003)
    # vents low + sides
    for k in range(6):
        mb.box('mat_black_plastic', (-0.20 + k * 0.08, 0.12, zf - 0.001), (-0.16 + k * 0.08, 0.135, zf))
    for sx in (-1, 1):
        for k in range(7):
            x = sx * (hx + 0.0005)
            mb.box('mat_black_plastic', (min(x, x + sx * 0.0015), 0.30 + k * 0.03, -0.09), (max(x, x + sx * 0.0015), 0.312 + k * 0.03, 0.09))
    # service door on the back: seam outline + lock
    for (a, b) in (((-0.30, 0.30), (-0.297, 1.50)), ((0.297, 0.30), (0.30, 1.50))):
        mb.box('mat_black_plastic', (a[0], a[1], hz), (b[0], b[1], hz + 0.0015))
    mb.box('mat_black_plastic', (-0.30, 0.30, hz), (0.30, 0.303, hz + 0.0015))
    mb.box('mat_black_plastic', (-0.30, 1.497, hz), (0.30, 1.50, hz + 0.0015))
    mb.cyl('mat_steel_polished', (0.22, 0.95, hz), (0.22, 0.95, hz + 0.012), 0.016, seg=12)
    # amber status lamp on top of header
    mb.box('mat_led_amber', (-0.03, 1.665, zf - 0.0025), (0.03, 1.673, zf))
    P.col_box('col_body-convcolonly', (-hx, 0, -hz), (hx, 1.70, hz))


# ============================================================================================ info totem
@prop('info_totem',
      desc='Free-standing double-sided information / map totem: brushed-steel frame, two printed panels, splayed feet.',
      origin='floor_centre', front='panel A faces -Z, panel B faces +Z',
      nodes={'body': 'frame + feet + panels', 'col_body-convcolonly': 'collision (footprint of the feet)'},
      slots={'mat_map_A': 'front (-Z) panel print, 650x1024 placeholder local-area map',
             'mat_map_B': 'back (+Z) panel print, 650x1024 placeholder network map'},
      anim={}, mount_height=0.0,
      notes=['Frame is 1.20 x 0.10 x 2.00; the splayed feet make the real footprint 1.2 x 0.44.'])
def info_totem(P):
    _decal_mat(P, 'mat_map_A', 'map_A', rough=0.22, spec=0.6)
    _decal_mat(P, 'mat_map_B', 'map_B', rough=0.22, spec=0.6)
    mb = P.mb('body')
    hw, dpt = 0.60, 0.05
    pw = 0.50
    # feet
    foot = [(-0.22, 0.0), (0.22, 0.0), (0.06, 0.16), (-0.06, 0.16)]
    for sx in (-1, 1):
        mb.prism('mat_charcoal', foot, 'x', sx * 0.47 - 0.07, sx * 0.47 + 0.07, bevel=0.006)
        mb.box('mat_steel', (sx * 0.47 - 0.05, 0.16, -0.045), (sx * 0.47 + 0.05, 0.22, 0.045), bevel=0.004)
    # frame: uprights, top & bottom rails
    for sx in (-1, 1):
        mb.box('mat_steel', (sx * (hw - 0.03) - 0.03, 0.20, -dpt), (sx * (hw - 0.03) + 0.03, 1.97, dpt), bevel=0.010, seg=2)
    mb.box('mat_steel', (-hw, 0.20, -dpt), (hw, 0.30, dpt), bevel=0.010, seg=1)
    mb.box('mat_steel', (-hw, 1.90, -dpt), (hw, 2.00, dpt), bevel=0.010, seg=1)
    # panel core + prints
    mb.box('mat_black_plastic', (-hw + 0.06, 0.30, -0.02), (hw - 0.06, 1.90, 0.02))
    pw = 2 * (hw - 0.06); ph = 1.60
    mb.fdecal('mat_map_A', 0.0, 0.30, pw, ph, -0.0205, facing=-1)
    mb.fdecal('mat_map_B', 0.0, 0.30, pw, ph, 0.0205, facing=+1)
    # small end caps + hinge screws
    for sx in (-1, 1):
        for sz in (-1, 1):
            for yy in (0.25, 1.95):
                mb.cyl('mat_steel_polished', (sx * (hw - 0.03), yy, sz * dpt), (sx * (hw - 0.03), yy, sz * (dpt + 0.004)), 0.007, seg=8)
    P.col_box('col_body-convcolonly', (-0.60, 0, -0.22), (0.60, 2.0, 0.22))


# ============================================================================================ journey planner
@prop('journey_planner_screen',
      desc='Wall-mounted portrait digital journey-planner display in a charcoal/steel housing.',
      origin='wall_back_bottom_centre', front='screen faces -Z; back plane (wall) at z=0, object extends toward -Z',
      nodes={'body': 'housing + screen'}, slots={'mat_screen': 'emissive screen 592x1024 placeholder UI'},
      anim={}, mount_height=0.55, notes=['Recommended mounting: bottom edge 0.55 m above the floor (top at 2.05 m).'])
def journey_planner_screen(P):
    _decal_mat(P, 'mat_screen', 'journey_ui', emit=0.8, rough=0.06)
    mb = P.mb('body')
    W, H, D = 0.90, 1.50, 0.10
    mb.box('mat_charcoal', (-W / 2, 0, -D), (W / 2, H, 0.0), bevel=0.014, seg=2)
    mb.box('mat_steel', (-W / 2 + 0.005, 0.005, -D - 0.001), (W / 2 - 0.005, 0.03, -D + 0.008), bevel=0.003)
    mb.box('mat_black_gloss', (-0.42, 0.06, -D - 0.006), (0.42, 1.44, -D + 0.01), bevel=0.006)
    sw = 0.80; sh = sw * 1024 / 592
    mb.fdecal('mat_screen', 0.0, 0.06 + (1.38 - sh) / 2 + 0.0, sw, sh, -D - 0.0062)
    mb.box('mat_steel', (-0.10, 0.0, 0.0), (0.10, 1.5, 0.006))    # wall bracket rail (hidden mostly)
    mb.box('mat_black_gloss', (-0.03, 1.455, -D - 0.002), (0.03, 1.462, -D + 0.002))   # camera/sensor slit
    P.col_box('col_body-convcolonly', (-W / 2, 0, -D), (W / 2, H, 0))


# ============================================================================================ help point
@prop('help_point',
      desc='Free-standing emergency help point pillar: brushed-steel column, illuminated blue "Help point" header, speaker grille, red emergency '
           'button, blue information button and a status lamp.',
      origin='floor_centre', front='panel faces -Z',
      nodes={'body': 'column, panel, buttons', 'lamp_status': 'small emissive status lamp (own material mat_help_lamp)',
             'col_body-convcolonly': 'collision'},
      slots={'mat_help_sign': 'emissive header sign', 'mat_help_panel': 'printed control panel', 'mat_help_lamp': 'emissive status lamp'},
      anim={}, mount_height=0.0, notes=['0.30 x 0.16 x 1.72 m.'])
def help_point(P):
    _decal_mat(P, 'mat_help_sign', 'help_sign', emit=1.3, rough=0.25)
    _decal_mat(P, 'mat_help_panel', 'help_panel', rough=0.35)
    P.mat('mat_red_button', color=(0.75, 0.02, 0.03, 1), rough=0.25, spec=0.7)
    P.mat('mat_blue_button', color=(0.05, 0.15, 0.75, 1), rough=0.25, spec=0.7)
    P.mat('mat_help_lamp', color=(0.1, 0.9, 0.25, 1), emit=(0.1, 1.0, 0.25), emit_strength=4.0, rough=0.3)
    mb = P.mb('body')
    hw, hd = 0.15, 0.08
    zf = -hd
    mb.box('mat_charcoal', (-hw + 0.012, 0, -hd + 0.01), (hw - 0.012, 0.09, hd - 0.01), bevel=0.006)
    mb.box('mat_steel', (-hw, 0.085, -hd), (hw, 1.56, hd), bevel=0.012, seg=1)
    mb.box('mat_charcoal', (-hw, 1.555, -hd - 0.004), (hw, 1.72, hd + 0.004), bevel=0.014, seg=2)
    mb.fdecal('mat_help_sign', 0.0, 1.575, 0.27, 0.135, zf - 0.0055)
    mb.box('mat_black_gloss', (-0.118, 0.865, zf - 0.006), (0.118, 1.515, zf + 0.002), bevel=0.004)
    mb.fdecal('mat_help_panel', 0.0, 0.89, 0.225, 0.60, zf - 0.0065)
    # red emergency button (decal ring centre at y=1.5 - 0.542*0.6)
    with mb.tf(Xf.T(0.0, 1.175, zf - 0.0065) * Xf.R('x', -90)):
        mb.lathe('mat_steel_polished', [(0.058, 0.0), (0.058, 0.008), (0.052, 0.008), (0.052, 0.0)], seg=28)
        mb.lathe('mat_red_button', [(0.048, 0.0), (0.048, 0.012), (0.040, 0.026), (0.020, 0.032), (0.0, 0.033)], seg=28)
    with mb.tf(Xf.T(0.0, 1.002, zf - 0.0065) * Xf.R('x', -90)):
        mb.lathe('mat_steel_polished', [(0.033, 0.0), (0.033, 0.005), (0.029, 0.005), (0.029, 0.0)], seg=20)
        mb.lathe('mat_blue_button', [(0.028, 0.0), (0.028, 0.008), (0.018, 0.014), (0.0, 0.015)], seg=20)
    # camera dot
    mb.cyl('mat_black_gloss', (0.0, 1.487, zf - 0.006), (0.0, 1.487, zf - 0.010), 0.008, seg=10)
    lm = P.mb('lamp_status', pivot=(0.085, 1.49, zf - 0.0065), dirt=False, extras={'kind': 'status_lamp'})
    lm.cyl('mat_help_lamp', (0.085, 1.49, zf - 0.0065), (0.085, 1.49, zf - 0.0115), 0.007, seg=10)
    P.col_box('col_body-convcolonly', (-hw, 0, -hd), (hw, 1.72, hd))


# ============================================================================================ fire cabinet
@prop('fire_cabinet',
      desc='Wall-mounted red fire-equipment cabinet with a window showing an extinguisher, printed FIRE labels, handle and hinges.',
      origin='wall_back_bottom_centre', front='door faces -Z; back plane at z=0',
      nodes={'body': 'cabinet, door, extinguisher'}, slots={'mat_fire_label_top': 'printed top label', 'mat_fire_label_bottom': 'printed instruction label', 'mat_red': 'painted door'},
      anim={}, mount_height=0.30, notes=['0.55 x 0.20 x 0.95 m; recommended bottom edge 0.30 m above floor.'])
def fire_cabinet(P):
    _decal_mat(P, 'mat_fire_label_top', 'fire_label_top', rough=0.35)
    _decal_mat(P, 'mat_fire_label_bottom', 'fire_label_bottom', rough=0.35)
    mb = P.mb('body')
    W, H, D = 0.55, 0.95, 0.20
    zf = -D
    # carcass (hollow: back plate + 4 walls) + door
    mb.box('mat_red', (-W / 2, 0, -0.02), (W / 2, H, 0.0), bevel=0.004, seg=1)
    mb.box('mat_red', (-W / 2, 0, zf + 0.02), (-W / 2 + 0.02, H, -0.02), bevel=0.0)
    mb.box('mat_red', (W / 2 - 0.02, 0, zf + 0.02), (W / 2, H, -0.02), bevel=0.0)
    mb.box('mat_red', (-W / 2, 0, zf + 0.02), (W / 2, 0.02, -0.02), bevel=0.0)
    mb.box('mat_red', (-W / 2, H - 0.02, zf + 0.02), (W / 2, H, -0.02), bevel=0.0)
    # door = frame around the window opening (x +-0.20, y 0.26..0.775)
    mb.box('mat_red', (-W / 2 - 0.005, 0.0, zf), (-0.20, H, zf + 0.022), bevel=0.006, seg=1)
    mb.box('mat_red', (0.20, 0.0, zf), (W / 2 + 0.005, H, zf + 0.022), bevel=0.006, seg=1)
    mb.box('mat_red', (-0.20, 0.0, zf), (0.20, 0.26, zf + 0.022), bevel=0.006, seg=1)
    mb.box('mat_red', (-0.20, 0.775, zf), (0.20, H, zf + 0.022), bevel=0.006, seg=1)
    # label strips
    mb.fdecal('mat_fire_label_top', 0.0, 0.79, 0.45, 0.45 * 128 / 512, zf - 0.0012)
    mb.fdecal('mat_fire_label_bottom', 0.0, 0.055, 0.45, 0.45 * 192 / 512, zf - 0.0012)
    # window: white backing + extinguisher inside, glass in front
    mb.box('mat_white', (-0.20, 0.26, -0.03), (0.20, 0.775, -0.022))
    mb.box('mat_steel', (-0.21, 0.255, zf - 0.002), (0.21, 0.27, zf + 0.02), bevel=0.003)
    mb.box('mat_steel', (-0.21, 0.765, zf - 0.002), (0.21, 0.78, zf + 0.02), bevel=0.003)
    for sx in (-1, 1):
        mb.box('mat_steel', (sx * 0.20 - 0.007 + (0.007 * sx), 0.255, zf - 0.002), (sx * 0.20 + 0.007 + (0.007 * sx), 0.78, zf + 0.02), bevel=0.003)
    mb.box('mat_glass', (-0.20, 0.27, zf + 0.005), (0.20, 0.765, zf + 0.008))
    # extinguisher
    ex = 0.0; ez = -0.09
    mb.lathe('mat_red', [(0.0, 0.29), (0.045, 0.29), (0.056, 0.30), (0.056, 0.60), (0.045, 0.655), (0.02, 0.675), (0.0, 0.675)], seg=20, cx=ex, cz=ez)
    mb.box('mat_black_plastic', (ex - 0.03, 0.675, ez - 0.03), (ex + 0.03, 0.71, ez + 0.02), bevel=0.005)
    mb.box('mat_steel_polished', (ex - 0.008, 0.71, ez - 0.05), (ex + 0.008, 0.725, ez + 0.02), bevel=0.003)
    mb.tube('mat_black_plastic', [(ex + 0.02, 0.69, ez - 0.02), (ex + 0.10, 0.66, ez - 0.02), (ex + 0.12, 0.45, ez - 0.02)], 0.009, seg=8)
    mb.box('mat_white', (ex - 0.03, 0.44, ez - 0.058), (ex + 0.03, 0.55, ez - 0.056))       # label on cylinder
    # handle + hinges
    mb.box('mat_steel_polished', (0.20, 0.43, zf - 0.02), (0.235, 0.55, zf - 0.005), bevel=0.005)
    for y in (0.15, 0.50, 0.80):
        mb.cyl('mat_steel_polished', (-W / 2 - 0.005, y - 0.04, zf + 0.011), (-W / 2 - 0.005, y + 0.04, zf + 0.011), 0.008, seg=8)
    mb.box('mat_black_plastic', (-0.03, H - 0.025, zf - 0.001), (0.03, H - 0.015, zf))


# ============================================================================================ cctv dome
@prop('cctv_dome',
      desc='Ceiling-mounted CCTV dome camera: white base, smoked dome with visible camera block, tiny status LED.',
      origin='mount_point', origin_note='point on the ceiling; the dome hangs towards -Y from the origin', front='camera dome hangs below the origin', nodes={'body': 'base + dome + camera', 'led': 'emissive red LED (own material)'},
      slots={'mat_glass_smoked': 'dome', 'mat_led_red': 'status LED'}, anim={}, mount_height=2.6,
      notes=['Origin is the point on the ceiling. Diameter 0.16 m, hangs 0.11 m.'])
def cctv_dome(P):
    P.mat('mat_led_red', color=(1, 0.05, 0.03, 1), emit=(1.0, 0.05, 0.03), emit_strength=6.0, rough=0.3)
    P.mat('mat_lens', color=(0.02, 0.05, 0.08, 1), rough=0.03, spec=1.0)
    mb = P.mb('body', dirt=False)
    mb.lathe('mat_white', [(0.0, 0.0), (0.08, 0.0), (0.08, -0.008), (0.074, -0.024), (0.066, -0.028), (0.0, -0.028)], seg=28)
    # camera block inside dome
    mb.cyl('mat_black_plastic', (0.0, -0.028, 0.0), (0.0, -0.05, 0.0), 0.018, seg=14)
    mb.sphere('mat_black_plastic', (0.0, -0.062, 0.0), 0.028, seg=16, rings=8)
    with mb.tf(Xf.T(0.0, -0.066, 0.0) * Xf.R('x', 35)):
        mb.cyl('mat_lens', (0.0, 0.0, 0.0), (0.0, 0.0, -0.032), 0.012, seg=12)
    # smoked dome (hemisphere)
    prof = [(0.066, -0.028)]
    for k in range(1, 10):
        a = math.radians(90.0 * k / 9)
        prof.append((0.066 * math.cos(a), -0.028 - 0.066 * math.sin(a)))
    mb.lathe('mat_glass_smoked', prof, seg=28)
    lm = P.mb('led', pivot=(0.055, -0.026, -0.03), dirt=False)
    lm.cyl('mat_led_red', (0.055, -0.024, -0.03), (0.055, -0.030, -0.03), 0.0035, seg=8)


# ============================================================================================ PA speaker
@prop('pa_speaker',
      desc='Public-address box speaker on a swivel wall/ceiling bracket: grey rounded box, perforated grille, steel U-bracket.',
      origin='mount_point', origin_note='centre of the wall plate (wall plane z=0); box hangs toward -Z', front='grille faces -Z', nodes={'body': 'bracket + speaker'},
      slots={'mat_pa_grille': 'grille print'}, anim={}, mount_height=2.4,
      notes=['0.32 x 0.20 x 0.24 m incl. bracket. Origin = centre of the wall plate. Tilted 12 degrees down.'])
def pa_speaker(P):
    _decal_mat(P, 'mat_pa_grille', 'pa_grille', rough=0.6)
    mb = P.mb('body', dirt=False)
    mb.box('mat_steel', (-0.05, -0.05, -0.008), (0.05, 0.05, 0.0), bevel=0.003)
    mb.box('mat_steel', (-0.012, -0.012, -0.05), (0.012, 0.012, -0.008), bevel=0.003)
    mb.box('mat_steel', (-0.17, 0.018, -0.085), (0.17, 0.028, -0.055), bevel=0.003)          # yoke bar
    for sx in (-1, 1):
        mb.box('mat_steel', (sx * 0.165 - 0.006, -0.10, -0.085), (sx * 0.165 + 0.006, 0.028, -0.06), bevel=0.003)
    with mb.tf(Xf.T(0, -0.045, -0.15) * Xf.R('x', 12)):
        mb.box('mat_grey', (-0.155, -0.10, -0.085), (0.155, 0.10, 0.085), bevel=0.02, seg=2)
        mb.tile('mat_pa_grille', 0.28, 0.14)
        mb.fdecal('mat_pa_grille', 0.0, -0.085, 0.27, 0.17, -0.0865)
    for sx in (-1, 1):
        mb.cyl('mat_steel_polished', (sx * 0.16, -0.045, -0.06), (sx * 0.175, -0.045, -0.06), 0.011, seg=10)


# ============================================================================================ clock
@prop('clock',
      desc='Round station clock: black case, white dial with numerals and minute ticks, glass, separate hour / minute / second hands pivoting at the dial centre.',
      origin='mount_point', origin_note='centre of the dial back plane on the wall (z=0); dial faces -Z', front='dial faces -Z',
      nodes={'body': 'case, dial, glass', 'hand_hour': 'origin = dial centre (0,0,-0.05)', 'hand_min': 'origin = dial centre', 'hand_sec': 'origin = dial centre'},
      slots={'mat_clock_face': 'dial print'},
      anim={'hand_hour': {'axis': 'z', 'rotation_z_rad': 'TAU*((h%12)+m/60)/12'}, 'hand_min': {'axis': 'z', 'rotation_z_rad': 'TAU*(m+s/60)/60'},
            'hand_sec': {'axis': 'z', 'rotation_z_rad': 'TAU*s/60'}},
      mount_height=2.6,
      notes=['Positive rotation.z turns a hand CLOCKWISE as seen from the front (from -Z). Hands are modelled at 12 o\'clock. Dial diameter 0.40 m, case 0.46 m, depth 0.06 m.'])
def clock(P):
    _decal_mat(P, 'mat_clock_face', 'clock_face', rough=0.35)
    P.mat('mat_clock_glass', color=(0.9, 0.95, 1.0, 1), rough=0.02, alpha=0.06, spec=1.0)
    mb = P.mb('body', dirt=False)
    with mb.tf(Xf.R('x', -90)):          # local +Y -> world -Z
        mb.lathe('mat_black_plastic', [(0.0, 0.0), (0.232, 0.0), (0.234, 0.012), (0.234, 0.05), (0.226, 0.058), (0.212, 0.058), (0.208, 0.052), (0.208, 0.02), (0.0, 0.02)], seg=48)
    mb.disc('mat_clock_face', 0.207, z=-0.021, facing=-1, seg=48)
    mb.disc('mat_clock_glass', 0.207, z=-0.053, facing=-1, seg=48)
    mb.box('mat_steel', (-0.015, -0.234, -0.008), (0.015, -0.24, -0.02))
    zc = -0.03
    def hand(name, length, tail, wid, z, mat, tip=0.0):
        hm = P.mb(name, pivot=(0.0, 0.0, zc), dirt=False)
        poly = [(-wid * 0.6, -tail), (wid * 0.6, -tail), (wid * 0.5, length * 0.8), (wid * 0.12 if tip == 0 else tip, length), (-wid * 0.12 if tip == 0 else -tip, length), (-wid * 0.5, length * 0.8)]
        hm.prism(mat, poly, 'z', z - 0.0035, z, bevel=0.0)
        return hm
    hand('hand_hour', 0.105, 0.03, 0.020, -0.041, 'mat_black_plastic')
    hand('hand_min', 0.175, 0.04, 0.014, -0.0455, 'mat_black_plastic')
    hs = P.mb('hand_sec', pivot=(0.0, 0.0, zc), dirt=False)
    hs.prism('mat_red', [(-0.003, -0.05), (0.003, -0.05), (0.0025, 0.185), (-0.0025, 0.185)], 'z', -0.0525, -0.050)
    hs.cyl('mat_red', (0, 0, -0.050), (0, 0, -0.0555), 0.012, seg=14)
    hs.cyl('mat_red', (0, -0.05, -0.050), (0, -0.05, -0.0525), 0.009, seg=10)


# ============================================================================================ emergency stop plunger
@prop('emergency_stop_plunger',
      desc='Platform emergency train-stop plunger: yellow steel box with protective guard, red mushroom button, printed label and amber lamp.',
      origin='wall_back_bottom_centre', front='button faces -Z; back plane at z=0',
      nodes={'body': 'box, guard, button, label', 'lamp': 'emissive amber lamp (own material)'},
      slots={'mat_estop_label': 'printed label', 'mat_lamp_amber': 'lamp'}, anim={'body': {'note': 'button is static; play a push tween on a scale/position if desired'}},
      mount_height=1.1, notes=['0.18 x 0.22 x 0.13 m. Recommended bottom edge at 1.1 m.'])
def emergency_stop_plunger(P):
    _decal_mat(P, 'mat_estop_label', 'estop_label', rough=0.4)
    P.mat('mat_lamp_amber', color=(1, 0.6, 0.05, 1), emit=(1.0, 0.55, 0.03), emit_strength=5.0, rough=0.3)
    P.mat('mat_red_button', color=(0.75, 0.02, 0.03, 1), rough=0.25, spec=0.7)
    mb = P.mb('body')
    W, H, D = 0.18, 0.22, 0.10
    mb.box('mat_yellow', (-W / 2, 0.0, -D), (W / 2, H, 0.0), bevel=0.008, seg=1)
    mb.fdecal('mat_estop_label', 0.0, 0.125, 0.14, 0.105, -D - 0.0012)
    with mb.tf(Xf.T(0, 0.062, -D) * Xf.R('x', -90)):
        mb.lathe('mat_steel_polished', [(0.05, 0.0), (0.05, 0.006), (0.044, 0.006), (0.044, 0.0)], seg=24)
        mb.cyl('mat_steel_polished', (0, 0.0, 0), (0, 0.020, 0), 0.014, seg=12)
        mb.lathe('mat_red_button', [(0.0, 0.020), (0.036, 0.020), (0.040, 0.030), (0.038, 0.040), (0.026, 0.050), (0.0, 0.054)], seg=28)
    # guard hood: two side cheeks + top bridge
    for sx in (-1, 1):
        mb.box('mat_yellow', (sx * 0.062 - 0.006 + 0.0, 0.0, -D - 0.045), (sx * 0.062 + 0.006, 0.115, -D + 0.001), bevel=0.003)
    mb.box('mat_yellow', (-0.068, 0.108, -D - 0.045), (0.068, 0.118, -D + 0.001), bevel=0.003)
    lm = P.mb('lamp', pivot=(0.0, H, -D / 2), dirt=False)
    lm.box('mat_lamp_amber', (-0.02, H, -D / 2 - 0.02), (0.02, H + 0.018, -D / 2 + 0.02), bevel=0.005)


# ============================================================================================ signal lamp
@prop('signal_lamp',
      desc='Post-mounted tunnel signal: black housing with two lens hoods (red / green emissive lamps as separate nodes), route indicator and number plate.',
      origin='floor_centre', front='lenses face -Z (drivers approach from -Z)',
      nodes={'body': 'post, housing, hoods, plates', 'lamp_red': 'emissive red aspect', 'lamp_green': 'emissive green aspect',
             'col_post-convcolonly': 'collision'},
      slots={'mat_lamp_red': 'emissive', 'mat_lamp_green': 'emissive', 'mat_signal_plate': 'number plate', 'mat_signal_route': 'route indicator'},
      anim={}, mount_height=0.0, notes=['0.34 x 0.32 x 2.25 m. Only ONE aspect should be visible/emitting at a time (set node.visible or emission energy).'])
def signal_lamp(P):
    _decal_mat(P, 'mat_signal_plate', 'signal_plate', rough=0.4)
    _decal_mat(P, 'mat_signal_route', 'signal_route', emit=1.5, rough=0.3)
    P.mat('mat_lamp_red', color=(1, 0.04, 0.03, 1), emit=(1.0, 0.03, 0.02), emit_strength=8.0, rough=0.15)
    P.mat('mat_lamp_green', color=(0.05, 1, 0.3, 1), emit=(0.05, 1.0, 0.25), emit_strength=8.0, rough=0.15)
    mb = P.mb('body')
    hx, hz = 0.16, 0.13
    mb.cyl('mat_steel', (0, 0.0, 0.10), (0, 1.52, 0.10), 0.045, seg=16, swap=True)
    mb.cyl('mat_charcoal', (0, 0.0, 0.10), (0, 0.06, 0.10), 0.11, seg=20, bevel=0.01)
    mb.box('mat_black_plastic', (-hx, 1.50, -hz), (hx, 2.10, hz), bevel=0.014, seg=2)
    mb.box('mat_white', (-hx - 0.012, 1.48, -hz - 0.004), (hx + 0.012, 2.12, -hz + 0.008), bevel=0.006)      # white backing board
    mb.box('mat_black_plastic', (-hx, 1.50, -hz - 0.006), (hx, 2.10, -hz + 0.004), bevel=0.01, seg=1)
    ys = {'lamp_red': 1.94, 'lamp_green': 1.68}
    for nm, y in ys.items():
        # lens surround + hood
        with mb.tf(Xf.T(0, y, -hz - 0.006) * Xf.R('x', -90)):
            mb.lathe('mat_black_gloss', [(0.088, 0.0), (0.088, 0.012), (0.078, 0.012), (0.078, 0.0)], seg=28)
        hood = [(0.088 * math.cos(math.radians(a)), 0.088 * math.sin(math.radians(a))) for a in range(0, 181, 15)]
        # visor (half tube on top of lens)
        with mb.tf(Xf.T(0, y, -hz - 0.006)):
            for k in range(len(hood) - 1):
                (x0, y0), (x1, y1) = hood[k], hood[k + 1]
                mb.quad('mat_black_plastic', (x0, y0, 0.0), (x1, y1, 0.0), (x1 * 1.04, y1 * 1.04, -0.075), (x0 * 1.04, y0 * 1.04, -0.075), hint=(-(x0 + x1), -(y0 + y1), 0.0))
                mb.quad('mat_black_plastic', (x0 * 1.10, y0 * 1.10, -0.0), (x0 * 1.10, y0 * 1.10, -0.0), (x0 * 1.04, y0 * 1.04, -0.075), (x0 * 1.04, y0 * 1.04, -0.075))
        lm = P.mb(nm, pivot=(0, y, -hz - 0.006), dirt=False, extras={'kind': 'signal_aspect'})
        mat = 'mat_' + nm
        with lm.tf(Xf.T(0, y, -hz - 0.006) * Xf.R('x', -90)):
            lm.lathe(mat, [(0.078, 0.0), (0.078, 0.004), (0.062, 0.012), (0.0, 0.016)], seg=28)
    # route indicator + plate
    mb.box('mat_black_plastic', (-0.12, 2.12, -0.10), (0.12, 2.23, 0.04), bevel=0.008, seg=1)
    mb.fdecal('mat_signal_route', 0.0, 2.13, 0.10, 0.09, -0.1012)
    mb.box('mat_white', (-0.10, 1.33, 0.10 - 0.055), (0.10, 1.43, 0.10 - 0.048), bevel=0.0)
    mb.fdecal('mat_signal_plate', 0.0, 1.33, 0.20, 0.10, 0.10 - 0.0552)
    P.col_box('col_post-convcolonly', (-0.08, 0, 0.02), (0.08, 1.6, 0.18))


# ============================================================================================ lift doors
@prop('lift_doors',
      desc='Passenger lift entrance: brushed-steel surround, two sliding steel door leaves (1.1 m clear opening), call panel with lit buttons, arrival indicator '
           'and a plain steel-panelled car interior behind the doors.',
      origin='floor_at_front_plane', front='fascia faces -Z; the lift car extends towards +Z (z = 0 is the fascia plane)',
      nodes={'body': 'surround, sill, floor', 'door_L': 'left leaf (x<0); origin at closed leaf centre (-0.275,0,-0.02)', 'door_R': 'right leaf (x>0); origin (+0.275,0,-0.02)',
             'lift_car': 'car interior (walls, rail, ceiling light) - hide/replace freely', 'lamp_call': 'emissive call-button lamp (own material)',
             'indicator': 'emissive arrival indicator (own material mat_lift_indicator)', 'col_body-convcolonly': 'collision of the surround'},
      slots={'mat_lift_call': 'call panel print', 'mat_lift_indicator': 'emissive indicator', 'mat_lamp_call': 'emissive button lamp'},
      anim={'door_L': {'open_offset': [-0.50, 0.0, 0.0]}, 'door_R': {'open_offset': [0.50, 0.0, 0.0]}},
      mount_height=0.0, notes=['Doors OPEN by translating door_L by -0.50 m and door_R by +0.50 m in X (they slide behind the surround).',
                               'Clear opening 1.10 x 2.10 m, overall 1.50 x 2.45 x 1.45 m (incl. car).'])
def lift_doors(P):
    _decal_mat(P, 'mat_lift_call', 'lift_call', rough=0.35)
    _decal_mat(P, 'mat_lift_indicator', 'lift_indicator', emit=2.5, rough=0.15)
    P.mat('mat_lamp_call', color=(1, 0.75, 0.2, 1), emit=(1.0, 0.7, 0.15), emit_strength=5.0, rough=0.3)
    P.mat('mat_lift_light', color=(1, 1, 0.95, 1), emit=(1.0, 0.97, 0.9), emit_strength=3.0, rough=0.4)
    mb = P.mb('body')
    W, H = 1.50, 2.45
    op = 1.10
    zf = 0.0
    # surround (fascia panels either side + lintel + sill)
    sw = (W - op) / 2
    for sx in (-1, 1):
        mb.box('mat_steel', (sx * (op / 2 + sw / 2) - sw / 2, 0.0, zf - 0.03), (sx * (op / 2 + sw / 2) + sw / 2, H, zf + 0.06), bevel=0.008, seg=1)
    mb.box('mat_steel', (-W / 2, 2.15, zf - 0.03), (W / 2, H, zf + 0.06), bevel=0.008, seg=1)
    mb.box('mat_black_plastic', (-op / 2 - 0.012, 0.0, zf - 0.031), (-op / 2, 2.15, zf - 0.03 + 0.03), bevel=0.0)
    mb.box('mat_black_plastic', (op / 2, 0.0, zf - 0.031), (op / 2 + 0.012, 2.15, zf - 0.03 + 0.03), bevel=0.0)
    # sill + floor of car
    mb.box('mat_steel_polished', (-op / 2, 0.0, zf - 0.02), (op / 2, 0.012, zf + 0.10), bevel=0.003)
    mb.box('mat_rubber', (-op / 2 + 0.02, 0.0, zf + 0.10), (op / 2 - 0.02, 0.008, zf + 1.40), bevel=0.0)
    # call panel on the right fascia
    mb.box('mat_steel_polished', (0.67, 0.92, zf - 0.034), (0.76, 1.12, zf - 0.028), bevel=0.003)
    mb.fdecal('mat_lift_call', 0.715, 0.93, 0.084, 0.168, zf - 0.0342)
    for yy in (1.055, 0.97):
        pass
    lm = P.mb('lamp_call', pivot=(0.715, 1.02, zf - 0.034), dirt=False)
    with lm.tf(Xf.T(0.715, 1.02, zf - 0.0345) * Xf.R('x', -90)):
        lm.lathe('mat_lamp_call', [(0.016, 0.0), (0.016, 0.003), (0.0, 0.004)], seg=16)
    mb.cyl('mat_steel_polished', (0.715, 1.02, zf - 0.034), (0.715, 1.02, zf - 0.0345), 0.020, seg=16)
    im = P.mb('indicator', pivot=(0.0, 2.29, zf - 0.03), dirt=False)
    im.box('mat_black_gloss', (-0.09, 2.24, zf - 0.033), (0.09, 2.34, zf - 0.02), bevel=0.004)
    im.fdecal('mat_lift_indicator', 0.0, 2.25, 0.16, 0.08, zf - 0.0332)
    # doors
    lw = op / 2 + 0.01
    for nm, sx in (('door_L', -1), ('door_R', 1)):
        cx = sx * op / 4
        dm = P.mb(nm, pivot=(cx, 0.0, zf - 0.02), extras={'open_offset': [sx * 0.50, 0.0, 0.0]})
        dm.box('mat_steel', (cx - lw / 2, 0.012, zf - 0.02), (cx + lw / 2, 2.13, zf + 0.0), bevel=0.004)
        for k in range(3):       # vertical embossed ribs
            xx = cx - lw / 2 + 0.06 + k * (lw - 0.12) / 2
            dm.box('mat_steel_polished', (xx - 0.004, 0.10, zf - 0.0215), (xx + 0.004, 2.05, zf - 0.02))
        dm.box('mat_black_plastic', (cx + sx * lw / 2 - sx * 0.008 - 0.004, 0.012, zf - 0.022), (cx + sx * lw / 2 - sx * 0.008 + 0.004, 2.13, zf - 0.02))
    # lift car interior
    cm = P.mb('lift_car')
    cd = 1.35
    cm.box('mat_steel', (-op / 2, 0.0, zf + 0.10), (-op / 2 + 0.02, 2.15, zf + cd))
    cm.box('mat_steel', (op / 2 - 0.02, 0.0, zf + 0.10), (op / 2, 2.15, zf + cd))
    cm.box('mat_steel', (-op / 2, 0.0, zf + cd - 0.02), (op / 2, 2.15, zf + cd))
    cm.box('mat_charcoal', (-op / 2, 2.15, zf + 0.10), (op / 2, 2.20, zf + cd))
    cm.box('mat_lift_light', (-0.35, 2.145, zf + 0.35), (0.35, 2.150, zf + 1.10))
    cm.tube('mat_steel_polished', [(-op / 2 + 0.05, 0.95, zf + 0.30), (-op / 2 + 0.05, 0.95, zf + cd - 0.05), (op / 2 - 0.05, 0.95, zf + cd - 0.05), (op / 2 - 0.05, 0.95, zf + 0.30)], 0.016, seg=8)
    P.col_box('col_body-convcolonly', (-W / 2, 0, -0.03), (W / 2, H, 0.06))


# ============================================================================================ platform edge marker
@prop('platform_edge_marker',
      desc='Hazard marker post for the end of a platform / edge: 1.0 m post with yellow-black chevron wrap, reflective cap, steel base plate.',
      origin='floor_centre', front='chevrons on all four faces', nodes={'body': 'post', 'col_body-convcolonly': 'collision'},
      slots={'mat_marker': 'chevron wrap'}, anim={}, mount_height=0.0, notes=['0.12 x 0.12 x 1.05 m.'])
def platform_edge_marker(P):
    _decal_mat(P, 'mat_marker', 'marker_chevron', rough=0.45)
    mb = P.mb('body')
    mb.tile('mat_marker', 0.12, 0.24)
    mb.box('mat_steel', (-0.09, 0.0, -0.09), (0.09, 0.012, 0.09), bevel=0.003)
    mb.box('mat_marker', (-0.05, 0.012, -0.05), (0.05, 1.00, 0.05), bevel=0.006)
    mb.box('mat_white', (-0.052, 1.0, -0.052), (0.052, 1.05, 0.052), bevel=0.01, seg=1)
    for sx in (-1, 1):
        for sz in (-1, 1):
            mb.cyl('mat_steel_polished', (sx * 0.075, 0.012, sz * 0.075), (sx * 0.075, 0.018, sz * 0.075), 0.008, seg=8)
    P.col_box('col_body-convcolonly', (-0.06, 0, -0.06), (0.06, 1.05, 0.06))
