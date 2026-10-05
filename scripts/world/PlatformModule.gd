class_name PlatformModule
extends Node3D
## Deep-tube "twin tunnel" platform module.
## Local frame: x along the track, z across, y = 0 at platform surface (rail head is at y = -0.9).
##
##        z = +8.0  ┌────────────── track-side wall (face A) ───────────────┐
##                  │  track A (z=+6.25)          platform A (z 1.7..4.7)   │
##        z = +1.7  ├──── platform-side wall (openings into the spine) ─────┤
##                  │  SPINE passage  (z -1.7..+1.7, flat ceiling 2.6 m)    │
##        z = -1.7  ├────────────────────────────────────────────────────────┤
##                  │  platform B (z -4.7..-1.7)      track B (z=-6.25)     │
##        z = -8.0  └────────────────────────────────────────────────────────┘
## Face A serves `faces[0]`, face B `faces[1]` (either may be absent for a single-face module).

const BED_Y := -1.15
const RAIL_Y := -0.90
const SPRING_Y := 2.3
const RISE := 1.9
const GAP := 3.4            # spine width
const TRACK_TO_EDGE := 1.55
const TRACK_TO_WALL := 1.75
const SPINE_H := 2.6
const OPEN_W := 3.0
const OPEN_H := 2.15
const TUNNEL_EXT := 170.0    # default running tunnel beyond each platform end (spec `tun_w` / `tun_e` shorten it where rooms lie in its way)
const RUN_IN := 4.0          # the platform's tiling runs on this far past each platform end before the dark lining of the running tunnel (TunnelDetail) begins
const TUNNEL_MIN := 30.0     # a shortened tunnel must still hold the player's car at a ride hand-over (22 m from the platform end)
const BOX_H := 4.7          # ceiling height of "box" halls (sub-surface / surface stations)
const HEAD := 2.15          # lowest underside allowed for anything hanging over a walkway
const PW_RUN := 3.2          # platform width AND running-tunnel clearance: constant so every tunnel joins invisibly
const RECESS_W := 2.0        # Victoria line seat recess (alcove in the platform wall): width, height, depth, pitch along the platform
const RECESS_H := 1.75
const RECESS_D := 0.20
const RECESS_PITCH := 10.0

var spec: Dictionary = {}
var meta: Dictionary = {}
var character: Dictionary = {}     # StationCharacter.platform(): ribs, pilasters, frame, recess ...
var recesses: Array = []           # x centres (module frame) of the seat recesses on the platform wall
var open := false                  # an open-air (surface) platform: canopy, retaining wall, sky (PlatformOpen)
var open_style: Dictionary = {}
var column_xs: Array = []          # x of the canopy columns (open platforms)
var column_zs: Array = []          # z of each column row (open platforms: two rows beside the median, or one on the centre line)
var column_w := 0.44               # collision width of a column
var column_extra: Array = []       # Vector2(x, z) of further columns that are not in the main rows (the entry roof)
var roof_spans: Array = []         # Vector2 x ranges the open-air roof covers (empty: all of it)
var roof_info: Dictionary = {}     # the roof's kind and measures, see PlatformOpen
var ped_doors: Dictionary = {}     # face sign -> [{x, l, r, open}]: the platform edge door leaves (PlatformDoors)
var ped_xs: Array = []             # door x positions when this module has platform edge doors
var box := false
var bend: Bend = null         # the platform curves (Bend): the module is built straight, in design space, and the shell, colliders, lights and trains are then wrapped round the arc
var kit := MeshKit.new()
var _open_xs: Array = []     # Vector2 x ranges of the running track beyond the platform that lie in daylight (RunScenery): they get the sky and daylight lights
var _cols: Array = []        # [center, size]  (collision boxes in local space)
var _lights: Array = []      # [pos, energy, range]
var edge_shapes: Dictionary = {}    # face sign (1.0 / -1.0) -> Array of [x_center, CollisionShape3D]


static func half_width(pw: float) -> float:
	return GAP * 0.5 + pw + TRACK_TO_EDGE + TRACK_TO_WALL


## a frame break between the big steps of a module's build when it is built in the background (the ride builds its destination while the player rides: no step may hold a frame for long)
var split := false          # one platform of a pair of side platforms (spec "split"): the other module lies across the tracks, no wall between them (see StationPlan)
var solo := 0.0              # the side (+1 / -1 in z) of the only face of a module that has just one, else 0
var _async_b := false          # (build() was called to run in the background: the big steps give the frame back, see _brk)


func _brk(p_async: bool) -> void:
	var st := get_parent() as Station
	if p_async and is_inside_tree() and st != null:
		await st._slice()          # (a frame only when the station's time slice for this stretch of the build is used up)
	elif p_async and is_inside_tree():
		await get_tree().process_frame


## spec: length, pw, wall ("tile_white"/"tile_cream"), faces:[{line,color,label}], openings_x:[...], spine_x0, spine_x1, name
func build(p_spec: Dictionary, p_async := false) -> void:
	spec = p_spec
	_async_b = p_async
	split = bool(spec.get("split", false))
	solo = 0.0
	var fl0: Array = spec.get("faces", [{}, {}])
	if fl0.size() == 2 and (fl0[0] == null) != (fl0[1] == null):
		solo = 1.0 if fl0[0] != null else -1.0
	box = spec.get("style", "arch") == "box"
	var L: float = spec.get("length", 110.0)
	var pw: float = spec.get("pw", 3.0)
	var wall_mat: String = spec.get("wall", "tile_cream")
	var faces: Array = spec.get("faces", [{}, {}])
	var openings: Array = spec.get("openings_x", [-L * 0.5 + 9.0, -L * 0.5 + 23.0])
	var spine_x0: float = spec.get("spine_x0", -L * 0.5 - 6.0)
	var spine_x1: float = spec.get("spine_x1", -L * 0.5 + 27.0)
	kit.seed_rng(int(spec.get("seed", 1)))
	character = spec.get("character", {})
	recesses = []
	if character.has("recess") and not box:
		var rx: float = spine_x1 + 6.0       # beyond the spine (its far wall would show through a niche) and its end
		while rx < L * 0.5 - 5.0:
			recesses.append(rx)
			rx += RECESS_PITCH
	open = bool(character.get("open", false)) and box
	open_style = character.get("open_style", {})
	ped_xs = []
	if character.get("peds", false) and faces.size() > 0 and faces[0] != null:
		ped_xs = PlatformDoors.door_xs(String(faces[0].get("line", "jubilee")))
	meta = {"faces": [], "openings": openings, "spine_x0": spine_x0, "spine_x1": spine_x1, "length": L, "pw": pw, "style": spec.get("style", "arch"),
		"tun_w": float(spec.get("tun_w", TUNNEL_EXT)), "tun_e": float(spec.get("tun_e", TUNNEL_EXT)), "recesses": recesses}

	var zwall := GAP * 0.5                      # platform-side wall (abs z)
	var zedge := zwall + pw                     # platform edge
	var ztrack := zedge + TRACK_TO_EDGE
	var zfar := ztrack + TRACK_TO_WALL          # track-side wall
	var x0 := -L * 0.5
	var x1 := L * 0.5

	for fi in 2:
		if fi >= faces.size() or faces[fi] == null:
			continue
		var s := 1.0 if fi == 0 else -1.0       # +z tunnel is face A
		var f: Dictionary = faces[fi]
		var band: Color = f.get("color", Color(0.9, 0.1, 0.1))
		await _build_tunnel(s, x0, x1, zwall, zedge, ztrack, zfar, wall_mat, band, openings)
		meta["faces"].append({
			"index": fi, "side": s, "track_z": s * ztrack, "edge_z": s * zedge, "wall_z": s * zwall,
			"x0": x0, "x1": x1, "rail_y": RAIL_Y, "label": f.get("label", ""), "line": f.get("line", ""),
		})
		await _brk(p_async)
	if box:
		await _build_box_hall(x0, x1, zwall, zedge, ztrack, zfar, wall_mat, openings)
	else:
		_build_spine(x0, x1, spine_x0, spine_x1, zwall, wall_mat, openings)
	await _brk(p_async)

	var mats := {}
	for n in ["tile_white", "tile_cream", "tile_sq_grey", "tile_oxford", "panel_white", "ped_glass", "stainless", "floor_cream", "brick_stock", "brick_red", "brick_blue", "ballast", "tactile_buff", "floor_lozenge", "floor_diamond_grey", "floor_diamond_bw", "floor_slab", "floor_stone", "tactile", "floor_platform", "floor_hall", "ceiling", "concrete", "trackbed", "track_sleepers", "metal", "rail", "yellow_paint", "white_paint", "black", "tunnel_dark", "light_emissive", "glass_roof", "steel", "timber_slab", "tunnel_lining", "grass", "grass_dark", "earth", "gravel", "cable_black", "cable_grey", "cable_red", "el_panel", "el_dark", "ped_glass_dark", "el_stripe"]:
		mats[n] = Mats.get_mat(n)
	for k in kit.surfaces.keys():
		if k.begins_with("flat:"):
			mats[k] = Mats.flat(Color.html(k.substr(5)), 0.4)
		elif k.begins_with("matt:"):
			mats[k] = Mats.flat(Color.html(k.substr(5)), 0.92)
		elif k.begins_with("dado:"):
			mats[k] = Mats.dado(Color.html(k.substr(5)))
		elif k.begins_with("char:"):
			mats[k] = StationCharacter.material(k)
		elif k.begins_with("bd:"):
			mats[k] = RunScenery.material(k)
		elif k.begins_with("light_emissive_"):
			mats[k] = RunScenery.lamp_material(k)
	bend = null
	var bd: Dictionary = spec.get("bend", {})
	if not bd.is_empty():
		bend = Bend.new(float(bd["kappa"]), float(bd["x0"]), float(bd["x1"]), 0.0)
		var tb := Time.get_ticks_usec()
		if p_async and is_inside_tree():
			# (a quarter of a second of vertex work: on a worker thread, the frames go on meanwhile)
			var task := WorkerThreadPool.add_task(func(): kit.bend(bend, 3.0), false, "bend platform")
			await MeshKit.wait_task(task, self)
		else:
			kit.bend(bend, 3.0)
		meta["bend_ms"] = (Time.get_ticks_usec() - tb) / 1000
		meta["bend"] = bd
	await _brk(p_async)
	var mi := MeshInstance3D.new()
	if p_async and is_inside_tree() and DisplayServer.get_name() != "headless":
		# (the surfaces of a deep platform's shell are 40 - 60 ms of vertex copying: on a worker thread, the frames go on meanwhile. Not headless: the dummy rendering server's RID owners are not
		# thread safe - "Attempting to initialize the wrong RID" in the tests - where the real one queues the calls)
		var built: Array = [null]
		var task_b := WorkerThreadPool.add_task(func(): built[0] = kit.build(mats), false, "build platform shell")
		await MeshKit.wait_task(task_b, self)
		mi.mesh = built[0]
	else:
		mi.mesh = kit.build(mats)
	mi.name = "Shell"
	add_child(mi)
	await _brk(p_async)
	_add_collision()
	_add_lights()
	await _add_footbridges(p_async)
	await _brk(p_async)
	if open:
		var ztr := GAP * 0.5 + float(spec.get("pw", 3.0)) + TRACK_TO_EDGE + TRACK_TO_WALL
		PlatformOpen.scenery(self, open_style, x0, x1, ztr)
	_ext_outdoors()
	_add_recess_seats()
	meta["tri_count"] = kit.triangle_count()


