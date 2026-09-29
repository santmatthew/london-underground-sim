extends Node3D
## Boards a real train and rides it. args: --shots=t1,t2,... (seconds after departure)  --speed=N
var st: Station
var player: Player
var ride: Ride
var shots: Array = []
var t_dep := 0.0
var shot_i := 0
var stage := "wait"
var pending_visit: Dictionary = {}
var elapsed_real := 0.0

func _ready() -> void:
	Timetable.build(3)
	var start := "Oxford Circus"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): 
			for x in a.substr(8).split(","): shots.append(float(x))
		if a.begins_with("--from="): start = a.substr(7)
	if shots.is_empty(): shots = [10, 40, 70]
	add_child(Env.make())
	var idx: int = Net.name_to_idx[start]
	var plan := StationPlan.for_station(idx)
	st = Station.new()
	add_child(st)
	st.build(plan)
	# pick a through train at the first face, board during its dwell
	var fk: String = plan.faces.keys()[0]
	var fc: Dictionary = plan.faces[fk]
	var gp: int = Timetable.plat_index[idx][fc["pid"]]
	var vs: Array = Timetable.visits_between(gp, 8.0 * 3600.0, 8.0 * 3600.0 + 900.0)
	var pick: Dictionary = {}
	for v0 in vs:
		if (Timetable.run_face[v0["run"]] as PackedByteArray)[v0["k"]] == fc["face_no"] and not v0["origin"] and not v0["final"] and v0["dep"] - v0["arr"] > 20.0:
			pick = v0; break
	pending_visit = pick
	Clock.set_time(pick["arr"] + 8.0)
	Clock.running = true
	Clock.time_scale = 1.0
	player = Player.new()
	add_child(player)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	st.trains.setup(st, player)
	st.trains.doors_closing.connect(_on_doors_closing)
	# spawn the train immediately
	st.trains._process(0.6)
	st.trains._process(0.1)
	var vkey := "%d:%d" % [pick["run"], pick["k"]]
	var v: Dictionary = st.trains.visits[vkey]
	var train: Train = v["train"]
	# stand in the middle of car 3 near the door
	var car: Node3D = train.cars[min(2, train.cars.size() - 1)]
	var stand := car.get_node_or_null("stand_00")
	var wp: Vector3 = (stand as Node3D).global_position if stand else car.global_position + Vector3(0, 1, 0)
	player.global_position = wp + Vector3(0, 0.2, 0)
	print("boarding run ", pick["run"], " ", Timetable.run_name(pick["run"]), " dep in ", pick["dep"] - Clock.now)

func _on_doors_closing(v: Dictionary) -> void:
	if stage != "wait": return
	var train: Train = v["train"]
	print("doors closing; player aboard: ", train.contains_world_point(player.global_position))
	if train.contains_world_point(player.global_position):
		stage = "ride"
		ride = Ride.new()
		add_child(ride)
		ride.arrived.connect(func(s, k): print("ARRIVED at ", s.plan.name); stage = "arrived"; t_arrived = Clock.now)
		ride.start(self, train, v["info"]["run"], v["info"]["k"], st, player.global_position)
		t_dep = ride.t_dep
		print("ride: dist ", ride.dist, " v ", ride.v_cruise, " T ", ride.t_arr - ride.t_dep)

var t_arrived := 0.0
func _process(delta: float) -> void:
	elapsed_real += delta
	if stage == "wait":
		Clock.time_scale = 4.0 if Clock.now < pending_visit["dep"] - 8.0 else 1.0
	if stage == "ride" or stage == "arrived":
		Clock.time_scale = 1.0
		var tt := Clock.now - t_dep
		if shot_i < shots.size() and tt >= shots[shot_i]:
			var cam_pos := player.global_position
			get_viewport().get_texture().get_image().save_png("res://build/shot_ride_%d.png" % int(shots[shot_i]))
			print("shot at ", int(tt), " phase ", ride.phase, " speed ", snappedf(ride.speed_now, 0.1), " s ", snappedf(ride.s_now, 1.0), "/", snappedf(ride.dist, 1.0))
			shot_i += 1
		if shot_i >= shots.size() or elapsed_real > 200.0:
			get_tree().quit()
	if elapsed_real > 200.0:
		print("timeout stage=", stage)
		get_tree().quit()
