extends Node
## Bot: start a journey, force the player onto the next through-train at the current station, and let the Game ride it.
func run():
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(g)
	g.opts["time"] = "am_peak"
	await get_tree().process_frame
	g.start_journey()
	while g.state != Game.State.BRIEFING:
		await get_tree().process_frame
	g._begin_play()
	var plan := g.station.plan
	# pick the first face with a through train arriving soon
	var found := false
	var v0: Dictionary
	var fk := ""
	for k in plan.faces:
		var f: Dictionary = plan.faces[k]
		var gp: int = Timetable.plat_index[plan.idx][f["pid"]]
		for vv in Timetable.visits_between(gp, Clock.now, Clock.now + 900.0):
			if (Timetable.run_face[vv["run"]] as PackedByteArray)[vv["k"]] == f["face_no"] and not vv["final"] and not vv["origin"] and vv["dep"] - vv["arr"] > 20.0:
				v0 = vv; fk = k; found = true; break
		if found: break
	if not found:
		print("no through train found"); return
	print("bot: boarding ", Timetable.run_name(v0["run"]), " at ", plan.name, " dep ", Clock.fmt(v0["dep"], true))
	Clock.set_time(v0["arr"] + 6.0)
	g.station.trains._process(0.6)
	g.station.trains._process(0.1)
	var vkey := "%d:%d" % [v0["run"], v0["k"]]
	var train: Train = g.station.trains.visits[vkey]["train"]
	var car: Node3D = train.cars[2]
	var stand := car.get_node_or_null("stand_00")
	g.player.global_position = (stand as Node3D).global_position + Vector3(0, 0.15, 0)
	g.player.velocity = Vector3.ZERO
	var t_real := 0.0
	var shots := {}
	var arrived_printed := false
	while t_real < 240.0 and not g.station == null or g.riding:
		await get_tree().process_frame
		t_real += get_process_delta_time()
		Clock.time_scale = 4.0
		if g.riding and g.ride != null:
			var tau := Clock.now - g.ride.t_dep
			for m in [10, 40, 80]:
				if tau > m and not shots.has(m):
					shots[m] = true
					get_viewport().get_texture().get_image().save_png("res://build/shot_gride_%d.png" % m)
					print("t+%d phase %d speed %.1f" % [m, g.ride.phase, g.ride.speed_now])
		if not g.riding and g.station != null and not arrived_printed and g.station.plan.idx != plan.idx:
			arrived_printed = true
			print("arrived at ", g.station.plan.name, " clock ", Clock.fmt(Clock.now, true))
			for i in 60: await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("res://build/shot_gride_arrived.png")
			break
	print("done; riding=", g.riding, " hud where: ", g.hud.where_label.text)
