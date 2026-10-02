class_name PropKit
extends RefCounted
## Procedural station props built from boxes/cylinders (MeshKit), after real London Underground fittings (see build/refs_dress/*/SPEC.md).
## Conventions as the glb props: metres, Y up, FRONT FACES -Z; floor props have their origin at floor level in the middle of their footprint;
## wall props have their origin on the wall surface and extend toward -Z; ceiling props have their origin at the mounting point and hang down.
## Every builder returns a Node3D with a "Mesh" child and, where someone could bump into it, a StaticBody3D "Collision"; meta "fp" = {c, h}
## (footprint centre and half extents in the prop's own x/z) for StationDressing.

const TEX := "res://assets/textures/props/gen2/"

static var _mats: Dictionary = {}


static func _tex(name: String) -> Texture2D:
	var p := TEX + name
	return load(p) if ResourceLoader.exists(p) else null


static func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"black":
			m.albedo_color = Color(0.03, 0.03, 0.035); m.roughness = 0.45; m.metallic = 0.3
		"charcoal":
			m.albedo_color = Color(0.15, 0.16, 0.18); m.roughness = 0.5
		"steel":
			m.albedo_color = Color(0.55, 0.57, 0.6); m.metallic = 0.55; m.roughness = 0.45
		"yellow":
			m.albedo_color = Color(0.91, 0.78, 0.0); m.roughness = 0.5
		"white":
			m.albedo_color = Color(0.93, 0.94, 0.94); m.roughness = 0.35
		"red":
			m.albedo_color = Color(0.72, 0.1, 0.1); m.roughness = 0.4
		"green":
			m.albedo_color = Color(0.1, 0.45, 0.22); m.roughness = 0.5
		"glass":
			m.albedo_color = Color(0.8, 0.9, 0.95, 0.22); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.roughness = 0.05
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"sack":
			m.albedo_color = Color(0.85, 0.9, 0.92, 0.28); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.roughness = 0.2
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"litter":
			m.albedo_color = Color(0.7, 0.6, 0.45); m.roughness = 0.8
		"timber":
			m.albedo_texture = _tex("timber.png"); m.roughness = 0.6; m.uv1_scale = Vector3(2, 2, 1)
		"shrub":
			m.albedo_color = Color(0.16, 0.34, 0.12); m.roughness = 0.9
		"shrub_light":
			m.albedo_color = Color(0.26, 0.42, 0.14); m.roughness = 0.9
		"soil":
			m.albedo_color = Color(0.17, 0.12, 0.08); m.roughness = 0.95
		"brick":
			m.albedo_color = Color(0.46, 0.2, 0.15); m.roughness = 0.85
		"coping":
			m.albedo_color = Color(0.72, 0.7, 0.66); m.roughness = 0.8
		"concrete_lamp":
			m.albedo_color = Color(0.82, 0.81, 0.77); m.roughness = 0.9
		"pole_grey":
			m.albedo_color = Color(0.6, 0.66, 0.64); m.roughness = 0.5; m.metallic = 0.3
		"lantern":
			m.albedo_color = Color(0.95, 0.93, 0.85); m.emission_enabled = true; m.emission = Color(1.0, 0.92, 0.75); m.emission_energy_multiplier = 0.8
		"perforated":
			m.albedo_texture = _tex("perforated.png"); m.albedo_color = Color(1.4, 1.4, 1.4); m.roughness = 0.5; m.metallic = 0.1; m.uv1_scale = Vector3(6, 6, 1)
		"sign_blue":
			m.albedo_texture = _tex("tickets_sign.png"); m.emission_enabled = true; m.emission_texture = _tex("tickets_sign.png"); m.emission_energy_multiplier = 1.2
		"mfm":
			m.albedo_texture = _tex("mfm_front.png"); m.roughness = 0.4; m.emission_enabled = true; m.emission_texture = _tex("mfm_front.png"); m.emission_energy_multiplier = 0.35
		"tvm":
			m.albedo_texture = _tex("tvm_front.png"); m.roughness = 0.4; m.emission_enabled = true; m.emission_texture = _tex("tvm_front.png"); m.emission_energy_multiplier = 0.35
		"newspaper":
			m.albedo_texture = _tex("newspaper.png"); m.roughness = 0.5
		"helppoint":
			m.albedo_texture = _tex("helppoint.png"); m.roughness = 0.35
		_:
			m.albedo_color = Color(0.5, 0.5, 0.5)
	_mats[key] = m
	return m


