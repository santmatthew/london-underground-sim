class_name Env
extends RefCounted
## Standard underground environment (no sky, dark ambient, cinematic-ish tonemapping).

static func make(quality := 2) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.01, 0.012)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.62)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_strength = 0.9
	e.glow_bloom = 0.04
	e.ssao_enabled = quality >= 1
	e.ssao_radius = 1.2
	e.ssao_intensity = 2.0
	e.ssao_power = 1.6
	e.ssao_detail = 0.5
	e.ssil_enabled = quality >= 2
	e.ssil_radius = 4.0
	e.ssil_intensity = 1.0
	e.ssr_enabled = quality >= 2
	e.ssr_max_steps = 48
	e.ssr_fade_in = 0.15
	e.ssr_fade_out = 2.0
	e.ssr_depth_tolerance = 0.3
	e.sdfgi_enabled = quality >= 3
	if quality >= 3:
		e.sdfgi_cascades = 3
		e.sdfgi_min_cell_size = 0.5
		e.sdfgi_use_occlusion = true
		e.sdfgi_bounce_feedback = 0.5
		e.sdfgi_energy = 1.0
		e.volumetric_fog_enabled = true
		e.volumetric_fog_density = 0.012
		e.volumetric_fog_albedo = Color(0.8, 0.82, 0.85)
		e.volumetric_fog_length = 40.0
		e.volumetric_fog_detail_spread = 2.0
	e.fog_enabled = true
	e.fog_sky_affect = 0.0
	e.fog_light_color = Color(0.5, 0.52, 0.56)
	e.fog_density = 0.0025
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.95
	e.adjustment_contrast = 1.05
	we.environment = e
	return we
