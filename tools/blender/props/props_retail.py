"""Retail / misc: vending_machine, newsstand_kiosk."""
import math, random
from propcore import prop
from propmesh import Xf


def _dm(P, name, tex, emit=None, rough=0.4, **kw):
    spec = dict(c='decals/%s_c.png' % tex, rough=rough)
    if emit:
        spec.update(emit=(1, 1, 1), emit_tex=True, emit_strength=emit, spec=0.7)
    spec.update(kw)
    P.mat(name, **spec)


@prop('vending_machine',
      desc='Drinks & snacks vending machine: blue cabinet, lit header sign, glass product window, keypad / coin / card / note column, delivery flap.',
      origin='floor_centre', front='front faces -Z',
      nodes={'body': 'cabinet, keypad, glazing', 'flap': 'delivery flap, origin = top hinge (-0.115, 0.335, -0.40); swing open by open_rotation_x_deg=-40',
             'col_body-convcolonly': 'collision'},
      slots={'mat_vend_front': 'product window print (retarget)', 'mat_vend_header': 'emissive header sign', 'mat_vend_display': 'emissive display', 'mat_vend_side': 'side panel prints', 'mat_glass': 'window glass'},
      anim={'flap': {'open_rotation_x_deg': -40.0}}, mount_height=0.0,
      notes=['0.85 x 0.80 x 1.85 m.'])
