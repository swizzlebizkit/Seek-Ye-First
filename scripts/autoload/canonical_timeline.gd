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
## THE BAPTISM EXCEPTION. Jesus' baptism is the sole player-arrival-triggered canonical event. Until the
## player reaches the designated place and trigger_baptism() accepts it, the ministry chronology has not
## begun: the baptism and every event that depends on it are unscheduled (start NEVER), the scheduler is
## idle, and the world clock and calendar run normally (nothing is frozen or adjusted). The call records the
## actual world minute as ministry Day 0, once and for good, and from then on every event follows the
## world simulation whatever the protagonist does or knows. The protagonist does not cause the baptism;
## their arrival triggers the game's representation of an event Scripture establishes independently.
## Festivals stay on their fixed calendar dates: a late baptism simply selects a later Passover.
##
## All times are world minutes (Calendar.world_minutes): minutes since the start of WorldSim day 1.

signal event_occurred(event_id: String)  ## An event has begun (the original signal, kept for compatibility).
signal event_completed(event_id: String)  ## Its duration has run out.
signal baptism_recorded(world_minutes: float)  ## The baptism trigger was accepted: ministry Day 0 now exists.

const NEVER := 1.0e18
const EPS := 0.0001
const DATA_PATH := "res://data/canon/events.json"
const PROTAGONIST := "protagonist"
const BAPTISM_EVENT := "baptism_of_jesus"
const FIRST_PASSOVER_EVENT := "passover_jerusalem"
const PASSION_PASSOVER_EVENT := "passion_passover"
const LONG_WAIT_DAYS := 150  ## a first-Passover wait longer than this is flagged for chronology review

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
			"player_arrival":
				# The recorded moment of the trigger IS ministry Day 0; it is never placed by data.
				if Calendar.has_ministry_clock():
					start = Calendar.baptism_minutes()
			"after_dependencies":
				start = constraint if constraint > -NEVER else NEVER
			"festival":
				start = _festival_start(str(sch["festival"]), float(sch.get("minute", 540)), constraint)
	var out := {"start": start, "end": NEVER, "rank": rank[0], "constraint": constraint}
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


# -- the baptism trigger (the Baptism Exception) ---------------------------------------------------
## True once the baptism has been recorded. It stays true for the rest of the game and across saves.
func baptism_recorded_yet() -> bool:
	return Calendar.has_ministry_clock()


## The one player-arrival-triggered canonical event. `location` is the place the player's arrival
## trigger is bound to; it must be the baptism's own location (event_location). Accepted at most once:
## it records the CURRENT world minute as ministry Day 0, rebuilds the schedule from it and announces the
## baptism (and anything else now due) in order. Returns false, changing nothing, when the baptism has
## already been recorded, the event is not in the data, or the location is not the designated one.
## Merely entering a region, talking to John or reaching a calendar date never calls this.
func trigger_baptism(location: String) -> bool:
	if Calendar.has_ministry_clock() or not _events.has(BAPTISM_EVENT):
		return false
	if location == "" or location != event_location(BAPTISM_EVENT):
		return false
	var now := _now()
	Calendar.set_ministry_start(now)
	_sched_key = -1
	baptism_recorded.emit(now)
	sync_to(now)
	return true


## Which calendar Passover the first Jerusalem Passover event landed on, and what that choice cost:
## {} until it can be placed (before the baptism), otherwise {calendar_day, date, ministry_day,
## baptism_to_passover_days, wait_days (idle days between the preceding events plus travel and the
## Passover), skipped_count (calendar Passovers that fell after the baptism but before it), skipped_days
## (their calendar days), certainty}. The ORDER (Cana, Capernaum, then a Passover) is explicit in John
## 2:1-13; which Passover and which date is a simulation choice, so certainty is "simulated".
func first_passover_selection() -> Dictionary:
	_ensure_schedule()
	var s: Dictionary = _sched.get(FIRST_PASSOVER_EVENT, {})
	if s.is_empty() or float(s.get("start", NEVER)) >= NEVER or not Calendar.has_ministry_clock():
		return {}
	var start := float(s["start"])
	var minute := float(_events[FIRST_PASSOVER_EVENT]["schedule"].get("minute", 540))
	var skipped: Array = []
	var first_year := int(Calendar.date(1)["year"])
	for y in range(first_year, first_year + 40):
		var f: Dictionary = Calendar.festivals_in_year(y).get("passover", {})
		if f.is_empty():
			continue
		var t := Calendar.world_minutes(int(f["start"]), minute)
		if t >= start - EPS:
			break
		if t >= Calendar.baptism_minutes():
			skipped.append(int(f["start"]))
	var cday := scheduled_calendar_day(FIRST_PASSOVER_EVENT)
	var constraint := float(s.get("constraint", -NEVER))
	return {"calendar_day": cday, "date": Calendar.full_date_string(cday), "ministry_day": scheduled_ministry_day(FIRST_PASSOVER_EVENT),
			"baptism_to_passover_days": int(floor((start - Calendar.baptism_minutes()) / 1440.0)),
			"wait_days": int(floor((start - constraint) / 1440.0)) if constraint > -NEVER else 0,
			"skipped_count": skipped.size(), "skipped_days": skipped, "certainty": "simulated"}


