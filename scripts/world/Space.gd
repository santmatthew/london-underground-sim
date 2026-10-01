class_name Space
extends Node3D
## A rectangular room / corridor with openings (portals) in its walls. World-space rectangle x0..x1, z0..z1 at floor height y.
## Sides: N = -z wall, S = +z wall, W = -x wall, E = +x wall. Openings: {side, c (centre coordinate along the wall), w, h, y_off (raise above floor)}
## Every connection between two spaces is an opening of identical size in both spaces (corridors simply have open ends).

var spec: Dictionary = {}
var kit := MeshKit.new()
var cols: Array = []          # [center, size] world-space collision boxes
var light_points: Array = []  # [pos, energy, range]
var x0 := 0.0
var x1 := 0.0
var z0 := 0.0
var z1 := 0.0
var y := 0.0
var h := 4.0
var openings: Array = []
var extra_nodes: Array = []


## spec keys: name, rect:[x0,x1,z0,z1], y, h, openings, wall, floor, ceil, band (Color, optional), lights ("grid"/"strip_x"/"strip_z"), light_dx, light_dz,
##            open_ends: ["E","W"] sides that have NO wall at all (corridor ends; they must be paired with an adjacent space)
func build(p_spec: Dictionary) -> void:
	spec = p_spec
	var r: Array = spec["rect"]
	x0 = r[0]; x1 = r[1]; z0 = r[2]; z1 = r[3]
	y = spec.get("y", 0.0)
	h = spec.get("h", 4.0)
	openings = spec.get("openings", [])
	kit.seed_rng(int(spec.get("seed", 1)))
	var wall_mat: String = spec.get("wall", "tile_white")
	var floor_mat: String = spec.get("floor", "floor_hall")
	var ceil_mat: String = spec.get("ceil", "ceiling")
	name = spec.get("name", "Space")

	# floor & ceiling
	kit.horiz(floor_mat, x0, x1, z0, z1, y, true, y)
	kit.horiz(ceil_mat, x0, x1, z0, z1, y + h, false, y)
	_cols_box(Vector3((x0 + x1) * 0.5, y - 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0 + 0.6, 1.0, z1 - z0 + 0.6))
	_cols_box(Vector3((x0 + x1) * 0.5, y + h + 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0 + 0.6, 1.0, z1 - z0 + 0.6))
	# walls
	for side in ["N", "S", "W", "E"]:
		_wall(side, wall_mat)
	# skirting / colour band
	if spec.has("bands"):
		for b in spec["bands"]:
			_band_at(b["key"], b["y0"], b["y1"])
	elif spec.has("band"):
		_band(spec["band"])
	# lights
	_lights()
	_finish()


func _side_open(side: String) -> bool:
	return side in spec.get("open_ends", [])


func _wall_len_range(side: String) -> Array:
	return [x0, x1] if side in ["N", "S"] else [z0, z1]


func _side_openings(side: String) -> Array:
	var out := []
	for o in openings:
		if o["side"] == side:
			out.append(o)
	out.sort_custom(func(a, b): return a["c"] < b["c"])
	return out


func _wall_pos(side: String) -> float:
	match side:
		"N": return z0
		"S": return z1
		"W": return x0
	return x1


## emit a wall segment [a,b] along the wall's axis between y_lo..y_hi (world y), visible from inside
func _seg(mat: String, side: String, a: float, b: float, y_lo: float, y_hi: float) -> void:
	if b - a < 0.002 or y_hi - y_lo < 0.002:
		return
	var p := _wall_pos(side)
	match side:
		"N": kit.wall(mat, Vector3(a, 0, p), Vector3(b, 0, p), y_lo, y_hi, y)
		"S": kit.wall(mat, Vector3(b, 0, p), Vector3(a, 0, p), y_lo, y_hi, y)
		"W": kit.wall(mat, Vector3(p, 0, b), Vector3(p, 0, a), y_lo, y_hi, y)
		"E": kit.wall(mat, Vector3(p, 0, a), Vector3(p, 0, b), y_lo, y_hi, y)


func _wall(side: String, mat: String) -> void:
	if _side_open(side):
		return
	var rng := _wall_len_range(side)
	var cur: float = rng[0]
	var ops := _side_openings(side)
	for o in ops:
		var a: float = o["c"] - o["w"] * 0.5
		var b: float = o["c"] + o["w"] * 0.5
		var oy: float = y + o.get("y_off", 0.0)
		_seg(mat, side, cur, a, y, y + h)
		# below (if raised) and above the opening
		_seg(mat, side, a, b, y, oy)
		_seg(mat, side, a, b, oy + o["h"], y + h)
		_col_wall(side, cur, a)
		cur = b
		_frame(side, o)
	_seg(mat, side, cur, rng[1], y, y + h)
	_col_wall(side, cur, rng[1])


func _col_wall(side: String, a: float, b: float) -> void:
	if b - a < 0.01:
		return
	var p := _wall_pos(side)
	var t := 0.4
	var c := (a + b) * 0.5
	var size_a := b - a
	if side in ["N", "S"]:
		var off := -t * 0.5 if side == "N" else t * 0.5
		_cols_box(Vector3(c, y + h * 0.5, p + off), Vector3(size_a, h, t))
	else:
		var off2 := -t * 0.5 if side == "W" else t * 0.5
		_cols_box(Vector3(p + off2, y + h * 0.5, c), Vector3(t, h, size_a))


