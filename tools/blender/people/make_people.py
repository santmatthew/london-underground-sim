"""Build the crowd characters with MPFB and export them as glb.

    blender -b --factory-startup -P tools/blender/people/make_people.py -- [id ...] [--outdir DIR] [--nobags]

Per character output (default assets/people/):
    chars/person_NN.glb          one skinned mesh (4 surfaces: skin, face, outfit, hair) + skeleton (game_engine rig,
                                 all bone rest orientations normalised to identity, character faces -Z, feet at y=0)
    chars/person_NN.info.json    build statistics, atlas layout, rig rest data (used by the retargeter / manifest)
"""
import bpy, bmesh, sys, os, json, math, traceback, time, random
from mathutils import Vector, Matrix, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import people_spec as PS

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUTDIR = os.path.join(PS.PROJECT, "assets", "people")
NOBAGS = False
ids = []
i = 0
while i < len(argv):
    if argv[i] == "--outdir":
        OUTDIR = argv[i + 1]; i += 2; continue
    if argv[i] == "--nobags":
        NOBAGS = True; i += 1; continue
    ids.append(argv[i]); i += 1

bpy.ops.preferences.addon_enable(module="bl_ext.user_default.mpfb")
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.assetservice import AssetService

BONES_ORDER = None
FACE_TILE_KEYS = PS.FACE_ATLAS["tiles"]


def reset_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images, bpy.data.node_groups):
        for d in list(coll):
            if d.users == 0:
                coll.remove(d)
    try:
        bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    except Exception:
        pass


def tris_of(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def select_only(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def strip_shape_keys(obj):
    if obj.data.shape_keys:
        select_only(obj)
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)


def bmesh_delete_verts(obj, predicate):
    """delete vertices for which predicate(vert, weights_dict)->True (weights: {group_name: weight})"""
    me = obj.data
    names = {vg.index: vg.name for vg in obj.vertex_groups}
    bm = bmesh.new()
    bm.from_mesh(me)
    dl = bm.verts.layers.deform.verify()
    dead = []
    for v in bm.verts:
        w = {names[g]: val for g, val in v[dl].items() if g in names}
        if predicate(v, w):
            dead.append(v)
    bmesh.ops.delete(bm, geom=dead, context='VERTS')
    # loose verts
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(me)
    bm.free()
    me.update()


def find_parts(rig, spec):
    """map object -> category using the asset names we requested."""
    parts = {}
    for o in rig.children:
        if o.type != 'MESH':
            continue
        n = o.name.split(".", 1)[1] if "." in o.name else o.name
        parts[n] = o
    return parts


def decimate_to(obj, target_tris):
    t = tris_of(obj)
    if t <= target_tris:
        return
    select_only(obj)
    m = obj.modifiers.new("Dec", 'DECIMATE')
    m.decimate_type = 'COLLAPSE'
    m.ratio = max(0.08, target_tris / float(t))
    m.use_collapse_triangulate = True
    m.delimit = {'UV'}
    while obj.modifiers[0].name != "Dec":
        bpy.ops.object.modifier_move_up(modifier="Dec")
    bpy.ops.object.modifier_apply(modifier="Dec")


def remap_uv(obj, tile):
    u0, v0, su, sv = tile
    uvl = obj.data.uv_layers.active
    pad = 0.006  # keep away from tile borders (mip bleed)
    for d in uvl.data:
        u, v = d.uv
        u = min(max(u, 0.0), 1.0)
        v = min(max(v, 0.0), 1.0)
        d.uv = (u0 + (pad + u * (1 - 2 * pad)) * su, v0 + (pad + v * (1 - 2 * pad)) * sv)


def set_vcol(obj, rgba):
    me = obj.data
    for ca in list(me.color_attributes):
        me.color_attributes.remove(ca)
    ca = me.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='POINT')
    n = len(me.vertices)
    ca.data.foreach_set("color", list(rgba) * n)
    me.color_attributes.active_color = ca
    me.color_attributes.render_color_index = 0


