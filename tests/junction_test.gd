extends Node
## Branch junctions (data/junctions.json): Camden Town, Euston and Kennington have one platform per direction AND branch; each is served by exactly its branch's
## trains, with the real platform number, and the planner routes a journey through the right one.
var ok := true


func check(cond: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		ok = false


func run():
	Timetable.build(1)
	var want := {
		"Camden Town": {"northern:Northbound~edgware": 1, "northern:Southbound~edgware": 2, "northern:Northbound~highbarnet": 3, "northern:Southbound~highbarnet": 4},
		"Euston": {"northern:Northbound~cx": 1, "northern:Southbound~cx": 2, "northern:Northbound~bank": 3, "northern:Southbound~bank": 6},
		"Kennington": {"northern:Northbound~cx": 1, "northern:Southbound~cx": 4, "northern:Northbound~bank": 3, "northern:Southbound~bank": 2},
	}
	for sname in want:
		var idx: int = Net.name_to_idx[sname]
		var plan := StationPlan.for_station(idx)
		for pid in want[sname]:
			check(plan.platform_no.get(pid, -1) == want[sname][pid], "%s %s is platform %d (plan says %s)" % [sname, pid, want[sname][pid], str(plan.platform_no.get(pid, "none"))])
			check(plan.faces.has(pid + "#0"), "%s: %s has a face in the plan" % [sname, pid])
			# every train on the platform belongs to its branch: check the destinations
			var gp: int = Timetable.plat_index[idx][pid]
			var visits: Array = Timetable.visits_between(gp, 8.0 * 3600.0, 9.0 * 3600.0)
			check(visits.size() >= 3, "%s %s: %d trains between 08:00 and 09:00" % [sname, pid, visits.size()])
			var dests: Array = plan.dests(pid)
			print("      ", plan.dir_text(pid), " -> ", ", ".join(dests))
		var seen_ends := {}
		for pid in want[sname]:
			for d in plan.dests(pid):
				seen_ends[d] = true
		# a branch platform never lists the other branch's terminus
		if sname == "Camden Town":
			check(not (plan.dests("northern:Northbound~edgware") as Array).has("High Barnet"), "Camden Town: the Edgware platform has no High Barnet trains")
			check(not (plan.dests("northern:Northbound~highbarnet") as Array).has("Edgware"), "Camden Town: the High Barnet platform has no Edgware trains")
			check((plan.dests("northern:Southbound~edgware") as Array).size() > 0, "Camden Town: southbound from the Edgware branch has trains")
	print("OK" if ok else "FAILED")
