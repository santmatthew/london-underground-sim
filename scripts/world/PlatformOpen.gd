class_name PlatformOpen
extends RefCounted
## Open-air (surface) platforms: no box roof but a canopy over the island, a low brick retaining wall with a palisade fence on the far side of each track, ballast, and
## the sky, trees and house backs beyond (a sky dome and two backdrop strips), lit by daylight lights that follow the simulated clock.
## Styles come from StationCharacter (data/station_character.json "open_styles"); reference photos are private (build/refs_dress/surface).

const WALL_TOP := 1.5                 # y of the top of the retaining wall across each track
const FENCE_H := 1.2
const CANOPY_HALF := 5.6              # canopy half-width (m): the island platform (4.9) plus a 0.7 m overhang
const CANOPY_T := 0.32                # slab thickness
const SKY_R := 300.0

static var _sky_shader: Shader
static var _noise: NoiseTexture2D
static var _backdrop_mats: Dictionary = {}


## 0 at night .. 1 in full day, from the simulated clock
static func daylight() -> float:
	var hh := fmod(Clock.now / 3600.0, 24.0)
	return clampf(sin((hh - 6.0) / 14.0 * PI) * 1.3, 0.0, 1.0)


## sun height -1..1 (negative at night)
static func sun() -> float:
	var hh := fmod(Clock.now / 3600.0, 24.0)
	var a := (hh - 6.0) / 14.0 * PI
	return sin(a) if (hh >= 6.0 and hh <= 20.0) else -0.5


# ---------------------------------------------------------------------------------------------------------------------------------------
# geometry written into the module's MeshKit
# ---------------------------------------------------------------------------------------------------------------------------------------

## Style keys (data/station_character.json "open_styles"; a station may have a style of its own, named after it, see "surface_overrides"):
##   canopy     "slab" (flat concrete) | "valanced" (white boards, shallow gable on top, scalloped valance) | "timber" | "gable" (pitched roof: rise, rafters, rooflights, valance) | "mushroom" (concrete umbrellas)
##   roof_h     height of the eaves / rim (default BOX_H);  spans: [[a, b], ...] fractions of the module length the roof covers (default all of it)
##   valance    "scallop" (default) | "saw" | "none";  rise (gable, m);  rooflights (gable: strips of glass in the slopes);  top / soffit / fascia: materials or colours
##   col        "square" | "round" | "iron" | "mushroom";  col_main / col_band / col_ring colours;  col_row: "edge" (two rows beside the platform walls, default) | "centre"
##   pitch      distance between columns (7.2) or between umbrella caps (12);  cap_r  umbrella radius (5.0)
##   front / wall / floor  platform front, track-side wall and platform deck materials (see StationCharacter)
##   bridge, planters, lamps ...  extras (PlatformExtras)

static func _spans(st: Dictionary, x0: float, x1: float) -> Array:
	var out: Array = []
	var sp: Array = st.get("spans", [])
	if sp.is_empty():
		out.append(Vector2(x0, x1))
	else:
		for a in sp:
			out.append(Vector2(lerpf(x0, x1, float(a[0])), lerpf(x0, x1, float(a[1]))))
	return out


static func roof_h(st: Dictionary) -> float:
	return float(st.get("roof_h", PlatformModule.BOX_H))


## the roof over the island: see the style keys above. Writes pm.roof_spans / pm.roof_info (what is overhead where) for the signs and fittings that hang from it
static func canopy(pm: PlatformModule, st: Dictionary, x0: float, x1: float, openings: Array) -> void:
	var kind := String(st.get("canopy", "slab"))
	var spans := _spans(st, x0, x1)
	pm.roof_info = {"kind": kind, "h": roof_h(st), "rise": float(st.get("rise", 0.0)) if kind == "gable" else 0.0, "zc": CANOPY_HALF, "caps": []}
	pm.column_extra = []
	# the way in from the cross-passages is under a flat roof of its own where the style's roofs do not reach back to the platform's west end (umbrellas, short shelters)
	var entry_end := x0
	if kind == "mushroom" or (st.has("spans") and (spans[0] as Vector2).x > x0 + 0.5):
		var last_open := x0
		for ox in openings:
			last_open = maxf(last_open, float(ox))
		entry_end = last_open + 3.4
		pm.roof_info["entry"] = Vector2(x0, entry_end)
	if kind == "mushroom":
		_mushrooms(pm, st, x0, x1, openings, entry_end)
	else:
		pm.roof_spans = spans
		for sp in spans:
			_roof(pm, st, kind, sp.x, sp.y)
		_columns(pm, st, spans, x0, x1, openings)
		for sp in spans:
			_strip_lights(pm, sp.x, sp.y, roof_h(st), kind == "gable")
	if entry_end > x0:
		_entry_roof(pm, st, x0, entry_end)
	if st.has("bridge"):
		_bridge(pm, st["bridge"], lerpf(x0, x1, float(st["bridge"].get("x", 0.7))))


