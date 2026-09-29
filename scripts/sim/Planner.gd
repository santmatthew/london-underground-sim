class_name Planner
extends RefCounted
## Earliest-arrival journey planner over the generated timetable + station walking graphs.
## Objective: be at the destination station's street exit as early as possible.

const BOARD_BUFFER := 6.0        # seconds to get onto the train once at the platform
const SAME_PLATFORM_RESET := 4.0


## start: {station:int, node:String}  ("hall_unpaid", "gate_out", "face:pid#f", ...); t0 seconds.
## Returns {ok, arrive, legs:[{run,line,from,to,dep,arr,pid_from,pid_to}], walk_start, walk_end}
static func plan(start_station: int, start_node: String, t0: float, dest_station: int, max_wait_horizon := 4.0 * 3600.0) -> Dictionary:
	var best := {"ok": false, "arrive": INF}
	var ready := {}          # gp -> earliest time ready to board
	var prev := {}           # gp -> {from_gp, run, k, j, arr, station}  (how we got to being ready at gp)
	var heap: Array = []     # [time, gp]
	var plan0 := StationPlan.for_station(start_station)
	var st: Dictionary = Net.stations[start_station]
	# start: walk to every platform of the start station
	for pid in st["platforms"]:
		var gp: int = Timetable.plat_index[start_station][pid]
		var w := 1e9
		for f in plan0.faces:
			if plan0.faces[f]["pid"] == pid:
				w = minf(w, plan0.walk_time(start_node, "face:" + f))
		if w >= 1e8:
			continue
		var t: float = t0 + w + BOARD_BUFFER
		ready[gp] = t
		prev[gp] = {"from": -1, "walk": w}
		_push(heap, t, gp)
	var best_total := INF
	var best_pred := {}
	var scanned := 0
	while heap.size() > 0:
		var top: Array = _pop(heap)
		var t: float = top[0]
		var gp: int = top[1]
		if t > ready.get(gp, INF) + 0.001:
			continue
		if t >= best_total:
			break
		scanned += 1
		var evs: PackedInt64Array = Timetable.events[gp]
		var i := _lower(evs, t)
		var seen := {}
		var count := 0
		while i < evs.size() and count < 45:
			var key := evs[i]
			i += 1
			count += 1
			var r := Timetable.ev_run(key)
			var k := Timetable.ev_stop(key)
			var stops: PackedInt32Array = Timetable.run_stops[r]
			if k >= stops.size() - 1:
				continue
			var tag: String = "%s/%d" % [Timetable.run_svc[r], Timetable.run_dir[r]]
			if seen.has(tag):
				continue
			seen[tag] = true
			var dep_t: float = Timetable.ev_time(key)
			if dep_t - t > max_wait_horizon:
				break
			var arr: PackedFloat32Array = Timetable.run_arr[r]
			var gps: PackedInt32Array = Timetable.run_plat[r]
			var faces: PackedByteArray = Timetable.run_face[r]
			for j in range(k + 1, stops.size()):
				var s_j: int = stops[j]
				var a_t: float = arr[j]
				if a_t >= best_total:
					break
				var gp_j: int = gps[j]
				var plan_j := StationPlan.for_station(s_j)
				var pid_j: String = Timetable.plat_pid[gp_j]
				var face_key := "%s#%d" % [pid_j, faces[j]]
				if s_j == dest_station:
					var exit_w := plan_j.time_face_to_exit(face_key) if plan_j.faces.has(face_key) else 60.0
					var total := a_t + exit_w
					if total < best_total:
						best_total = total
						best_pred = {"gp": gp, "run": r, "k": k, "j": j, "arr": a_t, "walk_end": exit_w}
					continue
				# transfer to every platform of the station
				for pid2 in Net.stations[s_j]["platforms"]:
					var q: int = Timetable.plat_index[s_j][pid2]
					var w2: float
					if q == gp_j:
						w2 = SAME_PLATFORM_RESET
					else:
						w2 = 1e9
						for f2 in plan_j.faces:
							if plan_j.faces[f2]["pid"] == pid2:
								w2 = minf(w2, plan_j.time_face_to_face(face_key, f2) if plan_j.faces.has(face_key) else 90.0)
						if w2 >= 1e8:
							continue
						w2 += BOARD_BUFFER
					var cand := a_t + w2
					if cand < ready.get(q, INF) - 0.001:
						ready[q] = cand
						prev[q] = {"from": gp, "run": r, "k": k, "j": j, "arr": a_t, "walk": w2}
						_push(heap, cand, q)
	if best_total == INF:
		return best
	# reconstruct
	var legs: Array = []
	var cur: Dictionary = best_pred
	var gp_cur: int = cur["gp"]
	var guard := 0
	legs.append(_leg(cur["run"], cur["k"], cur["j"]))
	while guard < 20:
		guard += 1
		var pv: Dictionary = prev[gp_cur]
		if pv["from"] == -1:
			break
		legs.append(_leg(pv["run"], pv["k"], pv["j"]))
		gp_cur = pv["from"]
	legs.reverse()
	return {"ok": true, "arrive": best_total, "legs": legs, "walk_end": best_pred["walk_end"], "walk_start": prev[gp_cur].get("walk", 0.0) if gp_cur != -1 else 0.0, "duration": best_total - t0}


static func _leg(r: int, k: int, j: int) -> Dictionary:
	var stops: PackedInt32Array = Timetable.run_stops[r]
	var arr: PackedFloat32Array = Timetable.run_arr[r]
	var dep: PackedFloat32Array = Timetable.run_dep[r]
	return {"run": r, "line": Timetable.run_line[r], "from": stops[k], "to": stops[j], "dep": dep[k], "arr": arr[j], "dest": Timetable.run_dest[r], "via": Timetable.run_via[r], "stops": j - k, "k": k, "j": j}


static func describe(res: Dictionary, t0: float) -> String:
	if not res.get("ok", false):
		return "no route"
	var s := ""
	for lg in res["legs"]:
		s += "  %s: %s -> %s (%s line to %s %s, %s -> %s, %d stops)\n" % [Clock.fmt(lg["dep"]), Net.station_name(lg["from"]), Net.station_name(lg["to"]), Net.line_name(lg["line"]), Net.station_name(lg["dest"]), lg["via"], Clock.fmt(lg["dep"], true), Clock.fmt(lg["arr"], true), lg["stops"]]
	s += "  arrive exit %s  (total %s)" % [Clock.fmt(res["arrive"], true), Clock.fmt_dur(res["arrive"] - t0)]
	return s


# --- tiny binary min-heap on [time, id] ---------------------------------------------------------
static func _push(h: Array, t: float, id: int) -> void:
	h.append([t, id])
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if h[p][0] <= h[i][0]:
			break
		var tmp = h[p]
		h[p] = h[i]
		h[i] = tmp
		i = p


static func _pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if h.size() > 0:
		h[0] = last
		var i := 0
		var n := h.size()
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < n and h[l][0] < h[m][0]:
				m = l
			if r < n and h[r][0] < h[m][0]:
				m = r
			if m == i:
				break
			var tmp = h[m]
			h[m] = h[i]
			h[i] = tmp
			i = m
	return top


static func _lower(arr: PackedInt64Array, t: float) -> int:
	var key: int = int(t * 2.0) << 24
	var lo := 0
	var hi := arr.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if arr[mid] < key:
			lo = mid + 1
		else:
			hi = mid
	return lo
