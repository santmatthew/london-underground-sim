class_name Station
extends Node3D
## Live 3D station built from a StationPlan.

signal street_exit_reached(door_id: String)
signal gate_tapped(direction: int)

var plan: StationPlan
var spaces: Dictionary = {}          # name -> Space
var escalators: Array = []           # Escalator nodes
var modules: Array = []              # PlatformModule nodes
var gate_nodes: Array = []
var light_nodes: Array = []
var fitting_root: Node3D
var stats := {"tris": 0, "lights": 0}
var trains: TrainService
var crowd: CrowdManager


var async_mode := false
var prof: Dictionary = {}


func _t(label: String, t0: int) -> int:
	prof[label] = prof.get(label, 0) + Time.get_ticks_msec() - t0
	return Time.get_ticks_msec()


func build(p: StationPlan) -> void:
	build_async(p, false)


func _yield() -> void:
	if async_mode:
		await get_tree().process_frame


## Builds the station spreading the work over several frames (call with `await`).
func build_async(p: StationPlan, use_async := true) -> void:
	async_mode = use_async and is_inside_tree()
	plan = p
	name = "Station_" + plan.name.replace(" ", "_")
	var _t0 := Time.get_ticks_msec()
	for spec in plan.rooms:
		var sp := Space.new()
		sp.build(spec)
		add_child(sp)
		spaces[spec["name"]] = sp
		await _yield()
	_t0 = _t("rooms", _t0)
	for e in plan.escs:
		var esc := Escalator.new()
		esc.build(e["rise"], e["lanes"])
		esc.position = e["pos"]
		esc.rotation.y = e["yaw"]
		esc.name = e["id"]
		add_child(esc)
		escalators.append(esc)
		await _yield()
	_t0 = _t("escalators", _t0)
	for mi in plan.modules.size():
		var m: Dictionary = plan.modules[mi]
		var pm := PlatformModule.new()
		pm.position = m["pos"]
		pm.name = "Module%d" % mi
		add_child(pm)
		pm.build(m["spec"])
		modules.append(pm)
		stats["tris"] += pm.meta.get("tri_count", 0)
		await _yield()
	fitting_root = Node3D.new()
	fitting_root.name = "Fittings"
	add_child(fitting_root)
	_t0 = _t("modules", _t0)
	_build_gateline()
	_build_street_doors()
	_t0 = _t("gates+doors", _t0)
	StationSigns.place(self)
	_t0 = _t("signs", _t0)
	await _yield()
	trains = TrainService.new()
	trains.name = "Trains"
	add_child(trains)
	for k in spaces:
		stats["tris"] += (spaces[k] as Space).kit.triangle_count()
		stats["lights"] += (spaces[k] as Space).light_points.size()


# ---------------------------------------------------------------------------------------------------
# Gateline
# ---------------------------------------------------------------------------------------------------
func _build_gateline() -> void:
	var g: Dictionary = plan.gates
	var kit := MeshKit.new()
	var z: float = g["z"]
	var n: int = g["n"]
	var pitch: float = g["pitch"]
	var total := n * pitch
	var x_start := -total * 0.5
	var body := StaticBody3D.new()
	body.name = "GateBody"
	fitting_root.add_child(body)
	var hx: float = -float((plan.hall["rect"] as Array)[0])
	# barrier posts: n+1 posts between lanes (thick 0.28)
	var kinds: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = plan.seed_value + 5
	for i in n:
		kinds.append(1 if i < (n + 1) / 2 else -1)        # +1 = entry (moves +z), -1 = exit
	if plan.imp < 1.2:
		# quiet stations: bidirectional-ish - keep the same lanes anyway
		pass
	for i in n + 1:
		var px := x_start + i * pitch
		_gate_post(kit, body, px, z)
	# fixed barriers from the last post to the hall walls
	var wall_l := -hx
	var wall_r := hx
	_fence(kit, body, wall_l, x_start, z)
	_fence(kit, body, x_start + total, wall_r, z)
	# one wide accessible gate at the end lane (skip flaps there)
	for i in n:
		var cx := x_start + (i + 0.5) * pitch
		var gate := _make_gate(kit, cx, z, kinds[i])
		gate_nodes.append(gate)
		fitting_root.add_child(gate["node"])
	var mats := {"metal": Mats.get_mat("metal"), "black": Mats.get_mat("black"), "light_emissive": Mats.get_mat("light_emissive"),
		"gate_body": Mats.flat(Color(0.22, 0.24, 0.27), 0.35, 0.6), "gate_top": Mats.flat(Color(0.05, 0.05, 0.06), 0.25, 0.2)}
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build(mats, Mats.get_mat("metal"))
	fitting_root.add_child(mi)


