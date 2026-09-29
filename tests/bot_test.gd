extends Node
## Runs the autopilot through a whole journey headless-ish and reports the result. args: --seed=N --time=am_peak --length=short
func run():
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {}
	add_child(g)
	await get_tree().process_frame
	var seed := 1
	var every := 3600
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="): seed = int(a.substr(7))
		if a.begins_with("--every="): every = int(a.substr(8))
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
	while g.state == Game.State.PLAYING and frames < 60 * 60 * 25:
		await get_tree().physics_frame
		frames += 1
		if frames % every == 0 and g.autopilot:
			print("  f=%d clock %s mode %s wp %d/%d pos %s local %s mv %s crowd %s" % [frames, Clock.fmt(Clock.now, true), g.autopilot.mode, g.autopilot.wp_i, g.autopilot.wps.size(), str(g.player.global_position), str(g.station.to_local(g.player.global_position).snapped(Vector3(0.1, 0.1, 0.1))) if g.station else "-", str(g.player.bot_move.snapped(Vector2(0.1, 0.1))), str(g.station.crowd.stats) if g.station and g.station.crowd else ""])
	print("state ", g.state, " frames ", frames, " sim end ", Clock.fmt(Clock.now, true))
	if g.autopilot:
		for l in g.autopilot.log_lines: print(l)
