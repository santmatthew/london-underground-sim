class_name Palette
extends RefCounted
## Line colours for the player's colour vision (Settings access/colour_vision: standard, protanopia, deuteranopia, tritanopia). The alternative palettes are computed by
## tools/gen_cvd_palettes.py (data/line_palettes.json): the closest two lines are at least ~26 CIELAB units apart as that player sees them, the brand colours move as little as that allows.
## Net.line_color asks here; things built from it (signs, trains, wall maps) pick the change up from the next station build, the live Tube map at once.

const PATH := "res://data/line_palettes.json"

static var _data: Dictionary = {}
static var _loaded := false
static var _cache: Dictionary = {}


static func kinds() -> Array:
	_load()
	var out: Array = ["standard"]
	for k in _data:
		if not String(k).begins_with("_"):
			out.append(k)
	return out


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			_data = d


static func line_color(lid: String, base: Color) -> Color:
	var kind := String(Settings.get_v("access", "colour_vision"))
	if kind == "standard":
		return base
	_load()
	var key := kind + "/" + lid
	if _cache.has(key):
		return _cache[key]
	var h = (_data.get(kind, {}) as Dictionary).get(lid, "")
	var c: Color = Color.html(String(h)) if String(h) != "" else base
	_cache[key] = c
	return c
