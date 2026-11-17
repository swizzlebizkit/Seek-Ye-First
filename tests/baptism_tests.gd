extends RefCounted
## GC-A.11 checks: the Baptism Exception. The baptism is the one canonical event the player's arrival
## triggers; it records the real world time as ministry Day 0, and every later event is scheduled from it
## while festivals stay on their fixed calendar dates. Driven by test_runner.gd.

var t: Node
var _defaults: Array = []

const MIN_DAY := 1440.0
const LOC := "bethany_beyond_jordan"
const EARLY := ["baptism_of_jesus", "temptation_in_wilderness", "john_testimony_first_disciples", "wedding_at_cana", "capernaum_stay"]


func run(runner: Node) -> void:
	t = runner
	_defaults = DataFiles.load_json("res://data/canon/events.json")["events"].duplicate(true)
	t._section = "baptism-before"
	test_before_baptism()
	t._section = "baptism-trigger"
	test_trigger_rules()
	t._section = "baptism-arrivals"
	test_arrival_dates()
	test_near_passover()
	test_festivals_fixed()
	t._section = "baptism-after"
	test_big_rest_after()
	t._section = "baptism-saves"
	test_saves()
	t._section = "baptism-data"
	test_travel_gap()
	test_validator()
	CanonicalTimeline.load_events(_defaults)
	t._fresh()


# -- helpers -----------------------------------------------------------------------------------
func _now() -> float:
	return Calendar.world_minutes(WorldSim.day, WorldSim.minute_of_day)


func _new_game() -> void:
	CanonicalTimeline.load_events(_defaults)
	GameState.new_game()
	GameState.mode = GameState.Mode.PAUSED  # tests drive the clock


## The player reaches the Jordan trigger on a calendar date (before sunset, so WorldSim.day is that day).
func _arrive(year: int, month, day: int, minute: float = 540.0) -> bool:
	WorldSim.day = Calendar.day_of(year, month, day)
	WorldSim.minute_of_day = minute
	return CanonicalTimeline.trigger_baptism(LOC)


func _passover_minutes(from_year: int = 1, to_year: int = 8) -> Array:
	var out: Array = []
	for y in range(from_year, to_year + 1):
		out.append(Calendar.world_minutes(int(Calendar.festivals_in_year(y)["passover"]["start"]), 540.0))
	return out


func _flag_ids() -> Array:
	return CanonicalTimeline.chronology_flags().map(func(f): return f["id"])


# -- before the baptism: the world runs, the ministry has not begun -------------------------------
func test_before_baptism() -> void:
	_new_game()
	t.check(not Calendar.has_ministry_clock() and Calendar.ministry_elapsed() == 0 and not CanonicalTimeline.baptism_recorded_yet(), "a new game has no ministry clock")
	var scheduled := 0
	for id in CanonicalTimeline.event_ids():
		if id != "john_preaching" and CanonicalTimeline.scheduled_start(id) < CanonicalTimeline.NEVER:
			scheduled += 1
	t.check(scheduled == 0, "no ministry event is scheduled, the baptism included")
	t.check(CanonicalTimeline.has_occurred("john_preaching") and CanonicalTimeline.occurred_ids() == ["john_preaching"], "John is already preaching at the opening")
	var fired: Array = []
	var cb := func(id): fired.append(id)
	CanonicalTimeline.event_occurred.connect(cb)
	var d0 := Calendar.current_day()
	WorldSim.advance(120.0 * MIN_DAY)
	CanonicalTimeline.event_occurred.disconnect(cb)
	t.check(Calendar.current_day() - d0 >= 119, "the world clock and calendar run normally for months")
	t.check(fired.is_empty() and CanonicalTimeline.occurred_ids() == ["john_preaching"] and not Calendar.has_ministry_clock(), "and the ministry scheduler stays inactive: nothing fires, no clock starts")
	var wait := WorldSim.serialize()
	t.check(CanonicalTimeline.arrival_state("baptism_of_jesus") == "unscheduled" and not CanonicalTimeline.witness("baptism_of_jesus", LOC), "nothing can be witnessed that has not been triggered")
	t.check(Calendar.date_string(Calendar.current_day()) != "" and WorldSim.serialize() == wait, "reading all of this changes nothing")
	t.check(CanonicalTimeline.chronology_flags().size() == 1 and _flag_ids() == ["passion_passover_unreconciled"], "before the baptism the only review flag is the open Passion Passover")


