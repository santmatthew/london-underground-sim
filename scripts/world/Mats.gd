class_name Mats
extends RefCounted
## Material library. All station surfaces share shaders/station_surface.gdshader with different texture sets.

static var _cache: Dictionary = {}
static var _shader: Shader
static var _tex_cache: Dictionary = {}

const TEX := "res://assets/textures/"


static func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[path] = t
	return t


static func _surface(albedo_dir: String, ext: String, uv_per_m: float, tint := Color.WHITE, opts := {}) -> ShaderMaterial:
	if _shader == null:
		_shader = load("res://shaders/station_surface.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	var base := TEX + albedo_dir + "/"
	m.set_shader_parameter("tex_albedo", tex(base + "Color." + ext))
	m.set_shader_parameter("tex_normal", tex(base + ("NormalGL." + ext)))
	m.set_shader_parameter("tex_rough", tex(base + "Roughness." + ext))
	var ao := tex(base + "AmbientOcclusion." + ext) if ResourceLoader.exists(base + "AmbientOcclusion." + ext) else tex(base + "AO." + ext)
	if ao:
		m.set_shader_parameter("tex_ao", ao)
	var metal := tex(base + "Metalness." + ext)
	if metal:
		m.set_shader_parameter("tex_metal", metal)
	m.set_shader_parameter("tex_grime", tex(TEX + "gen/grime/Grime.png"))
	m.set_shader_parameter("uv_scale", Vector2(uv_per_m, uv_per_m))
	m.set_shader_parameter("tint", tint)
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	return m


## name -> Material. Names used by builders: tile_white, tile_cream, floor_platform, ceiling, trackbed, concrete, rubber, metal, ...
static func get_mat(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var m: Material
	match name:
		"tile_white":
			m = _surface("gen/metro_white", "png", 1.0 / 1.2, Color(1, 1, 1), {"dirt": 0.5, "ceiling_soot": 0.45, "floor_dirt_height": 0.5})
		"tile_cream":
			m = _surface("gen/metro_cream", "png", 1.0 / 1.2, Color(1.0, 1.0, 1.0), {"dirt": 0.5, "ceiling_soot": 0.5, "floor_dirt_height": 0.5})
		"panel_white":
			m = _surface("gen/panel_white", "png", 1.0 / 2.0, Color(1, 1, 1), {"dirt": 0.35, "ceiling_soot": 0.3})
		"tactile":
			m = _surface("gen/tactile_yellow", "png", 1.0 / 0.6, Color(0.20, 0.20, 0.21), {"dirt": 0.5, "floor_dirt_height": 0.0})
		"floor_platform":
			m = _surface("Terrazzo004", "jpg", 1.0 / 1.0, Color(0.55, 0.55, 0.56), {"dirt": 0.5, "floor_dirt_height": 0.0, "rough_add": 0.05})
		"floor_hall":
			m = _surface("Terrazzo005", "jpg", 1.0 / 1.2, Color(0.72, 0.72, 0.74), {"dirt": 0.45, "floor_dirt_height": 0.0, "rough_add": 0.05})
		"floor_dark":
			m = _surface("Tiles140", "jpg", 1.0 / 1.0, Color(0.8, 0.8, 0.8), {"dirt": 0.5, "floor_dirt_height": 0.0})
		"ceiling":
			m = _surface("PaintedPlaster017", "jpg", 1.0 / 2.0, Color(0.92, 0.92, 0.92), {"dirt": 0.25, "ceiling_soot": 0.35, "normal_scale": 0.5})
		"concrete":
			m = _surface("Concrete030", "jpg", 1.0 / 2.0, Color(0.7, 0.7, 0.7), {"dirt": 0.6})
		"trackbed":
			m = _surface("Concrete036", "jpg", 1.0 / 1.5, Color(0.28, 0.27, 0.25), {"dirt": 0.9, "floor_dirt_height": 0.0})
		"track_sleepers":
			m = _surface("gen/trackbed_sleepers", "png", 1.0 / 1.3, Color(1, 1, 1), {"dirt": 0.5, "floor_dirt_height": 0.0})
		"rubber":
			m = _surface("Rubber004", "jpg", 1.0 / 0.8, Color(0.6, 0.6, 0.6), {"dirt": 0.4, "floor_dirt_height": 0.0})
		"metal":
			m = _surface("Metal032", "jpg", 1.0 / 1.0, Color(0.85, 0.85, 0.88), {"metallic_amount": 1.0, "dirt": 0.3})
		"rail":
			m = _surface("Metal063", "jpg", 1.0 / 1.0, Color(0.55, 0.42, 0.35), {"metallic_amount": 0.8, "dirt": 0.6, "rough_add": 0.25})
		"yellow_paint":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.93, 0.74, 0.05)
			s.roughness = 0.55
			m = s
		"black":
			var s2 := StandardMaterial3D.new()
			s2.albedo_color = Color(0.03, 0.03, 0.035)
			s2.roughness = 0.6
			m = s2
		"glass_roof":
			var gr := StandardMaterial3D.new()
			var hh := fmod(Clock.now / 3600.0, 24.0)
			var day := clampf(sin((hh - 6.0) / 14.0 * PI), 0.05, 1.0)
			gr.albedo_color = Color(0.75, 0.85, 0.95)
			gr.emission_enabled = true
			gr.emission = Color(0.80, 0.90, 1.0)
			gr.emission_energy_multiplier = 0.4 + 3.2 * day
			gr.roughness = 0.2
			m = gr
		"light_emissive":
			var s3 := StandardMaterial3D.new()
			s3.albedo_color = Color(1, 1, 0.95)
			s3.emission_enabled = true
			s3.emission = Color(1.0, 0.97, 0.9)
			s3.emission_energy_multiplier = 4.0
			m = s3
		_:
			var sd := StandardMaterial3D.new()
			sd.albedo_color = Color(1, 0, 1)
			m = sd
	_cache[name] = m
	return m


## Flat coloured material (line colours, signage backgrounds ...)
static func flat(color: Color, roughness := 0.45, metallic := 0.0) -> StandardMaterial3D:
	var key := "flat_%s_%.2f_%.2f" % [color.to_html(), roughness, metallic]
	if _cache.has(key):
		return _cache[key]
	var s := StandardMaterial3D.new()
	s.albedo_color = color
	s.roughness = roughness
	s.metallic = metallic
	_cache[key] = s
	return s


## Tinted tile (coloured dado / glazed colour bands) — same metro-tile texture, tinted albedo
static func dado(color: Color) -> Material:
	var key := "dado_" + color.to_html(false)
	if _cache.has(key):
		return _cache[key]
	var m := _surface("gen/metro_white", "png", 1.0 / 1.2, color, {"dirt": 0.55, "ceiling_soot": 0.2, "floor_dirt_height": 0.6})
	_cache[key] = m
	return m


static func material_table(names: Array) -> Dictionary:
	var d := {}
	for n in names:
		d[n] = get_mat(n)
	return d