## the flat roof over the way in (x0 .. x1): slab, two columns at each end clear of the cross-passages; part of the covered stretches (snap_x / soffit_y know it)
static func _entry_roof(pm: PlatformModule, st: Dictionary, x0: float, x1: float) -> void:
	_roof(pm, st, "slab", x0, x1)
	_strip_lights(pm, x0, x1, roof_h(st))
	var h := roof_h(st)
	var col_z := PlatformModule.GAP * 0.5 + 0.85
	var shaft := "flat:" + (st.get("col_main", Color(0.88, 0.88, 0.85)) as Color).to_html(false)
	for cx in [x0 + 3.5, x1 - 0.5]:
		for zz in [-col_z, col_z]:
			pm.kit.box(shaft, Vector3(cx, h * 0.5, zz), Vector3(0.42, h, 0.42), 0.0)
			pm.column_extra.append(Vector2(cx, zz))
	pm.roof_spans.append(Vector2(x0, x1))


static func _roof(pm: PlatformModule, st: Dictionary, kind: String, x0: float, x1: float) -> void:
	var kit := pm.kit
	var h := roof_h(st)
	var zc := CANOPY_HALF
	var soffit := String(st.get("soffit", "ceiling"))
	var fascia := "flat:" + (st.get("fascia", Color(0.85, 0.85, 0.82)) as Color).to_html(false)
	var top := String(st.get("top", "concrete"))
	var valance := String(st.get("valance", "scallop" if kind in ["valanced", "timber"] else "none"))
	if kind == "gable":
		_gable(pm, st, x0, x1, h)
	else:
		kit.horiz(soffit, x0, x1, -zc, zc, h, false, 0.0)
		# ribs under the soffit every 3.6 m (they also carry the strip lights)
		var bx := x0 + 1.8
		while bx < x1:
			kit.box(soffit if kind == "timber" else "ceiling", Vector3(bx, h - 0.09, 0.0), Vector3(0.18, 0.18, zc * 2.0), 0.0)
			bx += 3.6
	match kind:
		"valanced", "timber":
			# a shallow gable on top and a scalloped valance hanging from each long edge
			kit.horiz(top, x0, x1, -zc, zc, h + 0.05, true, 0.0)
			for sd: float in [1.0, -1.0]:
				kit.box(fascia, Vector3((x0 + x1) * 0.5, h + 0.02, sd * zc), Vector3(x1 - x0, 0.1, 0.06), 0.0)
		"gable":
			pass
		_:
			# a plain slab with a deep fascia all round
			kit.horiz(top, x0, x1, -zc, zc, h + CANOPY_T, true, 0.0)
			for sd: float in [1.0, -1.0]:
				kit.box(fascia, Vector3((x0 + x1) * 0.5, h + CANOPY_T * 0.5, sd * zc), Vector3(x1 - x0, CANOPY_T, 0.06), 0.0)
			for ex in [x0, x1]:
				kit.box(fascia, Vector3(ex, h + CANOPY_T * 0.5, 0.0), Vector3(0.06, CANOPY_T, zc * 2.0), 0.0)
	if valance != "none" and not Station.debug_off("valance"):
		for sd: float in [1.0, -1.0]:
			_valance(kit, sd * zc, x0, x1, h, sd, valance)


