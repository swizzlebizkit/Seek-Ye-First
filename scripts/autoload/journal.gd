extends Node
## The protagonist's journal. An entry's original text is copied in when it is discovered and is never
## edited afterwards. Later understanding arrives as appended notes and status changes, so the record
## of what the protagonist first thought survives. The whole record is saved with the game.

signal entry_added(id: String)
signal entry_updated(id: String)

const DATA_PATH := "res://data/journal/entries.json"

var types: Dictionary = {}
var statuses: Dictionary = {}
var _defs: Dictionary = {}
var _entries: Dictionary = {}  # id -> record
var _order: Array = []


func _ready() -> void:
	var data = DataFiles.load_json(DATA_PATH)
	if data is Dictionary:
		types = data.get("types", {})
		statuses = data.get("statuses", {})
		_defs = data.get("entries", {})


func has_definition(id: String) -> bool:
	return _defs.has(id)


func has_entry(id: String) -> bool:
	return _entries.has(id)


func discover(id: String) -> bool:
	if _entries.has(id):
		return false
	if not _defs.has(id):
		push_error("Journal: unknown entry '%s'" % id)
		return false
	var d: Dictionary = _defs[id]
	_entries[id] = {
		"id": id,
		"type": d["type"],
		"title": d["title"],
		"text": d["text"],
		"source": d.get("source", ""),
		"origin": d.get("origin", "fiction"),
		"refs": d.get("refs", []).duplicate(),
		"status": d.get("status", "recorded"),
		"day": WorldSim.day,
		"notes": [],
	}
	_order.append(id)
	entry_added.emit(id)
	GameState.toast.emit("Journal updated: %s" % d["title"])
	return true


## Appends a later note. `note_id` makes the call idempotent. Original text is never touched.
func annotate(id: String, text: String, refs: Array = [], source: String = "", note_id: String = "") -> bool:
	if not _entries.has(id):
		return false
	var rec: Dictionary = _entries[id]
	if note_id != "":
		for n in rec["notes"]:
			if n.get("id", "") == note_id:
				return false
	rec["notes"].append({"id": note_id, "text": text, "refs": refs.duplicate(), "source": source, "day": WorldSim.day})
	entry_updated.emit(id)
	GameState.toast.emit("Journal note added: %s" % rec["title"])
	return true


func set_status(id: String, status: String) -> bool:
	if not _entries.has(id) or _entries[id]["status"] == status:
		return false
	_entries[id]["status"] = status
	entry_updated.emit(id)
	GameState.toast.emit("%s is now %s" % [_entries[id]["title"], statuses.get(status, status).to_lower()])
	return true


func get_entry(id: String) -> Dictionary:
	return _entries.get(id, {})


func count() -> int:
	return _order.size()


## Entries in discovery order; optionally only one type.
func list(type_filter: String = "") -> Array:
	var out: Array = []
	for id in _order:
		var rec: Dictionary = _entries[id]
		if type_filter == "" or rec["type"] == type_filter:
			out.append(rec)
	return out


func reset() -> void:
	_entries.clear()
	_order.clear()


func serialize() -> Dictionary:
	return {"entries": _entries.duplicate(true), "order": _order.duplicate()}


func deserialize(d: Dictionary) -> void:
	_entries = d.get("entries", {}).duplicate(true)
	_order = d.get("order", []).duplicate()
	for id in _entries:
		_entries[id]["day"] = int(_entries[id].get("day", 1))
