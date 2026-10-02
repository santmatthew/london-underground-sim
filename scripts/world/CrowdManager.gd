class_name CrowdManager
extends Node3D
## Commuter crowds for one Station. Agents are cheap data records that follow graph routes (station-local space);
## PersonModel nodes + collision capsules only exist for agents near the player.
## Flows: street doors -> gates -> escalators -> corridors -> platform (wait) -> board;  train doors -> platform -> exit / transfer.
## Riders standing/sitting inside trains are created when a train spawns and can alight when its doors open.

const MAX_AWAKE := 100
const WAKE_DIST := 48.0
const SLEEP_DIST := 62.0
const CarUtil = preload("res://assets/models/train/train_car_util.gd")

class Agent:
	var pts: Array = []
	var i := 0
	var pos := Vector3.ZERO
	var yaw := 0.0
	var speed := 1.3
	var cur := 0.0
	var state := "walk"           # walk | gate | esc | wait | board | dead
	var char_idx := 0
	var seed := 0
	var node: PersonModel
	var body: AnimatableBody3D
	var lane := 0.0
	var face_key := ""
	var wait_t := 0.0
	var esc: Dictionary = {}
	var goal := ""
	var hurry := false
	var idle_clip: StringName = &"idle_stand_1"
	var stand_on_right := true
	var bag := false
	var route_done_action := ""     # "wait_platform" | "despawn"
	var door_local := Vector3.ZERO  # boarding target (station-local)

var station: Station
var plan: StationPlan
var player: Player
var agents: Array = []
var train_state: Dictionary = {}  # Train -> {load, visit, cars:{ci:[PersonModel]}}
var rng := RandomNumberGenerator.new()
var lod: CrowdLod
var awake_count := 0
var _spawn_acc := 0.0
var _wake_t := 0.0
var _board_t := 0.0
var _rider_t := 0.0
var enabled := true
var density := 1.0                # global multiplier (settings)
var stats := {"agents": 0, "awake": 0, "riders": 0}


func setup(st: Station, p: Node3D) -> void:
	station = st
	plan = st.plan
	player = p as Player
	rng.seed = plan.seed_value + int(Clock.now)
	lod = CrowdLod.new()
	add_child(lod)
	st.trains.doors_opened.connect(_on_doors_opened)
	st.trains.train_spawned.connect(_on_train_spawned)
	_prefill()


# ---------------------------------------------------------------------------------------------------
# Population targets
# ---------------------------------------------------------------------------------------------------
func _cf() -> float:
	return Clock.crowd_factor(Clock.now)


func _inbound_rate() -> float:
	return 0.16 * plan.imp * (0.08 + _cf()) * density        # people per second entering the station


func _prefill() -> void:
	var cf := _cf()
	# people already in flight: distribute along inbound routes
	var n_flight := int(round(_inbound_rate() * 70.0))
	for k in n_flight:
		var a := _new_inbound()
		if a == null:
			continue
		_advance_random(a, rng.randf())
	# people waiting on platforms
	for fkey in plan.faces:
		var n_wait := int(round(rng.randf_range(0.55, 1.0) * (2.0 + cf * plan.imp * 15.0) * density))
		for k in n_wait:
			_new_waiter(fkey)
	# people walking out (arrived earlier)
	var n_out := int(round(_inbound_rate() * 40.0))
	for k in n_out:
		var fkeys: Array = plan.faces.keys()
		var fk: String = fkeys[rng.randi() % fkeys.size()]
		var a2 := _new_outbound(fk, _face_x(fk) + rng.randf_range(-40.0, 40.0))
		if a2:
			_advance_random(a2, rng.randf())


func _face_x(fk: String) -> float:
	var f: Dictionary = plan.faces[fk]
	return (f["x0"] + f["x1"]) * 0.5


