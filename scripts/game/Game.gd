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
var _cb_fullscreen: CheckButton
var _ob_upscaler: OptionButton
var _ob_aa: OptionButton
var _adaptive: AdaptiveScale

var opts := {"mode": "single", "stops": 3, "time": "random", "length": "medium", "hints": true, "day": "random", "quality": 1, "scale": 0.0, "upscaler": "fsr1", "aa": "taa", "crowd": 1.0}
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
var _audio_t := 0.0
var _scores_label: Label
var _par_task := -1
var par_result: Dictionary = {}
var _settings: SettingsPanel
var autopilot: Autopilot
var announcer := PlatformAnnouncer.new()          # what the station says and does around the player (platform PA, tunnel wind ...)
var cli := {}


func _ready() -> void:
	font_b = load("res://assets/fonts/Barlow-Bold.ttf")
	font_r = load("res://assets/fonts/Barlow-SemiBold.ttf")
	env = Env.make(opts["quality"])
	add_child(env)
	player = Player.new()
	player.enabled = false
	add_child(player)
	player.fell.connect(_on_player_fell)
	player.interact_pressed.connect(_on_interact)
	player.respawn_provider = _respawn_point
	_stage("Game._ready begins")
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
	add_child(announcer)
	Sfx.subtitle.connect(func(t, secs): if hud and bool(Settings.get_v("audio", "subtitles")): hud.say(t, secs))
	_stage("HUD, map, UI nodes")
	_build_menu()
	_stage("_build_menu")
	_show_menu()
	get_tree().root.size_changed.connect(func():
		opts.erase("_auto_now")                                  # "Auto" render scale follows the window size (and restarts its adaptation)
		if _adaptive != null and _adaptive.enabled:
			_adaptive.stop()
		_apply_settings())
	_apply_settings()
	_stage("settings + signals")
	_preload()
	_stage("_preload (materials)")
	_warm_up_people.call_deferred()
	_parse_cli()
	_load_display_settings()
	if cli.has("fps-log"):
		_start_fps_log(String(cli["fps-log"]), float(cli.get("fps-secs", "0")), cli.has("fps-quit"))
	if cli.has("autopilot") or cli.has("auto-start"):
		_auto_start.call_deferred()


## `--menu-secs=N` waits N seconds at the main menu first, as a person would (the start-up work behind the menu then runs before the journey is chosen)
func _auto_start() -> void:
	var wait := float(cli.get("menu-secs", "0"))
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	start_journey()


## Full screen: borderless full-screen window at the desktop's resolution (F11 or Alt+Enter, or the menu). Remembered between runs; `--fullscreen` / `--windowed` override it.
func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func set_fullscreen(on: bool, save := true) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if not on:
		# leaving full screen: back to a sensible window size, centred on the screen it was on
		var scr := DisplayServer.window_get_current_screen()
		var area := DisplayServer.screen_get_usable_rect(scr)
		var sz := Vector2i(mini(1600, area.size.x - 80), mini(900, area.size.y - 80))
		DisplayServer.window_set_size(sz)
		DisplayServer.window_set_position(area.position + (area.size - sz) / 2)
	if _cb_fullscreen != null and _cb_fullscreen.button_pressed != on:
		_cb_fullscreen.set_pressed_no_signal(on)
	if save:
		var cf := ConfigFile.new()
		cf.load(Settings.path)
		cf.set_value("display", "fullscreen", on)
		cf.save(Settings.path)
	_apply_settings()


## Upscaler for the render scales below 100 % (menu "Upscaler"; remembered in user://settings.cfg; `--upscaler=fsr1|fsr2` overrides)
func set_upscaler(kind: String, save := true) -> void:
	opts["upscaler"] = kind
	if _ob_upscaler != null and _ob_upscaler.selected != (1 if kind == "fsr2" else 0):
		_ob_upscaler.select(1 if kind == "fsr2" else 0)
	if save:
		var cf := ConfigFile.new()
		cf.load(Settings.path)
		cf.set_value("display", "upscaler", kind)
		cf.save(Settings.path)
	_apply_settings()


## "Auto" render scale adapts to the GPU time (AdaptiveScale); a fixed scale or `--no-adaptive` switches it off
func _update_adaptive() -> void:
	var want := float(opts.get("scale", 0.0)) <= 0.0 and not cli.has("no-adaptive") and DisplayServer.get_name() != "headless"
	if want and _adaptive == null:
		_adaptive = AdaptiveScale.new()
		add_child(_adaptive)
		_adaptive.changed.connect(func(s):
			opts["_auto_now"] = s
			RenderSettings.apply(env.environment, get_viewport(), opts, DisplayServer.window_get_size()))
	if want and _adaptive != null and not _adaptive.enabled:
		_adaptive.start(get_viewport(), RenderSettings.auto_scale(DisplayServer.window_get_size()))
		opts["_auto_now"] = _adaptive.scale
	elif not want and _adaptive != null and _adaptive.enabled:
		_adaptive.stop()
		opts.erase("_auto_now")


## Anti-aliasing: TAA, FXAA (nearly free) or off (remembered like the upscaler; `--aa=taa|fxaa|off`)
func set_aa(kind: String, save := true) -> void:
	opts["aa"] = kind
	if _ob_aa != null:
		var i := ["taa", "fxaa", "off"].find(kind)
		if i >= 0 and _ob_aa.selected != i:
			_ob_aa.select(i)
	if save:
		var cf := ConfigFile.new()
		cf.load(Settings.path)
		cf.set_value("display", "aa", kind)
		cf.save(Settings.path)
	_apply_settings()


