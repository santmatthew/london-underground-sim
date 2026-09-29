class_name PlatformModule
extends Node3D
## Deep-tube "twin tunnel" platform module.
## Local frame: x along the track, z across, y = 0 at platform surface (rail head is at y = -0.9).
##
##        z = +8.0  ┌────────────── track-side wall (face A) ───────────────┐
##                  │  track A (z=+6.25)          platform A (z 1.7..4.7)   │
##        z = +1.7  ├──── platform-side wall (openings into the spine) ─────┤
##                  │  SPINE passage  (z -1.7..+1.7, flat ceiling 2.6 m)    │
##        z = -1.7  ├────────────────────────────────────────────────────────┤
##                  │  platform B (z -4.7..-1.7)      track B (z=-6.25)     │
##        z = -8.0  └────────────────────────────────────────────────────────┘
## Face A serves `faces[0]`, face B `faces[1]` (either may be absent for a single-face module).

const BED_Y := -1.15
const RAIL_Y := -0.90
const SPRING_Y := 2.3
const RISE := 1.9
const GAP := 3.4            # spine width
const TRACK_TO_EDGE := 1.55
const TRACK_TO_WALL := 1.75
const SPINE_H := 2.6
const OPEN_W := 3.0
const OPEN_H := 2.15
const TUNNEL_EXT := 170.0    # running tunnel visible beyond the platform ends (must exceed a full train length)
const BOX_H := 4.7          # ceiling height of "box" halls (sub-surface / surface stations)
const HEAD := 2.15          # lowest underside allowed for anything hanging over a walkway
const PW_RUN := 3.2          # platform width AND running-tunnel clearance: constant so every tunnel joins invisibly

var spec: Dictionary = {}
var meta: Dictionary = {}
var box := false
var kit := MeshKit.new()
var _cols: Array = []        # [center, size]  (collision boxes in local space)
var _lights: Array = []      # [pos, energy, range]
var edge_shapes: Dictionary = {}    # face sign (1.0 / -1.0) -> Array of [x_center, CollisionShape3D]


static func half_width(pw: float) -> float:
	return GAP * 0.5 + pw + TRACK_TO_EDGE + TRACK_TO_WALL


## spec: length, pw, wall ("tile_white"/"tile_cream"), faces:[{line,color,label}], openings_x:[...], spine_x0, spine_x1, name
func build(p_spec: Dictionary) -> void:
	spec = p_spec
	box = spec.get("style", "arch") == "box"
	var L: float = spec.get("length", 110.0)
	var pw: float = spec.get("pw", 3.0)
	var wall_mat: String = spec.get("wall", "tile_cream")
	var faces: Array = spec.get("faces", [{}, {}])
	var openings: Array = spec.get("openings_x", [-L * 0.5 + 9.0, -L * 0.5 + 23.0])
	var spine_x0: float = spec.get("spine_x0", -L * 0.5 - 6.0)
	var spine_x1: float = spec.get("spine_x1", -L * 0.5 + 27.0)
	kit.seed_rng(int(spec.get("seed", 1)))
	meta = {"faces": [], "openings": openings, "spine_x0": spine_x0, "spine_x1": spine_x1, "length": L, "pw": pw, "style": spec.get("style", "arch")}

	var zwall := GAP * 0.5                      # platform-side wall (abs z)
	var zedge := zwall + pw                     # platform edge
	var ztrack := zedge + TRACK_TO_EDGE
	var zfar := ztrack + TRACK_TO_WALL          # track-side wall
	var x0 := -L * 0.5
	var x1 := L * 0.5

	for fi in 2:
		if fi >= faces.size() or faces[fi] == null:
			continue
		var s := 1.0 if fi == 0 else -1.0       # +z tunnel is face A
		var f: Dictionary = faces[fi]
		var band: Color = f.get("color", Color(0.9, 0.1, 0.1))
		_build_tunnel(s, x0, x1, zwall, zedge, ztrack, zfar, wall_mat, band, openings)
		meta["faces"].append({
			"index": fi, "side": s, "track_z": s * ztrack, "edge_z": s * zedge, "wall_z": s * zwall,
			"x0": x0, "x1": x1, "rail_y": RAIL_Y, "label": f.get("label", ""), "line": f.get("line", ""),
		})
	if box:
		_build_box_hall(x0, x1, zwall, zedge, ztrack, zfar, wall_mat, openings)
	else:
		_build_spine(x0, x1, spine_x0, spine_x1, zwall, wall_mat, openings)

	var mats := {}
	for n in ["tile_white", "tile_cream", "panel_white", "tactile", "floor_platform", "floor_hall", "ceiling", "concrete", "trackbed", "track_sleepers", "metal", "rail", "yellow_paint", "black", "light_emissive", "glass_roof"]:
		mats[n] = Mats.get_mat(n)
	for k in kit.surfaces.keys():
		if k.begins_with("flat:"):
			mats[k] = Mats.flat(Color.html(k.substr(5)), 0.4)
		elif k.begins_with("dado:"):
			mats[k] = Mats.dado(Color.html(k.substr(5)))
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build(mats)
	mi.name = "Shell"
	add_child(mi)
	_add_collision()
	_add_lights()
	meta["tri_count"] = kit.triangle_count()