# -- the trigger: one place, once ---------------------------------------------------------------------
func test_trigger_rules() -> void:
	_new_game()
	WorldSim.day = 6
	WorldSim.minute_of_day = 600.0
	for wrong in ["", "nazareth", "kefar_zayit", "jerusalem", "jordan_valley", "Bethany_Beyond_Jordan"]:
		t.check(not CanonicalTimeline.trigger_baptism(wrong), "the trigger is refused at '%s'" % wrong)
	t.check(not Calendar.has_ministry_clock() and not CanonicalTimeline.has_occurred("baptism_of_jesus"), "refusals change nothing")
	var seen: Array = []
	var cb := func(id): seen.append(id)
	CanonicalTimeline.event_occurred.connect(cb)
	var heard: Array = []
	var hb := func(m): heard.append(m)
	CanonicalTimeline.baptism_recorded.connect(hb)
	t.check(CanonicalTimeline.trigger_baptism(LOC), "at the designated place it is accepted")
	var recorded := Calendar.baptism_minutes()
	t.check(recorded == Calendar.world_minutes(6, 600.0) and heard == [recorded], "it records the current world minute, not a configured date")
	t.check(seen == ["baptism_of_jesus"] and Calendar.ministry_elapsed() == 0, "the baptism fires once, now, as ministry Day 0")
	WorldSim.advance(5.0 * MIN_DAY)
	t.check(not CanonicalTimeline.trigger_baptism(LOC), "a second trigger is refused")
	WorldSim.day = 40
	t.check(not CanonicalTimeline.trigger_baptism(LOC) and not CanonicalTimeline.trigger_baptism("nazareth"), "later, or elsewhere, it is refused too")
	CanonicalTimeline.event_occurred.disconnect(cb)
	CanonicalTimeline.baptism_recorded.disconnect(hb)
	t.check(Calendar.baptism_minutes() == recorded and seen.count("baptism_of_jesus") == 1 and heard.size() == 1, "the record never moves and nothing is announced twice")
	t.check(not CanonicalTimeline.story_advance("baptism_of_jesus"), "story_advance still cannot start the baptism")
	_new_game()
	t.check(not Calendar.has_ministry_clock(), "a new game starts unrecorded")
	WorldSim.day = 3
	t.check(CanonicalTimeline.trigger_baptism(LOC), "and accepts the trigger again")
	# merely being in the area, or talking to John, is not the trigger: nothing in the API starts it implicitly
	_new_game()
	WorldSim.advance(30.0 * MIN_DAY)
	for id in ["john_preaching"]:
		CanonicalTimeline.witness(id, "judea")
	t.check(not Calendar.has_ministry_clock(), "witnessing John preaching (public, in the area) does not start the ministry")