func _frame(side: String, o: Dictionary) -> void:
	# dark metal reveal around an opening: 6 cm proud trim
	var w: float = o["w"]
	var oh: float = o["h"]
	var oy: float = y + o.get("y_off", 0.0)
	var c: float = o["c"]
	var p := _wall_pos(side)
	var inward := 1.0 if side in ["N", "W"] else -1.0
	var t := 0.10
	var d := 0.10   # depth
	if side in ["N", "S"]:
		for sg in [-1.0, 1.0]:
			kit.box("metal", Vector3(c + sg * (w * 0.5 - t * 0.5), oy + oh * 0.5, p + inward * d * 0.5), Vector3(t, oh, d), y)
		kit.box("metal", Vector3(c, oy + oh - t * 0.5, p + inward * d * 0.5), Vector3(w, t, d), y)
	else:
		for sg in [-1.0, 1.0]:
			kit.box("metal", Vector3(p + inward * d * 0.5, oy + oh * 0.5, c + sg * (w * 0.5 - t * 0.5)), Vector3(d, oh, t), y)
		kit.box("metal", Vector3(p + inward * d * 0.5, oy + oh - t * 0.5, c), Vector3(d, t, w), y)


func _band(col: Color) -> void:
	_band_at("flat:" + col.to_html(false), 1.15, 1.40)


## a band of material `key` between heights y0..y1 above the room's floor, on every wall that is not open, interrupted by the openings
func _band_at(key: String, y0: float, y1: float) -> void:
	var yb0 := y + y0
	var yb1 := y + y1
	for side in ["N", "S", "W", "E"]:
		if _side_open(side):
			continue
		var rng := _wall_len_range(side)
		var cur: float = rng[0]
		var pieces := []
		for o in _side_openings(side):
			if o.get("y_off", 0.0) > 0.0 or o["h"] < 1.5:
				continue
			pieces.append([cur, o["c"] - o["w"] * 0.5])
			cur = o["c"] + o["w"] * 0.5
		pieces.append([cur, rng[1]])
		for pc in pieces:
			_seg_band(key, side, pc[0], pc[1], yb0, yb1)


func _seg_band(mat: String, side: String, a: float, b: float, y_lo: float, y_hi: float) -> void:
	# same as _seg but nudged 4 mm into the room
	var save := [x0, x1, z0, z1]
	var eps := 0.004
	match side:
		"N": z0 += eps
		"S": z1 -= eps
		"W": x0 += eps
		"E": x1 -= eps
	_seg(mat, side, a, b, y_lo, y_hi)
	x0 = save[0]; x1 = save[1]; z0 = save[2]; z1 = save[3]


func _lights() -> void:
	var mode: String = spec.get("lights", "grid")
	var lx: float = spec.get("light_dx", 4.0)
	var lz: float = spec.get("light_dz", 4.0)
	var ceil_y := y + h
	var energy: float = spec.get("light_energy", 1.5)
	var rng_r: float = spec.get("light_range", 10.0)
	if mode == "grid":
		var nx := maxi(1, int(round((x1 - x0) / lx)))
		var nz := maxi(1, int(round((z1 - z0) / lz)))
		for i in nx:
			for j in nz:
				var px := x0 + (i + 0.5) * (x1 - x0) / nx
				var pz := z0 + (j + 0.5) * (z1 - z0) / nz
				kit.box("light_emissive", Vector3(px, ceil_y - 0.03, pz), Vector3(1.2, 0.05, 0.5), y)
				if (i + j) % 2 == 0:
					light_points.append([Vector3(px, ceil_y - 0.6, pz), energy, rng_r])
	elif mode == "strip_x":
		var n := maxi(1, int(round((x1 - x0) / lx)))
		var pz2 := (z0 + z1) * 0.5
		for i in n:
			var px2 := x0 + (i + 0.5) * (x1 - x0) / n
			kit.box("light_emissive", Vector3(px2, ceil_y - 0.03, pz2), Vector3(1.4, 0.05, 0.3), y)
			if i % 2 == 0:
				light_points.append([Vector3(px2, ceil_y - 0.5, pz2), energy, rng_r])
	else:
		var n2 := maxi(1, int(round((z1 - z0) / lz)))
		var px3 := (x0 + x1) * 0.5
		for j in n2:
			var pz3 := z0 + (j + 0.5) * (z1 - z0) / n2
			kit.box("light_emissive", Vector3(px3, ceil_y - 0.03, pz3), Vector3(0.3, 0.05, 1.4), y)
			if j % 2 == 0:
				light_points.append([Vector3(px3, ceil_y - 0.5, pz3), energy, rng_r])


func _cols_box(center: Vector3, size: Vector3) -> void:
	cols.append([center, size])


func _finish() -> void:
	var mats := {}
	for k in kit.surfaces.keys():
		if k.begins_with("flat:"):
			mats[k] = Mats.flat(Color.html(k.substr(5)), 0.4)
		elif k.begins_with("dado:"):
			mats[k] = Mats.dado(Color.html(k.substr(5)))
		else:
			mats[k] = Mats.get_mat(k)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = kit.build(mats)
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Collision"
	for c in cols:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = c[1]
		cs.shape = sh
		cs.position = c[0]
		body.add_child(cs)
	add_child(body)
	var holder := Node3D.new()
	holder.name = "Lights"
	add_child(holder)
	for l in light_points:
		var o := OmniLight3D.new()
		o.position = l[0]
		o.light_energy = l[1]
		o.omni_range = l[2]
		o.omni_attenuation = 1.3
		o.light_color = Color(1.0, 0.97, 0.92)
		o.shadow_enabled = false
		o.distance_fade_enabled = true
		o.distance_fade_begin = 40.0
		o.distance_fade_length = 12.0
		holder.add_child(o)
	# visibility range so far rooms are culled
	mi.visibility_range_end = 220.0


func contains_xz(p: Vector3, margin := 0.0) -> bool:
	return p.x >= x0 - margin and p.x <= x1 + margin and p.z >= z0 - margin and p.z <= z1 + margin and p.y >= y - 0.5 and p.y <= y + h + 0.5