## The sky and daylight over the running track that lies in the open beyond the platform ends (the open-air platforms have theirs from PlatformOpen.scenery)
func _ext_outdoors() -> void:
	if _open_xs.is_empty() or Station.debug_off("scenery"):
		return
	var holder: Node3D = get_node_or_null("Outdoors")
	var day := PlatformOpen.daylight()
	RunScenery.refresh_day()
	if holder == null:
		holder = Node3D.new()
		holder.name = "Outdoors"
		add_child(holder)
		PlatformOpen.add_dome(holder, 0.0, day)
	if day <= 0.04:
		return
	var seen := {}
	for r in _open_xs:
		var lx := ceilf((r as Vector2).x / 13.0) * 13.0
		while lx < (r as Vector2).y:
			var q := int(lx / 13.0)
			if not seen.has(q):
				seen[q] = true
				var o := OmniLight3D.new()
				var p := Vector3(lx, 9.0, 0.0)
				o.position = bend.map(p) if bend != null else p
				o.light_energy = 2.4 * day
				o.omni_range = 24.0
				o.omni_attenuation = 1.1
				o.light_color = Color(1.0, lerpf(0.86, 0.97, day), lerpf(0.72, 0.92, day))
				o.shadow_enabled = false
				o.distance_fade_enabled = true
				o.distance_fade_begin = 50.0
				o.distance_fade_length = 15.0
				holder.add_child(o)
			lx += 13.0


