extends Node
## Canonical-character protection: a gameplay safeguard that keeps the protagonist's combat from
## touching historically identified individuals or disrupting scripture-established events. The
## registry is data (data/canon/characters.json); no character name appears in code. Scripture-
## established outcomes (death, injury, arrest) are applied only by the canonical timeline through
## apply_outcome(). Nothing here confiscates equipment; it only gates combat actions.

signal restriction_changed(restricted: bool)
signal outcome_applied(character_id: String, outcome: String)

const FIELDS := ["display_name", "canonical_character", "combat_protected", "protected_event", "combat_restriction_radius"]
const OUTCOMES := ["death", "injury", "arrest"]
const TIMELINE := "timeline"
const HINT_TEXT := "Combat unavailable"

var registry: Dictionary = {}  # character id -> validated entry
var presence: Dictionary = {}  # character id -> world position of a present canonical character
var areas: Dictionary = {}  # area id -> {"center": Vector2, "radius": float, "event": String}
var active_events: Dictionary = {}  # protected event id -> true
var applied: Dictionary = {}  # character id -> outcome (timeline-applied)
var restricted := false


func _ready() -> void:
	var d = DataFiles.load_json("res://data/canon/characters.json")
	if d is Dictionary:
		registry = load_registry(d.get("characters", {}))


## Validates and returns the registry; invalid entries are rejected loudly.
static func load_registry(raw: Dictionary) -> Dictionary:
	var out := {}
	for id in raw:
		var err := validate_entry(raw[id])
		if err != "":
			push_error("Canon character '%s' rejected: %s" % [id, err])
			continue
		out[String(id)] = raw[id].duplicate(true)
	return out


## Returns "" if the entry is acceptable, else the reason it is not.
static func validate_entry(e: Variant) -> String:
	if not e is Dictionary:
		return "not a dictionary"
	for k in e:
		if not FIELDS.has(k):
			return "unknown field '%s'" % k
	if not e.has("combat_restriction_radius"):
		return "missing combat_restriction_radius"
	var r = e["combat_restriction_radius"]
	if not (r is float or r is int) or float(r) < 0.0:
		return "bad combat_restriction_radius"
	if e.get("canonical_character", false) != true:
		return "canonical_character must be true"
	if not e.has("combat_protected") or not e["combat_protected"] is bool:
		return "missing combat_protected"
	if e.has("protected_event") and not e["protected_event"] is String:
		return "bad protected_event"
	return ""


# -- lookup ------------------------------------------------------------------------------------
func is_canonical(id: String) -> bool:
	return registry.has(id)


func is_protected(id: String) -> bool:
	return registry.has(id) and bool(registry[id]["combat_protected"])


func radius_of(id: String) -> float:
	return float(registry.get(id, {}).get("combat_restriction_radius", 0.0))


func protected_event_of(id: String) -> String:
	return String(registry.get(id, {}).get("protected_event", ""))


# -- presence, areas and events ----------------------------------------------------------------
func set_presence(id: String, pos: Vector2) -> void:
	if is_protected(id):
		presence[id] = pos


func clear_presence(id: String) -> void:
	presence.erase(id)


## A protected area not tied to a character, e.g. a scripted scene. `event` may be "".
func set_area(area_id: String, center: Vector2, radius: float, event: String = "") -> void:
	areas[area_id] = {"center": center, "radius": radius, "event": event}


func clear_area(area_id: String) -> void:
	areas.erase(area_id)


func begin_event(event_id: String) -> void:
	active_events[event_id] = true


func end_event(event_id: String) -> void:
	active_events.erase(event_id)


func is_event_active(event_id: String) -> bool:
	return active_events.has(event_id)


## Combat of any kind can never disrupt an active protected event.
func combat_can_disrupt(event_id: String) -> bool:
	return not active_events.has(event_id)


# -- restriction -------------------------------------------------------------------------------
## True if offensive combat is unavailable at this world position.
func restricted_at(pos: Vector2) -> bool:
	for id in presence:
		if pos.distance_to(presence[id]) <= radius_of(id):
			return true
	for a in areas.values():
		if pos.distance_to(a["center"]) <= float(a["radius"]):
			return true
	return false


## Re-evaluates the player's restriction; emits on change. Returns the new state.
func update_restriction(pos: Vector2) -> bool:
	var r := restricted_at(pos)
	if r != restricted:
		restricted = r
		restriction_changed.emit(r)
	return r


# -- damage and outcomes -----------------------------------------------------------------------
## Whether anything ordinary may damage, rout, provoke or otherwise affect this actor in combat.
func can_be_harmed(actor_id: String) -> bool:
	return not is_protected(actor_id)


## Scripture-established outcome, applied only by the canonical timeline. Returns true if applied.
func apply_outcome(character_id: String, outcome: String, source: String) -> bool:
	if source != TIMELINE:
		push_warning("Outcome '%s' for '%s' refused: source '%s' is not the timeline" % [outcome, character_id, source])
		return false
	if not registry.has(character_id) or not OUTCOMES.has(outcome):
		push_warning("Unknown canonical outcome '%s' for '%s'" % [outcome, character_id])
		return false
	applied[character_id] = outcome
	if outcome == "death":
		Combat.actors[character_id] = {"status": "dead", "hp": 0}
		clear_presence(character_id)
	outcome_applied.emit(character_id, outcome)
	return true


func outcome_of(character_id: String) -> String:
	return applied.get(character_id, "")


# -- persistence -------------------------------------------------------------------------------
func reset() -> void:
	presence.clear()
	areas.clear()
	active_events.clear()
	applied.clear()
	if restricted:
		restricted = false
		restriction_changed.emit(false)


func serialize() -> Dictionary:
	var a := {}
	for k in areas:
		a[k] = {"x": areas[k]["center"].x, "y": areas[k]["center"].y, "radius": areas[k]["radius"], "event": areas[k]["event"]}
	var p := {}
	for k in presence:
		p[k] = [presence[k].x, presence[k].y]
	return {"events": active_events.keys(), "applied": applied.duplicate(), "areas": a,
		"presence": p, "restricted": restricted}


## A missing block (older save) restores defaults.
func deserialize(d: Dictionary) -> void:
	reset()
	for e in d.get("events", []):
		active_events[String(e)] = true
	for k in d.get("applied", {}):
		if OUTCOMES.has(String(d["applied"][k])):
			applied[String(k)] = String(d["applied"][k])
	for k in d.get("areas", {}):
		var a: Dictionary = d["areas"][k]
		areas[String(k)] = {"center": Vector2(float(a.get("x", 0)), float(a.get("y", 0))),
			"radius": float(a.get("radius", 0)), "event": String(a.get("event", ""))}
	for k in d.get("presence", {}):
		if is_protected(String(k)):
			presence[String(k)] = Vector2(float(d["presence"][k][0]), float(d["presence"][k][1]))
	if bool(d.get("restricted", false)) != restricted:
		restricted = bool(d.get("restricted", false))
		restriction_changed.emit(restricted)
