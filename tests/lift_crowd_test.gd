extends Node3D
## The crowd of a lift-only station (Hampstead: no escalators in reality) rides the lifts: people walk to a lift door, vanish for a while and come out of the other one; nobody crosses the gap
## between the levels on foot (no agent stands between two floors).
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func run():
	Timetable.build(9)
	Clock.set_time(8.5 * 3600.0)
	Clock.running = true
	var plan := StationPlan.for_station(Net.name_to_idx["Hampstead"])
	check(plan.lift_only and plan.escs.any(func(e): return e.get("removed", false)), "Hampstead is a lift-only station (its escalator-type bank is replaced by lifts)")
	add_child(Env.make(0))
	var st := Station.new()
	add_child(st)
	st.build(plan)
	var player := Player.new()
	add_child(player)
	player.enabled = false
	player.global_position = Vector3(0, 0, -10)
	st.trains.setup(st, player)
	st.attach_crowd(player)
	st.crowd.density = 1.5
	check(st.crowd != null, "the station has a crowd")
	var floors: Array = [0.0]
	for rm in plan.rooms:
		floors.append(float(rm.get("y", 0.0)))
	var between := 0
	var hop_seen := false
	for f in 3600:
		await get_tree().process_frame
		for a in st.crowd.agents:
			if a.state == "hop":
				hop_seen = true
			elif a.state == "walk":
				# on foot: within a metre of some floor (stairs flights are the exception: they are real ramps)
				var near := false
				for fy in floors:
					if absf(a.pos.y - fy) < 1.2:
						near = true
				if not near and not a.esc.is_empty():
					near = true
				if not near:
					between += 1
	print("  agents %d, lift rides %d" % [st.crowd.agents.size(), st.crowd.stats["lift_rides"]])
	check(hop_seen and st.crowd.stats["lift_rides"] > 0, "people ride the lifts (%d rides)" % st.crowd.stats["lift_rides"])
	check(between < 40, "nobody crosses the levels on foot (%d samples between floors)" % between)
	print("OK" if ok else "FAILED")