static func _node(kit: MeshKit, name: String) -> Node3D:
	var root := Node3D.new()
	root.name = name
	var mats := {}
	for k in kit.surfaces.keys():
		mats[k] = mat(String(k).get_slice("@", 0)) if not String(k).contains("@") else _sized(String(k))
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build(mats)
	mi.name = "Mesh"
	root.add_child(mi)
	return root


static func _sized(key: String) -> Material:
	# "name@w@h": a textured material whose UVs (metres in MeshKit) span exactly w x h
	if _mats.has(key):
		return _mats[key]
	var base := (mat(key.get_slice("@", 0)) as StandardMaterial3D).duplicate() as StandardMaterial3D
	base.uv1_scale = Vector3(1.0 / float(key.get_slice("@", 1)), 1.0 / float(key.get_slice("@", 2)), 1.0)
	_mats[key] = base
	return base


static func _solid(root: Node3D, centre: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = root.get_node_or_null("Collision")
	if body == null:
		body = StaticBody3D.new()
		body.name = "Collision"
		root.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = centre
	body.add_child(cs)


## seat markers (pelvis point, top of the cushion; -Z = the way the sitter faces) for Seats / the sit-down action
static func _seat_markers(root: Node3D, count: int, x0: float, pitch: float, z: float) -> void:
	for i in count:
		var m := Node3D.new()
		m.name = "seat_%d" % i
		m.position = Vector3(x0 + i * pitch, 0.45, z)
		m.add_to_group("seat")
		root.add_child(m)


static func _fp(root: Node3D, c: Vector2, h: Vector2) -> void:
	root.set_meta("fp", {"c": c, "h": h})


## a front-facing quad (faces -Z) centred at (x, y, z), width w, height h, textured once across it
static func _front(kit: MeshKit, key: String, x: float, y: float, z: float, w: float, h: float) -> void:
	# seen from -Z, +x is to the viewer's left: top-left = +x
	var l := x + w * 0.5
	var r := x - w * 0.5
	kit.quad("%s@%.3f@%.3f" % [key, w, h], Vector3(l, y + h * 0.5, z), Vector3(l, y - h * 0.5, z), Vector3(r, y - h * 0.5, z), Vector3(r, y + h * 0.5, z), 0.0, Vector2.ZERO, 0.0, true)


# ---------------------------------------------------------------------------------------------------
# platform furniture
# ---------------------------------------------------------------------------------------------------
## Perforated-steel 4-seat beam bench of deep-tube platforms (Toro-type): perforated shell seats and backs, black tubular frame, yellow end arms.
## 2.3 x 0.6 m, seat 0.445 m, overall height 0.765 m (Hille Toro data sheet).
static func bench_toro(shell := "perforated") -> Node3D:
	var kit := MeshKit.new()
	var L := 2.3
	var seats := 4
	var pitch := (L - 0.1) / seats
	for i in seats:
		var x := -L * 0.5 + 0.05 + (i + 0.5) * pitch
		kit.box(shell, Vector3(x, 0.445, 0.0), Vector3(pitch - 0.03, 0.035, 0.46), 0.0)              # seat pressing
		kit.box_xf(shell, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(x, 0.60, 0.28)), Vector3(pitch - 0.03, 0.30, 0.03), 0.0)   # back, leaning back (+z)
	for i in seats - 1:
		var xa := -L * 0.5 + 0.05 + (i + 1) * pitch
		kit.box("black", Vector3(xa, 0.62, 0.05), Vector3(0.025, 0.035, 0.30), 0.0)                     # dividing arms (slim armrest bars)
		kit.box("black", Vector3(xa, 0.51, 0.20), Vector3(0.025, 0.2, 0.025), 0.0)                      # ... each on a post at the back
	for sx in [-1.0, 1.0]:
		kit.box("yellow", Vector3(sx * (L * 0.5 - 0.02), 0.62, 0.0), Vector3(0.05, 0.05, 0.48), 0.0)   # yellow end arm straps
		kit.box("yellow", Vector3(sx * (L * 0.5 - 0.02), 0.50, -0.23), Vector3(0.05, 0.25, 0.05), 0.0)
		kit.box("black", Vector3(sx * (L * 0.5 - 0.12), 0.22, 0.0), Vector3(0.04, 0.44, 0.04), 0.0)     # legs
		kit.box("black", Vector3(sx * (L * 0.5 - 0.12), 0.02, 0.0), Vector3(0.05, 0.03, 0.44), 0.0)     # feet
	kit.box("black", Vector3(0, 0.40, 0.0), Vector3(L - 0.1, 0.05, 0.05), 0.0)                          # beam
	var n := _node(kit, "BenchToro")
	_seat_markers(n, seats, -L * 0.5 + 0.05 + pitch * 0.5, pitch, 0.0)
	_solid(n, Vector3(0, 0.45, 0.06), Vector3(L, 0.9, 0.62))
	_fp(n, Vector2(0, 0.06), Vector2(L * 0.5, 0.31))
	return n