# ---------------------------------------------------------------------------------------------------
func _build_tunnel(s: float, x0: float, x1: float, zwall: float, zedge: float, ztrack: float, zfar: float, wall_mat: String, band: Color, openings: Array) -> void:
	# --- arch + track-side wall profile (z, y), ordered so the visible side faces into the tunnel ---
	# running tunnels beyond the platform always have the SAME cross-section relative to the track (PW_RUN), so the
	# tunnel-run scenery used while riding joins every station invisibly
	var zwall_run := zfar - (TRACK_TO_WALL + TRACK_TO_EDGE + PW_RUN)
	var prof := _arch_profile(s, zwall, zfar)
	var prof_run := _arch_profile(s, zwall_run, zfar)
	var xa := x0 - TUNNEL_EXT
	var xb := x1 + TUNNEL_EXT
	if not box:
		kit.sweep_x(wall_mat, prof, x0, x1, 0.0)
	kit.sweep_x(wall_mat, prof_run, xa, x0, 0.0)
	kit.sweep_x(wall_mat, prof_run, x1, xb, 0.0)
	# platform-side wall, tunnel face. Full height under the platform (running tunnel) and above it at the platform.
	# In the running tunnel (no platform) the wall goes down to the trackbed.
	_wall_z(wall_mat, s * zwall_run, xa, x0, BED_Y, SPRING_Y, [], s < 0.0, true)
	_wall_z(wall_mat, s * zwall_run, x1, xb, BED_Y, SPRING_Y, [], s < 0.0, true)
	var holes := []
	for ox in openings:
		holes.append([ox - OPEN_W * 0.5, ox + OPEN_W * 0.5, OPEN_H])
	if not box:
		_wall_z(wall_mat, s * zwall, x0, x1, 0.0, SPRING_Y, holes, s < 0.0, true)

	# --- platform deck (y = 0) and edge ---
	var zlo := minf(s * zwall, s * zedge)
	var zhi := maxf(s * zwall, s * zedge)
	kit.horiz("floor_platform", x0, x1, zlo, zhi, 0.0, true, 0.0)
	# tactile strip along the edge (0.6 m)
	var tz0 := minf(s * (zedge - 0.6), s * zedge)
	var tz1 := maxf(s * (zedge - 0.6), s * zedge)
	kit.horiz("tactile", x0, x1, tz0, tz1, 0.004, true, 0.0)
	# yellow safety line 5 cm wide inboard of the tactile strip
	var lz0 := minf(s * (zedge - 0.10), s * (zedge - 0.0))
	var lz1 := maxf(s * (zedge - 0.10), s * (zedge - 0.0))
	kit.horiz("yellow_paint", x0, x1, lz0, lz1, 0.005, true, 0.0)
	# platform front face toward the track (from y=0 down to bed)
	if s > 0.0:
		kit.wall("concrete", Vector3(x1, 0, s * zedge), Vector3(x0, 0, s * zedge), BED_Y, 0.0, BED_Y, false)
	else:
		kit.wall("concrete", Vector3(x0, 0, s * zedge), Vector3(x1, 0, s * zedge), BED_Y, 0.0, BED_Y, false)
	# platform underside cap at the ends
	# --- track bed ---
	var bz0 := minf(s * zedge, s * zfar)
	var bz1 := maxf(s * zedge, s * zfar)
	kit.horiz("trackbed", xa, xb, bz0, bz1, BED_Y, true, BED_Y)
	# in the running tunnel the bed spans the whole tunnel width (there's no platform)
	var rz0 := minf(s * zwall_run, s * zedge)
	var rz1 := maxf(s * zwall_run, s * zedge)
	kit.horiz("trackbed", xa, x0, rz0, rz1, BED_Y, true, BED_Y)
	kit.horiz("trackbed", x1, xb, rz0, rz1, BED_Y, true, BED_Y)
	# end-of-view black walls
	_end_cap(s, xa, zwall_run, zfar, true)
	_end_cap(s, xb, zwall_run, zfar, false)

	# --- rails ---
	for dz in [-0.7175, 0.7175]:
		kit.box("rail", Vector3((xa + xb) * 0.5, RAIL_Y - 0.08, s * ztrack + dz), Vector3(xb - xa, 0.16, 0.07), BED_Y)
	kit.box("rail", Vector3((xa + xb) * 0.5, RAIL_Y - 0.07, s * ztrack + s * 0.0), Vector3(xb - xa, 0.10, 0.06), BED_Y)          # centre (negative) rail
	kit.box("rail", Vector3((xa + xb) * 0.5, RAIL_Y - 0.07, s * ztrack - s * 1.05), Vector3(xb - xa, 0.10, 0.06), BED_Y)         # outer (positive) rail
	# sleepers: a textured strip under the rails (2.6 m wide)
	kit.horiz("track_sleepers", xa, xb, s * ztrack - 1.3, s * ztrack + 1.3, BED_Y + 0.004, true, BED_Y)
	if box:
		_box_track_wall(s, x0, x1, zfar, wall_mat)
	# --- wall stripes / dado (station style) on the track-side wall and the platform wall ---
	var stripes: Array = spec.get("stripes", [{"y0": 1.15, "y1": 1.42, "color": band}])
	for st in stripes:
		var col: Color = st["color"]
		var key: String = ("dado:" if st.get("dado", false) else "flat:") + col.to_html(false)
		var y0: float = st["y0"]
		_band(key, s * zfar, xa + 20.0, xb - 20.0, y0, st["y1"], s < 0.0, true)
		if not box:
			_band(key, s * zwall, x0, x1, y0, st["y1"], s < 0.0, false, holes)
	# cable tray on the track-side wall
	kit.box("metal", Vector3((x0 + x1) * 0.5, 0.75, s * (zfar - 0.15)), Vector3(x1 - x0, 0.08, 0.3), 0.0)
	kit.box("metal", Vector3((x0 + x1) * 0.5, 0.35, s * (zfar - 0.15)), Vector3(x1 - x0, 0.08, 0.3), 0.0)

	# --- collision ---
	var pcenter := Vector3((x0 + x1) * 0.5, -0.5, s * (zwall + zedge) * 0.5)
	_cols.append([pcenter, Vector3(x1 - x0, 1.0, zedge - zwall)])                        # platform slab (top at y=0)
	# platform edge guard: invisible wall 0.55 m inboard of the yellow line so the player can't drop onto the track
	var ex := x0 + 0.5
	while ex < x1:
		_cols.append([Vector3(ex, 0.9, s * (zedge + 0.15)), Vector3(1.0, 1.8, 0.3), "edge", s])
		ex += 1.0
	# track-side wall & tunnel floor (only matter near platform)
	_cols.append([Vector3((x0 + x1) * 0.5, 2.5, s * (zfar + 0.5)), Vector3(x1 - x0 + 4.0, 6.0, 1.0)])
	# platform-side wall segments between openings (full-height box) — keeps player inside the spine/platform
	if not box:
		var segs := _segments(x0, x1, openings, OPEN_W)
		for sg in segs:
			_cols.append([Vector3((sg[0] + sg[1]) * 0.5, 1.5, s * zwall), Vector3(sg[1] - sg[0], 3.0, 0.3)])
	# platform ends
	_cols.append([Vector3(x0 - 0.5, 0.9, s * (zwall + zedge) * 0.5), Vector3(1.0, 1.8, zedge - zwall), "edge"])
	_cols.append([Vector3(x1 + 0.5, 0.9, s * (zwall + zedge) * 0.5), Vector3(1.0, 1.8, zedge - zwall), "edge"])
	# tunnel light fixtures at the crown
	var zc := s * (zwall + zfar) * 0.5
	var apex := SPRING_Y + RISE
	if not box:
		var lx := x0 + 2.0
		while lx < x1:
			kit.box("light_emissive", Vector3(lx, apex - 0.06, zc), Vector3(1.4, 0.06, 0.28), 0.0)
			lx += 3.0
		var lx2 := x0 + 6.0
		while lx2 < x1:
			_lights.append([Vector3(lx2, apex - 0.7, zc), 1.6, 11.0])
			lx2 += 7.0
	# reveal frames around the cross-passage openings (dark trim)
	if not box:
		for ox in openings:
			_frame(s * zwall, ox, OPEN_W, OPEN_H)


