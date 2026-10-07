class_name RunScenery
extends RefCounted
## What the track runs through between and beside stations, other than the deep-tube bore: open railway land, cuttings (grass banks or brick walls), embankments, viaducts, and the cut-and-cover
## box tunnels of the sub-surface lines, with the headwalls where a tunnel opens into daylight. One builder for both the running track beyond a platform (PlatformModule) and the cells of the ride
## (TunnelRun), so the hand-over from one to the other is invisible.
## Frame: x along the track, the track at z = t, y = 0 the platform level (rail head -0.9, ballast -1.15); the platform side of the running tunnel is toward -z (4.75 m from the track),
## the track-side wall 1.75 m to +z. Real shapes come from OpenStreetMap's tunnel / cutting / embankment / bridge ways (tools/fetch_line_sections.py -> data/line_geometry.json "sec").

const OPEN := 0
const BORE := 1                 # the deep-tube bore (TunnelRun / PlatformModule build it themselves)
const CUTTING := 2
const EMBANK := 3
const VIADUCT := 4
const BOX := 5                  # cut-and-cover tunnel of the sub-surface lines

const NEAR := 4.75              # platform-side wall of the running tunnel, from the track
const FAR := 1.75               # track-side wall
const G := -1.07                # railway land: a hand above the ballast
const GW := 46.0                # how far the ground reaches either side
const SHOULDER := 3.2           # half-width of the formation
const SLOPE := 1.5              # banks: metres across per metre of height
const CUT_H := 6.0              # a cutting this deep (at full depth)
const EMB_H := 4.2              # an embankment this high
const VIA_H := 6.5              # a viaduct this high
const VIA_HALF := 3.0           # half the width of the viaduct deck, between its parapets
const WATER_REACH := 60.0       # how far a river under a viaduct reaches from the deck: the far banks, where the backdrops of trees and houses stand
const PARAPET := 1.1
const BOX_TOP := 3.6            # ceiling of the box tunnel
const TILE := 36.0              # the backdrops repeat every 36 m (3 cells of the ride)
const BD_TREES := 12.0
const BD_HOUSES := 14.0
const FENCE := "char:open/fence.png|1.000|1.200|1"

static var _bd: Dictionary = {}
static var _mx := Mutex.new()


## the profile a section of the data ("sec" code: 0 open, 1 tunnel, 2 cutting, 3 embankment, 4 viaduct) is, for a line of the sub-surface group or not
static func profile_of(code: int, ss: bool) -> int:
	match code:
		1:
			return BOX if ss else BORE
		2:
			return CUTTING
		3:
			return EMBANK
		4:
			return VIADUCT
	return OPEN


## how much of the outdoors a passenger hears (1 in the open, on a viaduct or an embankment; the banks of a cutting muffle it)
static func open_weight(p: int) -> float:
	if enclosed(p):
		return 0.0
	return 0.7 if p == CUTTING else 1.0


static func enclosed(p: int) -> bool:
	return p == BORE or p == BOX


## full height of a raised or sunk profile
static func full_height(prof: int, tall: bool) -> float:
	if prof == CUTTING:
		return CUT_H
	return VIA_H if tall else EMB_H


# ---------------------------------------------------------------------------------------------------------------------------------------
# materials of the backdrops (alpha-cut strips of trees and the backs of houses, unshaded, tinted by the time of day like the platforms' own)
# ---------------------------------------------------------------------------------------------------------------------------------------

static func material(key: String) -> Material:
	_mx.lock()
	var m: StandardMaterial3D = _bd.get(key)
	if m == null:
		var tex := key.substr(3)
		m = StandardMaterial3D.new()
		var p := "res://assets/textures/char/open/%s.png" % tex
		if ResourceLoader.exists(p):
			m.albedo_texture = load(p)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.uv1_scale = Vector3(1.0 / TILE, 1.0 / (BD_TREES if tex == "trees" else BD_HOUSES), 1.0)
		m.albedo_color = _tint(tex)
		_bd[key] = m
	_mx.unlock()
	return m


## the glass of a signal lamp or an emergency light ("light_emissive_red" / "_green" / "_blue")
static func lamp_material(key: String) -> Material:
	_mx.lock()
	var m: StandardMaterial3D = _bd.get(key)
	if m == null:
		var col := Color(1, 0.1, 0.1) if key.ends_with("red") else (Color(0.1, 1, 0.3) if key.ends_with("green") else Color(0.2, 0.4, 1.0))
		m = StandardMaterial3D.new()
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 4.0
		_bd[key] = m
	_mx.unlock()
	return m


static func _tint(tex: String) -> Color:
	var day := PlatformOpen.daylight()
	var t := lerpf(0.10, 1.0, day)
	var warm := Color(t, t * lerpf(0.9, 1.0, day), t * lerpf(1.0, 0.96, day))
	return warm if tex == "trees" else warm.darkened(0.12)


## the strips follow the clock: call when a ride starts or a station is built
static func refresh_day() -> void:
	_mx.lock()
	for k in _bd:
		if String(k).begins_with("bd:"):
			(_bd[k] as StandardMaterial3D).albedo_color = _tint(String(k).substr(3))
	_mx.unlock()


# ---------------------------------------------------------------------------------------------------------------------------------------
# the stretch between x0 and x1 for the track at z = t. `o`: la / lb (levels 0..3 of a cutting / embankment at x0 / x1), tall (a viaduct run: the embankment ramps to its height), v (variant 0..5),
# u0 (position along the line of x0, so the backdrops repeat seamlessly), seed (a cutting: banks or brick walls), near_flat (a station's other track lies there: ground only on the platform side)
# The rails and sleepers are the caller's.
# ---------------------------------------------------------------------------------------------------------------------------------------

static func add(kit: MeshKit, prof: int, x0: float, x1: float, t: float, o: Dictionary = {}) -> void:
	match prof:
		OPEN:
			_open(kit, x0, x1, t, o)
		CUTTING:
			_cutting(kit, x0, x1, t, o)
		EMBANK:
			_embank(kit, x0, x1, t, o)
		VIADUCT:
			_viaduct(kit, x0, x1, t, o)
		BOX:
			_box(kit, x0, x1, t, o)


