class_name Train
extends Node3D
## A whole train made of Blender-generated cars. Local frame: X along the train (front = +X), origin at the train centre, rail-head height.
## Placed inside a PlatformModule at (0, RAIL_Y, track_z); rotated by PI about Y when it travels towards -x.

const CarUtil = preload("res://assets/models/train/train_car_util.gd")
const PITCH := {"deep": [16.64, 17.14], "ss": [18.5, 19.5]}       # mid-mid, cab-mid
const CAR_SCENES := {
	"deep_mid": "res://assets/models/train/tube_car_deep_mid.glb", "deep_cab": "res://assets/models/train/tube_car_deep_cab.glb",
	"ss_mid": "res://assets/models/train/tube_car_ss_mid.glb", "ss_cab": "res://assets/models/train/tube_car_ss_cab.glb",
	"deep72_mid": "res://assets/models/train/tube_car_deep72_mid.glb", "deep72_cab": "res://assets/models/train/tube_car_deep72_cab.glb",     # the 1972 / 1973 stock: mixed seating, boxy body
	"deep92_mid": "res://assets/models/train/tube_car_deep92_mid.glb", "deep92_cab": "res://assets/models/train/tube_car_deep92_cab.glb",     # the 1992 stock: rounded body and nose
}
const CAR_LEN := {"deep_mid": 16.0, "deep_cab": 16.5, "ss_mid": 18.0, "ss_cab": 19.0}
const DOOR_X := {  # door centre x per car type (README)
	"deep_mid": [-5.0, 0.0, 5.0], "deep_cab": [-5.4, -0.9, 3.6], "ss_mid": [-6.6, -2.2, 2.2, 6.6], "ss_cab": [-6.9, -2.5, 1.9],
}
static var _packed: Dictionary = {}
## the line's rolling stock where it is not the family's default: the Bakerloo's 1972 and the Piccadilly's 1973 stock have transverse seating bays at the car ends and a boxy body, the Central's and the Waterloo & City's
## 1992 stock a rounded one (all the size of the other tubes' cars)
const STOCK_OF_LINE := {"bakerloo": "deep72", "piccadilly": "deep72", "central": "deep92", "waterloo-city": "deep92"}


## which car model family (a key prefix of CAR_SCENES) a line runs
static func stock_of_line(lid: String) -> String:
	return STOCK_OF_LINE.get(lid, kind_of_line(lid))


## which car family a line runs: the sub-surface lines and the Elizabeth line use the wide "ss" cars, the deep tubes the small "deep" ones
static func kind_of_line(lid: String) -> String:
	var g: String = Net.lines[lid]["group"]
	return "ss" if (g == "ss" or g == "elizabeth") else "deep"

var kind := "deep"
var stock := "deep"             # the model family of the cars (kind, or deep72)
var n_cars := 6
var line_id := ""
var run := -1
var length := 0.0
var cars: Array = []
var car_x: Array = []
var facing := 1                 # +1: front car points +x, -1: rotated
var platform_side := 1.0        # sign of world z of the platform relative to this track
var door_side := "R"
var doors_open := false
var gap_plates: Array = []
var _busy_tween: Tween
var front_light: SpotLight3D
var bend: Bend = null            # the platform the train stands on is curved: the cars follow the arc (place)
var track_z := 0.0               # module frame, design space: z of the track the train runs on (curved platforms)
var edge_z := 0.0                # ... and of the platform edge beside it (0: unknown)
var _shift := PackedFloat32Array()      # per car: how far it was moved away from the platform to keep a gap on a curve (place), kept while the train rides on
const MIN_GAP := 0.07            # the least gap a car's side may have to the platform edge on a curve (m)
var design_x := 0.0              # module frame, design space: x of the middle of the train
var _placed_bent := false        # place() has put the cars on the curve at design_x
var _articulated := false        # the cars have been placed along a curve (place / follow_path): they are not in a straight line


## Start loading the four car models in the background (about 0.8 s each if loaded on the spot, which is what a station's first train used to cost in one frame)
static func preload_async() -> void:
	for k in CAR_SCENES:
		ResourceLoader.load_threaded_request(CAR_SCENES[k])


