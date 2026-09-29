extends Node3D
## Visual test of the twin-tube platform module. Args: --shot=name  (saves build/shot_<name>.png)
func _ready() -> void:
	add_child(Env.make())
	var m := PlatformModule.new()
	add_child(m)
	m.build({
		"length": 110.0, "pw": 3.2, "wall": "tile_white", "seed": 7,
		"faces": [{"line": "central", "color": Color(0.89, 0.13, 0.09), "label": "Eastbound"}, {"line": "central", "color": Color(0.89, 0.13, 0.09), "label": "Westbound"}],
	})
	print("tris: ", m.meta["tri_count"])
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 75
	var views := {
		"a": [Vector3(-30, 1.65, 3.2), Vector3(20, 1.4, 3.2)],     # along platform A
		"b": [Vector3(-10, 1.65, 2.3), Vector3(-10, 1.5, 7.0)],    # across the track
		"c": [Vector3(-40, 1.65, 0.0), Vector3(0, 1.5, 0.0)],       # spine
		"d": [Vector3(-50, 1.65, 2.4), Vector3(30, 1.0, 4.5)],      # long perspective
	}
	var shot := "a"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot = a.substr(7)
	var v: Array = views[shot]
	cam.position = v[0]
	cam.look_at(v[1])
	for i in 12: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/shot_platform_%s.png" % shot)
	print("saved")
	get_tree().quit()
