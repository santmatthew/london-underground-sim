class_name StationSigns
extends RefCounted
## Places wayfinding for a StationPlan into a Station node. Everything is derived from the plan so signs always agree with the layout.

const HANG_ROD := Color(0.35, 0.36, 0.38)

static var _rod_mat: StandardMaterial3D


static func place(station: Station) -> void:
	var plan := station.plan
	var root := Node3D.new()
	root.name = "Signs"
	station.add_child(root)
	var lines: Array = _lines_here(plan)
	for gl in plan.gatelines:
		_hall_signs_at(root, plan, gl, lines)
	if plan.authored:
		_authored_signs(root, plan)
	else:
		for li in plan.escs.size():
			_landing_signs(station, root, plan, li)
	for mi in plan.modules.size():
		_module_signs(station, root, plan, mi)
	cull(root, 42.0)
	for pm in station.modules:
		for c in pm.get_children():
			if c is Node3D and not (c is MeshInstance3D) and c.name not in ["Collision", "EdgeGuard", "Lights", "Props"] and not (c is Train):
				cull(c, 42.0)


static func _lines_here(plan: StationPlan) -> Array:
	var st: Dictionary = Net.stations[plan.idx]
	var out: Array = []
	for lid in Net.line_ids:
		if lid in st["lines"]:
			out.append(lid)
	return out


static func _line_rows(lines: Array, arrow: int, arrow_side := "left") -> Array:
	var rows: Array = []
	for lid in lines:
		rows.append({"text": "%s line" % Net.line_name(lid), "color": Net.line_color(lid), "arrow": arrow, "arrow_side": arrow_side, "bold": true})
	return rows


## Hang a board from `ceiling_y` at `pos` (its centre), facing horizontal direction `face` (unit vector)
static func hang(parent: Node3D, board: Node3D, pos: Vector3, face: Vector3, ceiling_y: float, double_sided := false) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = atan2(face.x, face.z)
	holder.add_child(board)
	parent.add_child(holder)
	# rods to the ceiling
	var rod_len := ceiling_y - pos.y
	if rod_len > 0.05:
		if _rod_mat == null:
			_rod_mat = StandardMaterial3D.new()
			_rod_mat.albedo_color = HANG_ROD
			_rod_mat.metallic = 0.8
			_rod_mat.roughness = 0.4
		for sx in [-0.5, 0.5]:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.012
			cm.bottom_radius = 0.012
			cm.height = rod_len
			mi.mesh = cm
			mi.material_override = _rod_mat
			mi.position = Vector3(sx * 0.9, rod_len * 0.5 + 0.2, -0.02)
			holder.add_child(mi)
	if double_sided:
		var back := board.duplicate()
		back.rotation.y = PI
		back.position.z = -0.03
		holder.add_child(back)


## Rods (stems) are thin cylinders from y_from up to y_to at (x, z) in `parent`'s frame
static func _stem(parent: Node3D, x: float, z: float, y_from: float, y_to: float) -> void:
	if y_to - y_from < 0.03:
		return
	if _rod_mat == null:
		_rod_mat = StandardMaterial3D.new()
		_rod_mat.albedo_color = HANG_ROD
		_rod_mat.metallic = 0.8
		_rod_mat.roughness = 0.4
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = y_to - y_from
	mi.mesh = cm
	mi.material_override = _rod_mat
	mi.position = Vector3(x, (y_from + y_to) * 0.5, z)
	parent.add_child(mi)


