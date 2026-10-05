extends Node
## The Elizabeth line's surface stations with two side platforms (StationPlan.is_split, data/el_platforms.json): one module per platform, the platforms outboard and the two tracks
## SPLIT_SPACING apart between them, no wall across the tracks; and the ride out of such a station keeps that spacing at the ends (RunScenery.cell_scenes split_a / split_b).
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func _id(nm: String) -> String:
	return Net.station_ids[Net.name_to_idx[nm]]


func run():
	Timetable.build(1)
	check(StationPlan.is_split(_id("Romford")), "Romford (two side platforms) is drawn as a split pair")
	for nm in ["Gidea Park", "Abbey Wood", "Shenfield", "Amersham", "Oxford Circus"]:
		check(not StationPlan.is_split(_id(nm)), "%s is not drawn as a split pair" % nm)
	var n := 0
	for i in Net.stations.size():
		if StationPlan.is_split(Net.station_ids[i]):
			n += 1
	check(n >= 20, "most of the surface stations are split pairs (%d)" % n)
	# the plan: two modules, a face each, the platforms outboard and the tracks SPLIT_SPACING apart
	for nm in ["Romford", "Hanwell", "Goodmayes", "Manor Park", "West Ealing", "Ealing Broadway"]:
		var plan := StationPlan.for_station(Net.name_to_idx[nm])
		var pair: Array = []          # (the split modules: a station of other lines has more modules, Ealing Broadway)
		for m in plan.modules:
			if bool((m["spec"] as Dictionary).get("split", false)):
				pair.append(m)
		check(pair.size() == 2, "%s: one module per platform (%d)" % [nm, pair.size()])
		if pair.size() != 2:
			continue
		var fa: Dictionary = {}
		var fb: Dictionary = {}
		for fk in plan.faces:
			var f: Dictionary = plan.faces[fk]
			if not String(f["pid"]).begins_with("elizabeth"):
				continue          # (a station of other lines has their faces too)
			if int(f["face"]) == 0:
				fa = f
			else:
				fb = f
		check(not fa.is_empty() and not fb.is_empty() and int(fa["module"]) != int(fb["module"]), "%s: the two faces are in two modules, slots 0 and 1" % nm)
		if fa.is_empty() or fb.is_empty():
			continue
		var ta: float = fa["track_z"]
		var tb: float = fb["track_z"]
		var lo := minf(ta, tb)
		var hi := maxf(ta, tb)
		check(absf((hi - lo) - RunScenery.SPLIT_SPACING) < 0.01, "%s: the tracks are %.2f m apart (%.2f)" % [nm, RunScenery.SPLIT_SPACING, hi - lo])
		var ea: float = fa["edge_z"]
		var eb: float = fb["edge_z"]
		var out_a := ea < ta if ta == lo else ea > ta
		var out_b := eb < tb if tb == lo else eb > tb
		check((ea < lo or ea > hi) and (eb < lo or eb > hi) and out_a == out_b and ((ea < lo) != (eb < lo)), "%s: each platform edge lies outside the pair of tracks, one on each side" % nm)
		var stag: float = float(RealData.el_platforms(_id(nm)).get("stagger", 0.0))
		var dx := float(pair[0]["pos"].x) - float(pair[1]["pos"].x)
		if stag == 0.0:
			check(absf(dx) < 0.01, "%s: the platforms lie side by side (same x)" % nm)
		else:
			check(absf(absf(dx) - absf(stag)) < 0.01, "%s: the platforms are staggered as the data says (%.1f m, data %.0f m)" % [nm, dx, stag])
		check(true, "%s: modules flagged split" % nm)
		var sf0: Array = pair[0]["spec"]["faces"]
		var sf1: Array = pair[1]["spec"]["faces"]
		check(sf0.size() == 2 and sf0[0] != null and sf0[1] == null and sf1.size() == 2 and sf1[0] == null and sf1[1] != null, "%s: each module has its one face in its own slot" % nm)
		var e1: Array = pair[1]["ext"]
		check(e1.size() == 2 and e1[0] == null and e1[1] != null, "%s: the second module's running track is read by slot" % nm)
	# a ride out of a split station keeps the spacing there; at an ordinary stop it starts at the station's
	var a := _id("Romford")
	var b := _id("Chadwell Heath")
	var g := _id("Gidea Park")
	var p_ss := TrackPath.between(a, b, 3000.0, 100.0, 130.0)
	var worst := 0.0
	for s in [0.0, 50.0, 150.0, 400.0, 1000.0, 2000.0, 2600.0, 2950.0]:
		var sp := p_ss.spacing_at(float(s))
		if (p_ss.cell_scene(int(roundf(float(s) / 12.0))) & RunScenery.PAIR) != 0:
			worst = maxf(worst, absf(sp - RunScenery.SPLIT_SPACING))
	check(worst < 0.01, "split to split: the two tracks stay %.1f m apart where there is a pair (worst error %.3f m)" % [RunScenery.SPLIT_SPACING, worst])
	var p_sg := TrackPath.between(a, g, 3000.0, 100.0, 130.0)
	check(absf(p_sg.spacing_at(100.0) - RunScenery.SPLIT_SPACING) < 0.01, "leaving a split station: %.1f m at 100 m" % p_sg.spacing_at(100.0))
	check(p_sg.spacing_at(2950.0) > RunScenery.TRACK_SPACING - 0.3, "arriving at an island station: the station's spacing again (%.1f m)" % p_sg.spacing_at(2950.0))
	print("OK" if ok else "FAILED")
