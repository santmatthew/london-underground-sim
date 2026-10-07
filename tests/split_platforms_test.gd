extends Node
## The surface stations with two side platforms (StationPlan.is_split: the Elizabeth line's, data/el_platforms.json, and the Underground's generated ones, data/surface_platforms.json): one module per platform, the platforms outboard and the two tracks
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
	# the Underground's: side platforms where the data says so and the doors are on the left; an island, a door side that says otherwise, or no data leaves the generator's island
	for pr in [["Buckhurst Hill", "central"], ["Harlesden", "bakerloo"], ["Hornchurch", "ss"], ["Queensbury", "jubilee"], ["Snaresbrook", "central"], ["Sudbury Hill", "piccadilly"], ["East Acton", "central"],
			["Dagenham East", "ss"], ["Plaistow", "ss"],          # (OpenStreetMap: a pair, but the outlines are of unlike length)
			["West Acton", "central"], ["West Finchley", "northern"], ["Totteridge & Whetstone", "northern"], ["Chorleywood", "ss"],          # (the outlines carry no numbers: the pair is the two big ones)
			["Rayners Lane", "ss"], ["Upton Park", "ss"], ["Debden", "central"], ["Ruislip Manor", "ss"], ["Boston Manor", "piccadilly"], ["Fairlop", "central"], ["Kew Gardens", "ss"], ["South Harrow", "piccadilly"], ["South Woodford", "central"]]:          # (the stop node between the two platforms: door side "B", not "right")
		check(StationPlan.is_split(_id(pr[0]), pr[1]), "%s (%s) is drawn as a split pair" % [pr[0], pr[1]])
		check(not StationPlan.is_split(_id(pr[0])), "%s is not an Elizabeth line split pair" % pr[0])
	for pr in [["Greenford", "central"], ["Hendon Central", "northern"], ["South Ealing", "piccadilly"], ["Colindale", "northern"], ["Barons Court", "piccadilly"], ["Oxford Circus", "victoria"], ["Epping", "central"],
			["Turnham Green", "piccadilly"], ["Wembley Park", "jubilee"], ["Finchley Road", "jubilee"], ["White City", "central"]]:          # (platforms of another line beside them, a gap the data does not settle; Colindale: an island, in CULG [IP])
		check(not StationPlan.is_split(_id(pr[0]), pr[1]), "%s (%s) is not drawn as a split pair" % [pr[0], pr[1]])
	var n := 0
	for i in Net.stations.size():
		if StationPlan.is_split(Net.station_ids[i]):
			n += 1
	check(n >= 20, "most of the surface stations are split pairs (%d)" % n)
	# the plan: two modules, a face each, the platforms outboard and the tracks SPLIT_SPACING apart
	for pr in [["Romford", "elizabeth"], ["Hanwell", "elizabeth"], ["Goodmayes", "elizabeth"], ["Manor Park", "elizabeth"], ["West Ealing", "elizabeth"], ["Ealing Broadway", "elizabeth"],
			["Buckhurst Hill", "central"], ["Harlesden", "bakerloo"], ["Hornchurch", "ss"], ["Snaresbrook", "central"], ["Queen's Park", "bakerloo"]]:
		var nm: String = pr[0]
		var grp: String = pr[1]
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
			if not String(f["pid"]).begins_with(grp):
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
		var stag: float = float(RealData.platform_layout(_id(nm), grp).get("stagger", 0.0))
		var dx := float(pair[0]["pos"].x) - float(pair[1]["pos"].x)
		if stag == 0.0:
			check(absf(dx) < 0.01, "%s: the platforms lie side by side (same x)" % nm)
		else:
			# (the data's stagger is along its own axis, whose sign is arbitrary: read against the direction the first platform's trains leave in, from the neighbouring station)
			var lay: Dictionary = RealData.platform_layout(_id(nm), grp)
			var nb: String = PlatformCurve.neighbours(_id(nm), String(pair[0]["faces"][0]["pid"]))[1]
			var s0: Dictionary = Net.stations[Net.name_to_idx[nm]]
			var s1: Dictionary = Net.stations[Net.id_to_idx[nb]]
			var east := (float(s1["lon"]) - float(s0["lon"])) * 111320.0 * cos(deg_to_rad(float(s0["lat"])))
			var north := (float(s1["lat"]) - float(s0["lat"])) * 110574.0
			var sgn := 1.0 if east * float(lay["axis"][0]) + north * float(lay["axis"][1]) >= 0.0 else -1.0
			check(absf(dx - sgn * stag) < 0.01, "%s: the platforms are staggered as the data says, the right way round (%.1f m, expected %.1f m)" % [nm, dx, sgn * stag])
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
	var n_ss := 0
	for s in [0.0, 50.0, 150.0, 400.0, 1000.0, 2000.0, 2600.0, 2950.0]:
		var sp := p_ss.spacing_at(float(s))
		if (p_ss.cell_scene(int(roundf(float(s) / 12.0))) & RunScenery.PAIR) != 0:
			n_ss += 1
			worst = maxf(worst, absf(sp - RunScenery.SPLIT_SPACING))
	check(n_ss > 0 and worst < 0.01, "split to split: the two tracks stay %.1f m apart where there is a pair (worst error %.3f m)" % [RunScenery.SPLIT_SPACING, worst])
	var p_sg := TrackPath.between(a, g, 3000.0, 100.0, 130.0)
	check(absf(p_sg.spacing_at(100.0) - RunScenery.SPLIT_SPACING) < 0.01, "leaving a split station: %.1f m at 100 m" % p_sg.spacing_at(100.0))
	check(p_sg.spacing_at(2950.0) > RunScenery.TRACK_SPACING - 0.3, "arriving at an island station: the station's spacing again (%.1f m)" % p_sg.spacing_at(2950.0))
	# an Underground ride between two split stations keeps the spacing there too (the ride's line decides the group)
	var h := _id("Harlesden")
	var sp_id := _id("Stonebridge Park")
	var p_h := TrackPath.between(h, sp_id, 1800.0, 100.0, 130.0, [], [], [], [], false, 0.0, 0.0, "bakerloo")
	worst = 0.0
	var n_pair := 0
	for s in [0.0, 50.0, 150.0, 300.0, 900.0, 1500.0, 1700.0, 1790.0]:
		if (p_h.cell_scene(int(roundf(float(s) / 12.0))) & RunScenery.PAIR) != 0:
			n_pair += 1
			worst = maxf(worst, absf(p_h.spacing_at(float(s)) - RunScenery.SPLIT_SPACING))
	check(n_pair > 0 and worst < 0.01, "Harlesden - Stonebridge Park: the tracks stay %.1f m apart where there is a pair (%d samples, worst error %.3f m)" % [RunScenery.SPLIT_SPACING, n_pair, worst])
	# where two lines share the platforms (the Piccadilly line's trains use the Metropolitan line's two platforms at Eastcote ... Hillingdon: one "ss" pair), a ride of either line starts from the pair
	for nm in ["Eastcote", "Ruislip", "Ickenham", "Hillingdon"]:
		check(StationPlan.group_of(_id(nm), "piccadilly") == "ss" and StationPlan.group_of(_id(nm), "metropolitan") == "ss", "%s: both lines' trains use the same group of platforms" % nm)
		check(StationPlan.is_split(_id(nm), "ss") and (Net.stations[Net.name_to_idx[nm]]["platforms"] as Dictionary).size() == 2, "%s: two platforms, drawn as a split pair" % nm)
	check(StationPlan.group_of(_id("Rayners Lane"), "piccadilly") == "ss" and StationPlan.group_of(_id("Acton Town"), "piccadilly") == "piccadilly" and StationPlan.group_of(_id("Acton Town"), "district") == "ss", "Rayners Lane's platforms are shared too; elsewhere a line's platforms are its own group's")
	for ln in ["piccadilly", "metropolitan"]:
		var p_e := TrackPath.between(_id("Eastcote"), _id("Ruislip"), 2400.0, 100.0, 130.0, [], [], [], [], false, 0.0, 0.0, ln)
		worst = 0.0
		n_pair = 0
		for s in [0.0, 60.0, 200.0, 1200.0, 2200.0, 2350.0]:
			if (p_e.cell_scene(int(roundf(float(s) / 12.0))) & RunScenery.PAIR) != 0:
				n_pair += 1
				worst = maxf(worst, absf(p_e.spacing_at(float(s)) - RunScenery.SPLIT_SPACING))
		check(n_pair > 0 and worst < 0.01, "Eastcote - Ruislip by the %s line: the tracks stay %.1f m apart where there is a pair (%d samples, worst error %.3f m)" % [ln, RunScenery.SPLIT_SPACING, n_pair, worst])
	print("OK" if ok else "FAILED")
