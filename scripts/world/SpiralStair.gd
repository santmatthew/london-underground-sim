class_name SpiralStair
extends Node3D
## A spiral emergency stair (Hampstead, Covent Garden, Russell Square, Goodge Street, Borough): a stairwell with a central newel, `steps` steps of `rise / steps` metres each winding round it, white-tiled
## outer wall, handrails on the wall and the newel, lights, a landing at each end with a door in the wall. The player does not walk out of its doors into the station: they are portals
## (Station._build_spirals); the stair itself is walked for real, on a smooth helical ramp collider (the visible steps are only decoration, like the straight stairs).
## Local frame: origin at the tower's axis on the top landing's floor, y up; the stair winds DOWN clockwise seen from above (angle theta: x = cos, z = sin, so +theta is clockwise).
## `top_door_angle` / `bottom_door_angle`: where the doors are.

const STEPS_PER_TURN := 17.0
const R_IN := 0.40             # the newel
const R_OUT := 1.70            # the wall
const WALK_R := 1.05           # the line people walk along
const WALL_H := 3.2            # the wall above the top landing
const LANDING_ARC := 2.4       # the landings extend this many steps' worth of angle either side
const PACE_UP := 0.40          # walking pace on the helix as a fraction of the flat pace (Player.WALK_SPEED 1.55 m/s): 0.39 m of arc a step at about 0.65 s a step
const PACE_DOWN := 0.52        # ... and down, about 0.38 s a step

var steps := 100
var rise := 18.0
var riser := 0.18
var d_theta := TAU / STEPS_PER_TURN
var theta0 := 0.0              # where the first tread starts (the top landing ends)
var top_door_angle := 0.0
var bottom_door_angle := 0.0
var kit := MeshKit.new()


# -- the geometry as pure functions of (steps, rise), so plans can lay out routes through it on a worker thread without making a node (theta0 = 0) --------------------------------------
static func s_dtheta() -> float:
	return TAU / STEPS_PER_TURN


static func s_ramp_y(p_steps: int, p_rise: float, theta: float) -> float:
	var s := (theta + s_dtheta() * 0.5) / s_dtheta()
	return -clampf(s, 0.0, float(p_steps)) * (p_rise / p_steps)


static func s_point(p_steps: int, p_rise: float, theta: float, radius := WALK_R) -> Vector3:
	return Vector3(cos(theta) * radius, s_ramp_y(p_steps, p_rise, theta), sin(theta) * radius)


static func s_tangent(theta: float) -> Vector3:
	return Vector3(-sin(theta), 0.0, cos(theta))


static func s_top_entry(p_steps: int, p_rise: float) -> Vector3:
	return s_point(p_steps, p_rise, -s_dtheta() * 0.6)


static func s_bottom_exit(p_steps: int, p_rise: float) -> Vector3:
	return s_point(p_steps, p_rise, s_dtheta() * (p_steps - 1 + 0.9))


static func s_walk_points(p_steps: int, p_rise: float, spacing := 0.9) -> Array:
	var out: Array = []
	var t_a := -s_dtheta() * 0.6
	var t_b := s_dtheta() * (p_steps - 1 + 0.9)
	var n := maxi(2, int(ceil(absf(t_b - t_a) * WALK_R / spacing)))
	for k in n + 1:
		out.append(s_point(p_steps, p_rise, lerpf(t_a, t_b, float(k) / n)))
	return out


func configure(p_steps: int, p_rise: float) -> SpiralStair:
	steps = maxi(p_steps, 8)
	rise = p_rise
	riser = rise / steps
	top_door_angle = theta0 - d_theta * LANDING_ARC * 0.5
	bottom_door_angle = theta0 + d_theta * (steps - 1 + LANDING_ARC * 0.5)
	return self


## the walking line at angle theta (local frame): the ramp's height there (flat on the landings)
func ramp_y(theta: float) -> float:
	var s := (theta - (theta0 - d_theta * 0.5)) / d_theta          # in steps from the top of the ramp
	return -clampf(s, 0.0, float(steps)) * riser


