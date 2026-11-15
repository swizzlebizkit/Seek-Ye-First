extends Node
## The protagonist's journal. An entry's original text is copied in when it is discovered and is never
## edited afterwards. Later understanding arrives as appended notes and status changes, so the record
## of what the protagonist first thought survives. The whole record is saved with the game.

signal entry_added(id: String)
signal entry_updated(id: String)
signal link_found(link_id: String)

const DATA_PATH := "res://data/journal/entries.json"
const LINKS_PATH := "res://data/journal/links.json"

var types: Dictionary = {}
var statuses: Dictionary = {}
var relationships: Dictionary = {}
var _defs: Dictionary = {}
var _link_defs: Dictionary = {}
var _found: Dictionary = {}  # link id -> {day, source, understood}; kept even if the entry is not written yet
var _entries: Dictionary = {}  # id -> record
var _order: Array = []


func _ready() -> void:
	var data = DataFiles.load_json(DATA_PATH)
	if data is Dictionary:
		types = data.get("types", {})
		statuses = data.get("statuses", {})
		_defs = data.get("entries", {})
	var links = DataFiles.load_json(LINKS_PATH)
	if links is Dictionary:
		relationships = links.get("relationships", {})
		_link_defs = links.get("links", {})


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
		"day": Calendar.current_day(),
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
	rec["notes"].append({"id": note_id, "text": text, "refs": refs.duplicate(), "source": source, "day": Calendar.current_day()})
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


# -- Scripture links ---------------------------------------------------------------------------
## A link joins a journal entry to a passage elsewhere in Scripture. It stays hidden until something in
## the world reveals it; once found it is permanent. Finding it is separate from understanding it.
func has_link_definition(link_id: String) -> bool:
	return _link_defs.has(link_id)


func link_ids() -> Array:
	return _link_defs.keys()


func link_def(link_id: String) -> Dictionary:
	return _link_defs.get(link_id, {})


func discover_link(link_id: String, source: String = "") -> bool:
	if _found.has(link_id):
		return false
	if not _link_defs.has(link_id):
		push_error("Journal: unknown scripture link '%s'" % link_id)
		return false
	_found[link_id] = {"day": Calendar.current_day(), "source": source, "understood": false}
	link_found.emit(link_id)
	var entry: String = _link_defs[link_id]["entry"]
	if _entries.has(entry):
		entry_updated.emit(entry)
		GameState.toast.emit("New connection noted: %s" % _entries[entry]["title"])
	return true


func has_link(link_id: String) -> bool:
	return _found.has(link_id)


## Marks a found link as truly grasped by the protagonist. Reserved for much later in the story.
func understand_link(link_id: String) -> bool:
	if not _found.has(link_id) or _found[link_id]["understood"]:
		return false
	_found[link_id]["understood"] = true
	var entry: String = _link_defs[link_id]["entry"]
	if _entries.has(entry):
		entry_updated.emit(entry)
	return true


## Found links for an entry, in the order the data lists them, as definition plus discovery details.
func links_for(entry_id: String) -> Array:
	var out: Array = []
	for lid in _link_defs:
		if _link_defs[lid]["entry"] == entry_id and _found.has(lid):
			var rec: Dictionary = _link_defs[lid].duplicate(true)
			rec["id"] = lid
			rec["found"] = _found[lid].duplicate()
			out.append(rec)
	return out


## How many links an entry could hold, without saying which. For a quiet "there may be more" hint.
func links_possible(entry_id: String) -> int:
	var n := 0
	for lid in _link_defs:
		if _link_defs[lid]["entry"] == entry_id:
			n += 1
	return n


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
	_found.clear()


func serialize() -> Dictionary:
	return {"entries": _entries.duplicate(true), "order": _order.duplicate(), "links": _found.duplicate(true)}


func deserialize(d: Dictionary) -> void:
	_entries = d.get("entries", {}).duplicate(true)
	_order = d.get("order", []).duplicate()
	_found.clear()
	var saved: Dictionary = d.get("links", {})
	for lid in saved:
		if _link_defs.has(lid):  # a link dropped from the data is quietly forgotten
			_found[lid] = {"day": int(saved[lid].get("day", 1)), "source": saved[lid].get("source", ""),
					"understood": bool(saved[lid].get("understood", false))}
	for id in _entries:
		_entries[id]["day"] = int(_entries[id].get("day", 1))
