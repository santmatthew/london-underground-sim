class_name PlatformDoors
extends RefCounted
## Platform edge doors (PEDs) of the Jubilee Line Extension stations (1999): a stainless head casing along the platform edge, fixed tinted-glass panels with a yellow
## band, and a pair of sliding glass leaves at every train door. They open with the train's doors (PlatformModule.set_edge_open, called by TrainService per door).
## Reference: build/refs_dress/platforms/SPEC.md section 12 (28 doors per platform, glass about 2.5 m, head casing about 0.55 m deep, 80-100 mm yellow band at 1.1-1.2 m).

const OPEN_W := 2.0            # clear opening of one door
const GLASS_H := 2.5
const HEAD_Y0 := 2.5
const HEAD_Y1 := 3.05
const HEAD_D := 0.55
const SLIDE := 1.0             # each leaf slides this far (a leaf is OPEN_W / 2 wide)
const OPEN_S := 1.4            # seconds

static var _leaf_mesh: ArrayMesh


## x positions of the doors along the platform (module frame): the train stops centred on the module origin
static func door_xs(line_id: String) -> Array:
	var cars: Array = StationPlan.CARS.get(line_id, [7, 17.0])
	return Train.door_positions_for(Train.kind_of_line(line_id) if Net.lines.has(line_id) else "deep", int(cars[0]))


static func _leaf() -> ArrayMesh:
	if _leaf_mesh != null:
		return _leaf_mesh
	var kit := MeshKit.new()
	var w := OPEN_W * 0.5
	kit.box("ped_glass", Vector3(0, GLASS_H * 0.5 + 0.04, 0), Vector3(w - 0.02, GLASS_H - 0.08, 0.012), 0.0)
	for sx in [-1.0, 1.0]:
		kit.box("stainless", Vector3(sx * (w * 0.5 - 0.02), GLASS_H * 0.5, 0), Vector3(0.04, GLASS_H, 0.03), 0.0)
	kit.box("stainless", Vector3(0, 0.03, 0), Vector3(w, 0.06, 0.03), 0.0)
	kit.box("stainless", Vector3(0, GLASS_H - 0.02, 0), Vector3(w, 0.05, 0.03), 0.0)
	kit.box("yellow_paint", Vector3(0, 1.16, 0.0), Vector3(w - 0.04, 0.09, 0.016), 0.0)
	kit.box("yellow_paint", Vector3(0, 0.98, 0.0), Vector3(w - 0.04, 0.02, 0.016), 0.0)
	_leaf_mesh = kit.build({"ped_glass": Mats.get_mat("ped_glass"), "stainless": Mats.get_mat("stainless"), "yellow_paint": Mats.get_mat("yellow_paint")})
	return _leaf_mesh


## fixed parts into the module's MeshKit and the sliding leaves as child nodes of the module; s = +1 for the +z face
static func build(pm: PlatformModule, kit: MeshKit, s: float, zedge: float, xs: Array, x0: float, x1: float) -> void:
	if xs.is_empty():
		return
	var zf := s * (zedge - 0.03)            # fixed glass
	var zl := s * (zedge - 0.07)            # sliding leaves, on the platform side of the fixed glass
	var xa := float(xs[0]) - OPEN_W * 0.5 - 1.2
	var xb := float(xs[xs.size() - 1]) + OPEN_W * 0.5 + 1.2
	xa = maxf(xa, x0 + 0.5)
	xb = minf(xb, x1 - 0.5)
	# head casing: a stainless box along the whole row of doors, with a slim lip below
	kit.box("stainless", Vector3((xa + xb) * 0.5, (HEAD_Y0 + HEAD_Y1) * 0.5, s * (zedge - HEAD_D * 0.5 + 0.03)), Vector3(xb - xa, HEAD_Y1 - HEAD_Y0, HEAD_D), 0.0)
	# fixed glass between the doors, and posts at every door edge and at the two ends
	var edges: Array = [xa]
	for xd in xs:
		edges.append(float(xd) - OPEN_W * 0.5)
		edges.append(float(xd) + OPEN_W * 0.5)
	edges.append(xb)
	for k in range(0, edges.size(), 2):
		var ga: float = edges[k]
		var gb: float = edges[k + 1]
		if gb - ga < 0.05:
			continue
		var a := Vector3(ga, 0, zf)
		var b := Vector3(gb, 0, zf)
		if s > 0.0:
			kit.wall("ped_glass", a, b, 0.04, GLASS_H, 0.0)
		else:
			kit.wall("ped_glass", b, a, 0.04, GLASS_H, 0.0)
		kit.box("yellow_paint", Vector3((ga + gb) * 0.5, 1.16, zf), Vector3(gb - ga, 0.09, 0.012), 0.0)
		kit.box("yellow_paint", Vector3((ga + gb) * 0.5, 0.98, zf), Vector3(gb - ga, 0.02, 0.012), 0.0)
	for ex in edges:
		kit.box("stainless", Vector3(ex, GLASS_H * 0.5, zf), Vector3(0.12, GLASS_H, 0.07), 0.0)
	kit.box("stainless", Vector3((xa + xb) * 0.5, 0.03, zf), Vector3(xb - xa, 0.06, 0.07), 0.0)       # sill
	for xd in xs:
		# amber lamp on the head, a ribbed sill at the door, and a dark inlay strip across the platform at each door position
		kit.box("flat:#ff9a10", Vector3(xd, HEAD_Y0 + 0.12, zf + s * 0.01), Vector3(0.09, 0.09, 0.02), 0.0)
		kit.box("black", Vector3(xd, 0.012, s * (zedge - 0.12)), Vector3(OPEN_W, 0.016, 0.16), 0.0)
		kit.horiz("flat:#4a4b50", float(xd) - 0.05, float(xd) + 0.05, minf(s * PlatformModule.GAP * 0.5, s * zedge), maxf(s * PlatformModule.GAP * 0.5, s * zedge), 0.004, true, 0.0)
	# the leaves
	var rec: Array = []
	for xd in xs:
		var pair: Dictionary = {"x": float(xd), "open": false}
		for side in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = _leaf()
			mi.position = Vector3(float(xd) + side * OPEN_W * 0.25, 0.0, zl)
			mi.name = "PED_%d_%s" % [int(float(xd) * 10.0), "L" if side < 0.0 else "R"]
			mi.visibility_range_end = 70.0
			pm.add_child(mi)
			pair["l" if side < 0.0 else "r"] = mi
		rec.append(pair)
	pm.ped_doors[s] = rec


## slide the pair of leaves nearest to x (module frame) open or shut
static func slide(pm: PlatformModule, face_sign: float, x: float, open: bool) -> void:
	if not pm.ped_doors.has(face_sign):
		return
	for pair in pm.ped_doors[face_sign]:
		if absf(float(pair["x"]) - x) > 1.0 or bool(pair["open"]) == open:
			continue
		pair["open"] = open
		var l: Node3D = pair["l"]
		var r: Node3D = pair["r"]
		if pair.has("tw") and pair["tw"] != null:
			(pair["tw"] as Tween).kill()
		var tw := pm.create_tween().set_parallel(true)
		var dx := SLIDE if open else 0.0
		var d := 0.25 if open else 0.0
		tw.tween_property(l, "position:x", float(pair["x"]) - OPEN_W * 0.25 - dx, OPEN_S).set_delay(d).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(r, "position:x", float(pair["x"]) + OPEN_W * 0.25 + dx, OPEN_S).set_delay(d).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pair["tw"] = tw
