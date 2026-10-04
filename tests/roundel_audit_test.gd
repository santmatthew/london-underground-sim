extends Node3D
## Every station-name roundel hangs on something and faces away from it: a ray from 15 cm in front of the plate to 45 cm behind it hits a wall, a column or another sign (a roundel with nothing behind it floats in the
## air), and a ray 25 cm out from the front hits nothing (a roundel that faces a column shows only its ring - the plate is one-sided - from outside, with the text behind it).
## args --stations=Name,Name (default: a spread of the network) --all
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	Timetable.build(1)
	var names: Array = []
	var all := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stations="):
			names = a.substr(11).split(",")
		if a == "--all":
			all = true
	if names.is_empty():
		var n := Net.station_ids.size()
		var step := 1 if all else 6
		var i := 0
		while i < n:
			names.append(Net.stations[i]["name"])
			i += step
	var total := 0
	var floating := 0
	for nm in names:
		var plan := StationPlan.for_station(Net.name_to_idx[nm])
		var st := Station.new()
		add_child(st)
		st.build(plan)
		for _f in 3:
			await get_tree().physics_frame
		var space := get_world_3d().direct_space_state
		var here := 0
		for n in st.find_children("*", "Node3D", true, false):
			if not n.has_meta("roundel"):
				continue
			total += 1
			var gt := (n as Node3D).global_transform
			var q := PhysicsRayQueryParameters3D.create(gt.origin + gt.basis.z * 0.15, gt.origin - gt.basis.z * 0.45)
			q.collision_mask = 0xFFFFFFFF
			var hit := space.intersect_ray(q)
			var qf := PhysicsRayQueryParameters3D.create(gt.origin + gt.basis.z * 0.06, gt.origin + gt.basis.z * 0.25)
			qf.collision_mask = 0xFFFFFFFF
			var fh := space.intersect_ray(qf)
			var blocked := not fh.is_empty()
			if hit.is_empty() or blocked:
				floating += 1
				here += 1
				if here <= 3:
					print("    %s: a roundel %s at station-local %s facing %s (module %s)" % [nm, "with nothing behind it" if hit.is_empty() else "facing a wall or column", str(st.to_local(gt.origin).snapped(Vector3(0.1, 0.1, 0.1))), str(st.global_transform.basis.inverse() * gt.basis.z), str((n as Node3D).get_parent().name)] + ("" if fh.is_empty() else " - hit %s at %.2f m" % [str((fh["collider"] as Node).get_path()).get_slice("/", 4) + "/" + str((fh["collider"] as Node).name), (fh["position"] as Vector3).distance_to(gt.origin)]))
		st.queue_free()
		await get_tree().process_frame
	print("  info: %d roundels in %d stations, %d floating or facing a wall" % [total, names.size(), floating])
	check(floating == 0, "every roundel hangs on something and faces away from it (%d do not)" % floating)
	print("OK" if ok else "FAILED")