# ---------------------------------------------------------------------------------------------------------------------------------------
# scenes: what each 12 m cell of a line (the ride's TunnelRun cells, and the running track beyond a platform) shows, as one number
#   profile (bits 0-2) | level at the entry (3-4) | level at the exit (5-6) | tall (7) | headwall at the entry (8) | headwall at the exit (9) | brick-walled cutting (10) | sub-surface line (11)
# The level is how far a cutting / embankment has risen yet (0..3 thirds of its height): they ramp up over three cells from where they begin, so that the land does not step.
# ---------------------------------------------------------------------------------------------------------------------------------------

const CELL := 12.0
const PAIR_RIGHT := 1 << 21     # scene bit (a ride sets it, never the data): the other track lies to the +z side of this one (a ride whose train has its doors on the left runs on the left and meets its trains on the right); without it, to the -z side
const PAIR := 1 << 12          # scene bit: the other track of the pair lies beside this one (12.9 m off, on the platform side, the same distance as the two tracks of a station): in the open the line is double track
const CROSS := 1 << 22         # scene bit (TrackPath's, with PAIR): in this cell of open land the other track changes sides, a flat crossing: the cell's entry / exit fields (bits 13 - 16, 17 - 20) are how far across it is (0..15 of 15)
                               # and bits 23 - 25 the spacing it crosses at (cross_spacing); PAIR_RIGHT is the side it ends on, in the cell's own frame
const CROSS_S_SHIFT := 23
const SIDE_LEFT := 1 << 26     # scene bit (TrackPath's, in path terms, never in a cell's key): the other track is on the LEFT of the train (a station module whose platforms are on the left has its other face there), or ends the crossing on the left

const TRACK_SPACING := 2.0 * (PlatformModule.GAP * 0.5 + PlatformModule.PW_RUN + PlatformModule.TRACK_TO_EDGE)          # (the two tracks of a station module)
const SPLIT_SPACING := 3.5     # the two tracks between a pair of side platforms (StationPlan.is_split): module pitch = TRACK_SPACING + this; the ride keeps it out to the first bend
const SPACING_MIN := SPLIT_SPACING       # ... and of the line between the stations (the real 3.5 - 4 m), reached in 15 steps over RAMP_LEN
const PAIR_LEVELS := 15
const RAMP_STATION := 200.0    # within this far of a stop (the module's own running track) the two tracks keep the station's spacing
const RAMP_LEN := 180.0        # ... and, coming out of a tunnel, they narrow over this far (scene bits 13-16: spacing level at the cell's entry, 17-20: at its exit)


## the pair levels a crossing can happen at (3 bits of the scene pick one): the cells either side of it are flattened to the same level, so the tracks meet it at exactly its spacing
const CROSS_LEVELS := [15, 12, 9, 7, 5, 3, 1, 0]


static func cross_level(scene: int) -> int:
	return CROSS_LEVELS[(scene >> CROSS_S_SHIFT) & 7]


static func cross_spacing(scene: int) -> float:
	return spacing_of_level(cross_level(scene))


## the code of the crossing level nearest to pair level `level`
static func cross_code(level: int) -> int:
	var best := 0
	for i in CROSS_LEVELS.size():
		if absi(int(CROSS_LEVELS[i]) - level) < absi(int(CROSS_LEVELS[best]) - level):
			best = i
	return best


static func scene_prof(sc: int) -> int:
	return sc & 7


## the spacing of the two tracks at a pair level (0: a station's, PAIR_LEVELS: the line's)
static func spacing_of_level(l: int) -> float:
	return lerpf(TRACK_SPACING, SPACING_MIN, float(clampi(l, 0, PAIR_LEVELS)) / float(PAIR_LEVELS))


## the level at a place `d_stop` metres from the nearest stop and `d_tunnel` metres from the nearest tunnel (BORE / BOX) cell: the tracks come together smoothly, away from the stations and the mouths
static func pair_level(d_stop: float, d_tunnel: float) -> int:
	var u := minf(clampf((d_stop - RAMP_STATION) / RAMP_LEN, 0.0, 1.0), clampf(d_tunnel / RAMP_LEN, 0.0, 1.0))
	return int(roundf(float(PAIR_LEVELS) * smoothstep(0.0, 1.0, u)))


