extends Node
## Prints the visits of one platform face around a time: two trains in the same platform at once?  args --station=Leyton --pid=central:Eastbound --hour=9.6 --window=900
func run():
	var nm := "Leyton"
	var want := "central:Eastbound"
	var hour := 9.6
	var win := 900.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): nm = a.substr(10)
		if a.begins_with("--pid="): want = a.substr(6)
		if a.begins_with("--hour="): hour = float(a.substr(7))
		if a.begins_with("--window="): win = float(a.substr(9))
	Timetable.build(1)
	var plan := StationPlan.for_station(Net.name_to_idx[nm])
	var f: Dictionary = plan.faces[want + "#0"]
	var gp: int = Timetable.plat_index[plan.idx][f["pid"]]
	var t0 := hour * 3600.0
	var last_dep := -1e9
	var overlaps := 0
	for vv in Timetable.visits_between(gp, t0, t0 + win):
		var fno: int = (Timetable.run_face[vv["run"]] as PackedByteArray)[vv["k"]]
		print("  run %d stop %d face %d arr %s dep %s %s" % [vv["run"], vv["k"], fno, Clock.fmt(vv["arr"], true), Clock.fmt(vv["dep"], true), "OVERLAP" if vv["arr"] < last_dep - 0.5 else ""])
		if vv["arr"] < last_dep - 0.5:
			overlaps += 1
		last_dep = maxf(last_dep, vv["dep"])
	print("overlaps ", overlaps)
	print("OK")
