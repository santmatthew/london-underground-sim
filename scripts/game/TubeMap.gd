class_name TubeMap
extends Control
## Full-screen tube map overlay with two views of the real network (G or the button top right switches):
##   DIAGRAM (default)  the familiar schematic: lines at 0/45/90 degrees, parallel lines on shared track, ticks and interchange markers, the Thames.
##                      The layout is generated offline from the real network (tools/build_diagram.py -> data/tube_diagram.json).
##   GEOGRAPHIC         stations where they really are, with the Thames; pan/zoom, hover names.
## Both: drag to pan, wheel to zoom, hover for a station's name and zone; YOU ARE HERE / DESTINATION / STOP markers.

enum Mode { DIAGRAM, GEOGRAPHIC }

const THAMES := [[51.4613, -0.3037], [51.4740, -0.3010], [51.4870, -0.2900], [51.4830, -0.2650], [51.4870, -0.2350], [51.4800, -0.2200], [51.4667, -0.2150], [51.4640, -0.1900],
	[51.4790, -0.1780], [51.4830, -0.1560], [51.4880, -0.1320], [51.4980, -0.1230], [51.5060, -0.1215], [51.5090, -0.1150], [51.5110, -0.1040], [51.5085, -0.0880], [51.5060, -0.0740],
	[51.5040, -0.0530], [51.5020, -0.0330], [51.4980, -0.0170], [51.4920, -0.0090], [51.4830, -0.0100], [51.4850, 0.0050], [51.4960, 0.0150], [51.5040, 0.0300], [51.5030, 0.0500], [51.4960, 0.0700]]
const DIAGRAM_FILE := "res://data/tube_diagram.json"
const LABEL_DIRS := [Vector2(1, 0), Vector2(1, -1), Vector2(0, -1), Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]     # E NE N NW W SW S SE

var mode: int = Mode.DIAGRAM
var _zoom := [24.0, 34.0]                 # diagram: px per grid cell; geographic: px per km
var _center := [Vector2.ZERO, Vector2.ZERO]
var zoom: float:
	get: return _zoom[mode]
	set(v): _zoom[mode] = v
var center: Vector2:
	get: return _center[mode]
	set(v): _center[mode] = v
var here := -1
var dest := -1
var stops: Array = []            # extra targets (multi-stop)
var hover := -1
var poster_mode := false        # a printed wall map (TubeMapTexture): no hint line, button, hover or markers
var font: Font
var _dragging := false
var _drag_moved := 0.0
var _seg_lines: Dictionary = {}
var _thames: PackedVector2Array = PackedVector2Array()
# diagram data
var _dia_ok := false
var _dp: PackedVector2Array = PackedVector2Array()        # station idx -> cell position
var _ddir: PackedVector2Array = PackedVector2Array()      # station idx -> direction of the line through it (unit)
var _dlab: PackedInt32Array = PackedInt32Array()          # station idx -> label direction (0..7)
var _dedges: Array = []                                   # {a, b, lines:[lid], pts:PackedVector2Array}
var _dlinks: Array = []
var _dthames: PackedVector2Array = PackedVector2Array()
var _dbundle: PackedInt32Array = PackedInt32Array()       # station idx -> largest number of parallel lines on an incident edge
var _btn_rect := Rect2()


func _ready() -> void:
	font = load("res://assets/fonts/Barlow-SemiBold.ttf")
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for p in THAMES:
		_thames.append(_proj(p[0], p[1]))
	for lid in Net.line_ids:
		for svc in Net.lines[lid]["services"]:
			var st: PackedInt32Array = svc["stop_idx"]
			for i in st.size() - 1:
				var a: int = mini(st[i], st[i + 1])
				var b: int = maxi(st[i], st[i + 1])
				var key := "%d_%d" % [a, b]
				if not _seg_lines.has(key):
					_seg_lines[key] = [a, b, []]
				if not lid in _seg_lines[key][2]:
					_seg_lines[key][2].append(lid)
	_load_diagram()
	if not _dia_ok:
		mode = Mode.GEOGRAPHIC