## `secs`: [[sec code, metres], ...] of the line from the stop (0 = open, 1 tunnel, 2 cutting, 3 embankment, 4 viaduct); cells k0..k1 (cell k covers k * 12 +- 6 m; before the start and past the end the first / last stretch goes on)
## `split_a` / `split_b`: the stop at the start / end of the ride is a pair of side platforms (StationPlan.is_split), where the tracks already lie SPACING_MIN apart: no ramp there
## `water`: [[metres from the start, width], ...] of the rivers under the viaducts: a viaduct cell within a river's width gets scene bit 10 (the brick bit, which only a cutting reads otherwise) and shows water under it
static func cell_scenes(secs: Array, ss: bool, seed: int, k0: int, k1: int, dist := -1.0, single := false, split_a := false, split_b := false, water := []) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(k1 - k0 + 1)
	if secs.is_empty():
		secs = [[1, 1000.0]]
	var n := secs.size()
	var s0: Array = []
	var s1: Array = []
	var pos := 0.0
	for r in secs:
		s0.append(pos)
		pos += float(r[1])
		s1.append(pos)
	# the stretch of a position: the last one starting at or before it
	var run_at := func(sv: float) -> int:
		var ri := 0
		for i in n:
			if sv >= float(s0[i]) - 0.001:
				ri = i
		return ri
	# a family: the neighbouring stretches of the same sort (embankment and viaduct are one), as [first run, last run]
	var fam := func(ri: int) -> Array:
		var c: int = int(secs[ri][0])
		var same := func(a: int, b: int) -> bool:
			return a == b or (a >= 3 and b >= 3)
		var a := ri
		var b := ri
		while a > 0 and same.call(int(secs[a - 1][0]), c):
			a -= 1
		while b < n - 1 and same.call(int(secs[b + 1][0]), c):
			b += 1
		return [a, b]
	var level := func(sv: float, f: Array) -> int:
		var fa: int = f[0]
		var fb: int = f[1]
		var da := 1e9
		var db := 1e9
		# a family that begins at the stop, or opens out of a tunnel, is at full height from the start
		if fa > 0 and int(secs[fa - 1][0]) != 1:
			da = sv - float(s0[fa])
		if fb < n - 1 and int(secs[fb + 1][0]) != 1:
			db = float(s1[fb]) - sv
		return clampi(int(roundf(minf(da, db) / CELL)), 0, 3)
	var prof_of_cell := func(k: int) -> int:
		var ri: int = run_at.call(float(k) * CELL)
		return profile_of(int(secs[ri][0]), ss)
	# the spacing level of the two tracks at every cell boundary (boundary j lies between cells j - 1 and j): only for a ride (`dist` >= 0); a station's running track keeps the station's spacing
	single = single or Station.debug_off("pair")          # (UG_OFF=pair: no second track, for A/B frame-time runs)
	var lv := PackedInt32Array()
	if dist >= 0.0:
		var m0 := k0 - 18
		var m1 := k1 + 18
		var enc: Array = []
		for m in range(m0, m1 + 1):
			enc.append(enclosed(prof_of_cell.call(m)))
		lv.resize(k1 - k0 + 2)
		for j in range(k0, k1 + 2):
			var pb := float(j) * CELL - CELL * 0.5
			var d_tun := 1e9
			for m in range(maxi(m0, j - 17), mini(m1, j + 16) + 1):
				if enc[m - m0]:
					d_tun = minf(d_tun, maxf(absf(pb - float(m) * CELL) - CELL * 0.5, 0.0))
			var d_stop := -pb if pb < 0.0 else (pb - dist if pb > dist else minf(pb, dist - pb))
			if split_a or split_b:
				var da := 1e9 if split_a else absf(pb)          # (distance from the stop at the start / the end of the ride)
				var db := 1e9 if split_b else absf(pb - dist)
				d_stop = minf(da, db)
			lv[j - k0] = pair_level(d_stop, d_tun)
	for k in range(k0, k1 + 1):
		var sc := float(k) * CELL
		var ri: int = run_at.call(sc)
		var code: int = int(secs[ri][0])
		var prof := profile_of(code, ss)
		var la := 0
		var lb := 0
		var tall := 0
		var brick := 0
		if code == 2 or code >= 3:
			var f: Array = fam.call(ri)
			la = level.call(sc - CELL * 0.5, f)
			lb = level.call(sc + CELL * 0.5, f)
			if code == 2:
				var real_len := 0.0
				for i in range(f[0], f[1] + 1):
					real_len += float(secs[i][2]) if secs[i].size() > 2 else float(secs[i][1])          # (the length on the ground: a ride stretches its sections a little, the station does not)
				brick = 1 if (seed + int(real_len / 50.0)) % 3 == 0 else 0
			else:
				for i in range(f[0], f[1] + 1):
					if int(secs[i][0]) == 4:
						tall = 1
				prof = VIADUCT if (code == 4 and la == 3 and lb == 3) else EMBANK
		if prof == VIADUCT and not water.is_empty():
			for w in water:
				if absf(sc - float(w[0])) <= float(w[1]) * 0.5 + CELL * 0.5:
					brick = 1          # (over a river)
		var pa := 0
		var pb := 0
		if not enclosed(prof):
			pa = 1 if enclosed(prof_of_cell.call(k - 1)) else 0
			pb = 1 if enclosed(prof_of_cell.call(k + 1)) else 0
			if pa == 1 and (code == 2 or code >= 3):
				la = 3
			if pb == 1 and (code == 2 or code >= 3):
				lb = 3
		var sc_bits := prof | (la << 3) | (lb << 5) | (tall << 7) | (pa << 8) | (pb << 9) | (brick << 10) | ((1 if ss else 0) << 11) | (0 if enclosed(prof) or single else PAIR)
		if dist >= 0.0 and not enclosed(prof) and not single:
			sc_bits |= (lv[k - k0] << 13) | (lv[k - k0 + 1] << 17)
		out[k - k0] = sc_bits
	return out


## the cell `scene` (variant v) between x0 and x1 for the track at z = t. o: u0, near_flat as for `add`.
## With the PAIR bit the other track of the line is built too: the same scene mirrored across the spine (z = 0, where t = ztrack of a module), rails and sleepers included - a station module builds that
## track itself (its other face), so it clears the bit there.
static func add_scene(kit: MeshKit, scene: int, v: int, x0: float, x1: float, t: float, o: Dictionary = {}) -> void:
	if (scene & CROSS) != 0 and (scene & 7) == OPEN:
		_add_cross(kit, scene, v, x0, x1, t, o)
		return
	var pair := (scene & PAIR) != 0 and not enclosed(scene & 7)
	var oo := o.duplicate()
	var ns := 1.0 if (scene & PAIR_RIGHT) != 0 else -1.0          # which side the other track is on
	var sh0 := 0.0          # where the other track's copy ends up (see below), at x0 and at x1
	var sh1 := 0.0
	if pair:
		var s0 := spacing_of_level((scene >> 13) & 15)          # the spacing of the two tracks at x0 and at x1
		var s1 := spacing_of_level((scene >> 17) & 15)
		oo["ns"] = ns
		oo["flat0"] = t + ns * s0 * 0.5          # (the ground between the tracks ends half way)
		oo["flat1"] = t + ns * s1 * 0.5
		sh0 = 2.0 * t + ns * s0
		sh1 = 2.0 * t + ns * s1
	_scene_kit(kit, scene, v, x0, x1, t, oo, pair, false)
	if pair:
		# the other track is the mirror image of this one across the line half way between them: built beside this one's own frame, reflected (z -> -z), then moved to its place (z -> 2 t + ns * spacing - z)
		var other := MeshKit.new()
		other.seed_rng(11 + v)
		_scene_kit(other, scene, v, x0, x1, t, oo, true, true)          # (the same variant: a station's other face has the main face's, so the signals stand level)
		track(other, x0, x1, t)
		other.mirror_z()
		if absf(sh0) > 0.0001 or absf(sh1) > 0.0001:
			other.shear_z(x0, x1, sh0, sh1)
		kit.merge(other)


## A cell of open land where the other track crosses this one (a flat crossover: TrackPath._plan_sides puts it where the other end of the hop wants the track on the other side): this track as a single one with
## the lineside of both sides, the other's rails and sleepers sheared across it from one side to the other, and the ground cut away from both formations wherever they lie.
const CROSS_SLICES := 8
const CROSS_LIFT := 0.012          # the other track lies this much above this one's where they cross (no z-fighting; the ballast under it a little below this one's)


