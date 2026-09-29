class_name Escalator
extends Node3D
## A bank of parallel escalators (lanes). Local frame: origin at the TOP end of the shaft, on the centre line, at the upper floor level;
## +x runs downhill (horizontal), +z lateral. The whole node is yawed/translated by the station builder.
##   |<-plate->|<-------- slope (run) -------->|<-plate->|
## lanes[i] = +1 moving DOWN (top -> bottom) or -1 moving UP.

const ANGLE := deg_to_rad(30.0)
const PLATE := 1.3
const LANE_W := 1.0
const PITCH := 1.5
const CLEARANCE := 3.7
const SPEED := 0.75               # m/s along the slope
const BALUSTRADE := 0.28

var rise := 12.0
var lanes: Array = [1, -1, 1]
var run := 0.0
var length := 0.0                 # total plan length incl. plates
var width := 0.0
var kit := MeshKit.new()
var _cols: Array = []
var _bodies: Array = []           # [AnimatableBody3D, dir(+1 down/-1 up)]
var wall_mat := "tile_white"
var floor_y := 0.0


func lane_z(i: int) -> float:
	return (i - (lanes.size() - 1) * 0.5) * PITCH


func slope_y(x: float) -> float:
	# height of the tread surface at plan distance x (local), top plate at y=0
	if x <= PLATE:
		return 0.0
	if x >= PLATE + run:
		return -rise
	return -(x - PLATE) * tan(ANGLE)


## position along the lane's path -> local position (t in metres along the total path 0 .. path_length)
func path_length() -> float:
	return PLATE * 2.0 + run / cos(ANGLE)


func build(p_rise: float, p_lanes: Array, p_wall_mat := "tile_white") -> void:
	rise = p_rise
	lanes = p_lanes
	wall_mat = p_wall_mat
	run = rise / tan(ANGLE)
	length = PLATE * 2.0 + run
	width = lanes.size() * PITCH + 0.6
	kit.seed_rng(int(rise * 100) + lanes.size())
	var hw := width * 0.5
	var ax := 0.0
	var bx := length
	var top_c := CLEARANCE
	# --- shaft walls & ceiling: profile in (x,y) ---
	# ceiling: flat at +CLEARANCE over the top plate, parallel to the slope, flat over the bottom plate
	var cy0 := top_c
	var cy1 := top_c - rise
	var ceil_pts := [Vector2(ax, cy0), Vector2(PLATE, cy0), Vector2(PLATE + run, cy1), Vector2(bx, cy1)]
	var floor_pts := [Vector2(ax, 0.0), Vector2(PLATE, 0.0), Vector2(PLATE + run, -rise), Vector2(bx, -rise)]
	for side in [-1.0, 1.0]:
		var z: float = side * hw
		for i in 3:
			var fa: Vector2 = floor_pts[i]
			var fb: Vector2 = floor_pts[i + 1]
			var ca: Vector2 = ceil_pts[i]
			var cb: Vector2 = ceil_pts[i + 1]
			# wall faces the shaft interior: normal -side*z
			var pa := Vector3(fa.x, fa.y, z)
			var pb := Vector3(fb.x, fb.y, z)
			var pc := Vector3(cb.x, cb.y, z)
			var pd := Vector3(ca.x, ca.y, z)
			if side < 0.0:
				kit.quad(wall_mat, pd, pa, pb, pc, floor_y)       # normal +z (into the shaft from the -z wall)
			else:
				kit.quad(wall_mat, pc, pb, pa, pd, floor_y)       # normal -z
	for i in 3:
		var ca: Vector2 = ceil_pts[i]
		var cb: Vector2 = ceil_pts[i + 1]
		kit.quad("ceiling", Vector3(ca.x, ca.y, -hw), Vector3(cb.x, cb.y, -hw), Vector3(cb.x, cb.y, hw), Vector3(ca.x, ca.y, hw), floor_y)
	# --- lanes ---
	for li in lanes.size():
		var zc := lane_z(li)
		var z0 := zc - LANE_W * 0.5
		var z1 := zc + LANE_W * 0.5
		# plates (flat comb plates) top and bottom
		kit.horiz("metal", ax, PLATE, z0, z1, 0.0, true, floor_y)
		kit.horiz("metal", PLATE + run, bx, z0, z1, -rise, true, floor_y)
		# sloped treads: material index by lane
		var mname := "esc_step_%d" % li
		var sa := Vector3(PLATE, 0.0, z0)
		var sb := Vector3(PLATE, 0.0, z1)
		var sc := Vector3(PLATE + run, -rise, z1)
		var sd := Vector3(PLATE + run, -rise, z0)
		# CCW seen from above: sa (top,-z), sb (top,+z), sc (bottom,+z), sd (bottom,-z); UV.y along slope
		kit.quad(mname, sd, sa, sb, sc, floor_y, Vector2.ZERO, 0.0, true)
		# balustrade + handrail at each lane edge (shared between lanes)
	for bi in lanes.size() + 1:
		var zb := (bi - lanes.size() * 0.5) * PITCH
		_balustrade(zb)
	_collision()
	_finish()


