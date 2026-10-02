extends Node
## The spiral emergency stair in the real game (Covent Garden, 193 steps): the doors in the hall and on the lower landing have prompts, going through one puts the player in the tower facing the
## stair, walking the helix takes the time of the steps (about 0.4 s a step down, 0.6 s up), the door at the far end leads to the other room, and the game says where the player is.
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func _door(st: Station, end: String) -> Node3D:
	for d in st.stair_doors:
		if String(d.get_meta("end")) == end:
			return d
	return null


## walk the helix points (world positions) with the player's own movement; returns the seconds it took, or -1 when it got stuck
func _walk(g: Game, pts: Array, limit: float) -> float:
	var p := g.player
	p.bot_active = true
	var t := 0.0
	var i := 0
	var stuck := 0.0
	var last := p.global_position
	while i < pts.size() and t < limit:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var tgt: Vector3 = pts[i]
		var flat := Vector3(tgt.x - p.global_position.x, 0, tgt.z - p.global_position.z)
		if flat.length() < 0.5:
			i += 1
			continue
		var dir := flat.normalized()
		p.bot_yaw_target = atan2(-dir.x, -dir.z)
		var yaw_err := absf(angle_difference(p.rotation.y, p.bot_yaw_target))
		p.bot_move = Vector2(0, -1.0 if yaw_err < 0.6 else -0.15)
		stuck = stuck + get_physics_process_delta_time() if p.global_position.distance_to(last) < 0.002 else 0.0
		last = p.global_position
		if stuck > 3.0:
			print("    stuck at ", p.global_position, " waypoint ", i, " of ", pts.size())
			break
	p.bot_move = Vector2.ZERO
	p.bot_active = false
	return t if i >= pts.size() else -1.0


