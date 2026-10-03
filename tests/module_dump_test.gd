extends Node
## Prints the plan of a station: its platform modules (position, length, faces) and rooms (rect, level). args --station=Name
func run():
	var nm := "Bank"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): nm = a.substr(10)
	var plan := StationPlan.for_station(Net.name_to_idx[nm])
	print("station ", plan.name, " ", plan.nodes.size(), " nodes")
	for i in plan.modules.size():
		var m: Dictionary = plan.modules[i]
		var sp: Dictionary = m["spec"]
		print("module %d pos %s len %.0f pw %.1f style %s group %s spine %.0f..%.0f tun_w %.0f tun_e %.0f bend %s faces %s" % [i, str(m["pos"]), sp["length"], sp["pw"], sp["style"], m["group"], sp["spine_x0"], sp["spine_x1"], sp.get("tun_w", 0), sp.get("tun_e", 170), str(m.get("bend", {})), str(m["faces"])])
	for r in plan.rooms:
		print("room %-16s rect %s y %.1f h %.1f" % [r["name"], str(r.get("rect", [])), float(r.get("y", 0.0)), float(r.get("h", 0.0))])
	for k in plan.faces:
		var f: Dictionary = plan.faces[k]
		print("face %s module %d side %.0f x %.0f..%.0f edge_z %.1f track_z %.1f y %.1f" % [k, f["module"], f["side"], f["x0"], f["x1"], f["edge_z"], f["track_z"], f["y"]])