## a pitched roof over the island: ridge along the middle, two slopes with rafters, soffit and top, optional strips of rooflight glass
static func _gable(pm: PlatformModule, st: Dictionary, x0: float, x1: float, h: float) -> void:
	var kit := pm.kit
	var zc := CANOPY_HALF
	var rise := float(st.get("rise", 0.9))
	var soffit := String(st.get("soffit", "timber_slab"))
	var top := String(st.get("top", "concrete"))
	var glass := bool(st.get("rooflights", false))
	var thick := 0.14
	var slope := atan2(rise, zc)
	# the slopes are built as bands along x so rooflight strips can be left in them: [xa, xb, glazed?]
	var bands: Array = []
	var gx := x0
	while gx < x1 - 0.01:
		var seg := minf(2.4 if glass else 6.0, x1 - gx)
		bands.append([gx, gx + seg, glass and (int((gx - x0) / 2.4) % 3 == 1)])
		gx += seg
	for sd: float in [1.0, -1.0]:
		for b in bands:
			var xa: float = b[0]
			var xb: float = b[1]
			# the slope runs from the ridge (t = 0) to the eaves (t = 1); a glazed band covers the middle of it
			var pieces: Array = [[0.0, 1.0, false]]
			if b[2]:
				pieces = [[0.0, 0.30, false], [0.30, 0.74, true], [0.74, 1.0, false]]
			for pc in pieces:
				var ta: float = pc[0]
				var tb: float = pc[1]
				var za := sd * zc * ta
				var zb := sd * zc * tb
				var ya := h + rise * (1.0 - ta)
				var yb := h + rise * (1.0 - tb)
				var s_mat := "glass_roof" if pc[2] else soffit
				var t_mat := "glass_roof" if pc[2] else top
				# soffit faces down, top faces up (CCW from the front)
				var p0 := Vector3(xa, ya, za)
				var p1 := Vector3(xb, ya, za)
				var p2 := Vector3(xb, yb, zb)
				var p3 := Vector3(xa, yb, zb)
				if sd > 0.0:
					kit.quad(s_mat, p0, p1, p2, p3, 0.0)                        # normal: (p1-p0) x (p2-p0) = x cross (z,-y) -> down
					kit.quad(t_mat, p3 + Vector3(0, thick, 0), p2 + Vector3(0, thick, 0), p1 + Vector3(0, thick, 0), p0 + Vector3(0, thick, 0), 0.0)
				else:
					kit.quad(s_mat, p3, p2, p1, p0, 0.0)
					kit.quad(t_mat, p0 + Vector3(0, thick, 0), p1 + Vector3(0, thick, 0), p2 + Vector3(0, thick, 0), p3 + Vector3(0, thick, 0), 0.0)
	# rafters under each slope every 2.4 m, a ridge beam, and an eaves plate; the gable ends are closed by a board
	var bx := x0 + 1.2
	while bx < x1:
		for sd: float in [1.0, -1.0]:
			var mid := Vector3(bx, h + rise * 0.5 - 0.05, sd * zc * 0.5)
			var xf := Transform3D(Basis(Vector3.RIGHT, sd * slope), mid)
			kit.box_xf(soffit, xf, Vector3(0.1, 0.16, sqrt(zc * zc + rise * rise)), 0.0)
		bx += 2.4
	kit.box(soffit, Vector3((x0 + x1) * 0.5, h + rise - 0.06, 0.0), Vector3(x1 - x0, 0.16, 0.2), 0.0)
	for sd: float in [1.0, -1.0]:
		kit.box("flat:" + (st.get("fascia", Color(0.85, 0.85, 0.82)) as Color).to_html(false), Vector3((x0 + x1) * 0.5, h + 0.08, sd * zc), Vector3(x1 - x0, 0.2, 0.06), 0.0)
	# the end gables: a triangle of boarding at each end (seen from outside and from under the roof)
	var fc := "flat:" + (st.get("fascia", Color(0.85, 0.85, 0.82)) as Color).to_html(false)
	for ex in [x0, x1]:
		var a := Vector3(ex, h, -zc)
		var b := Vector3(ex, h + rise, 0.0)
		var c := Vector3(ex, h, zc)
		var m := Vector3(ex, h, 0.0)
		kit.quad(fc, a, b, c, m, 0.0)
		kit.quad(fc, m, c, b, a, 0.0)


## a valance hung from the long edge at z (sd = +1 / -1): the texture says which kind ("scallop" 2.0 x 0.31 m, "saw" 2.0 x 0.39 m)
static func _valance(kit: MeshKit, z: float, x0: float, x1: float, h: float, s: float, kindv := "scallop") -> void:
	var vh := 0.31 if kindv == "scallop" else 0.39
	var key := "char:open/%s.png|2.000|%.3f|1" % ["valance" if kindv == "scallop" else "valance_saw", vh]
	var zf := z + s * 0.035
	if s > 0.0:
		kit.wall(key, Vector3(x0, 0, zf), Vector3(x1, 0, zf), h - vh + 0.05, h + 0.05, 0.0)
		kit.wall(key, Vector3(x1, 0, zf - 0.004), Vector3(x0, 0, zf - 0.004), h - vh + 0.05, h + 0.05, 0.0)
	else:
		kit.wall(key, Vector3(x1, 0, zf), Vector3(x0, 0, zf), h - vh + 0.05, h + 0.05, 0.0)
		kit.wall(key, Vector3(x0, 0, zf + 0.004), Vector3(x1, 0, zf + 0.004), h - vh + 0.05, h + 0.05, 0.0)


