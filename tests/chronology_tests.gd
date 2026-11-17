extends RefCounted
## GC-A checks: canonical event schema v2 and its validator, the nine early-ministry events, the
## time-driven scheduler (witness / miss / early / rest all give the same history), the ministry clock
## and the access-class API. Driven by test_runner.gd.

var t: Node
var doc: Dictionary = {}
var _defaults: Array = []

const MIN_DAY := 1440.0
const BAPTISM_LOC := "bethany_beyond_jordan"
const BAPTISM_DAY := 2  # WorldSim day 2, 09:00 is "2 Kislev" (the calendar day turns over at the previous sunset)
const BAPTISM_MINUTE := 540.0


func run(runner: Node) -> void:
	t = runner
	doc = DataFiles.load_json("res://data/canon/events.json")
	_defaults = doc["events"].duplicate(true)
	t._section = "chrono-schema"
	test_schema_valid()
	test_validator_failures()
	test_compat()
	t._section = "chrono-events"
	test_nine_events()
	t._section = "chrono-clock"
	test_ministry_clock()
	test_old_clock_unchanged()
	t._section = "chrono-scheduler"
	test_schedule_shape()
	test_story_advance_refused()
	test_same_history_all_ways()
	test_dependency_order()
	test_save_mid_event()
	await test_outcomes_via_timeline()
	t._section = "chrono-access"
	test_access_classes()
	test_early_arrival()
	CanonicalTimeline.load_events(_defaults)
	t._fresh()


# -- helpers -----------------------------------------------------------------------------------
func _now() -> float:
	return Calendar.world_minutes(WorldSim.day, WorldSim.minute_of_day)


func _to(time: float) -> void:
	if time > _now():
		WorldSim.advance(time - _now())


func _new_game(baptize: bool = true) -> void:
	CanonicalTimeline.load_events(_defaults)
	GameState.new_game()
	GameState.mode = GameState.Mode.PAUSED  # the real-time clock stays still; tests drive WorldSim.advance
	if baptize:
		_baptize()


## The player reaches the Jordan trigger at the given world time. Nothing happens before this.
func _baptize(day: int = BAPTISM_DAY, minute: float = BAPTISM_MINUTE) -> bool:
	WorldSim.day = day
	WorldSim.minute_of_day = minute
	return CanonicalTimeline.trigger_baptism(BAPTISM_LOC)


func _errs(mutate: Callable) -> Array:
	var d: Dictionary = doc.duplicate(true)
	mutate.call(d)
	return load("res://scripts/core/chronology_validator.gd").new().validate_doc(d)


func _has(errs: Array, needle: String) -> bool:
	return errs.any(func(e): return str(e).contains(needle))


func _ev(d: Dictionary, id: String) -> Dictionary:
	for e in d["events"]:
		if e["id"] == id:
			return e
	return {}


func _end() -> float:
	return CanonicalTimeline.scheduled_end("galilean_ministry_expands") + MIN_DAY


# -- GC-A.1 schema and validator -----------------------------------------------------------------
func test_schema_valid() -> void:
	var v = load("res://scripts/core/chronology_validator.gd").new()
	var errs: Array = v.validate_doc(doc)
	t.check(errs.is_empty(), "events.json validates under schema v2 %s" % str(errs))
	t.check(int(doc["schema_version"]) == 2 and doc["preliminary_harmonization"] == true, "the set declares schema v2 and is marked a preliminary harmonization")
	for e in doc["events"]:
		for k in ["certainty", "access", "refs", "location", "dependencies", "duration", "participants", "witnesses", "traveling_party", "rumor_sources", "testimony_sources", "significance"]:
			t.check(e.has(k), "%s has %s" % [e["id"], k])
	var d: Dictionary = _ev(doc, "temptation_in_wilderness")["duration"]
	t.check(d["basis"] == "scripture" and d["amount"] == 40, "a scriptural count (forty days) is marked basis scripture")
	t.check(_ev(doc, "capernaum_stay")["duration"]["basis"] == "estimate", "not many days is a gameplay estimate")


