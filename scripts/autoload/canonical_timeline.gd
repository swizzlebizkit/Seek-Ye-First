extends Node
## System A: the Canonical Timeline. Major biblical events, scheduled by the world clock.
##
## Hybrid model. Every event has a schedule (data/canon/events.json, schema v2, docs/chronology.md): a
## start worked out from the calendar and from its dependencies, and a duration. WorldSim drives time;
## each time it advances it calls sync_to(), and every event whose start (or end) has passed is marked
## and announced, in time order, even after a very large jump. Nothing the player does, no quest and no
## story flag can start, delay, reorder or alter an event: story_advance() refuses canonical ids. The
## player can only be in the right place at the right time, which is what the access API below answers.
##
## All times are world minutes (Calendar.world_minutes): minutes since the start of WorldSim day 1.

signal event_occurred(event_id: String)  ## An event has begun (the original signal, kept for compatibility).
signal event_completed(event_id: String)  ## Its duration has run out.

const NEVER := 1.0e18
const EPS := 0.0001
const DATA_PATH := "res://data/canon/events.json"
const PROTAGONIST := "protagonist"

var _events: Dictionary = {}
var _order: Array = []
var _occurred: Dictionary = {}  # id -> true, once the event has begun
var _completed: Dictionary = {}  # id -> true, once it has ended
var _sched: Dictionary = {}  # id -> {"start", "end", "rank"} in world minutes (NEVER when unschedulable)
var _bounds: Array = []  # sorted [{"t", "kind", "id"}]
var _sched_key := -1
var _syncing := false


func _ready() -> void:
	var data = DataFiles.load_json(DATA_PATH)
	if data is Dictionary:
		load_events(data.get("events", []))


## Replaces the event set (the default data at start-up; tests use it for other sets). Clears state.
func load_events(list: Array) -> void:
	_events.clear()
	_order.clear()
	_occurred.clear()
	_completed.clear()
	var sorted := list.duplicate(true)
	sorted.sort_custom(func(a, b): return a["order"] < b["order"])
	for e in sorted:
		if not e.has("title"):
			e["title"] = e.get("name", e["id"])  # the v1 key, kept for compatibility
		_events[e["id"]] = e
		_order.append(e["id"])
	_sched_key = -1


func has_event(id: String) -> bool:
	return _events.has(id)


func get_event(id: String) -> Dictionary:
	return _events.get(id, {}).duplicate(true)


func event_ids() -> Array:
	return _order.duplicate()


## True once the event has begun (and stays true after it ends).
func has_occurred(id: String) -> bool:
	return _occurred.get(id, false)


func is_completed(id: String) -> bool:
	return _completed.get(id, false)


func occurred_ids() -> Array:
	return _occurred.keys()


## Canonical events cannot be advanced from story code: the clock does it. Kept so existing callers
## compile; it changes nothing and always returns false.
func story_advance(id: String) -> bool:
	if _events.has(id) and not _occurred.has(id):
		push_warning("story_advance('%s') refused: canonical events are driven by world time only" % id)
	return false


# -- the schedule ------------------------------------------------------------------------------
## When an event starts, in world minutes (NEVER if it cannot be placed, e.g. no baptism anchor).
func scheduled_start(id: String) -> float:
	_ensure_schedule()
	return float(_sched.get(id, {}).get("start", NEVER))


func scheduled_end(id: String) -> float:
	_ensure_schedule()
	return float(_sched.get(id, {}).get("end", NEVER))


## The calendar day an event starts on (0 if unscheduled).
func scheduled_calendar_day(id: String) -> int:
	var s := scheduled_start(id)
	if s >= NEVER:
		return 0
	var day := int(floor(s / 1440.0)) + 1
	return Calendar.calendar_day(day, s - float(day - 1) * 1440.0)


## Days since the baptism at which the event starts (negative before it).
func scheduled_ministry_day(id: String) -> int:
	var s := scheduled_start(id)
	if s >= NEVER or not Calendar.has_ministry_clock():
		return 0
	return int(floor(Calendar.ministry_minutes(s) / 1440.0))


