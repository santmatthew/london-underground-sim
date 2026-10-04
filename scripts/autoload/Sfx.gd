extends Node
## Audio manager: manifest lookups (assets/audio/manifest.json), buses, ambience layers that crossfade by location,
## spatial one-shots and a PA/announcement queue (with subtitles). Autoload name: Sfx.

signal subtitle(text: String, seconds: float)

const ROOT := "res://assets/audio/"

var manifest: Dictionary = {}
var clips: Dictionary = {}
var index: Dictionary = {}
var _streams: Dictionary = {}
var enabled := true
var master_db := 0.0

# ambience layers: name -> {player, target_db, key}
var _layers: Dictionary = {}
var _zone := ""
var _speech_q: Array = []
var _speech_player: AudioStreamPlayer
var _speech_t := 0.0
var _duck := 0.0
var bus_sfx := "SFX"
var bus_amb := "Ambience"
var bus_speech := "Speech"


func _ready() -> void:
	var f := FileAccess.open(ROOT + "manifest.json", FileAccess.READ)
	if f == null:
		enabled = false
		push_warning("Sfx: audio manifest missing (run tools/audio/make_audio.py)")
		return
	manifest = JSON.parse_string(f.get_as_text())
	clips = manifest["clips"]
	index = manifest.get("index", {})
	_make_buses()
	_apply_buses()
	Settings.changed.connect(func(sec, _k): if sec == "audio": _apply_buses())
	for name in ["base", "crowd", "tunnel", "train"]:
		var p := AudioStreamPlayer.new()
		p.bus = bus_amb
		p.volume_db = -60.0
		add_child(p)
		_layers[name] = {"player": p, "target": -60.0, "key": ""}
	_speech_player = AudioStreamPlayer.new()
	_speech_player.bus = bus_speech
	add_child(_speech_player)
	set_process(true)


func _make_buses() -> void:
	for n in [bus_sfx, bus_amb, bus_speech]:
		if AudioServer.get_bus_index(n) == -1:
			AudioServer.add_bus()
			var i := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, "Master")


## the volume sliders of the settings (master, effects, ambience, announcements) onto the buses
func _apply_buses() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(Settings.get_v("audio", "master")), 0.0001)))
	for pair in [[bus_sfx, "effects"], [bus_speech, "announcements"]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(Settings.get_v("audio", pair[1])), 0.0001)))


func has(key: String) -> bool:
	return clips.has(key)


func stream(key: String) -> AudioStream:
	if not enabled or not clips.has(key):
		return null
	if _streams.has(key):
		return _streams[key]
	var c: Dictionary = clips[key]
	var path: String = ROOT + c["file"]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = c.get("loop", false)
	_streams[key] = s
	return s


func volume(key: String) -> float:
	return float(clips.get(key, {}).get("volume_db", 0.0))


func text_of(key: String) -> String:
	return String(clips.get(key, {}).get("text", ""))


func duration(key: String) -> float:
	return float(clips.get(key, {}).get("duration", 0.0))


# ---------------------------------------------------------------------------------------------------
# One-shots
# ---------------------------------------------------------------------------------------------------
## 2D one-shot
func play(key: String, vol_offset := 0.0, bus := "") -> AudioStreamPlayer:
	var s := stream(key)
	if s == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus if bus != "" else _bus_for(key)
	p.volume_db = volume(key) + vol_offset
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


## spatial one-shot attached to `parent` at local position `pos`
func play_at(key: String, parent: Node3D, pos := Vector3.ZERO, vol_offset := 0.0, max_dist := 40.0, from_pos := 0.0) -> AudioStreamPlayer3D:
	var s := stream(key)
	if s == null or parent == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = _bus_for(key)
	p.volume_db = volume(key) + vol_offset
	p.max_distance = max_dist
	p.unit_size = 6.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	parent.add_child(p)
	p.position = pos
	if not (s is AudioStreamOggVorbis and (s as AudioStreamOggVorbis).loop):
		p.finished.connect(p.queue_free)
	p.play(from_pos)
	return p


## looping spatial emitter (e.g. escalator hum). Returns the player; caller owns it.
func loop_at(key: String, parent: Node3D, pos := Vector3.ZERO, vol_offset := 0.0, max_dist := 30.0) -> AudioStreamPlayer3D:
	var p := play_at(key, parent, pos, vol_offset, max_dist)
	return p


func _bus_for(key: String) -> String:
	var cat := String(clips.get(key, {}).get("category", ""))
	if cat.begins_with("speech"):
		return bus_speech
	if cat == "ambience":
		return bus_amb
	return bus_sfx


