extends Node3D
## Contact sheet for the hall_b props with support for wall / ceiling mounted ones.
## args: --props=poster_stand,clock:2.2,cid_wall_screen:1.45   (name[:origin_height]; a height > 0 also draws a wall plane behind the prop, a NEGATIVE height places it without a wall, e.g. ceiling hung)
##       --cols=4  --out=name  --yaw=180 (default: fronts face the camera)  --dist=1.0 (camera distance multiplier)  --eye=1.4 (camera height)
##       --lookat=1.0  --fov=45  --space=2.6  --view=front|side|top
## Output: build/prop_sheet_<out>.png
func _ready() -> void:
	var items: Array = []
	var cols := 4
	var out := "hall_b"
	var yaw := 180.0
	var dist_mul := 1.0
	var eye := 1.4
	var lookat := 1.0
	var fov := 45.0
	var space := 2.6
	var view := "front"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--props="):
			for p in a.substr(8).split(","):
				var kv := p.split(":")
				items.append([kv[0], float(kv[1]) if kv.size() > 1 else 0.0])
		if a.begins_with("--cols="): cols = int(a.substr(7))
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--yaw="): yaw = float(a.substr(6))
		if a.begins_with("--dist="): dist_mul = float(a.substr(7))
		if a.begins_with("--eye="): eye = float(a.substr(6))
		if a.begins_with("--lookat="): lookat = float(a.substr(9))
		if a.begins_with("--fov="): fov = float(a.substr(6))
		if a.begins_with("--space="): space = float(a.substr(8))
		if a.begins_with("--view="): view = a.substr(7)
	var we := WorldEnvironment.new()
	var en := Environment.new()
	en.background_mode = Environment.BG_COLOR
	en.background_color = Color(0.62, 0.66, 0.72)
	en.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	en.ambient_light_color = Color(0.85, 0.85, 0.88)
	en.ambient_light_energy = 0.9
	we.environment = en
	add_child(we)
	var rows := int(ceil(float(items.size()) / cols))
	var w := cols * space
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.45, 0.47)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.80, 0.78, 0.72)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w + 4.0, rows * space + 4.0)
	pm.material = fm
	floor_mesh.mesh = pm
	floor_mesh.position = Vector3(w * 0.5 - space * 0.5, 0, rows * space * 0.5 - space * 0.5)
	add_child(floor_mesh)
	for i in items.size():
		var nm: String = items[i][0]
		var h: float = items[i][1]
		var wall_plane := h > 0.0
		h = absf(h)
		var col := i % cols
		var row := i / cols
		var n := StationProps.inst(nm)
		add_child(n)
		n.position = Vector3(col * space, h, row * space)
		n.rotation.y = deg_to_rad(yaw)
		if wall_plane:
			var wall := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(space * 0.95, 3.2, 0.1)
			bm.material = wm
			wall.mesh = bm
			wall.position = Vector3(col * space, 1.6, row * space - 0.05)
			add_child(wall)
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012; cm.bottom_radius = 0.012; cm.height = 1.8
		pole.mesh = cm
		pole.position = Vector3(col * space + space * 0.42, 0.9, row * space + 0.05)
		add_child(pole)
		var lab := Label3D.new()
		lab.text = nm
		lab.font_size = 40
		lab.pixel_size = 0.004
		lab.position = Vector3(col * space, 0.02, row * space + 0.7)
		lab.rotation.x = -PI / 2
		add_child(lab)
	var l := DirectionalLight3D.new()
	l.rotation = Vector3(-0.6, 0.45, 0)
	l.light_energy = 1.3
	add_child(l)
	var l2 := DirectionalLight3D.new()
	l2.rotation = Vector3(-0.3, PI + 0.4, 0)
	l2.light_energy = 0.5
	add_child(l2)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = fov
	var cx := w * 0.5 - space * 0.5
	var cz := rows * space * 0.5 - space * 0.5
	match view:
		"top":
			cam.position = Vector3(cx, 14.0 + rows * 3.0, cz + 0.1); cam.look_at(Vector3(cx, 0, cz))
		"side":
			cam.position = Vector3(cx + w * 0.9 * dist_mul, eye, cz); cam.look_at(Vector3(cx, lookat, cz))
		_:
			var half_w := w * 0.5 + 0.2
			var aspect := float(get_viewport().size.x) / float(get_viewport().size.y)
			var dist := (half_w / (tan(deg_to_rad(cam.fov * 0.5)) * aspect) + rows * 0.5) * dist_mul
			cam.position = Vector3(cx, eye, cz + dist); cam.look_at(Vector3(cx, lookat, cz))
	for i in 25: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/prop_sheet_%s.png" % out)
	get_tree().quit()
