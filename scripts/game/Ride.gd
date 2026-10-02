class_name Ride
extends Node
## Rides the player's train from one stop to the next. The train is static; the world moves.
## Phases: DEPART (origin station slides away) -> TUNNEL (endless tunnel scenery) -> ARRIVE (destination station slides in) -> done.
## The speed profile is solved so distance and time match the timetable exactly.

signal arrived(station: Station, visit_key: String)
signal segment_started(from_stop: int, to_stop: int)

const A_ACC := 1.1
const A_DEC := 1.0

enum Phase { DEPART, TUNNEL, ARRIVE, DONE }

var game: Node3D
var train: Train
var run: int
var k_from: int                     # stop index in the run where the ride starts
var origin: Station
var origin_frame: Transform3D       # module frame of the origin platform (ride frame)
var dest_station: Station
var dest_plan: StationPlan
var dest_ready := false
var tunnel: TunnelRun
var phase := Phase.DEPART
var t_dep := 0.0
var t_arr := 0.0
var dist := 0.0                     # segment length (m)
var v_cruise := 0.0
var t_acc := 0.0
var t_dec := 0.0
var dest_face_key := ""
var dest_vkey := ""
var car_offset := 0.0               # distance of the player's car centre ahead of the train centre (m)
var fwd := Vector3.RIGHT            # train forward in world
var origin_base := Vector3.ZERO
var _handoff_done := false
var rider_state: Dictionary = {}
var _building := false
var sway_t := 0.0
var speed_now := 0.0
var s_now := 0.0


func start(p_game: Node3D, p_train: Train, p_run: int, p_k: int, p_origin: Station, p_player_pos: Vector3) -> void:
	game = p_game
	train = p_train
	run = p_run
	k_from = p_k
	origin = p_origin
	var stops: PackedInt32Array = Timetable.run_stops[run]
	var arr: PackedFloat32Array = Timetable.run_arr[run]
	var dep: PackedFloat32Array = Timetable.run_dep[run]
	t_dep = dep[k_from]
	t_arr = arr[k_from + 1]
	dist = maxf(300.0, Net.dist_km(stops[k_from], stops[k_from + 1]) * 1150.0)
	_solve_profile()
	# reparent the train out of the moving station, keep its world transform
	train.reparent(game, true)
	fwd = train.global_transform.basis.x.normalized()
	car_offset = train.to_local(p_player_pos).x
	origin_base = origin.global_position
	origin_frame = origin.modules[0].global_transform if origin.modules.size() > 0 else Transform3D()
	# find the module that holds the train: the visit's module
	var v: Dictionary = train.get_meta("visit", {})
	if v.has("module"):
		origin_frame = (v["module"] as Node3D).global_transform
	origin.trains.external[v.get("vkey", "")] = true
	_mute(origin)
	segment_started.emit(stops[k_from], stops[k_from + 1])
	# destination station is built in the background while riding
	dest_plan = StationPlan.for_station(stops[k_from + 1])


func _solve_profile() -> void:
	var T := t_arr - t_dep
	var k := 1.0 / (2.0 * A_ACC) + 1.0 / (2.0 * A_DEC)
	var disc := T * T - 4.0 * dist * k
	if disc < 0.0:
		# infeasible: stretch distance so it fits (shouldn't happen with the timetable's own run times)
		dist = T * T / (4.0 * k) * 0.98
		disc = T * T - 4.0 * dist * k
	v_cruise = (T - sqrt(maxf(disc, 0.0))) / (2.0 * k)
	v_cruise = clampf(v_cruise, 6.0, 30.0)
	t_acc = v_cruise / A_ACC
	t_dec = v_cruise / A_DEC
	# rescale distance to exactly fit with clamped speed: recompute cruise length
	var d_acc := 0.5 * A_ACC * t_acc * t_acc
	var d_dec := 0.5 * A_DEC * t_dec * t_dec
	var t_cr := maxf(0.0, T - t_acc - t_dec)
	dist = d_acc + d_dec + v_cruise * t_cr


## distance travelled after tau seconds since departure
func s_at(tau: float) -> float:
	var T := t_arr - t_dep
	if tau <= 0.0:
		return 0.0
	if tau < t_acc:
		return 0.5 * A_ACC * tau * tau
	var d_acc := 0.5 * A_ACC * t_acc * t_acc
	var t_cr := maxf(0.0, T - t_acc - t_dec)
	if tau < t_acc + t_cr:
		return d_acc + v_cruise * (tau - t_acc)
	var u := minf(tau - t_acc - t_cr, t_dec)
	return d_acc + v_cruise * t_cr + v_cruise * u - 0.5 * A_DEC * u * u


