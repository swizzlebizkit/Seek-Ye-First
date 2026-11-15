class_name StrategicView
extends Control
## The long-distance map. Opened from a waymark or a landing, it lists the roads (or water routes) that leave
## the protagonist's present place, shows the day and Sabbath, and animates the traveller along the chosen
## route while the world clock runs. It is a way to travel, never a place to jump to: arriving or being
## stopped by the Sabbath always puts the protagonist in a playable region.

signal closed

const FAST := 8.0

var _modes: Array = ["land", "water"]
var _canvas: MapCanvas
var _list: ItemList
var _info: RichTextLabel
var _title: Label
var _clock: Label
var _bar: ProgressBar
var _msg: Label
var _go: Button
var _stop: Button
var _abandon: Button
var _close: Button
var _speed: Button
var _hint: Label
var _options: Array = []
var _moving := false
var _fast := false
var _busy := false  # a message is showing before a scene change
var _selected := -1
var _recenter_pending := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel(0.98))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -600
	panel.offset_right = 600
	panel.offset_top = -340
	panel.offset_bottom = 340
	add_child(panel)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	panel.add_child(body)

	_canvas = MapCanvas.new()
	_canvas.custom_minimum_size = Vector2(640, 0)
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.place_clicked.connect(_on_place_clicked)
	body.add_child(_canvas)

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)

	_title = UiTheme.label("The road", 26, UiTheme.GOLD)
	side.add_child(_title)
	_clock = UiTheme.label("", 18, UiTheme.MUTED)
	side.add_child(_clock)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 150)
	_list.select_mode = ItemList.SELECT_SINGLE
	_list.add_theme_font_size_override("font_size", 18)
	_list.add_theme_color_override("font_color", UiTheme.TEXT)
	_list.add_theme_color_override("font_selected_color", UiTheme.GOLD)
	_list.add_theme_color_override("font_hovered_color", UiTheme.GOLD)
	_list.add_theme_stylebox_override("panel", UiTheme._button_box(Color("1f1812"), 1))
	_list.add_theme_stylebox_override("selected", UiTheme._button_box(UiTheme.PARCHMENT_LIGHT, 2))
	_list.add_theme_stylebox_override("selected_focus", UiTheme._button_box(UiTheme.PARCHMENT_LIGHT, 2))
	_list.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_list.item_selected.connect(_on_row_selected)
	_list.item_activated.connect(func(_i): _on_go())
	side.add_child(_list)

	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info.focus_mode = Control.FOCUS_NONE
	_info.add_theme_font_size_override("normal_font_size", 18)
	_info.add_theme_font_size_override("bold_font_size", 18)
	_info.add_theme_color_override("default_color", UiTheme.TEXT)
	side.add_child(_info)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 18)
	_bar.max_value = 1.0
	_bar.show_percentage = false
	side.add_child(_bar)

	_msg = UiTheme.label("", 17, UiTheme.GOLD)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(0, 46)
	side.add_child(_msg)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	side.add_child(row)
	_go = _button("Set out", row, _on_go)
	_stop = _button("Stop at the next camp", row, _on_stop)
	_abandon = _button("Abandon", row, _on_abandon)
	_speed = _button("Faster", row, _on_speed)
	_close = _button("Close", row, close)

	_hint = UiTheme.label("Up/Down: choose    Enter: set out    Space: faster    + / -: zoom    Esc: close", 14, UiTheme.MUTED)
	side.add_child(_hint)


