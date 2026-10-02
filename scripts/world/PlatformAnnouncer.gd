class_name PlatformAnnouncer
extends Node
## What the station says and does around the player, on top of the train announcements Game already triggers (approach, "this is ...", "next station ...", doors):
##  * on a platform: "The next train is a <Line> line train to <Dest>. Due in N minutes." for the next train that is not yet in sight, now and then a safety message (mind the gap, stand
##    behind the yellow line, keep your belongings with you ...), and in tunnel stations the rush of air that pushes out of the tunnel a few seconds before a train arrives and the rumble of
##    trains in the other tunnels;
##  * on the first escalator: "please stand on the right"; once per journey in the first ticket hall a greeting by the time of day;
##  * aboard: "this train is ready to depart" at a terminus, "please move right down inside the carriages" in a crowd, the driver holding the train when it waits a long time.
## Game calls `tick(zone, density, delta)` twice a second with the zone its audio uses ("platform", "hall", "corridor", "escalator", "train_idle", "train_run").
## Everything goes through Sfx.say (queued, subtitled, switched off by the settings); the periodic ones are "chatter" (their own setting).

const NEXT_MIN_LEAD := 35.0         # a train closer than this is announced by its approach message
const NEXT_MAX_LEAD := 14.0 * 60.0  # ("due in 15 minutes" is the longest clip)
const FIRST_CHATTER_S := 22.0       # after reaching a platform
const GUST_LEAD := Vector2(9.0, 15.0)

var station: Station
var player: Node3D
var greeted := false                # once per journey (Game resets it when a journey starts)

var _platform_s := 0.0
var _away_s := 0.0
var _chatter_in := FIRST_CHATTER_S
var _last_chatter := ""
var _announced: Dictionary = {}     # run -> true
var _gusted: Dictionary = {}
var _esc_said := false
var _rumble_in := 30.0
var _train_said: Dictionary = {}    # vkey -> {"ready", "carriages", "held"}
var _rng := RandomNumberGenerator.new()


func setup(st: Station, pl: Node3D) -> void:
	station = st
	player = pl
	_platform_s = 0.0
	_away_s = 0.0
	_chatter_in = FIRST_CHATTER_S
	_announced.clear()
	_gusted.clear()
	_esc_said = false
	_train_said.clear()
	_rng.randomize()


## the platform face the player stands on: {"fd": face description, "face": plan face, "module": PlatformModule, "gp": global platform} or {}
func face_at(pos: Vector3) -> Dictionary:
	if station == null or station.plan == null:
		return {}
	for mi in station.modules.size():
		var m: PlatformModule = station.modules[mi]
		var lp := m.to_local(pos)
		if absf(lp.x) < float(m.meta["length"]) * 0.5 + 3.0 and absf(lp.z) < 9.0 and absf(lp.y) < 3.5:
			var mod: Dictionary = station.plan.modules[mi]
			for fd in mod["faces"]:
				var f: Dictionary = station.plan.faces["%s#%d" % [fd["pid"], fd["face"]]]
				# (an open-air island is one walkable strip: the face is the side of the middle the player is on)
				if (f["side"] > 0.0 and lp.z > 0.0) or (f["side"] < 0.0 and lp.z < 0.0):
					return {"fd": fd, "face": f, "module": m, "gp": Timetable.plat_index[station.plan.idx].get(String(fd["pid"]), -1)}
	return {}


func tick(zone: String, density: float, delta: float) -> void:
	if station == null or player == null or not is_instance_valid(station):
		return
	var now := Clock.now
	var on_platform := zone == "platform"
	if on_platform:
		_platform_s += delta
		_away_s = 0.0
	else:
		_away_s += delta
		if _away_s > 25.0:
			_platform_s = 0.0
			_chatter_in = FIRST_CHATTER_S
			_announced.clear()
	match zone:
		"platform":
			_on_platform(now, density, delta)
		"escalator":
			if not _esc_said:
				_esc_said = true
				if _rng.randf() < 0.7:
					Sfx.say(["please_stand_on_the_right_escalator"], false, true)
		"hall":
			if not greeted:
				greeted = true
				var hh := fmod(now / 3600.0, 24.0)
				Sfx.say(["good_morning" if hh < 12.0 else ("good_afternoon" if hh < 17.5 else "good_evening")], false, true)
		"train_idle":
			_on_train(now, density)
	if zone == "platform" or zone == "corridor":
		_rumble(delta)


