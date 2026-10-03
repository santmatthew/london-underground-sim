extends Node3D
## The scenery tunnel of a ride (TunnelRun) from a camera on the track: args --view=ahead|side --at=metres along the path --curve=curvature class (R = 1500 / class metres; negative turns right) of cells 3..40
## --out=build/x.png ; a light on the camera stands for the train's own lights
func _ready() -> void:
	var view := "ahead"
	var at := 0.0
	var cls := 0
	var out := "res://build/tunnel_view.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="): view = a.substr(7)
		if a.begins_with("--at="): at = float(a.substr(5))
		if a.begins_with("--curve="): cls = int(a.substr(8))
		if a.begins_with("--out="): out = a.substr(6)
	add_child(Env.make(0))
	var ks := PackedFloat32Array()
	for k in 60:
		ks.append(float(cls) * TrackPath.Q if (k >= 3 and k < 41) else 0.0)
	var path := TrackPath.new()
	path._build(ks, 600.0)
	var t := TunnelRun.new()
	add_child(t)
	t.setup(path)
	while t.busy():
		await get_tree().process_frame
	t.place(at)
	await get_tree().process_frame
	t.place(at)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 75.0
	var pose := path.pose(at)
	cam.transform = pose * Transform3D(Basis.IDENTITY, Vector3(0, 1.2, -0.4))
	if view == "side":
		cam.look_at(cam.global_position + pose.basis * Vector3(6, 0.2, 4.0))
	else:
		cam.look_at(cam.global_position + pose.basis * Vector3(40, -0.4, 0.4))
	var l := OmniLight3D.new()
	l.light_energy = 1.2
	l.omni_range = 7.0
	l.position = (pose * Transform3D(Basis.IDENTITY, Vector3(-1.0, 1.8, -0.4))).origin
	add_child(l)
	for i in 25: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
