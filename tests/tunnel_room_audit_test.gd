extends Node
## Trains run along each platform's tunnel (tun_w west / tun_e east of the platform, visible only inside it). A room (hall, landing, passage) inside that
## volume means passengers see trains drive through it. Audits every station. args: --verbose
func run():
	Timetable.build(1)
	var verbose := "--verbose" in OS.get_cmdline_user_args()
	var bad_st := 0
	var total := 0
	for idx in Net.station_ids.size():
		var plan := StationPlan.for_station(idx)
		var issues: Array = []
		for mi in plan.modules.size():
			var m: Dictionary = plan.modules[mi]
			var spec: Dictionary = m["spec"]
			var L: float = spec["length"]
			var pw: float = spec["pw"]
			var tw: float = float(spec.get("tun_w", PlatformModule.TUNNEL_EXT))
			var te: float = float(spec.get("tun_e", PlatformModule.TUNNEL_EXT))
			var mp: Vector3 = m["pos"]
			var zfar := PlatformModule.GAP * 0.5 + pw + PlatformModule.TRACK_TO_EDGE + PlatformModule.TRACK_TO_WALL
			var top := (PlatformModule.BOX_H if spec.get("style", "arch") == "box" else PlatformModule.SPRING_Y + PlatformModule.RISE)
			# the tunnel volume: x beyond the platform ends only (the platform itself is the module), both tracks
			for side in [[mp.x - L * 0.5 - tw, mp.x - L * 0.5, "west"], [mp.x + L * 0.5, mp.x + L * 0.5 + te, "east"]]:
				for rm in plan.rooms:
					var r: Array = rm["rect"]
					var ry: float = rm["y"]
					var rh: float = rm["h"]
					var nm: String = rm["name"]
					if nm.begins_with("corridor") and absf(ry - mp.y) < 0.5 and float(m["lane_z"]) > r[2] - 0.1 and float(m["lane_z"]) < r[3] + 0.1:
						continue     # the module's own passage (it runs along the spine at the module's lane) meets the tunnel cap by design
					var ox := minf(side[1] as float, r[1]) - maxf(side[0] as float, r[0])
					var oz := minf(mp.z + zfar, r[3]) - maxf(mp.z - zfar, r[2])
					var oy := minf(mp.y + top, ry + rh) - maxf(mp.y + PlatformModule.BED_Y, ry)
					if ox > 0.3 and oz > 0.3 and oy > 0.3:
						issues.append("module %d %s tunnel overlaps room %s by %.1f x %.1f x %.1f m" % [mi, side[2], nm, ox, oz, oy])
		if not issues.is_empty():
			bad_st += 1
			total += issues.size()
			if verbose or bad_st <= 12:
				print("  %s (%s): %s" % [plan.name, "authored" if plan.authored else "generated", "; ".join(issues.slice(0, 3))])
	print("TOTAL: %d stations with tunnel/room overlaps, %d overlaps" % [bad_st, total])
