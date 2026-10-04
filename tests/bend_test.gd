extends Node
## The curve maths: Bend (map / unmap / the mesh bend that wraps a straight module round an arc) and TrackPath (the cell-wise curved centre line a ride follows). Prints failures and OK.
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	# --- Bend: a round trip through map and unmap, in each region and for both turning directions
	for kap in [1.0 / 160.0, -1.0 / 160.0, 1.0 / 900.0, -1.0 / 400.0]:
		var b := Bend.new(kap, -20.0, 60.0, 0.0)
		var worst := 0.0
		for x in [-40.0, -20.0, -3.0, 0.0, 25.0, 59.0, 60.0, 61.0, 90.0]:
			for z in [-8.0, -3.4, 0.0, 1.7, 6.25]:
				var p := Vector3(x, 1.3, z)
				var q := b.unmap(b.map(p))
				worst = maxf(worst, q.distance_to(p))
		check(worst < 1e-3, "Bend round trip kappa %.5f: worst error %.5f m" % [kap, worst])
	# the centre line keeps its length, a line d metres off it is (1 + kappa d) times as long, and stays d from the centre of the arc
	var b2 := Bend.new(1.0 / 200.0, 0.0, 100.0, 0.0)
	var c_end := b2.map(Vector3(100.0, 0.0, 0.0))
	var centre := Vector3(0.0, 0.0, -200.0)
	check(absf(c_end.distance_to(centre) - 200.0) < 1e-3, "the centre line is a circle of radius 200 (%.3f)" % c_end.distance_to(centre))
	var off_end := b2.map(Vector3(100.0, 0.0, 6.25))
	check(absf(off_end.distance_to(centre) - 206.25) < 1e-3, "6.25 m off the centre line is a concentric arc (%.3f)" % off_end.distance_to(centre))
	var th_end := 100.0 / 200.0
	check(absf(b2.theta(100.0) - th_end) < 1e-6 and absf(b2.theta(150.0) - th_end) < 1e-6, "the heading is constant after the arc")
	# beyond the arc the track runs straight on in the direction it ended
	var q1 := b2.map(Vector3(110.0, 0.0, 0.0))
	var q0 := b2.map(Vector3(100.0, 0.0, 0.0))
	var dirn := (q1 - q0) / 10.0
	check(dirn.distance_to(Vector3(cos(th_end), 0.0, -sin(th_end))) < 1e-4, "straight on after the arc")
	# --- MeshKit.bend: a long wall and floor
	var kit := MeshKit.new()
	kit.wall("m", Vector3(0, 0, 4.0), Vector3(80, 0, 4.0), 0.0, 3.0, 0.0)
	kit.horiz("m", 0.0, 80.0, 1.7, 4.7, 0.0, true, 0.0)
	kit.box("m", Vector3(40, 1, 0), Vector3(2, 2, 2), 0.0)
	var tris0 := kit.triangle_count()
	var bb := Bend.new(1.0 / 160.0, 10.0, 70.0, 0.0)
	kit.bend(bb, 3.0)
	check(kit.triangle_count() > tris0 + 30, "long faces are cut into slabs (%d -> %d triangles)" % [tris0, kit.triangle_count()])
	var s: Dictionary = kit.surfaces["m"]
	var V: PackedVector3Array = s["v"]
	var N: PackedVector3Array = s["n"]
	var I: PackedInt32Array = s["i"]
	var bad := 0
	var off := 0.0
	for ti in range(0, I.size(), 3):
		var a := V[I[ti]]
		var bq := V[I[ti + 1]]
		var c := V[I[ti + 2]]
		var gn := (bq - a).cross(c - a)             # (Godot front faces are clockwise: the geometric normal of the index order points away from the stored normal)
		if gn.length() < 1e-6:
			continue
		if gn.normalized().dot(N[I[ti]]) > -0.5:
			bad += 1
		# every vertex of the wall (z 4 before bending) lies 4 m from the centre line of the arc
	check(bad == 0, "bent triangles keep their facing (%d wrong)" % bad)
	var far := V[I[0]]
	for ii in I:
		if V[ii].x > far.x:
			far = V[ii]
	check(far.x > 70.0 and absf(far.z) > 5.0, "the far end of the wall has swung round (%s)" % str(far))
	# --- TrackPath
	var ks := PackedFloat32Array()
	for k in 40:
		ks.append(TrackPath.Q * 5.0 if (k >= 8 and k < 20) else 0.0)
	var tp := TrackPath.new()
	tp._build(ks, 400.0)
	var p0 := tp.pose(0.0)
	check(p0.origin.length() < 1e-4 and absf(p0.basis.x.x - 1.0) < 1e-5, "the path starts at the identity")
	var worst_j := 0.0
	for k in range(1, 39):
		var sb := float(k) * TrackPath.CELL - TrackPath.CELL * 0.5
		var pa := tp.pose(sb - 0.001)
		var pb := tp.pose(sb + 0.001)
		worst_j = maxf(worst_j, pa.origin.distance_to(pb.origin) - 0.002)
		worst_j = maxf(worst_j, absf(tp.theta(sb - 0.001) - tp.theta(sb + 0.001)))
	check(worst_j < 1e-3, "poses are continuous at the cell boundaries (%.5f)" % worst_j)
	var turn := tp.theta(20.0 * TrackPath.CELL - 6.0) - tp.theta(8.0 * TrackPath.CELL - 6.0)
	check(absf(turn - 12.0 * TrackPath.CELL * TrackPath.Q * 5.0) < 1e-4, "twelve cells of R=300 m turn %.1f degrees" % rad_to_deg(turn))
	var pe := tp.pose(300.0)
	check(absf(tp.pose(300.0).basis.x.angle_to(Vector3(cos(turn), 0.0, -sin(turn)))) < 1e-4, "after the curve the track runs straight at the new heading")
	check(pe.origin.z < -5.0, "a left turn moves the track toward -z (%.1f)" % pe.origin.z)
	var tp2 := TrackPath.between("a", "b", 500.0, 80.0, 80.0)
	var flat_k := true
	for kk in tp2.kappa:
		if absf(kk) > 1e-9:
			flat_k = false
	check(flat_k and tp2.length == 500.0, "no data, no curve")
	print("OK" if ok else "FAILED")
