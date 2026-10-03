class_name TunnelRun
extends Node3D
## The running tunnel between two stations as the player sees it while riding. The train stays fixed; Ride moves this node (and the stations) past it along the TrackPath.
## Cross-section is identical (relative to the track) to the running tunnel in PlatformModule so the hand-over to a station is invisible.
## Local frame: the frame of the ride (TrackPath): the train's track is the path itself, y = 0 is the platform-surface level (rail head at -0.9). The scenery is a ring of SEG_LEN cells; cell k is
## centred on the path at k * SEG_LEN and curves with the path (a mesh per curvature step, built by worker threads the moment the path is known; straight ones at once).

const SEG_LEN := 12.0
const N_SEG := 22
const N_VAR := 3

var path: TrackPath
var mirror := false                  # the platform is on the RIGHT of the train (the cross-section is built with it on the left): the scenery is mirrored across the track
var segs: Array = []                 # the MeshInstance3D of cell k at index posmod(k, N_SEG)
var _lamps: Array = []               # the OmniLight3D of each instance
var _cells: PackedInt32Array = PackedInt32Array()
var _shown: PackedInt32Array = PackedInt32Array()      # the mesh key each instance shows (class * 16 + variant, 99999: the fallback)
var _zfar := 0.0
var _ztrack := 0.0
var _zwall_run := 0.0

static var _cache: Dictionary = {}          # class * 16 + variant -> ArrayMesh (shared by every ride)
static var _pending: Dictionary = {}        # key -> true while a worker builds it
static var _jobs: Array = []                # [task id, key, [MeshKit]] of the workers that are building them


func setup(p_path: TrackPath = null, p_mirror := false) -> void:
	path = p_path if p_path != null else TrackPath.new()
	mirror = p_mirror
	_zfar = PlatformModule.GAP * 0.5 + PlatformModule.PW_RUN + PlatformModule.TRACK_TO_EDGE + PlatformModule.TRACK_TO_WALL
	_ztrack = _zfar - PlatformModule.TRACK_TO_WALL
	_zwall_run = _zfar - (PlatformModule.TRACK_TO_WALL + PlatformModule.TRACK_TO_EDGE + PlatformModule.PW_RUN)
	# the straight meshes at once: variants 0..N_VAR-1 have a lamp in the middle of the cell, N_VAR..2*N_VAR-1 have none
	for v in 2 * N_VAR:
		if not _cache.has(v):
			_cache[v] = _finish(_cell_kit(v, 0), 0)
	_cells.resize(N_SEG)
	_shown.resize(N_SEG)
	for i in N_SEG:
		var mi := MeshInstance3D.new()
		mi.mesh = _cache[0]
		add_child(mi)
		segs.append(mi)
		var o := OmniLight3D.new()
		o.position = Vector3(0, TunnelDetail.LAMP_Y - 0.1, _zfar - 0.7)
		o.light_energy = 1.5
		o.omni_range = 9.0
		o.omni_attenuation = 1.3
		o.light_color = Color(1.0, 0.95, 0.85)
		o.shadow_enabled = false
		mi.add_child(o)
		_lamps.append(o)
		_cells[i] = -1000000
		_shown[i] = -1
	# the bent ones, for every curvature the path has
	var seen := {}
	for k in path.cell_count():
		var c := path.cell_class(k)
		if c != 0 and not seen.has(c):
			seen[c] = true
			for v in 2 * N_VAR:
				_request(c, v)
	place(0.0)


## the cell `k` of the tunnel (k * SEG_LEN along the path) as a MeshKit with the track at z = _ztrack; bent about the cell's entry when `cls` is not 0
func _cell_kit(v: int, cls: int) -> MeshKit:
	var zfar := PlatformModule.GAP * 0.5 + PlatformModule.PW_RUN + PlatformModule.TRACK_TO_EDGE + PlatformModule.TRACK_TO_WALL
	var ztrack := zfar - PlatformModule.TRACK_TO_WALL
	var zwall_run := zfar - (PlatformModule.TRACK_TO_WALL + PlatformModule.TRACK_TO_EDGE + PlatformModule.PW_RUN)
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
	if cls != 0:
		kit.bend(Bend.new(float(cls) * TrackPath.Q, -SEG_LEN * 0.5, SEG_LEN * 0.5, ztrack), 3.0)
	return kit


## the mesh of a kit (materials looked up on the main thread)
func _finish(kit: MeshKit, _cls: int) -> ArrayMesh:
	var mats := {}
	for k in kit.surfaces.keys():
		mats[k] = Mats.get_mat(k) if not k.begins_with("light_emissive_") else _lamp_mat(k)
	return kit.build(mats)


func _request(cls: int, v: int) -> void:
	var key := cls * 16 + v
	if _cache.has(key) or _pending.has(key):
		return
	var box: Array = [null]
	var id := WorkerThreadPool.add_task(func(): box[0] = _cell_kit(v, cls), false, "tunnel cell")
	_pending[key] = true
	_jobs.append([id, key, box])


## meshes the workers have finished become usable; instances that were showing the straight fallback are refreshed
func _collect() -> void:
	var any := false
	var left: Array = []
	for j in _jobs:
		if WorkerThreadPool.is_task_completed(j[0]):
			WorkerThreadPool.wait_for_task_completion(j[0])
			_cache[j[1]] = _finish(j[2][0], int(j[1]) / 16)
			_pending.erase(j[1])
			any = true
		else:
			left.append(j)
	_jobs = left
	if any:
		for i in N_SEG:
			_cells[i] = -1000000


func busy() -> bool:
	_collect()
	return not _jobs.is_empty()


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


## show the cells round the point `s` of the path (the player's car)
func place(s: float) -> void:
	_collect()
	var kc := int(roundf(s / SEG_LEN))
	for k in range(kc - N_SEG / 2, kc + N_SEG / 2):
		var i := posmod(k, N_SEG)
		if _cells[i] == k:
			continue
		_cells[i] = k
		var mi: MeshInstance3D = segs[i]
		var cls := path.cell_class(k) if k >= 0 else 0
		var lit := posmod(k, 2) == 0
		var v := (0 if lit else N_VAR) + posmod(k * 7 + (k >> 2), N_VAR)
		var key := cls * 16 + v
		if not _cache.has(key):
			key = v                                  # (not built yet: the straight cell)
			cls = 0
		mi.mesh = _cache[key]
		(_lamps[i] as OmniLight3D).visible = lit
		# the cell enters at s = k * SEG_LEN - SEG_LEN / 2 with the heading the path has there; its mesh runs from x = -SEG_LEN / 2 and has the track at z = _ztrack
		var s0 := float(k) * SEG_LEN - SEG_LEN * 0.5
		var pe := path.pose(s0)
		var fwd := pe.basis.x
		var flip := Transform3D(Basis.from_scale(Vector3(1.0, 1.0, -1.0 if mirror else 1.0)), Vector3.ZERO)
		mi.transform = Transform3D(pe.basis, pe.origin + fwd * (SEG_LEN * 0.5)) * flip * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -_ztrack))
		# the lamp hangs at the middle of the cell: where the bend puts it
		var lp := Vector3(0, TunnelDetail.LAMP_Y - 0.1, _zfar - 0.7)
		if cls != 0:
			lp = Bend.new(float(cls) * TrackPath.Q, -SEG_LEN * 0.5, SEG_LEN * 0.5, _ztrack).map(lp)
		(_lamps[i] as OmniLight3D).position = lp
