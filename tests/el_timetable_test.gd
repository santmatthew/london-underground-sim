extends Node
## The Elizabeth line's timetable: services exist in both directions all day, the core carries about the planned trains per hour, journey times are plausible (real: Abbey Wood - Paddington about
## 30 min, Shenfield - Paddington about 40 min, Reading - Paddington about 50 min), and platform conflicts at the terminating platforms do not drag trains far behind their nominal times.
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func run():
	Timetable.build(5)
	var by_svc := {}
	var late_max := 0.0
	for r in Timetable.run_line.size():
		if Timetable.run_line[r] != "elizabeth":
			continue
		var svc: String = Timetable.run_svc[r]
		if not by_svc.has(svc):
			by_svc[svc] = []
		by_svc[svc].append(r)
	check(by_svc.size() == 10, "ten services run (%d)" % by_svc.size())
	var wpl: int = Net.name_to_idx["Whitechapel"]
	# trains per hour through Whitechapel's eastbound platform, by hour of the day (departure events)
	var gp: int = Timetable.plat_index[wpl]["elizabeth:Eastbound"]
	var per_hour := {}
	for key in Timetable.events[gp]:
		var h := int(Timetable.ev_time(key) / 3600.0)
		per_hour[h] = int(per_hour.get(h, 0)) + 1
	print("    Whitechapel eastbound departures per hour: ", str(per_hour))
	check(int(per_hour.get(8, 0)) >= 18 and int(per_hour.get(8, 0)) <= 32, "08:00 peak: %d trains an hour through Whitechapel eastbound" % int(per_hour.get(8, 0)))
	check(int(per_hour.get(12, 0)) >= 10 and int(per_hour.get(12, 0)) <= 22, "12:00: %d" % int(per_hour.get(12, 0)))
	# journey times of the three main patterns (end to end, first run of the morning peak)
	var names := {"Abbey Wood – Paddington": [25.0, 45.0], "Shenfield – Paddington": [35.0, 60.0], "London Paddington – Reading": [45.0, 80.0]}
	for r in Timetable.run_line.size():
		if Timetable.run_line[r] != "elizabeth":
			continue
		var svc_name: String = Net.lines["elizabeth"]["services"][int(String(Timetable.run_svc[r]).get_slice("-", 1))]["name"]
		if names.has(svc_name) and Timetable.run_t0[r] > 7.5 * 3600.0:
			var mins: float = (Timetable.run_t1[r] - Timetable.run_t0[r]) / 60.0
			var lim: Array = names[svc_name]
			check(mins >= lim[0] and mins <= lim[1], "%s takes %.0f min (expected %d to %d)" % [svc_name, mins, int(lim[0]), int(lim[1])])
			names.erase(svc_name)
	# no train is badly late: compare each run's duration with its service's nominal run (the same service the quietest hour)
	var worst := 0.0
	for svc in by_svc:
		var durs: Array = []
		for r in by_svc[svc]:
			durs.append(Timetable.run_t1[r] - Timetable.run_t0[r])
		durs.sort()
		var med: float = durs[durs.size() / 2]
		worst = maxf(worst, float(durs[durs.size() - 1]) / med)
	check(worst < 1.6, "the slowest run of any service takes %.2f times the median" % worst)
	print("OK" if ok else "FAILED")
