extends Node3D
func _ready():
	print("API count=", PersonModel.count(), " has walk_normal=", PersonModel.has_clip(&"walk_normal"))
	for idx in [3, 28, 7]:
		var p := PersonModel.create(idx, 0)
		add_child(p)
		print("API person ", idx, " height=", p.info["height_m"], " leg_scale=", snappedf(p.leg_scale, 0.001), " motion_scale=", snappedf(p.skeleton.motion_scale, 0.001))
		for v in [0.0, 0.5, 0.9, 1.2, 1.4, 1.8, 2.3]:
			p.set_locomotion_speed(v)
			print("API   speed ", v, " -> clip ", p.current_clip, " playback x", snappedf(p.anim_player.speed_scale, 0.01))
		p.play(&"sit_down"); p.queue(&"sit_idle_1")
		for i in 100: p.tick(1.0 / 30.0)
		print("API   after sit_down+queue: ", p.current_clip, " ", p.anim_player.current_animation)
		p.play(&"stand_hold"); p.tick(0.5); p.play(&"idle_stand_1"); for i in 20: p.tick(0.05)
		await get_tree().create_timer(0.6).timeout
		var fb: int = p.skeleton.find_bone("index_02_r")
		print("API   finger rot after switching from stand_hold to idle: ", p.skeleton.get_bone_pose_rotation(fb), " rest ", p.skeleton.get_bone_rest(fb).basis.get_rotation_quaternion())
		p.set_detail(PersonModel.DETAIL_HIDDEN); print("API   hidden visible=", p.mesh_instance.visible)
		p.set_detail(PersonModel.DETAIL_NEAR)
		p.queue_free()
	var p2 := PersonModel.create(5, 77); add_child(p2)
	print("API variation tint_top=", p2.mesh_instance.get_instance_shader_parameter("tint_top"), " hair=", p2.mesh_instance.get_instance_shader_parameter("hair_tint"), " bag=", p2.info["has_bag"])
	get_tree().quit()
