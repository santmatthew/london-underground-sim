extends Node
## Every platform of the network has a place in the station: for each station and each platform id the plan has a face ("pid#0"), and for a terminal platform both faces (a terminating train may
## use either). --all also lists the stations of the other lines that lack one (known, older gaps); the test itself fails only for the Elizabeth line.
var ok := true


func run():
	var all := OS.get_cmdline_user_args().has("--all")
	var bad_el := 0
	var other := 0
	for idx in Net.stations.size():
		var plan := StationPlan.for_station(idx)
		var st: Dictionary = Net.stations[idx]
		for pid in st["platforms"]:
			var pl: Dictionary = st["platforms"][pid]
			var want: Array = ["%s#0" % pid]
			if pl["terminal"]:
				want.append("%s#1" % pid)
			for k in want:
				if not plan.faces.has(k):
					var is_el := String(pid).begins_with("elizabeth")
					if is_el:
						bad_el += 1
						print("  FAIL %s: no face %s" % [plan.name, k])
					else:
						other += 1
						if all:
							print("  (older gap) %s: no face %s" % [plan.name, k])
	print("  %d Elizabeth line platform faces missing; %d faces of other lines missing (run with --all to list them)" % [bad_el, other])
	print("OK" if bad_el == 0 else "FAILED")
