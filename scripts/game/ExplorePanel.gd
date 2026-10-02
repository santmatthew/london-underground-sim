class_name ExplorePanel
extends CenterContainer
## The setup screen of explore mode: pick any station (search or a random one), where in it to start (a street entrance, the ticket hall, the concourse past the gates or a platform), the day and the time.
## `start_requested({station, spot, hour, day})` when the player starts; `closed` when they go back (Back button or Esc). Game opens it from the main menu and from the pause panel of an explore session.

signal start_requested(cfg: Dictionary)
signal closed

var font_b: Font
var font_r: Font
var station := -1                     # the chosen station (Net index)
var spot_index := 0                   # the chosen start spot (index into plan.start_spots)
var _rows: Array = []                 # Net index of each row of the list
var _search: LineEdit
var _list: ItemList
var _spot: OptionButton
var _day: OptionButton
var _time: HSlider
var _time_lbl: Label
var _where: Label


func _init(p_font_b: Font = null, p_font_r: Font = null) -> void:
	font_b = p_font_b
	font_r = p_font_r
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _label(text: String, size := 18, col := Color.WHITE, bold := false, min_w := 0.0) -> Label:
	var l := Label.new()
	l.custom_minimum_size.x = min_w
	l.text = text
	l.add_theme_font_override("font", font_b if bold else font_r)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font_b)
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(240, 46)
	b.pressed.connect(func(): Sfx.play("ui_click_soft"))
	b.pressed.connect(cb)
	return b


func _ready() -> void:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(780, 0)
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
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	vb.add_child(_label("EXPLORE", 44, Color(1, 0.85, 0.2), true))
	vb.add_child(_label("Roam the network freely: no destination and no clock to beat. Choose a station and where in it you start; walk the station, ride any train and get off wherever you like.", 17, Color(0.85, 0.9, 1.0)))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vb.add_child(top)
	_search = LineEdit.new()
	_search.placeholder_text = "Search stations"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_font_override("font", font_r)
	_search.add_theme_font_size_override("font_size", 20)
	_search.text_changed.connect(func(_t): _fill())
	_search.text_submitted.connect(func(_t): _start())
	top.add_child(_search)
	var rnd := Button.new()
	rnd.text = "Random station"
	rnd.add_theme_font_override("font", font_b)
	rnd.pressed.connect(func():
		_search.text = ""
		station = randi() % Net.stations.size()
		_fill()
		_pick_station())
	top.add_child(rnd)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(720, 200)
	_list.add_theme_font_override("font", font_r)
	_list.add_theme_font_size_override("font_size", 20)
	_list.item_selected.connect(func(i):
		station = int(_rows[i])
		_pick_station())
	_list.item_activated.connect(func(_i): _start())
	vb.add_child(_list)
	_where = _label("", 16, Color(0.7, 0.8, 0.95), false, 700.0)
	vb.add_child(_where)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	vb.add_child(grid)
	grid.add_child(_label("Start at", 18, Color.WHITE, false, 150.0))
	_spot = OptionButton.new()
	_spot.add_theme_font_override("font", font_r)
	_spot.custom_minimum_size = Vector2(480, 0)
	_spot.item_selected.connect(func(i): spot_index = int(_spot.get_item_metadata(i)))
	grid.add_child(_spot)
	grid.add_child(_label("Day", 18, Color.WHITE, false, 150.0))
	_day = OptionButton.new()
	_day.add_theme_font_override("font", font_r)
	for t in [["Weekday", "weekday"], ["Saturday", "saturday"], ["Sunday", "sunday"]]:
		_day.add_item(t[0])
		_day.set_item_metadata(_day.item_count - 1, t[1])
	grid.add_child(_day)
	_time_lbl = _label("", 18, Color.WHITE, false, 150.0)
	grid.add_child(_time_lbl)
	_time = HSlider.new()
	_time.min_value = 5.0
	_time.max_value = 24.0
	_time.step = 0.25
	_time.value = 10.0
	_time.custom_minimum_size = Vector2(480, 26)
	_time.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time.value_changed.connect(func(_v): _show_time())
	grid.add_child(_time)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	row.add_child(_button("Start exploring", _start))
	row.add_child(_button("Back", close))
	visible = false
	_show_time()


