class_name Hud
extends CanvasLayer
## On-screen overlay: quest tracker, clock, interaction prompt, toasts, and the modal screens
## (dialogue, journal, pause).

signal save_requested(slot: int)
signal load_requested(slot: int)
signal quit_requested
signal defeat_continue

const MAX_TOASTS := 4

var dialogue_box: DialogueBox
var journal_view: JournalView
var pause_menu: PauseMenu
var equipment_view: EquipmentView

var _tracker: Label
var _clock: Label
var _hint: Label
var _prompt: Label
var _toasts: VBoxContainer
var _root: Control
var _hearts: HBoxContainer
var _flash: ColorRect
var _defeat: Control
var _defeat_ready := false
var _last_hp := -1


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_tracker = UiTheme.outlined(UiTheme.label("", 18, UiTheme.TEXT))
	_tracker.position = Vector2(24, 62)
	_root.add_child(_tracker)

	_flash = ColorRect.new()
	_flash.color = Color(0.75, 0.05, 0.05, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

	_hearts = HBoxContainer.new()
	_hearts.position = Vector2(24, 18)
	_hearts.add_theme_constant_override("separation", 4)
	_root.add_child(_hearts)

	_clock = UiTheme.outlined(UiTheme.label("", 18, UiTheme.MUTED))
	_clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_clock.offset_left = -520
	_clock.offset_right = -24
	_clock.offset_top = 18
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_clock)

	_hint = UiTheme.outlined(UiTheme.label("WASD move   E interact   K attack   Shift dodge   H eat   I equipment   J journal   Esc menu   F5 / F9 quick save / load", 15, UiTheme.MUTED))
	_hint.position = Vector2(24, 692)
	_root.add_child(_hint)

	_prompt = UiTheme.outlined(UiTheme.label("", 22, UiTheme.GOLD))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.offset_top = -92
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_prompt)

	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.offset_left = -320
	_toasts.offset_right = 320
	_toasts.offset_top = 56
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)

	dialogue_box = DialogueBox.new()
	_root.add_child(dialogue_box)
	journal_view = JournalView.new()
	_root.add_child(journal_view)
	equipment_view = EquipmentView.new()
	_root.add_child(equipment_view)
	pause_menu = PauseMenu.new()
	_root.add_child(pause_menu)
	_build_defeat_screen()
	pause_menu.save_requested.connect(func(s): save_requested.emit(s))
	pause_menu.load_requested.connect(func(s): load_requested.emit(s))
	pause_menu.quit_requested.connect(func(): quit_requested.emit())

	GameState.toast.connect(show_toast)
	GameState.mode_changed.connect(func(_m): _update_chrome())
	Combat.player_hp_changed.connect(_on_hp_changed)
	_on_hp_changed(Combat.player_hp, Combat.max_hp())
	Quests.quest_started.connect(func(_id): _refresh_tracker())
	Quests.quest_updated.connect(func(_id): _refresh_tracker())
	Quests.quest_completed.connect(func(_id): _refresh_tracker())
	_refresh_tracker()
	_update_chrome()


func bind(player: Player) -> void:
	player.focus_changed.connect(_on_focus_changed)


func _process(_delta: float) -> void:
	var phase := Calendar.current_phase()
	_clock.text = Calendar.hud_text(WorldSim.day, WorldSim.minute_of_day, WorldSim.time_string())
	_clock.add_theme_color_override("font_color", UiTheme.GOLD if phase == "sabbath" else UiTheme.MUTED)


func show_toast(text: String) -> void:
	var l := UiTheme.outlined(UiTheme.label(text, 20, UiTheme.GOLD), 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toasts.add_child(l)
	while _toasts.get_child_count() > MAX_TOASTS:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func _on_focus_changed(target: Interactable) -> void:
	_prompt.text = "[E]  %s" % target.prompt_text() if target != null else ""


func _refresh_tracker() -> void:
	var lines: PackedStringArray = []
	for id in Quests.active_ids():
		var def := Quests.get_def(id)
		for o in def["objectives"]:
			if not Quests.objective_done(id, o["id"]):
				lines.append("%s\n   %s" % [def["title"], o["text"]])
				break
	_tracker.text = "\n".join(lines)


func _on_hp_changed(hp: int, max_hp: int) -> void:
	for c in _hearts.get_children():
		_hearts.remove_child(c)
		c.queue_free()
	for i in range(max_hp / 2):
		var state := "full" if hp >= (i + 1) * 2 else ("half" if hp == i * 2 + 1 else "empty")
		var icon := TextureRect.new()
		icon.texture = load("res://assets/ui/heart_%s.png" % state)
		icon.custom_minimum_size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_hearts.add_child(icon)
	if _last_hp >= 0 and hp < _last_hp:
		_flash.color.a = 0.35
		create_tween().tween_property(_flash, "color:a", 0.0, 0.35)
	_last_hp = hp


func _build_defeat_screen() -> void:
	_defeat = Control.new()
	_defeat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_defeat.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.02, 0.02, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_defeat.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = -80
	box.offset_bottom = 80
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_defeat.add_child(box)
	var title := UiTheme.outlined(UiTheme.label("You are overcome", 44, UiTheme.GOLD), 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := UiTheme.outlined(UiTheme.label("When you come to, you are bruised but whole, back where you began.", 20, UiTheme.TEXT), 5)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	var hint := UiTheme.outlined(UiTheme.label("[E]  Get up", 24, UiTheme.MUTED), 5)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_root.add_child(_defeat)


func show_defeat() -> void:
	_defeat.visible = true
	_defeat_ready = false
	get_tree().create_timer(0.8).timeout.connect(func(): _defeat_ready = true)


func hide_defeat() -> void:
	_defeat.visible = false


func _input(event: InputEvent) -> void:
	if _defeat.visible and _defeat_ready and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		defeat_continue.emit()


func _update_chrome() -> void:
	var exploring := GameState.mode == GameState.Mode.EXPLORE
	_hearts.visible = GameState.mode != GameState.Mode.MENU
	_tracker.visible = exploring
	_clock.visible = exploring
	_hint.visible = exploring
	_prompt.visible = exploring