func _advance_random(a: Agent, frac: float) -> void:
	# jump the agent forward along its route by a fraction of the total length
	var total := 0.0
	for k in range(1, a.pts.size()):
		total += (a.pts[k]["pos"] as Vector3).distance_to(a.pts[k - 1]["pos"])
	var d := total * clampf(frac, 0.0, 0.97)
	var k := 1
	while k < a.pts.size():
		var seg := (a.pts[k]["pos"] as Vector3).distance_to(a.pts[k - 1]["pos"])
		if d <= seg or k == a.pts.size() - 1:
			var p0: Vector3 = a.pts[k - 1]["pos"]
			var p1: Vector3 = a.pts[k]["pos"]
			a.pos = p0.lerp(p1, clampf(d / maxf(seg, 0.001), 0.0, 1.0))
			a.i = k
			break
		d -= seg
		k += 1
	# on an escalator segment? put them on it properly
	if a.i > 0 and a.pts[a.i]["kind"] == "esc_out":
		_enter_escalator(a, a.i - 1)
		var e: Dictionary = a.esc
		e["s"] = lerpf(0.0, e["len"], clampf(rng.randf(), 0.0, 1.0)) if e["dir"] > 0 else lerpf(e["len"], 0.0, rng.randf())
	elif a.i < a.pts.size():
		var kind: String = a.pts[a.i]["kind"]
		if kind == "esc_out":
			pass


# ---------------------------------------------------------------------------------------------------
# Agent creation
# ---------------------------------------------------------------------------------------------------
func _mk(char_seed: int) -> Agent:
	var a := Agent.new()
	a.char_idx = rng.randi() % maxi(PersonModel.count(), 1)
	a.seed = char_seed
	a.speed = clampf(rng.randfn(1.32, 0.22), 0.85, 1.9)
	if _cf() > 0.6:
		a.speed *= 1.1
	a.lane = rng.randf_range(-0.55, 0.55)
	a.stand_on_right = rng.randf() < 0.82
	a.idle_clip = [&"idle_stand_1", &"idle_stand_2", &"idle_stand_3", &"idle_phone", &"idle_phone"][rng.randi() % 5]
	a.bag = rng.randf() < 0.3
	agents.append(a)
	return a


func _new_inbound() -> Agent:
	if plan.street_doors.is_empty() or plan.faces.is_empty():
		return null
	var a := _mk(rng.randi())
	var sd: Dictionary = plan.street_doors[rng.randi() % plan.street_doors.size()]
	# choose a platform face weighted toward busier lines
	var fkeys: Array = plan.faces.keys()
	var fk: String = fkeys[rng.randi() % fkeys.size()]
	a.face_key = fk
	var names := plan.path(sd["id"], _open_node(fk))
	if names.is_empty():
		agents.erase(a)
		return null
	a.pts = plan.walk_points(names, rng.randi() % 4)
	var spot := _platform_spot(fk)
	a.pts.append({"pos": spot, "kind": "walk"})
	a.pos = sd["pos"] as Vector3
	a.pts.push_front({"pos": a.pos, "kind": "walk"})
	a.i = 1
	a.route_done_action = "wait_platform"
	return a


func _open_node(fk: String) -> String:
	# nearest platform-entry node of this face (m<i>_open<j>_p<face>)
	var f: Dictionary = plan.faces[fk]
	var mi: int = f["module"]
	var fi: int = f["face"]
	return "m%d_open%d_p%d" % [mi, rng.randi() % 2, fi]


func _platform_spot(fk: String) -> Vector3:
	var f: Dictionary = plan.faces[fk]
	var x: float = lerpf(f["x0"] + 5.0, f["x1"] - 5.0, rng.randf())
	if rng.randf() < 0.5:
		# people cluster near the ways in/out of the platform
		var spec: Dictionary = plan.modules[f["module"]]["spec"]
		var ox: Array = spec["openings_x"]
		var mx: float = plan.modules[f["module"]]["pos"].x
		x = clampf(mx + ox[rng.randi() % ox.size()] + rng.randfn(0.0, 7.0), f["x0"] + 3.0, f["x1"] - 3.0)
	var inset := rng.randf_range(1.15, 2.6)
	return Vector3(x, f["y"], f["edge_z"] - f["side"] * inset)


