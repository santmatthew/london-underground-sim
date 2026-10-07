extends Node
## Which side of the train the ride's second track is on (TrackPath._plan_sides): on the right, the British way, except near a station module with two faces whose platforms are on the left of the trains, where
## the module's other face is on the left and the running track beyond the platform has the other track there; between two ends that want different sides the track changes sides once, inside a tunnel or in a flat
## crossing over open land (RunScenery CROSS).
## run: tools/gtest.sh side_swap_test [--list] (--list prints every hop that has a left end and what was done)
var ok := true
var list := false


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func _face_key(gps: PackedInt32Array, faces: PackedByteArray, k: int) -> String:
	return "%s#%d" % [Timetable.plat_pid[gps[k]], faces[k]]


func run():
	for a in OS.get_cmdline_user_args():
		if a == "--list":
			list = true
	Timetable.build(1)
	_levels()
	_one_face()
	_hops()
	_crossing_mesh()
	print("OK" if ok else "FAILED")


## the pair levels a crossing happens at give exactly the spacing of the levels beside it
func _levels() -> void:
	for i in RunScenery.CROSS_LEVELS.size():
		var sc := i << RunScenery.CROSS_S_SHIFT
		check(RunScenery.cross_code(RunScenery.cross_level(sc)) == i, "cross_code inverts cross_level %d" % i)
		check(is_equal_approx(RunScenery.cross_spacing(sc), RunScenery.spacing_of_level(RunScenery.CROSS_LEVELS[i])), "cross_spacing is the spacing of its level %d" % i)


## a module with one face that is not one of a pair (a lone platform) with its platform on the left of its trains has the other track on the right in the running track beyond the platform (spec "ext" other_right);
## one with the platform on the right, or with two faces (the other face is the other track), or a pair's, does not say so
func _one_face() -> void:
	var n_one := 0
	var n_right := 0
	for idx in Net.stations.size():
		var plan := StationPlan.for_station(idx)
		for mi in plan.modules.size():
			var m: Dictionary = plan.modules[mi]
			var ext: Array = m.get("ext", [])
			var one: bool = (m["faces"] as Array).size() == 1 and not bool(m.get("split", false))
			for fi in ext.size():
				if ext[fi] == null:
					continue
				var says: bool = bool((ext[fi] as Dictionary).get("other_right", false))
				if not one:
					check(not says, "%s module %d: only a lone platform has other_right" % [Net.stations[idx]["name"], mi])
					continue
				# its face's door side: the platform on the left of the train?
				var fkey := ""
				for k in plan.faces:
					if int(plan.faces[k]["module"]) == mi:
						fkey = k
				if fkey == "":
					continue
				var f: Dictionary = plan.faces[fkey]
				var doors_left := (-float(f["side"])) * float(plan.canon_of(f)) <= 0.0
				n_one += 1
				check(says == doors_left, "%s %s: a lone platform with its doors %s has other_right %s" % [Net.stations[idx]["name"], fkey, "left" if doors_left else "right", str(says)])
				n_right += 1 if says else 0
	print("  info: %d lone platforms, %d of them with the platform on the left of the trains (the other track on the right beyond it)" % [n_one, n_right])
	check(n_right > 5, "there are lone platforms on the left (%d)" % n_right)