## the columns stand where the box hall's steel columns did (same collision boxes, every `pitch` m, clear of the cross-passages); roofs with spans get a column near each end of every span
static func _columns(pm: PlatformModule, st: Dictionary, spans: Array, x0: float, x1: float, openings: Array) -> void:
	var kit := pm.kit
	var h := roof_h(st)
	var col_z := PlatformModule.GAP * 0.5 + 0.85
	var shaft := "flat:" + (st.get("col_main", Color(0.88, 0.88, 0.85)) as Color).to_html(false)
	var band := "flat:" + (st.get("col_band", Color(0.10, 0.20, 0.50)) as Color).to_html(false)
	var ring: String = "flat:" + (st["col_ring"] as Color).to_html(false) if st.has("col_ring") else ""
	var kind := String(st.get("col", "square"))
	var pitch := float(st.get("pitch", 7.2))
	pm.column_xs = []
	pm.column_zs = [-col_z, col_z]
	var xs: Array = []
	if not st.has("spans"):
		var cx := x0 + 5.0
		while cx < x1 - 3.0:
			xs.append(cx)
			cx += pitch
	else:
		for sp in spans:
			var a: float = (sp as Vector2).x + 1.2
			var b: float = (sp as Vector2).y - 1.2
			var n := maxi(1, int(ceil((b - a) / pitch)))
			for k in n + 1:
				xs.append(lerpf(a, b, float(k) / n))
	for cx in xs:
		var at_opening := false
		for ox in openings:
			if absf(cx - ox) < 2.6:
				at_opening = true
		if at_opening:
			continue
		pm.column_xs.append(cx)
		for zz in pm.column_zs:
			match kind:
				"round":
					# octagonal shaft with a flared capital that spreads into the slab
					kit.box(shaft, Vector3(cx, h * 0.5, zz), Vector3(0.40, h, 0.40), 0.0)
					kit.box_xf(shaft, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(cx, h * 0.5, zz)), Vector3(0.40, h, 0.40), 0.0)
					for k in 4:
						var f := 1.0 + k * 0.9
						kit.box(shaft, Vector3(cx, h - 0.14 - k * 0.1, zz), Vector3(0.4 * f, 0.1, 0.4 * f), 0.0)
					kit.box(band, Vector3(cx, 0.5, zz), Vector3(0.44, 0.9, 0.44), 0.0)
				"iron":
					# slim cast-iron post on a plinth, with a collar and a bracket cap (and, where the style has them, painted rings)
					kit.box(shaft, Vector3(cx, h * 0.5, zz), Vector3(0.24, h, 0.24), 0.0)
					kit.box(band, Vector3(cx, 0.45, zz), Vector3(0.34, 0.9, 0.34), 0.0)
					kit.box(shaft, Vector3(cx, 1.0, zz), Vector3(0.30, 0.08, 0.30), 0.0)
					kit.box(shaft, Vector3(cx, h - 0.2, zz), Vector3(0.40, 0.14, 0.40), 0.0)
					if ring != "":
						for ry in [1.12, 1.26]:
							kit.box(ring, Vector3(cx, ry, zz), Vector3(0.27, 0.05, 0.27), 0.0)
				_:
					# a square concrete column, painted: a dark band at the foot, a thin one at head height
					kit.box(shaft, Vector3(cx, h * 0.5, zz), Vector3(0.42, h, 0.42), 0.0)
					kit.box(band, Vector3(cx, 0.5, zz), Vector3(0.44, 1.0, 0.44), 0.0)
					kit.box(band, Vector3(cx, h - 2.45, zz), Vector3(0.435, 0.16, 0.435), 0.0)


# -- umbrella roofs (Loughton): a round column flaring into a broad dished cap with a thick rounded rim, one every `pitch` m along the middle of the island --------------------------

