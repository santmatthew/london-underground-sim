class_name StepFree
extends RefCounted
## Step-free access to the platforms (data/step_free.json from tools/build_step_free.py: TfL's step-free pathway graph) for the step-free journeys (Settings access/step_free; the plans then
## carry lifts instead of escalators and stairs). A platform with no entry counts as NOT step-free: better to leave a station out than to send someone to stairs.

const PATH := "res://data/step_free.json"

static var _data: Dictionary = {}
static var _loaded := false


## load the table (call on the main thread before the journey picker uses it from a worker)
static func ensure_loaded() -> void:
	_load()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			_data = d


## is this platform ("line:Direction", a branch junction's "line:Direction~branch" counts as its direction) reachable from the street without stairs or escalators?
static func platform_ok(station_idx: int, pid: String) -> bool:
	_load()
	var e: Dictionary = _data.get(Net.station_ids[station_idx], {})
	if e.is_empty():
		return false
	var key := pid.get_slice("~", 0).replace(":", "|")
	if e.has(key):
		return bool(e[key])
	# a direction the feed does not list: the line's other platforms at the station decide
	var line := key.get_slice("|", 0)
	for k in e:
		if String(k).begins_with(line + "|") and bool(e[k]):
			return true
	return false


## some platform of the station is step-free and every vertical link in its plan has a lift
static func station_ok(station_idx: int) -> bool:
	if not StationPlan.for_station(station_idx).sf_ok:
		return false
	for pid in Net.stations[station_idx]["platforms"]:
		if platform_ok(station_idx, pid):
			return true
	return false


## stations usable in a step-free journey, for the journey picker
static func station_list() -> Array:
	var out: Array = []
	for i in Net.stations.size():
		if station_ok(i):
			out.append(i)
	return out
