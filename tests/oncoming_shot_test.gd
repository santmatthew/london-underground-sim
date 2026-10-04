extends Node
## Rides one hop under a real renderer and takes screenshots from the player's eyes, turned toward the window on the second track's side, as a train comes the other way and passes (Oncoming).
## run: SHOT_ENGINE_ARGS="--fixed-fps 60" SHOT_TIMEOUT=900 tools/shot.sh res://tests/runner.tscn -- --test=oncoming_shot_test --start=Epping --dest="Theydon Bois" --hour=8.5 [--max=6]
## output: build/oncoming_<n>.png
var g: Game
var n := 0


func run():
	g = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {}
	add_child(g)
	await get_tree().process_frame
	var max_shots := 6
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] in ["start", "dest", "spot", "hour"]: g.cli[kv[0]] = kv[1]
		if a.begins_with("--seed="): g.cli["seed"] = a.substr(7)
		if a.begins_with("--max="): max_shots = int(a.substr(6))
	g.cli["autopilot"] = "1"
	g.start_journey()
	while g.state != Game.State.PLAYING:
		await get_tree().process_frame
	var frames := 0
	var marks := [100.0, 60.0, 30.0, 10.0, -12.0, -40.0]
	var next_mark := 0
	var done_at := -1
	while g.state == Game.State.PLAYING and frames < 60 * 60 * 40 and n < max_shots:
		await get_tree().physics_frame
		frames += 1
		if g.riding and g.ride != null and g.ride.oncoming != null and g.ride.phase == Ride.Phase.TUNNEL:
			var r: Ride = g.ride
			var onc: Oncoming = r.oncoming
			var s_p := r.s_now + float(r.train.car_x[r.ref_car])
			for e in onc.entries:
				var tr := e["train"] as Train
				if e["skip"] or tr == null or not tr.visible:
					continue
				var rel := onc.s_of(e, Clock.now) - s_p
				if next_mark < marks.size() and rel < marks[next_mark] and rel > marks[next_mark] - 25.0:
					# look at the middle of the train from the player's eyes
					var target: Vector3 = tr.global_position
					var d := target - g.player.global_position
					d.y = 0.0
					g.player.face(d.normalized())
					await get_tree().process_frame
					await get_tree().process_frame
					n += 1
					var path := "res://build/oncoming_%02d.png" % n
					get_viewport().get_texture().get_image().save_png(path)
					print("SNAP ", path, " train at ", snappedf(rel, 1.0), " m, s_p ", snappedf(s_p, 1.0), " of ", snappedf(r.dist, 1.0))
					next_mark += 1
					break
		elif n > 0 and not g.riding:
			if done_at < 0:
				done_at = frames
			if frames - done_at > 120:
				break
	print("done ", n)
	get_tree().quit()
