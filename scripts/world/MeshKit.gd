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
## `skip_z` +1 / -1 leaves out the +z / -z face (a box standing against a wall: its back face lies in the wall's plane, where it would z-fight with whatever is drawn on the other side of the wall)
func box(mats, center: Vector3, size: Vector3, floor_y: float = 0.0, skip_bottom := false, skip_z := 0) -> void:
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
	if skip_z <= 0:
		wall(m.call("front"), Vector3(x0, 0, z1), Vector3(x1, 0, z1), y0, y1, floor_y)      # +z face
	if skip_z >= 0:
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


## One quad with a normal per corner (smooth shading), p0..p3 counter-clockwise from the front like `quad`; UV in metres from `uv0` along p0->p1 / p0->p3
func quad_smooth(mat: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n0: Vector3, n1: Vector3, n2: Vector3, n3: Vector3, floor_y: float = 0.0, uv0: Vector2 = Vector2.ZERO) -> void:
	var s := _surf(mat)
	var t := (p1 - p0).normalized()
	var v_dir := (p3 - p0).normalized()
	var nf := (p1 - p0).cross(p2 - p0).normalized()
	var w := 1.0 if nf.cross(t).dot(-v_dir) >= 0.0 else -1.0
	var base: int = s["v"].size()
	var rnd := _rng.randf()
	var pts := [p0, p1, p2, p3]
	var nrm := [n0, n1, n2, n3]
	for k in 4:
		var p: Vector3 = pts[k]
		var d: Vector3 = p - p0
		s["v"].append(p)
		s["n"].append(nrm[k])
		s["uv"].append(uv0 + Vector2(d.dot(t), d.dot(v_dir)))
		s["t"].append_array([t.x, t.y, t.z, w])
		s["c"].append(Color(p.y - floor_y, rnd, 0.0, 1.0))
	s["i"].append_array([base, base + 2, base + 1, base, base + 3, base + 2])


## A surface of revolution about the vertical axis through (cx, cz): `profile` is a list of Vector2(radius, y) from the axis outward / upward; the radius is scaled by (ax, az)
## in x and z (an ellipse when they differ). The visible side is the one on the LEFT walking along the profile seen from outside with +y up; `flip` shows the other.
## Normals are smooth (taken from the profile). `segs` quads round; the seam is closed.
func lathe(mat: String, profile: PackedVector2Array, cx: float, cz: float, ax: float, az: float, segs := 20, floor_y := 0.0, flip := false) -> void:
	var n := profile.size()
	if n < 2:
		return
	# profile normals (r, y): the left of the travel direction
	var pn: Array = []
	for i in n:
		var a := profile[maxi(i - 1, 0)]
		var b := profile[mini(i + 1, n - 1)]
		var d := (b - a).normalized()
		pn.append(Vector2(-d.y, d.x))
	for k in segs:
		var a0 := TAU * float(k) / segs
		var a1 := TAU * float(k + 1) / segs
		for i in n - 1:
			var pa := profile[i]
			var pb := profile[i + 1]
			var v := func(r: float, y: float, ang: float) -> Vector3:
				return Vector3(cx + cos(ang) * r * ax, y, cz + sin(ang) * r * az)
			var nv := func(pnrm: Vector2, ang: float) -> Vector3:
				# the ellipse's normal: scale the radial part by 1/axis
				var rad := Vector3(cos(ang) / ax, 0.0, sin(ang) / az) * pnrm.x
				return (rad + Vector3(0.0, pnrm.y, 0.0)).normalized()
			var p00: Vector3 = v.call(pa.x, pa.y, a0)
			var p01: Vector3 = v.call(pa.x, pa.y, a1)
			var p10: Vector3 = v.call(pb.x, pb.y, a0)
			var p11: Vector3 = v.call(pb.x, pb.y, a1)
			var n00: Vector3 = nv.call(pn[i], a0)
			var n01: Vector3 = nv.call(pn[i], a1)
			var n10: Vector3 = nv.call(pn[i + 1], a0)
			var n11: Vector3 = nv.call(pn[i + 1], a1)
			var uv0 := Vector2(float(k) * (TAU / segs) * maxf(pa.x * ax, 0.01), pa.y)          # (metres along the arc, so tiles keep their size)
			if flip:
				quad_smooth(mat, p00, p10, p11, p01, -n00, -n10, -n11, -n01, floor_y, uv0)
			else:
				quad_smooth(mat, p00, p01, p11, p10, n00, n01, n11, n10, floor_y, uv0)


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


