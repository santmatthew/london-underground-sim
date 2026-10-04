extends Node
## The vertical profile of a ride (TrackPath): the real climb between the two platforms (their levels above Ordnance Datum) plus, in the tunnels of the deep lines, a typical dip; level at both platforms and
## over the stretches where the hand-overs happen, never steeper than MAX_GRADE; the open country and the sub-surface lines have the climb but no dip; a car on the slope pitches with it.
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	Timetable.build(1)
	var bank: String = Net.station_ids[Net.name_to_idx["Bank"]]
	var lst: String = Net.station_ids[Net.name_to_idx["Liverpool Street"]]
	var dist := 760.0
	var tp := TrackPath.between(bank, lst, dist, 90.0, 130.0)
	check(not tp.is_level(), "a tunnel hop between deep stations has a dip")
	var y_min := 0.0
	var g_max := 0.0
	var y0 := tp.pose(0.0).origin.y
	var y1 := tp.pose(dist).origin.y
	check(absf(y0) < 0.001, "level at the start (%.3f m)" % y0)
	var rise := TrackPath.rise_between(bank, lst)
	check(absf(y1 - rise) < 0.1 + 0.2 * absf(rise), "ends where the platform of the next station is: %.2f m (the data says %.2f m)" % [y1, rise])
	var s := -60.0
	while s < dist + 60.0:
		var a := tp.pose(s).origin
		var b := tp.pose(s + 1.0).origin
		y_min = minf(y_min, a.y)
		g_max = maxf(g_max, absf(b.y - a.y))
		if s <= 80.0:
			check(absf(a.y) < 0.05, "level %.0f m along the ride (%.3f m)" % [s, a.y])
		if s >= dist - 120.0 and s <= dist:
			check(absf(a.y - y1) < 0.05, "level %.0f m along the ride (%.3f m, ends at %.3f)" % [s, a.y, y1])
		s += 5.0
	check(y_min < -0.8, "the track dips (deepest %.2f m)" % y_min)
	check(g_max <= TrackPath.MAX_GRADE + 0.005, "no steeper than %.1f %% (%.2f %%)" % [TrackPath.MAX_GRADE * 100.0, g_max * 100.0])
	print("  info: Bank -> Liverpool Street dips %.2f m, steepest %.2f %%" % [-y_min, g_max * 100.0])
	# the climb changes gently from cell to cell (cells are rigid: a kink opens a crack in the lining)
	var kink := 0.0
	for k in range(tp.k_first(), tp.k_last()):
		kink = maxf(kink, absf(tp.pitch[k + 1 - tp.k_first()] - tp.pitch[k - tp.k_first()]))
	check(kink < 0.02, "no cell is more than %.3f rad off the one before (%.4f)" % [0.02, kink])
	# the pose is continuous across the cells, and its pitch is the slope
	var worst := 0.0
	for i in range(-20, int(dist) + 40):
		var p0 := tp.pose(float(i) + 0.001)
		var p1 := tp.pose(float(i) + 0.999)
		worst = maxf(worst, (p1.origin - p0.origin).length() - 0.998)
	check(worst < 0.02, "a metre of track is a metre long, everywhere (%.3f m off)" % worst)
	var mid := tp.pose(dist * 0.25)
	var pitch_mid := asin(clampf(mid.basis.x.y, -1.0, 1.0))
	check(absf(pitch_mid) > 0.005 and mid.basis.x.y < 0.0, "going down a quarter of the way (pitch %.2f deg)" % rad_to_deg(pitch_mid))
	# the open country and the sub-surface lines: the real climb (Amersham -> Chalfont & Latimer: the data says so), no dip - the profile only ever moves toward the end height
	var a: String = Net.station_ids[Net.name_to_idx["Amersham"]]
	var b: String = Net.station_ids[Net.name_to_idx["Chalfont & Latimer"]]
	for pr in [[a, b, 3300.0], [Net.station_ids[Net.name_to_idx["Baker Street"]], Net.station_ids[Net.name_to_idx["Great Portland Street"]], 900.0]]:
		var tpo := TrackPath.between(pr[0], pr[1], pr[2], 100.0, 130.0, [], [], [], [], true)
		var want := TrackPath.rise_between(pr[0], pr[1])
		var mono := true
		var prev := 0.0
		var sx := 0.0
		while sx <= float(pr[2]):
			var yy := tpo.pose(sx).origin.y
			if (want >= 0.0 and yy < prev - 0.02) or (want < 0.0 and yy > prev + 0.02):
				mono = false
			prev = yy
			sx += 12.0
		check(mono, "%s -> %s: no dip, only the climb of %.1f m" % [Net.stations[Net.station_ids.find(pr[0])]["name"], Net.stations[Net.station_ids.find(pr[1])]["name"], want])
		check(absf(tpo.pose(float(pr[2])).origin.y - want) < 0.1 + 0.25 * absf(want), "... and ends %.1f m from where it began (the data says %.1f m)" % [tpo.pose(float(pr[2])).origin.y, want])
	# the cars follow the slope: a car whose front is 1 m higher over 10 m pitches by atan(0.1)
	var t := Train._bogie_pose(Vector3(5, 0.5, 0), Vector3(-5, -0.5, 0))
	check(absf(asin(clampf(t.basis.x.y, -1.0, 1.0)) - atan(0.1)) < 0.002 and absf(t.origin.length()) < 0.001, "a car on a slope takes its pitch")
	var f := Train._bogie_pose(Vector3(5, 0, 0), Vector3(-5, 0, 0))
	check(absf(f.basis.x.y) < 1e-6, "a car on the level does not")
	print("OK" if ok else "FAILED")
