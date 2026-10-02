extends Node3D
## PlatformAnnouncer: standing on a platform with the next train a few minutes away the PA says which train and when ("The next train is a ... Due in N minutes."), the periodic
## messages respect the settings, nothing is said with announcements off, the escalator and greeting messages come once.
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func _flat(arr: Array) -> Array:
	var out: Array = []
	for g in arr:
		out.append_array(g)
	return out


func run():
	Timetable.build(1)
	Clock.set_time(8.5 * 3600.0)
	Settings.reset_section("audio")
	var plan := StationPlan.for_station(Net.name_to_idx["Oxford Circus"])
	var fk: String = plan.faces.keys()[0]
	var f: Dictionary = plan.faces[fk]
	var gp0: int = Timetable.plat_index[plan.idx][f["pid"]]
	var nxt: Array = Timetable.next_departures(gp0, Clock.now, 1)
	check(not nxt.is_empty(), "the timetable has a next train")
	Clock.set_time(float(nxt[0]["arr"]) - 150.0)       # (before the station is built: its trains start from this time)
	var st := Station.new()
	add_child(st)
	st.build(plan)
	var pl := Node3D.new()
	add_child(pl)
	st.trains.setup(st, pl)
	pl.global_position = Vector3(f["x0"] + 30.0, f["y"] + 0.2, f["edge_z"] - f["side"] * 1.2)
	var an := PlatformAnnouncer.new()
	add_child(an)
	an.setup(st, pl)
	var ctx := an.face_at(pl.global_position)
	check(not ctx.is_empty() and String(ctx["fd"]["pid"]) == String(f["pid"]), "the announcer finds the platform the player stands on")
	Sfx.spoken.clear()
	for k in 24:
		an.tick("platform", 0.4, 0.5)
	var said := _flat(Sfx.spoken)
	var next_key := ""
	var due_key := ""
	for k in said:
		if String(k).begins_with("platform_next/"):
			next_key = k
		if String(k).begins_with("due_in_"):
			due_key = k
	check(next_key != "" and due_key != "", "said which train and when: %s %s" % [next_key, due_key])
	check(due_key in ["due_in_02_min", "due_in_03_min"], "150 s away is two or three minutes (%s)" % due_key)
	# the same train is not announced twice
	var before := Sfx.spoken.size()
	for k in 10:
		an.tick("platform", 0.4, 0.5)
	var again := 0
	for g in Sfx.spoken.slice(before):
		if String(g[0]).begins_with("platform_next/"):
			again += 1
	check(again == 0, "the same train is announced once")
	# settings
	Settings.set_v("audio", "announce_on", false, false)
	Sfx.spoken.clear()
	var an2 := PlatformAnnouncer.new()
	add_child(an2)
	an2.setup(st, pl)
	for k in 30:
		an2.tick("platform", 0.4, 0.5)
	check(Sfx.spoken.is_empty(), "with announcements off nothing is said")
	Settings.set_v("audio", "announce_on", true, false)
	Settings.set_v("audio", "pa_chatter", false, false)
	Sfx._said.clear()
	Sfx.say(["mind_the_gap_platform"], false, true)
	check(Sfx.spoken.is_empty(), "chatter is switched off by its own setting")
	Settings.set_v("audio", "pa_chatter", true, false)
	# one-off messages
	Sfx._said.clear()
	Sfx.spoken.clear()
	var an3 := PlatformAnnouncer.new()
	add_child(an3)
	an3.setup(st, pl)
	an3.tick("escalator", 0.4, 0.5)
	an3.tick("escalator", 0.4, 0.5)
	an3.tick("hall", 0.4, 0.5)
	an3.tick("hall", 0.4, 0.5)
	var greet := 0
	for g in Sfx.spoken:
		if String(g[0]).begins_with("good_"):
			greet += 1
	check(greet == 1, "one greeting per journey")
	Settings.reset_section("audio")
	print("OK" if ok else "FAILED")
