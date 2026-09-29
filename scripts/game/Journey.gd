class_name Journey
extends RefCounted
## Generates a journey: start station/spot/time, destination, and the planner's optimal ("par") route.

const TIME_MODES := {
	"random": [5.75, 23.5], "am_peak": [7.25, 9.25], "midday": [10.5, 15.0], "pm_peak": [16.75, 18.75], "evening": [19.5, 22.5], "late": [22.75, 24.2],
}
const LENGTHS := {"short": [7.0 * 60.0, 22.0 * 60.0], "medium": [15.0 * 60.0, 45.0 * 60.0], "long": [35.0 * 60.0, 80.0 * 60.0]}


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
		var start := Net.random_station(rng, true)
		var plan := StationPlan.for_station(start)
		var spot := _pick_spot(rng, plan)
		var dest := Net.random_station(rng, false)
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
