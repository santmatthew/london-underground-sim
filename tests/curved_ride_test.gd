extends Node
## A ride that leaves a curved platform and arrives at another (Bank, Central line, towards Liverpool Street; real geometry): the cars follow the arc as the train sets off, the track bends on, the
## destination is entered along its own curve and the train stops with no jump. args --station=Bank --pid=central:Eastbound
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	var nm := "Bank"
	var want := "central:Eastbound"
	var shots := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): nm = a.substr(10)
		if a.begins_with("--pid="): want = a.substr(6)
		if a == "--shots": shots = true            # (needs a window: tools/shot.sh res://tests/runner.tscn -- --test=curved_ride_test --shots)
	Settings.set_v("access", "step_free", false, false)
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {"seed": "5", "explore": nm, "spot": "platform", "hour": "8"}
	add_child(g)
	var t0 := Time.get_ticks_msec()
	while g.state != Game.State.PLAYING and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	check(g.state == Game.State.PLAYING, "the session starts")
	for i in 10:
		await get_tree().process_frame
	var plan := g.station.plan
	var fk := ""
	for k in plan.faces:
		if String(k).begins_with(want):
			fk = k
	var f: Dictionary = plan.faces[fk]
	var pm: PlatformModule = g.station.modules[f["module"]]
	check(pm.bend != null, "the origin platform is curved")
	var gp: int = Timetable.plat_index[plan.idx][f["pid"]]
	var v0: Dictionary = {}
	for vv in Timetable.visits_between(gp, Clock.now, Clock.now + 1200.0):
		if (Timetable.run_face[vv["run"]] as PackedByteArray)[vv["k"]] == f["face_no"] and not vv["final"] and not vv["origin"] and vv["dep"] - vv["arr"] > 20.0:
			v0 = vv
			break
	check(not v0.is_empty(), "a through train calls")
	if v0.is_empty():
		print("FAILED")
		return
	Clock.set_time(v0["arr"] + 6.0)
	g.station.trains._process(0.6)
	g.station.trains._process(0.1)
	var vkey := "%d:%d" % [v0["run"], v0["k"]]
	var train: Train = g.station.trains.visits[vkey]["train"]
	var stand := train.cars[3].get_node_or_null("stand_00") as Node3D
	g.player.global_position = stand.global_position + Vector3(0, 0.15, 0)
	g.player.velocity = Vector3.ZERO
	if shots:
		# look out of the platform-side window
		var local_side := train.platform_side * (1.0 if train.facing > 0 else -1.0)
		g.player.face((train.global_transform.basis * Vector3(0.0, 0.0, local_side)).normalized())
	var t_real := 0.0
	var turned := 0.0
	var was_riding := false
	var finish_err := Vector2(-1, -1)
	var min_floor := 99.0
	var worst_axis := 0.0
	var bent_dest := false
	var taken := {}
	while t_real < 300.0:
		await get_tree().process_frame
		t_real += get_process_delta_time()
		Clock.time_scale = 4.0
		if g.riding and g.ride != null:
			was_riding = true
			var r: Ride = g.ride
			turned = maxf(turned, absf(r.path.theta(r.dist - 100.0)))
			min_floor = minf(min_floor, g.player.global_position.y - train.global_position.y)
			finish_err = r.finish_error
			# the player's car and its neighbours stay a car length apart, whatever the bends
			var d01 := (train.cars[3] as Node3D).global_position.distance_to((train.cars[4] as Node3D).global_position)
			worst_axis = maxf(worst_axis, absf(d01 - 16.7))
			if shots:
				var tau := Clock.now - r.t_dep
				for m in [4, 9, 16, 30, 50]:
					if tau > m and not taken.has(m):
						taken[m] = true
						if m >= 16:
							g.player.face((train.global_transform.basis * Vector3(1.0, 0.0, 0.0)).normalized())            # (then along the train, to see the bores bend)
						get_viewport().get_texture().get_image().save_png("res://build/curved_ride_%d.png" % m)
		elif was_riding and not g.riding:
			break
	check(was_riding, "the ride happened")
	check(not g.riding and g.station != null and g.station.plan.idx != plan.idx, "arrived at %s" % (g.station.plan.name if g.station else "?"))
	check(min_floor > 0.2, "the player stayed on the floor (%.2f)" % min_floor)
	check(finish_err.x >= 0.0 and finish_err.x < 0.15 and finish_err.y < 0.01, "no jump when the train stopped (%.3f m, %.4f rad)" % [finish_err.x, finish_err.y])
	check(worst_axis < 1.0, "neighbouring cars stay a car length apart (worst %.2f m off)" % worst_axis)
	if g.station != null:
		print("  info: arrived at %s, destination platform curved: %s, turn on the way %.0f deg" % [g.station.plan.name, str(g.station.has_bend), rad_to_deg(turned)])
	print("OK" if ok else "FAILED")
