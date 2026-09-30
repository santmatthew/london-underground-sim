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
}
const BASE_DEPTH := {  # metres below the ticket hall
	"bakerloo": 21.0, "central": 22.0, "jubilee": 29.0, "northern": 25.0, "piccadilly": 27.0, "victoria": 24.0, "waterloo-city": 23.0, "ss": 9.0,
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
var platform_no: Dictionary = {}   # pid -> 1..N
var _dests: Dictionary = {}
var bounds := AABB()

static var _cache: Dictionary = {}


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


func _edge(a: String, b: String, cost_override := -1.0, speed := 1.5) -> void:
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
		var d: float = BASE_DEPTH.get(md["group"], 24.0) + rng.randf_range(-2.0, 2.5)
		if imp < 1.6:
			d = minf(d, 18.0 + rng.randf() * 4.0)
		if kind == "surface":
			d = rng.randf_range(5.0, 6.5)
		elif kind == "sub":
			d = rng.randf_range(8.0, 10.5)
		# measured depth (TfL layout diagram): metres below street level -> below the ticket hall
		var g: String = md["group"]
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
			var is_box: bool = kind != "deep"
			var spine_x0 := -L * 0.5 if is_box else -L * 0.5 - 6.0
			var mx: float = rect[1] + corr_len - spine_x0
			var mpos := Vector3(mx, -lvl[li]["depth"], lane_z)
			var faces_spec: Array = []
			for fdef in md["faces"]:
				var pid: String = fdef["pid"]
				var pl: Dictionary = st["platforms"][pid]
				var lid: String = pl["lines"][0]
				faces_spec.append({"pid": pid, "line": lid, "color": Net.line_color(lid), "label": pl["dir"], "face": fdef["face"], "lines": pl["lines"]})
			var openings_x := [-L * 0.5 + 8.0, -L * 0.5 + 8.0 + 14.0]
			var wall_style := "tile_cream" if (seed_value + mi) % 3 == 0 else "tile_white"
			var stripes := _stripes_for(seed_value + mi, faces_spec[0]["color"])
			var tun_w := corr_len - spine_x0 - L * 0.5 - 1.0     # distance from the platform's west end to the landing wall, minus a metre of rock
			var mspec := {"tun_w": tun_w, "style": "box" if is_box else "arch", "roof": "glass" if kind == "surface" else "flat", "length": L, "pw": pw, "wall": wall_style, "stripes": stripes, "seed": seed_value + li * 7 + mi, "faces": faces_spec,
				"openings_x": openings_x, "spine_x0": spine_x0, "spine_x1": -L * 0.5 + 8.0 + 14.0 + 6.0, "name": name, "group": group}
			var midx := modules.size()
			modules.append({"pos": mpos, "spec": mspec, "faces": md["faces"], "level": li, "group": group, "lane_z": lane_z, "corr": [rect[1], mpos.x + spine_x0]})
			Ld["openings"].append({"side": "E", "c": lane_z, "w": CORR_W, "h": SPINE_H, "id": "corr%d_%d" % [li, mi]})
			rooms.append({"name": "corridor%d_%d" % [li, mi], "rect": [rect[1], mpos.x + spine_x0, lane_z - CORR_W * 0.5, lane_z + CORR_W * 0.5], "y": mpos.y, "h": SPINE_H,
				"open_ends": ["E", "W"], "wall": wall_style, "floor": "floor_platform", "lights": "strip_x", "light_dx": 4.0, "seed": seed_value + midx})
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
		rooms.append({"name": "street_passage%d" % i, "rect": [c - 1.6, c + 1.6, hz0 - street_len, hz0], "y": 0.0, "h": 3.0, "open_ends": ["S"], "wall": "tile_white", "floor": "floor_hall", "lights": "strip_z", "light_dz": 3.5, "seed": seed_value + 90 + i})
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
	rooms.append({"name": "hall", "rect": hall["rect"], "y": 0.0, "h": HALL_H, "openings": hall_openings, "wall": "tile_white", "floor": "floor_hall", "lights": "grid",
		"light_dx": 4.5, "light_dz": 5.0, "seed": seed_value, "band": Color(0.02, 0.18, 0.5)})
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
		var best := 0
		for lid in pl["lines"]:
			var n := RealData.platform_number(naptan, lid, pl["dir"])
			if n > 0 and (best == 0 or n < best):
				best = n
		if best > 0 and not used.has(best):
			used[best] = true
			real_no[pid] = best
	if real_no.size() == platform_no.size():
		platform_no = real_no
	_add_start_spots(rng)


func _reset_plan() -> void:
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


func station_platform(pid: String) -> Dictionary:
	return Net.stations[idx]["platforms"][pid]


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
func dijkstra(from_name: String) -> Dictionary:
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
		for e in adj[cur[1]]:
			var nd: float = cur[0] + e[1]
			if nd < d[e[0]]:
				d[e[0]] = nd
				open.append([nd, e[0]])
	for i in n:
		dist[nodes[i]["name"]] = d[i]
	return dist


## node-name path from a to b (shortest by cost); empty if unreachable
func path(a: String, b: String) -> Array:
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
		for e in adj[cur[1]]:
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


## x of a gate lane of the wanted kind (+1 entry, -1 exit); `pick` selects among the lanes nearest the centre (non-accessible preferred)
func gate_lane_x(kind: int, pick := 0, gl: Dictionary = {}) -> float:
	if gl.is_empty():
		gl = gates
	var xs: Array = []
	for ld in gl["lanes"]:
		if ld["kind"] == kind and not ld["wide"]:
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
			_dcache[n["name"]] = dijkstra(n["name"])


static var _all_warm := false


static func warm_all() -> void:
	if _all_warm:
		return
	for i in Net.stations.size():
		for_station(i).warm()
	_all_warm = true


var _dcache: Dictionary = {}


func walk_time(a: String, b: String) -> float:
	if not _dcache.has(a):
		_dcache[a] = dijkstra(a)
	return _dcache[a].get(b, 1e9)


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
