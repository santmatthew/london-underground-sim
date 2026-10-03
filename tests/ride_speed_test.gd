extends Node
## Over every scheduled hop between two stops: the track length the ride uses (real, from line_geometry.json, else the straight-line estimate), the cruise speed that fits the timetable, and how many hops are
## infeasible or clamped, compared with the estimate the rides used before the geometry was known.
const A_ACC := 1.1
const A_DEC := 1.0


func _cruise(dist: float, T: float) -> float:
	var k := 1.0 / (2.0 * A_ACC) + 1.0 / (2.0 * A_DEC)
	var disc := T * T - 4.0 * dist * k
	if disc < 0.0:
		return -1.0
	return (T - sqrt(disc)) / (2.0 * k)


func run():
	Timetable.build(9)
	var seen := {}
	var n := 0
	var real := 0
	var inf_real := 0
	var inf_est := 0
	var fast_real := 0
	var fast_est := 0
	var ratio_sum := 0.0
	var worst: Array = []
	for r in Timetable.run_stops.size():
		var stops: PackedInt32Array = Timetable.run_stops[r]
		var arr: PackedFloat32Array = Timetable.run_arr[r]
		var dep: PackedFloat32Array = Timetable.run_dep[r]
		for k in stops.size() - 1:
			var key := "%d>%d" % [stops[k], stops[k + 1]]
			if seen.has(key):
				continue
			seen[key] = true
			var T: float = arr[k + 1] - dep[k]
			if T < 20.0:
				continue
			var est := maxf(300.0, Net.dist_km(stops[k], stops[k + 1]) * 1150.0)
			var prof: Array = TrackPath.profile(Net.station_ids[stops[k]], Net.station_ids[stops[k + 1]])
			n += 1
			var d := est
			if not prof.is_empty():
				real += 1
				d = clampf(float(prof[0]), maxf(250.0, est * 0.7), est * 1.6)
				ratio_sum += d / est
			var v_r := _cruise(d, T)
			var v_e := _cruise(est, T)
			if v_r < 0.0:
				inf_real += 1
			if v_e < 0.0:
				inf_est += 1
			if v_r > 24.0:
				fast_real += 1
				worst.append([v_r, Net.station_name(stops[k]), Net.station_name(stops[k + 1]), d, T])
			if v_e > 24.0:
				fast_est += 1
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("%d distinct hops, %d with real track geometry (mean real/estimate %.2f)" % [n, real, ratio_sum / maxf(real, 1)])
	print("infeasible: %d with the real lengths, %d with the estimate; cruise over 24 m/s (86 km/h): %d real, %d estimate" % [inf_real, inf_est, fast_real, fast_est])
	for w in worst.slice(0, 8):
		print("   %.1f m/s  %s -> %s  %.0f m in %.0f s" % [w[0], w[1], w[2], w[3], w[4]])
