extends Node3D
## Looks at a spiral stair (needs a display): --steps=193 --rise=36 --view=down|up|side
func _arg(n: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % n): return a.substr(n.length() + 3)
	return d
func _ready() -> void:
	var sp := SpiralStair.new()
	sp.configure(int(_arg("steps", "193")), float(_arg("rise", "36")))
	add_child(Env.make(0))
	add_child(sp)
	sp.build()
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 75
	var view := _arg("view", "down")
	match view:
		"down":
			cam.position = sp.global_transform * (sp.top_entry() + Vector3(0, 1.65, 0))
			cam.look_at(cam.position + sp.tangent(sp.theta0 - 0.3) * 3.0 + Vector3(0, -1.6, 0))
		"up":
			var p := sp.point(sp.theta0 + sp.d_theta * (sp.steps - 6))
			cam.position = p + Vector3(0, 1.65, 0)
			cam.look_at(cam.position - sp.tangent(sp.theta0 + sp.d_theta * (sp.steps - 6)) * 3.0 + Vector3(0, 1.6, 0))
		"mid":
			var tt := sp.theta0 + sp.d_theta * sp.steps * 0.5
			var p2 := sp.point(tt)
			cam.position = p2 + Vector3(0, 1.65, 0)
			cam.look_at(cam.position + sp.tangent(tt) * 3.0 + Vector3(0, -1.0, 0))
		"axis":
			cam.fov = 85
			cam.position = Vector3(0.95, 3.0, 0.0)
			cam.look_at(Vector3(0.95, -sp.rise, 0.05))
		"stairs":
			# standing on the stair looking down it (pitched down)
			var t3 := sp.theta0 + sp.d_theta * sp.steps * 0.3
			var p3 := sp.point(t3)
			cam.position = p3 + Vector3(0, 1.65, 0)
			var tg := sp.tangent(t3)
			cam.look_at(cam.position + tg * 2.2 + (-Vector3(cos(t3), 0, sin(t3))) * 0.9 + Vector3(0, -1.4, 0))
		_:
			cam.position = Vector3(0, -sp.rise * 0.5, 0)
	for i in 20: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/spiral_%s.png" % view)
	get_tree().quit()