func footstep(kind: String, vol := 0.0) -> void:
	var n := 1 + (randi() % 6)
	var key := "footstep_%s_%d" % [kind, n]
	if has(key):
		play(key, vol - 6.0)


# ---------------------------------------------------------------------------------------------------
# Announcements (queued, spoken one after another, with subtitles and ducking of ambience)
# ---------------------------------------------------------------------------------------------------
## `say(keys)`: the clips are spoken one after another. `chatter` marks the periodic extras (mind the gap ...) that the "PA chatter" setting can switch off;
## the same message is not repeated within `REPEAT_S` seconds.
const REPEAT_S := 8.0
var _said: Dictionary = {}
var spoken: Array = []           # (the last few groups spoken or queued, for tests and the debug overlay)


func say(keys: Array, priority := false, chatter := false) -> void:
	if not enabled or not bool(Settings.get_v("audio", "announce_on")):
		return
	if chatter and not bool(Settings.get_v("audio", "pa_chatter")):
		return
	var valid: Array = []
	for k in keys:
		if has(k):
			valid.append(k)
	if valid.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _said.has(valid[0]) and now - float(_said[valid[0]]) < REPEAT_S:
		return
	_said[valid[0]] = now
	spoken.append(valid.duplicate())
	if spoken.size() > 12:
		spoken.pop_front()
	if priority:
		_speech_q.clear()
		_speech_player.stop()
	_speech_q.append(valid)


func station_key(station_idx: int, what: String) -> String:
	var id: String = Net.station_ids[station_idx]
	return "station/%s/%s" % [id, what]


func say_station_this(idx: int, line: String = "") -> void:
	var keys: Array = [station_key(idx, "this")]
	var ch := station_key(idx, "change")
	if has(ch) and Net.stations[idx]["lines"].size() > 1:
		keys.append(ch)
	say(keys)


func say_next(idx: int) -> void:
	say([station_key(idx, "next")])


func say_terminates(line: String, dest_idx: int, via: String = "") -> void:
	var key := _line_dest_key("terminates", line, dest_idx, via)
	if key != "":
		say([key])


func say_platform_approach(line: String, dest_idx: int, via: String = "") -> void:
	var key := _line_dest_key("platform_approach", line, dest_idx, via)
	if key != "":
		say([key])


func _line_dest_key(kind: String, line: String, dest_idx: int, via: String) -> String:
	var did: String = Net.station_ids[dest_idx]
	var base := "%s/%s/%s" % [kind, line, did]
	if via != "":
		var v := via.replace("via ", "").to_lower().replace(" ", "_")
		var k2 := base + "/via_" + v
		if has(k2):
			return k2
	return base if has(base) else ""


var _speech_end := 0.0


func _process(delta: float) -> void:
	if not enabled:
		return
	# ambience crossfades
	for name in _layers:
		var l: Dictionary = _layers[name]
		var p: AudioStreamPlayer = l["player"]
		var db := lerpf(p.volume_db, float(l["target"]), clampf(delta * 1.4, 0.0, 1.0))
		p.volume_db = db + master_db * 0.0
		if p.stream != null and not p.playing and db > -55.0:
			p.play()
	# speech queue
	_speech_t -= delta
	if _speech_t <= 0.0 and not _speech_player.playing and _speech_q.size() > 0:
		var group: Array = _speech_q.pop_front()
		_play_group(group)
	# duck ambience while speaking
	var ducking := 1.0 if _speech_player.playing else 0.0
	_duck = lerpf(_duck, ducking, clampf(delta * 4.0, 0.0, 1.0))
	var bi := AudioServer.get_bus_index(bus_amb)
	if bi >= 0:
		AudioServer.set_bus_volume_db(bi, linear_to_db(maxf(float(Settings.get_v("audio", "ambience")), 0.0001)) - 5.0 * _duck)


func _play_group(group: Array) -> void:
	# play the first clip now; the rest chained through `finished`
	var first: String = group[0]
	var s := stream(first)
	if s == null:
		return
	_speech_player.stream = s
	_speech_player.volume_db = volume(first)
	_speech_player.play()
	var txt := text_of(first)
	var total := duration(first)
	for k in group.slice(1):
		txt += " " + text_of(k)
		total += duration(k) + 0.25
	subtitle.emit(txt.strip_edges(), total + 1.5)
	if group.size() > 1:
		var rest := group.slice(1)
		_speech_player.finished.connect(func(): _speech_t = 0.25; _speech_q.push_front(rest), CONNECT_ONE_SHOT)