func _load_diagram() -> void:
	if not FileAccess.file_exists(DIAGRAM_FILE):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIAGRAM_FILE))
	if not (d is Dictionary):
		return
	var n := Net.stations.size()
	_dp.resize(n)
	_ddir.resize(n)
	_dlab.resize(n)
	_dbundle.resize(n)
	for sid in d["stations"]:
		if not Net.id_to_idx.has(sid):
			continue
		var i: int = Net.id_to_idx[sid]
		var s: Dictionary = d["stations"][sid]
		_dp[i] = Vector2(s["p"][0], s["p"][1])
		_ddir[i] = Vector2(s["d"][0], s["d"][1])
		_dlab[i] = int(s["l"])
	for e in d["edges"]:
		if not (Net.id_to_idx.has(e["a"]) and Net.id_to_idx.has(e["b"])):
			continue
		var pts := PackedVector2Array()
		for q in e["pts"]:
			pts.append(Vector2(q[0], q[1]))
		var lines: Array = []
		for lid in Net.line_ids:                      # the fixed line order keeps a line on the same side of a bundle along its whole length
			if lid in e["lines"]:
				lines.append(lid)
		var ia: int = Net.id_to_idx[e["a"]]
		var ib: int = Net.id_to_idx[e["b"]]
		_dedges.append({"a": ia, "b": ib, "lines": lines, "pts": pts})
		_dbundle[ia] = maxi(_dbundle[ia], lines.size())
		_dbundle[ib] = maxi(_dbundle[ib], lines.size())
	for l in d.get("links", []):
		if Net.id_to_idx.has(l["a"]) and Net.id_to_idx.has(l["b"]):
			_dlinks.append([Net.id_to_idx[l["a"]], Net.id_to_idx[l["b"]]])
	for q in d.get("thames", []):
		_dthames.append(Vector2(q[0], q[1]))
	_dia_ok = _dp.size() > 0
	if _dia_ok:
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for p in _dp:
			lo = lo.min(p)
			hi = hi.max(p)
		_center[Mode.DIAGRAM] = (lo + hi) * 0.5


static func _proj(lat: float, lon: float) -> Vector2:
	return Vector2((lon + 0.1278) * 111.32 * cos(deg_to_rad(51.5074)), -(lat - 51.5074) * 110.57)


func _sp(idx: int) -> Vector2:
	if mode == Mode.DIAGRAM:
		return _dp[idx]
	var s: Dictionary = Net.stations[idx]
	return Vector2(s["x"], -s["y"])


func to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + (p - center) * zoom


func toggle_mode() -> void:
	if not _dia_ok:
		return
	mode = Mode.GEOGRAPHIC if mode == Mode.DIAGRAM else Mode.DIAGRAM
	queue_redraw()


func focus_on(idx: int) -> void:
	if _dia_ok:
		_center[Mode.DIAGRAM] = _dp[idx]
	var s: Dictionary = Net.stations[idx]
	_center[Mode.GEOGRAPHIC] = Vector2(s["x"], -s["y"])
	queue_redraw()


func _draw() -> void:
	if mode == Mode.DIAGRAM:
		_draw_diagram()
	else:
		_draw_geographic()
	_draw_common()


