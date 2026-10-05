extends Node3D
## The footbridges over the side platforms of the Elizabeth line and of the Underground's generated stations (Footbridge, StationPlan._add_footbridges): which stations get one (those whose OpenStreetMap data maps a footbridge, nothing where it does
## not, nothing at an island), that they lie inside the platform and clear of the way in, that the canopy is cut where they stand, and - on the real built station, with the player's capsule - that one
## can walk from one platform up the steps, over the deck and down to the other, and that the parapets and the edge of the deck stop the player.
const RADIUS := 0.26
const HEIGHT := 1.76
const LIFT := 0.10
var ok := true
var _space: PhysicsDirectSpaceState3D
var _shape := CapsuleShape3D.new()


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	Timetable.build(1)
	Clock.set_time(11.0 * 3600.0)
	add_child(Env.make(0))
	_shape.radius = RADIUS
	_shape.height = HEIGHT
	_plans()
	for nm in ["West Ealing", "Slough", "Southall", "Buckhurst Hill", "Harlesden"]:
		await _walk(nm)
	await _graph("West Ealing", false)
	await _graph("Slough", true)          # (built for step-free journeys: the lifts are there)
	print("OK" if ok else "FAILED")


func _plans() -> void:
	var with_data := 0
	var drawn := 0
	var ug_with := 0
	var ug_drawn := 0
	for i in Net.stations.size():
		var sid: String = Net.station_ids[i]
		var groups := {}
		for pid in Net.stations[i]["platforms"]:
			groups[String(Net.stations[i]["platforms"][pid]["group"])] = true
		for g in groups:
			var el: Dictionary = RealData.platform_layout(sid, g)
			if el.is_empty():
				continue
			var plan := StationPlan.for_station(i)
			var nm: String = "%s (%s)" % [Net.stations[i]["name"], g]
			var fbs: Array = []
			for m in plan.modules:
				if String(m["group"]) == g:
					fbs.append_array((m["spec"] as Dictionary).get("footbridges", []))
			if not StationPlan.is_split(sid, g):
				check(fbs.is_empty(), "%s (not a pair of side platforms) has no footbridge" % nm)
				continue
			var want: Array = el.get("footbridges", [])
			if want.is_empty():
				check(fbs.is_empty(), "%s: no footbridge in the data, none drawn" % nm)
				continue
			with_data += 1
			var ug: bool = g != "elizabeth"
			if ug:
				ug_with += 1
			check(not fbs.is_empty(), "%s: the data maps a footbridge, one is drawn" % nm)
			if fbs.is_empty():
				continue
			drawn += 1
			if ug:
				ug_drawn += 1
			var ma: Dictionary = {}
			for m in plan.modules:
				if String(m["group"]) == g and (m["spec"] as Dictionary).has("footbridges"):
					ma = m
			var L: float = ma["spec"]["length"]
			var cuts: Array = ma["spec"]["cuts"]
			var prev := Vector2(-1e9, -1e9)
			for f in fbs:
				var fp := Footbridge.footprint(float(f["x"]), float(f["d"]))
				var west_lim := -L * 0.5
				for ox in (ma["spec"]["openings_x"] as Array):
					west_lim = maxf(west_lim, float(ox) + 4.0)
				check(fp.x >= west_lim - 0.01 and fp.y <= L * 0.5 - 2.9, "%s: the bridge at x %.0f (%.0f .. %.0f) lies inside the platform, clear of the way in (from %.0f)" % [nm, float(f["x"]), fp.x, fp.y, west_lim])
				check(fp.x > prev.y, "%s: two bridges do not overlap" % nm)
				prev = fp
				var cut_ok := false
				for c in cuts:
					if float(c[0]) <= fp.x and float(c[1]) >= fp.y:
						cut_ok = true
				check(cut_ok, "%s: the canopy is cut over the bridge at x %.0f" % [nm, float(f["x"])])
			for m in plan.modules:
				if bool((m["spec"] as Dictionary).get("split", false)) and String(m["group"]) == g:
					check(((m["spec"] as Dictionary).get("cuts", []) as Array).size() == cuts.size(), "%s: both modules of the pair have the cuts" % nm)
	check(with_data >= 12 and drawn == with_data, "footbridges are drawn at %d of %d stations whose data has one" % [drawn, with_data])
	check(ug_with >= 8 and ug_drawn == ug_with, "... and at %d of %d Underground ones" % [ug_drawn, ug_with])


