extends Node3D
## Casts horizontal rays from a station-local point in 8 directions and prints what each hits (node path, distance) - "what is that wall?".
## args: --station="Victoria" --pos=-14,-4.75,36 --dist=40
func run():
	var sname := "Victoria"
	var pos := Vector3.ZERO
	var dist := 40.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): sname = a.substr(10)
		if a.begins_with("--pos="):
			var c := a.substr(6).split(",")
			pos = Vector3(float(c[0]), float(c[1]), float(c[2]))
		if a.begins_with("--dist="): dist = float(a.substr(7))
	Timetable.build(1)
	add_child(Env.make(0))
	var plan := StationPlan.for_station(Net.name_to_idx[sname])
	var st := Station.new()
	add_child(st)
	st.build(plan)
	for i in 6: await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for k in 8:
		var ang := k * PI / 4.0
		var dir := Vector3(sin(ang), 0, cos(ang))
		var q := PhysicsRayQueryParameters3D.create(pos, pos + dir * dist)
		q.collision_mask = 0xffff
		var h := space.intersect_ray(q)
		if h.is_empty():
			print("dir (%+.0f,%+.0f): nothing within %.0f m" % [dir.x, dir.z, dist])
		else:
			var col := h["collider"] as Node
			print("dir (%+.0f,%+.0f): %.1f m  %s  layer %d" % [dir.x, dir.z, pos.distance_to(h["position"]), str(col.get_path()).replace("/root/Runner/", ""), (col as CollisionObject3D).collision_layer])