def vending_machine(P):
    _dm(P, 'mat_vend_front', 'vend_front', emit=0.6, rough=0.3)
    _dm(P, 'mat_vend_header', 'vend_header', emit=1.4, rough=0.3)
    _dm(P, 'mat_vend_display', 'vend_display', emit=1.6, rough=0.15)
    _dm(P, 'mat_vend_side', 'vend_side', rough=0.35)
    P.mat('mat_gate_reader', c='decals/gate_reader_c.png', rough=0.22, spec=0.6)
    P.mat('mat_key', color=(0.78, 0.8, 0.83, 1), rough=0.3, metal=0.6)
    mb = P.mb('body')
    W, D, H = 0.85, 0.80, 1.85
    hx, hz = W / 2, D / 2
    zf = -hz
    mb.box('mat_charcoal', (-hx + 0.015, 0.0, -hz + 0.015), (hx - 0.015, 0.07, hz - 0.015), bevel=0.006)
    mb.box('mat_blue', (-hx, 0.06, -hz), (hx, H, hz), bevel=0.022, seg=2)
    sw_, sh_ = 0.60, 0.60 * 768 / 512
    mb.qdecal('mat_vend_side', (hx + 0.0015, 0.42, sw_ / 2), (0, 0, -1), (0, 1, 0), sw_, sh_, hint=(1, 0, 0))       # side prints
    mb.qdecal('mat_vend_side', (-hx - 0.0015, 0.42, -sw_ / 2), (0, 0, 1), (0, 1, 0), sw_, sh_, hint=(-1, 0, 0))
    # service door on the back: seam outline + lock
    for (a, b) in (((-0.33, 0.35), (-0.327, 1.55)), ((0.327, 0.35), (0.33, 1.55))):
        mb.box('mat_black_plastic', (a[0], a[1], hz), (b[0], b[1], hz + 0.0015))
    mb.box('mat_black_plastic', (-0.33, 0.35, hz), (0.33, 0.353, hz + 0.0015))
    mb.box('mat_black_plastic', (-0.33, 1.547, hz), (0.33, 1.55, hz + 0.0015))
    mb.cyl('mat_steel_polished', (0.26, 1.0, hz), (0.26, 1.0, hz + 0.012), 0.016, seg=12)
    mb.box('mat_black_gloss', (0.2575, 0.99, hz + 0.012), (0.2625, 1.01, hz + 0.0125))
    mb.fdecal('mat_vend_header', 0.0, 1.60, 0.85, 0.85 * 241 / 1024, zf - 0.0015)
    # product window
    wcx, ww, wy0, wy1 = -0.115, 0.56, 0.38, 1.585
    mb.box('mat_charcoal', (wcx - ww / 2 - 0.02, wy0 - 0.02, zf - 0.006), (wcx + ww / 2 + 0.02, wy1 + 0.02, zf + 0.004), bevel=0.004)
    mb.fdecal('mat_vend_front', wcx, wy0, ww, wy1 - wy0, zf - 0.0065)
    mb.box('mat_glass', (wcx - ww / 2, wy0, zf - 0.012), (wcx + ww / 2, wy1, zf - 0.0105))
    for sx in (-1, 1):
        mb.box('mat_steel', (wcx + sx * (ww / 2 + 0.02) - 0.008, wy0 - 0.02, zf - 0.014), (wcx + sx * (ww / 2 + 0.02) + 0.008, wy1 + 0.02, zf - 0.004), bevel=0.003)
    mb.box('mat_steel', (wcx - ww / 2 - 0.02, wy1 + 0.005, zf - 0.014), (wcx + ww / 2 + 0.02, wy1 + 0.02, zf - 0.004), bevel=0.003)
    mb.box('mat_steel', (wcx - ww / 2 - 0.02, wy0 - 0.02, zf - 0.014), (wcx + ww / 2 + 0.02, wy0 - 0.005, zf - 0.004), bevel=0.003)
    # control column
    cx = 0.295
    mb.box('mat_steel', (cx - 0.11, 0.55, zf - 0.008), (cx + 0.11, 1.585, zf + 0.002), bevel=0.004)
    mb.box('mat_black_gloss', (cx - 0.09, 1.47, zf - 0.012), (cx + 0.09, 1.55, zf - 0.006), bevel=0.003)
    mb.fdecal('mat_vend_display', cx, 1.478, 0.16, 0.16 * 96 / 256, zf - 0.0122)
    for r in range(4):
        for k in range(3):
            x = cx - 0.055 + k * 0.055; y = 1.26 - r * 0.052
            mb.box('mat_key', (x - 0.02, y - 0.02, zf - 0.016), (x + 0.02, y + 0.02, zf - 0.008), bevel=0.003)
    mb.box('mat_charcoal', (cx - 0.06, 0.96, zf - 0.014), (cx + 0.06, 1.03, zf - 0.008), bevel=0.003)
    mb.box('mat_black_gloss', (cx - 0.004, 0.975, zf - 0.0145), (cx + 0.004, 1.015, zf - 0.0138))
    with mb.tf(Xf.T(cx, 0.85, zf - 0.008) * Xf.R('x', -90)):
        mb.tile('mat_gate_reader', -0.09, 0.09)
        mb.lathe('mat_steel_polished', [(0.044, 0.0), (0.044, 0.004), (0.039, 0.004), (0.039, 0.0)], seg=24)
        mb.lathe('mat_yellow', [(0.039, 0.0), (0.039, 0.0035), (0.033, 0.0035), (0.033, 0.0)], seg=24)
        mb.lathe('mat_gate_reader', [(0.033, 0.001), (0.0, 0.001)], seg=24)
    mb.box('mat_charcoal', (cx - 0.055, 0.66, zf - 0.014), (cx + 0.055, 0.72, zf - 0.008), bevel=0.003)
    mb.box('mat_yellow', (cx - 0.045, 0.683, zf - 0.0155), (cx + 0.045, 0.698, zf - 0.0135))
    mb.box('mat_black_gloss', (cx - 0.035, 0.6875, zf - 0.0158), (cx + 0.035, 0.6935, zf - 0.0152))
    mb.cyl('mat_steel_polished', (cx + 0.07, 0.585, zf - 0.008), (cx + 0.07, 0.585, zf - 0.016), 0.012, seg=12)
    # delivery bay
    mb.box('mat_black_gloss', (wcx - 0.27, 0.07, zf - 0.004), (wcx + 0.27, 0.345, zf + 0.01))
    mb.box('mat_steel', (wcx - 0.29, 0.335, zf - 0.02), (wcx + 0.29, 0.355, zf - 0.004), bevel=0.004)
    mb.box('mat_steel', (wcx - 0.29, 0.055, zf - 0.02), (wcx + 0.29, 0.075, zf - 0.004), bevel=0.004)
    fm = P.mb('flap', pivot=(wcx, 0.335, zf - 0.008), dirt=False, extras={'open_rotation_x_deg': -40.0})
    fm.box('mat_glass_smoked', (wcx - 0.26, 0.09, zf - 0.014), (wcx + 0.26, 0.335, zf - 0.008), bevel=0.0)
    fm.box('mat_steel', (wcx - 0.26, 0.09, zf - 0.020), (wcx + 0.26, 0.105, zf - 0.008), bevel=0.003)
    fm.box('mat_steel', (wcx - 0.26, 0.325, zf - 0.016), (wcx + 0.26, 0.338, zf - 0.006), bevel=0.003)
    # vent slots
    for k in range(8):
        mb.box('mat_black_plastic', (0.20, 0.10 + k * 0.03, zf - 0.001), (0.395, 0.114 + k * 0.03, zf))
    P.col_box('col_body-convcolonly', (-hx, 0, -hz), (hx, H, hz))


