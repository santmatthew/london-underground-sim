class_name InputBindings
extends RefCounted
## Every control the game reads is an InputMap action defined here: keyboard + mouse + gamepad, with the keys and buttons the player can change (Settings > Controls; saved in
## Settings "controls/bindings"). `install()` is idempotent and applies the saved overrides; Player and Game ask `Input.is_action_*` / `Input.get_vector`, never raw keys.
## Fixed: mouse look, left stick = move, right stick = look, triggers = map zoom, F-keys, Alt+Enter. The text on prompts follows the last device used (`prompt(action)`).

# id, label, default key (physical keycode), alias key (fixed, not rebindable; 0 = none), default pad button (-1 none), fixed pad axis [axis, value] or []
const ACTIONS := [
	{"id": "move_forward", "label": "Walk forward", "key": KEY_W, "alias": KEY_UP, "pad": -1, "axis": [JOY_AXIS_LEFT_Y, -1.0]},
	{"id": "move_back", "label": "Walk back", "key": KEY_S, "alias": KEY_DOWN, "pad": -1, "axis": [JOY_AXIS_LEFT_Y, 1.0]},
	{"id": "move_left", "label": "Step left", "key": KEY_A, "alias": KEY_LEFT, "pad": -1, "axis": [JOY_AXIS_LEFT_X, -1.0]},
	{"id": "move_right", "label": "Step right", "key": KEY_D, "alias": KEY_RIGHT, "pad": -1, "axis": [JOY_AXIS_LEFT_X, 1.0]},
	{"id": "hurry", "label": "Hurry (hold)", "key": KEY_SHIFT, "alias": 0, "pad": JOY_BUTTON_RIGHT_SHOULDER, "axis": []},
	{"id": "sprint", "label": "Run (with Hurry)", "key": KEY_CTRL, "alias": 0, "pad": JOY_BUTTON_LEFT_SHOULDER, "axis": []},
	{"id": "interact", "label": "Use / sit down", "key": KEY_E, "alias": 0, "pad": JOY_BUTTON_A, "axis": []},
	{"id": "map", "label": "Tube map", "key": KEY_M, "alias": 0, "pad": JOY_BUTTON_Y, "axis": []},
	{"id": "map_mode", "label": "Map: diagram / geographic", "key": KEY_G, "alias": 0, "pad": JOY_BUTTON_B, "axis": []},
	{"id": "hint", "label": "Route hints", "key": KEY_H, "alias": 0, "pad": JOY_BUTTON_X, "axis": []},
	{"id": "skip_time", "label": "Skip waiting (hold)", "key": KEY_TAB, "alias": 0, "pad": JOY_BUTTON_RIGHT_STICK, "axis": []},
	{"id": "pause", "label": "Pause / back", "key": KEY_ESCAPE, "alias": 0, "pad": JOY_BUTTON_START, "axis": []},
]
# actions that only have fixed axis bindings: the right stick looks, the triggers zoom the map
const AXIS_ACTIONS := {
	"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0], "look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"zoom_in": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "zoom_out": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}
const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L-stick", JOY_BUTTON_RIGHT_STICK: "R-stick", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}

static var last_was_pad := false
static var _installed := false


static func def_of(id: String) -> Dictionary:
	for a in ACTIONS:
		if a["id"] == id:
			return a
	return {}


## the saved override for an action: {"key": code, "pad": button} (either may be missing)
static func _override(id: String) -> Dictionary:
	return (Settings.get_v("controls", "bindings") as Dictionary).get(id, {})


static func key_of(id: String) -> int:
	var o := _override(id)
	if o.has("key"):
		return int(o["key"])
	return int(def_of(id).get("key", 0))


static func pad_of(id: String) -> int:
	var o := _override(id)
	if o.has("pad"):
		return int(o["pad"])
	return int(def_of(id).get("pad", -1))