def set_vcol_scalp(body_obj, cat, rough):
    """skin vertex colour R = how much of the vertex is covered by hair cards (-> darkened towards hair colour)"""
    from mathutils.bvhtree import BVHTree
    me = body_obj.data
    hair = [o for o, c in cat.items() if c == "hair"]
    eyes = [o for o, c in cat.items() if c == "eyes"]
    mask = [0.0] * len(me.vertices)
    if hair and eyes:
        zeye = sum(v.co.z for v in eyes[0].data.vertices) / len(eyes[0].data.vertices)
        bm = bmesh.new()
        bm.from_mesh(hair[0].data)
        tree = BVHTree.FromBMesh(bm)
        for v in me.vertices:
            if v.co.z < zeye - 0.005:
                continue
            loc, nor, idx, dist = tree.find_nearest(v.co)
            if dist is None:
                continue
            if v.co.z < zeye + 0.035:
                continue
            t = min(max((0.016 - dist) / (0.016 - 0.006), 0.0), 1.0)
            mask[v.index] = t * t * (3 - 2 * t)
        bm.free()
    for ca in list(me.color_attributes):
        me.color_attributes.remove(ca)
    ca = me.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='POINT')
    flat = []
    for m in mask:
        flat += [m, 0.0, 0.0, rough]
    ca.data.foreach_set("color", flat)
    me.color_attributes.active_color = ca
    me.color_attributes.render_color_index = 0


def make_material(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    return m


def tag(obj):
    return obj


FINGER_ANG = {"index": (12, 20, 12), "middle": (16, 24, 14), "ring": (20, 26, 16), "pinky": (24, 28, 18),
              "thumb": (8, 12, 8)}


def decimate_body(body, target_tris):
    """weighted collapse: keep the face, thin out hands and the rest"""
    t = tris_of(body)
    if t <= target_tris:
        return
    me = body.data
    names = {g.index: g.name for g in body.vertex_groups}
    vg = body.vertex_groups.new(name="_dec")
    face_bones = ("head", "neck_01")
    for v in me.vertices:
        ws = {names[g.group]: g.weight for g in v.groups}
        best = max(ws, key=ws.get) if ws else ""
        if best in face_bones:
            w = 1.0
        elif best.startswith(("hand_", "index_", "middle_", "ring_", "pinky_", "thumb_")):
            w = 0.12
        else:
            w = 0.45
        vg.add([v.index], w, 'REPLACE')
    select_only(body)
    m = body.modifiers.new("Dec", 'DECIMATE')
    m.decimate_type = 'COLLAPSE'
    m.ratio = max(0.1, target_tris / float(t))
    m.vertex_group = "_dec"
    m.vertex_group_factor = 1.0
    m.use_collapse_triangulate = True
    while body.modifiers[0].name != "Dec":
        bpy.ops.object.modifier_move_up(modifier="Dec")
    bpy.ops.object.modifier_apply(modifier="Dec")
    body.vertex_groups.remove(body.vertex_groups["_dec"])


def relax_fingers(rig, body, heads, tails, L):
    """bake a relaxed hand pose into the rest pose (mesh + bones) so no per-frame finger tracks are needed"""
    poses = {}
    newheads = {}
    axes = {}
    for side in ("l", "r"):
        hand = heads["hand_" + side]
        i1 = heads["index_01_" + side]
        p1 = heads["pinky_01_" + side]
        m1 = heads["middle_01_" + side]
        across = (i1 - p1).normalized()
        fwd = (m1 - hand).normalized()
        n = across.cross(fwd).normalized()
        want = Vector((1, 0, 0)) if side == "l" else Vector((-1, 0, 0))
        if n.dot(want) < 0:
            n = -n
        for f, angs in FINGER_ANG.items():
            names = ["%s_0%d_%s" % (f, k, side) for k in (1, 2, 3)]
            d = (tails[names[2]] - heads[names[0]]).normalized()
            axis = d.cross(n)
            if axis.length < 1e-6:
                continue
            axis.normalize()
            qs = [Quaternion(axis, math.radians(a)) for a in angs]
            for nm, q in zip(names, qs):
                poses[nm] = q
                axes[nm] = list(axis)
            Racc = Matrix.Identity(3)
            for k in range(2):
                Racc = Racc @ qs[k].to_matrix()
                off = heads[names[k + 1]] - heads[names[k]]
                newheads[names[k + 1]] = newheads.get(names[k], heads[names[k]]) + Racc @ off
    select_only(rig)
    bpy.ops.object.mode_set(mode='POSE')
    for nm, q in poses.items():
        pb = rig.pose.bones[nm]
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = q
    bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode='OBJECT')
    select_only(body)
    bpy.ops.object.modifier_apply(modifier="Armature")
    select_only(rig)
    bpy.ops.object.mode_set(mode='POSE')
    for nm in poses:
        rig.pose.bones[nm].rotation_quaternion = Quaternion((1, 0, 0, 0))
    bpy.ops.object.mode_set(mode='EDIT')
    for nm, h in newheads.items():
        eb = rig.data.edit_bones[nm]
        eb.head = h
        eb.tail = h + Vector((0, L, 0))
        eb.roll = 0.0
    bpy.ops.object.mode_set(mode='OBJECT')
    mod = body.modifiers.new("Armature", 'ARMATURE')
    mod.object = rig
    return newheads, axes


