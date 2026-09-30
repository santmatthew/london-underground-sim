extends Node3D
## Looks inside a carriage: the line-diagram strips above the doors, the adverts. args: --line=district --dir=0 --kind=deep|ss
## --cam=x,y,z --look=x,y,z (train frame: x along the train, y up from the rail head)   -> build/shot_train_interior.png
func _ready() -> void:
	var line := "district"
	var dir := 0
	var kind := "deep"
	var cam_a := ""
	var look_a := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--line="): line = a.substr(7)
		if a.begins_with("--dir="): dir = int(a.substr(6))
		if a.begins_with("--kind="): kind = a.substr(7)
		if a.begins_with("--cam="): cam_a = a.substr(6)
		if a.begins_with("--look="): look_a = a.substr(7)
	Timetable.build(1)
	Clock.set_time(11.0 * 3600.0)
	add_child(Env.make(0))
	var tr := Train.new()
	add_child(tr)
	tr.build(kind, 3, line, Net.line_color(line))
	tr.set_linemap(line, dir)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 70
	var pos := Vector3(1.5, 2.55, -0.2)
	var look := Vector3(1.5, 2.85, 1.3)
	if cam_a != "" and look_a != "":
		var c := cam_a.split(",")
		var l := look_a.split(",")
		pos = Vector3(float(c[0]), float(c[1]), float(c[2]))
		look = Vector3(float(l[0]), float(l[1]), float(l[2]))
	cam.position = pos
	cam.look_at(look)
	for i in 25: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/shot_train_interior.png")
	get_tree().quit()