# ---------------------------------------------------------------------------------------------------
func _build_tunnel(s: float, x0: float, x1: float, zwall: float, zedge: float, ztrack: float, zfar: float, wall_mat: String, band: Color, openings: Array) -> void:
	# --- arch + track-side wall profile (z, y), ordered so the visible side faces into the tunnel ---
	# running tunnels beyond the platform always have the SAME cross-section relative to the track (PW_RUN), so the
	# tunnel-run scenery used while riding joins every station invisibly
	var zwall_run := zfar - (TRACK_TO_WALL + TRACK_TO_EDGE + PW_RUN)
	var prof := _arch_profile(s, zwall, zfar)
	var prof_run := _arch_profile(s, zwall_run, zfar)
	var xa := x0 - float(meta["tun_w"])       # the running tunnel stops (black cap) before it reaches the rooms on that side
	var xb := x1 + float(meta["tun_e"])
	# a patterned wall tile (Oxford Circus) stays on the platform wall; the vault and the track-side wall are plain white
	var arch_mat := "tile_white" if wall_mat == "tile_oxford" else wall_mat
	if not box:
		kit.sweep_x(arch_mat, prof, x0, x1, 0.0)
		await _brk(_async_b)
	# beyond the platform the bore is bare dark lining with cabling and a lamp here and there, after a few metres of the platform's own tiling. Where the line comes out into daylight (or runs in a
	# cut-and-cover box) beyond a platform end, that stretch is what RunScenery builds, cell by cell, the same as the ride's own scenery (spec "ext": what the track runs through, see StationPlan)
	var runs_w: Array = _ext_runs(s, true, xa, x0)
	var runs_e: Array = _ext_runs(s, false, x1, xb)
	if runs_w.is_empty():
		runs_w = [[RunScenery.BORE, xa, x0, 0.0, 0.0, 0]]
	if runs_e.is_empty():
		runs_e = [[RunScenery.BORE, x1, xb, 0.0, 0.0, 0]]
	var bore_runs: Array = []                 # [a, b] of every stretch of the bore
	var two_faces: bool = (spec.get("faces", []) as Array).size() > 1 and spec["faces"][0] != null and spec["faces"][1] != null
	var rin_w := RUN_IN if (int(runs_w[runs_w.size() - 1][0]) & 7) == RunScenery.BORE else 0.0
	var rin_e := RUN_IN if (int(runs_e[0][0]) & 7) == RunScenery.BORE else 0.0
	for west in [true, false]:
		for r in (runs_w if west else runs_e):
			var a: float = r[1]
			var b: float = r[2]
			if (int(r[0]) & 7) == RunScenery.BORE:
				bore_runs.append([a, b])
				var at_plat: bool = (b >= x0 - 0.01) if west else (a <= x1 + 0.01)
				var lo_l := a
				var hi_l := b
				if at_plat:
					if west:
						hi_l = maxf(a, x0 - RUN_IN)
						kit.sweep_x(arch_mat, prof_run, hi_l, b, 0.0)
						_wall_z(wall_mat, s * zwall_run, hi_l, b, BED_Y, SPRING_Y, [], s < 0.0, true)
					else:
						lo_l = minf(b, x1 + RUN_IN)
						kit.sweep_x(arch_mat, prof_run, a, lo_l, 0.0)
						_wall_z(wall_mat, s * zwall_run, a, lo_l, BED_Y, SPRING_Y, [], s < 0.0, true)
				if hi_l - lo_l > 0.01:
					kit.sweep_x("tunnel_lining", prof_run, lo_l, hi_l, 0.0)
					_wall_z("tunnel_lining", s * zwall_run, lo_l, hi_l, BED_Y, SPRING_Y, [], s < 0.0, true)
					_run_detail(s, west, lo_l, hi_l, (x0 - RUN_IN) if west else (x1 + RUN_IN), zwall_run, zfar)
					await _brk(_async_b)
			else:
				var tmp := MeshKit.new()
				tmp.seed_rng(5 + int(r[5]))
				var kk: int = r[5]
				var oz := {"u0": float(r[3]), "near_flat": two_faces or split}
				if split:
					oz["ns"] = 1.0          # (the other track lies on the far side from the platform, SPLIT_SPACING away: ground between ends half way)
					oz["flat0"] = ztrack + RunScenery.SPLIT_SPACING * 0.5
					oz["flat1"] = ztrack + RunScenery.SPLIT_SPACING * 0.5
				RunScenery.add_scene(tmp, ext_scene(int(r[0]), two_faces or split), (0 if posmod(kk, 2) == 0 else 3) + posmod(kk, 3), float(r[3]), float(r[4]), ztrack, oz)
				if west:
					tmp.mirror_x()
				if s < 0.0:
					tmp.mirror_z()
				kit.merge(tmp)
				if not RunScenery.enclosed(int(r[0]) & 7):
					_open_xs.append(Vector2(a, b))
				await _brk(_async_b)          # (a cell of the running track beyond the platform: a few ms each)
	var holes := []
	for ox in openings:
		holes.append([ox - OPEN_W * 0.5, ox + OPEN_W * 0.5, OPEN_H])
	for rx in recesses:
		holes.append([rx - RECESS_W * 0.5, rx + RECESS_W * 0.5, RECESS_H])
	holes.sort_custom(func(a, b): return a[0] < b[0])
	if not box:
		await _brk(_async_b)
		_wall_z(wall_mat, s * zwall, x0, x1, 0.0, SPRING_Y, holes, s < 0.0, true)
		await _brk(_async_b)
		for rx in recesses:
			_recess(s, rx, zwall, String(character.get("recess", "plain")))
			await _brk(_async_b)

	await _brk(_async_b)
	# --- platform deck (y = 0) and edge ---
	var zlo := minf(s * zwall, s * zedge)
	var zhi := maxf(s * zwall, s * zedge)
	kit.horiz(String(character.get("floor", "floor_platform")), x0, x1, zlo, zhi, 0.0, true, 0.0)
	# edge stack, from the track: white coping line, a dark ribbed strip with the yellow line on its inner half (real deep-tube platforms)
	var tz0 := minf(s * (zedge - 0.50), s * (zedge - 0.06))
	var tz1 := maxf(s * (zedge - 0.50), s * (zedge - 0.06))
	kit.horiz("tactile_buff" if open else "tactile", x0, x1, tz0, tz1, 0.004, true, 0.0)
	var wz0 := minf(s * (zedge - 0.06), s * zedge)
	var wz1 := maxf(s * (zedge - 0.06), s * zedge)
	kit.horiz("white_paint", x0, x1, wz0, wz1, 0.005, true, 0.0)
	# (open-air platforms: the yellow line runs along the inboard edge of the buff strip)
	var yl0 := 0.42 if not open else 0.58
	var lz0 := minf(s * (zedge - yl0), s * (zedge - yl0 + 0.10))
	var lz1 := maxf(s * (zedge - yl0), s * (zedge - yl0 + 0.10))
	if ped_xs.is_empty():
		kit.horiz("yellow_paint", x0, x1, lz0, lz1, 0.006, true, 0.0)      # (the doors are the boundary where there are PEDs)
	else:
		PlatformDoors.build(self, kit, s, zedge, ped_xs, x0, x1, bool(character.get("el", false)))
	# platform front face toward the track (from y=0 down to bed)
	var front_mat := "brick_stock" if open else "concrete"
	if open:
		front_mat = String(open_style.get("front", "brick_stock"))
	if s > 0.0:
		kit.wall(front_mat, Vector3(x1, 0, s * zedge), Vector3(x0, 0, s * zedge), BED_Y, 0.0, BED_Y, false)
	else:
		kit.wall(front_mat, Vector3(x0, 0, s * zedge), Vector3(x1, 0, s * zedge), BED_Y, 0.0, BED_Y, false)
	# platform underside cap at the ends
	# --- track bed ---
	var bz0 := minf(s * zedge, s * zfar)
	var bz1 := maxf(s * zedge, s * zfar)
	kit.horiz("trackbed", x0, x1, bz0, bz1, BED_Y, true, BED_Y)
	for br in bore_runs:
		kit.horiz("trackbed", br[0], br[1], bz0, bz1, BED_Y, true, BED_Y)
	if open:
		kit.horiz("ballast", x0 - 0.5, x1 + 0.5, bz0, bz1, BED_Y + 0.002, true, BED_Y)
	# in the running tunnel the bed spans the whole tunnel width (there's no platform)
	var rz0 := minf(s * zwall_run, s * zedge)
	var rz1 := maxf(s * zwall_run, s * zedge)
	for br in bore_runs:
		kit.horiz("trackbed", br[0], br[1], rz0, rz1, BED_Y, true, BED_Y)
	# end-of-view black walls (the open stretches have the sky instead)
	if RunScenery.enclosed(int(runs_w[0][0]) & 7):
		_end_cap(s, xa, zwall_run, zfar, true)
	if RunScenery.enclosed(int(runs_e[runs_e.size() - 1][0]) & 7):
		_end_cap(s, xb, zwall_run, zfar, false)

	# --- rails ---
	for dz in [-0.7175, 0.7175]:
		kit.box("rail", Vector3((xa + xb) * 0.5, RAIL_Y - 0.08, s * ztrack + dz), Vector3(xb - xa, 0.16, 0.07), BED_Y)
	kit.box("rail", Vector3((xa + xb) * 0.5, RAIL_Y - 0.07, s * ztrack + s * 0.0), Vector3(xb - xa, 0.10, 0.06), BED_Y)          # centre (negative) rail
	kit.box("rail", Vector3((xa + xb) * 0.5, RAIL_Y - 0.07, s * ztrack - s * 1.05), Vector3(xb - xa, 0.10, 0.06), BED_Y)         # outer (positive) rail
	# sleepers: a textured strip under the rails (2.6 m wide)
	kit.horiz("track_sleepers", xa, xb, s * ztrack - 1.3, s * ztrack + 1.3, BED_Y + 0.004, true, BED_Y)
	if split:
		pass          # (the other platform's track lies right beside: no wall across the track)
	elif open:
		PlatformOpen.track_wall(self, open_style, s, x0, x1, zfar, wall_mat)
	elif box:
		_box_track_wall(s, x0, x1, zfar, wall_mat)
	await _brk(_async_b)
	# --- wall stripes / dado (station style) on the track-side wall and the platform wall ---
	var stripes: Array = spec.get("stripes", [{"y0": 1.15, "y1": 1.42, "color": band}])
	var stripe_i := 0
	for st in stripes:
		var col: Color = st["color"]
		var key: String = ("dado:" if st.get("dado", false) else "flat:") + col.to_html(false)
		var y0: float = st["y0"]
		var soff := 0.004 + 0.0025 * stripe_i          # (stripes that overlap - an inset one over a wider one - must not lie in the same plane)
		stripe_i += 1
		if not split:
			_band(key, s * zfar, x0 - rin_w, x1 + rin_e, y0, st["y1"], s < 0.0, true, [], soff)
		if not box:
			_band(key, s * zwall, x0, x1, y0, st["y1"], s < 0.0, false, holes, soff)
	if not box:
		if character.has("pilasters"):
			_pilasters(s, x0, x1, zwall, holes, openings, character["pilasters"])
		if character.has("ribs"):
			_ribs(s, x0, x1, zwall, zfar, character["ribs"])
	# cable tray on the track-side wall
	# (one low tray: real platforms carry the poster run down to platform level, see StationDressing._far_wall)
	if not split:
		kit.box("metal", Vector3((x0 + x1) * 0.5, 0.10, s * (zfar - 0.15)), Vector3(x1 - x0, 0.08, 0.3), 0.0)

	await _brk(_async_b)
	# --- collision ---
	var pcenter := Vector3((x0 + x1) * 0.5, -0.5, s * (zwall + zedge) * 0.5)
	_cols.append([pcenter, Vector3(x1 - x0, 1.0, zedge - zwall)])                        # platform slab (top at y=0)
	# platform edge guard: invisible wall 0.55 m inboard of the yellow line so the player can't drop onto the track
	var ex := x0 + 0.5
	while ex < x1:
		_cols.append([Vector3(ex, 0.9, s * (zedge + 0.15)), Vector3(1.0, 1.8, 0.3), "edge", s])
		ex += 1.0
	# track-side wall & tunnel floor (only matter near platform)
	if split:
		pass
	elif open:
		_cols.append([Vector3((x0 + x1) * 0.5, 2.5, s * (zfar + 0.5)), Vector3(x1 - x0 + 4.0, 6.0, 1.0), "open"])       # (open to the sky: the wall's own box does not occlude)
	else:
		_cols.append([Vector3((x0 + x1) * 0.5, 2.5, s * (zfar + 0.5)), Vector3(x1 - x0 + 4.0, 6.0, 1.0)])
	# platform-side wall segments between openings (full-height box) — keeps player inside the spine/platform
	if not box:
		var segs := _segments(x0, x1, openings, OPEN_W)
		for sg in segs:
			_cols.append([Vector3((sg[0] + sg[1]) * 0.5, 1.5, s * zwall), Vector3(sg[1] - sg[0], 3.0, 0.3)])
	# platform ends
	_cols.append([Vector3(x0 - 0.5, 0.9, s * (zwall + zedge) * 0.5), Vector3(1.0, 1.8, zedge - zwall), "edge"])
	_cols.append([Vector3(x1 + 0.5, 0.9, s * (zwall + zedge) * 0.5), Vector3(1.0, 1.8, zedge - zwall), "edge"])
	# tunnel light fixtures at the crown
	var zc := s * (zwall + zfar) * 0.5
	var apex := SPRING_Y + RISE
	if not box:
		var lx := x0 + 2.0
		while lx < x1:
			kit.box("light_emissive", Vector3(lx, apex - 0.06, zc), Vector3(1.4, 0.06, 0.28), 0.0)
			lx += 3.0
		var lx2 := x0 + 6.0
		while lx2 < x1:
			_lights.append([Vector3(lx2, apex - 0.7, zc), 1.6, 11.0])
			lx2 += 7.0
	# reveal frames around the cross-passage openings (dark trim)
	if not box:
		for ox in openings:
			_frame(s * zwall, ox, OPEN_W, OPEN_H)


