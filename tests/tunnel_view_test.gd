extends Node3D
## The scenery tunnel of a ride (TunnelRun) from a camera on the track: args --view=ahead|side --off=metres --out=build/x.png ; a light on the camera stands for the train's own lights
func _ready() -> void:
	var view := "ahead"
	var off := 0.0
	var out := "res://build/tunnel_view.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="): view = a.substr(7)
		if a.begins_with("--off="): off = float(a.substr(6))
		if a.begins_with("--out="): out = a.substr(6)
	add_child(Env.make(0))
	var t := TunnelRun.new()
	add_child(t)
	t.setup()
	t.advance(off)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 75.0
	var tz: float = t.track_z
	cam.position = Vector3(0, 1.2, tz - 0.4)
	if view == "side":
		cam.look_at(Vector3(6, 1.4, tz + 4.0))
	else:
		cam.look_at(Vector3(40, 0.8, tz))
	var l := OmniLight3D.new()
	l.light_energy = 1.2
	l.omni_range = 7.0
	l.position = Vector3(-1.0, 1.8, tz - 0.4)
	add_child(l)
	for i in 25: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
