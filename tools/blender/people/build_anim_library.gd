extends SceneTree
## Builds assets/people/anims/people_anims.res (AnimationLibrary) from build/people_tmp/anims_raw.json written by make_anims.py.
##   godot --headless --path build/sandbox_people --script res://tools/build_anim_library.gd -- <raw.json> <out.res>
## (the script lives in tools/blender/people/ and is copied to the sandbox project's tools/ dir by sync_sandbox.sh)
##
## Track paths are  Skeleton3D:<bone>  relative to the AnimationPlayer root_node, which PersonModel sets to the node
## that contains the glb's Skeleton3D child (the glb's "Armature" node).  Bone tracks are rotation_3d tracks holding the
## bone's absolute local rotation (all rest orientations are identity), plus one position_3d track on "pelvis" that is
## scaled by Skeleton3D.motion_scale (character pelvis height / reference pelvis height).
func _init():
	var args := OS.get_cmdline_user_args()
	var raw_path: String = args[0] if args.size() > 0 else "/home/msant/Projects/Personal/underground-sim/build/people_tmp/anims_raw.json"
	var out_path: String = args[1] if args.size() > 1 else "/home/msant/Projects/Personal/underground-sim/assets/people/anims/people_anims.res"
	var data = JSON.parse_string(FileAccess.get_file_as_string(raw_path))
	var fps: float = data["fps"]
	var lib := AnimationLibrary.new()
	var n_tracks := 0
	for cname in data["clips"]:
		var c: Dictionary = data["clips"][cname]
		var anim := Animation.new()
		var frames: int = c["frames"]
		anim.length = float(frames - 1) / fps
		anim.loop_mode = Animation.LOOP_LINEAR if c["loop"] else Animation.LOOP_NONE
		anim.step = 1.0 / fps
		for bone in c["tracks"]:
			var keys: Array = c["tracks"][bone]
			var t := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(t, NodePath("Skeleton3D:" + bone))
			anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
			for k in keys.size():
				var q = keys[k]
				anim.rotation_track_insert_key(t, float(k) / fps, Quaternion(q[0], q[1], q[2], q[3]).normalized())
			n_tracks += 1
		var pt := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(pt, NodePath("Skeleton3D:pelvis"))
		anim.track_set_interpolation_type(pt, Animation.INTERPOLATION_LINEAR)
		var pel: Array = c["pelvis"]
		for k in pel.size():
			var p = pel[k]
			anim.position_track_insert_key(pt, float(k) / fps, Vector3(p[0], p[1], p[2]))
		lib.add_animation(StringName(cname), anim)
	var err := ResourceSaver.save(lib, out_path)
	print("saved ", out_path, " clips=", data["clips"].size(), " tracks=", n_tracks, " err=", err)
	quit()