static func scene_for(key: String) -> PackedScene:
	if not _packed.has(key):
		_packed[key] = load(CAR_SCENES[key])
	return _packed[key]


func build(p_kind: String, p_cars: int, p_line: String, livery: Color) -> void:
	kind = p_kind
	n_cars = maxi(3, p_cars)
	line_id = p_line
	var pm: Array = PITCH[kind]
	stock = stock_of_line(p_line) if Net.lines.has(p_line) else kind
	# lay out cars: front cab, mids, rear cab
	var keys: Array = []
	for i in n_cars:
		keys.append(kind + ("_cab" if (i == 0 or i == n_cars - 1) else "_mid"))
	var xs: Array = []
	var x := 0.0
	for i in n_cars:
		if i > 0:
			x -= pm[1] if (i == 1 or i == n_cars - 1) else pm[0]
		xs.append(x)
	length = -x + CAR_LEN[keys[0]] * 0.5 + CAR_LEN[keys[n_cars - 1]] * 0.5
	var shift: float = -(float(xs[0]) + float(xs[n_cars - 1])) * 0.5
	for i in n_cars:
		var car: Node3D = scene_for(stock + (("_cab" if (i == 0 or i == n_cars - 1) else "_mid"))).instantiate()
		car.name = "Car%d" % i
		car.position.x = xs[i] + shift
		if i == n_cars - 1:
			car.rotation.y = PI
		add_child(car)
		CarUtil.set_livery(car, livery)
		for sm in car.find_children("seat_*", "Node3D", true, false):
			sm.add_to_group("seat")
		CarUtil.add_interior_lights(car, 0.9, 5.0, 3)
		CarUtil.set_lod_ranges(car, 40.0, 100.0)
		cars.append(car)
		car_x.append(xs[i] + shift)
		for did in CarUtil.door_ids(car):
			CarUtil.set_door_blocked(car, did, true)
	# headlight for the front cab
	front_light = SpotLight3D.new()
	front_light.position = Vector3(length * 0.5 + 0.2, 1.2, 0.0)
	front_light.rotation.y = -PI * 0.5           # -z of the light points to +x
	front_light.spot_range = 90.0
	front_light.spot_angle = 22.0
	front_light.light_energy = 3.0
	front_light.light_color = Color(1.0, 0.95, 0.85)
	front_light.shadow_enabled = false
	front_light.position = Vector3(length * 0.5 + 0.2 - float(car_x[0]), 1.2, 0.0)
	(cars[0] as Node3D).add_child(front_light)         # (the cars swing round curves: the light goes with the front one)


## A moving train passes through walkways that share its tunnel line (landings/corridors west of the platform): its bodies must only be
## solid while it stands at the platform. Layers are remembered so they can be restored.
func set_solid(on: bool) -> void:
	if get_meta("solid", true) == on:
		return
	set_meta("solid", on)
	for n in find_children("*", "CollisionObject3D", true, false):
		var co := n as CollisionObject3D
		if not co.has_meta("orig_layer"):
			co.set_meta("orig_layer", co.collision_layer)
		co.collision_layer = int(co.get_meta("orig_layer")) if on else 0


## puts the middle of the train at x along its platform (module frame, design space). On a curved platform the train takes the pose the track has there and every car sits on the arc.
func place(x: float) -> void:
	if bend == null:
		design_x = x
		if _articulated:
			straighten()
		position.x = x
		return
	if x == design_x and _placed_bent:
		return                                    # (standing at the platform: nothing to do)
	design_x = x
	_placed_bent = true
	_shift.resize(cars.size())
	var base := 0.0 if facing > 0 else PI
	transform = bend.pose(x, position.y, track_z) * Transform3D(Basis(Vector3.UP, base), Vector3.ZERO)
	var inv := transform.affine_inverse()
	for i in cars.size():
		var half := _bogie_half(i)
		var xi := float(car_x[i])
		var f := bend.map(Vector3(bend.advance_x(x, float(facing) * (xi + half), track_z), position.y, track_z))
		var r := bend.map(Vector3(bend.advance_x(x, float(facing) * (xi - half), track_z), position.y, track_z))
		var p := _bogie_pose(f, r)
		var d := _clearance_deficit(p, i)
		_shift[i] = d
		if d > 0.0:
			p.origin += p.basis * Vector3(0.0, 0.0, -_local_side() * d)          # (a car whose end would swing into the platform edge stands a little off the rail centre)
		var t := inv * p
		if i == cars.size() - 1:
			t.basis = t.basis * Basis(Vector3.UP, PI)
		(cars[i] as Node3D).transform = t


