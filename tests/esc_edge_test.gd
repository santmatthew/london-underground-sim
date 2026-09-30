extends Node3D
## Escalator containment: drives a real Player capsule on every lane of a station's escalators and fails if it ever climbs onto a
## balustrade (height above the tread), leaves the shaft sideways while inside its length, or drops below the shaft.
## Two patterns per start point: a plain 3 s push in eight directions, and "pin" = the autopilot's stuck routine (strafe 0.9 s + forward
## against the lane, for 25 s), aimed up the slope from the foot of a down lane and down the slope from the head of an up lane.
## args: --station="Oxford Circus"  --esc=0,3 (indices; default all)  --secs=3  --pin-secs=25  --no-push  --no-pin
func run():
	var sname := "Oxford Circus"
	var secs := 3.0
	var pin_secs := 25.0
	var only: Array = []
	var do_push := true
	var do_pin := true
	var npc := false
	var real_crowd := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): sname = a.substr(10)
		if a.begins_with("--secs="): secs = float(a.substr(7))
		if a.begins_with("--pin-secs="): pin_secs = float(a.substr(11))
		if a.begins_with("--esc="):
			for t in a.substr(6).split(","): only.append(int(t))
		if a == "--no-push": do_push = false
		if a == "--no-pin": do_pin = false
		if a == "--npc": npc = true
		if a == "--crowd": real_crowd = true       # the station's real crowd (08:50 peak) instead of the synthetic rider stream
	Timetable.build(1)
	Clock.set_time(11.0 * 3600.0)
	for a in OS.get_cmdline_user_args():
		if a == "--crowd": Clock.set_time(8.8 * 3600.0)
	add_child(Env.make(0))
	var plan := StationPlan.for_station(Net.name_to_idx[sname])
	var st := Station.new()
	add_child(st)
	st.build(plan)
	st.rotation.y = deg_to_rad(180.0)
	st.position = Vector3(37.0, -3.0, 91.0)
	var player := Player.new()
	add_child(player)
	player.bot_active = true
	player.enabled = true
	st.trains.setup(st, player)
	st.attach_crowd(player)
	st.crowd.enabled = real_crowd
	for i in 6: await get_tree().physics_frame
	var cmds := [Vector2(0, -1), Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0), Vector2(1, -1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var total := 0
	var bad := 0
	var riders: Array = []        # [body, esc, lane, s, dir, zoff]
	var rrng := RandomNumberGenerator.new()
	rrng.seed = 7
	var spawn_t := 0.0
	for ei in st.escalators.size():
		if not only.is_empty() and not (ei in only):
			continue
		var esc := st.escalators[ei] as Escalator
		if esc.stairs:
			continue
		for li in esc.lanes.size():
			var runs: Array = []      # [label, s_frac, pattern(cmd or "pin"), yaw_along(+1 down / -1 up hill)]
			if do_push:
				for s_frac in [0.02, 0.5, 0.98]:
					for c in cmds:
						runs.append(["push %s" % str(c), s_frac, c])
			if do_pin:
				# the foot of a down lane / the head of an up lane, pressing on against the lane
				runs.append(["pin up-slope", 0.97, "pin_up"])
				runs.append(["pin down-slope", 0.03, "pin_down"])
			for r in runs:
				var s_frac: float = r[1]
				var pat = r[2]
				var start_l := esc.point_on_lane(li, esc.path_length() * s_frac)
				player.global_position = esc.to_global(start_l + Vector3(0, 0.15, 0))
				player.velocity = Vector3.ZERO
				var down := (esc.global_transform.basis * Vector3(1, 0, 0)).normalized()
				var face := down if not (pat is String and pat == "pin_up") else -down
				if pat is String and pat == "pin_down":
					face = down
				player.rotation.y = atan2(-face.x, -face.z)
				player.bot_yaw_target = player.rotation.y
				player.bot_move = Vector2.ZERO
				for i in 6: await get_tree().physics_frame
				var worst_h := -99.0
				var worst_sink := 99.0
				var worst_z := 0.0
				var min_y := 99.0
				var t := 0.0
				var dur := pin_secs if pat is String else secs
				var cyc := 0.0
				while t < dur:
					var dt := get_physics_process_delta_time()
					if pat is String:
						# the autopilot's stuck routine: 0.9 s sideways (alternating) while pushing forward at 0.7, then straight on for ~0.6 s
						cyc = fmod(t, 1.5)
						var side := 1.0 if int(t / 1.5) % 2 == 0 else -1.0
						player.bot_move = Vector2(side, -0.7) if cyc < 0.9 else Vector2(0, -1.0)
					else:
						player.bot_move = pat
					await get_tree().physics_frame
					t += dt
					if npc:
						spawn_t -= dt
						if spawn_t <= 0.0:
							spawn_t = rrng.randf_range(0.8, 2.0)
							var lj := rrng.randi() % esc.lanes.size()
							var b := AnimatableBody3D.new()
							b.collision_layer = 1 << 1
							b.collision_mask = 0
							b.sync_to_physics = false
							var cs := CollisionShape3D.new()
							var cyl := CylinderShape3D.new()
							cyl.radius = 0.25
							cyl.height = 1.75
							cs.shape = cyl
							b.add_child(cs)
							add_child(b)
							var dirn := 1.0 if esc.lanes[lj] == 1 else -1.0
							riders.append([b, esc, lj, 0.0 if dirn > 0.0 else esc.path_length(), dirn, 0.24 if rrng.randf() < 0.82 else -0.24])
						for k in range(riders.size() - 1, -1, -1):
							var rd: Array = riders[k]
							rd[3] = float(rd[3]) + float(rd[4]) * Escalator.SPEED * dt
							var re := rd[1] as Escalator
							if float(rd[3]) < -0.5 or float(rd[3]) > re.path_length() + 0.5:
								(rd[0] as Node).queue_free()
								riders.remove_at(k)
								continue
							var pt := re.point_on_lane(int(rd[2]), clampf(float(rd[3]), 0.0, re.path_length()))
							(rd[0] as Node3D).global_position = re.to_global(pt + Vector3(0, 0.88, float(rd[5])))
					var lp := esc.to_local(player.global_position)
					if lp.x >= -0.2 and lp.x <= esc.length + 0.2:
						worst_h = maxf(worst_h, lp.y - esc.slope_y(lp.x))
						worst_sink = minf(worst_sink, lp.y - esc.slope_y(lp.x))
						worst_z = maxf(worst_z, absf(lp.z))
						min_y = minf(min_y, lp.y + esc.rise)      # a fall is only a fall inside the shaft: walking off the end and down the next flight is fine
				player.bot_move = Vector2.ZERO
				for rd in riders:
					(rd[0] as Node).queue_free()
				riders.clear()
				total += 1
				var hw := esc.width * 0.5
				if worst_sink < -0.3 and worst_sink > -3.0:
					bad += 1
					print("  FAIL esc%d lane %d s=%.2f %s : sank %.2f m into the tread (feet below the surface)" % [ei, li, s_frac, r[0], -worst_sink])
				if worst_h > 0.6 or worst_z > hw + 0.05 or min_y < -1.0:
					bad += 1
					print("  FAIL esc%d lane %d s=%.2f %s : max height above surface %.2f, max |z| %.2f (half width %.2f), min y above bottom %.2f" % [ei, li, s_frac, r[0], worst_h, worst_z, hw, min_y])
	print("%s: %d escalator runs, %d failed" % [sname, total, bad])
