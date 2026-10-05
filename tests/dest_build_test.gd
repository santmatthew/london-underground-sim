extends Node3D
## The frame times while a station is built in the background, as the ride does for its destination (Ride._build_destination): one station is built first (the origin, warm), then the other with
## `build_async` while the frames are timed. Prints the frames over 33 ms and the longest stretches. args: --warm="Epping" --dest="Theydon Bois" [--runs=2]
## run (real display): godot --path . --resolution 1920x1080 --windowed res://tests/dest_build_test.tscn -- --dest="Theydon Bois"
var frames: Array = []
var timing := false


func arg(name: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return d


func _process(delta: float) -> void:
	if timing:
		frames.append(delta * 1000.0)
		if arg("trace", "0") == "1" and delta > 0.02:
			print("FRAME %d: %.0f ms" % [frames.size(), delta * 1000.0])


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Timetable.build(1)
	Clock.set_time(8.5 * 3600.0)
	var we := Env.make(1)
	add_child(we)
	for k in Train.CAR_SCENES:
		Train.scene_for(k)
	Mats.preload_common()          # (the game does both at start-up (Game._preload): without them a destination's first escalator costs 200 - 500 ms)
	Escalator.warm_up()
	var cam := Camera3D.new()
	cam.far = 400.0
	add_child(cam)
	if arg("props", "0") == "1":
		StationProps.preload_async()          # (the game does it behind the menu: the prop models load on worker threads)
		await get_tree().create_timer(4.0).timeout
	var pre := arg("prewarm", "")
	if pre != "":
		# a throwaway station built the way a destination is (8 ms slices) and freed: what a start-up warm-up would do
		var pws := Station.new()
		add_child(pws)
		pws.global_position = Vector3(0.0, -5000.0, 0.0)
		pws.slice_us = 8000
		var tw := Time.get_ticks_usec()
		await pws.build_async(StationPlan.for_station(Net.name_to_idx[pre]))
		print("DESTBUILD prewarm %s: %.0f ms" % [pre, float(Time.get_ticks_usec() - tw) / 1000.0])
		pws.queue_free()
		for _i in 10:
			await get_tree().process_frame
	var warm := Station.new()
	add_child(warm)
	var pw := StationPlan.for_station(Net.name_to_idx[arg("warm", "Epping")])
	warm.build(pw)
	for _i in 20:
		await get_tree().process_frame
	for run in int(arg("runs", "2")):
		var pd := StationPlan.for_station(Net.name_to_idx[arg("dest", "Theydon Bois")])
		var dest := Station.new()
		add_child(dest)
		dest.global_position = Vector3(0.0, -5000.0, 0.0)
		dest.slice_us = int(arg("slice", "25000"))
		frames.clear()
		timing = true
		var t0 := Time.get_ticks_usec()
		await dest.build_async(pd)
		var total := float(Time.get_ticks_usec() - t0) / 1000.0
		print("DESTBUILD phases (ms, wall clock incl. the frames given back): %s" % str(dest.prof))
		# what Ride._build_destination does next
		var dummy := Node3D.new()
		add_child(dummy)
		var t1 := Time.get_ticks_usec()
		dest.trains.setup(dest, dummy)
		dest.trains.paused = true
		var t2 := Time.get_ticks_usec()
		await dest.attach_crowd(dummy, true)          # (as Ride._build_destination does)
		print("DESTBUILD trains.setup: %.1f ms, attach_crowd: %.1f ms" % [float(t2 - t1) / 1000.0, float(Time.get_ticks_usec() - t2) / 1000.0])
		for _i in 30:
			await get_tree().process_frame
		timing = false
		var worst := frames.duplicate()
		worst.sort()
		worst.reverse()
		var over := 0
		for f in frames:
			if f > 33.0:
				over += 1
		print("DESTBUILD run %d %s: %d frames over %.0f ms, %d of them over 33 ms; worst %s ms" % [run, pd.name, frames.size(), total, over, str(worst.slice(0, 8).map(func(x): return snappedf(x, 1.0)))])
		dest.queue_free()
		for _i in 10:
			await get_tree().process_frame
	get_tree().quit()