## Timber-slat bench on a black steel frame with yellow loop arms (open-air and sub-surface platforms): 2.2 x 0.62 m, seat 0.45 m, back 0.87 m
static func bench_timber() -> Node3D:
	var kit := MeshKit.new()
	var L := 2.2
	for k in 5:
		kit.box("timber", Vector3(0, 0.45, -0.22 + k * 0.105), Vector3(L - 0.1, 0.025, 0.085), 0.0)       # seat slats
	for k in 4:
		kit.box_xf("timber", Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-14.0)), Vector3(0, 0.58 + k * 0.1, 0.27 + k * 0.022)), Vector3(L - 0.1, 0.08, 0.022), 0.0)
	var legs := [-L * 0.5 + 0.12, -L * 0.25, 0.0, L * 0.25, L * 0.5 - 0.12]
	for x in legs:
		kit.box("black", Vector3(x, 0.22, -0.2), Vector3(0.04, 0.44, 0.04), 0.0)
		kit.box_xf("black", Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-14.0)), Vector3(x, 0.4, 0.3)), Vector3(0.04, 0.8, 0.04), 0.0)
		kit.box("black", Vector3(x, 0.02, 0.05), Vector3(0.05, 0.03, 0.6), 0.0)
	kit.box("black", Vector3(0, 0.40, -0.2), Vector3(L - 0.1, 0.04, 0.04), 0.0)
	for sx in [-1.0, 1.0]:
		kit.box("yellow", Vector3(sx * (L * 0.5 - 0.04), 0.66, -0.05), Vector3(0.04, 0.04, 0.5), 0.0)
		kit.box("yellow", Vector3(sx * (L * 0.5 - 0.04), 0.55, -0.27), Vector3(0.04, 0.22, 0.04), 0.0)
	var n := _node(kit, "BenchTimber")
	_seat_markers(n, 4, -L * 0.5 + 0.1 + (L - 0.2) / 8.0, (L - 0.2) / 4.0, -0.02)
	_solid(n, Vector3(0, 0.45, 0.04), Vector3(L, 0.9, 0.64))
	_fp(n, Vector2(0, 0.04), Vector2(L * 0.5, 0.32))
	return n