func _load_display_settings() -> void:
	var on := false
	var cf := ConfigFile.new()
	if cf.load(Settings.path) == OK:
		on = bool(cf.get_value("display", "fullscreen", false))
	if cli.has("fullscreen"):
		on = true
	if cli.has("windowed"):
		on = false
	if on != is_fullscreen():
		set_fullscreen(on, false)
	elif _cb_fullscreen != null:
		_cb_fullscreen.set_pressed_no_signal(on)
	var up := String(cf.get_value("display", "upscaler", "fsr1")) if cf.get_sections().size() > 0 else "fsr1"
	if cli.has("upscaler"):
		up = String(cli["upscaler"])
	set_upscaler("fsr2" if up == "fsr2" else "fsr1", false)
	var aa := String(cf.get_value("display", "aa", "taa")) if cf.get_sections().size() > 0 else "taa"
	if cli.has("aa"):
		aa = String(cli["aa"])
	set_aa(aa if aa in ["taa", "fxaa", "off"] else "taa", false)


## Frame-time log (FrameLog): `--fps-log=<file.csv> [--fps-secs=300] [--fps-quit]` from the command line, F4 in game (writes user://fps_<time>.csv and says where)
var _frame_log: FrameLog


func _start_fps_log(path: String, secs := 0.0, quit_when_done := false) -> void:
	if _frame_log != null and _frame_log.running:
		return
	if _frame_log == null:
		_frame_log = FrameLog.new()
		add_child(_frame_log)
	_frame_log.on_done = func(sm):
		if hud:
			hud.toast("Frame log saved: %s  (%s fps average, 1%% low %s)" % [_frame_log.path, str(sm.get("fps_mean", "?")), str(sm.get("fps_1pct_low", "?"))])
		if quit_when_done:
			get_tree().quit()
	_frame_log.start(path, secs)


func _toggle_fps_log() -> void:
	if _frame_log != null and _frame_log.running:
		_frame_log.stop()
	else:
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		_start_fps_log(ProjectSettings.globalize_path("user://fps_%s.csv" % stamp))
		if hud:
			hud.toast("Frame log started (F4 again to stop and save)")


