class_name Autopilot
extends Node
## A bot that plays the game by following the planner's optimal route: walks through the station graph (gates, escalators,
## corridors), waits for the planned train, boards, rides, alights, changes and finally exits. Used for the demo video
## and as an end-to-end test of the whole game loop.

var game: Game
var player: Player
var legs: Array = []
var leg_i := 0
var mode := "init"
var wps: Array = []
var wp_i := 0
var wait_t := 0.0
var target_run := -1
var target_face := ""
var log_lines: Array = []
var _post_walk := ""
var _door_pts: Array = []
var _replans := 0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var done := false
var quiet := false


func setup(g: Game) -> void:
	game = g
	player = g.player
	player.bot_active = true
	legs = (g.journey["par"]["legs"] as Array).duplicate(true)
	leg_i = 0
	mode = "init"


func _log(s: String) -> void:
	log_lines.append("[%s] %s" % [Clock.fmt(Clock.now, true), s])
	if not quiet:
		print("BOT ", log_lines[-1])


func _physics_process(delta: float) -> void:
	if done or game.state != Game.State.PLAYING:
		return
	game.bot_skip = false
	player.bot_hurry = false
	player.bot_move = Vector2.ZERO
	match mode:
		"init":
			_plan_to_leg_platform()
		"walk":
			_follow(delta)
		"wait_train":
			_wait_train(delta)
		"board":
			_follow(delta)
		"in_train":
			_in_train(delta)
		"alight":
			_follow(delta)
		"exit":
			_follow(delta)
	# stuck detection
	if mode in ["walk", "board", "alight", "exit"]:
		if player.global_position.distance_to(_last_pos) < 0.02 * delta * 60.0:
			_stuck_t += delta
		else:
			_stuck_t = 0.0
		_last_pos = player.global_position
		if _stuck_t > 6.0:
			_log("stuck at wp %d/%d (%s) — nudging" % [wp_i, wps.size(), str(player.global_position)])
			_stuck_t = 0.0
			wp_i = mini(wp_i + 1, wps.size() - 1)


# ---------------------------------------------------------------------------------------------------
# Planning helpers
# ---------------------------------------------------------------------------------------------------
func _station() -> Station:
	return game.station


func _nearest_node(st: Station) -> String:
	var lp := st.to_local(player.global_position)
	var best := "hall_unpaid"
	var bd := 1e9
	for n in st.plan.nodes:
		var d: float = (n["pos"] as Vector3).distance_to(lp)
		if d < bd:
			bd = d
			best = n["name"]
	return best


func _face_key_for_leg(lg: Dictionary) -> String:
	var r: int = lg["run"]
	var k: int = lg["k"]
	var gp: int = (Timetable.run_plat[r] as PackedInt32Array)[k]
	var face: int = (Timetable.run_face[r] as PackedByteArray)[k]
	return "%s#%d" % [Timetable.plat_pid[gp], face]


func _plan_to_leg_platform() -> void:
	var st := _station()
	if st == null:
		return
	if leg_i >= legs.size():
		_plan_exit()
		return
	var lg: Dictionary = legs[leg_i]
	if st.plan.idx != lg["from"]:
		_log("not at the boarding station (%s vs %s) — replanning" % [st.plan.name, Net.station_name(lg["from"])])
		_replan()
		return
	target_run = lg["run"]
	target_face = _face_key_for_leg(lg)
	var start := _nearest_node(st)
	var goal := "face:" + target_face
	var names := st.plan.path(start, goal)
	if names.is_empty():
		_log("no path from %s to %s" % [start, goal])
		return
	wps = _waypoints_for(st, names)
	# final waypoint: a spot on the platform mid-way (closer to where the train will stop)
	wps.append(st.platform_point(target_face, 0.5, 1.4))
	wp_i = 0
	mode = "walk"
	_post_walk = "wait_train"
	_log("heading to %s (%s line towards %s, dep %s)" % [target_face, Net.line_name(lg["line"]), Net.station_name(lg["dest"]), Clock.fmt(lg["dep"])])


func _plan_exit() -> void:
	var st := _station()
	if st == null:
		return
	var start := _nearest_node(st)
	var best: Array = []
	for sd in st.plan.street_doors:
		var p := st.plan.path(start, sd["id"])
		if best.is_empty() or (not p.is_empty() and p.size() < best.size()):
			best = p
	wps = _waypoints_for(st, best)
	wps.append(st.to_global(st.plan.street_doors[0]["pos"] + Vector3(0, 0, -1.5)))
	wp_i = 0
	mode = "exit"
	_log("heading for the street exit")


func _replan() -> void:
	_replans += 1
	var st := _station()
	if st == null or _replans > 6:
		return
	var res := Planner.plan(st.plan.idx, _nearest_node(st), Clock.now, game.journey["dest"])
	if res.get("ok", false):
		legs = res["legs"]
		leg_i = 0
		mode = "init"
		_log("replanned: %d leg(s)" % legs.size())


func _waypoints_for(st: Station, names: Array) -> Array:
	var out: Array = []
	for wp in st.plan.walk_points(names, 0):
		out.append(st.to_global(wp["pos"]))
	return out


