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
var multi := false
var quiet := false
var _shots := 0
var _side_t := 0.0
var _side_dir := 1.0
var _sidesteps := 0
var _wp_sides := 0               # stuck events at the current waypoint: a re-route is due after a few, whatever happened earlier
var _wp_sides_at := -1
var _last_repath_t := -100.0
var _stuck_total := 0.0
var _board_visit: Dictionary = {}
var _dbg_t := -1
var _win_t := 0.0
var _win_pos := Vector3.ZERO
var _route_from := ""
var _repaths := 0
var _unplanned := false         # carried off by a train we did not plan to take: get off at the next stop and replan


func setup(g: Game) -> void:
	game = g
	player = g.player
	player.bot_active = true
	multi = g.journey["mode"] == "multi"
	legs = [] if multi else (g.journey["par"]["legs"] as Array).duplicate(true)
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
	if game.riding and mode in ["init", "walk", "wait_train", "board", "exit"]:
		var planned: bool = mode == "board" and game.ride != null and game.ride.run == target_run
		mode = "in_train"
		wait_t = 0.0
		if planned:
			_log("aboard")
		else:
			# the doors closed with us in the way (a crowd, a sidestep towards the train): ride on, get off at the next stop
			_unplanned = true
			_log("carried off by an unplanned train — will get off at the next stop")
	# multi-stop: the game registers a stop the moment the door trigger fires and puts us back inside the entrance; our exit waypoints
	# are stale then (walking on would hit the trigger again and be pushed back forever)
	if multi and mode == "exit" and game.station != null and game.station.plan.idx in game.journey["visited"]:
		_log("stop registered at %s" % game.station.plan.name)
		mode = "done_wait"
		wait_t = 0.0
		legs = []
		leg_i = 0
	# shoved through the open door of a standing train (a boarding passenger pushed us): step back out before it leaves with us inside
	if mode in ["walk", "exit"]:
		var vin := _open_train_around_us()
		if not vin.is_empty():
			_log("pushed into a standing train - stepping back out")
			_start_alighting(vin, "step_out")
	match mode:
		"init":
			_plan_to_leg_platform()
		"walk":
			if not (_post_walk == "wait_train" and _board_early()):
				_follow(delta)
		"wait_train":
			_wait_train(delta)
		"board":
			player.bot_hurry = true
			# the doors closed (or the train left) before we got in: give up on this train
			if not _board_visit.is_empty() and not _board_visit.get("doors", false) and not (_board_visit["train"] as Train).contains_world_point(player.global_position):
				_abort_boarding()
			else:
				_follow(delta)
		"in_train":
			_in_train(delta)
		"done_wait":
			wait_t += delta
			if multi and wait_t > 2.0 and game.station != null and not (game.station.plan.idx in game.journey["visited"] and game.journey["visited"].size() >= game.journey["targets"].size()):
				mode = "init"
		"alight", "step_out":
			_follow(delta)
		"exit":
			_follow(delta)
	# stuck detection: commanding movement but not actually moving (standing on an escalator does not count)
	if mode in ["walk", "board", "alight", "exit", "step_out"]:
		var real_v := player.get_real_velocity().length()
		var commanded := player.bot_move.length() > 0.5
		var at_target := wp_i < wps.size() and player.global_position.distance_to(wps[wp_i]) < 0.7
		if commanded and real_v < 0.15 and not at_target:
			_stuck_t += delta
		else:
			_stuck_t = 0.0
		# creeping along a wall or corner still counts as stuck: judge net progress over a 2 s window as well
		_win_t += delta
		if _win_t >= 2.0:
			var moved := player.global_position.distance_to(_win_pos)
			_win_t = 0.0
			_win_pos = player.global_position
			if commanded and moved < 0.35 and not at_target and _side_t <= 0.0:
				_stuck_t = maxf(_stuck_t, 0.7)
		if _stuck_t > 0.6 and _side_t <= 0.0:
			_stuck_total += _stuck_t
			var ci := KinematicCollision3D.new()
			var dirv := Vector3(0, 0, -1).rotated(Vector3.UP, player.rotation.y) * 0.3
			var by_person := false
			var rel := Vector3.ZERO
			var blocker := "nothing"
			if player.test_move(player.global_transform, dirv, ci):
				var col := ci.get_collider() as Node
				by_person = col is AnimatableBody3D
				rel = ci.get_position() - player.global_position
				blocker = "%s (%s) at %s" % [col.name, col.get_class(), str(ci.get_position().snapped(Vector3(0.1, 0.1, 0.1)))]
			# step around whatever is in the way (usually a person)
			var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, player.rotation.y)
			var side_sign := -1.0 if fwd.cross(rel).y > 0.0 else 1.0
			_side_dir = side_sign if by_person else (1.0 if _sidesteps % 2 == 0 else -1.0)
			if mode != "board" and _side_enters_train(_side_dir):
				_side_dir = -_side_dir          # never dodge a passenger through an open door of a standing train
			_side_t = 0.9
			_sidesteps += 1
			if wp_i != _wp_sides_at:
				_wp_sides_at = wp_i
				_wp_sides = 0
			_wp_sides += 1
			_stuck_t = 0.0
			if (_wp_sides == 3 or _wp_sides % 8 == 0) and mode in ["walk", "exit"]:
				_repath()
			if _sidesteps % 6 == 0:
				var stn := _station()
				var loc := str(stn.to_local(player.global_position).snapped(Vector3(0.1, 0.1, 0.1))) if stn else "?"
				var tloc := str(stn.to_local(wps[wp_i]).snapped(Vector3(0.1, 0.1, 0.1))) if stn and wp_i < wps.size() else "-"
				_log("stuck near %s (station-local %s) wp %d/%d target-local %s — %d sidesteps, blocked by %s" % [str(player.global_position.snapped(Vector3(0.1, 0.1, 0.1))), loc, wp_i, wps.size(), tloc, _sidesteps, blocker])
			if _sidesteps > 40 and _stuck_total > 60.0:
				_log("giving up this waypoint")
				wp_i = mini(wp_i + 1, wps.size() - 1)
				_stuck_total = 0.0
				_sidesteps = 0
			if DisplayServer.get_name() != "headless" and _shots < 3 and _sidesteps > 3:
				_shots += 1
				get_viewport().get_texture().get_image().save_png("res://build/bot_stuck_%d.png" % _shots)
	_last_pos = player.global_position


