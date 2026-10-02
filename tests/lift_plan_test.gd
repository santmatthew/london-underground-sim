extends Node
## Lifts in the plans (step-free journeys): how many stations get a lift beside every escalator / stair bank (sf_ok), and in those that do, is every platform face reachable from the street
## door on the step-free graph (lifts, no escalators or stairs) while the normal graph is untouched (no lift node reachable in it)?  args: --list (print the stations that cannot have lifts)
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func run():
	var list := OS.get_cmdline_user_args().has("--list")
	var n_ok := 0
	var n_no := 0
	var bad_reach: Array = []
	var leaks: Array = []
	var failed: Array = []
	var no_esc := 0
	for idx in Net.stations.size():
		var p := StationPlan.for_station(idx)
		if p.escs.is_empty():
			no_esc += 1
		if not p.sf_ok:
			n_no += 1
			failed.append(p.name)
			continue
		n_ok += 1
		# the normal graph never reaches a lift node; the step-free one reaches every face from every street door
		for n in p.nodes:
			if String(n["name"]).begins_with("lift"):
				for sd in p.street_doors:
					if p.walk_time(sd["id"], n["name"], false) < 1e8:
						leaks.append("%s %s" % [p.name, n["name"]])
		for fk in p.faces:
			for sd in p.street_doors:
				if p.walk_time(sd["id"], "face:" + fk, true) >= 1e8:
					bad_reach.append("%s: %s -> %s" % [p.name, sd["id"], fk])
	# normal play: stations with real lifts (TfL facility record) get them in the walking graph of the player and the planner, others do not
	var real := 0
	var real_reach := 0
	for idx in Net.stations.size():
		var p := StationPlan.for_station(idx)
		if p.lifts_real and p.sf_ok and not p.lifts.is_empty():
			real += 1
			var reach := true
			for fk in p.faces:
				if p.walk_time(p.street_doors[0]["id"], "face:" + fk, false, true) >= 1e8:
					reach = false
			if reach:
				real_reach += 1
		elif not p.lifts_real:
			for n in p.nodes:
				if String(n["name"]).begins_with("lift") and p.walk_time(p.street_doors[0]["id"], n["name"], false, true) < 1e8:
					leaks.append("%s %s (no real lifts)" % [p.name, n["name"]])
	print("  stations with real lifts: %d, every face reachable with them: %d" % [real, real_reach])
	check(real > 70 and real_reach == real, "every station with real lifts can be walked with lifts (%d of %d)" % [real_reach, real])
	print("  stations whose every escalator / stair bank has a lift: %d of %d (%d have no vertical link at all)" % [n_ok, Net.stations.size(), no_esc])
	if list:
		print("  without: ", failed)
	check(n_ok > Net.stations.size() * 0.8, "at least 80 %% of the stations can have lifts (%d)" % n_ok)
	check(leaks.is_empty(), "no lift node is reachable in the normal graph %s" % str(leaks.slice(0, 3)))
	check(bad_reach.is_empty(), "every face is reachable step-free from every street door %s" % str(bad_reach.slice(0, 3)))
	print("OK" if ok else "FAILED")
