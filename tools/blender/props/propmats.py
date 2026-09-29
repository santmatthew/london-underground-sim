"""Blender material factory for the props (glTF-friendly Principled setups) + the shared material library.

Runs inside Blender. Textures come from assets/textures/props/{tile,decals,posters}.
"""
import os
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))
TEX = os.path.join(ROOT, 'assets', 'textures', 'props')

_imgcache = {}
IMAGES_USED = {}          # material name -> list of (relative file, w, h)


def load_img(rel, noncolor=False):
    key = (rel, noncolor)
    if key in _imgcache:
        return _imgcache[key]
    path = os.path.join(TEX, rel)
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    im = bpy.data.images.load(path, check_existing=False)
    im.colorspace_settings.name = 'Non-Color' if noncolor else 'sRGB'
    _imgcache[key] = im
    return im


def glTF_group():
    ng = bpy.data.node_groups.get('glTF Material Output')
    if ng is None:
        ng = bpy.data.node_groups.new('glTF Material Output', 'ShaderNodeTree')
        ng.interface.new_socket('Occlusion', in_out='INPUT', socket_type='NodeSocketFloat')
    return ng


def make_mat(name, c=None, n=None, orm=None, color=(1, 1, 1, 1), rough=0.5, metal=0.0, emit=None, emit_strength=0.0,
             emit_tex=False, alpha=None, double=False, spec=0.5, ior=None, aniso=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    if len(color) == 3:
        color = tuple(color) + (1.0,)
    bsdf.inputs['Base Color'].default_value = color
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    if 'Specular IOR Level' in bsdf.inputs:
        bsdf.inputs['Specular IOR Level'].default_value = spec
    if ior is not None and 'IOR' in bsdf.inputs:
        bsdf.inputs['IOR'].default_value = ior
    if aniso is not None and 'Anisotropic' in bsdf.inputs:
        bsdf.inputs['Anisotropic'].default_value = aniso
    used = []
    x = -700
    if c:
        t = nt.nodes.new('ShaderNodeTexImage'); t.location = (x, 300)
        t.image = load_img(c)
        used.append((c, t.image.size[0], t.image.size[1]))
        nt.links.new(t.outputs['Color'], bsdf.inputs['Base Color'])
        if alpha is not None and c.endswith('.png'):
            nt.links.new(t.outputs['Alpha'], bsdf.inputs['Alpha'])
        if emit_tex:
            nt.links.new(t.outputs['Color'], bsdf.inputs['Emission Color'])
    if n:
        t = nt.nodes.new('ShaderNodeTexImage'); t.location = (x, 0)
        t.image = load_img(n, True)
        used.append((n, t.image.size[0], t.image.size[1]))
        nm = nt.nodes.new('ShaderNodeNormalMap'); nm.location = (x + 300, 0)
        nt.links.new(t.outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    if orm:
        t = nt.nodes.new('ShaderNodeTexImage'); t.location = (x, -300)
        t.image = load_img(orm, True)
        used.append((orm, t.image.size[0], t.image.size[1]))
        sep = nt.nodes.new('ShaderNodeSeparateColor'); sep.location = (x + 300, -300)
        nt.links.new(t.outputs['Color'], sep.inputs['Color'])
        nt.links.new(sep.outputs['Green'], bsdf.inputs['Roughness'])
        nt.links.new(sep.outputs['Blue'], bsdf.inputs['Metallic'])
        g = nt.nodes.new('ShaderNodeGroup'); g.node_tree = glTF_group(); g.location = (x + 600, -500)
        nt.links.new(sep.outputs['Red'], g.inputs['Occlusion'])
    if emit is not None:
        if not emit_tex:
            bsdf.inputs['Emission Color'].default_value = tuple(emit) + (1.0,)
        bsdf.inputs['Emission Strength'].default_value = emit_strength
    if alpha is not None:
        if not (c and c.endswith('.png')):
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
    IMAGES_USED[name] = used
    return m


# ----------------------------------------------------------------------------------------- shared library
def _paint(name):
    return dict(c='tile/%s_c.jpg' % name, n='tile/paint_n.jpg', orm='tile/paint_orm.jpg')


LIB = {
    'mat_steel': dict(c='tile/steel_c.jpg', n='tile/steel_n.jpg', orm='tile/steel_orm.jpg'),
    'mat_steel_polished': dict(color=(0.80, 0.81, 0.83), rough=0.16, metal=1.0),
    'mat_chrome': dict(color=(0.92, 0.92, 0.94), rough=0.07, metal=1.0),
    'mat_charcoal': dict(c='tile/charcoal_c.jpg', n='tile/charcoal_n.jpg', orm='tile/charcoal_orm.jpg'),
    'mat_black_plastic': dict(color=(0.018, 0.019, 0.021), rough=0.38, metal=0.0),
    'mat_black_gloss': dict(color=(0.006, 0.007, 0.009), rough=0.08, metal=0.0, spec=0.7),
    'mat_rubber': dict(c='tile/rubber_c.jpg', n='tile/rubber_n.jpg', orm='tile/rubber_orm.jpg'),
    'mat_timber': dict(c='tile/timber_c.jpg', n='tile/timber_n.jpg', orm='tile/timber_orm.jpg'),
    'mat_blue': _paint('paint_blue'),
    'mat_white': _paint('paint_white'),
    'mat_red': _paint('paint_red'),
    'mat_yellow': _paint('paint_yellow'),
    'mat_grey': _paint('paint_grey'),
    'mat_navy': _paint('paint_navy'),
    'mat_glass': dict(color=(0.70, 0.86, 0.88), rough=0.03, metal=0.0, alpha=0.13, double=True, spec=0.8),
    'mat_glass_dark': dict(color=(0.02, 0.03, 0.035), rough=0.02, metal=0.0, alpha=0.72, double=True, spec=0.9),
    'mat_glass_smoked': dict(color=(0.03, 0.03, 0.035), rough=0.02, metal=0.0, alpha=0.55, double=True, spec=0.9),
    'mat_clear_plastic': dict(color=(0.85, 0.9, 0.92), rough=0.12, metal=0.0, alpha=0.20, double=True),
}


def build(names, extra=None):
    """create bpy materials for `names` from the library (and `extra` dict of prop-specific specs)."""
    out = {}
    for n in names:
        spec = None
        if extra and n in extra:
            spec = extra[n]
        elif n in LIB:
            spec = LIB[n]
        else:
            raise KeyError('unknown material ' + n)
        out[n] = make_mat(n, **spec)
    return out