func _parse_cli() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		cli[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if cli.has("time"):
		opts["time"] = cli["time"]
	if cli.has("length"):
		opts["length"] = cli["length"]


## Render scale for "Auto" (see RenderSettings)
static func auto_scale(size: Vector2i) -> float:
	return RenderSettings.auto_scale(size)


func _apply_settings() -> void:
	RenderSettings.apply(env.environment, get_viewport(), opts, DisplayServer.window_get_size())
	_update_adaptive()
	if station and station.crowd:
		station.crowd.density = opts["crowd"]
		station.crowd.enabled = opts["crowd"] > 0.0


## Draw every character once, off screen, while the menu is up: otherwise the first appearance of each of the 36 characters in a station costs about 130 ms
func _warm_up_people() -> void:
	_stage("_ready ends / warm-up starts")
	Train.preload_async()            # the car models load in the background while the menu is up
	StationProps.preload_async()
	StationPlan.warm_all_async()     # ... and so do the plans of all stations (1.7 s of work) that choosing a journey needs
	await get_tree().process_frame
	_stage("frame 1 after _ready")
	await get_tree().process_frame
	_stage("frame 2 after _ready")
	await CrowdWarmup.run(self)
	_stage("CrowdWarmup done")


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
	b.pressed.connect(func(): Sfx.play("ui_click_soft"))
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
	grid.add_child(_mk_label("Game mode", 18, Color.WHITE, false, false))
	var ob_mode := OptionButton.new()
	for t in [["Single destination", "single"], ["Multi-stop (visit several stations)", "multi"]]:
		ob_mode.add_item(t[0])
		ob_mode.set_item_metadata(ob_mode.item_count - 1, t[1])
	ob_mode.item_selected.connect(func(i): opts["mode"] = ob_mode.get_item_metadata(i))
	grid.add_child(ob_mode)
	grid.add_child(_mk_label("Stops (multi-stop)", 18, Color.WHITE, false, false))
	var ob_n := OptionButton.new()
	for t in [3, 4, 5]:
		ob_n.add_item("%d stations" % t)
		ob_n.set_item_metadata(ob_n.item_count - 1, t)
	ob_n.item_selected.connect(func(i): opts["stops"] = ob_n.get_item_metadata(i))
	grid.add_child(ob_n)
	grid.add_child(_mk_label("Day", 18, Color.WHITE, false, false))
	var ob_day := OptionButton.new()
	for t in [["Random", "random"], ["Weekday", "weekday"], ["Saturday", "saturday"], ["Sunday", "sunday"]]:
		ob_day.add_item(t[0])
		ob_day.set_item_metadata(ob_day.item_count - 1, t[1])
	ob_day.item_selected.connect(func(i): opts["day"] = ob_day.get_item_metadata(i))
	grid.add_child(ob_day)
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
	grid.add_child(_mk_label("Route hints", 18, Color.WHITE, false, false))
	var cb := CheckButton.new()
	cb.button_pressed = true
	cb.toggled.connect(func(v): opts["hints"] = v)
	grid.add_child(cb)
	grid.add_child(_mk_label("Graphics", 18, Color.WHITE, false, false))
	var ob_q := OptionButton.new()
	for t in [["Fast (no screen-space effects)", 0], ["Balanced (ambient occlusion)", 1], ["High (+ light bounce, reflections; much slower)", 2], ["Ultra (+ global illumination, haze; slowest)", 3]]:
		ob_q.add_item(t[0])
		ob_q.set_item_metadata(ob_q.item_count - 1, t[1])
	ob_q.select(int(opts["quality"]))
	ob_q.item_selected.connect(func(i): opts["quality"] = ob_q.get_item_metadata(i); _apply_settings())
	grid.add_child(ob_q)
	grid.add_child(_mk_label("Render scale", 18, Color.WHITE, false, false))
	var ob_s := OptionButton.new()
	for t in [["Auto (adapts to keep about 60 fps)", 0.0], ["100% (native)", 1.0], ["85% (upscaled)", 0.85], ["70% (upscaled, faster)", 0.7], ["55% (upscaled, fastest)", 0.55]]:
		ob_s.add_item(t[0])
		ob_s.set_item_metadata(ob_s.item_count - 1, t[1])
	ob_s.select(0)
	ob_s.item_selected.connect(func(i): opts["scale"] = ob_s.get_item_metadata(i); _apply_settings())
	grid.add_child(ob_s)
	grid.add_child(_mk_label("Upscaler", 18, Color.WHITE, false, false))
	_ob_upscaler = OptionButton.new()
	for t in [["FSR 1 (fastest)", "fsr1"], ["FSR 2 (sharper text and fences, a few ms slower)", "fsr2"]]:
		_ob_upscaler.add_item(t[0])
		_ob_upscaler.set_item_metadata(_ob_upscaler.item_count - 1, t[1])
	_ob_upscaler.select(1 if String(opts.get("upscaler", "fsr1")) == "fsr2" else 0)
	_ob_upscaler.item_selected.connect(func(i): set_upscaler(String(_ob_upscaler.get_item_metadata(i))))
	grid.add_child(_ob_upscaler)
	grid.add_child(_mk_label("Anti-aliasing", 18, Color.WHITE, false, false))
	_ob_aa = OptionButton.new()
	for t in [["TAA (smoothest)", "taa"], ["FXAA (about 2 ms faster at 4K, a little softer)", "fxaa"], ["Off", "off"]]:
		_ob_aa.add_item(t[0])
		_ob_aa.set_item_metadata(_ob_aa.item_count - 1, t[1])
	_ob_aa.select(["taa", "fxaa", "off"].find(String(opts.get("aa", "taa"))))
	_ob_aa.item_selected.connect(func(i): set_aa(String(_ob_aa.get_item_metadata(i))))
	grid.add_child(_ob_aa)
	grid.add_child(_mk_label("Full screen (F11)", 18, Color.WHITE, false, false))
	_cb_fullscreen = CheckButton.new()
	_cb_fullscreen.button_pressed = is_fullscreen()
	_cb_fullscreen.toggled.connect(func(v): set_fullscreen(v))
	grid.add_child(_cb_fullscreen)
	grid.add_child(_mk_label("Crowds", 18, Color.WHITE, false, false))
	var ob_c := OptionButton.new()
	for t in [["Empty", 0.0], ["Light", 0.6], ["Realistic", 1.0], ["Packed", 1.5]]:
		ob_c.add_item(t[0])
		ob_c.set_item_metadata(ob_c.item_count - 1, t[1])
	ob_c.select(2)
	ob_c.item_selected.connect(func(i): opts["crowd"] = ob_c.get_item_metadata(i))
	grid.add_child(ob_c)
	vb.add_child(_mk_button("Start journey", func(): start_journey()))
	vb.add_child(_mk_button("Settings (sound, accessibility, controls)", func(): _open_settings(_menu)))
	vb.add_child(_mk_button("Quit", func(): get_tree().quit()))
	_scores_label = _mk_label("", 15, Color(0.75, 0.8, 0.95))
	vb.add_child(_scores_label)
	_menu.visible = false


## the settings screen (sound, accessibility, controls) over whatever panel opened it, which comes back when the player leaves it
func _open_settings(back_to: Control) -> void:
	if _settings == null:
		_settings = SettingsPanel.new(font_b, font_r)
		_ui.add_child(_settings)
	back_to.visible = false
	_settings.open()
	await _settings.closed
	if is_instance_valid(back_to):
		back_to.visible = true


func _refresh_scores() -> void:
	if _scores_label == null:
		return
	var path := "user://scores.json"
	if not FileAccess.file_exists(path):
		_scores_label.text = ""
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var arr = JSON.parse_string(f.get_as_text())
	if not (arr is Array) or arr.is_empty():
		_scores_label.text = ""
		return
	var t := "Best journeys\n"
	for i in mini(5, arr.size()):
		var e: Dictionary = arr[i]
		t += "  %d%%  %s → %s  (%s)\n" % [int(round(e["score"])), e["from"], e["to"], Clock.fmt_dur(e["time"])]
	_scores_label.text = t


func _show_menu() -> void:
	_refresh_scores()
	state = State.MENU
	# nothing from a journey may stay on top of the main menu: the pause panel (Give up), the briefing, the map overlay
	paused = false
	player.cancel_sit()
	hud.set_prompt("")
	if _pause:
		_pause.queue_free()
		_pause = null
	if _brief:
		_brief.queue_free()
		_brief = null
	if map_open:
		map_open = false
		map.visible = false
	player.frozen = false
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
var _stage_t := 0


## UG_ON=loadtime prints how long each stage of starting a journey takes (and the frame-time hitch each leaves)
func _stage(label: String) -> void:
	if Station.debug_on("loadtime"):
		var now := Time.get_ticks_msec()
		print("LOAD %-34s %6d ms   (t = %.2f s since the engine started)" % [label, now - _stage_t if _stage_t != 0 else 0, now / 1000.0])
		_stage_t = now


func start_journey() -> void:
	_stage("(before start_journey)")
	_hide_all_panels()
	announcer.greeted = false
	state = State.LOADING
	_loading = _mk_label("Building the timetable...", 30, Color.WHITE, true)
	_loading.set_anchors_preset(Control.PRESET_CENTER)
	_loading.position = Vector2(-200, 0)
	_ui.add_child(_loading)
	await get_tree().process_frame
	await get_tree().process_frame
	_stage("loading label up")
	var seed := int(cli["seed"]) if cli.has("seed") else (int(Time.get_unix_time_from_system()) ^ randi())
	var day_rng := RandomNumberGenerator.new()
	day_rng.seed = seed + 99
	var day := Journey.pick_day(day_rng, str(cli.get("day", opts.get("day", "random"))))
	Clock.weekend = day != "weekday"
	var day_name: String = {"weekday": "Weekday", "saturday": "Saturday", "sunday": "Sunday"}[day]
	if station:                      # nothing may read the timetable while the worker rebuilds it
		station.queue_free()
		station = null
	await Timetable.build_async(seed)
	_stage("Timetable.build")
	_loading.text = "Choosing your journey..."
	while not StationPlan.warm_ready():      # normally long done: the plans were built in the background behind the menu
		await get_tree().process_frame
	StationPlan.warm_all()
	_stage("StationPlan.warm_all")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var multi: bool = opts.get("mode", "single") == "multi"
	if cli.has("start") and cli.has("dest"):
		multi = false
	# the pick plans routes over every station (a third of a second): on a worker thread, everything it reads is built and no longer written
	_pick_task = WorkerThreadPool.add_task(_pick_journey.bind(rng, multi), false, "journey pick")
	var pick_task := _pick_task
	while not WorkerThreadPool.is_task_completed(pick_task):
		await get_tree().process_frame
	if _pick_task == pick_task:
		WorkerThreadPool.wait_for_task_completion(pick_task)
		_pick_task = -1
	journey = _picked
	_stage("journey pick")
	journey["seed"] = seed
	journey["day"] = day_name
	journey["mode"] = "multi" if multi else "single"
	par_result = {}
	_par_task = -1
	if multi:
		var jc: Dictionary = journey
		_par_task = WorkerThreadPool.add_task(func():
			par_result = Planner.plan_tour(jc["start"], jc["spot"]["node"], jc["t0"], jc["targets"]))
	_loading.text = "Building %s station..." % Net.station_name(journey["start"])
	await get_tree().process_frame
	Clock.set_time(journey["t0"])
	Clock.running = false
	Clock.time_scale = 1.0
	await _enter_station(journey["start"])
	_stage("_enter_station (build + hook)")
	var spot: Dictionary = journey["spot"]
	player.cancel_sit()
	player.global_position = spot["pos"] + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	var yaw: float = spot.get("yaw", 0.0)
	player.face(Vector3(sin(yaw), 0, cos(yaw)))
	_loading.queue_free()
	_show_briefing()
	_stage("briefing up")
	if cli.has("autopilot") or cli.has("auto-start"):
		await get_tree().create_timer(float(cli.get("brief-secs", "2.5"))).timeout
		_begin_play()


var _picked: Dictionary = {}
var _pick_task := -1


## quitting while the journey is being picked: the worker reads this node, so it must be finished before the node is freed
func _exit_tree() -> void:
	StationPlan.finish_warm()
	if _pick_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_pick_task)
		_pick_task = -1


