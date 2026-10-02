extends Node
## Player settings that are not render options: audio, accessibility and controls. Saved in user://settings.cfg (sections "audio", "access", "controls"; the display options
## Game keeps live in "display" of the same file). `Settings.get_v("audio", "master")`, `Settings.set_v(...)` (saves, emits `changed`). Autoload name: Settings.
## `--colour-vision=<kind>` / `--step-free` on the command line override the saved values for one run.

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"
var path := PATH                 # tests run with UG_SETTINGS=user://something_else.cfg (tools/gtest.sh does) so they never touch the player's real settings

const DEFAULTS := {
	"audio": {
		"master": 0.8,           # 0..1
		"effects": 1.0,          # doors, gates, footsteps, trains
		"ambience": 1.0,         # station beds, crowds, wind
		"announcements": 1.0,    # PA and driver
		"announce_on": true,     # the PA / driver speak at all
		"pa_chatter": true,      # periodic safety messages (mind the gap ...) on top of the train announcements
		"subtitles": true,       # announcements shown as text
		"subtitle_size": 1.0,    # 0.8 .. 1.6 times the normal size
	},
	"access": {
		"colour_vision": "standard",   # standard | deuteranopia | protanopia | tritanopia (Palette)
		"step_free": false,            # journeys, routes and station fittings that need no stairs or escalators
		"reduce_sway": false,          # no camera sway in trains and on escalators
		"text_scale": 1.0,             # HUD text
	},
	"controls": {
		"sens": 0.0022,          # mouse look, radians per pixel
		"stick_sens": 2.6,       # right stick, radians per second at full deflection
		"stick_deadzone": 0.2,
		"invert_y": false,
		"bindings": {},          # action -> {"key": keycode, "pad": button index} overrides (InputBindings)
	},
}

var _data: Dictionary = {}
var _cli: Dictionary = {}


func _ready() -> void:
	if OS.has_environment("UG_SETTINGS"):
		path = OS.get_environment("UG_SETTINGS")
	_load()
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		_cli[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _load() -> void:
	_data = DEFAULTS.duplicate(true)
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	for sec in DEFAULTS:
		for k in DEFAULTS[sec]:
			if cf.has_section_key(sec, k):
				var v = cf.get_value(sec, k)
				# keep the default's type (a hand-edited file must not break the game)
				if typeof(v) == typeof(DEFAULTS[sec][k]) or (typeof(DEFAULTS[sec][k]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
					_data[sec][k] = v


func get_v(section: String, key: String):
	if section == "access":
		if key == "colour_vision" and _cli.has("colour-vision"):
			return String(_cli["colour-vision"])
		if key == "step_free" and _cli.has("step-free"):
			return true
	return _data.get(section, {}).get(key, DEFAULTS.get(section, {}).get(key))


func set_v(section: String, key: String, value, save := true) -> void:
	if not DEFAULTS.has(section) or not DEFAULTS[section].has(key):
		push_warning("Settings: unknown setting %s/%s" % [section, key])
		return
	if _data[section][key] == value:
		return
	_data[section][key] = value
	if save:
		save_all()
	changed.emit(section, key)


## the saved file keeps the sections other code wrote ("display"); only ours are replaced
func save_all() -> void:
	var cf := ConfigFile.new()
	cf.load(path)
	for sec in DEFAULTS:
		for k in DEFAULTS[sec]:
			cf.set_value(sec, k, _data[sec][k])
	cf.save(path)


func reset_section(section: String) -> void:
	if not DEFAULTS.has(section):
		return
	for k in DEFAULTS[section]:
		set_v(section, k, DEFAULTS[section][k].duplicate(true) if DEFAULTS[section][k] is Dictionary else DEFAULTS[section][k], false)
	save_all()
