class_name PlatformOpen
extends RefCounted
## Open-air (surface) platforms: no box roof but a canopy over the island, a low brick retaining wall with a palisade fence on the far side of each track, ballast, and
## the sky, trees and house backs beyond (a sky dome and two backdrop strips), lit by daylight lights that follow the simulated clock.
## Styles come from StationCharacter (data/station_character.json "open_styles"); reference photos are private (build/refs_dress/surface).

const WALL_TOP := 1.5                 # y of the top of the retaining wall across each track
const FENCE_H := 1.2
const CANOPY_HALF := 5.6              # canopy half-width (m): the island platform (4.9) plus a 0.7 m overhang
const CANOPY_T := 0.32                # slab thickness
const SKY_R := 300.0

static var _sky_shader: Shader
static var _noise: NoiseTexture2D
static var _backdrop_mats: Dictionary = {}


## 0 at night .. 1 in full day, from the simulated clock
static func daylight() -> float:
	var hh := fmod(Clock.now / 3600.0, 24.0)
	return clampf(sin((hh - 6.0) / 14.0 * PI) * 1.3, 0.0, 1.0)


## sun height -1..1 (negative at night)
static func sun() -> float:
	var hh := fmod(Clock.now / 3600.0, 24.0)
	var a := (hh - 6.0) / 14.0 * PI
	return sin(a) if (hh >= 6.0 and hh <= 20.0) else -0.5


# ---------------------------------------------------------------------------------------------------------------------------------------
# geometry written into the module's MeshKit
# ---------------------------------------------------------------------------------------------------------------------------------------

## the canopy over the island: slab (flat concrete), valanced (white boards + a shallow gable on top), flared (mushroom capitals, Loughton), timber (Metropolitan)
static func canopy(pm: PlatformModule, st: Dictionary, x0: float, x1: float, openings: Array) -> void:
	var kit := pm.kit
	var h := PlatformModule.BOX_H
	var zc := CANOPY_HALF
	var kind := String(st.get("canopy", "slab"))
	var soffit := String(st.get("soffit", "ceiling"))
	var fascia := "flat:" + (st.get("fascia", Color(0.85, 0.85, 0.82)) as Color).to_html(false)
	var top := "concrete"
	kit.horiz(soffit, x0, x1, -zc, zc, h, false, 0.0)
	# ribs under the soffit every 3.6 m (they also carry the strip lights)
	var bx := x0 + 1.8
	while bx < x1:
		kit.box(soffit if kind == "timber" else "ceiling", Vector3(bx, h - 0.09, 0.0), Vector3(0.18, 0.18, zc * 2.0), 0.0)
		bx += 3.6
	match kind:
		"valanced", "timber":
			# a shallow gable on top and a scalloped valance hanging from each long edge
			kit.horiz(top, x0, x1, -zc, zc, h + 0.05, true, 0.0)
			for s in [1.0, -1.0]:
				if not Station.debug_off("valance"):
					_valance(kit, s * zc, x0, x1, h, s)
				kit.box(fascia, Vector3((x0 + x1) * 0.5, h + 0.02, s * zc), Vector3(x1 - x0, 0.1, 0.06), 0.0)
		_:
			# a plain slab with a deep fascia all round
			kit.horiz(top, x0, x1, -zc, zc, h + CANOPY_T, true, 0.0)
			for s in [1.0, -1.0]:
				kit.box(fascia, Vector3((x0 + x1) * 0.5, h + CANOPY_T * 0.5, s * zc), Vector3(x1 - x0, CANOPY_T, 0.06), 0.0)
			for ex in [x0, x1]:
				kit.box(fascia, Vector3(ex, h + CANOPY_T * 0.5, 0.0), Vector3(0.06, CANOPY_T, zc * 2.0), 0.0)
	_columns(pm, st, x0, x1, openings)
	_strip_lights(pm, x0, x1, h)


static func _valance(kit: MeshKit, z: float, x0: float, x1: float, h: float, s: float) -> void:
	var key := "char:open/valance.png|2.000|0.310|1"
	var vh := 0.31
	var zf := z + s * 0.035
	if s > 0.0:
		kit.wall(key, Vector3(x0, 0, zf), Vector3(x1, 0, zf), h - vh + 0.05, h + 0.05, 0.0)
		kit.wall(key, Vector3(x1, 0, zf - 0.004), Vector3(x0, 0, zf - 0.004), h - vh + 0.05, h + 0.05, 0.0)
	else:
		kit.wall(key, Vector3(x1, 0, zf), Vector3(x0, 0, zf), h - vh + 0.05, h + 0.05, 0.0)
		kit.wall(key, Vector3(x0, 0, zf + 0.004), Vector3(x1, 0, zf + 0.004), h - vh + 0.05, h + 0.05, 0.0)


