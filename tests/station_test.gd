extends Node3D
## args: --station="Oxford Circus" --view=hall
func _ready() -> void:
	var sname := "Oxford Circus"
	var view := "hall"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): sname = a.substr(10)
		if a.begins_with("--view="): view = a.substr(7)
	Timetable.build(1)
	Clock.set_time(8.0 * 3600.0)
	var idx: int = Net.name_to_idx[sname]
	var t0 := Time.get_ticks_msec()
	var plan := StationPlan.for_station(idx)
	var t1 := Time.get_ticks_msec()
	add_child(Env.make())
	var st := Station.new()
	add_child(st)
	st.build(plan)
	print("plan ms ", t1 - t0, " build ms ", Time.get_ticks_msec() - t1, " tris ", st.stats["tris"], " lights ", st.stats["lights"], " levels ", plan.escs.size(), " modules ", plan.modules.size())
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 75
	var pos := Vector3.ZERO
	var look := Vector3.ZERO
	var r: Array = plan.hall["rect"]
	match view:
		"street":
			var d: Dictionary = plan.street_doors[0]
			pos = d["pos"] + Vector3(0, 1.65, 3.0); look = d["pos"] + Vector3(0, 1.4, -2)
		"hall":
			pos = Vector3(0, 1.65, plan.gates["z"] - 5.0); look = Vector3(0, 1.3, plan.gates["z"] + 6)
		"hall2":
			pos = Vector3(r[0] + 2, 1.65, r[2] + 2); look = Vector3(0, 1.3, plan.gates["z"] + 4)
		"gates":
			pos = Vector3(0, 1.65, plan.gates["z"] + 5.0); look = Vector3(0, 1.2, plan.gates["z"] - 4)
		"esc":
			pos = Vector3(0, 1.65, r[3] - 5.0); look = Vector3(0, -3.0, r[3] + 12)
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
		"plat":
			var f: Dictionary = plan.faces[plan.faces.keys()[int(sys_arg("fi", "0"))]]
			pos = Vector3(f["x0"] + 30, f["y"] + 1.65, f["edge_z"] - f["side"] * 1.2); look = pos + Vector3(30, -0.3, f["side"] * 0.6)
	if view == "train":
		# find a train visit at the first face and set the clock to mid-dwell
		var fk: String = plan.faces.keys()[0]
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
	cam.position = pos
	cam.look_at(look)
	for i in 20: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/shot_station_%s.png" % view)
	get_tree().quit()

func sys_arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.substr(name.length() + 3)
	return def
