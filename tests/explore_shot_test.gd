extends Node
## Screenshots of the explore setup screen and of an explore session (needs a display: tools/shot.sh res://tests/runner.tscn -- --test=explore_shot_test)
func run():
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {"seed": "5"}
	add_child(g)
	for i in 8:
		await get_tree().process_frame
	g._menu.visible = true
	get_viewport().get_texture().get_image().save_png("res://build/explore_menu.png")
	g._open_explore(g._menu)
	g._explore._search.text = "king"
	g._explore._fill()
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/explore_setup.png")
	g._explore._search.text = ""
	g._explore.station = Net.name_to_idx["Kennington"]
	g._explore._fill()
	g._explore._pick_station()
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/explore_setup2.png")
	g.start_explore({"station": Net.name_to_idx["Covent Garden"], "spot": 0, "hour": 10.0, "day": "weekday"})
	var t0 := Time.get_ticks_msec()
	while g.state != Game.State.PLAYING and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	for i in 60:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/explore_play.png")
	print("OK")
