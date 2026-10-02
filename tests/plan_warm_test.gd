extends Node
## The background builds at start-up: StationPlan.warm_all_async (all plans on worker threads) and Timetable.build_async must give exactly what the synchronous calls give,
## and the main thread must keep running frames while they work.
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func run():
	var t0 := Time.get_ticks_msec()
	StationPlan.warm_all_async()
	var frames := 0
	while not StationPlan.warm_ready():
		await get_tree().process_frame
		frames += 1
	print("  workers done after %d ms, the main thread ran %d frames meanwhile" % [Time.get_ticks_msec() - t0, frames])
	check(frames > 3, "the main thread kept running while the plans were built")
	StationPlan.warm_all()
	check(StationPlan._all_warm, "warm_all after the workers: all warm")
	var bad := 0
	var sample := 0
	for i in range(0, Net.stations.size(), 7):
		var fresh := StationPlan.new()
		fresh.generate(i)
		var p := StationPlan.for_station(i)
		sample += 1
		var same := p.nodes.size() == fresh.nodes.size() and p.edges.size() == fresh.edges.size() and p.name == fresh.name and p.modules.size() == fresh.modules.size()
		if same and not p.nodes.is_empty():
			var a: String = p.nodes[0]["name"]
			var b: String = p.nodes[p.nodes.size() - 1]["name"]
			same = absf(p.walk_time(a, b) - fresh.walk_time(a, b)) < 0.001
		if not same:
			bad += 1
			print("  differs: ", Net.station_name(i))
		if p._dcache.size() != p.nodes.size():
			bad += 1
			print("  walk-time cache incomplete: ", p.name)
	check(bad == 0, "%d sampled plans identical to synchronous ones" % sample)
	check(StationPlan.for_station(5) == StationPlan.for_station(5), "the cache hands out one object per station")
	# timetable
	Timetable.build(7)
	var runs := Timetable.run_line.size()
	var ev := 0
	for e in Timetable.events:
		ev += (e as PackedInt64Array).size()
	var t1 := Time.get_ticks_msec()
	await Timetable.build_async(7)
	print("  timetable build_async finished in %d ms" % (Time.get_ticks_msec() - t1))
	var runs2 := Timetable.run_line.size()
	var ev2 := 0
	for e in Timetable.events:
		ev2 += (e as PackedInt64Array).size()
	check(runs == runs2 and ev == ev2 and runs > 1000, "async timetable = sync timetable (%d runs, %d events)" % [runs2, ev2])
	print("OK" if ok else "FAILED")
