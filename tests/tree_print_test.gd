extends Node
func _dump(n: Node, depth: int) -> void:
	var extra := ""
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		extra = " mesh surfaces=%d" % (n as MeshInstance3D).mesh.get_surface_count()
	print("TREE %s%s [%s]%s" % ["  ".repeat(depth), n.name, n.get_class(), extra])
	for c in n.get_children():
		_dump(c, depth + 1)
func run():
	for nm in ["gate_unit", "gate_wide", "gate_fence"]:
		var node := StationProps.inst(nm)
		_dump(node, 0)
		node.free()
