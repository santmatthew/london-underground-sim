extends Node3D
## Floor-collision audit: samples every planned route (street -> platform faces and back) for missing floor. args: --stations="A,B,C"
func run():
	var names_arg := "King's Cross St. Pancras,Oxford Circus,Baker Street,Barbican,Chiswick Park,Epping,Bank"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stations="): names_arg = a.substr(11)
	Timetable.build(1)
	add_child(Env.make(0))
	var total_gaps := 0
	for sname in names_arg.split(","):
		var idx: int = Net.name_to_idx[sname]
		var plan := StationPlan.for_station(idx)
		var st := Station.new()
		add_child(st)
		st.build(plan)
		for i in 6: await get_tree().physics_frame
		var space := get_world_3d().direct_space_state
		var gaps := {}
		var checked := 0
		var pairs: Array = []
		for fk in plan.faces:
			pairs.append(["hall_unpaid", "face:" + fk])
			pairs.append(["face:" + fk, plan.street_doors[0]["id"]])
			var f: Dictionary = plan.faces[fk]
			for oi in 2:
				var on := "m%d_open%d_p%d" % [f["module"], oi, f["face"]]
				pairs.append([on, plan.street_doors[0]["id"]])
				for fk2 in plan.faces:
					if fk2 != fk:
						pairs.append([on, "face:" + fk2])
		for pr in pairs:
			var names := plan.path(pr[0], pr[1])
			var wps := plan.walk_points(names, 0)
			for k in range(1, wps.size()):
				var a: Vector3 = wps[k - 1]["pos"]
				var b: Vector3 = wps[k]["pos"]
				var len := a.distance_to(b)
				var steps := maxi(1, int(len / 0.4))
				for s in steps + 1:
					var p := a.lerp(b, float(s) / steps)
					var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.2, 0), p + Vector3(0, -2.5, 0))
					q.collision_mask = 1
					var hit := space.intersect_ray(q)
					checked += 1
					if hit.is_empty():
						var key := "%s->%s wp %d (%.0f,%.1f,%.0f)" % [pr[0], pr[1], k, p.x, p.y, p.z]
						if gaps.size() < 40:
							gaps[key] = true
		total_gaps += gaps.size()
		print("%s: %d samples, %d gap spots" % [sname, checked, gaps.size()])
		var shown := {}
		for k in gaps.keys():
			var seg: String = k.split(" (")[0]
			if not shown.has(seg):
				shown[seg] = true
				print("    ", k)
		st.queue_free()
		await get_tree().process_frame
	print("TOTAL gap spots: ", total_gaps)
