extends Node
## Deterministic train timetable for one simulated service day.
##
## A *run* is one train working one service in one direction, terminus to terminus.
## Every run stores, per stop k: station, global platform, arrival and departure times (seconds since midnight).
## Per global platform we keep a sorted PackedInt64Array of departure "events":
##     key = (int(dep*2) << 24) | (run << 8) | k
## which makes "next trains at platform P after time t" a binary search.

const SERVICE_START := 5.0 * 3600.0
const SERVICE_END := 24.5 * 3600.0
const ORIGIN_WAIT := 60.0       # train sits in the platform this long before departing its origin
const FINAL_WAIT := 45.0        # terminating train stays this long (passengers alight) then leaves empty
const CLEARANCE := 12.0         # minimum gap between one train leaving a platform face and the next arriving
const STREAM_START := 4.9 * 3600.0

# trains per hour (per direction, whole line) by band:  early 05:00, am 06:30, mid 09:45, pm 16:00, eve 19:15, late 22:30
const BAND_STARTS := [5.0, 6.5, 9.75, 16.0, 19.25, 22.5]
const TPH := {
	"bakerloo": [8, 22, 14, 22, 12, 8], "central": [10, 32, 20, 32, 16, 9], "circle": [4, 6, 6, 6, 6, 4],
	"district": [6, 24, 16, 24, 12, 6], "hammersmith-city": [4, 8, 6, 8, 6, 4], "jubilee": [10, 30, 20, 30, 16, 9],
	"metropolitan": [4, 16, 10, 16, 8, 4], "northern": [10, 30, 20, 30, 18, 10], "piccadilly": [8, 24, 18, 24, 14, 8],
	"victoria": [12, 34, 27, 34, 20, 12], "waterloo-city": [6, 20, 8, 20, 6, 0], "elizabeth": [8, 24, 16, 24, 14, 8],
}
# share of the line's trains that work each service (normalised at build time)
const WEIGHTS := {
	"central": [0.28, 0.18, 0.24, 0.06, 0.24],
	"district": [0.12, 0.10, 0.02, 0.14, 0.10, 0.28, 0.25],
	"metropolitan": [0.25, 0.10, 0.40, 0.25],
	"northern": [0.09, 0.09, 0.13, 0.05, 0.13, 0.13, 0.05, 0.13],
	"piccadilly": [0.20, 0.45, 0.35],
	# Abbey Wood - T4, - T5, - Reading; Paddington - T4, - T5, - Reading; Shenfield - T4, - T5; Abbey Wood - Paddington; Shenfield - Paddington (the API lists the through routes; the two short ones carry the core)
	"elizabeth": [0.10, 0.04, 0.08, 0.04, 0.02, 0.04, 0.04, 0.02, 0.30, 0.32],
}

# --- run storage (parallel arrays indexed by run id) ---
var run_line: Array = []            # String line id
var run_svc: Array = []             # String service id
var run_dir: PackedInt32Array = PackedInt32Array()   # 0 = along service order, 1 = reverse
var run_stops: Array = []           # PackedInt32Array station idx per stop
var run_plat: Array = []            # PackedInt32Array global platform per stop
var run_arr: Array = []             # PackedFloat32Array
var run_dep: Array = []             # PackedFloat32Array
var run_dest: PackedInt32Array = PackedInt32Array()  # destination station idx
var run_via: Array = []             # String ("" or "via Bank")
var run_t0: PackedFloat32Array = PackedFloat32Array()   # first arrival (start of run)
var run_t1: PackedFloat32Array = PackedFloat32Array()   # last departure (end of run)
var run_face: Array = []            # PackedByteArray per run: platform face (0/1; 1 only at terminus platforms)

# --- platform tables ---
var plat_station: PackedInt32Array = PackedInt32Array()
var plat_pid: Array = []            # "central:Eastbound"
var plat_index: Array = []          # station idx -> {pid: global platform}
var events: Array = []              # global platform -> PackedInt64Array (sorted)

var built := false
var seed_used := 0
var build_ms := 0


func _ready() -> void:
	_build_platform_tables()


func _build_platform_tables() -> void:
	plat_station.clear()
	plat_pid.clear()
	plat_index.clear()
	for s in Net.stations:
		var d := {}
		for pid in s["platforms"]:
			d[pid] = plat_station.size()
			plat_station.append(s["idx"])
			plat_pid.append(pid)
		plat_index.append(d)