## Items that need chronology review. The first Passover choice must never silently redefine the length of
## the ministry: when it had to skip a Passover, or while the Passion Passover is not in the data, this says so.
## Each is {id, severity ("info" or "warning"), message, ...}.
func chronology_flags() -> Array:
	var out: Array = []
	if not _events.has(PASSION_PASSOVER_EVENT):
		out.append({"id": "passion_passover_unreconciled", "severity": "info",
				"message": "The Passion Passover is not in the chronology yet. The first Passover choice fixes where the ministry begins on the calendar; once the later Passovers are built, the total length of the ministry must be reconciled with it by chronology review."})
	var sel := first_passover_selection()
	if not sel.is_empty() and int(sel["skipped_count"]) > 0:
		out.append({"id": "first_passover_skipped", "severity": "warning", "skipped_count": sel["skipped_count"],
				"skipped_days": sel["skipped_days"], "selected_calendar_day": sel["calendar_day"], "selected_date": sel["date"],
				"baptism_to_passover_days": sel["baptism_to_passover_days"],
				"message": "A late baptism skipped %d calendar Passover(s); the first Jerusalem Passover is %s, %d days after the baptism. The ministry now runs a year later on the calendar than an earlier baptism would; review against the Passion Passover." % [int(sel["skipped_count"]), sel["date"], int(sel["baptism_to_passover_days"])]})
	if not sel.is_empty() and int(sel["wait_days"]) > LONG_WAIT_DAYS:
		out.append({"id": "first_passover_long_wait", "severity": "warning", "wait_days": sel["wait_days"], "selected_date": sel["date"],
				"baptism_to_passover_days": sel["baptism_to_passover_days"],
				"message": "The first Jerusalem Passover (%s) falls %d days after the baptism and waits %d days past the end of the preceding events. John 2:12-13 reads as a short interval; the calendar fixes Passover, so the whole ministry now sits that much later. Review against the Passion Passover." % [sel["date"], int(sel["baptism_to_passover_days"]), int(sel["wait_days"])]})
	return out


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
## Back to the game opening: no baptism has happened. Events that are already under way when the game
## opens (John's preaching) are marked, nothing else.
func reset() -> void:
	_occurred.clear()
	_completed.clear()
	Calendar.clear_ministry_start()
	_sched_key = -1
	sync_to(Calendar.world_minutes(1, float(Calendar.start_minute)))


## "baptism_minutes" appears only once the baptism has been recorded.
func serialize() -> Dictionary:
	var d := {"occurred": _occurred.keys(), "completed": _completed.keys()}
	if Calendar.has_ministry_clock():
		d["baptism_minutes"] = Calendar.baptism_minutes()
	return d


## Old saves have only "occurred" and no baptism record: they load as before the baptism, so any event
## that cannot be placed without it is dropped (a stale save cannot show the ministry without Day 0).
## Time then fills in anything now due.
func deserialize(d: Dictionary) -> void:
	_occurred.clear()
	_completed.clear()
	if d.has("baptism_minutes"):
		Calendar.set_ministry_start(float(d["baptism_minutes"]))
	else:
		Calendar.clear_ministry_start()
	_sched_key = -1
	_ensure_schedule()
	for id in d.get("occurred", []):
		if scheduled_start(str(id)) < NEVER:
			_occurred[id] = true
	for id in d.get("completed", []):
		if scheduled_start(str(id)) < NEVER:
			_completed[id] = true
