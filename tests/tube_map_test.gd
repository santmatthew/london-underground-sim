extends Control
## Renders the tube map overlay to build/map_*.png. args: --view=diagram|geo|both  --here="Oxford Circus"  --dest="Heathrow Terminals 2 & 3"
func _ready() -> void:
	var view := "both"
	var here_name := "Oxford Circus"
	var dest_name := "Stratford"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="): view = a.substr(7)
		if a.begins_with("--here="): here_name = a.substr(7)
		if a.begins_with("--dest="): dest_name = a.substr(7)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := TubeMap.new()
	add_child(m)
	m.set_anchors_preset(Control.PRESET_TOP_LEFT)
	m.position = Vector2.ZERO
	m.size = get_viewport_rect().size
	for i in 4: await get_tree().process_frame
	if Net.name_to_idx.has(here_name): m.here = Net.name_to_idx[here_name]
	if Net.name_to_idx.has(dest_name): m.dest = Net.name_to_idx[dest_name]
	var shots: Array = []
	if view in ["diagram", "both"]:
		shots.append(["diagram_overview", TubeMap.Mode.DIAGRAM, 15.0, false])
		shots.append(["diagram_centre", TubeMap.Mode.DIAGRAM, 30.0, true])
	if view in ["geo", "both"]:
		shots.append(["geo_overview", TubeMap.Mode.GEOGRAPHIC, 34.0, false])
	for sh in shots:
		m.mode = sh[1]
		m.zoom = sh[2]
		if sh[3] and m.here >= 0:
			m.focus_on(m.here)
		elif sh[1] == TubeMap.Mode.DIAGRAM:
			var lo := Vector2(1e9, 1e9)
			var hi := Vector2(-1e9, -1e9)
			for p in m._dp:
				lo = lo.min(p)
				hi = hi.max(p)
			m.center = (lo + hi) * 0.5
		else:
			m.center = Vector2.ZERO
		for i in 4: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://build/map_%s.png" % sh[0])
	get_tree().quit()
