extends Node
## Screenshots of the settings screen, one per tab (needs a display: tools/shot.sh res://tests/runner.tscn -- --test=settings_shot_test).
func run():
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {}
	add_child(g)
	for i in 6:
		await get_tree().process_frame
	g._menu.visible = true
	g._open_settings(g._menu)
	await get_tree().process_frame
	var tabs: TabContainer = g._settings._tabs
	for t in tabs.get_tab_count():
		tabs.current_tab = t
		for i in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://build/settings_%d.png" % t)
	print("OK")
