extends Node
## What the line geometry says each hop runs through (data "sec"), against the kind of station at each end: a hop between two deep-tube stations should be all tunnel, a hop between two
## open-air stations should not be. Prints the odd ones out (a list to check against OpenStreetMap, not a pass / fail), and totals. args --all prints every hop.
func run():
	Timetable.build(1)
	var kind := {}          # station id -> "deep" | "box" | "open"
	for i in Net.station_ids.size():
		var plan := StationPlan.for_station(i)
		var k := "deep"
		for m in plan.modules:
			var sp: Dictionary = m["spec"]
			if String(sp.get("style", "arch")) == "box":
				k = "open" if bool(sp.get("character", {}).get("open", false)) else "box"
		kind[Net.station_ids[i]] = k
	var pairs: Dictionary = TrackPath.data().get("pairs", {})
	var tot := {}
	var odd_deep := []
	var odd_open := []
	var no_sec := 0
	for key in pairs:
		var e: Dictionary = pairs[key]
		var ab: PackedStringArray = String(key).split(">")
		if not e.has("sec"):
			no_sec += 1
			continue
		var m_by := {}
		for r in e["sec"]:
			m_by[int(r[0])] = float(m_by.get(int(r[0]), 0.0)) + float(r[1])
			tot[int(r[0])] = float(tot.get(int(r[0]), 0.0)) + float(r[1])
		var L: float = e["len"]
		var ka: String = kind.get(ab[0], "?")
		var kb: String = kind.get(ab[1], "?")
		var tun := float(m_by.get(1, 0.0))
		if ka == "deep" and kb == "deep" and L - tun > 0.05 * L:
			odd_deep.append("%s -> %s (%s): %.0f of %.0f m not in tunnel %s" % [Net.stations[Net.station_ids.find(ab[0])]["name"], Net.stations[Net.station_ids.find(ab[1])]["name"], e.get("line", "?"), L - tun, L, str(e["sec"])])
		if ka == "open" and kb == "open" and tun > 0.3 * L:
			odd_open.append("%s -> %s (%s): %.0f of %.0f m in tunnel %s" % [Net.stations[Net.station_ids.find(ab[0])]["name"], Net.stations[Net.station_ids.find(ab[1])]["name"], e.get("line", "?"), tun, L, str(e["sec"])])
	print("pairs ", pairs.size(), " without sec ", no_sec, " total km by code ", {"open": snappedf(float(tot.get(0, 0.0)) / 1000.0, 0.1), "tunnel": snappedf(float(tot.get(1, 0.0)) / 1000.0, 0.1), "cutting": snappedf(float(tot.get(2, 0.0)) / 1000.0, 0.1), "embankment": snappedf(float(tot.get(3, 0.0)) / 1000.0, 0.1), "viaduct": snappedf(float(tot.get(4, 0.0)) / 1000.0, 0.1)})
	print("deep-deep hops with more than 5% outside a tunnel: ", odd_deep.size())
	for s in odd_deep:
		print("  ", s)
	print("open-air to open-air hops with more than 30% tunnel: ", odd_open.size())
	for s in odd_open:
		print("  ", s)
	print("OK")
