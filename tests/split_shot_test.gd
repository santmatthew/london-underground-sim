extends Node
## Screenshots at a generated Underground station drawn as a pair of side platforms (StationPlan.is_split): on platform A looking along it, across the tracks to platform B and the footbridge, and on the footbridge's deck.
## run: SHOT_ENGINE_ARGS="--fixed-fps 60" SHOT_TIMEOUT=600 tools/shot.sh res://tests/runner.tscn -- --test=split_shot_test --station="Buckhurst Hill"
## output: build/split_<n>.png
var g: Game


func _snap(n: int) -> void:
	for i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/split_%d.png" % n)
	print("SNAP ", n, " player ", g.player.global_position)


func run():
	var nm := "Buckhurst Hill"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): nm = a.substr(10)
	g = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {"seed": "5"}
	add_child(g)
	for i in 8:
		await get_tree().process_frame
	g.start_explore({"station": Net.name_to_idx[nm], "spot": 0, "hour": 10.0, "day": "weekday"})
	var t0 := Time.get_ticks_msec()
	while g.state != Game.State.PLAYING and Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
	var plan := StationPlan.for_station(Net.name_to_idx[nm])
	var st: Station = g.station
	var fb: Dictionary = {}
	for m in plan.modules:
		if (m["spec"] as Dictionary).has("footbridges") and not (m["spec"]["footbridges"] as Array).is_empty():
			fb = m["spec"]["footbridges"][0]
			var mp: Vector3 = m["pos"]
			var xb := mp.x + float(fb["x"])
			var sg := signf(float(fb["x"]))          # (the bridge lies toward this end of the platforms)
			# 1: on platform A, 35 m from the bridge, looking along the platform toward it
			g.player.global_position = Vector3(xb - sg * 35.0, mp.y + 0.2, mp.z + 1.4)
			g.player.face(Vector3(sg, 0.0, 0.0))
			await _snap(1)
			# 2: on the deck, in the middle, looking across
			g.player.global_position = Vector3(xb, mp.y + 5.3, mp.z + 8.7)
			g.player.face(Vector3(0.0, 0.0, 1.0))
			await _snap(2)
			# 3: platform B, looking back along it from the far end of the platforms (away from the bridge), the bridge at the end of the view
			g.player.global_position = Vector3(mp.x - sg * 55.0, mp.y + 0.2, mp.z + 17.8)
			g.player.face(Vector3(sg, 0.0, 0.0))
			await _snap(3)
			break
	print("done ", not fb.is_empty())
	get_tree().quit()