## cabling, brackets and a few lamps on the lining of the running tunnel beyond the platform ends: west stretch xa..xw, east stretch xe..xb (TunnelDetail); the lamps nearest the platform
## also light the bore for real, the rest only glow
## the cabling and lamps of one stretch of the bore [lo, hi] beyond a platform end (`plat_end`: where the bore proper begins on that side: the lamps are laid out from there)
func _run_detail(s: float, west: bool, lo: float, hi: float, plat_end: float, zwall_run: float, zfar: float) -> void:
	if Station.debug_off("tunnel_detail"):         # (UG_OFF=tunnel_detail,tunnel_lights: the frame-rate experiment switches the cabling / its lights off)
		return
	var seed := hash(String(spec.get("name", "")) + str(s))
	var dirn := -1.0 if west else 1.0
	var lamps: Array = []
	var lx := plat_end + dirn * 7.0
	var k := 0
	while (lx > lo - 0.5) if west else (lx < hi + 0.5):
		if lx > lo + 0.5 and lx < hi - 0.5 and _frac(seed, k + (0 if west else 500)) > 0.18:
			lamps.append(lx + dirn * (_frac(seed + 5, k) - 0.5) * 3.0)       # (some are out)
		lx += dirn * (17.0 + 6.0 * _frac(seed + 9, k))
		k += 1
	var lights: Array = []
	var near := Vector2(plat_end - 45.0, plat_end) if west else Vector2(plat_end, plat_end + 45.0)
	TunnelDetail.add(kit, s, lo, hi, zwall_run, zfar, {"seed": seed, "lamps": lamps, "near": near, "lamp_lights": lights})
	for lp in lights:
		if absf((lp as Vector3).x - plat_end) < 45.0 and not Station.debug_off("tunnel_lights"):
			_lights.append([lp, 1.3, 9.0])


## the scene of an ext cell as the module builds it: with two faces the other face is the pair's second track, so the cell's own PAIR bit is cleared (RunScenery.add_scene would draw it twice)
static func ext_scene(scn: int, two_faces: bool) -> int:
	return scn & ~(RunScenery.PAIR if two_faces else 0)


## What lies beyond a platform end for the track of the face with sign `s`, as cells for RunScenery: [[scene, x0, x1, d0, d1, cell], ...] ascending in x from `a` to `b`, with the cells of
## deep-tube bore merged ([] when it is all bore: the bore is built as it always was). d0 / d1: distances from the stop; the cell is built in that frame and mirrored for the west end.
func _ext_runs(s: float, west: bool, a: float, b: float) -> Array:
	var ext: Array = spec.get("ext", [])
	var fi := 0 if s > 0.0 else 1
	if fi >= ext.size() or ext[fi] == null:
		return []
	var e: Dictionary = ext[fi]
	var secs: Array = e.get("w" if west else "e", [])
	if secs.is_empty():
		return []
	var d0 := absf(b) if west else absf(a)          # (the stop is at the module's middle)
	var d1 := d0 + (b - a)
	var k0 := int(floor((d0 + RunScenery.CELL * 0.5) / RunScenery.CELL))
	var k1 := int(floor((d1 + RunScenery.CELL * 0.5) / RunScenery.CELL))
	var scenes := RunScenery.cell_scenes(secs, bool(e.get("ss", false)), int(e.get("seed_w" if west else "seed_e", 0)), k0, k1, -1.0, bool(e.get("single_w" if west else "single_e", false)))
	var cells: Array = []
	var any := false
	for i in scenes.size():
		var k := k0 + i
		var da := maxf(float(k) * RunScenery.CELL - RunScenery.CELL * 0.5, d0)
		var db := minf(float(k) * RunScenery.CELL + RunScenery.CELL * 0.5, d1)
		if db - da < 0.01:
			continue
		if (scenes[i] & 7) != RunScenery.BORE:
			any = true
		cells.append([scenes[i], da, db, k])
	if not any:
		return []
	# a platform tunnel that opens into daylight (a hall with end walls has its own portal): a few metres of the platform's own tiling, then the headwall
	var out: Array = []
	if not box and not RunScenery.enclosed(int(cells[0][0]) & 7):
		var start_d := d0 + RUN_IN
		while cells.size() > 1 and float(cells[0][2]) <= start_d + 0.5:
			cells.remove_at(0)
		var c0: Array = cells[0]
		var scn: int = int(c0[0]) | (1 << 8)
		if (scn & 7) == RunScenery.CUTTING or (scn & 7) >= RunScenery.EMBANK:
			scn = (scn & ~(15 << 3)) | (3 << 3) | (3 << 5)          # (a cutting that begins at the mouth is at full depth from there on)
		cells[0] = [scn, start_d, c0[2], c0[3]]          # (the first cell starts where the stub of platform tiling ends, whatever the cell grid says)
		out.append([RunScenery.BORE, (-start_d) if west else d0, (-d0) if west else start_d, 0.0, 0.0, 0])
	for c in cells:
		var xa_c: float = -float(c[2]) if west else float(c[1])
		var xb_c: float = -float(c[1]) if west else float(c[2])
		if (int(c[0]) & 7) == RunScenery.BORE and not out.is_empty() and (int(out[out.size() - 1][0]) & 7) == RunScenery.BORE:
			out[out.size() - 1][2] = xb_c if not west else out[out.size() - 1][2]
			out[out.size() - 1][1] = xa_c if west else out[out.size() - 1][1]
		else:
			out.append([c[0], xa_c, xb_c, c[1], c[2], c[3]])
	if west:
		out.reverse()          # (ascending x)
	return out


static func _frac(a: int, b: int) -> float:
	return float(((a * 73856093) ^ (b * 19349663)) & 0xffff) / 65535.0


func _box_track_wall(s: float, x0: float, x1: float, zfar: float, wall_mat: String) -> void:
	# vertical wall on the track side up to the flat ceiling (visible from the hall)
	if s > 0.0:
		kit.wall(wall_mat, Vector3(x1, 0, zfar), Vector3(x0, 0, zfar), BED_Y, BOX_H, 0.0)
	else:
		kit.wall(wall_mat, Vector3(x0, 0, -zfar), Vector3(x1, 0, -zfar), BED_Y, BOX_H, 0.0)


