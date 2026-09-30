extends Node3D
## Analogue clock hands at known times: 03:00:00, 06:30:00, 10:10:30 (front view) -> build/shot_clock.png
func _ready() -> void:
	var we := WorldEnvironment.new()
	var en := Environment.new()
	en.background_mode = Environment.BG_COLOR
	en.background_color = Color(0.6, 0.62, 0.66)
	en.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	en.ambient_light_color = Color(0.9, 0.9, 0.9)
	we.environment = en
	add_child(we)
	var times := [3.0 * 3600.0, 6.5 * 3600.0, 10.0 * 3600.0 + 600.0 + 30.0]
	for i in times.size():
		var holder := Node3D.new()
		add_child(holder)
		holder.position = Vector3((i - 1) * 0.9, 1.0, 0)
		holder.rotation.y = PI
		var c := StationProps.inst("clock")
		holder.add_child(c)
		var tk := StationClocks.new()
		add_child(tk)
		tk.add(c)
		tk.set_process(false)
		tk._apply(tk._clocks[0], times[i])
		var hs = tk._clocks[0][2]
		print("t=", times[i], " hand_s=", hs, " rot=", (hs as Node3D).rotation if hs != null else "-", " basis=", (hs as Node3D).basis if hs != null else "-")
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.0, 1.6)
	cam.look_at(Vector3(0, 1.0, 0))
	var l := DirectionalLight3D.new()
	l.rotation = Vector3(-0.5, 0.0, 0)
	add_child(l)
	for i in 15: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/shot_clock.png")
	get_tree().quit()
