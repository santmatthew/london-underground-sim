extends Node3D
func _ready():
	for idx in [0, 3, 18, 31]:
		var ps: PackedScene = load("res://assets/people/chars/person_%02d.glb" % idx)
		var inst = ps.instantiate()
		var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
		var m: ArrayMesh = mi.mesh
		var rid := m.get_rid()
		var s0 := 0
		var lod_tris := {}
		for s in m.get_surface_count():
			var d: Dictionary = RenderingServer.mesh_get_surface(rid, s)
			s0 += int(d["index_count"]) / 3
			var lods: Array = d.get("lods", [])
			for i in lods.size():
				lod_tris[i] = lod_tris.get(i, 0) + (lods[i]["index_data"] as PackedByteArray).size() / (4 if int(d["vertex_count"]) > 65535 else 2) / 3
		print("LODCHECK person_%02d LOD0 tris=%d  tris of extra LOD levels=%s" % [idx, s0, lod_tris])
	get_tree().quit()