@prop('newsstand_kiosk',
      desc='Small station shop / newsagent kiosk: navy body, steel-capped counter, fascia sign, shelves of generic goods, magazine rack, till, '
           'roller shutter (separate node) and interior light strip.',
      origin='floor_centre', front='counter / opening faces -Z',
      nodes={'body': 'kiosk shell, shelves, goods, counter clutter', 'shutter': 'roller shutter; origin = TOP edge at (0,2.20,-0.80). Open by scale.y -> 0.03 (rolls up into the housing)',
             'kiosk_light': 'emissive interior light strip (own material mat_kiosk_light) - dimmable', 'col_body-convcolonly': 'collision'},
      slots={'mat_sign': 'fascia sign print (emissive)', 'mat_shutter': 'shutter slats', 'mat_goods': 'packaging atlas used by all stock', 'mat_mags': 'magazine covers',
             'mat_kiosk_light': 'emissive'},
      anim={'shutter': {'open_scale': [1.0, 0.03, 1.0], 'closed_scale': [1.0, 1.0, 1.0]}}, mount_height=0.0,
      notes=['3.24 x 2.04 x 2.7 m footprint incl. roof overhang. Shutter closed by default (covers the opening 2.6 x 1.14 m); tween shutter.scale.y 1 -> 0.03 to roll it up.'])
