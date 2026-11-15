extends Node
## Quest log. Definitions come from data/quests; progress is {quest_id: {state, done: {objective: true}}}.

signal quest_started(id: String)
signal quest_updated(id: String)
signal quest_completed(id: String)

var _defs: Dictionary = {}
var _state: Dictionary = {}
var _order: Array = []


func _ready() -> void:
	var data = DataFiles.load_json("res://data/quests/quests.json")
	if data is Dictionary:
		_defs = data


func has_definition(id: String) -> bool:
	return _defs.has(id)


func get_def(id: String) -> Dictionary:
	return _defs.get(id, {})


func is_active(id: String) -> bool:
	return _state.get(id, {}).get("state", "") == "active"


func is_done(id: String) -> bool:
	return _state.get(id, {}).get("state", "") == "done"


func objective_done(id: String, objective: String) -> bool:
	return _state.get(id, {}).get("done", {}).get(objective, false)


func start(id: String) -> bool:
	if not _defs.has(id):
		push_error("Quests: unknown quest '%s'" % id)
		return false
	if _state.has(id):
		return false
	_state[id] = {"state": "active", "done": {}}
	_order.append(id)
	quest_started.emit(id)
	GameState.toast.emit("New quest: %s" % _defs[id]["title"])
	return true


func complete_objective(id: String, objective: String) -> bool:
	if not is_active(id) or objective_done(id, objective):
		return false
	_state[id]["done"][objective] = true
	quest_updated.emit(id)
	var all_done := true
	for o in _defs[id]["objectives"]:
		if not _state[id]["done"].get(o["id"], false):
			all_done = false
	if all_done:
		_complete(id)
	return true


func _complete(id: String) -> void:
	_state[id]["state"] = "done"
	GameState.toast.emit("Quest complete: %s" % _defs[id]["title"])
	Effects.run_all(_defs[id].get("on_complete", []))
	quest_completed.emit(id)


## Quest ids in start order, active quests first.
func list_ids() -> Array:
	var active: Array = []
	var done: Array = []
	for id in _order:
		(active if is_active(id) else done).append(id)
	return active + done


func active_ids() -> Array:
	return _order.filter(func(id): return is_active(id))


func reset() -> void:
	_state.clear()
	_order.clear()


func serialize() -> Dictionary:
	return {"state": _state.duplicate(true), "order": _order.duplicate()}


func deserialize(d: Dictionary) -> void:
	_state = d.get("state", {}).duplicate(true)
	_order = d.get("order", []).duplicate()