func _button(text: String, row: Control, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(b, 17)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(cb)
	row.add_child(b)
	return b


# -- opening and closing -----------------------------------------------------------------------
func open(modes: Array = ["land", "water"]) -> void:
	_modes = modes
	visible = true
	_busy = false
	_moving = false
	_fast = false
	_msg.text = ""
	GameState.mode = GameState.Mode.MAP
	_refresh(false)
	_recenter_pending = true  # the map has no size until it has been laid out
	_list.grab_focus()


func close() -> void:
	if _moving or _busy:
		return
	visible = false
	if GameState.mode == GameState.Mode.MAP:
		GameState.mode = GameState.Mode.EXPLORE
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _moving:
			_on_stop()
		else:
			close()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				get_viewport().set_input_as_handled()
				_on_speed()
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				get_viewport().set_input_as_handled()
				_canvas.set_zoom(_canvas.zoom * 1.3)
			KEY_MINUS, KEY_KP_SUBTRACT:
				get_viewport().set_input_as_handled()
				_canvas.set_zoom(_canvas.zoom / 1.3)
			KEY_ENTER, KEY_KP_ENTER:
				if not _moving:
					get_viewport().set_input_as_handled()
					_on_go()
			KEY_A:
				if not _moving and _abandon.visible and not _abandon.disabled:
					get_viewport().set_input_as_handled()
					_on_abandon()


# -- state -------------------------------------------------------------------------------------
func _refresh(recenter: bool = false) -> void:
	_options = Travel.options().filter(func(o): return _modes.has(o["mode"]))
	_list.clear()
	_selected = -1
	var journey: Dictionary = Travel.journey
	var underway: bool = _moving
	var paused: bool = not journey.is_empty() and journey["state"] == "paused"
	_list.visible = journey.is_empty()
	_bar.visible = not journey.is_empty()
	_stop.visible = underway or (not journey.is_empty() and journey["state"] == "underway")
	_abandon.visible = paused
	_speed.visible = underway
	_close.disabled = underway
	_canvas.here = ""
	_canvas.highlight_route = ""
	_canvas.selected = ""
	_canvas.traveller = Vector2.ZERO

	if not journey.is_empty():
		_title.text = "To %s" % World.location_name(str(journey["to"]))
		_canvas.highlight_route = str(journey["route"])
		_canvas.traveller = Travel.traveller_point()
		_canvas.traveller_mode = str(journey["mode"])
		_bar.value = Travel.progress_fraction()
		if recenter:
			_canvas.set_zoom(5.0)
			_canvas.focus(Travel.traveller_point())
		_go.text = "Resume"
		_go.visible = paused
		_go.disabled = not paused or not Travel.can_resume()["ok"]
		_show_journey()
	else:
		var here := World.current_location()
		_title.text = "The road from %s" % World.location_name(here) if here != "" else "The road"
		_canvas.here = here
		if here != "":
			_canvas.traveller = Vector2(World.locations[here]["pos"][0], World.locations[here]["pos"][1])
			_canvas.traveller_mode = "land"
		elif World.context.has("route"):
			_canvas.traveller = World.point_on_route(str(World.context["route"]), float(World.context.get("km", 0.0)))
		if recenter and _canvas.traveller != Vector2.ZERO:
			_canvas.set_zoom(5.0)
			_canvas.focus(_canvas.traveller)
		_go.text = "Set out"
		_go.visible = true
		for o in _options:
			var r := World.route(str(o["route"]))
			var how := "by boat" if o["mode"] == "water" else "on foot"
			var from_road := "" if World.context.has("location") or World.current_location() != "" else " (from here)"
			_list.add_item("%s: %s, %.0f km %s%s" % [World.location_name(str(o["to"])), r["name"], _remaining(o), how, from_road])
		if _options.is_empty():
			_go.disabled = true
			_info.text = "No road leads on from here that you know of yet.\n\nWalk the land, speak to people, and the roads will show themselves."
		else:
			_list.select(0)
			_on_row_selected(0)
	_update_clock()


func _remaining(o: Dictionary) -> float:
	var length := float(World.route(str(o["route"]))["length_km"])
	return length - float(o["from_km"]) if int(o["dir"]) > 0 else float(o["from_km"])


func _on_row_selected(i: int) -> void:
	_selected = i
	if i < 0 or i >= _options.size():
		return
	var o: Dictionary = _options[i]
	_canvas.selected = str(o["to"])
	_canvas.highlight_route = str(o["route"])
	var chk := Travel.can_start(o)
	_go.disabled = not chk["ok"]
	var est := Travel.estimate_option(o)
	var r := World.route(str(o["route"]))
	var lines: Array = []
	lines.append("[b]%s[/b]  (%s)" % [r["name"], "by boat" if o["mode"] == "water" else "on foot"])
	lines.append("%.0f km to %s." % [_remaining(o), World.location_name(str(o["to"]))])
	lines.append("")
	if not chk["ok"]:
		lines.append("[color=#d49a9a]%s[/color]" % chk["reason"])
	elif est["event"] == "sabbath":
		lines.append("The Sabbath will begin on the way (%s). You would stop for it and could go on after sunset the next day." % Calendar.hud_text(int(est["day"]), float(est["minute"]), _time(float(est["minute"]))))
	else:
		lines.append("About %s on the road." % _duration(float(est["moving"])))
		lines.append("You would arrive: %s" % Calendar.hud_text(int(est["day"]), float(est["minute"]), _time(float(est["minute"]))))
		if float(est["rest"]) > 0.0:
			lines.append("Resting overnight on the way.")
	var dest: Dictionary = World.location(str(o["to"]))
	if World.level_of(str(o["to"])) == "rumored":
		lines.append("")
		lines.append("[i]You have only heard of this place.[/i]")
	elif dest.get("category", "") == "uncertain":
		lines.append("")
		lines.append("[i]Historical note: %s[/i]" % dest["certainty"])
	_info.text = "\n".join(lines)
	_update_clock()


func _show_journey() -> void:
	var j: Dictionary = Travel.journey
	var lines: Array = []
	lines.append("[b]%s[/b]  (%s)" % [World.route(str(j["route"]))["name"], "by boat" if j["mode"] == "water" else "on foot"])
	lines.append("From %s to %s. %.0f km remain." % [World.location_name(str(j["from"])), World.location_name(str(j["to"])), Travel.remaining_km()])
	var est := Travel.estimate()
	if j["state"] == "paused":
		lines.append("")
		match str(j["pause"]):
			"sabbath":
				lines.append("The journey is paused for the Sabbath. You may travel again after sunset on the seventh day.")
			"encounter":
				lines.append("The journey is paused; something has happened on the road.")
			"load":
				lines.append("The journey is paused.")
			_:
				lines.append("You have stopped on the road.")
		var chk := Travel.can_resume()
		if not chk["ok"]:
			lines.append("[color=#d49a9a]%s[/color]" % chk["reason"])
		else:
			lines.append("You may go on when you are ready. Nothing moves until you decide.")
	elif est["event"] != "":
		lines.append("")
		lines.append("Arrival: %s" % Calendar.hud_text(int(est["day"]), float(est["minute"]), _time(float(est["minute"]))) if est["event"] == "arrived" else "The Sabbath will stop you on the way.")
	_info.text = "\n".join(lines)


func _update_clock() -> void:
	_clock.text = Calendar.hud_text(WorldSim.day, WorldSim.minute_of_day, WorldSim.time_string())
	_clock.add_theme_color_override("font_color", UiTheme.GOLD if Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day) else UiTheme.MUTED)