func _balustrade(z: float) -> void:
	var t := BALUSTRADE
	var slope_len := run / cos(ANGLE)
	var rot := Basis(Vector3(0, 0, 1), -ANGLE)
	var mid := Vector3(PLATE + run * 0.5, -rise * 0.5, z)
	# sloped inner panel (black glossy), steel top cover, handrail (offsets follow the slope normal)
	kit.box_xf({"*": "metal", "top": "metal"}, Transform3D(rot, mid + rot * Vector3(0, 0.45, 0)), Vector3(slope_len, 0.9, t), floor_y)
	kit.box_xf("black", Transform3D(rot, mid + rot * Vector3(0, 0.97, 0)), Vector3(slope_len + 0.02, 0.07, 0.09), floor_y)
	# under-lit skirt strip
	kit.box_xf("light_emissive", Transform3D(rot, mid + rot * Vector3(0, 0.03, 0)), Vector3(slope_len, 0.04, t + 0.02), floor_y)
	# flat plate sections
	for xr in [[0.0, PLATE, 0.0], [PLATE + run, length, -rise]]:
		var cx: float = (xr[0] + xr[1]) * 0.5
		var w: float = xr[1] - xr[0]
		kit.box({"*": "metal", "top": "metal"}, Vector3(cx, xr[2] + 0.45, z), Vector3(w, 0.9, t), floor_y)
		kit.box("black", Vector3(cx, xr[2] + 0.98, z), Vector3(w, 0.07, 0.09), floor_y)
	# newel at each end (rounded cap approximated by a box)
	kit.box("metal", Vector3(0.0, 0.5, z), Vector3(0.2, 1.0, t + 0.04), floor_y)
	kit.box("metal", Vector3(length, -rise + 0.5, z), Vector3(0.2, 1.0, t + 0.04), floor_y)


func _collision() -> void:
	# static plates
	for li in lanes.size():
		var zc := lane_z(li)
		_cols.append([Vector3(PLATE * 0.5, -0.5, zc), Vector3(PLATE, 1.0, LANE_W + 0.3), null])
		_cols.append([Vector3(PLATE + run + PLATE * 0.5, -rise - 0.5, zc), Vector3(PLATE, 1.0, LANE_W + 0.3), null])
	# balustrade / outer walls (vertical, full height so nobody clips into the shaft edge)
	for bi in lanes.size() + 1:
		var zb := (bi - lanes.size() * 0.5) * PITCH
		# split into slope-following boxes
		var n := 8
		for k in n:
			var x := PLATE + run * (float(k) + 0.5) / n
			_cols.append([Vector3(x, slope_y(x) + 0.7, zb), Vector3(run / n + 0.05, 1.4, BALUSTRADE), null])
		_cols.append([Vector3(PLATE * 0.5, 0.7, zb), Vector3(PLATE, 1.4, BALUSTRADE), null])
		_cols.append([Vector3(PLATE + run + PLATE * 0.5, -rise + 0.7, zb), Vector3(PLATE, 1.4, BALUSTRADE), null])


func _finish() -> void:
	var mats := {}
	for k in kit.surfaces.keys():
		if k.begins_with("esc_step_"):
			var li := int(k.substr(9))
			var m := ShaderMaterial.new()
			m.shader = load("res://shaders/escalator_step.gdshader")
			m.set_shader_parameter("speed", SPEED * float(lanes[li]))
			mats[k] = m
		elif k.begins_with("flat:"):
			mats[k] = Mats.flat(Color.html(k.substr(5)), 0.4)
		else:
			mats[k] = Mats.get_mat(k)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build(mats)
	mi.name = "Mesh"
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Collision"
	for c in _cols:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = c[1]
		cs.shape = sh
		cs.position = c[0]
		body.add_child(cs)
	add_child(body)
	# moving tread bodies (one per lane)
	for li in lanes.size():
		var ab := AnimatableBody3D.new()
		ab.name = "Tread%d" % li
		ab.sync_to_physics = false
		var cs2 := CollisionShape3D.new()
		var sh2 := BoxShape3D.new()
		var slope_len := run / cos(ANGLE)
		sh2.size = Vector3(slope_len, 0.4, LANE_W)
		cs2.shape = sh2
		ab.add_child(cs2)
		ab.position = Vector3(PLATE + run * 0.5, -rise * 0.5, lane_z(li)) + Basis(Vector3(0, 0, 1), -ANGLE) * Vector3(0, -0.2, 0)
		ab.rotation = Vector3(0, 0, -ANGLE)
		add_child(ab)
		_bodies.append([ab, lanes[li]])
	# lights along the shaft ceiling
	var n := maxi(2, int(length / 6.0))
	for k in n:
		var x := (k + 0.5) * length / n
		var y := (CLEARANCE if x < PLATE else (CLEARANCE - rise if x > PLATE + run else CLEARANCE - (x - PLATE) * tan(ANGLE)))
		var o := OmniLight3D.new()
		o.position = Vector3(x, y - 0.5, 0)
		o.light_energy = 1.4
		o.omni_range = 9.0
		o.omni_attenuation = 1.3
		o.light_color = Color(1.0, 0.97, 0.92)
		o.distance_fade_enabled = true
		o.distance_fade_begin = 40.0
		o.distance_fade_length = 12.0
		add_child(o)


func _ready() -> void:
	# platform velocities are in world space; set once we're placed in the tree
	call_deferred("_apply_velocities")


func _apply_velocities() -> void:
	for b in _bodies:
		var ab: AnimatableBody3D = b[0]
		var dir: int = b[1]
		# tread moves along the slope: down = +x,-y
		var local_dir := Vector3(cos(ANGLE), -sin(ANGLE), 0.0) * SPEED * float(dir)
		ab.constant_linear_velocity = global_transform.basis * local_dir


## helpers for NPCs / navigation ------------------------------------------------------------------
## local point on the lane centre at path parameter s (0..path_length) walking from the TOP to the BOTTOM
func point_on_lane(li: int, s: float) -> Vector3:
	var slope_len := run / cos(ANGLE)
	var z := lane_z(li)
	if s <= PLATE:
		return Vector3(s, 0.0, z)
	if s >= PLATE + slope_len:
		var rest := s - PLATE - slope_len
		return Vector3(PLATE + run + rest, -rise, z)
	var d := s - PLATE
	return Vector3(PLATE + d * cos(ANGLE), -d * sin(ANGLE), z)