## runs on a worker thread (see start_journey)
func _pick_journey(rng: RandomNumberGenerator, multi: bool) -> void:
	if cli.has("start") and cli.has("dest"):
		_picked = Journey.make(str(cli["start"]).replace("_", " "), str(cli.get("spot", "platform")).replace("_", " "), str(cli["dest"]).replace("_", " "), float(cli.get("hour", "9")), rng)
		return
	_picked = Journey.generate_multi(rng, opts) if multi else Journey.generate(rng, opts)
	while _picked.is_empty():
		_picked = Journey.generate_multi(rng, opts) if multi else Journey.generate(rng, opts)


func _enter_station(idx: int) -> void:
	if station:
		station.queue_free()
	station = Station.new()
	add_child(station)
	await station.build_async(StationPlan.for_station(idx))
	_stage("  station.build_async")
	if Station.debug_on("loadtime"):
		print("LOAD   station build ms per part: ", station.prof)
	_hook_station(station)


func _hook_station(st: Station) -> void:
	st.street_exit_reached.connect(_on_street_exit)
	st.trains.setup(st, player)
	st.trains.doors_closing.connect(_on_doors_closing)
	st.trains.doors_opened.connect(_on_doors_opened)
	_stage("  trains.setup")
	st.attach_crowd(player)
	announcer.setup(st, player)
	_stage("  attach_crowd")
	if st.crowd:
		st.crowd.density = opts["crowd"]
		st.crowd.enabled = opts["crowd"] > 0.0
	_last_station_idx = st.plan.idx


