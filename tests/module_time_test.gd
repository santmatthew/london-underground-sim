extends Node3D
## How long a platform module takes to build (the first synchronous stretch of Station.build_async is one module's tunnel), with and without the running track beyond its ends (spec "ext"): --station="Theydon Bois"
func _ready() -> void:
	var sname := "Theydon Bois"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): sname = a.substr(10)
	Timetable.build(1)
	var plan := StationPlan.for_station(Net.name_to_idx[sname])
	for rep in 3:
		for with_ext in [true, false]:
			var tot := 0.0
			for m in plan.modules:
				var spec: Dictionary = (m["spec"] as Dictionary).duplicate()
				spec["ext"] = m.get("ext", []) if with_ext else []
				spec["nb"] = []
				spec["bend"] = m.get("bend", {})
				var pm := PlatformModule.new()
				add_child(pm)
				var t0 := Time.get_ticks_usec()
				await pm.build(spec, false)
				tot += float(Time.get_ticks_usec() - t0) / 1000.0
				pm.queue_free()
			print("MODTIME rep %d %s ext: %.1f ms over %d modules" % [rep, "with" if with_ext else "without", tot, plan.modules.size()])
	get_tree().quit()
