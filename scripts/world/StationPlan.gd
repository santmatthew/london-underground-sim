class_name StationPlan
extends RefCounted
## Pure-data layout of a station, generated deterministically from the station id.
## World frame: y = 0 is the ticket-hall floor; platforms are below. Everything is axis aligned.
##
##   street doors (N wall, z=-H) -> unpaid zone -> GATELINE (z=GATE_Z) -> paid zone -> escalators (S wall, +z)
##   -> landing 1 (shallowest platform level) -> corridors east -> platform modules
##   landing 1 -> escalators (+z) -> landing 2 -> ...
##
## The walking graph (nodes/edges) is used for NPC routing and to give the journey planner exact transfer times.

const CARS := {   # line -> [cars, car length m]
	"bakerloo": [7, 15.5], "central": [8, 16.5], "circle": [7, 18.0], "district": [7, 18.0], "hammersmith-city": [7, 18.0],
	"jubilee": [7, 17.0], "metropolitan": [8, 18.0], "northern": [6, 16.0], "piccadilly": [6, 17.0], "victoria": [8, 16.0], "waterloo-city": [4, 16.0],
	"elizabeth": [11, 18.5],          # (the Class 345 is 9 cars of 23 m = 205 m; the simulator's car models are the 18 m S-stock cars, so eleven of them make the same length)
}
const BASE_DEPTH := {  # metres below the ticket hall
	"bakerloo": 21.0, "central": 22.0, "jubilee": 29.0, "northern": 25.0, "piccadilly": 27.0, "victoria": 24.0, "waterloo-city": 23.0, "ss": 9.0, "elizabeth": 24.0,
}
const MAX_STREET_DOORS := 5
const HALL_H := 4.2
const LANDING_H := 3.9
const SPINE_H := 2.6
const CORR_W := 3.4

var idx := 0
var name := ""
var seed_value := 0
var imp := 1.0
var kind := "deep"

var hall: Dictionary = {}          # {rect, h, y, ...}
var rooms: Array = []              # Space specs (hall, landings, corridors)
var escs: Array = []               # {id, pos:Vector3 (top), yaw, rise, lanes, from_room, to_room}
var modules: Array = []            # {pos:Vector3, spec:Dictionary, faces:[{pid,face}], level:int, group:String}
var levels: Array = []             # [{depth, landing_room, module_idx:[...]}]
var street_doors: Array = []       # {pos:Vector3, dir:Vector3, id}
var gates: Dictionary = {}         # {z, x0, x1, n, pitch}  (the primary hall's gateline)
var authored := false              # built by LayoutCompiler from data/layouts/<naptan>.json
var gatelines: Array = []          # every hall's gateline: {z, x0, x1, n, lanes, total_w, cx, hall, rect}
var faces: Dictionary = {}         # "pid#f" -> {module:int, face:int, pos:Vector3 (platform centre), side, x0, x1, ...}
var nodes: Array = []              # {name, pos}
var node_idx: Dictionary = {}
var edges: Array = []              # {a, b, len, cost}
var adj: Array = []                # per node: [[to, cost, edge idx]]
var start_spots: Array = []        # candidate player start points: {name, pos, yaw, node}
var lifts: Array = []              # step-free mode: one lift per escalator / stair bank: {id, esc, rise, time, top:{pos, front, yaw, rot, y}, bot:{...}} (see _add_lifts)
var adj_sf: Array = []             # the walking graph for step-free journeys: no escalators or stairs, lifts instead (lifts never appear in `adj`)
var adj_lift: Array = []           # `adj` plus the lifts (stations that have real lifts): what the player and the planner walk; `adj` stays what the crowd walks
var lifts_real := false            # the station has lifts in reality (TfL facility record)
var adj_spiral: Array = []         # adj_lift plus the spiral stair (portals and the helix): the graph of `spiral_mode`
var spirals: Array = []            # the spiral emergency stair(s) of the station (see _add_spirals): {id, steps, rise, top:{pos, front, yaw, out, room}, bot:{...}, tower, tin, tout, tin_dir, tout_dir, interior}
var lift_only := false             # its way up and down is lifts: the escalator-type banks of the plan are replaced by lifts (`removed` banks, lifts in every graph, see _apply_lift_only)
var sf_ok := true                  # every vertical link has a lift, so the whole station can be used step-free
var platform_no: Dictionary = {}   # pid -> 1..N
var _dests: Dictionary = {}
var bounds := AABB()

static var _cache: Dictionary = {}
## Step-free journeys (Settings access/step_free; Game sets it before it plans or builds anything): walking queries use the lift graph, gates the wide lanes.
static var step_free_mode := false
## Lifts in the walking graph of the player and the planner (Game turns it on): a station with real lifts has one beside every escalator / stair bank, usable like the escalator; the
## crowd never uses them. Off in tests that walk plans (route audits pass --lifts).
static var lifts_enabled := false
## The planner may send the player up / down a spiral emergency stair (a bot journey that is meant to use it; off otherwise: the stair is the player's to choose, par times are the lifts')
static var spiral_mode := false

const VA_PATH := "res://data/vertical_access.json"
static var _va: Dictionary = {}
static var _va_loaded := false


## data/vertical_access.json entry of a station (lift-only stations and their spiral stairs), {} when it has none; call once on the main thread before plans are built on workers
static func vertical_access(naptan: String) -> Dictionary:
	if not _va_loaded:
		_va_loaded = true
		if FileAccess.file_exists(VA_PATH):
			var d = JSON.parse_string(FileAccess.get_file_as_string(VA_PATH))
			if d is Dictionary:
				_va = d
	return _va.get(naptan, {})
const LIFT_WAIT := 20.0            # call, wait for the car, doors (s)
const LIFT_SPEED := 0.9            # m/s
const LIFT_DOORS := 12.0           # both door cycles (s)
const LIFT_SIZE := Vector3(2.2, 3.0, 2.4)     # housing: width across the door, height, depth


static func for_station(station_idx: int) -> StationPlan:
	if _cache.has(station_idx):
		return _cache[station_idx]
	var p := StationPlan.new()
	p.generate(station_idx)
	_cache[station_idx] = p
	return p


func _node(n: String, pos: Vector3) -> int:
	if node_idx.has(n):
		return node_idx[n]
	node_idx[n] = nodes.size()
	nodes.append({"name": n, "pos": pos})
	adj.append([])
	return nodes.size() - 1


## the walking pace the par assumes (m/s): a hair below the player's default (Player.WALK_SPEED)
const PLAN_WALK := 1.75


func _edge(a: String, b: String, cost_override := -1.0, speed := PLAN_WALK) -> void:
	var ia: int = node_idx[a]
	var ib: int = node_idx[b]
	var d: float = (nodes[ia]["pos"] as Vector3).distance_to(nodes[ib]["pos"])
	var c := cost_override if cost_override >= 0.0 else d / speed
	edges.append({"a": ia, "b": ib, "len": d, "cost": c})
	adj[ia].append([ib, c, edges.size() - 1])
	adj[ib].append([ia, c, edges.size() - 1])


