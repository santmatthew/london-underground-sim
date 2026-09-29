class_name MeshKit
extends RefCounted
## Accumulates triangles per material name and bakes them into an ArrayMesh.
## Conventions: quads are given COUNTER-CLOCKWISE seen from the visible (front) side; UVs are in metres
## (the surface shader scales them per material). COLOR.r = height above the local floor (m), COLOR.g = 0..1 per-face random,
## COLOR.b = user value (e.g. distance to ceiling), COLOR.a = 1.

var surfaces: Dictionary = {}     # mat name -> {v, n, uv, t, c, i}
var _rng := RandomNumberGenerator.new()


func _surf(mat: String) -> Dictionary:
	if not surfaces.has(mat):
		surfaces[mat] = {
			"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
			"t": PackedFloat32Array(), "c": PackedColorArray(), "i": PackedInt32Array(),
		}
	return surfaces[mat]


func seed_rng(s: int) -> void:
	_rng.seed = s


## p0..p3 CCW from the front. UV: u along p0->p1, v along p0->p3 (in metres) plus offset uv0.
func quad(mat: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, floor_y: float = 0.0, uv0: Vector2 = Vector2.ZERO, blue: float = 0.0, swap_uv := false) -> void:
	var s := _surf(mat)
	var e1 := p1 - p0
	var e3 := p3 - p0
	var n := e1.cross(p2 - p0)
	if n.length_squared() < 1e-10:
		n = e1.cross(e3)
	n = n.normalized()
	var t := e1.normalized()
	var v_dir := e3.normalized()
	if swap_uv:
		t = e3.normalized()
		v_dir = e1.normalized()
	# binormal expected = -V direction (V grows "down" on the texture)
	var w := 1.0 if n.cross(t).dot(-v_dir) >= 0.0 else -1.0
	var base: int = s["v"].size()
	var rnd := _rng.randf()
	var pts := [p0, p1, p2, p3]
	# uv of each corner: project onto (u,v) axes so non-rectangular quads still work
	for p in pts:
		var d: Vector3 = p - p0
		s["v"].append(p)
		s["n"].append(n)
		s["uv"].append(uv0 + Vector2(d.dot(t), d.dot(v_dir)))
		s["t"].append_array([t.x, t.y, t.z, w])
		s["c"].append(Color(p.y - floor_y, rnd, blue, 1.0))
	# Godot front faces are clockwise
	s["i"].append_array([base, base + 2, base + 1, base, base + 3, base + 2])


## Vertical wall between floor points a->b spanning y0..y1. The visible (front) side is the RIGHT of the travel direction
## a->b seen with +y up (right = (b-a) x up). `flip` shows the other side.
func wall(mat: String, a: Vector3, b: Vector3, y0: float, y1: float, floor_y: float = 0.0, flip := false, uv_off := Vector2.ZERO) -> void:
	var a0 := Vector3(a.x, y0, a.z)
	var b0 := Vector3(b.x, y0, b.z)
	var b1 := Vector3(b.x, y1, b.z)
	var a1 := Vector3(a.x, y1, a.z)
	# UV v must grow downward, so start from the top: order a1,a0,b0,b1 (front = right of a->b)
	# U runs along the wall (a->b), V runs down
	if not flip:
		quad(mat, a1, a0, b0, b1, floor_y, uv_off, 0.0, true)
	else:
		quad(mat, b1, b0, a0, a1, floor_y, uv_off, 0.0, true)


## Horizontal quad: rectangle x0..x1, z0..z1 at height y. up = true faces +y (floor), false faces -y (ceiling).
func horiz(mat: String, x0: float, x1: float, z0: float, z1: float, y: float, up: bool, floor_y: float = 0.0, uv_off := Vector2.ZERO) -> void:
	var p00 := Vector3(x0, y, z0)
	var p10 := Vector3(x1, y, z0)
	var p11 := Vector3(x1, y, z1)
	var p01 := Vector3(x0, y, z1)
	if up:
		# normal +y : CCW seen from above (looking down -y, x right, z toward viewer/down) => p00, p01, p11, p10
		quad(mat, p00, p01, p11, p10, floor_y, uv_off)
	else:
		quad(mat, p00, p10, p11, p01, floor_y, uv_off)


