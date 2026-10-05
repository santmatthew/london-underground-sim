extends Node
## Screenshots at a generated Underground station drawn as a pair of side platforms (StationPlan.is_split): on platform A looking along it, across the tracks to platform B and the footbridge, and on the footbridge's deck.
## run: SHOT_ENGINE_ARGS="--fixed-fps 60" SHOT_TIMEOUT=600 tools/shot.sh res://tests/runner.tscn -- --test=split_shot_test --station="Buckhurst Hill" [--hour=10]
## output: build/split_<n>.png
var g: Game


func _snap(n: int) -> void:
	for i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/split_%d.png" % n)
	print("SNAP ", n, " player ", g.player.global_position)


func run():
	var nm := "Buckhurst Hill"
	var hour := 10.0
	var hide: PackedStringArray = []          # (debugging: node paths under the station to hide, "Module1/Shell")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): nm = a.substr(10)
		if a.begins_with("--hour="): hour = float(a.substr(7))
		if a.begins_with("--hide="): hide = a.substr(7).split(",")
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
	var st: Station = g.station
	for hp in hide:
		var hn := st.get_node_or_null(hp)
		print("hide ", hp, " found ", hn != null)
		if hn != null:
			hn.visible = false
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
			# 4: at the edge of platform A, looking across and down at the two tracks between the platforms
			g.player.global_position = Vector3(mp.x - sg * 20.0, mp.y + 0.2, mp.z + 1.4)
			g.player.face(Vector3(0.0, 0.0, 1.0))
			g.player._pitch = -0.75
			g.player.head.rotation.x = -0.75
			await _snap(4)
			var cam := get_viewport().get_camera_3d()
			for tz in [32.36, 33.91, 35.66, 37.41, 38.96]:
				print("screen of z ", tz, " bed point -> ", cam.unproject_position(Vector3(mp.x - sg * 20.0, mp.y + PlatformModule.BED_Y, tz)))
			# 6: at the edge of platform A, looking across the tracks at the front of platform B (a little below the horizon)
			g.player.global_position = Vector3(mp.x - sg * 20.0, mp.y + 0.2, mp.z + 4.2)
			g.player.face(Vector3(0.0, 0.0, 1.0))
			g.player._pitch = -0.2
			g.player.head.rotation.x = -0.2
			await _snap(6)
			# 7: at the edge of platform B, looking across the tracks at the front of platform A
			g.player.global_position = Vector3(mp.x - sg * 20.0, mp.y + 0.2, mp.z + 16.4 - 2.9)
			g.player.face(Vector3(0.0, 0.0, -1.0))
			g.player._pitch = -0.2
			g.player.head.rotation.x = -0.2
			await _snap(7)
			# 5: on the deck, in the middle, looking straight down at the tracks
			g.player.global_position = Vector3(xb, mp.y + 5.3, mp.z + 8.7)
			g.player.face(Vector3(1.0, 0.0, 0.0))
			g.player._pitch = -1.3
			g.player.head.rotation.x = -1.3
			await _snap(5)
			break
	print("done ", not fb.is_empty())
	get_tree().quit()