# ---------------------------------------------------------------------------------------------------------------------------------
# Diagram
# ---------------------------------------------------------------------------------------------------------------------------------
func _draw_diagram() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.965, 0.96, 0.945))
	var w := clampf(zoom * 0.34, 3.0, 12.0) * (1.9 if poster_mode else 1.0)     # line width in pixels (a printed wall map has bolder lines)
	var gap := w * 1.02                                  # centre-to-centre distance of parallel lines
	# river
	if _dthames.size() > 1:
		var rp := PackedVector2Array()
		for p in _dthames:
			rp.append(to_screen(p))
		draw_polyline(rp, Color(0.72, 0.86, 0.95), maxf(6.0, zoom * 1.5), true)
	# links between paired stations (Bank / Monument, the two Paddingtons, ...)
	for l in _dlinks:
		var pa := to_screen(_dp[l[0]])
		var pb := to_screen(_dp[l[1]])
		draw_line(pa, pb, Color(0.05, 0.05, 0.08), w * 0.95 + 2.0, true)
		draw_line(pa, pb, Color.WHITE, w * 0.95 - 1.0, true)
	# lines, one polyline per (edge, line) with the bundle centred on the edge
	for e in _dedges:
		var pts: PackedVector2Array = e["pts"]
		var scr := PackedVector2Array()
		for q in pts:
			scr.append(to_screen(q))
		var bb := Rect2(scr[0], Vector2.ZERO)
		for q in scr:
			bb = bb.expand(q)
		if not bb.grow(w * 4.0).intersects(Rect2(Vector2.ZERO, size)):
			continue
		var lines: Array = e["lines"]
		for i in lines.size():
			var off := (i - (lines.size() - 1) * 0.5) * gap
			var op := _offset_polyline(scr, off)
			draw_polyline(op, Net.line_color(lines[i]), w, true)
	# stations
	var show_all := zoom >= 20.0
	var labels: Array = []
	for s in Net.stations:
		var i: int = s["idx"]
		var p := to_screen(_dp[i])
		if p.x < -60 or p.y < -40 or p.x > size.x + 60 or p.y > size.y + 40:
			continue
		var nlines: int = (s["lines"] as Array).size()
		var d: Vector2 = _ddir[i] if _ddir[i] != Vector2.ZERO else Vector2.RIGHT
		var nrm := Vector2(-d.y, d.x)
		var bundle := maxi(_dbundle[i], 1)
		if nlines > 1 or bundle > 1:
			# interchange (or a station on a bundle): white capsule across the bundle with a dark outline
			var r0 := w * 0.72
			var half := maxf(0.0, (bundle - 1) * gap * 0.5)
			_capsule(p, nrm, half, r0 + 2.0, Color(0.05, 0.05, 0.08))
			_capsule(p, nrm, half, r0, Color.WHITE)
		else:
			var half2 := w * 0.75
			draw_line(p - nrm * half2, p + nrm * half2, Color(0.05, 0.05, 0.08), maxf(2.0, w * 0.3), true)
		var important: bool = i == here or i == dest or i in stops or i == hover
		if show_all or important or (nlines > 1 and zoom >= 12.0):
			var lb := _diagram_label(s, p, important, w)
			lb["prio"] = 10.0 if important else (2.0 + nlines * 0.2 if nlines > 1 else 1.0)
			labels.append(lb)
	# names, most important first; a name that would land on one already drawn is left out (zoom in to see it; hovering always names a station)
	labels.sort_custom(func(a, b): return a["prio"] > b["prio"])
	var taken: Array = []
	var panel := Rect2(14, 72, 190, 20.0 * Net.line_ids.size() + 30.0)
	for lb in labels:
		var r: Rect2 = lb["rect"]
		var ok: bool = lb["prio"] >= 10.0
		if not ok:
			ok = not r.intersects(panel)
			if ok:
				var rr := r.grow(2.0)
				for t in taken:
					if rr.intersects(t):
						ok = false
						break
		if not ok:
			continue
		taken.append(r)
		var halo := Color(0.965, 0.96, 0.945, 0.85)
		for o in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_string(font, lb["pos"] + o, lb["txt"], HORIZONTAL_ALIGNMENT_LEFT, -1, lb["fs"], halo)
		draw_string(font, lb["pos"], lb["txt"], HORIZONTAL_ALIGNMENT_LEFT, -1, lb["fs"], lb["col"])


func _capsule(p: Vector2, dir: Vector2, half: float, r: float, col: Color) -> void:
	var a := p - dir * half
	var b := p + dir * half
	draw_circle(a, r, col)
	draw_circle(b, r, col)
	if half > 0.01:
		var n := Vector2(-dir.y, dir.x) * r
		draw_colored_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), col)


## the polyline moved sideways by `off` (mitred at the bends)
func _offset_polyline(pts: PackedVector2Array, off: float) -> PackedVector2Array:
	if absf(off) < 0.01 or pts.size() < 2:
		return pts
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var n_prev := Vector2.ZERO
		var n_next := Vector2.ZERO
		if i > 0:
			var d0 := (pts[i] - pts[i - 1]).normalized()
			n_prev = Vector2(-d0.y, d0.x)
		if i < n - 1:
			var d1 := (pts[i + 1] - pts[i]).normalized()
			n_next = Vector2(-d1.y, d1.x)
		var nm: Vector2
		if i == 0:
			nm = n_next
		elif i == n - 1:
			nm = n_prev
		else:
			var sum := n_prev + n_next
			var k := 1.0 + n_prev.dot(n_next)
			nm = sum / maxf(k, 0.35)
		out.append(pts[i] + nm * off)
	return out


