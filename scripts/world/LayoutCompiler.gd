class_name LayoutCompiler
extends RefCounted
## Builds a StationPlan from an authored layout (data/layouts/<naptan>.json) instead of the generated "one hall + chain of escalators".
## The result uses the same structures as the generator (rooms with openings, escs, modules, faces, street doors, walking graph), so
## Station, signs, props, crowds, planner and the autopilot work unchanged.
##
## Layout JSON (all rooms axis aligned; `depth` = metres below the primary hall's floor; coordinates in metres):
##   rooms:   [{id, kind: "hall"|"landing", rect:[x0,x1,z0,z1] | size:[w,d], depth, gateline:{z, n}, doors:[{c, ref, len}]}]
##            (a room with `size` instead of `rect` is placed by the first escalator/link that reaches it)
##   esc:     [{id, from, to, dir:"N|S|E|W", c, lanes:[1,-1,..], stairs?}]  the top sits on the `dir` wall of `from` at wall coordinate c,
##            the bottom on the opposite wall of `to`; the rise is the depth difference
##   links:   [{a, b, side, c, w, h}]  straight opening between rooms that touch (or place b next to a)
##   modules: [{attach, lane_z, corr_len, group, faces:[[pid, face], ...]}]  platform modules east of room `attach`

const DIRS := {"N": Vector3(0, 0, -1), "S": Vector3(0, 0, 1), "E": Vector3(1, 0, 0), "W": Vector3(-1, 0, 0)}
const OPP := {"N": "S", "S": "N", "E": "W", "W": "E"}
const YAW := {"S": -PI / 2.0, "N": PI / 2.0, "E": 0.0, "W": PI}


static func _err(p: StationPlan, msg: String) -> bool:
	push_error("Layout %s: %s" % [p.name, msg])
	return false