func run():
	Settings.set_v("access", "step_free", false, false)
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {"seed": "5", "start": "Covent_Garden", "dest": "Holborn", "spot": "ticket_hall", "hour": "10"}
	add_child(g)
	await get_tree().process_frame
	g.start_journey()
	var t0 := Time.get_ticks_msec()
	while g.state != Game.State.BRIEFING and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	g._begin_play()
	for i in 10:
		await get_tree().process_frame
	var st: Station = g.station
	var sp: Dictionary = st.plan.spirals[0]
	check(st.has_spirals() and st.stair_doors.size() == 4 and st.towers.size() == 1, "the station has the stair: %d door anchors, %d tower" % [st.stair_doors.size(), st.towers.size()])
	var top := _door(st, "top")
	var bot_tower := _door(st, "bot_tower")
	var bot := _door(st, "bot")
	var top_tower := _door(st, "top_tower")
	check(top != null and bot != null and top_tower != null and bot_tower != null, "the four anchors are there")
	# the door in the hall
	g.player.global_position = top.global_position + Vector3(0, 0.05, 0)
	g.player.velocity = Vector3.ZERO
	for i in 3:
		await get_tree().process_frame
	check(g._nearest_stair_door() == top, "the hall's stair door is found")
	g._update_seat_prompt()
	check(g.hud.prompt_label.text.contains("emergency stairs") and g.hud.prompt_label.text.contains("193 steps") and g.hud.prompt_label.text.contains("down"), "prompt: %s" % g.hud.prompt_label.text)
	g._on_interact()
	check(g._portal_busy and g.player.frozen, "the door starts (the player is held for the fade)")
	var w0 := Time.get_ticks_msec()
	while g._portal_busy and Time.get_ticks_msec() - w0 < 20000:
		await get_tree().process_frame
	var tin: Vector3 = st.to_global(sp["tin"])
	check(not g._portal_busy and g.player.global_position.distance_to(tin) < 0.4, "the player is in the tower at the head of the stair (%.2f m)" % g.player.global_position.distance_to(tin))
	check(g.player.forward().dot(st.global_transform.basis * (sp["tin_dir"] as Vector3)) > 0.9, "facing down the stair")
	check(st.tower_at(g.player.global_position) != null and g._describe_location().begins_with("emergency stairs (193 steps)"), "the game says where the player is: %s" % g._describe_location())
	for i in 5:
		await get_tree().physics_frame
	check(g.player.is_on_floor(), "standing on the landing")
	# down the helix
	var pts_down: Array = []
	for hp in sp["interior"]:
		pts_down.append(st.to_global(hp))
	var down_s := await _walk(g, pts_down, 400.0)
	check(down_s > 0.0, "walked down to the bottom landing in %.0f s (%.2f s a step)" % [down_s, down_s / 193.0])
	check(down_s > 193.0 * 0.28 and down_s < 193.0 * 0.6, "the pace down is that of the steps")
	var tout: Vector3 = st.to_global(sp["tout"])
	check(g.player.global_position.distance_to(tout) < 1.2, "at the bottom (%.2f m from the exit, y %.2f of %.2f)" % [g.player.global_position.distance_to(tout), g.player.global_position.y, tout.y])
	for i in 20:
		await get_tree().physics_frame
	# the door at the bottom of the tower, to the lower landing
	g.player.global_position = bot_tower.global_position + Vector3(0, 0.05, 0)
	g.player.velocity = Vector3.ZERO
	for i in 3:
		await get_tree().process_frame
	g._update_seat_prompt()
	check(g.hud.prompt_label.text.contains("lower level"), "prompt at the bottom door of the tower: %s" % g.hud.prompt_label.text)
	g._on_interact()
	w0 = Time.get_ticks_msec()
	while g._portal_busy and Time.get_ticks_msec() - w0 < 20000:
		await get_tree().process_frame
	var front: Vector3 = st.to_global(sp["bot"]["front"])
	check(g.player.global_position.distance_to(front) < 0.4, "the player is on the lower landing in front of the door (%.2f m, y %.1f)" % [g.player.global_position.distance_to(front), g.player.global_position.y])
	check(g.player.forward().dot(st.global_transform.basis * (sp["bot"]["out"] as Vector3)) > 0.9 and g._describe_location() != "", "facing into the room")
	for i in 20:
		await get_tree().physics_frame
	# and up again: the door on the lower landing, up the helix, the door at the top of the tower
	g._update_seat_prompt()
	check(g.hud.prompt_label.text.contains("emergency stairs") and g.hud.prompt_label.text.contains("up"), "prompt: %s" % g.hud.prompt_label.text)
	g._on_interact()
	w0 = Time.get_ticks_msec()
	while g._portal_busy and Time.get_ticks_msec() - w0 < 20000:
		await get_tree().process_frame
	check(g.player.global_position.distance_to(tout) < 0.4 and g.player.forward().dot(st.global_transform.basis * (sp["tout_dir"] as Vector3)) > 0.9, "in the tower at the foot of the stair, facing up")
	for i in 5:
		await get_tree().physics_frame
	var pts_up := pts_down.duplicate()
	pts_up.reverse()
	var up_s := await _walk(g, pts_up, 600.0)
	check(up_s > 0.0, "walked up in %.0f s (%.2f s a step)" % [up_s, up_s / 193.0])
	check(up_s > down_s * 1.2 and up_s > 193.0 * 0.45 and up_s < 193.0 * 0.9, "up is slower than down")
	g.player.global_position = top_tower.global_position + Vector3(0, 0.05, 0)
	for i in 3:
		await get_tree().process_frame
	g._on_interact()
	w0 = Time.get_ticks_msec()
	while g._portal_busy and Time.get_ticks_msec() - w0 < 20000:
		await get_tree().process_frame
	var tfront: Vector3 = st.to_global(sp["top"]["front"])
	check(g.player.global_position.distance_to(tfront) < 0.4 and absf(g.player.global_position.y - tfront.y) < 0.2, "back in the hall in front of the door (%.2f m)" % g.player.global_position.distance_to(tfront))
	check(not g.player.frozen, "the player can move again")
	print("OK" if ok else "FAILED")
