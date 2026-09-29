class_name TubeMap
extends Control
## Full-screen tube map overlay: geographic layout of the real network with the Thames, pan/zoom, hover names.

const THAMES := [[51.4613, -0.3037], [51.4740, -0.3010], [51.4870, -0.2900], [51.4830, -0.2650], [51.4870, -0.2350], [51.4800, -0.2200], [51.4667, -0.2150], [51.4640, -0.1900],
	[51.4790, -0.1780], [51.4830, -0.1560], [51.4880, -0.1320], [51.4980, -0.1230], [51.5060, -0.1215], [51.5090, -0.1150], [51.5110, -0.1040], [51.5085, -0.0880], [51.5060, -0.0740],
	[51.5040, -0.0530], [51.5020, -0.0330], [51.4980, -0.0170], [51.4920, -0.0090], [51.4830, -0.0100], [51.4850, 0.0050], [51.4960, 0.0150], [51.5040, 0.0300], [51.5030, 0.0500], [51.4960, 0.0700]]

var zoom := 34.0                 # px per km
var center := Vector2.ZERO       # km
var here := -1
var dest := -1
var stops: Array = []            # extra targets (multi-stop)
var hover := -1
var font: Font
var _dragging := false
var _seg_lines: Dictionary = {}
var _thames: PackedVector2Array = PackedVector2Array()


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


static func _proj(lat: float, lon: float) -> Vector2:
	return Vector2((lon + 0.1278) * 111.32 * cos(deg_to_rad(51.5074)), -(lat - 51.5074) * 110.57)


func _sp(idx: int) -> Vector2:
	var s: Dictionary = Net.stations[idx]
	return Vector2(s["x"], -s["y"])


func to_screen(km: Vector2) -> Vector2:
	return size * 0.5 + (km - center) * zoom


func focus_on(idx: int) -> void:
	center = _sp(idx)
	queue_redraw()


func _draw() -> void:
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
	# markers
	if here >= 0:
		_marker(_sp(here), Color(0.2, 1.0, 0.4), "YOU ARE HERE")
	if dest >= 0:
		_marker(_sp(dest), Color(1.0, 0.35, 0.3), "DESTINATION")
	for st in stops:
		_marker(_sp(st), Color(1.0, 0.7, 0.2), "STOP")
	draw_string(font, Vector2(24, 34), "LONDON UNDERGROUND", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(24, 56), "drag to pan · wheel to zoom · M to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))
	# legend
	var y := 90.0
	for lid in Net.line_ids:
		draw_rect(Rect2(24, y - 11, 22, 10), Net.line_color(lid))
		draw_string(font, Vector2(54, y - 2), Net.line_name(lid), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		y += 20.0
	if hover >= 0:
		var hs: Dictionary = Net.stations[hover]
		var txt2: String = "%s (zone %d)" % [hs["name"], hs["zone"]]
		var lp := get_local_mouse_position() + Vector2(14, 18)
		draw_rect(Rect2(lp - Vector2(6, 16), Vector2(font.get_string_size(txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 12, 24)), Color(0, 0, 0, 0.8))
		draw_string(font, lp, txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)


func _marker(km: Vector2, col: Color, label: String) -> void:
	var p := to_screen(km)
	var t := fmod(Time.get_ticks_msec() / 1000.0, 1.2) / 1.2
	draw_arc(p, 10.0 + t * 16.0, 0.0, TAU, 32, Color(col.r, col.g, col.b, 1.0 - t), 3.0, true)
	draw_arc(p, 11.0, 0.0, TAU, 32, col, 3.0, true)
	draw_string(font, p + Vector2(16, -14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


func _process(_d: float) -> void:
	if visible:
		queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
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
	zoom = clampf(zoom * f, 12.0, 400.0)
	var after := (p - size * 0.5) / zoom + center
	center += before - after