## the columns stand exactly where the box hall's steel columns did (same collision boxes, every 7.2 m, clear of the cross-passages)
static func _columns(pm: PlatformModule, st: Dictionary, x0: float, x1: float, openings: Array) -> void:
	var kit := pm.kit
	var h := PlatformModule.BOX_H
	var col_z := PlatformModule.GAP * 0.5 + 0.85
	var shaft := "flat:" + (st.get("col_main", Color(0.88, 0.88, 0.85)) as Color).to_html(false)
	var band := "flat:" + (st.get("col_band", Color(0.10, 0.20, 0.50)) as Color).to_html(false)
	var kind := String(st.get("col", "square"))
	var cx := x0 + 5.0
	pm.column_xs = []
	while cx < x1 - 3.0:
		var at_opening := false
		for ox in openings:
			if absf(cx - ox) < 2.6:
				at_opening = true
		if not at_opening:
			pm.column_xs.append(cx)
			for zz in [-col_z, col_z]:
				match kind:
					"round":
						# octagonal shaft with a flared capital that spreads into the slab
						kit.box(shaft, Vector3(cx, h * 0.5, zz), Vector3(0.40, h, 0.40), 0.0)
						kit.box_xf(shaft, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(cx, h * 0.5, zz)), Vector3(0.40, h, 0.40), 0.0)
						for k in 4:
							var f := 1.0 + k * 0.9
							kit.box(shaft, Vector3(cx, h - 0.14 - k * 0.1, zz), Vector3(0.4 * f, 0.1, 0.4 * f), 0.0)
						kit.box(band, Vector3(cx, 0.5, zz), Vector3(0.44, 0.9, 0.44), 0.0)
					"iron":
						# slim cast-iron post on a plinth, with a collar and a bracket cap
						kit.box(shaft, Vector3(cx, h * 0.5, zz), Vector3(0.24, h, 0.24), 0.0)
						kit.box(band, Vector3(cx, 0.45, zz), Vector3(0.34, 0.9, 0.34), 0.0)
						kit.box(shaft, Vector3(cx, 1.0, zz), Vector3(0.30, 0.08, 0.30), 0.0)
						kit.box(shaft, Vector3(cx, h - 0.2, zz), Vector3(0.40, 0.14, 0.40), 0.0)
					_:
						# a square concrete column, painted: a dark band at the foot, a thin one at head height
						kit.box(shaft, Vector3(cx, h * 0.5, zz), Vector3(0.42, h, 0.42), 0.0)
						kit.box(band, Vector3(cx, 0.5, zz), Vector3(0.44, 1.0, 0.44), 0.0)
						kit.box(band, Vector3(cx, 2.25, zz), Vector3(0.435, 0.16, 0.435), 0.0)
		cx += 7.2


static func _strip_lights(pm: PlatformModule, x0: float, x1: float, h: float) -> void:
	var kit := pm.kit
	var lx := x0 + 3.0
	while lx < x1:
		for zz in [-3.2, 3.2, 0.0]:
			kit.box("light_emissive", Vector3(lx, h - 0.2, zz), Vector3(1.3, 0.06, 0.3), 0.0)
		lx += 3.2


## the far side of each track: brick retaining wall from the trackbed to WALL_TOP with a coping stone and a palisade fence above it
static func track_wall(pm: PlatformModule, st: Dictionary, s: float, x0: float, x1: float, zfar: float, wall_mat: String) -> void:
	if Station.debug_off("openwall"):
		return
	var kit := pm.kit
	var a := Vector3(x0 - 0.5, 0, s * zfar)
	var b := Vector3(x1 + 0.5, 0, s * zfar)
	if s > 0.0:
		kit.wall(wall_mat, b, a, PlatformModule.BED_Y, WALL_TOP, 0.0)
	else:
		kit.wall(wall_mat, a, b, PlatformModule.BED_Y, WALL_TOP, 0.0)
	# coping stone, a little proud, and its top
	kit.box("white_paint", Vector3((x0 + x1) * 0.5, WALL_TOP + 0.05, s * (zfar + 0.02)), Vector3(x1 - x0 + 1.0, 0.1, 0.36), 0.0)
	# the fence (a quad each way so it reads from both sides)
	var key := "char:open/fence.png|1.000|1.200|1"
	var zf := s * (zfar + 0.02)
	var y0 := WALL_TOP + 0.1
	var y1 := y0 + FENCE_H
	if s > 0.0:
		kit.wall(key, Vector3(x1 + 0.5, 0, zf), Vector3(x0 - 0.5, 0, zf), y0, y1, 0.0)
		kit.wall(key, Vector3(x0 - 0.5, 0, zf + 0.01), Vector3(x1 + 0.5, 0, zf + 0.01), y0, y1, 0.0)
	else:
		kit.wall(key, Vector3(x0 - 0.5, 0, zf), Vector3(x1 + 0.5, 0, zf), y0, y1, 0.0)
		kit.wall(key, Vector3(x1 + 0.5, 0, zf - 0.01), Vector3(x0 - 0.5, 0, zf - 0.01), y0, y1, 0.0)


