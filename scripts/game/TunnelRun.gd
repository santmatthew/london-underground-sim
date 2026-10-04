class_name TunnelRun
extends Node3D
## The running tunnel between two stations as the player sees it while riding. The train stays fixed; Ride moves this node (and the stations) past it along the TrackPath.
## Cross-section is identical (relative to the track) to the running tunnel in PlatformModule so the hand-over to a station is invisible.
## Local frame: the frame of the ride (TrackPath): the train's track is the path itself, y = 0 is the platform-surface level (rail head at -0.9). The scenery is a ring of SEG_LEN cells; cell k is
## centred on the path at k * SEG_LEN and curves with the path (a mesh per curvature step). What a cell shows comes from the path (TrackPath.cell_scene): the deep-tube bore, or a cut-and-cover box, open
## land, a cutting, an embankment, a viaduct (RunScenery), with a sky and daylight over the open ones. Meshes are built by worker threads as the cells come into view (the ones at hand-over at once).

const SEG_LEN := 12.0
const N_SEG := 22
const N_VAR := 3
const MAX_TRIS := 1500000             # the shared mesh cache is cleared when it holds more triangles than this (a long session: start afresh rather than keep every curve of every line)

var path: TrackPath
var mirror := false                  # the platform is on the RIGHT of the train (the cross-section is built with it on the left): the scenery is mirrored across the track
var segs: Array = []                 # the MeshInstance3D of cell k at index posmod(k, N_SEG)
var _lamps: Array = []               # the OmniLight3D of each instance
var _cells: PackedInt32Array = PackedInt32Array()
var _dome: MeshInstance3D
var _day := 1.0
var _zfar := 0.0
var _ztrack := 0.0
var _zwall_run := 0.0

static var _cache: Dictionary = {}          # key (see _key) -> ArrayMesh (shared by every ride)
static var _pending: Dictionary = {}        # key -> true while a worker builds it
static var _jobs: Array = []                # [task id, key, [MeshKit]] of the workers that are building them
static var _cache_tris := 0                 # triangles in _cache


## `s_start`: the path distance of the player's car, where the cells are first wanted (the ones round it are built at once, the rest as they come into view)
func setup(p_path: TrackPath = null, p_mirror := false, s_start := 0.0) -> void:
	path = p_path if p_path != null else TrackPath.new()
	mirror = p_mirror
	_zfar = PlatformModule.GAP * 0.5 + PlatformModule.PW_RUN + PlatformModule.TRACK_TO_EDGE + PlatformModule.TRACK_TO_WALL
	_ztrack = _zfar - PlatformModule.TRACK_TO_WALL
	_zwall_run = _zfar - (PlatformModule.TRACK_TO_WALL + PlatformModule.TRACK_TO_EDGE + PlatformModule.PW_RUN)
	_day = PlatformOpen.daylight()
	RunScenery.refresh_day()
	if _cache_tris > MAX_TRIS:
		_cache.clear()
		_cache_tris = 0
	_cells.resize(N_SEG)
	for i in N_SEG:
		var mi := MeshInstance3D.new()
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
	# the sky over the open stretches
	_dome = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = PlatformOpen.SKY_R
	sm.height = PlatformOpen.SKY_R * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	_dome.mesh = sm
	_dome.material_override = PlatformOpen._sky_material(_day, PlatformOpen.sun())
	_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dome.visible = false
	add_child(_dome)
	# the cells round the player's car at once (straight ones: at hand-over from a station the track is straight), the rest as they come into view
	var kc0 := int(roundf(s_start / SEG_LEN))
	for k in range(kc0 - N_SEG / 2, kc0 + N_SEG / 2):
		var key := _key_of(k)
		if path.cell_class(k) == 0 and not _cache.has(key):
			_store(key, _cell_kit(key))
	place(s_start)


func _exit_tree() -> void:
	drain()


## Every worker task must be waited for (the engine corrupts memory at exit otherwise): when the last ride's scenery goes, so do the jobs that were still building cells; their meshes are kept
static func drain() -> void:
	for j in _jobs:
		WorkerThreadPool.wait_for_task_completion(j[0])
		if j[2][0] != null:
			_store(j[1], j[2][0])
		_pending.erase(j[1])
	_jobs.clear()


static func _store(key: int, kit: MeshKit) -> void:
	_cache_tris += kit.triangle_count()
	_cache[key] = _finish(kit)


## the scene of cell k as this ride builds it: the other track of the pair lies on the right of the train whatever side its doors are on (British trains keep left and meet the others on the right), which
## in the cross-section built with the platform on the left (-z) is the +z side, and in the mirrored one (the platform on the right) the side the mirror brings to the right, the -z side the pair is built on by default
func _scene_of(k: int) -> int:
	var sc := path.cell_scene(k)
	if not mirror and (sc & RunScenery.PAIR) != 0:
		sc |= RunScenery.PAIR_RIGHT
	return sc


