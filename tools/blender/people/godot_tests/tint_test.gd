extends Node3D
func _ready():
	var l := DirectionalLight3D.new(); add_child(l); l.rotation_degrees = Vector3(-35, 30, 0)
	var we := WorldEnvironment.new(); var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.4,0.4,0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.7,0.7,0.7); we.environment = env; add_child(we)
	var cam := Camera3D.new(); add_child(cam); cam.position = Vector3(0, 1.0, 3.5); cam.look_at(Vector3(0, 0.9, 0)); cam.current = true
	var p := PersonModel.create(2, 0)
	add_child(p); p.rotation.y = PI
	var mi: MeshInstance3D = p.mesh_instance
	print("before ", mi.get_instance_shader_parameter("tint_top"), mi.get_instance_shader_parameter("hair_tint"))
	mi.set_instance_shader_parameter("tint_top", Color(0, 1, 0))
	mi.set_instance_shader_parameter("hair_tint", Color(0, 0, 1))
	mi.set_instance_shader_parameter("skin_tint", Color(1, 0.3, 0.3))
	print("after ", mi.get_instance_shader_parameter("tint_top"), mi.get_instance_shader_parameter("hair_tint"))
	print("surfaces ", mi.mesh.get_surface_count())
	for s in mi.mesh.get_surface_count():
		var m = mi.mesh.surface_get_material(s)
		print(s, " ", m, " ", (m as ShaderMaterial).shader.resource_path if m is ShaderMaterial else "-")
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/tint_test.png")
	get_tree().quit()