SHOULDER_GROUPS = ("clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r")


def smooth_shoulder_weights(obj, iters, factor):
    """laplacian smoothing of the deform weights around the shoulders / upper arms"""
    me = obj.data
    names = {g.index: g.name for g in obj.vertex_groups}
    sh_idx = {i for i, n in names.items() if n in SHOULDER_GROUPS}
    bm = bmesh.new()
    bm.from_mesh(me)
    dl = bm.verts.layers.deform.verify()
    region = set()
    for v in bm.verts:
        if any(g in sh_idx and w > 0.02 for g, w in v[dl].items()):
            region.add(v.index)
    bm.verts.ensure_lookup_table()
    for _ in range(iters):
        new = {}
        for vi in region:
            v = bm.verts[vi]
            nb = [e.other_vert(v) for e in v.link_edges]
            if not nb:
                continue
            acc = {}
            for u in nb:
                for g, w in u[dl].items():
                    acc[g] = acc.get(g, 0.0) + w / len(nb)
            cur = dict(v[dl].items())
            res = {}
            for g in set(acc) | set(cur):
                res[g] = (1 - factor) * cur.get(g, 0.0) + factor * acc.get(g, 0.0)
            new[vi] = res
        for vi, res in new.items():
            v = bm.verts[vi]
            for g in list(v[dl].keys()):
                del v[dl][g]
            for g, w in res.items():
                if w > 0.003:
                    v[dl][g] = w
    bm.to_mesh(me)
    bm.free()
    me.update()