## Hang a board in a room. `pos` is the wanted centre; the board is scaled so that it is at most `max_w` wide, its underside stays
## HEAD above the floor and its top stays under the ceiling, then it is hung on two stems from the ceiling.
static func hang_room(parent: Node3D, board: Node3D, pos: Vector3, face: Vector3, floor_y: float, ceil_y: float, max_w := 4.0) -> void:
	var size: Vector2 = board.get_meta("size", Vector2(2.4, 0.6))
	var room_h := ceil_y - 0.05 - (floor_y + PlatformModule.HEAD)
	var k := minf(1.0, max_w / size.x)
	if size.y * k > room_h:
		k = maxf(0.35, room_h / size.y)
	board.scale = board.scale * k
	board.set_meta("hung", true)
	var w := size.x * k
	var h := size.y * k
	var y_top := minf(pos.y + h * 0.5, ceil_y - 0.05)
	y_top = maxf(y_top, floor_y + PlatformModule.HEAD + h)
	y_top = minf(y_top, ceil_y - 0.05)
	var holder := Node3D.new()
	holder.position = Vector3(pos.x, y_top - h * 0.5, pos.z)
	holder.rotation.y = atan2(face.x, face.z)
	holder.add_child(board)
	parent.add_child(holder)
	# stems along the board's width axis (local x), from the top edge to the ceiling
	var across := Vector3(face.z, 0, -face.x)      # local +x of the holder in the parent's frame
	for sx in [-1.0, 1.0]:
		var o: Vector3 = across * (sx * maxf(w * 0.5 - 0.15, 0.1))
		_stem(parent, pos.x + o.x, pos.z + o.z, y_top, ceil_y)


## Flat on a wall: `pos` is the centre on the wall surface, `face` the wall normal. Scaled down to fit max_w x max_h.
static func mount_wall(parent: Node3D, board: Node3D, pos: Vector3, face: Vector3, max_w: float, max_h: float) -> void:
	var size: Vector2 = board.get_meta("size", Vector2(2.4, 0.6))
	var k := minf(1.0, minf(max_w / size.x, max_h / size.y))
	board.scale = board.scale * k
	var holder := Node3D.new()
	holder.position = pos + face * 0.02
	holder.rotation.y = atan2(face.x, face.z)
	holder.add_child(board)
	parent.add_child(holder)


## Blade in a platform tunnel/hall (module frame): faces along x (`face_x` = +1/-1, the direction the FRONT looks), spans z, is fitted
## under the roof by PlatformModule.fit_blade and hangs on stems that end exactly on the roof surface. `back` (optional) looks the other way.
static func hang_blade(pm: PlatformModule, s: float, x: float, z_want: float, y_top_want: float, front: Node3D, back: Node3D = null, face_x := -1.0) -> void:
	var size: Vector2 = front.get_meta("size", Vector2(2.4, 0.6))
	var fit := pm.fit_blade(s, z_want, size.x, size.y, y_top_want)
	var k: float = fit["k"]
	front.scale = front.scale * k
	front.set_meta("hung", true)
	var w := size.x * k
	var h := size.y * k
	var zc: float = fit["z"]
	var y_top: float = fit["y_top"]
	x = pm.clear_of_columns(x)
	var holder := Node3D.new()
	holder.position = Vector3(x, y_top - h * 0.5, zc)
	holder.rotation.y = atan2(face_x, 0.0)
	holder.add_child(front)
	if back != null:
		back.scale = back.scale * k
		back.set_meta("hung", true)
		back.rotation.y = PI
		back.position.z = -0.03
		holder.add_child(back)
	pm.add_child(holder)
	for sz in [-1.0, 1.0]:
		var zs: float = zc + sz * maxf(w * 0.5 - 0.15, 0.1)
		_stem(pm, x, zs, y_top, pm.ceiling_at(zs) + 0.02)


static func _arrow_for(viewer_dir: Vector3, target_dir: Vector3) -> int:
	# viewer looks along viewer_dir; returns 0 (right) / 2 (left) / 1 (forward) / 3 (back)
	var right := viewer_dir.cross(Vector3.UP)
	var fwd := viewer_dir.dot(target_dir)
	var r := right.dot(target_dir)
	if absf(fwd) > absf(r):
		return 1 if fwd > 0.0 else 3
	return 0 if r > 0.0 else 2


