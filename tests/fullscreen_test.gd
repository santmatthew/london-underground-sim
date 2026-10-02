extends Node
## Full screen: the menu check box and set_fullscreen() agree, the choice is saved to user://settings.cfg, and --windowed beats a saved "on".
## (A headless run has no window, so the display mode itself is not exercised here: see tools/shot.sh under xvfb for the real thing.)
var ok := true


func check(cond: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		ok = false


func run():
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {}
	add_child(g)
	await get_tree().process_frame
	check(g._cb_fullscreen != null, "the menu has a Full screen check box")
	var was := g.is_fullscreen()
	print("  window mode now: ", DisplayServer.window_get_mode(), " (display ", DisplayServer.get_name(), ")")
	if DisplayServer.get_name() != "headless":
		g.set_fullscreen(true)
		await get_tree().process_frame
		await get_tree().process_frame
		check(g.is_fullscreen(), "set_fullscreen(true) puts the window in full screen")
		check(g._cb_fullscreen.button_pressed, "the check box follows")
		var cf := ConfigFile.new()
		check(cf.load(Game.SETTINGS_PATH) == OK and bool(cf.get_value("display", "fullscreen", false)), "the choice is saved")
		var ev := InputEventKey.new()
		ev.keycode = KEY_F11
		ev.pressed = true
		g._unhandled_input(ev)
		await get_tree().process_frame
		await get_tree().process_frame
		check(not g.is_fullscreen(), "F11 leaves full screen")
		check(not g._cb_fullscreen.button_pressed, "the check box follows again")
		g.set_fullscreen(was)
	# upscaler option: FSR 1 by default, FSR 2 when chosen (only matters below 100 % render scale), saved and shown in the menu
	check(g._ob_upscaler != null, "the menu has an Upscaler option")
	g.opts["scale"] = 0.67
	g.set_upscaler("fsr1")
	check(get_viewport().scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR, "FSR 1 selected: viewport uses FSR 1")
	g.set_upscaler("fsr2")
	check(get_viewport().scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2, "FSR 2 selected: viewport uses FSR 2")
	check(g._ob_upscaler.selected == 1, "the menu option follows")
	var cf2 := ConfigFile.new()
	check(cf2.load(Game.SETTINGS_PATH) == OK and String(cf2.get_value("display", "upscaler", "")) == "fsr2", "the upscaler choice is saved")
	g.opts["scale"] = 1.0
	g._apply_settings()
	check(get_viewport().scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "at 100% render scale no upscaler is used")
	g.set_upscaler("fsr1")
	g.opts["scale"] = 0.0
	g._apply_settings()
	# anti-aliasing option and the Fast tier
	check(g._ob_aa != null, "the menu has an Anti-aliasing option")
	g.set_aa("fxaa")
	check(get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA and not get_viewport().use_taa, "FXAA selected: FXAA on, TAA off")
	g.set_aa("off")
	check(get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED and not get_viewport().use_taa, "AA off: both off")
	g.set_aa("taa")
	check(get_viewport().use_taa and get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "TAA selected: TAA on")
	var cf3 := ConfigFile.new()
	check(cf3.load(Game.SETTINGS_PATH) == OK and String(cf3.get_value("display", "aa", "")) == "taa", "the AA choice is saved")
	g.opts["quality"] = 0
	g._apply_settings()
	check(not g.env.environment.ssao_enabled and not g.env.environment.glow_enabled, "Fast tier: no ambient occlusion, no glow")
	g.opts["quality"] = 1
	g._apply_settings()
	check(g.env.environment.ssao_enabled and g.env.environment.glow_enabled, "Balanced tier: both on")
	print("OK" if ok else "FAILED")
