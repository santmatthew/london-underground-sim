class_name Footbridge
extends Node3D
## A covered footbridge over the two tracks between a pair of side platforms (StationPlan.is_split): a deck 5.2 m above the platforms, a landing at each end and a flight of 31 steps down from
## each landing to its platform, the steps beside the platform's back wall. Built in the frame of the module of the +z platform (slot 0), which is where the bridge's x is measured; the other
## platform's module lies `za .. zb` further along +z. The deck, the steps and the walls are solid (a plinth of brick under each landing and flight, a slab over the tracks, parapets and glazed
## sides, a roof over all of it), so the player can walk from one platform to the other over the tracks. It is NOT part of the plan's walking graph: the crowd and the planner do not use it
## (they go by the passages at the platform ends), it is there to look at and to walk on.
##
## Measures: a clear width of 2.0 m (W 2.4 with the 0.2 m walls), 31 risers of 0.168 m and 30 treads of 0.28 m (31 degrees), 2.6 m from the deck to the roof, parapets 1.1 m high, glass above them.

const DECK_Y := 5.2             # the deck's walking surface above the platform (rail clearance for the overhead wires, with the deck's depth)
const W := 2.4                  # outside width of the deck and of a flight
const HW := W * 0.5
const WALL_T := 0.2
const RISERS := 31
const TREAD := 0.28
const RUN := RISERS * TREAD     # the horizontal run of a flight, from the landing's edge to where the nosing line meets the platform
const HEAD := 2.6               # the walking surface to the underside of the roof
const PARAPET := 1.1
const SLAB := 0.3               # depth of the deck slab
const ROOF_T := 0.2

var kit := MeshKit.new()
var xb := 0.0
var d := 1.0                    # which way the steps go from the deck (+1 / -1 along x)
var wall_mat := "brick_red"
var _hulls: Array = []          # convex collision shapes: PackedVector3Array each
var _boxes: Array = []          # [centre, size] axis-aligned collision boxes
var _lights: Array = []         # Vector3


## the x range (module frame) a footbridge at x = p_xb whose steps go toward p_d takes up
static func footprint(p_xb: float, p_d: float) -> Vector2:
	var far := p_xb + p_d * (HW + RUN)
	return Vector2(minf(p_xb - HW, far), maxf(p_xb + HW, far))


## the height of the line through the nosings (and the ramp the player walks on) at distance u from the deck's middle, along the steps
static func line_y(u: float) -> float:
	return DECK_Y - (u - HW) * DECK_Y / RUN


## `pm`: the module that builds this (its _brk gives the frame back between the steps when the station is built in the background: the whole takes about 10 ms)
func build(p_xb: float, p_d: float, za: float, zb: float, p_wall_mat: String, pm: PlatformModule = null, p_async := false) -> void:
	xb = p_xb
	d = p_d
	wall_mat = "matt:a9aaa5" if p_wall_mat == "concrete" else p_wall_mat          # (the concrete of the station walls is much darker than a bridge's)
	kit.seed_rng(int(absf(xb) * 10.0) + 7)
	_deck(za, zb)
	if pm != null:
		await pm._brk(p_async)
	_flight(za, 1.0)
	if pm != null:
		await pm._brk(p_async)
	_flight(zb, -1.0)
	if pm != null:
		await pm._brk(p_async)
	_finish()


# --- helpers ----------------------------------------------------------------------------------------------------------------------------------

func _x(u: float) -> float:
	return xb + d * u


## a vertical wall between two floor points whose visible side is the one `facing` points to
func _wall(mat: String, a: Vector3, b: Vector3, y0: float, y1: float, facing: Vector3, floor_y := 0.0) -> void:
	if (b - a).cross(Vector3.UP).dot(facing) < 0.0:
		kit.wall(mat, b, a, y0, y1, floor_y)
	else:
		kit.wall(mat, a, b, y0, y1, floor_y)


## a quad (four points in order round it) visible from the side `facing` points to
func _quad(mat: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, facing: Vector3) -> void:
	if (p1 - p0).cross(p2 - p0).dot(facing) < 0.0:
		kit.quad(mat, p3, p2, p1, p0)
	else:
		kit.quad(mat, p0, p1, p2, p3)


func _box(mat, centre: Vector3, size: Vector3, floor_y := 0.0) -> void:
	kit.box(mat, centre, size, floor_y)


# --- the deck over the tracks, between the two landings ---------------------------------------------------------------------------------------

