extends Node3D
## The crowd walks round the player instead of into them: a player standing in the main flow of a busy hall (Oxford Circus, morning peak, a packed crowd) is never touched - no walking agent comes closer
## than the width of the two bodies (player capsule 0.27 + person cylinder 0.25) - while plenty of people do pass close by, and nobody stays stuck against the player. args: --seconds=60
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func run():
	var secs := 60.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="): secs = float(a.substr(10))
	Timetable.build(9)
	Clock.set_time(8.2 * 3600.0)
	Clock.running = true
	var plan := StationPlan.for_station(Net.name_to_idx["Oxford Circus"])
	add_child(Env.make(0))
	var st := Station.new()
	add_child(st)
	st.build(plan)
	var player := Player.new()
	add_child(player)
	player.enabled = false
	# in the walkway between the gates and the escalators, where everybody goes past
	var spot: Vector3 = plan.nodes[plan.node_idx["hall_paid"]]["pos"]
	player.global_position = st.to_global(spot + Vector3(0.0, 0.05, 0.0))
	st.trains.setup(st, player)
	st.attach_crowd(player)
	st.crowd.density = 1.5
	var closest := 99.0
	var passed := {}
	var stuck_t := {}
	var worst_stuck := 0.0
	var t := 0.0
	while t < secs:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		var pp := st.to_local(player.global_position)
		for a in st.crowd.agents:
			if a.state != "walk" and a.state != "board" and a.state != "gate":
				continue
			if absf(a.pos.y - pp.y) > 1.5:
				continue
			var d := Vector2(a.pos.x - pp.x, a.pos.z - pp.z).length()
			closest = minf(closest, d)
			if d < 1.5:
				passed[a.seed] = true
				if a.cur < 0.05 and a.state == "walk":
					stuck_t[a.seed] = float(stuck_t.get(a.seed, 0.0)) + dt
					worst_stuck = maxf(worst_stuck, float(stuck_t[a.seed]))
				else:
					stuck_t[a.seed] = 0.0
	print("  agents %d, %d came within 1.5 m, the closest was %.2f m, the longest stand-still beside the player %.1f s" % [st.crowd.agents.size(), passed.size(), closest, worst_stuck])
	check(passed.size() >= 8, "plenty of people pass close by (%d)" % passed.size())
	check(closest >= 0.6, "nobody walks into the player (closest %.2f m; the bodies touch at 0.52)" % closest)
	check(worst_stuck < 8.0, "nobody is stuck against the player (%.1f s)" % worst_stuck)
	print("OK" if ok else "FAILED")