static func compile(p: StationPlan, spec: Dictionary) -> bool:
	var st: Dictionary = Net.stations[p.idx]
	var naptan: String = Net.station_ids[p.idx]
	var real_ents: Array = RealData.entrances(naptan)
	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed_value

	# ---------------------------------------------------------------------------------------------------- rooms
	var rooms := {}
	var order: Array = []
	var n_hall := 0
	var n_land := 0
	for r in spec["rooms"]:
		var kind: String = r.get("kind", "landing")
		var rd := {"id": r["id"], "kind": kind, "y": -float(r.get("depth", 0.0)), "rect": r.get("rect", null), "size": r.get("size", null),
			"openings": [], "gateline": r.get("gateline", {}), "doors": r.get("doors", []), "spec": r}
		if kind == "hall":
			rd["name"] = "hall" if n_hall == 0 else "hall%d" % (n_hall + 1)
			rd["hidx"] = n_hall
			rd["h"] = StationPlan.HALL_H
			n_hall += 1
		else:
			rd["name"] = "landing%d" % n_land
			rd["h"] = StationPlan.LANDING_H
			n_land += 1
		rooms[r["id"]] = rd
		order.append(rd)
	if n_hall == 0:
		return _err(p, "needs at least one hall")

	# ------------------------------------------------------------------------------- escalators and links (placing rooms)
	var conns: Array = []
	for e in spec.get("esc", []):
		conns.append({"type": "esc", "d": e})
	for l in spec.get("links", []):
		conns.append({"type": "link", "d": l})
	var pending := conns.duplicate()
	var escs_out: Array = []
	var esc_of: Dictionary = {}          # connector id -> escs index
	var guard := 0
	while not pending.is_empty() and guard < 200:
		guard += 1
		var progressed := false
		for cn in pending.duplicate():
			var d: Dictionary = cn["d"]
			var a: Dictionary = rooms.get(d["from"] if cn["type"] == "esc" else d["a"], {})
			var b: Dictionary = rooms.get(d["to"] if cn["type"] == "esc" else d["b"], {})
			if a.is_empty() or b.is_empty():
				return _err(p, "unknown room in connector %s" % str(d))
			if a["rect"] == null and b["rect"] == null:
				continue
			if a["rect"] == null:
				continue                       # placed later from the other end (only forward placement supported)
			var ok := _place_esc(p, rooms, cn, escs_out, esc_of) if cn["type"] == "esc" else _place_link(p, rooms, cn)
			if not ok:
				return false
			pending.erase(cn)
			progressed = true
		if not progressed:
			break
	if not pending.is_empty():
		return _err(p, "could not place connectors (%d left): a room is not reachable from a room with a rect" % pending.size())
	for rd in order:
		if rd["rect"] == null:
			return _err(p, "room %s was never placed" % rd["id"])

	# ------------------------------------------------------------------------------------- halls: gatelines and street doors
	var door_i := 0
	var gatelines: Array = []
	var hall_room_names: Array = []
	for rd in order:
		if rd["kind"] != "hall":
			continue
		var r: Array = rd["rect"]
		hall_room_names.append(rd["name"])
		var doors: Array = rd["doors"]
		var hall_doors: Array = []
		for dd in doors:
			var c: float = dd["c"]
			var len: float = dd.get("len", 8.0)
			var sid := "street%d" % door_i
			rd["openings"].append({"side": "N", "c": c, "w": 3.2, "h": 3.0, "id": sid})
			var sdoor := {"id": sid, "pos": Vector3(c, 0.0, r[2] - len + 0.4), "dir": Vector3(0, 0, -1), "c": c, "len": len, "hall": rd["name"]}
			var ref := str(dd.get("ref", ""))
			if ref == "" and str(dd.get("name", "")) != "":
				sdoor["exit_name"] = str(dd["name"])           # a street name without an exit number
			if ref != "":
				for re in real_ents:
					if str(re.get("ref", "")) == ref:
						sdoor["exit_ref"] = ref
						sdoor["exit_name"] = RealData.street_of(re)
						break
				if not sdoor.has("exit_ref"):
					sdoor["exit_ref"] = ref
					sdoor["exit_name"] = str(dd.get("name", ""))
			p.street_doors.append(sdoor)
			hall_doors.append(sdoor)
			p.rooms.append({"name": "street_passage%d" % door_i, "rect": [c - 1.6, c + 1.6, r[2] - len, r[2]], "y": 0.0, "h": 3.0, "open_ends": ["S"], "wall": "tile_white",
				"floor": "floor_hall", "lights": "strip_z", "light_dz": 3.5, "seed": p.seed_value + 90 + door_i}.merged(p._passage_finish(), true))
			door_i += 1
		rd["door_list"] = hall_doors
		# gateline across the hall
		var gl: Dictionary = rd["gateline"]
		var n_gates: int = int(gl.get("n", 8))
		var lane_defs: Array = []
		var total_w := 0.0
		for gi in n_gates:
			var wide := gi == 0 or gi == n_gates - 1
			var lw := 1.23 if wide else 0.93
			lane_defs.append({"w": lw, "wide": wide, "kind": (1 if gi < (n_gates + 1) / 2 else -1)})
			total_w += lw
		var cx: float = (float(r[0]) + float(r[1])) * 0.5
		var gx: float = cx - total_w * 0.5
		for ld in lane_defs:
			ld["x"] = gx + ld["w"] * 0.5
			gx += ld["w"]
		var gline := {"z": float(gl.get("z", r[2] + 8.0)), "x0": r[0] + 0.3, "x1": r[1] - 0.3, "n": n_gates, "pitch": 0.93, "lanes": lane_defs, "total_w": total_w,
			"cx": cx, "hall": rd["name"], "rect": r}
		gatelines.append(gline)
		rd["gateline_data"] = gline
	p.gatelines = gatelines
	p.gates = gatelines[0]
	p.authored = true
	var hall0: Dictionary = order[0]
	for rd in order:
		if rd["kind"] == "hall":
			hall0 = rd
			break
	p.hall = {"rect": hall0["rect"], "y": 0.0, "h": StationPlan.HALL_H}

	# ------------------------------------------------------------------------------------------------ platform modules
	var mod_i := 0
	var corr_rooms: Array = []
	var mod_by_room: Dictionary = {}
	for md in spec.get("modules", []):
		var room: Dictionary = rooms.get(md["attach"], {})
		if room.is_empty():
			return _err(p, "module attaches to unknown room %s" % str(md["attach"]))
		var rect: Array = room["rect"]
		var lane_z: float = md["lane_z"]
		if md.get("lane_rel", false):
			lane_z += (float(rect[2]) + float(rect[3])) * 0.5          # relative to the room's centre line
		var group: String = md["group"]
		var faces_def: Array = md["faces"]
		for fdef0 in faces_def:
			if not st["platforms"].has(fdef0[0]):
				return _err(p, "module uses unknown platform %s (station has %s)" % [str(fdef0[0]), str(st["platforms"].keys())])
		var pid0: String = faces_def[0][0]
		var line_id: String = st["platforms"][pid0]["lines"][0]
		var cars: Array = StationPlan.CARS.get(line_id, [6, 16.0])
		var L: float = cars[0] * cars[1] + 10.0
		var pw := PlatformModule.PW_RUN
		var corr_len: float = maxf(md.get("corr_len", 14.0), PlatformModule.TUNNEL_MIN + 6.0)      # see StationPlan: the tunnel must stop before the landing
		var is_box: bool = StationCharacter.platform_is_box(p.name, line_id, p.kind)
		var spine_x0 := -L * 0.5 if is_box else -L * 0.5 - 6.0
		var mx: float = rect[1] + corr_len - spine_x0
		var mpos := Vector3(mx, room["y"], lane_z)
		var faces_spec: Array = []
		var facelist: Array = []
		for fdef in faces_def:
			var pid: String = fdef[0]
			var pl: Dictionary = st["platforms"][pid]
			var lid: String = pl["lines"][0]
			faces_spec.append({"pid": pid, "line": lid, "color": Net.line_color(lid), "label": p.dir_text(pid), "face": int(fdef[1]), "lines": pl["lines"]})
			facelist.append({"pid": pid, "face": int(fdef[1])})
		var wall_style := "tile_cream" if (p.seed_value + mod_i) % 3 == 0 else "tile_white"
		var stripes := p._stripes_for(p.seed_value + mod_i, faces_spec[0]["color"])
		var character := StationCharacter.platform(p.name, faces_spec[0]["line"], p.kind)
		if not character.is_empty():
			wall_style = character["wall"]
			stripes = character["stripes"]
		var openings_x := [-L * 0.5 + 8.0, -L * 0.5 + 8.0 + 14.0]
		var tun_w := corr_len - spine_x0 - L * 0.5 - 1.0
		var mspec := {"tun_w": tun_w, "style": "box" if is_box else "arch", "roof": "glass" if p.kind == "surface" else "flat", "length": L, "pw": pw, "wall": wall_style, "stripes": stripes, "character": character,
			"seed": p.seed_value + mod_i * 7, "faces": faces_spec, "openings_x": openings_x, "spine_x0": spine_x0, "spine_x1": -L * 0.5 + 8.0 + 14.0 + 6.0, "name": p.name, "group": group}
		var level := int(room["name"].substr(7)) if str(room["name"]).begins_with("landing") else 0
		p.modules.append({"pos": mpos, "spec": mspec, "faces": facelist, "level": level, "group": group, "lane_z": lane_z, "corr": [rect[1], mpos.x + spine_x0], "room": room["name"]})
		room["openings"].append({"side": "E", "c": lane_z, "w": StationPlan.CORR_W, "h": StationPlan.SPINE_H, "id": "corr%d" % mod_i})
		corr_rooms.append({"name": "corridor%d_%d" % [level, mod_i], "rect": [rect[1], mpos.x + spine_x0, lane_z - StationPlan.CORR_W * 0.5, lane_z + StationPlan.CORR_W * 0.5], "y": mpos.y, "h": StationPlan.SPINE_H,
			"open_ends": ["E", "W"], "wall": wall_style, "floor": "floor_platform", "lights": "strip_x", "light_dx": 4.0, "seed": p.seed_value + mod_i,
			"bands": StationCharacter.stripe_bands(stripes, StationPlan.SPINE_H) if not character.is_empty() else []})
		for fi in faces_spec.size():
			var f: Dictionary = faces_spec[fi]
			var side: float = 1.0 if fi == 0 else -1.0
			var key := "%s#%d" % [f["pid"], f["face"]]
			var zwall := PlatformModule.GAP * 0.5
			var edge_z := side * (zwall + pw)
			p.faces[key] = {"module": mod_i, "face": fi, "pid": f["pid"], "face_no": f["face"], "line": f["line"],
				"pos": mpos + Vector3(0, 0, edge_z - side * 1.0), "edge_z": mpos.z + edge_z, "side": side, "x0": mpos.x - L * 0.5, "x1": mpos.x + L * 0.5, "y": mpos.y,
				"track_z": mpos.z + side * (zwall + pw + PlatformModule.TRACK_TO_EDGE), "length": L, "pw": pw, "cars": cars}
		mod_by_room[mod_i] = room
		mod_i += 1

	# --------------------------------------------------------------------------------------------------- room specs (Space)
	for rd in order:
		var band := Color(0.02, 0.18, 0.5)
		var rspec := {"name": rd["name"], "rect": rd["rect"], "y": rd["y"], "h": rd["h"], "openings": rd["openings"], "wall": "tile_white", "floor": "floor_hall",
			"lights": "grid", "light_dx": 4.5, "light_dz": 5.0, "seed": p.seed_value + 30 + int(order.find(rd)), "band": band, "level": int(str(rd["name"]).substr(7)) if rd["kind"] != "hall" else 0}
		if rd["kind"] == "hall":
			rspec.merge(StationCharacter.hall(p.name), true)
		p.rooms.append(rspec)
	for cr in corr_rooms:
		p.rooms.append(cr)
	p.escs = escs_out

	if not _check_overlaps(p):
		return false
	_build_graph(p, rooms, order, conns, esc_of)
	return true