func test_validator_failures() -> void:
	t.check(_has(_errs(func(d): _ev(d, "wedding_at_cana").erase("access")), "missing field 'access'"), "validator: missing field")
	t.check(_has(_errs(func(d): _ev(d, "wedding_at_cana")["bogus"] = 1), "unknown field 'bogus'"), "validator: unknown field")
	t.check(_has(_errs(func(d): _ev(d, "wedding_at_cana")["schedule"]["bogus"] = 1), "schedule has unknown field"), "validator: unknown schedule field")
	t.check(_has(_errs(func(d): _ev(d, "wedding_at_cana")["access"] = "secret"), "access 'secret'"), "validator: unknown access value")
	t.check(_has(_errs(func(d): _ev(d, "wedding_at_cana")["certainty"] = "probably"), "certainty 'probably'"), "validator: unknown certainty value")
	t.check(_has(_errs(func(d): _ev(d, "wedding_at_cana")["dependencies"][0]["certainty"] = "sure"), "dependency"), "validator: unknown dependency certainty")
	t.check(_has(_errs(func(d): _ev(d, "wedding_at_cana")["dependencies"][0].erase("certainty")), "missing 'certainty'"), "validator: dependency without certainty")
	t.check(_has(_errs(func(d): _ev(d, "wedding_at_cana")["location"] = "atlantis"), "unknown location id 'atlantis'"), "validator: unknown location id")
	t.check(_has(_errs(func(d): _ev(d, "wedding_at_cana")["refs"] = ["John 2:99"]), "not complete"), "validator: ref Scripture.is_complete rejects")
	t.check(_has(_errs(func(d): _ev(d, "wedding_at_cana")["refs"] = []), "refs must be"), "validator: no refs")
	t.check(_has(_errs(func(d): _ev(d, "wedding_at_cana")["dependencies"][0]["id"] = "nowhere"), "unknown event"), "validator: unknown dependency target")
	var cyc := _errs(func(d):
		_ev(d, "john_preaching")["dependencies"] = [{"id": "capernaum_stay", "relation": "after_end", "certainty": "simulated"}])
	t.check(_has(cyc, "dependency cycle"), "validator: dependency cycle")
	t.check(_has(_errs(func(d): _ev(d, "baptism_of_jesus")["dependencies"].append({"id": "baptism_of_jesus", "relation": "after_end", "certainty": "explicit"})), "depends on itself"), "validator: self dependency")
	t.check(_has(_errs(func(d): _ev(d, "temptation_in_wilderness")["witnesses"] = ["crowds"]), "private event cannot list witnesses"), "validator: a private event has no witnesses")
	t.check(_has(_errs(func(d): _ev(d, "capernaum_stay")["duration"]["certainty"] = "explicit"), "estimate cannot be certainty explicit"), "validator: an estimate is never explicit")
	t.check(_has(_errs(func(d): _ev(d, "capernaum_stay")["duration"]["min"] = 99), "min <= amount <= max"), "validator: duration uncertainty bounds")
	t.check(_has(_errs(func(d): _ev(d, "passover_jerusalem")["schedule"]["festival"] = "fake_feast"), "not a known festival"), "validator: unknown festival")
	t.check(_has(_errs(func(d): d["events"].append(d["events"][0].duplicate(true))), "duplicate event id"), "validator: duplicate id")
	t.check(_has(_errs(func(d): d["ministry"]["passovers"][0]["ref"] = "John 2:99"), "passover"), "validator: ministry Passover refs are checked")
	t.check(_has(_errs(func(d): _ev(d, "baptism_of_jesus")["outcomes"] = [{"character_id": "x", "outcome": "vanish"}]), "outcome"), "validator: unknown outcome")


# -- GC-A.2 compatibility -------------------------------------------------------------------------
func test_compat() -> void:
	t._section = "chrono-compat"
	CanonicalTimeline.load_events(_defaults)
	for id in ["has_event", "get_event", "event_ids", "has_occurred", "occurred_ids"]:
		t.check(CanonicalTimeline.has_method(id), "public API kept: %s" % id)
	var ids: Array = CanonicalTimeline.event_ids()
	t.check(ids[0] == "john_preaching" and ids[1] == "baptism_of_jesus", "the two original events keep their ids and order")
	var b := CanonicalTimeline.get_event("baptism_of_jesus")
	t.check(b["refs"].has("Matthew 3:13-17") and b["title"] == "Jesus is baptized by John in the Jordan" and b["access"] == "public", "baptism migrated: old refs and title, new access")
	# a version-1 save carries only {"occurred": [...]}
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/pre_w1_v1_slot.json"))
	CanonicalTimeline.deserialize(fixture["canon"])
	t.check(CanonicalTimeline.occurred_ids() == ["john_preaching"] and CanonicalTimeline.has_occurred("john_preaching") and not CanonicalTimeline.has_occurred("baptism_of_jesus"), "a pre-GC save reports the same occurred set")
	t.check(CanonicalTimeline.serialize()["occurred"] == ["john_preaching"], "and serializes the same occurred list")
	WorldSim.deserialize(fixture["world"] if fixture.has("world") else {"day": 1, "minute": 420})
	t.check(CanonicalTimeline.occurred_ids() == ["john_preaching"], "loading the old clock adds nothing that is not yet due")
	t.check(Calendar.date_string(Calendar.current_day()).contains("Kislev") or WorldSim.day > 1, "old save clock reads normally")
	t._fresh()


