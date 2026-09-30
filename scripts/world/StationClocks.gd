class_name StationClocks
extends Node
## Keeps a station's analogue clocks on the simulation time: every clock prop has hand_h / hand_m / hand_s nodes pivoting at the dial centre
## (rotation about Z, positive = clockwise seen from the front), and this node sets them from Clock.now every frame.

var _clocks: Array = []        # [hour hand, minute hand, second hand (or null)]


static func register(station: Node, clock: Node3D) -> void:
	if clock == null:
		return
	var ticker := station.get_node_or_null("Clocks") as StationClocks
	if ticker == null:
		ticker = StationClocks.new()
		ticker.name = "Clocks"
		station.add_child(ticker)
	ticker.add(clock)


func add(clock: Node3D) -> void:
	var h := clock.find_child("hand_h", true, false) as Node3D
	var m := clock.find_child("hand_m", true, false) as Node3D
	if h == null or m == null:
		return
	var s := clock.find_child("hand_s", true, false) as Node3D
	_clocks.append([h, m, s])
	_apply(_clocks[-1], Clock.now)


## hand angles (radians, clockwise from 12) for a time in seconds since midnight
static func angles(t: float) -> Vector3:
	var tt := fposmod(t, 43200.0)
	return Vector3(TAU * tt / 43200.0, TAU * fposmod(tt, 3600.0) / 3600.0, TAU * fposmod(tt, 60.0) / 60.0)


func _apply(c: Array, t: float) -> void:
	var a := angles(t)
	(c[0] as Node3D).rotation.z = a.x
	(c[1] as Node3D).rotation.z = a.y
	if c[2] != null:
		(c[2] as Node3D).rotation.z = a.z


func _process(_delta: float) -> void:
	var t: float = Clock.now
	for c in _clocks:
		_apply(c, t)
