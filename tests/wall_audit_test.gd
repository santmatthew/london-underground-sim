extends Node3D
## "Can I walk through something that looks solid?" and "is there something invisible in my way?"
## From a grid of sample points on every walkable floor of a station (rooms, corridors, platforms) casts horizontal rays at waist and eye height
## twice: against the physics world (layer 1) and against the real visible meshes of the station's architecture (rooms, escalators, platform modules).
##   GHOST  = a visible surface is hit noticeably before the physics world: you would walk through it
##   INVIS  = the physics world is hit noticeably before any visible surface: an invisible wall
## args: --station="Victoria" (or --all-authored)  --step=2.5  --gap=0.5  --max=15 (examples printed per kind)
var _meshes: Array = []         # [MeshInstance3D, TriangleMesh, Transform3D inverse, AABB(world)]


func run():
	var names: Array = []
	var step := 2.5
	var gap := 0.5
	var maxp := 12
	var all_authored := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): names = a.substr(10).split("|")
		if a == "--all-authored": all_authored = true
		if a.begins_with("--range="):
			var c := a.substr(8).split(",")
			for i in range(int(c[0]), int(c[1]) + 1):
				names.append(Net.station_name(i))
		if a.begins_with("--step="): step = float(a.substr(7))
		if a.begins_with("--gap="): gap = float(a.substr(6))
		if a.begins_with("--max="): maxp = int(a.substr(6))
	Timetable.build(1)
	Clock.set_time(11.0 * 3600.0)
	add_child(Env.make(0))
	if all_authored:
		var dir := DirAccess.open("res://data/layouts")
		for f in dir.get_files():
			if f.ends_with(".json"):
				for i in Net.station_ids.size():
					if Net.station_ids[i] == f.get_basename():
						names.append(Net.station_name(i))
	if names.is_empty():
		names = ["Victoria"]
	var total_ghost := 0
	var total_invis := 0
	for sname in names:
		var r := await _audit(sname, step, gap, maxp)
		total_ghost += r[0]
		total_invis += r[1]
	print("TOTAL: %d stations, %d ghost rays, %d invisible-wall rays" % [names.size(), total_ghost, total_invis])


func _audit(sname: String, step: float, gap: float, maxp: int) -> Array:
	var idx: int = Net.name_to_idx[sname]
	var plan := StationPlan.for_station(idx)
	var st := Station.new()
	add_child(st)
	st.build(plan)
	for i in 4: await get_tree().physics_frame
	_meshes.clear()
	_collect(st)
	var space := get_world_3d().direct_space_state
	# ---- sample points: floors of every room, plus the platforms
	var pts: Array = []
	for rm in plan.rooms:
		if String(rm["name"]).begins_with("street_passage"):
			continue
		var r: Array = rm["rect"]
		var nx := maxi(1, int((r[1] - r[0]) / step))
		var nz := maxi(1, int((r[3] - r[2]) / step))
		for i in nx:
			for j in nz:
				pts.append([Vector3(r[0] + (i + 0.5) * (r[1] - r[0]) / nx, rm["y"], r[2] + (j + 0.5) * (r[3] - r[2]) / nz), str(rm["name"])])
	for fk in plan.faces:
		for t in 24:
			pts.append([st.platform_point(fk, (t + 0.5) / 24.0, 1.4), "platform " + str(fk)])
	var dirs: Array = []
	for k in 16:
		var ang := k * TAU / 16.0
		dirs.append(Vector3(sin(ang), 0, cos(ang)))
	var ghosts := {}       # key -> [count, example]
	var invis := {}
	var n_ghost := 0
	var n_invis := 0
	var rays := 0
	for p in pts:
		for hgt in [0.9, 1.6]:
			var o: Vector3 = (p[0] as Vector3) + Vector3(0, hgt, 0)
			for d in dirs:
				rays += 1
				var q := PhysicsRayQueryParameters3D.create(o, o + d * 30.0)
				q.collision_mask = 1 | 4
				var h := space.intersect_ray(q)
				var dp := 30.0 if h.is_empty() else o.distance_to(h["position"])
				var mh := _mesh_hit(o, d, 30.0)
				var dm: float = mh[0]
				if dm < dp - gap:
					n_ghost += 1
					var key := "%s  (seen from %s)" % [mh[1], p[1]]
					if not ghosts.has(key): ghosts[key] = [0, ""]
					ghosts[key][0] += 1
					if ghosts[key][0] % 7 == 1 and ghosts[key][0] < 50:
						ghosts[key][1] += "\n        at %s dir (%+.1f,%+.1f): visible surface %.1f m (at %s), solid %.1f m" % [str(o.snapped(Vector3(0.1, 0.1, 0.1))), d.x, d.z, dm, str((o + d * dm).snapped(Vector3(0.1, 0.1, 0.1))), dp]
				elif dp < dm - gap and not h.is_empty() and ((h["collider"] as CollisionObject3D).collision_layer & 1) != 0:
					n_invis += 1
					var cn: String = str((h["collider"] as Node).get_path()).replace("/root/Runner/", "")
					var key2 := "%s  (seen from %s)" % [cn, p[1]]
					if not invis.has(key2): invis[key2] = [0, "at %s dir (%+.1f,%+.1f): solid %.1f m, nearest visible surface %.1f m" % [str(h["position"].snapped(Vector3(0.1, 0.1, 0.1))), d.x, d.z, dp, dm]]
					invis[key2][0] += 1
	print("== %s: %d rays, GHOST %d, INVIS %d" % [sname, rays, n_ghost, n_invis])
	_print_top("GHOST", ghosts, maxp)
	_print_top("INVIS", invis, maxp)
	st.queue_free()
	await get_tree().process_frame
	return [n_ghost, n_invis]