# ---------------------------------------------------------------------------------------------------
# Planning helpers
# ---------------------------------------------------------------------------------------------------
func _station() -> Station:
	return game.station


## the plan node we are actually at: nearest one with a clear line of sight (the geometrically nearest can be a face node of the
## neighbouring platform module, on the far side of a wall)
func _nearest_node(st: Station) -> String:
	return _nearest_visible_node(st)


func _nearest_node_raw(st: Station) -> String:
	var lp := st.to_local(player.global_position)
	var best := "hall_unpaid"
	var bd := 1e9
	for n in st.plan.nodes:
		var d: float = (n["pos"] as Vector3).distance_to(lp)
		if d < bd:
			bd = d
			best = n["name"]
	return best


func _route_start(st: Station) -> String:
	return _route_from if _route_from != "" else _nearest_node(st)


## nearest plan node that the player can actually see (no wall in between): after being shoved through a platform opening the
## geometrically nearest node can be on the other side of a wall
func _nearest_visible_node(st: Station) -> String:
	var space := player.get_world_3d().direct_space_state
	var eye := player.global_position + Vector3(0, 1.0, 0)
	var cands: Array = []
	var lp := st.to_local(player.global_position)
	for n in st.plan.nodes:
		cands.append([(n["pos"] as Vector3).distance_to(lp), n["name"], n["pos"]])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for c in cands.slice(0, 24):
		var to: Vector3 = st.to_global((c[2] as Vector3) + Vector3(0, 1.0, 0))
		var across := (to - eye).cross(Vector3.UP).normalized() * 0.35     # the capsule is not a point: test three rays
		var clear := true
		for off in [Vector3.ZERO, across, -across]:
			var q := PhysicsRayQueryParameters3D.create(eye + off, to + off)
			q.collision_mask = 1 | 4        # world walls + the invisible platform-end/edge guards
			if not space.intersect_ray(q).is_empty():
				clear = false
				break
		if clear:
			return c[1]
	return _nearest_node_raw(st)


