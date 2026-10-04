extends Node
## A ride seen from a seat, screenshots at chosen moments: the hand-over from the station to the scenery of the ride and from the scenery to the next station (RunScenery, TunnelRun).
## run: SHOT_ENGINE_ARGS="--fixed-fps 60" SHOT_TIMEOUT=400 tools/shot.sh res://tests/runner.tscn -- --test=ride_seam_test --station=Amersham --pid=ss:Westbound --at=2,5,8,11,14,20,40 --arrive=14,10,6,3,1 [--hour=12] [--car=5] [--look=side|opp|ahead]
## output: build/seam_dep_<s>.png, build/seam_arr_<s>.png
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	var nm := "Amersham"
	var want := "ss:Westbound"
	var car_i := 5
	var at: Array = [2.0, 5.0, 8.0, 11.0, 14.0, 20.0, 40.0]
	var arrive: Array = [14.0, 10.0, 6.0, 3.0, 1.0]
	var hour := "12"
	var look := "side"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): nm = a.substr(10)
		if a.begins_with("--pid="): want = a.substr(6)
		if a.begins_with("--car="): car_i = int(a.substr(6))
		if a.begins_with("--hour="): hour = a.substr(7)
		if a.begins_with("--look="): look = a.substr(7)
		if a.begins_with("--at="):
			at = []
			for p in a.substr(5).split(","):
				at.append(float(p))
		if a.begins_with("--arrive="):
			arrive = []
			for p in a.substr(9).split(","):
				arrive.append(float(p))
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
	check(fk != "", "a platform face %s" % want)
	var f: Dictionary = plan.faces[fk]
	var gp: int = Timetable.plat_index[plan.idx][f["pid"]]
	var v0: Dictionary = {}
	var vl: Array = Timetable.visits_between(gp, Clock.now, Clock.now + 1800.0)
	print("  info: face ", fk, " face_no ", f["face_no"], " visits ", vl.size(), " first ", vl[0] if vl.size() > 0 else "-", " run_face ", (Timetable.run_face[vl[0]["run"]] as PackedByteArray)[vl[0]["k"]] if vl.size() > 0 else "-")
	for vv in Timetable.visits_between(gp, Clock.now, Clock.now + 1800.0):
		if (Timetable.run_face[vv["run"]] as PackedByteArray)[vv["k"]] == f["face_no"] and not vv["final"] and not vv["origin"] and vv["dep"] - vv["arr"] > 20.0:
			v0 = vv
			break
	if v0.is_empty():
		for vv in Timetable.visits_between(gp, Clock.now, Clock.now + 1800.0):
			if (Timetable.run_face[vv["run"]] as PackedByteArray)[vv["k"]] == f["face_no"] and not vv["final"]:
				v0 = vv
				break
	check(not v0.is_empty(), "a train that goes on calls")
	if v0.is_empty():
		print("FAILED")
		return
	Clock.set_time(v0["arr"] + 6.0)
	g.station.trains._process(0.6)
	g.station.trains._process(0.1)
	var vkey := "%d:%d" % [v0["run"], v0["k"]]
	var train: Train = g.station.trains.visits[vkey]["train"]
	var seat: Node3D = null
	for sm in train.cars[mini(car_i, train.cars.size() - 1)].find_children("seat_*", "Node3D", true, false):
		seat = sm
		break
	g.player.cancel_sit()
	g.player.global_position = seat.global_position + Vector3(0, 0.1, 0)
	g.player.velocity = Vector3.ZERO
	g.player.sit_on(seat)
	for i in 40:
		await get_tree().process_frame
	var t_real := 0.0
	var was_riding := false
	var taken := {}
	while t_real < 600.0:
		await get_tree().process_frame
		t_real += get_process_delta_time()
		Clock.time_scale = 1.0
		if g.riding and g.ride != null:
			was_riding = true
			var r: Ride = g.ride
			var tau := Clock.now - r.t_dep
			var left := r.t_arr - Clock.now
			var local_side := train.platform_side * (1.0 if train.facing > 0 else -1.0)
			var dirv := (train.global_transform.basis * Vector3(0.0, 0.0, local_side * (-1.0 if look == "opp" else 1.0))).normalized() if look != "ahead" else (train.global_transform.basis * Vector3(float(train.facing), 0.0, 0.0)).normalized()
			for m in at:
				if tau > m and not taken.has("d%s" % m):
					taken["d%s" % m] = true
					g.player.face(dirv)
					await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png("res://build/seam_dep_%d.png" % int(m))
			for m in arrive:
				if left < m and not taken.has("a%s" % m):
					taken["a%s" % m] = true
					g.player.face(dirv)
					await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png("res://build/seam_arr_%d.png" % int(m))
		elif was_riding and not g.riding:
			break
	check(was_riding, "the ride happened")
	print("OK" if ok else "FAILED")
