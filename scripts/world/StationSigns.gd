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
	_hall_signs(station, root, plan, lines)
	for li in plan.escs.size():
		_landing_signs(station, root, plan, li)
	for mi in plan.modules.size():
		_module_signs(station, root, plan, mi)


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


static func _arrow_for(viewer_dir: Vector3, target_dir: Vector3) -> int:
	# viewer looks along viewer_dir; returns 0 (right) / 2 (left) / 1 (forward) / 3 (back)
	var right := viewer_dir.cross(Vector3.UP)
	var fwd := viewer_dir.dot(target_dir)
	var r := right.dot(target_dir)
	if absf(fwd) > absf(r):
		return 1 if fwd > 0.0 else 3
	return 0 if r > 0.0 else 2


# ---------------------------------------------------------------------------------------------------
static func _hall_signs(station: Station, root: Node3D, plan: StationPlan, lines: Array) -> void:
	var r: Array = plan.hall["rect"]
	var gz: float = plan.gates["z"]
	var h: float = plan.hall["h"]
	# 1. above the gateline, facing the unpaid zone (people walking south to the gates): where to find trains
	var rows: Array = [{"text": "Trains", "bold": true, "icon": ""}]
	rows.append_array(_line_rows(lines, 1))
	hang(root, Signs.board(rows, 2.8, 0.36), Vector3(0, h - 1.0 - rows.size() * 0.14, gz - 0.3), Vector3(0, 0, -1), h)
	# 2. above the gateline, facing the paid zone: way out
	hang(root, Signs.board([{"text": "Way out", "bold": true, "arrow": 1}], 2.2, 0.42), Vector3(0, h - 1.15, gz + 0.3), Vector3(0, 0, 1), h)
	# 3. paid zone, above the escalators (S wall) facing north (viewers heading south)
	var esc_w: float = plan.escs[0]["width"]
	var prows: Array = [{"text": "Platforms", "bold": true, "arrow": 3}]
	prows.append_array(_line_rows(lines, 3))
	hang(root, Signs.board(prows, 3.0, 0.36), Vector3(0, h - 0.95 - prows.size() * 0.16, r[3] - 0.5), Vector3(0, 0, -1), h)
	# 4. paid zone: way out board mid-hall, facing +z
	hang(root, Signs.board([{"text": "Way out", "bold": true, "arrow": 1}], 2.2, 0.42), Vector3(0, h - 1.1, gz + 6.0), Vector3(0, 0, 1), h)
	# 5. street passages: exit boards over the N wall openings (visible from inside the hall)
	for sd in plan.street_doors:
		hang(root, Signs.board([{"text": "Way out", "bold": true, "arrow": 1}], 1.9, 0.38), Vector3(sd["c"], 3.35, r[2] + 0.25), Vector3(0, 0, 1), h)