static func _cap_profile(h: float, r: float) -> PackedVector2Array:
	var k := r / 5.0
	var p := PackedVector2Array()
	# the top, from the crown outward, over the thick rolled rim, then the underside back in to the column (a gentle flare, as in the photographs), then down the shaft
	for q in [[0.0, 0.50], [1.5, 0.49], [3.0, 0.45], [4.2, 0.40], [4.8, 0.36]]:
		p.append(Vector2(q[0] * k, h + q[1]))
	for q in [[5.0, 0.28], [5.04, 0.14], [4.98, 0.02], [4.84, -0.08]]:
		p.append(Vector2(q[0] * k, h + q[1]))
	for q in [[4.2, -0.12], [3.2, -0.20], [2.2, -0.36], [1.5, -0.52], [1.05, -0.72], [0.75, -0.95], [0.52, -1.25]]:
		p.append(Vector2(q[0] * k, h + q[1]))
	p.append(Vector2(0.48, 0.0))
	return p


static func _mushrooms(pm: PlatformModule, st: Dictionary, x0: float, x1: float, openings: Array, entry_end: float) -> void:
	var kit := pm.kit
	var h := roof_h(st)
	var r := float(st.get("cap_r", 5.0))
	var pitch := float(st.get("pitch", 12.0))
	var mat := "matt:" + (st.get("col_main", Color(0.9, 0.89, 0.84)) as Color).to_html(false)
	pm.column_xs = []
	pm.column_zs = [0.0]
	pm.column_w = 0.92
	pm.roof_spans = []
	var caps: Array = []
	var cx := entry_end + r + 1.0
	while cx < x1 - r + 1.0:
		caps.append(cx)
		cx += pitch
	var prof := _cap_profile(h, r)
	for c in caps:
		kit.lathe(mat, prof, c, 0.0, 1.0, 1.0, 32, 0.0)
		pm.column_xs.append(c)
		pm.roof_spans.append(Vector2(c - r * 0.55, c + r * 0.55))
		# four downlights in the dish
		for k in 4:
			var a := TAU * (k + 0.5) / 4.0
			kit.box("light_emissive", Vector3(c + cos(a) * 2.3, h - 0.30, sin(a) * 2.3), Vector3(0.5, 0.05, 0.28), 0.0)
	pm.roof_info["caps"] = caps
	pm.roof_info["cap_r"] = r
	pm.roof_info["cap_profile"] = prof


# -- a footbridge over the tracks (Kew Gardens): white-painted concrete, a shallow arch with a deep girder along each side carrying a row of blind panels ------------------------------