func generate(station_idx: int) -> void:
	idx = station_idx
	var st: Dictionary = Net.stations[idx]
	name = st["name"]
	kind = st["kind"]
	seed_value = Net.station_seed(idx)
	imp = Net.importance(idx)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# real-world facts (optional): entrances with their real exit numbers/names, gate and escalator counts, real platform numbers
	var naptan: String = Net.station_ids[idx]
	var real: Dictionary = RealData.station(naptan)
	var fac: Dictionary = real.get("facility", {})
	var real_ents: Array = RealData.entrances(naptan)
	var layout: Dictionary = RealData.layout(naptan)
	var real_depths: Dictionary = layout.get("depths", {})
	var hall_drop: float = float(layout.get("hall_depth", 4.0 if kind == "deep" else 3.0))     # ticket hall below street level
	var lspec: Dictionary = RealData.layout_spec(naptan)
	if not lspec.is_empty():
		if LayoutCompiler.compile(self, lspec):
			_add_lifts()
			return
		# a broken authored layout must never break the station: start again from scratch with the generator
		_reset_plan()

	# ---- 1. platform modules: group faces per line group (max 2 faces per module) --------------------------------
	var groups := {}    # group -> [pid...]
	for pid in st["platforms"]:
		var g: String = st["platforms"][pid]["group"]
		if not groups.has(g):
			groups[g] = []
		groups[g].append(pid)
	var mod_defs: Array = []
	for g in groups:
		var pids: Array = groups[g]
		pids.sort()
		var facelist: Array = []
		for pid in pids:
			var terminal: bool = st["platforms"][pid]["terminal"]
			facelist.append({"pid": pid, "face": 0})
			if terminal:
				facelist.append({"pid": pid, "face": 1})
		var i := 0
		while i < facelist.size():
			var fl: Array = [facelist[i]]
			if i + 1 < facelist.size():
				fl.append(facelist[i + 1])
			mod_defs.append({"group": g, "faces": fl})
			i += 2
	# ---- 2. depth per module, sorted shallow -> deep, min 7 m apart -----------------------------------------------
	var nth_of_group := {}
	for md in mod_defs:
		var d: float = BASE_DEPTH.get(String(md["group"]).get_slice(".", 0), 24.0) + rng.randf_range(-2.0, 2.5)
		if imp < 1.6:
			d = minf(d, 18.0 + rng.randf() * 4.0)
		if kind == "surface":
			d = rng.randf_range(5.0, 6.5)
		elif kind == "sub":
			d = rng.randf_range(8.0, 10.5)
		# measured depth (TfL layout diagram): metres below street level -> below the ticket hall
		var g: String = String(md["group"]).get_slice(".", 0)           # branch platforms ("northern.cx") share their line's measured depths
		if real_depths.has(g):
			var lst: Array = real_depths[g]
			var nth: int = nth_of_group.get(g, 0)
			nth_of_group[g] = nth + 1
			d = maxf(float(lst[mini(nth, lst.size() - 1)]) - hall_drop, 3.5)
		md["depth"] = d
	mod_defs.sort_custom(func(a, b): return a["depth"] < b["depth"])
	# cluster modules into levels: those within 4 m share a level (max 2 per level)
	var lvl: Array = []
	for md in mod_defs:
		if lvl.size() > 0 and lvl[-1]["mods"].size() < 2 and absf(md["depth"] - lvl[-1]["depth"]) < 4.5:
			lvl[-1]["mods"].append(md)
			lvl[-1]["depth"] = (lvl[-1]["depth"] + md["depth"]) * 0.5
		else:
			lvl.append({"depth": md["depth"], "mods": [md]})
	var prev_depth := 0.0
	for L in lvl:
		var gap_between := 4.5 if not real_depths.is_empty() else 7.0      # a real flight can be shorter than the generator's minimum
		var min_d: float = prev_depth + (gap_between if prev_depth > 0.0 else (3.5 if not real_depths.is_empty() else (5.0 if kind == "surface" else 8.0)))
		L["depth"] = maxf(L["depth"], min_d)
		prev_depth = L["depth"]

	# ---- 3. ticket hall -----------------------------------------------------------------------------------------------
	var n_real_doors := clampi(real_ents.size(), 0, MAX_STREET_DOORS)
	var hx := clampf(9.0 + 2.2 * imp, 10.0, 21.0)
	if n_real_doors > 3:
		hx = maxf(hx, 2.6 * n_real_doors + 3.0)         # room for the doors (3.2 m wide, at least 5 m apart)
	var hz0 := -clampf(9.0 + 1.6 * imp, 10.0, 16.0)
	var hz1 := 9.0
	hall = {"rect": [-hx, hx, hz0, hz1], "y": 0.0, "h": HALL_H}
	var n_lanes := 3 if imp >= 1.5 else 2
	var real_esc := int(fac.get("escalators", 0))
	if real_esc > 0 and kind == "deep":
		n_lanes = clampi(int(round(float(real_esc) / (float(lvl.size()) + 0.5))), 2, 4)
	# ---- 4. escalators & landings chain (south along +z from the hall's S wall) --------------------------------
	var chain_z := hz1
	var chain_y := 0.0
	var prev_room := "hall"
	var hall_openings: Array = []
	var lanes_pattern := _lane_pattern(rng, n_lanes)
	var landings: Array = []
	for li in lvl.size():
		var depth: float = lvl[li]["depth"]
		var rise := depth - (-chain_y)
		var lanes := lanes_pattern.duplicate()
		var esc_len := Escalator.PLATE * 2.0 + rise / tan(Escalator.ANGLE)
		var esc_id := "esc%d" % li
		var use_stairs := rise < 6.0 or (kind != "deep" and rise < 11.5)     # short flights are stairs, not escalators
		if use_stairs:
			lanes = [1, -1]
		var esc_w: float = lanes.size() * Escalator.PITCH + 0.6
		escs.append({"id": esc_id, "pos": Vector3(0, chain_y, chain_z), "yaw": -PI / 2.0, "rise": rise, "lanes": lanes, "length": esc_len, "width": esc_w, "stairs": use_stairs})
		var n_mod: int = lvl[li]["mods"].size()
		var lz0 := chain_z + esc_len
		var lzlen := 12.0 + 16.0 * (n_mod - 1)
		var ly := -depth
		var lx := 11.0
		var lrect := [-lx, lx, lz0, lz0 + lzlen]
		var lname := "landing%d" % li
		var openings := [{"side": "N", "c": 0.0, "w": esc_w, "h": Escalator.CLEARANCE, "id": esc_id + "_bot"}]
		landings.append({"name": lname, "rect": lrect, "y": ly, "h": LANDING_H, "openings": openings, "level": li})
		if prev_room == "hall":
			hall_openings.append({"side": "S", "c": 0.0, "w": esc_w, "h": Escalator.CLEARANCE, "id": esc_id + "_top"})
		else:
			# opening in the previous landing's S wall
			var pl: Dictionary = landings[li - 1]
			pl["openings"].append({"side": "S", "c": 0.0, "w": esc_w, "h": Escalator.CLEARANCE, "id": esc_id + "_top"})
		lvl[li]["landing"] = landings[-1]
		lvl[li]["esc_id"] = esc_id
		chain_z = lz0 + lzlen
		chain_y = ly
		prev_room = lname

	# ---- 5. modules east of each landing --------------------------------------------------------------------------------
	for li in lvl.size():
		var Ld: Dictionary = lvl[li]["landing"]
		var rect: Array = Ld["rect"]
		var mods: Array = lvl[li]["mods"]
		for mi in mods.size():
			var md: Dictionary = mods[mi]
			var lane_z: float = (rect[2] + rect[3]) * 0.5 if mods.size() == 1 else (rect[2] + 6.5 + mi * 16.0)
			var group: String = md["group"]
			var line_id := _line_of_group(st, group)
			var cars: Array = CARS.get(line_id, [6, 16.0])
			var L: float = cars[0] * cars[1] + 10.0
			var pw := PlatformModule.PW_RUN
			var corr_len := PlatformModule.TUNNEL_MIN + 6.0 + rng.randf() * 10.0      # the platform tunnel stops before the landing, so the passage is at least as long as the tunnel we keep
			var is_box: bool = StationCharacter.platform_is_box(name, line_id, kind)
			var spine_x0 := -L * 0.5 if is_box else -L * 0.5 - 6.0
			var mx: float = rect[1] + corr_len - spine_x0
			var mpos := Vector3(mx, -lvl[li]["depth"], lane_z)
			var faces_spec: Array = []
			for fdef in md["faces"]:
				var pid: String = fdef["pid"]
				var pl: Dictionary = st["platforms"][pid]
				var lid: String = pl["lines"][0]
				faces_spec.append({"pid": pid, "line": lid, "color": Net.line_color(lid), "label": dir_text(pid), "face": fdef["face"], "lines": pl["lines"]})
			var openings_x := [-L * 0.5 + 8.0, -L * 0.5 + 8.0 + 14.0]
			var wall_style := "tile_cream" if (seed_value + mi) % 3 == 0 else "tile_white"
			var stripes := _stripes_for(seed_value + mi, faces_spec[0]["color"])
			var character := StationCharacter.platform(name, faces_spec[0]["line"], kind)
			if not character.is_empty():
				wall_style = character["wall"]
				stripes = character["stripes"]
			var tun_w := corr_len - spine_x0 - L * 0.5 - 1.0     # distance from the platform's west end to the landing wall, minus a metre of rock
			var mspec := {"tun_w": tun_w, "style": "box" if is_box else "arch", "roof": StationCharacter.platform_roof(name, line_id, kind), "length": L, "pw": pw, "wall": wall_style, "stripes": stripes, "seed": seed_value + li * 7 + mi, "faces": faces_spec, "character": character,
				"openings_x": openings_x, "spine_x0": spine_x0, "spine_x1": -L * 0.5 + 8.0 + 14.0 + 6.0, "name": name, "group": group}
			var midx := modules.size()
			modules.append({"pos": mpos, "spec": mspec, "faces": md["faces"], "level": li, "group": group, "lane_z": lane_z, "corr": [rect[1], mpos.x + spine_x0]})
			Ld["openings"].append({"side": "E", "c": lane_z, "w": CORR_W, "h": SPINE_H, "id": "corr%d_%d" % [li, mi]})
			rooms.append({"name": "corridor%d_%d" % [li, mi], "rect": [rect[1], mpos.x + spine_x0, lane_z - CORR_W * 0.5, lane_z + CORR_W * 0.5], "y": mpos.y, "h": SPINE_H,
				"open_ends": ["E", "W"], "wall": wall_style, "floor": "floor_platform", "lights": "strip_x", "light_dx": 4.0, "seed": seed_value + midx,
				"bands": StationCharacter.stripe_bands(stripes, SPINE_H) if not character.is_empty() else []})
			for fi in faces_spec.size():
				var f: Dictionary = faces_spec[fi]
				var side: float = 1.0 if fi == 0 else -1.0
				var key := "%s#%d" % [f["pid"], f["face"]]
				var zwall := PlatformModule.GAP * 0.5
				var edge_z := side * (zwall + pw)
				faces[key] = {"module": midx, "face": fi, "pid": f["pid"], "face_no": f["face"], "line": f["line"],
					"pos": mpos + Vector3(0, 0, edge_z - side * 1.0), "edge_z": mpos.z + edge_z, "side": side, "x0": mpos.x - L * 0.5, "x1": mpos.x + L * 0.5, "y": mpos.y,
					"track_z": mpos.z + side * (zwall + pw + PlatformModule.TRACK_TO_EDGE), "length": L, "pw": pw, "cars": cars}

	# ---- 6. hall fittings: street doors, gateline ------------------------------------------------------------------------
	var n_doors := clampi(int(round(1.0 + imp * 0.6)), 1, 3)
	if n_real_doors > 0:
		n_doors = n_real_doors
	var door_cs: Array = []
	for i in n_doors:
		var c: float = 0.0 if n_doors == 1 else lerpf(-hx * 0.55, hx * 0.55, float(i) / (n_doors - 1))
		door_cs.append(c)
		hall_openings.append({"side": "N", "c": c, "w": 3.2, "h": 3.0, "id": "street%d" % i})
	var street_len := 6.0 + rng.randf() * 4.0
	for i in n_doors:
		var c: float = door_cs[i]
		var sdoor := {"id": "street%d" % i, "pos": Vector3(c, 0.0, hz0 - street_len + 0.4), "dir": Vector3(0, 0, -1), "c": c, "len": street_len}
		if i < n_real_doors:
			var re: Dictionary = real_ents[i]
			sdoor["exit_ref"] = str(re.get("ref", ""))
			sdoor["exit_name"] = RealData.street_of(re)
		street_doors.append(sdoor)
		rooms.append({"name": "street_passage%d" % i, "rect": [c - 1.6, c + 1.6, hz0 - street_len, hz0], "y": 0.0, "h": 3.0, "open_ends": ["S"], "wall": "tile_white", "floor": "floor_hall", "lights": "strip_z", "light_dz": 3.5, "seed": seed_value + 90 + i}.merged(_passage_finish(), true))
	var gate_z := hz0 + 8.0
	var n_gates := clampi(int(4 + imp * 1.8), 4, 14)
	var real_gates := int(fac.get("gates", 0))
	if real_gates > 0:
		n_gates = clampi(int(round(float(real_gates) / maxf(1.0, float(fac.get("ticket_halls", 1))))), 3, 16)
	var lane_defs: Array = []
	var total_w := 0.0
	for gi in n_gates:
		var wide := gi == 0 or gi == n_gates - 1        # accessible lanes at both ends of the line
		var lw := 1.23 if wide else 0.93
		lane_defs.append({"w": lw, "wide": wide, "kind": (1 if gi < (n_gates + 1) / 2 else -1)})
		total_w += lw
	var gx := -total_w * 0.5
	for ld in lane_defs:
		ld["x"] = gx + ld["w"] * 0.5
		gx += ld["w"]
	gates = {"z": gate_z, "x0": -hx + 0.3, "x1": hx - 0.3, "n": n_gates, "pitch": 0.93, "lanes": lane_defs, "total_w": total_w, "cx": 0.0, "hall": "hall", "rect": hall["rect"]}
	gatelines = [gates]
	var hall_room := {"name": "hall", "rect": hall["rect"], "y": 0.0, "h": HALL_H, "openings": hall_openings, "wall": "tile_white", "floor": "floor_hall", "lights": "grid",
		"light_dx": 4.5, "light_dz": 5.0, "seed": seed_value, "band": Color(0.02, 0.18, 0.5)}
	hall_room.merge(StationCharacter.hall(name), true)
	rooms.append(hall_room)
	for L2 in landings:
		L2["wall"] = "tile_white"
		L2["floor"] = "floor_hall"
		L2["lights"] = "grid"
		L2["light_dx"] = 4.5
		L2["light_dz"] = 5.0
		L2["seed"] = seed_value + 30 + int(L2["level"])
		L2["band"] = Color(0.02, 0.18, 0.5)
		rooms.append(L2)

	# ---- 7. walking graph ---------------------------------------------------------------------------------------------------
	var hy := 0.0
	_node("hall_unpaid", Vector3(0, hy, gate_z - 2.5))
	_node("hall_paid", Vector3(0, hy, gate_z + 3.0))
	_node("gate_in", Vector3(0, hy, gate_z - 0.9))
	_node("gate_out", Vector3(0, hy, gate_z + 0.9))
	for sd in street_doors:
		_node(sd["id"], sd["pos"])
		_edge(sd["id"], "hall_unpaid")
	_edge("hall_unpaid", "gate_in")
	_edge("gate_in", "gate_out", 3.5)          # tapping through the barrier (approx.)
	_edge("gate_out", "hall_paid")
	var prev_node := "hall_paid"
	for li in lvl.size():
		var e: Dictionary = escs[li]
		var Ld: Dictionary = lvl[li]["landing"]
		var r: Array = Ld["rect"]
		var top_name := "esc%d_top" % li
		var bot_name := "esc%d_bot" % li
		_node(top_name, e["pos"] + Vector3(0, 0, 1.0))
		_node(bot_name, Vector3(0, Ld["y"], r[2] + 1.0))
		_edge(prev_node, top_name)
		var slope_len: float = e["rise"] / sin(Escalator.ANGLE)
		_edge(top_name, bot_name, slope_len / 1.15 + 3.0)   # mix of standing and walking on the escalator + boarding
		var lc := "landing%d" % li
		_node(lc, Vector3(0, Ld["y"], (r[2] + r[3]) * 0.5))
		_edge(bot_name, lc)
		if li + 1 < lvl.size():
			var pn := "landing%d_s" % li
			_node(pn, Vector3(0, Ld["y"], r[3] - 1.0))
			_edge(lc, pn)
			prev_node = pn
	for mi in modules.size():
		var m: Dictionary = modules[mi]
		var li: int = m["level"]
		var lc := "landing%d" % li
		var mp: Vector3 = m["pos"]
		var spec: Dictionary = m["spec"]
		var sp_in := "m%d_spine" % mi
		_node(sp_in, Vector3(mp.x + spec["spine_x0"] + 3.0, mp.y, m["lane_z"]))
		_edge(lc, sp_in)
		var ox: Array = spec["openings_x"]
		var prev_open := sp_in
		for oi in ox.size():
			var on := "m%d_open%d" % [mi, oi]
			_node(on, Vector3(mp.x + ox[oi], mp.y, m["lane_z"]))
			_edge(prev_open, on)
			prev_open = on
		for fi in m["faces"].size():
			var fdef: Dictionary = m["faces"][fi]
			var key := "%s#%d" % [fdef["pid"], fdef["face"]]
			var fc: Dictionary = faces[key]
			var mid := "face:" + key
			_node(mid, Vector3(mp.x, mp.y, fc["pos"].z))
			for oi in ox.size():
				# entering the platform through the opening: walk to the platform centre along the platform
				var pn2 := "m%d_open%d_p%d" % [mi, oi, fi]
				_node(pn2, Vector3(mp.x + ox[oi], mp.y, fc["pos"].z))
				_edge("m%d_open%d" % [mi, oi], pn2)
				_edge(pn2, mid)
	finish_common(rng)


