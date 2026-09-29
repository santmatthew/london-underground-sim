"""Prop registry, build context and Blender export (runs inside Blender)."""
import os, sys, json, math
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import propmesh
from propmesh import MB, Xf, to_blender
import propmats

ROOT = propmats.ROOT
OUTDIR = os.path.join(ROOT, 'assets', 'models', 'props')
STATDIR = os.path.join(ROOT, 'build', 'props_scratch', 'stats')

REGISTRY = {}      # name -> (fn, info)
ORDER = []

# metres per texture repeat for box-mapped materials (u, v)
TILES = {
    'mat_steel': (0.5, 0.5), 'mat_charcoal': (0.35, 0.35), 'mat_rubber': (0.25, 0.25), 'mat_timber': (0.5, 0.5),
    'mat_blue': (0.6, 0.6), 'mat_white': (0.6, 0.6), 'mat_red': (0.6, 0.6), 'mat_yellow': (0.6, 0.6),
    'mat_grey': (0.6, 0.6), 'mat_navy': (0.6, 0.6),
}
DIRTY = {'mat_steel', 'mat_charcoal', 'mat_rubber', 'mat_timber', 'mat_blue', 'mat_white', 'mat_red', 'mat_yellow',
         'mat_grey', 'mat_navy'}


def dirt_fn(mat, p, n):
    """vertex-colour multiplier: dirt / scuffing gathers near the floor, undersides slightly darker."""
    if mat not in DIRTY:
        return None
    y = max(p[1], 0.0)
    k = 1.0 - 0.34 * math.exp(-y / 0.11)
    if n[1] < -0.5:
        k *= 0.82
    return (k, k * 0.99, k * 0.96)


def prop(name, **info):
    def deco(fn):
        REGISTRY[name] = (fn, info)
        ORDER.append(name)
        return fn
    return deco


class Ctx:
    def __init__(self, name, info):
        self.name = name
        self.info = dict(info)
        self.parts = []            # dict(name, mb, pivot, extras)
        self.extra_mats = {}
        self.anim = {}
        self.collision = []        # (name, lo, hi)

    def mat(self, name, **spec):
        self.extra_mats[name] = spec
        return name

    def mb(self, name, pivot=(0.0, 0.0, 0.0), extras=None, dirt=True, smooth=40.0, grime=True):
        m = MB(name, smooth)
        m.tiles.update(TILES)
        if dirt:
            m.colfn = dirt_fn
            if grime:
                m.grime_levels = (0.03, 0.10, 0.25)
                m.grime_mats = set(DIRTY)
        self.parts.append(dict(name=name, mb=m, pivot=pivot, extras=extras or {}))
        return m

    def col_box(self, name, lo, hi):
        self.collision.append((name, lo, hi))


def clear_scene():
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.node_groups):
        for x in list(coll):
            coll.remove(x)
    propmats._imgcache.clear()
    propmats.IMAGES_USED.clear()


def box_mesh(name, lo, hi):
    """simple collision box object (Godot coords) named e.g. 'col_body-convcolonly'"""
    m = MB(name)
    m.box('mat_col', lo, hi)
    return m


def build_prop(name, export=True):
    fn, info = REGISTRY[name]
    ctx = Ctx(name, info)
    fn(ctx)
    clear_scene()
    # materials
    used = []
    for p in ctx.parts:
        for m in p['mb'].materials_used():
            if m not in used:
                used.append(m)
    M = propmats.build(used, ctx.extra_mats)
    # objects
    stats = {'name': name, 'parts': {}, 'materials': used}
    lo = [1e9] * 3; hi = [-1e9] * 3
    tris = 0
    for p in ctx.parts:
        mb = p['mb']
        if not mb.F:
            continue
        ob = to_blender(mb, bpy, M, p['name'], pivot=p['pivot'], dirty=DIRTY)
        for k, v in p['extras'].items():
            ob[k] = v
        bpy.context.scene.collection.objects.link(ob)
        t = mb.stats()
        stats['parts'][p['name']] = t
        tris += t
        b0, b1 = mb.bbox()
        for i in range(3):
            lo[i] = min(lo[i], b0[i]); hi[i] = max(hi[i], b1[i])
    # collision
    if ctx.collision:
        colmat = bpy.data.materials.new('mat_col')
        for (cname, clo, chi) in ctx.collision:
            cm = box_mesh(cname, clo, chi)
            ob = to_blender(cm, bpy, {'mat_col': colmat}, cname)
            bpy.context.scene.collection.objects.link(ob)
    stats['tris'] = tris
    stats['surfaces'] = sum(len(p['mb'].materials_used()) for p in ctx.parts if p['mb'].F)
    stats['meshes'] = sum(1 for p in ctx.parts if p['mb'].F)
    stats['bbox_lo'] = [round(v, 4) for v in lo]
    stats['bbox_hi'] = [round(v, 4) for v in hi]
    stats['size'] = [round(hi[i] - lo[i], 4) for i in range(3)]
    imgs = {}
    for m in used:
        for (rel, w, h) in propmats.IMAGES_USED.get(m, []):
            imgs[rel] = (w, h)
    stats['textures'] = {k: list(v) for k, v in imgs.items()}
    # BC7/DXT5 style: 1 byte / px + mips (x1.33); large albedo may be RGBA
    stats['texture_vram_mb'] = round(sum(w * h * 1.33 for (w, h) in imgs.values()) / 1048576.0, 3)
    stats['info'] = ctx.info
    stats['anim'] = ctx.anim
    stats['collision'] = [c[0] for c in ctx.collision]
    if export:
        os.makedirs(OUTDIR, exist_ok=True)
        path = os.path.join(OUTDIR, name + '.glb')
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_yup=True, export_apply=False,
                                  export_extras=True, export_image_format='AUTO', export_materials='EXPORT',
                                  export_texcoords=True, export_normals=True, export_cameras=False,
                                  export_lights=False, export_animations=False, export_skins=False,
                                  export_vertex_color='ACTIVE', use_selection=False)
        stats['glb_kb'] = round(os.path.getsize(path) / 1024.0, 1)
    os.makedirs(STATDIR, exist_ok=True)
    with open(os.path.join(STATDIR, name + '.json'), 'w') as f:
        json.dump(stats, f, indent=1)
    print('BUILT %-26s tris=%-6d size=%s glb=%s KB tex=%s MB parts=%s' % (
        name, tris, stats['size'], stats.get('glb_kb'), stats['texture_vram_mb'], stats['parts']))
    return stats
