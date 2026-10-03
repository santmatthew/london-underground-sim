extends Node3D
## A curved platform (Bank, Central line): the module is bent (PlatformCurve), the trains' cars follow the arc with a sensible gap to the platform edge, the floor, the edge guard and the walls are where the
## shell is, the crowd stands on the platform, and design space <-> the curved world round-trips. Prints failures and OK. args --station=Bank --pid=central:Eastbound
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func half_w_of(t: Train) -> float:
	return 1.31 if t.kind == "deep" else 1.5


func run():
	var nm := "Bank"
	var want := "central:Eastbound"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): nm = a.substr(10)
		if a.begins_with("--pid="): want = a.substr(6)
	Timetable.build(9)
	Clock.set_time(8.0 * 3600.0)
	var idx: int = Net.name_to_idx[nm]
	var plan := StationPlan.for_station(idx)
	add_child(Env.make(0))
	var st := Station.new()
	add_child(st)
	st.build(plan)
	await get_tree().process_frame
	# the face
	var fk := ""
	for k in plan.faces:
		if String(k).begins_with(want):
			fk = k
	check(fk != "", "the face %s exists" % want)
	if fk == "":
		print("FAILED")
		return
	var f: Dictionary = plan.faces[fk]
	var pm: PlatformModule = st.modules[f["module"]]
	check(pm.bend != null and st.has_bend, "the module is curved (%s)" % str(plan.modules[f["module"]].get("bend", {})))
	if pm.bend == null:
		print("FAILED")
		return
	var b: Bend = pm.bend
	# design <-> world round trip over the platform
	var worst := 0.0
	for x in range(-60, 75, 7):
		for z in [-4.0, 0.0, 3.0, 6.4]:
			var p := Vector3(float(pm.position.x) + x, float(f["y"]) + 0.5, float(pm.position.z) + z)
			worst = maxf(worst, st.to_design(st.to_phys(p)).distance_to(p))
	check(worst < 0.01, "design -> world -> design round trip (%.4f m)" % worst)
	# the floor: a ray down at points along the platform finds the slab at platform level; the edge guard and the far wall are there too
	var space := get_world_3d().direct_space_state
	var bad_floor := 0
	var bad_edge := 0
	var bad_wall := 0
	var side: float = f["side"]
	var ez: float = f["edge_z"] - pm.position.z
	var x2 := float(f["x0"]) - pm.position.x + 3.0
	while x2 < float(f["x1"]) - pm.position.x - 2.0:
		var c := st.to_global(st.to_phys(pm.position + Vector3(x2, 1.2, ez - side * 1.4)))
		var q := PhysicsRayQueryParameters3D.create(c, c + Vector3(0, -3.0, 0))
		q.collision_mask = 1
		var h := space.intersect_ray(q)
		if h.is_empty() or absf(float(h["position"].y) - (float(f["y"]) + st.global_position.y)) > 0.1:
			bad_floor += 1
		# across the edge toward the track: the edge guard (layer 3) stops the player (three rays a hand apart: a thin ray can slip through the corner where two rotated boxes meet)
		var e0 := st.to_global(st.to_phys(pm.position + Vector3(x2, 0.9, ez - side * 0.8)))
		var hits := 0
		for dxe in [-0.3, 0.0, 0.3]:
			var ea := st.to_global(st.to_phys(pm.position + Vector3(x2 + dxe, 0.9, ez - side * 0.8)))
			var eb := st.to_global(st.to_phys(pm.position + Vector3(x2 + dxe, 0.9, ez + side * 1.4)))
			var qe := PhysicsRayQueryParameters3D.create(ea, eb)
			qe.collision_mask = 1 << 2
			if not space.intersect_ray(qe).is_empty():
				hits += 1
		if hits < 2:
			bad_edge += 1
		# toward the wall behind the platform: solid within a couple of metres
		var w1 := st.to_global(st.to_phys(pm.position + Vector3(x2, 1.2, ez - side * 3.6)))
		var qw := PhysicsRayQueryParameters3D.create(e0 + Vector3(0, 0.3, 0), w1)
		qw.collision_mask = 1
		var wall_open := false
		if not pm.box and x2 > float(plan.modules[f["module"]]["spec"]["spine_x1"]) + 4.0:       # (an island box hall has no wall behind its platforms)
			wall_open = space.intersect_ray(qw).is_empty()
		if wall_open:
			bad_wall += 1
		x2 += 6.0
	check(bad_floor == 0, "the platform floor is there along the curve (%d gaps)" % bad_floor)
	check(bad_edge == 0, "the edge guard follows the curve (%d gaps)" % bad_edge)
	check(bad_wall == 0, "the wall behind the platform is solid (%d gaps)" % bad_wall)
	# a train at the platform: cars on the arc, a sensible gap everywhere
	var gp: int = Timetable.plat_index[idx][f["pid"]]
	var pick: Dictionary = {}
	for vv in Timetable.visits_between(gp, 8.0 * 3600.0, 8.0 * 3600.0 + 900.0):
		if (Timetable.run_face[vv["run"]] as PackedByteArray)[vv["k"]] == f["face_no"] and not vv["origin"] and not vv["final"]:
			pick = vv
			break
	check(not pick.is_empty(), "a train calls at the platform")
	if not pick.is_empty():
		Clock.set_time(float(pick["arr"]) + 12.0)
		Clock.running = false
		st.trains.setup(st, null)
		st.trains._process(0.6)
		st.trains._process(0.1)
		var train: Train = null
		for vk in st.trains.visits:
			if st.trains.visits[vk]["key"] == fk:
				train = st.trains.visits[vk]["train"]
		check(train != null and train.bend != null, "the train knows the platform is curved")
		await get_tree().process_frame
		if train != null:
			var side_t: float = f["side"]
			var min_gap := 9.0
			var max_gap := -9.0
			var off_track := 0.0
			for i in train.cars.size():
				var car := train.cars[i] as Node3D
				# the car's middle lies on or just inside the track; the door sill is the platform-side face
				var lc := st.to_local(car.global_position)
				var d := b.unmap(lc - pm.position)
				off_track = maxf(off_track, absf(d.z - float(train.track_z)))
				for dx in [-5.0, 0.0, 5.0]:
					var sill := st.to_local(car.to_global(Vector3(dx, 0.0, (-1.0 if i == train.cars.size() - 1 else 1.0) * (1.0 if train.door_side == "R" else -1.0) * (1.31 if train.kind == "deep" else 1.5))))
					var ds := b.unmap(sill - pm.position)
					var gap := absf(float(f["edge_z"]) - pm.position.z - ds.z) * 1.0
					# the sill is the platform side of the car: its distance from the platform edge (the edge is nearer the platform, the sill nearer the track)
					var signed := side_t * (ds.z - (float(f["edge_z"]) - pm.position.z))
					min_gap = minf(min_gap, signed)
					max_gap = maxf(max_gap, signed)
					gap = gap
			check(off_track < 0.35, "the cars stand on the track (worst %.2f m off the centre line)" % off_track)
			check(min_gap > 0.03 and max_gap < 0.7, "the gap to the platform edge stays between %.2f and %.2f m" % [min_gap, max_gap])
			print("  info: gap between the door sills and the platform edge %.2f .. %.2f m, cars at most %.2f m off the track centre line" % [min_gap, max_gap, off_track])
			# the doors are open: nothing of the edge guard may stand in front of any door (a rail the player cannot step across), whatever the bend
			st.trains._process(0.1)
			for i in 3:
				await get_tree().physics_frame
			var local_side := train.platform_side * (1.0 if train.facing > 0 else -1.0)
			var blocked := 0
			var doors_n := 0
			for dx in train.door_positions():
				doors_n += 1
				var pa: Vector3 = train.slot_global(float(dx), 0.9, local_side * (half_w_of(train) + 1.4))
				var pb: Vector3 = train.slot_global(float(dx), 0.9, local_side * (half_w_of(train) - 0.8))
				var qd := PhysicsRayQueryParameters3D.create(pa, pb)
				qd.collision_mask = 1 << 2
				if not space.intersect_ray(qd).is_empty():
					blocked += 1
			check(train.doors_open and blocked == 0, "every open door is clear of the edge guard (%d of %d doors blocked, doors open: %s)" % [blocked, doors_n, str(train.doors_open)])
			var aboard_mid := train.contains_world_point(train.cars[3].global_position + Vector3(0, 1.2, 0))
			check(aboard_mid, "a point inside the middle of a car is aboard")
			var far_ok := true
			for i in train.cars.size():
				if not train.contains_world_point((train.cars[i] as Node3D).global_position + Vector3(0, 1.2, 0)):
					far_ok = false
			check(far_ok, "every car's middle counts as aboard")
	# the crowd stands on the platform
	st.attach_crowd(null)
	st.crowd.density = 1.5
	for i in 360:
		await get_tree().process_frame
	var waiting := 0
	var off := 0.0
	for a in st.crowd.agents:
		if a.state == "wait" and a.node != null and plan.faces[a.face_key]["module"] == f["module"]:
			waiting += 1
			off = maxf(off, st.to_design(a.node.position).distance_to(a.pos))
	check(off < 0.05, "the waiting people stand where the plan puts them (%d people, worst %.3f m)" % [waiting, off])
	print("OK" if ok else "FAILED")
