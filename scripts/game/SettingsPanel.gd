class_name SettingsPanel
extends CenterContainer
## The settings screen: Sound, Accessibility and Controls tabs over the Settings autoload (every change is applied and saved at once). Game opens it from the main menu and the pause
## panel; `closed` fires when the player leaves it (Back button or Esc).

signal closed

const ROW_W := 330.0                  # width of the label column

var font_b: Font
var font_r: Font
var _tabs: TabContainer
var _bind_rows: Dictionary = {}        # action -> {"key": Button, "pad": Button}
var _listening: Dictionary = {}        # {"action", "kind", "button"} while waiting for the next key / pad button


func _init(p_font_b: Font = null, p_font_r: Font = null) -> void:
	font_b = p_font_b
	font_r = p_font_r
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(760, 0)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.05, 0.12, 0.96)
	s.set_corner_radius_all(14)
	for side in ["left", "right"]:
		s.set("content_margin_" + side, 30)
	for side in ["top", "bottom"]:
		s.set("content_margin_" + side, 22)
	pc.add_theme_stylebox_override("panel", s)
	add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	vb.add_child(_label("SETTINGS", 38, Color(1, 0.85, 0.2), true))
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(700, 470)
	_tabs.add_theme_font_override("font", font_b)
	_tabs.add_theme_font_size_override("font_size", 20)
	vb.add_child(_tabs)
	_tabs.add_child(_tab_sound())
	_tabs.add_child(_tab_access())
	_tabs.add_child(_tab_controls())
	var back := Button.new()
	back.text = "Back"
	back.add_theme_font_override("font", font_b)
	back.add_theme_font_size_override("font_size", 22)
	back.custom_minimum_size = Vector2(320, 46)
	back.pressed.connect(close)
	vb.add_child(back)
	visible = false


func open() -> void:
	visible = true
	_refresh_bindings()
	_tabs.get_tab_bar().grab_focus.call_deferred()          # (so a gamepad can move around: left / right changes tab, down enters the page)


func close() -> void:
	_stop_listening()
	visible = false
	closed.emit()


# ---------------------------------------------------------------------------------------------------
# widgets
# ---------------------------------------------------------------------------------------------------
func _label(text: String, size := 18, col := Color.WHITE, bold := false, min_w := 0.0) -> Label:
	var l := Label.new()
	l.custom_minimum_size.x = min_w
	l.text = text
	l.add_theme_font_override("font", font_b if bold else font_r)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _page(title: String) -> Array:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 10)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(g)
	return [sc, g]


func _slider(g: GridContainer, text: String, section: String, key: String, lo: float, hi: float, step: float) -> HSlider:
	g.add_child(_label(text, 18, Color.WHITE, false, ROW_W))
	var h := HBoxContainer.new()
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = float(Settings.get_v(section, key))
	sl.custom_minimum_size = Vector2(220, 26)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var shown := func(v: float) -> String:
		return ("%.1f" % (v * 1000.0)) if hi < 0.1 else ("%.2f" % v)       # (mouse sensitivity is tiny: shown in thousandths)
	var val := _label(shown.call(sl.value), 16, Color(0.75, 0.8, 0.95))
	val.custom_minimum_size = Vector2(56, 0)
	sl.value_changed.connect(func(v):
		val.text = shown.call(v)
		Settings.set_v(section, key, v))
	h.add_child(sl)
	h.add_child(val)
	g.add_child(h)
	return sl


func _check(g: GridContainer, text: String, section: String, key: String, hint := "") -> CheckButton:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = ROW_W
	box.add_child(_label(text, 18, Color.WHITE, false, ROW_W))
	if hint != "":
		box.add_child(_label(hint, 14, Color(0.7, 0.75, 0.88), false, ROW_W))
	g.add_child(box)
	var cb := CheckButton.new()
	cb.button_pressed = bool(Settings.get_v(section, key))
	cb.toggled.connect(func(v): Settings.set_v(section, key, v))
	g.add_child(cb)
	return cb


func _option(g: GridContainer, text: String, section: String, key: String, items: Array, hint := "") -> OptionButton:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = ROW_W
	box.add_child(_label(text, 18, Color.WHITE, false, ROW_W))
	if hint != "":
		box.add_child(_label(hint, 14, Color(0.7, 0.75, 0.88), false, ROW_W))
	g.add_child(box)
	var ob := OptionButton.new()
	var cur = Settings.get_v(section, key)
	for i in items.size():
		ob.add_item(items[i][0])
		ob.set_item_metadata(i, items[i][1])
		if items[i][1] == cur:
			ob.select(i)
	ob.item_selected.connect(func(i): Settings.set_v(section, key, ob.get_item_metadata(i)))
	g.add_child(ob)
	return ob