func _diagram_label(s: Dictionary, p: Vector2, important: bool, w: float) -> Dictionary:
	var i: int = s["idx"]
	var fs := int(clampf(zoom * 0.55, 10.0, 20.0) * (1.9 if poster_mode else 1.0))
	if important:
		fs += 2
	var txt: String = s["name"]
	var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var r := zoom * 0.62 + (w * 0.2) + maxf(0.0, (_dbundle[i] - 1) * w * 0.5)
	var d: int = _dlab[i]
	var ascent := font.get_ascent(fs)
	var top_left: Vector2
	match d:
		0: top_left = Vector2(p.x + r, p.y - sz.y * 0.5)
		4: top_left = Vector2(p.x - r - sz.x, p.y - sz.y * 0.5)
		2: top_left = Vector2(p.x - sz.x * 0.5, p.y - r - sz.y)
		6: top_left = Vector2(p.x - sz.x * 0.5, p.y + r)
		1: top_left = Vector2(p.x + r * 0.6, p.y - r * 0.6 - sz.y)
		3: top_left = Vector2(p.x - r * 0.6 - sz.x, p.y - r * 0.6 - sz.y)
		5: top_left = Vector2(p.x - r * 0.6 - sz.x, p.y + r * 0.6)
		_: top_left = Vector2(p.x + r * 0.6, p.y + r * 0.6)
	var col := Color(0.08, 0.09, 0.14) if not important else Color(0.75, 0.1, 0.1)
	return {"rect": Rect2(top_left, sz), "txt": txt, "pos": top_left + Vector2(0, ascent), "fs": fs, "col": col}