static func _landing_signs(station: Station, root: Node3D, plan: StationPlan, li: int) -> void:
	var landing: Dictionary
	for rm in plan.rooms:
		if rm["name"] == "landing%d" % li:
			landing = rm
	var lr: Array = landing["rect"]
	var y: float = landing["y"]
	var h: float = landing["h"]
	# way out (up the escalators) facing +z, above the escalator opening on the N wall
	hang(root, Signs.board([{"text": "Way out", "bold": true, "arrow": 1}, {"text": "Escalators up", "text_color": Color(0.8, 0.8, 0.8)}], 2.4, 0.4), Vector3(0, y + h - 1.2, lr[2] + 0.3), Vector3(0, 0, 1), y + h)
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
		hang(root, Signs.board(rows, 3.6, 0.32), Vector3(lr[1] - 0.4, y + h - 0.95 - rows.size() * 0.1, m["lane_z"]), Vector3(-1, 0, 0), y + h)
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
		hang(root, Signs.board(rows2, 3.2, 0.36), Vector3(0, y + h - 0.95 - rows2.size() * 0.14, lr[3] - 0.5), Vector3(0, 0, -1), y + h)


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
	hang(root, Signs.board([{"text": "Way out", "bold": true, "arrow": 1}], 2.0, 0.4), Vector3(corr[1] - 4.0, mp.y + PlatformModule.SPINE_H - 0.75, m["lane_z"]), Vector3(1, 0, 0), mp.y + PlatformModule.SPINE_H)
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
	var spx: float = mp.x + (ox[0] - 2.5 if not box else -L * 0.5 + 4.5)
	var spy: float = (mp.y + PlatformModule.SPINE_H - 0.55 - rows.size() * 0.09) if not box else (mp.y + PlatformModule.BOX_H - 1.5 - rows.size() * 0.09)
	hang(root, Signs.board(rows, 3.1, 0.34), Vector3(spx, spy, m["lane_z"]), Vector3(-1, 0, 0), mp.y + (PlatformModule.SPINE_H if not box else PlatformModule.BOX_H))
	if box:
		for wx in [-L * 0.25, L * 0.05, L * 0.3]:
			hang(root, Signs.board([{"text": "Way out", "bold": true, "arrow": 1}], 1.9, 0.4), Vector3(mp.x + wx, mp.y + PlatformModule.BOX_H - 1.3, mp.z), Vector3(1, 0, 0), mp.y + PlatformModule.BOX_H)
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
			var ind := Signs.indicator(gp, 2.9)
			var holder := Node3D.new()
			holder.position = Vector3(ix, (PlatformModule.SPRING_Y - 0.15) if not box else (PlatformModule.BOX_H - 1.4), pz)
			if box:
				_rods(holder, 1.1)
			holder.add_child(ind)
			var ind2 := Signs.indicator(gp, 2.9)
			ind2.rotation.y = PI
			ind2.position.z = -0.05
			holder.add_child(ind2)
			holder.rotation.y = -PI * 0.5           # face -x ... second copy faces +x
			pm.add_child(holder)
		# platform id + line board over the opening (blade, both directions)
		var brd_rows: Array = [{"text": "%s line" % Net.line_name(f2["line"]), "color": f2["color"], "bold": true},
			{"text": "Platform %d  %s" % [plan.platform_no[pid2], f2["label"]], "bold": true}]
		var dt := plan.dest_text(pid2, 3)
		if dt != "":
			brd_rows.append({"text": dt, "text_color": Color(0.85, 0.85, 0.85)})
		for ix2 in [-L * 0.5 + 34.0, L * 0.5 - 34.0]:
			var b := Signs.board(brd_rows, 4.0, 0.4)
			var b2 := b.duplicate()
			var holder2 := Node3D.new()
			holder2.position = Vector3(ix2, (PlatformModule.SPRING_Y + 0.25) if not box else (PlatformModule.BOX_H - 1.5), pz)
			if box:
				_rods(holder2, 1.2)
			b.rotation.y = -PI * 0.5
			b2.rotation.y = PI * 0.5
			b2.position.x = 0.03
			holder2.add_child(b)
			holder2.add_child(b2)
			pm.add_child(holder2)
		# way-out boards at each opening, facing along the platform, pointing toward the wall side (the opening)
		for o in (ox if not box else []):
			for view_dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
				var target := Vector3(0, 0, -s)      # the opening is toward the spine
				var a := _arrow_for(view_dir, target)
				var wb := Signs.board([{"text": "Way out", "bold": true, "arrow": a, "arrow_side": "left" if a == 2 else "right"}, {"text": "Other platform", "text_color": Color(0.8, 0.8, 0.8), "arrow": a, "arrow_side": "left" if a == 2 else "right"}], 3.0, 0.45)
				var hw := Node3D.new()
				hw.position = Vector3(o + (0.15 if view_dir.x > 0 else -0.15), PlatformModule.SPRING_Y - 0.05, s * (zwall + 0.9))
				wb.rotation.y = atan2(-view_dir.x, -view_dir.z)
				hw.add_child(wb)
				pm.add_child(hw)


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
