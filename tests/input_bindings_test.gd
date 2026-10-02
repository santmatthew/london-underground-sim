extends Node
## InputBindings: every action exists with its default keys and pad buttons, the Player reads movement and look from actions (keyboard or stick), rebinding swaps with whoever had the
## key, the settings are saved/restored and the prompt text follows the last device.
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func _has_key(action: String, key: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == key:
			return true
	return false


func _has_pad(action: String, button: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == button:
			return true
	return false


func run():
	InputBindings.reset()
	for a in InputBindings.ACTIONS:
		check(InputMap.has_action(a["id"]), "action %s exists" % a["id"])
	check(_has_key("interact", KEY_E) and _has_pad("interact", JOY_BUTTON_A), "interact: E and the A button")
	check(_has_key("move_forward", KEY_W) and _has_key("move_forward", KEY_UP), "walk forward: W and the up arrow")
	check(InputMap.has_action("look_left") and InputMap.has_action("zoom_in"), "stick look and map zoom actions exist")
	# the player reads actions
	var pl := Player.new()
	add_child(pl)
	Input.action_press("move_forward")
	var v: Vector2 = pl._read_keys()
	Input.action_release("move_forward")
	check(v.y < -0.9 and absf(v.x) < 0.01, "the Player walks forward on the move_forward action (%s)" % str(v))
	Input.action_press("move_left", 0.6)
	v = pl._read_keys()
	Input.action_release("move_left")
	check(v.x < -0.4, "analogue strength carries through (stick, %s)" % str(v))
	# rebinding swaps
	InputBindings.rebind_key("interact", KEY_F)
	check(InputBindings.key_of("interact") == KEY_F and _has_key("interact", KEY_F) and not _has_key("interact", KEY_E), "interact moved to F")
	InputBindings.rebind_key("map", KEY_F)
	check(InputBindings.key_of("map") == KEY_F and InputBindings.key_of("interact") == KEY_M, "binding map to F swaps: interact takes M")
	InputBindings.rebind_pad("hint", JOY_BUTTON_A)
	check(InputBindings.pad_of("hint") == JOY_BUTTON_A and InputBindings.pad_of("interact") == JOY_BUTTON_X, "a pad button swaps the same way")
	check(not (Settings.get_v("controls", "bindings") as Dictionary).is_empty(), "the overrides are in the settings (saved with them)")
	InputBindings.last_was_pad = false
	check(InputBindings.prompt("map") == InputBindings.key_text("map"), "prompts show the key while the keyboard is in use")
	InputBindings.note_event(InputEventJoypadButton.new())
	check(InputBindings.last_was_pad and InputBindings.prompt("hint") == "A", "and the button after a pad press")
	InputBindings.last_was_pad = false
	InputBindings.reset()
	check(_has_key("interact", KEY_E) and _has_key("map", KEY_M), "reset restores the defaults")
	pl.queue_free()
	print("OK" if ok else "FAILED")