## platform numbers (real where TfL has them), bounds and start spots; shared by the generator and LayoutCompiler
func finish_common(rng: RandomNumberGenerator = null) -> void:
	var st: Dictionary = Net.stations[idx]
	var naptan: String = Net.station_ids[idx]
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = seed_value + 5150
	bounds = AABB(Vector3(-40, -40, -40), Vector3(400, 60, 400))
	var pn := 1
	for m in modules:
		for fd in m["faces"]:
			if not platform_no.has(fd["pid"]):
				platform_no[fd["pid"]] = pn
				pn += 1
	# real platform numbers where TfL data has them (only if they are all distinct: the signage relies on unique numbers)
	var real_no := {}
	var used := {}
	for pid in platform_no:
		var pl: Dictionary = st["platforms"][pid]
		var best := int(pl.get("number", 0))          # branch junction platforms carry their own real number (data/junctions.json)
		for lid in pl["lines"]:
			if best > 0 and pl.has("number"):
				break
			var n := RealData.platform_number(naptan, lid, pl["dir"])
			if n > 0 and (best == 0 or n < best):
				best = n
		if best > 0 and not used.has(best):
			used[best] = true
			real_no[pid] = best
	if real_no.size() == platform_no.size():
		platform_no = real_no
	for mi in modules.size():
		modules[mi]["bend"] = PlatformCurve.for_module(self, mi)         # curved platforms (Bank, Liverpool Street ...): {} for a straight one
	_add_start_spots(rng)
	_add_lifts()


func _reset_plan() -> void:
	authored = false        # a plan that fell back to the generator is not an authored one (layouts_test / route_audit rely on this)
	hall = {}
	rooms = []
	escs = []
	modules = []
	levels = []
	street_doors = []
	gates = {}
	gatelines = []
	faces = {}
	nodes = []
	node_idx = {}
	edges = []
	adj = []
	start_spots = []
	platform_no = {}
	lifts = []
	adj_sf = []
	adj_lift = []
	lifts_real = false
	lift_only = false
	spirals = []
	adj_spiral = []
	sf_ok = true


func station_platform(pid: String) -> Dictionary:
	return Net.stations[idx]["platforms"][pid]


## "Northbound", or at a branch junction "Northbound via Bank" / "Southbound Edgware branch" (data/junctions.json)
func dir_text(pid: String) -> String:
	var pl := station_platform(pid)
	var b: String = pl.get("branch", "")
	return pl["dir"] if b == "" else "%s %s" % [pl["dir"], b]


## Destination station names served by platform `pid` at this station (final stops of the services that use it).
func dests(pid: String) -> Array:
	if _dests.has(pid):
		return _dests[pid]
	var out: Array = []
	var st: Dictionary = Net.stations[idx]
	for lid in st["platforms"][pid]["lines"]:
		for svc in Net.lines[lid]["services"]:
			var stops: PackedInt32Array = svc["stop_idx"]
			for i in stops.size():
				if stops[i] != idx:
					continue
				var d := -1
				if svc["plat_fwd"][i] == pid and i < stops.size() - 1:
					d = stops[stops.size() - 1]
				elif svc["plat_bwd"][i] == pid and i > 0:
					d = stops[0]
				if d >= 0:
					var nm: String = Net.station_name(d).replace(" (Circle)", "").replace(" (H&C)", "").replace(" (D&P)", "")
					if not out.has(nm):
						out.append(nm)
	out.sort()
	_dests[pid] = out
	return out


func dest_text(pid: String, max_n := 3) -> String:
	var d := dests(pid)
	if d.size() <= max_n:
		return ", ".join(d)
	return ", ".join(d.slice(0, max_n)) + "..."


const DADO_COLORS := [Color(0.62, 0.42, 0.55), Color(0.18, 0.45, 0.30), Color(0.15, 0.30, 0.62), Color(0.55, 0.30, 0.16), Color(0.45, 0.47, 0.50), Color(0.72, 0.62, 0.40)]