# -- arriving on different dates ---------------------------------------------------------------------
## [label, year, month, day, minute, expected skipped Passovers]
const ARRIVALS := [
	["2 Kislev, Year 1", 1, "Kislev", 2, 540.0, 0],
	["11 Kislev, Year 1", 1, "Kislev", 11, 540.0, 0],
	["15 Tevet, Year 1", 1, "Tevet", 15, 540.0, 0],
	["15 Adar, Year 1", 1, "Adar", 15, 540.0, 1],
	["1 Nisan, Year 2", 2, "Nisan", 1, 540.0, 1],
	["10 Nisan, Year 2", 2, "Nisan", 10, 540.0, 1],
	["13 Nisan, Year 2", 2, "Nisan", 13, 540.0, 1],
	["14 Nisan, Year 2, 08:00", 2, "Nisan", 14, 480.0, 1],
	["14 Nisan, Year 2, 10:00", 2, "Nisan", 14, 600.0, 0],
	["20 Nisan, Year 2", 2, "Nisan", 20, 540.0, 0],
	["5 Tishri, Year 2", 2, "Tishri", 5, 540.0, 0],
	["1 Kislev, Year 3 (a leap year)", 3, "Kislev", 1, 540.0, 0],
	["15 Adar II, Year 3 (a leap year)", 3, "Adar II", 15, 540.0, 1],
	["14 Nisan, Year 5", 5, "Nisan", 14, 480.0, 1],
]


func _run_arrival(a: Array) -> Dictionary:
	_new_game()
	var ok := _arrive(int(a[1]), a[2], int(a[3]), float(a[4]))
	var r := {"ok": ok, "rel": [], "abs": [], "sel": CanonicalTimeline.first_passover_selection(), "flags": _flag_ids()}
	for id in EARLY:
		r["rel"].append(snappedf(Calendar.ministry_minutes(CanonicalTimeline.scheduled_start(id)), 0.01))
		r["abs"].append(CanonicalTimeline.scheduled_start(id))
	r["tempt"] = CanonicalTimeline.scheduled_end("temptation_in_wilderness") - CanonicalTimeline.scheduled_start("temptation_in_wilderness")
	r["cap_end"] = CanonicalTimeline.scheduled_end("capernaum_stay")
	r["p_start"] = CanonicalTimeline.scheduled_start("passover_jerusalem")
	r["p_day"] = CanonicalTimeline.scheduled_calendar_day("passover_jerusalem")
	r["b_day"] = Calendar.baptism_day()
	r["b_min"] = Calendar.baptism_minutes()
	return r


func test_arrival_dates() -> void:
	var base: Dictionary = _run_arrival(ARRIVALS[0])
	var gap := 0.0
	for d in CanonicalTimeline.get_event("passover_jerusalem")["dependencies"]:
		gap = float(d.get("gap_days", 0.0))
	var abs_seen: Dictionary = {}
	for a in ARRIVALS:
		var r: Dictionary = _run_arrival(a)
		var lab: String = a[0]
		t.check(r["ok"] and Calendar.date_string(r["b_day"]) == "%d %s" % [a[3], a[2]], "%s: the trigger records that very date (%s)" % [lab, Calendar.date_string(r["b_day"])])
		t.check(r["rel"] == base["rel"], "%s: the early ministry has the identical relative schedule" % lab)
		t.check(r["tempt"] == 40.0 * MIN_DAY, "%s: the wilderness period is exactly forty days, never compressed" % lab)
		t.check(r["rel"][1] == r["rel"][0] + 120.0 and r["abs"][1] >= r["abs"][0], "%s: the temptation follows the baptism immediately" % lab)
		abs_seen[r["b_min"]] = true
		var constraint: float = r["cap_end"] + gap * MIN_DAY
		t.check(r["p_start"] >= constraint - 0.01, "%s: the first Passover is never before its constraint" % lab)
		t.check(Calendar.date_string(r["p_day"]) == "14 Nisan" and Calendar.festivals_on(r["p_day"]).has("passover"), "%s: it lands on the fixed calendar Passover, 14 Nisan" % lab)
		var earlier := false
		for pm in _passover_minutes():
			if pm >= constraint - 0.01 and pm < r["p_start"] - 0.01:
				earlier = true
		t.check(not earlier, "%s: it is the EARLIEST Passover that satisfies the constraint" % lab)
		var sel: Dictionary = r["sel"]
		t.check(sel["skipped_count"] == a[5], "%s: skipped Passovers = %d (got %d)" % [lab, a[5], sel["skipped_count"]])
		t.check(sel["certainty"] == "simulated" and sel["calendar_day"] == r["p_day"] and sel["ministry_day"] >= 0, "%s: the selection is reported and labeled simulated" % lab)
		t.check(r["flags"].has("passion_passover_unreconciled"), "%s: the Passion Passover stays flagged for review" % lab)
		t.check(r["flags"].has("first_passover_skipped") == (a[5] > 0), "%s: first_passover_skipped is raised exactly when a Passover was skipped" % lab)
		var long_wait: bool = int(sel["wait_days"]) > 150
		t.check(r["flags"].has("first_passover_long_wait") == long_wait, "%s: first_passover_long_wait is raised exactly for waits over 150 days (%d)" % [lab, sel["wait_days"]])
	t.check(abs_seen.size() == ARRIVALS.size(), "every arrival gives a different absolute baptism date")


