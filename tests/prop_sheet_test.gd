extends Node3D
## Contact sheet of props: every glb in assets/models/props (or --props=a,b,c) in a row/grid on a floor, photographed from the front.
## args: --props=ticket_machine,bin   --cols=6   --view=front|side|top   --out=name   --scale-ref  (adds a 1.8 m person-height pole per prop)
## Output: build/prop_sheet_<out>.png  (default out = "all")
func _ready() -> void:
	var names: Array = []
	var cols := 6
	var view := "front"
	var out := "all"
	var yaw := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--props="): names = Array(a.substr(8).split(","))
		if a.begins_with("--cols="): cols = int(a.substr(7))
		if a.begins_with("--view="): view = a.substr(7)
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--yaw="): yaw = deg_to_rad(float(a.substr(6)))
	if names.is_empty():
		var d := DirAccess.open(StationProps.DIR)
		for f in d.get_files():
			if f.ends_with(".glb"):
				names.append(f.get_basename())
		names.sort()
	var we := WorldEnvironment.new()
	var en := Environment.new()
	en.background_mode = Environment.BG_COLOR
	en.background_color = Color(0.62, 0.66, 0.72)
	en.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	en.ambient_light_color = Color(0.85, 0.85, 0.88)
	en.ambient_light_energy = 0.9
	we.environment = en
	add_child(we)
	var space := 2.6
	var rows := int(ceil(float(names.size()) / cols))
	var w := cols * space
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w + 4.0, rows * space + 4.0)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.45, 0.47)
	pm.material = fm
	floor_mesh.position = Vector3(w * 0.5 - space * 0.5, 0, rows * space * 0.5 - space * 0.5)
	add_child(floor_mesh)
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w + 4.0, 3.5, 0.1)
	back.mesh = bm
	back.material_override = fm
	back.position = Vector3(w * 0.5 - space * 0.5, 1.75, -space * 0.5 - 0.6)
	add_child(back)
	for i in names.size():
		var n := StationProps.inst(names[i])
		var col := i % cols
		var row := i / cols
		add_child(n)
		n.position = Vector3(col * space, 0, row * space)
		n.rotation.y = yaw
		# 1.8 m reference pole and a label
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.015; cm.bottom_radius = 0.015; cm.height = 1.8
		pole.mesh = cm
		pole.position = Vector3(col * space + 1.05, 0.9, row * space - 0.4)
		add_child(pole)
		var lab := Label3D.new()
		lab.text = names[i]
		lab.font_size = 48
		lab.pixel_size = 0.004
		lab.position = Vector3(col * space, 0.02, row * space + 0.9)
		lab.rotation.x = -PI / 2
		add_child(lab)
	var l := DirectionalLight3D.new()
	l.rotation = Vector3(-0.7, 0.35, 0)
	l.light_energy = 1.4
	add_child(l)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 55
	var cx := w * 0.5 - space * 0.5
	var cz := rows * space * 0.5 - space * 0.5
	match view:
		"top":
			cam.position = Vector3(cx, 14.0 + rows * 3.0, cz + 0.1); cam.look_at(Vector3(cx, 0, cz))
		"side":
			cam.position = Vector3(cx + w * 0.9, 2.0, cz); cam.look_at(Vector3(cx, 1.0, cz))
		_:
			# fit the whole grid: distance from the half-height/half-width and the field of view
			var half_w := w * 0.5 + 0.4
			var aspect := float(get_viewport().size.x) / float(get_viewport().size.y)
			var dist := half_w / (tan(deg_to_rad(cam.fov * 0.5)) * aspect) + rows * 0.5
			cam.position = Vector3(cx, 1.4 + rows * 0.35, cz + dist); cam.look_at(Vector3(cx, 0.85, cz))
	for i in 25: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/prop_sheet_%s.png" % out)
	get_tree().quit()