## where the other track is in the cell's frame (+z = the side PAIR_RIGHT names) at the entry and at the exit: [offset at x0, offset at x1]
static func cross_offsets(scene: int) -> Vector2:
	var s := cross_spacing(scene)
	var d := 1.0 if (scene & PAIR_RIGHT) != 0 else -1.0
	return Vector2(d * s * (2.0 * float((scene >> 13) & 15) / 15.0 - 1.0), d * s * (2.0 * float((scene >> 17) & 15) / 15.0 - 1.0))


static func _add_cross(kit: MeshKit, scene: int, v: int, x0: float, x1: float, t: float, o: Dictionary) -> void:
	var off := cross_offsets(scene)
	var oo := o.duplicate()
	oo["cross"] = true
	var main_scene := scene & ~(PAIR | PAIR_RIGHT | CROSS | (15 << 13) | (15 << 17) | (7 << CROSS_S_SHIFT))
	_scene_kit(kit, main_scene, v, x0, x1, t, oo, false, false)
	var bed := PlatformModule.BED_Y
	for i in CROSS_SLICES:
		var fa := float(i) / float(CROSS_SLICES)
		var fb := float(i + 1) / float(CROSS_SLICES)
		var xa := lerpf(x0, x1, fa)
		var xb := lerpf(x0, x1, fb)
		var oa := lerpf(off.x, off.y, fa)
		var ob := lerpf(off.x, off.y, fb)
		for sg: float in [1.0, -1.0]:
			# on this side (u = distance out from the track's own line): its formation ends at 2.9, the other's spans c - 2.9 .. c + 2.9
			var ca := sg * oa
			var cb := sg * ob
			# the ground between the two formations, when the other lies clear of this one
			var ia0 := 2.9
			var ia1 := maxf(ca - 2.9, 2.9)
			var ib0 := 2.9
			var ib1 := maxf(cb - 2.9, 2.9)
			if ia1 > ia0 + 0.001 or ib1 > ib0 + 0.001:
				_strip(kit, "grass", xa, xb, t + sg * ia0, G, t + sg * ib0, G, t + sg * ia1, G, t + sg * ib1, G)
			# ... and out beyond the outer one
			var oa0 := maxf(2.9, ca + 2.9)
			var ob0 := maxf(2.9, cb + 2.9)
			_strip(kit, "grass", xa, xb, t + sg * oa0, G, t + sg * ob0, G, t + sg * GW, G, t + sg * GW, G)
			# the edge of this formation, where the other's does not cover it
			if not (ca - 2.9 < 2.9 and ca + 2.9 > 2.9 and cb - 2.9 < 2.9 and cb + 2.9 > 2.9):
				_wallq(kit, "ballast", Vector3(xa, G, t + sg * 2.9), Vector3(xa, bed, t + sg * 2.9), Vector3(xb, bed, t + sg * 2.9), Vector3(xb, G, t + sg * 2.9), Vector3(0, 0, -sg))
			# the other formation's edges on this side, where they stand in the grass (outside this formation): the outer one faces in, the inner one (when it is clear of this) out
			for e: float in [-1.0, 1.0]:
				var za := ca + e * 2.9
				var zb := cb + e * 2.9
				if za > 2.9 and zb > 2.9:
					_wallq(kit, "ballast", Vector3(xa, G, t + sg * za), Vector3(xa, bed, t + sg * za), Vector3(xb, bed, t + sg * zb), Vector3(xb, G, t + sg * zb), Vector3(0, 0, -sg * e))
	# the other track itself: bed, sleepers and rails, sheared across
	var other := MeshKit.new()
	other.seed_rng(11 + v)
	other.horiz("ballast", x0, x1, t - 2.9, t + 2.9, bed - 0.006, true, bed)
	var rails := MeshKit.new()
	track(rails, x0, x1, t)
	_lift(rails, CROSS_LIFT)
	other.merge(rails)
	other.shear_z(x0, x1, off.x, off.y)
	kit.merge(other)


## every point of a kit moves up by dy
static func _lift(kit: MeshKit, dy: float) -> void:
	for name in kit.surfaces:
		var vv: PackedVector3Array = kit.surfaces[name]["v"]
		for i in vv.size():
			vv[i] = Vector3(vv[i].x, vv[i].y + dy, vv[i].z)
		kit.surfaces[name]["v"] = vv


static func _scene_kit(kit: MeshKit, scene: int, v: int, x0: float, x1: float, t: float, o: Dictionary, near_flat: bool, stub: bool) -> MeshKit:
	var prof := scene & 7
	var ss := ((scene >> 11) & 1) == 1
	var oo := o.duplicate()
	oo["la"] = (scene >> 3) & 3
	oo["lb"] = (scene >> 5) & 3
	oo["tall"] = ((scene >> 7) & 1) == 1
	oo["seed"] = 0 if ((scene >> 10) & 1) == 1 else 1
	oo["water"] = prof == VIADUCT and ((scene >> 10) & 1) == 1          # (the brick bit of a viaduct cell: a river runs under it)
	oo["v"] = v
	if near_flat:
		oo["near_flat"] = true
	oo["stub"] = stub          # (the other track's tunnel mouth shows a few metres of its tunnel: the cell next door does not hold it)
	add(kit, prof, x0, x1, t, oo)
	var bore := BOX if ss else BORE
	if ((scene >> 8) & 1) == 1:
		portal(kit, bore, prof, x0, 1, t, oo)
	if ((scene >> 9) & 1) == 1:
		portal(kit, bore, prof, x1, -1, t, oo)
	return kit


## the rails (two running rails, the centre and the outer one) and the sleepers of the track at z = t between x0 and x1
static func track(kit: MeshKit, x0: float, x1: float, t: float) -> void:
	var xm := (x0 + x1) * 0.5
	for dz in [-0.7175, 0.7175]:
		kit.box("rail", Vector3(xm, PlatformModule.RAIL_Y - 0.08, t + dz), Vector3(x1 - x0, 0.16, 0.07), PlatformModule.BED_Y)
	kit.box("rail", Vector3(xm, PlatformModule.RAIL_Y - 0.07, t), Vector3(x1 - x0, 0.10, 0.06), PlatformModule.BED_Y)
	kit.box("rail", Vector3(xm, PlatformModule.RAIL_Y - 0.07, t - 1.05), Vector3(x1 - x0, 0.10, 0.06), PlatformModule.BED_Y)
	kit.horiz("track_sleepers", x0, x1, t - 1.3, t + 1.3, PlatformModule.BED_Y + 0.004, true, PlatformModule.BED_Y)


