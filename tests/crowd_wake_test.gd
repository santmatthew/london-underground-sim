extends Node3D
## A person waking up beside a standing player must not push the player: its collision body has to enter the physics space where the person is, not at the crowd node's origin and then be moved
## (found by the hub journeys: at the start of a journey the player stood at the hall origin when the first crowd woke and was thrown 0.9 m up and carried 10 m away). Stands a real Player at the
## station origin on the hall floor, wakes people at positions far away, and fails if the player moves at all or touches a crowd body.
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	Timetable.build(1)
	Clock.set_time(9.0 * 3600.0)
	add_child(Env.make(0))
	var plan := StationPlan.for_station(Net.name_to_idx["Hanger Lane"])
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
	# the player stands at the origin of the station's frame, on the hall floor
	player.global_position = st.to_global(Vector3(0.0, 0.05, 0.0))
	for i in 12:
		await get_tree().physics_frame
	var y0 := player.global_position.y
	var p0 := player.global_position
	check(absf(y0) < 0.2, "the player stands on the hall floor (y %.2f)" % y0)
	var touched := ""
	var worst := 0.0
	for k in 6:
		var a: CrowdManager.Agent = st.crowd._mk(100 + k)
		a.pos = Vector3(8.0 + k, 0.0, 5.0 + k)
		a.state = "wait"
		a.pts = []
		st.crowd._wake(a)
		for i in 3:
			await get_tree().physics_frame
			worst = maxf(worst, player.global_position.distance_to(p0))
			var sc := player.get_last_slide_collision()
			if sc != null and sc.get_collider() != null and str((sc.get_collider() as Node).get_path()).contains("Crowd"):
				touched = str((sc.get_collider() as Node).get_path())
	check(touched == "", "the player never touches a person who wakes up elsewhere (%s)" % touched)
	check(worst < 0.05, "the player is not moved by it (moved %.2f m)" % worst)
	print("OK" if ok else "FAILED")
