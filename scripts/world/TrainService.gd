class_name TrainService
extends Node
## Spawns and animates the trains at a Station's platform faces as a pure function of Clock.now (approach -> dwell with doors -> departure).

signal doors_opened(visit: Dictionary)
signal doors_closing(visit: Dictionary)
signal train_spawned(train: Train, visit: Dictionary)

const APPROACH_S := 26.0
const AFTER_S := 32.0
const A_DEC := 1.0
const V_IN := 13.0
const A_ACC := 1.1
const V_OUT := 16.0
const SPAWN_RANGE := 170.0

var station: Station
var visits: Dictionary = {}            # "run:k" -> visit dict {train, key(face), info, dir_arr, dir_dep, origin, doors}
var player: Node3D
var external: Dictionary = {}          # visit keys controlled externally (player's ride)
var _poll := 0.0
var paused := false


func setup(st: Station, p: Node3D) -> void:
	station = st
	player = p


static func r_app(tau: float) -> float:
	var t0 := V_IN / A_DEC
	if tau < t0:
		return 0.5 * A_DEC * tau * tau
	return 0.5 * A_DEC * t0 * t0 + V_IN * (tau - t0)


static func r_dep(tau: float) -> float:
	var t0 := V_OUT / A_ACC
	if tau < t0:
		return 0.5 * A_ACC * tau * tau
	return 0.5 * A_ACC * t0 * t0 + V_OUT * (tau - t0)


## signed x of the train centre (module local) at time `now`
static func x_at(v: Dictionary, now: float) -> float:
	var info: Dictionary = v["info"]
	var arr: float = info["arr"]
	var dep: float = info["dep"]
	if v["origin"]:
		return 0.0 if now < dep else v["dir_dep"] * r_dep(now - dep)
	if now < arr:
		return -v["dir_arr"] * r_app(arr - now)
	if now < dep:
		return 0.0
	return v["dir_dep"] * r_dep(now - dep)


## A train is longer than the short tunnel stub behind a platform, so while it arrives or leaves its rear cars would stand beyond the black cap, inside the
## passage or landing behind it (passengers saw trains drive through the rooms). A car is shown only while it lies entirely inside the tunnel.
func _clip_cars(train: Train, mlen: float, tun_w: float, tun_e: float) -> void:
	if not train.visible:
		return
	var cap_w := -mlen * 0.5 - tun_w + 0.3
	var cap_e := mlen * 0.5 + tun_e - 0.3
	var any := false
	var last := train.cars.size() - 1
	for i in train.cars.size():
		var cx := (train.transform * Vector3(float(train.car_x[i]), 0.0, 0.0)).x
		var key := train.kind + ("_cab" if (i == 0 or i == last) else "_mid")
		var half_car: float = float(Train.CAR_LEN[key]) * 0.5
		var vis := cx - half_car > cap_w and cx + half_car < cap_e
		(train.cars[i] as Node3D).visible = vis
		any = any or vis
	train.visible = any


func _process(delta: float) -> void:
	if station == null or paused:
		return
	var now := Clock.now
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.5
		_spawn_pass(now)
	var dead: Array = []
	for key in visits:
		var v: Dictionary = visits[key]
		if external.has(key):
			continue
		var info: Dictionary = v["info"]
		var x := x_at(v, now)
		var train: Train = v["train"]
		train.position.x = x
		train.set_solid(absf(x) < 0.5)
		# a running tunnel that stops short of the rooms behind it ends in a black cap: a train beyond it is not there
		var mod: PlatformModule = v["module"]
		var half: float = train.length * 0.5
		var mlen: float = mod.meta["length"]
		train.visible = x + half > -mlen * 0.5 - float(mod.meta["tun_w"]) + 0.5 and x - half < mlen * 0.5 + float(mod.meta["tun_e"]) - 0.5
		_clip_cars(train, mlen, float(mod.meta["tun_w"]), float(mod.meta["tun_e"]))
		var dwell: float = info["dep"] - info["arr"]
		# doors
		var want_open: bool = now >= info["arr"] + (3.0 if not v["origin"] else 0.0) and now < info["dep"] - 6.0 and dwell >= 15.0 and absf(x) < 0.5
		if v["origin"]:
			want_open = now >= info["dep"] - 42.0 and now < info["dep"] - 6.0 and absf(x) < 0.5
		if want_open != v["doors"]:
			v["doors"] = want_open
			train.set_doors(want_open)
			_edge_guard(v, want_open)
			if want_open:
				doors_opened.emit(v)
			else:
				doors_closing.emit(v)
		if now > info["dep"] + AFTER_S or absf(x) > 280.0 and now > info["dep"]:
			dead.append(key)
		elif now < info["arr"] - APPROACH_S - 4.0 and not v["origin"]:
			dead.append(key)
	for key in dead:
		_despawn(key)