## rebuild the waypoint list from where we really are (we were pushed off the route and are wedged against something)
func _repath() -> void:
	var st := _station()
	if st == null or _repaths >= 40 or Clock.now - _last_repath_t < 3.0:
		return
	_repaths += 1
	_last_repath_t = Clock.now
	_route_from = _nearest_visible_node(st)
	_log("re-routing from %s" % _route_from)
	if mode == "walk" and _post_walk == "wait_train":
		_plan_to_leg_platform()
	elif mode == "exit":
		_plan_exit()
	_route_from = ""
	_stuck_total = 0.0


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
	if multi and legs.is_empty():
		if st.plan.idx in game.journey["targets"] and not (st.plan.idx in game.journey["visited"]):
			_plan_exit()
			return
		if not _plan_next_target(st):
			return
	if leg_i >= legs.size():
		if multi and not (st.plan.idx in game.journey["targets"] and not (st.plan.idx in game.journey["visited"])):
			legs = []
			_plan_next_target(st)
			return
		_plan_exit()
		return
	var lg: Dictionary = legs[leg_i]
	if st.plan.idx != lg["from"]:
		_log("not at the boarding station (%s vs %s) — replanning" % [st.plan.name, Net.station_name(lg["from"])])
		_replan()
		return
	target_run = lg["run"]
	target_face = _face_key_for_leg(lg)
	var start := _route_start(st)
	var goal := "face:" + target_face
	var names := st.plan.path(start, goal)
	if names.is_empty():
		_log("no path from %s to %s" % [start, goal])
		return
	while names.size() > 1 and String(names[0]).begins_with("street"):
		names.remove_at(0)       # we are just inside the door: never walk back into the exit trigger
	wps = _waypoints_for(st, names)
	# final waypoint: a spot on the platform mid-way (closer to where the train will stop)
	wps.append(st.to_global(st.platform_point(target_face, 0.5, 1.4)))
	wp_i = 0
	mode = "walk"
	_post_walk = "wait_train"
	_log("heading to %s (%s line towards %s, dep %s)" % [target_face, Net.line_name(lg["line"]), Net.station_name(lg["dest"]), Clock.fmt(lg["dep"])])


func _plan_next_target(st: Station) -> bool:
	var remaining: Array = game.journey["targets"].filter(func(t): return not (t in game.journey["visited"]))
	if remaining.is_empty():
		return false
	var target: int = remaining[0]
	var pr: Dictionary = game.par_result
	if pr.get("ok", false):
		for t in pr["order"]:
			if t in remaining:
				target = t
				break
	else:
		# par not ready yet: go to the nearest remaining stop
		var all := Planner.plan_all(st.plan.idx, _nearest_node(st), Clock.now, 2.5 * 3600.0)
		var bt := INF
		for t in remaining:
			if all.get(t, INF) < bt:
				bt = all[t]
				target = t
	var res := Planner.plan(st.plan.idx, _nearest_node(st), Clock.now, target)
	if not res.get("ok", false) or res["legs"].is_empty():
		_log("no route to %s" % Net.station_name(target))
		return false
	legs = res["legs"]
	leg_i = 0
	_log("next stop: %s (%d leg%s)" % [Net.station_name(target), legs.size(), "" if legs.size() == 1 else "s"])
	return true


func _plan_exit() -> void:
	var st := _station()
	if st == null:
		return
	var start := _route_start(st)
	var best: Array = []
	var best_door: Dictionary = st.plan.street_doors[0]
	var best_t := INF
	for sd in st.plan.street_doors:
		var t: float = st.plan.walk_time(start, sd["id"])       # the fastest door (what the planner assumes), not the fewest nodes
		if t < best_t:
			var p: Array = st.plan.path(start, sd["id"])
			if not p.is_empty():
				best_t = t
				best = p
				best_door = sd
	wps = _waypoints_for(st, best)
	wps.append(st.to_global((best_door["pos"] as Vector3) + Vector3(0, 0, -1.5)))
	wp_i = 0
	mode = "exit"
	if OS.get_environment("BOT_DEBUG") != "":
		print("EXIT PLAN from %s: %s" % [start, str(best)])
		var pts := st.plan.walk_points(best, 0)
		for k in pts.size():
			print("   wp %d %s %s esc %s lane %s" % [k, pts[k]["kind"], str((pts[k]["pos"] as Vector3).snapped(Vector3(0.1, 0.1, 0.1))), str(pts[k].get("esc", "-")), str(pts[k].get("lane", "-"))])
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


