extends Node
func _dump(n: Node, depth: int, maxd: int) -> void:
	if depth > maxd: return
	var extra := ""
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var bb := (n as MeshInstance3D).get_aabb()
		extra = " surfaces=%d aabb pos(%.1f,%.1f,%.1f) size(%.1f,%.1f,%.1f)" % [(n as MeshInstance3D).mesh.get_surface_count(), bb.position.x, bb.position.y, bb.position.z, bb.size.x, bb.size.y, bb.size.z]
	print("TREE %s%s [%s]%s" % ["  ".repeat(depth), n.name, n.get_class(), extra])
	for c in n.get_children():
		_dump(c, depth + 1, maxd)
func run():
	var node: Node = (load("res://assets/models/train/tube_car_deep_mid.glb") as PackedScene).instantiate()
	_dump(node, 0, 3)