# ---------------------------------------------------------------------------------------------------------------------------------
static func _place_esc(p: StationPlan, rooms: Dictionary, cn: Dictionary, escs_out: Array, esc_of: Dictionary) -> bool:
	var d: Dictionary = cn["d"]
	var from: Dictionary = rooms[d["from"]]
	var to: Dictionary = rooms[d["to"]]
	var dir: String = d["dir"]
	var c: float = d["c"]
	var rise: float = from["y"] - to["y"]
	if rise < 0.5:
		return _err(p, "escalator %s must go down (from depth %.1f to %.1f)" % [str(d.get("id", "")), -from["y"], -to["y"]])
	var lanes: Array = d.get("lanes", [1, -1])
	var stairs: bool = d.get("stairs", rise < 6.0)
	if stairs:
		lanes = [1, -1]
	var width := lanes.size() * Escalator.PITCH + 0.6
	var length := Escalator.PLATE * 2.0 + rise / tan(Escalator.ANGLE)
	var fr: Array = from["rect"]
	var top := Vector3.ZERO
	match dir:
		"S": top = Vector3(c, from["y"], fr[3])
		"N": top = Vector3(c, from["y"], fr[2])
		"E": top = Vector3(fr[1], from["y"], c)
		"W": top = Vector3(fr[0], from["y"], c)
	var end: Vector3 = top + (DIRS[dir] as Vector3) * length
	if to["rect"] == null:
		var sz: Array = to["size"]
		var sx: float = sz[0]
		var sz2: float = sz[1]
		var dx: float = d.get("to_off", 0.0)
		match dir:
			"S": to["rect"] = [c + dx - sx * 0.5, c + dx + sx * 0.5, end.z, end.z + sz2]
			"N": to["rect"] = [c + dx - sx * 0.5, c + dx + sx * 0.5, end.z - sz2, end.z]
			"E": to["rect"] = [end.x, end.x + sx, c + dx - sz2 * 0.5, c + dx + sz2 * 0.5]
			"W": to["rect"] = [end.x - sx, end.x, c + dx - sz2 * 0.5, c + dx + sz2 * 0.5]
	else:
		var tr: Array = to["rect"]
		var wall_at: float = {"S": tr[2], "N": tr[3], "E": tr[0], "W": tr[1]}[dir]
		var end_at: float = end.z if (dir == "S" or dir == "N") else end.x
		if absf(wall_at - end_at) > 0.4:
			return _err(p, "escalator %s ends at %.2f but room %s has its wall at %.2f" % [str(d.get("id", "")), end_at, str(d["to"]), wall_at])
	var trr: Array = to["rect"]
	var lo: float = trr[0] if (dir == "S" or dir == "N") else trr[2]
	var hi: float = trr[1] if (dir == "S" or dir == "N") else trr[3]
	if c - width * 0.5 < lo + 0.2 or c + width * 0.5 > hi - 0.2:
		return _err(p, "escalator %s lands outside room %s (across range %.1f..%.1f, escalator at %.1f, width %.1f)" % [str(d.get("id", "")), str(d["to"]), lo, hi, c, width])
	var frr: Array = from["rect"]
	var flo: float = frr[0] if (dir == "S" or dir == "N") else frr[2]
	var fhi: float = frr[1] if (dir == "S" or dir == "N") else frr[3]
	if c - width * 0.5 < flo + 0.2 or c + width * 0.5 > fhi - 0.2:
		return _err(p, "escalator %s starts outside room %s (across range %.1f..%.1f, escalator at %.1f, width %.1f)" % [str(d.get("id", "")), str(d["from"]), flo, fhi, c, width])
	var eid := "esc%d" % escs_out.size()
	esc_of[str(d.get("id", eid))] = escs_out.size()
	escs_out.append({"id": eid, "pos": top, "yaw": YAW[dir], "rise": rise, "lanes": lanes, "length": length, "width": width, "stairs": stairs,
		"from": from["name"], "to": to["name"], "dir": dir, "c": c})
	from["openings"].append({"side": dir, "c": c, "w": width, "h": Escalator.CLEARANCE, "id": eid + "_top"})
	to["openings"].append({"side": OPP[dir], "c": c, "w": width, "h": Escalator.CLEARANCE, "id": eid + "_bot"})
	return true