func _build_box_hall(x0: float, x1: float, zwall: float, zedge: float, ztrack: float, zfar: float, wall_mat: String, openings: Array) -> void:
	var surface: bool = spec.get("roof", "flat") == "glass"
	# island median floor between the two platforms
	kit.horiz(String(character.get("floor", "floor_platform")), x0, x1, -zwall, zwall, 0.0, true, 0.0)
	_cols.append([Vector3((x0 + x1) * 0.5, -0.5, 0.0), Vector3(x1 - x0, 1.0, GAP)])
	if open:
		if solo != 0.0:
			# the back of the only platform: the retaining wall and palisade fence that the far side of a track has, where the other platform would have been
			PlatformOpen.track_wall(self, open_style, -solo, x0, x1, zwall, wall_mat)
			_cols.append([Vector3((x0 + x1) * 0.5, 2.5, -solo * (zwall + 0.5)), Vector3(x1 - x0 + 4.0, 6.0, 1.0), "open"])
		await _build_open_hall(x0, x1, zwall, ztrack, zfar, wall_mat, openings)
		return
	# ceiling
	if surface:
		kit.horiz("glass_roof", x0, x1, -zfar, zfar, BOX_H, false, 0.0)
		var rx := x0 + 3.0
		while rx < x1:
			kit.box("black", Vector3(rx, BOX_H - 0.12, 0.0), Vector3(0.22, 0.24, zfar * 2.0), 0.0)
			rx += 4.0
		for zz in [-zfar * 0.5, 0.0, zfar * 0.5]:
			kit.box("black", Vector3((x0 + x1) * 0.5, BOX_H - 0.1, zz), Vector3(x1 - x0, 0.2, 0.2), 0.0)
	else:
		kit.horiz(String(character.get("ceil", "ceiling")), x0, x1, -zfar, zfar, BOX_H, false, 0.0)
		# steel beams across the ceiling
		var bx := x0 + 2.0
		while bx < x1:
			kit.box("metal", Vector3(bx, BOX_H - 0.22, 0.0), Vector3(0.3, 0.44, zfar * 2.0), 0.0)
			bx += 6.4
	# light fixtures
	var lx := x0 + 3.0
	while lx < x1:
		for zz in [-3.2, 3.2, 0.0]:
			if not surface or zz == 0.0:
				kit.box("light_emissive", Vector3(lx, BOX_H - 0.32 if not surface else BOX_H - 0.3, zz), Vector3(1.3, 0.06, 0.3), 0.0)
		lx += 3.2
	var lx2 := x0 + 4.0
	while lx2 < x1:
		_lights.append([Vector3(lx2, BOX_H - 0.9, 3.2), 2.2 if not surface else 1.3, 13.0])
		_lights.append([Vector3(lx2, BOX_H - 0.9, -3.2), 2.2 if not surface else 1.3, 13.0])
		lx2 += 8.0
	# steel columns down the two platforms: on the wall side, well clear of the walking lane (edge - 1.0) and of the wall openings
	var cx := x0 + 5.0
	var col_z := zwall + 0.85
	while cx < x1 - 3.0:
		var at_opening := false
		for ox in openings:
			if absf(cx - ox) < 2.6:
				at_opening = true
		if not at_opening:
			for zz in [-col_z, col_z]:
				if character.has("tile_cols"):
					# a tile-clad column: white glazed tile, a black skirting and a band in the line colour at head height (Euston Square, Mansion House)
					var lc: Color = character["tile_cols"]
					kit.box("tile_white", Vector3(cx, BOX_H * 0.5, zz), Vector3(0.52, BOX_H, 0.52), 0.0)
					kit.box("dado:" + Color(0.06, 0.06, 0.07).to_html(false), Vector3(cx, 0.12, zz), Vector3(0.535, 0.24, 0.535), 0.0)
					kit.box("flat:" + lc.to_html(false), Vector3(cx, 2.38, zz), Vector3(0.535, 0.12, 0.535), 0.0)
					_cols.append([Vector3(cx, BOX_H * 0.5, zz), Vector3(0.54, BOX_H, 0.54)])
				else:
					kit.box("metal", Vector3(cx, BOX_H * 0.5, zz), Vector3(0.42, BOX_H, 0.42), 0.0)
					_cols.append([Vector3(cx, BOX_H * 0.5, zz), Vector3(0.44, BOX_H, 0.44)])
		cx += 7.2
	# end walls: track portals on both sides, plus a doorway at the west end leading to the corridor
	_box_end_wall(x0, true, zwall, ztrack, zfar, wall_mat, true)
	_box_end_wall(x1, false, zwall, ztrack, zfar, wall_mat, false)


## the open-air variant of the box hall: canopy + columns (PlatformOpen) instead of the closed roof; lights, end walls and collision are the same
func _build_open_hall(x0: float, x1: float, zwall: float, ztrack: float, zfar: float, wall_mat: String, openings: Array) -> void:
	await PlatformOpen.canopy(self, open_style, x0, x1, openings)
	var ly := PlatformOpen.roof_h(open_style) - 0.9          # (lights must hang below the roof's underside to light it)
	if String(roof_info.get("kind", "")) == "mushroom":
		for c in roof_info["caps"]:
			_lights.append([Vector3(float(c), ly, 2.6), 2.2, 13.0])
			_lights.append([Vector3(float(c), ly, -2.6), 2.2, 13.0])
	else:
		var lx2 := x0 + 4.0
		while lx2 < x1:
			if PlatformOpen.covered(self, lx2):
				if solo != 0.0:
					_lights.append([Vector3(lx2, ly, solo * 3.2), 2.2, 13.0])
				else:
					_lights.append([Vector3(lx2, ly, 3.2), 2.2, 13.0])
					_lights.append([Vector3(lx2, ly, -3.2), 2.2, 13.0])
			lx2 += 8.0
	for cx in column_xs:
		for zz in column_zs:
			_cols.append([Vector3(cx, BOX_H * 0.5, zz), Vector3(column_w, BOX_H, column_w)])
	for ce in column_extra:
		_cols.append([Vector3((ce as Vector2).x, BOX_H * 0.5, (ce as Vector2).y), Vector3(0.44, BOX_H, 0.44)])
	_box_end_wall(x0, true, zwall, ztrack, zfar, wall_mat, true)
	await _brk(_async_b)
	_box_end_wall(x1, false, zwall, ztrack, zfar, wall_mat, false)


func _box_end_wall(x: float, west: bool, zwall: float, ztrack: float, zfar: float, wall_mat: String, doorway: bool) -> void:
	# openings (z_lo, z_hi, y_lo, y_hi)
	var ops: Array = [[-ztrack - 1.9, -ztrack + 1.65, BED_Y, 3.4], [ztrack - 1.65, ztrack + 1.9, BED_Y, 3.4]]
	if solo > 0.0:
		ops.remove_at(0)          # (one face: no track on the other side)
	elif solo < 0.0:
		ops.remove_at(1)
	if doorway:
		ops.append([-zwall, zwall, 0.0, SPINE_H])
	ops.sort_custom(func(a, b): return a[0] < b[0])
	var z := -zfar
	for o in ops:
		_end_strip(x, west, wall_mat, z, o[0], BED_Y, BOX_H)
		# under / above the opening
		if o[2] > BED_Y:
			_end_strip(x, west, wall_mat, o[0], o[1], BED_Y, o[2])
		_end_strip(x, west, wall_mat, o[0], o[1], o[3], BOX_H)
		z = o[1]
	_end_strip(x, west, wall_mat, z, zfar, BED_Y, BOX_H)
	# solid collision segments between the openings (west end has a walk-through doorway)
	var cz := -zfar
	for o in ops:
		if o[0] - cz > 0.05:
			_cols.append([Vector3(x + (-0.15 if west else 0.15), BOX_H * 0.5, (cz + o[0]) * 0.5), Vector3(0.3, BOX_H, o[0] - cz)])
		cz = o[1]
	if zfar - cz > 0.05:
		_cols.append([Vector3(x + (-0.15 if west else 0.15), BOX_H * 0.5, (cz + zfar) * 0.5), Vector3(0.3, BOX_H, zfar - cz)])


func _end_strip(x: float, west: bool, mat: String, z0: float, z1: float, y0: float, y1: float) -> void:
	if z1 - z0 < 0.01 or y1 - y0 < 0.01:
		return
	if west:
		kit.wall(mat, Vector3(x, 0, z1), Vector3(x, 0, z0), y0, y1, 0.0)      # normal +x
	else:
		kit.wall(mat, Vector3(x, 0, z0), Vector3(x, 0, z1), y0, y1, 0.0)      # normal -x