func _time(minute: float) -> String:
	var m := int(minute)
	return "%d:%02d" % [m / 60, m % 60]


func _duration(minutes: float) -> String:
	var m := int(round(minutes))
	if m >= 48 * 60:
		return "%d days" % int(round(m / 1440.0))
	if m >= 60:
		return "%d h %02d min" % [m / 60, m % 60]
	return "%d min" % m


# -- actions -----------------------------------------------------------------------------------
func _on_place_clicked(id: String) -> void:
	if _moving:
		return
	for i in range(_options.size()):
		if _options[i]["to"] == id:
			_list.select(i)
			_on_row_selected(i)
			return


func _on_go() -> void:
	if _moving or _busy:
		return
	if Travel.journey.is_empty():
		if _selected < 0 or _selected >= _options.size():
			return
		var o: Dictionary = _options[_selected]
		if not Travel.start(o):
			_msg.text = Travel.can_start(o)["reason"]
			return
	elif not Travel.resume():
		_msg.text = Travel.can_resume()["reason"]
		return
	_moving = true
	_msg.text = ""
	_refresh()
	_canvas.set_zoom(4.0)


func _on_stop() -> void:
	if Travel.request_stop():
		_msg.text = "You will stop at the next camp on the road."
	else:
		_msg.text = "A boat cannot put in anywhere on the open water."


func _on_abandon() -> void:
	Travel.abandon()
	_msg.text = "You give up the journey. You stand on the road and may go on to either end, or turn back."
	_refresh()


func _on_speed() -> void:
	_fast = not _fast
	_speed.text = "Normal speed" if _fast else "Faster"


# -- the journey, frame by frame ---------------------------------------------------------------
func _recenter() -> void:
	_recenter_pending = false
	_canvas.set_zoom(5.0)
	if not Travel.journey.is_empty():
		_canvas.focus(Travel.traveller_point())
	elif _canvas.traveller != Vector2.ZERO:
		_canvas.focus(_canvas.traveller)


func _process(delta: float) -> void:
	if not visible:
		return
	if _recenter_pending and _canvas.size.x > 0.0:
		_recenter()
	_update_clock()
	if not _moving or _busy:
		return
	var rate := float(World.travel_rules.get("animation_minutes_per_second", 40.0)) * (FAST if _fast else 1.0)
	var out := Travel.run(delta * rate)
	_canvas.traveller = Travel.traveller_point() if not Travel.journey.is_empty() else _canvas.traveller
	_canvas.focus(_canvas.traveller)
	_bar.value = Travel.progress_fraction()
	if float(out["rest"]) > 0.0 and out["event"] == "":
		_msg.text = "Night falls. You rest, and set out again at dawn."
	if out["event"] == "":
		return
	_moving = false
	_busy = true
	match str(out["event"]):
		"arrived":
			Travel.notice = "arrived"
			_finish("You arrive at %s." % World.location_name(Travel.last_arrival), Callable(Travel, "enter_arrival_region"))
		"sabbath":
			Travel.notice = "sabbath"
			_finish("The sun goes down and the Sabbath begins. Strategic overland travel has paused. You make for the nearest camp.", Callable(Travel, "enter_paused_region"))
		"stop":
			Travel.notice = "stop"
			_finish("You stop at the camp on the road.", Callable(Travel, "enter_paused_region"))
		"scripted":
			_msg.text = str(out["text"])
			if not Travel.journey.is_empty() and Travel.journey["state"] == "paused":
				Travel.notice = "stop"
				_finish(str(out["text"]), Callable(Travel, "enter_paused_region"))
			else:
				_moving = true
				_busy = false


func _finish(text: String, then: Callable) -> void:
	_msg.text = text
	_moving = false
	for b in [_go, _stop, _speed, _abandon]:
		b.visible = false
	await get_tree().create_timer(1.4).timeout
	_busy = false
	visible = false
	if GameState.mode == GameState.Mode.MAP:
		GameState.mode = GameState.Mode.EXPLORE
	then.call()
	closed.emit()
