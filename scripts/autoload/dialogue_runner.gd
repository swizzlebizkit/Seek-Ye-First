extends Node
## Plays data-driven dialogue (data/dialogue/*.json) and ad-hoc "examine" text.
##
## A dialogue has `entries` (first whose `when` passes picks the start node) and `nodes`.
## A node has `lines` (pages), optional `effects` (run on entry), then either `choices` or `next`.

signal started(speaker: String)
signal line_shown(speaker: String, text: String, narration: bool)
signal choices_shown(speaker: String, texts: Array)
signal finished

var active := false

var _data: Dictionary = {}
var _node: Dictionary = {}
var _speaker := ""
var _narration := false
var _lines: Array = []
var _line_index := 0
var _choices: Array = []
var _cache: Dictionary = {}


func start(dialogue_id: String) -> void:
	var data = _load(dialogue_id)
	if not data is Dictionary:
		return
	var node_name := ""
	for e in data.get("entries", []):
		if not e.has("when") or GameState.check(e["when"]):
			node_name = e["node"]
			break
	if node_name == "":
		push_error("Dialogue '%s' has no matching entry" % dialogue_id)
		return
	_begin(data, node_name)


## One-off text, e.g. examining a signpost. `effects` run when the text opens.
func start_text(lines: Array, effects: Array = [], speaker: String = "", narration: bool = true) -> void:
	var data := {
		"speaker": speaker,
		"narration": narration,
		"nodes": {"_adhoc": {"lines": lines, "effects": effects}},
	}
	_begin(data, "_adhoc")


## Ends the current dialogue immediately (used by dev tooling and scene changes).
func cancel() -> void:
	if active:
		_finish()


func advance() -> void:
	if not active:
		return
	_line_index += 1
	if _line_index < _lines.size():
		_show_line()
	else:
		_after_lines()


func choose(index: int) -> void:
	if not active or index < 0 or index >= _choices.size():
		return
	var c: Dictionary = _choices[index]
	_choices = []
	Effects.run_all(c.get("effects", []))
	var next = c.get("next", null)
	if next == null:
		_finish()
	else:
		_enter(next)


func _load(id: String) -> Variant:
	if not _cache.has(id):
		_cache[id] = DataFiles.load_json("res://data/dialogue/%s.json" % id)
	return _cache[id]


func _begin(data: Dictionary, node_name: String) -> void:
	_data = data
	_narration = data.get("narration", false)
	active = true
	GameState.mode = GameState.Mode.DIALOGUE
	started.emit(data.get("speaker", ""))
	_enter(node_name)


func _enter(node_name: String) -> void:
	var node = _data.get("nodes", {}).get(node_name)
	if node == null:
		push_error("Dialogue node '%s' not found" % node_name)
		_finish()
		return
	_node = node
	Effects.run_all(node.get("effects", []))
	_speaker = node.get("speaker", _data.get("speaker", ""))
	_lines = node.get("lines", [])
	_line_index = 0
	if _lines.is_empty():
		_after_lines()
	else:
		_show_line()


func _show_line() -> void:
	line_shown.emit(_speaker, _lines[_line_index], _narration)


func _after_lines() -> void:
	var visible_choices: Array = []
	for c in _node.get("choices", []):
		if not c.has("when") or GameState.check(c["when"]):
			visible_choices.append(c)
	if not visible_choices.is_empty():
		_choices = visible_choices
		var texts: Array = []
		for c in _choices:
			texts.append(c["text"])
		choices_shown.emit(_speaker, texts)
	elif _node.get("next", null) != null:
		_enter(_node["next"])
	else:
		_finish()


func _finish() -> void:
	active = false
	_choices = []
	GameState.mode = GameState.Mode.EXPLORE
	finished.emit()
