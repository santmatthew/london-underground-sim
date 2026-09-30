extends Node3D
## Renders a few people with backpacks from behind and from the side (build/bag_back.png / bag_side.png). args: --kind=backpack|shoulder --rot=0|180 (extra yaw of the bag)
func _ready() -> void:
	var kind := "backpack"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kind="): kind = a.substr(7)
	Timetable.build(1)
	add_child(Env.make(0))
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	add_child(floor_mi)
	var xs := [-1.6, -0.5, 0.6, 1.7]
	for i in xs.size():
		var p := PersonModel.create(i * 7 + 2, 100 + i)
		add_child(p)
		p.position = Vector3(xs[i], 0, 0)
		p.rotation.y = 0.0            # faces -Z like the crowd (yaw = atan2(-x, -z))
		p.set_bag(true, kind)
		p.play(&"idle_stand_1", 0.0, 1.0)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 45
	cam.position = Vector3(0.0, 1.4, 4.2)     # behind them (they face -Z, so +Z is their back)
	cam.look_at(Vector3(0, 1.1, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	add_child(light)
	for i in 6: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/bag_back.png")
	cam.position = Vector3(3.6, 1.3, 0.0)
	cam.look_at(Vector3(0.6, 1.1, 0))
	for i in 3: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/bag_side.png")
	get_tree().quit()