# ---------------------------------------------------------------------------------------------------
static func _hall_signs_at(root: Node3D, plan: StationPlan, gl: Dictionary, lines: Array) -> void:
	var r: Array = gl.get("rect", plan.hall["rect"])
	var gz: float = gl["z"]
	var h: float = StationPlan.HALL_H
	var cx: float = gl.get("cx", 0.0)
	var hall_name: String = gl.get("hall", "hall")
	# 1. above the gateline, facing the unpaid zone (people walking south to the gates): where to find trains
	var rows: Array = [{"text": "Trains", "bold": true, "icon": ""}]
	rows.append_array(_line_rows(lines, 1))
	hang_room(root, Signs.board(rows, 2.8, 0.36), Vector3(cx, h - 1.0 - rows.size() * 0.14, gz - 0.3), Vector3(0, 0, -1), 0.0, h, 3.6)
	# 2. above the gateline, facing the paid zone: way out
	hang_room(root, Signs.board([{"text": "Way out", "bold": true, "arrow": 1}], 2.2, 0.42), Vector3(cx, h - 1.15, gz + 0.3), Vector3(0, 0, 1), 0.0, h, 3.0)
	# 3. paid zone: "Platforms" above each escalator that leaves this hall (chain layouts: the S wall)
	var prows: Array = [{"text": "Platforms", "bold": true, "arrow": 3}]
	prows.append_array(_line_rows(lines, 3))
	var shown := false
	for e in plan.escs:
		if e.get("from", "hall") != hall_name:
			continue
		var d: String = e.get("dir", "S")
		var face := Vector3(0, 0, -1)
		var pos := Vector3(0, h - 0.95 - prows.size() * 0.16, 0)
		match d:
			"S": face = Vector3(0, 0, -1); pos = Vector3(e.get("c", cx), pos.y, r[3] - 0.5)
			"N": face = Vector3(0, 0, 1); pos = Vector3(e.get("c", cx), pos.y, r[2] + 0.5)
			"E": face = Vector3(-1, 0, 0); pos = Vector3(r[1] - 0.5, pos.y, e.get("c", 0.0))
			"W": face = Vector3(1, 0, 0); pos = Vector3(r[0] + 0.5, pos.y, e.get("c", 0.0))
		hang_room(root, Signs.board(prows, 3.0, 0.36), pos, face, 0.0, h, 3.6)
		shown = true
	if not shown and not plan.authored:
		hang_room(root, Signs.board(prows, 3.0, 0.36), Vector3(cx, h - 0.95 - prows.size() * 0.16, r[3] - 0.5), Vector3(0, 0, -1), 0.0, h, 3.6)
	# 4. paid zone: way out board mid-hall, facing +z
	hang_room(root, Signs.board([{"text": "Way out", "bold": true, "arrow": 1}], 2.2, 0.42), Vector3(cx, h - 1.1, gz + 6.0), Vector3(0, 0, 1), 0.0, h, 3.0)
	# 5. street passages: exit boards over the N wall openings (visible from inside the hall)
	for sd in plan.street_doors:
		if sd.get("hall", "hall") != hall_name:
			continue
		var rows5: Array = [{"text": "Way out", "bold": true, "arrow": 1}]
		if str(sd.get("exit_ref", "")) != "":
			# real exit number and street (OpenStreetMap), first street only to keep the board readable
			var st1: String = str(sd["exit_name"]).split(" / ")[0]
			rows5.append({"text": "Exit %s  %s" % [sd["exit_ref"], st1], "text_color": Color(0.8, 0.8, 0.8)})
		hang_room(root, Signs.board(rows5, 1.9, 0.34), Vector3(sd["c"], 3.35, r[2] + 0.4), Vector3(0, 0, 1), 0.0, h, 3.6 if plan.street_doors.size() > 3 else 3.0)


