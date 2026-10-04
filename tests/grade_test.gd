extends Node
## The vertical profile of a ride (TrackPath): the tunnels between deep stations dip between them, level at both platforms and over the stretches where the hand-overs happen, never steeper than
## MAX_GRADE, ending as high as they began; the open and sub-surface lines stay level; a car on the slope pitches with it.
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
	check(absf(y1) < 0.05, "as high at the end as at the start (%.3f m)" % y1)
	var s := -60.0
	while s < dist + 60.0:
		var a := tp.pose(s).origin
		var b := tp.pose(s + 1.0).origin
		y_min = minf(y_min, a.y)
		g_max = maxf(g_max, absf(b.y - a.y))
		if s <= 80.0 or s >= dist - 120.0:
			check(absf(a.y) < 0.05, "level %.0f m along the ride (%.3f m)" % [s, a.y])
		s += 5.0
	check(y_min < -0.8, "the track dips (deepest %.2f m)" % y_min)
	check(g_max <= TrackPath.MAX_GRADE + 0.005, "no steeper than %.1f %% (%.2f %%)" % [TrackPath.MAX_GRADE * 100.0, g_max * 100.0])
	print("  info: Bank -> Liverpool Street dips %.2f m, steepest %.2f %%" % [-y_min, g_max * 100.0])
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
	# the open line and the sub-surface lines stay level
	var a: String = Net.station_ids[Net.name_to_idx["Amersham"]]
	var b: String = Net.station_ids[Net.name_to_idx["Chalfont & Latimer"]]
	check(TrackPath.between(a, b, 3300.0, 100.0, 130.0, [], [], [], [], true).is_level(), "open country is level")
	var bk: String = Net.station_ids[Net.name_to_idx["Baker Street"]]
	var gp: String = Net.station_ids[Net.name_to_idx["Great Portland Street"]]
	check(TrackPath.between(bk, gp, 900.0, 100.0, 130.0, [], [], [], [], true).is_level(), "the shallow tunnel of a sub-surface line is level")
	# the cars follow the slope: a car whose front is 1 m higher over 10 m pitches by atan(0.1)
	var t := Train._bogie_pose(Vector3(5, 0.5, 0), Vector3(-5, -0.5, 0))
	check(absf(asin(clampf(t.basis.x.y, -1.0, 1.0)) - atan(0.1)) < 0.002 and absf(t.origin.length()) < 0.001, "a car on a slope takes its pitch")
	var f := Train._bogie_pose(Vector3(5, 0, 0), Vector3(-5, 0, 0))
	check(absf(f.basis.x.y) < 1e-6, "a car on the level does not")
	print("OK" if ok else "FAILED")
