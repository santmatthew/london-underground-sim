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
		esc.build(e["rise"], e["lanes"], "tile_white", e.get("stairs", false))
		esc.position = e["pos"]
		esc.rotation.y = e["yaw"]
		esc.name = e["id"]
		add_child(esc)
		escalators.append(esc)
		if not e.get("stairs", false):
			Sfx.loop_at("escalator_loop", esc, Vector3(esc.length * 0.5, -esc.rise * 0.5 + 1.5, 0), -4.0, 26.0)
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
# Gateline (Blender gate units)
# ---------------------------------------------------------------------------------------------------
func _build_gateline() -> void:
	var g: Dictionary = plan.gates
	var z: float = g["z"]
	var hx: float = -float((plan.hall["rect"] as Array)[0])
	var total_w: float = g["total_w"]
	var fence_body := StaticBody3D.new()
	fence_body.name = "GateFence"
	fitting_root.add_child(fence_body)
	for ld in g["lanes"]:
		var lane := _make_gate(ld, z)
		gate_nodes.append(lane)
		fitting_root.add_child(lane["node"])
	# fixed barriers from the ends of the lane block to the hall walls
	for side: float in [-1.0, 1.0]:
		var edge: float = side * total_w * 0.5
		var span: float = hx - total_w * 0.5
		var x: float = edge
		while span > 0.05:
			var seg: float = minf(2.0, span)
			var f := StationProps.inst("gate_fence")
			fitting_root.add_child(f)
			f.position = Vector3(x + side * seg * 0.5, 0, z)
			if seg < 2.0:
				f.scale.x = seg / 2.0
			x += side * seg
			span -= seg
	var cs_l := CollisionShape3D.new()
	var sh_l := BoxShape3D.new()
	sh_l.size = Vector3(hx * 2.0, 1.6, 0.2)
	cs_l.shape = sh_l
	cs_l.position = Vector3(0, 0.8, z + 0.0)
	# (lane block collision comes from the gate units; the fences collide via a thin wall behind the fence line)
	var side_l := CollisionShape3D.new()
	var side_sh := BoxShape3D.new()
	side_sh.size = Vector3(hx - total_w * 0.5, 1.6, 0.2)
	side_l.shape = side_sh
	side_l.position = Vector3(-(total_w * 0.5 + (hx - total_w * 0.5) * 0.5), 0.8, z)
	fence_body.add_child(side_l)
	var side_r := CollisionShape3D.new()
	side_r.shape = side_sh
	side_r.position = Vector3((total_w * 0.5 + (hx - total_w * 0.5) * 0.5), 0.8, z)
	fence_body.add_child(side_r)


func _make_gate(ld: Dictionary, z: float) -> Dictionary:
	var kind: int = ld["kind"]
	var wide: bool = ld["wide"]
	var node := StationProps.inst("gate_wide" if wide else "gate_unit")
	node.position = Vector3(ld["x"], 0, z)
	# the models let passengers walk toward -Z; entry lanes (moving +z) are turned around
	node.rotation.y = PI if kind > 0 else 0.0
	node.name = "Gate"
	var flap_l := node.get_node_or_null("door_L" if wide else "flap_L") as Node3D
	var flap_r := node.get_node_or_null("door_R" if wide else "flap_R") as Node3D
	var lamp_go := node.get_node_or_null("lamp_go") as Node3D
	var lamp_stop := node.get_node_or_null("lamp_stop") as Node3D
	if lamp_go:
		lamp_go.visible = false
	# lane blocker (closed flaps)
	var blocker := StaticBody3D.new()
	var bcs := CollisionShape3D.new()
	var bsh := BoxShape3D.new()
	bsh.size = Vector3(0.9 if wide else 0.6, 1.3, 0.06)
	bcs.shape = bsh
	bcs.position = Vector3(0, 0.65, -0.1)
	blocker.add_child(bcs)
	node.add_child(blocker)
	# trigger zone on both sides of the lane
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = (1 << 3) | (1 << 1)
	var acs := CollisionShape3D.new()
	var ash := BoxShape3D.new()
	ash.size = Vector3(0.8 if not wide else 1.1, 1.8, 2.8)
	acs.shape = ash
	acs.position = Vector3(0, 0.9, 0)
	area.add_child(acs)
	node.add_child(area)
	var gd := {"node": node, "flaps": blocker, "fl": flap_l, "fr": flap_r, "kind": kind, "open_t": 0.0, "area": area, "lamp_go": lamp_go, "lamp_stop": lamp_stop, "wide": wide, "is_open": false}
	area.body_entered.connect(_on_gate_body.bind(gd))
	return gd


func _on_gate_body(body: Node3D, gd: Dictionary) -> void:
	# open if the body approaches from the correct side (entry lanes: from -z heading +z; exit lanes: from +z heading -z)
	# gate-local frame: the models let passengers walk toward local -Z, so the approach side is local +Z for both lane kinds.
	# (World coordinates would be wrong: after a ride the station is placed with an arbitrary rotation.)
	var kind: int = gd["kind"]
	if (gd["node"] as Node3D).to_local(body.global_position).z <= 0.0:
		return
	_open_gate(gd)
	Sfx.play_at("gate_beep_ok", gd["node"], Vector3(0, 1.1, 0), 0.0 if body is Player else -8.0, 18.0)
	if body is Player:
		gate_tapped.emit(kind)


func _set_gate_state(gd: Dictionary, open: bool) -> void:
	if gd["is_open"] == open:
		return
	gd["is_open"] = open
	Sfx.play_at("gate_flap_open" if open else "gate_flap_close", gd["node"], Vector3(0, 1.0, 0), -8.0, 14.0)
	(gd["flaps"] as StaticBody3D).collision_layer = 0 if open else 1
	var ang := 90.0 if open else 0.0
	for key in ["fl", "fr"]:
		var f: Node3D = gd[key]
		if f:
			var target := deg_to_rad(ang if key == "fl" else -ang)
			var tw := create_tween()
			tw.tween_property(f, "rotation:y", target, 0.28)
	if gd["lamp_go"]:
		(gd["lamp_go"] as Node3D).visible = open
	if gd["lamp_stop"]:
		(gd["lamp_stop"] as Node3D).visible = not open


func _open_gate(gd: Dictionary) -> void:
	gd["open_t"] = 2.4
	_set_gate_state(gd, true)


func _process(delta: float) -> void:
	for gd in gate_nodes:
		if gd["open_t"] > 0.0:
			gd["open_t"] -= delta
			if gd["open_t"] <= 0.0:
				var occupied := false
				for b in (gd["area"] as Area3D).get_overlapping_bodies():
					if absf((gd["node"] as Node3D).to_local(b.global_position).z) < 0.8:
						occupied = true
				if occupied:
					gd["open_t"] = 0.4
				else:
					_set_gate_state(gd, false)


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
## station-LOCAL position (use to_global() for world space: after a ride the station is not at the origin)
func platform_point(face_key: String, frac: float, inset := 0.9) -> Vector3:
	var f: Dictionary = plan.faces[face_key]
	var x: float = lerpf(f["x0"] + 4.0, f["x1"] - 4.0, frac)
	var side: float = f["side"]
	return Vector3(x, f["y"], f["edge_z"] - side * inset)
