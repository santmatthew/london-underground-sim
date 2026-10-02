extends Node
var _done := false


func _build(st: Station, plan: StationPlan) -> void:
	await st.build_async(plan)
	_done = true


## How long are the uninterrupted stretches of work when a station is built asynchronously, cold (first station of the run) and again warm (caches filled)?
## Run with UG_ON=loadtime (it prints every stretch over 60 ms); args: --station=<name> --reps=2
func run():
	var name := "Oxford Circus"
	var reps := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="):
			name = a.substr(10)
		if a.begins_with("--reps="):
			reps = int(a.substr(7))
	if OS.get_cmdline_user_args().has("--preload"):
		StationProps.preload_async()
		await get_tree().create_timer(4.0).timeout
	var plan := StationPlan.for_station(Net.name_to_idx[name])
	for r in reps:
		print("--- build %d (%s) ---" % [r + 1, "cold" if r == 0 else "warm"])
		var st := Station.new()
		add_child(st)
		var t0 := Time.get_ticks_msec()
		var longest := 0
		var last := Time.get_ticks_usec()
		_done = false
		_build(st, plan)
		while not _done:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			longest = maxi(longest, (now - last) / 1000)
			last = now
		print("build %d: %d ms in total, longest single frame %d ms" % [r + 1, Time.get_ticks_msec() - t0, longest])
		st.queue_free()
		await get_tree().process_frame
