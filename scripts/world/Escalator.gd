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
const TREAD_SEG := 6.0             # length of one tread collision box
const GUARD_H := 3.4               # collision height of the balustrades: full shaft height, so nobody can stand on (or vault) a handrail

var rise := 12.0
var lanes: Array = [1, -1, 1]
var run := 0.0
var length := 0.0                 # total plan length incl. plates
var width := 0.0
var kit := MeshKit.new()
var _cols: Array = []
var _slabs: Array = []            # convex guard slabs (PackedVector3Array each)
var _bodies: Array = []           # [AnimatableBody3D, dir(+1 down/-1 up)]
var wall_mat := "tile_white"
var stairs := false             # fixed stairs instead of moving treads
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


func build(p_rise: float, p_lanes: Array, p_wall_mat := "tile_white", p_stairs := false) -> void:
	rise = p_rise
	stairs = p_stairs
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
	if stairs:
		_stairs_geometry(hw)
		_stairs_collision(hw)
		_finish()
		return
	# --- lanes ---
	for li in lanes.size():
		var zc := lane_z(li)
		var z0 := zc - LANE_W * 0.5
		var z1 := zc + LANE_W * 0.5
		# plates (flat comb plates) top and bottom
		kit.horiz("esc_plate_top", ax, PLATE, z0, z1, 0.0, true, floor_y)
		kit.horiz("esc_plate_bot", PLATE + run, bx, z0, z1, -rise, true, floor_y)
		# (the steps between the plates are the moving mesh of _steps_mesh)
		# balustrade + handrail at each lane edge (shared between lanes)
	for bi in lanes.size() + 1:
		var zb := (bi - lanes.size() * 0.5) * PITCH
		_balustrade(zb)
	if not Station.debug_off("escband"):
		_poster_band(hw)
		_deck_fittings(hw)
	_collision()
	_finish()


func _stairs_geometry(hw: float) -> void:
	var n := int(round(rise / 0.173))
	var riser := rise / n
	var tread := riser / tan(ANGLE)
	# flat landings at the top and bottom
	kit.horiz("floor_hall", 0.0, PLATE, -hw, hw, 0.0, true, floor_y)
	kit.horiz("floor_hall", PLATE + n * tread, length, -hw, hw, -rise, true, floor_y)
	# each step is a box (tread top + riser face) with a yellow nosing strip
	for i in n:
		var x0 := PLATE + i * tread
		var y_top := -i * riser
		kit.box({"*": "concrete", "top": "floor_hall"}, Vector3(x0 + tread * 0.5, y_top - riser * 0.5, 0.0), Vector3(tread, riser, hw * 2.0), floor_y, true)
		kit.horiz("yellow_paint", x0, x0 + 0.05, -hw, hw, y_top + 0.003, true, floor_y)
	# side handrails + a central rail with posts
	var slope_len := run / cos(ANGLE)
	var rot := Basis(Vector3(0, 0, 1), -ANGLE)
	var mid := Vector3(PLATE + run * 0.5, -rise * 0.5, 0.0)
	for zz in [-hw + 0.08, 0.0, hw - 0.08]:
		kit.box_xf("metal", Transform3D(rot, mid + rot * Vector3(0, 0.95, 0) + Vector3(0, 0, zz)), Vector3(slope_len, 0.05, 0.05), floor_y)
		for k in 7:
			var t := (k + 0.5) / 7.0
			kit.box("metal", Vector3(PLATE + run * t, -rise * t + 0.47, zz), Vector3(0.04, 0.95, 0.04), floor_y)


func _stairs_collision(hw: float) -> void:
	# a smooth ramp over the steps (walkable), landings, and side rails
	var slope_len := run / cos(ANGLE)
	var body := AnimatableBody3D.new()
	body.name = "StairRamp"
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(slope_len, 0.4, hw * 2.0)
	cs.shape = sh
	body.add_child(cs)
	body.position = Vector3(PLATE + run * 0.5, -rise * 0.5, 0.0) + Basis(Vector3(0, 0, 1), -ANGLE) * Vector3(0, -0.2, 0)
	body.rotation = Vector3(0, 0, -ANGLE)
	add_child(body)
	_cols.append([Vector3(PLATE * 0.5, -0.5, 0.0), Vector3(PLATE, 1.0, hw * 2.0), null])
	_cols.append([Vector3(PLATE + run + PLATE * 0.5, -rise - 0.5, 0.0), Vector3(PLATE, 1.0, hw * 2.0), null])
	for sgn in [-1.0, 1.0]:
		_guard_slab(sgn * (hw - 0.05), 0.12)


