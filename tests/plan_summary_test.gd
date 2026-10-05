extends Node
## Prints what a station's plan holds: rooms, escalator banks, modules (faces, length), street doors. args: --stations="Romford|Slough"; --split lists the stations drawn as a pair of side platforms (StationPlan.is_split)
## with the door side of each face
func run():
	Timetable.build(1)
	var names := "Romford"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stations="): names = a.substr(11)
		if a == "--split":
			var l: Array = []
			for i in Net.stations.size():
				if StationPlan.is_split(Net.station_ids[i]):
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
			print("  module %d: length %.0f style %s faces %s dir_sign %s depth %.1f" % [mi, sp["length"], sp.get("style", "?"), str((m["faces"] as Array).map(func(f): return f["pid"])), str(m.get("dir_sign", 1)), -float(m["pos"].y)])
		if StationPlan.is_split(Net.station_ids[idx]):
			for fk in plan.faces:
				var f: Dictionary = plan.faces[fk]
				print("  face %s: module %d slot %d side %+d doors %s" % [fk, int(f["module"]), int(f["face"]), int(f["side"]), PlatformCurve.face_side(Net.station_ids[idx], String(f["pid"]))])
		print("  street doors %d, gatelines %d, faces %s" % [plan.street_doors.size(), plan.gatelines.size(), str(plan.faces.keys())])
