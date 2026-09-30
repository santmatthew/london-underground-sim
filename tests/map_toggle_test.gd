extends Node
## The tube map inside the real game: opens on the diagram, G switches to the geographic map and back, no script errors.
func run():
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {}
	add_child(g)
	await get_tree().process_frame
	g.cli["seed"] = "5"
	g.start_journey()
	while g.state != Game.State.BRIEFING:
		await get_tree().process_frame
	print("map diagram data loaded: ", g.map._dia_ok, "  default mode: ", g.map.mode, " (0 = diagram)  stations with positions: ", g.map._dp.size(), "  edges: ", g.map._dedges.size())
	g._begin_play()
	for i in 20: await get_tree().process_frame
	g._toggle_map()
	print("open: visible=", g.map.visible, " mode=", g.map.mode)
	var ev := InputEventKey.new()
	ev.keycode = KEY_G
	ev.pressed = true
	g._unhandled_input(ev)
	print("after G: mode=", g.map.mode, " (1 = geographic)")
	g._unhandled_input(ev)
	print("after G again: mode=", g.map.mode)
	g._toggle_map()
	print("closed: visible=", g.map.visible)
	print("OK")
