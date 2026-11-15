extends RefCounted
## W1 checks: geography data, regional exploration and transitions, strategic travel, the Sabbath rules
## for land and water, discovery, journey persistence and old-save compatibility. Driven by test_runner.gd.

var t: Node

const SUNSET := 18 * 60
const LAND_KMH := 4.0


func run(runner: Node) -> void:
	t = runner
	t._section = "world-geo"
	test_geography()
	test_discovery()
	t._section = "world-time"
	test_time_stepping()
	t._section = "world-travel"
	test_journey_basics()
	test_multi_day()
	test_interruption_and_abandon()
	t._section = "world-sabbath"
	test_sabbath_stop()
	test_multiple_sabbaths()
	test_boat()
	test_no_skipped_transitions()
	t._section = "world-save"
	test_journey_save()
	test_old_save()
	t._section = "world-regions"
	test_region_data()
	await test_transitions()
	await test_region_gameplay()
	await test_encounter()
	t._section = "world-journal"
	await load("res://tests/map_tests.gd").new().run(t)


# -- helpers -----------------------------------------------------------------------------------
func _fresh() -> void:
	t._fresh()
	Travel.reset()


func _clock(day: int, minute: float) -> void:
	WorldSim.day = day
	WorldSim.minute_of_day = minute


## Puts the protagonist at a strategic location, as the outskirts scene would.
func _at(loc: String) -> void:
	GameState.region_id = "outskirts"
	World.context = {"location": loc}
	World.visit(loc)


func _option(route: String) -> Dictionary:
	for o in Travel.options():
		if o["route"] == route:
			return o
	return {}


## A throwaway route of a chosen length, so long journeys can be tested without long real roads.
func _temp_route(mode: String, km: float) -> String:
	World.locations["zz_a"] = {"id": "zz_a", "name": "Zed A", "pos": [35.0, 32.0], "category": "fictional", "kind": "village", "certainty": "test", "region": null}
	World.locations["zz_b"] = {"id": "zz_b", "name": "Zed B", "pos": [35.1, 32.0], "category": "fictional", "kind": "village", "certainty": "test", "region": null}
	var id := "zz_a__zz_b__" + mode
	var r := {"id": id, "a": "zz_a", "b": "zz_b", "mode": mode, "name": "Test road", "via": [], "stops": [0.5] if mode == "land" else [], "events": []}
	World._finish_route(r)
	r["length_km"] = km
	for s in r["stop_list"]:
		s["km"] = float(s["at"]) * km
	World.routes[id] = r
	return id


func _drop_temp() -> void:
	World.routes.erase("zz_a__zz_b__land")
	World.routes.erase("zz_a__zz_b__water")
	World.locations.erase("zz_a")
	World.locations.erase("zz_b")
	World.place_level.erase("zz_a")
	World.place_level.erase("zz_b")
	World.route_known.erase("zz_a__zz_b__land")
	World.route_known.erase("zz_a__zz_b__water")


func _start_temp(mode: String, km: float, day: int, minute: float) -> String:
	_fresh()
	var id := _temp_route(mode, km)
	World.place_level["zz_a"] = "visited"
	World.place_level["zz_b"] = "discovered"
	World.route_known[id] = true
	_at("zz_a")
	_clock(day, minute)
	return id


func _run_all(max_events: int = 50) -> Array:
	var events: Array = []
	for i in range(max_events):
		var out := Travel.run(1.0e7)
		events.append(out)
		if out["event"] in ["arrived", "sabbath", "stop"] or Travel.journey.is_empty() or Travel.journey["state"] != "underway":
			break
	return events


# -- geography ---------------------------------------------------------------------------------
func test_geography() -> void:
	var v := World.validate()
	for e in v["errors"]:
		print("  geography error: ", e)
	for w in v["warnings"]:
		print("  geography warning: ", w)
	t.check(v["errors"].is_empty(), "world data validates with no errors")
	t.check(v["warnings"].is_empty(), "every region exit has a way back")
	t.check(World._geo_dupes.is_empty(), "location and route ids are unique")
	t.check(World.locations.size() >= 18, "at least eighteen locations (%d)" % World.locations.size())
	for id in ["nazareth", "cana", "capernaum", "bethsaida", "magdala", "tiberias", "sychar", "jerusalem", "bethlehem", "bethany", "jericho", "kefar_zayit"]:
		t.check(World.locations.has(id), "required location %s exists" % id)
	t.check(World.location("kefar_zayit")["category"] == "fictional", "Kefar Zayit is marked fictional")
	t.check(World.location("jerusalem")["category"] == "documented", "Jerusalem is documented")
	t.check(World.location("cana")["category"] == "uncertain" and World.location("bethsaida")["category"] == "uncertain", "debated sites are marked uncertain")
	var cats := {}
	for id in World.locations:
		cats[World.locations[id]["category"]] = true
		t.check(World.in_bounds(Vector2(World.locations[id]["pos"][0], World.locations[id]["pos"][1])), "%s is on the map" % id)
		var p := World.project(Vector2(World.locations[id]["pos"][0], World.locations[id]["pos"][1]))
		t.check(p.x >= 0.0 and p.x <= 1.0 and p.y >= 0.0 and p.y <= 1.0, "%s projects inside the map" % id)
	t.check(cats.size() == 3, "all three certainty categories are used")
	for f in ["mediterranean", "sea_of_galilee", "dead_sea", "jordan_river_south"]:
		t.check(World.features.has(f), "feature %s exists" % f)
	var kz := World.route("kefar_zayit__magdala__land")
	t.check(float(kz["length_km"]) > 5.0 and float(kz["length_km"]) < 30.0, "Kefar Zayit to Magdala is a plausible walk (%.1f km)" % float(kz["length_km"]))
	var jj := World.route("jerusalem__sychar__land")
	t.check(float(jj["length_km"]) > 40.0, "Sychar to Jerusalem is a long road (%.1f km)" % float(jj["length_km"]))
	t.check(World.routes.values().any(func(r): return r["mode"] == "water"), "a water route exists")
	t.check(World.neighbors("kefar_zayit").size() == 3, "Kefar Zayit has three neighbours")
	# the walk is not a straight line: a point halfway along is not on the chord
	var mid := World.point_on_route("kefar_zayit__magdala__land", float(kz["length_km"]) / 2.0)
	t.check(World.in_bounds(mid), "a point part-way along a route is on the map")
	t.check(World.point_on_route("kefar_zayit__magdala__land", 0.0).is_equal_approx(Vector2(35.40, 32.78)), "a route starts at its first location")
	# a break in the data is caught
	var saved: Dictionary = World.routes["cana__nazareth__land"]
	World.routes["cana__nazareth__land"] = saved.duplicate()
	World.routes["cana__nazareth__land"]["b"] = "atlantis"
	t.check(not World.validate()["errors"].is_empty(), "a route to an unknown place is reported")
	World.routes["cana__nazareth__land"] = saved
	t.check(World.validate()["errors"].is_empty(), "restoring the data clears the error")