func _arch_profile(s: float, zwall: float, zfar: float, inset := 0.0, arc_only := false) -> PackedVector2Array:
	# from the top of the platform-side wall, over the arch, down the track-side wall to the trackbed (ordered for +z traversal when s>0)
	# `inset` pulls the arc that far into the tunnel (ribs / bands laid on the vault); `arc_only` stops at the two springs
	var za := zwall
	var zb := zfar
	var pts := PackedVector2Array()
	var chord := zb - za
	var r := (chord * chord / 4.0 + RISE * RISE) / (2.0 * RISE)
	var zc := (za + zb) * 0.5
	var yc := SPRING_Y + RISE - r
	var a0 := atan2(SPRING_Y - yc, za - zc)   # angle at left spring
	var a1 := atan2(SPRING_Y - yc, zb - zc)
	var ri := r - inset
	# ensure we traverse over the top (a from a0 ~ (pi - x) down to a1 ~ x)
	var steps := 16
	if inset == 0.0:
		pts.append(Vector2(za, SPRING_Y))
	else:
		pts.append(Vector2(zc + ri * cos(a0), yc + ri * sin(a0)))
	for i in range(1, steps):
		var a := lerpf(a0, a1, float(i) / steps)
		pts.append(Vector2(zc + ri * cos(a), yc + ri * sin(a)))
	if inset == 0.0:
		pts.append(Vector2(zb, SPRING_Y))
	else:
		pts.append(Vector2(zc + ri * cos(a1), yc + ri * sin(a1)))
	if not arc_only:
		pts.append(Vector2(zb, BED_Y))
	if s < 0.0:
		# mirrored tunnel: build with mirrored z, still ordered +z, so reverse and negate
		var m := PackedVector2Array()
		for i in range(pts.size() - 1, -1, -1):
			m.append(Vector2(-pts[i].x, pts[i].y))
		return m
	return pts


## Wall in the plane z = zc between xa..xb, y0..y1 with holes [[x0,x1,top_y]]; both faces optional.
func _wall_z(mat: String, zc: float, xa: float, xb: float, y0: float, y1: float, holes: Array, face_neg: bool, tunnel_face_only := false) -> void:
	# visible side toward the tunnel: for A (zc>0) the tunnel is at larger z => normal +z ; for B (zc<0) normal -z
	var normal_pos := not face_neg
	var cuts := [[xa, xb]]
	# build segments between holes
	var segs: Array = _free_segments(xa, xb, holes)
	for sg in segs:
		_wall_quad(mat, zc, sg[0], sg[1], y0, y1, normal_pos)
	for h in holes:
		_wall_quad(mat, zc, h[0], h[1], h[2], y1, normal_pos)
	# spine-facing side (opposite normal) is drawn in _build_spine to limit it to the spine extent
	cuts = cuts


func _wall_quad(mat: String, zc: float, xa: float, xb: float, y0: float, y1: float, normal_pos: bool) -> void:
	if xb - xa < 0.001 or y1 - y0 < 0.001:
		return
	# `wall` shows the right of travel; normal +z needs travel +x ; normal -z needs travel -x
	if normal_pos:
		kit.wall(mat, Vector3(xa, 0, zc), Vector3(xb, 0, zc), y0, y1, 0.0)
	else:
		kit.wall(mat, Vector3(xb, 0, zc), Vector3(xa, 0, zc), y0, y1, 0.0)


## x-intervals of [xa, xb] not covered by holes [[x0, x1, top], ...] (any widths)
func _free_segments(xa: float, xb: float, holes: Array) -> Array:
	var hs := holes.duplicate()
	hs.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	var cur := xa
	for h in hs:
		if h[0] > cur:
			out.append([cur, minf(h[0], xb)])
		cur = maxf(cur, h[1])
	if cur < xb:
		out.append([cur, xb])
	return out


## x-intervals of [xa, xb] not covered by openings centred at `centres` with width w
func _segments(xa: float, xb: float, centres: Array, w: float) -> Array:
	var cs := centres.duplicate()
	cs.sort()
	var out := []
	var cur := xa
	for c in cs:
		var h0: float = c - w * 0.5
		var h1: float = c + w * 0.5
		if h0 > cur:
			out.append([cur, h0])
		cur = maxf(cur, h1)
	if cur < xb:
		out.append([cur, xb])
	return out


func _band(mat: String, zc: float, xa: float, xb: float, y0: float, y1: float, neg: bool, tunnel_side_positive_toward_center: bool, holes := [], off := 0.004) -> void:
	# thin coloured band slightly proud of the wall; faces the tunnel interior. (`off`: how far; a band that crosses another one - a pilaster over the dado - stands further out, or the two
	# would be drawn in the same plane and flicker)
	var toward_tunnel := -signf(zc) if tunnel_side_positive_toward_center else signf(zc)
	# for the track-side wall the tunnel interior is toward the centre (-sign(zc)); for the platform-side wall it is away from the centre (+sign)
	var z := zc + toward_tunnel * off
	var segs := [[xa, xb]]
	if holes.size() > 0:
		segs = _free_segments(xa, xb, holes)
	for sg in segs:
		if toward_tunnel > 0.0:
			kit.wall(mat, Vector3(sg[0], 0, z), Vector3(sg[1], 0, z), y0, y1, 0.0)
		else:
			kit.wall(mat, Vector3(sg[1], 0, z), Vector3(sg[0], 0, z), y0, y1, 0.0)


func _end_cap(s: float, x: float, zwall: float, zfar: float, west: bool) -> void:
	var za := minf(s * zwall, s * zfar)
	var zb := maxf(s * zwall, s * zfar)
	# a black plane closing the tunnel: seen from inside (normal toward the platform)
	var p0 := Vector3(x, SPRING_Y + RISE, za)
	var p1 := Vector3(x, SPRING_Y + RISE, zb)
	var p2 := Vector3(x, BED_Y, zb)
	var p3 := Vector3(x, BED_Y, za)
	if west:
		kit.quad("tunnel_dark", p0, p3, p2, p1, 0.0)      # normal +x
	else:
		kit.quad("tunnel_dark", p0, p1, p2, p3, 0.0)      # normal -x


func _frame(zc: float, ox: float, w: float, h: float) -> void:
	var t := 0.14
	var mat := "metal"
	if character.has("frame"):
		# station-specific portal surround in glazed tile (Archway: dark green)
		t = float(character["frame"].get("w", 0.3))
		mat = "dado:" + (character["frame"]["col"] as Color).to_html(false)
	for sgn in [-1.0, 1.0]:
		kit.box(mat, Vector3(ox + sgn * (w * 0.5 + t * 0.5), h * 0.5, zc), Vector3(t, h, 0.42), 0.0)
	kit.box(mat, Vector3(ox, h + t * 0.5, zc), Vector3(w + 2 * t, t, 0.42), 0.0)


## ribs: bands of glazed tile ringed over the vault at a fixed pitch (Edgware Road navy, Baker Street brown, Chalk Farm red ...)
func _ribs(s: float, x0: float, x1: float, zwall: float, zfar: float, rb: Dictionary) -> void:
	var key := "dado:" + (rb["col"] as Color).to_html(false)
	var every := float(rb.get("every", 3.0))
	var w := float(rb.get("w", 0.45))
	var prof := _arch_profile(s, zwall, zfar, 0.004, true)
	var x := x0 + every * 0.5
	while x + w < x1:
		kit.sweep_x(key, prof, x, x + w, 0.0, false, 4.0)
		x += every


## pilasters: full-height vertical bands of coloured tile on the platform wall (beside the cross-passages, or at a fixed pitch), optionally with a
## thin edge strip each side (Goodge Street green + black, Chalk Farm red, Warren Street dark red)
func _pilasters(s: float, x0: float, x1: float, zwall: float, holes: Array, openings: Array, pl: Dictionary) -> void:
	var key := "dado:" + (pl["col"] as Color).to_html(false)
	var w := float(pl.get("w", 0.6))
	var xs: Array = []
	if pl.get("at_openings", false):
		for o in openings:
			xs.append(o - OPEN_W * 0.5 - 0.16 - w * 0.5)
			xs.append(o + OPEN_W * 0.5 + 0.16 + w * 0.5)
	var every := float(pl.get("every", 0.0))
	if every > 0.0:
		var x := x0 + every * 0.5
		while x < x1:
			var clear := true
			for o in openings:
				if absf(x - o) < OPEN_W * 0.5 + w + 0.5:
					clear = false
			for rx in recesses:
				if absf(x - rx) < RECESS_W * 0.5 + w:
					clear = false
			if clear:
				xs.append(x)
			x += every
	var edge: String = ("dado:" + (pl["edge_col"] as Color).to_html(false)) if pl.has("edge_col") else ""
	var cols: Array = pl.get("cols", [])           # a cycle of colours (Bond Street Jubilee: alternating panels) instead of one
	var ci := 0
	for xc in xs:
		if not cols.is_empty():
			key = "dado:" + (cols[ci % cols.size()] as Color).to_html(false)
			ci += 1
		_band(key, s * zwall, xc - w * 0.5, xc + w * 0.5, 0.0, SPRING_Y, s < 0.0, false, holes, 0.016)
		if edge != "":
			_band(edge, s * zwall, xc + w * 0.5, xc + w * 0.5 + 0.075, 0.0, SPRING_Y, s < 0.0, false, holes, 0.020)