## the mesh key of cell k: curvature class (bits 24-), scene (RunScenery, bits 3-23) and variant
## (a mirrored ride - the platform on the right - flips the cells across the track, so they are bent the other way to start with)
func _key_of(k: int) -> int:
	var cls := path.cell_class(k) * (-1 if mirror else 1)
	var sc := _scene_of(k)
	var lit := posmod(k, 2) == 0
	var v: int
	if sc == RunScenery.BORE:
		v = (0 if lit else N_VAR) + posmod(k * 7 + (k >> 2), N_VAR)
	elif RunScenery.enclosed(sc & 7):
		v = (0 if lit else N_VAR) + posmod(k, N_VAR)        # (a box tunnel: lamps in the lit ones)
	else:
		v = posmod(k, N_VAR)                                  # (in the open: the backdrops repeat every three cells, nothing else to vary)
	return ((cls + 16) << 25) | (sc << 3) | v


## the cell of mesh key `key` as a MeshKit with the track at z = _ztrack; bent about the cell's entry when its class is not 0
static func _cell_kit(key: int) -> MeshKit:
	var v := key & 7
	var sc := (key >> 3) & 0x3fffff
	var cls := (key >> 25) - 16
	var zfar := PlatformModule.GAP * 0.5 + PlatformModule.PW_RUN + PlatformModule.TRACK_TO_EDGE + PlatformModule.TRACK_TO_WALL
	var ztrack := zfar - PlatformModule.TRACK_TO_WALL
	var zwall_run := zfar - (PlatformModule.TRACK_TO_WALL + PlatformModule.TRACK_TO_EDGE + PlatformModule.PW_RUN)
	var kit := MeshKit.new()
	kit.seed_rng(3 + v)
	var prof := sc & 7
	if prof == RunScenery.BORE:
		var pr := RunScenery.arch_points(zwall_run, zfar)
		pr.append(Vector2(zfar, PlatformModule.BED_Y))
		kit.sweep_x("tunnel_lining", pr, -SEG_LEN * 0.5, SEG_LEN * 0.5, 0.0, false, SEG_LEN)
		kit.wall("tunnel_lining", Vector3(-SEG_LEN * 0.5, 0, zwall_run), Vector3(SEG_LEN * 0.5, 0, zwall_run), PlatformModule.BED_Y, PlatformModule.SPRING_Y, 0.0)
		kit.horiz("trackbed", -SEG_LEN * 0.5, SEG_LEN * 0.5, zwall_run, zfar, PlatformModule.BED_Y, true, PlatformModule.BED_Y)
	for dz in [-0.7175, 0.7175]:
		kit.box("rail", Vector3(0, PlatformModule.RAIL_Y - 0.08, ztrack + dz), Vector3(SEG_LEN, 0.16, 0.07), PlatformModule.BED_Y)
	kit.box("rail", Vector3(0, PlatformModule.RAIL_Y - 0.07, ztrack), Vector3(SEG_LEN, 0.10, 0.06), PlatformModule.BED_Y)
	kit.box("rail", Vector3(0, PlatformModule.RAIL_Y - 0.07, ztrack - 1.05), Vector3(SEG_LEN, 0.10, 0.06), PlatformModule.BED_Y)
	kit.horiz("track_sleepers", -SEG_LEN * 0.5, SEG_LEN * 0.5, ztrack - 1.3, ztrack + 1.3, PlatformModule.BED_Y + 0.004, true, PlatformModule.BED_Y)
	if prof == RunScenery.BORE:
		TunnelDetail.add(kit, 1.0, -SEG_LEN * 0.5, SEG_LEN * 0.5, zwall_run, zfar, {"seed": 17 + v * 31, "lamps": [0.0] if v < N_VAR else []})
		match v % N_VAR:
			1:     # a signal post with its red and green lamps, on the track-side wall
				kit.box("steel", Vector3(-2.0, 1.1, zfar - 0.07), Vector3(0.12, 2.2, 0.10), 0.0)
				kit.box("light_emissive_red", Vector3(-2.0, 1.85, zfar - 0.135), Vector3(0.2, 0.2, 0.04), 0.0)
				kit.box("light_emissive_green", Vector3(-2.0, 1.5, zfar - 0.135), Vector3(0.2, 0.2, 0.04), 0.0)
			2:     # a blue emergency light by a dark cross-passage doorway in the far wall
				kit.box("light_emissive_blue", Vector3(1.5, 2.0, zwall_run + 0.1), Vector3(0.5, 0.18, 0.06), 0.0)
				kit.box("black", Vector3(1.5, 0.85, zwall_run + 0.03), Vector3(1.6, 1.7, 0.04), 0.0)
	else:
		RunScenery.add_scene(kit, sc, v, -SEG_LEN * 0.5, SEG_LEN * 0.5, ztrack, {"u0": float(v % N_VAR) * SEG_LEN - SEG_LEN * 0.5})
	if cls != 0:
		kit.bend(Bend.new(float(cls) * TrackPath.Q, -SEG_LEN * 0.5, SEG_LEN * 0.5, ztrack), 3.0)
	return kit