func speed_at(tau: float) -> float:
	var T := t_arr - t_dep
	var t_cr := maxf(0.0, T - t_acc - t_dec)
	if tau <= 0.0:
		return 0.0
	if tau < t_acc:
		return A_ACC * tau
	if tau < t_acc + t_cr:
		return v_cruise
	var u := tau - t_acc - t_cr
	return maxf(0.0, v_cruise - A_DEC * u)


func _process(delta: float) -> void:
	if phase == Phase.DONE:
		return
	var now := Clock.now
	var tau := now - t_dep
	var T := t_arr - t_dep
	s_now = s_at(tau)
	speed_now = speed_at(tau)
	var travelled := s_now
	var remaining := maxf(dist - s_now, 0.0)
	# subtle motion of the carriage
	sway_t += delta * (0.4 + speed_now * 0.1)
	match phase:
		Phase.DEPART:
			# origin station slides backwards
			origin.global_position = origin_base - fwd * travelled
			# hand-over when the player's car is well inside the running tunnel
			var L := _origin_module_length()
			var need := L * 0.5 - car_offset + 20.0
			if travelled > need or tau > 40.0:
				_start_tunnel(travelled)
		Phase.TUNNEL:
			if tunnel:
				tunnel.advance(speed_now * delta)
			# start building the destination once well into the ride
			if not _building and tau > minf(16.0, T * 0.35):
				_building = true
				_build_destination()
			# hand over to the destination when the car is inside its running tunnel and it is ready
			if dest_ready:
				var L2 := _dest_length()
				var r_h := L2 * 0.5 + car_offset + 8.0 + 14.0
				if remaining <= r_h + 4.0:
					_start_arrive(remaining)
		Phase.ARRIVE:
			dest_station.global_position = _dest_base() + fwd * remaining
			if remaining <= 0.02 or now >= t_arr + 0.5:
				_finish()


func _origin_module_length() -> float:
	var v: Dictionary = train.get_meta("visit", {})
	if v.has("module"):
		return (v["module"] as PlatformModule).meta.get("length", 120.0)
	return 120.0


func _dest_length() -> float:
	return dest_face_length


var dest_face_length := 120.0


func _start_tunnel(travelled: float) -> void:
	phase = Phase.TUNNEL
	tunnel = TunnelRun.new()
	game.add_child(tunnel)
	tunnel.setup("tile_white")
	tunnel.global_transform = origin_frame
	tunnel.scale.z = (train.get_meta("visit", {}) as Dictionary).get("side", 1.0)
	tunnel.direction = 1.0 if train.facing > 0 else -1.0
	if origin.crowd != null:
		origin.crowd.finish_riders(train)            # riders appear a few per frame; the destination station takes over the complete cars
		rider_state = origin.crowd.train_state.get(train, {})
	# match the fixture phase: origin fixtures sit at x1 + 6 + 12k (module frame)
	tunnel.offset = travelled
	tunnel.advance(0.0)
	origin.visible = false
	origin.process_mode = Node.PROCESS_MODE_DISABLED
	origin.queue_free()
	origin = null


func _build_destination() -> void:
	var stops: PackedInt32Array = Timetable.run_stops[run]
	var gps: PackedInt32Array = Timetable.run_plat[run]
	var faces: PackedByteArray = Timetable.run_face[run]
	var j := k_from + 1
	var pid: String = Timetable.plat_pid[gps[j]]
	dest_face_key = "%s#%d" % [pid, faces[j]]
	dest_vkey = "%d:%d" % [run, j]
	dest_station = Station.new()
	game.add_child(dest_station)
	# Built while the player rides: keep it far from the carriage from the very first frame (its colliders appear while it is built, and
	# a body appearing inside the player's capsule launches the player out of the train)
	dest_station.global_position = Vector3(0.0, -5000.0, 0.0)
	dest_station.visible = false
	await dest_station.build_async(dest_plan)
	# The new station is built at the world origin, which can overlap the moving train. Until it is slid into place it must be far away
	# and inert (colliders, its own service trains and triggers would otherwise hit the player inside the carriage).
	dest_station.global_position = Vector3(0.0, -5000.0, 0.0)
	_mute(dest_station)
	var f: Dictionary = dest_plan.faces[dest_face_key]
	dest_face_length = f["length"]
	# pre-register the visit so the service does not spawn a duplicate train
	dest_station.trains.setup(dest_station, (game as Game).player)
	dest_station.trains.external[dest_vkey] = true
	dest_station.attach_crowd((game as Game).player)
	dest_station.trains.paused = true
	dest_ready = true


