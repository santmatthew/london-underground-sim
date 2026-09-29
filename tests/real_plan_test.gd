extends Node
## Prints how real data shaped a station's plan. args: --stations="A|B"
func run():
	Timetable.build(1)
	var names := "Oxford Circus".split("|")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stations="): names = a.substr(11).split("|")
	for nm in names:
		var plan := StationPlan.for_station(Net.name_to_idx[nm])
		print("== ", nm, " kind ", plan.kind)
		print("platform numbers: ", plan.platform_no)
		print("street doors: ", plan.street_doors.map(func(d): return [d["id"], d.get("exit_ref", ""), d.get("exit_name", "")]))
		print("levels (depth below hall, modules): ", plan.escs.map(func(e): return snappedf(e["rise"], 0.1)), " modules y ", plan.modules.map(func(m): return snappedf(-(m["pos"] as Vector3).y, 0.1)))
		print("gates: ", plan.gates["n"], " escalator lanes per bank: ", plan.escs.map(func(e): return (e["lanes"] as Array).size()), " levels ", plan.escs.size(), " hall x ", plan.hall["rect"][0], "..", plan.hall["rect"][1])