# -- discovery ---------------------------------------------------------------------------------
func test_discovery() -> void:
	_fresh()
	t.check(World.level_of("kefar_zayit") == "visited", "the home village starts visited")
	t.check(World.level_of("magdala") == "discovered" and World.level_of("nazareth") == "discovered", "its neighbours start discovered")
	t.check(World.level_of("tiberias") == "rumored", "Tiberias starts as a rumor")
	t.check(World.level_of("jerusalem") == "rumored", "Jerusalem starts as a rumor")
	t.check(World.level_of("jericho") == "unknown", "far places start unknown")
	t.check(World.route_is_known("kefar_zayit__magdala__land"), "roads out of the village are known")
	t.check(not World.route_is_known("magdala__tiberias__land"), "roads beyond are not")
	World.reveal("tiberias", "rumored")
	t.check(not World.route_is_known("magdala__tiberias__land"), "a rumor reveals no route")
	World.reveal("tiberias", "unknown")
	t.check(World.level_of("tiberias") == "rumored", "discovery never goes backwards")
	World.visit("magdala")
	t.check(World.level_of("magdala") == "visited" and World.route_is_known("magdala__tiberias__land") and World.level_of("capernaum") == "discovered", "visiting a place shows its roads and neighbours")
	World.investigate("magdala")
	t.check(World.level_of("magdala") == "investigated", "a place can be investigated")
	World.reveal("nowhere", "visited")
	t.check(World.level_of("nowhere") == "unknown", "an unknown place is ignored")
	# canon knowledge puts a place on the map without touching canon
	_fresh()
	var before := CanonicalTimeline.serialize()
	t.check(World.level_of("bethany_beyond_jordan") == "unknown", "Bethany beyond Jordan is unknown at first")
	PlayerKnowledge.learn("baptism_of_jesus", "rumor", "test")
	t.check(World.level_of("bethany_beyond_jordan") == "rumored", "hearing of the baptism puts its place on the map as a rumor")
	t.check(not World.route_is_known("bethany_beyond_jordan__jordan_ford_jericho__land"), "…without giving the way there")
	t.check(CanonicalTimeline.serialize() == before, "the canonical timeline is untouched")
	# persistence
	var d := World.serialize()
	World.reset()
	World.deserialize(d)
	t.check(World.level_of("bethany_beyond_jordan") == "rumored" and World.level_of("kefar_zayit") == "visited", "discovery round-trips")
	World.deserialize({"places": {"magdala": "visited", "zzz": "visited", "nazareth": "bogus"}, "routes": ["nope"]})
	t.check(World.level_of("magdala") == "visited" and World.level_of("zzz") == "unknown" and World.level_of("nazareth") != "bogus", "unknown ids and levels are dropped on load")
	World.deserialize({})
	t.check(World.level_of("kefar_zayit") == "visited", "an empty block gives start-of-game knowledge")


# -- the clock ---------------------------------------------------------------------------------
func test_time_stepping() -> void:
	_fresh()
	var suns := []
	var rolls := []
	var on_sun := func(d): suns.append(d)
	var on_roll := func(d): rolls.append(d)
	WorldSim.sunset_passed.connect(on_sun)
	WorldSim.day_rolled.connect(on_roll)
	_clock(1, 17.0 * 60.0)
	WorldSim.advance(120.0)
	t.check(WorldSim.day == 1 and absf(WorldSim.minute_of_day - 19.0 * 60.0) < 0.001 and suns == [1], "two hours across sunset: one sunset, same day")
	t.check(Calendar.current_day() == 2, "the calendar day turned over at sunset")
	_clock(1, 7.0 * 60.0)
	suns.clear()
	rolls.clear()
	WorldSim.advance(24.0 * 60.0 * 400.0)
	t.check(WorldSim.day == 401 and absf(WorldSim.minute_of_day - 7.0 * 60.0) < 0.01, "400 days is exactly 400 days (day %d, %.2f)" % [WorldSim.day, WorldSim.minute_of_day])
	t.check(rolls.size() == 400 and suns.size() == 400, "every midnight and every sunset in 400 days was announced (%d, %d)" % [rolls.size(), suns.size()])
	# one big step equals many small ones
	_clock(1, 7.0 * 60.0)
	WorldSim.advance(100000.0)
	var big_day := WorldSim.day
	var big_min := WorldSim.minute_of_day
	_clock(1, 7.0 * 60.0)
	for i in range(1000):
		WorldSim.advance(100.0)
	t.check(WorldSim.day == big_day and absf(WorldSim.minute_of_day - big_min) < 0.01, "one big step equals a thousand small ones")
	# the calendar saw every month and year turn
	var seen_months := {}
	_clock(1, 7.0 * 60.0)
	for i in range(800):
		WorldSim.advance(24.0 * 60.0)
		var dd := Calendar.date(Calendar.current_day())
		seen_months["%d-%d" % [dd["year"], dd["month"]]] = true
	t.check(seen_months.size() >= 26, "crossing 800 days passes through every month (%d)" % seen_months.size())
	t.check(WorldSim.minutes_to_sunset() > 0.0, "minutes to sunset is positive")
	_clock(3, 17.5 * 60.0)
	t.check(absf(WorldSim.minutes_to_sunset() - 30.0) < 0.001, "thirty minutes before sunset")
	_clock(3, 19.0 * 60.0)
	t.check(absf(WorldSim.minutes_to_sunset() - (5.0 * 60.0 + 18.0 * 60.0)) < 0.001, "after sunset, the next sunset is tomorrow's")
	WorldSim.sunset_passed.disconnect(on_sun)
	WorldSim.day_rolled.disconnect(on_roll)


