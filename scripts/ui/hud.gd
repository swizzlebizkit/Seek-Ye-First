class_name Hud
extends CanvasLayer
## On-screen overlay: quest tracker, clock, interaction prompt, toasts, and the modal screens
## (dialogue, journal, pause).

signal save_requested(slot: int)
signal load_requested(slot: int)
signal quit_requested

const MAX_TOASTS := 4

var dialogue_box: DialogueBox
var journal_view: JournalView
var pause_menu: PauseMenu

var _tracker: Label
var _clock: Label
var _hint: Label
var _prompt: Label
var _toasts: VBoxContainer
var _root: Control


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_tracker = UiTheme.outlined(UiTheme.label("", 18, UiTheme.TEXT))
	_tracker.position = Vector2(24, 18)
	_root.add_child(_tracker)

	_clock = UiTheme.outlined(UiTheme.label("", 18, UiTheme.MUTED))
	_clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_clock.offset_left = -200
	_clock.offset_right = -24
	_clock.offset_top = 18
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_clock)

	_hint = UiTheme.outlined(UiTheme.label("WASD move   E interact   J journal   Esc menu   F5 quick save   F9 quick load", 15, UiTheme.MUTED))
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
	pause_menu = PauseMenu.new()
	_root.add_child(pause_menu)
	pause_menu.save_requested.connect(func(s): save_requested.emit(s))
	pause_menu.load_requested.connect(func(s): load_requested.emit(s))
	pause_menu.quit_requested.connect(func(): quit_requested.emit())

	GameState.toast.connect(show_toast)
	GameState.mode_changed.connect(func(_m): _update_chrome())
	Quests.quest_started.connect(func(_id): _refresh_tracker())
	Quests.quest_updated.connect(func(_id): _refresh_tracker())
	Quests.quest_completed.connect(func(_id): _refresh_tracker())
	_refresh_tracker()
	_update_chrome()


func bind(player: Player) -> void:
	player.focus_changed.connect(_on_focus_changed)


func _process(_delta: float) -> void:
	_clock.text = "Day %d   %s" % [WorldSim.day, WorldSim.time_string()]


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


func _update_chrome() -> void:
	var exploring := GameState.mode == GameState.Mode.EXPLORE
	_tracker.visible = exploring
	_clock.visible = exploring
	_hint.visible = exploring
	_prompt.visible = exploring