# ---------------------------------------------------------------------------------------------------
# tabs
# ---------------------------------------------------------------------------------------------------
func _tab_sound() -> Control:
	var pg := _page("Sound")
	var g: GridContainer = pg[1]
	_slider(g, "Master volume", "audio", "master", 0.0, 1.0, 0.05)
	_slider(g, "Effects (doors, gates, trains, footsteps)", "audio", "effects", 0.0, 1.0, 0.05)
	_slider(g, "Ambience (station, crowds, wind)", "audio", "ambience", 0.0, 1.0, 0.05)
	_slider(g, "Announcements (PA and driver)", "audio", "announcements", 0.0, 1.0, 0.05)
	_check(g, "Announcements", "audio", "announce_on", "The PA and the driver speak: train arrivals, stations, doors.")
	_check(g, "Extra PA messages", "audio", "pa_chatter", "Mind the gap, next train due in N minutes, tunnel wind before a train, greetings.")
	_check(g, "Subtitles", "audio", "subtitles", "Announcements shown as text at the top of the screen.")
	_slider(g, "Subtitle size", "audio", "subtitle_size", 0.8, 1.8, 0.1)
	g.add_child(_label("Try it", 18, Color.WHITE, false, ROW_W))
	var b := Button.new()
	b.text = "Play an announcement"
	b.add_theme_font_override("font", font_b)
	b.pressed.connect(func():
		Sfx.say(["next_train_due_in_03_min"], true))
	g.add_child(b)
	return pg[0]


func _tab_access() -> Control:
	var pg := _page("Accessibility")
	var g: GridContainer = pg[1]
	_check(g, "Reduce camera sway", "access", "reduce_sway", "No sway of the view in trains.")
	_slider(g, "HUD text size", "access", "text_scale", 0.8, 1.6, 0.1)
	_option(g, "Colour vision", "access", "colour_vision", [["Standard", "standard"], ["Deuteranopia (red-green)", "deuteranopia"], ["Protanopia (red-green)", "protanopia"], ["Tritanopia (blue-yellow)", "tritanopia"]],
		"Line colours on signs, trains, the Tube map and the HUD are changed so that every line can be told apart. Applies from the next journey; the map at once.")
	_check(g, "Step-free journeys (optional)", "access", "step_free", "Off by default: lifts are in the stations that have them whatever you choose. On: journeys only between stations with step-free platforms (about a quarter of them), the escalators and stairs are closed to you and every bank has a lift.")
	return pg[0]


func _tab_controls() -> Control:
	var pg := _page("Controls")
	var g: GridContainer = pg[1]
	_slider(g, "Mouse sensitivity", "controls", "sens", 0.0008, 0.006, 0.0001)
	_check(g, "Invert vertical look", "controls", "invert_y")
	_slider(g, "Stick look speed", "controls", "stick_sens", 1.0, 5.0, 0.1)
	_slider(g, "Stick dead zone", "controls", "stick_deadzone", 0.05, 0.5, 0.05)
	g.add_child(_label("Keys and buttons", 20, Color(1, 0.85, 0.2), true, ROW_W))
	g.add_child(_label("Click a key or button, then press the new one (Esc cancels).", 14, Color(0.7, 0.75, 0.88), false, 300.0))
	for a in InputBindings.ACTIONS:
		g.add_child(_label(String(a["label"]), 18, Color.WHITE, false, ROW_W))
		var hb := HBoxContainer.new()
		var kb := Button.new()
		kb.custom_minimum_size = Vector2(150, 0)
		kb.pressed.connect(_listen.bind(String(a["id"]), "key", kb))
		var pb := Button.new()
		pb.custom_minimum_size = Vector2(150, 0)
		pb.pressed.connect(_listen.bind(String(a["id"]), "pad", pb))
		hb.add_child(kb)
		hb.add_child(pb)
		g.add_child(hb)
		_bind_rows[String(a["id"])] = {"key": kb, "pad": pb}
	g.add_child(_label(""))
	var rb := Button.new()
	rb.text = "Restore default controls"
	rb.add_theme_font_override("font", font_b)
	rb.pressed.connect(func():
		InputBindings.reset()
		_refresh_bindings())
	g.add_child(rb)
	_refresh_bindings()
	return pg[0]


# ---------------------------------------------------------------------------------------------------
# rebinding
# ---------------------------------------------------------------------------------------------------
func _refresh_bindings() -> void:
	for id in _bind_rows:
		(_bind_rows[id]["key"] as Button).text = InputBindings.key_text(id)
		(_bind_rows[id]["pad"] as Button).text = InputBindings.pad_text(id)


func _listen(action: String, kind: String, btn: Button) -> void:
	_stop_listening()
	_listening = {"action": action, "kind": kind, "button": btn}
	btn.text = "press a key ..." if kind == "key" else "press a button ..."


func _stop_listening() -> void:
	if not _listening.is_empty():
		_listening = {}
		_refresh_bindings()


func _input(ev: InputEvent) -> void:
	if not visible:
		return
	if not _listening.is_empty():
		var kind: String = _listening["kind"]
		if ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo:
			get_viewport().set_input_as_handled()
			if (ev as InputEventKey).keycode == KEY_ESCAPE:
				_stop_listening()
			elif kind == "key":
				InputBindings.rebind_key(String(_listening["action"]), (ev as InputEventKey).physical_keycode if (ev as InputEventKey).physical_keycode != KEY_NONE else (ev as InputEventKey).keycode)
				_listening = {}
				_refresh_bindings()
		elif ev is InputEventJoypadButton and (ev as InputEventJoypadButton).pressed and kind == "pad":
			get_viewport().set_input_as_handled()
			InputBindings.rebind_pad(String(_listening["action"]), (ev as InputEventJoypadButton).button_index)
			_listening = {}
			_refresh_bindings()
		return
	if ev.is_action_pressed("pause", false, true) or ev.is_action_pressed("ui_cancel", false, true):
		get_viewport().set_input_as_handled()
		close()
