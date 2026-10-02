extends Node3D
## Frame-rate experiment: one rung of a ladder of progressively more complex scenes, run for `--secs` seconds (default 300) with a scripted walk through the station,
## logging every frame (FrameLog -> CSV). The camera follows the same ping-pong walk (hall -> platform and back at 1.6 m/s) at every rung so the rungs are comparable.
##   --level=0..5     0 empty scene (environment, camera, one floor)            1 architecture only (halls, escalators, landings, platforms, lights)
##                    2 + dressing (posters, props, benches, shops)             3 + signs (everything static)
##                    4 + trains and live clocks                                5 + crowd (Realistic density)
##   --station="Oxford Circus"  --secs=300  --out=res://build/fps/L5.csv  --vsync=0|1 (default 0: measure what the machine can do, not the 60 Hz cap)
##   --q=1 (graphics tier, as the game's default)  --scale=0 (Auto) | 1.0 | 0.67 ...   --fsr=1|2 (upscaler below 100 %)
##   --vp=3840x2160   render everything in an off-screen SubViewport of that size (a 4K target on any display; GPU time is the SubViewport's); then --scale/--fsr apply to it
##   --env=glow_enabled=false,ssao_enabled=false  set Environment properties; --vpset=use_taa=false,msaa_3d=0  set viewport properties (values as GDScript literals)
## Run:  godot --path . --resolution 1920x1080 res://tests/fps_experiment.tscn -- --level=3     (tools/fps_experiment.sh runs the whole ladder with a system sampler)
const SPEED := 1.6
var level := 3
var plan: StationPlan
var st: Station
var cam: Camera3D
var route: Array = []         # Vector3 points (station local), walked back and forth
var seg := 0
var seg_t := 0.0
var dirn := 1
var log: FrameLog
var sv: SubViewport
var game_opts := {}


