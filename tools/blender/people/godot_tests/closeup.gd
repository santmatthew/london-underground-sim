extends Node3D
# godot ... res://tests/closeup.tscn -- <idx> <clip> <target: hand|face|torso|full> <side: front|side|back|q> <out.png> [t]
func _ready():
	var a := OS.get_cmdline_user_args()
	var idx := int(a[0]); var clip: String = a[1]; var tgt: String = a[2]; var side: String = a[3]; var outp: String = a[4]
	var t := float(a[5]) if a.size() > 5 else 0.3
	var l := DirectionalLight3D.new(); add_child(l); l.rotation_degrees = Vector3(-35, 30, 0); l.shadow_enabled = true
	var l2 := DirectionalLight3D.new(); add_child(l2); l2.rotation_degrees = Vector3(-10, -140, 0); l2.light_energy = 0.4
	var we := WorldEnvironment.new(); var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.45, 0.47, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.75, 0.75, 0.78); we.environment = env; add_child(we)
	var cam := Camera3D.new(); add_child(cam); cam.current = true
	var p := PersonModel.create(idx, 0)
	add_child(p); p.rotation.y = PI
	if clip != "rest":
		p.play(StringName(clip), 0.0)
		p.tick(t)
	await get_tree().process_frame
	var sk: Skeleton3D = p.skeleton
	var h: float = p.info["height_m"]
	var center := Vector3(0, h * 0.5, 0); var dist := 3.4; var fov := 30.0
	if tgt == "hand":
		var b := sk.find_bone("hand_l")
		center = sk.global_transform * sk.get_bone_global_pose(b).origin; dist = 0.9; fov = 30
	elif tgt == "face":
		var b := sk.find_bone("head")
		center = sk.global_transform * sk.get_bone_global_pose(b).origin + Vector3(0, 0.07, 0.09); dist = 0.8; fov = 30
	elif tgt == "torso":
		center = Vector3(0, h * 0.72, 0); dist = 1.7; fov = 30
	cam.fov = fov
	var dir := Vector3(0, 0, 1)
	if side == "side": dir = Vector3(1, 0, 0)
	elif side == "back": dir = Vector3(0, 0, -1)
	elif side == "q": dir = Vector3(0.6, 0.15, 0.8).normalized()
	cam.position = center + dir * dist
	cam.look_at(center)
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(outp)
	get_tree().quit()