## The first scheduled moment strictly after `now` at which an event starts or ends (NEVER if none).
## WorldSim uses it so the clock stops exactly there instead of stepping over it.
func next_boundary(now: float) -> float:
	_ensure_schedule()
	for b in _bounds:
		if float(b["t"]) > now + EPS:
			return float(b["t"])
	return NEVER


## Brings state up to `now`: starts and ends every event that is due, in time order, one signal each.
## Safe for any jump size; calling it again with the same or an earlier time does nothing.
func sync_to(now: float) -> void:
	if _syncing:
		return
	_ensure_schedule()
	_syncing = true
	for b in _bounds:
		if float(b["t"]) > now + EPS:
			break
		var id: String = b["id"]
		if b["kind"] == "start":
			_begin(id)
		else:
			_begin(id)
			if not _completed.has(id):
				_completed[id] = true
				event_completed.emit(id)
	_syncing = false


func _begin(id: String) -> void:
	if _occurred.has(id):
		return
	_occurred[id] = true
	_apply_outcomes(_events[id])
	event_occurred.emit(id)


## The only route by which canonical outcomes reach characters: always with source "timeline".
func _apply_outcomes(e: Dictionary) -> void:
	var protection := get_node_or_null("/root/CanonicalProtection")
	for o in e.get("outcomes", []):
		if protection == null:
			push_warning("CanonicalProtection is not available; outcome for '%s' not applied" % o.get("character_id", "?"))
			continue
		protection.call("apply_outcome", str(o["character_id"]), str(o["outcome"]), "timeline")


func _ensure_schedule() -> void:
	if _sched_key == Calendar.config_version:
		return
	_sched_key = Calendar.config_version
	_sched.clear()
	var rank := [0]
	for id in _order:
		_resolve(id, [], rank)
	_bounds.clear()
	for id in _order:
		var s: Dictionary = _sched[id]
		if float(s["start"]) >= NEVER:
			continue
		_bounds.append({"t": s["start"], "kind": "start", "id": id, "rank": s["rank"]})
		_bounds.append({"t": s["end"], "kind": "end", "id": id, "rank": s["rank"]})
	# Ends come before starts at the same moment, then dependency order, so a dependent never precedes its cause.
	_bounds.sort_custom(func(a, b):
		if a["t"] != b["t"]:
			return a["t"] < b["t"]
		if a["kind"] != b["kind"]:
			return a["kind"] == "end"
		return a["rank"] < b["rank"])


func _resolve(id: String, stack: Array, rank: Array) -> Dictionary:
	if _sched.has(id):
		return _sched[id]
	var unplaced := {"start": NEVER, "end": NEVER, "rank": rank[0]}
	if stack.has(id) or not _events.has(id):
		return unplaced  # a cycle or an unknown id: the validator reports it; here it just never fires
	stack.append(id)
	var e: Dictionary = _events[id]
	var constraint := -NEVER
	for d in e.get("dependencies", []):
		var dep := _resolve(str(d["id"]), stack, rank)
		var ref := float(dep["start"] if d["relation"] == "after_start" else dep["end"])
		if ref >= NEVER:
			constraint = NEVER
			break
		constraint = maxf(constraint, ref + float(d.get("gap_days", 0.0)) * 1440.0)
	stack.pop_back()
	var sch: Dictionary = e["schedule"]
	var start := NEVER
	if constraint < NEVER:
		match sch["mode"]:
			"opening_offset":
				start = maxf(Calendar.world_minutes(1, float(Calendar.start_minute)) + float(sch["days"]) * 1440.0, constraint)
			"ministry_offset":
				if Calendar.has_ministry_clock():
					start = maxf(Calendar.baptism_minutes() + float(sch["days"]) * 1440.0, constraint)
			"after_dependencies":
				start = constraint if constraint > -NEVER else NEVER
			"festival":
				start = _festival_start(str(sch["festival"]), float(sch.get("minute", 540)), constraint)
	var out := {"start": start, "end": NEVER, "rank": rank[0]}
	rank[0] += 1
	if start < NEVER:
		out["end"] = start + _duration_minutes(e["duration"])
	_sched[id] = out
	return out