func _local_side() -> float:
	return platform_side * (1.0 if facing > 0 else -1.0)


## how much a car at pose p (module frame) must move away from the platform to keep MIN_GAP at its middle and at both ends: a wide car on a tight curve swings into the edge on the outside of the bend
func _clearance_deficit(p: Transform3D, i: int) -> float:
	if edge_z == 0.0 or bend == null:
		return 0.0
	var key := kind + ("_cab" if (i == 0 or i == cars.size() - 1) else "_mid")
	var half_len := float(CAR_LEN[key]) * 0.5
	var half_w := 1.31 if kind == "deep" else 1.5
	var sg := signf(track_z)
	var worst := 9.0
	for ex in [-half_len, 0.0, half_len]:
		var d := bend.unmap(p * Vector3(ex, 0.0, _local_side() * half_w))
		worst = minf(worst, sg * (d.z - edge_z))
	return maxf(0.0, MIN_GAP - worst)


## half the distance between the bogie centres of car i: a car's bogies sit on the rails, so its middle lies inside the curve and its ends swing outside it
func _bogie_half(i: int) -> float:
	var key := kind + ("_cab" if (i == 0 or i == cars.size() - 1) else "_mid")
	return float(CAR_LEN[key]) * 0.34


## the pose of a car whose front bogie is at f and rear bogie at r (module / ride frame): in the middle, pointing from one to the other
static func _bogie_pose(f: Vector3, r: Vector3) -> Transform3D:
	var d := f - r
	return Transform3D(Basis(Vector3.UP, atan2(-d.z, d.x)), (f + r) * 0.5)


## the pose of car i on the track `path` of a ride when the middle of the train is at path distance `s_c`: in the platform-level frame of the path, on the bogies (and moved away from the platform edge
## by the same shift it had at the station)
func car_pose_on_path(path: TrackPath, i: int, s_c: float) -> Transform3D:
	var half := _bogie_half(i)
	var f := path.pose(s_c + float(car_x[i]) + half).origin
	var r := path.pose(s_c + float(car_x[i]) - half).origin
	var p := _bogie_pose(f, r)
	if i < _shift.size() and _shift[i] > 0.0:
		p.origin += p.basis * Vector3(0.0, 0.0, -_local_side() * _shift[i])
	return p


## the cars follow the track `path` of a ride: `world` is where the path's frame is in the world (Ride keeps the player's car fixed, so this moves), s_c the path distance of the train's middle.
## The train's own node goes to the middle of the train, the cars to their places round it.
func follow_path(path: TrackPath, s_c: float, world: Transform3D) -> void:
	_articulated = not path.is_straight()
	var rail := Transform3D(Basis.IDENTITY, Vector3(0.0, PlatformModule.RAIL_Y, 0.0))
	var centre := path.pose(s_c) * rail
	global_transform = world * centre
	var inv := centre.affine_inverse()
	for i in cars.size():
		var t := inv * (car_pose_on_path(path, i, s_c) * rail)
		if i == cars.size() - 1:
			t.basis = t.basis * Basis(Vector3.UP, PI)
		(cars[i] as Node3D).transform = t


## the car a world point belongs to: the one whose walkable box holds it, else the nearest
func car_containing(p: Vector3) -> int:
	for i in cars.size():
		var key := kind + ("_cab" if (i == 0 or i == cars.size() - 1) else "_mid")
		var half := float(CAR_LEN[key]) * 0.5 + (0.2 if (i == 0 or i == cars.size() - 1) else 0.8)
		var lp := (cars[i] as Node3D).to_local(p)
		if lp.y >= 0.0 and lp.y <= 3.4 and absf(lp.z) <= 1.6 and absf(lp.x) < half:
			return i
	return car_index_at(p)