func arg(name: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return d


func _ready() -> void:
	level = int(arg("level", "3"))
	var sname := arg("station", "Oxford Circus")
	var secs := float(arg("secs", "300"))
	var out := arg("out", "res://build/fps/L%d.csv" % level)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if arg("vsync", "0") == "1" else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Timetable.build(1)
	Clock.set_time(8.25 * 3600.0)
	var we := Env.make(int(arg("q", "1")))
	add_child(we)
	# the same render settings as the game (Game._apply_settings)
	var vp: Viewport = get_viewport()
	var vps := arg("vp", "")
	if vps != "":
		var wh := vps.split("x")
		sv = SubViewport.new()
		sv.size = Vector2i(int(wh[0]), int(wh[1]))
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(sv)
		vp = sv
	game_opts = {"quality": int(arg("q", "1")), "scale": float(arg("scale", "0")), "upscaler": "fsr2" if arg("fsr", "1") == "2" else "fsr1", "aa": arg("aa", "taa")}
	RenderSettings.apply(we.environment, vp, game_opts, sv.size if sv != null else DisplayServer.window_get_size())
	cam = Camera3D.new()
	cam.fov = 75
	cam.far = 400.0
	(sv if sv != null else self).add_child(cam)
	cam.make_current()
	# global renderer settings: --rs=ssao_quality:1:true:0.5:2,glow_bicubic:0  (ssao_quality:<0 very low..4 ultra>:<half size>:<adaptive target>:<blur passes>)
	for kv in arg("rs", "").split(",", false):
		var q := kv.split(":")
		match q[0]:
			"ssao_quality":
				RenderingServer.environment_set_ssao_quality(int(q[1]), q[2] == "true", float(q[3]), int(q[4]), 50.0, 300.0)
			"glow_bicubic":
				RenderingServer.environment_glow_set_use_bicubic_upscale(q[1] == "1")
	# property overrides for ablations
	for kv in arg("env", "").split(",", false):
		var p := kv.split("=")
		we.environment.set(p[0], str_to_var(p[1]))
	for kv in arg("vpset", "").split(",", false):
		var p2 := kv.split("=")
		vp.set(p2[0], str_to_var(p2[1]))
	match level:
		0:
			_empty_scene()
		_:
			_station(sname)
	if level >= 4 and arg("warm", "1") == "1":
		Train.preload_async()
	if level >= 5 and arg("warm", "1") == "1":
		await CrowdWarmup.run(self)
	log = FrameLog.new()
	add_child(log)
	log.on_done = func(_s): get_tree().quit()
	if arg("adaptive", "0") == "1":
		var ad := AdaptiveScale.new()
		add_child(ad)
		ad.changed.connect(func(s):
			game_opts["_auto_now"] = s
			RenderSettings.apply(we.environment, sv if sv != null else get_viewport(), game_opts, sv.size if sv != null else DisplayServer.window_get_size())
			print("ADAPT t=%.0f s  render scale -> %.2f" % [(Time.get_ticks_usec() - log._t0_us) / 1e6 if log.running else 0.0, s]))
		ad.start(sv if sv != null else get_viewport(), RenderSettings.auto_scale(sv.size if sv != null else DisplayServer.window_get_size()))
		game_opts["_auto_now"] = ad.scale
	if arg("cycle", "") != "":
		await _cycle(arg("cycle", ""), sv if sv != null else get_viewport(), we.environment)
		get_tree().quit()
		return
	await get_tree().create_timer(4.0 if level >= 4 else 1.0).timeout          # (4 s: the background loading of the car models, as behind the menu)
	log.start(out, secs, sv.get_viewport_rid() if sv != null else RID())
	await get_tree().create_timer(4.0).timeout
	var mons := {}
	for k in ["TIME_FPS", "TIME_PROCESS", "TIME_PHYSICS_PROCESS", "TIME_NAVIGATION_PROCESS", "OBJECT_COUNT", "OBJECT_NODE_COUNT", "OBJECT_RESOURCE_COUNT", "PHYSICS_3D_ACTIVE_OBJECTS", "PHYSICS_3D_COLLISION_PAIRS", "PHYSICS_3D_ISLAND_COUNT", "RENDER_TOTAL_OBJECTS_IN_FRAME", "RENDER_TOTAL_DRAW_CALLS_IN_FRAME", "NAVIGATION_ACTIVE_MAPS", "AUDIO_OUTPUT_LATENCY"]:
		mons[k] = Performance.get_monitor(Performance.get(k))
	print("MONITORS ", mons)
	# which nodes have per-frame callbacks switched on, by class / script
	var proc := {}
	var phys := {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var key := n.get_class() + ((" " + String(n.get_script().resource_path.get_file())) if n.get_script() != null else "")
		if n.is_processing():
			proc[key] = int(proc.get(key, 0)) + 1
		if n.is_physics_processing():
			phys[key] = int(phys.get(key, 0)) + 1
	print("PROCESSING ", proc)
	print("PHYSICS_PROCESSING ", phys)
	print("EXPERIMENT vp ", (sv.size if sv != null else get_viewport().size), " level ", level, " station ", sname, " secs ", secs, " window ", get_window().size, " 3d scale ", vp.scaling_3d_scale, " mode ", vp.scaling_3d_mode, " vsync ", DisplayServer.window_get_vsync_mode())


## --cycle=<json file>: {"base": {...}, "slice": 4, "rounds": 3, "configs": [{"label": "...", "env": {...}, "vp": {...}, "rs": ["ssao_quality:1:true:0.5:2"]}]}
## Runs the configs in rotation inside this one process (each `slice` seconds, `rounds` times over) and prints the median GPU time per config: the GPU's clock drifts with
## temperature, so configs measured one after another in separate runs are not comparable, rotated ones are.
func _cycle(path: String, vp: Viewport, env: Environment) -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var slice_s := float(cfg.get("slice", 4.0))
	var rounds := int(cfg.get("rounds", 3))
	var res := {}
	var rid := vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await get_tree().create_timer(float(cfg.get("warm", 2.0))).timeout           # (a long warm-up brings the GPU to its throttled steady clock before anything is measured)
	var shuffler := RandomNumberGenerator.new()
	shuffler.seed = 7
	for r in rounds:
		var order: Array = (cfg["configs"] as Array).duplicate()
		for i in range(order.size() - 1, 0, -1):          # a different seeded order every round, so no config always follows the same neighbour
			var j := shuffler.randi() % (i + 1)
			var tmp = order[i]
			order[i] = order[j]
			order[j] = tmp
		for c in order:
			var all: Dictionary = (cfg.get("base", {}) as Dictionary).duplicate(true)
			for k in ["env", "vp", "rs"]:
				if c.has(k):
					if not all.has(k):
						all[k] = {} if k != "rs" else []
					if k == "rs":
						all[k] = c[k]
					else:
						for kk in c[k]:
							all[k][kk] = c[k][kk]
			if c.has("lights"):
				var stack: Array = [get_tree().root]
				while not stack.is_empty():
					var n: Node = stack.pop_back()
					for ch in n.get_children():
						stack.append(ch)
					if n is OmniLight3D or n is SpotLight3D or n is DirectionalLight3D:
						(n as Light3D).visible = bool(c["lights"])
			if c.has("light_fade"):
				var stack3: Array = [get_tree().root]
				var nl := 0
				while not stack3.is_empty():
					var n3: Node = stack3.pop_back()
					for ch3 in n3.get_children():
						stack3.append(ch3)
					if n3 is OmniLight3D:
						var o3 := n3 as OmniLight3D
						o3.visible = true
						o3.distance_fade_enabled = true
						o3.distance_fade_begin = float(c["light_fade"][0])
						o3.distance_fade_length = float(c["light_fade"][1])
						nl += 1
				print("LIGHTS ", nl)
			if c.has("light_range"):
				var stack2: Array = [get_tree().root]
				while not stack2.is_empty():
					var n2: Node = stack2.pop_back()
					for ch2 in n2.get_children():
						stack2.append(ch2)
					if n2 is OmniLight3D:
						var o := n2 as OmniLight3D
						if not o.has_meta("range0"):
							o.set_meta("range0", o.omni_range)
						o.omni_range = float(o.get_meta("range0")) * float(c["light_range"])
						o.visible = true
			if c.has("game"):
				var go := game_opts.duplicate()
				for gk in c["game"]:
					go[gk] = c["game"][gk]
				RenderSettings.apply(env, vp, go, sv.size if sv != null else DisplayServer.window_get_size())
			for k in all.get("env", {}):
				env.set(k, all["env"][k])
			for k in all.get("vp", {}):
				vp.set(k, all["vp"][k])
			for kv in all.get("rs", []):
				var q: PackedStringArray = String(kv).split(":")
				match q[0]:
					"ssao_quality": RenderingServer.environment_set_ssao_quality(int(q[1]), q[2] == "true", float(q[3]), int(q[4]), 50.0, 300.0)
					"glow_bicubic": RenderingServer.environment_glow_set_use_bicubic_upscale(q[1] == "1")
			await get_tree().create_timer(0.7).timeout           # settle (pipelines, TAA history)
			var samples := PackedFloat32Array()
			var t_end := Time.get_ticks_msec() + int(slice_s * 1000.0)
			while Time.get_ticks_msec() < t_end:
				await get_tree().process_frame
				samples.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			samples.sort()
			var label: String = c["label"]
			if not res.has(label):
				res[label] = []
			res[label].append(samples[samples.size() / 2])
	for label in res:
		var v: Array = res[label]
		v.sort()
		print("CYCLE %-60s GPU ms median %.2f   (rounds: %s)" % [label, v[v.size() / 2], ", ".join(v.map(func(x): return "%.2f" % x))])


func _empty_scene() -> void:
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.5, 0.52)
	floor_mi.material_override = m
	add_child(floor_mi)
	var l := OmniLight3D.new()
	l.position = Vector3(0, 4, 0)
	l.omni_range = 30
	add_child(l)
	route = [Vector3(-8, 1.65, -8), Vector3(8, 1.65, 8)]


func _station(sname: String) -> void:
	# what is switched off at each rung (Station.debug_off reads UG_OFF while the station is built)
	var off := ""
	match level:
		1: off = "dressing,signs,decals,labels,posters,furniture"
		2: off = "signs"
	var extra := arg("off", "")          # more things to switch off for ablations, e.g. --off=occlusion,decals
	if extra != "":
		off = extra if off == "" else off + "," + extra
	OS.set_environment("UG_OFF", off)
	var idx: int = Net.name_to_idx[sname]
	plan = StationPlan.for_station(idx)
	st = Station.new()
	add_child(st)
	st.build(plan)
	# the walk: ticket hall -> first platform face and back
	var fk: String = plan.faces.keys()[0]
	var names: Array = plan.path("hall_unpaid", "face:" + fk)
	for n in names:
		var p: Vector3 = plan.nodes[plan.node_idx[n]]["pos"]
		route.append(p + Vector3(0, 1.65, 0))
	if route.size() < 2:
		route = [Vector3(0, 1.65, -5), Vector3(0, 1.65, 5)]
	var player := Player.new()
	add_child(player)
	player.enabled = false
	player.global_position = route[0]
	if level >= 4:
		st.trains.setup(st, player)
		Clock.running = true
	if level >= 5:
		st.attach_crowd(player)


var _last_nodes := 0
var _hitch_log := false


func _process(delta: float) -> void:
	if OS.has_environment("UG_HITCH"):
		var nc := get_tree().get_node_count()
		if delta > 0.1 and log != null and log.running:
			print("HITCH t=%.1f frame=%.0f ms  nodes %d (%+d)  crowd %s" % [log.frames() * 0.0 + (Time.get_ticks_usec() - log._t0_us) / 1e6, delta * 1000.0, nc, nc - _last_nodes, str(st.crowd.stats) if (st != null and st.crowd != null) else "-"])
		_last_nodes = nc
	if route.size() < 2:
		return
	# walk the polyline back and forth
	var a: Vector3 = route[seg]
	var b: Vector3 = route[seg + dirn]
	var len := maxf(a.distance_to(b), 0.01)
	seg_t += SPEED * delta / len
	while seg_t >= 1.0:
		seg_t -= 1.0
		seg += dirn
		if seg + dirn < 0 or seg + dirn >= route.size():
			dirn = -dirn
			seg += dirn
			# seg now indexes the other end; the next target is seg + dirn
			seg = clampi(seg, 0, route.size() - 1)
		a = route[seg]
		b = route[clampi(seg + dirn, 0, route.size() - 1)]
		len = maxf(a.distance_to(b), 0.01)
	var p := a.lerp(b, seg_t)
	var fwd := (b - a)
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, 1)
	cam.global_position = (st.global_transform * p) if st != null else p
	var look := cam.global_position + (st.global_transform.basis * fwd.normalized() if st != null else fwd.normalized()) * 4.0
	look.y = cam.global_position.y - 0.15
	cam.look_at(look)
	# keep the crowd and trains around the camera (they follow the "player")
	if level >= 4 and st != null:
		for n in get_children():
			if n is Player:
				n.global_position = cam.global_position