func _show_briefing() -> void:
	state = State.BRIEFING
	var go_key := "Enter" if not InputBindings.last_was_pad else InputBindings.pad_text("interact")
	_brief = _center_panel(720)
	var vb: VBoxContainer = _brief.get_meta("vb")
	var spot: Dictionary = journey["spot"]
	vb.add_child(_mk_label("YOUR JOURNEY", 40, Color(1, 0.85, 0.2), true))
	vb.add_child(_mk_label("%s  ·  %s" % [journey.get("day", "Weekday"), Clock.fmt(journey["t0"])], 26, Color.WHITE, true))
	vb.add_child(_mk_label("You are at %s Underground station — %s." % [Net.station_name(journey["start"]), spot["name"]], 22))
	if journey["mode"] == "multi":
		vb.add_child(_mk_label("Visit all %d stations (in any order):" % journey["targets"].size(), 26, Color(0.5, 0.9, 1.0), true))
		var names: Array = []
		for t in journey["targets"]:
			names.append(Net.station_name(t))
		vb.add_child(_mk_label("  ·  ".join(names), 28, Color(1, 0.9, 0.4), true))
		vb.add_child(_mk_label("Reach the street exit ('Way out') at each station. After each one you re-enter (25 s). The clock starts when you press %s. Press %s for the Tube map." % [go_key, InputBindings.prompt("map")], 18, Color(0.8, 0.85, 0.95)))
	else:
		vb.add_child(_mk_label("Destination: %s" % Net.station_name(journey["dest"]), 34, Color(0.5, 0.9, 1.0), true))
		vb.add_child(_mk_label("Reach the street exit ('Way out') at your destination as quickly as you can. The clock starts when you press %s. Press %s for the Tube map." % [go_key, InputBindings.prompt("map")], 18, Color(0.8, 0.85, 0.95)))
	var start_btn := _mk_button("Start  (%s)" % go_key, func(): _begin_play())
	vb.add_child(start_btn)
	start_btn.grab_focus.call_deferred()
	map.here = journey["start"]
	map.dest = journey["dest"] if journey["mode"] == "single" else -1
	map.stops = journey.get("targets", [])
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
	_refresh_dest_label()
	_last_pos = player.global_position
	_apply_settings()
	if journey["mode"] == "multi":
		hud.toast("Visit all %d stations — any order" % journey["targets"].size(), 5.0)
	else:
		hud.toast("Find the way to %s" % Net.station_name(journey["dest"]), 5.0)
	if cli.has("autopilot"):
		autopilot = Autopilot.new()
		add_child(autopilot)
		autopilot.setup(self)


# ---------------------------------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------------------------------
var _seat_candidate: Node3D


## "E  Sit down" near an empty seat (train seat or platform bench), "E  Stand up" while seated
func _update_seat_prompt() -> void:
	if player.bot_active or paused or map_open or not player.enabled:
		hud.set_prompt("")
		_seat_candidate = null
		return
	if player.seated:
		hud.set_prompt("%s  Stand up   (or just move)" % InputBindings.prompt("interact"))
		return
	_seat_candidate = Seats.nearest_free(get_tree(), player.global_position)
	hud.set_prompt("%s  Sit down" % InputBindings.prompt("interact") if _seat_candidate != null else "")


func _on_interact() -> void:
	if state != State.PLAYING or paused or map_open or player.bot_active:
		return
	if player.seated:
		player.stand_up()
	elif _seat_candidate != null and is_instance_valid(_seat_candidate):
		player.sit_on(_seat_candidate)
		_seat_candidate = null


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	_update_seat_prompt()
	hud.clock_label.text = Clock.fmt(Clock.now, true)
	hud.elapsed_label.text = "elapsed  " + Clock.fmt_dur(Clock.now - t_play0)
	hud.stamina.value = player.stamina
	if hud.perf_on and station and station.crowd:
		hud.extra_perf = "\ncrowd %d agents · %d awake · %d riders" % [station.crowd.stats["agents"], station.crowd.stats["awake"], station.crowd.stats["riders"]] \
				+ "\nrender scale %d%%%s" % [int(round(get_viewport().scaling_3d_scale * 100.0)), " (adaptive)" if (_adaptive != null and _adaptive.enabled) else ""]
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
	if station and station.crowd and not riding:
		var cnt := station.crowd.density_ahead(player.global_position, player.forward())
		var target := clampf(1.0 - 0.08 * cnt, 0.5, 1.0)
		player.speed_mult = lerpf(player.speed_mult, target, clampf(delta * 3.0, 0.0, 1.0))
	else:
		player.speed_mult = 1.0
	_audio_t -= delta
	if _audio_t <= 0.0:
		_audio_t = 0.5
		_update_audio_zone()
	if Clock.now > Timetable.SERVICE_END + 1200.0 and state == State.PLAYING:
		_fail_journey("The last trains have gone. You didn't make it before the network closed for the night.")
		return
	var skip := Input.is_action_pressed("skip_time") and (riding or player.last_speed < 0.3)
	Clock.time_scale = 8.0 if (skip or bot_skip) else 1.0


func _refresh_dest_label() -> void:
	if journey["mode"] == "multi":
		var parts: Array = []
		for t in journey["targets"]:
			parts.append(("✔ " if t in journey["visited"] else "○ ") + Net.station_name(t))
		hud.dest_label.text = "Stops: " + "   ".join(parts)
	else:
		hud.dest_label.text = "To: %s" % Net.station_name(journey["dest"])