# ---------------------------------------------------------------------------------------------------
# open-air platform furniture (surface stations, after the reference photos in build/refs_dress/surface)
# ---------------------------------------------------------------------------------------------------
static func _shrub(kit: MeshKit, c: Vector3, r: float, h: float, key := "shrub") -> void:
	# a rounded bush: a squashed dome built as a surface of revolution
	var prof := PackedVector2Array()
	for q in [[0.0, 1.0], [0.45, 0.93], [0.78, 0.7], [0.97, 0.38], [1.0, 0.1], [0.9, 0.0]]:
		prof.append(Vector2(q[0] * r, c.y + q[1] * h))
	kit.lathe(key, prof, c.x, c.z, 1.0, 1.0, 10, 0.0)


## A timber box planter with shrubs, 1.1 x 0.45 m (the planters along the Kew Gardens platforms); front faces -Z
static func planter_box() -> Node3D:
	var kit := MeshKit.new()
	kit.seed_rng(5)
	kit.box("timber", Vector3(0, 0.22, 0), Vector3(1.1, 0.44, 0.46), 0.0)
	kit.box("soil", Vector3(0, 0.45, 0), Vector3(1.0, 0.03, 0.36), 0.0)
	for k in 3:
		_shrub(kit, Vector3(-0.34 + k * 0.34, 0.45, 0.0), 0.2, 0.42 + 0.06 * (k % 2), "shrub" if k != 1 else "shrub_light")
	var n := _node(kit, "PlanterBox")
	_solid(n, Vector3(0, 0.3, 0), Vector3(1.1, 0.6, 0.46))
	_fp(n, Vector2.ZERO, Vector2(0.55, 0.23))
	return n


## A low red-brick raised planter, 2.4 x 0.8 m, 0.55 m high, stone coping, planted (Northwick Park)
static func planter_brick() -> Node3D:
	var kit := MeshKit.new()
	kit.seed_rng(9)
	kit.box("brick", Vector3(0, 0.26, 0), Vector3(2.4, 0.52, 0.8), 0.0)
	kit.box("coping", Vector3(0, 0.55, 0), Vector3(2.5, 0.06, 0.9), 0.0)
	kit.box("soil", Vector3(0, 0.59, 0), Vector3(2.2, 0.03, 0.6), 0.0)
	for k in 4:
		_shrub(kit, Vector3(-0.8 + k * 0.54, 0.6, 0.0), 0.3, 0.5 + 0.1 * (k % 2), "shrub" if k % 2 == 0 else "shrub_light")
	var n := _node(kit, "PlanterBrick")
	_solid(n, Vector3(0, 0.4, 0), Vector3(2.5, 0.8, 0.9))
	_fp(n, Vector2.ZERO, Vector2(1.25, 0.45))
	return n


## A lamp standard for an open-air platform, 5.2 m: "victorian" (black fluted post with a lantern), "concrete" (a slim concrete pole with a round shade, Loughton),
## "cctv" (pale grey-green pole with an outrigger arm carrying CCTV cameras, Northwick Park)
static func lamp_post(kind: String) -> Node3D:
	var kit := MeshKit.new()
	var h := 5.2
	match kind:
		"victorian":
			kit.box("black", Vector3(0, 0.3, 0), Vector3(0.3, 0.6, 0.3), 0.0)
			kit.box("black", Vector3(0, 2.4, 0), Vector3(0.14, 4.4, 0.14), 0.0)
			kit.box("black", Vector3(0, 1.0, 0), Vector3(0.22, 0.1, 0.22), 0.0)
			kit.box("black", Vector3(0, h - 0.55, 0), Vector3(0.28, 0.08, 0.28), 0.0)
			kit.box("lantern", Vector3(0, h - 0.25, 0), Vector3(0.34, 0.4, 0.34), 0.0)
			kit.box("black", Vector3(0, h + 0.02, 0), Vector3(0.44, 0.06, 0.44), 0.0)
			kit.box("black", Vector3(0, h + 0.14, 0), Vector3(0.2, 0.2, 0.2), 0.0)
		"concrete":
			kit.box("concrete_lamp", Vector3(0, h * 0.5, 0), Vector3(0.22, h, 0.22), 0.0)
			kit.box("concrete_lamp", Vector3(0, 0.25, 0), Vector3(0.34, 0.5, 0.34), 0.0)
			kit.box("lantern", Vector3(0, h + 0.05, 0), Vector3(0.62, 0.12, 0.62), 0.0)
			kit.box("concrete_lamp", Vector3(0, h + 0.16, 0), Vector3(0.7, 0.08, 0.7), 0.0)
		_:
			kit.box("pole_grey", Vector3(0, h * 0.5, 0), Vector3(0.16, h, 0.16), 0.0)
			kit.box("pole_grey", Vector3(0, 0.3, 0), Vector3(0.26, 0.6, 0.26), 0.0)
			kit.box("pole_grey", Vector3(0.6, h - 0.35, 0), Vector3(1.2, 0.1, 0.1), 0.0)
			kit.box("lantern", Vector3(1.05, h - 0.45, 0), Vector3(0.5, 0.06, 0.2), 0.0)
			for cy in [h - 0.1, h - 1.0]:
				kit.box("charcoal", Vector3(-0.12, cy, 0.0), Vector3(0.14, 0.16, 0.3), 0.0)
				kit.box("charcoal", Vector3(0.12, cy, 0.0), Vector3(0.14, 0.16, 0.3), 0.0)
			kit.box("yellow", Vector3(0, 1.4, 0), Vector3(0.18, 0.12, 0.18), 0.0)
	var n := _node(kit, "Lamp_" + kind)
	_solid(n, Vector3(0, 1.0, 0), Vector3(0.3, 2.0, 0.3))
	_fp(n, Vector2.ZERO, Vector2(0.2, 0.2))
	return n