func _new_waiter(fk: String) -> Agent:
	var a := _mk(rng.randi())
	a.face_key = fk
	a.pos = _platform_spot(fk)
	a.pts = [{"pos": a.pos, "kind": "walk"}]
	a.i = 1
	a.state = "wait"
	a.wait_t = 0.0
	return a


func _new_outbound(fk: String, start_x: float, transfer := false) -> Agent:
	var f: Dictionary = plan.faces[fk]
	var a := _mk(rng.randi())
	var start_pos := Vector3(clampf(start_x, f["x0"] + 2.0, f["x1"] - 2.0), f["y"], f["edge_z"] - f["side"] * rng.randf_range(0.9, 1.6))
	a.pos = start_pos
	var goal_name := ""
	if transfer and plan.faces.size() > 1:
		var fkeys: Array = plan.faces.keys()
		var fk2: String = fkeys[rng.randi() % fkeys.size()]
		if fk2 != fk:
			a.face_key = fk2
			goal_name = _open_node(fk2)
			var names := plan.path(_open_node(fk), goal_name)
			if not names.is_empty():
				a.pts = plan.walk_points(names, rng.randi() % 4)
				a.pts.push_front({"pos": start_pos, "kind": "walk"})
				a.pts.append({"pos": _platform_spot(fk2), "kind": "walk"})
				a.i = 1
				a.route_done_action = "wait_platform"
				return a
	# exit via the nearest street door
	var best: Array = []
	var sid := ""
	for sd in plan.street_doors:
		var names2 := plan.path(_open_node(fk), sd["id"])
		if best.is_empty() or (not names2.is_empty() and names2.size() < best.size()):
			best = names2
			sid = sd["id"]
	if best.is_empty():
		agents.erase(a)
		return null
	a.pts = plan.walk_points(best, rng.randi() % 4)
	a.pts.push_front({"pos": start_pos, "kind": "walk"})
	var sdp: Vector3 = plan.nodes[plan.node_idx[sid]]["pos"]
	a.pts.append({"pos": sdp + Vector3(0, 0, -2.5), "kind": "walk"})
	a.i = 1
	a.route_done_action = "despawn"
	return a


# ---------------------------------------------------------------------------------------------------
# Trains
# ---------------------------------------------------------------------------------------------------
func _train_load(v: Dictionary) -> float:
	var info: Dictionary = v["info"]
	if info["origin"]:
		return 0.03 + rng.randf() * 0.1
	var cf := Clock.crowd_factor(info["arr"])
	var line_bias := 0.5 + 0.5 * absf(sin(float(hash(info["line"]) % 100)))
	return clampf((0.10 + 0.95 * cf) * (0.6 + 0.6 * line_bias) * rng.randf_range(0.7, 1.2), 0.0, 1.0)


func _on_train_spawned(train: Train, v: Dictionary) -> void:
	if not enabled:
		return
	train_state[train] = {"load": clampf(_train_load(v) * density, 0.0, 1.0), "visit": v, "cars": {}}
	train.tree_exiting.connect(func(): train_state.erase(train))


## Riders are created per car, only for cars near the player, and are deterministic per (run, car).
func _rider_pass() -> void:
	if player == null:
		return
	var pp := player.global_position
	for train in train_state.keys():
		if not is_instance_valid(train):
			train_state.erase(train)
			continue
		var st: Dictionary = train_state[train]
		var cars: Dictionary = st["cars"]
		for ci in train.cars.size():
			var car: Node3D = train.cars[ci]
			var d := pp.distance_to(car.global_position)
			if d < 44.0 and not cars.has(ci):
				cars[ci] = _begin_populate(train, ci, st["load"])
			elif d > 72.0 and cars.has(ci):
				for p in cars[ci]:
					if is_instance_valid(p):
						lod.unregister(p)
						p.queue_free()
				cars.erase(ci)