## The escalator poster band: portrait 419 x 572 mm panels (display area 387 x 540 mm) hung PLUMB on both shaft walls, stepping down with the
## slope (0.69 m along, 0.40 m down between frames: a 30 degree slope), their bottom edge about 1.35 m above the tread line. Unused slots hold a
## blank backing card. (Measured from photographs of London Underground escalators; see build/refs_dress/passages/SPEC.md 1.5.)
const PANEL_W := 0.419
const PANEL_H := 0.572
const PANEL_PITCH := 0.69
const PANEL_ABOVE := 1.35
const POSTER_VARIANTS := 10


func _poster_band(hw: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rise * 100.0) * 31 + lanes.size() * 7 + 5
	var picker := PosterKit.Picker.new(rng, POSTER_VARIANTS)
	var n := int((run - 1.6) / PANEL_PITCH)
	for side in [-1.0, 1.0]:
		var u_dir: float = -side          # the viewer's right-hand direction along x when facing this wall
		var zw: float = side * hw
		var zf: float = zw - side * 0.011     # frame centre (0.022 thick, on the shaft side of the wall)
		var zp: float = zw - side * 0.026     # poster face (4 mm in front of the frame, which is 22 mm deep: a poster at the frame's own depth would flicker)
		var last := ""
		for i in n:
			var xc: float = PLATE + 0.8 + (float(i) + 0.5) * PANEL_PITCH
			var yb: float = slope_y(xc) + PANEL_ABOVE
			var yc := yb + PANEL_H * 0.5
			kit.box("metal", Vector3(xc, yc, zf), Vector3(PANEL_W, PANEL_H, 0.022), floor_y)
			var mat := "flat:#c9cbc8"                                    # blank backing card
			if rng.randf() < 0.9:
				last = picker.pick("portrait", last)
				if last != "":
					mat = "poster:" + last
			var l: float = xc - u_dir * (PANEL_W - 0.032) * 0.5
			var r: float = xc + u_dir * (PANEL_W - 0.032) * 0.5
			var top := yc + (PANEL_H - 0.032) * 0.5
			var bot := yc - (PANEL_H - 0.032) * 0.5
			kit.quad(mat, Vector3(l, top, zp), Vector3(l, bot, zp), Vector3(r, bot, zp), Vector3(r, top, zp), floor_y, Vector2.ZERO, 0.0, true)


