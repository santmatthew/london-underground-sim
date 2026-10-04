extends Node
## What the track runs through (RunScenery): the scenes of the cells of a line (tunnel mouths, cuttings and embankments that ramp, viaducts), the ride's path knowing them, the running track
## beyond a platform agreeing with it, and every kind of cell building with materials for all its surfaces.
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func _prof(sc: int) -> int:
	return sc & 7


func run():
	Timetable.build(1)
	# --- the scenes of a made-up line: open land, a tunnel, a cutting that opens out of it, an embankment into a viaduct, open land
	var secs := [[0, 120.0], [1, 240.0], [2, 360.0], [0, 100.0], [3, 120.0], [4, 300.0], [3, 60.0], [0, 100.0]]
	var sc := RunScenery.cell_scenes(secs, false, 3, -4, 120)
	var at := func(s: float) -> int: return sc[int(roundf(s / 12.0)) + 4]
	# (open 0-120, tunnel 120-360, cutting 360-720, open 720-820, embankment 820-940, viaduct 940-1240, embankment 1240-1300, open 1300-1400)
	check(_prof(at.call(60.0)) == RunScenery.OPEN, "open land first")
	check(_prof(at.call(240.0)) == RunScenery.BORE, "the bore in a tunnel of a deep line")
	check(_prof(at.call(-40.0)) == RunScenery.OPEN, "before the start the first stretch goes on")
	var out_cell: int = at.call(360.0)    # the first cell of the cutting after the tunnel
	check(_prof(out_cell) == RunScenery.CUTTING and ((out_cell >> 8) & 1) == 1, "the headwall at the entry of the cutting that comes out of the tunnel (scene %x)" % out_cell)
	check(((out_cell >> 3) & 3) == 3, "... which is at full depth from the start")
	var mid_cut: int = at.call(560.0)
	check(_prof(mid_cut) == RunScenery.CUTTING and ((mid_cut >> 3) & 3) == 3 and ((mid_cut >> 5) & 3) == 3 and ((mid_cut >> 8) & 3) == 0, "full depth in the middle of the cutting")
	var cut_end: int = at.call(720.0 - 24.0)
	check(((cut_end >> 3) & 3) == 3 and ((cut_end >> 5) & 3) == 2, "the cutting shallows out over its last cells (%d -> %d)" % [(cut_end >> 3) & 3, (cut_end >> 5) & 3])
	# the embankment from open land ramps up over three cells and the viaduct only at full height
	var emb0: int = at.call(828.0)
	check(_prof(emb0) == RunScenery.EMBANK and ((emb0 >> 3) & 3) == 0 and ((emb0 >> 5) & 3) == 1, "the embankment starts at ground level and rises (scene %x)" % emb0)
	var via: int = at.call(1000.0)
	check(_prof(via) == RunScenery.VIADUCT, "the viaduct at full height")
	var tall_emb: int = at.call(900.0)
	check(_prof(tall_emb) == RunScenery.EMBANK and ((tall_emb >> 7) & 1) == 1 and ((tall_emb >> 3) & 3) == 3, "an embankment that leads to a viaduct rises to the viaduct's height")
	var short_via := RunScenery.cell_scenes([[0, 100.0], [4, 40.0], [0, 100.0]], false, 1, 0, 20)
	var any_via := false
	for scn in short_via:
		if _prof(scn) == RunScenery.VIADUCT:
			any_via = true
	check(not any_via, "a viaduct too short to rise to full height stays an embankment")
	# the same line for a sub-surface line: boxes instead of bores, and the cells say so
	var sc2 := RunScenery.cell_scenes(secs, true, 3, -4, 120)
	check(_prof(sc2[int(roundf(240.0 / 12.0)) + 4]) == RunScenery.BOX and ((sc2[int(roundf(240.0 / 12.0)) + 4] >> 11) & 1) == 1, "a cut-and-cover box on a sub-surface line")
	# a line with no data is the bore, as before
	var tp := TrackPath.between("nowhere-a", "nowhere-b", 800.0, 100.0, 100.0)
	check(_prof(tp.cell_scene(10)) == RunScenery.BORE and _prof(tp.cell_scene(-30)) == RunScenery.BORE, "no data: the bore")
	var tp2 := TrackPath.between("nowhere-a", "nowhere-b", 800.0, 100.0, 100.0, [], [], [], [], true)
	check(_prof(tp2.cell_scene(10)) == RunScenery.BOX, "no data on a sub-surface line: the box")
	# a hop between two real stations that the data lacks is guessed from the kinds of the stations: the open country between surface stations
	var bu: String = Net.station_ids[Net.name_to_idx["Burnham (Berks)"]] if Net.name_to_idx.has("Burnham (Berks)") else ""
	var tap: String = Net.station_ids[Net.name_to_idx["Taplow"]] if Net.name_to_idx.has("Taplow") else ""
	if bu != "" and tap != "" and TrackPath.sections(bu, tap).is_empty():
		var tpg := TrackPath.between(bu, tap, 3000.0, 100.0, 100.0)
		check(_prof(tpg.cell_scene(40)) == RunScenery.OPEN, "Burnham -> Taplow (no data, two surface stations): open country")
	# the real data: Amersham -> Chalfont & Latimer is open country
	var a: String = Net.station_ids[Net.name_to_idx["Amersham"]]
	var b: String = Net.station_ids[Net.name_to_idx["Chalfont & Latimer"]]
	var real := TrackPath.sections(a, b)
	check(not real.is_empty(), "the data has Amersham -> Chalfont & Latimer")
	var tp3 := TrackPath.between(a, b, 3300.0, 100.0, 100.0, [], [], [], [], true)
	check(_prof(tp3.cell_scene(50)) == RunScenery.OPEN, "Amersham -> Chalfont & Latimer: open")
	# the reverse direction is the same stretches the other way round
	var back := TrackPath.sections(b, a)
	check(back.size() == real.size() and absf(float(back[0][1]) - float(real[real.size() - 1][1])) < 60.0, "the other direction reads the same stretches reversed")
	# Bank -> Liverpool Street is all tunnel
	var bank: String = Net.station_ids[Net.name_to_idx["Bank"]]
	var lst: String = Net.station_ids[Net.name_to_idx["Liverpool Street"]]
	var tp4 := TrackPath.between(bank, lst, 770.0, 100.0, 100.0)
	var all_bore := true
	for k in range(-5, 60):
		if _prof(tp4.cell_scene(k)) != RunScenery.BORE:
			all_bore = false
	check(all_bore, "Bank -> Liverpool Street: bore all the way")

	# --- every kind of cell builds, every surface has a material, and no cell is huge
	var run_node := TunnelRun.new()
	var scenes_t := [
		RunScenery.OPEN, RunScenery.BORE, RunScenery.BOX | (1 << 11), RunScenery.CUTTING | (3 << 3) | (3 << 5), RunScenery.CUTTING | (0 << 3) | (1 << 5) | (1 << 10),
		RunScenery.EMBANK | (3 << 3) | (3 << 5), RunScenery.EMBANK | (1 << 3) | (2 << 5) | (1 << 7), RunScenery.VIADUCT | (3 << 3) | (3 << 5) | (1 << 7),
		RunScenery.OPEN | (1 << 8) | (1 << 9), RunScenery.CUTTING | (3 << 3) | (3 << 5) | (1 << 8), RunScenery.EMBANK | (3 << 3) | (3 << 5) | (1 << 9) | (1 << 11),
	]
	var worst := 0
	for scene in scenes_t:
		for v in 2 * TunnelRun.N_VAR:
			for cls in [0, 5]:
				var kit: MeshKit = run_node._cell_kit(((cls + 16) << 18) | (scene << 3) | v)
				worst = maxi(worst, kit.triangle_count())
				var mesh := run_node._finish(kit, 0)
				for si in mesh.get_surface_count():
					if mesh.surface_get_material(si) == null:
						check(false, "scene %x variant %d: surface %s has no material" % [scene, v, mesh.surface_get_name(si)])
	print("  info: the largest cell has %d triangles" % worst)
	check(worst < 6000, "no cell is huge (%d triangles)" % worst)
	run_node.free()

	# --- the running track beyond a platform agrees with the line's data: what the plan hands the module is the sections of the neighbouring hop
	for nm in ["Amersham", "Willesden Green", "Baker Street", "Stratford", "Hammersmith (H&C)", "Bank"]:
		if not Net.name_to_idx.has(nm):
			continue
		var plan := StationPlan.for_station(Net.name_to_idx[nm])
		var sid: String = Net.station_ids[Net.name_to_idx[nm]]
		var n_ext := 0
		for mi in plan.modules.size():
			var ext: Array = plan.modules[mi].get("ext", [])
			check(ext.size() == (plan.modules[mi]["faces"] as Array).size(), "%s module %d: an ext entry per face" % [nm, mi])
			for e in ext:
				for end in ["w", "e"]:
					var l: Array = e[end]
					if l.is_empty():
						continue
					n_ext += 1
					var total := 0.0
					for r in l:
						total += float(r[1])
					check(total > 100.0, "%s: the stretch beyond the %s end is %.0f m long" % [nm, end, total])
		print("  info: %s has %d stretches beyond its platform ends" % [nm, n_ext])
		check(n_ext > 0, "%s: has a neighbour beyond a platform end" % nm)
		# the two tracks of a module have the same on each end
		for mi in plan.modules.size():
			var ext2: Array = plan.modules[mi].get("ext", [])
			if ext2.size() == 2:
				for end in ["w", "e"]:
					check((ext2[0][end] as Array).is_empty() == (ext2[1][end] as Array).is_empty(), "%s: both tracks of module %d have (or lack) the %s end" % [nm, mi, end])
		# a module with a daylight stretch beyond a platform end builds, and has its sky
		var st := Station.new()
		add_child(st)
		st.build(plan)
		for pm in st.modules:
			var holder: Node = (pm as PlatformModule).get_node_or_null("Outdoors")
			check((pm as PlatformModule)._open_xs.is_empty() or holder != null, "%s: sky over the open stretches" % nm)
			var shell := (pm as PlatformModule).get_node_or_null("Shell") as MeshInstance3D
			if shell != null:
				for si in shell.mesh.get_surface_count():
					check(shell.mesh.surface_get_material(si) != null, "%s: surface %s has a material" % [nm, shell.mesh.surface_get_name(si)])
		st.queue_free()
	print("OK" if ok else "FAILED")
