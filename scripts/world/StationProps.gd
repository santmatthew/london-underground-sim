class_name StationProps
extends RefCounted
## Places the Blender-generated props (assets/models/props) in a Station: ticket hall furniture, platform benches, posters, CCTV ...
## Everything is deterministic per station (seeded from the station id).

const DIR := "res://assets/models/props/"
const PORTRAIT_POSTERS := 8      # poster_00..07 portrait, poster_08..11 landscape

static var _packed: Dictionary = {}
static var _poster_tex: Dictionary = {}
static var _poster_mats: Dictionary = {}


## Start loading every prop model on the worker threads (while the menu is up): the first station of a run otherwise loads them one by one on the main thread
static func preload_async() -> void:
	for f in ResourceLoader.list_directory(DIR):
		if f.ends_with(".glb"):
			ResourceLoader.load_threaded_request(DIR + f, "", true)


static func scene(name: String) -> PackedScene:
	if not _packed.has(name):
		_packed[name] = load(DIR + name + ".glb")
	return _packed[name]


static func inst(name: String) -> Node3D:
	return scene(name).instantiate() as Node3D


## rotate `n` so that its front (-Z) points along horizontal direction `dir`
static func face(n: Node3D, dir: Vector3) -> void:
	n.rotation.y = atan2(-dir.x, -dir.z)


static func put(parent: Node3D, name: String, pos: Vector3, dir: Vector3) -> Node3D:
	var n := inst(name)
	parent.add_child(n)
	n.position = pos
	face(n, dir)
	return n


static func poster_material(index: int) -> StandardMaterial3D:
	if _poster_mats.has(index):
		return _poster_mats[index]
	var m := StandardMaterial3D.new()
	var path := "res://assets/textures/props/posters/poster_%02d.png" % index
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
	m.roughness = 0.35
	m.emission_enabled = true
	m.emission_texture = m.albedo_texture
	m.emission_energy_multiplier = 0.55
	_poster_mats[index] = m
	return m


## a poster material for a quad whose UVs are in metres (MeshKit): the texture is scaled to the quad's real size
static func band_poster_material(index: int, w: float, h: float) -> StandardMaterial3D:
	var key := "band_%d_%.3f_%.3f" % [index, w, h]
	if _poster_mats.has(key):
		return _poster_mats[key]
	var m := poster_material(index).duplicate() as StandardMaterial3D
	m.uv1_scale = Vector3(1.0 / w, 1.0 / h, 1.0)
	m.emission_energy_multiplier = 0.3
	_poster_mats[key] = m
	return m


static func put_poster(parent: Node3D, kind: String, wall_pos: Vector3, normal: Vector3, rng: RandomNumberGenerator, bottom := -1.0) -> Node3D:
	var name := "poster_frame_6sheet" if kind == "6" else ("poster_frame_4sheet" if kind == "4" else "poster_frame_48sheet")
	var n := put(parent, name, wall_pos + Vector3(0, bottom if bottom >= 0.0 else (0.45 if kind == "6" else 0.5), 0), normal)
	var landscape := kind == "48"
	var idx: int = (PORTRAIT_POSTERS + rng.randi() % 4) if landscape else (rng.randi() % PORTRAIT_POSTERS)
	var poster := n.get_node_or_null("poster")
	if poster is MeshInstance3D:
		(poster as MeshInstance3D).material_override = poster_material(idx)
	return n


# ---------------------------------------------------------------------------------------------------
static func place(station: Station) -> void:
	var plan := station.plan
	var rng := RandomNumberGenerator.new()
	rng.seed = plan.seed_value + 4242
	var root := Node3D.new()
	root.name = "Props"
	station.add_child(root)
	_hall(station, root, plan, rng)
	for gl in plan.gatelines.slice(1):
		_hall_at(root, plan, gl, rng)
	for rm in plan.rooms:
		var nm: String = rm["name"]
		if nm.begins_with("landing") or nm.begins_with("corridor"):
			_room_dressing(root, rm, rng)
	for mi in plan.modules.size():
		_platform(station.modules[mi], plan, mi, rng)
	StationSigns.cull(root, 55.0)
	for pm in station.modules:
		var ph: Node = pm.get_node_or_null("Props")
		if ph:
			StationSigns.cull(ph, 55.0)


static func _hall(_station: Station, root: Node3D, plan: StationPlan, rng: RandomNumberGenerator) -> void:
	_hall_at(root, plan, plan.gates, rng)


