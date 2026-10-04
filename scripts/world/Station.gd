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
const DECALS := false             # floor grime decals: they also land on walls (grey blotches) and were never part of the shipped look
var fitting_root: Node3D


## profiling switch: UG_OFF=decals,dressing,... in the environment turns those build steps off (see tests/perf_test.gd)
static func debug_on(what: String) -> bool:
	return what in OS.get_environment("UG_ON").split(",")


static func debug_off(what: String) -> bool:
	return what in OS.get_environment("UG_OFF").split(",")
var stats := {"tris": 0, "lights": 0}
var trains: TrainService
var crowd: CrowdManager
var has_bend := false                # some platform module is curved (to_phys / to_design do something)


var async_mode := false
var prof: Dictionary = {}


func _t(label: String, t0: int) -> int:
	prof[label] = prof.get(label, 0) + Time.get_ticks_msec() - t0
	return Time.get_ticks_msec()


func build(p: StationPlan) -> void:
	build_async(p, false)


var _chunk_us := 0
const SLICE_US := 25000         # a stretch of build work between two frames should not be much longer than this


## Frame break between the big steps of the build (a no-op for the synchronous `build`)
func _yield() -> void:
	if async_mode:
		if Station.debug_on("loadtime"):        # which stretch of the build ran without a break for long: UG_ON=loadtime lists every stretch over 60 ms with the line that ended it
			var now := Time.get_ticks_usec()
			if _chunk_us != 0 and now - _chunk_us > 60000:
				var stk := get_stack()
				var at: Dictionary = stk[2] if stk.size() > 2 and stk[1]["function"] == "_slice" else (stk[1] if stk.size() > 1 else {"function": "?", "line": 0})
				print("LOAD     chunk %4d ms ends at %s:%d" % [(now - _chunk_us) / 1000, at["function"], at["line"]])
		await get_tree().process_frame
		_chunk_us = Time.get_ticks_usec()


## Frame break inside a loop of small items: only when the stretch since the last break has used up its time slice
func _slice() -> void:
	if async_mode and Time.get_ticks_usec() - _chunk_us > SLICE_US:
		await _yield()


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
		await _slice()
	_t0 = _t("rooms", _t0)
	for e in plan.escs:
		if e.get("removed", false):
			await _slice()
			continue          # (a lift-only station: its lifts stand where this escalator would be)
		var esc := Escalator.new()
		esc.build(e["rise"], e["lanes"], "tile_white", e.get("stairs", false))
		esc.position = e["pos"]
		esc.rotation.y = e["yaw"]
		esc.name = e["id"]
		add_child(esc)
		escalators.append(esc)
		if not e.get("stairs", false):
			Sfx.loop_at("escalator_loop", esc, Vector3(esc.length * 0.5, -esc.rise * 0.5 + 1.5, 0), -4.0, 26.0)
		await _slice()
	_t0 = _t("escalators", _t0)
	for mi in plan.modules.size():
		var m: Dictionary = plan.modules[mi]
		var pm := PlatformModule.new()
		pm.position = m["pos"]
		pm.name = "Module%d" % mi
		add_child(pm)
		# open-air platforms: which sides have another module close by (their backdrop would cut through it)
		var nb: Array = []
		for oi in plan.modules.size():
			if oi == mi:
				continue
			var om: Dictionary = plan.modules[oi]
			var d: Vector3 = (om["pos"] as Vector3) - (m["pos"] as Vector3)
			if absf(d.z) < 46.0 and absf(d.x) < float(m["spec"]["length"]):
				nb.append(1.0 if d.z > 0.0 else -1.0)
		(m["spec"] as Dictionary)["nb"] = nb
		(m["spec"] as Dictionary)["bend"] = m.get("bend", {})
		(m["spec"] as Dictionary)["ext"] = m.get("ext", [])
		await pm.build(m["spec"], async_mode)
		modules.append(pm)
		stats["tris"] += pm.meta.get("tri_count", 0)
		has_bend = has_bend or pm.bend != null
		await _slice()
	fitting_root = Node3D.new()
	fitting_root.name = "Fittings"
	add_child(fitting_root)
	_t0 = _t("modules", _t0)
	_build_lifts()
	_build_spirals()
	await _slice()
	_build_gateline()
	await _slice()
	_build_street_doors()
	await _slice()
	_t0 = _t("gates+doors", _t0)
	if not Station.debug_off("occlusion"):
		StationOcclusion.build(self)
	await _slice()
	await StationSigns.place(self)
	_t0 = _t("signs", _t0)
	if not Station.debug_off("dressing"):
		await StationDressing.place(self)
	_t0 = _t("props", _t0)
	for pm: PlatformModule in modules:
		pm.bend_children()                       # (curved platforms: the dressing and the signs were placed straight, now they follow the curve)
	if DECALS and not Station.debug_off("decals"):
		StationDecals.place(self)
	_t0 = _t("decals", _t0)
	await _slice()
	trains = TrainService.new()
	trains.name = "Trains"
	add_child(trains)
	for k in spaces:
		stats["tris"] += (spaces[k] as Space).kit.triangle_count()
		stats["lights"] += (spaces[k] as Space).light_points.size()