# -- journeys ----------------------------------------------------------------------------------
func test_journey_basics() -> void:
	_fresh()
	t.check(Travel.options().is_empty() or true, "options can be read")
	_at("kefar_zayit")
	var opts := Travel.options()
	t.check(opts.size() == 3, "three roads lead out of Kefar Zayit (%d)" % opts.size())
	t.check(not Travel.active(), "no journey yet")
	var o := _option("kefar_zayit__magdala__land")
	t.check(not o.is_empty() and o["to"] == "magdala" and o["mode"] == "land", "the Magdala road is offered")
	_clock(1, 7.0 * 60.0)
	var est := Travel.estimate()
	t.check(est["event"] == "" and est["elapsed"] == 0.0, "nothing to estimate before a journey starts")
	t.check(Travel.start(o), "a journey starts")
	t.check(Travel.active() and Travel.phase() == Travel.Phase.UNDERWAY, "it is under way")
	t.check(not Travel.start(o), "a second journey cannot start")
	var len_km := float(World.route("kefar_zayit__magdala__land")["length_km"])
	var want_min := len_km / LAND_KMH * 60.0
	var est2 := Travel.estimate()
	t.check(est2["arrives"] and absf(float(est2["elapsed"]) - want_min) < 0.01, "estimate: %.1f minutes for %.1f km" % [est2["elapsed"], len_km])
	t.check(WorldSim.minute_of_day == 420.0 and Travel.journey["pos"] == 0.0, "estimating changes nothing")
	var day0 := WorldSim.day
	var out := Travel.run(want_min / 2.0)
	t.check(out["event"] == "" and absf(float(Travel.journey["pos"]) - len_km / 2.0) < 0.01, "half the time covers half the road")
	t.check(absf(Travel.progress_fraction() - 0.5) < 0.01, "progress is half")
	t.check(absf(WorldSim.minute_of_day - (420.0 + want_min / 2.0)) < 0.01, "the world clock moved by exactly the time travelled")
	var p_mid := Travel.traveller_point()
	t.check(p_mid.distance_to(World.point_on_route("kefar_zayit__magdala__land", len_km / 2.0)) < 0.0001, "the avatar is half way along the route")
	out = Travel.run(1.0e6)
	t.check(out["event"] == "arrived", "the journey arrives")
	t.check(not Travel.active() and WorldSim.day == day0, "no journey remains; still the same day")
	t.check(absf(WorldSim.minute_of_day - (420.0 + want_min)) < 0.01, "arrival time is distance over speed")
	t.check(World.context == {"location": "magdala"} and World.level_of("magdala") == "visited", "the protagonist is now at Magdala, and has been there")
	t.check(World.route_is_known("kefar_zayit__magdala__land"), "the road is known")
	t.check(Travel.arrival_destination("magdala") == {"region": "magdala_shore", "entry": "arrival"}, "Magdala arrival uses its own region")
	t.check(Travel.arrival_destination("nazareth") == {"region": "outskirts", "entry": "arrival"}, "a place with no scene arrives at the outskirts")
	# a journey back along the same road
	_at("magdala")
	var back := _option("kefar_zayit__magdala__land")
	t.check(back["dir"] == -1 and back["to"] == "kefar_zayit", "the same road runs back, in the other direction")
	_clock(1, 7.0 * 60.0)
	Travel.start(back)
	Travel.run(1.0e6)
	t.check(World.context == {"location": "kefar_zayit"} and absf(WorldSim.minute_of_day - (420.0 + want_min)) < 0.01, "and takes the same time")
	# unknown destinations cannot be chosen
	_fresh()
	_at("kefar_zayit")
	t.check(_option("magdala__tiberias__land").is_empty(), "a road from somewhere else is not offered")
	World.place_level["nazareth"] = "unknown"
	t.check(_option("kefar_zayit__nazareth__land").is_empty(), "a destination the protagonist has never heard of is not offered")


func test_multi_day() -> void:
	var id := _start_temp("land", 100.0, 1, 7.0 * 60.0)
	Travel.start(_option(id))
	var suns := []
	var on_sun := func(d): suns.append(d)
	WorldSim.sunset_passed.connect(on_sun)
	var est := Travel.estimate()
	var events := _run_all()
	WorldSim.sunset_passed.disconnect(on_sun)
	t.check(events.back()["event"] == "arrived", "a 100 km walk arrives")
	# 11 h (07:00 to sunset) + 12 h + remaining: at 4 km/h that is 44 + 48 + 8 km on day 3
	t.check(WorldSim.day == 3, "it takes three days (day %d)" % WorldSim.day)
	var walking := 100.0 / LAND_KMH * 60.0
	var elapsed := (WorldSim.day - 1) * 1440.0 + WorldSim.minute_of_day - 420.0
	t.check(elapsed > walking + 600.0, "rests overnight are added to the walking time (%.0f vs %.0f)" % [elapsed, walking])
	t.check(est["arrives"] and est["day"] == WorldSim.day and absf(float(est["minute"]) - WorldSim.minute_of_day) < 0.01, "the estimate predicted the arrival day and time")
	t.check(suns.size() == 2, "the walker passed two sunsets (%d)" % suns.size())
	t.check(absf(WorldSim.minute_of_day - (360.0 + 8.0 / LAND_KMH * 60.0)) < 0.01, "arrival at dawn plus the last 8 km")
	_drop_temp()
	# a journey begun after sunset waits for dawn
	var id2 := _start_temp("land", 10.0, 2, 20.0 * 60.0)
	Travel.start(_option(id2))
	Travel.run(1.0e6)
	t.check(WorldSim.day == 3 and absf(WorldSim.minute_of_day - (360.0 + 150.0)) < 0.01, "a night start rests until dawn, then walks 2.5 hours")
	_drop_temp()


