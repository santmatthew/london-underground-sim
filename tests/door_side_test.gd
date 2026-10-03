extends Node3D
## Which side of the train the doors open on. Over the whole network: how many platform modules are data-backed (OpenStreetMap platform outlines beside the track) and how many run with the platform on the
## right. For a few stations the train is spawned and its door side must be the data's and the door sills must lie beside the platform edge. args --stations="Liverpool Street|Westminster|..."
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	var names: Array = ["Liverpool Street", "Westminster", "Bond Street", "Oxford Circus", "Stratford", "Wimbledon"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stations="):
			names = a.substr(11).split("|")
	# the network
	var mods := 0
	var right := 0
	var backed := 0
	for idx in Net.stations.size():
		var plan := StationPlan.for_station(idx)
		for mi in plan.modules.size():
			mods += 1
			if int(plan.modules[mi].get("dir_sign", 1)) < 0:
				right += 1
			for fd in plan.modules[mi]["faces"]:
				if PlatformCurve.face_side(Net.station_ids[idx], String(fd["pid"])) in ["L", "R"]:
					backed += 1
					break
	print("  info: %d platform modules, %d with the platform on the right of the trains, %d backed by platform outlines in OpenStreetMap" % [mods, right, backed])
	Timetable.build(9)
	Clock.set_time(8.0 * 3600.0)
	for nm in names:
		var idx: int = Net.name_to_idx[nm]
		var plan := StationPlan.for_station(idx)
		var st := Station.new()
		add_child(st)
		st.build(plan)
		await get_tree().process_frame
		st.trains.setup(st, null)
		var space := get_world_3d().direct_space_state
		for fk in plan.faces:
			var f: Dictionary = plan.faces[fk]
			var want := PlatformCurve.face_side(Net.station_ids[idx], String(f["pid"]))
			var gp: int = Timetable.plat_index[idx][f["pid"]]
			var pick: Dictionary = {}
			for vv in Timetable.visits_between(gp, 8.0 * 3600.0, 8.0 * 3600.0 + 1500.0):
				if (Timetable.run_face[vv["run"]] as PackedByteArray)[vv["k"]] == f["face_no"] and not vv["origin"] and not vv["final"]:
					pick = vv
					break
			if pick.is_empty():
				continue
			Clock.set_time(float(pick["arr"]) + 12.0)
			st.trains._process(0.6)
			st.trains._process(0.1)
			var train: Train = null
			for vk in st.trains.visits:
				if st.trains.visits[vk]["key"] == fk:
					train = st.trains.visits[vk]["train"]
			if train == null:
				continue
			await get_tree().process_frame
			var pm: PlatformModule = st.modules[f["module"]]
			# the sill of the middle door on the door side must be beside the platform edge, the other sill must not
			var half_w := 1.31 if train.kind == "deep" else 1.5
			var edge_z: float = signf(train.track_z) * (PlatformModule.GAP * 0.5 + float(pm.meta["pw"]))
			var gaps := {}
			for sd in ["R", "L"]:
				var car := train.cars[3] as Node3D
				var sill := st.to_local(car.to_global(Vector3(0.0, 0.0, (1.0 if sd == "R" else -1.0) * half_w)))
				var d := pm.bend.unmap(sill - pm.position) if pm.bend != null else sill - pm.position
				gaps[sd] = absf(d.z - edge_z)
			var side: String = train.door_side
			var other := "L" if side == "R" else "R"
			check(float(gaps[side]) < 0.7 and float(gaps[other]) > 2.0, "%s %s: doors open on the %s side, beside the platform (gaps %.2f / %.2f m)" % [nm, fk, side, gaps[side], gaps[other]])
			var sides := {}
			for fd2 in plan.modules[f["module"]]["faces"]:
				sides[PlatformCurve.face_side(Net.station_ids[idx], String(fd2["pid"]))] = true
			var mixed: bool = sides.has("L") and sides.has("R")           # (a module's two platforms cannot be on different sides: the geometry has them both beside the middle)
			if want in ["L", "R"] and not mixed:
				check(side == want, "%s %s: the data says the platform is on the %s, the train opens its %s doors" % [nm, fk, want, side])
			print("  info: %s %s: platform on the %s (data: %s)" % [nm, fk, side, want if want != "" else "none"])
		st.queue_free()
		await get_tree().process_frame
	print("OK" if ok else "FAILED")
