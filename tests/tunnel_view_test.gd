extends Node3D
## The scenery tunnel of a ride (TunnelRun) from a camera on the track: args --view=ahead|side --at=metres along the path --curve=curvature class (R = 1500 / class metres; negative turns right) of cells 3..40
## --sec=code:metres,... (what the track runs through: 0 open, 1 tunnel, 2 cutting, 3 embankment, 4 viaduct; default: the bore) --ss (a sub-surface line) --hour=H (time of day) --height=eye height
## --out=build/x.png ; a light on the camera stands for the train's own lights
func _ready() -> void:
	var view := "ahead"
	var at := 0.0
	var cls := 0
	var mirror := false
	var secs: Array = []
	var ss := false
	var eye := 1.2
	var out := "res://build/tunnel_view.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="): view = a.substr(7)
		if a.begins_with("--at="): at = float(a.substr(5))
		if a.begins_with("--curve="): cls = int(a.substr(8))
		if a.begins_with("--out="): out = a.substr(6)
		if a == "--mirror": mirror = true             # the platform on the right of the train
		if a.begins_with("--sec="):
			for part in a.substr(6).split(","):
				secs.append([int(part.split(":")[0]), float(part.split(":")[1])])
		if a == "--ss": ss = true
		if a.begins_with("--hour="): Clock.now = float(a.substr(7)) * 3600.0
		if a.begins_with("--height="): eye = float(a.substr(9))
	add_child(Env.make(0))
	var ks := PackedFloat32Array()
	for k in 60:
		ks.append(float(cls) * TrackPath.Q if (k >= 3 and k < 41) else 0.0)
	var path := TrackPath.new()
	path._build(ks, 600.0)
	if not secs.is_empty():
		path.plan_scenes(secs, ss, 7, 0, 59)
	var t := TunnelRun.new()
	add_child(t)
	var t0 := Time.get_ticks_msec()
	t.setup(path, mirror)
	print("setup ", Time.get_ticks_msec() - t0, " ms")
	while t.busy():
		await get_tree().process_frame
	t.place(at)
	await get_tree().process_frame
	t.place(at)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 75.0
	var pose := path.pose(at)
	cam.transform = pose * Transform3D(Basis.IDENTITY, Vector3(0, eye, -0.4))
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