## Riders appear a few per frame (RIDERS_PER_FRAME): filling a whole train at once took 150 ms to 1 s in one frame, the frame-rate experiment's biggest hitches.
## The list that is returned is filled in place; the choices (which seats, which people) are the same as populating the car in one go.
const RIDERS_PER_FRAME := 5
var _pending: Array = []         # cars being filled: {train, ci, arr, markers: [[marker, seated]], i, crng, ld}


func _begin_populate(train: Train, ci: int, ld: float) -> Array:
	var car: Node3D = train.cars[ci]
	var crng := RandomNumberGenerator.new()
	crng.seed = hash("%d/%d" % [train.run, ci])
	var markers: Array = []
	for m in car.find_children("seat_*", "Node3D", true, false):
		markers.append([m, true])
	for m in car.find_children("stand_*", "Node3D", true, false):
		if String((m as Node3D).get_meta("extras", {}).get("kind", "stand")) != "stand_door":
			markers.append([m, false])
	var arr: Array = []
	_pending.append({"train": train, "ci": ci, "arr": arr, "markers": markers, "i": 0, "crng": crng, "ld": ld})
	return arr


func _fill_pending(budget: int, only_train: Train = null) -> void:
	var k := 0
	while k < _pending.size() and budget > 0:
		var e: Dictionary = _pending[k]
		var train = e["train"]
		var alive: bool = is_instance_valid(train) and train_state.has(train) and (train_state[train]["cars"] as Dictionary).has(e["ci"]) \
				and is_same(train_state[train]["cars"][e["ci"]], e["arr"])
		if not alive:
			_pending.remove_at(k)
			continue
		if only_train != null and train != only_train:
			k += 1
			continue
		var car: Node3D = (train as Train).cars[e["ci"]]
		var crng: RandomNumberGenerator = e["crng"]
		var markers: Array = e["markers"]
		while budget > 0 and e["i"] < markers.size():
			var m: Array = markers[e["i"]]
			e["i"] += 1
			var seated: bool = m[1]
			var ld: float = e["ld"]
			if crng.randf() < (ld * 0.9 if seated else ld * ld * 0.8):
				(e["arr"] as Array).append(_place_rider(car, m[0], seated, crng))
				stats["riders"] += 1
				budget -= 1
		if e["i"] >= markers.size():
			_pending.remove_at(k)
		else:
			k += 1


## fill every car of `train` now (before its riders are handed to another station's crowd)
func finish_riders(train: Train) -> void:
	_fill_pending(1 << 20, train)


func _populate_car(train: Train, ci: int, ld: float) -> Array:
	var out: Array = []
	var car: Node3D = train.cars[ci]
	var crng := RandomNumberGenerator.new()
	crng.seed = hash("%d/%d" % [train.run, ci])
	var seats: Array = car.find_children("seat_*", "Node3D", true, false)
	var stands: Array = car.find_children("stand_*", "Node3D", true, false)
	for s in seats:
		if crng.randf() < ld * 0.9:
			out.append(_place_rider(car, s, true, crng))
	for s in stands:
		var kind := String((s as Node3D).get_meta("extras", {}).get("kind", "stand"))
		if kind == "stand_door":
			continue
		if crng.randf() < ld * ld * 0.8:
			out.append(_place_rider(car, s, false, crng))
	stats["riders"] += out.size()
	return out