## define the actions (once) and apply the saved bindings; call again after any change
static func install() -> void:
	for a in ACTIONS:
		var id: String = a["id"]
		_reset_action(id)
		var kc := key_of(id)
		if kc > 0:
			var ev := InputEventKey.new()
			ev.physical_keycode = kc as Key
			InputMap.action_add_event(id, ev)
		if int(a["alias"]) > 0:
			var ev2 := InputEventKey.new()
			ev2.physical_keycode = int(a["alias"]) as Key
			InputMap.action_add_event(id, ev2)
		var pb := pad_of(id)
		if pb >= 0:
			var jb := InputEventJoypadButton.new()
			jb.button_index = pb as JoyButton
			InputMap.action_add_event(id, jb)
		var axis: Array = a["axis"]
		if not axis.is_empty():
			var jm := InputEventJoypadMotion.new()
			jm.axis = int(axis[0]) as JoyAxis
			jm.axis_value = float(axis[1])
			InputMap.action_add_event(id, jm)
	for id2 in AXIS_ACTIONS:
		_reset_action(id2)
		var jm2 := InputEventJoypadMotion.new()
		jm2.axis = int(AXIS_ACTIONS[id2][0]) as JoyAxis
		jm2.axis_value = float(AXIS_ACTIONS[id2][1])
		InputMap.action_add_event(id2, jm2)
	_apply_deadzone()
	if not _installed:
		_installed = true
		Settings.changed.connect(func(sec, key):
			if sec == "controls" and key == "stick_deadzone":
				_apply_deadzone())


static func _reset_action(id: String) -> void:
	if InputMap.has_action(id):
		InputMap.action_erase_events(id)
	else:
		InputMap.add_action(id, 0.5)


static func _apply_deadzone() -> void:
	var dz := float(Settings.get_v("controls", "stick_deadzone"))
	for a in ACTIONS:
		if not (a["axis"] as Array).is_empty():
			InputMap.action_set_deadzone(a["id"], dz)
	for id in AXIS_ACTIONS:
		InputMap.action_set_deadzone(id, dz)


static func key_text(id: String) -> String:
	var kc := key_of(id)
	if kc <= 0:
		return "(none)"
	var shown := DisplayServer.keyboard_get_keycode_from_physical(kc as Key) if DisplayServer.get_name() != "headless" else (kc as Key)
	return OS.get_keycode_string(shown if shown != KEY_NONE else (kc as Key))


static func pad_text(id: String) -> String:
	var d := def_of(id)
	var pb := pad_of(id)
	if pb < 0:
		var axis: Array = d.get("axis", [])
		return "Left stick" if not axis.is_empty() else "(none)"
	return String(PAD_NAMES.get(pb, "Button %d" % pb))


## the text for a prompt ("E", "A"): the key or the pad button, whichever device was used last
static func prompt(id: String) -> String:
	if last_was_pad:
		var p := pad_text(id)
		if p != "(none)":
			return p
	return key_text(id)


static func rebind_key(id: String, keycode: int) -> void:
	_rebind(id, "key", keycode)


static func rebind_pad(id: String, button: int) -> void:
	_rebind(id, "pad", button)


static func _rebind(id: String, kind: String, code: int) -> void:
	var all: Dictionary = (Settings.get_v("controls", "bindings") as Dictionary).duplicate(true)
	var mine: int = key_of(id) if kind == "key" else pad_of(id)
	# a key or button can only do one thing: whoever had it gets the old one of this action (a swap)
	for a in ACTIONS:
		var other: String = a["id"]
		if other == id:
			continue
		var cur: int = key_of(other) if kind == "key" else pad_of(other)
		if cur == code:
			var o: Dictionary = all.get(other, {})
			o[kind] = mine
			all[other] = o
	var o2: Dictionary = all.get(id, {})
	o2[kind] = code
	all[id] = o2
	Settings.set_v("controls", "bindings", all)
	install()


static func reset() -> void:
	Settings.set_v("controls", "bindings", {})
	install()


## call from an input handler: remembers which device the player is using (for prompts)
static func note_event(ev: InputEvent) -> void:
	if ev is InputEventJoypadButton or (ev is InputEventJoypadMotion and absf((ev as InputEventJoypadMotion).axis_value) > 0.5):
		last_was_pad = true
	elif ev is InputEventKey or ev is InputEventMouseButton or (ev is InputEventMouseMotion and (ev as InputEventMouseMotion).relative.length() > 2.0):
		last_was_pad = false
