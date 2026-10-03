extends Node3D
## The driving cars of each rolling stock side by side in daylight (three-quarter front view, then from the side, then end-on): the shape of the bodies and noses. args --stocks=deep,deep92,deep72,ss --out=res://build/stock_sheet
func _ready() -> void:
	var stocks := ["deep92", "deep", "deep72", "ss"]
	var out := "res://build/stock_sheet"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stocks="): stocks = a.substr(9).split(",")
		if a.begins_with("--out="): out = a.substr(6)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.92)
	env.ambient_light_energy = 0.9
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.4
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.26, 0.28)
	ground.material_override = gm
	ground.position = Vector3(0, -0.02, 0)
	add_child(ground)
	for i in stocks.size():
		var car: Node3D = Train.scene_for(String(stocks[i]) + "_cab").instantiate()
		car.position = Vector3(0, 0, (i - (stocks.size() - 1) * 0.5) * 6.0)
		add_child(car)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 38.0
	for view in ["quarter", "side", "front", "top"]:
		match view:
			"quarter":
				cam.position = Vector3(19.0, 3.2, 17.0)
				cam.look_at(Vector3(6.0, 1.7, 0.0))
			"side":
				cam.position = Vector3(2.0, 2.0, 30.0)
				cam.look_at(Vector3(2.0, 1.7, 0.0))
			"front":
				cam.fov = 12.0
				cam.position = Vector3(90.0, 1.9, 0.0)
				cam.look_at(Vector3(8.0, 1.7, 0.0))
			"top":
				cam.fov = 30.0
				cam.position = Vector3(8.0, 40.0, -9.0)
				cam.look_at(Vector3(8.0, 0.0, -9.0))
		for k in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, view])
	get_tree().quit()