## A platform name board on a post, double sided (the white board carries the red ring and blue bar), as at Northwick Park; origin at the foot
static func roundel_post(name: String) -> Node3D:
	var kit := MeshKit.new()
	kit.box("pole_grey", Vector3(0, 1.2, 0), Vector3(0.12, 2.4, 0.12), 0.0)
	var n := _node(kit, "RoundelPost")
	for sd in [-1.0, 1.0]:
		var rd := Signs.roundel(name, 0.62, false)
		rd.position = Vector3(0, 1.7, sd * 0.07)
		rd.rotation.y = PI if sd < 0.0 else 0.0
		n.add_child(rd)
	_solid(n, Vector3(0, 1.2, 0), Vector3(0.9, 2.4, 0.2))
	_fp(n, Vector2.ZERO, Vector2(0.45, 0.12))
	return n


# ---------------------------------------------------------------------------------------------------
# step-free journeys (see StationPlan.lifts): a lift beside each escalator / stair bank, and a barrier across the bank
# ---------------------------------------------------------------------------------------------------
## A lift as it looks from the passenger side: a stainless-steel clad housing with a pair of doors, a call panel beside them and "LIFT" above. StationPlan.LIFT_SIZE (width, height, depth),
## origin at the floor in the middle of the footprint, the doors on the -Z face. (The car is not modelled: the ride is a fade, see Game._ride_lift.)
static func lift_housing() -> Node3D:
	var kit := MeshKit.new()
	var W := StationPlan.LIFT_SIZE.x
	var H := StationPlan.LIFT_SIZE.y
	var D := StationPlan.LIFT_SIZE.z
	kit.box("steel", Vector3(0, H * 0.5, 0), Vector3(W, H, D), 0.0)
	var zf := -D * 0.5 - 0.012
	kit.box("charcoal", Vector3(0, 1.1, zf), Vector3(1.38, 2.18, 0.03), 0.0)                    # the door frame
	for sx in [-1.0, 1.0]:
		kit.box("steel", Vector3(sx * 0.33, 1.08, zf - 0.025), Vector3(0.62, 2.06, 0.03), 0.0)    # the door leaves
	kit.box("charcoal", Vector3(0, 1.08, zf - 0.043), Vector3(0.02, 2.06, 0.01), 0.0)            # the seam between them
	kit.box("charcoal", Vector3(0.9, 1.05, zf - 0.02), Vector3(0.2, 0.34, 0.03), 0.0)            # the call panel
	kit.box("lantern", Vector3(0.9, 1.12, zf - 0.04), Vector3(0.05, 0.05, 0.01), 0.0)
	kit.box("yellow", Vector3(0.9, 0.98, zf - 0.04), Vector3(0.05, 0.05, 0.01), 0.0)
	kit.box("charcoal", Vector3(0, 2.46, zf - 0.02), Vector3(1.4, 0.34, 0.04), 0.0)              # the sign above
	var n := _node(kit, "LiftHousing")
	var lab := Label3D.new()
	lab.text = "LIFT"
	lab.font = load("res://assets/fonts/Barlow-Bold.ttf")
	lab.font_size = 96
	lab.pixel_size = 0.0021
	lab.modulate = Color(1, 1, 1)
	lab.shaded = false
	lab.double_sided = false
	lab.position = Vector3(0, 2.46, zf - 0.045)
	lab.rotation.y = PI
	n.add_child(lab)
	_solid(n, Vector3(0, H * 0.5, 0), Vector3(W, H, D))
	_fp(n, Vector2.ZERO, Vector2(W * 0.5, D * 0.5))
	return n


