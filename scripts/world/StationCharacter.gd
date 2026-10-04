class_name StationCharacter
extends RefCounted
## Per-station finishes: the tile scheme, bands, giant tile lettering, ribs, pilasters and seat recesses of a deep-tube platform.
## Data lives in data/station_character.json (stations authored from reference photos, line defaults for the rest); the textures
## are made by tools/gen_char_textures.py.

const PATH := "res://data/station_character.json"
const PATH_EL := "res://data/station_character_el.json"         # the Elizabeth line's outer stations (tools/author_el_outer.py): merged into open_styles / surface_overrides
const DIR := "res://assets/textures/char/"
const GIANT_PPM := 300.0          # pixels per metre of the giant lettering textures (tools/gen_char_textures.py)

static var _data: Dictionary = {}
static var _loaded := false


static var _mx := Mutex.new()


## (plans are generated on worker threads too: the first caller parses, the others wait and see the finished data)
static func _load() -> void:
	if _loaded:
		return
	_mx.lock()
	if not _loaded:
		if FileAccess.file_exists(PATH):
			var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if d is Dictionary:
				_data = d
		if FileAccess.file_exists(PATH_EL):
			var e = JSON.parse_string(FileAccess.get_file_as_string(PATH_EL))
			if e is Dictionary:
				for k in ["open_styles", "surface_overrides"]:
					var tgt: Dictionary = _data.get(k, {})
					tgt.merge(e.get(k, {}), true)
					_data[k] = tgt
				for k in ["elizabeth_heathrow", "elizabeth_bored"]:
					if e.has(k):
						_data[k] = e[k]
		_loaded = true
	_mx.unlock()


## width and height of a PNG file from its header, (0, 0) when the source file is not there or is not a PNG
static func _png_size(path: String) -> Vector2i:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 24:
		return Vector2i.ZERO
	var b := f.get_buffer(24)
	if b[1] != 0x50 or b[2] != 0x4E or b[3] != 0x47:
		return Vector2i.ZERO
	return Vector2i((b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19], (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23])


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


## true when the platforms of `line_id` at this station are in a box (flat roof) rather than a curved tunnel: all sub-surface and surface stations, and of the Elizabeth line's core stations
## the ones whose platforms are boxes (Paddington, Canary Wharf, Custom House, Woolwich); Bond Street, Tottenham Court Road, Farringdon, Liverpool Street and Whitechapel are vaulted
static func platform_is_box(station_name: String, line_id: String, kind: String) -> bool:
	_load()
	if line_id == "elizabeth":
		return not (short_name(station_name) in _data.get("elizabeth_vault", []) or short_name(station_name) in _data.get("elizabeth_bored", []))
	return kind != "deep"


## "glass" for the skylit halls of surface stations, "flat" for a covered platform (the Heathrow stations of the Elizabeth line are underground though their Underground namesakes are at the surface)
static func platform_roof(station_name: String, line_id: String, kind: String) -> String:
	_load()
	if line_id == "elizabeth" and short_name(station_name) in _data.get("elizabeth_covered", []):
		return "flat"
	return "glass" if kind == "surface" else "flat"


## Finishes for one platform module (authored scheme, line default, or the generic one). Keys: wall, stripes, frieze, giant, ribs, pilasters, frame, recess.
static func platform(station_name: String, line_id: String, kind: String) -> Dictionary:
	_load()
	if _data.is_empty():
		return {}
	if line_id == "elizabeth":
		# the nine new stations of the central and south-east sections share one platform design ("kit of parts": full-height edge doors, panelled walls)
		if short_name(station_name) in _data.get("elizabeth_core", []):
			var el: Dictionary = (_data.get("lines", {}) as Dictionary).get("elizabeth", {})
			var lc: Array = el.get("light", [1, 1, 1])
			var vault: bool = short_name(station_name) in _data.get("elizabeth_vault", [])
			var out := {"wall": "el_panel" if vault else "el_dark", "stripes": _stripes(el.get("stripes", [])), "frieze": false, "station_slug": slug(station_name), "peds": true,
				"floor": String(el.get("floor", "floor_stone")), "light_color": Color(lc[0], lc[1], lc[2]), "el": true}
			if not vault:
				out["ceil"] = "concrete"                 # (the box stations: bare concrete soffit, dark bronze wall panels)
			return out
		# the Heathrow stations are underground: covered platforms (authored from photographs, tools/author_el_outer.py), not open air
		if short_name(station_name) in _data.get("elizabeth_covered", []):
			var hx: Dictionary = (_data.get("elizabeth_heathrow", {}) as Dictionary).get(short_name(station_name), {})
			if hx.is_empty():
				return _generic(station_name, line_id, "sub")
			var hout := {"wall": String(hx.get("wall", "tile_white")), "stripes": _stripes(hx.get("stripes", [])), "frieze": false, "station_slug": slug(station_name), "floor": String(hx.get("floor", "floor_slab"))}
			if hx.has("ceil"):
				hout["ceil"] = String(hx["ceil"])
			if hx.has("light"):
				var hl: Array = hx["light"]
				hout["light_color"] = Color(hl[0], hl[1], hl[2])
			if hx.has("ribs"):
				var rb: Dictionary = (hx["ribs"] as Dictionary).duplicate()
				rb["col"] = color(String(rb.get("ink", "grey_mid")))
				hout["ribs"] = rb
			return hout
		return _generic(station_name, line_id, "surface" if kind == "deep" else kind)
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
	if src.has("floor"):
		out["floor"] = String(src["floor"])
	if src.get("peds", false):
		out["peds"] = true
	if src.has("light"):
		var lc: Array = src["light"]
		out["light_color"] = Color(lc[0], lc[1], lc[2])
	for k in ["ribs", "pilasters", "frame"]:
		if src.has(k):
			var d: Dictionary = (src[k] as Dictionary).duplicate()
			d["col"] = color(String(d.get("ink", "grey_mid")))
			if d.has("cols"):
				var cc: Array = []
				for nme in d["cols"]:
					cc.append(color(String(nme)))
				d["cols"] = cc
			if d.has("edge"):
				d["edge_col"] = color(String(d["edge"]))
			out[k] = d
	if src.has("giant"):
		var g: Dictionary = src["giant"]
		var p := DIR + "giant/%s.png" % slug(station_name)
		if ResourceLoader.exists(p):
			# (the size from the PNG header: plans are built on worker threads, and loading a texture there raced the main thread's texture loads now and then)
			var sz := _png_size(p)
			if sz == Vector2i.ZERO:
				var t: Texture2D = load(p)
				sz = Vector2i(t.get_width(), t.get_height())
			out["giant"] = {"path": p, "w": sz.x / GIANT_PPM, "h": sz.y / GIANT_PPM}
	if line_id == "victoria":
		var mot: Dictionary = _data.get("victoria_motifs", {})
		if mot.has(station_name):
			out["recess"] = String(mot[station_name])
		else:
			out["recess"] = "plain"
	return out