func _print_top(label: String, dict: Dictionary, maxp: int) -> void:
	var keys := dict.keys()
	keys.sort_custom(func(a, b): return dict[a][0] > dict[b][0])
	for i in mini(maxp, keys.size()):
		print("   %s x%d  %s\n        %s" % [label, dict[keys[i]][0], keys[i], dict[keys[i]][1]])


func _collect(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var path := str(mi.get_path())
		# architecture only: room shells, escalator shafts, platform-module shells; not lights, signs, gates, people, trains
		var arch: bool = mi.get_parent() is Space or mi.get_parent() is Escalator or mi.get_parent() is PlatformModule or mi.get_parent().get_parent() is PlatformModule
		var fitting: bool = path.contains("/Fittings/")          # gates and fences
		if not (path.contains("/Station_") and (arch or fitting)):
			continue
		if mi.has_meta("sign") or mi.name.begins_with("Light") or mi.name.begins_with("Decal"):
			continue
		var tm := mi.mesh.generate_triangle_mesh()
		if tm == null:
			continue
		_meshes.append([mi, tm, mi.global_transform.affine_inverse(), mi.global_transform * mi.get_aabb()])


## nearest visible-mesh hit along a ray: [distance, "node path"]
func _mesh_hit(o: Vector3, d: Vector3, maxd: float) -> Array:
	var best := maxd
	var who := ""
	for m in _meshes:
		var wa: AABB = m[3]
		if wa.intersects_segment(o, o + d * maxd) == null and not wa.has_point(o):
			continue
		var inv: Transform3D = m[2]
		var lo := inv * o
		var ld := (inv.basis * d)
		var hit = (m[1] as TriangleMesh).intersect_ray(lo, ld.normalized())
		if hit is Dictionary and not (hit as Dictionary).is_empty():
			var wp: Vector3 = (m[0] as MeshInstance3D).global_transform * (hit["position"] as Vector3)
			var dist := o.distance_to(wp)
			# ignore floors and ceilings (near-horizontal faces) and the surface we stand right next to
			var nrm: Vector3 = ((m[0] as MeshInstance3D).global_transform.basis * (hit["normal"] as Vector3)).normalized()
			if dist > 0.05 and dist < best and absf(nrm.y) < 0.6 and absf(nrm.dot(d)) > 0.3:       # not floors/ceilings, not grazing along a wall
				best = dist
				who = str((m[0] as Node).get_path()).replace("/root/Runner/", "")
	return [best, who]
