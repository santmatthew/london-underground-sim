extends Node3D
## The platform's front - the vertical face under the edge, from the platform down to the track bed - faces the track: from the opposite platform of a pair of side platforms (and from a train) it is seen,
## and a face that looks the other way is culled there and shows the sky under the edge (it was: MeshKit.wall shows the right of a -> b, and both calls had the platform's side).
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	Timetable.build(1)
	add_child(Env.make(0))
	for nm in ["Ickenham", "West Ealing", "Hounslow Central", "Greenford"]:          # (two pairs of side platforms, two islands)
		var idx: int = Net.name_to_idx[nm]
		var plan := StationPlan.for_station(idx)
		var st := Station.new()
		add_child(st)
		st.build(plan)
		for i in 2:
			await get_tree().physics_frame
		var faces_checked := 0
		for fk in plan.faces:
			var f: Dictionary = plan.faces[fk]
			var pm := st.get_node_or_null("Module%d" % int(f["module"])) as Node3D
			var shell := pm.get_node_or_null("Shell") as MeshInstance3D if pm != null else null
			if shell == null:
				continue
			var s := signf(float(f["track_z"]) - float(f["edge_z"]))          # (the track lies on this side of the edge, along z)
			var zedge: float = float(f["edge_z"]) - pm.position.z
			var mesh := shell.mesh as ArrayMesh
			var found := 0
			var wrong := 0
			for si in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(si)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for vi in vs.size():
					var v := vs[vi]
					# a vertex of the front: on the edge's line, between the platform and the bed, a face that stands upright
					if absf(v.z - zedge) < 0.001 and v.y < -0.3 and v.y > PlatformModule.BED_Y - 0.01 and absf(ns[vi].y) < 0.01 and absf(ns[vi].z) > 0.9:
						found += 1
						if signf(ns[vi].z) != s:
							wrong += 1
			check(found >= 2, "%s, %s: the platform's front is in the mesh (%d vertices)" % [nm, fk, found])
			check(wrong == 0, "%s, %s: the front faces the track (%d of %d vertices face the platform)" % [nm, fk, wrong, found])
			faces_checked += 1
		check(faces_checked == plan.faces.size(), "%s: every face's module was read (%d)" % [nm, faces_checked])
		st.queue_free()
		await get_tree().process_frame
	print("OK" if ok else "FAILED")