# -- GC-A.5 the nine events -----------------------------------------------------------------------
func test_nine_events() -> void:
	var ids: Array = CanonicalTimeline.event_ids()
	t.check(ids.size() == 9, "nine early-ministry events")
	var expect := ["john_preaching", "baptism_of_jesus", "temptation_in_wilderness", "john_testimony_first_disciples", "wedding_at_cana",
			"capernaum_stay", "passover_jerusalem", "judean_ministry_samaria", "galilean_ministry_expands"]
	t.check(ids == expect, "the nine are in harmonized order")
	var counts := {"public": 0, "restricted": 0, "private": 0}
	for e in doc["events"]:
		counts[e["access"]] += 1
		for r in e["refs"]:
			t.check(Scripture.is_complete(r), "%s: %s is in the KJV data" % [e["id"], r])
		for d in e["dependencies"]:
			t.check(["explicit", "inferred", "simulated"].has(d["certainty"]), "%s: dependency on %s has a certainty class" % [e["id"], d["id"]])
		t.check(["explicit", "inferred", "simulated"].has(e["schedule"]["certainty"]), "%s: schedule has a certainty class" % e["id"])
		for forbidden in ["date", "year", "calendar_day", "absolute_date"]:
			t.check(not e.has(forbidden) and not e["schedule"].has(forbidden), "%s: no fabricated precise date (%s)" % [e["id"], forbidden])
	t.check(counts == {"public": 6, "restricted": 2, "private": 1}, "access class counts: 6 public, 2 restricted, 1 private %s" % str(counts))
	t.check(_ev(doc, "temptation_in_wilderness")["refs"] == ["Matthew 4:1-11", "Mark 1:12-13", "Luke 4:1-13"], "the temptation carries its three accounts")
	t.check(_ev(doc, "temptation_in_wilderness")["access"] == "private", "the temptation is private")
	_new_game()
	var tempt_start := CanonicalTimeline.scheduled_start("temptation_in_wilderness")
	var tempt_end := CanonicalTimeline.scheduled_end("temptation_in_wilderness")
	var any_witness := false
	for loc in ["judea", "jordan_valley", "bethany_beyond_jordan", "jerusalem", "kefar_zayit", ""]:
		for at in [tempt_start - 100.0, tempt_start, (tempt_start + tempt_end) * 0.5, tempt_end - 1.0, tempt_end + 100.0]:
			for who in ["protagonist", "jesus", "crowds"]:
				if CanonicalTimeline.can_witness("temptation_in_wilderness", who, loc, at):
					any_witness = true
	t.check(not any_witness, "the temptation cannot be witnessed from any place, time or observer")
	t.check(not CanonicalTimeline.witness("temptation_in_wilderness", "judea"), "witness() refuses and records nothing")
	t.check(PlayerKnowledge.level_of("temptation_in_wilderness") == "unknown", "so the protagonist learns nothing of it by being near")
	var m: Dictionary = doc["ministry"]
	t.check(m["span_years"]["approx"] == 3 and m["span_years"]["certainty"] == "inferred", "the three-year ministry is an inferred bound")
	t.check(m["passovers"].map(func(p): return p["ref"]) == ["John 2:13", "John 6:4", "John 11:55"], "the three Passovers are recorded")
	var last := CanonicalTimeline.scheduled_end("galilean_ministry_expands")
	t.check(Calendar.ministry_minutes(last) < 3.5 * 365.0 * MIN_DAY, "all nine events fit inside the inferred three-year bound")


# -- GC-A.4 the ministry clock ----------------------------------------------------------------------
func _ordinal(dt: Dictionary) -> int:
	var idx: int = int(dt["year"]) - 1
	var n := 0
	for i in range(idx):
		for m in Calendar.months_in_year(i):
			n += int(m["length"])
	var ms: Array = Calendar.months_in_year(idx)
	for i in range(int(dt["month"]) - 1):
		n += int(ms[i]["length"])
	return n + int(dt["day"])


