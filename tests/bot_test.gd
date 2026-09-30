extends Node
## Runs the autopilot through a whole journey headless-ish and reports the result. args: --seed=N --time=am_peak --length=short
func run():
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {}
	add_child(g)
	await get_tree().process_frame
	var seed := 1
	var every := 3600
	var max_frames := 60 * 60 * 70        # --frames=N (physics frames); the GTEST timeout is the real limit
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="): seed = int(a.substr(7))
		if a.begins_with("--every="): every = int(a.substr(8))
		if a.begins_with("--frames="): max_frames = int(a.substr(9))
		if a.begins_with("--time="): g.opts["time"] = a.substr(7)
		if a.begins_with("--length="): g.opts["length"] = a.substr(9)
		if a.begins_with("--multi="): g.opts["mode"] = "multi"; g.opts["stops"] = int(a.substr(8))
	g.cli["seed"] = str(seed)
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] in ["start", "dest", "spot", "hour"]: g.cli[kv[0]] = kv[1]
	g.cli["autopilot"] = "1"
	g.start_journey()
	var t := 0.0
	while g.state != Game.State.BRIEFING:
		await get_tree().process_frame
	print("journey: ", Net.station_name(g.journey["start"]), " (", g.journey["spot"]["name"], ") mode ", g.journey["mode"], " targets ", g.journey.get("targets", []).map(func(t): return Net.station_name(t)) if g.journey["mode"] == "multi" else Net.station_name(g.journey["dest"]))
	while g.state != Game.State.PLAYING:
		await get_tree().process_frame
	var frames := 0
	var y_prev: float = g.player.global_position.y
	var drops := 0
	var trail: Array = []
	while g.state == Game.State.PLAYING and frames < max_frames:
		await get_tree().physics_frame
		frames += 1
		var y_now: float = g.player.global_position.y
		if frames % 10 == 0:
			var sc0 := g.player.get_last_slide_collision()
			trail.append("%s pos %s vfloor %s slide %s mode %s" % [Clock.fmt(Clock.now, true), str(g.player.global_position.snapped(Vector3(0.1, 0.1, 0.1))), str(g.player.is_on_floor()), ((sc0.get_collider() as Node).get_parent().name + "/" + (sc0.get_collider() as Node).name if sc0 and sc0.get_collider() != null and is_instance_valid(sc0.get_collider()) else "-"), g.autopilot.mode if g.autopilot else "-"])
			if trail.size() > 24:
				trail.pop_front()
		if y_now < y_prev - 0.25 and drops < 6:
			drops += 1
			var ph := "-"
			if g.ride != null:
				ph = "phase %d t_arr-now %.1f dest_ready %s speed %.1f" % [g.ride.phase, g.ride.t_arr - Clock.now, str(g.ride.dest_ready), g.ride.speed_now]
			print("DROP y %.2f -> %.2f at %s clock %s riding=%s ride[%s] station=%s on_floor=%s mode=%s" % [y_prev, y_now, str(g.player.global_position.snapped(Vector3(0.1, 0.1, 0.1))), Clock.fmt(Clock.now, true), str(g.riding), ph, g.station.plan.name if g.station else "null", str(g.player.is_on_floor()), g.autopilot.mode if g.autopilot else "-"])
			if drops == 1 and g.riding and g.ride != null and g.ride.train != null:
				var trn: Train = g.ride.train
				var pl: Vector3 = trn.to_local(g.player.global_position)
				print("   RIDE-DROP player train-local %s train x %.1f kind %s cars %d length %.1f" % [str(pl.snapped(Vector3(0.1, 0.1, 0.1))), trn.position.x, trn.kind, trn.n_cars, trn.length])
				var space := g.player.get_world_3d().direct_space_state
				var qy := PhysicsRayQueryParameters3D.create(g.player.global_position + Vector3(0, 0.6, 0), g.player.global_position + Vector3(0, -2.0, 0))
				qy.collision_mask = 0xffff
				var hy := space.intersect_ray(qy)
				print("   ray below player: ", (hy["collider"] as Node).get_path() if not hy.is_empty() else "NONE", " at ", str(hy.get("position", Vector3.ZERO)))
				for fl in trn.find_children("Floor*", "CollisionObject3D", true, false):
					var co := fl as CollisionObject3D
					var cs := co.get_child(0) as CollisionShape3D if co.get_child_count() > 0 and co.get_child(0) is CollisionShape3D else null
					print("     floor body ", co.get_path().get_name(co.get_path().get_name_count() - 2), "/", co.name, " layer ", co.collision_layer, " at ", str(co.global_position.snapped(Vector3(0.1, 0.1, 0.1))), " disabled ", str(cs.disabled) if cs else "?")
			if drops <= 2 and g.station != null and not g.riding:
				var sp := g.get_world_3d().direct_space_state
				var lp0: Vector3 = g.station.to_local(g.player.global_position)
				var sq := PhysicsShapeQueryParameters3D.new()
				var capq := CapsuleShape3D.new()
				capq.radius = 0.27
				capq.height = 1.76
				sq.shape = capq
				sq.collision_mask = 0xffff
				sq.transform = Transform3D(Basis.IDENTITY, g.player.global_position + Vector3(0, 0.88, 0))
				for hq in sp.intersect_shape(sq, 8):
					var cq := hq["collider"] as Node
					if cq != g.player:
						print("   OVERLAPS %s (layer %d)" % [str(cq.get_path()).replace("/root/Runner/", ""), (cq as CollisionObject3D).collision_layer])
				var sph := SphereShape3D.new()
				sph.radius = 1.3
				var sq2 := PhysicsShapeQueryParameters3D.new()
				sq2.shape = sph
				sq2.collision_mask = 0xffff
				sq2.transform = Transform3D(Basis.IDENTITY, g.player.global_position + Vector3(0, 1.0, 0))
				var near_names := {}
				for hq2 in sp.intersect_shape(sq2, 32):
					var c2 := hq2["collider"] as Node
					if c2 != g.player:
						var cs2 := (c2 as CollisionObject3D).shape_owner_get_shape(0, 0) if (c2 as CollisionObject3D).get_shape_owners().size() > 0 else null
						near_names["%s shape %d %s" % [str(c2.get_path()).replace("/root/Runner/", ""), int(hq2.get("shape", -1)), (cs2 as Shape3D).get_class() if cs2 else "?"]] = true
				print("   within 1.3 m: ", near_names.keys())
				print("   station-local %s; colliders below (ray from +1 m to -1.5 m):" % str(lp0.snapped(Vector3(0.1, 0.1, 0.1))))
				var from_p: Vector3 = g.player.global_position + Vector3(0, 1.0, 0)
				var ex: Array = []
				for k in 4:
					var qq := PhysicsRayQueryParameters3D.create(from_p, from_p + Vector3(0, -2.5, 0))
					qq.exclude = ex
					var hh := sp.intersect_ray(qq)
					if hh.is_empty(): break
					print("      %s at y %.2f" % [str((hh["collider"] as Node).get_path()).replace("/root/Runner/", ""), (hh["position"] as Vector3).y])
					ex.append(hh["rid"])
			if drops == 1:
				print("   TRAIL (last %d samples, 1/6 s apart):" % trail.size())
				for tl in trail:
					print("     ", tl)
			if drops == 1 and g.station != null and not g.riding:
				var pp: Vector3 = g.player.global_position
				for e in g.station.escalators:
					var en := e as Node3D
					var lp2: Vector3 = en.to_local(pp)
					if absf(lp2.z) < 6.0 and lp2.x > -8.0 and lp2.x < float(e.length) + 8.0:
						var lays := []
						for co in en.find_children("*", "CollisionObject3D", true, false):
							lays.append("%s:%d" % [co.name, (co as CollisionObject3D).collision_layer])
						print("   ESC near player: %s local %s rise %.1f layers %s" % [en.name, str(lp2.snapped(Vector3(0.1, 0.1, 0.1))), float(e.rise), str(lays)])
				print("   station rot y %.1f deg, pos %s" % [rad_to_deg(g.station.global_rotation.y), str(g.station.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
			if drops == 1 and g.station != null:
				for key in g.station.trains.visits:
					var vv: Dictionary = g.station.trains.visits[key]
					var tr: Train = vv["train"]
					print("   visit %s train at %s (x_local %.1f) doors %s player-in-train-coords %s ext %s info arr %s dep %s" % [key, str(tr.global_position.snapped(Vector3(0.1, 0.1, 0.1))), tr.position.x, str(vv["doors"]), str(tr.to_local(g.player.global_position).snapped(Vector3(0.1, 0.1, 0.1))), str(g.station.trains.external.has(key)), Clock.fmt(vv["info"]["arr"], true), Clock.fmt(vv["info"]["dep"], true)])
		y_prev = y_now
		if frames % every == 0 and g.autopilot:
			print("  f=%d clock %s mode %s wp %d/%d pos %s local %s mv %s crowd %s" % [frames, Clock.fmt(Clock.now, true), g.autopilot.mode, g.autopilot.wp_i, g.autopilot.wps.size(), str(g.player.global_position), str(g.station.to_local(g.player.global_position).snapped(Vector3(0.1, 0.1, 0.1))) if g.station else "-", str(g.player.bot_move.snapped(Vector2(0.1, 0.1))) + " hurry " + str(g.player.bot_hurry) + "/" + str(g.player.hurrying) + " stam %.2f" % g.player.stamina + " real " + str(g.player.get_real_velocity().snapped(Vector3(0.1, 0.1, 0.1))) + " floor " + str(g.player.is_on_floor()) + " slide " + (str(g.player.get_last_slide_collision().get_collider().get_path().get_name(g.player.get_last_slide_collision().get_collider().get_path().get_name_count() - 1)) if g.player.get_last_slide_collision() else "-"), str(g.station.crowd.stats) if g.station and g.station.crowd else ""])
	print("state ", g.state, " frames ", frames, " sim end ", Clock.fmt(Clock.now, true))
	if g.autopilot:
		for l in g.autopilot.log_lines: print(l)