def newsstand_kiosk(P):
    _dm(P, 'mat_sign', 'kiosk_sign', emit=1.0, rough=0.3)
    _dm(P, 'mat_shutter', 'shutter', rough=0.35, metal=0.6)
    _dm(P, 'mat_goods', 'kiosk_goods', rough=0.5)
    _dm(P, 'mat_mags', 'kiosk_mags', rough=0.4)
    P.mat('mat_gate_reader', c='decals/gate_reader_c.png', rough=0.22, spec=0.6)
    P.mat('mat_kiosk_light', color=(1, 0.97, 0.9, 1), emit=(1.0, 0.95, 0.85), emit_strength=4.0, rough=0.5)
    P.mat('mat_laminate', color=(0.10, 0.11, 0.13, 1), rough=0.35)
    P.mat('mat_jar_r', color=(0.85, 0.1, 0.15, 1), rough=0.2, alpha=0.8, double=True)
    P.mat('mat_jar_y', color=(0.95, 0.8, 0.1, 1), rough=0.2, alpha=0.8, double=True)
    mb = P.mb('body')
    mb.tile('mat_goods', 0.5, 0.5)
    mb.tile('mat_shutter', 0.6, 0.6)
    rnd = random.Random(17)
    X0, X1, Z0, Z1 = -1.5, 1.5, -0.9, 0.9
    H = 2.6
    # plinth, counter, walls, roof
    mb.box('mat_charcoal', (X0, 0.0, Z0), (X1, 0.10, Z1), bevel=0.01)
    mb.box('mat_navy', (X0, 0.10, Z0), (X1, 1.02, Z0 + 0.30), bevel=0.012, seg=1)
    mb.box('mat_laminate', (X0 - 0.02, 1.02, Z0 - 0.04), (X1 + 0.02, 1.06, Z0 + 0.34), bevel=0.008, seg=1)
    mb.box('mat_steel', (X0 - 0.02, 1.02, Z0 - 0.045), (X1 + 0.02, 1.06, Z0 - 0.035), bevel=0.003)
    for k in range(5):                          # counter front panels
        xa = X0 + 0.15 + k * 0.57
        mb.box('mat_steel', (xa, 0.20, Z0 - 0.004), (xa + 0.02, 0.98, Z0 + 0.002))
    mb.box('mat_navy', (X0, 0.10, Z1 - 0.06), (X1, H, Z1), bevel=0.008, seg=1)                # back wall
    for sx in (X0, X1 - 0.06):                                                              # side walls
        mb.box('mat_navy', (sx, 0.10, Z0), (sx + 0.06, H, Z1), bevel=0.008, seg=1)
    for sx in (-1, 1):                                                                      # front posts
        mb.box('mat_navy', (sx * 1.30 - 0.10 + (0.1 * sx), 1.06, Z0), (sx * 1.30 + 0.10 + (0.1 * sx), H, Z0 + 0.20), bevel=0.01, seg=1) if False else None
    for sx in (-1, 1):
        xa = sx * 1.40
        mb.box('mat_navy', (xa - 0.10, 1.06, Z0), (xa + 0.10, H, Z0 + 0.22), bevel=0.01, seg=1)
    mb.box('mat_navy', (-1.5, 2.22, Z0), (1.5, H, Z0 + 0.30), bevel=0.012, seg=1)          # header beam
    mb.box('mat_charcoal', (-1.62, H, -1.02), (1.62, H + 0.09, 1.02), bevel=0.02, seg=2)      # roof
    mb.box('mat_steel', (-1.62, H - 0.005, -1.02), (1.62, H + 0.005, -1.0), bevel=0.002)
    mb.fdecal('mat_sign', 0.0, 2.245, 2.8, 0.35, Z0 - 0.0015)
    mb.box('mat_steel', (-1.42, 2.235, Z0 - 0.006), (1.42, 2.245, Z0 + 0.002))
    mb.box('mat_steel', (-1.42, 2.60 - 0.0, Z0 - 0.006), (1.42, 2.61, Z0 + 0.002))
    # shutter housing / guide rails
    mb.box('mat_charcoal', (-1.30, 2.14, Z0 + 0.03), (1.30, 2.22, Z0 + 0.25), bevel=0.01)
    for sx in (-1, 1):
        mb.box('mat_steel', (sx * 1.31 - 0.015 + (0.015 * sx), 1.06, Z0 + 0.03), (sx * 1.31 + 0.015 + (0.015 * sx), 2.14, Z0 + 0.07))
    # interior: floor, shelves, goods
    mb.box('mat_rubber', (X0 + 0.06, 0.10, Z0 + 0.30), (X1 - 0.06, 0.104, Z1 - 0.06))
    for k, y in enumerate((0.48, 0.92, 1.36, 1.80, 2.16)):
        mb.box('mat_steel', (X0 + 0.10, y, 0.50), (X1 - 0.10, y + 0.025, Z1 - 0.06), bevel=0.003)
        x = X0 + 0.16
        while x < X1 - 0.30:
            w = rnd.choice([0.10, 0.14, 0.18, 0.24])
            h = rnd.choice([0.14, 0.20, 0.26, 0.32]) if k < 4 else rnd.choice([0.10, 0.14])
            h = min(h, 0.40 if k < 4 else 0.10)
            d = rnd.choice([0.10, 0.16, 0.22])
            mb.box('mat_goods', (x, y + 0.025, 0.78 - d / 2 + rnd.uniform(-0.02, 0.02)), (x + w, y + 0.025 + h, 0.78 + d / 2), bevel=0.0,
                   off=(rnd.random(), rnd.random()))
            x += w + rnd.uniform(0.015, 0.05)
    # magazine rack on the counter (right) - two angled boards
    for k, (zc, yc) in enumerate(((-0.70, 1.10), (-0.70, 1.42))):
        with mb.tf(Xf.T(0.75, yc, zc) * Xf.R('x', -20)):
            mb.box('mat_steel', (-0.55, -0.01, -0.006), (0.55, 0.30, 0.006), bevel=0.0)
            mb.qdecal('mat_mags', (0.53, 0.0, -0.0075), (-1, 0, 0), (0, 1, 0), 1.06, 0.28, uvrect=(0.0, 0.5 * k, 1.0, 0.5 + 0.5 * k), hint=(0, 0, -1))
        mb.box('mat_steel', (0.20, yc - 0.02, zc - 0.02), (1.30, yc - 0.005, zc + 0.05))
    # counter clutter: till, jars, card reader
    mb.box('mat_charcoal', (-0.95, 1.06, -0.72), (-0.50, 1.20, -0.50), bevel=0.01, seg=1)
    with mb.tf(Xf.T(-0.72, 1.20, -0.61) * Xf.R('x', -25)):
        mb.box('mat_black_gloss', (-0.16, 0.0, -0.10), (0.16, 0.20, -0.08), bevel=0.004)
    with mb.tf(Xf.T(-0.30, 1.06, -0.62) * Xf.R('x', 0)):
        pass
    for k, m in enumerate(('mat_jar_r', 'mat_jar_y', 'mat_jar_r')):
        mb.cyl(m, (-0.10 + k * 0.17 - 0.2, 1.06, -0.66), (-0.10 + k * 0.17 - 0.2, 1.24, -0.66), 0.065, seg=14, bevel=0.005)
        mb.cyl('mat_steel_polished', (-0.10 + k * 0.17 - 0.2, 1.24, -0.66), (-0.10 + k * 0.17 - 0.2, 1.255, -0.66), 0.069, seg=14)
    with mb.tf(Xf.T(-1.15, 1.06, -0.62)):
        mb.box('mat_charcoal', (-0.07, 0.0, -0.07), (0.07, 0.10, 0.07), bevel=0.005)
        with mb.tf(Xf.T(0, 0.10, 0) * Xf.R('x', 0)):
            mb.lathe('mat_gate_reader', [(0.04, 0.0), (0.0, 0.0)], seg=16)
    # coin/tip tray + counter edge rail
    mb.box('mat_steel_polished', (-1.2, 1.06, -0.86), (-0.9, 1.065, -0.76))
    # interior light + shutter
    lm = P.mb('kiosk_light', pivot=(0.0, 2.10, -0.55), dirt=False, extras={'kind': 'light'})
    lm.box('mat_kiosk_light', (-1.2, 2.10, -0.60), (1.2, 2.115, -0.53))
    sm = P.mb('shutter', pivot=(0.0, 2.20, -0.80), dirt=False, extras={'open_scale': [1.0, 0.03, 1.0]})
    sm.tile('mat_shutter', 0.6, 0.6)
    sm.box('mat_shutter', (-1.30, 1.09, -0.84), (1.30, 2.20, -0.815), bevel=0.0)
    sm.box('mat_steel', (-1.30, 1.06, -0.86), (1.30, 1.09, -0.80), bevel=0.004)
    sm.box('mat_black_plastic', (-0.06, 1.10, -0.865), (0.06, 1.13, -0.84))
    P.col_box('col_body-convcolonly', (X0, 0, Z0), (X1, H, Z1))
