extends Node
## The "Platforms" boards above the escalators that leave a ticket hall: each one must list only the lines whose platforms that escalator leads down to. Lists every authored station where an escalator
## from a hall reaches only some of the station's lines, and checks the signs a station builds show exactly that. args --list
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	var listed := 0
	var subsets := 0
	for idx in Net.stations.size():
		var plan := StationPlan.for_station(idx)
		if not plan.authored:
			continue
		var here: Array = StationSigns._lines_here(plan)
		for e in plan.escs:
			if not String(e.get("from", "hall")).begins_with("hall"):
				continue
			var below: Array = StationSigns._lines_below(plan, String(e["to"]))
			listed += 1
			if below.size() < here.size():
				subsets += 1
				print("  %-28s escalator %-6s from %-10s leads to %s only (of %s)" % [plan.name, e["id"], e["from"], str(below), str(here)])
	# the boards a station really builds: one "Platforms" board per hall escalator, listing exactly the lines that escalator leads to
	for nm in ["Liverpool Street", "Moorgate", "Bond Street", "Farringdon", "Paddington", "Barbican"]:
		var plan := StationPlan.for_station(Net.name_to_idx[nm])
		var st := Station.new()
		add_child(st)
		st.build(plan)
		var boards: Array = []
		for lb in st.find_children("*", "Label3D", true, false):
			if (lb as Label3D).text == "Platforms":
				var names: Array = []
				for sib in lb.get_parent().get_children():
					if sib is Label3D and (sib as Label3D).text != "Platforms":
						names.append((sib as Label3D).text)
				names.sort()
				boards.append(names)
		var want: Array = []
		for e in plan.escs:
			if not String(e.get("from", "hall")).begins_with("hall"):
				continue
			var names2: Array = []
			for lid in StationSigns._lines_below(plan, String(e["to"])):
				names2.append("%s line" % Net.line_name(lid))
			names2.sort()
			want.append(names2)
		var left := boards.duplicate()
		var missing := 0
		for w in want:
			var found := -1
			for i in left.size():
				if left[i] == w:
					found = i
					break
			if found >= 0:
				left.remove_at(found)
			else:
				missing += 1
		check(missing == 0 and want.size() > 0, "%s: %d hall escalators, %d boards, %d escalators without a board listing exactly their lines %s" % [nm, want.size(), boards.size(), missing, str(want)])
		st.queue_free()
		await get_tree().process_frame
	print("  info: %d hall escalators of authored stations, %d lead to only some of the station's lines" % [listed, subsets])
	print("OK" if ok else "FAILED")
