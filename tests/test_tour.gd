extends Node
func run():
	Timetable.build(3)
	var t1 := Time.get_ticks_msec()
	StationPlan.warm_all()
	print("warm_all ms ", Time.get_ticks_msec() - t1)
	var t0 := 9.0 * 3600.0
	var start: int = Net.name_to_idx["Oxford Circus"]
	var a := Time.get_ticks_msec()
	var all := Planner.plan_all(start, "hall_unpaid", t0)
	print("plan_all ms ", Time.get_ticks_msec() - a, " reachable ", all.size())
	for n in [3, 4]:
		var tg: Array = []
		for nm in ["Canary Wharf", "Heathrow Terminal 4", "Walthamstow Central", "Morden", "Stratford"].slice(0, n): tg.append(Net.name_to_idx[nm])
		var b := Time.get_ticks_msec()
		var res := Planner.plan_tour(start, "hall_unpaid", t0, tg)
		print("tour n=", n, " ms ", Time.get_ticks_msec() - b, " calls ", res.get("calls"), " total ", Clock.fmt_dur(res.get("duration", 0)), " order ", res.get("order", []).map(func(i): return Net.station_name(i)))
