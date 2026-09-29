extends Node
func run():
	print("stations: ", Net.stations.size())
	Timetable.build(12345)
	print("build ms: ", Timetable.build_ms, "  runs: ", Timetable.run_line.size())
	var evn := 0
	for e in Timetable.events: evn += e.size()
	print("events: ", evn)
	var oc = Net.name_to_idx["Oxford Circus"]
	var t := 8.0 * 3600.0
	for pid in Net.stations[oc]["platforms"]:
		var gp = Timetable.global_platform(oc, pid)
		var s := "%s: " % pid
		for d in Timetable.next_departures(gp, t, 4):
			s += "[%s %s in %d s] " % [d["line"], Timetable.run_name(d["run"]), int(d["dep"] - t)]
		print(s)
	var bs = Net.name_to_idx["Baker Street"]
	for pid in Net.stations[bs]["platforms"]:
		var gp = Timetable.global_platform(bs, pid)
		var s := "BS %s: " % pid
		for d in Timetable.next_departures(gp, 17.5*3600, 4):
			s += "[%s %s in %d s] " % [d["line"], Timetable.run_name(d["run"]), int(d["dep"] - 17.5*3600)]
		print(s)
	# run count check for 16-bit run ids
	print("max run id ok: ", Timetable.run_line.size() < 65535)

	# invariants: no overlapping visits per platform face, sorted; report delays
	var bad := 0
	var checked := 0
	var per := {}
	for r in Timetable.run_line.size():
		var gp: PackedInt32Array = Timetable.run_plat[r]
		var fc: PackedByteArray = Timetable.run_face[r]
		var a: PackedFloat32Array = Timetable.run_arr[r]
		var d: PackedFloat32Array = Timetable.run_dep[r]
		for k in gp.size():
			var key = gp[k] * 2 + fc[k]
			if not per.has(key): per[key] = []
			per[key].append([a[k], d[k]])
	for key in per:
		var l: Array = per[key]
		l.sort_custom(func(x, y): return x[0] < y[0])
		for i in range(1, l.size()):
			checked += 1
			if l[i][0] < l[i-1][1] - 0.01: bad += 1
	print("overlap check: ", bad, " overlaps of ", checked)
	# lateness: compare run duration to nominal
	var maxlen := 0.0
	for r in Timetable.run_line.size():
		maxlen = maxf(maxlen, Timetable.run_t1[r] - Timetable.run_t0[r])
	print("longest run (min): ", maxlen / 60.0)