func _gate_post(kit: MeshKit, body: StaticBody3D, x: float, z: float) -> void:
	kit.box({"*": "gate_body", "top": "gate_top"}, Vector3(x, 0.55, z), Vector3(0.14, 1.1, 1.5), 0.0)
	# reader / display head
	kit.box("gate_top", Vector3(x, 1.12, z + 0.0), Vector3(0.18, 0.06, 0.5), 0.0)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.16, 1.4, 1.5)
	cs.shape = sh
	cs.position = Vector3(x, 0.7, z)
	body.add_child(cs)


func _fence(kit: MeshKit, body: StaticBody3D, xa: float, xb: float, z: float) -> void:
	if xb - xa < 0.05:
		return
	kit.box({"*": "gate_body", "top": "gate_top"}, Vector3((xa + xb) * 0.5, 0.55, z), Vector3(xb - xa, 1.1, 0.12), 0.0)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(xb - xa, 1.6, 0.12)
	cs.shape = sh
	cs.position = Vector3((xa + xb) * 0.5, 0.8, z)
	body.add_child(cs)


func _make_gate(kit: MeshKit, cx: float, z: float, kind: int) -> Dictionary:
	# flaps: two thin panels that retract into the posts. Collision only while closed.
	var node := Node3D.new()
	node.position = Vector3(cx, 0, z)
	node.name = "Gate"
	var flaps := StaticBody3D.new()
	var mats_flap := StandardMaterial3D.new()
	mats_flap.albedo_color = Color(0.55, 0.75, 0.9, 0.55)
	mats_flap.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mats_flap.roughness = 0.1
	var flap_meshes := []
	for sgn in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.28, 0.85, 0.02)
		mi.mesh = bm
		mi.material_override = mats_flap
		mi.position = Vector3(sgn * 0.19, 0.75, 0.0)
		node.add_child(mi)
		flap_meshes.append(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.7, 1.0, 0.05)
	cs.shape = sh
	cs.position = Vector3(0, 0.7, 0)
	flaps.add_child(cs)
	node.add_child(flaps)
	# status light above the lane: green arrow when open
	var lamp := MeshInstance3D.new()
	var lm := QuadMesh.new()
	lm.size = Vector2(0.16, 0.16)
	lamp.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.1, 0.9, 0.3) if kind > 0 else Color(0.9, 0.2, 0.2)
	lmat.emission_enabled = true
	lmat.emission = lmat.albedo_color
	lmat.emission_energy_multiplier = 2.0
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp.material_override = lmat
	lamp.position = Vector3(0, 1.16, 0.0)
	lamp.rotation.x = -PI / 2.0
	node.add_child(lamp)
	# trigger zone (both sides)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = (1 << 3) | (1 << 1)      # player + people
	var acs := CollisionShape3D.new()
	var ash := BoxShape3D.new()
	ash.size = Vector3(0.7, 1.8, 2.6)
	acs.shape = ash
	acs.position = Vector3(0, 0.9, 0)
	area.add_child(acs)
	node.add_child(area)
	var gd := {"node": node, "flaps": flaps, "meshes": flap_meshes, "kind": kind, "open_t": 0.0, "area": area, "lamp": lamp}
	area.body_entered.connect(_on_gate_body.bind(gd))
	return gd