func _box_track_wall(s: float, x0: float, x1: float, zfar: float, wall_mat: String) -> void:
	# vertical wall on the track side up to the flat ceiling (visible from the hall)
	if s > 0.0:
		kit.wall(wall_mat, Vector3(x1, 0, zfar), Vector3(x0, 0, zfar), BED_Y, BOX_H, 0.0)
	else:
		kit.wall(wall_mat, Vector3(x0, 0, -zfar), Vector3(x1, 0, -zfar), BED_Y, BOX_H, 0.0)


func _build_box_hall(x0: float, x1: float, zwall: float, zedge: float, ztrack: float, zfar: float, wall_mat: String, openings: Array) -> void:
	var surface: bool = spec.get("roof", "flat") == "glass"
	# island median floor between the two platforms
	kit.horiz("floor_platform", x0, x1, -zwall, zwall, 0.0, true, 0.0)
	_cols.append([Vector3((x0 + x1) * 0.5, -0.5, 0.0), Vector3(x1 - x0, 1.0, GAP)])
	# ceiling
	if surface:
		kit.horiz("glass_roof", x0, x1, -zfar, zfar, BOX_H, false, 0.0)
		var rx := x0 + 3.0
		while rx < x1:
			kit.box("black", Vector3(rx, BOX_H - 0.12, 0.0), Vector3(0.22, 0.24, zfar * 2.0), 0.0)
			rx += 4.0
		for zz in [-zfar * 0.5, 0.0, zfar * 0.5]:
			kit.box("black", Vector3((x0 + x1) * 0.5, BOX_H - 0.1, zz), Vector3(x1 - x0, 0.2, 0.2), 0.0)
	else:
		kit.horiz("ceiling", x0, x1, -zfar, zfar, BOX_H, false, 0.0)
		# steel beams across the ceiling
		var bx := x0 + 2.0
		while bx < x1:
			kit.box("metal", Vector3(bx, BOX_H - 0.22, 0.0), Vector3(0.3, 0.44, zfar * 2.0), 0.0)
			bx += 6.4
	# light fixtures
	var lx := x0 + 3.0
	while lx < x1:
		for zz in [-3.2, 3.2, 0.0]:
			if not surface or zz == 0.0:
				kit.box("light_emissive", Vector3(lx, BOX_H - 0.32 if not surface else BOX_H - 0.3, zz), Vector3(1.3, 0.06, 0.3), 0.0)
		lx += 3.2
	var lx2 := x0 + 4.0
	while lx2 < x1:
		_lights.append([Vector3(lx2, BOX_H - 0.9, 3.2), 2.2 if not surface else 1.3, 13.0])
		_lights.append([Vector3(lx2, BOX_H - 0.9, -3.2), 2.2 if not surface else 1.3, 13.0])
		lx2 += 8.0
	# steel columns down the two platforms: on the wall side, well clear of the walking lane (edge - 1.0) and of the wall openings
	var cx := x0 + 5.0
	var col_z := zwall + 0.85
	while cx < x1 - 3.0:
		var at_opening := false
		for ox in openings:
			if absf(cx - ox) < 2.6:
				at_opening = true
		if not at_opening:
			for zz in [-col_z, col_z]:
				kit.box("metal", Vector3(cx, BOX_H * 0.5, zz), Vector3(0.42, BOX_H, 0.42), 0.0)
				_cols.append([Vector3(cx, BOX_H * 0.5, zz), Vector3(0.44, BOX_H, 0.44)])
		cx += 7.2
	# end walls: track portals on both sides, plus a doorway at the west end leading to the corridor
	_box_end_wall(x0, true, zwall, ztrack, zfar, wall_mat, true)
	_box_end_wall(x1, false, zwall, ztrack, zfar, wall_mat, false)


