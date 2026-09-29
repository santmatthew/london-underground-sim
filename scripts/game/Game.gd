class_name Game
extends Node3D
## Top-level game: menus, journey setup, station/ride orchestration, HUD, scoring.

enum State { MENU, LOADING, BRIEFING, PLAYING, RESULT }

var state := State.MENU
var player: Player
var hud: Hud
var map: TubeMap
var env: WorldEnvironment
var station: Station
var ride: Ride
var journey: Dictionary = {}
var opts := {"time": "random", "length": "medium", "hints": true}
var t_play0 := 0.0
var riding := false
var paused := false
var map_open := false
var stats := {"walk": 0.0, "wait": 0.0, "ride": 0.0, "dist": 0.0, "transfers": 0}
var _last_pos := Vector3.ZERO
var _ui: CanvasLayer
var _menu: Control
var _brief: Control
var _result: Control
var _pause: Control
var _loading: Label
var _hint_t := 0.0
var _last_station_idx := -1
var _next_stop_idx := -1
var _ride_line := ""
var _ride_dest := ""
var font_b: Font
var font_r: Font
var bot_skip := false
var autopilot: Autopilot
var cli := {}


func _ready() -> void:
	font_b = load("res://assets/fonts/Barlow-Bold.ttf")
	font_r = load("res://assets/fonts/Barlow-SemiBold.ttf")
	env = Env.make()
	add_child(env)
	player = Player.new()
	player.enabled = false
	add_child(player)
	hud = Hud.new()
	add_child(hud)
	hud.set_visible_hud(false)
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	map = TubeMap.new()
	map.focus_mode = Control.FOCUS_ALL
	map.visible = false
	_ui.add_child(map)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_menu()
	_show_menu()
	_preload()
	_parse_cli()
	if cli.has("autopilot") or cli.has("auto-start"):
		call_deferred("start_journey")


func _parse_cli() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		cli[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if cli.has("time"):
		opts["time"] = cli["time"]
	if cli.has("length"):
		opts["length"] = cli["length"]


func _preload() -> void:
	# warm the material cache so the first station builds quickly
	for n in ["tile_white", "tile_cream", "panel_white", "tactile", "floor_platform", "floor_hall", "ceiling", "concrete", "trackbed", "metal", "rail", "yellow_paint", "black", "light_emissive"]:
		Mats.get_mat(n)


# ---------------------------------------------------------------------------------------------------
# Menus
# ---------------------------------------------------------------------------------------------------
func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.05, 0.12, 0.92)
	s.set_corner_radius_all(14)
	s.content_margin_left = 34
	s.content_margin_right = 34
	s.content_margin_top = 26
	s.content_margin_bottom = 26
	return s


func _mk_label(text: String, size: int, col := Color.WHITE, bold := false, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_b if bold else font_r)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _mk_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font_b)
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(320, 48)
	b.pressed.connect(cb)
	return b


func _center_panel(width := 640.0) -> Control:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, 0)
	pc.add_theme_stylebox_override("panel", _panel_style())
	c.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pc.add_child(vb)
	c.set_meta("vb", vb)
	_ui.add_child(c)
	return c