func _place_rider(car: Node3D, marker: Node3D, seated: bool, crng: RandomNumberGenerator) -> PersonModel:
	var p := PersonModel.create(crng.randi() % maxi(PersonModel.count(), 1), crng.randi())
	car.add_child(p)
	p.transform = car.global_transform.affine_inverse() * marker.global_transform
	p.scale = Vector3.ONE
	if seated:
		marker.set_meta("rider", p)           # Seats.occupied() reads this
		p.position.y -= 0.45
		p.play([&"sit_idle_1", &"sit_idle_2", &"sit_phone"][crng.randi() % 3], 0.0, crng.randf_range(0.9, 1.1))
	else:
		p.position.y = marker.position.y
		var clip: StringName = [&"stand_pole", &"stand_hold", &"idle_stand_1", &"idle_phone", &"stand_pole_l", &"stand_hold_l", &"idle_stand_2"][crng.randi() % 7]
		p.play(clip, 0.0, crng.randf_range(0.9, 1.1))
	lod.register(p)
	p.set_meta("seated", seated)
	return p


## used by the ride hand-over: the destination station's crowd takes over the riders of the player's train
func adopt_train(train: Train, state: Dictionary) -> void:
	if state.is_empty():
		return
	train_state[train] = state
	for ci in state["cars"]:
		for p in state["cars"][ci]:
			if is_instance_valid(p):
				lod.register(p)
	train.tree_exiting.connect(func(): train_state.erase(train))


func _on_doors_opened(v: Dictionary) -> void:
	if not enabled:
		return
	var train: Train = v["train"]
	var fk: String = v["key"]
	if not plan.faces.has(fk):
		return
	var info: Dictionary = v["info"]
	var list: Array = []
	if train_state.has(train):
		for ci in train_state[train]["cars"]:
			for p in train_state[train]["cars"][ci]:
				list.append(p)
	var frac := 1.0 if info["final"] else clampf(0.18 + 0.06 * plan.imp, 0.15, 0.5)
	var doors: Array = train.door_positions()
	var f: Dictionary = plan.faces[fk]
	var n_alight := 0
	var idx: Array = range(list.size())
	idx.shuffle()
	for ii in idx:
		if rng.randf() > frac:
			continue
		var p = list[ii]
		if not is_instance_valid(p):
			continue
		var world_pos: Vector3 = (p as Node3D).global_position
		var best := Vector3.ZERO
		var bd := 1e9
		for dx in doors:
			var dw := train.to_global(Vector3(dx, 0.0, 0.0))
			var d := absf(to_local(dw).x - to_local(world_pos).x)
			if d < bd:
				bd = d
				best = to_local(dw)
		var a := _new_outbound(fk, best.x, rng.randf() < 0.14)
		if a == null:
			continue
		lod.unregister(p)
		(p as Node).queue_free()
		# forget it in the per-car list so it is not counted again
		for ci in train_state[train]["cars"]:
			(train_state[train]["cars"][ci] as Array).erase(p)
		n_alight += 1
	# also people already waiting for this train board it (they vanish into the doors)
	for a in agents:
		if a.state == "wait" and a.face_key == fk:
			if rng.randf() < 0.85:
				a.state = "board"
				var dx := 0.0
				var bd2 := 1e9
				for d in doors:
					var dxw := train.to_global(Vector3(d, 0, 0))
					var dl := to_local(dxw)
					var dist := absf(dl.x - a.pos.x)
					if dist < bd2:
						bd2 = dist
						dx = dl.x
				var side: float = f["side"]
				a.door_local = Vector3(dx, f["y"], f["edge_z"] + side * 0.5)
				a.pts = [{"pos": a.pos, "kind": "walk"}, {"pos": Vector3(dx, f["y"], f["edge_z"] - side * 1.2), "kind": "walk"}, {"pos": a.door_local, "kind": "walk"}]
				a.i = 1
				a.route_done_action = "despawn"
				a.hurry = rng.randf() < 0.3