## Small deck furniture seen in every real shaft: red STOP pods at each end of each balustrade, blue/orange "hold the handrail / stand on the
## right" wedge signs along the decks, and the standard notice board on the walls at the head and foot.
func _deck_fittings(hw: float) -> void:
	var rot := Basis(Vector3(0, 0, 1), -ANGLE)
	var slope_len := run / cos(ANGLE)
	var rail_top := 1.0 + 0.035
	for bi in lanes.size() + 1:
		var zb := (bi - lanes.size() * 0.5) * PITCH
		# emergency stop pods on the newel tops (about 0.12 m cubes)
		kit.box("flat:#c62020", Vector3(0.3, 1.0 + 0.06, zb), Vector3(0.13, 0.12, 0.13), floor_y)
		kit.box("flat:#c62020", Vector3(length - 0.3, -rise + 1.0 + 0.06, zb), Vector3(0.13, 0.12, 0.13), floor_y)
		# wedge signs on the decks, every ~6 m along the slope, alternating the lane they face (0.42 x 0.12 m: orange half + navy half)
		var n := int(slope_len / 6.0)
		for k in n:
			var d0 := 2.0 + (k + 0.5) * (slope_len - 4.0) / maxf(n, 1)
			var mid := Vector3(PLATE + d0 * cos(ANGLE), -d0 * sin(ANGLE), zb)
			var face: float = 1.0 if (k + bi) % 2 == 0 else -1.0
			for half in [0, 1]:
				var off: float = (-0.105 if half == 0 else 0.105)
				var col := "flat:#f48733" if half == 0 else "flat:#232b78"
				kit.box_xf(col, Transform3D(rot, mid + rot * Vector3(off, rail_top + 0.05, face * 0.03)), Vector3(0.21, 0.10, 0.09), floor_y)
	# the notice board on each side wall, beside the top and bottom newel (0.5 x 1.0 m, eye height)
	for side in [-1.0, 1.0]:
		var u_dir: float = -side
		for at in [[1.1, 0.0], [length - 1.1, -rise]]:
			var xc: float = at[0]
			var yb: float = at[1] + 0.85
			var zp: float = side * hw - side * 0.02
			var l: float = xc - u_dir * 0.25
			var r: float = xc + u_dir * 0.25
			kit.quad("tex:notice@0.500@1.000", Vector3(l, yb + 1.0, zp), Vector3(l, yb, zp), Vector3(r, yb, zp), Vector3(r, yb + 1.0, zp), floor_y, Vector2.ZERO, 0.0, true)


func _balustrade(z: float) -> void:
	var t := BALUSTRADE
	var slope_len := run / cos(ANGLE)
	var rot := Basis(Vector3(0, 0, 1), -ANGLE)
	var mid := Vector3(PLATE + run * 0.5, -rise * 0.5, z)
	# sloped inner panel (black glossy), steel top cover, handrail (offsets follow the slope normal)
	kit.box_xf({"*": "steel", "top": "steel"}, Transform3D(rot, mid + rot * Vector3(0, 0.45, 0)), Vector3(slope_len, 0.9, t), floor_y)
	# (the handrail is the moving ribbon of _handrails_mesh)
	# under-lit skirt strip
	kit.box_xf("light_emissive", Transform3D(rot, mid + rot * Vector3(0, 0.03, 0)), Vector3(slope_len, 0.04, t + 0.02), floor_y)
	# flat plate sections
	for xr in [[0.0, PLATE, 0.0], [PLATE + run, length, -rise]]:
		var cx: float = (xr[0] + xr[1]) * 0.5
		var w: float = xr[1] - xr[0]
		kit.box({"*": "steel", "top": "steel"}, Vector3(cx, xr[2] + 0.45, z), Vector3(w, 0.9, t), floor_y)
	# newel at each end (rounded cap approximated by a box)
	kit.box("steel", Vector3(0.0, 0.5, z), Vector3(0.2, 1.0, t + 0.04), floor_y)
	kit.box("steel", Vector3(length, -rise + 0.5, z), Vector3(0.2, 1.0, t + 0.04), floor_y)


func _collision() -> void:
	# static plates
	for li in lanes.size():
		var zc := lane_z(li)
		_cols.append([Vector3(PLATE * 0.5, -0.5, zc), Vector3(PLATE, 1.0, LANE_W + 0.3), null])
		_cols.append([Vector3(PLATE + run + PLATE * 0.5, -rise - 0.5, zc), Vector3(PLATE, 1.0, LANE_W + 0.3), null])
	# balustrade / outer walls (vertical, full height so nobody clips into the shaft edge)
	for bi in lanes.size() + 1:
		var zb := (bi - lanes.size() * 0.5) * PITCH
		_guard_slab(zb, BALUSTRADE)
		_cols.append([Vector3(PLATE * 0.5, GUARD_H * 0.5, zb), Vector3(PLATE, GUARD_H, BALUSTRADE), null])
		_cols.append([Vector3(PLATE + run + PLATE * 0.5, -rise + GUARD_H * 0.5, zb), Vector3(PLATE, GUARD_H, BALUSTRADE), null])


