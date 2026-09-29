extends Node
func run():
	print("Sfx enabled: ", Sfx.enabled, " clips: ", Sfx.clips.size())
	var missing := 0
	for k in ["door_chime_open", "gate_beep_ok", "train_arrive_platform", "concourse_ambience_loop", "platform_ambience_loop", "tunnel_rumble_loop", "escalator_loop", "footstep_concrete_1", "stand_clear_of_the_doors", "mind_the_gap", "ui_click_soft"]:
		var s := Sfx.stream(k)
		print("  ", k, " -> ", s.get_class() if s else "MISSING", " ", ("%.1fs" % s.get_length()) if s else "")
		if s == null: missing += 1
	var oc: int = Net.name_to_idx["Oxford Circus"]
	print("station keys: ", Sfx.has(Sfx.station_key(oc, "this")), Sfx.has(Sfx.station_key(oc, "next")), Sfx.has(Sfx.station_key(oc, "change")))
	Sfx.set_zone("platform", 0.8)
	await get_tree().create_timer(2.0).timeout
	for n in Sfx._layers:
		var l: Dictionary = Sfx._layers[n]
		print("layer ", n, " key=", l["key"], " playing=", (l["player"] as AudioStreamPlayer).playing, " vol=", snappedf((l["player"] as AudioStreamPlayer).volume_db, 0.1))
	Sfx.say_station_this(oc)
	await get_tree().create_timer(1.0).timeout
	print("speech playing: ", Sfx._speech_player.playing, " (missing streams: ", missing, ")")
