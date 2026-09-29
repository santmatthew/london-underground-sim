"""Advertising frames: poster_frame_4sheet, poster_frame_6sheet, poster_frame_48sheet."""
import math
from propcore import prop
from propmesh import Xf


def _poster_mats(P, landscape, emit):
    tex = 'decals/poster_ph_landscape_c.jpg' if landscape else 'decals/poster_ph_portrait_c.jpg'
    P.mat('mat_poster', c=tex, rough=0.45, emit=(1, 1, 1), emit_tex=True, emit_strength=emit, spec=0.4)
    P.mat('mat_glass_thin', color=(0.85, 0.92, 0.95, 1), rough=0.02, alpha=0.05, double=True, spec=0.5)
    P.mat('mat_backlight', color=(1, 0.97, 0.90, 1), emit=(1.0, 0.97, 0.90), emit_strength=3.0, rough=0.5)


def _lightbox(P, W, H, D, bar, emit, glass=True, lamp_bar=False, landscape=False):
    _poster_mats(P, landscape, emit)
    mb = P.mb('body')
    # frame bars (brushed aluminium, full depth) + charcoal back panel
    bv = min(0.006, bar * 0.2)
    mb.box('mat_charcoal', (-W / 2 + bar, bar, -0.02), (W / 2 - bar, H - bar, 0.0))
    mb.box('mat_steel', (-W / 2, 0.0, -D), (-W / 2 + bar, H, 0.0), bevel=bv, seg=1)
    mb.box('mat_steel', (W / 2 - bar, 0.0, -D), (W / 2, H, 0.0), bevel=bv, seg=1)
    mb.box('mat_steel', (-W / 2 + bar, 0.0, -D), (W / 2 - bar, bar, 0.0), bevel=bv, seg=1)
    mb.box('mat_steel', (-W / 2 + bar, H - bar, -D), (W / 2 - bar, H, 0.0), bevel=bv, seg=1)
    # inner reveal / diffuser back plate
    ow, oh = W - 2 * bar, H - 2 * bar
    mb.box('mat_white', (-ow / 2, bar, -D + 0.05), (ow / 2, H - bar, -D + 0.055))
    if glass:
        mb.box('mat_glass_thin', (-ow / 2 - 0.002, bar, -D + 0.0035), (ow / 2 + 0.002, H - bar, -D + 0.0055))
    # small details: lock + vent slots
    lk = (W / 2 - bar / 2, bar + 0.06 if bar < 0.1 else H * 0.5, -D - 0.0005)
    if not landscape:
        mb.cyl('mat_steel_polished', (W / 2 - bar / 2, H * 0.5, -D), (W / 2 - bar / 2, H * 0.5, -D - 0.006), min(0.012, bar * 0.3), seg=12)
        mb.box('mat_black_gloss', (W / 2 - bar / 2 - 0.0015, H * 0.5 - 0.006, -D - 0.0065), (W / 2 - bar / 2 + 0.0015, H * 0.5 + 0.006, -D - 0.006))
        for k in range(7):
            x = -0.30 + k * 0.10
            mb.box('mat_black_gloss', (x * (W / 1.2), H - 0.006, -0.06), (x * (W / 1.2) + 0.05, H + 0.0005, -0.03))
    # poster (own node) slightly smaller than the opening so the backlight rim shows
    gap = 0.006
    pw, ph = ow - 2 * gap, oh - 2 * gap
    pm = P.mb('poster', pivot=(0.0, H / 2, -D + 0.048), dirt=False)
    pm.fdecal('mat_poster', 0.0, bar + gap, pw, ph, -D + 0.05 - 0.002)
    # backlight rim
    bm = P.mb('backlight', pivot=(0.0, H / 2, -D + 0.05), dirt=False, extras={'kind': 'backlight', 'note': 'dim via material mat_backlight emission_energy'})
    z = -D + 0.05 - 0.0025
    bm.box('mat_backlight', (-ow / 2, bar, z), (ow / 2, bar + gap, z + 0.001))
    bm.box('mat_backlight', (-ow / 2, H - bar - gap, z), (ow / 2, H - bar, z + 0.001))
    bm.box('mat_backlight', (-ow / 2, bar + gap, z), (-ow / 2 + gap, H - bar - gap, z + 0.001))
    bm.box('mat_backlight', (ow / 2 - gap, bar + gap, z), (ow / 2, H - bar - gap, z + 0.001))
    return mb


