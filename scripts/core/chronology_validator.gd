extends RefCounted
## Validator for the canonical event schema v2 (docs/chronology.md). Returns a list of problems; an empty
## list means the document is valid. It checks structure only: it never reads or changes game state.

const CERTAINTY := ["explicit", "inferred", "simulated"]
const ACCESS := ["public", "restricted", "private"]
const RELATIONS := ["after_start", "after_end"]
const MODES := ["opening_offset", "ministry_offset", "after_dependencies", "festival"]
const UNITS := ["minutes", "hours", "days"]
const BASES := ["scripture", "estimate"]
const OUTCOMES := ["death", "injury", "arrest"]

const DOC_KEYS := ["note", "schema_version", "preliminary_harmonization", "harmonization_note", "ministry", "events"]
const REQUIRED := ["id", "order", "name", "origin", "refs", "certainty", "access", "location", "dependencies", "schedule",
		"duration", "participants", "witnesses", "traveling_party", "rumor_sources", "testimony_sources", "significance"]
const OPTIONAL := ["notes", "outcomes"]
const SCHEDULE_KEYS := ["mode", "days", "gap_days", "festival", "minute", "certainty", "note", "window_days"]
const DURATION_KEYS := ["amount", "unit", "basis", "certainty", "min", "max", "note"]
const DEP_KEYS := ["id", "relation", "certainty", "gap_days"]
const LIST_FIELDS := ["participants", "witnesses", "traveling_party", "rumor_sources", "testimony_sources"]

var _errs: Array = []
var _location_ids: Array = []
var _festival_ids: Array = []


## doc is the parsed events.json. locations/festivals default to the live game data.
func validate_doc(doc: Dictionary, location_ids: Array = [], festival_ids: Array = []) -> Array:
	_errs = []
	_location_ids = location_ids if not location_ids.is_empty() else _load_location_ids()
	_festival_ids = festival_ids if not festival_ids.is_empty() else Calendar.festival_config.get("festivals", {}).keys()
	for k in doc:
		if not DOC_KEYS.has(k):
			_err("document: unknown field '%s'" % k)
	if int(doc.get("schema_version", 0)) != 2:
		_err("document: schema_version must be 2")
	if not doc.get("preliminary_harmonization", null) is bool:
		_err("document: preliminary_harmonization must be a bool")
	_check_ministry(doc.get("ministry", null))
	var events = doc.get("events", null)
	if not events is Array or events.is_empty():
		_err("document: events must be a non-empty list")
		return _errs
	validate_events(events, false)
	return _errs


## Validates just a list of events (also resets the error list unless called from validate_doc).
func validate_events(events: Array, fresh: bool = true, location_ids: Array = [], festival_ids: Array = []) -> Array:
	if fresh:
		_errs = []
		_location_ids = location_ids if not location_ids.is_empty() else _load_location_ids()
		_festival_ids = festival_ids if not festival_ids.is_empty() else Calendar.festival_config.get("festivals", {}).keys()
	var ids: Dictionary = {}
	var orders: Dictionary = {}
	for e in events:
		if e is Dictionary and e.get("id", null) is String:
			if ids.has(e["id"]):
				_err("duplicate event id '%s'" % e["id"])
			ids[e["id"]] = e
			if e.has("order"):
				if orders.has(int(e["order"])):
					_err("%s: duplicate order %d" % [e["id"], int(e["order"])])
				orders[int(e["order"])] = true
	for e in events:
		if not e is Dictionary:
			_err("event is not an object")
			continue
		_check_event(e, ids)
	_check_cycles(ids)
	return _errs