func _box_end_wall(x: float, west: bool, zwall: float, ztrack: float, zfar: float, wall_mat: String, doorway: bool) -> void:
	# openings (z_lo, z_hi, y_lo, y_hi)
	var ops: Array = [[-ztrack - 1.9, -ztrack + 1.65, BED_Y, 3.4], [ztrack - 1.65, ztrack + 1.9, BED_Y, 3.4]]
	if doorway:
		ops.append([-zwall, zwall, 0.0, SPINE_H])
	ops.sort_custom(func(a, b): return a[0] < b[0])
	var z := -zfar
	for o in ops:
		_end_strip(x, west, wall_mat, z, o[0], BED_Y, BOX_H)
		# under / above the opening
		if o[2] > BED_Y:
			_end_strip(x, west, wall_mat, o[0], o[1], BED_Y, o[2])
		_end_strip(x, west, wall_mat, o[0], o[1], o[3], BOX_H)
		z = o[1]
	_end_strip(x, west, wall_mat, z, zfar, BED_Y, BOX_H)
	# solid collision segments between the openings (west end has a walk-through doorway)
	var cz := -zfar
	for o in ops:
		if o[0] - cz > 0.05:
			_cols.append([Vector3(x + (-0.15 if west else 0.15), BOX_H * 0.5, (cz + o[0]) * 0.5), Vector3(0.3, BOX_H, o[0] - cz)])
		cz = o[1]
	if zfar - cz > 0.05:
		_cols.append([Vector3(x + (-0.15 if west else 0.15), BOX_H * 0.5, (cz + zfar) * 0.5), Vector3(0.3, BOX_H, zfar - cz)])


