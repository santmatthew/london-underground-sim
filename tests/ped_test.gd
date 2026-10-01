extends Node3D
## Platform edge doors (Jubilee Line Extension stations): the leaves exist at every train door position, slide apart when the edge guard is opened for a door
## and close again; platforms of other stations have none.
var ok := true


func check(cond: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		ok = false


func run():
	Timetable.build(1)
	Clock.set_time(11.0 * 3600.0)
	add_child(Env.make(0))
	# the doors computed without a train are the doors of a built train
	var tr := Train.new()
	add_child(tr)
	tr.build("deep", 7, "jubilee", Color(0.5, 0.5, 0.5))
	var built: Array = tr.door_positions()
	var calc: Array = Train.door_positions_for("deep", 7)
	built.sort()
	calc.sort()
	var same := built.size() == calc.size()
	for i in mini(built.size(), calc.size()):
		if absf(float(built[i]) - float(calc[i])) > 0.001:
			same = false
	check(same, "door_positions_for matches a built train (%d doors)" % built.size())
	tr.queue_free()
	for sname in ["Canary Wharf", "Westminster", "Bank"]:
		var plan := StationPlan.for_station(Net.name_to_idx[sname])
		var st := Station.new()
		add_child(st)
		st.build(plan)
		await get_tree().physics_frame
		var with_peds := 0
		for pm in st.modules:
			var m: PlatformModule = pm
			if m.ped_xs.is_empty():
				continue
			with_peds += 1
			var n := m.ped_xs.size()
			check(n >= 18, "%s: %d doors per face" % [sname, n])
			for fs in m.ped_doors.keys():
				var pairs: Array = m.ped_doors[fs]
				check(pairs.size() == n, "%s: face %d has %d door pairs" % [sname, int(fs), pairs.size()])
				var p0: Dictionary = pairs[n / 2]
				var x0: float = p0["x"]
				var closed_gap: float = (p0["r"] as Node3D).position.x - (p0["l"] as Node3D).position.x
				check(absf(closed_gap - PlatformDoors.OPEN_W * 0.5) < 0.01, "%s: closed leaves meet (gap %.2f)" % [sname, closed_gap])
				m.set_edge_open(fs, x0 - 0.8, x0 + 0.8, true)
				await get_tree().create_timer(2.2).timeout
				var open_gap: float = (p0["r"] as Node3D).position.x - (p0["l"] as Node3D).position.x
				check(open_gap > PlatformDoors.OPEN_W + 0.9, "%s: open leaves clear a %.2f m gap" % [sname, open_gap])
				check(open_gap - PlatformDoors.OPEN_W * 0.5 >= PlatformDoors.OPEN_W * 0.99, "%s: the opening is at least one door wide" % sname)
				m.set_edge_open(fs, x0 - 0.8, x0 + 0.8, false)
				await get_tree().create_timer(2.0).timeout
				closed_gap = (p0["r"] as Node3D).position.x - (p0["l"] as Node3D).position.x
				check(absf(closed_gap - PlatformDoors.OPEN_W * 0.5) < 0.01, "%s: shut again" % sname)
				break
		if sname == "Bank":
			check(with_peds == 0, "Bank has no platform edge doors")
		else:
			check(with_peds >= 1, "%s has platform edge doors (%d modules)" % [sname, with_peds])
		st.queue_free()
		await get_tree().process_frame
	print("OK" if ok else "FAILED")