func _check_event(e: Dictionary, ids: Dictionary) -> void:
	var w := str(e.get("id", "?"))
	for k in REQUIRED:
		if not e.has(k):
			_err("%s: missing field '%s'" % [w, k])
	for k in e:
		if not REQUIRED.has(k) and not OPTIONAL.has(k):
			_err("%s: unknown field '%s'" % [w, k])
	if not e.get("id", null) is String or str(e.get("id", "")) == "":
		_err("%s: id must be a non-empty string" % w)
	if not (e.get("order", null) is int or e.get("order", null) is float):
		_err("%s: order must be a number" % w)
	for k in ["name", "origin", "significance"]:
		if e.has(k) and (not e[k] is String or e[k] == ""):
			_err("%s: %s must be a non-empty string" % [w, k])
	_enum(w, "certainty", e.get("certainty", null), CERTAINTY, e.has("certainty"))
	_enum(w, "access", e.get("access", null), ACCESS, e.has("access"))
	if e.has("refs"):
		var refs = e["refs"]
		if not refs is Array or refs.is_empty():
			_err("%s: refs must be a non-empty list" % w)
		else:
			for r in refs:
				if not r is String or not Scripture.is_complete(r):
					_err("%s: ref '%s' is not complete in the KJV data" % [w, str(r)])
	if e.has("location") and not _location_ids.has(e["location"]):
		_err("%s: unknown location id '%s'" % [w, str(e["location"])])
	for k in LIST_FIELDS:
		if e.has(k):
			if not e[k] is Array:
				_err("%s: %s must be a list" % [w, k])
			elif e[k].any(func(x): return not x is String or x == ""):
				_err("%s: %s must hold non-empty strings" % [w, k])
	if e.get("participants", []) is Array and e.has("participants") and e["participants"].is_empty():
		_err("%s: participants must not be empty" % w)
	if e.get("access", "") == "private" and e.get("witnesses", []) is Array and not e["witnesses"].is_empty():
		_err("%s: a private event cannot list witnesses" % w)
	_check_deps(w, e, ids)
	_check_schedule(w, e)
	_check_duration(w, e)
	if e.has("notes") and not e["notes"] is String:
		_err("%s: notes must be a string" % w)
	if e.has("outcomes"):
		if not e["outcomes"] is Array:
			_err("%s: outcomes must be a list" % w)
		else:
			for o in e["outcomes"]:
				if not o is Dictionary or str(o.get("character_id", "")) == "" or not OUTCOMES.has(o.get("outcome", null)):
					_err("%s: each outcome needs a character_id and an outcome of %s" % [w, str(OUTCOMES)])


func _check_deps(w: String, e: Dictionary, ids: Dictionary) -> void:
	if not e.has("dependencies"):
		return
	if not e["dependencies"] is Array:
		_err("%s: dependencies must be a list" % w)
		return
	for d in e["dependencies"]:
		if not d is Dictionary:
			_err("%s: a dependency is not an object" % w)
			continue
		for k in d:
			if not DEP_KEYS.has(k):
				_err("%s: dependency has unknown field '%s'" % [w, k])
		for k in ["id", "relation", "certainty"]:
			if not d.has(k):
				_err("%s: dependency is missing '%s'" % [w, k])
		if d.has("id") and not ids.has(d["id"]):
			_err("%s: dependency on unknown event '%s'" % [w, str(d["id"])])
		if d.get("id", null) == e.get("id", null):
			_err("%s: depends on itself" % w)
		_enum(w + " dependency", "relation", d.get("relation", null), RELATIONS, d.has("relation"))
		_enum(w + " dependency", "certainty", d.get("certainty", null), CERTAINTY, d.has("certainty"))
		if d.has("gap_days") and not _num(d["gap_days"]):
			_err("%s: dependency gap_days must be a number" % w)


func _check_schedule(w: String, e: Dictionary) -> void:
	if not e.has("schedule"):
		return
	var s = e["schedule"]
	if not s is Dictionary:
		_err("%s: schedule must be an object" % w)
		return
	for k in s:
		if not SCHEDULE_KEYS.has(k):
			_err("%s: schedule has unknown field '%s'" % [w, k])
	_enum(w + " schedule", "mode", s.get("mode", null), MODES, s.has("mode"))
	_enum(w + " schedule", "certainty", s.get("certainty", null), CERTAINTY, s.has("certainty"))
	match s.get("mode", ""):
		"opening_offset", "ministry_offset":
			if not _num(s.get("days", null)):
				_err("%s: schedule.days must be a number for mode %s" % [w, str(s["mode"])])
		"festival":
			if not _festival_ids.has(s.get("festival", null)):
				_err("%s: schedule.festival '%s' is not a known festival" % [w, str(s.get("festival", ""))])
		"after_dependencies":
			if not e.get("dependencies", []) is Array or e.get("dependencies", []).is_empty():
				_err("%s: mode after_dependencies needs at least one dependency" % w)
	if s.has("window_days"):
		var win = s["window_days"]
		if not win is Dictionary or not _num(win.get("earliest", null)) or not _num(win.get("latest", null)) \
				or float(win["earliest"]) > 0.0 or float(win["latest"]) < 0.0:
			_err("%s: schedule.window_days needs earliest <= 0 <= latest" % w)


