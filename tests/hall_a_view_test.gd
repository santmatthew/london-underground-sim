extends Node3D
## Close-up viewer for the ticket-hall props (hall_a): places props in a hall-like lighting set-up and photographs them.
## args: --props=a,b,c (each optionally name:x:y:z:yawdeg)  --space=1.6 (metres between props)  --yaw=180  --cam=x,y,z  --look=x,y,z  --out=name  --wall  --fov=50
## Output: build/hall_a_<out>.png
func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.substr(name.length() + 3)
	return def

func _has(name: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "--" + name: return true
	return false

func _ready() -> void:
	add_child(Env.make(1))
	var names := _arg("props", "gate_unit").split(",")
	var space := float(_arg("space", "1.6"))
	var yaw := deg_to_rad(float(_arg("yaw", "180")))
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.62, 0.6, 0.56)
	fm.roughness = 0.6
	pm.material = fm
	add_child(fl)
	if _has("wall"):
		var wl := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(30, 4.0, 0.1)
		wl.mesh = bm
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.86, 0.87, 0.85)
		wm.roughness = 0.35
		bm.material = wm
		wl.position = Vector3(0, 2.0, 0.40)
		add_child(wl)
	for i in names.size():
		# "name" or "name:x:y:z:yawdeg" (explicit placement)
		var parts := names[i].split(":")
		var n := StationProps.inst(parts[0])
		add_child(n)
		n.position = Vector3(i * space, 0, 0)
		n.rotation.y = yaw
		if parts.size() >= 4:
			n.position = Vector3(float(parts[1]), float(parts[2]), float(parts[3]))
		if parts.size() >= 5:
			n.rotation.y = deg_to_rad(float(parts[4]))
		if _has("open") and n.get_node_or_null("flap_L"):
			(n.get_node("flap_L") as Node3D).rotation.y = deg_to_rad(90)
			(n.get_node("flap_R") as Node3D).rotation.y = deg_to_rad(-90)
		if _has("open") and n.get_node_or_null("door_L"):
			(n.get_node("door_L") as Node3D).rotation.y = deg_to_rad(90)
			(n.get_node("door_R") as Node3D).rotation.y = deg_to_rad(-90)
		if _has("open") and n.get_node_or_null("lamp_stop"):
			(n.get_node("lamp_stop") as Node3D).visible = false
	# hall-like lighting: bright ceiling panels above and in front
	for k in 4:
		var l := OmniLight3D.new()
		l.position = Vector3(float(names.size() - 1) * space * 0.5 + (k % 2 * 2 - 1) * 2.5, 3.0, -2.5 if k < 2 else 2.5)
		l.omni_range = 12.0
		l.light_energy = 2.5
		add_child(l)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = float(_arg("fov", "50"))
	var cp := _arg("cam", "0,1.6,-3").split(",")
	var lp := _arg("look", "0,1.0,0").split(",")
	cam.position = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
	cam.look_at(Vector3(float(lp[0]), float(lp[1]), float(lp[2])))
	for i in 25: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/hall_a_%s.png" % _arg("out", "view"))
	get_tree().quit()