func _deck(za: float, zb: float) -> void:
	var Y := DECK_Y
	var z_lo := za - HW
	var z_hi := zb + HW
	var zs0 := za + HW
	var zs1 := zb - HW
	var xa := xb - HW
	var xe := xb + HW
	kit.horiz("floor_slab", xa, xe, z_lo, z_hi, Y, true, Y)
	kit.horiz("matt:9aa0a5", xa + WALL_T, xe - WALL_T, zs0, zs1, Y - SLAB, false, Y)          # (between the side panels, whose own undersides are drawn)
	var panel := "matt:7c848a"
	for sx: float in [-1.0, 1.0]:
		var xc := xb + sx * (HW - WALL_T * 0.5)
		var open_side := sx == d          # (the side the steps are on is open at the landings)
		var z0 := zs0 if open_side else z_lo
		var z1 := zs1 if open_side else z_hi
		var bz0 := z0 if open_side else z0 + WALL_T          # (the outer panel stops short of the landings' walls, which close the corners)
		var bz1 := z1 if open_side else z1 - WALL_T
		_box(panel, Vector3(xc, Y - SLAB + (SLAB + PARAPET) * 0.5, (bz0 + bz1) * 0.5), Vector3(WALL_T, SLAB + PARAPET, bz1 - bz0), Y)
		var gy0 := Y + PARAPET
		var gy1 := Y + HEAD
		_wall("ped_glass", Vector3(xc, 0, z0), Vector3(xc, 0, z1), gy0, gy1, Vector3(1, 0, 0), Y)          # (the glass is double-sided)
		var mz := z0
		while mz <= z1 + 0.01:
			_box("metal", Vector3(xc, (gy0 + gy1) * 0.5, mz), Vector3(0.1, gy1 - gy0, 0.1), Y)
			mz += 2.4
		_boxes.append([Vector3(xc, (Y - SLAB + Y + HEAD) * 0.5, (z0 + z1) * 0.5), Vector3(WALL_T, SLAB + HEAD, z1 - z0)])
	# the closed ends of the two landings (above the plinths)
	for sz: float in [-1.0, 1.0]:
		var zc := z_lo + WALL_T * 0.5 if sz < 0.0 else z_hi - WALL_T * 0.5
		_box(panel, Vector3(xb, Y + PARAPET * 0.5, zc), Vector3(W, PARAPET, WALL_T), Y)
		_wall("ped_glass", Vector3(xa, 0, zc), Vector3(xe, 0, zc), Y + PARAPET, Y + HEAD, Vector3(0, 0, 1), Y)
		_boxes.append([Vector3(xb, Y + HEAD * 0.5, zc), Vector3(W, HEAD, WALL_T)])
	# the roof, its underside white, and the light strips under it
	kit.box({"*": "matt:5f666c", "bottom": "ceiling"}, Vector3(xb, Y + HEAD + ROOF_T * 0.5, (z_lo + z_hi) * 0.5), Vector3(W + 0.3, ROOF_T, z_hi - z_lo + 0.2), Y)
	var lz := z_lo + 1.8
	while lz < z_hi - 1.0:
		kit.box("light_emissive", Vector3(xb, Y + HEAD - 0.03, lz), Vector3(0.34, 0.05, 1.2), Y)
		lz += 3.0
	var n_l := maxi(2, int(ceil((z_hi - z_lo) / 5.5)))
	for k in n_l:
		_lights.append(Vector3(xb, Y + HEAD - 0.5, z_lo + (float(k) + 0.5) * (z_hi - z_lo) / float(n_l)))
	_boxes.append([Vector3(xb, Y - SLAB * 0.5, (zs0 + zs1) * 0.5), Vector3(W, SLAB, zs1 - zs0)])


# --- a landing and the flight of steps that goes down from it to the platform ------------------------------------------------------------------
## zc: the z of the flight's axis (the back wall of the platform is HW beyond it); sg: +1 where the deck leaves the landing toward +z (the module of the +z platform), -1 toward -z