func test_ministry_clock() -> void:
	_new_game(false)
	t.check(Calendar.date_string(1) == "1 Kislev" and Calendar.full_date_string(1) == "1 Kislev, Year 1" and Calendar.start_minute == 7 * 60, "the game opening is 1 Kislev, Year 1, 07:00")
	t.check(not Calendar.config.get("anchors", {}).has("baptism") and Calendar.anchor_day("baptism") == 0, "calendar.json holds no baptism anchor")
	t.check(not Calendar.has_ministry_clock() and Calendar.baptism_day() == 0 and Calendar.baptism_minutes() < 0.0 and Calendar.ministry_elapsed() == 0 and Calendar.baptism_certainty() == "", "before the baptism there is no ministry clock")
	t.check(Calendar.baptism_record() == {"recorded": false}, "and no baptism record")
	WorldSim.advance(3.0 * MIN_DAY)
	t.check(not Calendar.has_ministry_clock() and Calendar.ministry_elapsed() == 0 and Calendar.current_day() > 1, "the world clock runs on normally and still no ministry clock")
	t.check(_baptize(5, 600.0), "the player reaches the trigger")
	var bd := Calendar.baptism_day()
	var dt := Calendar.date(bd)
	t.check(bd == Calendar.current_day() and Calendar.baptism_minutes() == Calendar.world_minutes(5, 600.0), "the recorded baptism is the actual moment, not a configured date")
	var rec := Calendar.baptism_record()
	t.check(rec["recorded"] and rec["certainty"] == "simulated" and rec["source"] == "recorded from the playthrough" and rec["calendar_day"] == bd, "it is labeled simulated and recorded from the playthrough")
	t.check(Calendar.ministry_elapsed(bd) == 0 and Calendar.ministry_elapsed(bd + 1) == 1 and Calendar.ministry_elapsed(bd - 1) == -1, "ministry_elapsed is 0 at the baptism, 1 the next day")
	var bad := 0
	var span_leap := false
	for d in range(bd - 5, bd + 1600):  # four-plus years: months, years and leap years
		if Calendar.ministry_elapsed(d) != _ordinal(Calendar.date(d)) - _ordinal(dt):
			bad += 1
		if Calendar.date(d)["leap"]:
			span_leap = true
	t.check(bad == 0 and span_leap, "ministry_elapsed equals calendar days since the baptism across month, year and leap-year boundaries")
	_new_game(false)
	t.check(_baptize(8, 17.0 * 60 + 59), "a baptism just before sunset")
	var before_sunset := Calendar.ministry_elapsed()
	WorldSim.advance(2.0)
	t.check(before_sunset == 0 and Calendar.ministry_elapsed() == 1, "ministry_elapsed turns over at sunset, like the calendar day")
	var start_day := Calendar.current_day()
	WorldSim.advance(100.0 * MIN_DAY + 300.0)
	t.check(Calendar.ministry_elapsed() == Calendar.current_day() - Calendar.baptism_day() and Calendar.current_day() - start_day >= 100, "the elapsed value follows WorldSim after a long advance")
	Calendar.clear_ministry_start()
	t.check(not Calendar.has_ministry_clock() and Calendar.ministry_elapsed(50) == 0, "clearing the record leaves no ministry clock and nothing breaks")
	t._fresh()


func test_old_clock_unchanged() -> void:
	var with_record: Array = []
	var without: Array = []
	for pass_i in range(2):
		_new_game(false)
		if pass_i == 0:
			_baptize(40, 540.0)
		var out: Array = with_record if pass_i == 0 else without
		for d in range(1, 800):
			out.append([Calendar.date_string(d), Calendar.weekday(d), Calendar.is_sabbath(d, 600.0), Calendar.phase(d, 960.0)])
	t.check(with_record == without, "dates, weekdays, Sabbaths and phases are identical with and without a recorded baptism")
	WorldSim.deserialize({"day": 12, "minute": 600.0})
	t.check(WorldSim.day == 12 and WorldSim.minute_of_day == 600.0 and Calendar.date_string(Calendar.current_day()) == "12 Kislev", "an old clock reading loads unchanged")
	t._fresh()