func _show_time() -> void:
	_time_lbl.text = "Time  %s" % Clock.fmt(_time.value * 3600.0)


func open() -> void:
	visible = true
	if station < 0:
		station = Net.name_to_idx.get("Oxford Circus", 0)
	_fill()
	_pick_station()
	_search.grab_focus.call_deferred()


func close() -> void:
	visible = false
	closed.emit()


## the stations whose name contains the search text, alphabetically
func _fill() -> void:
	var q := _search.text.strip_edges().to_lower()
	var items: Array = []
	for st in Net.stations:
		var nm: String = st["name"]
		if q == "" or nm.to_lower().contains(q):
			items.append([nm, int(st["idx"])])
	items.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	_list.clear()
	_rows = []
	var sel := -1
	for it in items:
		_list.add_item(String(it[0]))
		_rows.append(int(it[1]))
		if int(it[1]) == station:
			sel = _rows.size() - 1
	if sel >= 0:
		_list.select(sel)
		_list.ensure_current_is_visible()
	elif not _rows.is_empty() and q != "":
		_list.select(0)
		station = int(_rows[0])
		_pick_station()


## the start spots of the chosen station
func _pick_station() -> void:
	if station < 0:
		return
	var plan := StationPlan.for_station(station)
	_spot.clear()
	var best := 0
	var seen := {}
	for i in plan.start_spots.size():
		var sp: Dictionary = plan.start_spots[i]
		var lb := spot_label(plan, sp)
		seen[lb] = int(seen.get(lb, 0)) + 1
		_spot.add_item(lb if int(seen[lb]) == 1 else "%s (%d)" % [lb, int(seen[lb])])
		_spot.set_item_metadata(_spot.item_count - 1, i)
		if best == 0 and sp["name"] == "ticket hall":
			best = _spot.item_count - 1
	if _spot.item_count > 0:
		_spot.select(best)
		spot_index = int(_spot.get_item_metadata(best))
	var lines: Array = []
	for lid in Net.stations[station]["lines"]:
		lines.append(Net.line_name(lid))
	_where.text = "%s — %s" % [Net.station_name(station), ", ".join(lines)]


## what to call a start spot: street entrances by their street where it is known, the hall and concourse, platforms by number, line and direction
static func spot_label(plan: StationPlan, sp: Dictionary) -> String:
	var nm: String = sp["name"]
	match nm:
		"street entrance":
			var n := 0
			for i in plan.street_doors.size():
				if String(plan.street_doors[i]["id"]) == String(sp["node"]):
					n = i
			var sd: Dictionary = plan.street_doors[n] if n < plan.street_doors.size() else {}
			var street := String(sd.get("exit_name", ""))
			if street != "":
				return "Street entrance — %s" % street
			return "Street entrance" if plan.street_doors.size() <= 1 else "Street entrance %d" % (n + 1)
		"ticket hall":
			return "Ticket hall (before the gates)" + _hall_suffix(plan, sp)
		"concourse":
			return "Concourse (past the gates)" + _hall_suffix(plan, sp)
		"platform":
			var f: Dictionary = plan.faces.get(String(sp.get("face", "")), {})
			if f.is_empty():
				return "Platform"
			return "Platform %d — %s %s" % [plan.platform_no.get(f["pid"], 0), plan.dir_text(f["pid"]), Net.line_name(f["line"])]
	return nm.capitalize()


static func _hall_suffix(plan: StationPlan, sp: Dictionary) -> String:
	if plan.gatelines.size() <= 1:
		return ""
	var digits := String(sp["node"]).substr(4, String(sp["node"]).find("_") - 4)
	return " — hall %s" % (digits if digits != "" else "1")


func _start() -> void:
	if station < 0:
		return
	var day := String(_day.get_item_metadata(_day.selected))
	visible = false
	start_requested.emit({"station": station, "spot": spot_index, "hour": _time.value, "day": day})


func _input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev.is_action_pressed("pause", false, true) or ev.is_action_pressed("ui_cancel", false, true):
		get_viewport().set_input_as_handled()
		close()