var _lift_at: Dictionary = {}       # waypoint index -> the lift waypoint (step-free routes): stand at the door, ride, carry on from the other door
var _spiral_at: Dictionary = {}     # waypoint index -> the door of the spiral stair (spiral_mode routes): open it, carry on on the other side


func _waypoints_for(st: Station, names: Array) -> Array:
	var out: Array = []
	_lift_at.clear()
	_spiral_at.clear()
	for wp in st.plan.walk_points(names, 0):
		out.append(st.to_global(wp["pos"]))
		if wp["kind"] == "lift":
			_lift_at[out.size() - 1] = wp
		elif wp["kind"] == "spiral":
			_spiral_at[out.size() - 1] = wp
	return out


func _use_lift(info: Dictionary) -> void:
	var st := _station()
	if st == null:
		return
	var want := "top" if int(info["dir"]) == 1 else "bot"
	for d in st.lift_doors:
		if int(d.get_meta("lift")) == int(info["lift"]) and String(d.get_meta("end")) == want:
			_log("lift %d %s" % [int(info["lift"]), "down" if want == "top" else "up"])
			await game._ride_lift(d)
			wp_i += 1
			return
	_log("no lift door for %s" % str(info))
	wp_i += 1


func _use_spiral(info: Dictionary) -> void:
	var st := _station()
	if st == null:
		return
	for d in st.stair_doors:
		if String(d.get_meta("end")) == String(info["end"]):
			_log("stair door %s" % String(info["end"]))
			await game._use_stair_door(d)
			wp_i += 1
			return
	_log("no stair door for %s" % str(info))
	wp_i += 1


# ---------------------------------------------------------------------------------------------------
# Walking
# ---------------------------------------------------------------------------------------------------
func _follow(delta: float) -> void:
	if wp_i >= wps.size():
		_arrived_at_path_end()
		return
	if game._lift_busy or game._portal_busy:
		player.bot_move = Vector2.ZERO
		_stuck_t = 0.0
		return
	if _lift_at.has(wp_i) and player.global_position.distance_to(wps[wp_i]) < 0.9:
		_use_lift(_lift_at[wp_i])
		return
	if _spiral_at.has(wp_i) and player.global_position.distance_to(wps[wp_i]) < 0.9:
		_use_spiral(_spiral_at[wp_i])
		return
	var target: Vector3 = wps[wp_i]
	var pos := player.global_position
	var flat := Vector3(target.x - pos.x, 0, target.z - pos.z)
	# the last point of a walk is just "somewhere on the platform": someone may be standing on it, so be lenient
	var last := wp_i == wps.size() - 1
	var accept := 0.55
	if last and mode == "walk":
		accept = 1.8
	elif last and (mode == "alight" or mode == "exit"):
		accept = 0.9
	if flat.length() < accept:
		wp_i += 1
		return
	var dir := flat.normalized()
	player.bot_yaw_target = atan2(-dir.x, -dir.z)
	if _side_t > 0.0:
		_side_t -= delta
		player.bot_move = Vector2(_side_dir, -0.7)
		return
	# do not run forward until roughly facing the way
	var yaw_err := absf(angle_difference(player.rotation.y, player.bot_yaw_target))
	player.bot_move = Vector2(0, -1.0 if yaw_err < 0.6 else -0.15)
	player.bot_pitch_target = 0.0
	# hurry when the train is about to leave
	if mode == "walk" and _post_walk == "wait_train" and leg_i < legs.size():
		var lg: Dictionary = legs[leg_i]
		var slack: float = lg["dep"] - Clock.now - _remaining_walk() / Player.WALK_SPEED
		if OS.get_environment("BOT_DEBUG") != "" and int(Clock.now) % 10 == 0 and int(Clock.now) != _dbg_t:
			_dbg_t = int(Clock.now)
			print("HURRY? now %s dep %s remaining %.0f m slack %.0f s" % [Clock.fmt(Clock.now, true), Clock.fmt(lg["dep"], true), _remaining_walk(), slack])
		if lg["dep"] - Clock.now < 30.0 or slack < 20.0:
			player.bot_hurry = true
	if mode == "board" or mode == "alight":
		pass