static func _bridge(pm: PlatformModule, b: Dictionary, bx: float) -> void:
	var kit := pm.kit
	var zspan := float(b.get("half_span", 13.0))
	var y0 := float(b.get("clear", 5.6))                # underside of the deck at the abutments
	var rise := float(b.get("rise", 1.1))
	var depth := float(b.get("depth", 2.4))             # girder depth
	var gap := float(b.get("width", 2.7))               # clear width between the girders
	var gt := 0.34                                      # girder thickness
	var key := "char:open/bridge_panel.png|2.000|%.3f|0" % depth
	var paint := "matt:e4e4de"
	var n := 28
	var xs := [bx - gap * 0.5 - gt, bx - gap * 0.5, bx + gap * 0.5, bx + gap * 0.5 + gt]
	var yb := func(z: float) -> float:
		var u := clampf(z / zspan, -1.0, 1.0)
		return y0 + rise * (1.0 - u * u)
	for i in n:
		var za := -zspan + 2.0 * zspan * float(i) / n
		var zb := -zspan + 2.0 * zspan * float(i + 1) / n
		var ya0: float = yb.call(za)
		var yb0: float = yb.call(zb)
		# the four faces of each girder: the outer face (towards +/- x, panelled), the inner face, the top and the underside; then the deck
		for side: float in [-1.0, 1.0]:
			var xo: float = bx + side * (gap * 0.5 + gt)
			var xi: float = bx + side * gap * 0.5
			var uvz := Vector2(za, 0.0)
			# outer face: normal along `side` (x); corners a1 (top, za), a0 (bottom, za), b0, b1 (the wall() order: front is the right of travel)
			var a1 := Vector3(xo, ya0 + depth, za)
			var a0 := Vector3(xo, ya0, za)
			var b0 := Vector3(xo, yb0, zb)
			var b1 := Vector3(xo, yb0 + depth, zb)
			if side > 0.0:
				kit.quad(key, b1, b0, a0, a1, 0.0, Vector2(-zb, 0.0), 0.0, true)
			else:
				kit.quad(key, a1, a0, b0, b1, 0.0, uvz, 0.0, true)
			var c1 := Vector3(xi, ya0 + depth, za)
			var c0 := Vector3(xi, ya0, za)
			var d0 := Vector3(xi, yb0, zb)
			var d1 := Vector3(xi, yb0 + depth, zb)
			if side > 0.0:
				kit.quad(paint, c1, c0, d0, d1, 0.0, Vector2.ZERO, 0.0, true)
			else:
				kit.quad(paint, d1, d0, c0, c1, 0.0, Vector2.ZERO, 0.0, true)
			# top of the girder (faces up) and its underside (faces down)
			kit.quad(paint, Vector3(xo, ya0 + depth, za), Vector3(xo, yb0 + depth, zb), Vector3(xi, yb0 + depth, zb), Vector3(xi, ya0 + depth, za), 0.0) if side > 0.0 else kit.quad(paint, Vector3(xi, ya0 + depth, za), Vector3(xi, yb0 + depth, zb), Vector3(xo, yb0 + depth, zb), Vector3(xo, ya0 + depth, za), 0.0)
		# the deck: its top (walkway) and underside between the girders
		kit.quad("matt:8d8e8e", Vector3(xs[1], ya0 + 0.45, za), Vector3(xs[1], yb0 + 0.45, zb), Vector3(xs[2], yb0 + 0.45, zb), Vector3(xs[2], ya0 + 0.45, za), 0.0)
		kit.quad(paint, Vector3(xs[1], ya0, za), Vector3(xs[2], ya0, za), Vector3(xs[2], yb0, zb), Vector3(xs[1], yb0, zb), 0.0)
	# abutments: a concrete pier under each end, reaching down to the ground beyond the retaining wall
	for sd: float in [-1.0, 1.0]:
		var pz := sd * (zspan + 0.9)
		kit.box(paint, Vector3(bx, (y0 + PlatformModule.BED_Y) * 0.5, pz), Vector3(gap + 2.0 * gt + 0.5, y0 - PlatformModule.BED_Y + depth * 0.6, 1.8), 0.0)


# -- what is overhead (signs and fittings that hang from the roof ask) ---------------------------------------------------------------------

## y of the underside of the roof at (x, z) in the module frame, NAN where there is none
static func soffit_y(pm: PlatformModule, x: float, z: float) -> float:
	var info: Dictionary = pm.roof_info
	if info.is_empty():
		return NAN
	var covered := false
	for sp in pm.roof_spans:
		if x >= (sp as Vector2).x and x <= (sp as Vector2).y:
			covered = true
	if not covered:
		return NAN
	var h: float = info["h"]
	if info.has("entry") and x <= (info["entry"] as Vector2).y:
		return h
	match String(info["kind"]):
		"gable":
			return h + float(info["rise"]) * (1.0 - clampf(absf(z) / float(info["zc"]), 0.0, 1.0))
		"mushroom":
			var best := NAN
			var r: float = info["cap_r"]
			for c in info["caps"]:
				var d := Vector2(x - float(c), z).length()
				if d <= r:
					# the underside: profile points from the rim in to the column
					var prof: PackedVector2Array = info["cap_profile"]
					var y := NAN
					for i in range(prof.size() - 1):
						var a := prof[i]
						var b := prof[i + 1]
						if a.y <= h + 0.1 and a.x >= d and b.x <= d and a.x > b.x:
							y = lerpf(a.y, b.y, (a.x - d) / maxf(a.x - b.x, 0.001))
							break
					best = y
			return best
		_:
			return h


## x moved sideways, if need be, to where a board `half_w` wide hung there has roof over it (the full-length roofs return x itself)
static func snap_x(pm: PlatformModule, x: float, half_w: float) -> float:
	if pm.roof_spans.is_empty():
		return x
	var best := x
	var best_d := 1e9
	for sp in pm.roof_spans:
		var a: float = (sp as Vector2).x + half_w
		var b: float = (sp as Vector2).y - half_w
		if b < a:
			a = ((sp as Vector2).x + (sp as Vector2).y) * 0.5
			b = a
		var c := clampf(x, a, b)
		if absf(c - x) < best_d:
			best_d = absf(c - x)
			best = c
	return best


