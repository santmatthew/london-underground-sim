extends Node3D
## Render cost of a ride's scenery, controlled: a camera moves along the path of one hop at train speed through TunnelRun's cells (and the trains of the second track, Oncoming), looking out of the window
## on the platform side, every frame logged (FrameLog). A/B with UG_OFF=pair (no second track), UG_OFF=oncoming (no trains on it).
## args: --a="Epping" --b="Theydon Bois" --line=central --hour=8.5 --secs=45 --speed=22 --s0=300 --yaw=65 --out=res://build/fps/ride.csv --meet=12 (a train meets the camera this many seconds in)
## run (on a REAL display): godot --path . --resolution 1920x1080 --windowed res://tests/ride_perf_test.tscn -- --secs=45
var log: FrameLog
var path: TrackPath
var tun: TunnelRun
var onc: Oncoming
var cam: Camera3D
var s := 0.0
var v := 22.0
var yaw := 65.0
var t_base := 0.0
var elapsed := 0.0
var secs := 45.0


func arg(name: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return d


func _ready() -> void:
	var na := arg("a", "Epping")
	var nb := arg("b", "Theydon Bois")
	var line := arg("line", "central")
	secs = float(arg("secs", "45"))
	v = float(arg("speed", "22"))
	s = float(arg("s0", "300"))
	yaw = float(arg("yaw", "65"))
	var meet := float(arg("meet", "12"))
	var out := arg("out", "res://build/fps/ride.csv")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Timetable.build(1)
	var t0 := float(arg("hour", "8.5")) * 3600.0
	Clock.set_time(t0)
	var we := Env.make(1)
	add_child(we)
	RenderSettings.apply(we.environment, get_viewport(), {"quality": 1, "scale": 0.0, "upscaler": "fsr1", "aa": "taa"}, DisplayServer.window_get_size())
	for k in Train.CAR_SCENES:
		Train.scene_for(k)          # (the game loads the car models at start-up: Train.preload_async; a train built later must not pay for it)
	var ia: int = Net.name_to_idx[na]
	var ib: int = Net.name_to_idx[nb]
	var ida: String = Net.station_ids[ia]
	var idb: String = Net.station_ids[ib]
	var prof: Array = TrackPath.profile(ida, idb)
	var dist: float = float(prof[0]) if not prof.is_empty() else 2000.0
	var ss: bool = String(Net.lines[line]["group"]) == "ss"
	path = TrackPath.between(ida, idb, dist, 150.0, 150.0, [], [], [], [], ss, 0.0, 0.0, line)
	tun = TunnelRun.new()
	add_child(tun)
	tun.setup(path, false, s)
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.far = 400.0
	add_child(cam)
	if not Station.debug_off("oncoming"):
		onc = Oncoming.new()
		add_child(onc)
		onc.setup(path, false, ia, ib, t0, t0 + 1800.0, dist, line)
		# a train meets the camera `meet` seconds in
		var e: Dictionary = {}
		for e2 in onc.entries:
			e = e2
			break
		if not e.is_empty():
			var lo: float = e["info"]["dep"]
			var hi: float = lo + float(e["T"])
			var want := s + v * meet
			for _i in 40:
				var mid := (lo + hi) * 0.5
				if onc.s_of(e, mid) > want:
					lo = mid
				else:
					hi = mid
			t_base = (lo + hi) * 0.5 - meet
			print("RIDEPERF train of run ", e["info"]["run"], " meets the camera at s=", snappedf(want, 1.0), " (", Clock.fmt(t_base + meet, true), "), ", onc.entries.size(), " trains in 30 min")
	if t_base == 0.0:
		t_base = t0
	log = FrameLog.new()
	add_child(log)
	log.on_done = func(_sm): get_tree().quit()
	log.start(out, secs)
	print("RIDEPERF ", na, " -> ", nb, " ", snappedf(dist, 1.0), " m; UG_OFF=", OS.get_environment("UG_OFF"))


func _process(delta: float) -> void:
	elapsed += delta
	s += v * delta
	Clock.now = t_base + elapsed
	tun.place(s)
	var pose := path.pose(s)
	var up := Vector3(0.0, 1.5, 0.0)
	cam.global_transform = Transform3D(pose.basis, pose.origin + pose.basis * up)
	cam.rotate_object_local(Vector3.UP, deg_to_rad(yaw - 90.0))          # (the path's basis has the camera looking out to the left, the platform side: turned toward the way the train goes by 90 - yaw degrees)
	if onc != null:
		onc.update(s, Clock.now, Transform3D.IDENTITY, v)
	if log != null and s > path.length - 250.0:
		log.mark("end_of_path")
		s = 300.0
