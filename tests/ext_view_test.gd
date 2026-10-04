extends Node3D
## A station seen from a camera in its first module: what lies beyond the platform ends (RunScenery: open land, cuttings, viaducts, cut-and-cover boxes).
## args --station=Name --at=x,y,z (module frame) --look=x,y,z --module=N --hour=H --out=res://build/x.png [--info: print each module's ext cells]
func _ready() -> void:
	var out := "res://build/ext_view.png"
	var sname := "Amersham"
	var at := Vector3(60, 1.5, 3)
	var look := Vector3(200, 1.0, 6)
	var mod := 0
	var info := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--station="): sname = a.substr(10)
		if a.begins_with("--at="): at = _v(a.substr(5))
		if a.begins_with("--look="): look = _v(a.substr(7))
		if a.begins_with("--module="): mod = int(a.substr(9))
		if a.begins_with("--hour="): Clock.now = float(a.substr(7)) * 3600.0
		if a == "--info": info = true
	Timetable.build(1)
	add_child(Env.make(0))
	var plan := StationPlan.for_station(Net.name_to_idx[sname])
	var st := Station.new()
	add_child(st)
	await st.build_async(plan)
	for _i in 10:
		await get_tree().process_frame
	var pm: PlatformModule = st.modules[mod]
	print("module in tree ", pm.is_inside_tree(), " station in tree ", st.is_inside_tree(), " pos ", pm.position)
	if info:
		for mi in plan.modules.size():
			var ext: Array = plan.modules[mi].get("ext", [])
			print("module ", mi, " ext ", ext)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 75.0
	cam.global_position = pm.global_transform * at
	cam.look_at(pm.global_transform * look)
	var l := OmniLight3D.new()
	l.light_energy = 1.0
	l.omni_range = 8.0
	add_child(l)
	l.global_position = cam.global_position
	for _i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()


func _v(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
