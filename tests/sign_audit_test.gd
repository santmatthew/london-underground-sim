extends Node3D
## Audits every sign of some stations: signs (nodes tagged meta "sign") must not intersect walls/columns/roof, and hung ones must clear
## the floor by HEAD. args: --stations="A|B|C"  (default: a sample)  --verbose
const DEFAULT := "Euston|King's Cross St. Pancras|Oxford Circus|Bank|Euston Square|Stamford Brook|Barbican|Waterloo|Paddington|Victoria|Tottenham Court Road|Baker Street"


func run():
	Timetable.build(1)
	Clock.set_time(11.0 * 3600.0)
	add_child(Env.make(0))
	var names := DEFAULT.split("|")
	var verbose := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stations="): names = a.substr(11).split("|")
		if a == "--verbose": verbose = true
		if a == "--sf": StationPlan.step_free_mode = true
	var total_signs := 0
	var total_bad := 0
	for nm in names:
		if not Net.name_to_idx.has(nm):
			print("SKIP unknown station name: ", nm)
			continue
		var idx: int = Net.name_to_idx[nm]
		var st := Station.new()
		add_child(st)
		st.build(StationPlan.for_station(idx))
		for i in 3: await get_tree().physics_frame
		var signs: Array = []
		_collect(st, signs)
		var bad := 0
		var kinds := {}
		for sg in signs:
			var ab := _aabb(sg)
			if ab.size == Vector3.ZERO:
				continue
			var why := _check(st, sg, ab)
			total_signs += 1
			if why != "":
				bad += 1
				var k := why.split(" ")[0]
				kinds[k] = kinds.get(k, 0) + 1
				if verbose or bad <= 6:
					print("  BAD %s: %s  size %s at %s  parent %s" % [nm, why, str(ab.size.snapped(Vector3(0.01, 0.01, 0.01))), str(ab.get_center().snapped(Vector3(0.1, 0.1, 0.1))), str((sg as Node).get_parent().get_path()).right(60)])
		print("%s: %d signs, %d bad %s" % [nm, signs.size(), bad, str(kinds)])
		total_bad += bad
		st.queue_free()
		for i in 2: await get_tree().process_frame
	print("TOTAL: %d signs, %d bad" % [total_signs, total_bad])


func _collect(n: Node, out: Array) -> void:
	if n.has_meta("sign"):
		out.append(n)
		return
	for c in n.get_children():
		_collect(c, out)


func _aabb(sg: Node) -> AABB:
	var box := AABB()
	var first := true
	for n in sg.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if vi is Label3D and (vi as Label3D).text == "":
			continue
		var ab: AABB = vi.global_transform * vi.get_aabb()
		if first:
			box = ab
			first = false
		else:
			box = box.merge(ab)
	return box


func _check(st: Station, sg: Node, ab: AABB) -> String:
	var inset := 0.03
	var sz := (ab.size - Vector3.ONE * inset * 2.0).max(Vector3.ONE * 0.01)
	# 1. world colliders (walls, columns, fences, escalator shafts)
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = sz
	shape.margin = 0.0
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, ab.get_center())
	q.collision_mask = 1
	for h in space.intersect_shape(q, 4):
		var col := h["collider"] as Node
		var info := ""
		for c in col.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				var bab: AABB = (c as CollisionShape3D).global_transform * AABB(-((c as CollisionShape3D).shape as BoxShape3D).size * 0.5, ((c as CollisionShape3D).shape as BoxShape3D).size)
				if bab.intersects(AABB(ab.position + Vector3.ONE * 0.03, (ab.size - Vector3.ONE * 0.06).max(Vector3.ONE * 0.01))):
					info = " box %s..%s" % [str(bab.position.snapped(Vector3(0.1, 0.1, 0.1))), str(bab.end.snapped(Vector3(0.1, 0.1, 0.1)))]
					break
		return "solid %s/%s%s" % [col.get_parent().name, col.name, info]
	# 2. tunnel roof (arch) / spine / box ceiling, per platform module
	for pm in st.modules:
		var inv: Transform3D = pm.global_transform.affine_inverse()
		var lb: AABB = inv * ab
		var zf: float = PlatformModule.GAP * 0.5 + float(pm.meta["pw"]) + PlatformModule.TRACK_TO_EDGE + PlatformModule.TRACK_TO_WALL
		var L: float = pm.meta["length"]
		var cx := lb.get_center().x
		if absf(cx) > L * 0.5 + 30.0 or lb.position.y < -3.0 or lb.position.y > 7.0 or lb.position.z > zf + 0.2 or lb.end.z < -zf - 0.2:
			continue
		if cx < -L * 0.5 - 8.0 or cx > L * 0.5 + 8.0:
			continue        # corridor/spine outside the platform stretch: the room shells handle it (collider check above)
		var top := lb.end.y
		for k in 9:
			var z := lerpf(lb.position.z, lb.end.z, k / 8.0)
			if absf(z) > zf:
				continue
			if top > pm.ceiling_at(z) - 0.02 and lb.end.y > 1.0:
				return "roof z=%.2f top=%.2f ceiling=%.2f" % [z, top, pm.ceiling_at(z)]
	# 3. headroom of hung signs
	if sg.has_meta("hung"):
		var from := Vector3(ab.get_center().x, ab.position.y - 0.05, ab.get_center().z)
		var rq := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -6.0, 0))
		rq.collision_mask = 1
		var hit := space.intersect_ray(rq)
		if not hit.is_empty():
			var clear: float = ab.position.y - float(hit["position"].y)
			if clear < PlatformModule.HEAD - 0.06:
				return "headroom %.2f" % clear
	return ""
