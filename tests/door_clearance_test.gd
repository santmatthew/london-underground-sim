extends Node3D
## The player's real capsule (0.27 m radius, 1.72 m tall) must be able to stand in every doorway of every car model, and walk through it from the platform side to the aisle (a lintel too low, a wall in the
## way: the Central line's first rounded-body cars had a doorway 1.70 m high and nobody could board).
var ok := true

const FLOOR := {"deep": 0.88, "ss": 1.00}


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	var space := get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.27
	cap.height = 1.72
	var i := 0
	for key in Train.CAR_SCENES:
		var car: Node3D = (load(Train.CAR_SCENES[key]) as PackedScene).instantiate()
		car.position = Vector3(0, 0, 40.0 * float(i))
		add_child(car)
		i += 1
	for _f in 3:
		await get_tree().physics_frame
	space = get_world_3d().direct_space_state
	i = 0
	for key in Train.CAR_SCENES:
		var fam: String = key.substr(0, key.find("_"))
		var kind := "deep" if fam.begins_with("deep") else fam
		var base: String = kind + key.substr(key.find("_"))
		var fl: float = FLOOR[kind]
		var blocked := 0
		var tried := 0
		for dx in Train.DOOR_X[base]:
			for side in [-1.0, 1.0]:
				# along the doorway from the platform (2.2 m out) to the aisle
				var zz := 2.2
				while zz >= -0.4:
					var q := PhysicsShapeQueryParameters3D.new()
					q.shape = cap
					q.transform = Transform3D(Basis.IDENTITY, Vector3(float(dx), fl + 0.86 + 0.03, side * zz + 40.0 * float(i)))
					q.collision_mask = 0xFFFFFFFF
					var hits := space.intersect_shape(q, 8)
					for h in hits:
						var nm := str((h["collider"] as Node).name)
						if nm.begins_with("DoorBlock"):
							continue          # (the sliding doors: shut or open in the game)
						blocked += 1
						if blocked <= 2:
							print("    ", key, " door at ", dx, " side ", side, " z ", zz, " blocked by ", nm)
					tried += 1
					zz -= 0.1
		check(blocked == 0, "%s: the capsule passes every doorway (%d of %d positions blocked)" % [key, blocked, tried])
		i += 1
	print("OK" if ok else "FAILED")