# ---------------------------------------------------------------------------------------------------
# Walking
# ---------------------------------------------------------------------------------------------------
func _follow(delta: float) -> void:
	if wp_i >= wps.size():
		_arrived_at_path_end()
		return
	var target: Vector3 = wps[wp_i]
	var pos := player.global_position
	var flat := Vector3(target.x - pos.x, 0, target.z - pos.z)
	if flat.length() < 0.55:
		wp_i += 1
		return
	var dir := flat.normalized()
	player.bot_yaw_target = atan2(-dir.x, -dir.z)
	# do not run forward until roughly facing the way
	var yaw_err := absf(angle_difference(player.rotation.y, player.bot_yaw_target))
	player.bot_move = Vector2(0, -1.0 if yaw_err < 0.6 else -0.15)
	player.bot_pitch_target = 0.0
	# hurry when the train is about to leave
	if mode == "walk" and _post_walk == "wait_train" and leg_i < legs.size():
		var lg: Dictionary = legs[leg_i]
		if lg["dep"] - Clock.now < 30.0:
			player.bot_hurry = true
	if mode == "board" or mode == "alight":
		pass


func _arrived_at_path_end() -> void:
	match mode:
		"walk":
			mode = _post_walk
			wait_t = 0.0
		"board":
			mode = "in_train"
			wait_t = 0.0
			_log("aboard")
		"alight":
			_log("on the platform at %s" % game.station.plan.name)
			leg_i += 1
			mode = "init"
		"exit":
			_log("reached the exit")
			mode = "done_wait"


# ---------------------------------------------------------------------------------------------------
# Platform / train
# ---------------------------------------------------------------------------------------------------
func _wait_train(delta: float) -> void:
	var st := _station()
	if st == null:
		return
	var lg: Dictionary = legs[leg_i]
	# look along the platform towards where the train will come from
	var f: Dictionary = st.plan.faces[target_face]
	var from_dir := -1.0 if f["face"] == 0 else 1.0
	var dirv: Vector3 = st.global_transform.basis * Vector3(from_dir, 0, 0.0)
	player.bot_yaw_target = atan2(-dirv.x, -dirv.z)
	player.bot_pitch_target = 0.04
	var vkey := "%d:%d" % [target_run, lg["k"]]
	if st.trains.visits.has(vkey):
		var v: Dictionary = st.trains.visits[vkey]
		if v["doors"]:
			_start_boarding(v)
			return
	# train already gone?
	if Clock.now > lg["dep"] + 8.0 and not st.trains.visits.has(vkey):
		_log("missed the train — replanning")
		_replan()
		return
	# skip time while the train is far away
	if lg["arr"] - Clock.now > 25.0:
		game.bot_skip = true


func _start_boarding(v: Dictionary) -> void:
	var train: Train = v["train"]
	var pos := player.global_position
	var best := Vector3.ZERO
	var bd := 1e9
	var local_side := train.platform_side * (1.0 if train.facing > 0 else -1.0)
	var half_w := 1.31 if train.kind == "deep" else 1.5
	var floor_y := 0.88 if train.kind == "deep" else 1.0
	for dx in train.door_positions():
		var dw := train.to_global(Vector3(dx, floor_y, local_side * (half_w + 0.3)))
		var d := dw.distance_to(pos)
		if d < bd:
			bd = d
			best = Vector3(dx, floor_y, local_side)
	var dx2: float = best.x
	var outside := train.to_global(Vector3(dx2, floor_y, local_side * (half_w + 0.9)))
	var sill := train.to_global(Vector3(dx2, floor_y, local_side * half_w))
	var inside := train.to_global(Vector3(dx2 + 0.6, floor_y, local_side * (half_w - 1.5)))
	var deeper := train.to_global(Vector3(dx2 + 0.6, floor_y, local_side * (half_w - 1.5)))
	wps = [outside, sill, inside]
	wp_i = 0
	mode = "board"
	_log("boarding")


func _in_train(delta: float) -> void:
	wait_t += delta
	# gentle look around
	player.bot_yaw_target = player.rotation.y + sin(Clock.now * 0.3) * 0.02
	player.bot_pitch_target = -0.02
	var st := _station()
	if game.riding:
		# fast-forward through the middle of the ride but watch departure/arrival at normal speed
		var r := game.ride
		if r and r.phase == Ride.Phase.TUNNEL and Clock.now - r.t_dep > 25.0 and r.t_arr - Clock.now > 45.0:
			game.bot_skip = true
		return
	if st == null:
		return
	# at a station: alight if it is the leg's destination
	var lg: Dictionary = legs[leg_i]
	if st.plan.idx == lg["to"] and wait_t > 2.0:
		# find the train we are on and its open doors
		for key in st.trains.visits:
			var v: Dictionary = st.trains.visits[key]
			if (v["train"] as Train).contains_world_point(player.global_position) and v["doors"]:
				_start_alighting(v)
				return
	elif st.plan.idx != lg["to"]:
		# still riding through an intermediate stop (doors open/close) — just wait
		pass


func _start_alighting(v: Dictionary) -> void:
	var train: Train = v["train"]
	var st := _station()
	var pos := player.global_position
	var local_side := train.platform_side * (1.0 if train.facing > 0 else -1.0)
	var half_w := 1.31 if train.kind == "deep" else 1.5
	var floor_y := 0.88 if train.kind == "deep" else 1.0
	var bd := 1e9
	var bdx := 0.0
	for dx in train.door_positions():
		var dw := train.to_global(Vector3(dx, floor_y, local_side * half_w))
		var d := dw.distance_to(pos)
		if d < bd:
			bd = d
			bdx = dx
	var inside := train.to_global(Vector3(bdx, floor_y, local_side * (half_w - 1.0)))
	var sill := train.to_global(Vector3(bdx, floor_y, local_side * half_w))
	var outside := train.to_global(Vector3(bdx, floor_y, local_side * (half_w + 1.4)))
	# then a step further along the platform (away from the doorway)
	var beyond := train.to_global(Vector3(bdx + 1.2, floor_y, local_side * (half_w + 2.0)))
	wps = [inside, sill, outside, beyond]
	wp_i = 0
	mode = "alight"
	_log("alighting at %s" % st.plan.name)
