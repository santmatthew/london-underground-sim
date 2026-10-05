extends Node3D
## The footbridges over the Elizabeth line's side platforms (Footbridge, StationPlan._add_footbridges): which stations get one (those whose OpenStreetMap data maps a footbridge, nothing where it does
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
	for nm in ["West Ealing", "Slough", "Southall"]:
		await _walk(nm)
	print("OK" if ok else "FAILED")


func _plans() -> void:
	var with_data := 0
	var drawn := 0
	for i in Net.stations.size():
		var sid: String = Net.station_ids[i]
		var el: Dictionary = RealData.el_platforms(sid)
		if el.is_empty():
			continue
		var plan := StationPlan.for_station(i)
		var nm: String = Net.stations[i]["name"]
		var fbs: Array = []
		for m in plan.modules:
			fbs.append_array((m["spec"] as Dictionary).get("footbridges", []))
		if not StationPlan.is_split(sid):
			check(fbs.is_empty(), "%s (not a pair of side platforms) has no footbridge" % nm)
			continue
		var want: Array = el.get("footbridges", [])
		if want.is_empty():
			check(fbs.is_empty(), "%s: no footbridge in the data, none drawn" % nm)
			continue
		with_data += 1
		check(not fbs.is_empty(), "%s: the data maps a footbridge, one is drawn" % nm)
		if fbs.is_empty():
			continue
		drawn += 1
		var ma: Dictionary = plan.modules[0] if (plan.modules[0]["spec"] as Dictionary).has("footbridges") else plan.modules[1]
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
			check(((m["spec"] as Dictionary).get("cuts", []) as Array).size() == cuts.size(), "%s: both modules have the cuts" % nm)
	check(with_data >= 12 and drawn == with_data, "footbridges are drawn at %d of %d stations whose data has one" % [drawn, with_data])


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
		var foot := hw + Footbridge.RUN + 1.2
		var xa := pa.x + xb
		var route: Array = [
			Vector3(xa + d * (foot + 2.0), pa.y, pa.z + 2.8),
			Vector3(xa + d * foot, pa.y, pa.z + za),
			Vector3(xa + d * (hw + 0.2), pa.y + Y, pa.z + za),
			Vector3(xa, pa.y + Y, pa.z + za),
			Vector3(xa, pa.y + Y, pa.z + (zb + za) * 0.5),
			Vector3(xa, pa.y + Y, pa.z + zb),
			Vector3(xa + d * (hw + 0.2), pa.y + Y, pa.z + zb),
			Vector3(xa + d * foot, pa.y, pa.z + zb),
			Vector3(xa + d * (foot + 2.0), pa.y, pb.z - 3.0),
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
