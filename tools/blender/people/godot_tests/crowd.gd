extends Node3D
# godot ... res://tests/crowd.tscn -- <n_people> <seconds> <outprefix> [lod:1|0] [shadows:1|0]
var lod: CrowdLod
func _ready():
	var a := OS.get_cmdline_user_args()
	var n := int(a[0]); var secs := float(a[1]); var outp: String = a[2]
	var use_lod := (a[3] == "1") if a.size() > 3 else true
	var shadows := (a[4] == "1") if a.size() > 4 else true
	var force_detail := int(a[5]) if a.size() > 5 else -1
	var nlights := int(a[6]) if a.size() > 6 else 14
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_setup_env(shadows, nlights)
	var rng := RandomNumberGenerator.new(); rng.seed = 12345
	lod = CrowdLod.new(); add_child(lod)
	var walkers: Array = []
	for i in n:
		var p := PersonModel.create(rng.randi() % PersonModel.count(), 1 + rng.randi() % 100000)
		add_child(p)
		var z := rng.randf_range(-3.6, 3.6)
		var x := rng.randf_range(-12.0, 60.0)
		p.position = Vector3(x, 0, z)
		p.rotation.y = rng.randf() * TAU
		var r := rng.randf()
		if r < 0.45:
			p.play(&"idle_stand_%d" % (1 + rng.randi() % 3), 0.0, rng.randf_range(0.9, 1.1))
		elif r < 0.55:
			p.play(&"idle_phone", 0.0)
		elif r < 0.62:
			p.play(&"stand_hold", 0.0)
		else:
			p.rotation.y = PI / 2 if rng.randf() < 0.5 else -PI / 2
			var spd := rng.randf_range(0.9, 1.9)
			p.set_locomotion_speed(spd)
			walkers.append([p, spd])
		if r >= 0.62:
			pass
		p.tick(rng.randf() * 3.0)
		if force_detail >= 0: p.set_detail(force_detail)
		elif use_lod: lod.register(p)
	set_meta("walkers", walkers)
	var cam := Camera3D.new(); add_child(cam); cam.fov = 70; cam.current = true
	cam.position = Vector3(-8, 1.65, 0.5); cam.look_at(Vector3(20, 1.4, 0))
	lod.camera = cam
	# timed run
	var times: Array = []
	var last := Time.get_ticks_usec()
	var t_end := last + int(secs * 1e6)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var cpu0 := 0.0; var f0 := 0
	var gpu_sum := 0.0; var cpu_sum := 0.0; var proc_sum := 0.0; var mcount := 0
	var shot_done := false
	var frame := 0
	var last_frame_t := Time.get_ticks_usec()
	while Time.get_ticks_usec() < t_end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if frame > 20:
			times.append((now - last) / 1000.0)
		last = now
		frame += 1
		if frame == 31:
			cpu0 = _cpu_ticks(); f0 = frame
		if frame > 30:
			gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(vp)
			proc_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			mcount += 1
		var dt := (now - last_frame_t) / 1e6
		last_frame_t = now
		for w in walkers:
			var p: PersonModel = w[0]
			p.position += -p.global_transform.basis.z * w[1] * dt
			if p.position.x > 62.0: p.position.x = -14.0
			elif p.position.x < -14.0: p.position.x = 62.0
		if not shot_done and frame == 60:
			shot_done = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(outp + ".png")
	times.sort()
	var sum := 0.0
	for t in times: sum += t
	var avg := sum / times.size()
	var info := "people=%d lod=%s shadows=%s frames=%d avg=%.2fms (%.0f fps) p50=%.2f p95=%.2f p99=%.2f max=%.2f" % [n, use_lod, shadows, times.size(), avg, 1000.0 / avg, times[times.size() / 2], times[int(times.size() * 0.95)], times[int(times.size() * 0.99)], times[-1]]
	info += " | draw_calls=%d objects=%d primitives=%d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]
	info += " | proc_cpu_per_frame=%.2fms" % ((_cpu_ticks() - cpu0) * 10.0 / maxf(frame - f0, 1))
	info += " | gpu=%.2fms render_cpu=%.2fms script+anim(process)=%.2fms" % [gpu_sum / maxi(mcount, 1), cpu_sum / maxi(mcount, 1), proc_sum / maxi(mcount, 1)]
	print("PERF ", info)
	get_tree().quit()

func _cpu_ticks() -> float:
	var fa := FileAccess.open("/proc/self/stat", FileAccess.READ)
	var st := fa.get_line()
	var parts := st.substr(st.rfind(")") + 2).split(" ")
	return float(parts[11]) + float(parts[12])   # utime + stime (clock ticks, 100 Hz)


func _setup_env(shadows: bool, nlights: int = 14):
	var env := Environment.new()
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.02, 0.02, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.35, 0.37, 0.4); env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var fl := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(120, 30); fl.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.07, 0.07, 0.075); fm.roughness = 0.4; fl.material_override = fm; fl.position.x = 20; add_child(fl)
	var wall := MeshInstance3D.new(); var wm := QuadMesh.new(); wm.size = Vector2(120, 4); wall.mesh = wm
	var wmat := StandardMaterial3D.new(); wmat.albedo_color = Color(0.85, 0.86, 0.84); wmat.roughness = 0.25; wall.material_override = wmat
	wall.position = Vector3(20, 2, -5); add_child(wall)
	for i in nlights:
		var sp := SpotLight3D.new(); sp.position = Vector3(-8 + i * 5.5, 3.6, 0.0); sp.rotation_degrees = Vector3(-90, 0, 0)
		sp.spot_range = 8.0; sp.spot_angle = 65.0; sp.light_color = Color(0.92, 0.96, 1.0); sp.light_energy = 6.0; sp.shadow_enabled = shadows; add_child(sp)
		var tube := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(1.2, 0.05, 0.12); tube.mesh = bm
		var em := StandardMaterial3D.new(); em.emission_enabled = true; em.emission = Color(1, 1, 0.95); em.emission_energy_multiplier = 6.0; tube.material_override = em
		tube.position = sp.position; add_child(tube)
