extends Node
func run():
	Timetable.build(1)
	for nm in ["Acton Town", "Baker Street"]:
		var plan := StationPlan.for_station(Net.name_to_idx[nm])
		print("PLAN ", nm, " kind ", plan.kind)
		for mi in plan.modules.size():
			var m: Dictionary = plan.modules[mi]
			var spec: Dictionary = m["spec"]
			var zfar := PlatformModule.GAP * 0.5 + float(spec["pw"]) + PlatformModule.TRACK_TO_EDGE + PlatformModule.TRACK_TO_WALL
			print("PLAN  module %d level %s group %s pos %s L %.0f pw %.1f zfar %.1f tun_w %.1f lane_z %.1f style %s" % [mi, str(m["level"]), str(m["group"]), str(m["pos"].snapped(Vector3(0.1, 0.1, 0.1))), spec["length"], spec["pw"], zfar, float(spec.get("tun_w", 170.0)), float(m["lane_z"]), spec.get("style", "?")])
		for rm in plan.rooms:
			if str(rm["name"]).begins_with("corridor") or str(rm["name"]).begins_with("landing"):
				print("PLAN  room %s rect %s y %.1f h %.1f" % [rm["name"], str(rm["rect"]), rm["y"], rm["h"]])
