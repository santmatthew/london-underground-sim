extends Node3D
## The track path a ride follows into (or out of) a curved platform must put every car where the platform itself puts it when the train stands there: for each face of a curved module the cars as the path
## places them (Train.follow_path) are compared with the cars as the module places them (Train.place). args --station=Bank
var ok := true


func run():
	var nm := "Bank"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): nm = a.substr(10)
	Timetable.build(9)
	var idx: int = Net.name_to_idx[nm]
	var plan := StationPlan.for_station(idx)
	add_child(Env.make(0))
	var st := Station.new()
	add_child(st)
	st.build(plan)
	await get_tree().process_frame
	for fk in plan.faces:
		var f: Dictionary = plan.faces[fk]
		var pm: PlatformModule = st.modules[f["module"]]
		if pm.bend == null:
			continue
		var gp: int = Timetable.plat_index[idx][f["pid"]]
		var pick: Dictionary = {}
		for vv in Timetable.visits_between(gp, 8.0 * 3600.0, 8.0 * 3600.0 + 1500.0):
			if (Timetable.run_face[vv["run"]] as PackedByteArray)[vv["k"]] == f["face_no"] and not vv["origin"] and not vv["final"]:
				pick = vv
				break
		if pick.is_empty():
			continue
		Clock.set_time(float(pick["arr"]) + 12.0)
		st.trains.setup(st, null)
		st.trains._process(0.6)
		st.trains._process(0.1)
		var train: Train = null
		for vk in st.trains.visits:
			if st.trains.visits[vk]["key"] == fk:
				train = st.trains.visits[vk]["train"]
		if train == null:
			continue
		await get_tree().process_frame
		var placed: Array = []
		for c in train.cars:
			placed.append((c as Node3D).transform)
		# the path: the train arrives at x = 0 along this module (tail), and the track goes on through the platform (after); behind the stopped train it came along the arc, ahead it carries on
		var dist := 600.0
		var bend: Bend = pm.bend
		var canon := plan.canon_of(f)
		var tz := train.track_z
		var path := TrackPath.between("a", "b", dist, 100.0, 100.0, [], bend.arrival_segments(0.0, canon, tz), [], bend.departure_segments(0.0, canon, tz))
		train.follow_path(path, dist, Transform3D.IDENTITY)
		var worst := 0.0
		var worst_i := 0
		for i in train.cars.size():
			var d := ((train.cars[i] as Node3D).transform.origin - (placed[i] as Transform3D).origin).length()
			if d > worst:
				worst = d
				worst_i = i
		print("  %s: the path and the platform put the cars at most %.3f m apart (car %d of %d)" % [fk, worst, worst_i, train.cars.size()])
		if worst > 0.25:
			print("  FAIL %s" % fk)
			ok = false
	print("OK" if ok else "FAILED")
