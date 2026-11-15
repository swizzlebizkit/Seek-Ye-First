class_name PauseMenu
extends Control
## Esc menu: resume, save, load, quit to the main menu.

signal save_requested(slot: int)
signal load_requested(slot: int)
signal quit_requested

var _menu: PanelContainer
var _slots: SlotPanel
var _resume_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", UiTheme.panel(0.98))
	_center(_menu, 190, 0)
	add_child(_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_menu.add_child(box)
	box.add_child(UiTheme.label("Paused", 30, UiTheme.GOLD))
	_resume_button = _add_button(box, "Resume", close)
	_add_button(box, "Save Game", _open_slots.bind("save"))
	var load_btn := _add_button(box, "Load Game", _open_slots.bind("load"))
	load_btn.disabled = not SaveManager.has_any_save()
	_add_button(box, "Quit to Main Menu", func(): quit_requested.emit())


func open() -> void:
	visible = true
	GameState.mode = GameState.Mode.PAUSED
	_menu.visible = true
	_resume_button.grab_focus()


func close() -> void:
	_close_slots()
	visible = false
	if GameState.mode == GameState.Mode.PAUSED:
		GameState.mode = GameState.Mode.EXPLORE


func _input(event: InputEvent) -> void:
	if not visible or _slots != null:
		return  # an open slot panel handles its own cancel
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _open_slots(mode: String) -> void:
	_menu.visible = false
	_slots = SlotPanel.new().setup(mode)
	_center(_slots, 340, 0)
	_slots.slot_chosen.connect(func(slot: int):
		if mode == "save":
			save_requested.emit(slot)
			_close_slots()
			close()
		else:
			load_requested.emit(slot))
	_slots.closed.connect(func():
		_close_slots()
		_menu.visible = true
		_resume_button.grab_focus())
	add_child(_slots)


func _close_slots() -> void:
	if _slots != null:
		_slots.queue_free()
		_slots = null


func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	UiTheme.style_button(b, 22)
	b.custom_minimum_size = Vector2(300, 0)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _center(c: Control, half_w: float, half_h: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.5
	c.anchor_bottom = 0.5
	c.offset_left = -half_w
	c.offset_right = half_w
	c.offset_top = -half_h
	c.offset_bottom = half_h
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