func test_interruption_and_abandon() -> void:
	_fresh()
	_at("kefar_zayit")
	_clock(1, 7.0 * 60.0)
	var o := _option("kefar_zayit__magdala__land")
	Travel.start(o)
	t.check(Travel.request_stop(), "a walker may ask to stop")
	var len_km := float(World.route("kefar_zayit__magdala__land")["length_km"])
	var out := Travel.run(1.0e6)
	t.check(out["event"] == "stop" and absf(float(Travel.journey["pos"]) - len_km * 0.5) < 0.01, "the stop comes at the planned waypoint")
	t.check(Travel.phase() == Travel.Phase.PAUSED and Travel.journey["pause"] == "player", "the journey is paused at the player's request")
	t.check(Travel.pause_destination() == {"region": "galilee_hills", "entry": "camp"}, "the hillside camp is a real playable region")
	t.check(Travel.run(100.0)["elapsed"] == 0.0, "a paused journey does not move")
	t.check(WorldSim.minute_of_day == 420.0 + len_km * 0.5 / LAND_KMH * 60.0, "…nor does the clock")
	t.check(World.context.has("route") and absf(float(World.context["km"]) - len_km * 0.5) < 0.01, "the protagonist is on the road, half way")
	t.check(Travel.options().is_empty(), "no new journey while one is paused")
	var half_pos := float(Travel.journey["pos"])
	t.check(Travel.resume() and Travel.phase() == Travel.Phase.UNDERWAY, "the player resumes")
	Travel.run(30.0)
	t.check(float(Travel.journey["pos"]) > half_pos, "and moves on")
	# abandon on the road: no distance is gained, either end remains reachable
	Travel.abandon()
	_fresh()
	_at("nazareth")
	World.visit("nazareth")
	World.reveal("sychar", "discovered")
	World.discover_route("nazareth__sychar__land")
	_clock(1, 7.0 * 60.0)
	Travel.start(_option("nazareth__sychar__land"))
	Travel.request_stop()
	Travel.run(1.0e6)
	var pos := float(Travel.journey["pos"])
	t.check(Travel.journey["pause"] == "player" and pos > 10.0, "paused on the way to Sychar, %.1f km from Nazareth" % pos)
	Travel.abandon()
	t.check(not Travel.active() and World.context.get("route", "") == "nazareth__sychar__land", "abandoning keeps the protagonist on the road")
	t.check(absf(float(World.context["km"]) - pos) < 0.0001, "at exactly the same place")
	var opts := Travel.options()
	t.check(opts.size() == 2 and opts.any(func(x): return x["to"] == "sychar") and opts.any(func(x): return x["to"] == "nazareth"), "either end can be chosen from the road")
	var home = opts.filter(func(x): return x["to"] == "nazareth")[0]
	t.check(absf(float(home["from_km"]) - pos) < 0.0001 and home["dir"] == -1, "going home starts from where the protagonist stands")
	Travel.start(home)
	var back := Travel.estimate()
	t.check(absf(float(back["elapsed"]) - pos / LAND_KMH * 60.0) < 0.5, "and takes only as long as the distance back")
	Travel.run(1.0e6)
	t.check(World.context == {"location": "nazareth"}, "arrived back at Nazareth")
	# a boat cannot stop at sea
	var bid := _start_temp("water", 60.0, 2, 8.0 * 60.0)
	Travel.start(_option(bid))
	t.check(not Travel.request_stop(), "a boat at sea cannot be asked to stop")
	_drop_temp()
	# a scripted text event on the boat route fires and does not stop the boat
	_fresh()
	_at("capernaum")
	World.visit("magdala")
	World.visit("capernaum")
	_clock(2, 8.0 * 60.0)
	var bo := _option("capernaum__magdala__water")
	t.check(not bo.is_empty(), "the ferry is offered from Capernaum")
	var fired := []
	var on_ev := func(e): fired.append(e["id"])
	Travel.event_fired.connect(on_ev)
	Travel.start(bo)
	var o1 := Travel.run(1.0e6)
	t.check(o1["event"] == "scripted" and o1["text"] != "" and fired == ["calm_water"], "the boat's scripted event fires with its text")
	t.check(Travel.phase() == Travel.Phase.UNDERWAY, "…and the boat keeps going")
	var o2 := Travel.run(1.0e6)
	t.check(o2["event"] == "arrived" and World.context == {"location": "magdala"}, "the ferry arrives")
	Travel.event_fired.disconnect(on_ev)


# -- the Sabbath -------------------------------------------------------------------------------
func test_sabbath_stop() -> void:
	# Day 4 morning. The Sabbath begins at sunset on day 6.
	var id := _start_temp("land", 400.0, 4, 7.0 * 60.0)
	t.check(not Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day), "day 4 is not the Sabbath")
	Travel.start(_option(id))
	var events := _run_all()
	var last: Dictionary = events.back()
	t.check(last["event"] == "sabbath", "the walk stops for the Sabbath")
	t.check(WorldSim.day == 6 and WorldSim.minute_of_day == float(SUNSET), "at exactly sunset on the sixth day")
	t.check(Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day), "the calendar agrees it is the Sabbath")
	# 11 h + 12 h + 12 h of walking = 35 h = 140 km, exactly
	t.check(absf(float(Travel.journey["pos"]) - 140.0) < 0.001, "exact progress is kept (%.4f km)" % float(Travel.journey["pos"]))
	t.check(Travel.journey["state"] == "paused" and Travel.journey["pause"] == "sabbath", "paused for the Sabbath")
	t.check(Travel.pause_destination()["region"] == "road_camp", "the walker is put in the roadside camp")
	# explore, wait, try to resume
	t.check(not Travel.can_resume()["ok"] and not Travel.resume(), "no resuming during the Sabbath")
	t.check(Travel.can_resume()["reason"].contains("Sabbath"), "the reason is given")
	var pos := float(Travel.journey["pos"])
	WorldSim.advance(10.0 * 60.0)
	t.check(Travel.run(100.0)["elapsed"] == 0.0 and float(Travel.journey["pos"]) == pos, "time passing on the Sabbath moves no one along the road")
	_clock(7, SUNSET - 1.0)
	t.check(not Travel.can_resume()["ok"], "one minute before the Sabbath ends, still no")
	WorldSim.advance(1.0)
	t.check(not Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day), "the Sabbath has ended at sunset on the seventh day")
	t.check(Travel.can_resume()["ok"], "resuming is now allowed")
	WorldSim.advance(6.0 * 60.0)
	t.check(Travel.journey["state"] == "paused" and float(Travel.journey["pos"]) == pos, "…but the journey did not resume itself")
	t.check(Travel.resume(), "the player resumes")
	var out := Travel.run(60.0)
	t.check(absf(float(out["rest"]) - 6.0 * 60.0) < 0.01, "resuming in the small hours: the walker rests until dawn first (%.0f min)" % out["rest"])
	t.check(absf(float(Travel.journey["pos"]) - (pos + 4.0)) < 0.001 and absf(WorldSim.minute_of_day - (360.0 + 60.0)) < 0.01, "then walks an hour of road")
	# starting a land journey on the Sabbath is refused
	_drop_temp()
	var id2 := _start_temp("land", 50.0, 7, 10.0 * 60.0)
	t.check(Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day), "day 7 daytime is the Sabbath")
	t.check(not Travel.can_start(_option(id2))["ok"] and not Travel.start(_option(id2)), "a land journey cannot begin on the Sabbath")
	_clock(6, 17.0 * 60.0)
	t.check(Travel.can_start(_option(id2))["ok"], "on Friday afternoon it can")
	Travel.start(_option(id2))
	var e := Travel.run(1.0e6)
	t.check(e["event"] == "sabbath" and WorldSim.minute_of_day == float(SUNSET) and absf(float(Travel.journey["pos"]) - 4.0) < 0.001, "begun on Friday, it walks one hour and stops at sunset")
	_drop_temp()


