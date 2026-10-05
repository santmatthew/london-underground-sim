extends Node3D
## The escalators have real steps: one moving mesh a lane (a tread and a riser per step, put on the track by shaders/escalator_steps.gdshader), the steps run the way the lane goes and as fast as its collision
## slab carries a rider, the loop closes (a whole number of steps, long enough to wrap out of sight under the plates), the mesh is given a culling box, and fixed stairs have none.
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	for rise in [3.2, 11.5, 24.0]:
		for lanes in [[1.0, -1.0, 1.0], [-1.0, -1.0], [1.0]]:
			var e := Escalator.new()
			e.build(rise, lanes)
			add_child(e)
			var tag := "rise %.1f lanes %s" % [rise, str(lanes)]
			var mi := e.get_node_or_null("Steps") as MeshInstance3D
			check(mi != null, "%s: has a Steps mesh" % tag)
			if mi == null:
				continue
			var mesh := mi.mesh as ArrayMesh
			check(mesh.get_surface_count() == lanes.size(), "%s: a surface a lane (%d)" % [tag, mesh.get_surface_count()])
			var slope := e.run / cos(Escalator.ANGLE)
			for li in mesh.get_surface_count():
				var m := mesh.surface_get_material(li) as ShaderMaterial
				var arrays := mesh.surface_get_arrays(li)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
				var n := verts.size() / 8
				var pitch: float = m.get_shader_parameter("pitch")
				var loop_len: float = m.get_shader_parameter("loop_len")
				check(verts.size() == n * 8 and n >= 3, "%s lane %d: a tread and a riser (8 vertices) a step (%d steps)" % [tag, li, n])
				check(absf(loop_len - float(n) * pitch) < 0.0001, "%s lane %d: the loop is a whole number of steps (%.2f m of %d)" % [tag, li, loop_len, n])
				# the loop has room for the slope and for a step to go in under each plate and come out of the other
				check(loop_len >= slope + 2.0 * pitch, "%s lane %d: the loop (%.1f m) covers the slope (%.1f m) and the hidden stretch" % [tag, li, loop_len, slope])
				check(loop_len <= slope + 2.0 * pitch + 2.5 * pitch + 0.001, "%s lane %d: ... without many more steps than that" % [tag, li])
				# the hidden stretch stays under the plate (a plate is Escalator.PLATE long)
				check(loop_len - slope - pitch <= Escalator.PLATE, "%s lane %d: the steps out of sight fit under the landing plate" % [tag, li])
				check(float(m.get_shader_parameter("speed")) == Escalator.SPEED * float(lanes[li]), "%s lane %d: the steps go %s at the slab's speed" % [tag, li, "down" if lanes[li] > 0.0 else "up"])
				check(float(m.get_shader_parameter("fillet")) == Escalator.STEP_FILLET and float(m.get_shader_parameter("pitch")) == Escalator.STEP_PITCH, "%s lane %d: the steps' shader has the pitch and the corner radius (%.2f, %.2f)" % [tag, li, float(m.get_shader_parameter("pitch")), float(m.get_shader_parameter("fillet"))])
				check(absf(float(m.get_shader_parameter("l_vis")) - slope) < 0.0001 and is_equal_approx(float(m.get_shader_parameter("x0")), Escalator.PLATE), "%s lane %d: the track runs along the slope the slab does" % [tag, li])
				check(is_equal_approx(float(m.get_shader_parameter("rise")), rise) and is_equal_approx(float(m.get_shader_parameter("run")), e.run), "%s lane %d: ... down to the same bottom" % [tag, li])
				# every step index once, as a tread and as a riser; the local coordinates are what the shader expects
				var seen := {}
				var bad := 0
				for i in verts.size():
					var k := int(uv2[i].x)
					seen[k] = seen.get(k, 0) + 1
					if verts[i].x < -0.001 or verts[i].x > 1.001 or verts[i].y < -0.001 or verts[i].y > 1.001:
						bad += 1
				check(seen.size() == n and bad == 0, "%s lane %d: steps 0..%d, local coordinates in 0..1" % [tag, li, n - 1])
				# the lane's width: the steps are as wide as the lane
				var z0 := 1e9
				var z1 := -1e9
				for v in verts:
					z0 = minf(z0, v.z)
					z1 = maxf(z1, v.z)
				check(absf((z1 - z0) - Escalator.LANE_W) < 0.001 and absf((z0 + z1) * 0.5 - e.lane_z(li)) < 0.001, "%s lane %d: as wide as the lane and on it" % [tag, li])
			# the handrails: a ribbon a lane (its two rails) moving with the lane, following the balustrade
			var hr := e.get_node_or_null("Handrails") as MeshInstance3D
			check(hr != null and (hr.mesh as ArrayMesh).get_surface_count() == lanes.size(), "%s: a handrail surface a lane" % tag)
			if hr != null:
				for li in lanes.size():
					var hm := (hr.mesh as ArrayMesh).surface_get_material(li) as ShaderMaterial
					check(float(hm.get_shader_parameter("speed")) == Escalator.SPEED * float(lanes[li]), "%s lane %d: the rails move %s with the steps" % [tag, li, "down" if lanes[li] > 0.0 else "up"])
					var hv: PackedVector3Array = (hr.mesh as ArrayMesh).surface_get_arrays(li)[Mesh.ARRAY_VERTEX]
					var zlo := 1e9
					var zhi := -1e9
					for v in hv:
						zlo = minf(zlo, v.z)
						zhi = maxf(zhi, v.z)
					# (two rails: one each side of the lane, between the balustrades' middles)
					check(zlo > e.lane_z(li) - Escalator.PITCH * 0.5 and zhi < e.lane_z(li) + Escalator.PITCH * 0.5 and zhi - zlo > Escalator.PITCH - 0.4, "%s lane %d: the rails lie on the lane's balustrades (z %.2f .. %.2f)" % [tag, li, zlo, zhi])
			var rp: Array = e._rail_path()
			var first: Vector2 = rp[0][0]
			var last: Vector2 = rp[rp.size() - 1][0]
			check(absf(first.y - Escalator.RAIL_H) < 0.001 and absf(last.y - (-rise + Escalator.RAIL_H)) < 0.001 and absf(last.x - e.length) < 0.001, "%s: the rail runs from one newel to the other at handrail height" % tag)
			var mono := true
			var worst := 0.0
			for i in rp.size():
				if i > 0 and float(rp[i][1]) <= float(rp[i - 1][1]):
					mono = false
				# on the slope the rail lies RAIL_H above the tread line, along the normal
				var pt: Vector2 = rp[i][0]
				if pt.x > Escalator.PLATE + 1.0 and pt.x < Escalator.PLATE + e.run - 1.0:
					var dist_line := (pt.y + (pt.x - Escalator.PLATE) * tan(Escalator.ANGLE)) * cos(Escalator.ANGLE)
					worst = maxf(worst, absf(dist_line - Escalator.RAIL_H))
			check(mono, "%s: the rail's arc length only grows" % tag)
			check(worst < 0.01, "%s: on the slope the rail is %.3f m above the treads, along the normal (worst %.3f m off)" % [tag, Escalator.RAIL_H, worst])
			# the culling box holds the shaft (the vertices the engine sees are not where they are drawn)
			var box := mesh.custom_aabb
			check(box.has_point(Vector3(0.0, 0.0, 0.0)) and box.has_point(Vector3(e.length, -rise, 0.0)) and box.has_point(Vector3(e.length * 0.5, -rise * 0.5, e.width * 0.5)), "%s: the culling box holds the shaft" % tag)
			# the slab that carries the rider moves the same way as the steps (its velocity is set once the node is in the tree)
			await get_tree().process_frame
			for bi in lanes.size():
				var body := e.get_node("Tread%d" % bi) as AnimatableBody3D
				var v := body.constant_linear_velocity
				check((v.x > 0.0) == (lanes[bi] > 0.0) and absf(v.length() - Escalator.SPEED) < 0.001, "%s lane %d: the slab carries a rider %s at %.2f m/s" % [tag, bi, "down" if lanes[bi] > 0.0 else "up", v.length()])
			e.queue_free()
	# the sound is at the steps' pace (tools/audio/ambience.py STEPS_PER_S = speed / pitch; its 16 s loops hold 30 steps), and the path is rounded at its corners
	check(is_equal_approx(16.0 * Escalator.SPEED / Escalator.STEP_PITCH, 30.0), "the escalator sound loops hold a whole number of steps (16 s x %.3f steps/s)" % (Escalator.SPEED / Escalator.STEP_PITCH))
	# ... and the generator's own number is the same (read from the script that makes the loops: a changed speed or pitch without new audio fails here)
	var src := FileAccess.open("res://tools/audio/ambience.py", FileAccess.READ)
	var rate := NAN
	if src != null:
		for line in src.get_as_text().split("\n"):
			if line.begins_with("STEPS_PER_S ="):
				var parts := line.get_slice("#", 0).get_slice("=", 1).strip_edges().split("/")
				if parts.size() == 2:
					rate = float(parts[0]) / float(parts[1])
	check(not is_nan(rate) and absf(rate - Escalator.SPEED / Escalator.STEP_PITCH) < 1e-6, "tools/audio/ambience.py makes the escalator sound at the steps' pace (%.4f steps/s, the game's %.4f)" % [rate, Escalator.SPEED / Escalator.STEP_PITCH])
	check(Escalator.STEP_FILLET > 0.0 and Escalator.STEP_FILLET * tan(Escalator.ANGLE * 0.5) < 1.0, "the steps' track is rounded at its corners (radius %.1f m)" % Escalator.STEP_FILLET)
	# the shaders live on: a second escalator (after the first has gone) uses the very same Shader resources, which are not compiled again
	var e1 := Escalator.new()
	e1.build(6.0, [1.0, -1.0])
	var sh_steps: Shader = ((e1._steps_mesh() as ArrayMesh).surface_get_material(0) as ShaderMaterial).shader
	e1.free()
	var e2 := Escalator.new()
	e2.build(7.0, [1.0, -1.0])
	check(((e2._steps_mesh() as ArrayMesh).surface_get_material(0) as ShaderMaterial).shader == sh_steps and Escalator.shader("escalator_steps") == sh_steps, "the escalator shaders are kept between escalators (a fresh compile is 120 ms each)")
	e2.free()
	# fixed stairs have steps of their own
	var st := Escalator.new()
	st.build(5.0, [1.0, -1.0], "tile_white", true)
	add_child(st)
	check(st.get_node_or_null("Steps") == null and st.get_node_or_null("Handrails") == null, "fixed stairs have no moving steps or handrails")
	st.queue_free()
	print("OK" if ok else "FAILED")
