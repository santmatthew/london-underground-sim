class_name TunnelRun
extends Node3D
## Endless running tunnel used while riding between stations. The train stays fixed; this node's segments scroll past.
## Cross-section is identical (relative to the track) to the running tunnel in PlatformModule so the hand-over to a station is invisible.
## Local frame: the train's track is along +x at z = track_z; y = 0 is the platform-surface level (rail head at -0.9).

const SEG_LEN := 12.0
const N_SEG := 22

var track_z := 6.45          # world z of the track relative to this node
var side := 1.0              # +1: platform (absent) toward -z, like module face A
var speed := 0.0             # m/s the scenery moves toward -x (train moving toward +x)
var direction := 1.0         # train travel direction sign along x
var offset := 0.0            # accumulated distance
var limit_ahead := INF       # scenery is not shown farther than this distance ahead of the train centre (station approach)
var segs: Array = []
var _prof_mesh: ArrayMesh
var _variants: Array = []
var _pw := PlatformModule.PW_RUN
var _light_phase := 0.0


func setup(wall_mat := "tile_white") -> void:
	# one segment mesh built with the same profile as the platform module's running tunnel
	var kit := MeshKit.new()
	kit.seed_rng(3)
	var zfar := PlatformModule.GAP * 0.5 + _pw + PlatformModule.TRACK_TO_EDGE + PlatformModule.TRACK_TO_WALL
	var ztrack := zfar - PlatformModule.TRACK_TO_WALL
	var zwall_run := zfar - (PlatformModule.TRACK_TO_WALL + PlatformModule.TRACK_TO_EDGE + PlatformModule.PW_RUN)
	# build in "face A" coordinates (s = +1) then position the whole node so ztrack lands on track_z
	var prof := _profile(zwall_run, zfar)
	kit.sweep_x(wall_mat, prof, -SEG_LEN * 0.5, SEG_LEN * 0.5, 0.0, false, SEG_LEN)
	# platform-side wall
	kit.wall(wall_mat, Vector3(-SEG_LEN * 0.5, 0, zwall_run), Vector3(SEG_LEN * 0.5, 0, zwall_run), PlatformModule.BED_Y, PlatformModule.SPRING_Y, 0.0)
	# bed
	kit.horiz("trackbed", -SEG_LEN * 0.5, SEG_LEN * 0.5, zwall_run, zfar, PlatformModule.BED_Y, true, PlatformModule.BED_Y)
	# rails + sleepers
	for dz in [-0.7175, 0.7175]:
		kit.box("rail", Vector3(0, PlatformModule.RAIL_Y - 0.08, ztrack + dz), Vector3(SEG_LEN, 0.16, 0.07), PlatformModule.BED_Y)
	kit.box("rail", Vector3(0, PlatformModule.RAIL_Y - 0.07, ztrack), Vector3(SEG_LEN, 0.10, 0.06), PlatformModule.BED_Y)
	kit.box("rail", Vector3(0, PlatformModule.RAIL_Y - 0.07, ztrack - 1.05), Vector3(SEG_LEN, 0.10, 0.06), PlatformModule.BED_Y)
	kit.horiz("track_sleepers", -SEG_LEN * 0.5, SEG_LEN * 0.5, ztrack - 1.3, ztrack + 1.3, PlatformModule.BED_Y + 0.004, true, PlatformModule.BED_Y)
	# cable trays on the track-side wall and crown lights
	kit.box("metal", Vector3(0, 0.9, zfar - 0.15), Vector3(SEG_LEN, 0.08, 0.3), 0.0)
	kit.box("metal", Vector3(0, 0.45, zfar - 0.15), Vector3(SEG_LEN, 0.08, 0.3), 0.0)
	kit.box("metal", Vector3(0, 1.4, zwall_run + 0.15), Vector3(SEG_LEN, 0.08, 0.3), 0.0)
	var zc := (zwall_run + zfar) * 0.5
	kit.box("light_emissive", Vector3(0, PlatformModule.SPRING_Y + PlatformModule.RISE - 0.06, zc), Vector3(1.2, 0.06, 0.25), 0.0)
	var mats := {}
	for k in kit.surfaces.keys():
		mats[k] = Mats.get_mat(k)
	_prof_mesh = kit.build(mats)
	_variants = [_prof_mesh]
	# variants that add detail to a copy of the base geometry
	for v in 3:
		var k2 := MeshKit.new()
		k2.seed_rng(40 + v)
		match v:
			0:   # signal post with red/green lamps and a cable junction box on the track-side wall
				k2.box("metal", Vector3(-2.0, 1.1, zfar - 0.35), Vector3(0.12, 2.2, 0.12), 0.0)
				k2.box("light_emissive_red", Vector3(-2.0, 1.85, zfar - 0.5), Vector3(0.2, 0.2, 0.05), 0.0)
				k2.box("light_emissive_green", Vector3(-2.0, 1.5, zfar - 0.5), Vector3(0.2, 0.2, 0.05), 0.0)
				k2.box("metal", Vector3(3.0, 0.9, zfar - 0.2), Vector3(0.5, 0.6, 0.3), 0.0)
			1:   # blue emergency light + dark cross-passage doorway on the far wall
				k2.box("light_emissive_blue", Vector3(0.0, 2.0, zfar - 0.1), Vector3(0.5, 0.18, 0.06), 0.0)
				k2.box("black", Vector3(0.0, 0.85, zfar - 0.02), Vector3(1.6, 1.7, 0.04), 0.0)
			2:   # wall bracket / pipe run on the platform-side wall
				k2.box("metal", Vector3(0.0, 2.1, zwall_run + 0.12), Vector3(SEG_LEN, 0.12, 0.12), 0.0)
				k2.box("metal", Vector3(-3.0, 1.6, zwall_run + 0.08), Vector3(0.08, 1.0, 0.08), 0.0)
				k2.box("metal", Vector3(3.0, 1.6, zwall_run + 0.08), Vector3(0.08, 1.0, 0.08), 0.0)
		var m2 := {}
		for kk in k2.surfaces.keys():
			m2[kk] = Mats.get_mat(kk) if not kk.begins_with("light_emissive_") else _lamp_mat(kk)
		var extra := k2.build(m2)
		# merge: new ArrayMesh = base surfaces + extra surfaces
		var merged := ArrayMesh.new()
		for si in _prof_mesh.get_surface_count():
			merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _prof_mesh.surface_get_arrays(si))
			merged.surface_set_material(si, _prof_mesh.surface_get_material(si))
		for si in extra.get_surface_count():
			var idx := merged.get_surface_count()
			merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, extra.surface_get_arrays(si))
			merged.surface_set_material(idx, extra.surface_get_material(si))
		_variants.append(merged)
	for i in N_SEG:
		var mi := MeshInstance3D.new()
		var pick := 0
		if i % 7 == 3:
			pick = 1
		elif i % 11 == 5:
			pick = 2
		elif i % 5 == 1:
			pick = 3
		mi.mesh = _variants[pick]
		add_child(mi)
		segs.append(mi)
		var o := OmniLight3D.new()
		o.position = Vector3(0, PlatformModule.SPRING_Y + PlatformModule.RISE - 0.8, zc)
		o.light_energy = 2.2
		o.omni_range = 14.0
		o.omni_attenuation = 1.2
		o.light_color = Color(1.0, 0.96, 0.88)
		o.shadow_enabled = false
		mi.add_child(o)
	# the tunnel geometry was built in face-A coordinates: shift so the track sits at track_z
	position = Vector3(0, 0, track_z - ztrack)
	_place(0.0)


