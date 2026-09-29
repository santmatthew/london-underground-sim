extends Node3D
## Every spine must be walled on both sides along its whole length: a capsule pushed sideways must not be able to step off the floor.
## args: --stations="A|B|C"
func run():
	Timetable.build(1)
	add_child(Env.make(0))
	var names := "Euston|Holborn|Bank|King's Cross St. Pancras|Oxford Circus|Goodge Street|Edgware Road (Circle)".split("|")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stations="): names = a.substr(11).split("|")
	var holes := 0
	for nm in names:
		var idx: int = Net.name_to_idx[nm]
		var st := Station.new()
		add_child(st)
		st.build(StationPlan.for_station(idx))
		for i in 3: await get_tree().physics_frame
		var space := get_world_3d().direct_space_state
		var bad := 0
		for mi in st.modules.size():
			var pm: PlatformModule = st.modules[mi]
			if pm.box:
				continue
			var sx0: float = pm.meta["spine_x0"]
			var sx1: float = pm.meta["spine_x1"]
			for s in [1.0, -1.0]:
				var x := sx0 + 0.3
				while x < sx1:
					# skip the wall openings into the platforms
					var in_open := false
					for ox in pm.meta["openings"]:
						if absf(x - ox) < PlatformModule.OPEN_W * 0.5 + 0.2:
							in_open = true
					if not in_open:
						var a := pm.to_global(Vector3(x, 1.0, s * (PlatformModule.GAP * 0.5 - 0.4)))
						var b := pm.to_global(Vector3(x, 1.0, s * (PlatformModule.GAP * 0.5 + 0.4)))
						var q := PhysicsRayQueryParameters3D.create(a, b)
						q.collision_mask = 1
						if space.intersect_ray(q).is_empty():
							bad += 1
							if bad <= 3:
								print("  HOLE %s module %d side %+.0f x=%.1f (module-local)" % [nm, mi, s, x])
					x += 0.5
		print("%s: %d wall holes" % [nm, bad])
		holes += bad
		st.queue_free()
		for i in 2: await get_tree().process_frame
	print("TOTAL wall holes: ", holes)
