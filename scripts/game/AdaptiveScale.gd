class_name AdaptiveScale
extends Node
## Adaptive render scale for the "Auto" setting: keeps the GPU time of the 3D view under `target_ms` (about 60 fps) by moving the internal resolution along STEPS, down after two
## consecutive seconds over the target, up after four seconds well under it (and only if the next step is predicted to fit). The laptop GPU this was measured on throttles
## (power cap / thermal slowdown: clocks between 740 and 1700 MHz in the same run), so a fixed render scale is either wasteful when it is cool or too slow when it is hot.
## The scale is applied through `changed` (Game stores it in opts["_auto_now"] and RenderSettings.apply uses it); a change reallocates the render buffers, so steps are coarse and rare.

signal changed(new_scale: float)

const FLOOR := 0.40            # never render below 40 % of the target size
const FACTOR := 0.88           # each step down is 12 % smaller (about 23 % fewer pixels)
const WINDOW_S := 1.0
const SETTLE_S := 6.0          # ignore the first seconds after start: the station is still loading and the GPU idles

var target_ms := 14.5
var enabled := false
var scale := 1.0
var ceiling := 1.0
var steps: Array = [1.0]
var _rid := RID()
var _samples := PackedFloat32Array()
var _t := 0.0
var _age := 0.0
var _over := 0
var _under := 0


## the ladder from the starting scale (the most the player asked for) down to FLOOR
static func make_steps(top: float) -> Array:
	var out: Array = [top]
	var v := top
	while v * FACTOR > FLOOR + 0.01:
		v *= FACTOR
		out.append(snappedf(v, 0.01))
	if out[out.size() - 1] > FLOOR + 0.01 and top > FLOOR:
		out.append(FLOOR)
	return out


func start(vp: Viewport, initial: float) -> void:
	_rid = vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	ceiling = initial
	steps = make_steps(initial)
	scale = initial
	enabled = true
	_samples.clear()
	_t = 0.0
	_age = 0.0
	_over = 0
	_under = 0
	set_process(true)


func stop() -> void:
	enabled = false
	set_process(false)
	if _rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(_rid, false)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if not enabled:
		return
	_age += delta
	if _age < SETTLE_S:
		return
	var g := RenderingServer.viewport_get_measured_render_time_gpu(_rid)
	if g > 0.0:
		_samples.append(g)
	_t += delta
	if _t < WINDOW_S:
		return
	_t = 0.0
	if _samples.size() < 5:
		_samples.clear()
		return
	var sorted := _samples.duplicate()
	sorted.sort()
	var median := sorted[sorted.size() / 2]
	_samples.clear()
	var r := decide(steps, scale, median, target_ms, _over, _under)
	_over = r["over"]
	_under = r["under"]
	if absf(r["scale"] - scale) > 0.001:
		scale = r["scale"]
		_over = 0
		_under = 0
		changed.emit(scale)


static func _index(steps: Array, cur: float) -> int:
	var best := 0
	for k in steps.size():
		if absf(float(steps[k]) - cur) < absf(float(steps[best]) - cur):
			best = k
	return best


## one control decision from one second's median GPU time: {scale, over, under}. `steps` runs from the highest scale (index 0) downwards.
static func decide(steps: Array, cur: float, median_ms: float, target: float, over: int, under: int) -> Dictionary:
	var i := _index(steps, cur)
	var here: float = steps[i]
	if median_ms > target:
		over += 1
		under = 0
		if over >= 2 and i < steps.size() - 1:
			return {"scale": steps[i + 1], "over": 0, "under": 0}
		return {"scale": here, "over": over, "under": under}
	if median_ms < target * 0.72 and i > 0:
		under += 1
		over = 0
		var up: float = steps[i - 1]
		var predicted: float = median_ms * (up * up) / (here * here)           # GPU time grows with the pixel count
		if under >= 4 and predicted < target * 0.92:
			return {"scale": up, "over": 0, "under": 0}
		return {"scale": here, "over": over, "under": under}
	return {"scale": here, "over": 0, "under": 0}