## the street passages take their hall's wall, floor and bands (brick at a Holden hall, terracotta at a Leslie Green one ...)
func _passage_finish() -> Dictionary:
	var h := StationCharacter.hall(name)
	if h.is_empty():
		return {}
	return {"wall": h["wall"], "floor": h["floor"], "bands": h["bands"], "light_color": h.get("light_color", Color(1.0, 0.97, 0.92))}


func _stripes_for(sd: int, line_col: Color) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = sd * 31 + 7
	var kind := r.randi() % 4
	var black := Color(0.02, 0.02, 0.02)
	match kind:
		0:
			return [{"y0": 1.15, "y1": 1.42, "color": line_col}]
		1:
			return [{"y0": 0.60, "y1": 0.70, "color": black}, {"y0": 0.98, "y1": 1.08, "color": black}, {"y0": 1.95, "y1": 2.03, "color": line_col}]
		2:
			var dc: Color = DADO_COLORS[r.randi() % DADO_COLORS.size()]
			return [{"y0": -1.15, "y1": 1.10, "color": dc, "dado": true}, {"y0": 1.10, "y1": 1.18, "color": black}, {"y0": 1.18, "y1": 1.24, "color": Color(0.92, 0.9, 0.8)}]
	return [{"y0": 0.25, "y1": 0.55, "color": Color(0.03, 0.03, 0.03)}, {"y0": 1.40, "y1": 1.47, "color": line_col}]


func _lane_pattern(rng: RandomNumberGenerator, n: int) -> Array:
	if n == 2:
		return [1, -1]
	if n >= 4:
		var pats4 := [[1, -1, 1, -1], [1, 1, -1, 1], [-1, 1, 1, -1]]
		return pats4[rng.randi() % pats4.size()]
	var pats := [[1, -1, 1], [-1, 1, -1], [1, 1, -1]]
	return pats[rng.randi() % pats.size()]


func _line_of_group(st: Dictionary, group: String) -> String:
	for pid in st["platforms"]:
		var p: Dictionary = st["platforms"][pid]
		if p["group"] == group:
			return p["lines"][0]
	return "northern"


func _add_start_spots(rng: RandomNumberGenerator) -> void:
	# a few candidate start positions: street entrance, unpaid hall, paid hall, landing, platforms
	for sd in street_doors:
		start_spots.append({"name": "street entrance", "pos": sd["pos"] + Vector3(0, 0, 1.5), "yaw": 0.0, "node": sd["id"], "weight": 3.0})
	for gi in gatelines.size():
		var gl: Dictionary = gatelines[gi]
		var pre := "" if gi == 0 else str(gi + 1)
		var gcx: float = gl.get("cx", 0.0)
		start_spots.append({"name": "ticket hall", "pos": Vector3(gcx + rng.randf_range(-6, 6), 0.0, gl["z"] - 4.0 - rng.randf() * 2.0), "yaw": 0.0, "node": "hall%s_unpaid" % pre, "weight": 2.0})
		start_spots.append({"name": "concourse", "pos": Vector3(gcx + rng.randf_range(-6, 6), 0.0, gl["z"] + 3.0 + rng.randf() * 3.0), "yaw": PI, "node": "hall%s_paid" % pre, "weight": 1.5})
	for f in faces:
		var fc: Dictionary = faces[f]
		start_spots.append({"name": "platform", "pos": Vector3(fc["pos"].x + rng.randf_range(-20, 20), fc["y"], fc["pos"].z), "yaw": (PI * 0.5 if rng.randf() < 0.5 else -PI * 0.5), "node": "face:" + f, "weight": 1.0, "face": f})


# ---------------------------------------------------------------------------------------------------
# Walking-time queries (seconds) on the graph
# ---------------------------------------------------------------------------------------------------
## which walking graph a query uses: 2 = step-free (lifts, no escalators), 1 = with lifts (stations that have them), 3 = with lifts and the spiral emergency stair (`spiral_mode`), 0 = the crowd's (escalators and stairs only)
func _graph_kind(sf: bool, lifts: bool) -> int:
	if sf and not adj_sf.is_empty():
		return 2
	if lifts and lifts_real and not adj_lift.is_empty():
		return 3 if (spiral_mode and not adj_spiral.is_empty()) else 1
	return 0


func _adjacency(kind: int) -> Array:
	return adj_sf if kind == 2 else (adj_spiral if kind == 3 else (adj_lift if kind == 1 else adj))


func dijkstra(from_name: String, sf := step_free_mode, lifts := lifts_enabled) -> Dictionary:
	var A: Array = _adjacency(_graph_kind(sf, lifts))
	var dist := {}
	var n := nodes.size()
	var d := PackedFloat64Array()
	d.resize(n)
	d.fill(1e9)
	var src: int = node_idx[from_name]
	d[src] = 0.0
	var open: Array = [[0.0, src]]
	while open.size() > 0:
		# tiny graph: linear extraction is fine
		var bi := 0
		for i in open.size():
			if open[i][0] < open[bi][0]:
				bi = i
		var cur: Array = open[bi]
		open.remove_at(bi)
		if cur[0] > d[cur[1]]:
			continue
		for e in A[cur[1]]:
			var nd: float = cur[0] + e[1]
			if nd < d[e[0]]:
				d[e[0]] = nd
				open.append([nd, e[0]])
	for i in n:
		dist[nodes[i]["name"]] = d[i]
	return dist


## node-name path from a to b (shortest by cost); empty if unreachable
func path(a: String, b: String, sf := step_free_mode, lifts := lifts_enabled) -> Array:
	var A: Array = _adjacency(_graph_kind(sf, lifts))
	var n := nodes.size()
	var d := PackedFloat64Array()
	d.resize(n)
	d.fill(1e18)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var src: int = node_idx[a]
	var dst: int = node_idx[b]
	d[src] = 0.0
	var open: Array = [[0.0, src]]
	while open.size() > 0:
		var bi := 0
		for i in open.size():
			if open[i][0] < open[bi][0]:
				bi = i
		var cur: Array = open[bi]
		open.remove_at(bi)
		if cur[0] > d[cur[1]]:
			continue
		if cur[1] == dst:
			break
		for e in A[cur[1]]:
			var nd: float = cur[0] + e[1]
			if nd < d[e[0]]:
				d[e[0]] = nd
				prev[e[0]] = cur[1]
				open.append([nd, e[0]])
	if d[dst] >= 1e17:
		return []
	var out: Array = []
	var c := dst
	while c != -1:
		out.push_front(nodes[c]["name"])
		c = prev[c]
	return out


## plan-space point from an escalator-local point
func esc_point(ei: int, local: Vector3) -> Vector3:
	var e: Dictionary = escs[ei]
	return (e["pos"] as Vector3) + Basis(Vector3.UP, e["yaw"]) * local


func esc_lane_z(ei: int, li: int) -> float:
	var n: int = (escs[ei]["lanes"] as Array).size()
	return (li - (n - 1) * 0.5) * Escalator.PITCH


## which lane of escalator `ei` moves in direction `dir` (+1 down / -1 up); `pick` chooses among several
func esc_lane_for(ei: int, dir: int, pick := 0) -> int:
	var idxs: Array = []
	var lanes: Array = escs[ei]["lanes"]
	for i in lanes.size():
		if lanes[i] == dir:
			idxs.append(i)
	if idxs.is_empty():
		return 0
	return idxs[pick % idxs.size()]


# ---------------------------------------------------------------------------------------------------
# Lifts (step-free journeys)
# ---------------------------------------------------------------------------------------------------
func _is_esc_edge(ei: int) -> bool:
	if ei < 0:
		return false
	var a: String = nodes[edges[ei]["a"]]["name"]
	var b: String = nodes[edges[ei]["b"]]["name"]
	return (a.begins_with("esc") and a.ends_with("_top") and b.begins_with("esc") and b.ends_with("_bot")) or (a.begins_with("esc") and a.ends_with("_bot") and b.begins_with("esc") and b.ends_with("_top"))


## names of the rooms an escalator / stair bank joins (top room, bottom room): authored plans name them, the generator's chain is hall -> landing0 -> landing1 ...
func _esc_rooms(ei: int) -> Array:
	var e: Dictionary = escs[ei]
	if e.has("from"):
		return [String(e["from"]), String(e["to"])]
	return ["hall" if ei == 0 else "landing%d" % (ei - 1), "landing%d" % ei]


func _room_named(n: String) -> Dictionary:
	for rm in rooms:
		if rm["name"] == n:
			return rm
	return {}


## the footprint of an escalator-local rectangle (x0..x1 along the escalator, z0..z1 across) as a plan-space xz rectangle [xmin, xmax, zmin, zmax]
func _esc_rect(ei: int, x0: float, x1: float, z0: float, z1: float) -> Array:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for cx in [x0, x1]:
		for cz in [z0, z1]:
			var p := esc_point(ei, Vector3(cx, 0.0, cz))
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	return [lo.x, hi.x, lo.y, hi.y]


func _rect_inside(inner: Array, outer: Array, margin: float) -> bool:
	return inner[0] >= outer[0] + margin and inner[1] <= outer[1] - margin and inner[2] >= outer[2] + margin and inner[3] <= outer[3] - margin


func _rects_overlap(a: Array, b: Array, margin: float) -> bool:
	return a[0] < b[1] + margin and a[1] > b[0] - margin and a[2] < b[3] + margin and a[3] > b[2] - margin


