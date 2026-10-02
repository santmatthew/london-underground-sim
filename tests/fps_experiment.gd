extends Node3D
## Frame-rate experiment: one rung of a ladder of progressively more complex scenes, run for `--secs` seconds (default 300) with a scripted walk through the station,
## logging every frame (FrameLog -> CSV). The camera follows the same ping-pong walk (hall -> platform and back at 1.6 m/s) at every rung so the rungs are comparable.
##   --level=0..5     0 empty scene (environment, camera, one floor)            1 architecture only (halls, escalators, landings, platforms, lights)
##                    2 + dressing (posters, props, benches, shops)             3 + signs (everything static)
##                    4 + trains and live clocks                                5 + crowd (Realistic density)
##   --station="Oxford Circus"  --secs=300  --out=res://build/fps/L5.csv  --vsync=0|1 (default 0: measure what the machine can do, not the 60 Hz cap)
##   --q=1 (graphics tier, as the game's default)  --scale=0 (Auto) | 1.0 | 0.67 ...   --fsr=1|2 (upscaler below 100 %)
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
	var vp := get_viewport()
	var sc := float(arg("scale", "0"))
	if sc <= 0.0:
		sc = Game.auto_scale(DisplayServer.window_get_size())
	var fsr2 := arg("fsr", "1") == "2"
	vp.use_taa = not (fsr2 and sc < 0.99)
	vp.scaling_3d_mode = (Viewport.SCALING_3D_MODE_FSR2 if fsr2 else Viewport.SCALING_3D_MODE_FSR) if sc < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = sc
	cam = Camera3D.new()
	cam.fov = 75
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	match level:
		0:
			_empty_scene()
		_:
			_station(sname)
	if level >= 5 and arg("warm", "1") == "1":
		await CrowdWarmup.run(self)
	log = FrameLog.new()
	add_child(log)
	log.on_done = func(_s): get_tree().quit()
	await get_tree().create_timer(1.0).timeout
	log.start(out, secs)
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
	print("EXPERIMENT level ", level, " station ", sname, " secs ", secs, " window ", get_window().size, " 3d scale ", vp.scaling_3d_scale, " mode ", vp.scaling_3d_mode, " vsync ", DisplayServer.window_get_vsync_mode())


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