func _build_menu() -> void:
	_menu = _center_panel(700)
	var vb: VBoxContainer = _menu.get_meta("vb")
	vb.add_child(_mk_label("UNDERGROUND", 54, Color(1, 0.85, 0.2), true))
	vb.add_child(_mk_label("Find your way through the London Underground against the clock. You start somewhere inside a station. Get to your destination's street exit as fast as you can: read the signs, catch the right trains, mind the timetable — and the crowds.", 18, Color(0.85, 0.9, 1.0)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	vb.add_child(grid)
	grid.add_child(_mk_label("Time of day", 18, Color.WHITE, false, false))
	var ob_time := OptionButton.new()
	for t in [["Random", "random"], ["Morning peak", "am_peak"], ["Midday", "midday"], ["Evening peak", "pm_peak"], ["Evening", "evening"], ["Late night", "late"]]:
		ob_time.add_item(t[0])
		ob_time.set_item_metadata(ob_time.item_count - 1, t[1])
	ob_time.item_selected.connect(func(i): opts["time"] = ob_time.get_item_metadata(i))
	grid.add_child(ob_time)
	grid.add_child(_mk_label("Journey length", 18, Color.WHITE, false, false))
	var ob_len := OptionButton.new()
	for t in [["Short", "short"], ["Medium", "medium"], ["Long", "long"]]:
		ob_len.add_item(t[0])
		ob_len.set_item_metadata(ob_len.item_count - 1, t[1])
	ob_len.select(1)
	ob_len.item_selected.connect(func(i): opts["length"] = ob_len.get_item_metadata(i))
	grid.add_child(ob_len)
	grid.add_child(_mk_label("Route hints (H)", 18, Color.WHITE, false, false))
	var cb := CheckButton.new()
	cb.button_pressed = true
	cb.toggled.connect(func(v): opts["hints"] = v)
	grid.add_child(cb)
	vb.add_child(_mk_button("Start journey", func(): start_journey()))
	vb.add_child(_mk_button("Quit", func(): get_tree().quit()))
	_menu.visible = false


func _show_menu() -> void:
	state = State.MENU
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.enabled = false
	_menu.visible = true
	hud.set_visible_hud(false)
	if _result:
		_result.queue_free()
		_result = null
	if station:
		station.queue_free()
		station = null


func _hide_all_panels() -> void:
	_menu.visible = false
	if _brief:
		_brief.queue_free()
		_brief = null
	if _pause:
		_pause.queue_free()
		_pause = null


# ---------------------------------------------------------------------------------------------------
# Journey setup
# ---------------------------------------------------------------------------------------------------
func start_journey() -> void:
	_hide_all_panels()
	state = State.LOADING
	_loading = _mk_label("Building the timetable...", 30, Color.WHITE, true)
	_loading.set_anchors_preset(Control.PRESET_CENTER)
	_loading.position = Vector2(-200, 0)
	_ui.add_child(_loading)
	await get_tree().process_frame
	await get_tree().process_frame
	var seed := int(cli["seed"]) if cli.has("seed") else (int(Time.get_unix_time_from_system()) ^ randi())
	Timetable.build(seed)
	_loading.text = "Choosing your journey..."
	await get_tree().process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	journey = Journey.generate(rng, opts)
	while journey.is_empty():
		journey = Journey.generate(rng, opts)
	journey["seed"] = seed
	_loading.text = "Building %s station..." % Net.station_name(journey["start"])
	await get_tree().process_frame
	Clock.set_time(journey["t0"])
	Clock.running = false
	Clock.time_scale = 1.0
	await _enter_station(journey["start"])
	var spot: Dictionary = journey["spot"]
	player.global_position = spot["pos"] + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	var yaw: float = spot.get("yaw", 0.0)
	player.face(Vector3(sin(yaw), 0, cos(yaw)))
	_loading.queue_free()
	_show_briefing()
	if cli.has("autopilot") or cli.has("auto-start"):
		await get_tree().create_timer(float(cli.get("brief-secs", "2.5"))).timeout
		_begin_play()


func _enter_station(idx: int) -> void:
	if station:
		station.queue_free()
	station = Station.new()
	add_child(station)
	await station.build_async(StationPlan.for_station(idx))
	_hook_station(station)


func _hook_station(st: Station) -> void:
	st.street_exit_reached.connect(_on_street_exit)
	st.trains.setup(st, player)
	st.trains.doors_closing.connect(_on_doors_closing)
	st.trains.doors_opened.connect(_on_doors_opened)
	st.attach_crowd(player)
	_last_station_idx = st.plan.idx


func _show_briefing() -> void:
	state = State.BRIEFING
	_brief = _center_panel(720)
	var vb: VBoxContainer = _brief.get_meta("vb")
	var spot: Dictionary = journey["spot"]
	vb.add_child(_mk_label("YOUR JOURNEY", 40, Color(1, 0.85, 0.2), true))
	vb.add_child(_mk_label("Weekday  ·  %s" % Clock.fmt(journey["t0"]), 26, Color.WHITE, true))
	vb.add_child(_mk_label("You are at %s Underground station — %s." % [Net.station_name(journey["start"]), spot["name"]], 22))
	vb.add_child(_mk_label("Destination: %s" % Net.station_name(journey["dest"]), 34, Color(0.5, 0.9, 1.0), true))
	vb.add_child(_mk_label("Reach the street exit ('Way out') at your destination as quickly as you can. The clock starts when you press Enter. Press M for the Tube map.", 18, Color(0.8, 0.85, 0.95)))
	vb.add_child(_mk_button("Start  (Enter)", func(): _begin_play()))
	map.here = journey["start"]
	map.dest = journey["dest"]
	map.focus_on(journey["start"])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _begin_play() -> void:
	if _brief:
		_brief.queue_free()
		_brief = null
	state = State.PLAYING
	Clock.running = true
	t_play0 = Clock.now
	stats = {"walk": 0.0, "wait": 0.0, "ride": 0.0, "dist": 0.0, "transfers": 0}
	player.enabled = true
	player.frozen = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_visible_hud(true)
	hud.dest_label.text = "To: %s" % Net.station_name(journey["dest"])
	_last_pos = player.global_position
	hud.toast("Find the way to %s" % Net.station_name(journey["dest"]), 5.0)
	if cli.has("autopilot"):
		autopilot = Autopilot.new()
		add_child(autopilot)
		autopilot.setup(self)


# ---------------------------------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	hud.clock_label.text = Clock.fmt(Clock.now, true)
	hud.elapsed_label.text = "elapsed  " + Clock.fmt_dur(Clock.now - t_play0)
	hud.stamina.value = player.stamina
	if riding:
		hud.where_label.text = "On the %s line to %s — next: %s" % [Net.line_name(_ride_line), _ride_dest, Net.station_name(_next_stop_idx) if _next_stop_idx >= 0 else "?"]
		stats["ride"] += delta * Clock.time_scale
	else:
		var loc := "in the station"
		if station:
			loc = _describe_location()
			hud.where_label.text = "%s — %s" % [station.plan.name, loc]
		var d := player.global_position.distance_to(_last_pos)
		if d < 3.0:
			stats["dist"] += d
		_last_pos = player.global_position
		if loc.begins_with("platform") and player.last_speed < 0.5:
			stats["wait"] += delta * Clock.time_scale
		else:
			stats["walk"] += delta * Clock.time_scale
	var skip := Input.is_key_pressed(KEY_TAB) and (riding or player.last_speed < 0.3)
	Clock.time_scale = 8.0 if (skip or bot_skip) else 1.0


func _describe_location() -> String:
	if station == null:
		return ""
	var p := player.global_position
	for mi in station.modules.size():
		var m: PlatformModule = station.modules[mi]
		var lp := m.to_local(p)
		if absf(lp.x) < m.meta["length"] * 0.5 + 12.0 and absf(lp.z) < 9.0 and absf(lp.y) < 3.5:
			var mod: Dictionary = station.plan.modules[mi]
			for fd in mod["faces"]:
				var f: Dictionary = station.plan.faces["%s#%d" % [fd["pid"], fd["face"]]]
				if (f["side"] > 0.0 and lp.z > 1.5 and lp.z < 5.2) or (f["side"] < 0.0 and lp.z < -1.5 and lp.z > -5.2):
					return "platform %d, %s %s" % [station.plan.platform_no[fd["pid"]], station.plan.station_platform(fd["pid"])["dir"], Net.line_name(f["line"])]
			return "platform passages"
	if p.y > -1.0:
		if p.z < station.plan.gates["z"]:
			return "ticket hall (before the gates)"
		return "ticket hall (paid area)"
	return "below ground"


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				if state == State.BRIEFING:
					_begin_play()
			KEY_M:
				if state == State.PLAYING or state == State.BRIEFING:
					_toggle_map()
			KEY_H:
				if state == State.PLAYING:
					_toggle_hint()
			KEY_ESCAPE:
				if map_open:
					_toggle_map()
				elif state == State.PLAYING:
					_toggle_pause()


func _toggle_map() -> void:
	map_open = not map_open
	map.visible = map_open
	if journey.has("dest"):
		map.dest = journey["dest"]
	map.here = _last_station_idx if not riding else -1
	if map.here >= 0:
		map.focus_on(map.here)
	if state == State.PLAYING:
		player.frozen = map_open
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if map_open else Input.MOUSE_MODE_CAPTURED
	if map_open:
		map.grab_focus()


func _toggle_pause() -> void:
	paused = not paused
	if paused:
		Clock.running = false
		player.enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_pause = _center_panel(420)
		var vb: VBoxContainer = _pause.get_meta("vb")
		vb.add_child(_mk_label("PAUSED", 40, Color(1, 0.85, 0.2), true))
		vb.add_child(_mk_button("Resume", func(): _toggle_pause()))
		vb.add_child(_mk_button("Give up (main menu)", func(): paused = false; _end_to_menu()))
	else:
		if _pause:
			_pause.queue_free()
			_pause = null
		Clock.running = true
		player.enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _end_to_menu() -> void:
	riding = false
	if ride:
		ride.queue_free()
		ride = null
	for c in get_children():
		if c is Train or c is TunnelRun:
			c.queue_free()
	Clock.running = true
	_show_menu()


func _toggle_hint() -> void:
	if not opts.get("hints", true):
		hud.toast("Hints are off (enable them in the menu)")
		return
	if hud.hint_panel.visible:
		hud.hint_panel.visible = false
		return
	hud.hint_panel.visible = true
	hud.hint_label.text = "Working out the best route..."
	await get_tree().process_frame
	hud.hint_label.text = _hint_text()


func _hint_text() -> String:
	var dest: int = journey["dest"]
	if riding:
		return "You are on the %s line to %s.\nNext stop: %s.\nDestination: %s." % [Net.line_name(_ride_line), _ride_dest, Net.station_name(_next_stop_idx), Net.station_name(dest)]
	var idx: int = station.plan.idx
	if idx == dest:
		return "You are at your destination station. Follow the 'Way out' signs to the street exit."
	var plan := station.plan
	var best := "hall_unpaid"
	var bd := 1e9
	var p := player.global_position
	for n in plan.nodes:
		var d: float = (n["pos"] as Vector3).distance_to(p)
		if d < bd:
			bd = d
			best = n["name"]
	var res := Planner.plan(idx, best, Clock.now, dest)
	if not res.get("ok", false):
		return "No route found from here."
	var s := "Fastest route from here:\n"
	for lg in res["legs"]:
		s += "• %s line towards %s — board at %s (%s), alight %s\n" % [Net.line_name(lg["line"]), Net.station_name(lg["dest"]), Net.station_name(lg["from"]), Clock.fmt(lg["dep"]), Net.station_name(lg["to"])]
	s += "Arrive at the street exit about %s." % Clock.fmt(res["arrive"])
	return s


# ---------------------------------------------------------------------------------------------------
# Trains: boarding / riding / alighting
# ---------------------------------------------------------------------------------------------------
func _on_doors_opened(v: Dictionary) -> void:
	var train: Train = v["train"]
	if station and train.contains_world_point(player.global_position):
		var info: Dictionary = v["info"]
		hud.say("This is %s.%s" % [station.plan.name, _change_text(station.plan.idx, info["line"])], 7.0)
		if info["final"]:
			hud.say("This train terminates here. All change please.", 7.0)


func _change_text(idx: int, line: String) -> String:
	var others: Array = []
	for lid in Net.stations[idx]["lines"]:
		if lid != line:
			others.append(Net.line_name(lid))
	if others.is_empty():
		return ""
	return "  Change here for the %s line%s." % [", ".join(others), "s" if others.size() > 1 else ""]


func _on_doors_closing(v: Dictionary) -> void:
	if state != State.PLAYING or riding or station == null:
		return
	var train: Train = v["train"]
	if not train.contains_world_point(player.global_position):
		return
	var info: Dictionary = v["info"]
	if info["final"]:
		var pos := station.platform_point(v["key"], 0.5, 1.2)
		player.global_position = pos + Vector3(0, 0.1, 0)
		hud.toast("This train terminates here — everybody off.", 4.0)
		return
	_begin_ride(train, v)


func _begin_ride(train: Train, v: Dictionary) -> void:
	riding = true
	stats["transfers"] += 1
	ride = Ride.new()
	add_child(ride)
	ride.arrived.connect(_on_ride_arrived)
	var info: Dictionary = v["info"]
	_ride_line = info["line"]
	_ride_dest = Net.station_name(info["dest"])
	var next_idx: int = (Timetable.run_stops[info["run"]] as PackedInt32Array)[info["k"] + 1]
	_next_stop_idx = next_idx
	ride.start(self, train, info["run"], info["k"], station, player.global_position)
	station = null
	hud.say("Stand clear of the doors please.  This is a %s line train to %s.  The next station is %s." % [Net.line_name(_ride_line), _ride_dest, Net.station_name(next_idx)], 8.0)


func _on_ride_arrived(dest_station: Station, vkey: String) -> void:
	riding = false
	station = dest_station
	ride.queue_free()
	ride = null
	_hook_station(station)
	station.trains.player = player
	var info: Dictionary = (station.trains.visits[vkey] as Dictionary)["info"]
	hud.say("This is %s.%s Mind the gap." % [station.plan.name, _change_text(station.plan.idx, info["line"])], 7.0)
	if station.plan.idx == journey["dest"]:
		hud.toast("Your destination! Leave the train and follow the Way out signs.", 5.0)


func _on_street_exit(_door: String) -> void:
	if state != State.PLAYING or station == null:
		return
	if station.plan.idx == journey["dest"]:
		_finish_journey()
	else:
		hud.toast("That's not your destination — this is %s. Head back down to the platforms." % station.plan.name, 4.0)
		player.global_position += Vector3(0, 0, 3.0)


# ---------------------------------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------------------------------
func _finish_journey() -> void:
	state = State.RESULT
	Clock.running = false
	player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var elapsed: float = Clock.now - t_play0
	var par: float = journey["par_s"]
	var score := clampf(par / maxf(elapsed, 1.0), 0.0, 1.0) * 100.0
	_result = _center_panel(760)
	var vb: VBoxContainer = _result.get_meta("vb")
	vb.add_child(_mk_label("JOURNEY COMPLETE", 40, Color(1, 0.85, 0.2), true))
	vb.add_child(_mk_label("%s → %s" % [Net.station_name(journey["start"]), Net.station_name(journey["dest"])], 26, Color.WHITE, true))
	vb.add_child(_mk_label("Your time: %s        Optimal: %s" % [Clock.fmt_dur(elapsed), Clock.fmt_dur(par)], 24, Color(0.6, 0.9, 1.0), true))
	vb.add_child(_mk_label("Score %d%%  —  %s" % [int(round(score)), Journey.rating(score)], 30, Color(1, 0.9, 0.4), true))
	vb.add_child(_mk_label("Walking %s · waiting %s · on trains %s · %d train%s · %d m on foot" % [Clock.fmt_dur(stats["walk"]), Clock.fmt_dur(stats["wait"]), Clock.fmt_dur(stats["ride"]), stats["transfers"], "" if stats["transfers"] == 1 else "s", int(stats["dist"])], 17, Color(0.8, 0.85, 0.95)))
	var route := "Fastest route:\n"
	for lg in journey["par"]["legs"]:
		route += "• %s line: %s → %s  (%s–%s)\n" % [Net.line_name(lg["line"]), Net.station_name(lg["from"]), Net.station_name(lg["to"]), Clock.fmt(lg["dep"]), Clock.fmt(lg["arr"])]
	vb.add_child(_mk_label(route, 17, Color(0.85, 0.9, 1.0)))
	vb.add_child(_mk_button("New journey", func(): _result.queue_free(); _result = null; start_journey()))
	vb.add_child(_mk_button("Main menu", func(): _show_menu()))
	_save_score(score, elapsed)
	print("RESULT %s -> %s  time %s  par %s  score %d%%" % [Net.station_name(journey["start"]), Net.station_name(journey["dest"]), Clock.fmt_dur(elapsed), Clock.fmt_dur(par), int(round(score))])
	if cli.has("autopilot") and cli.has("quit-when-done"):
		await get_tree().create_timer(float(cli.get("end-secs", "4.0"))).timeout
		get_tree().quit()


func _save_score(score: float, elapsed: float) -> void:
	var path := "user://scores.json"
	var arr: Array = []
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Array:
			arr = parsed
	arr.append({"score": score, "time": elapsed, "from": Net.station_name(journey["start"]), "to": Net.station_name(journey["dest"]), "when": Time.get_datetime_string_from_system()})
	arr.sort_custom(func(a, b): return a["score"] > b["score"])
	arr = arr.slice(0, 20)
	var fw := FileAccess.open(path, FileAccess.WRITE)
	fw.store_string(JSON.stringify(arr))
