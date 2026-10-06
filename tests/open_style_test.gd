extends Node3D
## The photo-authored surface stations (Loughton, Kew Gardens, Boston Manor, Northwick Park): their styles reach the module (roof kind, spans, columns, bridge) and the roof helpers
## (what is overhead where: soffit_y, snap_x, covered) answer sensibly.
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func _module(name: String) -> PlatformModule:
	var st := Station.new()
	add_child(st)
	st.build(StationPlan.for_station(Net.name_to_idx[name]))
	return st.modules[0]


func run():
	Timetable.build(1)
	var pm := _module("Loughton")
	check(pm.open and String(pm.roof_info.get("kind")) == "mushroom", "Loughton: open platform with umbrella roofs")
	var caps: Array = pm.roof_info["caps"]
	check(caps.size() >= 6, "Loughton: %d umbrellas" % caps.size())
	check(pm.column_zs == [0.0], "Loughton: one row of columns on the centre line")
	var c0: float = caps[1]
	var under := PlatformOpen.soffit_y(pm, c0 + 2.0, 0.0)
	check(not is_nan(under) and under < PlatformOpen.roof_h(pm.open_style) and under > 2.2, "Loughton: dished underside under a cap (%.2f m)" % under)
	check(is_nan(PlatformOpen.soffit_y(pm, c0 + 6.0, 0.0)), "Loughton: open sky between two umbrellas")
	var sn := PlatformOpen.snap_x(pm, c0 + 6.0, 1.0)
	check(PlatformOpen.covered(pm, sn), "Loughton: a board meant for the gap is moved under a roof (%.1f -> %.1f)" % [c0 + 6.0, sn])
	pm = _module("Kew Gardens")
	check(pm.roof_spans.size() == 3 and String(pm.roof_info.get("kind")) == "valanced", "Kew Gardens: three separate canopy sections")
	var has_bridge := false
	for k in pm.kit.surfaces.keys():
		if String(k).contains("bridge_panel"):
			has_bridge = true
	check(has_bridge, "Kew Gardens: the footbridge is in the module's mesh")
	pm = _module("Boston Manor")
	check(String(pm.roof_info.get("kind")) == "gable" and pm.roof_spans.size() == 1, "Boston Manor: one long pitched roof")
	var h := PlatformOpen.roof_h(pm.open_style)
	# (Boston Manor is a pair of side platforms now - Piccadilly's own platforms, confirmed by the layout codes of the Underground Line Guide - so each module's gable is over its own platform: the ridge is on the middle of the roof's reach, the eaves at its edge)
	var zm: float = float(pm.roof_info["zm"])
	var zc: float = float(pm.roof_info["zc"])
	check(absf(PlatformOpen.soffit_y(pm, 0.0, zm) - (h + 1.0)) < 0.01 and absf(PlatformOpen.soffit_y(pm, 0.0, zm + zc * 0.999) - h) < 0.02, "Boston Manor: the soffit rises 1 m from the eaves to the ridge (ridge z %.1f, half width %.1f)" % [zm, zc])
	pm = _module("Northwick Park")
	check(pm.roof_spans.size() == 3, "Northwick Park: two shelters and the entry roof")
	var mid_gap := -77.0 + 154.0 * 0.40
	check(not PlatformOpen.covered(pm, mid_gap), "Northwick Park: no roof between the shelters")
	# every other open-air station keeps the full-length roof
	pm = _module("Acton Town")
	check(pm.open and pm.roof_info.get("kind") != "mushroom" and PlatformOpen.covered(pm, 0.0), "Acton Town: unchanged full-length roof")
	print("OK" if ok else "FAILED")