## a seat recess in the platform wall (Victoria line): a shallow niche in the 150 mm tile with a motif panel at the back, stainless trim and a timber slab
func _recess(s: float, xc: float, zwall: float, motif: String) -> void:
	var hw := RECESS_W * 0.5
	var zw := s * zwall                        # the wall plane
	var zb := s * (zwall - RECESS_D)           # the niche's back, toward the spine
	var back_mat := "tile_sq_grey"
	if motif != "plain" and ResourceLoader.exists(StationCharacter.DIR + "motif/%s.png" % motif):
		back_mat = "char:motif/%s.png|%.3f|%.3f|0" % [motif, RECESS_W, RECESS_H]
	var xl := xc - hw
	var xr := xc + hw
	if s > 0.0:
		kit.wall(back_mat, Vector3(xl, 0, zb), Vector3(xr, 0, zb), 0.0, RECESS_H, 0.0)
	else:
		kit.wall(back_mat, Vector3(xr, 0, zb), Vector3(xl, 0, zb), 0.0, RECESS_H, 0.0)
	var za := maxf(zw, zb)
	var zi := minf(zw, zb)
	kit.wall("tile_sq_grey", Vector3(xl, 0, za), Vector3(xl, 0, zi), 0.0, RECESS_H, 0.0)       # left side, normal +x
	kit.wall("tile_sq_grey", Vector3(xr, 0, zi), Vector3(xr, 0, za), 0.0, RECESS_H, 0.0)       # right side, normal -x
	kit.horiz("tile_sq_grey", xl, xr, zi, za, RECESS_H, false, 0.0)                              # soffit
	kit.horiz("floor_platform", xl, xr, zi, za, 0.0, true, 0.0)
	# stainless trim round the opening
	for sx in [xl - 0.02, xr + 0.02]:
		kit.box("steel", Vector3(sx, RECESS_H * 0.5, zw + s * 0.008), Vector3(0.04, RECESS_H, 0.016), 0.0)
	kit.box("steel", Vector3(xc, RECESS_H + 0.02, zw + s * 0.008), Vector3(RECESS_W + 0.08, 0.04, 0.016), 0.0)
	# the timber slab: seat height 0.45 m, about 0.34 m deep, standing 0.14 m proud of the wall
	var slab_z0 := zb
	var slab_z1 := zw + s * 0.14
	kit.box("timber_slab", Vector3(xc, 0.425, (slab_z0 + slab_z1) * 0.5), Vector3(RECESS_W - 0.02, 0.05, absf(slab_z1 - slab_z0)), 0.0)
	kit.box("black", Vector3(xc, 0.2, zb + s * 0.1), Vector3(RECESS_W - 0.06, 0.4, 0.2), 0.0)


func _build_spine(x0: float, x1: float, sx0: float, sx1: float, zwall: float, wall_mat: String, openings: Array) -> void:
	# floor + ceiling
	kit.horiz("floor_platform", sx0, sx1, -zwall, zwall, 0.0, true, 0.0)
	kit.horiz("ceiling", sx0, sx1, -zwall, zwall, SPINE_H, false, 0.0)
	# spine-facing sides of the two platform-side walls (normal toward the spine centre)
	for s in [1.0, -1.0]:
		var holes := []
		for ox in openings:
			holes.append([ox - OPEN_W * 0.5, ox + OPEN_W * 0.5, OPEN_H])
		var segs := _segments(sx0, sx1, openings, OPEN_W)
		for sg in segs:
			# normal toward centre: for the +z wall the normal is -z
			if s > 0.0:
				kit.wall(wall_mat, Vector3(sg[1], 0, s * zwall), Vector3(sg[0], 0, s * zwall), 0.0, SPINE_H, 0.0)
			else:
				kit.wall(wall_mat, Vector3(sg[0], 0, s * zwall), Vector3(sg[1], 0, s * zwall), 0.0, SPINE_H, 0.0)
		for h in holes:
			if h[0] >= sx0 and h[1] <= sx1:
				if s > 0.0:
					kit.wall(wall_mat, Vector3(h[1], 0, s * zwall), Vector3(h[0], 0, s * zwall), h[2], SPINE_H, 0.0)
				else:
					kit.wall(wall_mat, Vector3(h[0], 0, s * zwall), Vector3(h[1], 0, s * zwall), h[2], SPINE_H, 0.0)
	# the station's tile bands carry on along the spine
	var sholes := []
	for ox2 in openings:
		sholes.append([ox2 - OPEN_W * 0.5, ox2 + OPEN_W * 0.5, OPEN_H])
	for st in spec.get("stripes", []):
		var sy1: float = minf(st["y1"], SPINE_H - 0.1)
		if st["y0"] >= sy1:
			continue
		var skey: String = ("dado:" if st.get("dado", false) else "flat:") + (st["color"] as Color).to_html(false)
		for s3 in [1.0, -1.0]:
			_band(skey, s3 * zwall, sx0, sx1, st["y0"], sy1, s3 < 0.0, true, sholes, 0.004 + 0.0025 * float(spec.get("stripes", []).find(st)))
	# east end cap (tile), west end open (portal)
	kit.wall(wall_mat, Vector3(sx1, 0, zwall), Vector3(sx1, 0, -zwall), 0.0, SPINE_H, 0.0)
	# lights: emissive panels in the spine ceiling
	var lx := sx0 + 2.0
	while lx < sx1:
		kit.box("light_emissive", Vector3(lx, SPINE_H - 0.03, 0.0), Vector3(1.2, 0.05, 0.3), 0.0)
		lx += 3.5
	var l2 := sx0 + 3.0
	while l2 < sx1:
		_lights.append([Vector3(l2, SPINE_H - 0.5, 0.0), 1.4, 9.0])
		l2 += 7.0
	# spine collision. The side walls stop the player stepping off the spine floor; the stretch beside the platform (x0..x1) already gets
	# wall segments from _build_tunnel, so only the part of the spine outside it needs its own (the west stretch, and any east overhang)
	for s2 in [1.0, -1.0]:
		if sx0 < x0 - 0.01:
			var xe := minf(x0, sx1)
			_cols.append([Vector3((sx0 + xe) * 0.5, 1.5, s2 * zwall), Vector3(xe - sx0, 3.0, 0.3)])
		if sx1 > x1 + 0.01:
			var xs := maxf(x1, sx0)
			_cols.append([Vector3((xs + sx1) * 0.5, 1.5, s2 * zwall), Vector3(sx1 - xs, 3.0, 0.3)])
	_cols.append([Vector3((sx0 + sx1) * 0.5, -0.5, 0.0), Vector3(sx1 - sx0, 1.0, GAP)])
	_cols.append([Vector3(sx1 + 0.15, 1.3, 0.0), Vector3(0.3, 2.6, GAP)])
	_cols.append([Vector3((sx0 + sx1) * 0.5, 3.0, 0.0), Vector3(sx1 - sx0, 0.4, GAP)])
	# reveal-fill: openings are 3.0 wide and the wall is thin; reveal frames handled by _frame


## two seat markers (group "seat", pelvis point, -Z = facing) on the slab of every seat recess
func _add_recess_seats() -> void:
	for f in meta["faces"]:
		var s: float = f["side"]
		for rx in recesses:
			for dx in [-0.5, 0.5]:
				var m := Node3D.new()
				m.name = "seat_%d_%d" % [int(rx * 10.0), int(dx * 2.0)]
				m.position = Vector3(rx + dx, 0.45, s * (GAP * 0.5 - 0.03))
				m.rotation.y = atan2(0.0, -s)
				if bend != null:
					m.rotation.y += bend.theta(m.position.x)
					m.position = bend.map(m.position)
				m.add_to_group("seat")
				add_child(m)


## the world point p in this module's design frame (straight, x along the platform): on a curved platform the module is wrapped round an arc, which is undone here
func design_local(p: Vector3) -> Vector3:
	var lp := to_local(p)
	return bend.unmap(lp) if bend != null else lp


## Moves what dressing, signs and props added to this module (placed straight, in design space) onto the curve: a baked mesh was bent where it was made (PosterKit.finish), everything else is
## picked up and set down again on the curve with the heading the track has there. Holders (plain Node3Ds at the origin) are looked through.
func bend_children() -> void:
	if bend == null:
		return
	for c in get_children():
		_bend_node(c)