## a wall along the slope: a parallelogram prism whose lower edge is exactly the tread line and whose height is GUARD_H
## (axis-aligned boxes left a gap under the downhill end of each box, wide enough to walk through on a very long escalator)
func _guard_slab(z: float, thick: float) -> void:
	var pts := PackedVector3Array()
	for zz in [z - thick * 0.5, z + thick * 0.5]:
		for x in [PLATE, PLATE + run]:
			pts.append(Vector3(x, slope_y(x), zz))
			pts.append(Vector3(x, slope_y(x) + GUARD_H, zz))
	_slabs.append(pts)


const RAIL_H := 0.985              # the handrail's centre line, along the normal to the tread line
const RAIL_W := 0.085
const RAIL_T := 0.045
const RAIL_OFF := 0.075            # how far from the middle of the balustrade each lane's rail lies, toward its lane
## The shaders are kept for good: a Shader resource that nothing refers to is freed with the station that used it, and loading it again (the next station, built in the background while a ride goes on) means
## compiling it again - 120 - 150 ms each, three of them for the first escalator of every station (measured 2026-10-04)
static var _shaders: Dictionary = {}


static func shader(nm: String) -> Shader:
	if not _shaders.has(nm):
		_shaders[nm] = load("res://shaders/%s.gdshader" % nm)
	return _shaders[nm]


## load all of them now (while the menu is up)
static func preload_shaders() -> void:
	for nm in ["escalator_steps", "escalator_plate", "escalator_handrail"]:
		shader(nm)


## the shaders, and one escalator built and thrown away: the first of a run costs 140 ms (its materials, the first mesh builds, the steps and the handrails' shader materials) against 11 ms for
## the next, and a ride to a deep station would otherwise pay it in the middle of the destination's build; done at start-up, behind the menu
static func warm_up() -> void:
	preload_shaders()
	var e := Escalator.new()
	e.build(6.0, [1, -1, 1], "tile_white")
	e.free()


const STEP_PITCH := 0.4            # arc length between neighbouring steps (a 0.2 m riser at 30 degrees)
const STEP_FILLET := 1.5           # the radius of the arcs that round the track's two corners (a 30 degree turn over 0.8 m: the steps no longer kink as they reach the slope)
const STEP_SINK := 0.07


## The moving steps, one surface per lane. Every step is built once (a tread quad and the riser under its front edge, in local coordinates); shaders/escalator_steps.gdshader puts them on the track
## each frame, so nothing is updated on the CPU. The mesh holds enough steps to cover the slope and wrap round under the plates.
func _steps_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var slope_len := run / cos(ANGLE)
	var n := int(ceil((slope_len + 2.0 * STEP_PITCH) / STEP_PITCH)) + 1
	var sh := shader("escalator_steps")
	for li in lanes.size():
		var z0 := lane_z(li) - LANE_W * 0.5
		var z1 := lane_z(li) + LANE_W * 0.5
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var idx := PackedInt32Array()
		for k in n:
			# tread: u along it (0 back .. 1 front), a quad facing up
			var b := verts.size()
			verts.append_array(PackedVector3Array([Vector3(0, 0, z0), Vector3(1, 0, z0), Vector3(1, 0, z1), Vector3(0, 0, z1)]))
			uvs.append_array(PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]))
			for _i in 4:
				norms.append(Vector3.UP)
				uv2s.append(Vector2(float(k), 0.0))
			idx.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))          # (Godot's front faces are the clockwise ones: this faces up)
			# riser under the front edge: w from the tread (0) down to the next step's tread (1), facing downhill
			b = verts.size()
			verts.append_array(PackedVector3Array([Vector3(1, 0, z0), Vector3(1, 0, z1), Vector3(1, 1, z1), Vector3(1, 1, z0)]))
			uvs.append_array(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))
			for _i in 4:
				norms.append(Vector3.RIGHT)
				uv2s.append(Vector2(float(k), 1.0))
			idx.append_array(PackedInt32Array([b, b + 2, b + 1, b, b + 3, b + 2]))          # (... and this one downhill)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("speed", SPEED * float(lanes[li]))
		m.set_shader_parameter("pitch", STEP_PITCH)
		m.set_shader_parameter("loop_len", float(n) * STEP_PITCH)
		m.set_shader_parameter("x0", PLATE)
		m.set_shader_parameter("run", run)
		m.set_shader_parameter("rise", rise)
		m.set_shader_parameter("cos_t", cos(ANGLE))
		m.set_shader_parameter("sin_t", sin(ANGLE))
		m.set_shader_parameter("l_vis", slope_len)
		m.set_shader_parameter("sink", STEP_SINK)
		m.set_shader_parameter("fillet", STEP_FILLET)
		mesh.surface_set_material(li, m)
	# (the vertices are placed by the shader: the box the engine culls by has to be given)
	mesh.custom_aabb = AABB(Vector3(-0.5, -rise - 1.0, -width * 0.5 - 0.5), Vector3(length + 1.0, rise + 2.0, width + 1.0))
	return mesh