# ---------------------------------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not enabled or station == null or plan == null:
		return
	# continuous spawns at the street doors
	_spawn_acc += delta * _inbound_rate()
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		var a := _new_inbound()
		if a:
			a.cur = 0.0
	_wake_t -= delta
	if _wake_t <= 0.0:
		_wake_t = 0.25
		_wake_sleep_pass()
	_board_t -= delta
	if _board_t <= 0.0:
		_board_t = 0.6
		_wait_pass()
	_rider_t -= delta
	if _rider_t <= 0.0:
		_rider_t = 0.7
		_rider_pass()
	if not _pending.is_empty():
		_fill_pending(RIDERS_PER_FRAME)
	var dead: Array = []
	var ppos := to_local(player.global_position) if player else Vector3(1e6, 1e6, 1e6)
	for a in agents:
		_step(a, delta, ppos)
		if a.state == "dead":
			dead.append(a)
	for a in dead:
		_free_agent(a)
		agents.erase(a)
	stats["agents"] = agents.size()
	stats["awake"] = awake_count


func _step(a: Agent, delta: float, ppos: Vector3) -> void:
	match a.state:
		"wait":
			a.wait_t += delta
			# stationary; face the track
			return
		"esc":
			_step_escalator(a, delta)
		"walk", "board", "gate":
			_step_walk(a, delta, ppos)
	# sync visuals
	if a.node:
		a.node.position = a.pos
		a.node.rotation.y = a.yaw
	if a.body:
		a.body.position = a.pos + Vector3(0, 0.88, 0)


func _step_walk(a: Agent, delta: float, ppos: Vector3) -> void:
	if a.state == "gate":
		a.wait_t -= delta
		a.cur = 0.0
		if a.wait_t <= 0.0:
			a.state = "walk"
		if a.node:
			a.node.set_locomotion_speed(0.0)
		return
	if a.i >= a.pts.size():
		_finish_route(a)
		return
	var wp: Dictionary = a.pts[a.i]
	var target: Vector3 = wp["pos"]
	var to := Vector3(target.x - a.pos.x, 0, target.z - a.pos.z)
	var dist := to.length()
	if dist < 0.25:
		var kind: String = wp["kind"]
		if kind == "gate":
			a.state = "gate"
			a.wait_t = 0.8
		elif kind == "esc_in":
			_enter_escalator(a, a.i)
			a.i += 1
			return
		a.pos.y = target.y
		a.i += 1
		return
	var dir := to / dist
	# lateral lane offset in wide spaces (not on gates / boarding)
	var lat_target := Vector3(-dir.z, 0, dir.x) * a.lane * 0.5 if a.state == "walk" and a.route_done_action != "despawn" else Vector3.ZERO
	var desired := dir * a.speed * (1.35 if a.hurry else 1.0)
	# slow for the player / others ahead
	var slow := 1.0
	var pl := Vector3(a.pos.x - ppos.x, 0, a.pos.z - ppos.z)
	if absf(a.pos.y - ppos.y) < 2.5 and pl.length() < 1.6:
		var ahead := -pl.normalized().dot(dir)
		if ahead > 0.3:
			slow = clampf(pl.length() / 1.6, 0.15, 1.0)
			desired += Vector3(-dir.z, 0, dir.x) * (0.6 if (a.seed & 1) == 0 else -0.6)
	a.cur = move_toward(a.cur, a.speed * slow * (1.35 if a.hurry else 1.0), 3.0 * delta)
	var step := (desired.normalized() * a.cur + lat_target * 0.2) * delta
	a.pos += step
	a.pos.y = lerpf(a.pos.y, target.y, clampf(delta * 6.0, 0.0, 1.0)) if absf(a.pos.y - target.y) < 0.6 else target.y
	if step.length() > 0.0005:
		a.yaw = lerp_angle(a.yaw, atan2(-step.x, -step.z), clampf(delta * 8.0, 0.0, 1.0))
	if a.node:
		a.node.set_locomotion_speed(a.cur)


## People riding an escalator (or stairs) cannot steer round the player, and a solid body that is carried into a player boxed in by the
## balustrades can only be resolved upwards - onto the rider's head or the rail. So riders are not solid for the player while they ride.
func _set_solid(a: Agent, solid: bool) -> void:
	if a.body:
		a.body.collision_layer = (1 << 1) if solid else 0