func _walk(nm: String) -> void:
	var idx: int = Net.name_to_idx[nm]
	var plan := StationPlan.for_station(idx)
	var ia := -1
	var ib := -1
	for mi in plan.modules.size():
		if (plan.modules[mi]["spec"] as Dictionary).has("footbridges"):
			ia = mi
		else:
			ib = mi
	check(ia >= 0 and ib >= 0, "%s: a module carries the bridge" % nm)
	if ia < 0 or ib < 0:
		return
	var st := Station.new()
	add_child(st)
	st.build(plan)
	for i in 3:
		await get_tree().physics_frame
	_space = get_world_3d().direct_space_state
	var ma: Dictionary = plan.modules[ia]
	var mb: Dictionary = plan.modules[ib]
	var pa: Vector3 = ma["pos"]
	var pb: Vector3 = mb["pos"]
	var bi := 0
	for f in (ma["spec"]["footbridges"] as Array):
		bi += 1
		var xb: float = f["x"]
		var d: float = f["d"]
		var za: float = f["za"]
		var zb: float = f["zb"]
		var Y := Footbridge.DECK_Y
		var hw := Footbridge.HW
		var foot := hw + Footbridge.RUN + 0.5          # (the plan's own foot nodes: the canopy is cut round them, a column would be a metre away anywhere else)
		var xa := pa.x + xb
		var route: Array = [
			Vector3(xa + d * foot, pa.y, pa.z + 3.9),
			Vector3(xa + d * foot, pa.y, pa.z + za),
			Vector3(xa + d * (hw + 0.2), pa.y + Y, pa.z + za),
			Vector3(xa, pa.y + Y, pa.z + za),
			Vector3(xa, pa.y + Y, pa.z + (zb + za) * 0.5),
			Vector3(xa, pa.y + Y, pa.z + zb),
			Vector3(xa + d * (hw + 0.2), pa.y + Y, pa.z + zb),
			Vector3(xa + d * foot, pa.y, pa.z + zb),
			Vector3(xa + d * foot, pa.y, pb.z - 3.9),
		]
		var err := _sweep(route, 0.3)
		check(err == "", "%s, bridge %d: the way from one platform to the other is free (%s)" % [nm, bi, err])
		var back := route.duplicate()
		back.reverse()
		err = _sweep(back, 0.3)
		check(err == "", "%s, bridge %d: ... and back (%s)" % [nm, bi, err])
		if bi == 1:
			err = await _player_walk(route, pa.y)
			check(err == "", "%s, bridge %d: the real player walks it, from one platform to the other (%s)" % [nm, bi, err])
		# what must stop the player: the parapets of the steps (platform side and back side), the side of the deck, the edge of the landing, the plinth
		var u_mid := hw + Footbridge.RUN * 0.5
		var y_mid := pa.y + Footbridge.line_y(u_mid)
		for blocked in [
				["a parapet of the steps (platform side)", Vector3(xa + d * u_mid, y_mid, pa.z + za + hw - 0.1)],
				["a parapet of the steps (back side)", Vector3(xa + d * u_mid, y_mid, pa.z + za - hw + 0.1)],
				["the glazed side of the deck", Vector3(xa + hw - 0.1, pa.y + Y, pa.z + (za + zb) * 0.5)],
				["the other side of the deck", Vector3(xa - hw + 0.1, pa.y + Y, pa.z + (za + zb) * 0.5)],
				["the end wall of the landing", Vector3(xa, pa.y + Y, pa.z + za - hw + 0.1)],
				["the plinth under the landing", Vector3(xa, pa.y + 1.0, pa.z + za)],
			]:
			check(not _free(blocked[1] as Vector3), "%s, bridge %d: %s stops the player" % [nm, bi, blocked[0]])
		# the stretch of track under the deck is open (a train runs there): nothing solid between the platforms below the slab
		check(_free(Vector3(xa, pa.y + 0.9, pa.z + 8.2)), "%s, bridge %d: nothing solid on the track under the deck" % [nm, bi])
		# the canopy is cut where the bridge stands
		var pm: PlatformModule = st.modules[ia]
		var fp := Footbridge.footprint(xb, d)
		for sp in pm.roof_spans:
			check(not ((sp as Vector2).x < fp.y and (sp as Vector2).y > fp.x and (sp as Vector2).y - (sp as Vector2).x > 0.5), "%s, bridge %d: no roof over the bridge's footprint (span %s)" % [nm, bi, str(sp)])
	st.queue_free()
	await get_tree().process_frame


