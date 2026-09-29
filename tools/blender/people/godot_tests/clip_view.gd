extends Node3D
# godot ... res://tests/clip_view.tscn -- <char> <lib.res> <clip1,clip2> <nframes> <view: front|side|q> <outprefix> [motion_scale]
func _ready():
	var a := OS.get_cmdline_user_args()
	var ch: String = a[0]; var libp: String = a[1]; var clips: PackedStringArray = a[2].split(","); var nf := int(a[3]); var view: String = a[4]; var outp: String = a[5]
	var inst = (load("res://assets/people/chars/%s.glb" % ch) as PackedScene).instantiate()
	add_child(inst)
	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	if a.size() > 6: sk.motion_scale = float(a[6])
	var ap := AnimationPlayer.new(); add_child(ap)
	ap.root_node = ap.get_path_to(sk.get_parent())
	ap.add_animation_library(&"", load(libp))
	var fl := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(8, 8); fl.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.3, 0.3, 0.33); fl.material_override = fm; add_child(fl)
	var l := DirectionalLight3D.new(); add_child(l); l.rotation_degrees = Vector3(-45, 25, 0)
	var we := WorldEnvironment.new(); var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.35, 0.36, 0.4)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.7, 0.7, 0.7); we.environment = env; add_child(we)
	var cam := Camera3D.new(); add_child(cam); cam.fov = 40
	for cn in clips:
		ap.play(cn); ap.pause()
		var len := ap.current_animation_length
		for i in nf:
			var t := len * float(i) / float(nf)
			ap.seek(t, true)
			await get_tree().process_frame
			if view == "front": cam.position = Vector3(0, 1.0, -4.2)
			elif view == "side": cam.position = Vector3(4.2, 1.0, 0)
			else: cam.position = Vector3(3.0, 1.4, -3.0)
			cam.look_at(Vector3(0, 0.9, 0))
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s_%s_%02d.png" % [outp, cn, i])
	get_tree().quit()
