extends Node
## System C: Player Knowledge. What the *protagonist* has heard, been told or witnessed.
##
## This is separate from the Canonical Timeline (what happened) and from what the human player
## already knows. An event can have occurred without the protagonist knowing anything about it.

const LEVELS := ["unknown", "rumor", "testimony", "witnessed"]

var _facts: Dictionary = {}  # event_id -> {"level": String, "sources": [String]}
var _understood: Dictionary = {}  # event_id -> true (the protagonist grasps its significance)


func learn(event_id: String, level: String, source: String = "") -> void:
	if not CanonicalTimeline.has_event(event_id):
		push_warning("PlayerKnowledge.learn: unknown canon event '%s'" % event_id)
		return
	if not LEVELS.has(level):
		push_warning("PlayerKnowledge.learn: unknown level '%s'" % level)
		return
	var fact: Dictionary = _facts.get(event_id, {"level": "unknown", "sources": []})
	if LEVELS.find(level) > LEVELS.find(fact["level"]):
		fact["level"] = level
	if source != "" and not fact["sources"].has(source):
		fact["sources"].append(source)
	_facts[event_id] = fact


func level_of(event_id: String) -> String:
	return _facts.get(event_id, {}).get("level", "unknown")


func knows(event_id: String, min_level: String = "rumor") -> bool:
	return LEVELS.find(level_of(event_id)) >= LEVELS.find(min_level)


func sources_of(event_id: String) -> Array:
	return _facts.get(event_id, {}).get("sources", []).duplicate()


func mark_understood(event_id: String) -> void:
	_understood[event_id] = true


func understands(event_id: String) -> bool:
	return _understood.get(event_id, false)


func reset() -> void:
	_facts.clear()
	_understood.clear()


func serialize() -> Dictionary:
	return {"facts": _facts.duplicate(true), "understood": _understood.keys()}


func deserialize(d: Dictionary) -> void:
	_facts = d.get("facts", {}).duplicate(true)
	_understood.clear()
	for id in d.get("understood", []):
		_understood[id] = true
