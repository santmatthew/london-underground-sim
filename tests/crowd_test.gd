extends Node3D
## Crowd visual test. args: --station="Oxford Circus" --view=hall|plat|train --hour=8.25
func _arg(n: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % n): return a.substr(n.length() + 3)
	return d
func _ready() -> void:
	var sname := _arg("station", "Oxford Circus")
	var view := _arg("view", "hall")
	Timetable.build(9)
	Clock.set_time(float(_arg("hour", "8.25")) * 3600.0)
	Clock.running = false
	var idx: int = Net.name_to_idx[sname]
	var plan := StationPlan.for_station(idx)
	add_child(Env.make(int(_arg("quality", "2"))))
	var st := Station.new()
	add_child(st)
	st.build(plan)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 75
	cam.current = true
	var player := Player.new()
	add_child(player)
	player.enabled = false
	var pos := Vector3.ZERO
	var look := Vector3.ZERO
	var r: Array = plan.hall["rect"]
	var fk: String = plan.faces.keys()[0]
	var f: Dictionary = plan.faces[fk]
	match view:
		"hall":
			pos = Vector3(0, 1.65, plan.gates["z"] - 5.5); look = Vector3(0, 1.4, plan.gates["z"] + 8)
		"gates":
			pos = Vector3(0, 1.65, plan.gates["z"] + 6.0); look = Vector3(0, 1.3, plan.gates["z"] - 5)
		"esc":
			pos = Vector3(0, 1.65, r[3] - 4.0); look = Vector3(0, 0.0, r[3] + 10)
		"plat":
			pos = Vector3(f["x0"] + 40, f["y"] + 1.65, f["edge_z"] - f["side"] * 1.3); look = pos + Vector3(30, 0.0, f["side"] * 0.5)
		"train":
			pos = Vector3(f["x0"] + 30, f["y"] + 1.65, f["edge_z"] - f["side"] * 1.3); look = pos + Vector3(25, 0.0, f["side"] * 3.0)
	player.global_position = pos
	cam.position = pos
	cam.look_at(look)
	cam.make_current()
	st.trains.setup(st, player)
	if view == "train":
		var gp: int = Timetable.plat_index[idx][f["pid"]]
		for v0 in Timetable.visits_between(gp, Clock.now, Clock.now + 900.0):
			if (Timetable.run_face[v0["run"]] as PackedByteArray)[v0["k"]] == f["face_no"] and not v0["origin"] and not v0["final"] and v0["dep"] - v0["arr"] > 20.0:
				Clock.set_time(v0["arr"] + 10.0); break
	st.attach_crowd(player)
	st.trains._spawn_pass(Clock.now)
	st.trains._process(0.6)
	Clock.running = true
	var t0 := Time.get_ticks_msec()
	for i in 240: await get_tree().process_frame
	Clock.running = false
	print("crowd: ", st.crowd.stats, " build+sim ms ", Time.get_ticks_msec() - t0)
	var vp := get_viewport().get_viewport_rid()
	get_viewport().get_texture().get_image().save_png("res://build/shot_crowd_%s.png" % view)
	print("saved")