func _update_audio_zone() -> void:
	var dens := Clock.crowd_factor(Clock.now)
	if riding:
		var sp: float = ride.speed_now if ride else 0.0
		player.sway = clampf(sp / 12.0, 0.0, 1.6) * (0.0 if bool(Settings.get_v("access", "reduce_sway")) else 1.0)
		Sfx.set_zone("train_run" if sp > 1.0 else "train_idle", dens, sp)
		player.surface = "rubber"
		return
	player.sway = 0.0
	if station == null:
		return
	# inside a train at a platform?
	for v in station.trains.visits.values():
		if (v["train"] as Train).contains_world_point(player.global_position):
			Sfx.set_zone("train_idle", dens)
			announcer.tick("train_idle", dens, 0.5)
			player.surface = "rubber"
			return
	var loc := _describe_location()
	player.surface = "concrete"
	var zone := "corridor"
	if loc.begins_with("platform"):
		var open_air := false
		for m in station.modules:
			if (m as PlatformModule).open:
				open_air = true
		zone = "platform"
		Sfx.set_zone("platform_open" if open_air else "platform", dens)
	elif loc.begins_with("ticket hall"):
		zone = "hall"
		Sfx.set_zone("hall", dens)
	else:
		# on or near an escalator?
		var on_esc := false
		for e in station.escalators:
			var lp: Vector3 = (e as Node3D).to_local(player.global_position)
			if lp.x > -1.0 and lp.x < e.length + 1.0 and absf(lp.z) < e.width * 0.5 + 0.5 and lp.y > -e.rise - 2.5 and lp.y < 4.0:
				on_esc = true
		zone = "escalator" if on_esc else "corridor"
		Sfx.set_zone(zone, dens)
	announcer.tick(zone, dens, 0.5)


func _describe_location() -> String:
	if station == null:
		return ""
	var p := player.global_position
	for vv in station.trains.visits.values():
		if (vv["train"] as Train).contains_world_point(p):
			return "aboard the %s line train to %s" % [Net.line_name((vv["info"] as Dictionary)["line"]), Net.station_name((vv["info"] as Dictionary)["dest"])]
	for mi in station.modules.size():
		var m: PlatformModule = station.modules[mi]
		var lp := m.to_local(p)
		if absf(lp.x) < m.meta["length"] * 0.5 + 12.0 and absf(lp.z) < 9.0 and absf(lp.y) < 3.5:
			var mod: Dictionary = station.plan.modules[mi]
			for fd in mod["faces"]:
				var f: Dictionary = station.plan.faces["%s#%d" % [fd["pid"], fd["face"]]]
				if (f["side"] > 0.0 and lp.z > 1.5 and lp.z < 5.2) or (f["side"] < 0.0 and lp.z < -1.5 and lp.z > -5.2):
					return "platform %d, %s %s" % [station.plan.platform_no[fd["pid"]], station.plan.dir_text(fd["pid"]), Net.line_name(f["line"])]
			return "platform passages"
	var lp2 := station.to_local(p)
	if lp2.y > -1.0:
		for gl in station.plan.gatelines:
			var hr: Array = gl.get("rect", station.plan.hall["rect"])
			if lp2.x >= hr[0] - 0.5 and lp2.x <= hr[1] + 0.5 and lp2.z >= hr[2] - 0.5 and lp2.z <= hr[3] + 0.5:
				return "ticket hall (before the gates)" if lp2.z < gl["z"] else "ticket hall (paid area)"
		return "ticket hall (paid area)"
	return "below ground"


func _unhandled_input(ev: InputEvent) -> void:
	InputBindings.note_event(ev)
	# fixed keys: full screen, the performance overlay and log
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_F11:
				set_fullscreen(not is_fullscreen())
			KEY_ENTER, KEY_KP_ENTER:
				if ev.alt_pressed:
					set_fullscreen(not is_fullscreen())
			KEY_F3:
				hud.toggle_perf()
			KEY_F4:
				_toggle_fps_log()
	# everything else is an action (rebindable, keyboard or gamepad; see InputBindings)
	if ev.is_action_pressed("ui_accept", false, true) and state == State.BRIEFING and not (_settings != null and _settings.visible):
		_begin_play()
	elif ev.is_action_pressed("map", false, true):
		if state == State.PLAYING or state == State.BRIEFING:
			_toggle_map()
	elif ev.is_action_pressed("hint", false, true):
		if state == State.PLAYING:
			_toggle_hint()
	elif ev.is_action_pressed("map_mode", false, true):
		if map_open:
			map.toggle_mode()          # tube map: diagram <-> geographic
	elif ev.is_action_pressed("pause", false, true):
		if map_open:
			_toggle_map()
		elif state == State.PLAYING:
			_toggle_pause()


func _toggle_map() -> void:
	map_open = not map_open
	map.visible = map_open
	if journey.has("dest") and journey.get("mode", "single") == "single":
		map.dest = journey["dest"]
	map.stops = journey.get("targets", []).filter(func(t): return not (t in journey["visited"]))
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
		vb.add_child(_mk_button("Settings", func(): _open_settings(_pause)))
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
	if journey["mode"] == "multi":
		return _hint_multi()
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


