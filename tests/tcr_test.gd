extends Node3D
## Diagnostic: walking route between a platform face and the street in one station, plus platform-module extents.
## args: --station=Name_With_Underscores --face=central:Eastbound#0
func run():
	Timetable.build(1)
	add_child(Env.make(0))
	var sname := "Tottenham Court Road"
	var face := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): sname = a.substr(10).replace("_", " ")
		if a.begins_with("--face="): face = a.substr(7)
	var idx: int = Net.name_to_idx[sname]
	var plan := StationPlan.for_station(idx)
	var st := Station.new()
	add_child(st)
	st.build(plan)
	for i in 6: await get_tree().physics_frame
	print("faces: ", plan.faces.keys().map(func(k): return [k, snappedf(plan.faces[k]["y"], 0.1), snappedf(plan.faces[k]["pos"].x, 0.1), snappedf(plan.faces[k]["pos"].z, 0.1), snappedf(plan.faces[k]["x0"], 0.1), snappedf(plan.faces[k]["x1"], 0.1)]))
	for m in plan.modules:
		print("module pos ", (m["pos"] as Vector3).snapped(Vector3(0.1, 0.1, 0.1)), " style ", m["spec"]["style"], " L ", m["spec"]["length"], " openings_x ", m["spec"]["openings_x"])
	if face == "":
		face = plan.faces.keys()[0]
	var start := "face:" + face
	var best: Array = []
	for sd in plan.street_doors:
		var p := plan.path(start, sd["id"])
		if best.is_empty() or (not p.is_empty() and p.size() < best.size()):
			best = p
	print("path: ", best)
	for wp in plan.walk_points(best, 0):
		print("  wp ", wp["kind"], " ", (wp["pos"] as Vector3).snapped(Vector3(0.1, 0.1, 0.1)))