## a lift housing beside the mouth of escalator `ei` on one side of the bank (top = in the upper room, bottom = in the lower one): the first of the two sides where the housing and the
## space in front of its door lie inside the room, clear of the room's other openings, other lifts and the escalators' own shafts. Returns {} when neither fits.
func _lift_side(ei: int, top: bool, taken: Array, centred := false) -> Dictionary:
	var e: Dictionary = escs[ei]
	var room := _room_named(String(_esc_rooms(ei)[0 if top else 1]))
	if room.is_empty() or not room.has("rect"):
		return {}
	var rect: Array = room["rect"]
	var w: float = e["width"]
	var len: float = e["length"]
	var rise: float = e["rise"]
	var depth := LIFT_SIZE.z
	var across := LIFT_SIZE.x
	# a removed bank (lift-only station): the lifts stand where the escalator's opening was, in the wall that is now closed: one housing, two side by side in a wide bank
	var n_house := 2 if (centred and w >= 4.8) else 1
	for side in ([1.0] if centred else [1.0, -1.0]):
		var zc: float = 0.0 if centred else side * (w * 0.5 + 0.6 + across * 0.5)
		# the housing against the wall the escalator pierces, the door on the room side
		var hx0: float = -depth if top else len
		var hx1: float = 0.0 if top else len + depth
		var fx0: float = hx0 - 1.6 if top else hx1
		var fx1: float = hx0 if top else hx1 + 1.6
		var span: float = across * 0.5 + (0.0 if n_house == 1 else across * 0.5 + 0.15)
		var house := _esc_rect(ei, hx0, hx1, zc - span, zc + span)
		var front := _esc_rect(ei, fx0, fx1, zc - span, zc + span)
		var both := [minf(house[0], front[0]), maxf(house[1], front[1]), minf(house[2], front[2]), maxf(house[3], front[3])]
		if not (_rect_inside(house, rect, -0.01) and _rect_inside(front, rect, 0.4)):
			continue                       # (the housing stands against the wall: only the space in front of its door needs a margin)
		var clash := false
		for op in room.get("openings", []):
			var o: Dictionary = op
			if centred:
				break                     # (the closed opening is exactly where the lifts go)
			var c: float = float(o["c"])
			var half: float = float(o["w"]) * 0.5
			var orect: Array
			match String(o["side"]):
				"N":
					orect = [c - half, c + half, rect[2], rect[2] + 1.4]
				"S":
					orect = [c - half, c + half, rect[3] - 1.4, rect[3]]
				"W":
					orect = [rect[0], rect[0] + 1.4, c - half, c + half]
				_:
					orect = [rect[1] - 1.4, rect[1], c - half, c + half]
			# (the opening of this escalator itself is where the housing stands next to: only its neighbours count)
			if String(o.get("id", "")).begins_with("esc%d_" % ei):
				continue
			if _rects_overlap(both, orect, 0.3):
				clash = true
		for t in taken:
			if _rects_overlap(both, t, 0.3):
				clash = true
		if clash:
			continue
		var xc: float = (hx0 + hx1) * 0.5
		var door_x: float = hx0 if top else hx1
		var floor_y: float = 0.0 if top else -rise
		var front_x: float = door_x - 1.1 if top else door_x + 1.1
		var yaw: float = float(e["yaw"]) + (PI * 0.5 if top else -PI * 0.5)
		var res := {"pos": esc_point(ei, Vector3(xc, floor_y, zc)), "front": esc_point(ei, Vector3(front_x, floor_y, zc)), "yaw": yaw, "y": floor_y, "footprint": both, "side": side, "extra": []}
		if n_house == 2:
			# two housings side by side: the first two are the ones at +-(across / 2 + 0.075), the node in front of the pair stays in the middle
			res["pos"] = esc_point(ei, Vector3(xc, floor_y, zc - across * 0.5 - 0.075))
			res["front_a"] = esc_point(ei, Vector3(front_x, floor_y, zc - across * 0.5 - 0.075))
			res["extra"] = [{"pos": esc_point(ei, Vector3(xc, floor_y, zc + across * 0.5 + 0.075)), "front": esc_point(ei, Vector3(front_x, floor_y, zc + across * 0.5 + 0.075)), "yaw": yaw}]
		return res
	return {}


## Lifts for every escalator / stair bank: a housing at each end beside the mouth, a node in front of each door joined to the room's walking graph, and a lift edge between them
## (call + ride + doors) that only the step-free graph `adj_sf` has; that graph lacks the escalator edges. Without a lift for some bank the station is not usable step-free (sf_ok false).
func _add_lifts() -> void:
	lifts = []
	adj_sf = []
	adj_lift = []
	sf_ok = true
	lifts_real = int((RealData.station(Net.station_ids[idx]).get("facility", {}) as Dictionary).get("lifts", 0)) > 0
	lift_only = bool(vertical_access(Net.station_ids[idx]).get("lift_only", false)) and lifts_real
	if lift_only:
		_apply_lift_only()
	spirals = []
	adj_spiral = []
	for i in adj.size():
		var kept: Array = []
		for e in adj[i]:
			if not _is_esc_edge(int(e[2])):
				kept.append(e)
		adj_sf.append(kept)
		adj_lift.append(adj[i].duplicate())
	var taken: Array = []
	for ei in escs.size():
		var removed: bool = escs[ei].get("removed", false)
		var top := _lift_side(ei, true, taken, removed)
		var bot := _lift_side(ei, false, taken, removed)
		if top.is_empty() or bot.is_empty():
			sf_ok = false
			continue
		taken.append(top["footprint"])
		taken.append(bot["footprint"])
		var rise: float = escs[ei]["rise"]
		var t: float = LIFT_WAIT + rise / LIFT_SPEED + LIFT_DOORS
		var tn := "lift%d_top" % ei
		var bn := "lift%d_bot" % ei
		_node(tn, top["front"])
		_node(bn, bot["front"])
		while adj_sf.size() < adj.size():
			adj_sf.append([])
			adj_lift.append([])
		var top_access := _access_node(ei, true)
		var bot_access := _access_node(ei, false)
		if top_access == "" or bot_access == "":
			sf_ok = false
			continue
		_edge_sf(tn, top_access, -1.0)
		_edge_sf(bn, bot_access, -1.0)
		_edge_sf(tn, bn, t)
		if removed:
			# a lift-only station's lifts are its only link here: the crowd's graph has them too
			_edge_plain(tn, top_access, -1.0)
			_edge_plain(bn, bot_access, -1.0)
			_edge_plain(tn, bn, t)
		lifts.append({"id": "lift%d" % ei, "esc": ei, "rise": rise, "time": t, "top": top, "bot": bot, "removed": removed})
	_add_spirals(taken)


## the walking-graph node that the lift's door-front node hangs on: authored plans have a node set back from the mouth (escN_pre / escN_post), otherwise the nearest node on the same
## floor at least 2.5 m from the mouth (the barrier across the mouth must not stand on the route)
func _access_node(ei: int, top: bool) -> String:
	var removed: bool = escs[ei].get("removed", false)
	var pre := "esc%d_%s" % [ei, "pre" if top else "post"]
	if node_idx.has(pre) and not removed:
		return pre
	var me := "esc%d_%s" % [ei, "top" if top else "bot"]
	var mouth: Vector3 = nodes[node_idx[me]]["pos"]
	var room := _room_named(String(_esc_rooms(ei)[0 if top else 1]))
	var rrect: Array = room.get("rect", [-1e9, 1e9, -1e9, 1e9])
	var seen := {node_idx[me]: true}
	var queue: Array = [node_idx[me]]
	var fallback := ""
	while not queue.is_empty():
		var u: int = queue.pop_front()
		for e in adj[u]:
			var v: int = e[0]
			if seen.has(v) or _is_esc_edge(int(e[2])):
				continue
			seen[v] = true
			var np: Vector3 = nodes[v]["pos"]
			if absf(np.y - mouth.y) > 1.5:
				continue
			if np.x < rrect[0] + 0.5 or np.x > rrect[1] - 0.5 or np.z < rrect[2] + 0.5 or np.z > rrect[3] - 0.5:
				queue.append(v)               # (a node in the passage beyond the room: the straight way to it would cut the wall; keep looking from there)
				continue
			if fallback == "":
				fallback = nodes[v]["name"]
			if np.distance_to(mouth) >= (LIFT_SIZE.z + 2.6 if removed else 2.5):
				return nodes[v]["name"]          # (a removed bank's lifts stand in the old opening: the node must be in front of them)
			queue.append(v)
	return fallback


## The spiral emergency stair of a station that has one (data/vertical_access.json): a door in a wall of the ticket hall and one in the deepest landing, joined by the stair itself, a tower
## (SpiralStair) far from everything else that the doors are portals to. Graph: top door front - tower top entry (portal), tower top - tower bottom (the walk down the helix), tower bottom -
## bottom door front (portal); only the player's and the planner's graph (adj_lift) has them. Needs a free stretch of wall in both rooms.
const SPIRAL_DOOR_W := 1.4
const SPIRAL_DOOR_D := 0.5
const SPIRAL_S_PER_STEP := 0.5        # seconds a step takes on average (Player: about 0.6 up, 0.4 down on the helix)


