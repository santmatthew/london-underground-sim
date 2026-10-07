extends Node3D
## The scenery of a ride (TunnelRun) seen from a camera on the track, without a train: the other track of the pair, the cuttings and the mouths.
## args --a=Name --b=Name [--left_a] [--left_b] (the other face of the module at that end is on the left: TrackPath._plan_sides) [--line=piccadilly] [--trains --cam=s --offsets=-4,-2,0,1.5] (the trains of the other track: shots around the moment the first one passes the camera at path distance s) --at=s1,s2,.. (path distance) --look=left|right|ahead|back [--mirror] [--hour=H] [--out=res://build/run_view] [--eye=1.6] [--fov=75]
## output: <out>_<n>.png per position. "right" is the side of the path the other track of the pair lies on, whatever the door side (--mirror: the train has its doors on the right).
func _ready() -> void:
	var out := "res://build/run_view"
	var na := "Amersham"
	var nb := "Chalfont & Latimer"
	var line := ""
	var ats := [300.0]
	var look := "right"
	var mirror := false
	var left_a := false
	var left_b := false
	var trains := false
	var nohide := false
	var cam_s := 600.0
	var offsets := [-4.0, -2.0, -0.7, 0.0, 1.5]
	var eye := 1.6
	var fov := 75.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--a="): na = a.substr(4)
		if a.begins_with("--b="): nb = a.substr(4)
		if a.begins_with("--line="): line = a.substr(7)
		if a.begins_with("--at="):
			ats = []
			for p in a.substr(5).split(","):
				ats.append(float(p))
		if a.begins_with("--look="): look = a.substr(7)
		if a.begins_with("--hour="): Clock.now = float(a.substr(7)) * 3600.0
		if a.begins_with("--eye="): eye = float(a.substr(6))
		if a.begins_with("--fov="): fov = float(a.substr(6))
		if a == "--mirror": mirror = true
		if a == "--left_a": left_a = true
		if a == "--left_b": left_b = true
		if a == "--trains": trains = true
		if a == "--nohide": nohide = true          # (a train on a crossing is shown although the camera, taken for the player's train, stands on it)
		if a.begins_with("--cam="): cam_s = float(a.substr(6))
		if a.begins_with("--offsets="):
			offsets = []
			for p in a.substr(10).split(","):
				offsets.append(float(p))
	if trains:
		Timetable.build(1)
	add_child(Env.make(0))
	var ia: int = Net.name_to_idx[na]
	var ib: int = Net.name_to_idx[nb]
	var ida: String = Net.station_ids[ia]
	var idb: String = Net.station_ids[ib]
	var prof: Array = TrackPath.profile(ida, idb)
	var dist: float = float(prof[0]) if not prof.is_empty() else 1500.0
	var ss: bool = line != "" and String(Net.lines[line]["group"]) == "ss"
	var path := TrackPath.between(ida, idb, dist, 120.0, 120.0, [], [], [], [], ss, 0.0, 0.0, line, left_a, left_b)
	print("hop ", na, " -> ", nb, " ", snappedf(dist, 1.0), " m; scenes along it:")
	var row := ""
	for k in range(0, int(dist / 12.0) + 1, 2):
		row += "%d" % (path.cell_scene(k) & 7)
	print("  ", row)
	var sides := ""
	for k in range(0, int(dist / 12.0) + 1, 2):
		var sck := path.cell_scene(k)
		sides += "." if (sck & RunScenery.PAIR) == 0 else ("X" if (sck & RunScenery.CROSS) != 0 else ("L" if (sck & RunScenery.SIDE_LEFT) != 0 else "R"))
	print("  ", sides, "  (", path.side_change, ")")
	var tun := TunnelRun.new()
	add_child(tun)
	tun.setup(path, mirror, float(ats[0]))
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = fov
	cam.far = 400.0
	var n := 0
	if trains:
		var t0 := Clock.now
		var onc := Oncoming.new()
		add_child(onc)
		onc.setup(path, ia, ib, t0, t0 + 900.0, dist)
		if nohide:
			onc._cross_hi = -1e9
		print("oncoming trains in the next 15 min: ", onc.entries.size())
		if onc.entries.is_empty():
			get_tree().quit()
			return
		var e: Dictionary = onc.entries[0]
		for e2 in onc.entries:
			if onc.s_of(e2, float(e2["info"]["dep"]) + float(e2["T"]) * 0.5) < dist:
				e = e2
				break
		# the moment its middle is at the camera
		var lo := float(e["info"]["dep"])
		var hi := lo + float(e["T"])
		for _i in 40:
			var mid := (lo + hi) * 0.5
			if onc.s_of(e, mid) > cam_s:
				lo = mid
			else:
				hi = mid
		var t_pass := (lo + hi) * 0.5
		print("run ", e["info"]["run"], " (", e["info"]["line"], ") passes s=", cam_s, " at ", Clock.fmt(t_pass, true), " T ", snappedf(e["T"], 1.0), " s, len ", snappedf(e["len"], 1.0))
		tun.place(cam_s)
		var t_wait := Time.get_ticks_msec() + 30000
		while tun.busy() and Time.get_ticks_msec() < t_wait:
			await get_tree().process_frame          # (the workers build in real time, the frames of a headless run go by far faster)
		tun.place(cam_s)
		for _i in 10:
			await get_tree().process_frame
		var pose0 := path.pose(cam_s)
		for off: float in offsets:
			for _i in 12:
				Clock.now = t_pass + off
				onc.update(cam_s, Clock.now, Transform3D.IDENTITY)
				await get_tree().process_frame
			var up0 := Vector3(0.0, eye, 0.0)
			var dirs0 := {"left": Vector3(0, 0, -12), "right": Vector3(0, 0, 12), "ahead": Vector3(40, 0, 0), "back": Vector3(-40, 0, 0), "rightdown": Vector3(0, -9, 10), "leftdown": Vector3(0, -9, -10), "aheaddown": Vector3(30, -10, 0)}
			var d0: Vector3 = dirs0.get(look, dirs0["left"])
			cam.global_transform = Transform3D(pose0.basis, pose0.origin + pose0.basis * up0)
			cam.look_at(pose0.origin + pose0.basis * (up0 + d0))
			Clock.now = t_pass + off
			onc.update(cam_s, Clock.now, Transform3D.IDENTITY)
			await get_tree().process_frame
			await get_tree().process_frame
			n += 1
			var p0 := "%s_t%d.png" % [out, n]
			get_viewport().get_texture().get_image().save_png(p0)
			print("SNAP ", p0, " offset ", off, " s_mid ", snappedf(onc.s_of(e, Clock.now), 0.1), " shown ", onc.shown)
		get_tree().quit()
		return
	for s: float in ats:
		tun.place(s)
		var t_wait2 := Time.get_ticks_msec() + 30000
		while tun.busy() and Time.get_ticks_msec() < t_wait2:
			await get_tree().process_frame
		tun.place(s)
		for _i in 20:
			await get_tree().process_frame
		var pose := path.pose(s)
		var up := Vector3(0.0, eye, 0.0)
		var dirs := {"left": Vector3(0, 0, -20), "right": Vector3(0, 0, 20), "ahead": Vector3(40, 0, 0), "back": Vector3(-40, 0, 0), "rightdown": Vector3(0, -9, 10), "leftdown": Vector3(0, -9, -10), "aheaddown": Vector3(30, -10, 0)}
		var d: Vector3 = dirs.get(look, dirs["left"])
		cam.global_transform = Transform3D(pose.basis, pose.origin + pose.basis * up)
		cam.look_at(pose.origin + pose.basis * (up + d))
		for _i in 10:
			await get_tree().process_frame
		n += 1
		var p := "%s_%d.png" % [out, n]
		get_viewport().get_texture().get_image().save_png(p)
		print("SNAP ", p, " s=", s, " scene ", path.cell_scene(int(roundf(s / 12.0))))
	get_tree().quit()
