extends Node
## A ride on a curved track (UG_CURVE forces R = 1500 / class, here 8, so every ride bends): the player's train sets off, the origin station swings round, the tunnel scenery bends with the track,
## the destination arrives rotated to meet it, and when the train stops the station is where it should be (no jump), the train sits on its platform and the player is still aboard on the floor.
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	OS.set_environment("UG_CURVE", "8")
	Timetable.build(9)
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(g)
	g.opts["time"] = "am_peak"
	await get_tree().process_frame
	g.start_journey()
	while g.state != Game.State.BRIEFING:
		await get_tree().process_frame
	g._begin_play()
	var plan := g.station.plan
	var found := false
	var v0: Dictionary
	for k in plan.faces:
		var f: Dictionary = plan.faces[k]
		var gp: int = Timetable.plat_index[plan.idx][f["pid"]]
		for vv in Timetable.visits_between(gp, Clock.now, Clock.now + 900.0):
			if (Timetable.run_face[vv["run"]] as PackedByteArray)[vv["k"]] == f["face_no"] and not vv["final"] and not vv["origin"] and vv["dep"] - vv["arr"] > 20.0:
				v0 = vv
				found = true
				break
		if found:
			break
	check(found, "a through train is found")
	if not found:
		print("FAILED")
		return
	Clock.set_time(v0["arr"] + 6.0)
	g.station.trains._process(0.6)
	g.station.trains._process(0.1)
	var vkey := "%d:%d" % [v0["run"], v0["k"]]
	var train: Train = g.station.trains.visits[vkey]["train"]
	var stand := train.cars[2].get_node_or_null("stand_00") as Node3D
	g.player.global_position = stand.global_position + Vector3(0, 0.15, 0)
	g.player.velocity = Vector3.ZERO
	var t_real := 0.0
	var seen_curve := false
	var min_floor := 99.0
	var turned := 0.0
	var finish_err := Vector2(-1, -1)
	var was_riding := false
	while t_real < 240.0:
		await get_tree().process_frame
		t_real += get_process_delta_time()
		Clock.time_scale = 4.0
		if g.riding and g.ride != null:
			was_riding = true
			var r: Ride = g.ride
			if r.phase == Ride.Phase.TUNNEL:
				seen_curve = seen_curve or not r.path.is_straight()
				turned = maxf(turned, absf(r.path.theta(r.s_now + r.car_offset)))
			min_floor = minf(min_floor, g.player.global_position.y - train.global_position.y)
			finish_err = r.finish_error
		elif was_riding and not g.riding:
			break
	check(was_riding, "the ride happened")
	check(seen_curve, "the path of the ride bends")
	check(turned > deg_to_rad(8.0), "the track turned %.0f degrees" % rad_to_deg(turned))
	check(not g.riding and g.station != null and g.station.plan.idx != plan.idx, "arrived at another station")
	check(min_floor > 0.2, "the player stayed on the floor of the train (%.2f)" % min_floor)
	if g.station != null:
		var tr: Train = null
		for vk in g.station.trains.visits:
			var vv2: Dictionary = g.station.trains.visits[vk]
			if vv2["train"] == train:
				tr = train
		check(tr != null, "the train is a visit of the destination station")
		if tr != null:
			check(tr.global_position.distance_to(g.player.global_position) < 12.0, "the player is still with the train (%.1f m)" % tr.global_position.distance_to(g.player.global_position))
	check(finish_err.x >= 0.0 and finish_err.x < 0.15 and finish_err.y < 0.01, "no jump when the train stopped (%.3f m, %.4f rad)" % [finish_err.x, finish_err.y])
	print("OK" if ok else "FAILED")
