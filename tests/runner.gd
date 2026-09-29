extends Node
## Usage: godot --headless --path . res://tests/runner.tscn -- --test=test_timetable
## The test script must `extends Node` and implement `func run()` (may await).
func _ready() -> void:
	var name := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			name = a.substr(7)
	var script = load("res://tests/%s.gd" % name)
	if script == null or not script.can_instantiate():
		push_error("test script failed to load: " + name)
		get_tree().quit(1)
		return
	var t: Node = script.new()
	add_child(t)
	await t.run()
	get_tree().quit()