## the cars back in a straight line along the train
func straighten() -> void:
	_articulated = false
	_placed_bent = false
	for i in cars.size():
		var c := cars[i] as Node3D
		c.position = Vector3(float(car_x[i]), 0.0, 0.0)
		c.rotation = Vector3(0.0, PI if i == cars.size() - 1 else 0.0, 0.0)


## design x of the middle of car i: the cars stand a fixed distance apart ALONG the track, which on a curve is not the same as along x
func car_design_x(i: int) -> float:
	if bend == null:
		return design_x + float(facing) * float(car_x[i])
	return bend.advance_x(design_x, float(facing) * float(car_x[i]), track_z)


## design x (module frame, along the straight platform of the plan) of the door at train-frame x `dx`: on a curve the cars stand a fixed distance apart along the track, which is not the same along x
func door_design_x(dx: float) -> float:
	if bend == null:
		return design_x + float(facing) * dx
	return bend.advance_x(design_x, float(facing) * dx, track_z)


## where the point (x, y, z) of the train's frame is in the world: the same as to_global for a straight train, but on a curve the car that holds x is turned off the train's axis, so the point is taken in that car's frame
func slot_global(x: float, y := 0.0, z := 0.0) -> Vector3:
	if bend == null and not _articulated:
		return to_global(Vector3(x, y, z))
	var i := car_index_at_x(x)
	var flip := -1.0 if i == cars.size() - 1 else 1.0
	return (cars[i] as Node3D).to_global(Vector3((x - float(car_x[i])) * flip, y, z * flip))


## the train-frame x of the world point p (for a curved train: along the car nearest to it)
func train_x_of(p: Vector3) -> float:
	if bend == null and not _articulated:
		return to_local(p).x
	var i := car_index_at(p)
	var flip := -1.0 if i == cars.size() - 1 else 1.0
	return float(car_x[i]) + flip * (cars[i] as Node3D).to_local(p).x


func door_world(dx: float) -> Vector3:
	return slot_global(dx)


func car_index_at_x(x: float) -> int:
	var best := 0
	var bd := 1e9
	for i in cars.size():
		var d := absf(x - float(car_x[i]))
		if d < bd:
			bd = d
			best = i
	return best


func setup_orientation(p_facing: int, p_platform_side: float) -> void:
	facing = p_facing
	platform_side = p_platform_side
	rotation.y = 0.0 if facing > 0 else PI
	# R doors are on +Z of the train; with yaw PI they point to world -Z
	var world_right_sign := 1.0 if facing > 0 else -1.0
	door_side = "R" if platform_side * world_right_sign > 0.0 else "L"
	front_light.visible = true
	_make_gap_plates()


## door centres (train-local x) on the platform side, all cars
## door x positions (train frame, centre of the train = 0) of a train of n cars of `kind`; the same maths as build()/door_positions(), without building the cars
static func door_positions_for(p_kind: String, p_cars: int) -> Array:
	var n := maxi(3, p_cars)
	var pm: Array = PITCH[p_kind]
	var xs: Array = []
	var x := 0.0
	for i in n:
		if i > 0:
			x -= pm[1] if (i == 1 or i == n - 1) else pm[0]
		xs.append(x)
	var shift: float = -(float(xs[0]) + float(xs[n - 1])) * 0.5
	var out: Array = []
	for i in n:
		var key: String = p_kind + ("_cab" if (i == 0 or i == n - 1) else "_mid")
		var flip := -1.0 if i == n - 1 else 1.0
		for dx in DOOR_X[key]:
			out.append(float(xs[i]) + shift + float(dx) * flip)
	return out


func door_positions() -> Array:
	var out: Array = []
	for i in n_cars:
		var key: String = kind + ("_cab" if (i == 0 or i == n_cars - 1) else "_mid")
		var flip := -1.0 if i == n_cars - 1 else 1.0
		for dx in DOOR_X[key]:
			# doors on the platform side of this car: the rear car is rotated, its R/L swap but the x positions mirror
			out.append(car_x[i] + dx * flip)
	return out