## The first occurrence of a festival whose start is not before `constraint` (world minutes).
func _festival_start(festival: String, minute: float, constraint: float) -> float:
	var first_year := int(Calendar.date(1)["year"])
	for y in range(first_year, first_year + 40):
		var f: Dictionary = Calendar.festivals_in_year(y).get(festival, {})
		if f.is_empty():
			continue
		var t := Calendar.world_minutes(int(f["start"]), minute)
		if t >= constraint:
			return t
	return NEVER


func _duration_minutes(d: Dictionary) -> float:
	var unit := 1440.0
	match d["unit"]:
		"minutes":
			unit = 1.0
		"hours":
			unit = 60.0
	return float(d["amount"]) * unit


# -- access classes and arrival states (what the protagonist can legitimately witness) ----------
## "before", "during" or "after" for an arrival at world minute `at` (default: now);
## "unscheduled" when the event cannot be placed on the calendar.
func arrival_state(id: String, at: float = NEVER) -> String:
	var s := scheduled_start(id)
	if s >= NEVER:
		return "unscheduled"
	var t := _now() if at >= NEVER else at
	if t < s - EPS:
		return "before"
	return "during" if t < scheduled_end(id) - EPS else "after"


## Where the event takes place. Fixed by the data: the player's position never moves it.
func event_location(id: String) -> String:
	return str(_events.get(id, {}).get("location", ""))


## Everything about whether `observer` at `location` can witness the event at world minute `at`:
## {state, access, present, listed, observation ("none", "partial", "full"), can_witness, reason}.
##   public:     anyone present while it is under way sees it, but only listed participants and witnesses
##               take it in fully; a bystander gets a partial view.
##   restricted: only its scriptural participants and witnesses can; being near is not enough.
##   private:    never witnessable by anyone but the people in it, and never by the protagonist.
## Nothing here moves or blocks an event; a knowledgeable early arrival who waits sees a public event.
func witness_report(id: String, observer: String, location: String, at: float = NEVER) -> Dictionary:
	var r := {"state": "unscheduled", "access": "", "present": false, "listed": false, "observation": "none",
			"can_witness": false, "reason": "unknown event"}
	if not _events.has(id):
		return r
	var e: Dictionary = _events[id]
	r["access"] = e["access"]
	r["state"] = arrival_state(id, at)
	r["present"] = location != "" and location == e["location"]
	r["listed"] = e["participants"].has(observer) or e["witnesses"].has(observer)
	if r["state"] != "during":
		r["reason"] = "the event is %s" % r["state"]
	elif not r["present"]:
		r["reason"] = "not at the place"
	elif e["access"] == "private":
		r["reason"] = "private: no one else can witness it"
	elif e["access"] == "restricted" and not r["listed"]:
		r["reason"] = "restricted to those in it"
	else:
		r["observation"] = "full" if r["listed"] else "partial"
		r["can_witness"] = true
		r["reason"] = "present while it happened"
	return r


func can_witness(id: String, observer: String = PROTAGONIST, location: String = "", at: float = NEVER) -> bool:
	return witness_report(id, observer, location, at)["can_witness"]


## Records the protagonist's witnessing in PlayerKnowledge if (and only if) it is legitimate.
## It never touches the event itself.
func witness(id: String, location: String, at: float = NEVER) -> bool:
	if not can_witness(id, PROTAGONIST, location, at):
		return false
	PlayerKnowledge.learn(id, "witnessed", "witness")
	return true


func _now() -> float:
	return Calendar.world_minutes(WorldSim.day, WorldSim.minute_of_day)


# -- state -------------------------------------------------------------------------------------
## Back to the game opening: events that are already under way when the game opens (John's preaching)
## are marked, nothing else.
func reset() -> void:
	_occurred.clear()
	_completed.clear()
	sync_to(Calendar.world_minutes(1, float(Calendar.start_minute)))


func serialize() -> Dictionary:
	return {"occurred": _occurred.keys(), "completed": _completed.keys()}


## Old saves have only "occurred"; they load as they were. Time then fills in anything now due.
func deserialize(d: Dictionary) -> void:
	_occurred.clear()
	_completed.clear()
	for id in d.get("occurred", []):
		_occurred[id] = true
	for id in d.get("completed", []):
		_completed[id] = true