func _end_strip(x: float, west: bool, mat: String, z0: float, z1: float, y0: float, y1: float) -> void:
	if z1 - z0 < 0.01 or y1 - y0 < 0.01:
		return
	if west:
		kit.wall(mat, Vector3(x, 0, z1), Vector3(x, 0, z0), y0, y1, 0.0)      # normal +x
	else:
		kit.wall(mat, Vector3(x, 0, z0), Vector3(x, 0, z1), y0, y1, 0.0)      # normal -x


func _arch_profile(s: float, zwall: float, zfar: float) -> PackedVector2Array:
	# from the top of the platform-side wall, over the arch, down the track-side wall to the trackbed (ordered for +z traversal when s>0)
	var za := zwall
	var zb := zfar
	var pts := PackedVector2Array()
	var chord := zb - za
	var r := (chord * chord / 4.0 + RISE * RISE) / (2.0 * RISE)
	var zc := (za + zb) * 0.5
	var yc := SPRING_Y + RISE - r
	var a0 := atan2(SPRING_Y - yc, za - zc)   # angle at left spring
	var a1 := atan2(SPRING_Y - yc, zb - zc)
	# ensure we traverse over the top (a from a0 ~ (pi - x) down to a1 ~ x)
	var steps := 16
	pts.append(Vector2(za, SPRING_Y))
	for i in range(1, steps):
		var a := lerpf(a0, a1, float(i) / steps)
		pts.append(Vector2(zc + r * cos(a), yc + r * sin(a)))
	pts.append(Vector2(zb, SPRING_Y))
	pts.append(Vector2(zb, BED_Y))
	if s < 0.0:
		# mirrored tunnel: build with mirrored z, still ordered +z, so reverse and negate
		var m := PackedVector2Array()
		for i in range(pts.size() - 1, -1, -1):
			m.append(Vector2(-pts[i].x, pts[i].y))
		return m
	return pts