func _add_spirals(taken: Array) -> void:
	var va := vertical_access(Net.station_ids[idx])
	if not va.has("spiral"):
		return
	# the rooms: the ticket hall and the deepest room that has platforms
	var top_room := _room_named("hall")
	var bot_room: Dictionary = {}
	for m in modules:
		var rn := String(m.get("room", "landing%d" % int(m["level"])))
		var rm := _room_named(rn)
		if not rm.is_empty() and (bot_room.is_empty() or float(rm["y"]) < float(bot_room["y"])):
			bot_room = rm
	if top_room.is_empty() or bot_room.is_empty():
		return
	var rise := float(top_room.get("y", 0.0)) - float(bot_room["y"])
	if rise < 6.0:
		return
	var steps_src = (va["spiral"] as Dictionary).get("steps", null)
	var steps: int = int(steps_src) if steps_src != null else int(round(rise / 0.18))
	var near_top := Vector2.ZERO
	var near_bot := Vector2.ZERO
	for lf in lifts:
		var t: Dictionary = lf["top"]
		var b: Dictionary = lf["bot"]
		if _room_of_point(t["pos"]) == String(top_room["name"]):
			near_top = Vector2(t["pos"].x, t["pos"].z)
		if _room_of_point(b["pos"]) == String(bot_room["name"]):
			near_bot = Vector2(b["pos"].x, b["pos"].z)
	var top_spot := _wall_spot(top_room, taken, near_top, true)
	var bot_spot := _wall_spot(bot_room, taken, near_bot, false)
	if top_spot.is_empty() or bot_spot.is_empty():
		push_warning("%s: no free wall for the spiral stair's doors" % name)
		return
	# the tower: east of everything (rooms and the platform tunnels), at ground level of the plan
	var xmax := -1e9
	for rm in rooms:
		xmax = maxf(xmax, float((rm["rect"] as Array)[1]))
	for m in modules:
		var ln: float = float((m["spec"] as Dictionary).get("length", 110.0))
		var tun: float = float((m["spec"] as Dictionary).get("tun_e", PlatformModule.TUNNEL_EXT))
		xmax = maxf(xmax, (m["pos"] as Vector3).x + ln * 0.5 + tun)
	var tower := Vector3(xmax + 60.0, float(top_room.get("y", 0.0)), 0.0)
	var d_in := SpiralStair.s_top_entry(steps, rise)
	var d_out := SpiralStair.s_bottom_exit(steps, rise)
	var down_dir := SpiralStair.s_tangent(-SpiralStair.s_dtheta() * 0.6)
	var up_dir := -SpiralStair.s_tangent(SpiralStair.s_dtheta() * (steps - 1 + 0.9))
	var interior: Array = []
	for pt in SpiralStair.s_walk_points(steps, rise):
		interior.append(tower + pt)
	var sp := {"id": "spiral0", "steps": steps, "rise": rise, "riser": rise / steps, "top": top_spot, "bot": bot_spot, "tower": tower, "tin": tower + d_in, "tout": tower + d_out,
		"tin_dir": down_dir, "tout_dir": up_dir, "interior": interior, "known": steps_src != null}
	sp["top"]["room"] = String(top_room["name"])
	sp["bot"]["room"] = String(bot_room["name"])
	# graph: the door fronts hang on the room's walking graph (adj_lift), the stair itself is only in `adj_spiral` (used when `spiral_mode` is on): the planner never sends anybody up the
	# emergency stair, the par times are the lifts', but a player can walk it and the bot can be told to
	var ta: String = top_spot["attach"]
	var ba: String = bot_spot["attach"]
	taken.append(top_spot["footprint"])
	taken.append(bot_spot["footprint"])
	var tn := "spiral0_top"
	var tin := "spiral0_tin"
	var tout := "spiral0_tout"
	var bn := "spiral0_bot"
	_node(tn, top_spot["front"])
	_node(tin, sp["tin"])
	_node(tout, sp["tout"])
	_node(bn, bot_spot["front"])
	while adj_lift.size() < adj.size():
		adj_lift.append([])
		adj_sf.append([])
	_edge_lift_only(tn, ta, -1.0)
	_edge_lift_only(bn, ba, -1.0)
	adj_spiral = []
	for a in adj_lift:
		adj_spiral.append((a as Array).duplicate())
	_edge_spiral(tn, tin, 3.0)
	_edge_spiral(tin, tout, 3.0 + steps * SPIRAL_S_PER_STEP)
	_edge_spiral(tout, bn, 3.0)
	spirals.append(sp)


func _edge_spiral(a: String, b: String, cost: float) -> void:
	var ia: int = node_idx[a]
	var ib: int = node_idx[b]
	adj_spiral[ia].append([ib, cost, -1])
	adj_spiral[ib].append([ia, cost, -1])


## an edge only the player's / planner's graph has (not the crowd's, not the step-free one)
func _edge_lift_only(a: String, b: String, cost_override := -1.0) -> void:
	var ia: int = node_idx[a]
	var ib: int = node_idx[b]
	var c := cost_override if cost_override >= 0.0 else (nodes[ia]["pos"] as Vector3).distance_to(nodes[ib]["pos"]) / PLAN_WALK
	adj_lift[ia].append([ib, c, -1])
	adj_lift[ib].append([ia, c, -1])


func _room_of_point(p: Vector3) -> String:
	for rm in rooms:
		var r: Array = rm["rect"]
		if p.x >= r[0] and p.x <= r[1] and p.z >= r[2] and p.z <= r[3] and absf(p.y - float(rm["y"])) < 1.5:
			return String(rm["name"])
	return ""


## the walking-graph node of a room that a door front can be joined to: on the same floor, at least 1.8 m away, in plain sight (the straight way to it crosses none of `taken` and, in a hall,
## stays on the paid side of the gateline), the nearest of those; "" when there is none
func _attach_node(room: Dictionary, front: Vector3, taken: Array) -> String:
	var r: Array = room["rect"]
	var best := ""
	var bd := 1e9
	for n in nodes:
		var np: Vector3 = n["pos"]
		if np.x < r[0] + 0.4 or np.x > r[1] - 0.4 or np.z < r[2] + 0.4 or np.z > r[3] - 0.4 or absf(np.y - float(room["y"])) > 1.5:
			continue
		var nm: String = n["name"]
		if nm.begins_with("lift") or nm.begins_with("spiral") or (nm.begins_with("esc") and (nm.ends_with("_top") or nm.ends_with("_bot"))) or nm.begins_with("street") or nm.begins_with("gate"):
			continue
		var d := np.distance_to(front)
		if d < 1.8 or d >= bd or not _line_clear(front, np, taken, room):
			continue
		bd = d
		best = nm
	return best


## the straight way between two points of a room is free: it crosses none of the housings (`taken`, grown by 0.35 m) and does not cross a gateline
func _line_clear(a: Vector3, b: Vector3, taken: Array, room: Dictionary) -> bool:
	for t in taken:
		if _seg_hits_rect(a, b, t, 0.35):
			return false
	for gl in gatelines:
		var gr: Array = gl.get("rect", hall["rect"])
		var gz: float = gl["z"]
		if (a.x >= gr[0] and a.x <= gr[1] and a.z >= gr[2] and a.z <= gr[3]) or (b.x >= gr[0] and b.x <= gr[1] and b.z >= gr[2] and b.z <= gr[3]):
			if (a.z - gz) * (b.z - gz) < 0.0 or absf(a.z - gz) < 0.8 or absf(b.z - gz) < 0.8:
				return false
	return true


## does the segment a-b (in xz) touch the rectangle [xmin, xmax, zmin, zmax] grown by m?  (Liang-Barsky)
static func _seg_hits_rect(a: Vector3, b: Vector3, r: Array, m: float) -> bool:
	var x0: float = r[0] - m
	var x1: float = r[1] + m
	var z0: float = r[2] - m
	var z1: float = r[3] + m
	var t0 := 0.0
	var t1 := 1.0
	var dx := b.x - a.x
	var dz := b.z - a.z
	for pq: Array in [[-dx, a.x - x0], [dx, x1 - a.x], [-dz, a.z - z0], [dz, z1 - a.z]]:
		var pp: float = pq[0]
		var qq: float = pq[1]
		if absf(pp) < 1e-9:
			if qq < 0.0:
				return false
		else:
			var t := qq / pp
			if pp < 0.0:
				if t > t1:
					return false
				t0 = maxf(t0, t)
			else:
				if t < t0:
					return false
				t1 = minf(t1, t)
	return true


## a stretch of wall in a room for a door housing (SPIRAL_DOOR_W wide, SPIRAL_DOOR_D deep): clear of the room's openings, the other housings (`taken`) and the room's corners, the one nearest to `near`
## (the lifts) first. Returns {pos (at the wall, on the floor), front (1.3 m out), yaw (housing rotation, door facing into the room), out (direction out of the door), footprint} or {}.
func _wall_spot(room: Dictionary, taken: Array, near: Vector2, in_hall: bool) -> Dictionary:
	var r: Array = room["rect"]
	var y: float = room["y"]
	var cands: Array = []
	var x := float(r[0]) + 3.0
	while x <= float(r[1]) - 3.0:
		cands.append([x, float(r[2]), Vector2(0, 1)])        # the north wall (z0), the room is toward +z
		cands.append([x, float(r[3]), Vector2(0, -1)])
		x += 0.5
	var z := float(r[2]) + 3.0
	while z <= float(r[3]) - 3.0:
		cands.append([float(r[0]), z, Vector2(1, 0)])
		cands.append([float(r[1]), z, Vector2(-1, 0)])
		z += 0.5
	cands.sort_custom(func(a, b): return Vector2(a[0], a[1]).distance_to(near) < Vector2(b[0], b[1]).distance_to(near))
	for c in cands:
		var n: Vector2 = c[2]
		var along := Vector2(-n.y, n.x)
		var hw := SPIRAL_DOOR_W * 0.5
		var p0 := Vector2(c[0], c[1])
		var rect_pts: Array = []
		for dd: float in [0.0, SPIRAL_DOOR_D + 1.4]:
			for ww: float in [-hw - 0.4, hw + 0.4]:
				var q: Vector2 = p0 + n * dd + along * ww
				rect_pts.append(q)
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for q2: Vector2 in rect_pts:
			lo = Vector2(minf(lo.x, q2.x), minf(lo.y, q2.y))
			hi = Vector2(maxf(hi.x, q2.x), maxf(hi.y, q2.y))
		var foot: Array = [lo.x, hi.x, lo.y, hi.y]
		if not _rect_inside(foot, r, -0.01):
			continue
		var clash := false
		for op in room.get("openings", []):
			var o: Dictionary = op
			var cc: float = float(o["c"])
			var half: float = float(o["w"]) * 0.5 + 1.0
			var orect: Array
			match String(o["side"]):
				"N":
					orect = [cc - half, cc + half, r[2], r[2] + 1.6]
				"S":
					orect = [cc - half, cc + half, r[3] - 1.6, r[3]]
				"W":
					orect = [r[0], r[0] + 1.6, cc - half, cc + half]
				_:
					orect = [r[1] - 1.6, r[1], cc - half, cc + half]
			if _rects_overlap(foot, orect, 0.0):
				clash = true
		for t in taken:
			if _rects_overlap(foot, t, 0.4):
				clash = true
		if clash:
			continue
		var out_dir := Vector3(n.x, 0, n.y)
		var front := Vector3(p0.x + n.x * 1.3, y, p0.y + n.y * 1.3)
		# (in the ticket hall the stair is on the paid side: nobody gets to the platforms past the gates by it)
		if in_hall:
			var unpaid := false
			for gl in gatelines:
				var gr: Array = gl.get("rect", hall["rect"])
				if front.x >= gr[0] and front.x <= gr[1] and front.z >= gr[2] and front.z <= gr[3] and front.z < float(gl["z"]) + 1.2:
					unpaid = true
			if unpaid:
				continue
		var att := _attach_node(room, front, taken)
		if att == "":
			continue
		return {"pos": Vector3(p0.x, y, p0.y), "front": front, "yaw": atan2(-out_dir.x, -out_dir.z), "out": out_dir, "footprint": foot, "attach": att}
	return {}