## Axis-aligned box. `mats` may be a String (all faces) or a Dictionary with keys top,bottom,front,back,left,right ("*" fallback)
func box(mats, center: Vector3, size: Vector3, floor_y: float = 0.0, skip_bottom := false) -> void:
	var h := size * 0.5
	var x0 := center.x - h.x
	var x1 := center.x + h.x
	var y0 := center.y - h.y
	var y1 := center.y + h.y
	var z0 := center.z - h.z
	var z1 := center.z + h.z
	var m := func(k: String) -> String:
		if mats is String:
			return mats
		return mats.get(k, mats.get("*", "default"))
	horiz(m.call("top"), x0, x1, z0, z1, y1, true, floor_y)
	if not skip_bottom:
		horiz(m.call("bottom"), x0, x1, z0, z1, y0, false, floor_y)
	wall(m.call("front"), Vector3(x0, 0, z1), Vector3(x1, 0, z1), y0, y1, floor_y)      # +z face
	wall(m.call("back"), Vector3(x1, 0, z0), Vector3(x0, 0, z0), y0, y1, floor_y)       # -z face
	wall(m.call("right"), Vector3(x1, 0, z1), Vector3(x1, 0, z0), y0, y1, floor_y)      # +x face
	wall(m.call("left"), Vector3(x0, 0, z0), Vector3(x0, 0, z1), y0, y1, floor_y)       # -x face


## Oriented box: `xf` places a box of `size` centred at the origin of xf (any rotation).
func box_xf(mats, xf: Transform3D, size: Vector3, floor_y: float = 0.0) -> void:
	var h := size * 0.5
	var c := func(sx: float, sy: float, sz: float) -> Vector3:
		return xf * Vector3(sx * h.x, sy * h.y, sz * h.z)
	var m := func(k: String) -> String:
		if mats is String:
			return mats
		return mats.get(k, mats.get("*", "default"))
	# +y top (CCW from above)
	quad(m.call("top"), c.call(-1, 1, -1), c.call(-1, 1, 1), c.call(1, 1, 1), c.call(1, 1, -1), floor_y)
	quad(m.call("bottom"), c.call(-1, -1, -1), c.call(1, -1, -1), c.call(1, -1, 1), c.call(-1, -1, 1), floor_y)
	# +z
	quad(m.call("front"), c.call(-1, 1, 1), c.call(-1, -1, 1), c.call(1, -1, 1), c.call(1, 1, 1), floor_y, Vector2.ZERO, 0.0, true)
	# -z
	quad(m.call("back"), c.call(1, 1, -1), c.call(1, -1, -1), c.call(-1, -1, -1), c.call(-1, 1, -1), floor_y, Vector2.ZERO, 0.0, true)
	# +x
	quad(m.call("right"), c.call(1, 1, 1), c.call(1, -1, 1), c.call(1, -1, -1), c.call(1, 1, -1), floor_y, Vector2.ZERO, 0.0, true)
	# -x
	quad(m.call("left"), c.call(-1, 1, -1), c.call(-1, -1, -1), c.call(-1, -1, 1), c.call(-1, 1, 1), floor_y, Vector2.ZERO, 0.0, true)


## Sweep a 2D profile (Vector2(z, y) points, in order) along the X axis from x0 to x1.
## The visible side is the one on the LEFT when walking along the profile order seen with +x pointing away from the viewer
## (use `flip` to invert). U runs along the profile (metres), V along x.
func sweep_x(mat: String, profile: PackedVector2Array, x0: float, x1: float, floor_y: float = 0.0, flip := false, seg_len := 4.0, blue_from_profile_top := false) -> void:
	var n := profile.size()
	# split long spans into chunks so UVs/dirt stay tiled and precision stays fine
	var chunks := maxi(1, int(ceil((x1 - x0) / seg_len)))
	var arc := 0.0
	for i in n - 1:
		var pa := profile[i]
		var pb := profile[i + 1]
		var seg_arc := pa.distance_to(pb)
		for c in chunks:
			var xa := lerpf(x0, x1, float(c) / chunks)
			var xb := lerpf(x0, x1, float(c + 1) / chunks)
			var a0 := Vector3(xa, pa.y, pa.x)
			var b0 := Vector3(xa, pb.y, pb.x)
			var b1 := Vector3(xb, pb.y, pb.x)
			var a1 := Vector3(xb, pa.y, pa.x)
			# profile ordered left-bottom -> over the top -> right-bottom: flip=false faces INTO the tunnel
			if not flip:
				quad(mat, a0, a1, b1, b0, floor_y, Vector2(xa, arc), 0.0)
			else:
				quad(mat, a1, a0, b0, b1, floor_y, Vector2(-xb, arc), 0.0)
		arc += seg_arc


func build(materials: Dictionary, default_mat: Material = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for name in surfaces:
		var s: Dictionary = surfaces[name]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s["v"]
		arrays[Mesh.ARRAY_NORMAL] = s["n"]
		arrays[Mesh.ARRAY_TEX_UV] = s["uv"]
		arrays[Mesh.ARRAY_TANGENT] = s["t"]
		arrays[Mesh.ARRAY_COLOR] = s["c"]
		arrays[Mesh.ARRAY_INDEX] = s["i"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var idx := mesh.get_surface_count() - 1
		mesh.surface_set_name(idx, name)
		mesh.surface_set_material(idx, materials.get(name, default_mat))
	return mesh


func triangle_count() -> int:
	var n := 0
	for name in surfaces:
		n += (surfaces[name]["i"] as PackedInt32Array).size() / 3
	return n