## Bends everything gathered so far (see Bend). A triangle that reaches into the curved stretch is first cut along x into slabs of at most `step` metres, so a long wall or floor follows the arc
## in a chain of short flat pieces; then every vertex is moved, and its normal and tangent turned with the track. Texture coordinates, colours and the order of the corners are kept.
## Triangles before the arc stay as they are and those beyond it (the running tunnel) are moved as one rigid piece, both in place; only the ones in the arc are rebuilt.
func bend(b: Bend, step := 3.0) -> void:
	if b.is_straight():
		return
	var tail_xf := Transform3D(b.rot(b.x1), Vector3.ZERO)
	var tail_pos := b.map(Vector3(b.x1, 0.0, 0.0)) - tail_xf.basis * Vector3(b.x1, 0.0, 0.0)
	tail_xf.origin = tail_pos
	var tail_rot := Transform3D(tail_xf.basis, Vector3.ZERO)
	for name in surfaces.keys():
		var s: Dictionary = surfaces[name]
		var V: PackedVector3Array = s["v"]
		var N: PackedVector3Array = s["n"]
		var UV: PackedVector2Array = s["uv"]
		var T: PackedFloat32Array = s["t"]
		var C: PackedColorArray = s["c"]
		var I: PackedInt32Array = s["i"]
		var nv := V.size()
		var is_tail := PackedByteArray()
		is_tail.resize(nv)
		var keep := PackedInt32Array()
		var rebuilt: Array = []                 # the corners of the triangles that are in the arc (read before anything is moved)
		for ti in range(0, I.size(), 3):
			var i0: int = I[ti]
			var i1: int = I[ti + 1]
			var i2: int = I[ti + 2]
			var x0v: float = V[i0].x
			var x1v: float = V[i1].x
			var x2v: float = V[i2].x
			var xmax := maxf(x0v, maxf(x1v, x2v))
			if xmax <= b.x0:
				keep.append_array([i0, i1, i2])
				continue
			var xmin := minf(x0v, minf(x1v, x2v))
			if xmin >= b.x1:
				keep.append_array([i0, i1, i2])
				is_tail[i0] = 1
				is_tail[i1] = 1
				is_tail[i2] = 1
				continue
			var corner: Array = []
			for i in [i0, i1, i2]:
				var p := V[i]
				corner.append([p.x, p.y, p.z, N[i].x, N[i].y, N[i].z, UV[i].x, UV[i].y, T[i * 4], T[i * 4 + 1], T[i * 4 + 2], T[i * 4 + 3], C[i].r, C[i].g, C[i].b, C[i].a])
			rebuilt.append([corner, xmin, xmax])
		# the tail, as one rigid piece
		for i in nv:
			if is_tail[i] == 1:
				V[i] = tail_xf * V[i]
				N[i] = tail_rot * N[i]
				var tt := tail_rot * Vector3(T[i * 4], T[i * 4 + 1], T[i * 4 + 2])
				T[i * 4] = tt.x
				T[i * 4 + 1] = tt.y
				T[i * 4 + 2] = tt.z
		# the arc
		for rb in rebuilt:
			var polys: Array = [rb[0]]
			if float(rb[2]) > b.x0 and float(rb[1]) < b.x1:
				polys = _cut_slabs(rb[0], rb[1], rb[2], b, step)
			for poly: Array in polys:
				var base := V.size()
				for vt: Array in poly:
					var rbasis := b.rot(vt[0])
					var n2 := rbasis * Vector3(vt[3], vt[4], vt[5])
					var t2 := rbasis * Vector3(vt[8], vt[9], vt[10])
					V.append(b.map(Vector3(vt[0], vt[1], vt[2])))
					N.append(n2)
					UV.append(Vector2(vt[6], vt[7]))
					T.append(t2.x)
					T.append(t2.y)
					T.append(t2.z)
					T.append(vt[11])
					C.append(Color(vt[12], vt[13], vt[14], vt[15]))
				for k in range(1, poly.size() - 1):
					keep.append_array([base, base + k, base + k + 1])
		s["v"] = V
		s["n"] = N
		s["uv"] = UV
		s["t"] = T
		s["c"] = C
		s["i"] = keep


## the pieces (convex polygons, corners as 16-float arrays) a triangle falls into when cut by the planes x = b.x0, b.x1 and b.x0 + k step between them
func _cut_slabs(tri: Array, xmin: float, xmax: float, b: Bend, step: float) -> Array:
	var planes: Array = []
	if xmin < b.x0 and b.x0 < xmax:
		planes.append(b.x0)
	var lo := maxf(xmin, b.x0)
	var hi := minf(xmax, b.x1)
	var k := int(floor((lo - b.x0) / step)) + 1
	while b.x0 + k * step < hi - 1e-4:
		var xc := b.x0 + k * step
		if xc > lo + 1e-4 and xc < b.x1 - 1e-4:
			planes.append(xc)
		k += 1
	if xmin < b.x1 and b.x1 < xmax:
		planes.append(b.x1)
	planes.sort()
	var out: Array = []
	var rest: Array = tri
	for xc: float in planes:
		var below: Array = []
		var above: Array = []
		var n: int = rest.size()
		for i in n:
			var a: Array = rest[i]
			var c: Array = rest[(i + 1) % n]
			var a_in: bool = a[0] <= xc
			var c_in: bool = c[0] <= xc
			if a_in:
				below.append(a)
			if not a_in:
				above.append(a)
			if a_in != c_in:
				var t: float = (xc - a[0]) / (c[0] - a[0])
				var m: Array = []
				for j in 16:
					m.append(lerpf(a[j], c[j], t))
				m[0] = xc
				var nl := Vector3(m[3], m[4], m[5]).normalized()
				m[3] = nl.x
				m[4] = nl.y
				m[5] = nl.z
				below.append(m)
				above.append(m)
		if below.size() >= 3:
			out.append(below)
		rest = above
		if rest.size() < 3:
			break
	if rest.size() >= 3:
		out.append(rest)
	return out


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
