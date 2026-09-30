extends Node
## Every file in data/layouts/ must belong to a station and compile into an authored plan (a wrong NaPTAN code would silently fall back to the
## generated layout). Prints one line per file and a total.
func run():
	Timetable.build(1)
	var dir := DirAccess.open("res://data/layouts")
	var bad := 0
	var n := 0
	var files := dir.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		n += 1
		var naptan := f.get_basename()
		var idx := -1
		for i in Net.station_ids.size():
			if Net.station_ids[i] == naptan:
				idx = i
				break
		if idx < 0:
			print("  BAD  %s: no station with this code" % f)
			bad += 1
			continue
		var plan := StationPlan.for_station(idx)
		if not plan.authored:
			print("  BAD  %s (%s): did not compile into an authored plan" % [f, plan.name])
			bad += 1
			continue
		print("  ok   %-13s %-28s %d halls, %d modules, %d street doors" % [naptan, plan.name, plan.gatelines.size(), plan.modules.size(), plan.street_doors.size()])
	print("layouts: %d files, %d bad" % [n, bad])