func _edge_guard(v: Dictionary, open: bool) -> void:
	var train: Train = v["train"]
	var module: PlatformModule = v["module"]
	var side: float = v["side"]
	for dx in train.door_positions():
		var mx: float = train.position.x + train.facing * dx
		module.set_edge_open(side, mx - 0.8, mx + 0.8, open)


func _spawn_pass(now: float) -> void:
	var plan := station.plan
	for fkey in plan.faces:
		var f: Dictionary = plan.faces[fkey]
		var module: PlatformModule = station.modules[f["module"]]
		if player != null and player.global_position.distance_to(module.global_position) > SPAWN_RANGE + f["length"] * 0.5:
			continue
		var gp: int = Timetable.plat_index[plan.idx][f["pid"]]
		for info in Timetable.visits_between(gp, now - AFTER_S, now + APPROACH_S + 4.0):
			var r: int = info["run"]
			var k: int = info["k"]
			var face_no: int = (Timetable.run_face[r] as PackedByteArray)[k]
			if face_no != f["face_no"]:
				continue
			var vkey := "%d:%d" % [r, k]
			if visits.has(vkey):
				continue
			if now > info["dep"] + AFTER_S or now < info["arr"] - APPROACH_S - 3.0:
				if not info["origin"]:
					continue
			# already gone (would be despawned again on the very next frame, after building a whole train): skip
			if now > info["dep"] and absf(x_at({"info": info, "origin": info["origin"], "dir_arr": 1, "dir_dep": 1}, now)) > 280.0:
				continue
			_spawn(vkey, fkey, f, module, info)


func _spawn(vkey: String, fkey: String, f: Dictionary, module: PlatformModule, info: Dictionary) -> void:
	var plan := station.plan
	var canon := 1 if f["face"] == 0 else -1
	var origin: bool = info["origin"]
	var dir_arr := canon
	var dir_dep := -canon if origin else canon
	var lid: String = info["line"]
	var cars: Array = StationPlan.CARS.get(lid, [6, 16.0])
	var kind := "ss" if Net.lines[lid]["group"] == "ss" else "deep"
	var train := Train.new()
	train.name = "Train_" + vkey.replace(":", "_")
	train.run = info["run"]
	train.build(kind, cars[0], lid, Net.line_color(lid))
	module.add_child(train)
	var side: float = f["side"]
	train.position = Vector3(0, PlatformModule.RAIL_Y, side * (PlatformModule.GAP * 0.5 + module.meta["pw"] + PlatformModule.TRACK_TO_EDGE))
	var facing: int = dir_dep if origin else dir_arr
	train.setup_orientation(facing, -side)    # platform lies toward the tunnel centre (-side)
	var dest_txt: String = Net.station_name(info["dest"]).replace(" (H&C)", "").replace(" (D&P)", "").replace(" (Circle)", "")
	if info["via"] != "":
		dest_txt += " " + info["via"]
	train.set_destination("NOT IN SERVICE" if info["final"] else dest_txt)
	train.set_linemap(lid, Timetable.run_dir[info["run"]])
	var v := {"train": train, "key": fkey, "info": info, "dir_arr": dir_arr, "dir_dep": dir_dep, "origin": origin, "doors": false, "module": module, "side": side, "vkey": vkey}
	train.set_meta("visit", v)
	visits[vkey] = v
	train.position.x = x_at(v, Clock.now)
	if not origin:
		var lead: float = info["arr"] - Clock.now         # seconds until it stops
		if lead > -2.0 and lead < 26.0 and Sfx.has("train_arrive_platform"):
			Sfx.play_at("train_arrive_platform", train, Vector3(length_front(train), 1.0, 0), 0.0, 90.0, maxf(0.0, 25.0 - lead))
		if lead > 8.0 and player != null:
			# the platform PA only speaks for the platform you are on (stations with several modules must not announce each other's trains)
			var lp := module.to_local(player.global_position)
			if absf(lp.x) < module.meta["length"] * 0.5 + 6.0 and absf(lp.z) < 9.0 and absf(lp.y) < 3.5:
				Sfx.say_platform_approach(lid, info["dest"], info["via"])
	train_spawned.emit(train, v)


func length_front(train: Train) -> float:
	return train.length * 0.5 - 4.0


func _despawn(vkey: String) -> void:
	var v: Dictionary = visits[vkey]
	if player != null and is_instance_valid(v["train"]) and (v["train"] as Train).contains_world_point(player.global_position):
		var inf: Dictionary = v["info"]
		push_warning("DESPAWN of the player's own train %s: now %s arr %s dep %s x %.1f origin %s" % [vkey, Clock.fmt(Clock.now, true), Clock.fmt(inf["arr"], true), Clock.fmt(inf["dep"], true), (v["train"] as Train).position.x, str(v["origin"])])
	if is_instance_valid(v["train"]):
		(v["train"] as Train).queue_free()
	visits.erase(vkey)


func visit_for_train(t: Train) -> Dictionary:
	return t.get_meta("visit", {})