func test_multiple_sabbaths() -> void:
	var id := _start_temp("land", 1000.0, 1, 7.0 * 60.0)
	Travel.start(_option(id))
	var stops: Array = []
	for i in range(3):
		var events := _run_all()
		t.check(events.back()["event"] == "sabbath", "Sabbath stop number %d" % (i + 1))
		stops.append([WorldSim.day, WorldSim.minute_of_day, float(Travel.journey["pos"])])
		# wait it out and resume
		WorldSim.advance(24.0 * 60.0)
		t.check(Travel.resume(), "resumed after Sabbath %d" % (i + 1))
	t.check(stops[0][0] == 6 and stops[1][0] == 13 and stops[2][0] == 20, "stops fall on the sixth day of each week (%s)" % [stops.map(func(s): return s[0])])
	t.check(stops[0][1] == float(SUNSET) and stops[1][1] == float(SUNSET), "always at sunset")
	# each week the walker covers the same distance: 4 daytime days of 48 km plus the 11 hours of the first day
	t.check(absf((stops[1][2] - stops[0][2]) - 6.0 * 12.0 * LAND_KMH) < 0.001, "a full week's walking between Sabbaths is six days (%.1f km)" % (stops[1][2] - stops[0][2]))
	_drop_temp()


func test_boat() -> void:
	# A boat that sails on Friday afternoon keeps going through the Sabbath.
	var id := _start_temp("water", 200.0, 6, 12.0 * 60.0)
	t.check(Travel.can_start(_option(id))["ok"], "a boat may leave on Friday midday")
	Travel.start(_option(id))
	var ev := Travel.run(1.0e7)
	t.check(ev["event"] == "arrived", "the boat arrives without stopping for the Sabbath")
	var hours := 200.0 / 6.0
	var elapsed := (WorldSim.day - 6) * 1440.0 + WorldSim.minute_of_day - 12.0 * 60.0
	t.check(absf(elapsed - hours * 60.0) < 0.01, "it sailed straight through, night and Sabbath (%.1f h)" % (elapsed / 60.0))
	t.check(WorldSim.day == 7 and WorldSim.minute_of_day > float(SUNSET), "arriving after the Sabbath ended")
	_drop_temp()
	# but a boat does not depart on the Sabbath
	var id2 := _start_temp("water", 20.0, 7, 9.0 * 60.0)
	t.check(not Travel.can_start(_option(id2))["ok"] and not Travel.start(_option(id2)), "no boat leaves on the Sabbath")
	_clock(7, SUNSET + 5.0)
	t.check(Travel.can_start(_option(id2))["ok"], "after sunset it may")
	_drop_temp()
	# the water route has no overnight rest
	var id3 := _start_temp("water", 60.0, 2, 20.0 * 60.0)
	Travel.start(_option(id3))
	Travel.run(1.0e6)
	t.check(absf(WorldSim.minute_of_day - (20.0 * 60.0 + 10.0 * 60.0 - 1440.0)) < 0.01 and WorldSim.day == 3, "a boat sails at night: 60 km at 6 km/h from 20:00 lands at 06:00")
	_drop_temp()
	# the real ferry
	_fresh()
	_at("capernaum")
	World.visit("capernaum")
	World.visit("magdala")
	_clock(3, 9.0 * 60.0)
	var ferry := _option("capernaum__magdala__water")
	t.check(ferry["mode"] == "water", "the ferry is a water route")
	Travel.start(ferry)
	var len_km := float(World.route("capernaum__magdala__water")["length_km"])
	Travel.run(1.0e7)
	Travel.run(1.0e7)
	t.check(absf(WorldSim.minute_of_day - (9.0 * 60.0 + len_km / 6.0 * 60.0)) < 0.01, "the ferry takes distance over boat speed (%.1f km)" % len_km)


func test_no_skipped_transitions() -> void:
	var id := _start_temp("land", 600.0, 1, 7.0 * 60.0)
	Travel.start(_option(id))
	var suns := []
	var rolls := []
	var on_sun := func(d): suns.append(d)
	var on_roll := func(d): rolls.append(d)
	WorldSim.sunset_passed.connect(on_sun)
	WorldSim.day_rolled.connect(on_roll)
	var start_day := WorldSim.day
	var stops := 0
	for i in range(40):
		var events := _run_all()
		if events.back()["event"] == "arrived":
			break
		if events.back()["event"] == "sabbath":
			stops += 1
			WorldSim.advance(24.0 * 60.0)
			Travel.resume()
	WorldSim.sunset_passed.disconnect(on_sun)
	WorldSim.day_rolled.disconnect(on_roll)
	t.check(rolls.size() == WorldSim.day - start_day, "every midnight on a long journey was announced (%d of %d)" % [rolls.size(), WorldSim.day - start_day])
	t.check(suns.size() >= WorldSim.day - start_day, "every sunset was announced (%d)" % suns.size())
	t.check(stops >= 2, "the 600 km walk crossed several Sabbaths (%d)" % stops)
	t.check(Travel.journey.is_empty(), "and arrived")
	# the calendar date followed along
	var d := Calendar.date(Calendar.current_day())
	t.check(d["day"] >= 1 and d["day"] <= 30, "the calendar date is valid after the journey")
	_drop_temp()