func _on_gate_body(body: Node3D, gd: Dictionary) -> void:
	# open if the body approaches from the correct side (entry lanes: from -z heading +z; exit lanes: from +z heading -z)
	var gz: float = (gd["node"] as Node3D).global_position.z
	var side: float = body.global_position.z - gz
	var kind: int = gd["kind"]
	var ok: bool = (kind > 0 and side < 0.0) or (kind < 0 and side > 0.0)
	if not ok:
		return
	_open_gate(gd)
	if body is Player:
		gate_tapped.emit(kind)


func _open_gate(gd: Dictionary) -> void:
	gd["open_t"] = 2.2
	(gd["flaps"] as StaticBody3D).collision_layer = 0
	for m in gd["meshes"]:
		(m as MeshInstance3D).visible = false


func _process(delta: float) -> void:
	for gd in gate_nodes:
		if gd["open_t"] > 0.0:
			gd["open_t"] -= delta
			if gd["open_t"] <= 0.0:
				# only close when nobody is standing in the lane
				var occupied := false
				for b in (gd["area"] as Area3D).get_overlapping_bodies():
					if absf(b.global_position.z - (gd["node"] as Node3D).global_position.z) < 0.6:
						occupied = true
				if occupied:
					gd["open_t"] = 0.4
				else:
					(gd["flaps"] as StaticBody3D).collision_layer = 1
					for m in gd["meshes"]:
						(m as MeshInstance3D).visible = true


# ---------------------------------------------------------------------------------------------------
# Street doors (the "Way out")
# ---------------------------------------------------------------------------------------------------
func _build_street_doors() -> void:
	for sd in plan.street_doors:
		var pos: Vector3 = sd["pos"]
		# glass doors at the end of the passage with a bright daylight panel behind them
		var glass := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(3.0, 2.9)
		glass.mesh = qm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.85, 0.92, 1.0)
		gm.emission_enabled = true
		gm.emission = Color(0.75, 0.85, 1.0)
		gm.emission_energy_multiplier = 3.0
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glass.material_override = gm
		glass.position = Vector3(pos.x, 1.5, pos.z - 0.35)
		glass.rotation.y = 0.0
		fitting_root.add_child(glass)
		# door frame bars
		var kit := MeshKit.new()
		for bx in [-1.5, -0.75, 0.0, 0.75, 1.5]:
			kit.box("metal", Vector3(pos.x + bx, 1.45, pos.z - 0.33), Vector3(0.07, 2.9, 0.07), 0.0)
		kit.box("metal", Vector3(pos.x, 1.0, pos.z - 0.33), Vector3(3.0, 0.06, 0.07), 0.0)
		kit.box("metal", Vector3(pos.x, 2.9, pos.z - 0.33), Vector3(3.0, 0.06, 0.07), 0.0)
		var mi := MeshInstance3D.new()
		mi.mesh = kit.build({"metal": Mats.get_mat("metal")})
		fitting_root.add_child(mi)
		# trigger
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 1 << 3
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(3.0, 2.5, 1.0)
		cs.shape = sh
		area.add_child(cs)
		area.position = Vector3(pos.x, 1.25, pos.z + 0.2)
		area.body_entered.connect(func(b): if b is Player: street_exit_reached.emit(sd["id"]))
		fitting_root.add_child(area)


func attach_crowd(p: Node3D) -> void:
	if crowd != null:
		crowd.player = p as Player
		return
	crowd = CrowdManager.new()
	crowd.name = "Crowd"
	add_child(crowd)
	crowd.setup(self, p)


## world position of a platform face's boarding point given a fraction along the platform (0..1) — inside the platform, at the edge
func platform_point(face_key: String, frac: float, inset := 0.9) -> Vector3:
	var f: Dictionary = plan.faces[face_key]
	var x: float = lerpf(f["x0"] + 4.0, f["x1"] - 4.0, frac)
	var side: float = f["side"]
	return Vector3(x, f["y"], f["edge_z"] - side * inset)