## Signs of a LayoutCompiler plan: at every escalator bottom "Way out", at every escalator top a "Platforms" board listing the lines below,
## at every platform corridor a board for its platforms.
static func _authored_signs(root: Node3D, plan: StationPlan) -> void:
	var by_name := {}
	for rm in plan.rooms:
		by_name[rm["name"]] = rm
	for e in plan.escs:
		var d: String = e["dir"]
		var c: float = e["c"]
		# bottom: way out, on the far side, facing into the room
		var to: Dictionary = by_name[e["to"]]
		var tr: Array = to["rect"]
		var ty: float = to["y"]
		var th: float = to["h"]
		var rows: Array = [{"text": "Way out", "bold": true, "arrow": 1}, {"text": "Escalators up" if not e["stairs"] else "Stairs up", "text_color": Color(0.8, 0.8, 0.8)}]
		var face := Vector3.ZERO
		var pos := Vector3.ZERO
		match d:
			"S": face = Vector3(0, 0, 1); pos = Vector3(c, ty + th - 1.2, tr[2] + 0.4)
			"N": face = Vector3(0, 0, -1); pos = Vector3(c, ty + th - 1.2, tr[3] - 0.4)
			"E": face = Vector3(1, 0, 0); pos = Vector3(tr[0] + 0.4, ty + th - 1.2, c)
			"W": face = Vector3(-1, 0, 0); pos = Vector3(tr[1] - 0.4, ty + th - 1.2, c)
		hang_room(root, Signs.board(rows, 2.4, 0.4), pos, face, ty, ty + th, 3.0)
		# top (only in landings; halls got theirs from _hall_signs_at): the lines below
		var from: Dictionary = by_name[e["from"]]
		if not String(e["from"]).begins_with("hall"):
			var fr: Array = from["rect"]
			var fy: float = from["y"]
			var fh: float = from["h"]
			var below := _lines_below(plan, e["to"])
			if below.is_empty():
				continue
			var prow: Array = [{"text": "Lower platforms", "bold": true, "arrow": 3}]
			for lid in below:
				prow.append({"text": "%s line" % Net.line_name(lid), "color": Net.line_color(lid), "arrow": 3, "bold": true})
			var fpos := Vector3.ZERO
			var fface := Vector3.ZERO
			match d:
				"S": fface = Vector3(0, 0, -1); fpos = Vector3(c, fy + fh - 0.95 - prow.size() * 0.14, fr[3] - 0.5)
				"N": fface = Vector3(0, 0, 1); fpos = Vector3(c, fy + fh - 0.95 - prow.size() * 0.14, fr[2] + 0.5)
				"E": fface = Vector3(-1, 0, 0); fpos = Vector3(fr[1] - 0.5, fy + fh - 0.95 - prow.size() * 0.14, c)
				"W": fface = Vector3(1, 0, 0); fpos = Vector3(fr[0] + 0.5, fy + fh - 0.95 - prow.size() * 0.14, c)
			hang_room(root, Signs.board(prow, 3.2, 0.36), fpos, fface, fy, fy + fh, 3.4)
	# platform boards: one per module, above its corridor opening on the room's E wall, facing -x
	for mi in plan.modules.size():
		var m: Dictionary = plan.modules[mi]
		var room: Dictionary = by_name[m["room"]]
		var rr: Array = room["rect"]
		var ry: float = room["y"]
		var rh: float = room["h"]
		var rrows: Array = []
		var seen := {}
		for fd in m["faces"]:
			var pid: String = fd["pid"]
			if seen.has(pid):
				continue
			seen[pid] = true
			var ln: String = plan.station_platform(pid)["lines"][0]
			rrows.append({"text": "%s line" % Net.line_name(ln), "color": Net.line_color(ln), "bold": true, "arrow": 0, "arrow_side": "right"})
			rrows.append({"text": "Platform %d  %s  %s" % [plan.platform_no[pid], plan.station_platform(pid)["dir"], plan.dest_text(pid, 2)], "text_color": Color(0.85, 0.85, 0.85)})
		hang_room(root, Signs.board(rrows, 3.6, 0.32), Vector3(rr[1] - 0.4, ry + rh - 0.95 - rrows.size() * 0.1, m["lane_z"]), Vector3(-1, 0, 0), ry, ry + rh, 3.4)