func _hint_multi() -> String:
	var remaining: Array = journey["targets"].filter(func(t): return not (t in journey["visited"]))
	var s := ""
	if not par_result.is_empty() and par_result.get("ok", false):
		var names: Array = []
		for t in par_result["order"]:
			names.append(Net.station_name(t))
		s += "Best order from the start: " + " → ".join(names) + "\n"
	if riding or station == null:
		return s + "Remaining: " + ", ".join(remaining.map(func(t): return Net.station_name(t)))
	var plan := station.plan
	var best := "hall_unpaid"
	var bd := 1e9
	for n in plan.nodes:
		var d: float = (n["pos"] as Vector3).distance_to(station.to_local(player.global_position))
		if d < bd:
			bd = d
			best = n["name"]
	var all := Planner.plan_all(plan.idx, best, Clock.now, 2.5 * 3600.0)
	var nxt := -1
	var nt := INF
	for t in remaining:
		if all.get(t, INF) < nt:
			nt = all[t]
			nxt = t
	if nxt < 0:
		return s + "No remaining stop reachable."
	var res := Planner.plan(plan.idx, best, Clock.now, nxt)
	s += "Nearest remaining stop: %s (about %s)\n" % [Net.station_name(nxt), Clock.fmt_dur(nt - Clock.now)]
	if res.get("ok", false):
		for lg in res["legs"]:
			s += "• %s line towards %s — board at %s (%s), alight %s\n" % [Net.line_name(lg["line"]), Net.station_name(lg["dest"]), Net.station_name(lg["from"]), Clock.fmt(lg["dep"]), Net.station_name(lg["to"])]
	return s


# ---------------------------------------------------------------------------------------------------
# Trains: boarding / riding / alighting
# ---------------------------------------------------------------------------------------------------
func _on_doors_opened(v: Dictionary) -> void:
	var train: Train = v["train"]
	if station and train.contains_world_point(player.global_position):
		var info: Dictionary = v["info"]
		Sfx.say_station_this(station.plan.idx, info["line"])
		Sfx.say(["mind_the_gap"], false, true)
		Sfx.play_at("door_chime_open", train, Vector3(0, 1.8, 0), 0.0, 30.0)
		if info["final"]:
			Sfx.say(["this_train_terminates_here_all_change"])
	elif station and train.global_position.distance_to(player.global_position) < 40.0:
		Sfx.play_at("door_slide_open", train, Vector3(0, 1.5, 0), -6.0, 30.0)


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
	Sfx.play_at("door_chime_close", train, Vector3(0, 1.8, 0), 0.0, 30.0)
	if info["final"]:
		var pos := station.to_global(station.platform_point(v["key"], 0.5, 1.2))
		player.cancel_sit()
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
	Sfx.say(["stand_clear_of_the_doors"], true)
	Sfx.say_terminates(_ride_line, info["dest"], info["via"])
	Sfx.say_next(next_idx)
	Sfx.play_at("train_depart_platform", train, Vector3(0, 1.0, 0), -2.0, 60.0)


## Fall safety net: the last standing position can have lost its floor (e.g. it was inside a train that has left). Use it only while
## something solid is still under it, otherwise the nearest platform spot of the current station.
func _respawn_point(safe: Vector3) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(safe + Vector3(0, 0.6, 0), safe + Vector3(0, -1.5, 0))
	q.collision_mask = 1
	if not space.intersect_ray(q).is_empty() or station == null:
		return safe + Vector3(0, 0.3, 0)
	var best := safe + Vector3(0, 0.3, 0)
	var bd := 1e9
	for fk in station.plan.faces:
		var p: Vector3 = station.to_global(station.platform_point(fk, 0.5, 1.4))
		var d := p.distance_to(safe)
		if d < bd:
			bd = d
			best = p + Vector3(0, 0.3, 0)
	return best


## diagnostics for the fall-safety net: where in which station the floor was missing
func _on_player_fell(_from: Vector3, safe: Vector3) -> void:
	if station == null:
		push_warning("fell while no station is active (riding=%s)" % str(riding))
		return
	var lp := station.to_local(safe)
	var space := player.get_world_3d().direct_space_state
	var msg := "fell near %s station-local %s;" % [station.plan.name, str(lp.snapped(Vector3(0.1, 0.1, 0.1)))]
	for dx in [-1.5, -0.75, 0.0, 0.75, 1.5]:
		var from := safe + Vector3(dx, 0.5, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -3.0, 0))
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		msg += " dx%+.2f:%s" % [dx, ("floor@%.2f %s" % [hit["position"].y, (hit["collider"] as Node).get_parent().name]) if not hit.is_empty() else "NONE"]
	push_warning(msg)


func _on_ride_arrived(dest_station: Station, vkey: String) -> void:
	riding = false
	station = dest_station
	ride.queue_free()
	ride = null
	_hook_station(station)
	station.trains.player = player
	var info: Dictionary = (station.trains.visits[vkey] as Dictionary)["info"]
	Sfx.say_station_this(station.plan.idx, info["line"])
	if journey["mode"] == "single" and station.plan.idx == journey["dest"]:
		hud.toast("Your destination! Leave the train and follow the Way out signs.", 5.0)
	elif journey["mode"] == "multi" and station.plan.idx in journey["targets"] and not (station.plan.idx in journey["visited"]):
		hud.toast("One of your stops! Leave the train and follow the Way out signs.", 5.0)


func _on_street_exit(_door: String) -> void:
	if state != State.PLAYING or station == null:
		return
	var idx: int = station.plan.idx
	if journey["mode"] == "multi":
		if idx in journey["targets"] and not (idx in journey["visited"]):
			journey["visited"].append(idx)
			_refresh_dest_label()
			Sfx.play("ui_success_chime")
			if journey["visited"].size() >= journey["targets"].size():
				_finish_journey()
				return
			hud.toast("Stop reached: %s  (%d of %d)" % [station.plan.name, journey["visited"].size(), journey["targets"].size()], 4.5)
			_reenter()
		else:
			hud.toast("%s is not one of your remaining stops. Head back down." % station.plan.name, 4.0)
			player.global_position = station.to_global(station.to_local(player.global_position) + Vector3(0, 0, 3.0))
		return
	if idx == journey["dest"]:
		_finish_journey()
	else:
		hud.toast("That's not your destination — this is %s. Head back down to the platforms." % station.plan.name, 4.0)
		player.global_position = station.to_global(station.to_local(player.global_position) + Vector3(0, 0, 3.0))


