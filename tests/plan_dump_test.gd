extends Node
## Prints the platform faces / groups / street doors / rooms of a station's plan (what an authored layout may refer to).
## args: --station="Victoria"
func run():
	var sname := "Victoria"
	var from_n := ""
	var to_n := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): sname = a.substr(10)
		if a.begins_with("--from="): from_n = a.substr(7)
		if a.begins_with("--to="): to_n = a.substr(5)
	Timetable.build(1)
	var plan := StationPlan.for_station(Net.name_to_idx[sname])
	var naptan: String = Net.station_ids[plan.idx]
	print("station ", plan.name, " idx ", plan.idx, " naptan ", naptan, " authored ", plan.authored)
	print("faces: ", plan.faces.keys())
	print("street doors: ", plan.street_doors.map(func(d): return "%s ref=%s name=%s" % [d["id"], str(d.get("ref", "")), str(d.get("name", ""))]))
	for rm in plan.rooms:
		print("room %s rect %s y %.1f h %.1f" % [rm["name"], str((rm["rect"] as Array).map(func(v): return snappedf(v, 0.1))), rm["y"], rm["h"]])
	for m in plan.modules:
		var sp: Dictionary = m["spec"]
		print("module %s pos %s level %s lane_z %.1f corr %s style %s length %s spine_x0 %s faces %s" % [str(m["group"]), str((m["pos"] as Vector3).snapped(Vector3(0.1, 0.1, 0.1))), str(m["level"]), float(m["lane_z"]), str(m["corr"]), str(sp.get("style", "?")), str(sp.get("length", sp.get("L", "?"))), str(sp.get("spine_x0", "?")), str(m["faces"])])
	print("layout depths: ", RealData.layout(naptan).get("depths", {}))
	print("real entrances (<=130 m): ", RealData.entrances(naptan).map(func(e): return "%s %s" % [str(e.get("ref", "")), str(e.get("name", ""))]))
	if from_n != "" and to_n != "":
		var names := plan.path(from_n, to_n)
		print("path ", from_n, " -> ", to_n, ": ", names)
		var pts := plan.walk_points(names, 0)
		for k in pts.size():
			print("  wp %d %s %s esc %s lane %s" % [k, pts[k]["kind"], str((pts[k]["pos"] as Vector3).snapped(Vector3(0.1, 0.1, 0.1))), str(pts[k].get("esc", "-")), str(pts[k].get("lane", "-"))])
		var flat := 0.0
		var esc_len := 0.0
		for k in range(1, pts.size()):
			var a: Vector3 = pts[k - 1]["pos"]
			var b: Vector3 = pts[k]["pos"]
			var seg := b.distance_to(a) if pts[k]["kind"] == "esc_out" else Vector2(a.x - b.x, a.z - b.z).length()
			if pts[k]["kind"] == "esc_out":
				esc_len += seg
			else:
				flat += seg
		print("planner walk_time %.0f s ; waypoint route: %.0f m flat (%.0f s at 1.5 m/s) + %.0f m on escalators/stairs" % [plan.walk_time(from_n, to_n), flat, flat / 1.5, esc_len])
