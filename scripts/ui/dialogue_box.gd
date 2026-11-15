class_name DialogueBox
extends Control
## Bottom-of-screen dialogue panel driven by the DialogueRunner autoload. Text types out;
## pressing interact first completes the line, then moves on. Choices are picked with
## Up/Down + interact, number keys, or the mouse.

const CHARS_PER_SECOND := 75.0

var _name_label: Label
var _text: RichTextLabel
var _choices_box: VBoxContainer
var _arrow: Blinker
var _choice_labels: Array[Label] = []
var _typing := false
var _progress := 0.0
var _choosing := false
var _selected := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel())
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 80
	panel.offset_right = -80
	panel.offset_top = -236
	panel.offset_bottom = -28
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_name_label = UiTheme.label("", 24, UiTheme.GOLD)
	box.add_child(_name_label)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(0, 84)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("normal_font_size", 22)
	_text.add_theme_font_size_override("italics_font_size", 22)
	_text.add_theme_color_override("default_color", UiTheme.TEXT)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_text)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 2)
	box.add_child(_choices_box)

	_arrow = Blinker.new()
	_arrow.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(_arrow)

	DialogueRunner.started.connect(_on_started)
	DialogueRunner.line_shown.connect(_on_line)
	DialogueRunner.choices_shown.connect(_on_choices)
	DialogueRunner.finished.connect(_on_finished)


func _process(delta: float) -> void:
	if not _typing:
		return
	_progress += CHARS_PER_SECOND * delta
	var total := _text.get_total_character_count()
	if _progress >= total:
		_finish_typing()
	else:
		_text.visible_characters = int(_progress)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or GameState.mode != GameState.Mode.DIALOGUE:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_confirm()
	elif _choosing and (event.is_action_pressed("move_up") or event.is_action_pressed("ui_up")):
		get_viewport().set_input_as_handled()
		_select(_selected - 1)
	elif _choosing and (event.is_action_pressed("move_down") or event.is_action_pressed("ui_down")):
		get_viewport().set_input_as_handled()
		_select(_selected + 1)
	elif _choosing and event is InputEventKey and event.pressed and not event.echo:
		var n: int = event.keycode - KEY_1
		if n >= 0 and n < _choice_labels.size():
			get_viewport().set_input_as_handled()
			_pick(n)


func _confirm() -> void:
	if _typing:
		_finish_typing()
	elif _choosing:
		_pick(_selected)
	else:
		DialogueRunner.advance()


func _pick(index: int) -> void:
	_choosing = false
	_clear_choices()
	DialogueRunner.choose(index)


func _on_started(_speaker: String) -> void:
	visible = true
	_clear_choices()
	_text.text = ""


func _on_line(speaker: String, text: String, narration: bool) -> void:
	_name_label.text = speaker
	_name_label.visible = speaker != ""
	_choosing = false
	_clear_choices()
	_text.text = "[i][color=#d8cbb0]%s[/color][/i]" % text if narration else text
	_text.visible_characters = 0
	_progress = 0.0
	_typing = true
	_arrow.visible = false


func _on_choices(_speaker: String, texts: Array) -> void:
	_clear_choices()
	_arrow.visible = false
	for i in range(texts.size()):
		var l := UiTheme.label("", 21)
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.mouse_entered.connect(_select.bind(i))
		l.gui_input.connect(_on_choice_gui_input.bind(i))
		l.set_meta("text_plain", "%d. %s" % [i + 1, texts[i]])
		_choices_box.add_child(l)
		_choice_labels.append(l)
	_choosing = true
	_select(0)


func _on_choice_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pick(index)


func _select(index: int) -> void:
	if _choice_labels.is_empty():
		return
	_selected = wrapi(index, 0, _choice_labels.size())
	for i in range(_choice_labels.size()):
		var l := _choice_labels[i]
		var on := i == _selected
		l.text = ("> " if on else "   ") + l.get_meta("text_plain")
		l.add_theme_color_override("font_color", UiTheme.GOLD if on else UiTheme.TEXT)


func _clear_choices() -> void:
	for l in _choice_labels:
		_choices_box.remove_child(l)
		l.queue_free()
	_choice_labels.clear()


func _finish_typing() -> void:
	_typing = false
	_text.visible_characters = -1
	_arrow.visible = not _choosing


func _on_finished() -> void:
	visible = false
	_typing = false
	_choosing = false
	_clear_choices()