# --- helpers -----------------------------------------------------------------------------------------------------------------------------

## a quad facing +y (or the way of `hint`): p0..p3 in any order that is a loop; the winding is chosen to match
static func _q(kit: MeshKit, mat: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, hint := Vector3.UP, uv0 := Vector2.ZERO) -> void:
	var n := (p1 - p0).cross(p2 - p0)
	if n.length_squared() < 1e-10:
		n = (p1 - p0).cross(p3 - p0)
	if n.dot(hint) < 0.0:
		kit.quad(mat, p0, p3, p2, p1, 0.0, uv0)
	else:
		kit.quad(mat, p0, p1, p2, p3, 0.0, uv0)


## a vertical wall between two ground points with a top that may differ at the ends: tl, bl, br, tr seen from the front (which side `hint` points to); texture upright
static func _wallq(kit: MeshKit, mat: String, tl: Vector3, bl: Vector3, br: Vector3, tr: Vector3, hint: Vector3, uv0 := Vector2.ZERO) -> void:
	var n := (bl - tl).cross(br - tl)
	if n.dot(hint) < 0.0:
		kit.quad(mat, tr, br, bl, tl, 0.0, uv0, 0.0, true)
	else:
		kit.quad(mat, tl, bl, br, tr, 0.0, uv0, 0.0, true)


## a strip along x between two lines (z, y at x0 and at x1 for each): the ground, a bank
static func _strip(kit: MeshKit, mat: String, x0: float, x1: float, za0: float, ya0: float, za1: float, ya1: float, zb0: float, yb0: float, zb1: float, yb1: float, up := true) -> void:
	_q(kit, mat, Vector3(x0, ya0, za0), Vector3(x1, ya1, za1), Vector3(x1, yb1, zb1), Vector3(x0, yb0, zb0), Vector3.UP if up else Vector3.DOWN)


## a fence that reads from both sides: base from (x0, ya) to (x1, yb) at z
static func _fence(kit: MeshKit, x0: float, x1: float, z: float, ya: float, yb: float, h := 1.2) -> void:
	for side: int in [0, 1]:
		var zz := z + 0.01 * side
		_wallq(kit, FENCE, Vector3(x0, ya + h, zz), Vector3(x0, ya, zz), Vector3(x1, yb, zz), Vector3(x1, yb + h, zz), Vector3(0, 0, 1.0 if side == 0 else -1.0), Vector2(x0, 0.0))


## a backdrop strip (trees / houses) at z with its foot at ya (x0) .. yb (x1)
static func _backdrop(kit: MeshKit, tex: String, x0: float, x1: float, z: float, ya: float, yb: float, u0: float) -> void:
	var h := BD_TREES if tex == "trees" else BD_HOUSES
	var key := "bd:" + tex
	kit.quad(key, Vector3(x0, ya + h, z), Vector3(x0, ya, z), Vector3(x1, yb, z), Vector3(x1, yb + h, z), 0.0, Vector2(fposmod(u0, TILE), 0.0), 0.0, true)


static func _backdrops(kit: MeshKit, x0: float, x1: float, t: float, o: Dictionary, trees_dz: float, houses_dz: float, ya: float, yb: float) -> void:
	var u0: float = o.get("u0", x0)
	var near_flat: bool = o.get("near_flat", false)
	for sg: float in [1.0, -1.0]:
		if sg == float(o.get("ns", -1.0)) and near_flat:
			continue
		_backdrop(kit, "trees", x0, x1, t + sg * trees_dz, ya, yb, u0)
		_backdrop(kit, "houses", x0, x1, t + sg * houses_dz, ya, yb, u0 + 7.0)


## where the ground between a station's two tracks ends, at x0 and at x1 (z of the line half way to the other track; 0, the spine, for a station module)
static func _flat(o: Dictionary) -> Vector2:
	return Vector2(float(o.get("flat0", 0.0)), float(o.get("flat1", 0.0)))


## is there ground (not just touching formations) between the edge of this track's formation, at z = edge, and the line half way to the other track?
static func _gap(fl: Vector2, edge: float, ns: float) -> bool:
	return ns * (fl.x - edge) > 0.05 and ns * (fl.y - edge) > 0.05


## ballast across the formation
static func _formation(kit: MeshKit, x0: float, x1: float, t: float, half := 2.9) -> void:
	kit.horiz("ballast", x0, x1, t - half, t + half, PlatformModule.BED_Y, true, PlatformModule.BED_Y)


## lineside furniture by variant: a signal post on the track-side, or an equipment cabinet and a cable trough
static func _lineside(kit: MeshKit, x0: float, x1: float, t: float, v: int, dz: float, y: float) -> void:
	var xm := (x0 + x1) * 0.5
	var sg := signf(dz)          # (dz < 0: the furniture is on the -z side, facing +z)
	match v % 3:
		1:
			kit.box("steel", Vector3(xm - 2.0, y + 1.5, t + dz), Vector3(0.12, 3.0, 0.12), y)
			kit.box("light_emissive_red", Vector3(xm - 2.0, y + 2.6, t + dz - 0.1 * sg), Vector3(0.22, 0.22, 0.05), y)
			kit.box("light_emissive_green", Vector3(xm - 2.0, y + 2.25, t + dz - 0.1 * sg), Vector3(0.22, 0.22, 0.05), y)
		2:
			kit.box("concrete", Vector3(xm + 1.0, y + 0.75, t + dz + 0.6 * sg), Vector3(2.2, 1.5, 0.9), y)
			kit.box("steel", Vector3(xm + 1.0, y + 1.56, t + dz + 0.6 * sg), Vector3(2.3, 0.1, 1.0), y)
	# the cable trough beside the ballast, the whole stretch
	kit.box("concrete", Vector3(xm, PlatformModule.BED_Y + 0.14, t + 2.35 * sg), Vector3(x1 - x0, 0.28, 0.4), PlatformModule.BED_Y)


