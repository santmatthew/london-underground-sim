class_name StationDecals
extends RefCounted
## Floor grime: stains, chewing gum and shoe scuffs projected with Decal nodes (distance-faded so they cost little).

const DIR := "res://assets/textures/gen/decals/"
static var _tex: Dictionary = {}


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var p := DIR + name + ".png"
		_tex[name] = load(p) if ResourceLoader.exists(p) else null
	return _tex[name]


static func floor_decal(parent: Node3D, name: String, pos: Vector3, size: Vector2, yaw: float, fade_start := 22.0) -> void:
	var t := tex(name)
	if t == null:
		return
	var d := Decal.new()
	d.texture_albedo = t
	d.size = Vector3(size.x, 0.6, size.y)
	d.position = pos
	d.rotation.y = yaw
	d.distance_fade_enabled = true
	d.distance_fade_begin = fade_start
	d.distance_fade_length = 8.0
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.modulate = Color(1, 1, 1, 1)
	d.cull_mask = 1
	parent.add_child(d)


static func place(station: Station) -> void:
	var plan := station.plan
	var rng := RandomNumberGenerator.new()
	rng.seed = plan.seed_value + 777
	var root := Node3D.new()
	root.name = "Decals"
	station.add_child(root)
	var dens := clampf(0.6 + plan.imp * 0.25, 0.7, 1.8)
	# hall
	var r: Array = plan.hall["rect"]
	_scatter(root, rng, r[0], r[1], r[2], r[3], 0.02, int(26 * dens), int(34 * dens), int(22 * dens))
	for rm in plan.rooms:
		var nm: String = rm["name"]
		var rr: Array = rm["rect"]
		if nm.begins_with("landing"):
			_scatter(root, rng, rr[0], rr[1], rr[2], rr[3], rm["y"] + 0.02, int(8 * dens), int(10 * dens), int(8 * dens))
		elif nm.begins_with("corridor"):
			var n := maxi(2, int((rr[1] - rr[0]) / 7.0))
			_scatter(root, rng, rr[0], rr[1], rr[2], rr[3], rm["y"] + 0.02, n, n, n)
	# platforms
	for mi in plan.modules.size():
		var m: Dictionary = plan.modules[mi]
		var pm: PlatformModule = station.modules[mi]
		var L: float = m["spec"]["length"]
		var zw := PlatformModule.GAP * 0.5
		var holder := Node3D.new()
		holder.name = "Decals"
		pm.add_child(holder)
		for fi in (m["spec"]["faces"] as Array).size():
			var s := 1.0 if fi == 0 else -1.0
			var z0 := minf(s * zw, s * (zw + m["spec"]["pw"]))
			var z1 := maxf(s * zw, s * (zw + m["spec"]["pw"]))
			_scatter(holder, rng, -L * 0.5, L * 0.5, z0, z1, 0.02, int(22 * dens), int(28 * dens), int(20 * dens))
	StationSigns.cull(root, 40.0)


static func _scatter(parent: Node3D, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float, y: float, n_stain: int, n_gum: int, n_scuff: int) -> void:
	for i in n_stain:
		floor_decal(parent, "stain_%d" % (rng.randi() % 4), Vector3(rng.randf_range(x0, x1), y, rng.randf_range(z0, z1)), Vector2.ONE * rng.randf_range(0.7, 2.4), rng.randf() * TAU)
	for i in n_gum:
		floor_decal(parent, "gum", Vector3(rng.randf_range(x0, x1), y, rng.randf_range(z0, z1)), Vector2.ONE * rng.randf_range(1.0, 1.8), rng.randf() * TAU, 12.0)
	for i in n_scuff:
		floor_decal(parent, "scuff", Vector3(rng.randf_range(x0, x1), y, rng.randf_range(z0, z1)), Vector2.ONE * rng.randf_range(1.5, 3.2), rng.randf() * TAU, 16.0)