func _enter_escalator(a: Agent, idx_in: int) -> void:
	var wp: Dictionary = a.pts[idx_in]
	var e: Dictionary = plan.escs[wp["esc"]]
	var slope: float = float(e["rise"]) / sin(Escalator.ANGLE)
	var total: float = Escalator.PLATE * 2.0 + slope
	a.state = "esc"
	_set_solid(a, false)
	var is_stairs: bool = e.get("stairs", false)
	a.esc = {"idx": wp["esc"], "lane": wp["lane"], "dir": wp["dir"], "len": total, "s": 0.0 if wp["dir"] > 0 else total, "walk": is_stairs or rng.randf() < 0.2, "stairs": is_stairs}
	a.cur = 0.0


func _esc_local(e: Dictionary, li: int, s: float, rise: float, lanes: int) -> Vector3:
	var lz := (li - (lanes - 1) * 0.5) * Escalator.PITCH
	var slope := rise / sin(Escalator.ANGLE)
	var run := rise / tan(Escalator.ANGLE)
	if s <= Escalator.PLATE:
		return Vector3(s, 0.0, lz)
	if s >= Escalator.PLATE + slope:
		return Vector3(Escalator.PLATE + run + (s - Escalator.PLATE - slope), -rise, lz)
	var d := s - Escalator.PLATE
	return Vector3(Escalator.PLATE + d * cos(Escalator.ANGLE), -d * sin(Escalator.ANGLE), lz)


func _step_escalator(a: Agent, delta: float) -> void:
	var info: Dictionary = a.esc
	var e: Dictionary = plan.escs[info["idx"]]
	var spd: float = 1.05 if info.get("stairs", false) else (Escalator.SPEED + (0.9 if info["walk"] else 0.0))
	info["s"] += spd * delta * (1.0 if info["dir"] > 0 else -1.0)
	var lanes: int = (e["lanes"] as Array).size()
	var s: float = info["s"]
	var done: bool = (info["dir"] > 0 and s >= info["len"]) or (info["dir"] < 0 and s <= 0.0)
	var local := _esc_local(e, info["lane"], clampf(s, 0.0, info["len"]), e["rise"], lanes)
	# stand on the right, walk on the left
	var side := 0.24 if not info["walk"] else -0.24
	local.z += side * float(info["dir"]) * (1.0 if a.stand_on_right else -1.0)
	a.pos = plan.esc_point(info["idx"], local)
	var fwd_local := Vector3(float(info["dir"]), 0, 0)
	var fwd_world := Basis(Vector3.UP, e["yaw"]) * fwd_local
	a.yaw = atan2(-fwd_world.x, -fwd_world.z)
	if a.node:
		a.node.position = a.pos
		a.node.rotation.y = a.yaw
	if a.body:
		a.body.position = a.pos + Vector3(0, 0.88, 0)
	if done:
		a.state = "walk"
		_set_solid(a, true)
		a.esc = {}
		# skip to the esc_out waypoint's successor
		while a.i < a.pts.size() and a.pts[a.i]["kind"] != "esc_out":
			a.i += 1
		a.i = mini(a.i + 1, a.pts.size())
		a.cur = Escalator.SPEED
	elif a.node:
		a.node.play(&"escalator_stand" if not info["walk"] else &"walk_normal", 0.3)


func _finish_route(a: Agent) -> void:
	match a.route_done_action:
		"wait_platform":
			a.state = "wait"
			a.wait_t = 0.0
			a.pts = [{"pos": a.pos, "kind": "walk"}]
			a.i = 1
			# face the track: the track lies toward +side (z); a person's forward is -Z rotated by yaw
			var f: Dictionary = plan.faces[a.face_key]
			a.yaw = PI if f["side"] > 0.0 else 0.0
			if a.node:
				a.node.play(a.idle_clip, 0.3)
				a.node.rotation.y = a.yaw
		_:
			a.state = "dead"


