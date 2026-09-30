extends Node3D
## Is there always a free path? For every station, every route a passenger can take - each street door -> each platform face (through the gates),
## each face -> each street door, and each face -> every other face (interchange) - is walked as a polyline of the plan's own waypoints with the
## real player capsule swept along it in small steps (gates opened, crowd off). It fails at the first place where there is no floor to stand on
## (a hole, a missing ramp) or where something solid is in the way (a wall, a shaft, a column). Static, so it is quick enough for all 272 stations.
## args: --stations="Victoria|Bank"  |  --range=0,40 (station indices)  |  --all      --step=0.3  --verbose  --faces-only (skip interchange)
const RADIUS := 0.26
const HEIGHT := 1.76
const LIFT := 0.10

var _space: PhysicsDirectSpaceState3D
var _shape := CapsuleShape3D.new()


func run():
	var names: Array = []
	var i0 := -1
	var i1 := -1
	var step := 0.3
	var verbose := false
	var faces_only := false
	var all := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stations="): names = a.substr(11).split("|")
		if a.begins_with("--range="):
			var c := a.substr(8).split(",")
			i0 = int(c[0])
			i1 = int(c[1])
		if a == "--all": all = true
		if a.begins_with("--step="): step = float(a.substr(7))
		if a == "--verbose": verbose = true
		if a == "--faces-only": faces_only = true
	Timetable.build(1)
	Clock.set_time(11.0 * 3600.0)
	add_child(Env.make(0))
	_shape.radius = RADIUS
	_shape.height = HEIGHT
	var idxs: Array = []
	if not names.is_empty():
		for n in names:
			idxs.append(Net.name_to_idx[n])
	else:
		var lo := 0 if (all or i0 < 0) else i0
		var hi: int = Net.station_ids.size() - 1 if (all or i1 < 0) else i1
		for i in range(lo, hi + 1):
			idxs.append(i)
	var total_routes := 0
	var total_fail := 0
	var bad_stations := 0
	for idx in idxs:
		var r := await _audit_station(idx, step, verbose, faces_only)
		total_routes += r[0]
		total_fail += r[1]
		if r[1] > 0:
			bad_stations += 1
	print("TOTAL: %d stations, %d routes, %d failed (%d stations with failures)" % [idxs.size(), total_routes, total_fail, bad_stations])


func _audit_station(idx: int, step: float, verbose: bool, faces_only: bool) -> Array:
	var plan := StationPlan.for_station(idx)
	var st := Station.new()
	add_child(st)
	st.build(plan)
	for gd in st.gate_nodes:
		(gd["flaps"] as StaticBody3D).collision_layer = 0          # the gates open for a passenger
	for i in 3: await get_tree().physics_frame
	_space = get_world_3d().direct_space_state
	var routes: Array = []      # [label, node names, start point (or null), end point (or null)]
	var fkeys: Array = plan.faces.keys()
	for sd in plan.street_doors:
		for fk in fkeys:
			routes.append(["%s -> %s" % [sd["id"], fk], plan.path(sd["id"], "face:" + fk), null, "face:" + fk])
			routes.append(["%s -> %s" % [fk, sd["id"]], plan.path("face:" + fk, sd["id"]), "face:" + fk, null])
	if not faces_only:
		for fa in fkeys:
			for fb in fkeys:
				if fa != fb:
					routes.append(["%s -> %s" % [fa, fb], plan.path("face:" + fa, "face:" + fb), "face:" + fa, "face:" + fb])
	# the places a journey can start: the spot itself must be free ground, and from it every street door and every platform must be reachable
	for sp in plan.start_spots:
		var spos: Vector3 = sp["pos"]
		routes.append(["spot '%s' (%s)" % [sp["name"], str(spos.snapped(Vector3(0.1, 0.1, 0.1)))], [String(sp["node"])], spos, null])
		for sd in plan.street_doors:
			routes.append(["spot '%s' -> %s" % [sp["name"], sd["id"]], plan.path(String(sp["node"]), sd["id"]), spos, null])
		for fk in fkeys:
			routes.append(["spot '%s' -> %s" % [sp["name"], fk], plan.path(String(sp["node"]), "face:" + fk), spos, "face:" + fk])
	var fails := 0
	var lines: Array = []
	# a platform tunnel that stops short of the rooms must still be long enough to hold the player's car at a ride hand-over
	for m in plan.modules:
		var tw: float = (m["spec"] as Dictionary).get("tun_w", PlatformModule.TUNNEL_EXT)
		if tw < PlatformModule.TUNNEL_MIN + 4.0:
			fails += 1
			lines.append("   FAIL  module %s: west tunnel only %.1f m" % [str(m["group"]), tw])
	for r in routes:
		var names: Array = r[1]
		if names.is_empty():
			fails += 1
			lines.append("   NO PATH  %s" % r[0])
			continue
		var wps: Array = plan.walk_points(names, 0)
		var pts: Array = []
		if r[2] is Vector3:
			pts.append(r[2])
		elif r[2] != null:
			pts.append(st.platform_point(String(r[2]).substr(5), 0.5, 1.4))
		for w in wps:
			pts.append(w["pos"])
		if r[3] != null:
			pts.append(st.platform_point(String(r[3]).substr(5), 0.5, 1.4))
		var err := _sweep(st, pts, step)
		if err != "":
			fails += 1
			lines.append("   FAIL  %s : %s" % [r[0], err])
	var name_s := plan.name + (" [authored]" if plan.authored else "")
	if fails > 0 or verbose:
		print("== %s: %d routes, %d failed" % [name_s, routes.size(), fails])
		for l in lines:
			print(l)
	st.queue_free()
	await get_tree().process_frame
	return [routes.size(), fails]


