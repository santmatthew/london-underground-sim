extends Node
## London Underground network data (data/network.json, built by tools/build_network.py).
## Stations are addressed by integer index everywhere in hot code; `station_ids[idx]` gives the NaPTAN id.

var lines: Dictionary = {}          # line id -> {name, color:Color, group, services:[...]}
var line_ids: Array = []            # stable ordering
var stations: Array = []            # idx -> station dict (with "id","idx")
var station_ids: Array = []         # idx -> id string
var id_to_idx: Dictionary = {}      # id -> idx
var name_to_idx: Dictionary = {}    # display name -> idx
var links: Array = []               # [{a:idx,b:idx,walk_s}]
var loaded := false


func _ready() -> void:
	load_data()


func load_data() -> void:
	if loaded:
		return
	var f := FileAccess.open("res://data/network.json", FileAccess.READ)
	assert(f != null, "data/network.json missing - run tools/build_network.py")
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	for lid in d["lines"]:
		var l: Dictionary = d["lines"][lid]
		l["color"] = Color.html(l["color"])
		l["id"] = lid
		lines[lid] = l
	line_ids = ["bakerloo", "central", "circle", "district", "hammersmith-city", "jubilee", "metropolitan", "northern", "piccadilly", "victoria", "waterloo-city", "elizabeth"]
	var sids: Array = d["stations"].keys()
	sids.sort()
	for sid in sids:
		var s: Dictionary = d["stations"][sid]
		s["id"] = sid
		s["idx"] = stations.size()
		id_to_idx[sid] = s["idx"]
		name_to_idx[s["name"]] = s["idx"]
		station_ids.append(sid)
		stations.append(s)
	# convert service stop ids to indices
	for lid in lines:
		for svc in lines[lid]["services"]:
			var idxs := PackedInt32Array()
			for sid in svc["stops"]:
				idxs.append(id_to_idx[sid])
			svc["stop_idx"] = idxs
	for lk in d["links"]:
		links.append({"a": id_to_idx[lk["a"]], "b": id_to_idx[lk["b"]], "walk_s": lk["walk_s"]})
	loaded = true


func station_name(idx: int) -> String:
	return stations[idx]["name"]


func line_color(lid: String) -> Color:
	return Palette.line_color(lid, lines[lid]["color"])


func line_name(lid: String) -> String:
	return lines[lid]["name"]


func dist_km(a: int, b: int) -> float:
	var sa: Dictionary = stations[a]
	var sb: Dictionary = stations[b]
	return Vector2(sa["x"] - sb["x"], sa["y"] - sb["y"]).length()


## Stable per-station seed so that layouts are identical every visit.
func station_seed(idx: int) -> int:
	return hash(station_ids[idx]) & 0x7fffffff


## Interchange importance: 1 (quiet suburban) .. ~5 (major hub)
func importance(idx: int) -> float:
	var s: Dictionary = stations[idx]
	var n: int = s["lines"].size()
	var z: int = s["zone"]
	return clampf(0.6 + 0.9 * (n - 1) + (2 - min(z, 4)) * 0.35, 0.6, 5.0)


func random_station(rng: RandomNumberGenerator, weighted := true) -> int:
	if not weighted:
		return rng.randi() % stations.size()
	# favour busy stations (interchanges, inner zones)
	var total := 0.0
	for s in stations:
		total += importance(s["idx"])
	var r := rng.randf() * total
	for s in stations:
		r -= importance(s["idx"])
		if r <= 0.0:
			return s["idx"]
	return 0
