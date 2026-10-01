extends Node3D
## Seated view from a platform bench and from a train seat -> build/shot_seated_bench.png, build/shot_seated_train.png
func _shot(player: Player, seat: Node3D, name: String, look: Vector3, along := false) -> void:
	player.global_position = seat.global_position - Vector3(0, 0.45, 0) + Vector3(0, 0.02, 0) + (-seat.global_transform.basis.z) * 0.7
	for i in 3: await get_tree().physics_frame
	player.sit_on(seat)
	for i in 60: await get_tree().physics_frame
	player.face(look)
	if along:
		player.head.rotation.x = -0.12
	for i in 6: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/shot_seated_%s.png" % name)
	player.cancel_sit()


func _ready() -> void:
	Timetable.build(1)
	Clock.set_time(11.0 * 3600.0)
	add_child(Env.make(1))
	var player := Player.new()
	add_child(player)
	player.enabled = true
	var plan := StationPlan.for_station(Net.name_to_idx["Oxford Circus"])
	var st := Station.new()
	add_child(st)
	st.build(plan)
	for i in 6: await get_tree().physics_frame
	var seats: Array = []
	for n in get_tree().get_nodes_in_group("seat"):
		if st.is_ancestor_of(n):
			seats.append(n)
	if seats.size() > 0:
		var s0: Node3D = seats[2]
		await _shot(player, s0, "bench", -s0.global_transform.basis.z)
	st.queue_free()
	await get_tree().process_frame
	var tr := Train.new()
	add_child(tr)
	tr.position = Vector3(0, 0, 60)
	tr.build("deep", 3, "northern", Color(0.3, 0.3, 0.3))
	tr.set_linemap("northern", 0)
	await get_tree().physics_frame
	var cs: Array = tr.cars[1].find_children("seat_R_*", "Node3D", true, false)
	await _shot(player, cs[5] as Node3D, "train", tr.cars[1].global_transform.basis.x, true)
	get_tree().quit()
