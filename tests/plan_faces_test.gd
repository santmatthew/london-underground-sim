extends Node
## Every platform of the network has a place in the station: for each station and each platform id the plan has a face ("pid#0"), and for a terminal platform both faces (a terminating train may
## use either), and the crowd can walk to each face (CrowdManager._open_node asks for the nodes "m<module>_open<0|1>_p<face>"). --all also lists the stations of the other lines that lack one (known, older gaps); the test itself fails only for the Elizabeth line.
var ok := true
var bad_nodes := 0


func run():
	var all := OS.get_cmdline_user_args().has("--all")
	var bad_el := 0
	var other := 0
	for idx in Net.stations.size():
		var plan := StationPlan.for_station(idx)
		var st: Dictionary = Net.stations[idx]
		for fk in plan.faces:
			var fc: Dictionary = plan.faces[fk]
			for oi in 2:
				var nn := "m%d_open%d_p%d" % [int(fc["module"]), oi, int(fc["face"])]
				if not plan.node_idx.has(nn):
					bad_nodes += 1
					print("  FAIL %s: face %s has no node %s" % [plan.name, fk, nn])
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
	print("  %d faces have no platform-entry node for the crowd" % bad_nodes)
	print("  %d Elizabeth line platform faces missing; %d faces of other lines missing (run with --all to list them)" % [bad_el, other])
	print("OK" if bad_el == 0 and bad_nodes == 0 else "FAILED")
