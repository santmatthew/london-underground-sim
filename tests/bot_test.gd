extends Node
## Runs the autopilot through a whole journey headless-ish and reports the result. args: --seed=N --time=am_peak --length=short
func run():
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {}
	add_child(g)
	await get_tree().process_frame
	var seed := 1
	var every := 3600
	var max_frames := 60 * 60 * 70        # --frames=N (physics frames); the GTEST timeout is the real limit
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="): seed = int(a.substr(7))
		if a.begins_with("--every="): every = int(a.substr(8))
		if a.begins_with("--frames="): max_frames = int(a.substr(9))
		if a.begins_with("--time="): g.opts["time"] = a.substr(7)
		if a.begins_with("--length="): g.opts["length"] = a.substr(9)
		if a.begins_with("--multi="): g.opts["mode"] = "multi"; g.opts["stops"] = int(a.substr(8))
	g.cli["seed"] = str(seed)
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] in ["start", "dest", "spot", "hour"]: g.cli[kv[0]] = kv[1]
	g.cli["autopilot"] = "1"
	g.start_journey()
	var t := 0.0
	while g.state != Game.State.BRIEFING:
		await get_tree().process_frame
	print("journey: ", Net.station_name(g.journey["start"]), " (", g.journey["spot"]["name"], ") mode ", g.journey["mode"], " targets ", g.journey.get("targets", []).map(func(t): return Net.station_name(t)) if g.journey["mode"] == "multi" else Net.station_name(g.journey["dest"]))
	while g.state != Game.State.PLAYING:
		await get_tree().process_frame
	var frames := 0
	var y_prev: float = g.player.global_position.y
	var drops := 0
	while g.state == Game.State.PLAYING and frames < max_frames:
		await get_tree().physics_frame
		frames += 1
		var y_now: float = g.player.global_position.y
		if y_now < y_prev - 0.25 and drops < 6:
			drops += 1
			var ph := "-"
			if g.ride != null:
				ph = "phase %d t_arr-now %.1f dest_ready %s speed %.1f" % [g.ride.phase, g.ride.t_arr - Clock.now, str(g.ride.dest_ready), g.ride.speed_now]
			print("DROP y %.2f -> %.2f at %s clock %s riding=%s ride[%s] station=%s on_floor=%s mode=%s" % [y_prev, y_now, str(g.player.global_position.snapped(Vector3(0.1, 0.1, 0.1))), Clock.fmt(Clock.now, true), str(g.riding), ph, g.station.plan.name if g.station else "null", str(g.player.is_on_floor()), g.autopilot.mode if g.autopilot else "-"])
			if drops == 1 and g.station != null:
				for key in g.station.trains.visits:
					var vv: Dictionary = g.station.trains.visits[key]
					var tr: Train = vv["train"]
					print("   visit %s train at %s (x_local %.1f) doors %s player-in-train-coords %s ext %s info arr %s dep %s" % [key, str(tr.global_position.snapped(Vector3(0.1, 0.1, 0.1))), tr.position.x, str(vv["doors"]), str(tr.to_local(g.player.global_position).snapped(Vector3(0.1, 0.1, 0.1))), str(g.station.trains.external.has(key)), Clock.fmt(vv["info"]["arr"], true), Clock.fmt(vv["info"]["dep"], true)])
		y_prev = y_now
		if frames % every == 0 and g.autopilot:
			print("  f=%d clock %s mode %s wp %d/%d pos %s local %s mv %s crowd %s" % [frames, Clock.fmt(Clock.now, true), g.autopilot.mode, g.autopilot.wp_i, g.autopilot.wps.size(), str(g.player.global_position), str(g.station.to_local(g.player.global_position).snapped(Vector3(0.1, 0.1, 0.1))) if g.station else "-", str(g.player.bot_move.snapped(Vector2(0.1, 0.1))), str(g.station.crowd.stats) if g.station and g.station.crowd else ""])
	print("state ", g.state, " frames ", frames, " sim end ", Clock.fmt(Clock.now, true))
	if g.autopilot:
		for l in g.autopilot.log_lines: print(l)
