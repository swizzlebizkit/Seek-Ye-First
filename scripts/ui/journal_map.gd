class_name JournalMap
extends HBoxContainer
## The journal's Map tab: the strategic map, the regions the protagonist has walked, and the villages
## they know, each showing only what has been discovered. It is a record to read and reason from. There
## is deliberately no way to travel from here: no button, key or click on this screen moves the
## protagonist; roads are walked, or taken from a waymark.

enum Level { STRATEGIC, REGIONAL, LOCAL }

const WORLD_ENTRY := "__world__"
var level: int = Level.STRATEGIC
var _list: ItemList
var _level_buttons: Array[Button] = []
var _canvas: MapCanvas
var _region_map: RegionMap
var _details: RichTextLabel
var _ids: Array = []


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	left.add_child(row)
	for i in range(3):
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = ["Lands", "Roads", "Village"][i]
		UiTheme.style_button(b, 16)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(set_level.bind(i))
		b.tooltip_text = ["The whole map", "Country you have walked", "A village you know"][i]
		row.add_child(b)
		_level_buttons.append(b)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.select_mode = ItemList.SELECT_SINGLE
	_list.add_theme_font_size_override("font_size", 17)
	_list.add_theme_color_override("font_color", UiTheme.TEXT)
	_list.add_theme_color_override("font_selected_color", UiTheme.GOLD)
	_list.add_theme_color_override("font_hovered_color", UiTheme.GOLD)
	_list.add_theme_stylebox_override("panel", UiTheme._button_box(Color("1f1812"), 1))
	_list.add_theme_stylebox_override("selected", UiTheme._button_box(UiTheme.PARCHMENT_LIGHT, 2))
	_list.add_theme_stylebox_override("selected_focus", UiTheme._button_box(UiTheme.PARCHMENT_LIGHT, 2))
	_list.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_list.item_selected.connect(_on_selected)
	left.add_child(_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	_canvas = MapCanvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size = Vector2(420, 330)
	_canvas.place_clicked.connect(_on_place_clicked)
	right.add_child(_canvas)
	_region_map = RegionMap.new()
	_region_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_region_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_region_map.custom_minimum_size = Vector2(420, 330)
	right.add_child(_region_map)
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.custom_minimum_size = Vector2(0, 150)
	_details.focus_mode = Control.FOCUS_NONE
	_details.add_theme_font_size_override("normal_font_size", 17)
	_details.add_theme_font_size_override("bold_font_size", 17)
	_details.add_theme_font_size_override("italics_font_size", 17)
	_details.add_theme_color_override("default_color", UiTheme.TEXT)
	right.add_child(_details)


func focus_list() -> void:
	_list.grab_focus()


func set_level(l: int) -> void:
	level = l
	refresh()


func zoom(factor: float) -> void:
	if level == Level.STRATEGIC:
		_canvas.set_zoom(_canvas.zoom * factor)
	else:
		_region_map.set_zoom(_region_map.zoom * factor)


## Rebuilds the list for the current level from what has been discovered.
func refresh() -> void:
	for i in range(_level_buttons.size()):
		_level_buttons[i].set_pressed_no_signal(i == level)
	_canvas.visible = level == Level.STRATEGIC
	_region_map.visible = level != Level.STRATEGIC
	_list.clear()
	_ids.clear()
	match level:
		Level.STRATEGIC:
			var here := World.current_location()
			for id in World.locations:
				var lv := World.level_of(id)
				if lv == "unknown":
					continue
				var tag := "  (heard of)" if lv == "rumored" else ""
				_list.add_item("%s%s" % [World.location_name(id), tag])
				_ids.append(id)
			_canvas.here = here
			_canvas.traveller = Vector2.ZERO
		_:
			var shown := 0
			for rid in World.region_ids():
				var m := World.region_meta(rid)
				var want: String = "local" if level == Level.LOCAL else "regional"
				if m.get("kind", "") == want and World.regions_visited.has(rid) and World.explored.has(rid):
					if level == Level.REGIONAL and shown == 0:
						_list.add_item("The whole countryside")
						_ids.append(WORLD_ENTRY)
					shown += 1
					_list.add_item(World.region_name(rid))
					_ids.append(rid)
	if _ids.is_empty():
		_details.text = "[i][color=#b3a27c]%s[/color][/i]" % ["Nothing of the wider land is known yet." if level == Level.STRATEGIC else ("You have not yet walked far enough from a village to draw the country." if level == Level.REGIONAL else "No village is known well enough to draw.")]
		_region_map.region_id = ""
		_region_map._data = {}
		_region_map.queue_redraw()
		_canvas.selected = ""
		_canvas.queue_redraw()
		return
	_list.select(0)
	_on_selected(0)


func _on_place_clicked(id: String) -> void:
	var i := _ids.find(id)
	if i >= 0 and level == Level.STRATEGIC:
		_list.select(i)
		_on_selected(i)


func _on_selected(i: int) -> void:
	if i < 0 or i >= _ids.size():
		return
	var id: String = _ids[i]
	if level == Level.STRATEGIC:
		_canvas.selected = id
		if _canvas.zoom <= 1.0:
			_canvas.set_zoom(3.0)
		_canvas.focus(Vector2(World.locations[id]["pos"][0], World.locations[id]["pos"][1]))
		_details.text = place_text(id)
	elif id == WORLD_ENTRY:
		_region_map.set_world()
		_details.text = world_text()
	else:
		_region_map.set_region(id, level == Level.LOCAL)
		_details.text = region_text(id)
	_canvas.queue_redraw()


## What the protagonist knows about a place, and nothing they have not found out.
func place_text(id: String) -> String:
	var loc: Dictionary = World.location(id)
	var lv := World.level_of(id)
	var s := "[b][color=#e8d29a]%s[/color][/b]  [color=#b3a27c](%s)[/color]\n" % [loc["name"], {
		"rumored": "you have only heard of it", "discovered": "known, not yet visited",
		"visited": "you have been here", "investigated": "you have asked questions here"}.get(lv, lv)]
	var heard: Array = World.place_sources.get(id, [])
	if not heard.is_empty():
		s += "Heard of: %s\n" % ", ".join(heard)
	if lv != "rumored":
		var roads: Array = []
		for rid in World.routes_from(id):
			if World.route_is_known(rid):
				roads.append("%s (%.0f km, %s)" % [World.location_name(World.other_end(rid, id)), World.route(rid)["length_km"], "by boat" if World.route(rid)["mode"] == "water" else "on foot"])
		if not roads.is_empty():
			s += "Roads: " + "; ".join(roads) + "\n"
		if loc["category"] == "uncertain":
			s += "[i]%s[/i]\n" % loc["certainty"]
		var refs: Array = loc.get("hooks", {}).get("scripture_refs", [])
		if not refs.is_empty() and lv in ["visited", "investigated"]:
			s += "Written of in: %s\n" % ", ".join(refs)
	else:
		s += "[i]No one has told you the way there.[/i]\n"
	return s


func world_text() -> String:
	var seen: Array = []
	for rid in World.continuous_rects():
		if World.explored.has(rid):
			seen.append("%s (%d%%)" % [World.region_name(rid), int(round(World.explored_fraction(rid) * 100.0))])
	return "[b][color=#e8d29a]The whole countryside[/color][/b]
Country you have walked, where it lies. Explored: %s" % ", ".join(seen)


func region_text(id: String) -> String:
	var m := World.region_meta(id)
	var s := "[b][color=#e8d29a]%s[/color][/b]\n" % World.region_name(id)
	s += "Explored: %d%%\n" % int(round(World.explored_fraction(id) * 100.0))
	var found: Array = []
	for it in m.get("interactables", []):
		var lm := str(it.get("landmark", ""))
		if lm != "" and World.landmarks_found.get(lm, false):
			found.append(str(it["name"]))
	if not found.is_empty():
		s += "Landmarks: %s\n" % ", ".join(found)
	return s
