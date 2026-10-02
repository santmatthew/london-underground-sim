extends Node
## Lifts in the real game: the station has lifts (normal play: a station that has lifts in reality, no closed escalators; --mode=stepfree: every station, and a barrier across each escalator), the interact prompt
## appears at a lift door, and riding a lift takes the player to the other end of the bank facing out of the door, with the clock moved on by the ride.
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func run():
	var sf := OS.get_cmdline_user_args().has("--mode=stepfree")
	Settings.set_v("access", "step_free", sf, false)
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {"seed": "5", "start": "Green_Park" if sf else "Kennington", "dest": "Southwark" if sf else "Oxford_Circus", "spot": "ticket_hall", "hour": "10"}
	add_child(g)
	await get_tree().process_frame
	g.start_journey()
	var t0 := Time.get_ticks_msec()
	while g.state != Game.State.BRIEFING and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	check(g.state == Game.State.BRIEFING and StationPlan.step_free_mode == sf, "the journey reaches the briefing (%s)" % ("step-free from Green Park" if sf else "normal, from Kennington"))
	g._begin_play()
	for i in 10:
		await get_tree().process_frame
	var st: Station = g.station
	check(st.lift_doors.size() == st.plan.lifts.size() * 2 and st.lift_doors.size() >= 2, "the station has %d lift doors" % st.lift_doors.size())
	var barriers := 0
	for c in st.fitting_root.get_children():
		if String(c.name).begins_with("Barrier"):
			barriers += 1
	check(barriers == (st.plan.lifts.size() * 2 if sf else 0), "barriers across the banks: %d (%s)" % [barriers, "step-free journeys close the escalators" if sf else "none in normal play"])
	var door: Node3D = st.lift_doors[0]
	g.player.global_position = door.global_position + Vector3(0, 0.05, 0)
	g.player.velocity = Vector3.ZERO
	for i in 3:
		await get_tree().process_frame
	check(g._nearest_lift_door() == door, "the lift door in front of the player is found")
	g._update_seat_prompt()
	check(g.hud.prompt_label.text.contains("Call the lift"), "the prompt offers the lift (%s)" % g.hud.prompt_label.text)
	var clock0 := Clock.now
	var to: Vector3 = st.to_global(door.get_meta("to"))
	g._on_interact()
	check(g._lift_busy, "the ride starts")
	var w0 := Time.get_ticks_msec()
	while g._lift_busy and Time.get_ticks_msec() - w0 < 60000:
		await get_tree().process_frame
	check(not g._lift_busy and g.player.global_position.distance_to(to) < 0.4, "the player comes out at the other door (%.2f m away)" % g.player.global_position.distance_to(to))
	var out: Vector3 = st.global_transform.basis * (door.get_meta("to_out") as Vector3)
	check(g.player.forward().dot(out) > 0.9, "facing out of the door")
	var took := Clock.now - clock0
	check(took > float(door.get_meta("time")) * 0.8 and took < float(door.get_meta("time")) * 1.6, "the ride took %d s of the clock (lift time %d s)" % [int(took), int(float(door.get_meta("time")))])
	check(not g.player.frozen, "the player can move again")
	Settings.set_v("access", "step_free", false, false)
	StationPlan.step_free_mode = false
	print("OK" if ok else "FAILED")
