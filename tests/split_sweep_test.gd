extends Node
## Four screenshots at a generated station that is drawn as a pair of side platforms (StationPlan.is_split), from the middle of the first platform along it both ways and across the tracks, and from the second
## platform across at the first: what the audits cannot see (a face that is culled, a canopy that is cut wrong, furniture on one platform only, a sign that faces nowhere).
## run: SHOT_ENGINE_ARGS="--fixed-fps 60" SHOT_TIMEOUT=600 tools/shot.sh res://tests/runner.tscn -- --test=split_sweep_test --station="Ickenham" [--hour=10]
## output: build/sweep_<station>_<n>.png  (tools/sweep_montage.py joins them)
var g: Game
var tag := ""


func _snap(n: int, pitch := 0.0) -> void:
	g.player._pitch = pitch
	g.player.head.rotation.x = pitch
	for i in 14:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/sweep_%s_%d.png" % [tag, n])


func run():
	var nm := "Ickenham"
	var hour := 10.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): nm = a.substr(10)
		if a.begins_with("--hour="): hour = float(a.substr(7))
	tag = nm.replace(" ", "_").replace("&", "and").replace("'", "")
	g = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {"seed": "5"}
	add_child(g)
	for i in 8:
		await get_tree().process_frame
	g.start_explore({"station": Net.name_to_idx[nm], "spot": 0, "hour": hour, "day": "weekday"})
	var t0 := Time.get_ticks_msec()
	while g.state != Game.State.PLAYING and Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
	var plan := StationPlan.for_station(Net.name_to_idx[nm])
	var pair: Array = []
	for m in plan.modules:
		if bool((m["spec"] as Dictionary).get("split", false)):
			pair.append(m)
	if pair.size() != 2:
		print("not a pair: ", nm)
		get_tree().quit()
		return
	var pa: Vector3 = pair[0]["pos"]
	var pb: Vector3 = pair[1]["pos"]
	var mx := (pa.x + pb.x) * 0.5
	g.player.global_position = Vector3(pa.x, pa.y + 0.2, pa.z + 1.4)
	g.player.face(Vector3(1, 0, 0))
	await _snap(1)
	g.player.global_position = Vector3(pa.x, pa.y + 0.2, pa.z + 1.4)
	g.player.face(Vector3(-1, 0, 0))
	await _snap(2)
	g.player.global_position = Vector3(mx - 20.0, pa.y + 0.2, pa.z + 3.2)
	g.player.face(Vector3(0, 0, 1))
	await _snap(3, -0.2)
	g.player.global_position = Vector3(mx - 20.0, pb.y + 0.2, pb.z - 3.2)
	g.player.face(Vector3(0, 0, -1))
	await _snap(4, -0.2)
	print("SWEEP done ", nm)
	get_tree().quit()
