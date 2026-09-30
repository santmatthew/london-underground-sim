extends Node
## Every file in data/layouts/ must belong to a station and compile into an authored plan (a wrong NaPTAN code would silently fall back to the
## generated layout). Prints one line per file and a total.
## args: --station="Victoria" (or a NaPTAN code): only that one, and compile errors are printed ("BAD ...")   --list: "name|halls|naptan" lines for scripts
func run():
	var only := ""
	var list := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): only = a.substr(10)
		if a == "--list": list = true
	Timetable.build(1)
	var dir := DirAccess.open("res://data/layouts")
	var bad := 0
	var n := 0
	var files := dir.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var naptan := f.get_basename()
		var idx := -1
		for i in Net.station_ids.size():
			if Net.station_ids[i] == naptan:
				idx = i
				break
		if only != "" and only != naptan and (idx < 0 or Net.station_name(idx) != only):
			continue
		n += 1
		if idx < 0:
			print("  BAD  %s: no station with this code" % f)
			bad += 1
			continue
		var plan := StationPlan.for_station(idx)
		if not plan.authored:
			print("  BAD  %s (%s): did not compile into an authored plan (see the ERROR line above)" % [f, plan.name])
			bad += 1
			continue
		if list:
			print("LAYOUT|%s|%d|%s" % [plan.name, plan.gatelines.size(), naptan])
		else:
			print("  ok   %-13s %-28s %d halls, %d modules, %d street doors" % [naptan, plan.name, plan.gatelines.size(), plan.modules.size(), plan.street_doors.size()])
	if only != "" and n == 0:
		print("  BAD  no layout file for %s" % only)
		bad += 1
	if not list:
		print("layouts: %d files, %d bad" % [n, bad])
