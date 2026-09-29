extends Node
func run():
	var root := Node3D.new(); add_child(root)
	root.add_child(Env.make(0))
	var cam := Camera3D.new(); root.add_child(cam); cam.position = Vector3(0, 1.6, 4); cam.current = true
	var m := MeshInstance3D.new(); m.mesh = BoxMesh.new(); root.add_child(m)
	var l := DirectionalLight3D.new(); root.add_child(l)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 30: await get_tree().process_frame
	var g := 0.0
	for i in 60:
		await get_tree().process_frame
		g += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	print("baseline GPU ms (near-empty scene): ", g / 60.0)