# --- open railway land --------------------------------------------------------------------------------------------------------------------

static func _open(kit: MeshKit, x0: float, x1: float, t: float, o: Dictionary) -> void:
	var v: int = o.get("v", 0)
	var near_flat: bool = o.get("near_flat", false)
	var ns: float = float(o.get("ns", -1.0))          # (the side the other track is on)
	var fl := _flat(o)
	var gap := near_flat and _gap(fl, t + ns * 2.9, ns)
	_formation(kit, x0, x1, t)
	# the ground, a step above the ballast (a crossing builds its own: the other track's formation is a hole in it that moves)
	for sg: float in ([] if bool(o.get("cross", false)) else [1.0, -1.0]):
		if sg == ns and near_flat:
			if gap:
				_strip(kit, "grass", x0, x1, t + ns * 2.9, G, t + ns * 2.9, G, fl.x, G, fl.y, G)
			else:
				continue          # (the formations of the two tracks touch)
		else:
			_strip(kit, "grass", x0, x1, t + sg * 2.9, G, t + sg * 2.9, G, t + sg * GW, G, t + sg * GW, G)
		_wallq(kit, "ballast", Vector3(x0, G, t + sg * 2.9), Vector3(x0, PlatformModule.BED_Y, t + sg * 2.9), Vector3(x1, PlatformModule.BED_Y, t + sg * 2.9), Vector3(x1, G, t + sg * 2.9), Vector3(0, 0, -sg))
	_lineside(kit, x0, x1, t, v, (FAR + 0.6) * -ns, G)
	if not (near_flat and ns < 0.0):
		_fence(kit, x0, x1, t - 7.0, G, G)
	if not (near_flat and ns > 0.0):
		_fence(kit, x0, x1, t + 7.0, G, G)
	_backdrops(kit, x0, x1, t, o, 13.0, 32.0, G, G)


# --- cutting ------------------------------------------------------------------------------------------------------------------------------

## banks of grass, or brick retaining walls (a run is one or the other, by the seed)
static func _cutting(kit: MeshKit, x0: float, x1: float, t: float, o: Dictionary) -> void:
	var v: int = o.get("v", 0)
	var la: float = float(o.get("la", 3)) / 3.0
	var lb: float = float(o.get("lb", 3)) / 3.0
	var ha := CUT_H * la
	var hb := CUT_H * lb
	var near_flat: bool = o.get("near_flat", false)
	var ns: float = float(o.get("ns", -1.0))
	var fl := _flat(o)
	var gap := near_flat and _gap(fl, t + ns * 2.9, ns)
	var brick: bool = int(o.get("seed", 0)) % 3 == 0
	_formation(kit, x0, x1, t)
	for sg: float in [1.0, -1.0]:
		if sg == ns and near_flat:
			if gap:
				_strip(kit, "grass", x0, x1, t + ns * 2.9, G, t + ns * 2.9, G, fl.x, G, fl.y, G)
			continue
		if brick:
			var wz := 5.2 if sg < 0.0 else 3.4          # (the platform side of the running tunnel is wider: the walls clear it)
			# ground at the foot, the wall, the ground on top
			_strip(kit, "gravel", x0, x1, t + sg * 2.9, G, t + sg * 2.9, G, t + sg * wz, G, t + sg * wz, G)
			var hw_a := minf(ha, 3.6)
			var hw_b := minf(hb, 3.6)
			_wallq(kit, "brick_stock", Vector3(x0, G + hw_a, t + sg * wz), Vector3(x0, PlatformModule.BED_Y, t + sg * wz), Vector3(x1, PlatformModule.BED_Y, t + sg * wz), Vector3(x1, G + hw_b, t + sg * wz), Vector3(0, 0, -sg))
			_strip(kit, "grass", x0, x1, t + sg * wz, G + hw_a, t + sg * wz, G + hw_b, t + sg * GW, G + hw_a, t + sg * GW, G + hw_b)
			if hw_a + hw_b > 0.5:
				_fence(kit, x0, x1, t + sg * (wz + 0.5), G + hw_a, G + hw_b)
			_backdrops_side(kit, x0, x1, t, sg, o, 13.0, 32.0, G + hw_a, G + hw_b)
		else:
			var za := SHOULDER + ha * SLOPE
			var zb := SHOULDER + hb * SLOPE
			# the bank in two bands: bare earth at the foot, scrub above it
			var fa := 0.22
			_strip(kit, "gravel", x0, x1, t + sg * 2.9, G, t + sg * 2.9, G, t + sg * SHOULDER, G, t + sg * SHOULDER, G)
			_strip(kit, "earth", x0, x1, t + sg * SHOULDER, G, t + sg * SHOULDER, G, t + sg * lerpf(SHOULDER, za, fa), G + ha * fa, t + sg * lerpf(SHOULDER, zb, fa), G + hb * fa)
			_strip(kit, "grass_dark", x0, x1, t + sg * lerpf(SHOULDER, za, fa), G + ha * fa, t + sg * lerpf(SHOULDER, zb, fa), G + hb * fa, t + sg * za, G + ha, t + sg * zb, G + hb)
			_strip(kit, "grass", x0, x1, t + sg * za, G + ha, t + sg * zb, G + hb, t + sg * GW, G + ha, t + sg * GW, G + hb)
			if ha + hb > 1.0:
				_fence(kit, x0, x1, t + sg * (CUT_H * SLOPE + SHOULDER + 0.6), G + ha, G + hb)
			_backdrops_side(kit, x0, x1, t, sg, o, CUT_H * SLOPE + SHOULDER + 8.0, CUT_H * SLOPE + SHOULDER + 26.0, G + ha, G + hb)
		if sg == -ns:
			_lineside(kit, x0, x1, t, v, (FAR + 0.3) * sg, G)


static func _backdrops_side(kit: MeshKit, x0: float, x1: float, t: float, sg: float, o: Dictionary, trees_dz: float, houses_dz: float, ya: float, yb: float) -> void:
	var u0: float = o.get("u0", x0)
	_backdrop(kit, "trees", x0, x1, t + sg * trees_dz, ya, yb, u0)
	_backdrop(kit, "houses", x0, x1, t + sg * houses_dz, ya, yb, u0 + 7.0)