## Wall in the plane z = zc between xa..xb, y0..y1 with holes [[x0,x1,top_y]]; both faces optional.
func _wall_z(mat: String, zc: float, xa: float, xb: float, y0: float, y1: float, holes: Array, face_neg: bool, tunnel_face_only := false) -> void:
	# visible side toward the tunnel: for A (zc>0) the tunnel is at larger z => normal +z ; for B (zc<0) normal -z
	var normal_pos := not face_neg
	var cuts := [[xa, xb]]
	# build segments between holes
	var segs: Array = _segments(xa, xb, holes.map(func(h): return (h[0] + h[1]) * 0.5), holes[0][1] - holes[0][0] if holes.size() > 0 else 0.0)
	for sg in segs:
		_wall_quad(mat, zc, sg[0], sg[1], y0, y1, normal_pos)
	for h in holes:
		_wall_quad(mat, zc, h[0], h[1], h[2], y1, normal_pos)
	# spine-facing side (opposite normal) is drawn in _build_spine to limit it to the spine extent
	cuts = cuts


func _wall_quad(mat: String, zc: float, xa: float, xb: float, y0: float, y1: float, normal_pos: bool) -> void:
	if xb - xa < 0.001 or y1 - y0 < 0.001:
		return
	# `wall` shows the right of travel; normal +z needs travel +x ; normal -z needs travel -x
	if normal_pos:
		kit.wall(mat, Vector3(xa, 0, zc), Vector3(xb, 0, zc), y0, y1, 0.0)
	else:
		kit.wall(mat, Vector3(xb, 0, zc), Vector3(xa, 0, zc), y0, y1, 0.0)


## x-intervals of [xa, xb] not covered by openings centred at `centres` with width w
func _segments(xa: float, xb: float, centres: Array, w: float) -> Array:
	var cs := centres.duplicate()
	cs.sort()
	var out := []
	var cur := xa
	for c in cs:
		var h0: float = c - w * 0.5
		var h1: float = c + w * 0.5
		if h0 > cur:
			out.append([cur, h0])
		cur = maxf(cur, h1)
	if cur < xb:
		out.append([cur, xb])
	return out


func _band(mat: String, zc: float, xa: float, xb: float, y0: float, y1: float, neg: bool, tunnel_side_positive_toward_center: bool, holes := []) -> void:
	# thin coloured band slightly proud of the wall; faces the tunnel interior
	var off := 0.004
	var toward_tunnel := -signf(zc) if tunnel_side_positive_toward_center else signf(zc)
	# for the track-side wall the tunnel interior is toward the centre (-sign(zc)); for the platform-side wall it is away from the centre (+sign)
	var z := zc + toward_tunnel * off
	var segs := [[xa, xb]]
	if holes.size() > 0:
		segs = _segments(xa, xb, holes.map(func(h): return (h[0] + h[1]) * 0.5), holes[0][1] - holes[0][0])
	for sg in segs:
		if toward_tunnel > 0.0:
			kit.wall(mat, Vector3(sg[0], 0, z), Vector3(sg[1], 0, z), y0, y1, 0.0)
		else:
			kit.wall(mat, Vector3(sg[1], 0, z), Vector3(sg[0], 0, z), y0, y1, 0.0)


func _end_cap(s: float, x: float, zwall: float, zfar: float, west: bool) -> void:
	var za := minf(s * zwall, s * zfar)
	var zb := maxf(s * zwall, s * zfar)
	# a black plane closing the tunnel: seen from inside (normal toward the platform)
	var p0 := Vector3(x, SPRING_Y + RISE, za)
	var p1 := Vector3(x, SPRING_Y + RISE, zb)
	var p2 := Vector3(x, BED_Y, zb)
	var p3 := Vector3(x, BED_Y, za)
	if west:
		kit.quad("black", p0, p3, p2, p1, 0.0)      # normal +x
	else:
		kit.quad("black", p0, p1, p2, p3, 0.0)      # normal -x


