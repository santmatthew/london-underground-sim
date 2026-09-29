extends Node3D
func _ready():
	var cam := Camera3D.new(); add_child(cam); cam.position = Vector3(0, 1.6, 3)
	var m := MeshInstance3D.new(); m.mesh = BoxMesh.new(); add_child(m)
	var l := DirectionalLight3D.new(); add_child(l); l.rotation_degrees = Vector3(-50, 30, 0)
	await get_tree().process_frame; await get_tree().process_frame; await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/hello.png")
	print("GPU: ", RenderingServer.get_video_adapter_name(), " | ", RenderingServer.get_video_adapter_api_version())
	get_tree().quit()