# ---------------------------------------------------------------------------------------------------
# Ambience by location
# ---------------------------------------------------------------------------------------------------
func _set_layer(name: String, key: String, db: float) -> void:
	var l: Dictionary = _layers[name]
	if l["key"] != key:
		l["key"] = key
		var p: AudioStreamPlayer = l["player"]
		if key == "":
			l["target"] = -60.0
			return
		var s := stream(key)
		if s != null:
			# crossfade: swap the stream once the old one is inaudible; simple approach: swap immediately at low volume
			p.stream = s
			p.volume_db = -50.0
			p.play(randf() * maxf(duration(key) - 1.0, 0.0))
	l["target"] = db + (volume(key) if key != "" else 0.0)


## zones: "street", "hall", "corridor", "escalator", "platform", "train_idle", "train_run"; density 0..1 (crowd); speed m/s for train_run; in a train, `outdoors` 0..1 is how open the surroundings are (the
## outdoor bed comes up and the tunnel rumble goes down) and `boxy` 0..1 how much of the track is the brick box of a cut-and-cover tunnel (a closer, louder rumble than the bored tube's)
func set_zone(zone: String, density: float, speed := 0.0, outdoors := 0.0, boxy := 0.0) -> void:
	if not enabled:
		return
	_zone = zone
	var crowd_key := "crowd_murmur_dense_loop" if density > 0.55 else "crowd_murmur_light_loop"
	match zone:
		"hall", "street":
			_set_layer("base", "concourse_ambience_loop", -3.0)
			_set_layer("crowd", crowd_key, -4.0 - (1.0 - density) * 14.0)
			_set_layer("tunnel", "", -60.0)
			_set_layer("train", "", -60.0)
		"corridor":
			_set_layer("base", "corridor_ambience_loop", -3.0)
			_set_layer("crowd", crowd_key, -10.0 - (1.0 - density) * 14.0)
			_set_layer("tunnel", "", -60.0)
			_set_layer("train", "", -60.0)
		"escalator":
			_set_layer("base", "corridor_ambience_loop", -6.0)
			_set_layer("crowd", crowd_key, -12.0 - (1.0 - density) * 12.0)
			_set_layer("tunnel", "tunnel_rumble_loop", -22.0)
			_set_layer("train", "", -60.0)
		"platform":
			_set_layer("base", "platform_ambience_loop", -3.0)
			_set_layer("crowd", crowd_key, -6.0 - (1.0 - density) * 14.0)
			_set_layer("tunnel", "tunnel_rumble_loop", -20.0)
			_set_layer("train", "", -60.0)
		"platform_open":
			# an open-air platform: the outdoors (day or night), no tunnel; a little of the crowd
			var day_bed := "outdoor_day_loop" if PlatformOpen.daylight() > 0.25 else "outdoor_night_loop"
			_set_layer("base", day_bed, -2.0)
			_set_layer("crowd", crowd_key, -8.0 - (1.0 - density) * 14.0)
			_set_layer("tunnel", "", -60.0)
			_set_layer("train", "", -60.0)
		"train_idle":
			_set_layer("base", _outdoor_bed() if outdoors > 0.02 else "", -17.0 - (1.0 - clampf(outdoors, 0.0, 1.0)) * 20.0)
			_set_layer("crowd", crowd_key, -9.0 - (1.0 - density) * 10.0)
			_set_layer("tunnel", "", -60.0)
			_set_layer("train", "train_interior_idle_loop", -3.0)
		"train_run":
			# through the windows: the outdoors comes up where the track is in the open (a cutting's banks muffle it, see Ride.ambience), the bore's rumble goes down, a box tunnel's is closer and louder
			var o := clampf(outdoors, 0.0, 1.0)
			_set_layer("base", _outdoor_bed() if o > 0.02 else "", -12.0 - (1.0 - o) * 22.0)
			_set_layer("crowd", crowd_key, -13.0 - (1.0 - density) * 10.0)
			_set_layer("tunnel", "tunnel_rumble_loop", -14.0 - o * 13.0 + clampf(boxy, 0.0, 1.0) * 3.5)
			_set_layer("train", "train_interior_run_fast_loop" if speed > 13.0 else "train_interior_run_slow_loop", -2.0 - clampf(1.0 - speed / 20.0, 0.0, 1.0) * 8.0)
		_:
			for n in _layers:
				_set_layer(n, "", -60.0)


func _outdoor_bed() -> String:
	return "outdoor_day_loop" if PlatformOpen.daylight() > 0.25 else "outdoor_night_loop"


func silence() -> void:
	for n in _layers:
		_set_layer(n, "", -60.0)
	_speech_q.clear()
	if _speech_player:
		_speech_player.stop()