static func covered(pm: PlatformModule, x: float) -> bool:
	if pm.roof_spans.is_empty():
		return true
	for sp in pm.roof_spans:
		if x >= (sp as Vector2).x and x <= (sp as Vector2).y:
			return true
	return false


static func _strip_lights(pm: PlatformModule, x0: float, x1: float, h: float, pendant := false) -> void:
	var kit := pm.kit
	var lx := x0 + 3.0
	while lx < x1:
		for zz in [-3.2, 3.2, 0.0]:
			kit.box("light_emissive", Vector3(lx, h - 0.2, zz), Vector3(1.3, 0.06, 0.3), 0.0)
		lx += 3.2


## the far side of each track: brick retaining wall from the trackbed to WALL_TOP with a coping stone and a palisade fence above it
static func track_wall(pm: PlatformModule, st: Dictionary, s: float, x0: float, x1: float, zfar: float, wall_mat: String) -> void:
	if Station.debug_off("openwall"):
		return
	var kit := pm.kit
	var a := Vector3(x0 - 0.5, 0, s * zfar)
	var b := Vector3(x1 + 0.5, 0, s * zfar)
	if s > 0.0:
		kit.wall(wall_mat, b, a, PlatformModule.BED_Y, WALL_TOP, 0.0)
	else:
		kit.wall(wall_mat, a, b, PlatformModule.BED_Y, WALL_TOP, 0.0)
	# coping stone, a little proud, and its top
	kit.box("white_paint", Vector3((x0 + x1) * 0.5, WALL_TOP + 0.05, s * (zfar + 0.02)), Vector3(x1 - x0 + 1.0, 0.1, 0.36), 0.0)
	# the fence (a quad each way so it reads from both sides)
	var key := "char:open/fence.png|1.000|1.200|1"
	var zf := s * (zfar + 0.02)
	var y0 := WALL_TOP + 0.1
	var y1 := y0 + FENCE_H
	if s > 0.0:
		kit.wall(key, Vector3(x1 + 0.5, 0, zf), Vector3(x0 - 0.5, 0, zf), y0, y1, 0.0)
		kit.wall(key, Vector3(x0 - 0.5, 0, zf + 0.01), Vector3(x1 + 0.5, 0, zf + 0.01), y0, y1, 0.0)
	else:
		kit.wall(key, Vector3(x0 - 0.5, 0, zf), Vector3(x1 + 0.5, 0, zf), y0, y1, 0.0)
		kit.wall(key, Vector3(x1 + 0.5, 0, zf - 0.01), Vector3(x0 - 0.5, 0, zf - 0.01), y0, y1, 0.0)


# ---------------------------------------------------------------------------------------------------------------------------------------
# the sky, the backdrop and the daylight (child nodes of the module)
# ---------------------------------------------------------------------------------------------------------------------------------------

static func scenery(pm: PlatformModule, st: Dictionary, x0: float, x1: float, zfar: float) -> void:
	if Station.debug_off("scenery"):
		return
	var holder := Node3D.new()
	holder.name = "Outdoors"
	pm.add_child(holder)
	var day := daylight()
	# --- the sky dome
	add_dome(holder, (x0 + x1) * 0.5, day)
	# --- backdrop strips: a belt of trees close behind the fence and the backs of a terrace beyond it, on both sides
	var tint := lerpf(0.10, 1.0, day)
	var warm := Color(tint, tint * lerpf(0.9, 1.0, day), tint * lerpf(1.0, 0.96, day))
	var length := (x1 - x0) + 2.0        # no further: the end walls hide the rest, and a longer strip would cut through the rooms beyond them
	var cx := (x0 + x1) * 0.5
	var nb: Array = pm.spec.get("nb", [])
	if OS.has_environment("UG_CHAR_DEBUG"):
		print("OPEN ", pm.name, " pos ", pm.position, " nb ", nb, " zfar ", zfar)
	for s in [1.0, -1.0]:
		if s in nb:
			continue         # another platform lies that way: the view across is its canopy, not a backdrop
		_backdrop(holder, "trees", Vector3(cx, PlatformModule.BED_Y + 0.0, s * (zfar + 11.0)), s, length, 12.0, 40.0, warm, pm.bend)
		_backdrop(holder, "houses", Vector3(cx, PlatformModule.BED_Y + 0.0, s * (zfar + 30.0)), s, length, 14.0, 56.0, warm.darkened(0.12), pm.bend)
	# --- daylight: soft omni lights high above the island (none at night; the canopy lights take over)
	if day > 0.04:
		var lx := x0 + 6.0
		while lx < x1:
			var o := OmniLight3D.new()
			o.position = Vector3(lx, 9.0, 0.0)
			o.light_energy = 2.4 * day
			o.omni_range = 24.0
			o.omni_attenuation = 1.1
			o.light_color = Color(1.0, lerpf(0.86, 0.97, day), lerpf(0.72, 0.92, day))
			o.shadow_enabled = false
			o.distance_fade_enabled = true
			o.distance_fade_begin = 50.0
			o.distance_fade_length = 15.0
			holder.add_child(o)
			lx += 13.0