func tph_at(line: String, hour: float) -> float:
	var arr: Array = TPH[line]
	var b := 0
	for i in BAND_STARTS.size():
		if hour >= BAND_STARTS[i]:
			b = i
	# smooth ramp over the first 20 minutes of a band
	var start: float = BAND_STARTS[b]
	var cur: float = arr[b] * _weekend_scale(b)
	if b > 0 and hour < start + 0.33:
		var prev: float = arr[b - 1] * _weekend_scale(b - 1)
		return lerpf(prev, cur, (hour - start) / 0.33)
	return cur


func _weekend_scale(band: int) -> float:
	if not Clock.weekend:
		return 1.0
	return [1.0, 0.72, 0.9, 0.72, 1.0, 1.0][band]      # thinner peak services at weekends


## `build` on a worker thread, so that the loading screen keeps animating (about a second of work). Nothing may read the timetable until this returns:
## the previous journey's station is gone by then (the menu frees it).
func build_async(seed_value: int) -> void:
	_build_task = WorkerThreadPool.add_task(build.bind(seed_value), false, "timetable")
	var task := _build_task
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	if _build_task == task:
		WorkerThreadPool.wait_for_task_completion(task)
		_build_task = -1


var _build_task := -1


## quitting during the loading screen: the worker must be finished with this node before it is freed
func _exit_tree() -> void:
	if _build_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_build_task)
		_build_task = -1


func build(seed_value: int) -> void:
	var t_begin := Time.get_ticks_msec()
	seed_used = seed_value
	run_line.clear(); run_svc.clear(); run_stops.clear(); run_plat.clear(); run_arr.clear(); run_dep.clear(); run_via.clear(); run_face.clear()
	run_dir = PackedInt32Array(); run_dest = PackedInt32Array(); run_t0 = PackedFloat32Array(); run_t1 = PackedFloat32Array()
	var ev_lists: Array = []
	ev_lists.resize(plat_station.size())
	# platform face occupancy: per (platform*2+face) -> sorted lists of visit start / end
	var occ_a: Array = []
	var occ_d: Array = []
	occ_a.resize(plat_station.size() * 2)
	occ_d.resize(plat_station.size() * 2)
	for i in ev_lists.size():
		ev_lists[i] = []
	for i in occ_a.size():
		occ_a[i] = []
		occ_d[i] = []
	var rng := RandomNumberGenerator.new()

	# 1. train requests: an evenly spaced stream per (line, direction) measured at a reference station on the trunk
	var requests: Array = []      # [t_origin, line, service index, dir]
	for lid in Net.line_ids:
		var svcs: Array = Net.lines[lid]["services"]
		var w: Array = WEIGHTS.get(lid, [])
		var shares := PackedFloat32Array()
		var wsum := 0.0
		for i in svcs.size():
			wsum += (w[i] if i < w.size() else 1.0)
		for i in svcs.size():
			shares.append((w[i] if i < w.size() else 1.0) / wsum)
		var ref := _reference_station(svcs)
		var offsets: Array = []      # per service: [offset fwd, offset bwd] = seconds from origin departure to the reference stop
		for svc in svcs:
			offsets.append([_offset_to(svc, ref, 0), _offset_to(svc, ref, 1)])
		for dir in 2:
			rng.seed = hash("%d/%s/%d" % [seed_value, lid, dir])
			var acc := PackedFloat32Array()
			acc.resize(svcs.size())
			var t := STREAM_START + rng.randf() * 90.0
			while t < SERVICE_END:
				var tph := tph_at(lid, t / 3600.0)
				if tph < 0.2:
					t += 300.0
					continue
				var best := 0
				for i in svcs.size():
					acc[i] += shares[i]
					if acc[i] > acc[best]:
						best = i
				acc[best] -= 1.0
				requests.append([t - offsets[best][dir], lid, best, dir])
				t += 3600.0 / tph * rng.randf_range(0.93, 1.07)
	requests.sort_custom(func(a, b): return a[0] < b[0])

	# 2. materialise runs in origin-time order, resolving platform conflicts by delaying later trains
	for rq in requests:
		var svc: Dictionary = Net.lines[rq[1]]["services"][rq[2]]
		rng.seed = hash("%d/%s/%d" % [seed_value, svc["id"], int(rq[0])])
		_add_run(rq[1], svc, rq[3], rq[0], rng, ev_lists, occ_a, occ_d)

	events = []
	events.resize(ev_lists.size())
	for i in ev_lists.size():
		var pa := PackedInt64Array(ev_lists[i])
		pa.sort()
		events[i] = pa
	built = true
	build_ms = Time.get_ticks_msec() - t_begin


