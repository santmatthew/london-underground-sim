class_name RealData
extends RefCounted
## Real-world facts about the stations, digested by tools/fetch_station_real.py (TfL open data + OpenStreetMap, see CREDITS.md) and
## tools/fetch_platform_numbers.py (TfL live arrivals). Everything here is optional: a station without data keeps the generated values.

const STATIONS := "res://data/stations_real.json"
const PLATFORM_NUMBERS := "res://data/platform_numbers.json"
const LAYOUTS := "res://data/station_layouts.json"

static var _stations: Dictionary = {}
static var _numbers: Dictionary = {}
static var _layouts: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	for pair in [[STATIONS, "_stations"], [PLATFORM_NUMBERS, "_numbers"], [LAYOUTS, "_layouts"]]:
		if FileAccess.file_exists(pair[0]):
			var f := FileAccess.open(pair[0], FileAccess.READ)
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				match pair[1]:
					"_stations":
						_stations = parsed
					"_numbers":
						_numbers = parsed
					_:
						_layouts = parsed


## digest for a NaPTAN id, or {}
static func station(naptan: String) -> Dictionary:
	_load()
	return _stations.get(naptan, {})


## authored/measured layout facts for a station (depths in metres below street level per line group, ...), or {}
static func layout(naptan: String) -> Dictionary:
	_load()
	return _layouts.get(naptan, {})


## authored layout spec (data/layouts/<naptan>.json, see LayoutCompiler), or {}
static func layout_spec(naptan: String) -> Dictionary:
	var path := "res://data/layouts/%s.json" % naptan
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## real platform number for (line, direction) at a station, 0 if unknown
static func platform_number(naptan: String, line: String, direction: String) -> int:
	_load()
	var d: Dictionary = _numbers.get(naptan, {})
	var lst: Array = d.get("%s|%s" % [line, direction], [])
	if lst.is_empty():
		return 0
	var best := 1 << 30
	for n in lst:
		best = mini(best, int(n))
	return best


## entrances usable as street doors, sorted by their real exit number ({ref, name, exit_only})
static func entrances(naptan: String) -> Array:
	var out: Array = []
	for e in station(naptan).get("entrances", []):
		# OSM's search radius also catches neighbouring stations' entrances: keep only what is close to this station's centre
		if Vector2(float(e.get("e", 0.0)), float(e.get("n", 0.0))).length() > 130.0:
			continue
		if str(e.get("ref", "")) != "" or str(e.get("name", "")) != "":
			out.append(e)
	out.sort_custom(func(a, b):
		var ra := int(str(a.get("ref", "0")).to_int())
		var rb := int(str(b.get("ref", "0")).to_int())
		if ra != rb:
			return ra < rb
		return str(a.get("name", "")) < str(b.get("name", "")))
	return out


## "Exit 4, Oxford Street - West / Regent Street - North" -> "Oxford Street West / Regent Street North"
static func street_of(entrance: Dictionary) -> String:
	var n := str(entrance.get("name", ""))
	var comma := n.find(", ")
	if n.begins_with("Exit") and comma >= 0:
		n = n.substr(comma + 2)
	return n.replace(" - ", " ")