static func _place_link(p: StationPlan, rooms: Dictionary, cn: Dictionary) -> bool:
	var d: Dictionary = cn["d"]
	var a: Dictionary = rooms[d["a"]]
	var b: Dictionary = rooms[d["b"]]
	var side: String = d["side"]
	var c: float = d["c"]
	var w: float = d.get("w", StationPlan.CORR_W)
	var h: float = d.get("h", StationPlan.SPINE_H)
	var ar: Array = a["rect"]
	if b["rect"] == null:
		var sz: Array = b["size"]
		match side:
			"E": b["rect"] = [ar[1], ar[1] + sz[0], c - sz[1] * 0.5, c + sz[1] * 0.5]
			"W": b["rect"] = [ar[0] - sz[0], ar[0], c - sz[1] * 0.5, c + sz[1] * 0.5]
			"S": b["rect"] = [c - sz[0] * 0.5, c + sz[0] * 0.5, ar[3], ar[3] + sz[1]]
			"N": b["rect"] = [c - sz[0] * 0.5, c + sz[0] * 0.5, ar[2] - sz[1], ar[2]]
	var br: Array = b["rect"]
	var touch: float = {"E": absf(br[0] - ar[1]), "W": absf(br[1] - ar[0]), "S": absf(br[2] - ar[3]), "N": absf(br[3] - ar[2])}[side]
	if touch > 0.3:
		return _err(p, "link %s: rooms %s and %s do not touch on side %s (gap %.2f)" % [str(d.get("id", "")), str(d["a"]), str(d["b"]), side, touch])
	if absf(a["y"] - b["y"]) > 0.6:
		return _err(p, "link between rooms at different depths: use an escalator")
	var lid := str(d.get("id", "link"))
	a["openings"].append({"side": side, "c": c, "w": w, "h": h, "id": lid + "_a"})
	b["openings"].append({"side": OPP[side], "c": c, "w": w, "h": h, "id": lid + "_b"})
	return true


