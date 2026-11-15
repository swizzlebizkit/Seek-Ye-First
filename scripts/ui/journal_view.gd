class_name JournalView
extends Control
## The protagonist's journal, quest log and satchel. Journal entries show their original text first,
## then relevant KJV passages, then any later notes the protagonist added.

enum Tab { JOURNAL, QUESTS, SATCHEL }

const TYPE_COLORS := {
	"eyewitness": Color("9fd3a4"),
	"testimony": Color("8fb3c9"),
	"rumor": Color("d9b36a"),
	"observation": Color("c8c0a8"),
	"question": Color("d49a9a"),
}
const ORIGIN_LABELS := {
	"fiction": "Fictional account",
	"scripture": "Scripture",
	"history": "Historical reconstruction",
}

var _tab_buttons: Array[Button] = []
var _list: ItemList
var _details: RichTextLabel
var _hint: Label
var _tab: int = Tab.JOURNAL
var _row_ids: Array = []


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
	panel.offset_top = -330
	panel.offset_bottom = 330
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	for i in range(3):
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = ["Journal", "Quests", "Satchel"][i]
		UiTheme.style_button(b, 22)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(_set_tab.bind(i))
		header.add_child(b)
		_tab_buttons.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_hint = UiTheme.label("Left/Right: tab    Up/Down: choose    PgUp/PgDn: scroll    J or Esc: close", 15, UiTheme.MUTED)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_hint)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(400, 0)
	_list.select_mode = ItemList.SELECT_SINGLE
	_list.auto_height = false
	_list.add_theme_font_size_override("font_size", 18)
	_list.add_theme_color_override("font_color", UiTheme.TEXT)
	_list.add_theme_color_override("font_selected_color", UiTheme.GOLD)
	_list.add_theme_color_override("font_hovered_color", UiTheme.GOLD)
	_list.add_theme_stylebox_override("panel", UiTheme._button_box(Color("1f1812"), 1))
	_list.add_theme_stylebox_override("selected", UiTheme._button_box(UiTheme.PARCHMENT_LIGHT, 2))
	_list.add_theme_stylebox_override("selected_focus", UiTheme._button_box(UiTheme.PARCHMENT_LIGHT, 2))
	_list.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_list.item_selected.connect(_on_row_selected)
	body.add_child(_list)

	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.focus_mode = Control.FOCUS_NONE
	_details.add_theme_font_size_override("normal_font_size", 20)
	_details.add_theme_font_size_override("bold_font_size", 20)
	_details.add_theme_font_size_override("italics_font_size", 20)
	_details.add_theme_color_override("default_color", UiTheme.TEXT)
	body.add_child(_details)


func open() -> void:
	visible = true
	GameState.mode = GameState.Mode.JOURNAL
	_refresh()
	_list.grab_focus()


func close() -> void:
	visible = false
	if GameState.mode == GameState.Mode.JOURNAL:
		GameState.mode = GameState.Mode.EXPLORE


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("journal") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		_set_tab(wrapi(_tab - 1, 0, 3))
	elif event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		_set_tab(wrapi(_tab + 1, 0, 3))
	elif event is InputEventKey and event.pressed and (event.keycode == KEY_PAGEDOWN or event.keycode == KEY_PAGEUP):
		get_viewport().set_input_as_handled()
		var bar := _details.get_v_scroll_bar()
		bar.value += (200 if event.keycode == KEY_PAGEDOWN else -200)


func _set_tab(tab: int) -> void:
	_tab = tab
	_refresh()
	_list.grab_focus()


func _refresh() -> void:
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
	_tab_buttons[0].text = "Journal (%d)" % Journal.count()
	_list.clear()
	_row_ids.clear()
	match _tab:
		Tab.JOURNAL:
			for rec in Journal.list():
				var idx := _list.add_item("%s: %s" % [Journal.types.get(rec["type"], rec["type"]), rec["title"]])
				_list.set_item_custom_fg_color(idx, TYPE_COLORS.get(rec["type"], UiTheme.TEXT))
				_row_ids.append(rec["id"])
		Tab.QUESTS:
			for id in Quests.list_ids():
				var done := Quests.is_done(id)
				_list.add_item(Quests.get_def(id)["title"] + ("  (done)" if done else ""))
				if done:
					_list.set_item_custom_fg_color(_list.item_count - 1, UiTheme.DISABLED)
				_row_ids.append(id)
		Tab.SATCHEL:
			for id in GameState.inventory:
				_list.add_item("%s  x%d" % [GameState.item_name(id), GameState.item_count(id)])
				_row_ids.append(id)
	if _row_ids.is_empty():
		_details.text = _empty_text()
	else:
		_list.select(0)
		_on_row_selected(0)


