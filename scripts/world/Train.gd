class_name Train
extends Node3D
## A whole train made of Blender-generated cars. Local frame: X along the train (front = +X), origin at the train centre, rail-head height.
## Placed inside a PlatformModule at (0, RAIL_Y, track_z); rotated by PI about Y when it travels towards -x.

const CarUtil = preload("res://assets/models/train/train_car_util.gd")
const PITCH := {"deep": [16.64, 17.14], "ss": [18.5, 19.5]}       # mid-mid, cab-mid
const CAR_SCENES := {
	"deep_mid": "res://assets/models/train/tube_car_deep_mid.glb", "deep_cab": "res://assets/models/train/tube_car_deep_cab.glb",
	"ss_mid": "res://assets/models/train/tube_car_ss_mid.glb", "ss_cab": "res://assets/models/train/tube_car_ss_cab.glb",
}
const CAR_LEN := {"deep_mid": 16.0, "deep_cab": 16.5, "ss_mid": 18.0, "ss_cab": 19.0}
const DOOR_X := {  # door centre x per car type (README)
	"deep_mid": [-5.0, 0.0, 5.0], "deep_cab": [-5.4, -0.9, 3.6], "ss_mid": [-6.6, -2.2, 2.2, 6.6], "ss_cab": [-6.9, -2.5, 1.9],
}
static var _packed: Dictionary = {}


## which car family a line runs: the sub-surface lines and the Elizabeth line use the wide "ss" cars, the deep tubes the small "deep" ones
static func kind_of_line(lid: String) -> String:
	var g: String = Net.lines[lid]["group"]
	return "ss" if (g == "ss" or g == "elizabeth") else "deep"

var kind := "deep"
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
		var car: Node3D = scene_for(keys[i]).instantiate()
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
	add_child(front_light)


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
		body.position = Vector3(dx, floor_h - 0.04, local_side * (half_w + 0.1))
		add_child(body)
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
	var lp := to_local(p)
	if lp.y < 0.7 or lp.y > 3.2 or absf(lp.z) > 1.3:
		return false
	return absf(lp.x) < length * 0.5 + 0.2


func car_index_at(p: Vector3) -> int:
	var lp := to_local(p)
	var best := 0
	var bd := 1e9
	for i in cars.size():
		var d := absf(lp.x - car_x[i])
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