## The centre line of a handrail in the (x, y) plane, from the newel at the top to the newel at the bottom, as [point, arc length u]: along the plate, down the line `RAIL_H` above the treads, along the
## bottom plate, the corners rounded (a quadratic curve through each)
func _rail_path() -> Array:
	var h := RAIL_H
	var half := tan(ANGLE * 0.5)
	var c1 := Vector2(PLATE + h * half, h)
	var c2 := Vector2(PLATE + run + h * half, -rise + h)
	var p0 := Vector2(0.1, h)
	var p3 := Vector2(length, -rise + h)
	var d_flat := Vector2(1.0, 0.0)
	var d_slope := Vector2(cos(ANGLE), -sin(ANGLE))
	var tl := 1.1 * half          # (tangent length of a corner rounded with a radius of 1.1 m)
	var pts: Array = [p0]
	for corner in [[c1, d_flat, d_slope], [c2, d_slope, d_flat]]:
		var c: Vector2 = corner[0]
		var a: Vector2 = c - (corner[1] as Vector2) * tl
		var b: Vector2 = c + (corner[2] as Vector2) * tl
		for k in range(0, 7):
			var t := float(k) / 6.0
			pts.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	pts.append(p3)
	var out: Array = []
	var u := 0.0
	for i in pts.size():
		if i > 0:
			u += (pts[i] as Vector2).distance_to(pts[i - 1])
		out.append([pts[i], u])
	return out