func _bend_node(n: Node) -> void:
	if n.name in ["Shell", "Collision", "EdgeGuard", "Lights"] or n is Train or n.has_meta("bent"):
		return
	if not n is Node3D:
		return
	var nd := n as Node3D
	nd.set_meta("bent", true)
	if nd.get_class() == "Node3D" and nd.transform == Transform3D.IDENTITY:
		for c in nd.get_children():
			_bend_node(c)
		return
	var p := nd.position
	nd.position = bend.map(p)
	nd.basis = bend.rot(p.x) * nd.basis


## a collision box [centre, size] of the straight design as the boxes that follow the bend: long ones are cut into pieces (a little longer than their pitch so they overlap and leave no crack),
## each turned with the track where it stands. -> [[centre, size, basis], ...]
func _bent_pieces(c: Array) -> Array:
	var ctr: Vector3 = c[0]
	var size: Vector3 = c[1]
	var xa := ctr.x - size.x * 0.5
	var xb := ctr.x + size.x * 0.5
	if xb <= bend.x0:
		return [[ctr, size, Basis.IDENTITY]]
	if size.x <= 1.6:
		var pad := 0.12 if xa > bend.x0 + 0.5 else 0.0          # (a little longer than the pitch: neighbouring pieces overlap, no crack at the corners; not where a wall stands on the edge of the arc)
		return [[bend.map(ctr), size + Vector3(pad, 0.0, 0.0), bend.rot(ctr.x)]]
	var n := maxi(1, int(ceil(size.x / 4.0)))
	var out: Array = []
	for i in n:
		var xc := xa + (float(i) + 0.5) * size.x / float(n)
		var len := size.x / float(n)
		var piece := Vector3(len + (0.3 if n > 1 else 0.0), size.y, size.z)
		out.append([bend.map(Vector3(xc, ctr.y, ctr.z)), piece, bend.rot(xc)])
	return out


func _add_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	var edge_body := StaticBody3D.new()
	edge_body.name = "EdgeGuard"
	edge_body.collision_layer = 1 << 2      # layer 3: platform-edge guard (player only)
	edge_body.collision_mask = 0
	body.collision_layer = 1
	for c in _cols:
		var pieces: Array = _bent_pieces(c) if bend != null else [[c[0], c[1], Basis.IDENTITY]]
		for pc in pieces:
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = pc[1]
			cs.shape = sh
			cs.transform = Transform3D(pc[2], pc[0])
			if c.size() > 2 and c[2] == "edge":
				edge_body.add_child(cs)
				if c.size() > 3:
					if not edge_shapes.has(c[3]):
						edge_shapes[c[3]] = []
					edge_shapes[c[3]].append([c[0].x, cs])
			else:
				body.add_child(cs)
	add_child(body)
	add_child(edge_body)


# ---------------------------------------------------------------------------------------------------
# Roof clearance (for signs)
# ---------------------------------------------------------------------------------------------------
func _arch() -> Dictionary:
	var zw := GAP * 0.5
	var zf: float = zw + float(meta["pw"]) + TRACK_TO_EDGE + TRACK_TO_WALL
	var chord := zf - zw
	var r := (chord * chord / 4.0 + RISE * RISE) / (2.0 * RISE)
	return {"zw": zw, "zf": zf, "zc": (zw + zf) * 0.5, "r": r, "yc": SPRING_Y + RISE - r}


## Roof height above the platform at module-local z (arch tunnels: circular arch over each tunnel, flat spine between; box halls: flat)
func ceiling_at(z: float, x := NAN) -> float:
	if box:
		if open and not is_nan(x):
			var y := PlatformOpen.soffit_y(self, x, z)
			if not is_nan(y):
				return y
		return BOX_H
	var a := _arch()
	var az := absf(z)
	if az < float(a["zw"]):
		return SPINE_H
	if az > float(a["zf"]):
		return SPRING_Y
	var dz := az - float(a["zc"])
	return float(a["yc"]) + sqrt(maxf(float(a["r"]) * float(a["r"]) - dz * dz, 0.0))


## Box halls: move x sideways so a board hung at x clears the steel columns (every 7.2 m from x0 + 5)
func clear_of_columns(x: float, half_w := 0.4) -> float:
	if not box:
		return x
	if open:
		# open-air columns: wherever PlatformOpen put them
		var wcol := column_w * 0.5 + half_w + 0.3
		for cxo in column_xs:
			if absf(x - float(cxo)) < wcol:
				return float(cxo) + wcol if x >= float(cxo) else float(cxo) - wcol
		for ce in column_extra:
			var cxe: float = (ce as Vector2).x
			if absf(x - cxe) < 0.22 + half_w + 0.3:
				return cxe + 0.22 + half_w + 0.3 if x >= cxe else cxe - 0.22 - half_w - 0.3
		return x
	var x0 := -float(meta["length"]) * 0.5
	var k := roundf((x - (x0 + 5.0)) / 7.2)
	var cx := x0 + 5.0 + k * 7.2
	var need := half_w + 0.3
	if absf(x - cx) < need:
		return cx + need if x >= cx else cx - need
	return x


## Where a hanging blade (faces along x, spans z) of size w x h fits under the roof of the tunnel on side `s` (+1/-1).
## Prefers z_want (signed) and a top edge at y_top_want; slides sideways / rises / shrinks until it clears the roof and walls.
## Returns {"z": signed centre z, "y_top": top edge, "k": scale}.
func fit_blade(s: float, z_want: float, w: float, h: float, y_top_want: float, margin := 0.12) -> Dictionary:
	var a := _arch()
	var zlo: float = float(a["zw"]) + 0.15
	var zhi: float = float(a["zf"]) - 0.15
	var za := absf(z_want)
	var top_limit: float = (BOX_H if box else SPRING_Y + RISE) - 0.05
	for k in [1.0, 0.88, 0.76, 0.66, 0.56]:
		var wk: float = w * k
		var hk: float = h * k
		var y_top := maxf(y_top_want, HEAD + hk)
		while y_top <= top_limit:
			var lo := zlo
			var hi := zhi
			if not box:
				var dy: float = y_top + margin - float(a["yc"])
				if dy > float(a["r"]):
					break
				var d := sqrt(maxf(float(a["r"]) * float(a["r"]) - dy * dy, 0.0))
				lo = maxf(lo, float(a["zc"]) - d)
				hi = minf(hi, float(a["zc"]) + d)
			if hi - lo >= wk:
				return {"z": s * clampf(za, lo + wk * 0.5, hi - wk * 0.5), "y_top": y_top, "k": k}
			y_top += 0.05
	return {"z": s * float(a["zc"]), "y_top": top_limit - 0.1, "k": 0.5}


## Open/close the invisible platform-edge guard between x_from..x_to (module-local) on the face at `face_sign` (+1 = +z tunnel)
func set_edge_open(face_sign: float, x_from: float, x_to: float, open: bool) -> void:
	if not ped_doors.is_empty():
		PlatformDoors.slide(self, face_sign, (x_from + x_to) * 0.5, open)
	if not edge_shapes.has(face_sign):
		return
	for e in edge_shapes[face_sign]:
		if e[0] >= x_from - 0.5 and e[0] <= x_to + 0.5:
			(e[1] as CollisionShape3D).set_deferred("disabled", open)


## the footbridges over this module and the one across the tracks (spec "footbridges", from StationPlan._add_footbridges)
func _add_footbridges(p_async := false) -> void:
	if bend != null or Station.debug_off("footbridge"):
		return
	var stn := get_parent() as Station
	var lifts_here: bool = stn != null and stn.has_lifts()          # (the lift towers are drawn where the station has its lifts: Station._build_lifts makes their doors work)
	for fbd: Dictionary in spec.get("footbridges", []):
		var fb := Footbridge.new()
		fb.name = "Footbridge"
		add_child(fb)
		await fb.build(float(fbd["x"]), float(fbd["d"]), float(fbd["za"]), float(fbd["zb"]), String(spec.get("wall", "brick_red")), lifts_here, self, p_async)


func _add_lights() -> void:
	var holder := Node3D.new()
	holder.name = "Lights"
	add_child(holder)
	for l in _lights:
		var o := OmniLight3D.new()
		o.position = bend.map(l[0]) if bend != null else l[0]
		o.light_energy = l[1]
		o.omni_range = l[2]
		o.omni_attenuation = 1.3
		o.light_color = character.get("light_color", Color(1.0, 0.97, 0.92))
		o.shadow_enabled = false
		o.distance_fade_enabled = true
		o.distance_fade_begin = 45.0
		o.distance_fade_length = 15.0
		holder.add_child(o)