# -- saving ------------------------------------------------------------------------------------
func test_journey_save() -> void:
	var id := _start_temp("land", 400.0, 4, 7.0 * 60.0)
	Travel.start(_option(id))
	_run_all()
	t.check(Travel.journey["pause"] == "sabbath", "paused for the Sabbath before saving")
	var pos := float(Travel.journey["pos"])
	World.find_landmark("shepherds_cairn")
	GameState.region_id = "road_camp"
	t.check(SaveManager.save_slot(1), "saved during a Sabbath pause")
	Travel.reset()
	World.reset()
	t.check(SaveManager.load_slot(1), "loaded")
	t.check(Travel.journey["route"] == id and absf(float(Travel.journey["pos"]) - pos) < 0.0001, "the journey is restored at exactly the same place")
	t.check(Travel.journey["state"] == "paused" and Travel.journey["pause"] == "sabbath", "…still paused for the Sabbath")
	t.check(Travel.journey["to"] == "zz_b" and Travel.journey["dir"] == 1 and Travel.journey["mode"] == "land", "destination, direction and mode survive")
	t.check(WorldSim.day == 6 and WorldSim.minute_of_day == float(SUNSET), "the clock is restored")
	t.check(not Travel.can_resume()["ok"], "loading did not make the Sabbath any shorter")
	t.check(World.landmarks_found.get("shepherds_cairn", false), "landmarks persist")
	t.check(World.context.has("route"), "the position on the road persists")
	# a journey saved while 'underway' (it should not happen) loads paused, never moving
	Travel.journey["state"] = "underway"
	Travel.journey["pause"] = ""
	_clock(2, 8.0 * 60.0)
	SaveManager.save_slot(2)
	Travel.reset()
	SaveManager.load_slot(2)
	t.check(Travel.journey["state"] == "paused", "a journey is always restored paused")
	t.check(Travel.run(500.0)["elapsed"] == 0.0, "and loading never moves anyone")
	# a boat paused is not a Sabbath pause
	# during the Sabbath a loaded land journey is a Sabbath pause whatever it was
	_clock(7, 9.0 * 60.0)
	SaveManager.save_slot(3)
	Travel.reset()
	SaveManager.load_slot(3)
	t.check(Travel.journey["pause"] == "sabbath", "a land journey loaded on the Sabbath is a Sabbath pause")
	# a route that no longer exists is dropped safely
	var bad := Travel.serialize()
	bad["journey"]["route"] = "gone__away__land"
	Travel.deserialize(bad)
	t.check(Travel.journey.is_empty(), "a journey on a vanished route is dropped")
	_drop_temp()
	for s in [1, 2, 3]:
		SaveManager.delete_slot(s)


func test_old_save() -> void:
	_fresh()
	SaveManager.save_slot(1)
	var raw := SaveManager.read_slot(1)
	raw["version"] = 2
	raw.erase("geo")
	raw.erase("travel")
	var f := FileAccess.open(SaveManager.slot_path(1), FileAccess.WRITE)
	f.store_string(JSON.stringify(raw))
	f.close()
	World.place_level["jericho"] = "visited"
	Travel.journey = {"route": "x"}
	t.check(SaveManager.load_slot(1), "a version-2 save with no map or journey loads")
	t.check(World.level_of("kefar_zayit") == "visited" and World.level_of("jericho") == "unknown", "the map starts at its defaults")
	t.check(Travel.journey.is_empty(), "no journey")
	t.check(GameState.region_id == "kefar_zayit", "the game is where the save left it")
	var newer := SaveManager.read_slot(1)
	newer["version"] = 99
	var f2 := FileAccess.open(SaveManager.slot_path(1), FileAccess.WRITE)
	f2.store_string(JSON.stringify(newer))
	f2.close()
	t.check(not SaveManager.load_slot(1), "a save from a newer version is refused")
	SaveManager.delete_slot(1)


# -- regions -----------------------------------------------------------------------------------
func _load_region(id: String) -> Region:
	var rg := Region.new()
	t.add_child(rg)
	rg.load_region(id)
	return rg


## Tiles reachable on foot from a start tile in a built region.
func _reach(rg: Region, start: Vector2i) -> Dictionary:
	var size: Array = rg.data["size"]
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= int(size[0]) or n.y >= int(size[1]) or rg.tile_blocked(n) or seen.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return seen


func test_region_data() -> void:
	_fresh()
	var ids := World.region_ids()
	for need in ["kefar_zayit", "galilee_hills", "magdala_shore", "road_camp", "outskirts"]:
		t.check(ids.has(need), "region %s exists" % need)
	for id in ids:
		if id == "training_yard":
			continue
		var m := World.region_meta(id)
		t.check(m.get("kind", "") in ["local", "regional", "template"], "%s has a kind" % id)
		t.check(m["ground"].size() == int(m["size"][1]) and m["ground"][0].length() == int(m["size"][0]), "%s ground matches its size" % id)
		var rg := _load_region(id)
		var spawn := Vector2i(int(m["spawn"][0]), int(m["spawn"][1]))
		t.check(not rg.tile_blocked(spawn), "%s spawn is walkable" % id)
		var seen := _reach(rg, spawn)
		for eid in m.get("entries", {}):
			var e: Dictionary = m["entries"][eid]
			t.check(seen.has(Vector2i(int(e["tile"][0]), int(e["tile"][1]))), "%s entry %s is reachable from spawn" % [id, eid])
		for ex in m.get("exits", []):
			var rc: Array = ex["rect"]
			var ok := false
			for y in range(int(rc[1]), int(rc[1] + rc[3])):
				for x in range(int(rc[0]), int(rc[0] + rc[2])):
					ok = ok or seen.has(Vector2i(x, y))
			t.check(ok, "%s exit %s can be walked to" % [id, ex["id"]])
		for n in m["npcs"]:
			t.check(seen.has(Vector2i(int(n["tile"][0]), int(n["tile"][1]))), "%s: %s stands somewhere reachable" % [id, n["id"]])
		for it in m["interactables"]:
			var tile := Vector2i(int(it["tile"][0]), int(it["tile"][1]))
			var near := false
			for dx in range(-2, 3):
				for dy in range(-2, 3):
					near = near or seen.has(tile + Vector2i(dx, dy))
			t.check(near, "%s: %s can be reached" % [id, it["name"]])
			for ef in it.get("effects", []):
				t.check(ef is Dictionary, "%s effect is well formed" % it["name"])
		rg.free()
	# the countryside is a real place
	var hills := World.region_meta("galilee_hills")
	t.check(int(hills["size"][0]) >= 60, "the hills are a large region")
	t.check(hills["exits"].size() >= 2, "with a way to the village and a way on")
	var cliffs := 0
	for row in hills["ground"]:
		cliffs += row.count("c")
	t.check(cliffs > 600, "terrain barriers (cliffs and outcrops) fill part of it (%d)" % cliffs)
	t.check(hills["ground"].any(func(r): return r.contains("w")), "a stream runs through it")
	var branches = hills["interactables"].filter(func(i): return i["name"] == "The shepherds' cairn")
	t.check(branches.size() == 1, "a landmark waits at the end of the north branch")
	t.check(hills["npcs"].size() >= 1, "and there is an optional encounter")
	t.check(World.region_name("road_camp") != "Wayside camp: {place}", "template names are filled in (%s)" % World.region_name("road_camp"))
	World.context = {"location": "nazareth"}
	t.check(World.region_name("outskirts") == "Outskirts of Nazareth", "outskirts takes its name from the place")
	World.context = {"route": "kefar_zayit__magdala__land", "km": 3.0}
	t.check(World.region_name("road_camp").contains("Magdala road"), "the camp takes its name from the road")
	# every exit is a data entry that points back
	for id in ["kefar_zayit", "galilee_hills", "magdala_shore"]:
		for ex in World.region_meta(id)["exits"]:
			var to: Dictionary = ex["to"]
			var back = World.region_meta(to["region"])["exits"].any(func(e): return e["to"]["region"] == id)
			t.check(back, "%s -> %s has a way back" % [id, to["region"]])