func _frame(zc: float, ox: float, w: float, h: float) -> void:
	var t := 0.14
	for sgn in [-1.0, 1.0]:
		kit.box("metal", Vector3(ox + sgn * (w * 0.5 + t * 0.5), h * 0.5, zc), Vector3(t, h, 0.42), 0.0)
	kit.box("metal", Vector3(ox, h + t * 0.5, zc), Vector3(w + 2 * t, t, 0.42), 0.0)


func _build_spine(x0: float, x1: float, sx0: float, sx1: float, zwall: float, wall_mat: String, openings: Array) -> void:
	# floor + ceiling
	kit.horiz("floor_platform", sx0, sx1, -zwall, zwall, 0.0, true, 0.0)
	kit.horiz("ceiling", sx0, sx1, -zwall, zwall, SPINE_H, false, 0.0)
	# spine-facing sides of the two platform-side walls (normal toward the spine centre)
	for s in [1.0, -1.0]:
		var holes := []
		for ox in openings:
			holes.append([ox - OPEN_W * 0.5, ox + OPEN_W * 0.5, OPEN_H])
		var segs := _segments(sx0, sx1, openings, OPEN_W)
		for sg in segs:
			# normal toward centre: for the +z wall the normal is -z
			if s > 0.0:
				kit.wall(wall_mat, Vector3(sg[1], 0, s * zwall), Vector3(sg[0], 0, s * zwall), 0.0, SPINE_H, 0.0)
			else:
				kit.wall(wall_mat, Vector3(sg[0], 0, s * zwall), Vector3(sg[1], 0, s * zwall), 0.0, SPINE_H, 0.0)
		for h in holes:
			if h[0] >= sx0 and h[1] <= sx1:
				if s > 0.0:
					kit.wall(wall_mat, Vector3(h[1], 0, s * zwall), Vector3(h[0], 0, s * zwall), h[2], SPINE_H, 0.0)
				else:
					kit.wall(wall_mat, Vector3(h[0], 0, s * zwall), Vector3(h[1], 0, s * zwall), h[2], SPINE_H, 0.0)
	# east end cap (tile), west end open (portal)
	kit.wall(wall_mat, Vector3(sx1, 0, zwall), Vector3(sx1, 0, -zwall), 0.0, SPINE_H, 0.0)
	# lights: emissive panels in the spine ceiling
	var lx := sx0 + 2.0
	while lx < sx1:
		kit.box("light_emissive", Vector3(lx, SPINE_H - 0.03, 0.0), Vector3(1.2, 0.05, 0.3), 0.0)
		lx += 3.5
	var l2 := sx0 + 3.0
	while l2 < sx1:
		_lights.append([Vector3(l2, SPINE_H - 0.5, 0.0), 1.4, 9.0])
		l2 += 7.0
	# spine collision
	_cols.append([Vector3((sx0 + sx1) * 0.5, -0.5, 0.0), Vector3(sx1 - sx0, 1.0, GAP)])
	_cols.append([Vector3(sx1 + 0.15, 1.3, 0.0), Vector3(0.3, 2.6, GAP)])
	_cols.append([Vector3((sx0 + sx1) * 0.5, 3.0, 0.0), Vector3(sx1 - sx0, 0.4, GAP)])
	# reveal-fill: openings are 3.0 wide and the wall is thin; reveal frames handled by _frame


func _add_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	var edge_body := StaticBody3D.new()
	edge_body.name = "EdgeGuard"
	edge_body.collision_layer = 1 << 2      # layer 3: platform-edge guard (player only)
	edge_body.collision_mask = 0
	body.collision_layer = 1
	for c in _cols:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = c[1]
		cs.shape = sh
		cs.position = c[0]
		if c.size() > 2 and c[2] == "edge":
			edge_body.add_child(cs)
			if c.size() > 3:
				if not edge_shapes.has(c[3]):
					edge_shapes[c[3]] = []
				edge_shapes[c[3]].append([c[0].x, cs])
		else:
			body.add_child(cs)
	add_child(body)
	add_child(edge_body)


