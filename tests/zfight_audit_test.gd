extends Node3D
## Z-fighting audit: two triangles of the built station that lie in the same plane, face the same way and overlap are drawn on top of each other and flicker as the camera moves. Every MeshInstance3D
## of the station (rooms, platform modules, fittings, props) is flattened to world-space triangles; triangles are grouped by plane (normal and offset, to 2 mm) and the overlap of each pair in a group is
## measured (convex polygon clipping). Prints the worst overlaps with the nodes that own them.
## args: --stations="Goodge Street|Oxford Circus"  --all  --min=0.02 (smallest overlap area to report, m2)  --max=15
var _min_area := 0.02
var _agg: Dictionary = {}        # normalised pair -> [pairs, area, stations]
var _detail := false
var _big: Array = []             # groups of architecture / escalator overlaps over BIG m2: what the suite fails on
var _sep := 0.0006               # triangles whose planes are closer than this (m) are drawn at the same depth


func run():
	var idxs_arg: Array = []
	var names: Array = []
	var all := false
	var maxp := 15
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stations="): names = a.substr(11).split("|")
		if a == "--all": all = true
		if a.begins_with("--range="):
			var c := a.substr(8).split(",")
			for i in range(int(c[0]), int(c[1]) + 1):
				idxs_arg.append(i)
		if a.begins_with("--min="): _min_area = float(a.substr(6))
		if a.begins_with("--sep="): _sep = float(a.substr(6))
		if a == "--detail": _detail = true
		if a.begins_with("--max="): maxp = int(a.substr(6))
	StationPlan.lifts_enabled = true
	Timetable.build(1)
	Clock.set_time(11.0 * 3600.0)
	add_child(Env.make(0))
	var idxs: Array = idxs_arg.duplicate()
	if not idxs.is_empty():
		pass
	elif all:
		for i in Net.stations.size():
			idxs.append(i)
	else:
		for n in names:
			idxs.append(Net.name_to_idx[n])
	var total := 0
	for idx in idxs:
		var plan := StationPlan.for_station(idx)
		var st := Station.new()
		add_child(st)
		st.build(plan)
		for i in 3: await get_tree().process_frame
		var found := _audit(st, maxp)
		total += found
		st.queue_free()
		await get_tree().process_frame
	var ak: Array = _agg.keys()
	ak.sort_custom(func(x, y): return _agg[x][1] > _agg[y][1])
	if idxs.size() > 3:
		print("-- by kind over %d stations:" % idxs.size())
		for k in ak.slice(0, 30):
			print("   %d stations, x%d, %.1f m2   %s" % [_agg[k][2].size(), _agg[k][0], _agg[k][1], k])
	print("TOTAL: %d stations, %d z-fighting overlaps over %.2f m2" % [idxs.size(), total, _min_area])
	for b in _big:
		print("  FAIL ", b)
	print("OK" if _big.is_empty() else "FAILED")


func _audit(st: Station, maxp: int) -> int:
	var tris: Array = []        # [a, b, c, normal, owner path, surface name]
	_collect(st, st, tris)
	var groups: Dictionary = {}
	for i in tris.size():
		var t: Array = tris[i]
		var n: Vector3 = t[3]
		var d: float = n.dot(t[0])
		var key := Vector4i(roundi(n.x * 50.0), roundi(n.y * 50.0), roundi(n.z * 50.0), roundi(d * 500.0))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(i)
	var hits: Array = []
	for key in groups:
		var g: Array = groups[key]
		if g.size() < 2:
			continue
		# neighbouring offsets (rounding at a bucket edge): also compare with the next bucket
		var cand: Array = g.duplicate()
		var nb := Vector4i(key.x, key.y, key.z, key.w + 1)
		if groups.has(nb):
			cand.append_array(groups[nb])
		if cand.size() > 400:
			cand = cand.slice(0, 400)
		for i in g.size():
			for j in range(i + 1, cand.size()):
				var a: Array = tris[g[i]]
				var b: Array = tris[cand[j]]
				if g[i] == cand[j] or a[5] == b[5]:
					continue                    # (the same material: nothing to see flicker)
				if absf((a[3] as Vector3).dot((b[0] as Vector3) - (a[0] as Vector3))) > _sep:
					continue
				var ov := _overlap(a, b)
				if ov > _min_area:
					hits.append([ov, a, b])
	hits.sort_custom(func(x, y): return x[0] > y[0])
	if not hits.is_empty():
		print("== %s: %d overlapping coplanar triangle pairs" % [st.plan.name, hits.size()])
		# group by the pair of owners
		var per: Dictionary = {}
		for h in hits:
			var k := "%s [%s]  <>  %s [%s]" % [h[1][4], h[1][5], h[2][4], h[2][5]]
			if not per.has(k):
				per[k] = [0, 0.0, (h[1][0] + h[1][1] + h[1][2]) / 3.0, h[1][3], h]
			per[k][0] += 1
			per[k][1] += h[0]
		for k in per:
			if float(per[k][1]) > 3.0 and (k.contains("/Shell") or k.contains("esc")) and not k.contains("Props"):
				_big.append("%s: %s (%.1f m2)" % [st.plan.name, k, float(per[k][1])])
			var nk := _norm(k)
			if not _agg.has(nk):
				_agg[nk] = [0, 0.0, {}]
			_agg[nk][0] += per[k][0]
			_agg[nk][1] += per[k][1]
			_agg[nk][2][st.plan.name] = true
		var keys: Array = per.keys()
		keys.sort_custom(func(x, y): return per[x][1] > per[y][1])
		for k in keys.slice(0, maxp):
			print("   x%d  %.2f m2  at %s facing %s   %s" % [per[k][0], per[k][1], str((per[k][2] as Vector3).snapped(Vector3(0.1, 0.1, 0.1))), str((per[k][3] as Vector3).snapped(Vector3(0.1, 0.1, 0.1))), k])
			if _detail:
				var hh: Array = per[k][4]
				for tt in [hh[1], hh[2]]:
					print("        tri %s  %s  %s" % [str((tt[0] as Vector3).snapped(Vector3(0.01, 0.01, 0.01))), str((tt[1] as Vector3).snapped(Vector3(0.01, 0.01, 0.01))), str((tt[2] as Vector3).snapped(Vector3(0.01, 0.01, 0.01)))])
	return hits.size()


