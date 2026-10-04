extends Node3D
## The cells of the ride's scenery join: where cell k leaves the track (its mesh bent by its curvature class, then placed on the path) is where cell k + 1 takes it up - left turns and right turns, for a platform
## on the left of the train and on the right (the cells are mirrored then). Measured on the track centre line at the cell ends.
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	var ztrack := PlatformModule.GAP * 0.5 + PlatformModule.PW_RUN + PlatformModule.TRACK_TO_EDGE
	for mirror in [false, true]:
		for cls in [3, 14, -3, -14]:
			var ks := PackedFloat32Array()
			ks.resize(60)
			for k in 60:
				ks[k] = float(cls) * TrackPath.Q if (k >= 5 and k < 50) else 0.0
			var path := TrackPath.new()
			path._build(ks, 600.0)
			var t := TunnelRun.new()
			add_child(t)
			t.setup(path, mirror)
			while t.busy():
				await get_tree().process_frame
			t.place(300.0)
			await get_tree().process_frame
			t.place(300.0)
			var worst := 0.0
			for k in range(26, 34):
				var i := posmod(k, TunnelRun.N_SEG)
				var mi: MeshInstance3D = t.segs[i]
				var key: int = t._key_of(k)
				if not t._cache.has(key):
					continue
				var kc := ((key >> 18) - 16)
				var local_exit := Vector3(TunnelRun.SEG_LEN * 0.5, 0.0, ztrack)
				if kc != 0:
					local_exit = Bend.new(float(kc) * TrackPath.Q, -TunnelRun.SEG_LEN * 0.5, TunnelRun.SEG_LEN * 0.5, ztrack).map(local_exit)
				var world_exit: Vector3 = mi.transform * local_exit
				var want: Vector3 = path.pose(float(k) * TunnelRun.SEG_LEN + TunnelRun.SEG_LEN * 0.5).origin
				worst = maxf(worst, Vector2(world_exit.x - want.x, world_exit.z - want.z).length())
			check(worst < 0.05, "mirror %s, class %d: the cells meet the path within %.3f m" % [str(mirror), cls, worst])
			t.queue_free()
			await get_tree().process_frame
	print("OK" if ok else "FAILED")
