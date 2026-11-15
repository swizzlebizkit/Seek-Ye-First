extends Node
## Registers keyboard actions at startup so the bindings live in code, not in project.godot.

const BINDINGS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E, KEY_SPACE, KEY_ENTER],
	"journal": [KEY_J, KEY_TAB],
	"pause": [KEY_ESCAPE],
	"quick_save": [KEY_F5],
	"quick_load": [KEY_F9],
}


func _init() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