## the escalator-type banks of a lift-only station are not there in reality (lifts are): mark them removed, close their openings in the rooms and drop their edges from the walking graph;
## _add_lifts then puts the lifts where the openings were
func _apply_lift_only() -> void:
	for ei in escs.size():
		var e: Dictionary = escs[ei]
		if e.get("stairs", false):
			continue
		e["removed"] = true
		for rm in rooms:
			var kept: Array = []
			for op in rm.get("openings", []):
				if not String((op as Dictionary).get("id", "")).begins_with("esc%d_" % ei):
					kept.append(op)
			rm["openings"] = kept
	for i in adj.size():
		var kept2: Array = []
		for ed in adj[i]:
			var removed_edge := false
			if int(ed[2]) >= 0 and _is_esc_edge(int(ed[2])):
				var an: String = nodes[edges[int(ed[2])]["a"]]["name"]
				var ei2 := int(an.substr(3, an.find("_") - 3))
				removed_edge = bool(escs[ei2].get("removed", false))
			if not removed_edge:
				kept2.append(ed)
		adj[i] = kept2


## an edge in the crowd's graph `adj` only needs no care for the other two (they are made by _edge_sf)
func _edge_plain(a: String, b: String, cost_override := -1.0) -> void:
	var ia: int = node_idx[a]
	var ib: int = node_idx[b]
	var c := cost_override if cost_override >= 0.0 else (nodes[ia]["pos"] as Vector3).distance_to(nodes[ib]["pos"]) / PLAN_WALK
	adj[ia].append([ib, c, -1])
	adj[ib].append([ia, c, -1])


func _edge_sf(a: String, b: String, cost_override := -1.0) -> void:
	var ia: int = node_idx[a]
	var ib: int = node_idx[b]
	var c := cost_override if cost_override >= 0.0 else (nodes[ia]["pos"] as Vector3).distance_to(nodes[ib]["pos"]) / PLAN_WALK
	adj_sf[ia].append([ib, c, -1])
	adj_sf[ib].append([ia, c, -1])
	adj_lift[ia].append([ib, c, -1])
	adj_lift[ib].append([ia, c, -1])


func lift_of(ei: int) -> Dictionary:
	for l in lifts:
		if int(l["esc"]) == ei:
			return l
	return {}


## a node path split where it rides a lift: [[names before], [names after], ...] (each part is one continuous walk)
func path_segments(names: Array) -> Array:
	var out: Array = []
	var cur: Array = []
	for i in names.size():
		cur.append(names[i])
		var n: String = names[i]
		var nxt: String = names[i + 1] if i + 1 < names.size() else ""
		if n.begins_with("lift") and nxt.begins_with("lift") and n.get_slice("_", 0) == nxt.get_slice("_", 0):
			out.append(cur)
			cur = []
		elif (n == "spiral0_top" and nxt == "spiral0_tin") or (n == "spiral0_tout" and nxt == "spiral0_bot") or (n == "spiral0_bot" and nxt == "spiral0_tout") or (n == "spiral0_tin" and nxt == "spiral0_top"):
			out.append(cur)           # (the doors are portals: the room, the helix and the other room are three separate walks)
			cur = []
	if not cur.is_empty():
		out.append(cur)
	return out


## x of a gate lane of the wanted kind (+1 entry, -1 exit); `pick` selects among the lanes nearest the centre (non-accessible preferred)
func gate_lane_x(kind: int, pick := 0, gl: Dictionary = {}) -> float:
	if gl.is_empty():
		gl = gates
	var xs: Array = []
	for ld in gl["lanes"]:
		if ld["kind"] == kind and (ld["wide"] == step_free_mode):
			xs.append(ld["x"])
	if xs.is_empty():
		for ld in gl["lanes"]:
			if ld["kind"] == kind:
				xs.append(ld["x"])
	var cxg: float = gl.get("cx", 0.0)
	xs.sort_custom(func(a, b): return absf(a - cxg) < absf(b - cxg))
	return xs[pick % xs.size()]


## gateline for a node name "gate_in" / "gate2_out" ...
func gateline_of(node_name: String) -> Dictionary:
	var digits := node_name.substr(4, node_name.find("_") - 4)
	var gi := 0 if digits == "" else int(digits) - 1
	return gatelines[clampi(gi, 0, gatelines.size() - 1)]


func hall_rect_for_door(sd: Dictionary) -> Array:
	var hn: String = sd.get("hall", "hall")
	for rm in rooms:
		if rm["name"] == hn:
			return rm["rect"]
	return hall["rect"]


