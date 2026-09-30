class_name Signs
extends RefCounted
## Procedural London-Underground-style signage (built from meshes + Label3D so it works for any station name).
## Styles: black wayfinding boards (white text, yellow arrows), roundel name plates, platform line/direction boards,
## dot-matrix next-train indicators.

const FONT_PATH := "res://assets/fonts/HammersmithOne-Regular.ttf"
const FONT_BOLD := "res://assets/fonts/Barlow-Bold.ttf"
const FONT_DOT := "res://assets/fonts/Doto.ttf"
const YELLOW := Color(1.0, 0.82, 0.05)
const BLUE := Color(0.0, 0.10, 0.55)
const RED := Color(0.87, 0.10, 0.10)

static var _font: Font
static var _font_b: Font
static var _font_dot: Font
static var _cache: Dictionary = {}


static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH)
	return _font


static func font_bold() -> Font:
	if _font_b == null:
		_font_b = load(FONT_BOLD)
	return _font_b


static func font_dot() -> Font:
	if _font_dot == null:
		_font_dot = load(FONT_DOT)
	return _font_dot


static func _mat(color: Color, emission := 0.0, rough := 0.5, unshaded := false) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f_%s" % [color.to_html(), emission, rough, unshaded]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cache[key] = m
	return m


static func label(text: String, size_m: float, color := Color.WHITE, bold := false, align := HORIZONTAL_ALIGNMENT_LEFT, emissive := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font_bold() if bold else font()
	l.font_size = 64
	l.pixel_size = size_m / 64.0
	l.modulate = color
	l.outline_size = 0
	l.horizontal_alignment = align
	l.shaded = false
	l.double_sided = false
	l.no_depth_test = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	return l


static func _quad(size: Vector2, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = mat
	return mi


## Yellow arrow pointing in `dir`: 0 = right, 1 = up, 2 = left, 3 = down, 4 = down-right... (as a flat mesh, 0.28 m)
static func arrow(dir: int, size := 0.30, color := YELLOW) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# arrow pointing +x in the XY plane, facing +z
	var pts := [
		Vector2(-0.5, -0.12), Vector2(0.12, -0.12), Vector2(0.12, -0.36), Vector2(0.5, 0.0), Vector2(0.12, 0.36), Vector2(0.12, 0.12), Vector2(-0.5, 0.12),
	]
	# tri fan by hand
	var tris := [[0, 1, 5], [0, 5, 6], [2, 3, 4], [2, 4, 1], [1, 4, 5]]
	# ensure CCW facing +z (Godot front = clockwise: emit reversed)
	for t in tris:
		for k in [0, 2, 1]:
			var p: Vector2 = pts[t[k]]
			st.set_normal(Vector3(0, 0, 1))
			st.add_vertex(Vector3(p.x * size, p.y * size, 0))
	mi.mesh = st.commit()
	mi.material_override = _mat(color, 1.5, 0.5, true)
	mi.rotation.z = deg_to_rad(90.0 * dir) if dir < 4 else deg_to_rad(-45.0)
	root.add_child(mi)
	return root


const NAVY := Color(0.05, 0.13, 0.55)
const INK := Color(0.04, 0.04, 0.05)


static func _lum_text(col: Color) -> Color:
	return INK if col.get_luminance() > 0.5 else Color.WHITE


## Real Underground wayfinding: a white enamel panel with black text, a thin LINE-COLOURED RULE above each row and black arrows.
## A row whose text starts with "Way out" is drawn as the black box with yellow text.
## rows: [{text, color (line rule), arrow (0 right,1 up,2 left,3 down), arrow_side "left"/"right", bold, text_color}]
static func board(rows: Array, width := 2.4, row_h := 0.34, _bg := Color.WHITE, max_w := 0.0) -> Node3D:
	var root := Node3D.new()
	var gap := 0.03
	# widen the panel for long text so nothing is clipped
	var longest := 0
	for r in rows:
		var txt_len: int = String(r.get("text", "")).length()
		if r.has("color") or r.has("arrow"):
			txt_len += 4
		longest = maxi(longest, txt_len)
	width = maxf(width, longest * row_h * 0.43 + 0.5)
	var h := 0.0
	for r in rows:
		h += row_h + (0.05 if r.has("color") else 0.0)
	h += 0.12
	var frame := _quad(Vector2(width + 0.06, h + 0.06), _mat(Color(0.22, 0.23, 0.25), 0.0, 0.35))
	frame.position = Vector3(0, 0, 0.004)
	root.add_child(frame)
	var panel := _quad(Vector2(width, h), _mat(Color(0.94, 0.945, 0.95), 0.25, 0.28))
	panel.position = Vector3(0, 0, 0.010)
	root.add_child(panel)
	var y := h * 0.5 - 0.06
	for r in rows:
		var rule_h := 0.05 if r.has("color") else 0.0
		var top := y
		if rule_h > 0.0:
			var rule := _quad(Vector2(width - 0.1, 0.03), _mat(r["color"], 0.4, 0.4, true))
			rule.position = Vector3(0, top - 0.02, 0.014)
			root.add_child(rule)
			top -= rule_h
		var yc := top - row_h * 0.5
		var txt: String = r.get("text", "")
		var arrow_dir: int = r.get("arrow", -1)
		var arrow_left: bool = r.get("arrow_side", "left") == "left"
		if txt.begins_with("Way out"):
			# black box with yellow text
			var bw := minf(width - 0.12, 0.95 + 0.0)
			var bx := -width * 0.5 + 0.08 + bw * 0.5
			var box := _quad(Vector2(bw, row_h * 0.86), _mat(Color(0.02, 0.02, 0.02), 0.0, 0.4))
			box.position = Vector3(bx, yc, 0.016)
			root.add_child(box)
			var lt := label(txt, row_h * 0.52, YELLOW, true, HORIZONTAL_ALIGNMENT_LEFT)
			lt.position = Vector3(bx - bw * 0.5 + 0.07, yc - row_h * 0.02, 0.022)
			root.add_child(lt)
			if arrow_dir >= 0:
				var ay := arrow(arrow_dir, row_h * 0.6, YELLOW)
				ay.position = Vector3(bx + bw * 0.5 - row_h * 0.38, yc, 0.024)
				root.add_child(ay)
		else:
			var x := -width * 0.5 + 0.1
			var tc: Color = r.get("text_color", INK)
			if tc.get_luminance() > 0.6:
				tc = Color(0.26, 0.27, 0.30)
			if arrow_dir >= 0 and arrow_left:
				var a := arrow(arrow_dir, row_h * 0.58, INK)
				a.position = Vector3(x + row_h * 0.3, yc, 0.02)
				root.add_child(a)
				x += row_h * 0.75
			var lt2 := label(txt, row_h * 0.66, tc, r.get("bold", false), HORIZONTAL_ALIGNMENT_LEFT)
			lt2.position = Vector3(x, yc - row_h * 0.02, 0.02)
			root.add_child(lt2)
			if arrow_dir >= 0 and not arrow_left:
				var a2 := arrow(arrow_dir, row_h * 0.58, INK)
				a2.position = Vector3(width * 0.5 - row_h * 0.45, yc, 0.02)
				root.add_child(a2)
		y = top - row_h - gap * 0.0
	# `size` = outer size in metres after any scaling; `max_w` shrinks the whole board (text included) instead of letting long text
	# push it wider than the space it hangs in
	var k := 1.0
	if max_w > 0.0 and width + 0.06 > max_w:
		k = max_w / (width + 0.06)
		root.scale = Vector3(k, k, k)
	root.set_meta("sign", true)
	root.set_meta("size", Vector2(width + 0.06, h + 0.06) * k)
	return root


## Long white enamel fascia with the station name in Underground blue and a blue stripe along the top edge. Faces +z.
static func fascia(station_name: String, length: float, wayout_x: Array = [], wayout_arrow := 0, show_name := true) -> Node3D:
	var root := Node3D.new()
	var h := 0.46
	var panel := _quad(Vector2(length, h), _mat(Color(0.95, 0.955, 0.96), 0.2, 0.25))
	panel.position = Vector3(0, 0, 0.006)
	root.add_child(panel)
	var stripe := _quad(Vector2(length, 0.06), _mat(NAVY, 0.0, 0.3))
	stripe.position = Vector3(0, h * 0.5 - 0.03, 0.008)
	root.add_child(stripe)
	var nm := station_name.to_upper()
	var x := -length * 0.5 + 6.0
	var flip := false
	while x < length * 0.5 - 4.0:
		if show_name:
			var l := label(nm, 0.24, NAVY, true, HORIZONTAL_ALIGNMENT_CENTER)
			l.position = Vector3(x, -0.03, 0.012)
			root.add_child(l)
		var wo := Node3D.new()
		var b := board([{"text": "Way out", "arrow": wayout_arrow}], 1.0, 0.24)
		wo.add_child(b)
		wo.position = Vector3(x + 5.5, -0.02, 0.016)
		if wayout_x.size() > 0:
			root.add_child(wo)
		x += 11.0
		flip = not flip
	return root


## Tile-mosaic station name in a framed panel (seen on many platform walls): ":NAME:" in bold serif on cream with black border
static func tile_name(station_name: String, height := 0.85) -> Node3D:
	var root := Node3D.new()
	var nm := station_name.to_upper()
	var w := maxf(2.4, nm.length() * height * 0.36 + 0.5)
	var frame := _quad(Vector2(w + 0.16, height + 0.16), _mat(Color(0.03, 0.03, 0.03), 0.0, 0.25))
	frame.position = Vector3(0, 0, 0.006)
	root.add_child(frame)
	var panel := _quad(Vector2(w, height), _mat(Color(0.90, 0.88, 0.76), 0.0, 0.3))
	panel.position = Vector3(0, 0, 0.009)
	root.add_child(panel)
	var l := label(":" + nm + ":", height * 0.62, Color(0.10, 0.04, 0.05), true, HORIZONTAL_ALIGNMENT_CENTER)
	l.font = font_serif()
	l.position = Vector3(0, -height * 0.03, 0.012)
	root.add_child(l)
	return root


static var _font_serif: Font


static func font_serif() -> Font:
	if _font_serif == null:
		var path := "res://assets/fonts/LibreBaskerville-Bold.ttf"
		_font_serif = load(path) if ResourceLoader.exists(path) else font_bold()
	return _font_serif


## Roundel name plate for platform walls: white plate, thick red ring, name bar (blue for modern, black for older). Faces +z.
static func roundel(station_name: String, scale_m := 1.0, black_bar := false) -> Node3D:
	var root := Node3D.new()
	var bar_w := maxf(1.7, 0.10 * station_name.length() + 0.55) * scale_m
	var bar_h := 0.32 * scale_m
	var ring_r := 0.46 * scale_m
	var back := _quad(Vector2(bar_w + 0.32 * scale_m, ring_r * 2.0 + 0.22 * scale_m), _mat(Color(0.95, 0.95, 0.95), 0.2, 0.28))
	back.position = Vector3(0, 0, 0.004)
	root.add_child(back)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = ring_r * 0.60
	tm.outer_radius = ring_r
	tm.rings = 48
	tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = _mat(RED, 0.0, 0.3)
	ring.rotation.x = deg_to_rad(90.0)
	ring.scale = Vector3(1, 0.06, 1)
	ring.position = Vector3(0, 0, 0.02)
	root.add_child(ring)
	var bar := _quad(Vector2(bar_w, bar_h), _mat(Color(0.02, 0.02, 0.03) if black_bar else BLUE, 0.0, 0.3))
	bar.position = Vector3(0, 0, 0.045)
	root.add_child(bar)
	var l := label(station_name.to_upper(), bar_h * 0.62, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	l.position = Vector3(0, -bar_h * 0.03, 0.05)
	root.add_child(l)
	return root


## Platform line + direction board (hangs from the ceiling or mounts on walls): coloured line bullet + "Northbound" + destinations
static func platform_board(line_id: String, line_color: Color, direction: String, dests: String, platform_no: int) -> Node3D:
	var rows: Array = [
		{"text": "%s line" % Net.line_name(line_id), "color": line_color, "bold": true},
		{"text": "Platform %d  %s" % [platform_no, direction], "bold": false},
	]
	if dests != "":
		rows.append({"text": dests, "text_color": Color(0.85, 0.85, 0.85)})
	return board(rows, 3.0)


## Dot-matrix indicator: 3 lines "1 Epping            3 min"
class Indicator:
	extends Node3D
	var labels: Array = []
	var platform_gp := -1
	var _accum := 0.0

	func setup(gp: int, width := 2.2) -> void:
		platform_gp = gp
		# everything scales with the width (the text is laid out for 2.9 m)
		var f := width / 2.9
		set_meta("sign", true)
		set_meta("size", Vector2(width + 0.06 * f, 0.68 * f))
		var panel := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(width, 0.62 * f)
		panel.mesh = q
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.01, 0.01, 0.012)
		m.roughness = 0.3
		panel.material_override = m
		panel.position.z = 0.01
		add_child(panel)
		var back := MeshInstance3D.new()
		var q2 := QuadMesh.new()
		q2.size = Vector2(width + 0.06 * f, 0.68 * f)
		back.mesh = q2
		var m2 := StandardMaterial3D.new()
		m2.albedo_color = Color(0.4, 0.4, 0.42)
		m2.roughness = 0.4
		back.material_override = m2
		back.position.z = 0.003
		add_child(back)
		for i in 3:
			var l := Label3D.new()
			l.font = Signs.font_dot()
			l.font_size = 64
			l.pixel_size = 0.150 / 64.0 * f
			l.modulate = Color(1.0, 0.62, 0.06)
			l.shaded = false
			l.double_sided = false
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			l.position = Vector3(-width * 0.5 + 0.08 * f, (0.19 - i * 0.19) * f, 0.02)
			add_child(l)
			labels.append(l)
		refresh()

	func _process(delta: float) -> void:
		_accum += delta
		if _accum >= 1.0:
			_accum = 0.0
			refresh()

	func refresh() -> void:
		var now: float = Clock.now
		var deps: Array = Timetable.next_departures(platform_gp, now - 5.0, 3)
		for i in 3:
			var l: Label3D = labels[i]
			if i < deps.size():
				var d: Dictionary = deps[i]
				var name: String = Net.station_name(d["dest"])
				name = name.replace(" (Circle)", "").replace(" (H&C)", "").replace(" (D&P)", "")
				if name.length() > 17:
					name = name.substr(0, 16) + "."
				var mins := int(round((d["dep"] - now) / 60.0))
				var due: String = "due" if (d["arr"] - now) < 20.0 and (d["arr"] - now) > -1.0 else ("" if d["dep"] < now else ("%d min" % maxi(mins, 0)))
				if d["arr"] <= now and d["dep"] > now:
					due = "at plat"
				l.text = "%d %-17s %6s" % [i + 1, name, due]
			else:
				l.text = ""


static func indicator(gp: int, width := 2.9) -> Node3D:
	var ind := Indicator.new()
	ind.setup(gp, width)
	return ind