func _make_gap_plates() -> void:
	for g in gap_plates:
		g.queue_free()
	gap_plates.clear()
	var floor_h := 0.88 if kind == "deep" else 1.0
	var half_w := 1.31 if kind == "deep" else 1.5
	# platform side in the train's local z: world z sign * facing sign
	var local_side := platform_side * (1.0 if facing > 0 else -1.0)
	for dx in door_positions():
		var body := StaticBody3D.new()
		body.collision_layer = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(1.5, 0.08, 0.5)
		cs.shape = sh
		body.add_child(cs)
		# (a plate belongs to the car its door is in, so it swings with it round a curve; the rear car is turned half round)
		var ci := car_index_at_x(dx)
		var flip := -1.0 if ci == cars.size() - 1 else 1.0
		body.position = Vector3((dx - float(car_x[ci])) * flip, floor_h - 0.04, local_side * (half_w + 0.1) * flip)
		(cars[ci] as Node3D).add_child(body)
		gap_plates.append(body)


func set_doors(open: bool, duration := 1.6, stagger := 0.12) -> void:
	if open == doors_open:
		return
	doors_open = open
	if _busy_tween:
		_busy_tween.kill()
	for i in cars.size():
		var car: Node3D = cars[i]
		# platform side letter relative to this car (rear car is rotated)
		var side := door_side
		if i == cars.size() - 1:
			side = "L" if door_side == "R" else "R"
		CarUtil.tween_all_doors(car, open, side, duration, stagger)
		for did in CarUtil.door_ids(car):
			if did.begins_with(side):
				CarUtil.set_door_blocked(car, did, not open)
	for g in gap_plates:
		(g as StaticBody3D).collision_layer = 1 if open else 0


## is a world point inside any car's walkable interior (used to decide whether the player is aboard)
func contains_world_point(p: Vector3) -> bool:
	if bend == null and not _articulated:
		var lp := to_local(p)
		if lp.y < 0.7 or lp.y > 3.2 or absf(lp.z) > 1.3:
			return false
		return absf(lp.x) < length * 0.5 + 0.2
	# on a curve the cars stand off the train's axis: test each one in its own frame
	for i in cars.size():
		var half: float = float(CAR_LEN[kind + ("_cab" if (i == 0 or i == cars.size() - 1) else "_mid")]) * 0.5 + (0.2 if (i == 0 or i == cars.size() - 1) else 0.8)
		var lp2 := (cars[i] as Node3D).to_local(p)
		if lp2.y >= 0.7 and lp2.y <= 3.2 and absf(lp2.z) <= 1.3 and absf(lp2.x) < half:
			return true
	return false


func car_index_at(p: Vector3) -> int:
	var best := 0
	var bd := 1e9
	for i in cars.size():
		var d := (cars[i] as Node3D).global_position.distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func set_lights(on: bool) -> void:
	for c in cars:
		CarUtil.set_lights_lit(c, on)


## dot-matrix destination on the cab-front displays (rendered once into a texture)
func set_destination(text: String) -> void:
	for ci in [0, cars.size() - 1]:
		var car: Node3D = cars[ci]
		var vp := SubViewport.new()
		vp.size = Vector2i(512, 96)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		vp.disable_3d = true
		var bg := ColorRect.new()
		bg.color = Color(0.01, 0.01, 0.01)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		vp.add_child(bg)
		var l := Label.new()
		l.text = text.to_upper()
		l.add_theme_font_override("font", Signs.font_dot())
		l.add_theme_font_size_override("font_size", 54 if text.length() < 16 else 40)
		l.add_theme_color_override("font_color", Color(1.0, 0.62, 0.06))
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vp.add_child(l)
		add_child(vp)
		var tex := vp.get_texture()
		CarUtil.edit_material(car, "mat_dest_display", func(m: StandardMaterial3D):
			m.albedo_texture = tex
			m.emission_texture = tex
			m.emission_enabled = true
			m.emission_energy_multiplier = 1.6)


func set_linemap(line: String, direction: int) -> void:
	var path := "res://assets/textures/linemaps/%s_%d.png" % [line, clampi(direction, 0, 1)]
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	for car in cars:
		CarUtil.set_line_diagram(car, tex)