## The moving handrails, one surface a lane (the lane's two rails): a ribbon of rubber following the balustrade at the speed of the steps, patterned by shaders/escalator_handrail.gdshader
func _handrails_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var path := _rail_path()
	var sh := shader("escalator_handrail")
	for li in lanes.size():
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var idx := PackedInt32Array()
		for side in [-1.0, 1.0]:
			# the balustrade on that side of the lane, and the rail on the lane's side of it
			var zb: float = lane_z(li) + side * PITCH * 0.5
			var zr: float = zb - side * RAIL_OFF
			var base := verts.size()
			for i in path.size():
				var p: Vector2 = path[i][0]
				var u: float = path[i][1]
				var d: Vector2 = ((path[mini(i + 1, path.size() - 1)][0] as Vector2) - (path[maxi(i - 1, 0)][0] as Vector2)).normalized()
				var n := Vector2(-d.y, d.x)          # (up from the rail's direction)
				var top := p + n * RAIL_T * 0.5
				var bot := p - n * RAIL_T * 0.5
				# top-left, top-right, bottom-left, bottom-right (left: toward -z)
				for q in [[top, -1.0, Vector3(n.x, n.y, 0.0), 0.0], [top, 1.0, Vector3(n.x, n.y, 0.0), 1.0], [bot, -1.0, Vector3(0, 0, -1.0), 0.0], [bot, 1.0, Vector3(0, 0, 1.0), 1.0]]:
					var pos: Vector2 = q[0]
					verts.append(Vector3(pos.x, pos.y, zr + float(q[1]) * RAIL_W * 0.5))
					norms.append(q[2])
					uvs.append(Vector2(float(q[3]), u))
			for i in path.size() - 1:
				var r0 := base + i * 4
				var r1 := r0 + 4
				# (Godot's front faces are the clockwise ones) top, right side, left side
				idx.append_array(PackedInt32Array([r0, r1, r1 + 1, r0, r1 + 1, r0 + 1]))
				idx.append_array(PackedInt32Array([r0 + 1, r1 + 1, r1 + 3, r0 + 1, r1 + 3, r0 + 3]))
				idx.append_array(PackedInt32Array([r0, r1 + 2, r1, r0, r0 + 2, r1 + 2]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("speed", SPEED * float(lanes[li]))
		mesh.surface_set_material(li, m)
	return mesh


func _finish() -> void:
	var mats := {}
	for k in kit.surfaces.keys():
		if k.begins_with("esc_plate_"):
			var pm := ShaderMaterial.new()
			pm.shader = shader("escalator_plate")
			pm.set_shader_parameter("edge_x", PLATE if k.ends_with("top") else PLATE + run)
			pm.set_shader_parameter("side", 1.0 if k.ends_with("top") else -1.0)
			mats[k] = pm
		elif k.begins_with("flat:"):
			mats[k] = Mats.flat(Color.html(k.substr(5)), 0.4)
		elif k.begins_with("tex:"):
			var tp := "res://assets/textures/props/esc/%s.png" % k.substr(4).get_slice("@", 0)
			var tm := StandardMaterial3D.new()
			if ResourceLoader.exists(tp):
				tm.albedo_texture = load(tp)
			tm.roughness = 0.4
			tm.uv1_scale = Vector3(1.0 / float(k.get_slice("@", 1)), 1.0 / float(k.get_slice("@", 2)), 1.0)
			mats[k] = tm
		elif k.begins_with("poster:"):
			mats[k] = PosterKit._material(k.substr(7), PANEL_W - 0.032, PANEL_H - 0.032)
		else:
			mats[k] = Mats.get_mat(k)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build(mats)
	mi.name = "Mesh"
	add_child(mi)
	if not stairs and not Station.debug_off("escsteps"):          # (UG_OFF=escsteps: for A/B frame-time runs)
		var steps := MeshInstance3D.new()
		steps.mesh = _steps_mesh()
		steps.name = "Steps"
		steps.set_meta("shader_placed", true)          # (its vertices are not where they are drawn: audits that read the mesh skip it)
		steps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(steps)
	if not stairs:
		var rails := MeshInstance3D.new()
		rails.mesh = _handrails_mesh()
		rails.name = "Handrails"
		rails.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rails)
	var body := StaticBody3D.new()
	body.name = "Collision"
	for c in _cols:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = c[1]
		cs.shape = sh
		cs.position = c[0]
		body.add_child(cs)
	for pts in _slabs:
		var cs3 := CollisionShape3D.new()
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		cs3.shape = hull
		body.add_child(cs3)
	add_child(body)
	# moving tread bodies (one per lane)
	for li in lanes.size():
		var ab := AnimatableBody3D.new()
		ab.name = "Tread%d" % li
		ab.sync_to_physics = false
		var slope_len := run / cos(ANGLE)
		# short boxes rather than one 60 m slab: on a very long escalator the player used to sink 0.44 m into a single long tread collider
		var nseg := maxi(1, ceili(slope_len / TREAD_SEG))
		var seg := slope_len / float(nseg)
		for si in nseg:
			var cs2 := CollisionShape3D.new()
			var sh2 := BoxShape3D.new()
			sh2.size = Vector3(seg + 0.04, 0.4, LANE_W)
			cs2.shape = sh2
			cs2.position = Vector3(-slope_len * 0.5 + seg * (si + 0.5), 0, 0)
			ab.add_child(cs2)
		ab.position = Vector3(PLATE + run * 0.5, -rise * 0.5, lane_z(li)) + Basis(Vector3(0, 0, 1), -ANGLE) * Vector3(0, -0.2, 0)
		ab.rotation = Vector3(0, 0, -ANGLE)
		add_child(ab)
		_bodies.append([ab, lanes[li]])
	# lights along the shaft ceiling
	var n := maxi(2, int(length / 6.0))
	if stairs:
		pass
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
