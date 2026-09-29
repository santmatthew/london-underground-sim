extends Node
## Simulation clock. `now` is seconds since midnight of the simulated day (can exceed 86400 after midnight).

signal minute_changed(minute: int)

static var weekend := false        # Saturday/Sunday: no commuter peaks, busier midday and evening
var now: float = 8.0 * 3600.0
var time_scale: float = 1.0        # 1 = real time; fast-forward while riding
var running := true
var _last_minute := -1


func _process(delta: float) -> void:
	if not running:
		return
	now += delta * time_scale
	var m := int(now / 60.0)
	if m != _last_minute:
		_last_minute = m
		minute_changed.emit(m)


func set_time(t: float) -> void:
	now = t
	_last_minute = -1


## "08:47" or "08:47:12"
static func fmt(t: float, with_seconds := false) -> String:
	var s := int(t) % 86400
	var h := s / 3600
	var m := (s % 3600) / 60
	if with_seconds:
		return "%02d:%02d:%02d" % [h, m, s % 60]
	return "%02d:%02d" % [h, m]


## Human duration: "12 min 05 s"
static func fmt_dur(sec: float) -> String:
	var s := int(round(sec))
	if s >= 3600:
		return "%d h %02d min %02d s" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d min %02d s" % [s / 60, s % 60]


## 0..1 daylight-independent 'crowd factor' by time of day (weekday). Peaks ~08:15 and ~17:45.
static func crowd_factor(t: float) -> float:
	var h := fmod(t / 3600.0, 24.0)
	if h < 5.0:
		h += 24.0
	var v := 0.10
	if weekend:
		v += 0.20 * exp(-pow((h - 9.5) / 1.2, 2.0))
		v += 0.62 * exp(-pow((h - 13.5) / 3.6, 2.0))     # shopping / leisure hump
		v += 0.40 * exp(-pow((h - 21.5) / 2.2, 2.0))     # nights out
		if h >= 24.0:
			v *= clampf(1.0 - (h - 24.0) / 0.75, 0.0, 1.0)
		return clampf(v, 0.04, 1.0)
	v += 0.90 * exp(-pow((h - 8.25) / 1.0, 2.0))        # AM peak
	v += 0.85 * exp(-pow((h - 17.75) / 1.25, 2.0))      # PM peak
	v += 0.42 * exp(-pow((h - 12.75) / 3.2, 2.0))       # inter-peak
	v += 0.25 * exp(-pow((h - 21.0) / 1.8, 2.0))        # evening
	if h >= 24.0:
		v *= clampf(1.0 - (h - 24.0) / 0.75, 0.0, 1.0)  # after midnight fade-out
	return clampf(v, 0.04, 1.0)
