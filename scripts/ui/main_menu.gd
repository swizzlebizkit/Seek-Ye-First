extends Control
## Title screen: Continue, New Game, Load Game, Quit.

var _column: VBoxContainer
var _slots: SlotPanel


func _ready() -> void:
	GameState.mode = GameState.Mode.MENU
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/title_bg.png")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_top", 70)
	add_child(margin)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	margin.add_child(_column)

	_column.add_child(UiTheme.outlined(UiTheme.label("SEEK YE FIRST", 76, UiTheme.GOLD), 10))
	_column.add_child(UiTheme.outlined(UiTheme.label("A New Testament Adventure", 28, UiTheme.TEXT), 6))
	var verse := UiTheme.outlined(UiTheme.label("%s  (Matthew 6:33, KJV)" % Scripture.get_passage("Matthew 6:33"), 17, UiTheme.MUTED), 4)
	verse.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	verse.custom_minimum_size = Vector2(620, 0)
	_column.add_child(verse)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 28)
	_column.add_child(gap)

	var continue_btn := _add_button("Continue", _on_continue)
	continue_btn.disabled = not SaveManager.has_any_save()
	var new_btn := _add_button("New Game", _on_new_game)
	var load_btn := _add_button("Load Game", _on_load_game)
	load_btn.disabled = not SaveManager.has_any_save()
	if OS.is_debug_build():
		_add_button("Combat Training Yard (dev)", func(): start_game({"mode": "training"}))
	_add_button("Quit", func(): get_tree().quit())
	(new_btn if continue_btn.disabled else continue_btn).grab_focus()

	var footer := UiTheme.outlined(UiTheme.label(
		"Prototype: Milestone 2A.  Kefar Zayit and its people are invented for the story.  Scripture text: King James Version (public domain).", 14, UiTheme.MUTED), 4)
	footer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	footer.offset_left = 24
	footer.offset_top = -34
	add_child(footer)

	DevHooks.maybe_autostart(self)


func start_game(request: Dictionary) -> void:
	GameState.start_request = request
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _add_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	UiTheme.style_button(b, 26)
	b.custom_minimum_size = Vector2(300, 0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(action)
	_column.add_child(b)
	return b


func _on_continue() -> void:
	var slot := SaveManager.latest_slot()
	if slot > 0:
		start_game({"mode": "load", "slot": slot})


func _on_new_game() -> void:
	start_game({"mode": "new"})


func _on_load_game() -> void:
	_column.get_parent().visible = false
	_slots = SlotPanel.new().setup("load")
	_slots.anchor_left = 0.5
	_slots.anchor_right = 0.5
	_slots.anchor_top = 0.5
	_slots.anchor_bottom = 0.5
	_slots.offset_left = -340
	_slots.offset_right = 340
	_slots.offset_top = -170
	_slots.offset_bottom = 170
	_slots.slot_chosen.connect(func(slot: int): start_game({"mode": "load", "slot": slot}))
	_slots.closed.connect(func():
		_slots.queue_free()
		_column.get_parent().visible = true)
	add_child(_slots)
