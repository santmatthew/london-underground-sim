extends Node
## Step-free journeys on the planner level: the station list, platforms, the journey picker and the planner only use step-free platforms, and every planned journey is possible.
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func run():
	Timetable.build(1)
	StationPlan.warm_all()
	var kn: int = Net.name_to_idx["Kennington"]
	var gp: int = Net.name_to_idx["Green Park"]
	var ox: int = Net.name_to_idx["Oxford Circus"]
	check(not StepFree.station_ok(kn) and not StepFree.station_ok(ox), "Kennington and Oxford Circus have no step-free platforms")
	check(StepFree.station_ok(gp) and StepFree.platform_ok(gp, "victoria:Northbound"), "Green Park does (Victoria, Jubilee, Piccadilly)")
	var list := StepFree.station_list()
	print("  step-free stations: %d" % list.size())
	check(list.size() > 50 and list.size() < 150, "a sensible number of step-free stations (%d)" % list.size())
	StationPlan.step_free_mode = true
	var rng := RandomNumberGenerator.new()
	var bad := 0
	var made := 0
	for seed in range(1, 13):
		rng.seed = seed
		var j := Journey.generate(rng, {"time": "midday", "length": "medium"})
		if j.is_empty():
			continue
		made += 1
		if not (StepFree.station_ok(j["start"]) and StepFree.station_ok(j["dest"])):
			bad += 1
		for leg in j["par"]["legs"]:
			var gps: PackedInt32Array = Timetable.run_plat[leg["run"]]
			var pf: String = Timetable.plat_pid[gps[leg["k"]]]
			var pt: String = Timetable.plat_pid[gps[leg["j"]]]
			if not (StepFree.platform_ok(leg["from"], pf) and StepFree.platform_ok(leg["to"], pt)):
				bad += 1
	check(made >= 10 and bad == 0, "%d step-free journeys picked, every start, destination and boarding / alighting platform step-free (%d violations)" % [made, bad])
	# the same pair planned normally and step-free: step-free is never faster
	rng.seed = 5
	var a := StepFree.station_list()
	var s0: int = a[0]
	var d0: int = a[a.size() / 2]
	var sf := Planner.plan(s0, "street0", 11.0 * 3600.0, d0)
	StationPlan.step_free_mode = false
	var nm := Planner.plan(s0, "street0", 11.0 * 3600.0, d0)
	check(sf.get("ok", false) and nm.get("ok", false) and float(sf["arrive"]) >= float(nm["arrive"]) - 0.5, "step-free takes at least as long as normal (%s vs %s)" % [Clock.fmt(sf.get("arrive", 0.0)), Clock.fmt(nm.get("arrive", 0.0))])
	print("OK" if ok else "FAILED")