func _norm(k: String) -> String:
	var r := RegEx.new()
	r.compile("@[A-Za-z0-9]+@[0-9]+|[0-9]+")
	return r.sub(k, "#", true)


func _collect(root: Node, n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh is ArrayMesh and (n as MeshInstance3D).visible:
		var mi := n as MeshInstance3D
		var xf := mi.global_transform
		var path := String(root.get_path_to(mi))
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var mat := mi.mesh.surface_get_material(si)
			if mat is BaseMaterial3D and ((mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
				continue
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var sname: String = mi.mesh.surface_get_name(si)
			var cnt: int = (idx as PackedInt32Array).size() if idx != null else vs.size()
			for k in range(0, cnt - 2, 3):
				var ia: int = idx[k] if idx != null else k
				var ib: int = idx[k + 1] if idx != null else k + 1
				var ic: int = idx[k + 2] if idx != null else k + 2
				var a: Vector3 = xf * vs[ia]
				var b: Vector3 = xf * vs[ib]
				var c: Vector3 = xf * vs[ic]
				var nrm := (b - a).cross(c - a)
				if nrm.length() < 1e-6:
					continue
				out.append([a, b, c, nrm.normalized(), path, sname])
	for c in n.get_children():
		_collect(root, c, out)


## area of the intersection of two coplanar triangles
func _overlap(a: Array, b: Array) -> float:
	var n: Vector3 = a[3]
	var u: Vector3 = ((a[1] as Vector3) - (a[0] as Vector3)).normalized()
	var v: Vector3 = n.cross(u)
	var pa: Array = []
	var pb: Array = []
	for i in 3:
		var da: Vector3 = (a[i] as Vector3) - (a[0] as Vector3)
		var db: Vector3 = (b[i] as Vector3) - (a[0] as Vector3)
		pa.append(Vector2(da.dot(u), da.dot(v)))
		pb.append(Vector2(db.dot(u), db.dot(v)))
	# quick reject
	var la := Vector2(minf(minf(pa[0].x, pa[1].x), pa[2].x), minf(minf(pa[0].y, pa[1].y), pa[2].y))
	var ha := Vector2(maxf(maxf(pa[0].x, pa[1].x), pa[2].x), maxf(maxf(pa[0].y, pa[1].y), pa[2].y))
	var lb := Vector2(minf(minf(pb[0].x, pb[1].x), pb[2].x), minf(minf(pb[0].y, pb[1].y), pb[2].y))
	var hb := Vector2(maxf(maxf(pb[0].x, pb[1].x), pb[2].x), maxf(maxf(pb[0].y, pb[1].y), pb[2].y))
	if ha.x <= lb.x or hb.x <= la.x or ha.y <= lb.y or hb.y <= la.y:
		return 0.0
	# only the same facing (back to back is not drawn twice)
	if (a[3] as Vector3).dot(b[3]) < 0.9:
		return 0.0
	var poly: Array = _ccw(pa)
	var clip: Array = _ccw(pb)
	for i in clip.size():
		var e0: Vector2 = clip[i]
		var e1: Vector2 = clip[(i + 1) % clip.size()]
		var out: Array = []
		for j in poly.size():
			var p0: Vector2 = poly[j]
			var p1: Vector2 = poly[(j + 1) % poly.size()]
			var in0 := (e1 - e0).cross(p0 - e0) >= 0.0
			var in1 := (e1 - e0).cross(p1 - e0) >= 0.0
			if in0:
				out.append(p0)
			if in0 != in1:
				var d0 := (e1 - e0).cross(p0 - e0)
				var d1 := (e1 - e0).cross(p1 - e0)
				out.append(p0.lerp(p1, d0 / (d0 - d1)))
		poly = out
		if poly.size() < 3:
			return 0.0
	var area := 0.0
	for i in poly.size():
		area += (poly[i] as Vector2).cross(poly[(i + 1) % poly.size()])
	return absf(area) * 0.5


func _ccw(p: Array) -> Array:
	var area: float = ((p[1] as Vector2) - (p[0] as Vector2)).cross((p[2] as Vector2) - (p[0] as Vector2))
	return p if area >= 0.0 else [p[0], p[2], p[1]]