# -- GC-A.3 the scheduler -----------------------------------------------------------------------
func test_schedule_shape() -> void:
	_new_game(false)
	t.check(CanonicalTimeline.has_occurred("john_preaching") and CanonicalTimeline.occurred_ids().size() == 1, "at the opening only John's preaching is under way")
	t.check(CanonicalTimeline.scheduled_start("baptism_of_jesus") >= CanonicalTimeline.NEVER and CanonicalTimeline.arrival_state("baptism_of_jesus") == "unscheduled", "before the trigger the baptism is unscheduled")
	var anything := false
	for id in CanonicalTimeline.event_ids():
		if id != "john_preaching" and CanonicalTimeline.scheduled_start(id) < CanonicalTimeline.NEVER:
			anything = true
	t.check(not anything and CanonicalTimeline.next_boundary(0.0) < CanonicalTimeline.NEVER, "no ministry event is scheduled; only John's own end remains on the clock")
	_new_game()
	t.check(CanonicalTimeline.scheduled_start("baptism_of_jesus") == Calendar.baptism_minutes(), "the baptism starts at ministry Day 0")
	t.check(CanonicalTimeline.scheduled_ministry_day("baptism_of_jesus") == 0 and CanonicalTimeline.scheduled_calendar_day("baptism_of_jesus") == Calendar.baptism_day(), "and on the baptism's calendar day")
	t.check(Calendar.date_string(Calendar.baptism_day()) == "2 Kislev", "a baptism on 2 Kislev is recorded as 2 Kislev")
	for id in CanonicalTimeline.event_ids():
		for dep in CanonicalTimeline.get_event(id)["dependencies"]:
			var ref: float = CanonicalTimeline.scheduled_start(dep["id"]) if dep["relation"] == "after_start" else CanonicalTimeline.scheduled_end(dep["id"])
			t.check(CanonicalTimeline.scheduled_start(id) >= ref + float(dep.get("gap_days", 0.0)) * MIN_DAY - 0.01, "%s starts no earlier than its dependency %s allows" % [id, dep["id"]])
	var pday := CanonicalTimeline.scheduled_calendar_day("passover_jerusalem")
	var fs := Calendar.festivals_on(pday)
	t.check(fs.has("passover"), "the Passover event starts on the calendar's Passover day (%s)" % Calendar.full_date_string(pday))
	t.check(Calendar.date_string(pday) == "14 Nisan", "which is 14 Nisan")
	var md := CanonicalTimeline.scheduled_ministry_day("passover_jerusalem")
	t.check(md > CanonicalTimeline.scheduled_ministry_day("capernaum_stay"), "the first Passover follows Capernaum")
	t.check(CanonicalTimeline.arrival_state("baptism_of_jesus") == "during", "at the trigger the baptism is under way")


func test_story_advance_refused() -> void:
	_new_game()
	var before := JSON.stringify(CanonicalTimeline.serialize())
	var refused := true
	for id in CanonicalTimeline.event_ids():
		if CanonicalTimeline.story_advance(id):
			refused = false
	t.check(refused and JSON.stringify(CanonicalTimeline.serialize()) == before, "story_advance on any canonical id changes nothing")
	t.check(not CanonicalTimeline.story_advance("not_an_event"), "story_advance on an unknown id is harmless")
	GameState.set_flag("my_own_flag")
	t.check(GameState.has_flag("my_own_flag") and Quests.start("missing_jar") and Quests.is_active("missing_jar"), "story flags and quests still work")
	t.check(JSON.stringify(CanonicalTimeline.serialize()) == before, "and still do not touch the canon")


## One run of the history: returns {times: id -> world minute at emission, order, done, final}.
func _history(style: String) -> Dictionary:
	_new_game(false)
	var h := {"times": {}, "order": [], "done": [], "counts": {}}
	var on_start := func(id):
		h["times"][id] = _now()
		h["order"].append(id)
		h["counts"][id] = int(h["counts"].get(id, 0)) + 1
		if style == "witness":
			CanonicalTimeline.witness(id, CanonicalTimeline.event_location(id))
	var on_end := func(id): h["done"].append(id)
	CanonicalTimeline.event_occurred.connect(on_start)
	CanonicalTimeline.event_completed.connect(on_end)
	# The same arrival at the Jordan in every style: 2 Kislev, 09:00 (the ministry is unscheduled until then).
	h["pre"] = CanonicalTimeline.arrival_state("baptism_of_jesus")
	WorldSim.advance(float(BAPTISM_DAY - 1) * MIN_DAY + BAPTISM_MINUTE - float(Calendar.start_minute))
	t.check(_baptize(WorldSim.day, WorldSim.minute_of_day), "%s: the trigger is accepted at the Jordan" % style)
	var end := _end()
	match style:
		"miss", "witness":
			while _now() < end:
				WorldSim.advance(MIN_DAY)
		"rest":
			WorldSim.advance(end - _now())  # one enormous rest/travel jump
		"early":
			for id in CanonicalTimeline.event_ids():
				var s := CanonicalTimeline.scheduled_start(id)
				if s > _now() and s < CanonicalTimeline.NEVER:
					_to(s - 180.0)  # arrive three hours early and wait
					h["early_" + id] = CanonicalTimeline.arrival_state(id)
					_to(s + 30.0)
			_to(end)
	_to(end)
	CanonicalTimeline.event_occurred.disconnect(on_start)
	CanonicalTimeline.event_completed.disconnect(on_end)
	h["final"] = JSON.stringify(CanonicalTimeline.serialize())
	h["know"] = PlayerKnowledge.level_of("baptism_of_jesus")
	return h


