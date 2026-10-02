extends Node
## Explore mode: starts from the command line (--explore=...) and from the setup screen, no destination, no result panel (street exit, closing time), the pause panel can start somewhere else, the setup
## screen's search and start-spot labels, and a ride to another station keeps the session going.
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func _wait_playing(g: Game, secs := 90.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while g.state != Game.State.PLAYING and Time.get_ticks_msec() - t0 < secs * 1000.0:
		await get_tree().process_frame
	return g.state == Game.State.PLAYING


func run():
	Settings.set_v("access", "step_free", false, false)
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {"seed": "5", "explore": "Kennington", "spot": "platform", "hour": "10"}
	add_child(g)
	var up := await _wait_playing(g)
	check(up, "--explore starts the session without a briefing")
	if not up:
		print("FAILED")
		return
	for i in 10:
		await get_tree().process_frame
	check(g._exploring() and g.journey["mode"] == "explore", "the journey is an explore session")
	check(g.station != null and g.station.plan.name == "Kennington", "at Kennington")
	check(g.player.enabled and not g.paused and g.hud.dest_label.text == "Exploring", "the player can move, the HUD says Exploring (%s)" % g.hud.dest_label.text)
	check(g.hud.elapsed_label.text == "explore mode" and g.hud.where_label.text.contains("platform"), "no elapsed timer; where: %s" % g.hud.where_label.text)
	check(abs(Clock.now - 10.0 * 3600.0) < 120.0, "the clock starts at 10:00 (%s)" % Clock.fmt(Clock.now))
	check(g._hint_text().begins_with("Explore mode"), "the hint says there is no destination")
	# the street exit does not end it
	g._on_street_exit("street0")
	check(g.state == Game.State.PLAYING and g._result == null, "the street exit only turns the player back")
	# closing time does not fail it
	Clock.set_time(Timetable.SERVICE_END + 1500.0)
	for i in 5:
		await get_tree().process_frame
	check(g.state == Game.State.PLAYING and g._result == null, "the end of service does not end the session")
	Clock.set_time(10.0 * 3600.0)
	# the pause panel can start somewhere else
	g._toggle_pause()
	var labels: Array = []
	for c in (g._pause.get_meta("vb") as VBoxContainer).get_children():
		if c is Button:
			labels.append((c as Button).text)
	check(labels.has("Start somewhere else") and labels.has("Main menu") and not labels.has("Give up (main menu)"), "pause panel buttons: %s" % str(labels))
	g._open_explore(g._pause)
	check(g._explore.visible and not g._pause.visible, "the setup screen opens over the pause panel")
	g._explore._search.text = "king"
	g._explore._fill()
	var all_king := g._explore._rows.size() >= 2
	for ri in g._explore._rows:
		if not Net.station_name(ri).to_lower().contains("king"):
			all_king = false
	check(all_king, "searching \"king\" lists %d stations, all containing it" % g._explore._rows.size())
	g._explore._search.text = ""
	g._explore._fill()
	check(g._explore._rows.size() == Net.stations.size(), "no search lists all %d stations" % g._explore._rows.size())
	g._explore.close()
	check(g._pause.visible and not g._explore.visible, "Back brings the pause panel back")
	g._toggle_pause()
	# start somewhere else: another station, another day and time
	g.start_explore({"station": Net.name_to_idx["Hampstead"], "spot": 0, "hour": 18.0, "day": "saturday"})
	await get_tree().process_frame
	check(g.state == Game.State.LOADING, "starting somewhere else loads")
	up = await _wait_playing(g)
	check(up and g.station.plan.name == "Hampstead" and g.journey["day"] == "Saturday" and Clock.weekend, "now at Hampstead on a Saturday")
	check(abs(Clock.now - 18.0 * 3600.0) < 120.0 and not g.paused and g._pause == null, "at 18:00, no pause panel left over (%s)" % Clock.fmt(Clock.now))
	# the start spot labels of every station
	var bad := 0
	var dup := 0
	for idx in Net.stations.size():
		var plan := StationPlan.for_station(idx)
		var seen := {}
		for sp in plan.start_spots:
			var lb := ExplorePanel.spot_label(plan, sp)
			if lb == "" or lb == "Platform":
				bad += 1
			if seen.has(lb):
				dup += 1
			seen[lb] = true
	check(bad == 0, "every start spot of every station has a proper label (%d bad, %d repeated)" % [bad, dup])
	# riding on: through a train to the next station, still exploring
	g.start_explore({"station": Net.name_to_idx["Aldgate East"], "spot": 0, "hour": 7.5, "day": "weekday"})
	await get_tree().process_frame
	up = await _wait_playing(g)
	var plan2 := g.station.plan
	var v0: Dictionary = {}
	var found := false
	for k in plan2.faces:
		var f: Dictionary = plan2.faces[k]
		var gp: int = Timetable.plat_index[plan2.idx][f["pid"]]
		for vv in Timetable.visits_between(gp, Clock.now, Clock.now + 900.0):
			if (Timetable.run_face[vv["run"]] as PackedByteArray)[vv["k"]] == f["face_no"] and not vv["final"] and not vv["origin"] and vv["dep"] - vv["arr"] > 20.0:
				v0 = vv
				found = true
				break
		if found:
			break
	check(found, "a through train comes")
	Clock.set_time(v0["arr"] + 6.0)
	g.station.trains._process(0.6)
	g.station.trains._process(0.1)
	var train: Train = g.station.trains.visits["%d:%d" % [v0["run"], v0["k"]]]["train"]
	var stand := train.cars[2].get_node_or_null("stand_00") as Node3D
	g.player.global_position = stand.global_position + Vector3(0, 0.15, 0)
	g.player.velocity = Vector3.ZERO
	var t_real := 0.0
	var started := false
	var arrived := false
	while t_real < 300.0:
		await get_tree().process_frame
		t_real += get_process_delta_time()
		Clock.time_scale = 4.0
		if g.riding:
			started = true
		if started and not g.riding and g.station != null and g.station.plan.idx != plan2.idx:
			arrived = true
			break
	check(started and arrived, "the train took the player to %s" % (g.station.plan.name if g.station else "?"))
	for i in 30:
		await get_tree().process_frame
	check(g.state == Game.State.PLAYING and g._result == null and g._exploring(), "the session carries on after the ride")
	print("OK" if ok else "FAILED")
