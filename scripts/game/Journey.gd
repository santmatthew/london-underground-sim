class_name Journey
extends RefCounted
## Generates a journey: start station/spot/time, destination, and the planner's optimal ("par") route.

const TIME_MODES := {
	"random": [5.75, 23.5], "am_peak": [7.25, 9.25], "midday": [10.5, 15.0], "pm_peak": [16.75, 18.75], "evening": [19.5, 22.5], "late": [22.75, 24.2],
}
const LENGTHS := {"short": [7.0 * 60.0, 22.0 * 60.0], "medium": [15.0 * 60.0, 45.0 * 60.0], "long": [35.0 * 60.0, 80.0 * 60.0]}


static func pick_day(rng: RandomNumberGenerator, mode: String) -> String:
	match mode:
		"saturday", "sunday", "weekday":
			return mode
	var r := rng.randf()
	return "weekday" if r < 0.62 else ("saturday" if r < 0.82 else "sunday")


static func pick_time(rng: RandomNumberGenerator, mode: String) -> float:
	var span: Array = TIME_MODES.get(mode, TIME_MODES["random"])
	if mode == "random":
		# weight by crowd factor so the busy/interesting periods come up often
		for i in 40:
			var h := rng.randf_range(span[0], span[1])
			if rng.randf() < 0.25 + Clock.crowd_factor(h * 3600.0):
				return h * 3600.0 + rng.randf() * 60.0
	return rng.randf_range(span[0], span[1]) * 3600.0


static func generate(rng: RandomNumberGenerator, opts: Dictionary) -> Dictionary:
	var t0 := pick_time(rng, opts.get("time", "random"))
	var lens: Array = LENGTHS.get(opts.get("length", "medium"), LENGTHS["medium"])
	var best := {}
	var best_score := 1e18
	for attempt in 14:
		var start := _station(rng, true)
		var plan := StationPlan.for_station(start)
		var spot := _pick_spot(rng, plan)
		var dest := _station(rng, false)
		if dest == start:
			continue
		var res := Planner.plan(start, spot["node"], t0, dest)
		if not res.get("ok", false) or res["legs"].size() == 0:
			continue
		var dur: float = res["duration"]
		var target: float = (float(lens[0]) + float(lens[1])) * 0.5
		var score := 0.0 if (dur >= lens[0] and dur <= lens[1]) else absf(dur - target)
		if score < best_score:
			best_score = score
			best = {"start": start, "spot": spot, "dest": dest, "t0": t0, "par": res, "par_s": dur}
			if score == 0.0:
				break
	return best


## a random station; with step-free journeys on, one that can be used step-free (a platform with step-free access and a lift beside every escalator and stair bank)
static func _station(rng: RandomNumberGenerator, weighted: bool) -> int:
	if not StationPlan.step_free_mode:
		return Net.random_station(rng, weighted)
	for k in 80:
		var s := Net.random_station(rng, weighted)
		if StepFree.station_ok(s):
			return s
	var pool := StepFree.station_list()
	return pool[rng.randi() % pool.size()] if not pool.is_empty() else Net.random_station(rng, weighted)


static func _pick_spot(rng: RandomNumberGenerator, plan: StationPlan) -> Dictionary:
	var total := 0.0
	for s in plan.start_spots:
		total += s["weight"]
	var r := rng.randf() * total
	for s in plan.start_spots:
		r -= s["weight"]
		if r <= 0.0:
			return s
	return plan.start_spots[0]


static func rating(score: float) -> String:
	if score >= 97.0: return "Faster than the Tube map"
	if score >= 88.0: return "Zone 1 native"
	if score >= 75.0: return "Seasoned commuter"
	if score >= 60.0: return "Regular Oyster user"
	if score >= 40.0: return "Confused tourist"
	return "Lost on the Circle line"


## Multi-stop: start + N target stations clustered within reach of each other (par is computed by Planner.plan_tour in a thread)
static func generate_multi(rng: RandomNumberGenerator, opts: Dictionary) -> Dictionary:
	var n: int = clampi(int(opts.get("stops", 3)), 2, 5)
	var t0 := pick_time(rng, opts.get("time", "random"))
	for attempt in 30:
		var start := _station(rng, true)
		var sx: float = Net.stations[start]["x"]
		var sy: float = Net.stations[start]["y"]
		var cands: Array = []
		for s in Net.stations:
			if s["idx"] == start:
				continue
			var d := Vector2(s["x"] - sx, s["y"] - sy).length()
			if d > 2.5 and d < 11.0 and (not StationPlan.step_free_mode or StepFree.station_ok(s["idx"])):
				cands.append(s["idx"])
		if cands.size() < n * 2:
			continue
		var picks: Array = []
		var tries := 0
		while picks.size() < n and tries < 200:
			tries += 1
			var c: int = cands[rng.randi() % cands.size()]
			var ok := true
			for p in picks:
				if Net.dist_km(c, p) < 2.2:
					ok = false
			if ok:
				picks.append(c)
		if picks.size() < n:
			continue
		var plan := StationPlan.for_station(start)
		var spot := _pick_spot(rng, plan)
		return {"mode": "multi", "start": start, "spot": spot, "targets": picks, "visited": [], "t0": t0, "dest": picks[0]}
	return {}


## Fixed journey for testing / replays: start station name, spot kind ("platform","street entrance","ticket hall"...), destination, hour
static func make(start_name: String, spot_kind: String, dest_name: String, hour: float, rng: RandomNumberGenerator) -> Dictionary:
	var start: int = Net.name_to_idx[start_name]
	var dest: int = Net.name_to_idx[dest_name]
	var plan := StationPlan.for_station(start)
	var spot: Dictionary = plan.start_spots[0]
	var cands: Array = plan.start_spots.filter(func(sp): return sp["name"] == spot_kind)
	if not cands.is_empty():
		spot = cands[rng.randi() % cands.size()]
	var t0 := hour * 3600.0
	var res := Planner.plan(start, spot["node"], t0, dest)
	return {"start": start, "spot": spot, "dest": dest, "t0": t0, "par": res, "par_s": res.get("duration", 0.0), "mode": "single"}
