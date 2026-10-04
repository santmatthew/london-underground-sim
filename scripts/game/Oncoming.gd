class_name Oncoming
extends Node3D
## The trains that come the other way on the second track of a ride (RunScenery PAIR): the timetable's trains from the destination to the origin, each at the place its own run puts it, drawn only where that
## track is in view (open land, cuttings, embankments, viaducts - the other bore of a deep tube is out of sight). They are scenery: no colliders, never boarded, never a visit of a station.
## Ride frame: path distance s runs from the origin's stop (0) to the destination's (dist); the second track lies `side` of the path (TunnelRun: on the platform side of the unmirrored cross-section, so on the other
## side when the ride is mirrored) at the spacing the path has there (TrackPath.spacing_at), a train on it travels toward lower s.

const BUILD_RANGE := 700.0          # a train is built (hidden) when its middle is this close to the player's car
const AHEAD := 110.0                # a car is shown while its middle is no more than this far ahead of the player's car (TunnelRun draws the cells to about 120 m ahead and 132 m behind: the car's own half length too)
const BEHIND := 120.0
const NEAR_WINDOW := 120.0          # at the hand-over from the origin station the trains inside this window are left out: the station has shown its own, and a train would pop into being
const GUST := "wind_gust_tunnel_air_push_short"          # (4.8 s, loudest at 3.5 s: it is started that long before the train is level with the player)
const GUST_LEAD := 3.5
const RUMBLE := ["distant_train_rumble_c", "distant_train_rumble_a"]          # (the other bore of a deep tube, or the next box: nothing to see, a rumble that peaks about 4.8 s in)
const RUMBLE_LEAD := 4.8

var path: TrackPath
var side := -1.0                    # which side of the path the second track lies on (path z): -1 on the platform side of the unmirrored cross-section, +1 when the ride is mirrored
var dist := 0.0
var entries: Array = []             # {"info", "pr", "T", "scale", "train": Train or null, "skip": bool, "len": float}
var shown := 0                      # trains in view now (tests)


## `a_idx` / `b_idx`: the stations the player's train runs between (a -> b); `t_dep` / `t_arr` its times; `p_dist` the length of the ride; `line`: the player's line (only trains of lines of its group, which share its tracks
## in the sub-surface lines' case, come the other way on the second track: a deep tube's neighbours on a four-track stretch run on tracks beyond it)
func setup(p_path: TrackPath, mirror: bool, a_idx: int, b_idx: int, t_dep: float, t_arr: float, p_dist: float, line := "") -> void:
	path = p_path
	dist = p_dist
	side = 1.0 if mirror else -1.0
	if path.single:
		return          # (a single track: nothing comes the other way)
	var group: String = String(Net.lines[line]["group"]) if Net.lines.has(line) else ""
	for info in Timetable.oncoming(a_idx, b_idx, t_dep, t_arr):
		var T: float = float(info["arr"]) - float(info["dep"])
		if T < 20.0:
			continue
		if group != "" and String(Net.lines[info["line"]]["group"]) != group:
			continue
		var pr := Ride.solve_profile(T, dist)
		var lid: String = info["line"]
		var cars: Array = StationPlan.CARS.get(lid, [6, 16.0])
		entries.append({"info": info, "pr": pr, "T": T, "scale": dist / maxf(float(pr["dist"]), 1.0), "train": null, "skip": false, "heard": false,
				"len": Train.length_for(Train.kind_of_line(lid), int(cars[0]))})


## where the middle of an entry's train is on the path at clock time `now` (it leaves the destination at s = dist and reaches the origin's stop at 0)
func s_of(e: Dictionary, now: float) -> float:
	var tau := now - float(e["info"]["dep"])
	return dist - Ride.profile_s(e["pr"], e["T"], tau) * float(e["scale"])


## the player's car is at path distance `s_p` as the scenery takes over from the origin station: the trains that are in view now stay out of the ride
func begin(s_p: float, now: float) -> void:
	for e in entries:
		var tau := now - float(e["info"]["dep"])
		if tau > float(e["T"]):
			e["skip"] = true
		elif tau >= 0.0 and s_of(e, now) - float(e["len"]) * 0.5 < s_p + NEAR_WINDOW:
			e["skip"] = true


