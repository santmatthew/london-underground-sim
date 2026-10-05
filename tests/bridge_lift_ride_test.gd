extends Node
## The lifts of a footbridge in the real game (step-free journey from West Ealing): the lift doors are in the station, the player at the platform door rides up and comes out in the lobby on the deck
## facing out of the door, and back down from there to the platform; the barriers close the steps. (Same as lift_ride_test, for the lifts that Footbridge draws.)
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func run():
	Settings.set_v("access", "step_free", true, false)
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {"seed": "5", "start": "West_Ealing", "dest": "Southall", "spot": "ticket_hall", "hour": "10"}
	add_child(g)
	await get_tree().process_frame
	g.start_journey()
	var t0 := Time.get_ticks_msec()
	while g.state != Game.State.BRIEFING and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	check(g.state == Game.State.BRIEFING and StationPlan.step_free_mode, "the step-free journey reaches the briefing")
	g._begin_play()
	for i in 10:
		await get_tree().process_frame
	var st: Station = g.station
	var bridge_doors: Array = []
	for d in st.lift_doors:
		if int(d.get_meta("lift")) >= 100:
			bridge_doors.append(d)
	check(bridge_doors.size() == 4 * st.plan.bridges.size(), "the bridge's lift doors are there (%d)" % bridge_doors.size())
	var barriers := 0
	for c in st.fitting_root.get_children():
		if String(c.name).begins_with("BridgeBarrier"):
			barriers += 1
	check(barriers == 4 * st.plan.bridges.size(), "the steps of the bridge are closed with barriers (%d)" % barriers)
	if bridge_doors.is_empty():
		print("FAILED")
		return
	var door: Node3D = null
	for d in bridge_doors:
		if int(d.get_meta("lift")) == 100 and String(d.get_meta("end")) == "bot":
			door = d
	check(door != null, "the platform door of the first lift is found")
	g.player.global_position = door.global_position + Vector3(0, 0.05, 0)
	g.player.velocity = Vector3.ZERO
	for i in 3:
		await get_tree().process_frame
	check(door != null and g._nearest_lift_door() == door, "the player finds the door in front of them")
	var to: Vector3 = st.to_global(door.get_meta("to"))
	g._on_interact()
	check(g._lift_busy, "the ride starts")
	var w0 := Time.get_ticks_msec()
	while g._lift_busy and Time.get_ticks_msec() - w0 < 60000:
		await get_tree().process_frame
	check(not g._lift_busy and g.player.global_position.distance_to(to) < 0.4, "the player comes out in the lobby on the deck (%.2f m from the other door's front)" % g.player.global_position.distance_to(to))
	var plat_y: float = (door as Node3D).global_position.y          # (the platform door's own floor: where the ride began)
	check(g.player.global_position.y > plat_y + Footbridge.DECK_Y - 0.5 and g.player.global_position.y < plat_y + Footbridge.DECK_Y + 0.5, "... on the deck, %.1f m above the platform (y %.1f, the deck is %.1f m up)" % [g.player.global_position.y - plat_y, g.player.global_position.y, Footbridge.DECK_Y])
	var out: Vector3 = st.global_transform.basis * (door.get_meta("to_out") as Vector3)
	check(g.player.forward().dot(out) > 0.9, "facing out of the door")
	# and the way back: the upper door takes the player down to the platform
	var up_door: Node3D = null
	for d in bridge_doors:
		if int(d.get_meta("lift")) == 100 and String(d.get_meta("end")) == "top":
			up_door = d
	for i in 3:
		await get_tree().process_frame
	check(up_door != null and g._nearest_lift_door() == up_door, "the lift door on the deck is found")
	var back: Vector3 = st.to_global(up_door.get_meta("to"))
	g._on_interact()
	var w1 := Time.get_ticks_msec()
	while g._lift_busy and Time.get_ticks_msec() - w1 < 60000:
		await get_tree().process_frame
	check(not g._lift_busy and g.player.global_position.distance_to(back) < 0.4, "and down again to the platform door (%.2f m)" % g.player.global_position.distance_to(back))
	check(not g.player.frozen, "the player can move again")
	Settings.set_v("access", "step_free", false, false)
	StationPlan.step_free_mode = false
	print("OK" if ok else "FAILED")
