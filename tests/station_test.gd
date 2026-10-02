extends Node3D
## args: --station="Oxford Circus" --view=hall
func _ready() -> void:
	var sname := "Oxford Circus"
	var view := "hall"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): sname = a.substr(10)
		if a.begins_with("--view="): view = a.substr(7)
	StationPlan.step_free_mode = sys_arg("sf", "") != ""          # --sf=1: step-free journey fittings (lifts, barriers across the escalators)
	Timetable.build(1)
	Clock.set_time(float(sys_arg("hour", "8.0")) * 3600.0)
	var idx: int = Net.name_to_idx[sname]
	var t0 := Time.get_ticks_msec()
	var plan := StationPlan.for_station(idx)
	var t1 := Time.get_ticks_msec()
	add_child(Env.make())
	var st := Station.new()
	add_child(st)
	st.build(plan)
	print("plan ms ", t1 - t0, " build ms ", Time.get_ticks_msec() - t1, " tris ", st.stats["tris"], " lights ", st.stats["lights"], " levels ", plan.escs.size(), " modules ", plan.modules.size())
	var props_root := st.get_node_or_null("Props")
	if props_root:
		for c in props_root.get_children():
			if str(c.name).begins_with("Shop_") or str(c.name).begins_with("TicketBay") or str(c.name).begins_with("PosterStand") or str(c.name).begins_with("NewspaperStand") or str(c.name).begins_with("HelpPoint"):
				print("prop ", c.name, " at ", (c as Node3D).position, " yaw ", rad_to_deg((c as Node3D).rotation.y))
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = float(sys_arg("fov", "75"))
	var pos := Vector3.ZERO
	var look := Vector3.ZERO
	var r: Array = plan.hall["rect"]
	var cam_a := ""
	var look_a := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="): cam_a = a.substr(6)
		if a.begins_with("--look="): look_a = a.substr(7)
	match view:
		"street":
			var d: Dictionary = plan.street_doors[0]
			pos = d["pos"] + Vector3(0, 1.65, 3.0); look = d["pos"] + Vector3(0, 1.4, -2)
		"hall":
			pos = Vector3(0, 1.65, plan.gates["z"] - 5.0); look = Vector3(0, 1.3, plan.gates["z"] + 6)
		"exits":
			# the first street door, seen from inside its hall (authored halls have doors off-centre)
			var sd0: Dictionary = plan.street_doors[0]
			var hr0: Array = plan.hall_rect_for_door(sd0)
			var dcx: float = sd0["c"]
			pos = Vector3(dcx + 3.0, 1.65, hr0[2] + 7.0); look = Vector3(dcx, 2.0, hr0[2])
		"hall2":
			pos = Vector3(r[0] + 2, 1.65, r[2] + 2); look = Vector3(0, 1.3, plan.gates["z"] + 4)
		"gates":
			pos = Vector3(0, 1.65, plan.gates["z"] + 5.0); look = Vector3(0, 1.2, plan.gates["z"] - 4)
		"esc":
			pos = Vector3(0, 1.65, r[3] - 5.0); look = Vector3(0, -3.0, r[3] + 12)
		"shaft", "shaft_up":
			# standing on an escalator lane (--ei=escalator index, --lane=lane index) looking down ("shaft") or, from the foot, up the slope ("shaft_up")
			var ei := int(sys_arg("ei", "0"))
			var e: Dictionary = plan.escs[ei]
			var lz := plan.esc_lane_z(ei, int(sys_arg("lane", "0")))
			if view == "shaft":
				pos = plan.esc_point(ei, Vector3(float(sys_arg("x", "0.5")), 1.65, lz)); look = plan.esc_point(ei, Vector3(e["length"], -e["rise"] + 0.9, lz))
			else:
				pos = plan.esc_point(ei, Vector3(e["length"] - 0.8, -e["rise"] + 1.65, lz)); look = plan.esc_point(ei, Vector3(0.0, 1.2, lz))
		"landing":
			var l: Dictionary = plan.rooms[plan.rooms.size() - 1]
			for rm in plan.rooms:
				if rm["name"] == "landing0": l = rm
			var lr: Array = l["rect"]
			pos = Vector3(-4, l["y"] + 1.65, lr[2] + 2.5); look = Vector3(8, l["y"] + 1.5, (lr[2] + lr[3]) * 0.5)
		"corr":
			var m: Dictionary = plan.modules[0]
			pos = Vector3(m["corr"][0] + 1, m["pos"].y + 1.65, m["lane_z"]); look = Vector3(m["corr"][0] + 30, m["pos"].y + 1.5, m["lane_z"])
		"spine":
			var m2: Dictionary = plan.modules[0]
			pos = m2["pos"] + Vector3(m2["spec"]["spine_x0"] + 6, 1.65, 0); look = pos + Vector3(20, -0.2, 0)
		"spine2":
			var m3: Dictionary = plan.modules[1]
			pos = m3["pos"] + Vector3(m3["spec"]["spine_x0"] + 3, 1.65, 0); look = pos + Vector3(20, 0.2, 0)
		"landing2":
			var l2: Dictionary = plan.rooms[0]
			for rm in plan.rooms:
				if rm["name"] == "landing0": l2 = rm
			var lr2: Array = l2["rect"]
			pos = Vector3(0, l2["y"] + 1.65, lr2[2] + 3.0); look = Vector3(7, l2["y"] + 2.5, (lr2[2] + lr2[3]) * 0.5)
		"plat2":
			var f2: Dictionary = plan.faces[plan.faces.keys()[2]]
			pos = Vector3(f2["x0"] + 12, f2["y"] + 1.65, f2["edge_z"] - f2["side"] * 1.2); look = pos + Vector3(30, 0.6, f2["side"] * 0.2)
		"wall":
			# straight across the tracks at the track-side wall (where the station-name signs are); --x=metres from the west end
			var fwl: Dictionary = plan.faces[plan.faces.keys()[int(sys_arg("fi", "0"))]]
			var wx: float = fwl["x0"] + float(sys_arg("x", "40"))
			pos = Vector3(wx, fwl["y"] + 1.5, fwl["edge_z"] - fwl["side"] * 0.5); look = Vector3(wx, fwl["y"] + 1.1, fwl["track_z"] + fwl["side"] * 1.75)
		"pwall":
			# across the platform at its wall (the tile scheme, fascia, lettering, recesses); --x=metres from the west end, --fi=face, --dx=look offset along the wall
			var fpw: Dictionary = plan.faces[plan.faces.keys()[int(sys_arg("fi", "0"))]]
			var mpz: float = (plan.modules[fpw["module"]]["pos"] as Vector3).z
			var pwx: float = fpw["x0"] + float(sys_arg("x", "40"))
			var zwl: float = mpz + float(fpw["side"]) * PlatformModule.GAP * 0.5
			pos = Vector3(pwx, fpw["y"] + 1.5, float(fpw["edge_z"]) - float(fpw["side"]) * 0.4)
			look = Vector3(pwx + float(sys_arg("dx", "6")), fpw["y"] + 1.3, zwl)
		"lift_top", "lift_bot":
			# in front of a lift (--li=bank index), looking at the housing; --back=metres further away
			var lf: Dictionary = plan.lift_of(int(sys_arg("li", "0")))
			var ld: Dictionary = lf["top" if view == "lift_top" else "bot"]
			var out: Vector3 = Basis(Vector3.UP, float(ld["yaw"])) * Vector3(0, 0, -1)
			pos = (ld["front"] as Vector3) + out * float(sys_arg("back", "1.0")) + Vector3(0, 1.65, 0)
			look = (ld["pos"] as Vector3) + Vector3(0, 1.4, 0)
		"plat_w":
			# from near the west end of a platform looking west, along the track into the (shortened) running tunnel and its cap
			var fw: Dictionary = plan.faces[plan.faces.keys()[int(sys_arg("fi", "0"))]]
			pos = Vector3(fw["x0"] + 6, fw["y"] + 1.65, fw["edge_z"] - fw["side"] * 1.2); look = pos + Vector3(-30, -0.3, fw["side"] * 0.6)
		"plat":
			var f: Dictionary = plan.faces[plan.faces.keys()[int(sys_arg("fi", "0"))]]
			pos = Vector3(f["x0"] + 30, f["y"] + 1.65, f["edge_z"] - f["side"] * 1.2); look = pos + Vector3(30, -0.3, f["side"] * 0.6)
	if view == "train":
		# find a train visit at the first face and set the clock to mid-dwell
		var fk: String = plan.faces.keys()[int(sys_arg("fi", "0"))]
		var fc: Dictionary = plan.faces[fk]
		var gp: int = Timetable.plat_index[idx][fc["pid"]]
		var vs: Array = Timetable.visits_between(gp, 8.0 * 3600.0, 8.0 * 3600.0 + 600.0)
		var pick: Dictionary = vs[0]
		for v0 in vs:
			if (Timetable.run_face[v0["run"]] as PackedByteArray)[v0["k"]] == fc["face_no"] and not v0["origin"] and not v0["final"]:
				pick = v0; break
		var tm: float = float(pick["arr"]) + float(sys_arg("t", "12"))
		Clock.set_time(tm)
		Clock.running = false
		st.trains.setup(st, null)
		st.trains._process(0.6)
		st.trains._process(0.1)
		pos = Vector3(fc["x0"] + 20, fc["y"] + 1.65, fc["edge_z"] - fc["side"] * 1.2); look = Vector3(fc["x0"] + 60, fc["y"] + 1.2, fc["edge_z"] + fc["side"] * 3.0)
	# --mcam=x,y,z --mlook=x,y,z : camera and target in a module's frame (--mi=module index; x along the track, z across it, y = platform level)
	var mcam := sys_arg("mcam", "")
	if mcam != "":
		var mpos: Vector3 = plan.modules[int(sys_arg("mi", "0"))]["pos"]
		var a1 := mcam.split(",")
		var a2 := sys_arg("mlook", "0,1.5,0").split(",")
		pos = mpos + Vector3(float(a1[0]), float(a1[1]), float(a1[2]))
		look = mpos + Vector3(float(a2[0]), float(a2[1]), float(a2[2]))
	if cam_a != "" and look_a != "":
		var cp := cam_a.split(",")
		var lp := look_a.split(",")
		pos = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
		look = Vector3(float(lp[0]), float(lp[1]), float(lp[2]))
	cam.position = pos
	cam.look_at(look)
	# upscaler comparison: --mode=native|fsr1|fsr2 --scale=0.667 (the 3D scene is drawn at that fraction of the window and upscaled)
	var mode := sys_arg("mode", "")
	if mode != "":
		var vp := get_viewport()
		vp.scaling_3d_scale = float(sys_arg("scale", "1.0"))
		match mode:
			"fsr1": vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			"fsr2": vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			_: vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		print("upscale: ", mode, " at ", vp.scaling_3d_scale, " (window ", get_window().size, ")")
	var out_name := sys_arg("out", "")
	for i in int(sys_arg("frames", "20")): await get_tree().process_frame
	var rs := RenderingServer
	print("render: draw calls %d, primitives %d, objects %d" % [rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	get_viewport().get_texture().get_image().save_png(out_name if out_name != "" else "res://build/shot_station_%s.png" % view)
	get_tree().quit()

func gz_hall(plan: StationPlan) -> float:
	return float(plan.gates["z"])


func sys_arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.substr(name.length() + 3)
	return def
