class_name SlotPanel
extends PanelContainer
## Three save slots, used for both saving and loading. Emits slot_chosen(slot) or closed.

signal slot_chosen(slot: int)
signal closed

var _mode := "load"
var _buttons: Array[Button] = []


func setup(mode: String) -> SlotPanel:
	_mode = mode
	return self


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel(0.98))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	box.add_child(UiTheme.label("Save Game" if _mode == "save" else "Load Game", 28, UiTheme.GOLD))
	for slot in range(1, SaveManager.SLOTS + 1):
		var b := Button.new()
		UiTheme.style_button(b, 20)
		b.custom_minimum_size = Vector2(640, 0)
		var info := SaveManager.slot_info(slot)
		b.text = _describe(slot, info)
		b.disabled = _mode == "load" and not info["exists"]
		b.pressed.connect(func(): slot_chosen.emit(slot))
		box.add_child(b)
		_buttons.append(b)
	var back := Button.new()
	back.text = "Back"
	UiTheme.style_button(back, 20)
	back.pressed.connect(func(): closed.emit())
	box.add_child(back)
	for b in _buttons:
		if not b.disabled:
			b.grab_focus()
			return
	back.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		closed.emit()


func _describe(slot: int, info: Dictionary) -> String:
	if not info["exists"]:
		return "Slot %d    (empty)" % slot
	var minutes := int(float(info["play_seconds"]) / 60.0)
	return "Slot %d    %s    %d min    %d journal entries    %s" % [
		slot, info["place"], minutes, int(info["journal_entries"]), info["saved_at"]]
