extends Node3D
## Screenshots of the "Platforms" boards over the escalators of a station's ticket hall(s): one image per board, taken from 5 m in front of it. args --station="Liverpool Street" --out=res://build/esc_sign
func _ready() -> void:
	var nm := "Liverpool Street"
	var out := "res://build/esc_sign"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): nm = a.substr(10)
		if a.begins_with("--out="): out = a.substr(6)
	Timetable.build(1)
	Clock.set_time(9.0 * 3600.0)
	add_child(Env.make())
	var st := Station.new()
	add_child(st)
	st.build(StationPlan.for_station(Net.name_to_idx[nm]))
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 70.0
	var n := 0
	for lb in st.find_children("*", "Label3D", true, false):
		if (lb as Label3D).text != "Platforms":
			continue
		var board := lb.get_parent() as Node3D
		var c := board.global_position
		var face := board.global_transform.basis.z.normalized()
		cam.global_position = c + face * 5.0 + Vector3(0, -0.8, 0)
		cam.look_at(c, Vector3.UP)
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [out, n])
		n += 1
		if n >= 4:
			break
	print("boards photographed: ", n)
	get_tree().quit()
