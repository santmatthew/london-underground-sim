extends Node
## For each car model: where the side walls of its collision mesh stop at a height of 1.2 m above the rail (the doorways), x ranges in the car's frame, against Train.DOOR_X.
func _gaps(car: Node3D, wall: String, half_len: float) -> Array:
	var faces := PackedVector3Array()
	for n in car.find_children(wall, "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		if str(cs.get_parent().name) == wall:
			var f: PackedVector3Array = (cs.shape as ConcavePolygonShape3D).get_faces()
			for v in f:
				faces.append(cs.global_transform * v)
	for n in car.find_children("*", "CollisionShape3D", true, false):
		pass
	var out: Array = []
	var x := -half_len
	var in_gap := false
	var start := 0.0
	while x <= half_len:
		var covered := false
		for i in range(0, faces.size(), 3):
			var a := faces[i]
			var b := faces[i + 1]
			var c := faces[i + 2]
			var xmin := minf(a.x, minf(b.x, c.x))
			var xmax := maxf(a.x, maxf(b.x, c.x))
			var ymin := minf(a.y, minf(b.y, c.y))
			var ymax := maxf(a.y, maxf(b.y, c.y))
			if x >= xmin and x <= xmax and 1.2 >= ymin and 1.2 <= ymax:
				covered = true
				break
		if not covered and not in_gap:
			in_gap = true
			start = x
		if covered and in_gap:
			in_gap = false
			out.append([snappedf(start, 0.01), snappedf(x, 0.01)])
		x += 0.02
	return out


func run():
	for key in ["deep_mid", "deep92_mid", "deep72_mid", "deep_cab", "deep92_cab", "ss_mid"]:
		var ps: PackedScene = load(Train.CAR_SCENES[key])
		var car: Node3D = ps.instantiate()
		add_child(car)
		var fam: String = key.substr(0, key.find("_"))
		var base: String = ("deep" if fam.begins_with("deep") else fam) + key.substr(key.find("_"))
		print("== ", key, " doors at ", Train.DOOR_X[base])
		print("   WallL gaps ", _gaps(car, "WallL", 10.0))
		print("   WallR gaps ", _gaps(car, "WallR", 10.0))
		car.queue_free()
	print("OK")