## A barrier across the mouth of an escalator or stair bank on a step-free journey: posts, two bars and a board; it stops the player only (collision layer 3, like the platform-edge guard)
static func bank_barrier(width: float, stairs: bool) -> Node3D:
	var kit := MeshKit.new()
	var hw := width * 0.5 + 0.35
	for sx in [-1.0, 1.0]:
		kit.box("steel", Vector3(sx * hw, 0.5, 0), Vector3(0.07, 1.0, 0.07), 0.0)
		kit.box("black", Vector3(sx * hw, 0.04, 0), Vector3(0.3, 0.08, 0.3), 0.0)
	for y in [0.55, 0.9]:
		kit.box("yellow" if y > 0.7 else "white", Vector3(0, y, 0), Vector3(hw * 2.0, 0.05, 0.03), 0.0)
	var n := _node(kit, "BankBarrier")
	var board := Signs.board([{"text": "Stairs only" if stairs else "Escalators", "bold": true}, {"text": "not step-free: use the lift", "text_color": Color(0.85, 0.85, 0.85)}], 1.2, 0.34)
	board.position = Vector3(0, 1.25, 0)
	n.add_child(board)
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1 << 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(hw * 2.0, 1.8, 0.4)
	cs.shape = sh
	cs.position = Vector3(0, 0.9, 0)
	body.add_child(cs)
	n.add_child(body)
	_fp(n, Vector2.ZERO, Vector2(hw, 0.2))
	return n


## A platform waste hoop: a steel hoop about 0.45 m across at 0.85 m on a short pole, with a CLEAR polythene sack so the contents show
## (bins were withdrawn after 1991 and came back from 2011 as clear sacks on hoops). recycle = green hoop, else black.
static func bin_hoop(recycle := false) -> Node3D:
	var kit := MeshKit.new()
	var hoop := "green" if recycle else "black"
	kit.box(hoop, Vector3(0, 0.45, 0.0), Vector3(0.05, 0.9, 0.05), 0.0)                                # pole
	kit.box(hoop, Vector3(0, 0.02, 0.0), Vector3(0.36, 0.03, 0.36), 0.0)                               # base
	for a in 8:
		var ang := a * TAU / 8.0
		kit.box_xf(hoop, Transform3D(Basis(Vector3.UP, -ang), Vector3(cos(ang) * 0.225, 0.86, sin(ang) * 0.225)), Vector3(0.03, 0.03, 0.18), 0.0)   # the ring, eight segments
	kit.box("sack", Vector3(0, 0.55, 0.0), Vector3(0.42, 0.62, 0.42), 0.0)
	kit.box("litter", Vector3(0.05, 0.3, 0.04), Vector3(0.14, 0.1, 0.12), 0.0)
	kit.box("white", Vector3(-0.06, 0.38, -0.05), Vector3(0.1, 0.12, 0.1), 0.0)
	var n := _node(kit, "BinHoop")
	_solid(n, Vector3(0, 0.45, 0.0), Vector3(0.46, 0.9, 0.46))
	_fp(n, Vector2.ZERO, Vector2(0.23, 0.23))
	return n