## `world`: where the path's frame is in the world now; `s_p`: the path distance of the player's car, `v_p` its speed
func update(s_p: float, now: float, world: Transform3D, v_p := 0.0) -> void:
	shown = 0
	var built_one := false
	for e in entries:
		if e["skip"]:
			continue
		var tau := now - float(e["info"]["dep"])
		if tau < 0.0:
			continue
		var half := float(e["len"]) * 0.5
		if tau > float(e["T"]) + 2.0 or s_of(e, now) < s_p - BEHIND - half - 30.0:
			_retire(e)          # (it has reached the origin, or gone far behind the player)
			continue
		var s_mid := s_of(e, now)
		if not e["heard"]:
			_listen(e, s_mid - half - s_p, s_p, v_p, now)
		if e["train"] == null:
			if absf(s_mid - s_p) < BUILD_RANGE and not built_one and _pair_near(s_mid):
				built_one = true             # (one train a frame: the cars are scenes)
				e["train"] = _build(e["info"])
			continue
		var tr := e["train"] as Train
		if s_mid - s_p > AHEAD + half or s_p - s_mid > BEHIND + half:
			tr.visible = false
			continue
		# the cars that stand where the second track is in view
		var any := false
		tr.follow_oncoming(path, s_mid, world, side)
		for i in tr.cars.size():
			var sc := s_mid - float(tr.car_x[i])
			var vis := sc - s_p < AHEAD and s_p - sc < BEHIND and (path.cell_scene(int(roundf(sc / RunScenery.CELL))) & RunScenery.PAIR) != 0
			(tr.cars[i] as Node3D).visible = vis
			any = any or vis
		tr.visible = any
		if any:
			shown += 1


## a train that is done with: freed, and not looked at again
func _retire(e: Dictionary) -> void:
	e["skip"] = true
	if e["train"] != null:
		(e["train"] as Train).queue_free()
		e["train"] = null


## is the second track in view anywhere near path distance s (a train is only built where it will be seen)
func _pair_near(s: float) -> bool:
	var k0 := int(roundf((s - BEHIND - 90.0) / RunScenery.CELL))
	var k1 := int(roundf((s + AHEAD + 90.0) / RunScenery.CELL))
	for k in range(k0, k1 + 1):
		if (path.cell_scene(k) & RunScenery.PAIR) != 0:
			return true
	return false


## the sound of the train going by, started so that it is at its loudest as the train's front is level with the player: a gust where the track is open, a rumble from the next bore or box where it is not
## `d`: path distance from the player to the train's front (positive: still ahead)
func _listen(e: Dictionary, d: float, s_p: float, v_p: float, now: float) -> void:
	if d < -2.0 or Clock.time_scale > 1.5:
		e["heard"] = true          # (already past: the hand-over or a late start; or the clock is running fast, when the trains go by far quicker than a sound plays)
		return
	var v_on := (s_of(e, now) - s_of(e, now + 0.5)) / 0.5
	var v_rel := maxf(v_p + v_on, 1.0)
	var here := path.cell_scene(int(roundf((s_p + v_p * GUST_LEAD) / RunScenery.CELL)))
	var open := (here & RunScenery.PAIR) != 0
	var lead := GUST_LEAD if open else RUMBLE_LEAD
	if d / v_rel > lead:
		return
	e["heard"] = true
	if open:
		Sfx.play(GUST, -6.0)
	else:
		Sfx.play(RUMBLE[int(e["info"]["run"]) % RUMBLE.size()], -14.0 + (3.0 if (here & 7) == RunScenery.BOX else 0.0))


func _build(info: Dictionary) -> Train:
	var lid: String = info["line"]
	var cars: Array = StationPlan.CARS.get(lid, [6, 16.0])
	var train := Train.new()
	train.name = "Oncoming_%d" % int(info["run"])
	train.build(Train.kind_of_line(lid), int(cars[0]), lid, Net.line_color(lid))
	add_child(train)
	train.visible = false
	train.set_solid(false)
	var dest_txt: String = Net.station_name(info["dest"]).replace(" (H&C)", "").replace(" (D&P)", "").replace(" (Circle)", "")
	if String(info["via"]) != "":
		dest_txt += " " + String(info["via"])
	train.set_destination("NOT IN SERVICE" if info["final"] else dest_txt)
	train.set_linemap(lid, Timetable.run_dir[info["run"]])
	return train