def build(spec):
    t0 = time.time()
    reset_scene()
    race = PS.RACE[spec["race"]]
    hi = HumanService._create_default_human_info_dict()
    hi["phenotype"].update(dict(gender=spec["gender"], age=PS.age_slider(spec["age"]), muscle=spec["muscle"],
                                weight=spec["weight"], proportions=spec["proportions"],
                                height=PS.height_slider(spec["gender"], race, spec["height"]),
                                cupsize=spec.get("cup", 0.5), firmness=0.5))
    hi["phenotype"]["race"] = dict(asian=race[0], caucasian=race[1], african=race[2])
    hi["rig"] = "game_engine"
    hi["eyes"] = "low-poly.mhclo"
    hi["eyebrows"] = spec["brows"] + ".mhclo"
    hi["eyelashes"] = spec["lashes"] + ".mhclo"
    hi["hair"] = (spec["hair"] + ".mhclo") if spec["hair"] else ""
    hi["clothes_material_type"] = "NONE"
    hi["eyes_material_type"] = "NONE"
    hi["skin_material_type"] = "NONE"
    hi["skin_mhmat"] = ""
    clothes = []
    for item, slot, col in spec["garments"]:
        clothes.append(item + ".mhclo")
    if spec.get("glasses"):
        clothes.append(spec["glasses"] + ".mhclo")
    if spec.get("hat"):
        clothes.append(spec["hat"] + ".mhclo")
    hi["clothes"] = clothes
    s = HumanService.get_default_deserialization_settings()
    s["subdiv_levels"] = 0
    s["mask_helpers"] = False
    s["detailed_helpers"] = True
    s["extra_vertex_groups"] = False
    s["feet_on_ground"] = True
    s["material_instances"] = "NEVER"
    s["scale"] = 0.1
    bm_obj = HumanService.deserialize_from_dict(hi, s)
    rig = bm_obj.parent
    assert rig is not None and rig.type == 'ARMATURE', "no rig"
    parts = find_parts(rig, spec)
    body = bm_obj
    print("  parts:", {k: (len(v.data.vertices), tris_of(v)) for k, v in parts.items()})

    # ---- bake shape keys (macro details) into the base mesh
    strip_shape_keys(body)
    for o in list(parts.values()):
        if o is not body:
            strip_shape_keys(o)

    # ---- cut helper geometry + body parts hidden under clothes
    bone_names = {b.name for b in rig.data.bones}
    del_groups = [vg.name for vg in body.vertex_groups if vg.name.startswith("Delete.")]

    def body_pred(v, w):
        if w.get("body", 0.0) < 0.5:
            return True
        # feet are always inside shoes: drop everything that is mainly foot / toe
        bw = {k: val for k, val in w.items() if k in bone_names}
        if bw and max(bw, key=bw.get) in ("foot_l", "foot_r", "ball_l", "ball_r"):
            return True
        for g in del_groups:
            if w.get(g, 0.0) > 0.5:
                return True
        return False
    nb = len(body.data.vertices)
    bmesh_delete_verts(body, body_pred)
    print('  body verts', nb, '->', len(body.data.vertices), 'del_groups', del_groups)
    if os.environ.get("PEOPLE_DEBUG"):
        from collections import Counter
        nm = {vg.index: vg.name for vg in body.vertex_groups}
        cc = Counter()
        for v in body.data.vertices:
            ws = {nm[g.group]: g.weight for g in v.groups if nm[g.group] in bone_names}
            cc[max(ws, key=ws.get) if ws else 'none'] += 1
        print('  remaining by bone', cc.most_common(12))

    # ---- weights: keep only bone groups, max 4 influences
    all_meshes = [o for o in parts.values()]
    for o in all_meshes:
        for vg in list(o.vertex_groups):
            if vg.name not in bone_names:
                o.vertex_groups.remove(vg)
        select_only(o)
        bpy.ops.object.vertex_group_limit_total(group_select_mode='BONE_DEFORM', limit=4)
        bpy.ops.object.vertex_group_normalize_all(group_select_mode='BONE_DEFORM', lock_active=False)
        for m in list(o.modifiers):
            if m.type != 'ARMATURE':
                o.modifiers.remove(m)

    # ---- classify parts
    cat = {}
    for n, o in parts.items():
        if o is body:
            cat[o] = "skin"
        elif n == "low-poly" or n == "high-poly":
            cat[o] = "eyes"
        elif n.startswith("eyebrow") or n.startswith("mindfront_eyebrows"):
            cat[o] = "brows"
        elif n.startswith("eyelashes") or n.startswith("mindfront_eyelashes"):
            cat[o] = "lashes"
        elif spec["hair"] and n == spec["hair"]:
            cat[o] = "hair"
        elif spec.get("glasses") and n == spec["glasses"]:
            cat[o] = "glasses"
        elif spec.get("hat") and n == spec["hat"]:
            cat[o] = "hat"
        else:
            cat[o] = None
    slot_of = {item: slot for item, slot, col in spec["garments"]}
    colour_of = {item: col for item, slot, col in spec["garments"]}
    for n, o in parts.items():
        if cat[o] is None:
            cat[o] = slot_of.get(n, "top")

    # ---- body / garment decimation
    stats_pre = {}
    decimate_body(body, 8500)
    budget = {"main": 7500, "top": 3800, "bottom": 3800, "outer": 3800, "shoes": 1800, "hat": 1200, "glasses": 1500,
              "hair": 4500}
    for o, c in cat.items():
        stats_pre[o.name] = tris_of(o)
        if c in budget:
            decimate_to(o, budget[c])

    # ---- drop body skin that lies under / just poking through the (decimated) clothing
    cover_cats = ("top", "bottom", "main", "outer")
    cloth_trees = []
    from mathutils.bvhtree import BVHTree
    from mathutils.kdtree import KDTree
    for o, c in cat.items():
        if c in cover_cats:
            bmc = bmesh.new()
            bmc.from_mesh(o.data)
            bmc.faces.ensure_lookup_table()
            bverts = [v.co.copy() for v in bmc.verts if any(e.is_boundary for e in v.link_edges)]
            kd = KDTree(max(len(bverts), 1))
            for bi, co in enumerate(bverts):
                kd.insert(co, bi)
            kd.balance()
            cloth_trees.append((BVHTree.FromBMesh(bmc), bmc, kd, len(bverts)))
    if cloth_trees:
        bnames = {g.index: g.name for g in body.vertex_groups}

        def under_cloth(v, w):
            bw = {k: val for k, val in w.items() if k in bone_names}
            dom = max(bw, key=bw.get) if bw else ""
            if dom in ("head", "neck_01") or dom.startswith(("hand_", "index_", "middle_", "ring_", "pinky_", "thumb_")):
                return False
            for tree, _b, kd, nb_ in cloth_trees:
                loc, nor, fidx, dist = tree.find_nearest(v.co, 0.03)
                if loc is None or dist is None:
                    continue
                if nb_ and kd.find(v.co)[2] < 0.035:
                    continue      # near the garment's open edge (neckline / cuff / hem): keep the skin
                d = (v.co - loc).dot(nor)
                if abs(abs(d) - dist) < 0.002 and d < 0.010:
                    return True
            return False
        nb2 = len(body.data.vertices)
        bmesh_delete_verts(body, under_cloth)
        print("  body verts under cloth removed:", nb2 - len(body.data.vertices))
    for _t, _b, _k, _n in cloth_trees:
        _b.free()

    # ---- garment layout
    layout = PS.layout_for(spec["garments"])
    for o, c in cat.items():
        if c in layout["tiles"] and c not in ("skin",):
            remap_uv(o, layout["tiles"][c])
        elif c in FACE_TILE_KEYS:
            remap_uv(o, FACE_TILE_KEYS[c])

    # ---- vertex colours and materials
    mats = {n: make_material(n) for n in ("skin", "face", "outfit", "hair")}
    face_rough = {"eyes": 0.10, "lashes": 0.8, "brows": 0.9, "glasses": 0.25}
    for o, c in cat.items():
        if c == "skin":
            set_vcol_scalp(o, cat, 0.5); surf = "skin"
        elif c in face_rough:
            set_vcol(o, (1.0 if c == "brows" else 0.0, 1.0, 0, face_rough[c])); surf = "face"
        elif c == "hair":
            set_vcol(o, (1, 0, 0, 0.55)); surf = "hair"
        else:
            ch = PS.SLOT_CHANNEL.get(c, (0, 0, 0))
            if colour_of.get(o.name.split(".", 1)[-1]) is None:
                ch = (0, 0, 0)
            set_vcol(o, (ch[0], ch[1], ch[2], PS.ROUGHNESS.get(c, 0.8))); surf = "outfit"
        o.data.materials.clear()
        o.data.materials.append(mats[surf])
    # slot order on the active (body) object: skin, face, outfit, hair
    body.data.materials.clear()
    for n in ("skin", "face", "outfit", "hair"):
        body.data.materials.append(mats[n])
    # remove armature modifier links before join, join, re-add
    to_join = [o for o in cat.keys() if o is not body]
    # ---- join everything into the body object
    bpy.ops.object.select_all(action='DESELECT')
    for o in to_join:
        o.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    # every part must share the same parent/armature for join to keep weights
    bpy.ops.object.join()
    body.name = spec["id"] + "_Body"
    body.data.name = spec["id"] + "_Body"
    # smooth skin weights a bit (limits shoulder / armpit LBS collapse when the arms come down from the A-pose)
    smooth_shoulder_weights(body, int(os.environ.get("PEOPLE_SMOOTH", "4")), 0.55)
    select_only(body)
    bpy.ops.object.vertex_group_limit_total(group_select_mode='BONE_DEFORM', limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode='BONE_DEFORM', lock_active=False)
    me = body.data
    print("  joined:", len(me.vertices), "verts", tris_of(body), "tris", [m.name for m in me.materials])

    # ---- geometry: lift so lowest point is y=0, scale to target height, rotate 180 deg about Z
    zs = [v.co.z for v in me.vertices]
    zmin, zmax = min(zs), max(zs)
    # body height without hair/hats: use skin verts (material index 0)
    skin_z = []
    for p in me.polygons:
        if p.material_index == 0:
            for vi in p.vertices:
                skin_z.append(me.vertices[vi].co.z)
    body_top = max(skin_z)
    cur_h = body_top - zmin
    target = spec["height"]
    k = target / cur_h
    print("  height: measured %.3f target %.3f scale %.4f" % (cur_h, target, k))
    R = Matrix.Rotation(math.pi, 4, 'Z')
    M = R @ Matrix.Scale(k, 4) @ Matrix.Translation((0, 0, -zmin))
    me.transform(M)
    me.update()
    # rig data in final frame
    rig_info = {}
    select_only(rig)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = rig.data.edit_bones
    heads = {}
    tails = {}
    parents = {}
    for b in eb:
        heads[b.name] = (M @ (rig.matrix_world @ b.head)).copy()
        tails[b.name] = (M @ (rig.matrix_world @ b.tail)).copy()
        parents[b.name] = b.parent.name if b.parent else ""
    order = [b.name for b in eb]
    for b in eb:
        b.use_connect = False
    L = 0.04 * k
    for b in eb:
        h = heads[b.name]
        b.head = h
        b.tail = h + Vector((0, L, 0))
        b.roll = 0.0
    bpy.ops.object.mode_set(mode='OBJECT')
    rig.matrix_world = Matrix.Identity(4)
    rig.location = (0, 0, 0)
    rig_info = {n: dict(parent=parents[n], head=list(heads[n]), tail_orig=list(tails[n])) for n in order}
    # armature modifier target
    for m in body.modifiers:
        if m.type == 'ARMATURE':
            m.object = rig
    body.parent = rig
    body.matrix_parent_inverse = Matrix.Identity(4)
    body.matrix_world = Matrix.Identity(4)
    rig.name = "Armature"
    rig.data.name = spec["id"] + "_rig"
    newheads, finger_axes = relax_fingers(rig, body, heads, tails, L)
    for nm, h in newheads.items():
        rig_info[nm]["head"] = list(h)
    me = body.data

    # sanity: mesh bounds after
    zs2 = [v.co.z for v in me.vertices]
    xs2 = [v.co.x for v in me.vertices]
    ys2 = [v.co.y for v in me.vertices]
    info = dict(id=spec["id"], tris=tris_of(body), verts=len(me.vertices),
                surf_tris=[sum(len(p.vertices) - 2 for p in me.polygons if p.material_index == i) for i in range(4)],
                height_m=round(max(skin_z) * 0 + (body_top - zmin) * k, 4), bbox_min=[min(xs2), min(ys2), min(zs2)],
                bbox_max=[max(xs2), max(ys2), max(zs2)], layout="main" if layout is PS.LAYOUT_MAIN else "split",
                atlas_size=list(layout["size"]), pre_decimate={k_: v for k_, v in stats_pre.items()},
                rig=rig_info, bone_order=order, scale_k=k, finger_axes=finger_axes)
    # export
    os.makedirs(os.path.join(OUTDIR, "chars"), exist_ok=True)
    path = os.path.join(OUTDIR, "chars", spec["id"] + ".glb")
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=False, export_image_format='NONE', export_materials='EXPORT',
                              export_skins=True, export_animations=False, export_def_bones=False,
                              export_vertex_color='ACTIVE', export_all_vertex_colors=False,
                              export_normals=True, export_texcoords=True, export_tangents=False,
                              export_morph=False, export_influence_nb=4, export_all_influences=False,
                              export_rest_position_armature=True, export_cameras=False, export_lights=False,
                              export_extras=False, export_leaf_bone=False)
    info["glb_bytes"] = os.path.getsize(path)
    with open(os.path.join(OUTDIR, "chars", spec["id"] + ".info.json"), "w") as f:
        json.dump(info, f)
    print("  OK %s tris=%d in %.1fs (%s)" % (spec["id"], info["tris"], time.time() - t0, spec["name"]))
    return info


def main():
    specs = PS.SPECS
    if ids:
        sel = set(ids)
        specs = [s for s in specs if s["id"] in sel or str(s["index"]) in sel]
    for sp in specs:
        print("BUILD", sp["id"], sp["name"])
        try:
            build(sp)
        except Exception:
            traceback.print_exc()
            print("FAILED", sp["id"])


main()
