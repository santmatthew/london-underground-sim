extends Node
## A player STANDING in a car of a train (not seated: the bots do this) stays on its floor for the whole ride, whichever car and wherever in it - the ends of the car and of the train included.
## The default is the rear car at Leyton, where the next train is due 12 s after this one leaves and arrives at the platform through its rear cars (the timetable's headways are that short): the other trains of the
## station are held non-solid while it slides away (Ride, Train.set_solid), or the player was shoved out of the train. args --station=Leyton --pid=central:Eastbound --car=7 --dx=-6.5 (metres along the car from its middle) --dz=0.0 --hour=9.5 --hops=1
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	var nm := "Leyton"
	var want := "central:Eastbound"
	var car_i := 7
	var dx := -6.5
	var dz := 0.0
	var hour := "9.5"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): nm = a.substr(10)
		if a.begins_with("--pid="): want = a.substr(6)
		if a.begins_with("--car="): car_i = int(a.substr(6))
		if a.begins_with("--dx="): dx = float(a.substr(5))
		if a.begins_with("--dz="): dz = float(a.substr(5))
		if a.begins_with("--hour="): hour = a.substr(7)
	Settings.set_v("access", "step_free", false, false)
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {"seed": "5", "explore": nm, "spot": "platform", "hour": hour}
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
		if String(k).begins_with(want) and fk == "":
			fk = k
	check(fk != "", "a face %s" % want)
	var f: Dictionary = plan.faces[fk]
	var gp: int = Timetable.plat_index[plan.idx][f["pid"]]
	var v0: Dictionary = {}
	for vv in Timetable.visits_between(gp, Clock.now, Clock.now + 1800.0):
		if (Timetable.run_face[vv["run"]] as PackedByteArray)[vv["k"]] == f["face_no"] and not vv["final"] and vv["dep"] - vv["arr"] > 20.0:
			v0 = vv
			break
	check(not v0.is_empty(), "a train that goes on calls")
	if v0.is_empty():
		print("FAILED")
		return
	Clock.set_time(v0["arr"] + 6.0)
	g.station.trains._process(0.6)
	g.station.trains._process(0.1)
	var train: Train = g.station.trains.visits["%d:%d" % [v0["run"], v0["k"]]]["train"]
	var car := train.cars[mini(car_i, train.cars.size() - 1)] as Node3D
	g.player.cancel_sit()
	g.player.global_position = car.to_global(Vector3(dx, 0.92, dz))
	g.player.velocity = Vector3.ZERO
	for i in 40:
		await get_tree().process_frame
	var lp0 := car.to_local(g.player.global_position)
	check(lp0.y > 0.8 and lp0.y < 1.0, "the player stands on the floor of car %d (%.2f above its rail)" % [car_i, lp0.y])
	var t_real := 0.0
	var was_riding := false
	var worst_dy := 0.0
	var bad := 0
	var first_bad := ""
	var phase := -1
	while t_real < 300.0:
		await get_tree().process_frame
		t_real += get_process_delta_time()
		Clock.time_scale = 1.0
		if g.riding and g.ride != null:
			was_riding = true
			var r: Ride = g.ride
			if r.phase != phase:
				phase = r.phase
				print("  info: phase %d at %.1f s, %.0f m" % [phase, Clock.now - r.t_dep, r.s_now])
			# the player's own car (the one that stays put) - or whichever car holds him now
			var ci := train.car_containing(g.player.global_position)
			var lp := (train.cars[ci] as Node3D).to_local(g.player.global_position)
			var dy := lp.y - 0.88
			worst_dy = minf(worst_dy, dy)
			if dy < -0.15 or dy > 0.35 or absf(lp.x) > 9.0 or absf(lp.z) > 1.6:
				bad += 1
				if first_bad == "":
					first_bad = "phase %d at %.1f s, %.0f m: car %d local %s (ref car %d)" % [phase, Clock.now - r.t_dep, r.s_now, ci, str(lp.snapped(Vector3(0.01, 0.01, 0.01))), r.ref_car]
				if bad > 5:
					break
			if g.ride.phase >= 2 and Clock.now - r.t_dep > 40.0:
				break
		elif was_riding and not g.riding:
			break
	check(was_riding, "the ride happened")
	check(bad == 0, "the player stayed on the car floor for the whole ride (%d frames off it, first: %s)" % [bad, first_bad])
	print("  info: lowest the player went relative to the floor: %.2f m" % worst_dy)
	print("OK" if ok else "FAILED")
