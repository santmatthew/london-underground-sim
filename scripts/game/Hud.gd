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
var hint_panel: PanelContainer
var hint_label: Label
var stamina: ProgressBar
var fade: ColorRect
var help_label: Label
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
	help_label.text = "WASD move · Shift hurry · M map · H route hint · Tab skip time (when standing still) · Esc menu"
	help_label.add_theme_font_size_override("font_size", 13)
	help_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_label.position = Vector2(20, -28)
	root.add_child(help_label)
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


func toast(text: String, seconds := 3.5) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	_toast_t = seconds


func _process(delta: float) -> void:
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
