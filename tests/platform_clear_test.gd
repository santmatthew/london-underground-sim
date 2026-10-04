extends Node
## Two trains are never in the same platform at once. For every platform face of the whole timetable, the trains of consecutive visits are moved the way TrainService moves them - a train that is not starting its
## run comes in from behind, exists from APPROACH_S + 3 s before its arrival, stands, and leaves ahead; one that starts its run appears at rest at its `arr` and sets off the other way (a terminus); trains go
## when they are 280 m out or AFTER_S after leaving - and the nose of one must stay clear of the tail of the other by at least 4 m whenever both exist (sampled every half second). Independent of Timetable.min_headway
## (which has to satisfy this); a count of how long the delays it causes are is printed.
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


## centre of a train along the platform's axis (+ = the way arrivals travel) at time t, and whether it exists
func _pos(arr: float, dep: float, origin: bool, t: float) -> Array:
	if origin:
		if t < arr or t > dep + TrainService.AFTER_S:
			return [0.0, false]
		var x := 0.0 if t < dep else -TrainService.r_dep(t - dep)
		return [x, not (t > dep and absf(x) > 280.0)]
	if t < arr - TrainService.APPROACH_S - 3.0 or t > dep + TrainService.AFTER_S:
		return [0.0, false]
	var x2 := -TrainService.r_app(arr - t) if t < arr else (0.0 if t < dep else TrainService.r_dep(t - dep))
	return [x2, not (t > dep and absf(x2) > 280.0)]


func run():
	Timetable.build(1)
	var pairs := 0
	var bad := 0
	var worst := 1e9
	var worst_at := ""
	var overlaps := 0
	var late := 0
	var hops := 0
	for gp in Timetable.plat_station.size():
		var last := {}          # face -> [arr, dep, length, origin]
		for vv in Timetable.visits_between(gp, 4.0 * 3600.0, 26.0 * 3600.0):
			var r: int = vv["run"]
			var k: int = vv["k"]
			var fno: int = (Timetable.run_face[r] as PackedByteArray)[k]
			var len_f := Timetable.train_len(Timetable.run_line[r])
			var arr: float = vv["arr"]
			var dep: float = vv["dep"]
			var org: bool = vv["origin"]
			if last.has(fno):
				var lv: Array = last[fno]
				pairs += 1
				if arr < float(lv[1]):
					overlaps += 1
				var need: float = (float(lv[2]) + len_f) * 0.5
				var minsep := 1e9
				var t: float = minf(arr, float(lv[1])) - 40.0
				while t <= float(lv[1]) + TrainService.AFTER_S + 5.0:
					var pl := _pos(float(lv[0]), float(lv[1]), bool(lv[3]), t)
					var pf := _pos(arr, dep, org, t)
					if pl[1] and pf[1]:
						minsep = minf(minsep, absf(float(pl[0]) - float(pf[0])) - need)
					t += 0.5
				if minsep < 4.0:
					bad += 1
				if minsep < worst:
					worst = minsep
					worst_at = "%s %s, %s then run %d" % [Net.stations[Timetable.plat_station[gp]]["name"], Timetable.plat_pid[gp], Clock.fmt(float(lv[1]), true), r]
			last[fno] = [arr, dep, len_f, org]
	# how much the spacing costs: stops where a train arrives more than 40 s later than its running time says
	for rr in Timetable.run_arr.size():
		var arr_a: PackedFloat32Array = Timetable.run_arr[rr]
		var dep_a: PackedFloat32Array = Timetable.run_dep[rr]
		var svc_secs := Timetable._service_run_times(_svc_of(rr))
		for kk in range(1, arr_a.size()):
			hops += 1
			var seg := kk - 1 if int(Timetable.run_dir[rr]) == 0 else svc_secs.size() - kk
			var expect: float = svc_secs[clampi(seg, 0, svc_secs.size() - 1)]
			if arr_a[kk] - dep_a[kk - 1] > expect * 1.05 + 40.0:
				late += 1
	print("  info: %d consecutive visits of a face; closest nose to tail %.1f m (%s); %d of %d hops arrive more than 40 s later than running time (%.1f %%)" % [pairs, worst, worst_at, late, hops, 100.0 * float(late) / maxf(float(hops), 1.0)])
	check(pairs > 100000, "the whole day was checked (%d pairs)" % pairs)
	check(overlaps == 0, "no two visits of a face overlap in time (%d do)" % overlaps)
	check(bad == 0, "trains that exist together stay 4 m clear (%d of %d pairs do not)" % [bad, pairs])
	print("OK" if ok else "FAILED")


func _svc_of(rr: int) -> Dictionary:
	var lid: String = Timetable.run_line[rr]
	for svc in Net.lines[lid]["services"]:
		if svc["id"] == Timetable.run_svc[rr]:
			return svc
	return {}