# ---------------------------------------------------------------------------------------------------------------------------------------
# the sky, the backdrop and the daylight (child nodes of the module)
# ---------------------------------------------------------------------------------------------------------------------------------------

static func scenery(pm: PlatformModule, st: Dictionary, x0: float, x1: float, zfar: float) -> void:
	if Station.debug_off("scenery"):
		return
	var holder := Node3D.new()
	holder.name = "Outdoors"
	pm.add_child(holder)
	var day := daylight()
	var sn := sun()
	# --- the sky dome
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = SKY_R
	sm.height = SKY_R * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	dome.mesh = sm
	dome.material_override = _sky_material(day, sn)
	dome.position = Vector3((x0 + x1) * 0.5, 0.0, 0.0)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(dome)
	# --- backdrop strips: a belt of trees close behind the fence and the backs of a terrace beyond it, on both sides
	var tint := lerpf(0.10, 1.0, day)
	var warm := Color(tint, tint * lerpf(0.9, 1.0, day), tint * lerpf(1.0, 0.96, day))
	var length := (x1 - x0) + 2.0        # no further: the end walls hide the rest, and a longer strip would cut through the rooms beyond them
	var cx := (x0 + x1) * 0.5
	var nb: Array = pm.spec.get("nb", [])
	if OS.has_environment("UG_CHAR_DEBUG"):
		print("OPEN ", pm.name, " pos ", pm.position, " nb ", nb, " zfar ", zfar)
	for s in [1.0, -1.0]:
		if s in nb:
			continue         # another platform lies that way: the view across is its canopy, not a backdrop
		_backdrop(holder, "trees", Vector3(cx, PlatformModule.BED_Y + 0.0, s * (zfar + 11.0)), s, length, 12.0, 40.0, warm)
		_backdrop(holder, "houses", Vector3(cx, PlatformModule.BED_Y + 0.0, s * (zfar + 30.0)), s, length, 14.0, 56.0, warm.darkened(0.12))
	# --- daylight: soft omni lights high above the island (none at night; the canopy lights take over)
	if day > 0.04:
		var lx := x0 + 6.0
		while lx < x1:
			var o := OmniLight3D.new()
			o.position = Vector3(lx, 9.0, 0.0)
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


static func _backdrop(holder: Node3D, tex: String, at: Vector3, s: float, length: float, height: float, tile_w: float, tint: Color) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(length, height)
	mi.mesh = q
	mi.position = at + Vector3(0, height * 0.5, 0)
	mi.rotation.y = atan2(0.0, -s)           # the quad's front (+z) faces the island
	var key := "%s|%.2f|%.1f" % [tex, tint.r, length]
	var m: StandardMaterial3D = _backdrop_mats.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		var t: Texture2D = load("res://assets/textures/char/open/%s.png" % tex) if ResourceLoader.exists("res://assets/textures/char/open/%s.png" % tex) else null
		m.albedo_texture = t
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.albedo_color = tint
		m.uv1_scale = Vector3(length / tile_w, 1.0, 1.0)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_backdrop_mats[key] = m
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)


static func _sky_material(day: float, sn: float) -> ShaderMaterial:
	if _sky_shader == null:
		_sky_shader = load("res://shaders/sky_dome.gdshader")
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.02
		fn.fractal_octaves = 4
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.noise = fn
	var m := ShaderMaterial.new()
	m.shader = _sky_shader
	# colour sets: night, dusk/dawn, day; dusk weight peaks when the sun is low
	var night_top := Color(0.012, 0.018, 0.05)
	var night_hor := Color(0.06, 0.08, 0.14)
	var day_top := Color(0.28, 0.50, 0.84)
	var day_hor := Color(0.80, 0.88, 0.95)
	var dusk_top := Color(0.20, 0.26, 0.52)
	var dusk_hor := Color(0.96, 0.62, 0.42)
	var t := clampf(sn * 1.6, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(sn) * 3.5, 0.0, 1.0) * (1.0 if sn > -0.3 else 0.0)
	var top := night_top.lerp(day_top, t).lerp(dusk_top, dusk * 0.7)
	var hor := night_hor.lerp(day_hor, t).lerp(dusk_hor, dusk * 0.8)
	m.set_shader_parameter("top_color", top)
	m.set_shader_parameter("horizon_color", hor)
	m.set_shader_parameter("ground_color", hor.darkened(0.45))
	m.set_shader_parameter("cloud_color", Color(0.96, 0.96, 0.97).lerp(Color(0.12, 0.13, 0.18), 1.0 - t).lerp(Color(1.0, 0.82, 0.7), dusk * 0.5))
	m.set_shader_parameter("cloud_amount", 0.55)
	m.set_shader_parameter("star_amount", clampf(0.55 - sn * 3.0, 0.0, 1.0))
	m.set_shader_parameter("noise_tex", _noise)
	return m
