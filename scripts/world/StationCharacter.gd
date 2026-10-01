class_name StationCharacter
extends RefCounted
## Per-station finishes: the tile scheme, bands, giant tile lettering, ribs, pilasters and seat recesses of a deep-tube platform.
## Data lives in data/station_character.json (stations authored from reference photos, line defaults for the rest); the textures
## are made by tools/gen_char_textures.py.

const PATH := "res://data/station_character.json"
const DIR := "res://assets/textures/char/"
const GIANT_PPM := 300.0          # pixels per metre of the giant lettering textures (tools/gen_char_textures.py)

static var _data: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			_data = d


static func short_name(n: String) -> String:
	var i := n.find(" (")
	return n.substr(0, i) if i >= 0 else n


static func slug(n: String) -> String:
	var s := ""
	var last_us := true
	for ch in short_name(n).to_lower():
		var c: String = ch
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			s += c
			last_us = false
		elif not last_us:
			s += "_"
			last_us = true
	return s.trim_suffix("_")


static func color(pal: String) -> Color:
	_load()
	var a: Array = (_data.get("palette", {}) as Dictionary).get(pal, [0.5, 0.5, 0.5])
	return Color(a[0], a[1], a[2])


static func _stripes(arr: Array) -> Array:
	var out: Array = []
	for s in arr:
		out.append({"y0": float(s[0]), "y1": float(s[1]), "color": color(String(s[2])), "dado": int(s[3]) == 1})
	return out


## Finishes for one platform module (authored scheme, line default, or the generic one). Keys: wall, stripes, frieze, giant, ribs, pilasters, frame, recess.
static func platform(station_name: String, line_id: String, kind: String) -> Dictionary:
	_load()
	if _data.is_empty():
		return {}
	if kind != "deep":
		return _generic(station_name, line_id, kind)
	var stations: Dictionary = _data.get("stations", {})
	var lines: Dictionary = _data.get("lines", {})
	var key := "%s|%s" % [station_name, line_id]
	var src: Dictionary = {}
	if stations.has(key):
		src = stations[key]
	else:
		var lk := line_id
		if line_id == "jubilee" and short_name(station_name) in _data.get("jubilee_ext", []):
			lk = "jubilee_ext"
		if lines.has(lk):
			src = lines[lk]
	if src.is_empty():
		return _generic(station_name, line_id, kind)
	var out := {"wall": String(src.get("wall", "tile_white")), "stripes": _stripes(src.get("stripes", [])), "frieze": true, "station_slug": slug(station_name)}
	for k in ["ribs", "pilasters", "frame"]:
		if src.has(k):
			var d: Dictionary = (src[k] as Dictionary).duplicate()
			d["col"] = color(String(d.get("ink", "grey_mid")))
			if d.has("edge"):
				d["edge_col"] = color(String(d["edge"]))
			out[k] = d
	if src.has("giant"):
		var g: Dictionary = src["giant"]
		var p := DIR + "giant/%s.png" % slug(station_name)
		if ResourceLoader.exists(p):
			var t: Texture2D = load(p)
			out["giant"] = {"path": p, "w": t.get_width() / GIANT_PPM, "h": t.get_height() / GIANT_PPM}
	if line_id == "victoria":
		var mot: Dictionary = _data.get("victoria_motifs", {})
		if mot.has(station_name):
			out["recess"] = String(mot[station_name])
		else:
			out["recess"] = "plain"
	return out


## A platform with no authored scheme (sub-surface and surface lines, and any line without a default): white glazed tile, a dark skirt and one band in the line's colour
static func _generic(station_name: String, line_id: String, kind: String) -> Dictionary:
	var stripes: Array = [{"y0": 0.0, "y1": 0.25, "color": color("grey_dk"), "dado": true}, {"y0": 1.15, "y1": 1.42, "color": Net.line_color(line_id), "dado": false}]
	return {"wall": "tile_white", "stripes": stripes, "frieze": kind == "deep", "station_slug": slug(station_name)}


## Finishes of a ticket hall: {wall, floor, ceil, bands:[{key, y0, y1}]} (Space spec keys). Authored stations get their era's scheme, every other hall the default.
static func hall(station_name: String) -> Dictionary:
	_load()
	var types: Dictionary = _data.get("hall_types", {})
	if types.is_empty():
		return {}
	var ent = (_data.get("halls", {}) as Dictionary).get(station_name, "default")
	var tname := "default"
	var over: Dictionary = {}
	if ent is Dictionary:
		tname = String(ent.get("type", "default"))
		over = ent
	else:
		tname = String(ent)
	var t: Dictionary = types.get(tname, types["default"])
	var out := {"wall": String(t["wall"]), "floor": String(t["floor"]), "ceil": String(t["ceil"])}
	if over.has("floor"):
		out["floor"] = String(over["floor"])
	var bands: Array = []
	for b in over.get("bands", t.get("bands", [])):
		var col := color(String(b[2]))
		bands.append({"key": ("dado:" if int(b[3]) == 1 else "flat:") + col.to_html(false), "y0": float(b[0]), "y1": float(b[1])})
	out["bands"] = bands
	return out


static var _mats: Dictionary = {}


## Material for a quad textured with a character texture: key "char:<path under assets/textures/char>|<w m>|<h m>|<alpha 0/1>" (UVs are metres, as in MeshKit)
static func material(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var parts := key.substr(5).split("|")
	var m := StandardMaterial3D.new()
	var p := DIR + parts[0]
	if ResourceLoader.exists(p):
		m.albedo_texture = load(p)
	m.roughness = 0.35
	if parts.size() > 3 and parts[3] == "1":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.45
		m.roughness = 0.2          # glazed tile
	m.uv1_scale = Vector3(1.0 / float(parts[1]), 1.0 / float(parts[2]), 1.0)
	_mats[key] = m
	return m