## metres left along the current waypoint list (flat distance)
func _remaining_walk() -> float:
	var total := 0.0
	var prev := player.global_position
	for i in range(wp_i, wps.size()):
		var w: Vector3 = wps[i]
		total += Vector2(w.x - prev.x, w.z - prev.z).length()
		prev = w
	return total


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
			if _unplanned:
				_unplanned = false
				if multi:
					legs = []
					leg_i = 0
				else:
					_replan()
		"step_out":
			mode = "init"
		"exit":
			_log("reached the exit")
			mode = "done_wait"
			wait_t = 0.0
			if multi:
				legs = []
				leg_i = 0


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


## the visit of a standing train (doors open) that we are inside of, or {}
func _open_train_around_us() -> Dictionary:
	var st := _station()
	if st == null or game.riding:
		return {}
	for key in st.trains.visits:
		var v: Dictionary = st.trains.visits[key]
		var tr: Train = v["train"]
		if v["doors"] and is_instance_valid(tr) and tr.contains_world_point(player.global_position):
			return v
	return {}


## would a sidestep to `side` (+1 = the player's right) end up inside a train?
func _side_enters_train(side: float) -> bool:
	var st := _station()
	if st == null:
		return false
	var probe := player.global_position + player.global_transform.basis.x * side * 1.8 + Vector3(0, 0.9, 0)
	for key in st.trains.visits:
		var tr: Train = (st.trains.visits[key] as Dictionary)["train"]
		if is_instance_valid(tr) and tr.contains_world_point(probe):
			return true
	return false


## the train we are walking to is standing with its doors open and we are nearly there: get on it instead of finishing the walk to the
## "mid-platform" spot first (the platform is often crowded and the doors are about to close)
func _board_early() -> bool:
	var st := _station()
	if st == null or leg_i >= legs.size() or wp_i < wps.size() - 2 or _remaining_walk() > 30.0:
		return false       # only once on the platform proper (the last waypoints), never from a corridor with a wall in between
	var lg: Dictionary = legs[leg_i]
	var vkey := "%d:%d" % [target_run, lg["k"]]
	if not st.trains.visits.has(vkey):
		return false
	var v: Dictionary = st.trains.visits[vkey]
	if not v["doors"]:
		return false
	_log("doors are open - boarding early")
	_start_boarding(v)
	return true


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
	_board_visit = v
	_log("boarding")


func _abort_boarding() -> void:
	_log("missed the doors — replanning")
	_board_visit = {}
	if multi:
		legs = []
		leg_i = 0
		mode = "init"
	else:
		mode = "init"
		_replan()


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
	if OS.get_environment("BOT_DEBUG") != "" and int(Clock.now) % 3 == 0 and int(Clock.now) != _dbg_t and leg_i < legs.size():
		_dbg_t = int(Clock.now)
		for key in st.trains.visits:
			var vv: Dictionary = st.trains.visits[key]
			if int((vv["info"] as Dictionary)["run"]) == int(legs[leg_i]["run"]):
				var tr: Train = vv["train"]
				print("INTRAIN %s %s train-local %s train x %.1f doors %s vel %s" % [Clock.fmt(Clock.now, true), key, str(tr.to_local(player.global_position).snapped(Vector3(0.1, 0.1, 0.1))), tr.position.x, str(vv["doors"]), str(player.velocity.snapped(Vector3(0.1, 0.1, 0.1)))])
	# at a station: alight if it is the leg's destination
	var lg: Dictionary = legs[leg_i] if leg_i < legs.size() else {}
	if wait_t > 2.0 and (_unplanned or (not lg.is_empty() and st.plan.idx == lg["to"])):
		# find the train we are on and its open doors
		for key in st.trains.visits:
			var v: Dictionary = st.trains.visits[key]
			if (v["train"] as Train).contains_world_point(player.global_position) and v["doors"]:
				_start_alighting(v)
				return
	# else: still riding through an intermediate stop (doors open/close) — just wait


func _start_alighting(v: Dictionary, next_mode := "alight") -> void:
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
	mode = next_mode
	if next_mode == "alight":
		_log("alighting at %s" % st.plan.name)
