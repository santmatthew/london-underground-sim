extends Node
## Rides one hop under a real renderer and saves screenshots of the scenery on the way (RunScenery: daylight, cuttings, viaducts, tunnel mouths).
## run: SHOT_ENGINE_ARGS="--fixed-fps 60" SHOT_TIMEOUT=600 tools/shot.sh res://tests/runner.tscn -- --test=ride_shot_test --start=Amersham --dest="Chalfont & Latimer" [--hour=12] [--every=10] [--max=12]
## output: build/ride_<n>_<phase>_<seconds>.png
var g: Game
var n := 0


func run():
	g = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {}
	add_child(g)
	await get_tree().process_frame
	var every := 10.0
	var max_shots := 12
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] in ["start", "dest", "spot", "hour"]: g.cli[kv[0]] = kv[1]
		if a.begins_with("--seed="): g.cli["seed"] = a.substr(7)
		if a.begins_with("--every="): every = float(a.substr(8))
		if a.begins_with("--max="): max_shots = int(a.substr(6))
	g.cli["autopilot"] = "1"
	g.start_journey()
	while g.state != Game.State.PLAYING:
		await get_tree().process_frame
	var frames := 0
	var last_t := -100.0
	var done_at := -1
	while g.state == Game.State.PLAYING and frames < 60 * 60 * 40 and n < max_shots:
		await get_tree().physics_frame
		frames += 1
		if g.riding and g.ride != null:
			var r: Ride = g.ride
			var tau := Clock.now - r.t_dep
			if tau - last_t >= every or (last_t < -50.0 and tau > 3.0):
				last_t = tau
				n += 1
				var ph: String = ["depart", "tunnel", "arrive", "done"][r.phase]
				var path := "res://build/ride_%02d_%s_%03d.png" % [n, ph, int(tau)]
				get_viewport().get_texture().get_image().save_png(path)
				print("SNAP ", path, " s=", snappedf(r.s_now, 1.0), " of ", snappedf(r.dist, 1.0))
		elif last_t > -50.0 and not g.riding:
			if done_at < 0:
				done_at = frames
			if frames - done_at > 120:
				break
	print("done ", n)
	get_tree().quit()
