class_name TubeMapTexture
extends RefCounted
## The Tube diagram rendered once into a texture, for the framed wall maps in stations (TubeMap in print mode: no UI, plain paper).
## The SubViewport stays alive in the scene tree so the ViewportTexture keeps working; it redraws once.

const SIZE := Vector2i(2000, 1600)      # the aspect of a Quad Royal frame's picture (1.25)

static var _vp: SubViewport
static var _tex: Texture2D


static func texture() -> Texture2D:
	if _tex != null:
		return _tex
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.transparent_bg = false
	var map := TubeMap.new()
	map.poster_mode = true
	_vp.add_child(map)
	tree.root.add_child.call_deferred(_vp)
	_fit.call_deferred(map)
	_tex = _vp.get_texture()
	return _tex


static func _fit(map: TubeMap) -> void:
	map.set_anchors_preset(Control.PRESET_TOP_LEFT)       # TubeMap fills its parent by default; here it is exactly the viewport
	map.size = Vector2(SIZE)
	if not map._dia_ok:
		return
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in map._dp:
		lo = lo.min(p)
		hi = hi.max(p)
	var ext := hi - lo
	map.zoom = minf(float(SIZE.x) * 0.94 / ext.x, float(SIZE.y) * 0.94 / ext.y)
	map.center = (lo + hi) * 0.5
	map.queue_redraw()
	# once it has been drawn, stop redrawing
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	if map.get_parent() is SubViewport:
		(map.get_parent() as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	# the map must not keep queueing redraws: TubeMap._process re-recorded its whole 2000 x 1600 diagram every frame (about 20 ms of main-thread time in every
	# station with a wall map, found by the frame-rate experiment); the texture is complete, so nothing about it needs to run any more
	if not Station.debug_on("tubemap_redraw"):          # (UG_ON=tubemap_redraw brings the old behaviour back for the frame-rate experiment)
		map.set_process(false)