## Ceiling-hung bracket seen on deep-tube platforms: a steel bar from the crown carrying two black ball loudspeakers and a pair of small
## cameras. Origin at the ceiling attachment, hangs 0.9 m.
static func crown_cluster() -> Node3D:
	var kit := MeshKit.new()
	kit.box("steel", Vector3(0, -0.12, 0), Vector3(0.05, 0.24, 0.05), 0.0)                              # stalk
	kit.box("steel", Vector3(0, -0.26, 0), Vector3(0.9, 0.05, 0.05), 0.0)                               # cross bar
	for sx in [-0.32, 0.32]:
		kit.box("black", Vector3(sx, -0.40, 0), Vector3(0.03, 0.22, 0.03), 0.0)                         # speaker stalks
	var n := _node(kit, "CrownCluster")
	# speaker balls and camera domes are spheres: add them as real meshes
	for sx in [-0.32, 0.32]:
		var sm := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.14; sph.height = 0.28; sph.radial_segments = 16; sph.rings = 8
		sm.mesh = sph
		sm.material_override = mat("black")
		sm.position = Vector3(sx, -0.62, 0)
		n.add_child(sm)
	for cx in [-0.08, 0.08]:
		var cm := MeshInstance3D.new()
		var dome := SphereMesh.new()
		dome.radius = 0.07; dome.height = 0.14; dome.radial_segments = 12; dome.rings = 6
		cm.mesh = dome
		cm.material_override = mat("white")
		cm.position = Vector3(cx, -0.33, 0)
		n.add_child(cm)
	return n


# ---------------------------------------------------------------------------------------------------
# halls
# ---------------------------------------------------------------------------------------------------
## Round white Help Point (about 0.45 m) on the wall at 1.3 m: white drum with a blue ring, information and emergency buttons, call point.
## Origin on the wall at the pod's centre height.
static func help_point_disc() -> Node3D:
	var root := Node3D.new()
	root.name = "HelpPoint"
	var drum := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.225; cyl.bottom_radius = 0.225; cyl.height = 0.09; cyl.radial_segments = 32
	drum.mesh = cyl
	drum.material_override = mat("white")
	drum.rotation.x = PI * 0.5
	drum.position = Vector3(0, 0, -0.045)
	root.add_child(drum)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.44, 0.44)
	face.mesh = q
	face.material_override = mat("helppoint")
	face.rotation.y = PI
	face.position = Vector3(0, 0, -0.092)
	root.add_child(face)
	_solid(root, Vector3(0, 0, -0.05), Vector3(0.46, 0.46, 0.1))
	_fp(root, Vector2(0, -0.05), Vector2(0.23, 0.05))
	return root


## Free-standing two-pole information stand (grey aluminium, weighted base) holding a Double Royal poster: 0.7 x 1.9 m
static func poster_stand(art: String) -> Node3D:
	var kit := MeshKit.new()
	kit.box("steel", Vector3(0, 0.03, 0.0), Vector3(0.62, 0.06, 0.4), 0.0)                              # weighted base
	for sx in [-0.3, 0.3]:
		kit.box("steel", Vector3(sx, 0.95, 0.0), Vector3(0.045, 1.8, 0.045), 0.0)
	kit.box("steel", Vector3(0, 1.82, 0.0), Vector3(0.66, 0.05, 0.05), 0.0)
	kit.box("steel", Vector3(0, 0.6, 0.0), Vector3(0.66, 0.05, 0.05), 0.0)
	var n := _node(kit, "PosterStand")
	# the poster itself, both faces, as one framed panel
	var pk := MeshKit.new()
	for face in [-1.0, 1.0]:
		PosterKit.add(pk, "dr", Vector3(0, 0.72, face * 0.03), Vector3(0, 0, face), art, "silver")
	PosterKit.finish(pk, n, "Poster")
	_solid(n, Vector3(0, 0.95, 0), Vector3(0.7, 1.9, 0.12))
	_fp(n, Vector2.ZERO, Vector2(0.35, 0.2))
	return n