## the mesh of a kit (materials looked up on the main thread)
static func _finish(kit: MeshKit) -> ArrayMesh:
	var mats := {}
	for k in kit.surfaces.keys():
		if k.begins_with("light_emissive_"):
			mats[k] = RunScenery.lamp_material(k)
		elif k.begins_with("bd:"):
			mats[k] = RunScenery.material(k)
		elif k.begins_with("char:"):
			mats[k] = StationCharacter.material(k)
		else:
			mats[k] = Mats.get_mat(k)
	return kit.build(mats)


func _request(key: int) -> void:
	if _cache.has(key) or _pending.has(key):
		return
	var box: Array = [null]
	var id := WorkerThreadPool.add_task(func(): box[0] = TunnelRun._cell_kit(key), false, "tunnel cell")
	_pending[key] = true
	_jobs.append([id, key, box])


## meshes the workers have finished become usable; instances that were showing a stand-in are refreshed
func _collect() -> void:
	var any := false
	var left: Array = []
	for j in _jobs:
		if WorkerThreadPool.is_task_completed(j[0]):
			WorkerThreadPool.wait_for_task_completion(j[0])
			if j[2][0] != null:
				_store(j[1], j[2][0])
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


## show the cells round the point `s` of the path (the player's car)
func place(s: float) -> void:
	_collect()
	var kc := int(roundf(s / SEG_LEN))
	# the cells about to come into view are built ahead
	for k in range(kc + N_SEG / 2, kc + N_SEG / 2 + 9):
		var key_a := _key_of(k)
		if not _cache.has(key_a):
			_request(key_a)
	var any_open := false
	for k in range(kc - N_SEG / 2, kc + N_SEG / 2):
		var i := posmod(k, N_SEG)
		var sc := _scene_of(k)
		if not RunScenery.enclosed(sc & 7):
			any_open = true
		if _cells[i] == k:
			continue
		_cells[i] = k
		var mi: MeshInstance3D = segs[i]
		var cls := path.cell_class(k)
		var key := _key_of(k)
		var lit := posmod(k, 2) == 0
		if not _cache.has(key):
			_request(key)
			# (not built yet: the same scene straight, else the bore)
			var v := key & 7
			var alt := (16 << 25) | (sc << 3) | v
			cls = 0
			key = alt if _cache.has(alt) else ((16 << 25) | (RunScenery.BORE << 3) | v)
			if not _cache.has(key):
				key = (16 << 25) | (RunScenery.BORE << 3) | (v % N_VAR)
				if not _cache.has(key):
					_store(key, _cell_kit(key))
		mi.mesh = _cache[key]
		var lamp := _lamps[i] as OmniLight3D
		var outdoors := not RunScenery.enclosed(sc & 7)
		if outdoors:
			# daylight from above (a faint glow at night), like the open-air platforms' own
			lamp.visible = lit
			lamp.position = Vector3(0, 9.0, _ztrack)
			lamp.light_energy = 0.4 + 3.4 * _day
			lamp.omni_range = 34.0
			lamp.omni_attenuation = 1.1
			lamp.light_color = Color(1.0, lerpf(0.86, 0.97, _day), lerpf(0.72, 0.92, _day))
		else:
			lamp.visible = lit
			lamp.light_energy = 1.5
			lamp.omni_range = 9.0
			lamp.omni_attenuation = 1.3
			lamp.light_color = Color(1.0, 0.95, 0.85)
		# the cell enters at s = k * SEG_LEN - SEG_LEN / 2 with the heading the path has there; its mesh runs from x = -SEG_LEN / 2 and has the track at z = _ztrack
		var s0 := float(k) * SEG_LEN - SEG_LEN * 0.5
		var pe := path.pose(s0)
		var fwd := pe.basis.x
		var flip := Transform3D(Basis.from_scale(Vector3(1.0, 1.0, -1.0 if mirror else 1.0)), Vector3.ZERO)
		mi.transform = Transform3D(pe.basis, pe.origin + fwd * (SEG_LEN * 0.5)) * flip * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -_ztrack))
		# the lamp hangs at the middle of the cell: where the bend puts it
		if not outdoors:
			var lp := Vector3(0, TunnelDetail.LAMP_Y - 0.1, _zfar - 0.7)
			if cls != 0:
				lp = Bend.new(float(cls) * TrackPath.Q, -SEG_LEN * 0.5, SEG_LEN * 0.5, _ztrack).map(lp)
			lamp.position = lp
	if _dome != null:
		_dome.visible = any_open
		_dome.position = path.pose(s).origin
