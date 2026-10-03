extends Node
## Prints the size of the four car models (width, height above the rail head, length): what the tunnel must leave room for.
func run():
	for key in ["deep_mid", "deep_cab", "ss_mid", "ss_cab"]:
		var car: Node3D = Train.scene_for(key).instantiate()
		add_child(car)
		var box := AABB()
		var first := true
		for n in car.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var ab: AABB = car.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			if first:
				box = ab
				first = false
			else:
				box = box.merge(ab)
		print("%-9s x %.2f..%.2f (length %.2f)   y %.2f..%.2f   z %.2f..%.2f (width %.2f)" % [key, box.position.x, box.end.x, box.size.x, box.position.y, box.end.y, box.position.z, box.end.z, box.size.z])
		car.queue_free()
