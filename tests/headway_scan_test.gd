extends Node
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


## How tight the timetable is: for every platform face, the gaps between a train leaving and the next one arriving (08:00 - 10:00), counted in bands; and visits per hour of the busiest faces. args --from=8 --to=10
func run():
	var h0 := 8.0
	var h1 := 10.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--from="): h0 = float(a.substr(7))
		if a.begins_with("--to="): h1 = float(a.substr(5))
	Timetable.build(1)
	var bands := [12.0, 20.0, 25.0, 30.0, 40.0, 60.0]
	var counts := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	var worst := []
	var total := 0
	for gp in Timetable.plat_station.size():
		var last_dep := {}
		var n := 0
		for vv in Timetable.visits_between(gp, h0 * 3600.0, h1 * 3600.0):
			var fno: int = (Timetable.run_face[vv["run"]] as PackedByteArray)[vv["k"]]
			if last_dep.has(fno):
				var gap: float = vv["arr"] - last_dep[fno]
				total += 1
				var bi := 0
				while bi < bands.size() and gap >= bands[bi]:
					bi += 1
				counts[bi] += 1
				if gap < 20.0:
					worst.append([gap, gp, vv["run"]])
			last_dep[fno] = vv["dep"]
			n += 1
	print("gaps between a departure and the next arrival on the same face, %s-%s h: " % [str(h0), str(h1)], total)
	print("  <12 s ", counts[0], " <20 s ", counts[1], " <25 s ", counts[2], " <30 s ", counts[3], " <40 s ", counts[4], " <60 s ", counts[5], " >=60 s ", counts[6])
	worst.sort_custom(func(x, y): return x[0] < y[0])
	for i in mini(8, worst.size()):
		var gp: int = worst[i][1]
		print("  %.1f s at %s %s (run %d)" % [worst[i][0], Net.stations[Timetable.plat_station[gp]]["name"], Timetable.plat_pid[gp], worst[i][2]])
	check(total > 5000, "the window was scanned (%d gaps)" % total)
	check(counts[0] == 0, "no train arrives within 12 s of the previous one leaving (%d do)" % counts[0])
	check(float(counts[1]) / float(maxi(total, 1)) < 0.02, "fewer than 2 %% of the gaps are under 20 s (%d of %d)" % [counts[1], total])
	print("OK" if ok else "FAILED")
