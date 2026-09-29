extends Node3D
## Drives a real Player capsule along planned routes (hall -> each platform face) and reports where it gets stuck or leaves the floor.
## args: --station="King's Cross St. Pancras"  --max=4
func run():
	var sname := "King's Cross St. Pancras"
	var maxr := 99
	var rot_deg := 0.0       # --rot=180: place the station rotated/offset like the ride does (catches world-space assumptions, e.g. gates)
	var trace := false       # --trace: print the position twice a second
	var reverse := false     # --reverse: walk from each platform face out to the street instead of hall -> platform
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): sname = a.substr(10)
		if a.begins_with("--max="): maxr = int(a.substr(6))
		if a == "--reverse": reverse = true
		if a == "--trace": trace = true
		if a.begins_with("--rot="): rot_deg = float(a.substr(6))
	Timetable.build(1)
	Clock.set_time(11.0 * 3600.0)
	add_child(Env.make(0))
	var idx: int = Net.name_to_idx[sname]
	var plan := StationPlan.for_station(idx)
	var st := Station.new()
	add_child(st)
	st.build(plan)
	if rot_deg != 0.0:
		st.rotation.y = deg_to_rad(rot_deg)
		st.position = Vector3(37.0, -3.0, 91.0)
	var player := Player.new()
	add_child(player)
	player.bot_active = true
	player.enabled = true
	st.trains.setup(st, player)
	st.attach_crowd(player)
	st.crowd.enabled = false
	for i in 6: await get_tree().physics_frame
	var routes := 0
	var fails := 0
	for fk in plan.faces:
		if routes >= maxr: break
		routes += 1
		var names := plan.path("hall_unpaid", "face:" + fk)
		var wps: Array
		if reverse:
			names = []
			for sd in plan.street_doors:
				var p := plan.path("face:" + fk, sd["id"])
				if names.is_empty() or (not p.is_empty() and p.size() < names.size()):
					names = p
			wps = plan.walk_points(names, 0)
			wps.insert(0, {"pos": st.platform_point(fk, 0.5, 1.4), "kind": "walk"})
		else:
			wps = plan.walk_points(names, 0)
			wps.append({"pos": st.platform_point(fk, 0.5, 1.4), "kind": "walk"})
		for w in wps:
			w["pos"] = st.to_global(w["pos"])
		player.global_position = wps[0]["pos"] + Vector3(0, 0.1, 0)
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		var ok := true
		var k := 1
		var t_wp := 0.0
		while k < wps.size():
			var target: Vector3 = wps[k]["pos"]
			var pos := player.global_position
			var flat := Vector3(target.x - pos.x, 0, target.z - pos.z)
			if flat.length() < 0.5:
				k += 1
				t_wp = 0.0
				continue
			var dir := flat.normalized()
			player.bot_yaw_target = atan2(-dir.x, -dir.z)
			var yaw_err := absf(angle_difference(player.rotation.y, player.bot_yaw_target))
			player.bot_move = Vector2(0, -1.0 if yaw_err < 0.6 else -0.1)
			await get_tree().physics_frame
			t_wp += get_physics_process_delta_time()
			if trace and int(t_wp * 60.0) % 30 == 0:
				var sc := player.get_last_slide_collision()
				print("    t=%.1f wp %d pos %s vel %s floor %s slide %s" % [t_wp, k, str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))), str(player.velocity.snapped(Vector3(0.1, 0.1, 0.1))), str(player.is_on_floor()), sc.get_collider().get_path().get_name(sc.get_collider().get_path().get_name_count() - 1) if sc else "-"])
			var seg_len: float = (wps[k]["pos"] as Vector3).distance_to(wps[k - 1]["pos"])
			if t_wp > seg_len / 0.9 + 6.0 or player.global_position.y < -80.0:
				print("  FAIL %s wp %d/%d (%s) at %s target %s  dy=%.2f" % [fk, k, wps.size(), wps[k]["kind"], str(player.global_position.snapped(Vector3(0.1, 0.1, 0.1))), str(target.snapped(Vector3(0.1, 0.1, 0.1))), player.global_position.y - target.y])
				ok = false
				var col_info := KinematicCollision3D.new()
				var motion := (target - player.global_position)
				motion.y = 0.0
				motion = motion.normalized() * 0.3
				if player.test_move(player.global_transform, motion, col_info):
					var cc := col_info.get_collider() as Node
					print("      MOVE BLOCKED by ", cc.get_path(), " at ", col_info.get_position(), " normal ", col_info.get_normal(), " shape ", col_info.get_collider_shape())
				var space := get_world_3d().direct_space_state
				var sq := PhysicsShapeQueryParameters3D.new()
				var cap := CapsuleShape3D.new(); cap.radius = 0.36; cap.height = 1.8
				sq.shape = cap
				sq.collision_mask = 0xffff
				for off in [Vector3(0.6, 0.9, 0), Vector3(-0.6, 0.9, 0), Vector3(0, 0.9, 0.6), Vector3(0, 0.9, -0.6)]:
					sq.transform = Transform3D(Basis.IDENTITY, player.global_position + off)
					for h in space.intersect_shape(sq, 6):
						var col := h["collider"] as Node
						if col != player:
							print("      blocker near ", off, ": ", col.get_path(), " layer ", (col as CollisionObject3D).collision_layer)
				break
		player.bot_move = Vector2.ZERO
		if not ok: fails += 1
		else: print("  ok   ", fk)
	print("%s: %d routes, %d failed" % [sname, routes, fails])
