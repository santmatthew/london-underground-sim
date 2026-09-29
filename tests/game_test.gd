extends Node
## Smoke-tests the real Game scene: menu -> journey -> briefing -> play. args: --time=am_peak
func run():
	var packed: PackedScene = load("res://scenes/main.tscn")
	var g: Game = packed.instantiate()
	add_child(g)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="): g.opts["time"] = a.substr(7)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/shot_game_menu.png")
	var t0 := Time.get_ticks_msec()
	g.start_journey()
	while g.state != Game.State.BRIEFING and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	print("briefing after ms: ", Time.get_ticks_msec() - t0, " state ", g.state)
	if g.state != Game.State.BRIEFING:
		return
	print("journey: ", Net.station_name(g.journey["start"]), " (", g.journey["spot"]["name"], ") -> ", Net.station_name(g.journey["dest"]), " at ", Clock.fmt(g.journey["t0"]), " par ", Clock.fmt_dur(g.journey["par_s"]))
	for i in 10: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/shot_game_brief.png")
	g._begin_play()
	for i in 40: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/shot_game_play.png")
	g._toggle_map()
	for i in 5: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/shot_game_map.png")
	print("ok, frames fine")