func _via_of(name: String) -> String:
	var i := name.find(" via ")
	return "via " + name.substr(i + 5).strip_edges() if i >= 0 else ""


## A station served by every service of the line (closest to the centre); -1 if none.
func _reference_station(svcs: Array) -> int:
	var common := {}
	for s in (svcs[0]["stop_idx"] as PackedInt32Array):
		common[s] = true
	for svc in svcs:
		var here := {}
		for s in (svc["stop_idx"] as PackedInt32Array):
			here[s] = true
		for k in common.keys():
			if not here.has(k):
				common.erase(k)
	var best := -1
	var bd := 1e9
	for k in common:
		var st: Dictionary = Net.stations[k]
		var d := Vector2(st["x"], st["y"]).length()
		if d < bd:
			bd = d
			best = k
	return best


## nominal seconds from origin departure until arrival at station `ref` (0 if ref < 0)
func _offset_to(svc: Dictionary, ref: int, dir: int) -> float:
	if ref < 0:
		return 0.0
	var stops: PackedInt32Array = svc["stop_idx"]
	var n := stops.size()
	var secs := _service_run_times(svc)
	var t := 0.0
	for k in n:
		var i := k if dir == 0 else n - 1 - k
		if stops[i] == ref:
			return t
		if k < n - 1:
			var seg := i if dir == 0 else i - 1
			t += secs[seg] + 30.0
	return t


## seconds to run between consecutive service stops (index i -> i+1)
func _service_run_times(svc: Dictionary) -> PackedFloat32Array:
	if svc.has("_run_secs"):
		return svc["_run_secs"]
	var stops: PackedInt32Array = svc["stop_idx"]
	var out := PackedFloat32Array()
	for i in stops.size() - 1:
		var d_m := Net.dist_km(stops[i], stops[i + 1]) * 1000.0 * 1.15
		# longer gaps reach higher cruising speeds
		out.append(maxf(42.0, 14.0 + d_m / minf(24.0, 12.0 + d_m / 300.0)))
	svc["_run_secs"] = out
	return out


## Earliest start >= a0 for a visit of length `len` on the platform face without touching any booked visit.
func _fit(occ_a: Array, occ_d: Array, key: int, a0: float, length: float) -> float:
	var la: Array = occ_a[key]
	var ld: Array = occ_d[key]
	var n := la.size()
	if n == 0 or a0 >= ld[n - 1] + CLEARANCE and a0 >= la[n - 1]:
		return a0
	var a := a0
	while true:
		# first booked visit starting after `a`
		var lo := 0
		var hi := n
		while lo < hi:
			var mid := (lo + hi) >> 1
			if la[mid] <= a:
				lo = mid + 1
			else:
				hi = mid
		if lo > 0 and ld[lo - 1] + CLEARANCE > a:
			a = ld[lo - 1] + CLEARANCE
			continue
		if lo < n and a + length + CLEARANCE > la[lo]:
			a = ld[lo] + CLEARANCE
			continue
		return a
	return a


func _book(occ_a: Array, occ_d: Array, key: int, a: float, d: float) -> void:
	var la: Array = occ_a[key]
	var ld: Array = occ_d[key]
	var n := la.size()
	if n == 0 or a >= la[n - 1]:
		la.append(a)
		ld.append(d)
		return
	var lo := 0
	var hi := n
	while lo < hi:
		var mid := (lo + hi) >> 1
		if la[mid] <= a:
			lo = mid + 1
		else:
			hi = mid
	la.insert(lo, a)
	ld.insert(lo, d)


