extends Node3D
## Reports rooms/escalators/nodes of a station plan that intersect a train footprint (a train standing at a platform must not overlap walkways).
## args: --stations="A|B"
func run():
	Timetable.build(1)
	var names := "Bank|King's Cross St. Pancras|Oxford Circus".split("|")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stations="): names = a.substr(11).split("|")
	for nm in names:
		var plan := StationPlan.for_station(Net.name_to_idx[nm])
		var bad := 0
		for fk in plan.faces:
			var f: Dictionary = plan.faces[fk]
			var cars: Array = StationPlan.CARS.get(fk.split(":")[0], [6, 16.0])
			var half: float = float(cars[0]) * float(cars[1]) * 0.5
			var mx: float = (plan.modules[f["module"]]["pos"] as Vector3).x
			var tz: float = f["track_z"]
			var y: float = f["y"]
			for rm in plan.rooms:
				var r: Array = rm["rect"]
				if absf(float(rm["y"]) - y) > 2.0:
					continue
				if r[1] > mx - half and r[0] < mx + half and r[3] > tz - 1.6 and r[2] < tz + 1.6:
					bad += 1
					print("  %s: train on %s (x %.0f..%.0f, z %.1f) overlaps room %s rect x %.0f..%.0f z %.0f..%.0f" % [nm, fk, mx - half, mx + half, tz, rm["name"], r[0], r[1], r[2], r[3]])
		print("%s: %d room/train overlaps" % [nm, bad])
