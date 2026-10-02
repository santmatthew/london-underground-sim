extends Node
## Screenshots of the Tube map in the standard colours and for deuteranopia / tritanopia (needs a display: tools/shot.sh res://tests/runner.tscn -- --test=access_shot_test).
func run():
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {"seed": "5"}
	add_child(g)
	await get_tree().process_frame
	g.start_journey()
	while g.state != Game.State.BRIEFING:
		await get_tree().process_frame
	g._begin_play()
	for i in 10:
		await get_tree().process_frame
	g._toggle_map()
	for kind in ["standard", "deuteranopia", "tritanopia"]:
		Settings.set_v("access", "colour_vision", kind, false)
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://build/map_%s.png" % kind)
	Settings.set_v("access", "colour_vision", "standard", false)
	print("OK")