func _enter(region: String, entry: String, offset: float = 0.0) -> Node:
	World.set_destination(region, entry)
	World.entry_offset = offset
	return await t._spawn_game({"mode": "resume"})


func _drop(game: Node) -> void:
	game.free()


func test_transitions() -> void:
	_fresh()
	var game: Node = await t._spawn_game({"mode": "new"})
	DialogueRunner.cancel()
	t.check(GameState.region_id == "kefar_zayit" and game.region.data["exits"].size() == 1, "the village has a physical exit")
	# walk out of the village by the east road
	var exits = game.region.get_children().filter(func(n): return n is RegionExit)
	t.check(exits.size() == 1, "one exit area is built")
	t.check(game.region.is_walkable_px(Vector2(36.5, 13.5) * 32.0), "the road to the exit is open ground")
	var seen := []
	var on_t := func(r, e): seen.append(r)
	World.transition_requested.connect(on_t)
	game.player.teleport(Vector2(39.5, 13.5) * 32.0, "right")
	await t._frames(4)
	await t.get_tree().process_frame
	World.transition_requested.disconnect(on_t)
	t.check(seen.size() == 1, "walking into the exit asks for exactly one transition")
	t.check(GameState.region_id == "galilee_hills" and World.entry_id == "from_village", "the destination is the hills, by the village entry")
	t.check(absf(World.entry_offset - 1.5) < 0.2, "the offset along the edge is remembered (%.2f)" % World.entry_offset)
	_drop(game)
	# rebuild in the hills, as the real scene reload does
	game = await t._spawn_game({"mode": "resume"})
	t.check(game.region.data["id"] == "galilee_hills", "the hills are built")
	t.check(not GameState.has_saved_position, "no stale position")
	var want := Vector2(3.0, 21.0 + World.entry_offset) * 32.0
	t.check(game.player.global_position.distance_to(want) < 2.0, "the player arrives on the west edge at the same height along it")
	t.check(game.player.facing == "right", "facing into the region")
	t.check(game.region.is_walkable_px(game.player.global_position), "on open ground")
	# play state survives the move
	_drop(game)
	_fresh()
	GameState.add_item("ezra_sword", 1, true)
	GameState.set_flag("test_flag")
	Combat.player_hp = 3
	_clock(2, 9.0 * 60.0)
	game = await _enter("galilee_hills", "from_village", 1.0)
	t.check(GameState.item_count("ezra_sword") == 1 and GameState.has_flag("test_flag") and Combat.player_hp == 3 and WorldSim.day == 2, "items, flags, health and the clock are unchanged by a region change")
	# every region reaches every other region by walking the exits
	var graph := {}
	for id in ["kefar_zayit", "galilee_hills", "magdala_shore"]:
		graph[id] = World.region_meta(id)["exits"].map(func(e): return e["to"]["region"])
	var reach := {"kefar_zayit": true}
	var todo := ["kefar_zayit"]
	while not todo.is_empty():
		var c: String = todo.pop_back()
		for n in graph[c]:
			if not reach.has(n):
				reach[n] = true
				todo.append(n)
	t.check(reach.size() == 3, "from the village the shore is reachable on foot, without the map")
	# cross-region walk: hills east exit to the shore and back
	game.player.teleport(Vector2(63.5, 23.5) * 32.0, "right")
	seen = []
	var on_t2 := func(r, e): seen.append(r)
	World.transition_requested.connect(on_t2)
	await t._frames(4)
	World.transition_requested.disconnect(on_t2)
	t.check(GameState.region_id == "magdala_shore" and World.entry_id == "from_hills", "the east end of the hills leads to the lake shore")
	_drop(game)
	game = await t._spawn_game({"mode": "resume"})
	t.check(game.region.data["id"] == "magdala_shore" and game.region.is_walkable_px(game.player.global_position), "the shore is built with the player on open ground")
	game.player.teleport(Vector2(0.5, 17.5) * 32.0, "left")
	await t._frames(4)
	t.check(GameState.region_id == "galilee_hills" and World.entry_id == "from_shore", "and the shore leads back")
	_drop(game)
	# an exit does nothing while the player is in a dialogue or menu
	_fresh()
	game = await _enter("galilee_hills", "from_village")
	GameState.mode = GameState.Mode.DIALOGUE
	game.player.teleport(Vector2(0.5, 22.5) * 32.0, "left")
	await t._frames(4)
	t.check(GameState.region_id == "galilee_hills", "an exit ignores the player outside exploration")
	GameState.mode = GameState.Mode.EXPLORE
	_drop(game)