## lines whose platforms can be reached by going down from `room_name`
static func _lines_below(plan: StationPlan, room_name: String) -> Array:
	var out: Array = []
	var seen := {}
	var todo: Array = [room_name]
	while not todo.is_empty():
		var rn: String = todo.pop_back()
		if seen.has(rn):
			continue
		seen[rn] = true
		for m in plan.modules:
			if m["room"] == rn:
				for fd in m["faces"]:
					var ln: String = plan.station_platform(fd["pid"])["lines"][0]
					if not (ln in out):
						out.append(ln)
		for e in plan.escs:
			if e["from"] == rn:
				todo.append(e["to"])
	return out


static func _landing_signs(station: Station, root: Node3D, plan: StationPlan, li: int) -> void:
	var landing: Dictionary
	for rm in plan.rooms:
		if rm["name"] == "landing%d" % li:
			landing = rm
	var lr: Array = landing["rect"]
	var y: float = landing["y"]
	var h: float = landing["h"]
	# way out (up the escalators) facing +z, above the escalator opening on the N wall
	hang_room(root, Signs.board([{"text": "Way out", "bold": true, "arrow": 1}, {"text": "Escalators up", "text_color": Color(0.8, 0.8, 0.8)}], 2.4, 0.4), Vector3(0, y + h - 1.2, lr[2] + 0.3), Vector3(0, 0, 1), y, y + h, 3.0)
	# platforms of this level: one board per module corridor above its opening on the E wall, facing -x
	for mi in plan.modules.size():
		var m: Dictionary = plan.modules[mi]
		if m["level"] != li:
			continue
		var rows: Array = []
		for fd in m["spec"]["faces"]:
			pass
		var seen := {}
		for fd in m["faces"]:
			var pid: String = fd["pid"]
			if seen.has(pid):
				continue
			seen[pid] = true
			var ln: String = plan.station_platform(pid)["lines"][0]
			rows.append({"text": "%s line" % Net.line_name(ln), "color": Net.line_color(ln), "bold": true, "arrow": 0, "arrow_side": "right"})
			rows.append({"text": "%s  %s" % [plan.station_platform(pid)["dir"], plan.dest_text(pid, 2)], "text_color": Color(0.85, 0.85, 0.85)})
		hang_room(root, Signs.board(rows, 3.6, 0.32), Vector3(lr[1] - 0.4, y + h - 0.95 - rows.size() * 0.1, m["lane_z"]), Vector3(-1, 0, 0), y, y + h, 3.4)
	# deeper level: board above the S wall opening
	if li + 1 < plan.escs.size():
		var next_lines := {}
		for m in plan.modules:
			if m["level"] == li + 1:
				for fd in m["faces"]:
					next_lines[plan.station_platform(fd["pid"])["lines"][0]] = true
		var rows2: Array = [{"text": "Lower platforms", "bold": true, "arrow": 3}]
		for lid in next_lines:
			rows2.append({"text": "%s line" % Net.line_name(lid), "color": Net.line_color(lid), "arrow": 3, "bold": true})
		hang_room(root, Signs.board(rows2, 3.2, 0.36), Vector3(0, y + h - 0.95 - rows2.size() * 0.14, lr[3] - 0.5), Vector3(0, 0, -1), y, y + h, 3.4)