## walk the polyline with the capsule; "" = free, else what went wrong first
func _sweep(st: Station, pts: Array, step: float) -> String:
	var y_prev := NAN
	var p_prev := Vector3.ZERO
	for i in range(pts.size() - 1):
		var a: Vector3 = st.to_global(pts[i])
		var b: Vector3 = st.to_global(pts[i + 1])
		var flat := Vector2(b.x - a.x, b.z - a.z).length()
		var n := maxi(1, int(ceil(flat / step)))
		for k in range(0 if i == 0 else 1, n + 1):
			var t := float(k) / n
			var x := lerpf(a.x, b.x, t)
			var z := lerpf(a.z, b.z, t)
			var fy: float
			if is_nan(y_prev):
				fy = _floor(x, z, a.y + 1.5, 3.0)         # first point: the plan's y is only approximate
			else:
				fy = _floor(x, z, y_prev + 0.7, 1.6)
			if is_nan(fy):
				return "no floor at (%.1f, %.1f) after %.1f m (last floor y %.1f)" % [x, z, _len(pts, i, t), y_prev if not is_nan(y_prev) else a.y]
			if not is_nan(y_prev) and absf(fy - y_prev) > step * 1.3 + 0.08:
				return "floor jumps %.2f m at (%.1f, %.1f)" % [fy - y_prev, x, z]
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = _shape
			q.collision_mask = 1 | 4
			q.transform = Transform3D(Basis.IDENTITY, Vector3(x, fy + LIFT + HEIGHT * 0.5, z))
			var hits := _space.intersect_shape(q, 4)
			if not hits.is_empty():
				var col := hits[0]["collider"] as Node
				return "blocked by %s at (%.1f, %.1f, %.1f) after %.1f m" % [str(col.get_path()).replace("/root/Runner/", "").replace("@Node3D@", "N"), x, fy, z, _len(pts, i, t)]
			y_prev = fy
	return ""


func _floor(x: float, z: float, from_y: float, depth: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, from_y - depth, z))
	q.collision_mask = 1
	var h := _space.intersect_ray(q)
	if h.is_empty():
		return NAN
	return (h["position"] as Vector3).y


func _len(pts: Array, seg: int, t: float) -> float:
	var d := 0.0
	for i in seg:
		d += Vector2((pts[i + 1] as Vector3).x - (pts[i] as Vector3).x, (pts[i + 1] as Vector3).z - (pts[i] as Vector3).z).length()
	d += t * Vector2((pts[seg + 1] as Vector3).x - (pts[seg] as Vector3).x, (pts[seg + 1] as Vector3).z - (pts[seg] as Vector3).z).length()
	return d