func test_near_passover() -> void:
	var near: Dictionary = _run_arrival(["", 2, "Nisan", 13, 540.0, 1])
	var late: Dictionary = _run_arrival(["", 2, "Nisan", 20, 540.0, 0])
	var early: Dictionary = _run_arrival(ARRIVALS[0])
	t.check(Calendar.full_date_string(near["p_day"]).begins_with("14 Nisan, Year 3"), "a baptism on 13 Nisan, Year 2 selects 14 Nisan, Year 3, not the Passover the next day")
	t.check(Calendar.full_date_string(late["p_day"]).begins_with("14 Nisan, Year 3"), "a baptism after Passover selects the following year's")
	t.check(Calendar.full_date_string(early["p_day"]).begins_with("14 Nisan, Year 2"), "a baptism on 2 Kislev, Year 1 selects 14 Nisan, Year 2")
	t.check(near["sel"]["skipped_days"].size() == 1 and near["sel"]["baptism_to_passover_days"] > 300, "the skipped Passover is listed and the wait from the baptism is long (%d days)" % near["sel"]["baptism_to_passover_days"])
	var f := {}
	_run_arrival(["", 2, "Nisan", 13, 540.0, 1])
	for fl in CanonicalTimeline.chronology_flags():
		f[fl["id"]] = fl
	t.check(f.has("first_passover_skipped") and f["first_passover_skipped"]["severity"] == "warning" and f["first_passover_skipped"]["skipped_count"] == 1, "the skip is a warning flag with its count")
	t.check(str(f["first_passover_skipped"]["selected_date"]).contains("Nisan") and f["passion_passover_unreconciled"]["severity"] == "info", "it names the selected date; the Passion Passover flag is informational")
	t.check(not _run_arrival(ARRIVALS[0])["flags"].has("first_passover_skipped"), "an early baptism raises no skip flag")
	for id in CanonicalTimeline.event_ids():
		t.check(CanonicalTimeline.scheduled_start(id) < CanonicalTimeline.NEVER, "%s stays scheduled (nothing is skipped or dropped)" % id)


## Festival dates belong to the calendar alone: the baptism date never moves them.
func test_festivals_fixed() -> void:
	_new_game()
	var before: Array = []
	for y in range(1, 9):
		before.append(Calendar.festivals_in_year(y))
	var all_same := true
	for a in ARRIVALS:
		_run_arrival(a)
		for y in range(1, 9):
			if Calendar.festivals_in_year(y) != before[y - 1]:
				all_same = false
	t.check(all_same, "no festival date changes with the baptism date, in any of %d arrivals" % ARRIVALS.size())
	t.check(Calendar.date_string(int(before[1]["passover"]["start"])) == "14 Nisan", "Passover is still 14 Nisan")