func point(theta: float, radius := WALK_R) -> Vector3:
	return Vector3(cos(theta) * radius, ramp_y(theta), sin(theta) * radius)


## where the player comes out of the top door: on the walking line a step in from the door, facing down the stair (local frame)
func top_entry() -> Vector3:
	return point(theta0 - d_theta * 0.6)


func bottom_exit() -> Vector3:
	return point(theta0 + d_theta * (steps - 1 + 0.9))


## direction of travel (down the stair, clockwise) at theta, horizontal
func tangent(theta: float) -> Vector3:
	return Vector3(-sin(theta), 0.0, cos(theta))


## walking-line points from the top entry to the bottom exit, about every `spacing` metres (local frame)
func walk_points(spacing := 0.9) -> Array:
	var out: Array = []
	var t_a := theta0 - d_theta * 0.6
	var t_b := theta0 + d_theta * (steps - 1 + 0.9)
	var n := maxi(2, int(ceil(absf(t_b - t_a) * WALK_R / spacing)))
	for k in n + 1:
		out.append(point(lerpf(t_a, t_b, float(k) / n)))
	return out


func build() -> void:
	kit = MeshKit.new()
	_geometry()
	var mats := {}
	for n in ["tile_white", "floor_hall", "metal", "light_emissive", "yellow_paint", "ceiling", "black", "white_paint", "steel"]:
		mats[n] = Mats.get_mat(n)
	for k in kit.surfaces.keys():
		if k.begins_with("flat:"):
			mats[k] = Mats.flat(Color.html(k.substr(5)), 0.5)
		elif k.begins_with("matt:"):
			mats[k] = Mats.flat(Color.html(k.substr(5)), 0.92)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build(mats)
	mi.name = "Shell"
	add_child(mi)
	_collision()
	_lights()


func _geometry() -> void:
	var y_top := WALL_H
	var y_bot := -rise
	# the outer wall (faces in) and the newel (faces out), a ceiling over the top landing and a floor under the bottom one
	kit.lathe("tile_white", PackedVector2Array([Vector2(R_OUT + 0.02, y_bot - 0.3), Vector2(R_OUT + 0.02, y_top)]), 0.0, 0.0, 1.0, 1.0, 48, y_bot)
	kit.lathe("matt:c4c1b8", PackedVector2Array([Vector2(R_IN, y_bot - 0.3), Vector2(R_IN, y_top)]), 0.0, 0.0, 1.0, 1.0, 16, y_bot, true)
	kit.lathe("ceiling", PackedVector2Array([Vector2(R_OUT, y_top), Vector2(R_IN, y_top)]), 0.0, 0.0, 1.0, 1.0, 24, y_bot)
	kit.lathe("matt:c4c1b8", PackedVector2Array([Vector2(R_IN, y_bot - 0.3), Vector2(R_OUT, y_bot - 0.3)]), 0.0, 0.0, 1.0, 1.0, 24, y_bot, true)
	# the landings: a flat sector each, floor and underside
	_sector("floor_hall", theta0 - d_theta * LANDING_ARC, theta0, 0.0, true)
	_sector("floor_hall", theta0 + d_theta * (steps - 1), theta0 + d_theta * (steps - 1 + LANDING_ARC), -rise, true)
	# the treads: tread k (1 .. steps - 1) spans [theta0 + (k - 1) d, theta0 + k d] at height -k * riser; its riser (the step down from the one before) stands at its start
	for k in range(1, steps):
		var a0 := theta0 + (k - 1) * d_theta
		var a1 := theta0 + k * d_theta
		var y := -k * riser
		var in0 := Vector3(cos(a0) * R_IN, y, sin(a0) * R_IN)
		var in1 := Vector3(cos(a1) * R_IN, y, sin(a1) * R_IN)
		var out0 := Vector3(cos(a0) * R_OUT, y, sin(a0) * R_OUT)
		var out1 := Vector3(cos(a1) * R_OUT, y, sin(a1) * R_OUT)
		kit.quad("floor_hall", in0, in1, out1, out0, y_bot)                                                   # the tread (faces up)
		var up := Vector3(0, riser, 0)
		kit.quad("matt:c4c1b8", in0 + up, out0 + up, out0, in0, y_bot)                                           # the riser at its start (faces down the stair)
		var dn := Vector3(0, -0.10, 0)
		kit.quad("matt:c4c1b8", in0 + dn, out0 + dn, out1 + dn, in1 + dn, y_bot)                                 # the underside (faces down)
	# handrails on the wall and on the newel, following the ramp
	var seg := maxi(steps, 8)
	for rr in [R_OUT - 0.07, R_IN + 0.08]:
		for k in seg:
			var t0 := theta0 - d_theta * 0.5 + k * d_theta
			var t1 := t0 + d_theta
			var p0 := Vector3(cos(t0) * rr, ramp_y(t0) - riser * 0.0 + 0.92, sin(t0) * rr)
			var p1 := Vector3(cos(t1) * rr, ramp_y(t1) + 0.92, sin(t1) * rr)
			var d := p1 - p0
			var b := Basis.looking_at(d.normalized(), Vector3.UP)
			kit.box_xf("metal", Transform3D(b, (p0 + p1) * 0.5), Vector3(0.05, 0.05, d.length() + 0.01), y_bot)
	# brackets: a post from the tread to the rail every 4th step
	for k in range(1, steps, 4):
		var tt := theta0 + (k - 0.5) * d_theta
		var rr2 := R_OUT - 0.07
		var py := ramp_y(tt) + riser * 0.0
		kit.box("metal", Vector3(cos(tt) * rr2, py + 0.46 - riser * 0.5, sin(tt) * rr2), Vector3(0.03, 0.92, 0.03), y_bot)
	# the doors in the wall at the two landings: a frame and a leaf
	for ang in [top_door_angle, bottom_door_angle]:
		_door(ang, 0.0 if ang == top_door_angle else -rise)