## furniture of one ticket hall (its gateline dictionary carries the hall rect and the gateline z)
static func _hall_at(root: Node3D, plan: StationPlan, gl: Dictionary, rng: RandomNumberGenerator) -> void:
	var r: Array = gl.get("rect", plan.hall["rect"])
	var h: float = StationPlan.HALL_H
	var gz: float = gl["z"]
	var imp := plan.imp
	# ticket machines along the side walls of the unpaid zone
	var n_tm := clampi(int(1.5 + imp), 2, 6)
	for k in n_tm:
		var side := -1.0 if k % 2 == 0 else 1.0
		var z: float = r[2] + 4.2 + (k / 2) * 1.35
		if z > gz - 3.0:
			continue
		var x: float = (r[0] + 0.32) if side < 0.0 else (r[1] - 0.32)
		put(root, "ticket_machine", Vector3(x, 0, z), Vector3(-side, 0, 0))
	# journey planner screen + info totem
	put(root, "journey_planner_screen", Vector3(r[0] + 0.12 * 0.0 + 3.2, 0.55, r[2] + 0.02), Vector3(0, 0, 1))
	put(root, "info_totem", Vector3(r[1] - 5.0, 0, r[2] + 3.6), Vector3(0, 0, 1))
	# kiosk + vending in busier stations
	if imp >= 1.8:
		put(root, "newsstand_kiosk", Vector3(r[1] - 3.0, 0, r[2] + 6.2), Vector3(-1, 0, 0.2).normalized())
	put(root, "vending_machine", Vector3(r[0] + 0.5, 0, gz - 4.2), Vector3(1, 0, 0))
	# bins, clock, cctv, speakers, help point, fire cabinet
	put(root, "bin", Vector3(r[0] + 0.4, 0, r[2] + 1.6), Vector3(1, 0, 0))
	put(root, "bin_recycling", Vector3(r[1] - 0.4, 0, gz - 2.4), Vector3(-1, 0, 0))
	put(root, "clock", Vector3(r[1] - 0.05, 3.1, gz + 2.2), Vector3(-1, 0, 0))
	put(root, "help_point", Vector3(r[0] + 0.3, 0, gz + 4.0), Vector3(1, 0, 0))
	put(root, "fire_cabinet", Vector3(r[1] - 0.02, 0.3, gz + 5.5), Vector3(-1, 0, 0))
	for k in 4:
		var cx: float = lerpf(r[0] + 3.0, r[1] - 3.0, k / 3.0)
		var cz: float = r[2] + 2.0 if k % 2 == 0 else r[3] - 2.0
		put(root, "cctv_dome", Vector3(cx, h, cz), Vector3(0, 0, 1))
	for k in 3:
		put(root, "pa_speaker", Vector3(lerpf(r[0] + 4.0, r[1] - 4.0, k / 2.0), h - 0.6, (r[2] + r[3]) * 0.5), Vector3(0, 0, 1))
	# posters on the paid-side E/W walls
	var zp: float = gz + 4.0
	while zp < r[3] - 5.0:
		put_poster(root, "6", Vector3(r[0] + 0.02, 0, zp), Vector3(1, 0, 0), rng)
		put_poster(root, "6", Vector3(r[1] - 0.02, 0, zp + 3.0), Vector3(-1, 0, 0), rng)
		zp += 7.0
	# the gateline itself
	# (placed by Station._build_gateline)


static func _room_dressing(root: Node3D, rm: Dictionary, rng: RandomNumberGenerator) -> void:
	var r: Array = rm["rect"]
	var y: float = rm["y"]
	var h: float = rm["h"]
	var nm: String = rm["name"]
	if nm.begins_with("landing"):
		# posters on the west wall, cctv + speakers
		var z: float = r[2] + 3.0
		while z < r[3] - 3.0:
			put_poster(root, "6", Vector3(r[0] + 0.02, y, z), Vector3(1, 0, 0), rng)
			z += 6.0
		put(root, "cctv_dome", Vector3((r[0] + r[1]) * 0.5, y + h, (r[2] + r[3]) * 0.5), Vector3(0, 0, 1))
		put(root, "bin", Vector3(r[0] + 0.4, y, r[3] - 1.5), Vector3(1, 0, 0))
	else:
		# corridor: posters every ~13 m on alternating walls
		var x: float = r[0] + 6.0
		var flip := rng.randf() < 0.5
		while x < r[1] - 6.0:
			var zc: float = (r[2] + r[3]) * 0.5
			var wall_z: float = r[3] - 0.02 if flip else r[2] + 0.02
			put_poster(root, "6", Vector3(x, y, wall_z), Vector3(0, 0, -1 if flip else 1), rng)
			flip = not flip
			x += 13.0
		put(root, "cctv_dome", Vector3((r[0] + r[1]) * 0.5, y + h, (r[2] + r[3]) * 0.5), Vector3(1, 0, 0))


