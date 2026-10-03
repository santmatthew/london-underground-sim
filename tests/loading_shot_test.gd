extends Node
## The loading message at the start of a journey (screenshot, needs a window: tools/shot.sh res://tests/runner.tscn -- --test=loading_shot_test): one centred line, readable.
func run():
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(g)
	await get_tree().process_frame
	g.start_journey()
	for i in 4:
		await get_tree().process_frame
	var l: Label = g._loading
	print("loading label: ", l.text if l else "none", " size ", l.size if l else "-", " lines ", l.get_line_count() if l else 0)
	get_viewport().get_texture().get_image().save_png("res://build/loading.png")