func _on_platform(now: float, density: float, delta: float) -> void:
	var ctx := face_at(player.global_position)
	if ctx.is_empty():
		return
	var gp: int = ctx["gp"]
	var m: PlatformModule = ctx["module"]
	var face: Dictionary = ctx["face"]
	var dwelling := false
	for v in station.trains.visits.values():
		if (v["module"] as PlatformModule) != m or float(v["side"]) != float(face["side"]):
			continue
		var info: Dictionary = v["info"]
		var lead: float = float(info["arr"]) - now
		if lead <= 0.0 and now < float(info["dep"]):
			dwelling = true
		# the air a train pushes ahead of it out of the tunnel
		if not m.open and not info["origin"] and lead > GUST_LEAD.x and lead < GUST_LEAD.y and not _gusted.has(v["vkey"]) and bool(Settings.get_v("audio", "pa_chatter")):
			_gusted[v["vkey"]] = true
			_gust(v, m)
	# the next train, once the player has been on the platform a few seconds
	if _platform_s >= 5.0 and not dwelling and gp >= 0:
		# (the next departure may be the train standing there now: the next train is the first one that has not arrived yet)
		var coming: Dictionary = {}
		for cand in Timetable.next_departures(gp, now, 3):
			if float(cand["arr"]) > now:
				coming = cand
				break
		if not coming.is_empty():
			var info: Dictionary = coming
			var lead: float = float(info["arr"]) - now
			if lead >= NEXT_MIN_LEAD and lead <= NEXT_MAX_LEAD and not _announced.has(info["run"]):
				_announced[info["run"]] = true
				var keys := _next_train_keys(info, lead)
				if not keys.is_empty():
					Sfx.say(keys)
					_chatter_in = maxf(_chatter_in, 25.0)
	# a safety message now and then
	_chatter_in -= delta
	if _chatter_in <= 0.0:
		var soon := false
		for v2 in station.trains.visits.values():
			var l2: float = float((v2["info"] as Dictionary)["arr"]) - now
			if l2 > -3.0 and l2 < 25.0:
				soon = true
		if soon or Sfx._speech_q.size() > 0 or Sfx._speech_player.playing:
			_chatter_in = 6.0
		else:
			_chatter(density)
			_chatter_in = lerpf(150.0, 80.0, clampf(density, 0.0, 1.0)) * _rng.randf_range(0.8, 1.25)


func _next_train_keys(info: Dictionary, lead: float) -> Array:
	var base := "platform_next/%s/%s" % [info["line"], Net.station_ids[int(info["dest"])]]
	var key := base
	var via := String(info["via"])
	if via != "":
		var k2 := base + "/via_" + via.replace("via ", "").to_lower().replace(" ", "_")
		if Sfx.has(k2):
			key = k2
	if not Sfx.has(key):
		return []
	var mins := clampi(int(ceil(lead / 60.0)), 1, 15)
	var due := "due_in_%02d_min" % mins
	return [key, due] if Sfx.has(due) else [key]


func _chatter(density: float) -> void:
	var pool: Array = [["mind_the_gap_platform", 3.0], ["stand_behind_the_yellow_line", 2.0], ["keep_your_belongings_with_you", 2.0], ["please_stand_back_from_the_platform_edge", 1.0]]
	if density > 0.6:
		pool.append(["please_keep_moving_along_the_platform", 2.0])
	var total := 0.0
	for p in pool:
		if p[0] != _last_chatter:
			total += float(p[1])
	var r := _rng.randf() * total
	for p in pool:
		if p[0] == _last_chatter:
			continue
		r -= float(p[1])
		if r <= 0.0:
			_last_chatter = p[0]
			Sfx.say([p[0]], false, true)
			return


## the push of air out of the tunnel mouth the train comes from
func _gust(v: Dictionary, m: PlatformModule) -> void:
	var train: Train = v["train"]
	var from_x := signf(train.position.x) * (float(m.meta["length"]) * 0.5 + 4.0)
	var key: String = "wind_gust_tunnel_air_push" if _rng.randf() < 0.6 else "wind_gust_tunnel_air_push_short"
	Sfx.play_at(key, m, Vector3(from_x, 1.5, float(v["side"]) * (PlatformModule.GAP * 0.5 + float(m.meta["pw"]) + PlatformModule.TRACK_TO_EDGE)), -7.0, 70.0)


func _rumble(delta: float) -> void:
	if station.plan.kind == "surface":
		return
	_rumble_in -= delta
	if _rumble_in <= 0.0:
		_rumble_in = _rng.randf_range(35.0, 80.0)
		var key: String = "distant_train_rumble_" + String(["a", "b", "c", "d"][_rng.randi() % 4])
		Sfx.play(key, -13.0)


func _on_train(now: float, density: float) -> void:
	for v in station.trains.visits.values():
		var train: Train = v["train"]
		if not train.contains_world_point(player.global_position):
			continue
		var info: Dictionary = v["info"]
		var st: Dictionary = _train_said.get(v["vkey"], {})
		var to_dep: float = float(info["dep"]) - now
		if info["origin"] and to_dep > 2.0 and to_dep < 14.0 and not st.has("ready"):
			st["ready"] = true
			Sfx.say(["this_train_is_ready_to_depart"], false, true)
		if now > float(info["arr"]) + 2.0 and density > 0.6 and not info["final"] and not st.has("carriages"):
			st["carriages"] = true
			Sfx.say(["please_move_right_down_inside_the_carriages"], false, true)
		var dwell := float(info["dep"]) - float(info["arr"])
		if not info["origin"] and not info["final"] and dwell >= 75.0 and now > float(info["arr"]) + 30.0 and to_dep > 20.0 and not st.has("held"):
			st["held"] = true
			Sfx.say(["holding_here_for_a_short_while"], false, true)
		_train_said[v["vkey"]] = st