## the real Player (bot mode) walks the route, waypoint by waypoint; "" when it gets to the end on its feet
func _player_walk(route: Array, y_floor: float) -> String:
	var player := Player.new()
	add_child(player)
	player.bot_active = true
	player.enabled = true
	player.global_position = (route[0] as Vector3) + Vector3(0, 0.05, 0)
	for i in 10:
		await get_tree().physics_frame
	var err := ""
	var max_y := y_floor
	for k in range(1, route.size()):
		var wp: Vector3 = route[k]
		var frames := 0
		while err == "":
			var to := wp - player.global_position
			to.y = 0.0
			if to.length() < 0.3:
				break
			player.face(to.normalized())
			player.bot_move = Vector2(0, -1)
			await get_tree().physics_frame
			frames += 1
			max_y = maxf(max_y, player.global_position.y)
			if player.global_position.y < y_floor - 0.7:
				err = "fell to y %.2f near waypoint %d" % [player.global_position.y, k]
			elif frames > 900:
				err = "stuck near waypoint %d at (%.1f, %.2f, %.1f)" % [k, player.global_position.x, player.global_position.y, player.global_position.z]
		if err != "":
			break
	player.bot_move = Vector2.ZERO
	if err == "" and max_y < y_floor + Footbridge.DECK_Y - 0.5:
		err = "never got up to the deck (highest y %.2f)" % max_y
	if err == "" and absf(player.global_position.y - y_floor) > 0.3:
		err = "ended at y %.2f, not on the platform" % player.global_position.y
	player.queue_free()
	return err


## is the capsule standing with its feet at `p` clear of everything solid?
func _free(p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.collision_mask = 1 | 4
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, LIFT + HEIGHT * 0.5, 0))
	return _space.intersect_shape(q, 4).is_empty()


func _sweep(pts: Array, step: float) -> String:
	var y_prev := NAN
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var n := maxi(1, int(ceil(Vector2(b.x - a.x, b.z - a.z).length() / step)))
		for k in range(0 if i == 0 else 1, n + 1):
			var t := float(k) / n
			var p := a.lerp(b, t)
			var fy := _floor(p.x, p.z, (a.y + 1.5) if is_nan(y_prev) else (y_prev + 0.7), 3.0 if is_nan(y_prev) else 1.6)
			if is_nan(fy):
				return "no floor at (%.1f, %.1f)" % [p.x, p.z]
			if not is_nan(y_prev) and absf(fy - y_prev) > step * 0.6 + 0.12:
				return "floor jumps %.2f m at (%.1f, %.1f)" % [fy - y_prev, p.x, p.z]
			if not _free(Vector3(p.x, fy, p.z)):
				return "blocked at (%.1f, %.2f, %.1f)" % [p.x, fy, p.z]
			y_prev = fy
	return ""


func _floor(x: float, z: float, from_y: float, depth: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, from_y - depth, z))
	q.collision_mask = 1
	var h := _space.intersect_ray(q)
	return NAN if h.is_empty() else (h["position"] as Vector3).y


