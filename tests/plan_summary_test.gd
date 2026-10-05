extends Node
## Prints what a station's plan holds: rooms, escalator banks, modules (faces, length), street doors. args: --stations="Romford|Slough"; --split lists the stations drawn as a pair of side platforms (StationPlan.is_split)
## with the door side of each face (of any line group: --split=central lists one group's)
func _any_split(i: int, only := "") -> bool:
	var seen := {}
	for pid in Net.stations[i]["platforms"]:
		seen[String(Net.stations[i]["platforms"][pid]["group"])] = true
	for g in seen:
		if (only == "" or only == g) and StationPlan.is_split(Net.station_ids[i], g):
			return true
	return false


func run():
	Timetable.build(1)
	var names := "Romford"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stations="): names = a.substr(11)
		if a == "--split" or a.begins_with("--split="):
			var l: Array = []
			for i in Net.stations.size():
				if _any_split(i, a.substr(8)):
					l.append(String(Net.stations[i]["name"]))
			names = "|".join(l)
			print("SPLIT stations: %d" % l.size())
	for nm in names.split("|"):
		var idx: int = Net.name_to_idx[nm]
		var plan := StationPlan.for_station(idx)
		var st: Dictionary = Net.stations[idx]
		print("PLAN %s: kind %s, authored %s, platforms %s" % [nm, st.get("kind", "?"), str(plan.authored), str(st["platforms"].keys())])
		print("  rooms: %s" % str(plan.rooms.map(func(r): return "%s %s" % [r["name"], str(r.get("rect", []))])))
		print("  escs: %d %s" % [plan.escs.size(), str(plan.escs.map(func(e): return "%s rise %.1f lanes %d stairs %s" % [e["id"], e["rise"], (e["lanes"] as Array).size(), str(e.get("stairs", false))]))])
		for mi in plan.modules.size():
			var m: Dictionary = plan.modules[mi]
			var sp: Dictionary = m["spec"]
			print("  module %d: length %.0f style %s faces %s dir_sign %s depth %.1f at x %.1f z %.1f" % [mi, sp["length"], sp.get("style", "?"), str((m["faces"] as Array).map(func(f): return f["pid"])), str(m.get("dir_sign", 1)), -float(m["pos"].y), float(m["pos"].x), float(m["pos"].z)])
			if sp.has("footbridges"):
				print("    footbridges: %s cuts %s" % [str(sp["footbridges"]), str(sp.get("cuts", []))])
			if not (m.get("bend", {}) as Dictionary).is_empty():
				print("    bend: kappa %.5f (R %.0f m) x %.0f .. %.0f" % [float(m["bend"]["kappa"]), 1.0 / absf(float(m["bend"]["kappa"])), float(m["bend"]["x0"]), float(m["bend"]["x1"])])
		if _any_split(idx):
			for fk in plan.faces:
				var f: Dictionary = plan.faces[fk]
				print("  face %s: module %d slot %d side %+d doors %s" % [fk, int(f["module"]), int(f["face"]), int(f["side"]), PlatformCurve.face_side(Net.station_ids[idx], String(f["pid"]))])
		print("  street doors %d, gatelines %d, faces %s" % [plan.street_doors.size(), plan.gatelines.size(), str(plan.faces.keys())])
