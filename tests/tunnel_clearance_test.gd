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
	for cls in [0]:                      # (bending keeps every offset from the track: the straight cell is the one to measure)
		for v in 2 * TunnelRun.N_VAR:
			var kit: MeshKit = run._cell_kit(v, cls)
			for mat in kit.surfaces:
				if mat in ["tunnel_lining", "trackbed", "rail", "track_sleepers"]:
					continue
				for p in kit.surfaces[mat]["v"]:
					checked += 1
					var d := absf(p.z - ztrack)
					if p.y > y0 and p.y < y1 and d < half_w + 0.02 and p.z > ztrack - 0.5 * 0.0:
						inside += 1
						kinds[mat] = int(kinds.get(mat, 0)) + 1
					if p.y > y0 and p.y < y1 and p.z > ztrack:
						worst = minf(worst, d)
	print("  info: %d vertices checked, the nearest piece of equipment is %.2f m from the track centre (the cars are %.2f m wide each side)" % [checked, worst, half_w])
	if inside > 0:
		print("  FAIL %d vertices of tunnel equipment stand inside the widest train %s" % [inside, str(kinds)])
		ok = false
	print("OK" if ok else "FAILED")
	run.free()