func test_same_history_all_ways() -> void:
	var runs := {}
	for style in ["miss", "witness", "early", "rest"]:
		runs[style] = _history(style)
	var base: Dictionary = runs["miss"]
	var ids: Array = CanonicalTimeline.event_ids()
	t.check(base["order"].size() == 8 and not base["order"].has("john_preaching"), "the eight events after the opening each fire (John's is already under way at the opening)")
	for style in ["witness", "early", "rest"]:
		var r: Dictionary = runs[style]
		t.check(r["order"] == base["order"], "%s: the same events fire in the same order" % style)
		t.check(r["done"] == base["done"], "%s: the same events complete in the same order" % style)
		t.check(r["final"] == base["final"], "%s: the same final canonical state" % style)
		var same := true
		for id in base["times"]:
			if not r["times"].has(id) or absf(float(r["times"][id]) - float(base["times"][id])) > 0.01:
				same = false
		t.check(same, "%s: every event happens at the same simulated minute" % style)
	for id in ids:
		if base["times"].has(id):
			t.check(absf(float(base["times"][id]) - CanonicalTimeline.scheduled_start(id)) < 0.01, "%s fires at its scheduled start" % id)
	var once := true
	for style in runs:
		for id in runs[style]["counts"]:
			if runs[style]["counts"][id] != 1:
				once = false
	t.check(once, "no event is announced twice in any run")
	t.check(runs["witness"]["know"] == "witnessed" and runs["miss"]["know"] == "unknown" and runs["rest"]["know"] == "unknown", "witnessing changes what the protagonist knows, never what happened")
	t.check(runs["early"]["pre"] == "unscheduled" and runs["early"]["early_passover_jerusalem"] == "before" and not runs["early"].has("early_baptism_of_jesus"), "before the trigger the baptism cannot be waited for; later events can be, and are still before")
	var chrono := true
	var last := -1.0e30
	for id in base["order"]:
		if base["times"][id] < last - 0.01:
			chrono = false
		last = base["times"][id]
	t.check(chrono, "events are announced in time order even after a big jump")
	t.check(base["order"].find("baptism_of_jesus") < base["order"].find("temptation_in_wilderness") and base["order"].find("wedding_at_cana") < base["order"].find("passover_jerusalem"), "dependency order holds in the history")


func test_dependency_order() -> void:
	var evs: Array = []
	for i in range(3):
		var id := "x%d" % i
		evs.append({"id": id, "order": i + 1, "name": id, "refs": ["John 2:1"], "access": "public", "location": "cana", "participants": ["a"], "witnesses": [],
				"dependencies": [] if i == 0 else [{"id": "x%d" % (i - 1), "relation": "after_end", "certainty": "inferred", "gap_days": 1}],
				"schedule": {"mode": "ministry_offset", "days": 5 - i, "certainty": "simulated"},  # data asks for them reversed
				"duration": {"amount": 2, "unit": "days", "basis": "estimate", "certainty": "simulated", "min": 1, "max": 3}})
	CanonicalTimeline.load_events(evs)
	GameState.new_game()
	Calendar.set_ministry_start(Calendar.world_minutes(BAPTISM_DAY, BAPTISM_MINUTE))  # a ministry clock for the offset mode
	t.check(CanonicalTimeline.scheduled_start("x1") >= CanonicalTimeline.scheduled_end("x0") + MIN_DAY - 0.01 and CanonicalTimeline.scheduled_start("x2") >= CanonicalTimeline.scheduled_end("x1") + MIN_DAY - 0.01, "a dependency forces its dependants later, never earlier")
	var order: Array = []
	var cb := func(id): order.append(id)
	CanonicalTimeline.event_occurred.connect(cb)
	WorldSim.advance(Calendar.baptism_minutes() + 30.0 * MIN_DAY - _now())
	CanonicalTimeline.event_occurred.disconnect(cb)
	t.check(order == ["x0", "x1", "x2"], "a single big jump still fires them in dependency order")
	_new_game()