## after a stop in multi-stop mode: step back in through the entrance (costs 25 s)
func _reenter() -> void:
	Clock.now += 25.0
	var sd: Dictionary = station.plan.street_doors[0]
	player.global_position = station.to_global(sd["pos"] + Vector3(0, 0.05, 1.8))
	player.velocity = Vector3.ZERO
	player.face(station.global_transform.basis * Vector3(0, 0, 1))


# ---------------------------------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------------------------------
func _finish_journey() -> void:
	state = State.RESULT
	Clock.running = false
	player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var elapsed: float = Clock.now - t_play0
	if journey["mode"] == "multi":
		if _par_task >= 0:
			WorkerThreadPool.wait_for_task_completion(_par_task)
		journey["par_s"] = par_result.get("duration", elapsed)
		journey["par"] = {"legs": []}
	var par: float = journey["par_s"]
	var score := clampf(par / maxf(elapsed, 1.0), 0.0, 1.0) * 100.0
	_result = _center_panel(760)
	var vb: VBoxContainer = _result.get_meta("vb")
	vb.add_child(_mk_label("JOURNEY COMPLETE", 40, Color(1, 0.85, 0.2), true))
	if journey["mode"] == "multi":
		var nms: Array = []
		for t in journey["targets"]:
			nms.append(Net.station_name(t))
		vb.add_child(_mk_label("%s → %s" % [Net.station_name(journey["start"]), " · ".join(nms)], 22, Color.WHITE, true))
	else:
		vb.add_child(_mk_label("%s → %s" % [Net.station_name(journey["start"]), Net.station_name(journey["dest"])], 26, Color.WHITE, true))
	vb.add_child(_mk_label("Your time: %s        Optimal: %s" % [Clock.fmt_dur(elapsed), Clock.fmt_dur(par)], 24, Color(0.6, 0.9, 1.0), true))
	vb.add_child(_mk_label("Score %d%%  —  %s" % [int(round(score)), Journey.rating(score)], 30, Color(1, 0.9, 0.4), true))
	vb.add_child(_mk_label("Walking %s · waiting %s · on trains %s · %d train%s · %d m on foot" % [Clock.fmt_dur(stats["walk"]), Clock.fmt_dur(stats["wait"]), Clock.fmt_dur(stats["ride"]), stats["transfers"], "" if stats["transfers"] == 1 else "s", int(stats["dist"])], 17, Color(0.8, 0.85, 0.95)))
	var route := "Fastest route:\n"
	if journey["mode"] == "multi" and par_result.get("ok", false):
		route = "Best order: " + " → ".join(par_result["order"].map(func(t): return Net.station_name(t))) + "\n"
	for lg in journey["par"]["legs"]:
		route += "• %s line: %s → %s  (%s–%s)\n" % [Net.line_name(lg["line"]), Net.station_name(lg["from"]), Net.station_name(lg["to"]), Clock.fmt(lg["dep"]), Clock.fmt(lg["arr"])]
	vb.add_child(_mk_label(route, 17, Color(0.85, 0.9, 1.0)))
	vb.add_child(_mk_button("New journey", func(): _result.queue_free(); _result = null; start_journey()))
	vb.add_child(_mk_button("Main menu", func(): _show_menu()))
	_save_score(score, elapsed)
	print("RESULT %s -> %s  time %s  par %s  score %d%%" % [Net.station_name(journey["start"]), Net.station_name(journey["dest"]) if journey["mode"] == "single" else "multi", Clock.fmt_dur(elapsed), Clock.fmt_dur(par), int(round(score))])
	if cli.has("autopilot") and cli.has("quit-when-done"):
		await get_tree().create_timer(float(cli.get("end-secs", "4.0"))).timeout
		get_tree().quit()


func _fail_journey(reason: String) -> void:
	state = State.RESULT
	Clock.running = false
	player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_result = _center_panel(700)
	var vb: VBoxContainer = _result.get_meta("vb")
	vb.add_child(_mk_label("JOURNEY ABANDONED", 40, Color(1, 0.5, 0.4), true))
	vb.add_child(_mk_label(reason, 22, Color.WHITE))
	vb.add_child(_mk_label("Elapsed: %s" % Clock.fmt_dur(Clock.now - t_play0), 20, Color(0.7, 0.8, 1.0)))
	vb.add_child(_mk_button("New journey", func(): _result.queue_free(); _result = null; start_journey()))
	vb.add_child(_mk_button("Main menu", func(): _show_menu()))


func _save_score(score: float, elapsed: float) -> void:
	var path := "user://scores.json"
	var arr: Array = []
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Array:
			arr = parsed
	arr.append({"score": score, "time": elapsed, "from": Net.station_name(journey["start"]), "to": (Net.station_name(journey["dest"]) if journey["mode"] == "single" else "multi-stop x%d" % journey["targets"].size()), "when": Time.get_datetime_string_from_system()})
	arr.sort_custom(func(a, b): return a["score"] > b["score"])
	arr = arr.slice(0, 20)
	var fw := FileAccess.open(path, FileAccess.WRITE)
	fw.store_string(JSON.stringify(arr))
