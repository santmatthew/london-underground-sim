"""Procedural carried bags (CC0, generated here): backpack, shoulder (messenger), briefcase, handbag, tote.

    blender -b --factory-startup -P tools/blender/people/make_bags.py [-- --outdir DIR]

Authored in metres for a 1.75 m person in the character frame (X right, Y forward, Z up); the origin is the pivot:
 backpack / shoulder: bag centre;  briefcase / handbag / tote: top centre (grip point).  PersonModel places + scales them.
Vertex colour R = 1 on straps / handles (drives darker, rougher shading).
"""
import bpy, bmesh, sys, os, math
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = "/home/msant/Projects/Personal/underground-sim/assets/people/bags"
if "--outdir" in argv:
    OUT = argv[argv.index("--outdir") + 1]
os.makedirs(OUT, exist_ok=True)


def new_bm():
    return bmesh.new()


def box(bm, center, size, bevel=0.02, red=0.0, taper=0.0):
    before = set(bm.verts)
    res = bmesh.ops.create_cube(bm, size=1.0)
    verts = res["verts"]
    for v in verts:
        z_rel = v.co.z + 0.5
        f = 1.0 - taper * (1.0 - z_rel)
        v.co = Vector((v.co.x * size[0] * f, v.co.y * size[1], v.co.z * size[2])) + Vector(center)
    edges = list({e for v in verts for e in v.link_edges})
    if bevel > 0:
        r = bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=3, profile=0.55, affect='EDGES')
    new = [v for v in bm.verts if v not in before]
    for v in new:
        v[bm.verts.layers.float_color.active or bm.verts.layers.float_color.verify()] = (red, 0, 0, 1)
    return new


def ribbon(bm, pts, width, thick, red=1.0, normal_hint=Vector((0, 1, 0))):
    """flat ribbon along polyline pts (list of Vector)"""
    layer = bm.verts.layers.float_color.verify()
    rows = []
    n = len(pts)
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        side = t.cross(normal_hint)
        if side.length < 1e-4:
            side = t.cross(Vector((1, 0, 0)))
        side.normalize()
        up = side.cross(t).normalized()
        row = []
        for sx, sy in ((-1, 1), (1, 1), (1, -1), (-1, -1)):
            v = bm.verts.new(p + side * sx * width / 2 + up * sy * thick / 2)
            v[layer] = (red, 0, 0, 1)
            row.append(v)
        rows.append(row)
    for a, b in zip(rows[:-1], rows[1:]):
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bm.faces.new(rows[0][::-1])
    bm.faces.new(rows[-1])


def arc(p0, p1, height, n=8, axis=Vector((0, 0, 1))):
    pts = []
    for i in range(n + 1):
        t = i / n
        p = p0.lerp(p1, t) + axis * math.sin(t * math.pi) * height
        pts.append(p)
    return pts


def planar_uv(bm, scale=3.0):
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a, b = [i for i in range(3) if i != ax]
        for l in f.loops:
            l[uv].uv = (l.vert.co[a] * scale, l.vert.co[b] * scale)


def finish(name, bm):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    planar_uv(bm)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new("bag")
    mat.use_nodes = True
    me.materials.append(mat)
    # colour attribute from bmesh float_color layer is stored as 'Col'? make sure the active one exists
    return ob


def backpack():
    bm = new_bm()
    bm.verts.layers.float_color.verify()
    box(bm, (0, 0, 0), (0.30, 0.15, 0.44), bevel=0.045, taper=0.10)
    box(bm, (0, -0.10, -0.10), (0.22, 0.06, 0.20), bevel=0.02, taper=0.05)      # front pocket (-Y = forward/chest side)
    # straps over the shoulders, torso surface at y=-0.075 (back) .. -0.295 (front); body axis y=-0.185
    for sx in (-1, 1):
        x = 0.105 * sx
        pts = [Vector(p) for p in [(x, -0.07, 0.19), (x, -0.09, 0.26), (x * 1.05, -0.13, 0.31), (x * 1.05, -0.19, 0.325),
                                   (x * 1.05, -0.26, 0.31), (x * 1.08, -0.305, 0.22), (x * 1.10, -0.31, 0.08),
                                   (x * 1.35, -0.25, -0.03), (x * 1.45, -0.15, -0.06), (x * 1.0, -0.075, -0.13)]]
        ribbon(bm, pts, 0.05, 0.012, red=1.0, normal_hint=Vector((0, 0, 1)))
    # top grab loop
    ribbon(bm, arc(Vector((-0.04, 0.0, 0.22)), Vector((0.04, 0.0, 0.22)), 0.04), 0.02, 0.01, red=1.0, normal_hint=Vector((0, 1, 0)))
    return finish("Bag", bm)


