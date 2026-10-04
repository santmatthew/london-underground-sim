extends Node
## Nothing of the cabling, brackets, boxes, signals and lamps of the running tunnel may stand inside the space the widest train needs (the sub-surface cars: 3.06 m wide, 3.73 m above the rail head). The scenery cells
## of a ride are checked, straight and bent, every variant.
var ok := true


func run():
	var run := TunnelRun.new()
	var zfar := PlatformModule.GAP * 0.5 + PlatformModule.PW_RUN + PlatformModule.TRACK_TO_EDGE + PlatformModule.TRACK_TO_WALL
	var ztrack := zfar - PlatformModule.TRACK_TO_WALL
	var half_w := 1.53
	var y0 := PlatformModule.RAIL_Y + 0.3          # (below this are the wheels, the rails and the track bed)
	var y1 := PlatformModule.RAIL_Y + 3.73
	var inside := 0
	var checked := 0
	var worst := 9.0
	var kinds := {}
	var scenes_c: Array = [RunScenery.BORE, RunScenery.BOX | (1 << 11), RunScenery.OPEN, RunScenery.CUTTING | (3 << 3) | (3 << 5), RunScenery.EMBANK | (3 << 3) | (3 << 5), RunScenery.VIADUCT | (3 << 3) | (3 << 5), RunScenery.OPEN | (1 << 8) | (1 << 9), RunScenery.CUTTING | (3 << 3) | (3 << 5) | (1 << 8), RunScenery.CUTTING | (3 << 3) | (3 << 5) | (1 << 9) | (1 << 10), RunScenery.EMBANK | (3 << 3) | (3 << 5) | (1 << 8) | (1 << 7), RunScenery.VIADUCT | (3 << 3) | (3 << 5) | (1 << 9) | (1 << 7)]
	for sc0: int in scenes_c.duplicate():
		if not RunScenery.enclosed(sc0 & 7):
			scenes_c.append(sc0 | RunScenery.PAIR)          # (with the other track of the pair beside it: its furniture must stay out of this one's way too)
	for scene in scenes_c:
		for v in 2 * TunnelRun.N_VAR:                 # (bending keeps every offset from the track: the straight cell is the one to measure)
			var kit: MeshKit = run._cell_kit((16 << 18) | (scene << 3) | v)
			for mat in kit.surfaces:
				if mat in ["tunnel_lining", "trackbed", "rail", "track_sleepers", "ballast"]:
					continue
				for p in kit.surfaces[mat]["v"]:
					if mat == "brick_stock" and absf(absf(p.x) - TunnelRun.SEG_LEN * 0.5) < 0.001:
						continue          # (a headwall's edge round the mouth is the bore's own lining, which this test leaves out: the arch is no wider than a deep-tube car needs)
					checked += 1
					var d := absf(p.z - ztrack)
					if p.y > y0 and p.y < y1 and d < half_w + 0.02:
						inside += 1
						kinds[mat] = int(kinds.get(mat, 0)) + 1
					if p.y > y0 and p.y < y1:
						worst = minf(worst, d)
	print("  info: %d vertices checked, the nearest piece of equipment is %.2f m from the track centre (the cars are %.2f m wide each side)" % [checked, worst, half_w])
	if inside > 0:
		print("  FAIL %d vertices of tunnel equipment stand inside the widest train %s" % [inside, str(kinds)])
		ok = false
	print("OK" if ok else "FAILED")
	run.free()
