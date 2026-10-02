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
var _variants: Array = []
var _pw := PlatformModule.PW_RUN


## The scenery: segments of SEG_LEN of the bare bore (dark lining, cabling on both walls; TunnelDetail, the same as the running tunnel beyond a platform), some with a lamp. What a segment shows is a
## function of its absolute cell along the tunnel, so it does not change as the segments are recycled; a lamp hangs in every second cell (about every 24 m).
const N_VAR := 3

var _lamps: Array = []         # the OmniLight3D of each segment instance
var _cells: PackedInt32Array = PackedInt32Array()
var _zc := 0.0


func setup(_wall_mat := "tunnel_lining") -> void:
	var zfar := PlatformModule.GAP * 0.5 + _pw + PlatformModule.TRACK_TO_EDGE + PlatformModule.TRACK_TO_WALL
	var ztrack := zfar - PlatformModule.TRACK_TO_WALL
	var zwall_run := zfar - (PlatformModule.TRACK_TO_WALL + PlatformModule.TRACK_TO_EDGE + PlatformModule.PW_RUN)
	_zc = (zwall_run + zfar) * 0.5
	# variants 0..N_VAR-1 have a lamp in the middle of the segment, N_VAR..2*N_VAR-1 have none
	for v in 2 * N_VAR:
		_variants.append(_segment_mesh(v, zwall_run, zfar, ztrack))
	_cells.resize(N_SEG)
	for i in N_SEG:
		var mi := MeshInstance3D.new()
		mi.mesh = _variants[0]
		add_child(mi)
		segs.append(mi)
		var o := OmniLight3D.new()
		o.position = Vector3(0, TunnelDetail.LAMP_Y - 0.1, zfar - 0.7)
		o.light_energy = 1.5
		o.omni_range = 9.0
		o.omni_attenuation = 1.3
		o.light_color = Color(1.0, 0.95, 0.85)
		o.shadow_enabled = false
		mi.add_child(o)
		_lamps.append(o)
		_cells[i] = -1000000
	# the tunnel geometry was built in face-A coordinates: shift so the track sits at track_z
	position = Vector3(0, 0, track_z - ztrack)
	_place(0.0)


func _segment_mesh(v: int, zwall_run: float, zfar: float, ztrack: float) -> ArrayMesh:
	var kit := MeshKit.new()
	kit.seed_rng(3 + v)
	var prof := _profile(zwall_run, zfar)
	kit.sweep_x("tunnel_lining", prof, -SEG_LEN * 0.5, SEG_LEN * 0.5, 0.0, false, SEG_LEN)
	kit.wall("tunnel_lining", Vector3(-SEG_LEN * 0.5, 0, zwall_run), Vector3(SEG_LEN * 0.5, 0, zwall_run), PlatformModule.BED_Y, PlatformModule.SPRING_Y, 0.0)
	kit.horiz("trackbed", -SEG_LEN * 0.5, SEG_LEN * 0.5, zwall_run, zfar, PlatformModule.BED_Y, true, PlatformModule.BED_Y)
	for dz in [-0.7175, 0.7175]:
		kit.box("rail", Vector3(0, PlatformModule.RAIL_Y - 0.08, ztrack + dz), Vector3(SEG_LEN, 0.16, 0.07), PlatformModule.BED_Y)
	kit.box("rail", Vector3(0, PlatformModule.RAIL_Y - 0.07, ztrack), Vector3(SEG_LEN, 0.10, 0.06), PlatformModule.BED_Y)
	kit.box("rail", Vector3(0, PlatformModule.RAIL_Y - 0.07, ztrack - 1.05), Vector3(SEG_LEN, 0.10, 0.06), PlatformModule.BED_Y)
	kit.horiz("track_sleepers", -SEG_LEN * 0.5, SEG_LEN * 0.5, ztrack - 1.3, ztrack + 1.3, PlatformModule.BED_Y + 0.004, true, PlatformModule.BED_Y)
	TunnelDetail.add(kit, 1.0, -SEG_LEN * 0.5, SEG_LEN * 0.5, zwall_run, zfar, {"seed": 17 + v * 31, "lamps": [0.0] if v < N_VAR else []})
	match v % N_VAR:
		1:     # a signal post with its red and green lamps, on the track-side wall
			kit.box("steel", Vector3(-2.0, 1.1, zfar - 0.55), Vector3(0.12, 2.2, 0.12), 0.0)
			kit.box("light_emissive_red", Vector3(-2.0, 1.85, zfar - 0.68), Vector3(0.2, 0.2, 0.05), 0.0)
			kit.box("light_emissive_green", Vector3(-2.0, 1.5, zfar - 0.68), Vector3(0.2, 0.2, 0.05), 0.0)
		2:     # a blue emergency light by a dark cross-passage doorway in the far wall
			kit.box("light_emissive_blue", Vector3(1.5, 2.0, zwall_run + 0.1), Vector3(0.5, 0.18, 0.06), 0.0)
			kit.box("black", Vector3(1.5, 0.85, zwall_run + 0.03), Vector3(1.6, 1.7, 0.04), 0.0)
	var mats := {}
	for k in kit.surfaces.keys():
		mats[k] = Mats.get_mat(k) if not k.begins_with("light_emissive_") else _lamp_mat(k)
	return kit.build(mats)


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
	# segment i sits at x = (i - N/2) * SEG_LEN - direction * fposmod(off, SEG_LEN)  (scenery moves opposite to the train); the cell of the tunnel it shows is
	# i - N/2 + direction * floor(off / SEG_LEN)
	var f := fposmod(off, SEG_LEN)
	var k := int(floor(off / SEG_LEN))
	var dir := int(direction)
	for i in N_SEG:
		var x := (i - N_SEG / 2) * SEG_LEN - direction * f
		var mi: MeshInstance3D = segs[i]
		mi.position.x = x
		var cell := i - N_SEG / 2 + dir * k
		if _cells[i] != cell:
			_cells[i] = cell
			var lit := posmod(cell, 2) == 0
			mi.mesh = _variants[(0 if lit else N_VAR) + posmod(cell * 7 + (cell >> 2), N_VAR)]
			(_lamps[i] as OmniLight3D).visible = lit
		# hide segments beyond the station approach plane
		var ahead := x * direction
		mi.visible = ahead + SEG_LEN * 0.5 <= limit_ahead