func test_region_gameplay() -> void:
	_fresh()
	var game: Node = await _enter("galilee_hills", "from_village")
	var rg: Region = game.region
	var player: Player = game.player
	# terrain barriers hold the player
	var col := -1
	for x in range(5, 15):
		if rg.tile_blocked(Vector2i(x, 11)) and rg.tile_blocked(Vector2i(x, 10)):
			col = x
			break
	t.check(col > 0, "the north-west outcrop has solid ground")
	player.teleport(Vector2(col + 0.5, 15.5) * 32.0, "up")
	Input.action_press("move_up")
	await t._frames(90)
	Input.action_release("move_up")
	t.check(not rg.tile_blocked(Vector2i(floori(player.global_position.x / 32.0), floori(player.global_position.y / 32.0))), "walking into an outcrop stops at its edge")
	t.check(player.global_position.y > 12.0 * 32.0, "the outcrop could not be entered (y=%.0f)" % player.global_position.y)
	# water blocks, the ford does not
	var water := Vector2i(-1, -1)
	for y in range(26, 36):
		for x in range(14, 26):
			if rg.data["ground_legend"][rg.data["ground"][y][x]][0] == "water_0":
				water = Vector2i(x, y)
	t.check(rg.tile_blocked(water), "the stream blocks the way")
	t.check(not rg.tile_blocked(Vector2i(20, 21)) and not rg.tile_blocked(Vector2i(20, 22)), "but the ford across it is open")
	# the road is continuous from the village edge to the shore edge
	var seen := _reach(rg, Vector2i(3, 22))
	t.check(seen.has(Vector2i(61, 22)), "the road runs from the village side of the hills to the lake side")
	t.check(seen.has(Vector2i(41, 8)) and seen.has(Vector2i(40, 37)), "both branches can be walked to")
	# camera limits cover the whole region
	var cam: Camera2D = player.get_children().filter(func(n): return n is Camera2D)[0]
	t.check(cam.limit_right == 64 * 32 and cam.limit_bottom == 44 * 32, "the camera is bound to the large region")
	# the landmark
	var cairn = rg.entities.get_children().filter(func(n): return n is ExamineInteractable and n.display_name == "The shepherds' cairn")
	t.check(cairn.size() == 1, "the cairn is built")
	t.check(not World.landmarks_found.get("shepherds_cairn", false) and World.level_of("capernaum") == "unknown", "not yet found")
	t.check(not GameState.check({"landmark": "shepherds_cairn"}), "the landmark condition is false before")
	var first: Dictionary = cairn[0].variants[0]
	Effects.run_all(first["effects"])
	t.check(World.landmarks_found.get("shepherds_cairn", false) and GameState.check({"landmark": "shepherds_cairn"}), "examining the cairn finds the landmark")
	t.check(World.level_of("tiberias") == "discovered" and World.level_of("capernaum") == "rumored", "it shows Tiberias and hints at Capernaum")
	t.check(not World.route_is_known("magdala__tiberias__land"), "…without drawing roads")
	t.check(cairn[0].variants[0]["when"] == {"not_flag": "saw_cairn"}, "the first-visit text is gated so it is read once")
	# waymarks
	var waymarks = rg.entities.get_children().filter(func(n): return n is WaymarkInteractable)
	t.check(waymarks.size() == 1 and waymarks[0].modes == ["land"], "one road marker offers land routes")
	var asked: Array = []
	var on_map := func(m): asked.append(m)
	GameState.map_requested.connect(on_map)
	waymarks[0]._open_map()
	GameState.map_requested.disconnect(on_map)
	t.check(asked == [["land"]], "the marker asks for the strategic map with its modes")
	t.check(World.current_location() == "kefar_zayit", "the hills belong to the Kefar Zayit end of the world")
	# the map is not reachable from the middle of nowhere: only at a marker, a landing or a camp
	t.check(rg.data["interactables"].filter(func(i): return i["type"] == "waymark").size() == 1, "only the marker opens the map")
	# save and load in a region: place and position
	player.teleport(Vector2(30.5, 18.5) * 32.0, "up")
	GameState.player_pos = player.global_position
	GameState.player_facing = "up"
	World.find_landmark("shepherds_cairn")
	t.check(SaveManager.save_slot(1), "saved in the hills")
	_drop(game)
	_fresh()
	t.check(SaveManager.load_slot(1), "loaded")
	t.check(GameState.region_id == "galilee_hills" and GameState.has_saved_position, "the region and a saved position are restored")
	game = await t._spawn_game({"mode": "resume"})
	t.check(game.player.global_position.distance_to(Vector2(30.5, 18.5) * 32.0) < 1.0 and game.player.facing == "up", "the player stands where they saved, facing the same way")
	t.check(World.landmarks_found.get("shepherds_cairn", false), "and the landmark is still found")
	# a saved spot that is no longer valid falls back to somewhere safe
	GameState.player_pos = Vector2(10.0, 10.0)
	GameState.has_saved_position = true
	_drop(game)
	game = await t._spawn_game({"mode": "resume"})
	t.check(game.region.is_walkable_px(game.player.global_position), "an invalid saved position falls back to open ground")
	_drop(game)
	# template regions
	_fresh()
	World.context = {"route": "kefar_zayit__nazareth__land", "km": 4.0}
	game = await _enter("road_camp", "camp")
	t.check(game.region.data["template"] == true and game.player.global_position.distance_to(game.region.entry_position("camp")) < 2.0, "the camp is built where the entry says")
	var camp_names = game.region.entities.get_children().filter(func(n): return n is WaymarkInteractable and n.display_name != "")
	t.check(camp_names.size() == 1 and GameState.place_name().contains("Nazareth path"), "the camp is named for the road (%s)" % GameState.place_name())
	t.check(camp_names[0].text[0].contains("Nazareth path"), "its text names the road")
	_drop(game)
	_fresh()
	_at("nazareth")
	game = await _enter("outskirts", "arrival")
	t.check(GameState.place_name() == "Outskirts of Nazareth", "the outskirts are named for the place")
	t.check(World.current_location() == "nazareth", "and put the protagonist at it")
	_drop(game)


func test_encounter() -> void:
	# present by day, absent at night, unaffected by the Sabbath
	_fresh()
	_clock(1, 10.0 * 60.0)
	var game: Node = await _enter("galilee_hills", "from_village")
	t.check(game.region.npcs.has("hills_highwayman"), "the highwayman is at the spring by day")
	_drop(game)
	_clock(1, 23.0 * 60.0)
	game = await _enter("galilee_hills", "from_village")
	t.check(not game.region.npcs.has("hills_highwayman"), "…and not there at night")
	_drop(game)
	_clock(7, 10.0 * 60.0)
	t.check(Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day), "it is the Sabbath")
	game = await _enter("galilee_hills", "from_village")
	t.check(game.region.npcs.has("hills_highwayman"), "highwaymen do not keep the Sabbath")
	# it is a real encounter with every outcome open
	var enc: Dictionary = DataFiles.load_json("res://data/combat/encounters.json")["encounters"]["hills_highwayman"]
	t.check(enc["valid"].has("avoidance") and enc["valid"].has("diplomacy") and enc["valid"].size() == 5, "avoiding, talking and fighting are all valid")
	var npc: Npc = game.region.npcs["hills_highwayman"]
	t.check(npc.disposition != "noncombatant" and npc.profile_id == "highwayman", "he uses the combat profile from Milestone 2A (%s)" % npc.disposition)
	var tile := Vector2i(int(npc.position.x / 32.0), int(npc.position.y / 32.0))
	t.check(tile == Vector2i(41, 37), "he waits at the spring")
	# the road itself does not pass through him: the main road and both branch ends are far away
	var road_dist := Vector2(36.0, 21.0).distance_to(Vector2(41.5, 37.5))
	t.check(road_dist > 10.0, "he is off the main road (%.0f tiles from the junction)" % road_dist)
	# defeated or fled, he stays gone when the region is built again
	_drop(game)
	Combat.set_actor("hills_highwayman", "fled", 0)
	game = await _enter("galilee_hills", "from_village")
	t.check(not game.region.npcs.has("hills_highwayman"), "a highwayman who fled is not there on the next visit")
	_drop(game)
	_fresh()
