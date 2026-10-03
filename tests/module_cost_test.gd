extends Node
## Prints the triangle count and build time of each platform module of a station. args --station=Name
func run():
	var nm := "Bank"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--station="): nm = a.substr(10)
	var plan := StationPlan.for_station(Net.name_to_idx[nm])
	for i in plan.modules.size():
		var pm := PlatformModule.new()
		add_child(pm)
		var t0 := Time.get_ticks_msec()
		(plan.modules[i]["spec"] as Dictionary)["bend"] = plan.modules[i].get("bend", {})
		pm.build(plan.modules[i]["spec"])
		print("module %d: %d triangles, built in %d ms%s" % [i, pm.meta["tri_count"], Time.get_ticks_msec() - t0, (" (bending the shell: %d ms)" % pm.meta["bend_ms"]) if pm.meta.has("bend_ms") else ""])
