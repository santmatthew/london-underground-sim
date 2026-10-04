extends Node3D
## A train that spawns on the track beside a standing player must not push the player (the same trap as the crowd's bodies: a collision body that enters the physics space at its parent's origin and is moved
## afterwards). Stands a real Player on a platform at the middle of a module and runs the train service until a train has spawned and stopped. args: --station="Hanger Lane"
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	var sname := "Hanger Lane"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): sname = a.substr(10)
	Timetable.build(1)
	var idx: int = Net.name_to_idx[sname]
	var plan := StationPlan.for_station(idx)
	# a time at which some train is about to arrive at the first module's first face
	var f0: Dictionary = plan.faces[plan.faces.keys()[0]]
	var gp: int = Timetable.plat_index[idx][f0["pid"]]
	Clock.set_time(9.0 * 3600.0)
	var vis: Array = Timetable.visits_between(gp, Clock.now, Clock.now + 900.0)
	var due := 9.0 * 3600.0
	for v in vis:
		if not v["origin"]:
			due = float(v["arr"])
			break
	Clock.set_time(due - 40.0)
	add_child(Env.make(0))
	var st := Station.new()
	add_child(st)
	st.build(plan)
	var player := Player.new()
	add_child(player)
	player.bot_active = true
	player.enabled = true
	st.trains.setup(st, player)
	st.attach_crowd(player)
	st.crowd.enabled = false
	var pm: PlatformModule = st.modules[f0["module"]]
	var side: float = f0["side"]
	var platform_z: float = side * (PlatformModule.GAP * 0.5 + float(pm.meta["pw"]) * 0.5)
	player.global_position = pm.to_global(Vector3(0.0, 0.1, platform_z))
	for i in 10:
		await get_tree().physics_frame
	var p0 := player.global_position
	var worst := 0.0
	var spawned := 0
	var seen := {}
	for i in 60 * 50:
		await get_tree().physics_frame
		worst = maxf(worst, player.global_position.distance_to(p0))
		for k in st.trains.visits:
			seen[k] = true
	spawned = seen.size()
	check(spawned > 0, "a train spawned during the test (%d visits, clock %s)" % [spawned, Clock.fmt(Clock.now, true)])
	check(worst < 0.05, "the player on the platform was not moved by the trains arriving (moved %.2f m)" % worst)
	print("OK" if ok else "FAILED")
