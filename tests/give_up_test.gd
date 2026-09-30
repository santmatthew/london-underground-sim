extends Node
## Pause -> "Give up (main menu)" must leave ONLY the main menu on screen (no stale pause panel), with Quit reachable, and a new journey must start.
func _visible_panels(g: Game) -> int:
	var n := 0
	for c in g._ui.get_children():
		if c is CenterContainer and (c as CenterContainer).visible:
			n += 1
	return n


func _find_button(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(text):
			return b as Button
	return null


func run():
	var g: Game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	g.cli = {}
	add_child(g)
	await get_tree().process_frame
	g.cli["seed"] = "5"
	g.start_journey()
	while g.state != Game.State.BRIEFING:
		await get_tree().process_frame
	g._begin_play()
	for i in 20: await get_tree().process_frame
	g._toggle_pause()
	await get_tree().process_frame
	print("paused: panels visible = ", _visible_panels(g), " state = ", g.state)
	var b := _find_button(g._pause, "Give up")
	print("give-up button found: ", b != null)
	b.pressed.emit()
	for i in 6: await get_tree().process_frame
	var panels := _visible_panels(g)
	var quit := _find_button(g._menu, "Quit")
	print("after give up: state = ", g.state, " (", Game.State.MENU, " = MENU) panels visible = ", panels, " pause panel = ", g._pause, " menu visible = ", g._menu.visible, " quit button = ", quit != null, " paused = ", g.paused)
	var ok := g.state == Game.State.MENU and panels == 1 and g._pause == null and g._menu.visible and quit != null and not g.paused
	# a new journey must start from there
	g.cli["seed"] = "6"
	g.start_journey()
	var guard := 0
	while g.state != Game.State.BRIEFING and guard < 600:
		await get_tree().process_frame
		guard += 1
	print("new journey reaches the briefing: ", g.state == Game.State.BRIEFING)
	ok = ok and g.state == Game.State.BRIEFING
	print("OK" if ok else "FAILED")
