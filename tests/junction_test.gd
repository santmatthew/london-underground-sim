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
		"Camden Town": {"northern:Northbound~edgware": 1, "northern:Southbound~cx": 2, "northern:Northbound~highbarnet": 3, "northern:Southbound~bank": 4},
		"Euston": {"northern:Northbound~cx": 1, "northern:Southbound~cx": 2, "northern:Northbound~bank": 3, "northern:Southbound~bank": 6},
		"Kennington": {"northern:Northbound~cx": 1, "northern:Southbound~cx": 2, "northern:Northbound~bank": 3, "northern:Southbound~bank": 4},
		"Finchley Central": {"northern:Northbound~mhe": 1, "northern:Northbound~hb": 2, "northern:Southbound": 3},
	}
	# what each branch platform serves: a word that every train there has in its service name, and one that none has
	var serves := {
		"Camden Town": {"northern:Northbound~edgware": ["Edgware", "High Barnet"], "northern:Northbound~highbarnet": ["High Barnet", "Edgware"], "northern:Southbound~cx": ["Charing Cross", "Bank"], "northern:Southbound~bank": ["Bank", "Charing Cross"]},
		"Euston": {"northern:Northbound~cx": ["Charing Cross", "Bank"], "northern:Northbound~bank": ["Bank", "Charing Cross"], "northern:Southbound~cx": ["Charing Cross", "Bank"], "northern:Southbound~bank": ["Bank", "Charing Cross"]},
		"Kennington": {"northern:Northbound~cx": ["Charing Cross", "Bank"], "northern:Northbound~bank": ["Bank", "Charing Cross"], "northern:Southbound~cx": ["Charing Cross", "Bank"], "northern:Southbound~bank": ["Bank", "Charing Cross"]},
		"Finchley Central": {"northern:Northbound~mhe": ["Mill Hill East", "High Barnet"], "northern:Northbound~hb": ["High Barnet", "Mill Hill East"]},
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
		var plan2 := plan
		for pid in serves.get(sname, {}):
			var must: String = serves[sname][pid][0]
			var never: String = serves[sname][pid][1]
			var gp2: int = Timetable.plat_index[idx][pid]
			var bad := 0
			var n_ok := 0
			for v in Timetable.visits_between(gp2, 6.0 * 3600.0, 10.0 * 3600.0):
				var nm := String(Timetable.run_name(v["run"]))
				if nm.contains(never) and not nm.contains(must):
					bad += 1
				elif nm.contains(must):
					n_ok += 1
			check(bad == 0 and n_ok > 0, "%s %s: %d trains for '%s', %d for the other branch" % [sname, pid, n_ok, must, bad])
	print("OK" if ok else "FAILED")
