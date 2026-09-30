extends Node3D
## The station clocks and the platform indicators follow the simulation clock.
func run():
	Timetable.build(1)
	Clock.set_time(9.0 * 3600.0 + 5.0 * 60.0 + 7.0)
	Clock.running = false
	add_child(Env.make(0))
	var idx: int = Net.name_to_idx["Oxford Circus"]
	var plan := StationPlan.for_station(idx)
	var st := Station.new()
	add_child(st)
	st.build(plan)
	for i in 4: await get_tree().process_frame
	var tk := st.get_node_or_null("Clocks") as StationClocks
	print("analogue clocks registered: ", tk._clocks.size() if tk else 0)
	var ok := true
	for t in [9.0 * 3600.0 + 5.0 * 60.0 + 7.0, 15.0 * 3600.0 + 30.0 * 60.0]:
		Clock.set_time(t)
		await get_tree().process_frame
		await get_tree().process_frame
		var a := StationClocks.angles(t)
		var h: Node3D = tk._clocks[0][0]
		var m: Node3D = tk._clocks[0][1]
		var good := absf(h.rotation.z - a.x) < 0.001 and absf(m.rotation.z - a.y) < 0.001
		ok = ok and good
		print("t=%s hour hand %.3f (want %.3f) minute hand %.3f (want %.3f) %s" % [Clock.fmt(t, true), h.rotation.z, a.x, m.rotation.z, a.y, "ok" if good else "WRONG"])
	var gp: int = Timetable.plat_index[idx].values()[0]
	var ind := Signs.indicator(gp, 2.0)
	add_child(ind)
	await get_tree().process_frame
	await get_tree().process_frame
	for l in ind.labels:
		print("indicator row: [", (l as Label3D).text, "]")
	print("OK" if ok else "FAILED")
