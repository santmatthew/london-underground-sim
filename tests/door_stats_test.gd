extends Node
## Which side the doors are on, over all faces of all stations: counts by line (a train that runs the face's canonical direction)
func run():
	Timetable.build(1)
	var by_line := {}
	var tot_l := 0
	var tot_r := 0
	for idx in Net.stations.size():
		var plan := StationPlan.for_station(idx)
		for k in plan.faces:
			var f: Dictionary = plan.faces[k]
			var canon := plan.canon_of(f)
			var side: float = f["side"]
			var right: bool = (-side) * float(canon) > 0.0
			var lid: String = f["line"]
			var d: Array = by_line.get(lid, [0, 0])
			d[0 if not right else 1] += 1
			by_line[lid] = d
			if right:
				tot_r += 1
			else:
				tot_l += 1
	for lid in by_line:
		print("DOORS %-18s left %4d  right %4d" % [lid, by_line[lid][0], by_line[lid][1]])
	print("DOORS total left %d right %d" % [tot_l, tot_r])