# ---------------------------------------------------------------------------------------------------
# Lifts and bank barriers (step-free journeys only: StationPlan.step_free_mode)
# ---------------------------------------------------------------------------------------------------
var lift_doors: Array = []         # Node3D anchors in front of each lift door (group "lift_door"): meta lift, end, to (the other door's anchor position), time, out (the direction out of the door)


## lifts are built where the station has them in reality (the TfL facility record) and for step-free journeys at every station; the closed escalators only on step-free journeys
func has_lifts() -> bool:
	return plan != null and not plan.lifts.is_empty() and (StationPlan.step_free_mode or plan.lift_only or (StationPlan.lifts_enabled and plan.lifts_real))


func _build_lifts() -> void:
	if not has_lifts():
		return
	for lf in plan.lifts:
		var li: int = lf["esc"]
		for end in ["top", "bot"]:
			var d: Dictionary = lf[end]
			var other: Dictionary = lf["bot" if end == "top" else "top"]
			# the housings of this end: one, or a pair side by side (every one has a door the player can use; the graph's node is in front of the middle of the pair)
			var houses: Array = [{"pos": d["pos"], "front": d.get("front_a", d["front"]), "yaw": d["yaw"]}]
			houses.append_array(d.get("extra", []))
			for hi in houses.size():
				var hs: Dictionary = houses[hi]
				var car := PropKit.lift_housing()
				car.name = "Lift%d_%s_%d" % [li, end, hi]
				fitting_root.add_child(car)
				car.position = hs["pos"]
				car.rotation.y = hs["yaw"]
				var door := Node3D.new()
				door.name = "LiftDoor%d_%s_%d" % [li, end, hi]
				fitting_root.add_child(door)
				door.position = hs["front"]
				door.set_meta("lift", li)
				door.set_meta("end", end)
				door.set_meta("to", other["front"])
				door.set_meta("time", lf["time"])
				door.set_meta("out", Basis(Vector3.UP, float(d["yaw"])) * Vector3(0, 0, -1))
				door.set_meta("to_out", Basis(Vector3.UP, float(other["yaw"])) * Vector3(0, 0, -1))
				door.add_to_group("lift_door")
				lift_doors.append(door)
	if not StationPlan.step_free_mode:
		return
	# step-free journeys: the escalators and stairs are closed to the player, a barrier across each mouth
	for ei in plan.escs.size():
		var e: Dictionary = plan.escs[ei]
		if plan.lift_of(ei).is_empty() or e.get("removed", false):
			continue
		for top in [true, false]:
			var b := PropKit.bank_barrier(float(e["width"]), bool(e.get("stairs", false)))
			b.name = "Barrier%d_%s" % [ei, "top" if top else "bot"]
			fitting_root.add_child(b)
			b.position = plan.esc_point(ei, Vector3(-0.8, 0.0, 0.0) if top else Vector3(float(e["length"]) + 0.8, -float(e["rise"]), 0.0))
			b.rotation.y = float(e["yaw"]) + (-PI * 0.5 if top else PI * 0.5)      # (the board faces the passenger coming from the room)


# ---------------------------------------------------------------------------------------------------
# Spiral emergency stairs (the stations that have one, in normal play with lifts: StationPlan._add_spirals)
# ---------------------------------------------------------------------------------------------------
var stair_doors: Array = []        # Node3D anchors in front of each door of the stair (group "stair_door"): meta end ("top", "bot" in the rooms; "top_tower", "bot_tower" in the tower), to (where the
								   # other side's anchor is), to_dir (the way the player faces coming out), steps, rise
