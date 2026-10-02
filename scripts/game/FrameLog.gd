class_name FrameLog
extends Node
## Per-frame performance log: wall-clock frame time, GPU and CPU render time of the main viewport, script/physics time, draw calls, primitives, objects, video and static memory.
## Written as CSV (one row per frame) when stopped; `summary()` gives the headline numbers. Used by the frame-rate experiment (tests/fps_experiment.tscn, tools/fps_experiment.sh),
## by the game's `--fps-log=<file> [--fps-secs=300]` option and by F4 in game (writes user://fps_<time>.csv).

const COLS := ["t_s", "frame_ms", "gpu_ms", "render_cpu_ms", "process_ms", "physics_ms", "draws", "prims", "objects", "vram_mb", "mem_mb"]

var path := ""
var secs := 0.0                 # stop by itself after this many seconds (0 = until stop())
var running := false
var on_done: Callable = Callable()
var _t0_us := 0
var _last_us := 0
var _rows := PackedFloat32Array()
var _vp: RID


## `vp` = the viewport whose GPU / CPU render time is measured (default: this node's own); the frame time itself is always the wall clock
func start(p_path: String, p_secs := 0.0, vp := RID()) -> void:
	path = p_path
	secs = p_secs
	_rows = PackedFloat32Array()
	_vp = vp if vp.is_valid() else get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	_t0_us = Time.get_ticks_usec()
	_last_us = _t0_us
	running = true
	set_process(true)


func _ready() -> void:
	process_priority = 1000          # after everything else, so the frame's script time is complete
	set_process(running)


func _process(_delta: float) -> void:
	if not running:
		return
	var now := Time.get_ticks_usec()
	var t := float(now - _t0_us) / 1e6
	_rows.append_array(PackedFloat32Array([
		t,
		float(now - _last_us) / 1000.0,
		RenderingServer.viewport_get_measured_render_time_gpu(_vp),
		RenderingServer.viewport_get_measured_render_time_cpu(_vp),
		float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
		float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
		float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
		float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)),
		float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0,
		float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0,
	]))
	_last_us = now
	if secs > 0.0 and t >= secs:
		stop()


func frames() -> int:
	return _rows.size() / COLS.size()


## stop, write the CSV and return the summary
func stop() -> Dictionary:
	if not running:
		return {}
	running = false
	set_process(false)
	RenderingServer.viewport_set_measure_render_time(_vp, false)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_line(",".join(COLS))
		var n := frames()
		for i in n:
			var parts := PackedStringArray()
			for c in COLS.size():
				parts.append("%.3f" % _rows[i * COLS.size() + c])
			f.store_line(",".join(parts))
		f.close()
	var s := summary()
	print("FRAMELOG ", path, " ", s)
	if on_done.is_valid():
		on_done.call(s)
	return s


## headline numbers over the frames recorded so far (the first `skip_s` seconds are warm-up and ignored)
func summary(skip_s := 3.0) -> Dictionary:
	var ft := PackedFloat32Array()
	var gpu := PackedFloat32Array()
	var n := frames()
	for i in n:
		if _rows[i * COLS.size()] < skip_s:
			continue
		ft.append(_rows[i * COLS.size() + 1])
		gpu.append(_rows[i * COLS.size() + 2])
	if ft.is_empty():
		return {"frames": 0}
	var sorted := ft.duplicate()
	sorted.sort()
	var sum := 0.0
	for v in ft:
		sum += v
	var mean := sum / ft.size()
	var gs := gpu.duplicate()
	gs.sort()
	var slow33 := 0
	var slow50 := 0
	for v in ft:
		if v > 33.4:
			slow33 += 1
		if v > 50.0:
			slow50 += 1
	return {
		"frames": ft.size(), "fps_mean": snappedf(1000.0 / mean, 0.1), "frame_ms_p50": snappedf(sorted[sorted.size() / 2], 0.01),
		"frame_ms_p99": snappedf(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))], 0.01), "frame_ms_max": snappedf(sorted[sorted.size() - 1], 0.01),
		"fps_1pct_low": snappedf(1000.0 / maxf(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))], 0.001), 0.1),
		"gpu_ms_p50": snappedf(gs[gs.size() / 2], 0.01), "over_33ms": slow33, "over_50ms": slow50,
	}