# --- embankment ---------------------------------------------------------------------------------------------------------------------------

static func _embank(kit: MeshKit, x0: float, x1: float, t: float, o: Dictionary) -> void:
	var v: int = o.get("v", 0)
	var tall: bool = o.get("tall", false)
	var hmax := full_height(EMBANK, tall)
	var ha := hmax * float(o.get("la", 3)) / 3.0
	var hb := hmax * float(o.get("lb", 3)) / 3.0
	var near_flat: bool = o.get("near_flat", false)
	var ns: float = float(o.get("ns", -1.0))
	var fl := _flat(o)
	var gap := near_flat and _gap(fl, t + ns * 2.9, ns)
	_formation(kit, x0, x1, t)
	for sg: float in [1.0, -1.0]:
		if sg == ns and near_flat:
			if gap:
				_strip(kit, "grass", x0, x1, t + ns * 2.9, G, t + ns * 2.9, G, fl.x, G, fl.y, G)
			continue
		var za := SHOULDER + 0.4 + ha * 1.6
		var zb := SHOULDER + 0.4 + hb * 1.6
		var zfoot := SHOULDER + 0.4 + hmax * 1.6
		_strip(kit, "gravel", x0, x1, t + sg * 2.9, G, t + sg * 2.9, G, t + sg * (SHOULDER + 0.4), G, t + sg * (SHOULDER + 0.4), G)
		_strip(kit, "grass", x0, x1, t + sg * (SHOULDER + 0.4), G, t + sg * (SHOULDER + 0.4), G, t + sg * za, G - ha, t + sg * zb, G - hb)
		_strip(kit, "grass", x0, x1, t + sg * za, G - ha, t + sg * zb, G - hb, t + sg * GW, G - ha, t + sg * GW, G - hb)
		_fence(kit, x0, x1, t + sg * (SHOULDER + 0.2), G, G, 1.1)
		_backdrops_side(kit, x0, x1, t, sg, o, zfoot + 6.0, zfoot + 24.0, G - ha, G - hb)
	_lineside(kit, x0, x1, t, v, (FAR + 0.3) * -ns, G)


# --- viaduct ------------------------------------------------------------------------------------------------------------------------------

static func _viaduct(kit: MeshKit, x0: float, x1: float, t: float, o: Dictionary) -> void:
	var near_flat: bool = o.get("near_flat", false)
	var ns: float = float(o.get("ns", -1.0))
	var gy := G - VIA_H
	kit.horiz("ballast", x0, x1, t - VIA_HALF, t + VIA_HALF, PlatformModule.BED_Y, true, PlatformModule.BED_Y)
	for sg: float in [1.0, -1.0]:
		if sg == ns and near_flat:
			continue          # (a flat deck out to the other track, below)
		var zp := t + sg * VIA_HALF
		# parapet: inner face, outer face, coping
		_wallq(kit, "brick_red", Vector3(x0, G + PARAPET, zp), Vector3(x0, PlatformModule.BED_Y, zp), Vector3(x1, PlatformModule.BED_Y, zp), Vector3(x1, G + PARAPET, zp), Vector3(0, 0, -sg))
		_wallq(kit, "brick_red", Vector3(x0, G + PARAPET, zp + sg * 0.45), Vector3(x0, gy, zp + sg * 0.45), Vector3(x1, gy, zp + sg * 0.45), Vector3(x1, G + PARAPET, zp + sg * 0.45), Vector3(0, 0, sg))
		_q(kit, "concrete", Vector3(x0, G + PARAPET, zp), Vector3(x1, G + PARAPET, zp), Vector3(x1, G + PARAPET, zp + sg * 0.45), Vector3(x0, G + PARAPET, zp + sg * 0.45), Vector3.UP)
		_strip(kit, "grass", x0, x1, zp + sg * 0.45, gy, zp + sg * 0.45, gy, t + sg * GW, gy, t + sg * GW, gy)
	var fl := _flat(o)
	if near_flat and _gap(fl, t + ns * VIA_HALF, ns):
		_strip(kit, "ballast", x0, x1, fl.x, PlatformModule.BED_Y, fl.y, PlatformModule.BED_Y, t + ns * VIA_HALF, PlatformModule.BED_Y, t + ns * VIA_HALF, PlatformModule.BED_Y)
	if o.get("water", false):
		# a river under the viaduct: water out to the far bank, 60 m either side (seen over the parapet at a shallow angle, not from just beside the track), where the trees and the houses stand
		kit.horiz("water", x0, x1, t - (VIA_HALF + WATER_REACH), t + (VIA_HALF + WATER_REACH), gy + 0.06, true, gy)
		_backdrops(kit, x0, x1, t, o, VIA_HALF + WATER_REACH + 2.0, VIA_HALF + WATER_REACH + 20.0, gy + 0.06, gy + 0.06)
		return
	_backdrops(kit, x0, x1, t, o, VIA_HALF + 12.0, VIA_HALF + 28.0, gy, gy)


# --- cut-and-cover box tunnel (sub-surface lines) -----------------------------------------------------------------------------------------

static func _box(kit: MeshKit, x0: float, x1: float, t: float, o: Dictionary) -> void:
	var v: int = o.get("v", 0)
	var bed := PlatformModule.BED_Y
	var zn := t - NEAR
	var zf := t + FAR
	kit.horiz("trackbed", x0, x1, zn, zf, bed, true, bed)
	# walls of brick, the far one flush with the track-side wall of the platform tunnels
	kit.wall("brick_stock", Vector3(x0, 0, zn), Vector3(x1, 0, zn), bed, BOX_TOP, bed)
	kit.wall("brick_stock", Vector3(x1, 0, zf), Vector3(x0, 0, zf), bed, BOX_TOP, bed)
	# the roof: a concrete deck on steel girders
	kit.horiz("concrete", x0, x1, zn, zf, BOX_TOP, false, bed)
	var gx := ceilf(x0 / 3.0) * 3.0 + 1.5
	while gx < x1:
		kit.box("steel", Vector3(gx, BOX_TOP - 0.2, (zn + zf) * 0.5), Vector3(0.2, 0.4, zf - zn - 0.02), bed, true)
		gx += 3.0
	TunnelDetail.add(kit, 1.0, x0, x1, zn, zf, {"seed": 17 + v * 31, "lamps": [(x0 + x1) * 0.5] if v < 3 else []})
	match v % 3:
		1:
			kit.box("steel", Vector3((x0 + x1) * 0.5 - 2.0, 1.1, zf - 0.07), Vector3(0.12, 2.2, 0.10), 0.0)
			kit.box("light_emissive_red", Vector3((x0 + x1) * 0.5 - 2.0, 1.85, zf - 0.135), Vector3(0.2, 0.2, 0.04), 0.0)
			kit.box("light_emissive_green", Vector3((x0 + x1) * 0.5 - 2.0, 1.5, zf - 0.135), Vector3(0.2, 0.2, 0.04), 0.0)
		2:
			kit.box("light_emissive_blue", Vector3((x0 + x1) * 0.5 + 1.5, 2.0, zn + 0.1), Vector3(0.5, 0.18, 0.06), 0.0)
			kit.box("black", Vector3((x0 + x1) * 0.5 + 1.5, 0.85, zn + 0.03), Vector3(1.6, 1.7, 0.04), 0.0)