## an annular sector of floor (and its underside) between two angles at height y
func _sector(mat: String, a0: float, a1: float, y: float, up: bool) -> void:
	var n := 6
	for k in n:
		var t0 := lerpf(a0, a1, float(k) / n)
		var t1 := lerpf(a0, a1, float(k + 1) / n)
		var i0 := Vector3(cos(t0) * R_IN, y, sin(t0) * R_IN)
		var i1 := Vector3(cos(t1) * R_IN, y, sin(t1) * R_IN)
		var o0 := Vector3(cos(t0) * R_OUT, y, sin(t0) * R_OUT)
		var o1 := Vector3(cos(t1) * R_OUT, y, sin(t1) * R_OUT)
		kit.quad(mat, i0, i1, o1, o0, y)
		var dn := Vector3(0, -0.10, 0)
		kit.quad("matt:c4c1b8", i0 + dn, o0 + dn, o1 + dn, i1 + dn, y)


func _door(ang: float, floor_y: float) -> void:
	var r := R_OUT - 0.01
	var c := Vector3(cos(ang) * r, floor_y, sin(ang) * r)
	var inward := Vector3(-cos(ang), 0, -sin(ang))
	var across := Vector3(-sin(ang), 0, cos(ang))
	var w := 0.62
	# the frame (dark) and the leaf (green: emergency exit), flat against the wall facing in
	for sd in [-1.0, 1.0]:
		kit.box_xf("black", Transform3D(Basis.looking_at(inward, Vector3.UP), c + across * sd * (w + 0.04) + Vector3(0, 1.1, 0)), Vector3(0.08, 2.2, 0.06), floor_y)
	kit.box_xf("black", Transform3D(Basis.looking_at(inward, Vector3.UP), c + Vector3(0, 2.24, 0)), Vector3(w * 2.0 + 0.2, 0.08, 0.06), floor_y)
	kit.box_xf("flat:2f7d4a", Transform3D(Basis.looking_at(inward, Vector3.UP), c + inward * 0.02 + Vector3(0, 1.08, 0)), Vector3(w * 2.0, 2.16, 0.04), floor_y)