func _add_run(lid: String, svc: Dictionary, dir: int, t_origin_dep: float, rng: RandomNumberGenerator, ev_lists: Array, occ_a: Array, occ_d: Array) -> void:
	var stops: PackedInt32Array = svc["stop_idx"]
	var run_secs := _service_run_times(svc)
	var plats: Array = svc["plat_fwd"] if dir == 0 else svc["plat_bwd"]
	var n := stops.size()
	var st := PackedInt32Array(); st.resize(n)
	var gp := PackedInt32Array(); gp.resize(n)
	var arr := PackedFloat32Array(); arr.resize(n)
	var dep := PackedFloat32Array(); dep.resize(n)
	var face := PackedByteArray(); face.resize(n)
	var rid := run_line.size()
	var t := t_origin_dep
	var crowd := Clock.crowd_factor(t_origin_dep)
	for k in n:
		var i := k if dir == 0 else n - 1 - k
		var sidx: int = stops[i]
		var g: int = plat_index[sidx][plats[i]]
		st[k] = sidx
		gp[k] = g
		var terminal: bool = Net.stations[sidx]["platforms"][plats[i]]["terminal"]
		var length: float
		if k == 0:
			length = ORIGIN_WAIT
		elif k == n - 1:
			length = FINAL_WAIT
		else:
			length = 22.0 + (Net.importance(sidx) - 1.0) * 2.5 + crowd * 8.0 + rng.randf() * 7.0
		var want: float = (t - ORIGIN_WAIT) if k == 0 else t
		# choose the face that lets the train in earliest
		var a := _fit(occ_a, occ_d, g * 2, want, length)
		var f := 0
		if terminal:
			var a2 := _fit(occ_a, occ_d, g * 2 + 1, want, length)
			if a2 < a:
				a = a2
				f = 1
		_book(occ_a, occ_d, g * 2 + f, a, a + length)
		arr[k] = a
		dep[k] = a + length
		face[k] = f
		if k < n - 1:
			var seg := i if dir == 0 else i - 1
			t = dep[k] + run_secs[seg] * rng.randf_range(0.97, 1.05)
	run_line.append(lid)
	run_svc.append(svc["id"])
	run_dir.append(dir)
	run_stops.append(st)
	run_plat.append(gp)
	run_arr.append(arr)
	run_dep.append(dep)
	run_face.append(face)
	run_dest.append(st[n - 1])
	run_via.append(_via_of(svc["name"]))
	run_t0.append(arr[0])
	run_t1.append(dep[n - 1])
	for k in n:
		var key: int = (int(dep[k] * 2.0) << 24) | (rid << 8) | k
		ev_lists[gp[k]].append(key)


# ---------------------------------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------------------------------
static func ev_time(key: int) -> float:
	return float(key >> 24) * 0.5


static func ev_run(key: int) -> int:
	return (key >> 8) & 0xffff


static func ev_stop(key: int) -> int:
	return key & 0xff


func global_platform(station_idx: int, pid: String) -> int:
	return plat_index[station_idx].get(pid, -1)


## index of first event with dep >= t
func _lower_bound(arr: PackedInt64Array, t: float) -> int:
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


## Next in-service departures from a platform (terminating arrivals are skipped).
func next_departures(gp: int, t: float, count: int = 3) -> Array:
	var out: Array = []
	if not built or gp < 0:
		return out
	var ev: PackedInt64Array = events[gp]
	var i := _lower_bound(ev, t)
	while i < ev.size() and out.size() < count:
		var key := ev[i]
		var r := ev_run(key)
		var k := ev_stop(key)
		if k < (run_stops[r] as PackedInt32Array).size() - 1:
			out.append(train_info(r, k))
		i += 1
	return out


func train_info(r: int, k: int) -> Dictionary:
	return {
		"run": r, "k": k, "line": run_line[r], "dest": run_dest[r], "via": run_via[r],
		"arr": (run_arr[r] as PackedFloat32Array)[k], "dep": (run_dep[r] as PackedFloat32Array)[k],
		"final": k == (run_stops[r] as PackedInt32Array).size() - 1, "origin": k == 0,
	}


## All trains that are (or will be, within `lookahead`) in the platform: arrivals within [t - dwell, t + lookahead]
func visits_between(gp: int, t0: float, t1: float) -> Array:
	var out: Array = []
	if not built or gp < 0:
		return out
	var ev: PackedInt64Array = events[gp]
	var i := _lower_bound(ev, t0)   # events whose dep >= t0
	while i < ev.size():
		var key := ev[i]
		var r := ev_run(key)
		var k := ev_stop(key)
		var arr_t: float = (run_arr[r] as PackedFloat32Array)[k]
		if arr_t > t1:
			# events are sorted by dep, arr <= dep, so a later event may still have an earlier arr; stop only when dep is far beyond
			if ev_time(key) > t1 + 300.0:
				break
		else:
			out.append(train_info(r, k))
		i += 1
	return out


func run_stop_count(r: int) -> int:
	return (run_stops[r] as PackedInt32Array).size()


func run_name(r: int) -> String:
	var dest: String = Net.station_name(run_dest[r])
	var via: String = run_via[r]
	return dest + (" " + via if via != "" else "")