## Waypoints (plan space) along a node path. Each: {pos, kind:"walk"|"gate"|"esc_in"|"esc_out", esc, lane, dir}
## `pick` varies lane choices between agents.
func walk_points(names: Array, pick := 0) -> Array:
	var out: Array = []
	var i := 0
	while i < names.size():
		var n: String = names[i]
		var nxt: String = names[i + 1] if i + 1 < names.size() else ""
		var prv: String = names[i - 1] if i > 0 else ""
		if n.begins_with("gate") and n.ends_with("_in") and nxt == n.replace("_in", "_out"):
			var gl := gateline_of(n)
			var lx := gate_lane_x(1, pick, gl)
			out.append({"pos": Vector3(lx, 0, gl["z"] - 1.6), "kind": "walk"})
			out.append({"pos": Vector3(lx, 0, gl["z"] - 0.2), "kind": "gate"})
			out.append({"pos": Vector3(lx, 0, gl["z"] + 1.8), "kind": "walk"})
			i += 2
			continue
		if n.begins_with("gate") and n.ends_with("_out") and nxt == n.replace("_out", "_in"):
			var gl2 := gateline_of(n)
			var lx2 := gate_lane_x(-1, pick, gl2)
			out.append({"pos": Vector3(lx2, 0, gl2["z"] + 1.6), "kind": "walk"})
			out.append({"pos": Vector3(lx2, 0, gl2["z"] + 0.2), "kind": "gate"})
			out.append({"pos": Vector3(lx2, 0, gl2["z"] - 1.8), "kind": "walk"})
			i += 2
			continue
		if n.begins_with("lift") and nxt.begins_with("lift") and n.get_slice("_", 0) == nxt.get_slice("_", 0):
			# a lift ride: stand at the door in front of the car (kind "lift", with the way it goes and where it comes out), then walk on from the other door
			var li := int(n.get_slice("_", 0).substr(4))
			var lf := lift_of(li)
			var down := n.ends_with("_top")
			var here: Dictionary = lf["top"] if down else lf["bot"]
			var there: Dictionary = lf["bot"] if down else lf["top"]
			out.append({"pos": here["front"], "kind": "lift", "lift": li, "dir": 1 if down else -1, "to": there["front"], "time": lf["time"]})
			out.append({"pos": there["front"], "kind": "walk"})
			i += 2
			continue
		if not spirals.is_empty() and ((n == "spiral0_top" and nxt == "spiral0_tin") or (n == "spiral0_bot" and nxt == "spiral0_tout")):
			# through the spiral stair: a portal at the door (kind "spiral": `to` where it comes out in the tower, `to_dir` the way the player faces there), the walk along the helix, a portal at
			# the far door of the tower, then on from the other room's door
			var sp: Dictionary = spirals[0]
			var down := n == "spiral0_top"
			var near_d: Dictionary = sp["top"] if down else sp["bot"]
			var far_d: Dictionary = sp["bot"] if down else sp["top"]
			out.append({"pos": near_d["front"], "kind": "spiral", "spiral": 0, "end": "top" if down else "bot", "to": sp["tin"] if down else sp["tout"], "to_dir": sp["tin_dir"] if down else sp["tout_dir"]})
			var helix: Array = (sp["interior"] as Array).duplicate()
			if not down:
				helix.reverse()
			for hi in range(1, helix.size()):
				out.append({"pos": helix[hi], "kind": "walk", "tower": true})
			out.append({"pos": sp["tout"] if down else sp["tin"], "kind": "spiral", "spiral": 0, "end": "bot_tower" if down else "top_tower", "to": far_d["front"], "to_dir": far_d["out"]})
			out.append({"pos": far_d["front"], "kind": "walk"})
			var skip := 4
			if i + 4 < names.size() and String(names[i + 4]) == String(far_d["attach"]):
				out.append({"pos": nodes[node_idx[String(far_d["attach"])]]["pos"], "kind": "walk"})      # (the node the door hangs on is walked to as it is: the line to it was cleared in _attach_node)
				skip = 5
			i += skip
			continue
		if not spirals.is_empty() and (n == "spiral0_top" or n == "spiral0_bot") and nxt != "" and not nxt.begins_with("spiral"):
			# a door front and the node it hangs on: straight from one to the other (the line was cleared in _attach_node)
			var dd: Dictionary = spirals[0]["top" if n == "spiral0_top" else "bot"]
			out.append({"pos": dd["front"], "kind": "walk"})
			if nxt == String(dd["attach"]):
				out.append({"pos": nodes[node_idx[nxt]]["pos"], "kind": "walk"})
				i += 2
			else:
				i += 1
			continue
		if not spirals.is_empty() and ((n == "spiral0_tin" and nxt == "spiral0_tout") or (n == "spiral0_tout" and nxt == "spiral0_tin")):
			# the helix on its own (a stretch of a path that starts or ends at a portal: see path_segments)
			var hx: Array = (spirals[0]["interior"] as Array).duplicate()
			if n == "spiral0_tout":
				hx.reverse()
			for hp in hx:
				out.append({"pos": hp, "kind": "walk", "tower": true})
			i += 2
			continue
		if n.begins_with("esc") and n.ends_with("_top") and nxt.begins_with("esc") and nxt.ends_with("_bot"):
			var ei := int(n.substr(3, n.find("_") - 3))
			var li := esc_lane_for(ei, 1, pick)
			var lz := esc_lane_z(ei, li)
			var e: Dictionary = escs[ei]
			# line up with the lane before the plate: a diagonal approach hits the balustrade fronts of the outer lanes
			out.append({"pos": esc_point(ei, Vector3(-1.4, 0.0, lz)), "kind": "walk"})
			out.append({"pos": esc_point(ei, Vector3(0.6, 0.0, lz)), "kind": "esc_in", "esc": ei, "lane": li, "dir": 1})
			out.append({"pos": esc_point(ei, Vector3(e["length"] - 0.9, -e["rise"], lz)), "kind": "esc_out", "esc": ei, "lane": li, "dir": 1})
			out.append({"pos": esc_point(ei, Vector3(e["length"] + 1.5, -e["rise"], lz)), "kind": "walk"})      # straight out of the lane before turning
			i += 2
			continue
		if n.begins_with("esc") and n.ends_with("_bot") and nxt.begins_with("esc") and nxt.ends_with("_top"):
			var ej := int(n.substr(3, n.find("_") - 3))
			var lj := esc_lane_for(ej, -1, pick)
			var lzj := esc_lane_z(ej, lj)
			var e2: Dictionary = escs[ej]
			out.append({"pos": esc_point(ej, Vector3(e2["length"] + 1.4, -e2["rise"], lzj)), "kind": "walk"})
			out.append({"pos": esc_point(ej, Vector3(e2["length"] - 0.6, -e2["rise"], lzj)), "kind": "esc_in", "esc": ej, "lane": lj, "dir": -1})
			out.append({"pos": esc_point(ej, Vector3(0.9, 0.0, lzj)), "kind": "esc_out", "esc": ej, "lane": lj, "dir": -1})
			out.append({"pos": esc_point(ej, Vector3(-1.5, 0.0, lzj)), "kind": "walk"})
			i += 2
			continue
		# street passage: line up with the opening in the hall's north wall
		if n.begins_with("street") and prv.begins_with("hall") and prv.ends_with("_unpaid"):
			var sdi := _street_by_id(n)
			var hr: Array = hall_rect_for_door(sdi)
			out.append({"pos": Vector3(sdi["c"], 0, hr[2] + 2.0), "kind": "walk"})
			out.append({"pos": Vector3(sdi["c"], 0, hr[2] - 1.0), "kind": "walk"})
			out.append({"pos": nodes[node_idx[n]]["pos"], "kind": "walk"})
			i += 1
			continue
		if n.begins_with("hall") and n.ends_with("_unpaid") and prv.begins_with("street"):
			var sdp := _street_by_id(prv)
			var hr2: Array = hall_rect_for_door(sdp)
			out.append({"pos": Vector3(sdp["c"], 0, hr2[2] - 1.0), "kind": "walk"})
			out.append({"pos": Vector3(sdp["c"], 0, hr2[2] + 2.0), "kind": "walk"})
			out.append({"pos": nodes[node_idx[n]]["pos"], "kind": "walk"})
			i += 1
			continue
		if n.begins_with("landing") and nxt.contains("_spine"):
			var mi := int(nxt.substr(1, nxt.find("_") - 1))
			var m: Dictionary = modules[mi]
			var lr: Array = _landing_rect(int(m["level"]))
			out.append({"pos": Vector3(lr[1] - 2.5, m["pos"].y, m["lane_z"]), "kind": "walk"})
			out.append({"pos": Vector3(lr[1] + 1.5, m["pos"].y, m["lane_z"]), "kind": "walk"})
			i += 1
			continue
		if n.contains("_spine") and prv.begins_with("landing"):
			out.append({"pos": nodes[node_idx[n]]["pos"], "kind": "walk"})
			i += 1
			continue
		if n.contains("_spine") and not prv.is_empty() and prv.contains("_open") and nxt.begins_with("landing"):
			# leaving a spine towards the landing: line up with the corridor first
			var mk := int(n.substr(1, n.find("_") - 1))
			var mm: Dictionary = modules[mk]
			var lr2: Array = _landing_rect(int(mm["level"]))
			out.append({"pos": nodes[node_idx[n]]["pos"], "kind": "walk"})
			out.append({"pos": Vector3(lr2[1] + 1.5, mm["pos"].y, mm["lane_z"]), "kind": "walk"})
			out.append({"pos": Vector3(lr2[1] - 2.5, mm["pos"].y, mm["lane_z"]), "kind": "walk"})
			i += 1
			continue
		out.append({"pos": nodes[node_idx[n]]["pos"], "kind": "walk"})
		i += 1
	return out


func _street_by_id(id: String) -> Dictionary:
	for sd in street_doors:
		if sd["id"] == id:
			return sd
	return street_doors[0]


func _landing_rect(level: int) -> Array:
	for rm in rooms:
		if rm["name"] == "landing%d" % level:
			return rm["rect"]
	return [-11.0, 11.0, 0.0, 12.0]


## Fills the walk-time cache for every node so later queries are read-only (thread safe).
func warm() -> void:
	for n in nodes:
		if not _dcache.has(n["name"]):
			_dcache[n["name"]] = dijkstra(n["name"], false, false)
		if not _dcache_sf.has(n["name"]):
			_dcache_sf[n["name"]] = dijkstra(n["name"], true, false)
		if lifts_real and not _dcache_lift.has(n["name"]):
			_dcache_lift[n["name"]] = dijkstra(n["name"], false, true)


static var _all_warm := false
static var _warm_group := -1
static var _warm_out: Array = []


## Builds every station's plan and its walk-time cache on the worker threads (about 1.7 s of work on one core): started while the main menu is up, so that starting a journey does not stall.
## The plans are only handed to the cache by `warm_all()`; the workers write nothing but their own slot of `_warm_out`.
static func warm_all_async() -> void:
	if _all_warm or _warm_group >= 0:
		return
	RealData.station("")            # the lazily loaded static tables are filled here, on the main thread, so the workers only read them
	vertical_access("")
	StationCharacter.color("")
	_warm_out = []
	_warm_out.resize(Net.stations.size())
	_warm_group = WorkerThreadPool.add_group_task(_warm_one, Net.stations.size(), -1, false, "station plans")


static func _warm_one(i: int) -> void:
	var p := StationPlan.new()
	p.generate(i)
	p.warm()
	_warm_out[i] = p


## true when `warm_all()` will not have to wait
static func warm_ready() -> bool:
	return _all_warm or (_warm_group >= 0 and WorkerThreadPool.is_group_task_completed(_warm_group))


## Quitting while the workers are still building plans: they read the network, so they must be done before it is freed
static func finish_warm() -> void:
	if _warm_group >= 0:
		warm_all()


## Every plan generated and warm (waits for `warm_all_async()` when it is still running; does the work itself when it was never started)
static func warm_all() -> void:
	if _all_warm:
		return
	warm_all_async()
	WorkerThreadPool.wait_for_group_task_completion(_warm_group)
	for i in _warm_out.size():
		if _cache.has(i):
			_cache[i].warm()           # built on the main thread meanwhile: keep that object, the worker's copy is dropped
		else:
			_cache[i] = _warm_out[i]
	_warm_out = []
	_warm_group = -1
	_all_warm = true


var _dcache: Dictionary = {}
var _dcache_sf: Dictionary = {}
var _dcache_lift: Dictionary = {}
var _dcache_spiral: Dictionary = {}


func walk_time(a: String, b: String, sf := step_free_mode, lifts := lifts_enabled) -> float:
	var k := _graph_kind(sf, lifts)
	var c: Dictionary = _dcache_sf if k == 2 else (_dcache_spiral if k == 3 else (_dcache_lift if k == 1 else _dcache))
	if not c.has(a):
		c[a] = dijkstra(a, sf, lifts)
	return c[a].get(b, 1e9)


## time from the paid side of the gateline (arriving from the street) to the platform face node
func time_gate_to_face(key: String) -> float:
	return walk_time("gate_out", "face:" + key)


func time_face_to_exit(key: String) -> float:
	# walk to the gateline, tap out, then to the nearest street door
	var best := 1e9
	for sd in street_doors:
		best = minf(best, walk_time("face:" + key, sd["id"]))
	return best


func time_face_to_face(ka: String, kb: String) -> float:
	return walk_time("face:" + ka, "face:" + kb)