func _wait_pass() -> void:
	# people waiting on a platform board any train that has opened its doors on their face (handled in _on_doors_opened),
	# and late arrivals join a train already standing with open doors
	for v in station.trains.visits.values():
		if not v["doors"]:
			continue
		var fk: String = v["key"]
		for a in agents:
			if a.state == "wait" and a.face_key == fk and a.wait_t > 1.5 and rng.randf() < 0.3:
				var train: Train = v["train"]
				if not is_instance_valid(train):
					continue
				var f: Dictionary = plan.faces[fk]
				var doors: Array = train.door_positions()
				var dx := 0.0
				var bd := 1e9
				for d in doors:
					var dl := to_local(train.to_global(Vector3(d, 0, 0)))
					var dist := absf(dl.x - a.pos.x)
					if dist < bd:
						bd = dist
						dx = dl.x
				var side: float = f["side"]
				a.state = "board"
				a.door_local = Vector3(dx, f["y"], f["edge_z"] + side * 0.5)
				a.pts = [{"pos": a.pos, "kind": "walk"}, {"pos": Vector3(dx, f["y"], f["edge_z"] - side * 1.2), "kind": "walk"}, {"pos": a.door_local, "kind": "walk"}]
				a.i = 1
				a.route_done_action = "despawn"


# ---------------------------------------------------------------------------------------------------
# Wake / sleep (model + collision instantiation near the player)
# ---------------------------------------------------------------------------------------------------
func _wake_sleep_pass() -> void:
	if player == null:
		return
	var ppos := to_local(player.global_position)
	awake_count = 0
	for a in agents:
		var d: float = a.pos.distance_to(ppos)
		if a.node != null:
			awake_count += 1
			if d > SLEEP_DIST:
				_sleep(a)
	for a in agents:
		if a.node == null and a.state != "dead":
			var d: float = a.pos.distance_to(ppos)
			if d < WAKE_DIST and awake_count < MAX_AWAKE:
				_wake(a)
				awake_count += 1


func _wake(a: Agent) -> void:
	var p := PersonModel.create(a.char_idx, a.seed)
	add_child(p)
	a.node = p
	p.position = a.pos
	p.rotation.y = a.yaw
	if a.bag:
		p.set_bag(true)
	lod.register(p)
	match a.state:
		"wait":
			p.play(a.idle_clip, 0.0, rng.randf_range(0.9, 1.1))
		"esc":
			p.play(&"escalator_stand", 0.0)
		_:
			p.set_locomotion_speed(a.cur if a.cur > 0.1 else a.speed)
	var b := AnimatableBody3D.new()
	b.collision_layer = 0 if a.state == "esc" else 1 << 1
	b.collision_mask = 0
	b.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var cap := CylinderShape3D.new()      # flat top: the player cannot stand on people's heads
	cap.radius = 0.25
	cap.height = 1.75
	cs.shape = cap
	b.add_child(cs)
	add_child(b)
	b.position = a.pos + Vector3(0, 0.88, 0)
	a.body = b


func _sleep(a: Agent) -> void:
	if a.node:
		lod.unregister(a.node)
		a.node.queue_free()
		a.node = null
	if a.body:
		a.body.queue_free()
		a.body = null


func _free_agent(a: Agent) -> void:
	_sleep(a)


## number of people in a 3 m cone ahead of `world_pos` (used to slow the player in dense crowds)
func density_ahead(world_pos: Vector3, forward: Vector3) -> int:
	var lp := to_local(world_pos)
	var fwd := (global_transform.basis.inverse() * forward)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var n := 0
	for a in agents:
		if a.node == null:
			continue
		var d: Vector3 = a.pos - lp
		if absf(d.y) > 1.5:
			continue
		var dist := Vector2(d.x, d.z).length()
		if dist < 0.3 or dist > 3.2:
			continue
		if Vector3(d.x, 0, d.z).normalized().dot(fwd) > 0.55:
			n += 1
	return n