func _empty_text() -> String:
	match _tab:
		Tab.JOURNAL:
			return "[i][color=#b3a27c]Nothing is written here yet.\n\nThings you see and hear will be recorded: what you witness yourself, what others tell you, rumors you have yet to verify, and the questions you cannot put down.[/color][/i]"
		Tab.QUESTS:
			return "[i][color=#b3a27c]You have no errands or questions to pursue yet.[/color][/i]"
		_:
			return "[i][color=#b3a27c]Your satchel is empty.[/color][/i]"


func _on_row_selected(index: int) -> void:
	if index < 0 or index >= _row_ids.size():
		return
	var id: String = _row_ids[index]
	match _tab:
		Tab.JOURNAL:
			_details.text = _entry_bbcode(Journal.get_entry(id))
		Tab.QUESTS:
			_details.text = _quest_bbcode(id)
		Tab.SATCHEL:
			_details.text = "[b][color=#e8d29a]%s[/color][/b]\n\n%s" % [
				GameState.item_name(id), _esc(GameState.items.get(id, {}).get("description", ""))]
	_details.scroll_to_line(0)


func _entry_bbcode(rec: Dictionary) -> String:
	var type_name: String = Journal.types.get(rec["type"], rec["type"])
	var status_name: String = Journal.statuses.get(rec["status"], rec["status"])
	var s := "[b][color=#e8d29a]%s[/color][/b]\n" % _esc(rec["title"])
	s += "[color=#b3a27c]%s  |  %s  |  Day %d[/color]\n" % [type_name, status_name, rec["day"]]
	if rec["source"] != "":
		s += "[color=#b3a27c]From: %s[/color]\n" % _esc(rec["source"])
	s += "\n%s\n" % _esc(rec["text"])
	if not rec["refs"].is_empty():
		s += "\n[b][color=#e8d29a]Scripture to compare (KJV)[/color][/b]\n"
		for ref in rec["refs"]:
			s += _scripture_bbcode(ref)
	if not rec["notes"].is_empty():
		s += "\n[b][color=#e8d29a]Later notes[/color][/b]\n"
		for n in rec["notes"]:
			var who: String = n.get("source", "")
			s += "- [color=#b3a27c](%sDay %d)[/color] %s\n" % [who + ", " if who != "" else "", int(n.get("day", 1)), _esc(n["text"])]
			for ref in n.get("refs", []):
				s += _scripture_bbcode(ref, "    ")
	s += "\n[color=#7d705a]%s[/color]" % ORIGIN_LABELS.get(rec.get("origin", "fiction"), "")
	return s


func _scripture_bbcode(ref: String, indent: String = "") -> String:
	var verses: Array = Scripture.get_verses(ref)
	var s := "%s[i]%s[/i]\n" % [indent, ref]
	if verses.is_empty():
		return s + "%s[color=#7d705a](text not yet available)[/color]\n" % indent
	for v in verses:
		s += "%s[color=#b3a27c]%d[/color] %s\n" % [indent, v["n"], _esc(v["text"])]
	return s


func _quest_bbcode(id: String) -> String:
	var def := Quests.get_def(id)
	var s := "[b][color=#e8d29a]%s[/color][/b]\n" % _esc(def["title"])
	s += "[color=#b3a27c]%s[/color]\n\n%s\n\n" % ["Complete" if Quests.is_done(id) else "In progress", _esc(def["summary"])]
	for o in def["objectives"]:
		if Quests.objective_done(id, o["id"]):
			s += "[color=#7d705a]- %s (done)[/color]\n" % _esc(o["text"])
		else:
			s += "- %s\n" % _esc(o["text"])
	return s


## Keeps player text from being parsed as BBCode tags.
func _esc(t: String) -> String:
	return t.replace("[", "[lb]")
