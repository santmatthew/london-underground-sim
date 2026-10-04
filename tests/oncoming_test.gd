extends Node
## The trains that come the other way on a ride's second track (Oncoming, RunScenery PAIR): the timetable query agrees with a brute-force search, each train goes from the destination to the origin in its run's
## time, stands on the second track facing the other way, is shown only where that track is in view, and the trains already in view at the hand-over are left out.
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	Timetable.build(1)
	var t0 := 12.0 * 3600.0
	Clock.now = t0
	# (open country with a train every few minutes both ways; a line of the other group, mirrored)
	for hop in [["Amersham", "Chalfont & Latimer", false, 600.0], ["Chalfont & Latimer", "Amersham", true, 700.0], ["Colindale", "Hendon Central", false, 400.0]]:
		await _hop(hop[0], hop[1], hop[2], hop[3], t0)
	print("OK" if ok else "FAILED")


func _hop(na: String, nb: String, mirror: bool, cam_s: float, t0: float) -> void:
	var ia: int = Net.name_to_idx[na]
	var ib: int = Net.name_to_idx[nb]
	var ida: String = Net.station_ids[ia]
	var idb: String = Net.station_ids[ib]
	var prof: Array = TrackPath.profile(ida, idb)
	var dist: float = float(prof[0])
	var path := TrackPath.between(ida, idb, dist, 120.0, 120.0)
	var t1 := t0 + 900.0
	# --- the query against a search of every run
	var found: Array = Timetable.oncoming(ia, ib, t0, t1)
	var brute := 0
	for r in Timetable.run_stops.size():
		var stops: PackedInt32Array = Timetable.run_stops[r]
		for k in range(1, stops.size()):
			if stops[k - 1] == ib and stops[k] == ia:
				var dep: float = (Timetable.run_dep[r] as PackedFloat32Array)[k - 1]
				var arr: float = (Timetable.run_arr[r] as PackedFloat32Array)[k]
				if arr >= t0 and dep <= t1:
					brute += 1
	check(found.size() == brute, "%s -> %s: oncoming() finds %d trains, a search of every run finds %d" % [na, nb, found.size(), brute])
	check(found.size() > 0, "%s -> %s: there are trains coming the other way in 15 minutes" % [na, nb])
	for f in found:
		check(float(f["arr"]) > float(f["dep"]), "run %d: arrives after it leaves" % int(f["run"]))
	var onc := Oncoming.new()
	add_child(onc)
	onc.setup(path, mirror, ia, ib, t0, t1, dist)
	check(onc.entries.size() > 0, "%s -> %s: the ride has oncoming trains" % [na, nb])
	check(is_equal_approx(onc.lat, RunScenery.TRACK_SPACING * (1.0 if mirror else -1.0)), "the second track is on the platform side (%s)" % ("right" if mirror else "left"))
	# --- each goes from the destination to the origin in its run's time
	var last_s := 1e9
	for e in onc.entries:
		var dep: float = e["info"]["dep"]
		check(absf(onc.s_of(e, dep) - dist) < 0.5, "run %d leaves the destination (s %.1f of %.1f)" % [int(e["info"]["run"]), onc.s_of(e, dep), dist])
		check(absf(onc.s_of(e, dep + float(e["T"]))) < 1.0, "run %d reaches the origin (s %.1f)" % [int(e["info"]["run"]), onc.s_of(e, dep + float(e["T"]))])
		last_s = 1e9
		var mono := true
		for i in 41:
			var sv := onc.s_of(e, dep + float(e["T"]) * float(i) / 40.0)
			if sv > last_s + 0.001:
				mono = false
			last_s = sv
		check(mono, "run %d only ever goes toward the origin" % int(e["info"]["run"]))
	# --- one train passing the camera: where its cars stand
	var tun := TunnelRun.new()
	add_child(tun)
	tun.setup(path, mirror, cam_s)
	var e0: Dictionary = {}
	for e in onc.entries:
		if onc.s_of(e, float(e["info"]["dep"]) + float(e["T"]) * 0.5) < dist:
			e0 = e
			break
	if e0.is_empty():
		check(false, "a train to watch")
		return
	var lo: float = e0["info"]["dep"]
	var hi: float = lo + float(e0["T"])
	for _i in 40:
		var mid := (lo + hi) * 0.5
		if onc.s_of(e0, mid) > cam_s:
			lo = mid
		else:
			hi = mid
	var t_pass := (lo + hi) * 0.5
	var pose_cam := path.pose(cam_s)
	var cell_ok := (path.cell_scene(int(roundf(cam_s / 12.0))) & RunScenery.PAIR) != 0
	check(cell_ok, "%s -> %s: the camera stands where the second track is (cell scene %x)" % [na, nb, path.cell_scene(int(roundf(cam_s / 12.0)))])
	# the rails of the second track as the scenery has them (the mesh of the camera's cell): which side of the path, how far
	var kc := int(roundf(cam_s / 12.0))
	var mi: MeshInstance3D = tun.segs[posmod(kc, TunnelRun.N_SEG)]
	var mesh := mi.mesh as ArrayMesh
	var zsum := 0.0
	var zn := 0
	for si in mesh.get_surface_count():
		if true:
			var vs: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in vs:
				var lz := (pose_cam.affine_inverse() * (mi.global_transform * v)).z
				if absf(lz) > 8.0 and absf(lz) < 18.0 and mesh.surface_get_material(si) == Mats.get_mat("rail"):
					zsum += lz
					zn += 1
	check(zn > 0, "%s -> %s: the scenery has rails of a second track" % [na, nb])
	if zn > 0:
		var zmean := zsum / float(zn)
		check(signf(zmean) == signf(onc.lat) and absf(absf(zmean) - RunScenery.TRACK_SPACING) < 1.5, "the trains run on the side the scenery has the second track (rails at %.1f m, trains at %.1f m)" % [zmean, onc.lat])
	var worst_lat := 0.0
	var worst_dir := -1.0
	var shown_max := 0
	var build_ms := 0.0
	for off: float in [-13.0, -3.0, -1.5, 0.0, 1.5, 3.0]:
		for _i in 10:
			Clock.now = t_pass + off
			var tb := Time.get_ticks_usec()
			onc.update(cam_s, Clock.now, Transform3D.IDENTITY, 18.0)
			build_ms = maxf(build_ms, float(Time.get_ticks_usec() - tb) / 1000.0)
			await get_tree().process_frame
		Clock.now = t_pass + off
		onc.update(cam_s, Clock.now, Transform3D.IDENTITY, 18.0)
		shown_max = maxi(shown_max, onc.shown)
		if off <= -12.0:
			check(not bool(e0["heard"]), "the train is not heard yet %.0f s before it passes" % -off)
		if off >= -1.5:
			check(bool(e0["heard"]), "the train is heard by the time it is level (%.1f s)" % off)
		var tr := e0["train"] as Train
		if tr == null:
			check(false, "the train is built by the time it is near")
			continue
		var s_mid: float = onc.s_of(e0, Clock.now)
		if absf(s_mid - cam_s) > Oncoming.VIEW + float(e0["len"]) * 0.5 + 1.0:
			check(not tr.visible, "a train %.0f m away is not drawn" % absf(s_mid - cam_s))
			continue
		for i in tr.cars.size():
			var car := tr.cars[i] as Node3D
			var sc := s_mid - float(tr.car_x[i])
			var want_vis := absf(sc - cam_s) < Oncoming.VIEW + 10.0 and (path.cell_scene(int(roundf(sc / 12.0))) & RunScenery.PAIR) != 0
			check(car.visible == want_vis or not tr.visible, "car %d at s %.0f: shown %s, should be %s" % [i, sc, str(car.visible), str(want_vis)])
			if not car.visible:
				continue
			var p := path.pose(sc)
			var local := p.affine_inverse() * car.global_position
			# a car stands on the second track (a bend moves the middle of a long car off the chord by a few centimetres)
			worst_lat = maxf(worst_lat, absf(local.z - onc.lat))
			check(absf(local.y - (PlatformModule.RAIL_Y)) < 0.9, "car %d stands at rail level (y %.2f)" % [i, local.y])
			var fwd := car.global_transform.basis.x * (-1.0 if i == tr.cars.size() - 1 else 1.0)
			worst_dir = maxf(worst_dir, fwd.dot(p.basis.x))
	check(worst_lat < 0.4, "the cars stand on the second track (worst %.2f m off)" % worst_lat)
	check(worst_dir < -0.95, "the cars face the other way (worst heading dot %.2f)" % worst_dir)
	check(shown_max > 0, "the train is in view as it passes")
	var tu := Time.get_ticks_usec()
	for _i in 200:
		onc.update(cam_s, Clock.now, Transform3D.IDENTITY)
	var steady_us := float(Time.get_ticks_usec() - tu) / 200.0
	print("  info: %s -> %s: %d trains, update takes up to %.1f ms (with the build of a train), %.0f us a frame once built" % [na, nb, onc.entries.size(), build_ms, steady_us])
	check(steady_us < 2000.0, "placing a train costs under 2 ms a frame (%.0f us)" % steady_us)
	# --- the hand-over: a train in view when the scenery takes over stays out, one far ahead comes
	var onc2 := Oncoming.new()
	add_child(onc2)
	onc2.setup(path, mirror, ia, ib, t0, t1, dist)
	var e_in: Dictionary = {}
	var e_far: Dictionary = {}
	var tn := t_pass - 3.0
	for e in onc2.entries:
		var sm := onc2.s_of(e, tn)
		var tau := tn - float(e["info"]["dep"])
		if tau >= 0.0 and tau <= float(e["T"]):
			if sm - float(e["len"]) * 0.5 < cam_s + Oncoming.NEAR_WINDOW and sm > cam_s - 200.0:
				e_in = e
			elif sm > cam_s + Oncoming.NEAR_WINDOW + float(e["len"]):
				e_far = e
	onc2.begin(cam_s, tn)
	if not e_in.is_empty():
		check(bool(e_in["skip"]), "a train within %.0f m of the player at the hand-over is left out" % Oncoming.NEAR_WINDOW)
	else:
		check(false, "a train near the player at the hand-over (test set-up)")
	for e in onc2.entries:
		if not bool(e["skip"]):
			var tau2 := tn - float(e["info"]["dep"])
			check(tau2 < float(e["T"]), "a train that has already arrived is left out")
	onc.queue_free()
	onc2.queue_free()
	tun.queue_free()
	await get_tree().process_frame