# ---------------------------------------------------------------------------------------------------------------------------------------
# the headwall where a tunnel (BORE or BOX) opens at plane x into the open stretch at that side (dir = +1: the open air is toward +x). `open_prof` is what lies outside.
# ---------------------------------------------------------------------------------------------------------------------------------------

static func arch_points(za: float, zb: float) -> PackedVector2Array:
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
	return pts


static func portal(kit: MeshKit, bore: int, open_prof: int, x: float, dir: int, t: float, o: Dictionary = {}) -> void:
	var bed := PlatformModule.BED_Y
	var pl := 9.0
	var pr := 6.5
	var top := 6.5
	if open_prof == CUTTING:
		var brick: bool = int(o.get("seed", 0)) % 3 == 0
		if brick:
			pl = 5.7
			pr = 4.0
			top = 5.0
		else:
			pl = CUT_H * SLOPE + SHOULDER
			pr = pl
			top = G + CUT_H
	var near_flat: bool = o.get("near_flat", false)
	var ns: float = float(o.get("ns", -1.0))
	if near_flat:
		var mid := float(o.get("flat0" if dir > 0 else "flat1", 0.0))
		if ns < 0.0:
			pl = t - mid
		else:
			pr = mid - t          # (the other track of the pair lies on the platform side: this headwall stops half way to it, the other one takes over from there)
	var hint := Vector3(float(dir), 0, 0)
	var zl := t - NEAR
	var zr := t + FAR
	# the land outside: on an embankment or a viaduct it is far below the track, and the headwall is an abutment that stands on it
	var low := bed
	if open_prof == EMBANK or open_prof == VIADUCT:
		low = G - full_height(EMBANK, bool(o.get("tall", false)) or open_prof == VIADUCT)
	# the blocks beside the opening
	_wallq(kit, "brick_stock", Vector3(x, top, t - pl), Vector3(x, low, t - pl), Vector3(x, low, zl), Vector3(x, top, zl), hint)
	_wallq(kit, "brick_stock", Vector3(x, top, zr), Vector3(x, low, zr), Vector3(x, low, t + pr), Vector3(x, top, t + pr), hint)
	# over the opening: above the arch, or above the box
	if bore == BOX:
		_wallq(kit, "brick_stock", Vector3(x, top, zl), Vector3(x, BOX_TOP, zl), Vector3(x, BOX_TOP, zr), Vector3(x, top, zr), hint)
	else:
		var pts := arch_points(zl, zr)
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			_wallq(kit, "brick_stock", Vector3(x, top, a.x), Vector3(x, a.y, a.x), Vector3(x, b.y, b.x), Vector3(x, top, b.x), hint)
	if o.get("stub", false):
		_stub(kit, bore, x, dir, t)
	# a coping on the top, and wing walls splaying out along the ground
	_q(kit, "concrete", Vector3(x, top, t - pl), Vector3(x, top, t + pr), Vector3(x + dir * 0.4, top, t + pr), Vector3(x + dir * 0.4, top, t - pl), Vector3.UP)
	if open_prof != CUTTING:
		for sg: float in [-1.0, 1.0]:
			if sg == ns and near_flat:
				continue
			var zw := t - pl if sg < 0.0 else t + pr
			var xe := x + dir * 7.0
			var ze := zw + sg * 2.5
			for face: int in [0, 1]:
				var h := Vector3(0, 0, -sg if face == 0 else sg)
				_wallq(kit, "brick_stock", Vector3(x, top, zw), Vector3(x, low if low < G else G, zw), Vector3(xe, low if low < G else G, ze), Vector3(xe, (low if low < G else G) + 1.2, ze), h)


## a few metres of the tunnel behind a headwall at plane x (the open air toward dir), closed by a dark plane: for the other track of a pair, whose tunnel the neighbouring cell does not hold
const STUB := 18.0


static func _stub(kit: MeshKit, bore: int, x: float, dir: int, t: float) -> void:
	var bed := PlatformModule.BED_Y
	var xi := x - float(dir) * STUB
	var a := minf(x, xi)
	var b := maxf(x, xi)
	var zl := t - NEAR
	var zr := t + FAR
	if bore == BOX:
		_box(kit, a, b, t, {"v": 3})
	else:
		var pr := arch_points(zl, zr)
		pr.append(Vector2(zr, bed))
		kit.sweep_x("tunnel_lining", pr, a, b, 0.0, false, STUB)
		kit.wall("tunnel_lining", Vector3(a, 0, zl), Vector3(b, 0, zl), bed, PlatformModule.SPRING_Y, 0.0)
		kit.horiz("trackbed", a, b, zl, zr, bed, true, bed)
	var p0 := Vector3(xi, PlatformModule.SPRING_Y + PlatformModule.RISE, zl)
	var p1 := Vector3(xi, PlatformModule.SPRING_Y + PlatformModule.RISE, zr)
	var p2 := Vector3(xi, bed, zr)
	var p3 := Vector3(xi, bed, zl)
	if dir > 0:
		kit.quad("tunnel_dark", p0, p3, p2, p1, 0.0)          # (the tunnel lies toward -x: the plane faces +x)
	else:
		kit.quad("tunnel_dark", p0, p1, p2, p3, 0.0)