func _check_duration(w: String, e: Dictionary) -> void:
	if not e.has("duration"):
		return
	var d = e["duration"]
	if not d is Dictionary:
		_err("%s: duration must be an object" % w)
		return
	for k in d:
		if not DURATION_KEYS.has(k):
			_err("%s: duration has unknown field '%s'" % [w, k])
	for k in ["amount", "unit", "basis", "certainty", "min", "max"]:
		if not d.has(k):
			_err("%s: duration is missing '%s'" % [w, k])
	_enum(w + " duration", "unit", d.get("unit", null), UNITS, d.has("unit"))
	_enum(w + " duration", "basis", d.get("basis", null), BASES, d.has("basis"))
	_enum(w + " duration", "certainty", d.get("certainty", null), CERTAINTY, d.has("certainty"))
	if _num(d.get("amount", null)) and _num(d.get("min", null)) and _num(d.get("max", null)):
		if float(d["amount"]) <= 0.0:
			_err("%s: duration.amount must be positive" % w)
		if float(d["min"]) > float(d["amount"]) or float(d["amount"]) > float(d["max"]):
			_err("%s: duration needs min <= amount <= max" % w)
	elif d.has("amount") and d.has("min") and d.has("max"):
		_err("%s: duration amount, min and max must be numbers" % w)
	if d.get("basis", "") == "estimate" and d.get("certainty", "") == "explicit":
		_err("%s: a gameplay estimate cannot be certainty explicit" % w)


func _check_ministry(m) -> void:
	if not m is Dictionary:
		_err("document: ministry must be an object")
		return
	for k in m:
		if not ["span_years", "passovers"].has(k):
			_err("ministry: unknown field '%s'" % k)
	var sp = m.get("span_years", {})
	if not sp is Dictionary or not _num(sp.get("approx", null)):
		_err("ministry: span_years.approx must be a number")
	elif not CERTAINTY.has(sp.get("certainty", null)):
		_err("ministry: span_years needs a certainty class")
	var ps = m.get("passovers", null)
	if not ps is Array or ps.is_empty():
		_err("ministry: passovers must be a non-empty list")
		return
	for p in ps:
		if not p is Dictionary or not Scripture.is_complete(str(p.get("ref", ""))) or not CERTAINTY.has(p.get("certainty", null)):
			_err("ministry: each passover needs a complete KJV ref and a certainty class")


func _check_cycles(ids: Dictionary) -> void:
	var state: Dictionary = {}  # 1 = visiting, 2 = done
	for id in ids:
		_visit(id, ids, state, [])


func _visit(id: String, ids: Dictionary, state: Dictionary, path: Array) -> void:
	if state.get(id, 0) == 2:
		return
	if state.get(id, 0) == 1:
		_err("dependency cycle: %s" % " -> ".join(path + [id]))
		return
	state[id] = 1
	var deps = ids[id].get("dependencies", [])
	if deps is Array:
		for d in deps:
			if d is Dictionary and ids.has(d.get("id", null)) and d["id"] != id:
				_visit(d["id"], ids, state, path + [id])
	state[id] = 2


func _enum(w: String, field: String, v, allowed: Array, present: bool) -> void:
	if present and not allowed.has(v):
		_err("%s: %s '%s' is not one of %s" % [w, field, str(v), str(allowed)])
	elif not present:
		_err("%s: missing field '%s'" % [w, field])


func _num(v) -> bool:
	return v is int or v is float


func _err(msg: String) -> void:
	_errs.append(msg)


func _load_location_ids() -> Array:
	var out: Array = []
	var g = DataFiles.load_json("res://data/world/geography.json")
	if g is Dictionary:
		for k in ["areas", "locations"]:
			for x in g.get(k, []):
				out.append(x["id"])
	return out