## the sky over a stretch of open track: a dome centred at x = cx
static func add_dome(holder: Node3D, cx: float, day: float) -> void:
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = SKY_R
	sm.height = SKY_R * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	dome.mesh = sm
	dome.material_override = _sky_material(day, sun())
	dome.position = Vector3(cx, 0.0, 0.0)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(dome)


static func _backdrop(holder: Node3D, tex: String, at: Vector3, s: float, length: float, height: float, tile_w: float, tint: Color, bend: Bend = null) -> void:
	var mi := MeshInstance3D.new()
	if bend != null:
		# a curved platform: the strip follows the curve, a chain of quads one metre-ish wide in a mesh of its own (in module space)
		var n := maxi(1, int(ceil(length / 5.0)))
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var idx := PackedInt32Array()
		for i in n + 1:
			var x := at.x - length * 0.5 + length * float(i) / float(n)
			verts.append(bend.map(Vector3(x, at.y + height, at.z)))
			verts.append(bend.map(Vector3(x, at.y, at.z)))
			var u := float(i) / float(n)
			uvs.append(Vector2(u, 0.0))
			uvs.append(Vector2(u, 1.0))
			if i > 0:
				var b := (i - 1) * 2
				idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mi.mesh = am
		mi.set_meta("bent", true)
	else:
		var q := QuadMesh.new()
		q.size = Vector2(length, height)
		mi.mesh = q
		mi.position = at + Vector3(0, height * 0.5, 0)
		mi.rotation.y = atan2(0.0, -s)           # the quad's front (+z) faces the island
	var key := "%s|%.2f|%.1f" % [tex, tint.r, length]
	var m: StandardMaterial3D = _backdrop_mats.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		var t: Texture2D = load("res://assets/textures/char/open/%s.png" % tex) if ResourceLoader.exists("res://assets/textures/char/open/%s.png" % tex) else null
		m.albedo_texture = t
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.albedo_color = tint
		m.uv1_scale = Vector3(length / tile_w, 1.0, 1.0)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_backdrop_mats[key] = m
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)


static func _sky_material(day: float, sn: float) -> ShaderMaterial:
	if _sky_shader == null:
		_sky_shader = load("res://shaders/sky_dome.gdshader")
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.02
		fn.fractal_octaves = 4
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.noise = fn
	var m := ShaderMaterial.new()
	m.shader = _sky_shader
	# colour sets: night, dusk/dawn, day; dusk weight peaks when the sun is low
	var night_top := Color(0.012, 0.018, 0.05)
	var night_hor := Color(0.06, 0.08, 0.14)
	var day_top := Color(0.28, 0.50, 0.84)
	var day_hor := Color(0.80, 0.88, 0.95)
	var dusk_top := Color(0.20, 0.26, 0.52)
	var dusk_hor := Color(0.96, 0.62, 0.42)
	var t := clampf(sn * 1.6, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(sn) * 3.5, 0.0, 1.0) * (1.0 if sn > -0.3 else 0.0)
	var top := night_top.lerp(day_top, t).lerp(dusk_top, dusk * 0.7)
	var hor := night_hor.lerp(day_hor, t).lerp(dusk_hor, dusk * 0.8)
	m.set_shader_parameter("top_color", top)
	m.set_shader_parameter("horizon_color", hor)
	m.set_shader_parameter("ground_color", hor.darkened(0.45))
	m.set_shader_parameter("cloud_color", Color(0.96, 0.96, 0.97).lerp(Color(0.12, 0.13, 0.18), 1.0 - t).lerp(Color(1.0, 0.82, 0.7), dusk * 0.5))
	m.set_shader_parameter("cloud_amount", 0.55)
	m.set_shader_parameter("star_amount", clampf(0.55 - sn * 3.0, 0.0, 1.0))
	m.set_shader_parameter("noise_tex", _noise)
	return m