## every distinct pair of faces a timetable run goes between, where an end has its other face on the left
func _hops() -> void:
	var seen := {}
	var kinds := {}
	var n_left := 0
	var none: Array = []
	var worst_jump := 0.0
	var worst_at := ""
	var n_cross_cells := 0
	var mirror_checked := {}
	for r in Timetable.run_stops.size():
		var stops: PackedInt32Array = Timetable.run_stops[r]
		var gps: PackedInt32Array = Timetable.run_plat[r]
		var faces: PackedByteArray = Timetable.run_face[r]
		for k in stops.size() - 1:
			var ka := "%d.%d>%d.%d" % [gps[k], faces[k], gps[k + 1], faces[k + 1]]
			if seen.has(ka):
				continue
			seen[ka] = true
			var pa := StationPlan.for_station(stops[k])
			var pb := StationPlan.for_station(stops[k + 1])
			var la := pa.other_track_left(_face_key(gps, faces, k))
			var lb := pb.other_track_left(_face_key(gps, faces, k + 1))
			if not la and not lb:
				continue
			n_left += 1
			var id_a: String = Net.station_ids[stops[k]]
			var id_b: String = Net.station_ids[stops[k + 1]]
			var prof := TrackPath.profile(id_a, id_b)
			var dist := clampf(float(prof[0]), 250.0, 20000.0) if not prof.is_empty() else maxf(300.0, Net.dist_km(stops[k], stops[k + 1]) * 1150.0)
			var tp := TrackPath.between(id_a, id_b, dist, 90.0, 110.0, [], [], [], [], false, 0.0, 0.0, "", la, lb)
			var name := "%s %s -> %s %s (%.0f m, %s)" % [Net.stations[stops[k]]["name"], "L" if la else "R", Net.stations[stops[k + 1]]["name"], "L" if lb else "R", dist, tp.side_change]
			kinds[tp.side_change] = int(kinds.get(tp.side_change, 0)) + 1
			if list:
				print("  ", name)
			if tp.single:
				continue
			if tp.side_change == "none":
				none.append(name)
			# the ends: the cells next to a stop that wants the left have the other track on the left; the others on the right
			var kk0 := int(floor(dist / TrackPath.CELL)) + 1
			for q in [1, 2, 3, 4, 5]:
				var sc_a := tp.cell_scene(q)
				if (sc_a & RunScenery.PAIR) != 0 and tp.side_change != "none":
					check(((sc_a & RunScenery.SIDE_LEFT) != 0) == la, "%s: the cell %d from the start is on the %s" % [name, q, "left" if la else "right"])
				var sc_b := tp.cell_scene(kk0 - q)
				if (sc_b & RunScenery.PAIR) != 0 and tp.side_change != "none":
					check(((sc_b & RunScenery.SIDE_LEFT) != 0) == lb, "%s: the cell %d from the end is on the %s" % [name, q, "left" if lb else "right"])
			# the second track's place never jumps (a metre at most per metre: a crossing is gentle, the levels' steps are 0.6 m per cell)
			var prev := tp.offset_at(0.0)
			var s := 0.5
			while s < dist:
				var cur := tp.offset_at(s)
				var a_pair := (tp.cell_scene(int(roundf(s / TrackPath.CELL))) & RunScenery.PAIR) != 0
				var b_pair := (tp.cell_scene(int(roundf((s - 0.5) / TrackPath.CELL))) & RunScenery.PAIR) != 0
				if a_pair and b_pair and absf(cur - prev) > worst_jump:
					worst_jump = absf(cur - prev)
					worst_at = "%s at %.1f m" % [name, s]
				prev = cur
				s += 0.5
			for ci in range(-5, kk0 + 5):
				if (tp.cell_scene(ci) & RunScenery.CROSS) != 0:
					n_cross_cells += 1
			# the side changes at most once, and not between two neighbouring cells that both have a second track unless one is a crossing's
			var changes := 0
			var last_left := -1
			var last_ci := -100
			for ci in range(-5, kk0 + 5):
				var sc := tp.cell_scene(ci)
				if (sc & RunScenery.PAIR) == 0 or (sc & RunScenery.CROSS) != 0:
					continue
				var lf := 1 if (sc & RunScenery.SIDE_LEFT) != 0 else 0
				if last_left >= 0 and lf != last_left:
					changes += 1
					var crossing_between := false
					var enclosed_between := false
					for cj in range(last_ci + 1, ci):
						var scj := tp.cell_scene(cj)
						crossing_between = crossing_between or (scj & RunScenery.CROSS) != 0
						enclosed_between = enclosed_between or RunScenery.enclosed(scj & 7)
					check(crossing_between or enclosed_between, "%s: the side changes between cells %d and %d with nothing between" % [name, last_ci, ci])
				last_left = lf
				last_ci = ci
			check(changes <= 1, "%s: the side changes %d times" % [name, changes])
			# a ride's cells: the other track's cell bit follows the side and the mirror (the cell is built with the platform on the left, -z; PAIR_RIGHT puts the other track on +z)
			if not mirror_checked.has(tp.side_change):
				mirror_checked[tp.side_change] = true
				for mir in [false, true]:
					var tr := TunnelRun.new()
					tr.path = tp
					tr.mirror = mir
					for ci in range(-5, kk0 + 5):
						var sc0 := tp.cell_scene(ci)
						if (sc0 & RunScenery.PAIR) == 0:
							continue
						var scr := tr._scene_of(ci)
						var path_left := (sc0 & RunScenery.SIDE_LEFT) != 0
						check((scr & RunScenery.SIDE_LEFT) == 0, "%s: the cell's bit for the path's side is gone" % name)
						check(((scr & RunScenery.PAIR_RIGHT) != 0) == ((not path_left) != mir), "%s: cell %d (%s, %s) has PAIR_RIGHT %s" % [name, ci, "left" if path_left else "right", "mirrored" if mir else "plain", str((scr & RunScenery.PAIR_RIGHT) != 0)])
					tr.free()
	print("  info: %d hops have a left end: %s" % [n_left, str(kinds)])
	print("  info: the largest step of the second track's place in half a metre: %.3f m (%s); %d crossing cells" % [worst_jump, worst_at, n_cross_cells])
	check(n_left > 20, "there are hops with a left end (%d)" % n_left)
	check(worst_jump < 0.12, "the second track's place has no jumps (%.3f m in 0.5 m at %s)" % [worst_jump, worst_at])
	if not none.is_empty():
		print("  info: %d hops where the track stays on the right (nowhere to change): %s" % [none.size(), str(none.slice(0, 6))])