static func _platform(pm: PlatformModule, plan: StationPlan, mi: int, rng: RandomNumberGenerator) -> void:
	var m: Dictionary = plan.modules[mi]
	var spec: Dictionary = m["spec"]
	var L: float = spec["length"]
	var ox: Array = spec["openings_x"]
	var pw: float = spec["pw"]
	var zwall := PlatformModule.GAP * 0.5
	var zedge := zwall + pw
	var faces: Array = spec["faces"]
	var holder := Node3D.new()
	holder.name = "Props"
	pm.add_child(holder)
	for fi in faces.size():
		var s := 1.0 if fi == 0 else -1.0
		# benches against the platform-side wall
		var n_b := clampi(int(L / 34.0), 2, 4)
		for k in n_b:
			var x := -L * 0.5 + (k + 0.5) * L / n_b + rng.randf_range(-2.0, 2.0)
			if _near(x, ox, 4.0):
				x += 6.0
			put(holder, "bench_platform", Vector3(x, 0, s * (zwall + 0.30)), Vector3(0, 0, s))
		# bins, help points at the ends, edge markers
		put(holder, "bin", Vector3(-L * 0.5 + 12.0, 0, s * (zwall + 0.3)), Vector3(0, 0, s))
		put(holder, "bin_recycling", Vector3(L * 0.5 - 14.0, 0, s * (zwall + 0.3)), Vector3(0, 0, s))
		put(holder, "help_point", Vector3(-L * 0.5 + 3.0, 0, s * (zwall + 0.25)), Vector3(0, 0, s))
		put(holder, "help_point", Vector3(L * 0.5 - 3.0, 0, s * (zwall + 0.25)), Vector3(0, 0, s))
		put(holder, "platform_edge_marker", Vector3(-L * 0.5 + 1.0, 0, s * (zedge - 0.3)), Vector3(0, 0, s))
		put(holder, "platform_edge_marker", Vector3(L * 0.5 - 1.0, 0, s * (zedge - 0.3)), Vector3(0, 0, s))
		# posters on the platform-side wall, away from openings and roundels
		var x2 := -L * 0.5 + 9.0
		while x2 < L * 0.5 - 8.0:
			if not _near(x2, ox, 4.5):
				put_poster(holder, "6", Vector3(x2, 0, s * (zwall + 0.02)), Vector3(0, 0, s), rng)
			x2 += 9.5
		# cctv + clocks + speakers on the wall
		var x3 := -L * 0.5 + 10.0
		while x3 < L * 0.5 - 6.0:
			put(holder, "cctv_dome", Vector3(x3, 2.15, s * (zwall + 0.1)), Vector3(0, 0, s))
			x3 += 26.0
		put(holder, "clock", Vector3(-L * 0.25, 2.1, s * (zwall + 0.03)), Vector3(0, 0, s))
		put(holder, "clock", Vector3(L * 0.25, 2.1, s * (zwall + 0.03)), Vector3(0, 0, s))
		var x4 := -L * 0.5 + 18.0
		while x4 < L * 0.5 - 8.0:
			put(holder, "pa_speaker", Vector3(x4, 2.3, s * (zwall + 0.1)), Vector3(0, 0, s))
			x4 += 20.0
		# tunnel-mouth signals
		var ztrack := zedge + PlatformModule.TRACK_TO_EDGE
		put(holder, "signal_lamp", Vector3(L * 0.5 + 18.0, PlatformModule.BED_Y, s * (ztrack + 1.35)), Vector3(0, 0, -s))
		put(holder, "signal_lamp", Vector3(-L * 0.5 - 18.0, PlatformModule.BED_Y, s * (ztrack + 1.35)), Vector3(0, 0, -s))


static func _near(x: float, xs: Array, d: float) -> bool:
	for o in xs:
		if absf(x - o) < d:
			return true
	return false