# -- after the baptism --------------------------------------------------------------------------------
func test_big_rest_after() -> void:
	for a in [ARRIVALS[0], ARRIVALS[7]]:
		_new_game()
		_arrive(int(a[1]), a[2], int(a[3]), float(a[4]))
		var order: Array = []
		var times: Array = []
		var cb := func(id):
			order.append(id)
			times.append(_now())
		CanonicalTimeline.event_occurred.connect(cb)
		WorldSim.advance(900.0 * MIN_DAY)
		CanonicalTimeline.event_occurred.disconnect(cb)
		t.check(order == ["temptation_in_wilderness", "john_testimony_first_disciples", "wedding_at_cana", "capernaum_stay", "passover_jerusalem", "judean_ministry_samaria", "galilean_ministry_expands"], "%s: one big rest fires every later event, none skipped, in order" % a[0])
		var sorted := times.duplicate()
		sorted.sort()
		t.check(times == sorted, "%s: and in time order" % a[0])
		t.check(CanonicalTimeline.occurred_ids().size() == 9 and CanonicalTimeline.is_completed("galilean_ministry_expands"), "%s: all nine have occurred and the last is complete" % a[0])
	# the player's presence changes nothing: stepping day by day gives the same history as one jump
	var runs: Array = []
	for style in ["jump", "daily"]:
		_new_game()
		_arrive(2, "Nisan", 1)
		if style == "jump":
			WorldSim.advance(900.0 * MIN_DAY)
		else:
			for i in range(900):
				WorldSim.advance(MIN_DAY)
		runs.append(JSON.stringify(CanonicalTimeline.serialize()))
	t.check(runs[0] == runs[1], "stepping day by day and resting in one jump end in the same canonical state")