var towers: Array = []             # the SpiralStair nodes


func has_spirals() -> bool:
	return plan != null and not plan.spirals.is_empty() and StationPlan.lifts_enabled and plan.lifts_real and not StationPlan.step_free_mode


func _build_spirals() -> void:
	if not has_spirals():
		return
	for sp in plan.spirals:
		var tower := SpiralStair.new().configure(int(sp["steps"]), float(sp["rise"]))
		tower.name = "SpiralStair"
		add_child(tower)
		tower.position = sp["tower"]
		tower.build()
		towers.append(tower)
		var ends := [
			["top", sp["top"], sp["tin"], sp["tin_dir"], 0.0],
			["bot", sp["bot"], sp["tout"], sp["tout_dir"], 0.0],
		]
		for e in ends:
			var end: String = e[0]
			var d: Dictionary = e[1]
			var door := PropKit.stair_door()
			door.name = "StairDoor_%s" % end
			fitting_root.add_child(door)
			door.position = d["pos"]
			door.rotation.y = d["yaw"]
			var a := _stair_anchor("StairAnchor_%s" % end, d["front"], end, sp)
			a.set_meta("to", e[2])
			a.set_meta("to_dir", e[3])
			# the tower's side: arrive at the same landing the door leads to
			var b := _stair_anchor("StairAnchor_%s_tower" % end, e[2], end + "_tower", sp)
			b.set_meta("to", d["front"])
			b.set_meta("to_dir", d["out"])


## the spiral stair's tower a world point is inside, or null
func tower_at(world_pos: Vector3) -> SpiralStair:
	for t in towers:
		if (t as SpiralStair).contains(world_pos):
			return t
	return null


func _stair_anchor(nm: String, pos: Vector3, end: String, sp: Dictionary) -> Node3D:
	var a := Node3D.new()
	a.name = nm
	fitting_root.add_child(a)
	a.position = pos
	a.set_meta("end", end)
	a.set_meta("steps", int(sp["steps"]))
	a.set_meta("known", bool(sp.get("known", false)))
	a.set_meta("rise", float(sp["rise"]))
	a.add_to_group("stair_door")
	stair_doors.append(a)
	return a


# ---------------------------------------------------------------------------------------------------
# Gateline (Blender gate units)
# ---------------------------------------------------------------------------------------------------
func _build_gateline() -> void:
	var lines: Array = plan.gatelines if not plan.gatelines.is_empty() else [plan.gates]
	var instanced: Array = []          # gate units and fence sections whose static body is drawn as an instanced mesh
	var fence_body := StaticBody3D.new()
	fence_body.name = "GateFence"
	fitting_root.add_child(fence_body)
	for g: Dictionary in lines:
		var z: float = g["z"]
		var rect: Array = g.get("rect", plan.hall["rect"])
		var total_w: float = g["total_w"]
		var cx: float = g.get("cx", 0.0)
		for ld in g["lanes"]:
			var lane := _make_gate(ld, z)
			gate_nodes.append(lane)
			fitting_root.add_child(lane["node"])
			instanced.append(lane["node"])
		# fixed barriers from the ends of the lane block to the hall walls
		for side: float in [-1.0, 1.0]:
			var edge: float = cx + side * total_w * 0.5
			var wall: float = float(rect[1]) if side > 0.0 else float(rect[0])
			var span: float = absf(wall - edge)
			var x: float = edge
			while span > 0.05:
				var seg: float = minf(2.0, span)
				var f := StationProps.inst("gate_fence")
				fitting_root.add_child(f)
				instanced.append(f)
				f.position = Vector3(x + side * seg * 0.5, 0, z)
				if seg < 2.0:
					f.scale.x = seg / 2.0
				x += side * seg
				span -= seg
			var side_l := CollisionShape3D.new()
			var side_sh := BoxShape3D.new()
			side_sh.size = Vector3(maxf(span_len(edge, wall), 0.1), 1.6, 0.2)
			side_l.shape = side_sh
			side_l.position = Vector3((edge + wall) * 0.5, 0.8, z)
			fence_body.add_child(side_l)
	_instance_bodies(instanced)


