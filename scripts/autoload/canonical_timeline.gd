extends Node
## System A: the Canonical Timeline. Major biblical events, in scriptural order.
##
## Nothing the player does can add, remove, reorder or change these. Dialogue, quests, flags and
## the Effects helper have no route to this node; only the story controller advances it.

signal event_occurred(event_id: String)

var _events: Dictionary = {}
var _order: Array = []
var _occurred: Dictionary = {}


func _ready() -> void:
	var data = DataFiles.load_json("res://data/canon/events.json")
	if not data is Dictionary:
		return
	var list: Array = data.get("events", [])
	list.sort_custom(func(a, b): return a["order"] < b["order"])
	for e in list:
		_events[e["id"]] = e
		_order.append(e["id"])


func has_event(id: String) -> bool:
	return _events.has(id)


func get_event(id: String) -> Dictionary:
	return _events.get(id, {}).duplicate(true)


func event_ids() -> Array:
	return _order.duplicate()


func has_occurred(id: String) -> bool:
	return _occurred.get(id, false)


func occurred_ids() -> Array:
	return _occurred.keys()


## Story-controller only. Events must happen in scriptural order.
func story_advance(id: String) -> bool:
	if not _events.has(id) or _occurred.has(id):
		return false
	var idx := _order.find(id)
	for i in range(idx):
		if not _occurred.has(_order[i]):
			push_warning("Canon event '%s' advanced before '%s'" % [id, _order[i]])
			return false
	_occurred[id] = true
	event_occurred.emit(id)
	return true


func reset() -> void:
	_occurred.clear()


func serialize() -> Dictionary:
	return {"occurred": _occurred.keys()}


func deserialize(d: Dictionary) -> void:
	_occurred.clear()
	for id in d.get("occurred", []):
		_occurred[id] = true