# ---------------------------------------------------------------------------------------------------------------------------------
# Walking graph. Node naming follows the generator where other code depends on it (hall_unpaid/paid, gate_in/out, escN_top/bot, mN_spine ...).
static func _build_graph(p: StationPlan, rooms: Dictionary, order: Array, conns: Array, esc_of: Dictionary) -> void:
	# nodes at room centres (halls: unpaid/paid zone nodes on either side of the gateline)
	var room_node: Dictionary = {}       # room id -> node name used when arriving in the room from the paid side
	for rd in order:
		var r: Array = rd["rect"]
		var cx: float = (float(r[0]) + float(r[1])) * 0.5
		var cz: float = (float(r[2]) + float(r[3])) * 0.5
		if rd["kind"] == "hall":
			var hi: int = rd["hidx"]
			var pre := "" if hi == 0 else str(hi + 1)
			var gl: Dictionary = rd["gateline_data"]
			var gz: float = gl["z"]
			var gcx: float = gl["cx"]
			p._node("hall%s_unpaid" % pre, Vector3(gcx, 0, gz - 2.5))
			p._node("hall%s_paid" % pre, Vector3(gcx, 0, gz + 3.0))
			p._node("gate%s_in" % ("" if hi == 0 else str(hi + 1)), Vector3(gcx, 0, gz - 0.9))
			p._node("gate%s_out" % ("" if hi == 0 else str(hi + 1)), Vector3(gcx, 0, gz + 0.9))
			p._edge("hall%s_unpaid" % pre, "gate%s_in" % ("" if hi == 0 else str(hi + 1)))
			p._edge("gate%s_in" % ("" if hi == 0 else str(hi + 1)), "gate%s_out" % ("" if hi == 0 else str(hi + 1)), 3.5)
			p._edge("gate%s_out" % ("" if hi == 0 else str(hi + 1)), "hall%s_paid" % pre)
			room_node[rd["id"]] = "hall%s_paid" % pre
			for sd in rd["door_list"]:
				p._node(sd["id"], sd["pos"])
				p._edge(sd["id"], "hall%s_unpaid" % pre)
		else:
			var nn := "room_%s" % rd["name"]
			p._node(nn, Vector3(cx, rd["y"], cz))
			room_node[rd["id"]] = nn
	# escalators
	for cn in conns:
		var d: Dictionary = cn["d"]
		if cn["type"] == "esc":
			var ei: int = esc_of[str(d.get("id", ""))] if esc_of.has(str(d.get("id", ""))) else -1
			if ei < 0:
				continue
			var e: Dictionary = p.escs[ei]
			var dirv: Vector3 = DIRS[e["dir"]]
			var top_name := "esc%d_top" % ei
			var bot_name := "esc%d_bot" % ei
			var pos: Vector3 = e["pos"]
			var end: Vector3 = pos + dirv * float(e["length"])
			var c: float = e["c"]
			# approach nodes in front of the openings so straight edges pass through them
			var pre_top := pos - dirv * 2.5
			var post_bot := end + dirv * 3.0
			var from_n: String = room_node[d["from"]]
			var to_n: String = room_node[d["to"]]
			p._node("esc%d_pre" % ei, pre_top)
			p._node(top_name, pos + dirv * 1.0)
			p._node(bot_name, end + dirv * 1.0)
			p._node("esc%d_post" % ei, post_bot)
			p._edge(from_n, "esc%d_pre" % ei)
			p._edge("esc%d_pre" % ei, top_name)
			var slope_len: float = e["rise"] / sin(Escalator.ANGLE)
			p._edge(top_name, bot_name, slope_len / 1.15 + 3.0)
			p._edge(bot_name, "esc%d_post" % ei)
			p._edge("esc%d_post" % ei, to_n)
		else:
			var a: Dictionary = rooms[d["a"]]
			var b: Dictionary = rooms[d["b"]]
			var side: String = d["side"]
			var cc: float = d["c"]
			var ar: Array = a["rect"]
			var wall: float = {"E": ar[1], "W": ar[0], "S": ar[3], "N": ar[2]}[side]
			var dv: Vector3 = DIRS[side]
			var mid := Vector3(wall, a["y"], cc) if (side == "E" or side == "W") else Vector3(cc, a["y"], wall)
			var lid := str(d.get("id", "link"))
			p._node("%s_a" % lid, mid - dv * 2.5)
			p._node("%s_b" % lid, mid + dv * 2.5)
			p._edge(room_node[d["a"]], "%s_a" % lid)
			p._edge("%s_a" % lid, "%s_b" % lid)
			p._edge("%s_b" % lid, room_node[d["b"]])
	# modules
	for mi in p.modules.size():
		var m: Dictionary = p.modules[mi]
		var mp: Vector3 = m["pos"]
		var spec: Dictionary = m["spec"]
		var room: Dictionary = {}
		for rd in order:
			if rd["name"] == m["room"]:
				room = rd
		var rect: Array = room["rect"]
		var sp_in := "m%d_spine" % mi
		p._node("m%d_pre" % mi, Vector3(rect[1] - 2.5, mp.y, m["lane_z"]))
		p._node(sp_in, Vector3(mp.x + spec["spine_x0"] + 3.0, mp.y, m["lane_z"]))
		p._edge(room_node[room["id"]], "m%d_pre" % mi)
		p._edge("m%d_pre" % mi, sp_in)
		var ox: Array = spec["openings_x"]
		var prev_open := sp_in
		for oi in ox.size():
			var on := "m%d_open%d" % [mi, oi]
			p._node(on, Vector3(mp.x + ox[oi], mp.y, m["lane_z"]))
			p._edge(prev_open, on)
			prev_open = on
		for fi in m["faces"].size():
			var fdef: Dictionary = m["faces"][fi]
			var key := "%s#%d" % [fdef["pid"], fdef["face"]]
			var fc: Dictionary = p.faces[key]
			var mid := "face:" + key
			p._node(mid, Vector3(mp.x, mp.y, fc["pos"].z))
			for oi in ox.size():
				var pn2 := "m%d_open%d_p%d" % [mi, oi, fi]
				p._node(pn2, Vector3(mp.x + ox[oi], mp.y, fc["pos"].z))
				p._edge("m%d_open%d" % [mi, oi], pn2)
				p._edge(pn2, mid)
	p.finish_common()