func _probe_covered(kit: MeshKit, mat: String, x: float, z: float) -> bool:
	if not kit.surfaces.has(mat):
		return false
	var v: PackedVector3Array = kit.surfaces[mat]["v"]
	var ix: PackedInt32Array = kit.surfaces[mat]["i"]
	for j in range(0, ix.size(), 3):
		var a := Vector2(v[ix[j]].x, v[ix[j]].z)
		var b := Vector2(v[ix[j + 1]].x, v[ix[j + 1]].z)
		var c := Vector2(v[ix[j + 2]].x, v[ix[j + 2]].z)
		var p := Vector2(x, z)
		var d1 := (p - b).cross(a - b)
		var d2 := (p - c).cross(b - c)
		var d3 := (p - a).cross(c - a)
		var neg := d1 < -1e-6 or d2 < -1e-6 or d3 < -1e-6
		var pos := d1 > 1e-6 or d2 > 1e-6 or d3 > 1e-6
		if not (neg and pos):
			return true
	return false


## a crossing cell as built: the other track's rails at the entry and the exit are where the scene says, and no ground lies over its bed
func _crossing_mesh() -> void:
	var t := PlatformModule.GAP * 0.5 + PlatformModule.PW_RUN + PlatformModule.TRACK_TO_EDGE
	for right in [true, false]:
		for level_code in [0, 3, 7]:
			var p0 := 5
			var p1 := 9
			var sc: int = RunScenery.OPEN | RunScenery.PAIR | RunScenery.CROSS | (p0 << 13) | (p1 << 17) | (level_code << RunScenery.CROSS_S_SHIFT)
			if right:
				sc |= RunScenery.PAIR_RIGHT
			var off := RunScenery.cross_offsets(sc)
			var kit := MeshKit.new()
			RunScenery.add_scene(kit, sc, 1, -6.0, 6.0, t, {"u0": 0.0})
			# the rails of the other track are lifted a little above this one's: their top vertices at the entry and at the exit
			var top := PlatformModule.RAIL_Y + RunScenery.CROSS_LIFT
			var v: PackedVector3Array = kit.surfaces["rail"]["v"]
			for xe in [-6.0, 6.0]:
				var zs := 0.0
				var cnt := 0
				for p in v:
					if absf(p.x - xe) < 0.001 and absf(p.y - top) < 0.002:
						zs += p.z
						cnt += 1
				check(cnt > 0, "crossing: rail vertices of the other track at x = %.0f (%d)" % [xe, cnt])
				if cnt > 0:
					var want := t + (off.x if xe < 0.0 else off.y)          # (the top vertices are the two outer rails': 0.7175 and -0.7175 about the track's z)
					check(absf(zs / float(cnt) - want) < 0.06, "crossing: the other track at x = %.0f is at z %.2f, want %.2f (right %s, code %d)" % [xe, zs / float(cnt), want, str(right), level_code])
			# the ground does not cover the other formation's centre line
			for xs in [-5.0, -2.0, 0.0, 2.0, 5.0]:
				var f: float = (xs + 6.0) / 12.0
				var zc: float = t + lerpf(off.x, off.y, f)
				check(not _probe_covered(kit, "grass", xs, zc), "crossing: grass over the other track at x %.0f (z %.2f)" % [xs, zc])
			check(_probe_covered(kit, "grass", 0.0, t + 20.0) and _probe_covered(kit, "grass", 0.0, t - 20.0), "crossing: grass on both sides further out")
