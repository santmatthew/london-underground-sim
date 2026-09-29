extends Node
## Frame-time / draw-call survey at several spots of a big station with trains present. args: --station="Baker Street"
func run():
	var sname := "Baker Street"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): sname = a.substr(10)
	Timetable.build(5)
	Clock.set_time(8.25 * 3600.0)
	var idx: int = Net.name_to_idx[sname]
	var plan := StationPlan.for_station(idx)
	add_child(Env.make())
	var t0 := Time.get_ticks_msec()
	var st := Station.new()
	add_child(st)
	st.build(plan)
	print("station build ms ", Time.get_ticks_msec() - t0, " stages ", st.prof, " tris(meshkit) ", st.stats["tris"], " lights ", st.stats["lights"], " modules ", plan.modules.size())
	var player := Player.new()
	add_child(player)
	player.enabled = false
	st.trains.setup(st, player)
	var spots := {}
	var r: Array = plan.hall["rect"]
	spots["hall"] = [Vector3(0, 1.65, plan.gates["z"] + 3), Vector3(0, 1.4, r[3])]
	var f: Dictionary = plan.faces[plan.faces.keys()[0]]
	spots["platform"] = [Vector3(f["x0"] + 30, f["y"] + 1.65, f["edge_z"] - f["side"] * 1.2), Vector3(f["x0"] + 80, f["y"] + 1.2, f["edge_z"])]
	var f2: Dictionary = plan.faces[plan.faces.keys()[plan.faces.size() - 1]]
	spots["platform2"] = [Vector3(f2["x0"] + 60, f2["y"] + 1.65, f2["edge_z"] - f2["side"] * 1.2), Vector3(f2["x0"] + 20, f2["y"] + 1.2, f2["edge_z"])]
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 75
	cam.current = true
	# put a train in every face
	Clock.set_time(8.25 * 3600.0)
	for k in spots:
		cam.global_position = spots[k][0]
		cam.look_at(spots[k][1])
		player.global_position = spots[k][0]
		st.trains._spawn_pass(Clock.now)
		for i in 30: await get_tree().process_frame
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		var n := 60
		var gpu := 0.0
		var cpu := 0.0
		for i in n:
			await get_tree().process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		var ms := gpu / n
		print("%s: GPU %.1f ms  render-CPU %.1f ms  draw calls %d  primitives %.2fM  objects %d  vram %.0f MB  trains %d" % [k, ms, cpu / n, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1e6, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, st.trains.visits.size()])