# -- saves --------------------------------------------------------------------------------------------
func test_saves() -> void:
	_new_game()
	_arrive(2, "Nisan", 10)
	WorldSim.advance(10.0 * MIN_DAY)
	var before := {}
	for id in CanonicalTimeline.event_ids():
		before[id] = [CanonicalTimeline.scheduled_start(id), CanonicalTimeline.scheduled_end(id)]
	var occurred := CanonicalTimeline.occurred_ids().duplicate()
	occurred.sort()
	var canon := CanonicalTimeline.serialize()
	t.check(canon.has("baptism_minutes") and canon["baptism_minutes"] == Calendar.baptism_minutes(), "the canon block stores the recorded baptism")
	var world := WorldSim.serialize()
	_new_game()
	t.check(not Calendar.has_ministry_clock(), "a fresh game has none")
	CanonicalTimeline.deserialize(canon)
	WorldSim.deserialize(world)
	var same := true
	for id in before:
		if CanonicalTimeline.scheduled_start(id) != before[id][0] or CanonicalTimeline.scheduled_end(id) != before[id][1]:
			same = false
	var occ2 := CanonicalTimeline.occurred_ids().duplicate()
	occ2.sort()
	t.check(same and occ2 == occurred, "a save with the record restores the identical schedule and occurred set")
	t.check(not CanonicalTimeline.trigger_baptism(LOC) and Calendar.has_ministry_clock(), "after loading, the trigger cannot fire a second baptism")
	# a block without the record (older save) loads before the baptism
	CanonicalTimeline.deserialize({"occurred": ["john_preaching", "baptism_of_jesus", "temptation_in_wilderness"], "completed": ["baptism_of_jesus"]})
	t.check(not Calendar.has_ministry_clock() and CanonicalTimeline.occurred_ids() == ["john_preaching"] and not CanonicalTimeline.is_completed("baptism_of_jesus"), "a save without baptism_minutes loads as before the baptism, and stale ministry events are dropped")
	CanonicalTimeline.deserialize({})
	t.check(not Calendar.has_ministry_clock() and CanonicalTimeline.occurred_ids().is_empty(), "an empty block loads")
	# the real save file round trip, and the oldest fixture
	_new_game()
	_arrive(1, "Tevet", 20)
	WorldSim.advance(3.0 * MIN_DAY)
	var rec := Calendar.baptism_minutes()
	t.check(SaveManager.save_slot(7), "a game after the baptism saves")
	t._fresh()
	t.check(not Calendar.has_ministry_clock(), "a new game forgets it")
	t.check(SaveManager.load_slot(7) and Calendar.baptism_minutes() == rec and CanonicalTimeline.has_occurred("baptism_of_jesus"), "and the loaded slot has the same baptism record")
	var data := SaveManager.read_slot(7)
	data["canon"].erase("baptism_minutes")
	var f := FileAccess.open(SaveManager.slot_path(7), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	t.check(SaveManager.load_slot(7) and not Calendar.has_ministry_clock() and not CanonicalTimeline.has_occurred("baptism_of_jesus"), "the same slot without the record loads before the baptism")
	SaveManager.delete_slot(7)
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/pre_w1_v1_slot.json"))
	CanonicalTimeline.deserialize(fixture["canon"])
	WorldSim.deserialize(fixture["world"])
	t.check(CanonicalTimeline.occurred_ids() == ["john_preaching"] and not Calendar.has_ministry_clock(), "the oldest fixture still loads, before the baptism")
	t._fresh()


# -- data ---------------------------------------------------------------------------------------------
## The travel gap before the first Passover is explicit data, not smaller than the shortest land trip.
func test_travel_gap() -> void:
	var gap := 0.0
	var certainty := ""
	var dep_certainty := ""
	for d in CanonicalTimeline.get_event("passover_jerusalem")["dependencies"]:
		if d["id"] == "capernaum_stay":
			gap = float(d.get("gap_days", 0.0))
			certainty = str(d.get("gap_certainty", ""))
			dep_certainty = str(d["certainty"])
	t.check(gap > 0.0 and certainty == "simulated" and dep_certainty == "explicit", "the gap is data: a simulated number of days; the order itself is explicit (John 2:12-13)")
	var best := {"capernaum": 0.0}
	var todo: Array = ["capernaum"]
	var seen: Dictionary = {}
	while not todo.is_empty():
		todo.sort_custom(func(a, b): return best[a] < best[b])
		var u: String = todo.pop_front()
		if seen.has(u):
			continue
		seen[u] = true
		for rid in World.routes_from(u, "land"):
			var v := World.other_end(rid, u)
			var nd: float = best[u] + float(World.route(rid)["length_km"])
			if not best.has(v) or nd < best[v]:
				best[v] = nd
				todo.append(v)
	t.check(best.has("jerusalem"), "a land route links Capernaum and Jerusalem in the geography data")
	if best.has("jerusalem"):
		var hours := (float(Calendar.sunset_minute) - Travel.window_start("land")) / 60.0
		var days := ceilf(float(best["jerusalem"]) / (Travel.speed_kmh("land") * hours))
		t.check(gap >= days, "the gap (%d days) covers the land trip of %.0f km at walking pace in daylight (%d days)" % [int(gap), best["jerusalem"], int(days)])


func test_validator() -> void:
	var doc: Dictionary = DataFiles.load_json("res://data/canon/events.json")
	var v = load("res://scripts/core/chronology_validator.gd").new()
	t.check(v.validate_doc(doc).is_empty(), "events.json validates with the player_arrival baptism")
	var d: Dictionary = doc.duplicate(true)
	for e in d["events"]:
		if e["id"] == "wedding_at_cana":
			e["schedule"] = {"mode": "player_arrival", "certainty": "simulated"}
	var errs: Array = v.validate_doc(d)
	t.check(errs.any(func(x): return str(x).contains("only the baptism may use schedule mode player_arrival")), "validator: no other event may be player-arrival triggered")
	d = doc.duplicate(true)
	for e in d["events"]:
		if e["id"] == "passover_jerusalem":
			e["dependencies"][0]["gap_certainty"] = "maybe"
	t.check(v.validate_doc(d).any(func(x): return str(x).contains("gap_certainty")), "validator: gap_certainty is checked")
