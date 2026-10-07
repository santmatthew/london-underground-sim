extends Node
## The hand-over between a station's running track beyond the platform and the ride's cells, seen from the same place: the cells of a ride that arrives at `--b` (TunnelRun, from the path) and the module's own
## stretch there (PlatformModule's ext), from a camera on the path `--d` metres before the platform's end, looking left, ahead and right. Whatever differs between the two is a pop at the hand-over.
## --left_a: the other end of the hop has its other face on the left too (else the ride's second track changes sides somewhere, or not at all)
## --c=Name: the ride DEPARTS from --b for that station instead (the camera is --d metres beyond the platform's far end, the cells are the ride's first)
## run: SHOT_ENGINE_ARGS="--fixed-fps 60" SHOT_TIMEOUT=400 tools/shot.sh res://tests/runner.tscn -- --test=handover_view_test --a="Fulham Broadway" --b="Parsons Green" --pid=ss:Eastbound --face=0 [--d=45] [--hour=12] [--eye=2.2]
## output: build/handover_<b>.png (rows: left, ahead, right; left column the ride's cells, right column the station's own)
var root: Node3D
var cam: Camera3D


func _grab(path: String) -> Image:
	for _i in 6:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	return img


func run():
	var na := "Fulham Broadway"
	var nb := "Parsons Green"
	var pid := "ss:Eastbound"
	var face := 0
	var d := 45.0
	var eye := 2.2
	var left_a := false
	var nc := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--a="): na = a.substr(4)
		if a.begins_with("--b="): nb = a.substr(4)
		if a.begins_with("--pid="): pid = a.substr(6)
		if a.begins_with("--face="): face = int(a.substr(7))
		if a.begins_with("--d="): d = float(a.substr(4))
		if a.begins_with("--c="): nc = a.substr(4)
		if a.begins_with("--eye="): eye = float(a.substr(6))
		if a == "--left_a": left_a = true          # (the other end of the hop wants the other face on the left too)
		if a.begins_with("--hour="): Clock.now = float(a.substr(7)) * 3600.0
	Timetable.build(1)
	root = Node3D.new()
	add_child(root)
	root.add_child(Env.make(0))
	var ia: int = Net.name_to_idx[na]
	var ib: int = Net.name_to_idx[nb]
	var ida: String = Net.station_ids[ia]
	var idb: String = Net.station_ids[ib]
	var plan := StationPlan.for_station(ib)
	var key := "%s#%d" % [pid, face]
	var f: Dictionary = plan.faces[key]
	var length: float = f["length"]
	var left_b := plan.other_track_left(key)
	var line: String = f["line"]
	var ss: bool = String(Net.lines[line]["group"]) == "ss"
	var nbrs := PlatformCurve.neighbours(idb, pid)
	print("neighbours of ", key, " (the stations before and after it along its line, in the module's frame: west, east) ", nbrs, ", trains run toward ", "east" if plan.canon_of(f) > 0 else "west")
	var depart := nc != ""
	var path: TrackPath
	var dist := 0.0
	var s_cam := 0.0
	var s_stand := 0.0          # where the train's centre stands on the path in the module's frame: its stop
	if depart:
		var idc: String = Net.station_ids[Net.name_to_idx[nc]]
		var prof_c: Array = TrackPath.profile(idb, idc)
		dist = float(prof_c[0]) if not prof_c.is_empty() else 1200.0
		path = TrackPath.between(idb, idc, dist, length * 0.5 + 24.0, length * 0.5 + 66.0, [], [], [], [], ss, 0.0, 0.0, line, left_b, left_a)
		s_cam = length * 0.5 + d
		s_stand = 0.0
		print("departing %s -> %s %s, %.0f m, other face on the left: %s, sides %s" % [nb, nc, key, dist, str(left_b), path.side_change])
	else:
		var prof: Array = TrackPath.profile(ida, idb)
		dist = float(prof[0]) if not prof.is_empty() else 1200.0
		path = TrackPath.between(ida, idb, dist, length * 0.5 + 24.0, length * 0.5 + 66.0, [], [], [], [], ss, 0.0, 0.0, line, left_a, left_b)
		s_cam = dist - length * 0.5 - d
		s_stand = dist
		print("arriving %s -> %s %s, %.0f m, other face on the left: %s, sides %s" % [na, nb, key, dist, str(left_b), path.side_change])
	var sides := ""
	for k in range(int(s_cam / 12.0) - 15, int(s_cam / 12.0) + 15):
		var sck := path.cell_scene(k)
		sides += "." if (sck & RunScenery.PAIR) == 0 else ("X" if (sck & RunScenery.CROSS) != 0 else ("L" if (sck & RunScenery.SIDE_LEFT) != 0 else "R"))
	print("  the cells round the camera: ", sides)
	var pose := path.pose(s_cam)
	cam = Camera3D.new()
	root.add_child(cam)
	cam.fov = 75.0
	cam.far = 400.0
	var dirs := {"left": Vector3(0, 0, -20), "ahead": Vector3(40, 0, 0), "right": Vector3(0, 0, 20)}
	var imgs := {}          # "cells" / "module" -> [Image...]
	# 1. the ride's cells
	var tun := TunnelRun.new()
	root.add_child(tun)
	tun.setup(path, false, s_cam)
	tun.place(s_cam)
	for _i in 600:
		await get_tree().process_frame
		if not tun.busy():
			break
	tun.place(s_cam)
	imgs["cells"] = []
	for look in ["left", "ahead", "right"]:
		cam.global_transform = Transform3D(pose.basis, pose.origin + pose.basis * Vector3(0.0, eye, 0.0))
		cam.look_at(pose.origin + pose.basis * (Vector3(0.0, eye, 0.0) + dirs[look]))
		imgs["cells"].append(await _grab("res://build/handover_cells_%s.png" % look))
	tun.queue_free()
	for _i in 5:
		await get_tree().process_frame
	# 2. the station's own
	var st := Station.new()
	root.add_child(st)
	await st.build_async(plan)
	for _i in 10:
		await get_tree().process_frame
	var canon := plan.canon_of(f)
	var tz: float = f["track_z"] - plan.modules[f["module"]]["pos"].z
	var turn := Transform3D(Basis(Vector3.UP, 0.0 if canon > 0 else PI), Vector3.ZERO)
	var slot := Transform3D(Basis.IDENTITY, Vector3(0, PlatformModule.RAIL_Y, tz)) * turn
	var stand := Transform3D(Basis.IDENTITY, plan.modules[f["module"]]["pos"]) * slot
	st.global_transform = path.pose(s_stand) * Transform3D(Basis.IDENTITY, Vector3(0.0, PlatformModule.RAIL_Y, 0.0)) * stand.affine_inverse()
	for _i in 20:
		await get_tree().process_frame
	imgs["module"] = []
	for look in ["left", "ahead", "right"]:
		cam.global_transform = Transform3D(pose.basis, pose.origin + pose.basis * Vector3(0.0, eye, 0.0))
		cam.look_at(pose.origin + pose.basis * (Vector3(0.0, eye, 0.0) + dirs[look]))
		imgs["module"].append(await _grab("res://build/handover_module_%s.png" % look))
	# the sheet
	var w := 640
	var h := 360
	var sheet := Image.create(w * 2, h * 3, false, Image.FORMAT_RGB8)
	for r in 3:
		for c in 2:
			var im: Image = (imgs["cells"] if c == 0 else imgs["module"])[r]
			im.convert(Image.FORMAT_RGB8)
			im.resize(w, h)
			sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(c * w, r * h))
	var outp := "res://build/handover_%s.png" % nb.replace(" ", "_")
	sheet.save_png(outp)
	print("SNAP ", outp)
	get_tree().quit()