func _lamp_mat(key: String) -> Material:
	var col := Color(1, 0.1, 0.1) if key.ends_with("red") else (Color(0.1, 1, 0.3) if key.ends_with("green") else Color(0.2, 0.4, 1.0))
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 4.0
	return m


func _profile(za: float, zb: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var chord := zb - za
	var r := (chord * chord / 4.0 + PlatformModule.RISE * PlatformModule.RISE) / (2.0 * PlatformModule.RISE)
	var zc := (za + zb) * 0.5
	var yc := PlatformModule.SPRING_Y + PlatformModule.RISE - r
	var a0 := atan2(PlatformModule.SPRING_Y - yc, za - zc)
	var a1 := atan2(PlatformModule.SPRING_Y - yc, zb - zc)
	pts.append(Vector2(za, PlatformModule.SPRING_Y))
	for i in range(1, 16):
		var a := lerpf(a0, a1, float(i) / 16.0)
		pts.append(Vector2(zc + r * cos(a), yc + r * sin(a)))
	pts.append(Vector2(zb, PlatformModule.SPRING_Y))
	pts.append(Vector2(zb, PlatformModule.BED_Y))
	return pts


## advance the scenery by `dist` metres (train moves along `direction`)
func advance(dist: float) -> void:
	offset += dist
	_place(offset)


func _place(off: float) -> void:
	# segment i sits at x = (i - N/2) * SEG_LEN - direction * fposmod(off, SEG_LEN)  (scenery moves opposite to the train)
	var f := fposmod(off, SEG_LEN)
	for i in N_SEG:
		var x := (i - N_SEG / 2) * SEG_LEN - direction * f
		var mi: MeshInstance3D = segs[i]
		mi.position.x = x
		# hide segments beyond the station approach plane
		var ahead := x * direction
		mi.visible = ahead + SEG_LEN * 0.5 <= limit_ahead