# ---------------------------------------------------------------------------------------------------------------------------------
# Authoring aid: everything that occupies space (rooms, corridors, escalator shafts, platform modules) must not intersect anything else.
static func _check_overlaps(p: StationPlan) -> bool:
	var boxes: Array = []      # {name, aabb}
	for rm in p.rooms:
		if String(rm["name"]).begins_with("street_passage"):
			continue
		var r: Array = rm["rect"]
		var rbox := {"name": rm["name"], "aabb": AABB(Vector3(r[0], rm["y"] - 0.4, r[2]), Vector3(r[1] - r[0], float(rm["h"]) + 0.8, r[3] - r[2])), "kind": "room"}
		if String(rm["name"]).begins_with("corridor"):
			rbox["mod"] = int(String(rm["name"]).get_slice("_", 1))          # "corridor<level>_<module>": a module and its own passage meet end to end
		boxes.append(rbox)
	for e in p.escs:
		var dirv: Vector3 = DIRS[e["dir"]]
		var pos: Vector3 = e["pos"]
		var length: float = e["length"]
		var width: float = e["width"]
		var run: float = float(e["rise"]) / tan(Escalator.ANGLE)
		var steps := int(ceil(length / 2.0))
		for i in steps:
			var t0: float = length * float(i) / steps
			var t1: float = length * float(i + 1) / steps
			var yf0 := _esc_floor(t0, run, float(e["rise"]))
			var yf1 := _esc_floor(t1, run, float(e["rise"]))
			var ylo := minf(yf0, yf1) - 0.3
			var yhi := maxf(yf0, yf1) + Escalator.CLEARANCE + 0.3
			var a: Vector3 = pos + dirv * t0
			var b: Vector3 = pos + dirv * t1
			var across := Vector3(absf(dirv.z), 0, absf(dirv.x)) * (width * 0.5)
			var lo := Vector3(minf(a.x, b.x), 0, minf(a.z, b.z)) - across
			var hi := Vector3(maxf(a.x, b.x), 0, maxf(a.z, b.z)) + across
			boxes.append({"name": "%s (segment %d)" % [e["id"], i], "aabb": AABB(Vector3(lo.x, pos.y + ylo, lo.z), Vector3(hi.x - lo.x, yhi - ylo, hi.z - lo.z)), "kind": "esc", "esc": e["id"]})
	for mi in p.modules.size():
		var m: Dictionary = p.modules[mi]
		var mp: Vector3 = m["pos"]
		var L: float = m["spec"]["length"]
		boxes.append({"name": "module%d" % mi, "aabb": AABB(Vector3(mp.x - L * 0.5 - 1.0, mp.y - 1.4, mp.z - 8.6), Vector3(L + 2.0, 5.8, 17.2)), "kind": "module", "mod": mi})
		# the running tunnels beyond both platform ends (the west one is shortened to stop before the landing; a cap closes it)
		var tw: float = m["spec"].get("tun_w", PlatformModule.TUNNEL_EXT)
		var te: float = m["spec"].get("tun_e", PlatformModule.TUNNEL_EXT)
		boxes.append({"name": "module%d tunnel (west)" % mi, "aabb": AABB(Vector3(mp.x - L * 0.5 - tw, mp.y - 1.4, mp.z - 8.6), Vector3(tw - 1.0, 5.8, 17.2)), "kind": "tunnel", "mod": mi})
		boxes.append({"name": "module%d tunnel (east)" % mi, "aabb": AABB(Vector3(mp.x + L * 0.5 + 1.0, mp.y - 1.4, mp.z - 8.6), Vector3(te, 5.8, 17.2)), "kind": "tunnel", "mod": mi})
	var ok := true
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			var bi: Dictionary = boxes[i]
			var bj: Dictionary = boxes[j]
			if bi["kind"] == "esc" and bj["kind"] == "esc" and bi["esc"] == bj["esc"]:
				continue
			if bi.get("mod", -1) == bj.get("mod", -2):
				continue                 # a module and its own tunnels
			# the module's own connecting passage runs between its two tunnels
			if (bi["kind"] == "tunnel" and bj["kind"] == "room" and str(bj["name"]).begins_with("corridor")) or (bj["kind"] == "tunnel" and bi["kind"] == "room" and str(bi["name"]).begins_with("corridor")):
				continue
			# an escalator legitimately touches the two rooms it connects; shrink the test a little
			var a: AABB = (bi["aabb"] as AABB).grow(-0.35)
			var b: AABB = (bj["aabb"] as AABB).grow(-0.35)
			if a.size.x <= 0.0 or a.size.y <= 0.0 or a.size.z <= 0.0 or b.size.x <= 0.0 or b.size.y <= 0.0 or b.size.z <= 0.0:
				continue
			if a.intersects(b):
				if bi["kind"] == "esc" and bj["kind"] == "room" and _esc_touches(p, str(bi["esc"]), str(bj["name"])):
					continue
				if bj["kind"] == "esc" and bi["kind"] == "room" and _esc_touches(p, str(bj["esc"]), str(bi["name"])):
					continue
				push_error("Layout %s: %s overlaps %s" % [p.name, bi["name"], bj["name"]])
				ok = false
	return ok


static func _esc_touches(p: StationPlan, esc_id: String, room_name: String) -> bool:
	for e in p.escs:
		if e["id"] == esc_id:
			return e["from"] == room_name or e["to"] == room_name
	return false


## floor height (relative to the top plate) at distance t along an escalator run
static func _esc_floor(t: float, run: float, rise: float) -> float:
	if t <= Escalator.PLATE:
		return 0.0
	if t >= Escalator.PLATE + run:
		return -rise
	return -(t - Escalator.PLATE) * tan(Escalator.ANGLE)
