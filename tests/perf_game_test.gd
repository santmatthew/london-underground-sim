extends Node
## Frame cost while the autopilot plays a real journey (crowds, trains, rides): every 90 physics frames prints the game state, process/physics script time
## and render CPU/GPU time. run: SHOT_RES=1920x1080 SHOT_ENGINE_ARGS="--fixed-fps 60" SHOT_TIMEOUT=600 tools/shot.sh res://tests/runner.tscn -- --test=perf_game_test --seed=3 [--q=1 --crowd=1.0 --frames=5400]
func run():
	var q := -1
	var crowd := -1.0
	var frames := 5400
	var seed_s := "3"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--q="): q = int(a.substr(4))
		if a.begins_with("--crowd="): crowd = float(a.substr(8))
		if a.begins_with("--frames="): frames = int(a.substr(9))
		if a.begins_with("--seed="): seed_s = a.substr(7)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {"seed": seed_s, "autopilot": "1"}
	add_child(g)
	await get_tree().process_frame
	if q >= 0: g.opts["quality"] = q
	if crowd >= 0.0: g.opts["crowd"] = crowd
	g._apply_settings()
	g.start_journey()
	while g.state != Game.State.BRIEFING:
		await get_tree().process_frame
	g._begin_play()
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var rs := RenderingServer
	print("PERFG adapter=%s res=%s quality=%s crowd=%s" % [rs.get_video_adapter_name(), str(get_viewport().size), str(g.opts["quality"]), str(g.opts["crowd"])])
	var n := 0
	var cpu := 0.0
	var gpu := 0.0
	var proc := 0.0
	var phys := 0.0
	var cnt := 0
	var worst_gpu := 0.0
	var t_last := Time.get_ticks_usec()
	while g.state == Game.State.PLAYING and n < frames:
		await get_tree().physics_frame
		n += 1
		cpu += rs.viewport_get_measured_render_time_cpu(vp)
		var gp := rs.viewport_get_measured_render_time_gpu(vp)
		gpu += gp
		worst_gpu = maxf(worst_gpu, gp)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		cnt += 1
		if n % 90 == 0:
			var mode: String = g.autopilot.mode if g.autopilot else "-"
			var wall_ms := float(Time.get_ticks_usec() - t_last) / 1000.0 / 90.0
			t_last = Time.get_ticks_usec()
			print("PERFG f=%5d %-9s %-12s render cpu %5.2f gpu %5.2f (max %5.2f) | script process %5.2f physics %5.2f ms | draws %4d prims %7d objs %4d | nodes %6d | WALL %6.2f ms/frame" % [n, "riding" if g.riding else "station", mode, cpu / cnt, gpu / cnt, worst_gpu, proc / cnt, phys / cnt, rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), wall_ms])
			cpu = 0.0; gpu = 0.0; proc = 0.0; phys = 0.0; cnt = 0; worst_gpu = 0.0
	print("PERFG done")