func _collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	var faces := PackedVector3Array()
	var th := 0.3
	var sub := 4
	# the ramp: from the top landing's level at theta0 - d/2 to the bottom landing's level at theta0 + (steps - 0.5) d, 4 slices a step; landings flat before and after it
	var t_start := theta0 - d_theta * LANDING_ARC
	var t_end := theta0 + d_theta * (steps - 1 + LANDING_ARC)
	var slices := int(ceil((t_end - t_start) / (d_theta / sub)))
	for k in slices:
		var t0 := lerpf(t_start, t_end, float(k) / slices)
		var t1 := lerpf(t_start, t_end, float(k + 1) / slices)
		var i0 := Vector3(cos(t0) * (R_IN - 0.02), ramp_y(t0), sin(t0) * (R_IN - 0.02))
		var i1 := Vector3(cos(t1) * (R_IN - 0.02), ramp_y(t1), sin(t1) * (R_IN - 0.02))
		var o0 := Vector3(cos(t0) * R_OUT, ramp_y(t0), sin(t0) * R_OUT)
		var o1 := Vector3(cos(t1) * R_OUT, ramp_y(t1), sin(t1) * R_OUT)
		var dn := Vector3(0, -th, 0)
		# top (counter-clockwise from above is the front in Godot's trimesh: both sides collide, backface_collision below)
		faces.append_array([i0, o0, o1, i0, o1, i1])
		faces.append_array([i0 + dn, o1 + dn, o0 + dn, i0 + dn, i1 + dn, o1 + dn])
	# the wall: a 48-gon from the bottom landing's floor to the top of the wall (faces in), and the ceiling
	var n := 48
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var w0 := Vector3(cos(a0) * (R_OUT + 0.02), -rise - th, sin(a0) * (R_OUT + 0.02))
		var w1 := Vector3(cos(a1) * (R_OUT + 0.02), -rise - th, sin(a1) * (R_OUT + 0.02))
		var up := Vector3(0, rise + th + WALL_H, 0)
		faces.append_array([w0, w1, w1 + up, w0, w1 + up, w0 + up])
		faces.append_array([w0 + up, Vector3(0, WALL_H, 0), w1 + up])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	# the newel: a solid cylinder
	var cyl := CylinderShape3D.new()
	cyl.radius = R_IN
	cyl.height = rise + WALL_H + th
	var cn := CollisionShape3D.new()
	cn.shape = cyl
	cn.position = Vector3(0, (WALL_H - rise - th) * 0.5, 0)
	body.add_child(cn)
	add_child(body)


## lights up the well: a light on the wall side every 5 m of height, brighter at the landings (omni lights fade out beyond 22 m)
func _lights() -> void:
	var y := 2.2
	while y > -rise - 1.0:
		var o := OmniLight3D.new()
		var ang := theta0 + (-y / maxf(riser, 0.01)) * d_theta
		o.position = Vector3(cos(ang) * (R_IN + 0.15), y + 1.2, sin(ang) * (R_IN + 0.15))
		o.light_energy = 1.1
		o.omni_range = 7.5
		o.shadow_enabled = false
		o.distance_fade_enabled = true
		o.distance_fade_begin = 16.0
		o.distance_fade_length = 6.0
		add_child(o)
		y -= 5.0
	for ly in [-rise + 2.6, 2.6]:
		var o2 := OmniLight3D.new()
		o2.position = Vector3(0, ly, 0)
		o2.light_energy = 1.4
		o2.omni_range = 6.0
		o2.shadow_enabled = false
		add_child(o2)


func contains(world_pos: Vector3) -> bool:
	var l := to_local(world_pos)
	return Vector2(l.x, l.z).length() < R_OUT + 0.3 and l.y > -rise - 1.0 and l.y < WALL_H