def shoulder():
    bm = new_bm()
    bm.verts.layers.float_color.verify()
    box(bm, (0, 0, 0), (0.34, 0.10, 0.26), bevel=0.02, taper=0.05)
    box(bm, (0, -0.005, 0.10), (0.35, 0.106, 0.07), bevel=0.012, red=0.4)      # flap
    # strap: bag top corners up over the near shoulder
    pts = [Vector(p) for p in [(-0.16, 0.0, 0.13), (-0.13, -0.03, 0.30), (-0.05, -0.06, 0.52), (0.02, -0.08, 0.62), (0.10, -0.09, 0.60)]]
    ribbon(bm, pts, 0.04, 0.01, red=1.0, normal_hint=Vector((0, 1, 0)))
    pts = [Vector(p) for p in [(0.16, 0.0, 0.13), (0.14, -0.03, 0.30), (0.12, -0.06, 0.50), (0.10, -0.09, 0.60)]]
    ribbon(bm, pts, 0.04, 0.01, red=1.0, normal_hint=Vector((0, 1, 0)))
    return finish("Bag", bm)


def briefcase():
    bm = new_bm()
    bm.verts.layers.float_color.verify()
    box(bm, (0, 0, -0.17), (0.09, 0.42, 0.30), bevel=0.012)
    box(bm, (0, 0, -0.02), (0.05, 0.10, 0.02), bevel=0.004, red=1.0)
    ribbon(bm, arc(Vector((0, -0.09, -0.02)), Vector((0, 0.09, -0.02)), 0.045, 10, Vector((1, 0, 0))), 0.02, 0.012, red=1.0, normal_hint=Vector((1, 0, 0)))
    return finish("Bag", bm)


def handbag():
    bm = new_bm()
    bm.verts.layers.float_color.verify()
    box(bm, (0, 0, -0.17), (0.11, 0.30, 0.20), bevel=0.02, taper=0.12)
    ribbon(bm, arc(Vector((0, -0.09, -0.06)), Vector((0, 0.09, -0.06)), 0.09, 12, Vector((0, 0, 1))), 0.018, 0.01, red=1.0, normal_hint=Vector((1, 0, 0)))
    return finish("Bag", bm)


def tote():
    bm = new_bm()
    bm.verts.layers.float_color.verify()
    box(bm, (0, 0, -0.27), (0.10, 0.34, 0.34), bevel=0.012, taper=-0.05)
    for sy in (-0.06, 0.06):
        ribbon(bm, arc(Vector((0, sy - 0.03, -0.11)), Vector((0, sy + 0.03, -0.11)), 0.10, 10, Vector((0, 0, 1))), 0.03, 0.01, red=1.0, normal_hint=Vector((1, 0, 0)))
    ribbon(bm, [Vector((0, -0.13, -0.11)), Vector((0, -0.09, 0.0)), Vector((0, -0.03, -0.11))], 0.03, 0.01, red=1.0, normal_hint=Vector((1, 0, 0)))
    ribbon(bm, [Vector((0, 0.13, -0.11)), Vector((0, 0.09, 0.0)), Vector((0, 0.03, -0.11))], 0.03, 0.01, red=1.0, normal_hint=Vector((1, 0, 0)))
    return finish("Bag", bm)


for name, fn in (("backpack", backpack), ("shoulder", shoulder), ("briefcase", briefcase), ("handbag", handbag), ("tote", tote)):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    ob = fn()
    # Blender colour attribute name for bmesh float_color layer is preserved as 'Col'/'Color'
    me = ob.data
    if not me.color_attributes:
        print("WARNING no colour attr for", name)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    path = os.path.join(OUT, "bag_%s.glb" % name)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True, export_apply=False,
                              export_image_format='NONE', export_materials='EXPORT', export_vertex_color='ACTIVE',
                              export_normals=True, export_texcoords=True, export_cameras=False, export_lights=False)
    print("bag", name, "tris", sum(len(p.vertices) - 2 for p in me.polygons), path)
