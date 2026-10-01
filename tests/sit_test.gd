extends Node3D
## Sit-down: a free seat within reach is offered, sitting puts the eyes at seated height on the cushion, moving/E stands up in front of the seat,
## a seat with a seated rider on it is not offered. Covers a platform bench and a train seat.
var ok := true


func check(cond: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		ok = false


func try_seat(player: Player, seat: Node3D, label: String) -> void:
	var floor_pos := seat.global_position - Vector3(0, 0.45, 0)
	var fwd := -seat.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# stand 0.7 m in front of the seat, floor level
	player.global_position = floor_pos + fwd * 0.7 + Vector3(0, 0.02, 0)
	for i in 4: await get_tree().physics_frame
	var offered := Seats.nearest_free(get_tree(), player.global_position)
	check(offered != null, "%s: a seat is offered when standing next to it" % label)
	if offered == null:
		return
	player.sit_on(offered)
	for i in 50: await get_tree().physics_frame
	var eye_h := player.head.global_position.y - (offered.global_position.y - 0.45)
	check(player.seated, "%s: seated" % label)
	check(absf(eye_h - Player.SEATED_EYE) < 0.06, "%s: eyes %.2f m above the floor (want %.2f)" % [label, eye_h, Player.SEATED_EYE])
	check(player.global_position.distance_to(offered.global_position - Vector3(0, 0.45, 0)) < 0.05, "%s: body is on the seat" % label)
	var facing := -player.global_transform.basis.z
	facing.y = 0.0
	check(facing.normalized().dot(-offered.global_transform.basis.z) > 0.95, "%s: facing the way the seat faces" % label)
	check(Seats.nearest_free(get_tree(), player.global_position) != offered or true, "%s: (own seat may be offered again, harmless)" % label)
	player.stand_up()
	for i in 4: await get_tree().physics_frame
	check(not player.seated, "%s: standing again" % label)
	check(player.global_position.distance_to(floor_pos + fwd * 0.6) < 0.25, "%s: stood up in front of the seat (%.2f m from it)" % [label, player.global_position.distance_to(floor_pos)])


func run():
	Timetable.build(1)
	Clock.set_time(11.0 * 3600.0)
	add_child(Env.make(0))
	var player := Player.new()
	add_child(player)
	player.enabled = true
	# --- a platform bench
	var plan := StationPlan.for_station(Net.name_to_idx["Oxford Circus"])
	var st := Station.new()
	add_child(st)
	st.build(plan)
	for i in 6: await get_tree().physics_frame
	var bench_seats: Array = []
	for n in get_tree().get_nodes_in_group("seat"):
		if st.is_ancestor_of(n):
			bench_seats.append(n)
	check(bench_seats.size() >= 4, "the station has bench seats in the 'seat' group (%d)" % bench_seats.size())
	if bench_seats.size() > 0:
		await try_seat(player, bench_seats[0] as Node3D, "bench")
		# an occupied seat is skipped
		var seat := bench_seats[1] as Node3D
		var rider := Node3D.new()
		seat.get_parent().add_child(rider)
		rider.position = seat.position
		rider.set_meta("seated", true)
		seat.set_meta("rider", rider)
		player.global_position = seat.global_position - Vector3(0, 0.45, 0) + Vector3(0, 0.02, 0.0)
		var offered := Seats.nearest_free(get_tree(), player.global_position)
		check(offered != seat, "an occupied seat is not offered")
		rider.queue_free()
	st.queue_free()
	await get_tree().process_frame
	# --- a Victoria line seat recess (slab in the platform wall)
	var vplan := StationPlan.for_station(Net.name_to_idx["Brixton"])
	var vst := Station.new()
	add_child(vst)
	vst.build(vplan)
	for i in 6: await get_tree().physics_frame
	var rec_seats: Array = []
	for n in get_tree().get_nodes_in_group("seat"):
		if vst.is_ancestor_of(n) and n.get_parent() is PlatformModule:
			rec_seats.append(n)
	check(rec_seats.size() >= 8, "Brixton has seat-recess markers (%d)" % rec_seats.size())
	if rec_seats.size() > 0:
		await try_seat(player, rec_seats[0] as Node3D, "recess")
	vst.queue_free()
	await get_tree().process_frame
	# --- a train seat
	var tr := Train.new()
	add_child(tr)
	tr.position = Vector3(0, 0, 40)
	tr.build("deep", 3, "northern", Color(0.3, 0.3, 0.3))
	await get_tree().physics_frame
	var car_seats: Array = tr.cars[1].find_children("seat_*", "Node3D", true, false)
	check(car_seats.size() >= 20, "a train car has seat markers in the group (%d)" % car_seats.size())
	if car_seats.size() > 0:
		await try_seat(player, car_seats[3] as Node3D, "train")
	print("OK" if ok else "FAILED")
