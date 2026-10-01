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
	print("OK" if ok else "FAILED")