## The bodies of a gateline's gate units (13 surfaces each) and fence sections are identical meshes: one MultiMesh per distinct mesh draws them all
## (one draw per surface for the whole line instead of one per gate). Flaps, lamps and colliders stay as they are: they move or collide.
func _instance_bodies(nodes: Array) -> void:
	var groups: Dictionary = {}
	var bodies: Array = []
	for n in nodes:
		var node := n as Node3D
		var body := node.get_node_or_null("body") as MeshInstance3D
		if body == null or body.mesh == null or body.get_child_count() > 0:
			continue
		if not groups.has(body.mesh):
			groups[body.mesh] = []
		groups[body.mesh].append(node.transform * body.transform)
		bodies.append(body)
	for mesh in groups:
		var xfs: Array = groups[mesh]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "GateBodies"
		mmi.multimesh = mm
		fitting_root.add_child(mmi)
	for b in bodies:
		b.get_parent().remove_child(b)
		b.queue_free()


static func span_len(a: float, b: float) -> float:
	return absf(b - a)


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
		glass.material_override = _street_material(plan.kind != "deep" or int(Net.stations[plan.idx]["zone"]) >= 4)
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


## what is seen through the glass doors: a London street, by the time of day (tools/gen_street.py), a little over-exposed as it is from indoors
static func _street_material(suburban := false) -> StandardMaterial3D:
	var hh := fmod(Clock.now / 3600.0, 24.0)
	var mode := "night"
	var gain := 1.0
	if hh >= 7.5 and hh < 17.5:
		mode = "day"
		gain = 1.3
	elif (hh >= 5.5 and hh < 7.5) or (hh >= 17.5 and hh < 20.0):
		mode = "dusk"
		gain = 1.15
	var gm := StandardMaterial3D.new()
	var path := "res://assets/textures/char/street_%s%s.png" % ["sub_" if suburban else "", mode]
	if ResourceLoader.exists(path):
		gm.albedo_texture = load(path)
	else:
		gm.albedo_color = Color(0.85, 0.92, 1.0)
	gm.albedo_color = Color(gain, gain, gain)
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return gm


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
	return to_phys(platform_point_design(face_key, frac, inset))


## the same in design space (every platform straight): what the plan, the walking graph and the placement maps use
func platform_point_design(face_key: String, frac: float, inset := 0.9) -> Vector3:
	var f: Dictionary = plan.faces[face_key]
	var x: float = lerpf(f["x0"] + 4.0, f["x1"] - 4.0, frac)
	var side: float = f["side"]
	return Vector3(x, f["y"], f["edge_z"] - side * inset)


# ---------------------------------------------------------------------------------------------------
# Curved platforms. The plan, the walking graph and the crowd live in "design space", where every module is straight; a curved module (PlatformCurve) is wrapped round an arc in the
# world. to_phys / to_design convert a station-local point between the two (identity everywhere except in a bent module's reach).
# ---------------------------------------------------------------------------------------------------
func bent_modules() -> Array:
	var out: Array = []
	for pm in modules:
		if (pm as PlatformModule).bend != null:
			out.append(pm)
	return out


## which bent module's reach holds the design-space point p (station-local), or null: past the start of its arc, within the tunnel, around the track pair and the levels it spans
func _bent_module_at(p: Vector3) -> PlatformModule:
	for pm: PlatformModule in modules:
		if pm.bend == null:
			continue
		var lp := p - pm.position
		if lp.x >= pm.bend.x0 and lp.x <= pm.bend.x1 + PlatformModule.TUNNEL_EXT and absf(lp.z) < 11.0 and lp.y > -3.0 and lp.y < 9.0:
			return pm
	return null


func to_phys(p: Vector3) -> Vector3:
	if not has_bend:
		return p
	var pm := _bent_module_at(p)
	if pm == null:
		return p
	return pm.position + pm.bend.map(p - pm.position)


## the heading (radians about +y) a thing that faces along the platform has in the world where design space says it faces along +x
func phys_yaw(p: Vector3) -> float:
	if not has_bend:
		return 0.0
	var pm := _bent_module_at(p)
	if pm == null:
		return 0.0
	return pm.bend.theta((p - pm.position).x)


func to_design(q: Vector3) -> Vector3:
	if not has_bend:
		return q
	for pm: PlatformModule in modules:
		if pm.bend == null:
			continue
		var lq := q - pm.position
		if lq.y < -3.0 or lq.y > 9.0:
			continue
		var d := pm.bend.unmap(lq)
		if d.x >= pm.bend.x0 and d.x <= pm.bend.x1 + PlatformModule.TUNNEL_EXT and absf(d.z) < 11.0:
			return pm.position + d
	return q
