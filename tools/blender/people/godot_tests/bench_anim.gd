extends Node3D
# per-frame CPU cost of animating N people (advance + skeleton pose update) by detail level, measured in a tight loop
func _ready():
	var n := 150
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var people: Array = []
	for i in n:
		var p := PersonModel.create(rng.randi() % PersonModel.count(), 1 + rng.randi() % 100000)
		p.manual_tick = true
		add_child(p)
		var r := rng.randf()
		if r < 0.5: p.play(&"idle_stand_%d" % (1 + rng.randi() % 3), 0.0)
		elif r < 0.6: p.play(&"stand_hold", 0.0)
		else: p.set_locomotion_speed(rng.randf_range(0.9, 1.9))
		people.append(p)
	await get_tree().process_frame
	for level in [0, 1, 2, 3]:
		for p in people: p.set_detail(level)
		var t0 := Time.get_ticks_usec()
		var frames := 240
		for f in frames:
			for p in people:
				p.tick(1.0 / 60.0)
				p.skeleton.force_update_all_bone_transforms()
		var dt := (Time.get_ticks_usec() - t0) / 1000.0 / frames
		print("BENCH level=", level, " (", ["60Hz", "30Hz", "15Hz", "8Hz"][level], ") avg CPU per 60Hz frame for ", n, " people = ", snappedf(dt, 0.01), " ms")
	for p in people: p.set_detail(4)
	var t0 := Time.get_ticks_usec()
	for f in 240:
		for p in people: p.tick(1.0 / 60.0)
	print("BENCH frozen ", snappedf((Time.get_ticks_usec() - t0) / 1000.0 / 240, 0.001), " ms")
	get_tree().quit()
