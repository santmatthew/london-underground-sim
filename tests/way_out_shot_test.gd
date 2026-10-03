extends Node3D
## The "Way out" boards as the stations hang them (several sizes, every arrow direction) on one sheet: the arrow must clear the text. args --out=res://build/way_out.png
func _ready() -> void:
	var out := "res://build/way_out.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	add_child(Env.make())
	var y := 0.0
	for spec in [[2.2, 0.42], [3.0, 0.4], [2.0, 0.4], [1.9, 0.4], [2.4, 0.4], [1.0, 0.24]]:
		var x := -3.6
		for dir in [0, 1, 2, 3]:
			var b := Signs.board([{"text": "Way out", "bold": true, "arrow": dir}], spec[0], spec[1])
			b.position = Vector3(x, y, 0)
			add_child(b)
			x += 2.6
		y -= 0.65
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.9, -1.6, 7.0)
	cam.fov = 40.0
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-20, 20, 0)
	add_child(l)
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