## Space band list ({key, y0, y1}) from a stripes list, clipped to a room `h` metres high (corridors and passages carry the platform's bands)
static func stripe_bands(stripes: Array, h: float) -> Array:
	var out: Array = []
	for st in stripes:
		var y1: float = minf(st["y1"], h - 0.1)
		if st["y0"] >= y1:
			continue
		out.append({"key": ("dado:" if st.get("dado", false) else "flat:") + (st["color"] as Color).to_html(false), "y0": float(st["y0"]), "y1": y1})
	return out


## the open-air style of a surface (or open-cutting sub-surface) platform, "" for a covered one
static func open_style_name(station_name: String, line_id: String, kind: String) -> String:
	_load()
	var n := short_name(station_name)
	if kind == "deep":
		return ""
	var over: Dictionary = _data.get("surface_overrides", {})
	if over.has(n):
		return String(over[n])
	if kind == "sub" and not (n in _data.get("open_sub", [])):
		return ""
	return String((_data.get("surface_lines", {}) as Dictionary).get(line_id, "victorian" if kind == "sub" else "holden"))


static func _resolve_style(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	for k in ["col_main", "col_band", "col_ring", "fascia"]:
		if out.has(k):
			var a: Array = out[k]
			out[k] = Color(a[0], a[1], a[2])
	return out


## A platform with no authored scheme (sub-surface and surface lines, and any line without a default): an open-air platform (canopy, brick, sky) for surface stations,
## white glazed tile with a dark skirt and one band in the line's colour for covered sub-surface ones
static func _generic(station_name: String, line_id: String, kind: String) -> Dictionary:
	var ost := open_style_name(station_name, line_id, kind)
	if ost != "":
		var d: Dictionary = (_data.get("open_styles", {}) as Dictionary).get(ost, {})
		if not d.is_empty():
			var style := _resolve_style(d)
			return {"wall": String(d.get("wall", "brick_stock")), "stripes": [], "frieze": false, "station_slug": slug(station_name), "open": true, "open_style": style,
				"floor": String(d.get("floor", "floor_slab")), "light_color": Color(1.0, 0.96, 0.88)}
	var stripes: Array = [{"y0": 0.0, "y1": 0.25, "color": color("grey_dk"), "dado": true}, {"y0": 1.15, "y1": 1.42, "color": Net.line_color(line_id), "dado": false}]
	var out := {"wall": "tile_white", "stripes": stripes, "frieze": kind == "deep", "station_slug": slug(station_name)}
	if kind == "sub":
		# covered sub-surface platform (Temple, Mansion House, Euston Square ...): buff ceramic floor, tile-clad columns, a name fascia on the wall across the tracks
		out["floor"] = "floor_cream"
		out["frieze_far"] = true
		out["tile_cols"] = Net.line_color(line_id)
	return out


## Finishes of a ticket hall: {wall, floor, ceil, bands:[{key, y0, y1}]} (Space spec keys). Authored stations get their era's scheme, every other hall the default.
static func hall(station_name: String) -> Dictionary:
	_load()
	var types: Dictionary = _data.get("hall_types", {})
	if types.is_empty():
		return {}
	var ent = (_data.get("halls", {}) as Dictionary).get(station_name, "default")
	if short_name(station_name) in _data.get("jubilee_ext", []) and not (_data.get("halls", {}) as Dictionary).has(station_name):
		ent = "stone"          # the Jubilee Line Extension stations share one design (stone floors, stainless and panel walls)
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
	if t.has("light"):
		var lc: Array = t["light"]
		out["light_color"] = Color(lc[0], lc[1], lc[2])
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
