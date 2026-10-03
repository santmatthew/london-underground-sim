extends Node3D
## The rolling stock of every line: the Bakerloo and Piccadilly lines run the 1972/73 stock (transverse seating bays at the car ends, red moquette), the other tubes the longitudinal-seating cars, the
## sub-surface lines and the Elizabeth line the wide S-stock-style cars. Each model is checked: it is the right family, its seats face the right way, and nothing it asks a passenger to stand on or walk through
## is blocked (a capsule at every standing spot, a ray down the aisle).
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	var want := {"bakerloo": "deep72", "piccadilly": "deep72", "central": "deep92", "northern": "deep", "victoria": "deep", "jubilee": "deep", "waterloo-city": "deep92",
		"district": "ss", "circle": "ss", "metropolitan": "ss", "hammersmith-city": "ss", "elizabeth": "ss"}
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.24
	shape.height = 1.7
	var y := 0.0
	for lid in want:
		check(Train.stock_of_line(lid) == want[lid], "%s runs the %s stock (%s)" % [lid, want[lid], Train.stock_of_line(lid)])
		var tr := Train.new()
		add_child(tr)
		tr.build(Train.kind_of_line(lid), 3, lid, Net.line_color(lid))
		tr.position = Vector3(0, 0, y)
		y += 12.0
		await get_tree().physics_frame
		await get_tree().physics_frame
		var transverse := 0
		var longitudinal := 0
		var seats := 0
		for car in tr.cars:
			for sm in car.find_children("seat_*", "Node3D", true, false):
				seats += 1
				var fwd: Vector3 = -(sm as Node3D).global_transform.basis.z
				var along := absf(fwd.dot((car as Node3D).global_transform.basis.x.normalized()))
				if along > 0.7:
					transverse += 1
				else:
					longitudinal += 1
		if want[lid] == "deep72":
			check(transverse >= 12 and longitudinal >= 20, "%s: %d transverse and %d across-the-car seats" % [lid, transverse, longitudinal])
		else:
			check(transverse == 0, "%s: all %d seats face across the car (%d face along it)" % [lid, seats, transverse])
		check(seats >= 40, "%s: %d seats in three cars" % [lid, seats])
		# standing spots are free ground; the aisle is open from end to end of the middle car
		var blocked := 0
		var spots := 0
		var mid := tr.cars[1] as Node3D
		for sm in mid.find_children("stand_*", "Node3D", true, false):
			var kind: String = (sm.get_meta("extras", {}) as Dictionary).get("kind", "stand")
			if kind == "stand_door":
				continue
			spots += 1
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shape
			q.collision_mask = 1
			q.transform = Transform3D(Basis.IDENTITY, (sm as Node3D).global_position + Vector3(0, 0.9 + 0.05, 0))
			if not space.intersect_shape(q, 1).is_empty():
				blocked += 1
				print("    blocked: %s %s at car-local %s" % [sm.name, kind, str(mid.to_local((sm as Node3D).global_position).snapped(Vector3(0.01, 0.01, 0.01)))])
		check(blocked == 0, "%s: %d of %d standing spots of a car are blocked" % [lid, blocked, spots])
		var half := 6.0
		var a := mid.global_position + Vector3(-half, 1.3, 0)
		var b := mid.global_position + Vector3(half, 1.3, 0)
		var rq := PhysicsRayQueryParameters3D.create(a, b)
		rq.collision_mask = 1
		var hit := space.intersect_ray(rq)
		check(hit.is_empty(), "%s: the aisle of a car is open along %.0f m (%s)" % [lid, half * 2.0, str(hit.get("collider", ""))])
		print("  info: %-17s %s stock: %d seats (%d facing along the car), %d standing spots" % [lid, tr.stock, seats, transverse, spots])
		tr.queue_free()
		await get_tree().process_frame
	print("OK" if ok else "FAILED")