## the footbridge in the plan's walking graph: paths over it, through its lifts in the step-free graph, the plan's own waypoints (ramps, lift segments) swept with the capsule, the lift doors
func _graph(nm: String, step_free: bool) -> void:
	StationPlan.step_free_mode = step_free
	StationPlan.lifts_enabled = true
	var idx: int = Net.name_to_idx[nm]
	var plan := StationPlan.for_station(idx)
	check(not plan.bridges.is_empty(), "%s: the plan has its footbridges' graph" % nm)
	if plan.bridges.is_empty():
		StationPlan.step_free_mode = false
		return
	var st := Station.new()
	add_child(st)
	st.build(plan)
	for i in 3:
		await get_tree().physics_frame
	_space = get_world_3d().direct_space_state
	for br in plan.bridges:
		var k: int = br["k"]
		var fa: String = "face:" + String((br["flights"][0] as Dictionary)["face"])
		var fb: String = "face:" + String((br["flights"][1] as Dictionary)["face"])
		var by_stairs: Array = ["fb%d_a_pf" % k, "fb%d_a_foot" % k, "fb%d_a_top" % k, "fb%d_b_top" % k, "fb%d_b_foot" % k, "fb%d_b_pf" % k]
		for rev in ([] if step_free else [false, true]):          # (a step-free journey has the steps closed with barriers: only the lifts are walked)
			var names: Array = [fa] + by_stairs + [fb]
			if rev:
				names.reverse()
			var err := _plan_route(plan, st, names)
			check(err == "", "%s, bridge %d: the steps route %s is free (%s)" % [nm, k, "back" if rev else "across", err])
			if k == 0:
				# the real player follows the plan's waypoints, as the autopilot does: it must get from one platform to the other, over the deck
				var pts: Array = []
				for w in plan.walk_points(names, 0):
					pts.append(st.to_global(w["pos"] as Vector3))
				var base_y: float = (pts[0] as Vector3).y
				var err3 := await _player_walk(pts, base_y)
				check(err3 == "", "%s, bridge %d: the real player walks the plan's route %s (%s)" % [nm, k, "back" if rev else "across", err3])
		# the planner finds its way over the bridge or the passages, and the lifts when the steps are closed
		var p := plan.path(fa, fb, false, false)
		check(not p.is_empty(), "%s, bridge %d: a path between the platforms" % [nm, k])
		var psf := plan.path(fa, fb, true, true)
		var uses_foot := false
		for n in psf:
			if String(n).ends_with("_foot"):
				uses_foot = true
		check(not psf.is_empty() and not uses_foot, "%s, bridge %d: the step-free path between the platforms has no steps of the bridge (%d nodes)" % [nm, k, psf.size()])
		# the lifts: a route through both of them, door to door
		var lift_names: Array = [fa, "fb%d_a_pf" % k, "fb%d_a_lf" % k, "lift%d_bot" % (100 + 2 * k), "lift%d_top" % (100 + 2 * k), "fb%d_a_top" % k, "fb%d_b_top" % k, "lift%d_top" % (101 + 2 * k), "lift%d_bot" % (101 + 2 * k), "fb%d_b_lf" % k, "fb%d_b_pf" % k, fb]
		var err2 := _plan_route(plan, st, lift_names)
		check(err2 == "", "%s, bridge %d: the route through the two lifts is free (%s)" % [nm, k, err2])
		# the lifts' doors: anchors where the plan says, in front of a door, clear, each pointing at the other
		if st.has_lifts():
			for f in 2:
				var eid := 100 + 2 * k + f
				var lf: Dictionary = plan.lift_of(eid)
				check(not lf.is_empty(), "%s: the lift %d is in the plan" % [nm, eid])
				var seen := 0
				for dnode in st.lift_doors:
					if int(dnode.get_meta("lift")) != eid:
						continue
					seen += 1
					var end: String = dnode.get_meta("end")
					var front: Vector3 = lf["top" if end == "top" else "bot"]["front"]
					check(dnode.position.distance_to(front) < 0.01, "%s: lift %d %s: its anchor stands where the plan puts the door front" % [nm, eid, end])
					check(_free(st.to_global(front)), "%s: lift %d %s: nobody stands inside something at its door front" % [nm, eid, end])
					var other: Vector3 = lf["bot" if end == "top" else "top"]["front"]
					check((dnode.get_meta("to") as Vector3).distance_to(other) < 0.01, "%s: lift %d %s: it leads to the other door" % [nm, eid, end])
				check(seen == 2, "%s: lift %d has both its doors (%d)" % [nm, eid, seen])
		# step-free journeys close the steps with a barrier at each end of each flight
		if step_free:
			var barriers := 0
			for c in st.fitting_root.get_children():
				if String(c.name).begins_with("BridgeBarrier%d_" % k):
					barriers += 1
			check(barriers == 4, "%s, bridge %d: a step-free journey has a barrier across each end of both flights (%d)" % [nm, k, barriers])
	st.queue_free()
	await get_tree().process_frame
	StationPlan.step_free_mode = false


## the plan's own way along `names` (every stretch between lifts on its own, as the route audit does): sweeps each with the capsule; "" when all is free
func _plan_route(plan: StationPlan, st: Station, names: Array) -> String:
	for seg in plan.path_segments(names):
		var pts: Array = []
		for w in plan.walk_points(seg, 0):
			pts.append(st.to_global((w["pos"] as Vector3)))
		if pts.size() < 2:
			continue
		var err := _sweep(pts, 0.3)
		if err != "":
			return err
	return ""