# ---------------------------------------------------------------------------------------------------
# Roof clearance (for signs)
# ---------------------------------------------------------------------------------------------------
func _arch() -> Dictionary:
	var zw := GAP * 0.5
	var zf: float = zw + float(meta["pw"]) + TRACK_TO_EDGE + TRACK_TO_WALL
	var chord := zf - zw
	var r := (chord * chord / 4.0 + RISE * RISE) / (2.0 * RISE)
	return {"zw": zw, "zf": zf, "zc": (zw + zf) * 0.5, "r": r, "yc": SPRING_Y + RISE - r}


## Roof height above the platform at module-local z (arch tunnels: circular arch over each tunnel, flat spine between; box halls: flat)
func ceiling_at(z: float) -> float:
	if box:
		return BOX_H
	var a := _arch()
	var az := absf(z)
	if az < float(a["zw"]):
		return SPINE_H
	if az > float(a["zf"]):
		return SPRING_Y
	var dz := az - float(a["zc"])
	return float(a["yc"]) + sqrt(maxf(float(a["r"]) * float(a["r"]) - dz * dz, 0.0))


## Box halls: move x sideways so a board hung at x clears the steel columns (every 7.2 m from x0 + 5)
func clear_of_columns(x: float, half_w := 0.4) -> float:
	if not box:
		return x
	var x0 := -float(meta["length"]) * 0.5
	var k := roundf((x - (x0 + 5.0)) / 7.2)
	var cx := x0 + 5.0 + k * 7.2
	var need := half_w + 0.3
	if absf(x - cx) < need:
		return cx + need if x >= cx else cx - need
	return x


## Where a hanging blade (faces along x, spans z) of size w x h fits under the roof of the tunnel on side `s` (+1/-1).
## Prefers z_want (signed) and a top edge at y_top_want; slides sideways / rises / shrinks until it clears the roof and walls.
## Returns {"z": signed centre z, "y_top": top edge, "k": scale}.
func fit_blade(s: float, z_want: float, w: float, h: float, y_top_want: float, margin := 0.12) -> Dictionary:
	var a := _arch()
	var zlo: float = float(a["zw"]) + 0.15
	var zhi: float = float(a["zf"]) - 0.15
	var za := absf(z_want)
	var top_limit: float = (BOX_H if box else SPRING_Y + RISE) - 0.05
	for k in [1.0, 0.88, 0.76, 0.66, 0.56]:
		var wk: float = w * k
		var hk: float = h * k
		var y_top := maxf(y_top_want, HEAD + hk)
		while y_top <= top_limit:
			var lo := zlo
			var hi := zhi
			if not box:
				var dy: float = y_top + margin - float(a["yc"])
				if dy > float(a["r"]):
					break
				var d := sqrt(maxf(float(a["r"]) * float(a["r"]) - dy * dy, 0.0))
				lo = maxf(lo, float(a["zc"]) - d)
				hi = minf(hi, float(a["zc"]) + d)
			if hi - lo >= wk:
				return {"z": s * clampf(za, lo + wk * 0.5, hi - wk * 0.5), "y_top": y_top, "k": k}
			y_top += 0.05
	return {"z": s * float(a["zc"]), "y_top": top_limit - 0.1, "k": 0.5}


## Open/close the invisible platform-edge guard between x_from..x_to (module-local) on the face at `face_sign` (+1 = +z tunnel)
func set_edge_open(face_sign: float, x_from: float, x_to: float, open: bool) -> void:
	if not edge_shapes.has(face_sign):
		return
	for e in edge_shapes[face_sign]:
		if e[0] >= x_from - 0.5 and e[0] <= x_to + 0.5:
			(e[1] as CollisionShape3D).set_deferred("disabled", open)


func _add_lights() -> void:
	var holder := Node3D.new()
	holder.name = "Lights"
	add_child(holder)
	for l in _lights:
		var o := OmniLight3D.new()
		o.position = l[0]
		o.light_energy = l[1]
		o.omni_range = l[2]
		o.omni_attenuation = 1.3
		o.light_color = Color(1.0, 0.97, 0.92)
		o.shadow_enabled = false
		o.distance_fade_enabled = true
		o.distance_fade_begin = 45.0
		o.distance_fade_length = 15.0
		holder.add_child(o)