## Blue free-newspaper stand, 0.5 x 0.3 x 1.0 m (invented title)
static func newspaper_stand() -> Node3D:
	var kit := MeshKit.new()
	kit.box("newspaper", Vector3(0, 0.5, 0.0), Vector3(0.5, 1.0, 0.3), 0.0)
	kit.box("charcoal", Vector3(0, 0.03, 0.0), Vector3(0.52, 0.06, 0.32), 0.0)
	var n := _node(kit, "NewspaperStand")
	_solid(n, Vector3(0, 0.5, 0.0), Vector3(0.5, 1.0, 0.3))
	_fp(n, Vector2.ZERO, Vector2(0.25, 0.15))
	return n


## A wall bay of ticket machines: a charcoal surround (0.52 m deep, 2.3 m tall) with a header carrying the lit 'Tickets' sign, around `n_mfm`
## multi-fare machines (0.9 m) and `n_tvm` narrow card-only ones (0.5 m), modelled props set back inside it. Origin on the wall at the bay's
## centre, body toward -Z. Falls back to flat machine fronts when the machine models are missing.
static func ticket_bay(n_mfm: int, n_tvm: int) -> Node3D:
	var have := ResourceLoader.exists(StationProps.DIR + "ticket_machine_mfm.glb") and ResourceLoader.exists(StationProps.DIR + "ticket_machine_tvm.glb")
	var kit := MeshKit.new()
	var w := n_mfm * 1.0 + n_tvm * 0.62 + 0.24
	var d := 0.52
	kit.box("charcoal", Vector3(0, 1.15, -0.03), Vector3(w, 2.3, 0.06), 0.0)                              # back panel on the wall
	for sx in [-1.0, 1.0]:
		kit.box("charcoal", Vector3(sx * (w * 0.5 - 0.03), 1.15, -d * 0.5), Vector3(0.06, 2.3, d), 0.0)   # sides
	kit.box("charcoal", Vector3(0, 2.15, -d * 0.5), Vector3(w, 0.3, d), 0.0)                              # header
	kit.box("steel", Vector3(0, 2.32, -d * 0.5), Vector3(w + 0.06, 0.04, d + 0.04), 0.0)                  # cap
	kit.box("charcoal", Vector3(0, 0.05, -d * 0.5), Vector3(w - 0.1, 0.1, d - 0.05), 0.0)                 # plinth
	var x := -w * 0.5 + 0.12
	var items: Array = []
	for i in n_mfm:
		items.append("mfm")
	for i in n_tvm:
		items.append("tvm")
	var root: Node3D = null
	var slots: Array = []
	for it in items:
		var mw := 0.92 if it == "mfm" else 0.52
		slots.append([it, x + mw * 0.5])
		if not have:
			_front(kit, it, -(x + mw * 0.5), 1.05, -d + 0.05, mw, 1.4)
		x += mw + 0.1
	if not have:
		_front(kit, "sign_blue", 0.0, 2.15, -d - 0.004, minf(w - 0.1, 1.6), 0.22)
	root = _node(kit, "TicketBay")
	if have:
		for sl in slots:
			var m := StationProps.inst("ticket_machine_mfm" if sl[0] == "mfm" else "ticket_machine_tvm")
			root.add_child(m)
			m.position = Vector3(sl[1], 0.1, -0.36)
			m.rotation.y = 0.0
		var sg := StationProps.inst("tickets_sign")
		root.add_child(sg)
		sg.position = Vector3(0, 2.1, -d - 0.005)
	_solid(root, Vector3(0, 1.15, -d * 0.5), Vector3(w, 2.3, d))
	_fp(root, Vector2(0, -d * 0.5), Vector2(w * 0.5, d * 0.5))
	root.set_meta("width", w)
	return root
