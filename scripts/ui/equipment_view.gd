class_name EquipmentView
extends Control
## The equipment screen: six physical slots on the left, what could fill the chosen slot in the
## middle, and plain stat details on the right. Names and numbers only: wearing something grants
## its listed physical stats and nothing else.

var _slots: ItemList
var _items: ItemList
var _details: RichTextLabel
var _totals: Label
var _slot_ids: Array = []
var _item_ids: Array = []  # parallel to _items rows; "" = take it off


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel(0.98))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -560
	panel.offset_right = 560
	panel.offset_top = -300
	panel.offset_bottom = 300
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	header.add_child(UiTheme.label("Equipment", 30, UiTheme.GOLD))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var hint := UiTheme.label("Up/Down: choose    Enter: select or equip    Left/Right: switch list    I or Esc: close", 15, UiTheme.MUTED)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(hint)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	_slots = _make_list(340)
	_slots.item_selected.connect(func(_i): _refresh_items())
	_slots.item_activated.connect(func(_i): _focus_items())
	body.add_child(_slots)

	_items = _make_list(300)
	_items.item_selected.connect(func(_i): _refresh_details())
	_items.item_activated.connect(_on_item_activated)
	body.add_child(_items)

	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.focus_mode = Control.FOCUS_NONE
	for f in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		_details.add_theme_font_size_override(f, 19)
	_details.add_theme_color_override("default_color", UiTheme.TEXT)
	body.add_child(_details)

	_totals = UiTheme.label("", 19, UiTheme.GOLD)
	root.add_child(_totals)


func _make_list(width: int) -> ItemList:
	var l := ItemList.new()
	l.custom_minimum_size = Vector2(width, 0)
	l.select_mode = ItemList.SELECT_SINGLE
	l.auto_height = false
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", UiTheme.TEXT)
	l.add_theme_color_override("font_selected_color", UiTheme.GOLD)
	l.add_theme_color_override("font_hovered_color", UiTheme.GOLD)
	l.add_theme_stylebox_override("panel", UiTheme._button_box(Color("1f1812"), 1))
	l.add_theme_stylebox_override("selected", UiTheme._button_box(UiTheme.PARCHMENT_LIGHT, 2))
	l.add_theme_stylebox_override("selected_focus", UiTheme._button_box(UiTheme.PARCHMENT_LIGHT, 2))
	l.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return l


func open() -> void:
	visible = true
	GameState.mode = GameState.Mode.EQUIPMENT
	_refresh_slots()
	_slots.grab_focus()


func close() -> void:
	visible = false
	if GameState.mode == GameState.Mode.EQUIPMENT:
		GameState.mode = GameState.Mode.EXPLORE


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("equipment") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _items.has_focus() and not event.is_action_pressed("equipment"):
			_slots.grab_focus()
		else:
			close()
	elif event.is_action_pressed("ui_right") and _slots.has_focus():
		get_viewport().set_input_as_handled()
		_focus_items()
	elif event.is_action_pressed("ui_left") and _items.has_focus():
		get_viewport().set_input_as_handled()
		_slots.grab_focus()


# -- content -----------------------------------------------------------------------------------
func _selected_slot() -> String:
	var sel := _slots.get_selected_items()
	return _slot_ids[sel[0]] if not sel.is_empty() else ""


func _refresh_slots() -> void:
	var keep := _selected_slot()
	_slots.clear()
	_slot_ids = Equipment.slot_ids()
	for slot in _slot_ids:
		var worn := Equipment.equipped(slot)
		_slots.add_item("%s:  %s" % [Equipment.slot_label(slot), GameState.item_name(worn) if worn != "" else "-"])
	var idx := maxi(0, _slot_ids.find(keep))
	_slots.select(idx)
	_refresh_items()
	_refresh_totals()


func _refresh_items() -> void:
	_items.clear()
	_item_ids.clear()
	var slot := _selected_slot()
	if slot == "":
		return
	if Equipment.equipped(slot) != "":
		_items.add_item("Take off")
		_item_ids.append("")
	for id in Equipment.candidates_for(slot):
		var mark := "  (worn)" if Equipment.is_equipped(id) else ""
		_items.add_item(GameState.item_name(id) + mark)
		_item_ids.append(id)
	if _item_ids.is_empty():
		_items.add_item("Nothing to wear here")
		_items.set_item_disabled(0, true)
		_item_ids.append("none")
	else:
		_items.select(0)
	_refresh_details()


func _refresh_details() -> void:
	var slot := _selected_slot()
	var sel := _items.get_selected_items()
	var id := ""
	if not sel.is_empty() and _item_ids[sel[0]] != "" and _item_ids[sel[0]] != "none":
		id = _item_ids[sel[0]]
	elif Equipment.equipped(slot) != "":
		id = Equipment.equipped(slot)
	if id == "":
		_details.text = "[i][color=#b3a27c]%s: nothing worn.[/color][/i]" % _esc(Equipment.slot_label(slot))
		return
	_details.text = details_bbcode(id)


## Plain description of an item and its physical stats. Public so tests can check what is shown.
func details_bbcode(id: String) -> String:
	var def: Dictionary = GameState.items.get(id, {})
	var s := "[b][color=#e8d29a]%s[/color][/b]\n" % _esc(GameState.item_name(id))
	s += "[color=#b3a27c]%s%s[/color]\n\n" % [Equipment.slot_label(Equipment.slot_of(id)),
		"  |  Placeholder item" if def.get("placeholder", false) else ""]
	s += "%s\n\n" % _esc(def.get("description", ""))
	var stats: Dictionary = def.get("stats", {})
	if stats.is_empty():
		s += "[color=#7d705a]No special properties.[/color]\n"
	for k in stats:
		s += "%s: %s\n" % [Equipment.stat_label(k), stat_text(k, float(stats[k]))]
	return s


func _refresh_totals() -> void:
	var t := Equipment.totals()
	var parts: PackedStringArray = []
	for k in ["defense", "block", "mobility"]:
		parts.append("%s %s" % [Equipment.stat_label(k), stat_text(k, float(t.get(k, 0.0)))])
	if Equipment.has_sword():
		parts.append("%s %s" % [Equipment.stat_label("attack"), stat_text("attack", float(t.get("attack", 0.0)))])
	else:
		parts.append("No sword in hand")
	_totals.text = "Worn:   " + "    ".join(parts)


static func stat_text(key: String, value: float) -> String:
	match key:
		"mobility":
			return "%+d%%" % int(round(value * 100.0))
		"cooldown":
			return "%.2f s" % value
		"reach":
			return "%d" % int(value)
		_:
			return "%d" % int(value)


# -- actions -----------------------------------------------------------------------------------
func _focus_items() -> void:
	if _items.item_count > 0 and not _items.is_item_disabled(0):
		_items.grab_focus()


func _on_item_activated(index: int) -> void:
	var slot := _selected_slot()
	var id: String = _item_ids[index]
	if id == "none":
		return
	if id == "":
		Equipment.unequip(slot)
	else:
		Equipment.equip(id)
	_refresh_slots()
	_slots.grab_focus()


func _esc(t: String) -> String:
	return t.replace("[", "[lb]")