# ---------------------------------------------------------------------------------------------------------------------------------
# Geographic
# ---------------------------------------------------------------------------------------------------------------------------------
func _draw_geographic() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.075, 0.13, 0.94))
	# Thames
	if _thames.size() > 1:
		var pts := PackedVector2Array()
		for p in _thames:
			pts.append(to_screen(p))
		draw_polyline(pts, Color(0.16, 0.30, 0.52, 0.9), maxf(4.0, zoom * 0.16), true)
	# lines
	var w := clampf(zoom * 0.075, 2.0, 7.0)
	for key in _seg_lines:
		var e: Array = _seg_lines[key]
		var pa := to_screen(_sp(e[0]))
		var pb := to_screen(_sp(e[1]))
		if pa.x < -50 and pb.x < -50 or pa.x > size.x + 50 and pb.x > size.x + 50 or pa.y < -50 and pb.y < -50 or pa.y > size.y + 50 and pb.y > size.y + 50:
			continue
		var d := (pb - pa)
		var nrm := Vector2(-d.y, d.x).normalized()
		var lines: Array = e[2]
		for i in lines.size():
			var off := (i - (lines.size() - 1) * 0.5) * (w * 0.95)
			draw_line(pa + nrm * off, pb + nrm * off, Net.line_color(lines[i]), w, true)
	# stations
	var show_all := zoom > 60.0
	for s in Net.stations:
		var p := to_screen(_sp(s["idx"]))
		if p.x < -30 or p.y < -30 or p.x > size.x + 30 or p.y > size.y + 30:
			continue
		var inter: bool = s["lines"].size() > 1
		var r := (w * 1.0 + 2.0) if inter else (w * 0.55 + 1.0)
		draw_circle(p, r + 1.5, Color(0.03, 0.03, 0.04))
		draw_circle(p, r, Color.WHITE)
		var important: bool = s["idx"] == here or s["idx"] == dest or s["idx"] in stops or s["idx"] == hover
		if show_all or important or (inter and zoom > 30.0) or zoom > 110.0:
			var txt: String = s["name"]
			draw_string(font, p + Vector2(r + 4, 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13 if not important else 16, Color(1, 1, 0.9) if not important else Color(1, 0.9, 0.3))


# ---------------------------------------------------------------------------------------------------------------------------------
# Both
# ---------------------------------------------------------------------------------------------------------------------------------
func _draw_common() -> void:
	var light := mode == Mode.DIAGRAM
	var ink := Color(0.08, 0.09, 0.14) if light else Color.WHITE
	var ink2 := Color(0.08, 0.09, 0.14, 0.6) if light else Color(1, 1, 1, 0.6)
	if poster_mode:
		_draw_print_key(ink)
		return
	# markers
	if here >= 0:
		_marker(_sp(here), Color(0.05, 0.6, 0.25) if light else Color(0.2, 1.0, 0.4), "YOU ARE HERE")
	if dest >= 0:
		_marker(_sp(dest), Color(0.85, 0.15, 0.1) if light else Color(1.0, 0.35, 0.3), "DESTINATION")
	for st in stops:
		_marker(_sp(st), Color(0.9, 0.5, 0.0) if light else Color(1.0, 0.7, 0.2), "STOP")
	if light:
		draw_rect(Rect2(0, 0, 420, 68), Color(0.965, 0.96, 0.945))
	draw_string(font, Vector2(24, 34), "LONDON UNDERGROUND", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	var hint := "drag to pan · wheel to zoom · M to close"
	if _dia_ok:
		hint += " · G: " + ("geographic map" if mode == Mode.DIAGRAM else "diagram")
	draw_string(font, Vector2(24, 56), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink2)
	# legend
	var y := 90.0
	if light:
		draw_rect(Rect2(0, 0, 420, 68), Color(0.965, 0.96, 0.945))
		draw_rect(Rect2(14, 72, 190, 20.0 * Net.line_ids.size() + 30.0), Color(0.965, 0.96, 0.945))
		draw_rect(Rect2(14, 72, 190, 20.0 * Net.line_ids.size() + 30.0), Color(0.08, 0.09, 0.14, 0.25), false, 1.0)
	for lid in Net.line_ids:
		draw_rect(Rect2(24, y - 11, 22, 10), Net.line_color(lid))
		draw_string(font, Vector2(54, y - 2), Net.line_name(lid), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
		y += 20.0
	# view switch, top right: two halves, the active one lit
	if _dia_ok:
		_btn_rect = Rect2(size.x - 250, 18, 226, 34)
		draw_rect(_btn_rect, Color(0.08, 0.09, 0.14, 0.92) if light else Color(1, 1, 1, 0.12))
		var left := Rect2(_btn_rect.position + Vector2(4, 4), Vector2(84, 26))
		var right := Rect2(_btn_rect.position + Vector2(92, 4), Vector2(130, 26))
		draw_rect(left if mode == Mode.DIAGRAM else right, Color(1, 1, 1, 0.2))
		draw_string(font, left.position + Vector2(10, 19), "Diagram", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE if mode == Mode.DIAGRAM else Color(1, 1, 1, 0.5))
		draw_string(font, right.position + Vector2(10, 19), "Geographic (G)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE if mode == Mode.GEOGRAPHIC else Color(1, 1, 1, 0.5))
	if hover >= 0:
		var hs: Dictionary = Net.stations[hover]
		var txt2: String = "%s (zone %d)" % [hs["name"], hs["zone"]]
		var lp := get_local_mouse_position() + Vector2(14, 18)
		draw_rect(Rect2(lp - Vector2(6, 16), Vector2(font.get_string_size(txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 12, 24)), Color(0, 0, 0, 0.82))
		draw_string(font, lp, txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)


## the key of a printed wall map: title and line colours, bottom left
func _draw_print_key(ink: Color) -> void:
	var fs := maxf(14.0, size.y * 0.02)
	var row := fs * 1.45
	var x0 := size.x * 0.025
	var y0 := size.y - (Net.line_ids.size() * row + fs * 3.4) - size.y * 0.02
	draw_rect(Rect2(x0 - fs * 0.6, y0 - fs * 0.4, fs * 12.0, Net.line_ids.size() * row + fs * 3.2), Color(0.965, 0.96, 0.945))
	draw_string(font, Vector2(x0, y0 + fs * 1.1), "LONDON UNDERGROUND", HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 1.25), ink)
	var y := y0 + fs * 2.9
	for lid in Net.line_ids:
		draw_rect(Rect2(x0, y - fs * 0.72, fs * 1.8, fs * 0.5), Net.line_color(lid))
		draw_string(font, Vector2(x0 + fs * 2.3, y - fs * 0.15), Net.line_name(lid), HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), ink)
		y += row


func _marker(p0: Vector2, col: Color, label: String) -> void:
	var p := to_screen(p0)
	var t := fmod(Time.get_ticks_msec() / 1000.0, 1.2) / 1.2
	draw_arc(p, 10.0 + t * 16.0, 0.0, TAU, 32, Color(col.r, col.g, col.b, 1.0 - t), 3.0, true)
	draw_arc(p, 11.0, 0.0, TAU, 32, col, 3.0, true)
	draw_string(font, p + Vector2(16, -26), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


func _process(_d: float) -> void:
	if visible and (not poster_mode or Station.debug_on("tubemap_redraw")):
		queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo and (ev as InputEventKey).keycode == KEY_G:
		toggle_mode()
		accept_event()
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _dia_ok and _btn_rect.has_point(mb.position):
				toggle_mode()
				return
			_dragging = mb.pressed
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _dragging:
			center -= mm.relative / zoom
		# hover
		hover = -1
		var bd := 14.0
		for s in Net.stations:
			var d := to_screen(_sp(s["idx"])).distance_to(mm.position)
			if d < bd:
				bd = d
				hover = s["idx"]


func _zoom_at(p: Vector2, f: float) -> void:
	var before := (p - size * 0.5) / zoom + center
	var lo := 9.0 if mode == Mode.DIAGRAM else 12.0
	var hi := 70.0 if mode == Mode.DIAGRAM else 400.0
	zoom = clampf(zoom * f, lo, hi)
	var after := (p - size * 0.5) / zoom + center
	center += before - after