func test_save_mid_event() -> void:
	_new_game()
	var mid := CanonicalTimeline.scheduled_start("temptation_in_wilderness") + 5.0 * MIN_DAY
	_to(mid)
	t.check(CanonicalTimeline.has_occurred("temptation_in_wilderness") and not CanonicalTimeline.is_completed("temptation_in_wilderness") and CanonicalTimeline.arrival_state("temptation_in_wilderness") == "during", "mid-temptation: begun, not finished")
	var canon := CanonicalTimeline.serialize()
	var world := WorldSim.serialize()
	_new_game()
	CanonicalTimeline.deserialize(canon)
	WorldSim.deserialize(world)
	t.check(CanonicalTimeline.has_occurred("temptation_in_wilderness") and not CanonicalTimeline.is_completed("temptation_in_wilderness") and CanonicalTimeline.has_occurred("baptism_of_jesus") and CanonicalTimeline.is_completed("baptism_of_jesus"), "save/load mid-event keeps its state")
	var starts: Array = []
	var ends: Array = []
	var a := func(id): starts.append(id)
	var b := func(id): ends.append(id)
	CanonicalTimeline.event_occurred.connect(a)
	CanonicalTimeline.event_completed.connect(b)
	_to(CanonicalTimeline.scheduled_end("temptation_in_wilderness") + 10.0)
	CanonicalTimeline.event_occurred.disconnect(a)
	CanonicalTimeline.event_completed.disconnect(b)
	t.check(ends == ["temptation_in_wilderness"] and not starts.has("temptation_in_wilderness") and not starts.has("baptism_of_jesus"), "the loaded game finishes the event once and does not restart earlier ones")
	# an old-format block (occurred only) is accepted
	CanonicalTimeline.deserialize({"occurred": ["john_preaching", "baptism_of_jesus"]})
	t.check(CanonicalTimeline.has_occurred("john_preaching") and not CanonicalTimeline.has_occurred("baptism_of_jesus") and not Calendar.has_ministry_clock(), "a block with only 'occurred' loads before the baptism: a stale baptism without a record is dropped")
	_new_game()


func test_outcomes_via_timeline() -> void:
	var existing := t.get_tree().root.get_node_or_null("CanonicalProtection")
	var stub: Node = null
	if existing == null:
		stub = Node.new()
		stub.name = "CanonicalProtection"
		var s := GDScript.new()
		s.source_code = "extends Node\nvar calls: Array = []\nfunc apply_outcome(c, o, src = \"\"):\n\tcalls.append([c, o, src])\n\treturn true\n"
		s.reload()
		stub.set_script(s)
		t.get_tree().root.add_child.call_deferred(stub)
		await t.get_tree().process_frame
		existing = stub
	var evs: Array = []
	evs.append({"id": "fall", "order": 1, "name": "fall", "refs": ["John 2:1"], "access": "public", "location": "cana", "participants": ["a"], "witnesses": [],
			"dependencies": [], "schedule": {"mode": "ministry_offset", "days": 3, "certainty": "simulated"},
			"duration": {"amount": 1, "unit": "days", "basis": "estimate", "certainty": "simulated", "min": 1, "max": 2},
			"outcomes": [{"character_id": "john_the_baptist", "outcome": "arrest"}]})
	CanonicalTimeline.load_events(evs)
	GameState.new_game()
	Calendar.set_ministry_start(Calendar.world_minutes(BAPTISM_DAY, BAPTISM_MINUTE))  # a ministry clock for the offset mode
	if stub != null:
		existing.calls.clear()
		WorldSim.advance(Calendar.baptism_minutes() + 20.0 * MIN_DAY - _now())
		t.check(existing.calls == [["john_the_baptist", "arrest", "timeline"]], "a canonical outcome reaches CanonicalProtection once, from the timeline")
		WorldSim.advance(10.0 * MIN_DAY)
		t.check(existing.calls.size() == 1, "and is never applied again")
		stub.queue_free()
		await t.get_tree().process_frame
	else:
		# the real autoload: the scheduler outcome must land in the real protection system, once
		existing.reset()
		WorldSim.advance(Calendar.baptism_minutes() + 20.0 * MIN_DAY - _now())
		t.check(existing.outcome_of("john_the_baptist") == "arrest", "the timeline applies a canonical outcome through the real CanonicalProtection")
		WorldSim.advance(10.0 * MIN_DAY)
		t.check(existing.applied.size() == 1 and existing.outcome_of("john_the_baptist") == "arrest", "and it is applied once")
		existing.reset()
	_new_game()


