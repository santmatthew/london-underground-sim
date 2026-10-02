extends Node
## Spiral emergency stairs in the plans: the five stations that have one get doors in a wall of the ticket hall and of the deepest landing, a tower far from the rooms, a step count that
## is the sourced one (data/vertical_access.json) where there is one, a riser a person can climb, and a route through the stair from the street to every platform face on the player's graph.
## The normal (crowd) graph and the step-free one never use the stair.  args: --verbose
var ok := true
var verbose := false


func check(c: bool, what: String) -> void:
	if verbose or not c:
		print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func run():
	verbose = OS.get_cmdline_user_args().has("--verbose")
	var n := 0
	for idx in Net.stations.size():
		var nap: String = Net.station_ids[idx]
		var va := StationPlan.vertical_access(nap)
		var want: bool = va.has("spiral")
		var p := StationPlan.for_station(idx)
		if not want:
			if p.spirals.size() > 0:
				check(false, "%s has no spiral stair in the data but the plan has one" % p.name)
			continue
		n += 1
		check(p.spirals.size() == 1, "%s: one spiral stair" % p.name)
		if p.spirals.is_empty():
			continue
		var sp: Dictionary = p.spirals[0]
		var src = (va["spiral"] as Dictionary).get("steps", null)
		if src != null:
			check(int(sp["steps"]) == int(src), "%s: %d steps as sourced" % [p.name, int(sp["steps"])])
		check(float(sp["riser"]) <= 0.215 and float(sp["riser"]) >= 0.12, "%s: riser %.3f m (rise %.1f m over %d steps)" % [p.name, float(sp["riser"]), float(sp["rise"]), int(sp["steps"])])
		check(not sp["top"].is_empty() and not sp["bot"].is_empty(), "%s: a door in the hall and one in the deepest landing" % p.name)
		# the planner never uses the stair (par times are the lifts'); with `spiral_mode` the way to every face goes through it when it is shorter, and the stair is walkable end to end
		var faces := 0
		var via_default := 0
		var via_spiral := 0
		for fk in p.faces:
			faces += 1
			StationPlan.spiral_mode = false
			if p.path(p.street_doors[0]["id"], "face:" + fk, false, true).has("spiral0_tin"):
				via_default += 1
			StationPlan.spiral_mode = true
			if p.path("spiral0_top", "spiral0_bot", false, true).has("spiral0_tin"):
				via_spiral += 1
			check(p.walk_time("spiral0_bot", "face:" + fk, false, true) < 1e8, "%s: %s reachable from the stair's bottom door" % [p.name, fk])
		StationPlan.spiral_mode = false
		check(via_default == 0, "%s: the planner never routes through the stair (%d of %d faces)" % [p.name, via_default, faces])
		check(via_spiral == faces, "%s: with spiral_mode the way from the top door to the bottom one is the stair (%d of %d)" % [p.name, via_spiral, faces])
		var dt: float = p.walk_time("spiral0_top", "spiral0_bot", false, true)
		StationPlan.spiral_mode = true
		var ds: float = p.walk_time("spiral0_top", "spiral0_bot", false, true)
		StationPlan.spiral_mode = false
		check(ds < 1e8 and ds > 3.0 * 2 + float(sp["steps"]) * 0.3 and ds < 1e5, "%s: the stair takes %.0f s door to door (default graph: %s)" % [p.name, ds, "none" if dt >= 1e8 else "%.0f s" % dt])
		if verbose:
			print("    %s: tower %s, top door %s (%s), bottom door %s (%s)" % [p.name, sp["tower"], sp["top"]["pos"], sp["top"]["room"], sp["bot"]["pos"], sp["bot"]["room"]])
		for fk in p.faces:
			check(p.walk_time(p.street_doors[0]["id"], "face:" + fk, false, true) < 1e8, "%s: %s reachable (lifts graph)" % [p.name, fk])
		for nm in ["spiral0_tin", "spiral0_tout", "spiral0_top", "spiral0_bot"]:
			check(p.walk_time(p.street_doors[0]["id"], nm, false, false) >= 1e8, "%s: crowd graph never reaches %s" % [p.name, nm])
			check(p.walk_time(p.street_doors[0]["id"], nm, true, false) >= 1e8, "%s: step-free graph never reaches %s" % [p.name, nm])
	print("  %d stations with a spiral stair, %d checks failed so far" % [n, 0 if ok else 1])
	check(n == 5, "five stations have spiral stairs (%d)" % n)
	print("OK" if ok else "FAILED")
