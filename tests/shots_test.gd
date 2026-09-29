extends Node
## Plays a whole journey with the autopilot under a real (xvfb) renderer and saves screenshots at the interesting moments.
## run: SHOT_ENGINE_ARGS="--fixed-fps 60" SHOT_TIMEOUT=900 tools/shot.sh res://tests/runner.tscn -- --test=shots_test --seed=1 [--start=.. --dest=.. --spot=.. --hour=..]
## output: build/tour_<n>_<label>.png
var g: Game
var n := 0
var _last_snap := -100.0
var _seen := {}


func snap(label: String, once := true, min_gap := 4.0) -> void:
	var key := label
	if once and _seen.has(key):
		return
	if Clock.now - _last_snap < min_gap and not (Clock.now < _last_snap):
		return
	_seen[key] = true
	_last_snap = Clock.now
	n += 1
	var path := "res://build/tour_%02d_%s.png" % [n, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("SNAP ", path, " clock ", Clock.fmt(Clock.now, true))


func run():
	g = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {}
	add_child(g)
	await get_tree().process_frame
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="): g.opts["time"] = a.substr(7)
		if a.begins_with("--length="): g.opts["length"] = a.substr(9)
		if a.begins_with("--seed="): g.cli["seed"] = a.substr(7)
		var kv: PackedStringArray = a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] in ["start", "dest", "spot", "hour"]: g.cli[kv[0]] = kv[1]
	g.cli["autopilot"] = "1"
	g.start_journey()
	while g.state != Game.State.BRIEFING:
		await get_tree().process_frame
	for i in 20: await get_tree().process_frame
	snap("briefing")
	while g.state != Game.State.PLAYING:
		await get_tree().process_frame
	for i in 90: await get_tree().physics_frame
	snap("start")
	var frames := 0
	var y_prev := g.player.global_position.y
	var esc_shots := 0
	var t_mode := 0.0
	var last_mode := ""
	var alighted_shot := false
	while g.state == Game.State.PLAYING and frames < 60 * 60 * 40:
		await get_tree().physics_frame
		frames += 1
		var ap := g.autopilot
		if ap == null:
			continue
		if ap.mode != last_mode:
			last_mode = ap.mode
			t_mode = 0.0
		t_mode += 1.0 / 60.0
		if frames % 20 == 0:
			var y := g.player.global_position.y
			if absf(y - y_prev) > 0.35 and g.station != null and not g.riding and esc_shots < 2:
				esc_shots += 1
				snap("escalator_%d" % esc_shots, true, 0.0)
			y_prev = y
		match ap.mode:
			"wait_train":
				if t_mode > 6.0 and g.station != null:
					snap("platform_waiting")
				if g.station != null and ap.target_face != "":
					var vkey := "%d:%d" % [ap.target_run, ap.legs[ap.leg_i]["k"]] if ap.leg_i < ap.legs.size() else ""
					if vkey != "" and g.station.trains.visits.has(vkey):
						var v: Dictionary = g.station.trains.visits[vkey]
						if v["doors"] and t_mode > 0.5:
							snap("train_doors_open")
			"in_train":
				if g.riding and g.ride != null and g.ride.phase == Ride.Phase.TUNNEL and Clock.now - g.ride.t_dep > 20.0:
					snap("riding_tunnel", true, 0.0)
				elif not g.riding and t_mode > 1.0:
					snap("in_train_stopped_%s" % str(g.station.plan.idx if g.station else 0), false, 20.0)
			"alight":
				if not alighted_shot and t_mode > 1.5:
					alighted_shot = true
					snap("alighting", true, 0.0)
			"walk":
				if t_mode > 20.0 and int(t_mode) % 25 == 0 and g.station != null and not g.riding:
					snap("walking_%d" % int(t_mode), false, 15.0)
			"exit":
				if t_mode > 4.0:
					snap("exit_walk", true, 0.0)
	print("done state ", g.state, " frames ", frames, " shots ", n)
