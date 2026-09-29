extends Node3D
# godot ... res://tests/lineup.tscn -- <mode neutral|tunnel> <first> <per_shot> <shots> <outprefix> [cam: full|face] [clip]
var people: Array = []
func _ready():
	var a := OS.get_cmdline_user_args()
	var mode: String = a[0]; var first := int(a[1]); var per := int(a[2]); var shots := int(a[3]); var outp: String = a[4]
	var cam_mode: String = a[5] if a.size() > 5 else "full"
	var clip: String = a[6] if a.size() > 6 else "idle_stand_1"
	_setup_env(mode)
	var cam := Camera3D.new(); add_child(cam); cam.fov = 30 if cam_mode == "full" else 22
	cam.current = true
	for s in shots:
		for p in people: p.queue_free()
		people.clear()
		for k in per:
			var idx := first + s * per + k
			if idx >= PersonModel.count(): break
			var p := PersonModel.create(idx, 0)
			add_child(p)
			var x := (float(k) - (per - 1) * 0.5) * (1.0 if cam_mode == "full" else 0.55)
			p.position = Vector3(x, 0, 0)
			p.rotation.y = PI
			p.play(StringName(clip), 0.0)
			p.tick(0.5 + 0.3 * k)
			people.append(p)
		await get_tree().process_frame
		if cam_mode == "full":
			cam.position = Vector3(0, 1.0, 4.4 if per <= 4 else 3.4 + per * 0.5); cam.look_at(Vector3(0, 0.92, 0))
		else:
			cam.position = Vector3(0, 1.55, 1.8); cam.look_at(Vector3(0, 1.5, 0))
			# heads: adjust per character height
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [outp, s])
	get_tree().quit()

func _setup_env(mode: String):
	var env := Environment.new()
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	if mode == "neutral":
		env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.5, 0.52, 0.55)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.75, 0.75, 0.78); env.ambient_light_energy = 0.8
		var l := DirectionalLight3D.new(); add_child(l); l.rotation_degrees = Vector3(-35, 30, 0); l.light_energy = 1.1; l.shadow_enabled = true
		var l2 := DirectionalLight3D.new(); add_child(l2); l2.rotation_degrees = Vector3(-15, -140, 0); l2.light_energy = 0.35
		var fl := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(30, 30); fl.mesh = pm
		var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.4, 0.4, 0.42); fl.material_override = fm; add_child(fl)
	else:
		env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.02, 0.02, 0.025)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.35, 0.37, 0.4); env.ambient_light_energy = 0.5
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		# dark floor, white tiled wall behind, tube lights on the ceiling
		var fl := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(30, 30); fl.mesh = pm
		var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.06, 0.06, 0.065); fm.roughness = 0.35; fl.material_override = fm; add_child(fl)
		var wall := MeshInstance3D.new(); var wm := QuadMesh.new(); wm.size = Vector2(16, 4); wall.mesh = wm
		var wmat := StandardMaterial3D.new(); wmat.albedo_color = Color(0.85, 0.86, 0.84); wmat.roughness = 0.25; wall.material_override = wmat
		wall.position = Vector3(0, 2, -2.2); add_child(wall)
		var ceil := MeshInstance3D.new(); var cm := QuadMesh.new(); cm.size = Vector2(16, 12); ceil.mesh = cm
		var cmat := StandardMaterial3D.new(); cmat.albedo_color = Color(0.5, 0.5, 0.5); ceil.material_override = cmat
		ceil.position = Vector3(0, 3.2, 2); ceil.rotation.x = PI / 2; add_child(ceil)
		for i in 5:
			var tube := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(1.2, 0.05, 0.12); tube.mesh = bm
			var em := StandardMaterial3D.new(); em.emission_enabled = true; em.emission = Color(1, 1, 0.95); em.emission_energy_multiplier = 6.0; em.albedo_color = Color(1, 1, 1); tube.material_override = em
			tube.position = Vector3(-3.2 + i * 1.6, 3.15, 0.6); add_child(tube)
			var sp := SpotLight3D.new(); sp.position = Vector3(-3.2 + i * 1.6, 3.1, 0.6); sp.rotation_degrees = Vector3(-90, 0, 0)
			sp.spot_range = 6.0; sp.spot_angle = 60.0; sp.light_color = Color(0.92, 0.96, 1.0); sp.light_energy = 5.0; sp.shadow_enabled = true; add_child(sp)
