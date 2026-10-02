extends Node
## The closing warning of a train's doors: for a train at the platform the player waits on, the order is doors opened, the beeps (once, door_chime_close heard at one of the train's doors), then doors closing
## about TrainService.WARN_S later; the closing itself is the slide sound.
var ok := true
var log: Array = []


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func _beeps(train: Train) -> int:
	var n := 0
	for c in train.get_children():
		if c is AudioStreamPlayer3D and (c as AudioStreamPlayer3D).stream != null and (c as AudioStreamPlayer3D).stream.resource_path.ends_with("door_chime_close.ogg"):
			n += 1
	return n


func run():
	Settings.set_v("access", "step_free", false, false)
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {"seed": "5", "start": "Kennington", "dest": "Oxford_Circus", "spot": "platform", "hour": "10"}
	add_child(g)
	await get_tree().process_frame
	g.start_journey()
	var t0 := Time.get_ticks_msec()
	while g.state != Game.State.BRIEFING and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	g._begin_play()
	for i in 10:
		await get_tree().process_frame
	var st: Station = g.station
	st.trains.doors_opened.connect(func(v): log.append(["open", Clock.now, v["info"]["dep"], _beeps(v["train"])]))
	st.trains.doors_warning.connect(func(v): log.append(["warn", Clock.now, v["info"]["dep"], _beeps(v["train"])]))
	st.trains.doors_closing.connect(func(v): log.append(["close", Clock.now, v["info"]["dep"], _beeps(v["train"])]))
	g.bot_skip = true                                  # (the clock runs at 8x)
	var w0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - w0 < 120000:
		await get_tree().process_frame
		var closes := 0
		for e in log:
			if e[0] == "close":
				closes += 1
		if closes >= 2 or g.state != Game.State.PLAYING:
			break
	g.bot_skip = false
	for e in log:
		print("    ", e[0], " at ", Clock.fmt(e[1], true), " (departure ", Clock.fmt(e[2], true), ") beeps playing ", e[3])
	var warns := log.filter(func(e): return e[0] == "warn")
	var opens := log.filter(func(e): return e[0] == "open")
	var closes2 := log.filter(func(e): return e[0] == "close")
	check(warns.size() >= 1 and closes2.size() >= 1, "%d openings, %d warnings, %d closings" % [opens.size(), warns.size(), closes2.size()])
	check(warns.size() <= opens.size(), "at most one warning per opening")
	for w in warns:
		check(float(w[1]) < float(w[2]) - 6.0 + 0.4 and float(w[1]) > float(w[2]) - 6.0 - TrainService.WARN_S - 0.6, "the warning comes %.1f s before the doors start to close" % (float(w[2]) - 6.0 - float(w[1])))
		check(int(w[3]) >= 1, "the beeps are playing at the train")
	print("OK" if ok else "FAILED")
