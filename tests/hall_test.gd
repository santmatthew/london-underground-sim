extends Node3D
func _ready() -> void:
	add_child(Env.make())
	var rise := 13.0
	var esc := Escalator.new()
	esc.build(rise, [1, -1, 1])
	var hall := Space.new()
	hall.build({"name": "Hall", "rect": [-12, 12, -9, 9], "y": 0.0, "h": 4.2, "wall": "tile_white", "floor": "floor_hall", "band": Color(0.0, 0.2, 0.55), "light_dx": 4.0, "light_dz": 4.5,
		"openings": [{"side": "S", "c": 0.0, "w": esc.width, "h": Escalator.CLEARANCE}, {"side": "N", "c": -6.0, "w": 4.0, "h": 3.0}, {"side": "N", "c": 6.0, "w": 4.0, "h": 3.0}]})
	add_child(hall)
	esc.position = Vector3(0, 0, 9)
	esc.rotation.y = -PI / 2
	add_child(esc)
	var land := Space.new()
	var zl := 9.0 + esc.length
	land.build({"name": "Landing", "rect": [-9, 9, zl, zl + 10], "y": -rise, "h": 3.9, "wall": "tile_white", "floor": "floor_hall", "band": Color(0.0, 0.2, 0.55), "light_dx": 4.0, "light_dz": 5.0,
		"openings": [{"side": "N", "c": 0.0, "w": esc.width, "h": Escalator.CLEARANCE}, {"side": "E", "c": zl + 5, "w": 3.0, "h": 2.6}]})
	add_child(land)
	print("esc length ", esc.length, " width ", esc.width)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 75
	var views := {
		"a": [Vector3(0, 1.65, -6), Vector3(0, 0.5, 9)],
		"b": [Vector3(0, 1.65, 6), Vector3(0, -3, 20)],
		"c": [Vector3(2, -rise + 1.65, zl + 8), Vector3(0, -rise + 2, zl - 3)],
		"d": [Vector3(-0.8, -rise*0.5+1.9, 9+13), Vector3(-0.8, -rise*0.5-0.5, 9+30)],
	}
	var shot := "a"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot = a.substr(7)
	cam.position = views[shot][0]
	cam.look_at(views[shot][1])
	for i in 15: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/shot_hall_%s.png" % shot)
	get_tree().quit()