@prop('poster_frame_6sheet',
      desc='Portrait 6-sheet backlit advertising light-box (1.2 x 1.8 m): brushed aluminium frame, glazing, poster on its own node.',
      origin='wall_back_bottom_centre', front='poster faces -Z; back plane at z=0',
      nodes={'body': 'frame, glazing, diffuser', 'poster': 'poster quad (own node) with mat_poster', 'backlight': 'thin emissive rim (own material mat_backlight) - dimmable'},
      slots={'mat_poster': 'the picture: albedo + emission texture. Retarget albedo_texture AND emission_texture (or reuse the same texture); portrait 2:3 (1024x1536)',
             'mat_backlight': 'emission_energy_multiplier = brightness of the light-box'},
      anim={}, mount_height=0.45,
      notes=['Outer 1.20 x 1.80 x 0.10 m; visible picture 1.12 x 1.72 m (frame bar 0.04). Dim: set mat_poster.emission_energy_multiplier (0.55 default) and mat_backlight.emission_energy_multiplier (3.0).'])
def poster_frame_6sheet(P):
    _lightbox(P, 1.20, 1.80, 0.10, 0.04, 0.55)


@prop('poster_frame_4sheet',
      desc='Portrait 4-sheet backlit advertising light-box (1.0 x 1.4 m).',
      origin='wall_back_bottom_centre', front='poster faces -Z; back plane at z=0',
      nodes={'body': 'frame, glazing', 'poster': 'poster quad (own node)', 'backlight': 'emissive rim'},
      slots={'mat_poster': 'picture (portrait)', 'mat_backlight': 'brightness'}, anim={}, mount_height=0.5,
      notes=['Outer 1.00 x 1.40 x 0.08 m; visible picture 0.93 x 1.33 m.'])
def poster_frame_4sheet(P):
    _lightbox(P, 1.00, 1.40, 0.08, 0.035, 0.55)


@prop('poster_frame_48sheet',
      desc='Landscape 48-sheet cross-track billboard frame (6.1 x 3.05 m): dark steel frame with top lamp trough, poster on its own node.',
      origin='wall_back_bottom_centre', front='poster faces -Z; back plane at z=0',
      nodes={'body': 'frame + lamp trough', 'poster': 'poster quad (own node)', 'backlight': 'emissive rim + lamp strip (own material mat_backlight)'},
      slots={'mat_poster': 'picture (landscape 2:1, 2048x1024)', 'mat_backlight': 'brightness of the lamp strip/rim'}, anim={}, mount_height=1.0,
      notes=['Outer 6.10 x 3.05 x 0.30 m (incl. lamp trough), visible picture 5.90 x 2.87 m. Poster emission default 0.35 (front lit); raise for backlit look.'])
def poster_frame_48sheet(P):
    W, H, D, bar = 6.10, 3.05, 0.14, 0.10
    mb = _lightbox(P, W, H, D, bar, 0.35, glass=False, landscape=True)
    # lamp trough along the top
    mb.box('mat_charcoal', (-W / 2, H, -0.26), (W / 2, H + 0.09, 0.0), bevel=0.01)
    mb.box('mat_steel', (-W / 2, H + 0.09, -0.26), (W / 2, H + 0.11, 0.0), bevel=0.004)
    for k in range(9):
        x = -W / 2 + 0.35 + k * (W - 0.7) / 8
        with mb.tf(Xf.T(x, H, -0.18) * Xf.R('x', -35)):
            mb.box('mat_steel', (-0.05, 0.0, -0.13), (0.05, 0.05, 0.0), bevel=0.004)
        mb.box('mat_steel', (x - 0.012, H - 0.02, -0.03), (x + 0.012, H + 0.02, 0.0))
    lm = P.mb('lamp_strip', pivot=(0.0, H + 0.02, -0.26), dirt=False, extras={'kind': 'backlight'})
    lm.box('mat_backlight', (-W / 2 + 0.3, H - 0.01, -0.255), (W / 2 - 0.3, H + 0.005, -0.24))
    # feet brackets
    for x in (-W / 2 + 0.6, 0.0, W / 2 - 0.6):
        mb.box('mat_charcoal', (x - 0.05, -0.05, -0.16), (x + 0.05, 0.10, 0.0), bevel=0.006)
