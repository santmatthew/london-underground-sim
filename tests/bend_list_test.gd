extends Node
## Lists the platform modules that are curved, over every station (PlatformCurve): station, line group, turn across the platform (degrees), radius, whether it had to be mirrored to fit.
func run():
	var n := 0
	var tot := 0
	for idx in Net.stations.size():
		var plan := StationPlan.for_station(idx)
		for mi in plan.modules.size():
			var b: Dictionary = plan.modules[mi].get("bend", {})
			tot += 1
			if b.is_empty():
				continue
			n += 1
			print("%-28s %-14s style %-5s open %-5s dh %6.1f  R %5.0f m  arc %3.0f..%3.0f%s" % [plan.name, plan.modules[mi]["group"], plan.modules[mi]["spec"]["style"], str(bool(plan.modules[mi]["spec"].get("character", {}).get("open", false))), b["dh"], 1.0 / absf(float(b["kappa"])), b["x0"], b["x1"], "  (mirrored)" if b.has("mirrored") else ""])
	print("%d of %d platform modules are curved" % [n, tot])
