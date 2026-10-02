class_name RenderSettings
extends RefCounted
## The game's render settings in one place, shared by Game._apply_settings and the frame-rate experiment so that the experiment measures what the game does.
## opts: quality (0 Fast .. 3 Ultra), scale (0 = Auto), upscaler ("fsr1" / "fsr2"), aa ("taa" / "fxaa" / "off").
##   Fast      no ambient occlusion, no glow          (GPU cost at a 4K target with the Auto scale on an RTX 3050 Ti Mobile, static hall: ambient occlusion about +2.6 ms,
##   Balanced  + ambient occlusion and glow            TAA +2.4 ms, glow +1.3 ms; FXAA about +0.0 ms)
##   High      + screen-space light bounce and reflections     Ultra  + global illumination and haze

## Auto render scale: the 3D scene is drawn at about 2.4 million pixels (a bit over 1080p) and upscaled, so a 4K screen costs about the same as a 1080p one.
static func auto_scale(size: Vector2i) -> float:
	var px := float(maxi(size.x, 1)) * float(maxi(size.y, 1))
	var sc := clampf(sqrt(2.4e6 / px), 0.5, 1.0)
	return 1.0 if sc > 0.93 else snappedf(sc, 0.01)


static func apply(e: Environment, vp: Viewport, opts: Dictionary, size: Vector2i) -> void:
	var q: int = int(opts.get("quality", 1))
	e.ssao_enabled = q >= 1
	e.glow_enabled = q >= 1
	e.ssil_enabled = q >= 2
	e.ssr_enabled = q >= 2
	e.sdfgi_enabled = q >= 3
	e.volumetric_fog_enabled = q >= 3
	var sc: float = float(opts.get("scale", 0.0))
	if sc <= 0.0:
		sc = float(opts["_auto_now"]) if opts.has("_auto_now") else auto_scale(size)       # Auto: adaptive (AdaptiveScale) once it has moved, else the size-based start value
	# FSR 1: spatial, about 1 ms; FSR 2: temporal, sharper on small text and fences (about 3 ms more at the Auto scale at 4K, much more at higher scales)
	var up_mode := Viewport.SCALING_3D_MODE_FSR2 if String(opts.get("upscaler", "fsr1")) == "fsr2" else Viewport.SCALING_3D_MODE_FSR
	var upscaling := sc < 0.99
	var aa := String(opts.get("aa", "taa"))
	# FSR 2 does its own temporal anti-aliasing (Godot warns when TAA is on with it): TAA goes off before FSR 2 comes on, and on after it has gone
	var want_taa := aa == "taa" and not (up_mode == Viewport.SCALING_3D_MODE_FSR2 and upscaling)
	if not want_taa:
		vp.use_taa = false
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_mode = up_mode if upscaling else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = sc
	if want_taa:
		vp.use_taa = true