func _flight(zc: float, sg: float) -> void:
	var Y := DECK_Y
	var r := Y / RISERS
	var zl := zc - HW
	var zh := zc + HW
	var x_end := _x(-HW)
	var th := atan2(r, TREAD)
	# --- the plinth under the landing: its three sides below the deck (the fourth is the first riser of the steps)
	_wall(wall_mat, Vector3(x_end, 0, zl), Vector3(x_end, 0, zh), 0.0, Y - SLAB, Vector3(-d, 0, 0))          # (the deck's side panel carries on above it)
	_wall(wall_mat, Vector3(xb - HW, 0, zc - sg * HW), Vector3(xb + HW, 0, zc - sg * HW), 0.0, Y, Vector3(0, 0, -sg))
	_wall(wall_mat, Vector3(xb - HW, 0, zc + sg * HW), Vector3(xb + HW, 0, zc + sg * HW), 0.0, Y, Vector3(0, 0, sg))
	# --- the steps: a riser at every u_i, a tread between each pair, brick parapets either side
	for i in RISERS:
		var u0 := HW + float(i) * TREAD
		var u1 := u0 + TREAD
		var h := Y - float(i + 1) * r                  # the top of tread i (the last 'tread' is the platform itself)
		var xs0 := _x(u0)
		var xs1 := _x(u1)
		var xlo := minf(xs0, xs1)
		var xhi := maxf(xs0, xs1)
		# riser i: between this tread and the one above it, facing the foot of the steps
		_wall("concrete", Vector3(xs0, 0, zl + WALL_T), Vector3(xs0, 0, zh - WALL_T), h, h + r, Vector3(d, 0, 0))
		if i < RISERS - 1:
			kit.horiz("floor_slab", xlo, xhi, zl + WALL_T, zh - WALL_T, h, true, 0.0)
			var nlo := xlo if d < 0.0 else xhi - 0.06
			kit.horiz("yellow_paint", nlo, nlo + 0.06, zl + WALL_T, zh - WALL_T, h + 0.003, true, 0.0)
		var top := Y - float(i) * r + PARAPET
		for zz: float in [zl + WALL_T * 0.5, zh - WALL_T * 0.5]:
			kit.box(wall_mat, Vector3((xlo + xhi) * 0.5, top * 0.5, zz), Vector3(TREAD, top, WALL_T), 0.0, true)
	# --- handrails, posts, glass and the sloped roof over the steps
	var rot := Basis(Vector3(d * cos(th), -sin(th), 0.0), Vector3(d * sin(th), cos(th), 0.0), Vector3(0, 0, d))
	var slope := RUN / cos(th)
	var u_mid := HW + RUN * 0.5
	var mid := Vector3(_x(u_mid), line_y(u_mid), 0.0)
	for zz: float in [zl + WALL_T * 0.5, zh - WALL_T * 0.5]:
		kit.box_xf("metal", Transform3D(rot, mid + Vector3(0, PARAPET + 0.06, zz)), Vector3(slope, 0.05, 0.07), 0.0)
		for k in 4:
			var u := HW + (float(k) + 0.5) * RUN / 4.0
			var y0 := line_y(u) + PARAPET
			kit.box("metal", Vector3(_x(u), (y0 + line_y(u) + HEAD) * 0.5, zz), Vector3(0.08, line_y(u) + HEAD - y0, 0.08), 0.0)
		# glass above the parapet, both ways
		var gz := zz
		var q0 := Vector3(_x(HW), Y + PARAPET, gz)
		var q1 := Vector3(_x(HW + RUN), PARAPET, gz)
		var q2 := Vector3(_x(HW + RUN), HEAD, gz)
		var q3 := Vector3(_x(HW), Y + HEAD, gz)
		_quad("ped_glass", q0, q1, q2, q3, Vector3(0, 0, 1))
	kit.box_xf({"*": "matt:5f666c", "bottom": "ceiling"}, Transform3D(rot, mid + Vector3(0, HEAD + ROOF_T * 0.5, 0)), Vector3(slope, ROOF_T, W + 0.3), 0.0)
	for u in [HW + RUN * 0.28, HW + RUN * 0.72]:
		_lights.append(Vector3(_x(u), line_y(u) + HEAD - 0.5, zc))
	# --- collision: the plinth and the ramp (one convex shape whose top is the ramp the player walks up), the parapets above it, the back wall of the landing
	var foot_u := HW + RUN
	var prof := [Vector2(-HW, 0.0), Vector2(foot_u, 0.0), Vector2(HW, Y), Vector2(-HW, Y)]
	_hulls.append(_prism(prof, zl, zh))
	var par := [Vector2(HW, Y), Vector2(foot_u, 0.0), Vector2(foot_u, PARAPET), Vector2(HW, Y + PARAPET)]
	for zz: float in [zl, zh - WALL_T]:
		_hulls.append(_prism(par, zz, zz + WALL_T))


## the shape (u, y) extruded between z0 and z1, u mapped to x
func _prism(prof: Array, z0: float, z1: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for p: Vector2 in prof:
		pts.append(Vector3(_x(p.x), p.y, z0))
		pts.append(Vector3(_x(p.x), p.y, z1))
	return pts


func _finish() -> void:
	var mats := {}
	for k in kit.surfaces.keys():
		if k.begins_with("flat:"):
			mats[k] = Mats.flat(Color.html(k.substr(5)), 0.4)
		elif k.begins_with("matt:"):
			mats[k] = Mats.flat(Color.html(k.substr(5)), 0.92)
		else:
			mats[k] = Mats.get_mat(k)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build(mats)
	mi.name = "Mesh"
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Collision"
	for b in _boxes:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = b[1]
		cs.shape = sh
		cs.position = b[0]
		body.add_child(cs)
	for pts in _hulls:
		var cs2 := CollisionShape3D.new()
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		cs2.shape = hull
		body.add_child(cs2)
	add_child(body)
	for lp in _lights:
		var o := OmniLight3D.new()
		o.position = lp
		o.light_energy = 1.3
		o.omni_range = 8.0
		o.omni_attenuation = 1.3
		o.light_color = Color(1.0, 0.97, 0.92)
		o.shadow_enabled = false
		o.distance_fade_enabled = true
		o.distance_fade_begin = 45.0
		o.distance_fade_length = 15.0
		add_child(o)
