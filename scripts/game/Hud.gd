class_name Hud
extends CanvasLayer
## Heads-up display: clock, destination, announcements, toasts, hints, fade.

var root: Control
var clock_label: Label
var elapsed_label: Label
var dest_label: Label
var where_label: Label
var sub_label: Label
var toast_label: Label
var prompt_label: Label
var hint_panel: PanelContainer
var hint_label: Label
var stamina: ProgressBar
var fade: ColorRect
var help_label: Label
var perf_label: Label
var perf_on := false
var _perf_t := 0.0
var extra_perf := ""
var _sub_t := 0.0
var _toast_t := 0.0
var font_b: Font
var font_r: Font


func _ready() -> void:
	layer = 10
	font_b = load("res://assets/fonts/Barlow-Bold.ttf")
	font_r = load("res://assets/fonts/Barlow-SemiBold.ttf")
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# top-left panel
	var pc := PanelContainer.new()
	pc.position = Vector2(18, 16)
	pc.add_theme_stylebox_override("panel", _box(Color(0.03, 0.05, 0.12, 0.72)))
	root.add_child(pc)
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	clock_label = _label(vb, 34, font_b, Color(1, 0.85, 0.2))
	elapsed_label = _label(vb, 16, font_r, Color(0.8, 0.85, 1.0))
	dest_label = _label(vb, 20, font_b, Color.WHITE)
	where_label = _label(vb, 15, font_r, Color(0.7, 0.75, 0.85))
	# announcement subtitle
	sub_label = Label.new()
	sub_label.add_theme_font_override("font", font_r)
	sub_label.add_theme_font_size_override("font_size", 22)
	sub_label.add_theme_color_override("font_color", Color.WHITE)
	sub_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	sub_label.add_theme_constant_override("outline_size", 6)
	sub_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub_label.position = Vector2(-500, 70)
	sub_label.size = Vector2(1000, 60)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub_label)
	# toast (bottom centre)
	toast_label = Label.new()
	toast_label.add_theme_font_override("font", font_b)
	toast_label.add_theme_font_size_override("font_size", 24)
	toast_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	toast_label.add_theme_constant_override("outline_size", 6)
	toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.position = Vector2(-500, -150)
	toast_label.size = Vector2(1000, 50)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(toast_label)
	# interaction prompt (bottom centre, just above the toast): "E  Sit down"
	prompt_label = Label.new()
	prompt_label.add_theme_font_override("font", font_b)
	prompt_label.add_theme_font_size_override("font_size", 22)
	prompt_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	prompt_label.add_theme_constant_override("outline_size", 6)
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position = Vector2(-300, -215)
	prompt_label.size = Vector2(600, 40)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt_label)
	# hint panel (right)
	hint_panel = PanelContainer.new()
	hint_panel.add_theme_stylebox_override("panel", _box(Color(0.03, 0.05, 0.12, 0.85)))
	hint_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint_panel.position = Vector2(-470, 16)
	hint_panel.custom_minimum_size = Vector2(450, 0)
	hint_panel.visible = false
	root.add_child(hint_panel)
	hint_label = Label.new()
	hint_label.add_theme_font_override("font", font_r)
	hint_label.add_theme_font_size_override("font_size", 16)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_panel.add_child(hint_label)
	# stamina
	stamina = ProgressBar.new()
	stamina.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stamina.position = Vector2(20, -40)
	stamina.size = Vector2(160, 8)
	stamina.show_percentage = false
	stamina.max_value = 1.0
	root.add_child(stamina)
	help_label = Label.new()
	refresh_help()
	help_label.add_theme_font_size_override("font_size", 13)
	help_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_label.position = Vector2(20, -28)
	root.add_child(help_label)
	perf_label = Label.new()
	perf_label.add_theme_font_size_override("font_size", 14)
	perf_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	perf_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	perf_label.add_theme_constant_override("outline_size", 4)
	perf_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	perf_label.position = Vector2(-420, -110)
	perf_label.size = Vector2(400, 100)
	perf_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	perf_label.visible = false
	root.add_child(perf_label)
	# fade
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	# crosshair
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.5)
	dot.size = Vector2(4, 4)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position = Vector2(-2, -2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)
	apply_text_scale()
	Settings.changed.connect(func(sec, key):
		if (sec == "access" and key == "text_scale") or (sec == "audio" and key == "subtitle_size"):
			apply_text_scale())


## HUD text size (Settings access/text_scale) and the subtitle size (audio/subtitle_size): every label keeps its design size in meta and is scaled from it
func apply_text_scale() -> void:
	var k := float(Settings.get_v("access", "text_scale"))
	for l in root.find_children("*", "Label", true, false):
		var lab := l as Label
		if not lab.has_meta("base_size"):
			lab.set_meta("base_size", lab.get_theme_font_size("font_size"))
		var sz := float(lab.get_meta("base_size")) * k
		if lab == sub_label:
			sz *= float(Settings.get_v("audio", "subtitle_size"))
		lab.add_theme_font_size_override("font_size", int(round(sz)))


func _box(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(8)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 10
	return s


func _label(parent: Node, size: int, font: Font, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func set_visible_hud(v: bool) -> void:
	root.visible = v


func say(text: String, seconds := 6.0) -> void:
	sub_label.text = text
	sub_label.modulate.a = 1.0
	_sub_t = seconds


func set_prompt(text: String) -> void:
	if prompt_label.text != text:
		prompt_label.text = text


func toast(text: String, seconds := 3.5) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	_toast_t = seconds


func toggle_perf() -> void:
	perf_on = not perf_on
	perf_label.visible = perf_on


func _process(delta: float) -> void:
	if perf_on:
		_perf_t -= delta
		if _perf_t <= 0.0:
			_perf_t = 0.4
			var info := "%d fps  (%.1f ms)  on %s\ndraw calls %d · %.2fM tris · %d objects\nvideo mem %d MB" % [
				Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0), RenderingServer.get_video_adapter_name(),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0]
			perf_label.text = info + extra_perf
	if _sub_t > 0.0:
		_sub_t -= delta
		if _sub_t < 1.0:
			sub_label.modulate.a = maxf(_sub_t, 0.0)
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t < 0.8:
			toast_label.modulate.a = maxf(_toast_t / 0.8, 0.0)


func fade_to(a: float, secs := 0.5) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", a, secs)


## the controls line at the bottom: the keys or the buttons, whichever the player is using (and has set)
func refresh_help() -> void:
	if InputBindings.last_was_pad:
		help_label.text = "Left stick move · %s hurry · %s map · %s route hint · Right stick look · %s use · %s menu" % [InputBindings.pad_text("hurry"), InputBindings.pad_text("map"), InputBindings.pad_text("hint"), InputBindings.pad_text("interact"), InputBindings.pad_text("pause")]
	else:
		help_label.text = "%s%s%s%s move · %s hurry · %s map · %s route hint · %s skip time (when standing still) · %s menu" % [InputBindings.key_text("move_forward"), InputBindings.key_text("move_left"), InputBindings.key_text("move_back"), InputBindings.key_text("move_right"), InputBindings.key_text("hurry"), InputBindings.key_text("map"), InputBindings.key_text("hint"), InputBindings.key_text("skip_time"), InputBindings.key_text("pause")]