# -- GC-A.6 access classes and arrival states -------------------------------------------------------
func test_access_classes() -> void:
	_new_game()
	var s := CanonicalTimeline.scheduled_start("baptism_of_jesus")
	var e := CanonicalTimeline.scheduled_end("baptism_of_jesus")
	var loc := CanonicalTimeline.event_location("baptism_of_jesus")
	var mid := (s + e) * 0.5
	t.check(CanonicalTimeline.can_witness("baptism_of_jesus", "protagonist", loc, mid), "a public event is witnessable by someone present during it")
	var rep := CanonicalTimeline.witness_report("baptism_of_jesus", "protagonist", loc, mid)
	t.check(rep["observation"] == "partial" and rep["present"], "but presence alone is a partial view, not full observation")
	t.check(CanonicalTimeline.witness_report("baptism_of_jesus", "jesus", loc, mid)["observation"] == "full", "a participant takes it in fully")
	t.check(not CanonicalTimeline.can_witness("baptism_of_jesus", "protagonist", "nazareth", mid), "not from elsewhere")
	t.check(CanonicalTimeline.arrival_state("baptism_of_jesus", s - 60.0) == "before" and not CanonicalTimeline.can_witness("baptism_of_jesus", "protagonist", loc, s - 60.0), "arriving before: state before, nothing to see yet")
	t.check(CanonicalTimeline.arrival_state("baptism_of_jesus", mid) == "during", "arriving during: state during")
	t.check(CanonicalTimeline.arrival_state("baptism_of_jesus", e + 60.0) == "after" and not CanonicalTimeline.can_witness("baptism_of_jesus", "protagonist", loc, e + 60.0), "arriving after: state after, missed it")
	var cana_s := CanonicalTimeline.scheduled_start("wedding_at_cana") + 60.0
	t.check(not CanonicalTimeline.can_witness("wedding_at_cana", "protagonist", "cana", cana_s), "a restricted event is closed to the protagonist even when present")
	t.check(CanonicalTimeline.can_witness("wedding_at_cana", "servants", "cana", cana_s) and CanonicalTimeline.can_witness("wedding_at_cana", "disciples", "cana", cana_s), "restricted: open to its scriptural participants and witnesses")
	t.check(not CanonicalTimeline.can_witness("wedding_at_cana", "servants", "capernaum", cana_s), "but only where it happens")
	var snapshot := JSON.stringify(CanonicalTimeline.get_event("baptism_of_jesus")) + str(CanonicalTimeline.scheduled_start("baptism_of_jesus")) + CanonicalTimeline.event_location("baptism_of_jesus")
	for l in ["nazareth", "kefar_zayit", "bethany_beyond_jordan", "jerusalem"]:
		CanonicalTimeline.witness("baptism_of_jesus", l, mid)
		CanonicalTimeline.witness_report("baptism_of_jesus", "protagonist", l, mid)
	var after := JSON.stringify(CanonicalTimeline.get_event("baptism_of_jesus")) + str(CanonicalTimeline.scheduled_start("baptism_of_jesus")) + CanonicalTimeline.event_location("baptism_of_jesus")
	t.check(snapshot == after, "the player's position never alters the event or where Jesus is")
	t.check(CanonicalTimeline.arrival_state("baptism_of_jesus", NAN) != "", "arrival_state never blocks (always answers)")


func test_early_arrival() -> void:
	_new_game()
	var s := CanonicalTimeline.scheduled_start("passover_jerusalem")
	var loc := CanonicalTimeline.event_location("passover_jerusalem")
	_to(s - 300.0)  # the knowledgeable player is already in Jerusalem, five hours early
	t.check(CanonicalTimeline.arrival_state("passover_jerusalem") == "before" and not CanonicalTimeline.witness("passover_jerusalem", loc), "five hours early: nothing yet")
	_to(s - 60.0)
	t.check(not CanonicalTimeline.has_occurred("passover_jerusalem"), "the Passover does not wait for the player")
	_to(s + 20.0)
	t.check(CanonicalTimeline.has_occurred("passover_jerusalem") and CanonicalTimeline.arrival_state("passover_jerusalem") == "during", "it begins on schedule")
	t.check(CanonicalTimeline.witness("passover_jerusalem", loc) and PlayerKnowledge.level_of("passover_jerusalem") == "witnessed", "an early arrival who waits witnesses a public event")
	t.check(CanonicalTimeline.scheduled_start("passover_jerusalem") == s, "the early arrival did not move it")
	_new_game()