static func _module_signs(station: Station, root: Node3D, plan: StationPlan, mi: int) -> void:
	var m: Dictionary = plan.modules[mi]
	var pm: PlatformModule = station.modules[mi]
	var spec: Dictionary = m["spec"]
	var mp: Vector3 = m["pos"]
	var L: float = spec["length"]
	var ox: Array = spec["openings_x"]
	var meta: Dictionary = pm.meta
	var pw: float = spec["pw"]
	var zwall := PlatformModule.GAP * 0.5
	var zfar := zwall + pw + PlatformModule.TRACK_TO_EDGE + PlatformModule.TRACK_TO_WALL
	# --- corridor: way-out board for people walking back west, at the corridor's east end, facing +x
	var corr: Array = m["corr"]
	hang_room(root, Signs.board([{"text": "Way out", "bold": true, "arrow": 1}], 2.0, 0.4), Vector3(corr[1] - 4.0, mp.y + PlatformModule.SPINE_H - 0.3, m["lane_z"]), Vector3(1, 0, 0), mp.y, mp.y + PlatformModule.SPINE_H, 2.6)
	# --- spine blade boards facing -x (viewer walks +x): right = +z tunnel (face 0), left = -z tunnel (face 1)
	var view := Vector3(1, 0, 0)
	var rows: Array = []
	var faces: Array = spec["faces"]
	for fi in faces.size():
		var f: Dictionary = faces[fi]
		var pid: String = f["pid"]
		var side := Vector3(0, 0, 1.0 if fi == 0 else -1.0)
		var arr := _arrow_for(view, side)
		rows.append({"text": "Platform %d  %s" % [plan.platform_no[pid], f["label"]], "color": f["color"], "arrow": arr, "arrow_side": "left" if arr == 2 else "right", "bold": true})
		rows.append({"text": plan.dest_text(pid, 3), "text_color": Color(0.85, 0.85, 0.85)})
	var box := pm.box
	if not box:
		# the spine is only 2.6 m high: the platform directory is mounted flat on the spine's end wall, at eye level
		var sx1: float = pm.meta["spine_x1"]
		mount_wall(root, Signs.board(rows, 3.0, 0.3), Vector3(mp.x + sx1, mp.y + 1.7, m["lane_z"]), Vector3(-1, 0, 0), 3.0, 1.3)
	else:
		hang_room(root, Signs.board(rows, 3.0, 0.32), Vector3(mp.x - L * 0.5 + 4.5, mp.y + PlatformModule.BOX_H - 1.5, m["lane_z"]), Vector3(-1, 0, 0), mp.y, mp.y + PlatformModule.BOX_H, 3.4)
		for wx in [-L * 0.25, L * 0.05, L * 0.3]:
			hang_room(root, Signs.board([{"text": "Way out", "bold": true, "arrow": 1}], 1.9, 0.4), Vector3(mp.x + wx, mp.y + PlatformModule.BOX_H - 1.3, mp.z), Vector3(1, 0, 0), mp.y, mp.y + PlatformModule.BOX_H, 2.4)
	# --- per face: roundels, indicators, boards
	for fi in faces.size():
		var f2: Dictionary = faces[fi]
		var s := 1.0 if fi == 0 else -1.0
		var pid2: String = f2["pid"]
		var gp: int = Timetable.plat_index[plan.idx][pid2]
		# station name: white fascia + tile lettering + roundels on the track-side wall (facing the platform), roundels behind the platform
		var short_name: String = plan.name.replace(" (H&C)", "").replace(" (D&P)", "").replace(" (Circle)", "")
		var style := (plan.seed_value + mi) % 3
		var fas := Signs.fascia(short_name, L - 10.0, [1], 0)
		fas.position = Vector3(0, 1.98, s * (zfar - 0.03))
		fas.rotation.y = atan2(0.0, -s)
		pm.add_child(fas)
		var n := maxi(2, int(L / 30.0))
		for k in n:
			var x := -L * 0.5 + (k + 0.5) * L / n
			if (k + style) % 2 == 0:
				var tn := Signs.tile_name(short_name, 0.8)
				tn.position = Vector3(x, 1.0, s * (zfar - 0.03))
				tn.rotation.y = atan2(0.0, -s)
				pm.add_child(tn)
			else:
				var rd := Signs.roundel(short_name, 0.95, style == 1)
				rd.position = Vector3(x, 1.0, s * (zfar - 0.03))
				rd.rotation.y = atan2(0.0, -s)
				pm.add_child(rd)
			var near_open := false
			for o in ox:
				if absf(x + L / n * 0.3 - o) < 4.0:
					near_open = true
			if not near_open and not box:
				var rd2 := Signs.roundel(short_name, 0.85, style == 1)
				rd2.position = Vector3(x + L / n * 0.3, 1.75, s * (zwall + 0.03))
				rd2.rotation.y = atan2(0.0, s)
				pm.add_child(rd2)
		# dot-matrix indicators hung from the crown, double sided
		var apex := PlatformModule.SPRING_Y + PlatformModule.RISE
		var zc := s * (zwall + zfar) * 0.5
		var pz := s * (zwall + pw * 0.6)
		for ix in [-L * 0.5 + 14.0, L * 0.5 - 16.0]:
			# real indicators are about 2 m wide and hang tight under the crown
			hang_blade(pm, s, ix, pz, PlatformModule.SPRING_Y + 1.2 if not box else PlatformModule.BOX_H - 0.9, Signs.indicator(gp, 2.0), Signs.indicator(gp, 2.0), -1.0)
		# platform id + line board over the opening (blade, both directions)
		var brd_rows: Array = [{"text": "%s line" % Net.line_name(f2["line"]), "color": f2["color"], "bold": true},
			{"text": "Platform %d  %s" % [plan.platform_no[pid2], f2["label"]], "bold": true}]
		var dt := plan.dest_text(pid2, 3)
		if dt != "":
			brd_rows.append({"text": dt, "text_color": Color(0.85, 0.85, 0.85)})
		# the two faces' blades are staggered along the platform so they do not line up and hide each other
		var stagger := (-2.8 if fi == 0 else 2.8)
		for ix2 in [-L * 0.5 + 34.0 + stagger, L * 0.5 - 34.0 + stagger]:
			var b := Signs.board(brd_rows, 2.2, 0.28, Color.WHITE, 2.6)
			var b2 := Signs.board(brd_rows, 2.2, 0.28, Color.WHITE, 2.6)
			hang_blade(pm, s, ix2, pz, PlatformModule.SPRING_Y + 1.15 if not box else PlatformModule.BOX_H - 1.0, b, b2, -1.0)
		# way-out boards at each opening, facing along the platform, pointing toward the wall side (the opening)
		for o in (ox if not box else []):
			for view_dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
				var target := Vector3(0, 0, -s)      # the opening is toward the spine
				var a := _arrow_for(view_dir, target)
				var wb := Signs.board([{"text": "Way out", "bold": true, "arrow": a, "arrow_side": "left" if a == 2 else "right"}, {"text": "Other platform", "text_color": Color(0.8, 0.8, 0.8), "arrow": a, "arrow_side": "left" if a == 2 else "right"}], 1.9, 0.28, Color.WHITE, 2.1)
				hang_blade(pm, s, o + (0.15 if view_dir.x > 0 else -0.15), s * (zwall + 1.1), PlatformModule.SPRING_Y + 0.9, wb, null, -view_dir.x)


static func _rods(holder: Node3D, length: float) -> void:
	if _rod_mat == null:
		_rod_mat = StandardMaterial3D.new()
		_rod_mat.albedo_color = HANG_ROD
		_rod_mat.metallic = 0.8
		_rod_mat.roughness = 0.4
	for sx in [-0.8, 0.8]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.012
		cm.height = length
		mi.mesh = cm
		mi.material_override = _rod_mat
		mi.position = Vector3(sx, length * 0.5 + 0.3, 0.0)
		holder.add_child(mi)


## distance-cull every renderable under `n` (cheap: keeps far-away signs out of the draw list)
static func cull(n: Node, dist: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).visibility_range_end = dist
		(n as GeometryInstance3D).visibility_range_end_margin = 4.0
	for c in n.get_children():
		cull(c, dist)
