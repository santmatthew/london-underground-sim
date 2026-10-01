extends Node3D
## Render cost of a station: CPU and GPU milliseconds per frame, draw calls and primitives for a hall, an escalator and a platform view.
## args: --station="Oxford Circus" --q=2 (Env quality tier 0-3) --frames=40      env: UG_OFF=decals,dressing (see Station.debug_off)
## run: SHOT_RES=1920x1080 SHOT_TIMEOUT=300 tools/shot.sh res://tests/perf_test.tscn -- --station=Bank --q=2
func _ready() -> void:
	var sname := "Oxford Circus"
	var q := 2
	var frames := 40
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): sname = a.substr(10)
		if a.begins_with("--q="): q = int(a.substr(4))
		if a.begins_with("--frames="): frames = int(a.substr(9))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Timetable.build(1)
	Clock.set_time(8.5 * 3600.0)
	var we := Env.make(q)
	add_child(we)
	var env: Environment = we.environment
	var lights_off := false
	var lights_half := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--set="):
			for kv in a.substr(6).split(","):
				match kv:
					"glow=0": env.glow_enabled = false
					"ssao=0": env.ssao_enabled = false
					"ssil=0": env.ssil_enabled = false
					"ssr=0": env.ssr_enabled = false
					"fog=0": env.fog_enabled = false
					"adjust=0": env.adjustment_enabled = false
					"taa=0": get_viewport().use_taa = false
					"scale=0.75": get_viewport().scaling_3d_scale = 0.75
					"bil=0.5":
						get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
						get_viewport().scaling_3d_scale = 0.5
					"bil=0.67":
						get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
						get_viewport().scaling_3d_scale = 0.67
					"fsr1=0.5":
						get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
						get_viewport().scaling_3d_scale = 0.5
					"fsr1=0.59":
						get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
						get_viewport().scaling_3d_scale = 0.59
					"fsr1=0.67":
						get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
						get_viewport().scaling_3d_scale = 0.67
					"fsr=0.5":
						get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
						get_viewport().scaling_3d_scale = 0.5
					"fsr=0.77":
						get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
						get_viewport().scaling_3d_scale = 0.77
					"fsr=0.67":
						get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
						get_viewport().scaling_3d_scale = 0.67
					"fsr=0.59":
						get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
						get_viewport().scaling_3d_scale = 0.59
					"scale=0.5": get_viewport().scaling_3d_scale = 0.5
					"ssao=low":
						RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW, true, 0.5, 2, 50, 300)
					"ssao=verylow":
						RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, true, 0.5, 1, 50, 300)
					"lights=0": lights_off = true
					"lights=half": lights_half = true
					"msaa=0": get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	var plan := StationPlan.for_station(Net.name_to_idx[sname])
	var st := Station.new()
	add_child(st)
	st.build(plan)
	st.trains.setup(st, null)
	for a in OS.get_cmdline_user_args():
		if a == "--hide-labels":
			for l in st.find_children("*", "Label3D", true, false):
				(l as Label3D).visible = false
		if a == "--hide-modsigns":
			for pm in st.modules:
				for c in pm.get_children():
					if c is Node3D and not (c is MeshInstance3D) and c.name not in ["Shell", "Collision", "EdgeGuard", "Lights", "Props"]:
						(c as Node3D).visible = false
		if a.begins_with("--hide="):
			for nm in a.substr(7).split(","):
				for n in st.find_children(nm, "Node3D", true, false):
					(n as Node3D).visible = false
				print("hidden: ", nm, " x", st.find_children(nm, "Node3D", true, false).size())
	if lights_half:
		var k := 0
		for l in st.find_children("*", "OmniLight3D", true, false):
			k += 1
			if k % 2 == 0:
				(l as OmniLight3D).visible = false
	if lights_off:
		for l in st.find_children("*", "OmniLight3D", true, false):
			(l as OmniLight3D).visible = false
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 75
	var views: Array = []
	var gz: float = plan.gates["z"]
	views.append(["hall", Vector3(0, 1.65, gz - 5.0), Vector3(0, 1.3, gz + 6.0)])
	if plan.escs.size() > 0:
		var e: Dictionary = plan.escs[0]
		var lz := plan.esc_lane_z(0, 0)
		views.append(["escalator", plan.esc_point(0, Vector3(0.5, 1.65, lz)), plan.esc_point(0, Vector3(e["length"], -e["rise"] + 0.9, lz))])
	var fk: String = plan.faces.keys()[0]
	var f: Dictionary = plan.faces[fk]
	views.append(["platform", Vector3(f["x0"] + 30, f["y"] + 1.65, f["edge_z"] - f["side"] * 1.2), Vector3(f["x0"] + 60, f["y"] + 1.35, f["edge_z"] + f["side"] * 0.2)])
	# census of what the station is made of: nodes, mesh surfaces (draw calls when visible), labels, lights, per top-level group
	var census := OS.get_environment("UG_CENSUS") != ""
	if census:
		for c in st.get_children():
			var meshes := 0
			var surfs := 0
			for mi in c.find_children("*", "MeshInstance3D", true, false):
				meshes += 1
				if (mi as MeshInstance3D).mesh:
					surfs += (mi as MeshInstance3D).mesh.get_surface_count()
			print("CENSUS %-14s meshes %4d surfaces %4d labels %3d lights %3d" % [c.name, meshes, surfs, c.find_children("*", "Label3D", true, false).size(), c.find_children("*", "OmniLight3D", true, false).size()])
			if c.name.begins_with("Module"):
				for cc in c.get_children():
					var m2 := 0
					var s2 := 0
					for mi in cc.find_children("*", "MeshInstance3D", true, false) + ([cc] if cc is MeshInstance3D else []):
						m2 += 1
						if (mi as MeshInstance3D).mesh:
							s2 += (mi as MeshInstance3D).mesh.get_surface_count()
					print("CENSUS   %-12s meshes %4d surfaces %4d labels %3d" % [cc.name, m2, s2, cc.find_children("*", "Label3D", true, false).size()])
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var rs := RenderingServer
	print("PERF station=%s q=%d off=[%s] adapter=%s res=%s" % [sname, q, OS.get_environment("UG_OFF"), rs.get_video_adapter_name(), str(get_viewport().size)])
	for v in views:
		cam.position = v[1]
		cam.look_at(v[2])
		for i in 25: await get_tree().process_frame
		var cpu := 0.0
		var gpu := 0.0
		var t0 := Time.get_ticks_usec()
		for i in frames:
			await get_tree().process_frame
			cpu += rs.viewport_get_measured_render_time_cpu(vp)
			gpu += rs.viewport_get_measured_render_time_gpu(vp)
		var wall := float(Time.get_ticks_usec() - t0) / 1000.0 / frames
		print("PERF  %-9s cpu %5.2f ms  gpu %5.2f ms  frame %5.2f ms (%3.0f fps)  draws %4d  prims %7d  objects %4d" % [v[0], cpu / frames, gpu / frames, wall, 1000.0 / maxf(wall, 0.01), rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	get_tree().quit()
