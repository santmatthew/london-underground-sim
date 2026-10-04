extends Node
## Two trains are never in the same platform at once: for every platform face of the whole timetable, between one train leaving and the next arriving, the nose of the one coming in stays at least 6 m behind
## the tail of the one that leaves (positions from TrainService.r_dep / r_app, the movement the trains are really given), sampled every half second; and no two visits of a face overlap in time.
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	Timetable.build(1)
	var pairs := 0
	var bad := 0
	var worst := 1e9
	var worst_at := ""
	var overlaps := 0
	for gp in Timetable.plat_station.size():
		var last := {}          # face -> [arr, dep, length, origin]
		for vv in Timetable.visits_between(gp, 4.0 * 3600.0, 26.0 * 3600.0):
			var r: int = vv["run"]
			var k: int = vv["k"]
			var fno: int = (Timetable.run_face[r] as PackedByteArray)[k]
			var lid: String = Timetable.run_line[r]
			var len_f := Timetable.train_len(lid)
			var arr: float = vv["arr"]
			var dep: float = vv["dep"]
			if last.has(fno):
				var lv: Array = last[fno]
				pairs += 1
				if arr < float(lv[1]):
					overlaps += 1
				# separation between the leader's tail and the follower's nose over time
				var t := float(lv[1])
				var minsep := 1e9
				while t <= arr:
					var lead_x := TrainService.r_dep(t - float(lv[1]))
					var foll_x := 0.0 if (k == 0 and t >= arr) else (-TrainService.r_app(arr - t))
					if k == 0:
						foll_x = 0.0 if t >= arr else -1e9           # (a train that starts its run is not there until it appears)
					if foll_x > -1e8:
						minsep = minf(minsep, (lead_x - float(lv[2]) * 0.5) - (foll_x + len_f * 0.5))
					t += 0.5
				if k == 0:
					minsep = (TrainService.r_dep(arr - float(lv[1])) - float(lv[2]) * 0.5) - len_f * 0.5
				if minsep < 6.0:
					bad += 1
				if minsep < worst:
					worst = minsep
					worst_at = "%s %s, %s then run %d" % [Net.stations[Timetable.plat_station[gp]]["name"], Timetable.plat_pid[gp], Clock.fmt(float(lv[1]), true), r]
			last[fno] = [arr, dep, len_f]
	print("  info: %d consecutive visits of a face, the closest approach of nose to tail: %.1f m (%s)" % [pairs, worst, worst_at])
	check(overlaps == 0, "no two visits of a face overlap in time (%d do)" % overlaps)
	check(bad == 0, "the nose never comes within 6 m of the tail (%d of %d pairs do)" % [bad, pairs])
	print("OK" if ok else "FAILED")