func _dest_base() -> Vector3:
	return dest_base_pos


var dest_base_pos := Vector3.ZERO
var _muted: Array = []          # [CollisionObject3D, original layer] of station geometry that must not touch the player while it slides past


## While a station slides past the (static) train, parts of it (a landing or corridor beyond the platform end) can pass straight through the
## carriage and drag the player along. Nothing of the moving station may collide until it has stopped.
func _mute(root: Node) -> void:
	for n in root.find_children("*", "CollisionObject3D", true, false):
		var co := n as CollisionObject3D
		if co.collision_layer != 0:
			_muted.append([co, co.collision_layer])
			co.collision_layer = 0


func _unmute() -> void:
	for pair in _muted:
		if is_instance_valid(pair[0]):
			(pair[0] as CollisionObject3D).collision_layer = pair[1]
	_muted.clear()


func _start_arrive(remaining: float) -> void:
	phase = Phase.ARRIVE
	var f: Dictionary = dest_plan.faces[dest_face_key]
	var module: PlatformModule = dest_station.modules[f["module"]]
	# slot of the train inside the module for this face (canonical arrival direction)
	var canon := 1 if f["face"] == 0 else -1
	var slot := Transform3D(Basis(Vector3.UP, 0.0 if canon > 0 else PI), Vector3(0, PlatformModule.RAIL_Y, f["track_z"] - dest_plan.modules[f["module"]]["pos"].z))
	var mod_local := Transform3D(Basis.IDENTITY, dest_plan.modules[f["module"]]["pos"])
	# the train's world transform (static) must equal dest.global * module_local * slot
	var t_train := train.global_transform
	t_train.basis = t_train.basis.orthonormalized()
	var dest_global := t_train * (mod_local * slot).affine_inverse()
	dest_station.global_transform = dest_global
	dest_base_pos = dest_global.origin
	dest_station.global_position = dest_base_pos + fwd * remaining
	_mute(dest_station)
	dest_station.visible = true
	if tunnel:
		tunnel.queue_free()
		tunnel = null


func _finish() -> void:
	phase = Phase.DONE
	var f: Dictionary = dest_plan.faces[dest_face_key]
	var module: PlatformModule = dest_station.modules[f["module"]]
	dest_station.global_position = dest_base_pos
	_unmute()
	# adopt the train into the destination module at its slot
	var side: float = f["side"]
	train.reparent(module, true)
	var canon := 1 if f["face"] == 0 else -1
	train.position = Vector3(0, PlatformModule.RAIL_Y, side * (PlatformModule.GAP * 0.5 + module.meta["pw"] + PlatformModule.TRACK_TO_EDGE))
	train.rotation = Vector3(0, 0.0 if canon > 0 else PI, 0)
	train.setup_orientation(canon, -side)     # orientation is relative to the destination module, not the origin one
	if dest_station.crowd != null:
		dest_station.crowd.adopt_train(train, rider_state)
	var svc := dest_station.trains
	svc.paused = false
	var stops: PackedInt32Array = Timetable.run_stops[run]
	var info := Timetable.train_info(run, k_from + 1)
	# The train service places a train from the timetable (approaching before `arr`, departing after `dep`). If the ride ended a little
	# early/late, that would teleport the player's train along the track while the player stands still (and falls). Hold it at the platform.
	var now := Clock.now
	if now < float(info["arr"]) or now > float(info["dep"]) - 10.0:
		if now < float(info["arr"]) - 1.5 or now > float(info["dep"]) - 10.0:
			push_warning("Ride ended out of sync with the timetable (now %s, arr %s, dep %s): holding the train at the platform" % [Clock.fmt(now, true), Clock.fmt(float(info["arr"]), true), Clock.fmt(float(info["dep"]), true)])
		info = info.duplicate()
		info["arr"] = minf(float(info["arr"]), now - 4.0)
		info["dep"] = maxf(float(info["dep"]), now + 20.0)
	var v := {"train": train, "key": dest_face_key, "info": info, "dir_arr": canon, "dir_dep": canon, "origin": false, "doors": false, "module": module, "side": side, "vkey": dest_vkey}
	train.set_meta("visit", v)
	svc.visits[dest_vkey] = v
	svc.external.erase(dest_vkey)
	arrived.emit(dest_station, dest_vkey)
