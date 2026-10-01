extends Node
func run():
	for n in ["gate_unit", "gate_wide", "ticket_machine_mfm", "clock", "poster_stand", "newspaper_stand", "assistance_booth", "platform_edge_marker", "signal_lamp", "help_point"]:
		var node := StationProps.inst(n)
		var surfs := 0
		var mats := {}
		var meshes := 0
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			meshes += 1
			var m := (mi as MeshInstance3D).mesh
			for s in m.get_surface_count():
				surfs += 1
				var mat := m.surface_get_material(s)
				mats[mat.get_rid().get_id() if mat else 0] = true
		print("SURF %-22s meshes %3d surfaces %3d distinct materials %3d" % [n, meshes, surfs, mats.size()])
		node.free()
