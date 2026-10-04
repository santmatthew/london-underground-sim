extends Node3D
## Which way do the escalator steps visibly move? Two frames of one lane 0.3 s apart -> build/esc_dir_A.png / esc_dir_B.png (the lane's direction is printed)
func _ready() -> void:
	var lane := 0
	var ei := 1
	var from := "top"
	var at := Vector3(2.0, 2.2, 0.0)
	var look := Vector3(-1.0, 0.0, 0.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lane="): lane = int(a.substr(7))
		if a.begins_with("--ei="): ei = int(a.substr(5))
		if a.begins_with("--from="): from = a.substr(7)          # top (default) / bottom: the camera at the foot, looking up the slope (the risers show)
		if a.begins_with("--at="):                              # x along the shaft, height above the tread line, as a fraction of the length: --at=0.5,1.2 (looking down the slope)
			var q := a.substr(5).split(",")
			at = Vector3(float(q[0]), float(q[1]), 0.0)
	Timetable.build(1)
	Clock.set_time(11.0 * 3600.0)
	add_child(Env.make(0))
	var plan := StationPlan.for_station(Net.name_to_idx["Oxford Circus"])
	var st := Station.new()
	add_child(st)
	st.build(plan)
	var esc := st.escalators[ei] as Escalator
	print("ESCDIR lane %d moves %s (lanes = %s)" % [lane, "DOWN" if int(esc.lanes[lane]) > 0 else "UP", str(esc.lanes)])
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 60
	var lz := plan.esc_lane_z(ei, lane)
	# above the lane near the top, looking down the slope: farther down the slope is nearer the vanishing point (higher in the image)
	if from == "bottom":
		cam.position = plan.esc_point(ei, Vector3(esc.length - 2.0, -esc.rise + 2.0, lz))
		cam.look_at(plan.esc_point(ei, Vector3(esc.length * 0.45, -esc.rise * 0.45 + 0.3, lz)))
	elif from == "side":
		# half way down, over the lane next to this one, looking across at the steps' profile
		var xm := esc.length * at.x
		cam.position = plan.esc_point(ei, Vector3(xm, -(xm - Escalator.PLATE) * tan(Escalator.ANGLE) + at.y, lz + 0.01))
		cam.look_at(plan.esc_point(ei, Vector3(xm + 1.5, -(xm + 1.5 - Escalator.PLATE) * tan(Escalator.ANGLE) + 0.1, lz)))
	else:
		cam.position = plan.esc_point(ei, Vector3(2.0, 2.2, lz))
		cam.look_at(plan.esc_point(ei, Vector3(esc.length * 0.6, -esc.rise * 0.6 + 0.4, lz)))
	for i in 20: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/esc_dir_A.png")
	await get_tree().create_timer(float(OS.get_environment("ESC_DT") if OS.get_environment("ESC_DT") != "" else "0.3")).timeout
	get_viewport().get_texture().get_image().save_png("res://build/esc_dir_B.png")
	get_tree().quit()
