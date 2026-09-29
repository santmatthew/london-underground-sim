extends Node
func run():
	Timetable.build(12345)
	print("timetable ms ", Timetable.build_ms)
	var cases := [["Oxford Circus", "Canary Wharf", 8.0], ["Epping", "Morden", 8.5], ["Heathrow Terminal 5", "Cockfosters", 14.0], ["Baker Street", "Bank", 23.7], ["Brixton", "Walthamstow Central", 17.5], ["Ealing Broadway", "Upminster", 9.0], ["Stanmore", "Amersham", 12.0]]
	for c in cases:
		var a: int = Net.name_to_idx[c[0]]
		var b: int = Net.name_to_idx[c[1]]
		var t0: float = c[2] * 3600.0
		var t1 := Time.get_ticks_msec()
		var res := Planner.plan(a, "hall_unpaid", t0, b)
		print("%s -> %s @ %s   [%d ms]" % [c[0], c[1], Clock.fmt(t0), Time.get_ticks_msec() - t1])
		print(Planner.describe(res, t0))
