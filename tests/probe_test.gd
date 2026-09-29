extends Node3D
func run():
	Timetable.build(1)
	add_child(Env.make(0))
	var idx: int = Net.name_to_idx["King's Cross St. Pancras"]
	var plan := StationPlan.for_station(idx)
	var st := Station.new()
	add_child(st)
	st.build(plan)
	for i in 6: await get_tree().physics_frame
	print("modules: ", plan.modules.map(func(m): return [snappedf(m["pos"].x, 0.1), snappedf(m["pos"].y, 0.1), snappedf(m["pos"].z, 0.1), m["spec"]["style"], m["spec"]["faces"].size()]))
	print("faces: ", plan.faces.keys().map(func(k): return [k, snappedf(plan.faces[k]["y"], 0.1), snappedf(plan.faces[k]["pos"].x, 0.1), snappedf(plan.faces[k]["pos"].z, 0.1)]))
	var space := get_world_3d().direct_space_state
	var p := Vector3(111.1, -22.84, 86.15)
	for dy in [3.0, 1.0, -0.5, -2.5]:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, dy + 4, 0), p + Vector3(0, dy - 4, 0))
		var hit := space.intersect_ray(q)
		print("ray around y%+.1f: " % dy, hit.get("position", "none"), " ", (hit.get("collider") as Node).get_path() if hit.has("collider") else "")
	var sq := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new(); sh.radius = 0.4
	sq.shape = sh; sq.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.9, 0))
	for h in space.intersect_shape(sq, 8):
		print("overlap: ", (h["collider"] as Node).get_path())
