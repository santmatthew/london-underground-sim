extends Node
## Settings (audio / access / controls): defaults, changes emit a signal, a wrong type is refused, reset restores the defaults; the audio buses follow the sliders.
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func run():
	Settings.reset_section("audio")
	check(is_equal_approx(float(Settings.get_v("audio", "master")), 0.8), "default master volume 0.8")
	check(bool(Settings.get_v("audio", "announce_on")) and bool(Settings.get_v("audio", "subtitles")), "announcements and subtitles on by default")
	check(String(Settings.get_v("access", "colour_vision")) == "standard" and not bool(Settings.get_v("access", "step_free")), "accessibility defaults: standard colours, no step-free")
	var got := []
	Settings.changed.connect(func(sec, key): got.append("%s/%s" % [sec, key]))
	Settings.set_v("audio", "master", 0.5, false)
	check(got == ["audio/master"], "a change emits `changed`")
	check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.5)), "the master bus follows the slider (%.1f dB)" % AudioServer.get_bus_volume_db(0))
	Settings.set_v("audio", "effects", 0.25, false)
	var i := AudioServer.get_bus_index("SFX")
	check(i >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(i), linear_to_db(0.25)), "the effects bus follows its slider")
	got.clear()
	Settings.set_v("audio", "master", 0.5, false)
	check(got.is_empty(), "setting the same value again changes nothing")
	Settings.set_v("audio", "nonsense", 1, false)
	check(got.is_empty(), "an unknown setting is refused")
	Settings.set_v("access", "colour_vision", "tritanopia", false)
	check(String(Settings.get_v("access", "colour_vision")) == "tritanopia", "colour vision can be changed")
	Settings.reset_section("access")
	Settings.reset_section("audio")
	check(String(Settings.get_v("access", "colour_vision")) == "standard" and is_equal_approx(float(Settings.get_v("audio", "master")), 0.8), "reset restores the defaults")
	print("OK" if ok else "FAILED")
