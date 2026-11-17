extends RefCounted
## W1.3 and W1.4 interface checks: the strategic travel screen driven through its real UI, and the journal
## Map tab (three levels, discovery, fog, zoom, and the guarantee that it never moves anyone).

var t: Node


func run(runner: Node) -> void:
	t = runner
	t._section = "world-map"
	test_map_data()
	await test_journal_map()
	await test_no_teleport()
	t._section = "world-strategic-ui"
	await test_strategic_ui_walk()
	await test_strategic_ui_sabbath()
	await test_strategic_ui_boat()
	await test_notices()


func _fresh() -> void:
	t._fresh()
	Travel.reset()


func _enter(region: String, entry: String) -> Node:
	World.set_destination(region, entry)
	World.entry_offset = 0.0
	return await t._spawn_game({"mode": "resume"})


func _wait(seconds: float) -> void:
	await t.get_tree().create_timer(seconds).timeout


func _all_nodes(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children():
		_all_nodes(c, out)
	return out


# -- map data ----------------------------------------------------------------------------------
func test_map_data() -> void:
	_fresh()
	# fog of war: sight reveals blocks, far tiles stay hidden
	t.check(not World.is_explored("galilee_hills", Vector2i(30, 20)), "nothing is explored in a region not yet entered")
	t.check(World.note_player("galilee_hills", Vector2(30, 20)), "standing somewhere reveals the ground around it")
	t.check(World.is_explored("galilee_hills", Vector2i(30, 20)) and World.is_explored("galilee_hills", Vector2i(33, 22)), "nearby tiles are seen")
	t.check(not World.is_explored("galilee_hills", Vector2i(5, 40)), "far tiles are not")
	t.check(not World.note_player("galilee_hills", Vector2(30, 20)), "standing still reveals nothing new")
	t.check(World.explored_fraction("galilee_hills") > 0.02 and World.explored_fraction("galilee_hills") < 0.3, "a small part of the region is explored (%.2f)" % World.explored_fraction("galilee_hills"))
	t.check(not World.note_player("not_a_region", Vector2(1, 1)), "an unknown region reveals nothing")
	# a walk along the road explores it
	for x in range(2, 62, 3):
		World.note_player("galilee_hills", Vector2(x, 22))
	t.check(World.is_explored("galilee_hills", Vector2i(60, 22)) and World.is_explored("galilee_hills", Vector2i(10, 22)), "walking the road explores the whole road")
	# exploration and discovery survive a save
	World.reveal("magdala", "visited", "Yosef the trader")
	World.find_landmark("shepherds_cairn")
	var d := World.serialize()
	World.reset()
	t.check(not World.is_explored("galilee_hills", Vector2i(30, 20)), "a reset forgets the fog")
	World.deserialize(d)
	t.check(World.is_explored("galilee_hills", Vector2i(30, 20)) and World.is_explored("galilee_hills", Vector2i(60, 22)), "explored ground round-trips")
	t.check(World.place_sources.get("magdala", []) == ["Yosef the trader"], "where a place was heard of round-trips")
	t.check(World.landmarks_found.get("shepherds_cairn", false), "found landmarks round-trip")
	t.check(World.level_of("magdala") == "visited", "visited places round-trip")
	# the data hooks for later investigation exist and are well formed
	var with_refs := 0
	for id in World.locations:
		var h: Dictionary = World.locations[id].get("hooks", {})
		if h.has("scripture_refs"):
			with_refs += 1
			t.check(h["scripture_refs"] is Array and h["canon_events"] is Array and h["investigations"] is Array, "%s hooks are lists" % id)
	t.check(with_refs >= 8, "places carry scripture reference hooks (%d)" % with_refs)
	# a reveal_place effect with a source records it
	_fresh()
	Effects.run({"reveal_place": {"place": "capernaum", "level": "rumored", "source": "a fisherman"}})
	t.check(World.level_of("capernaum") == "rumored" and World.place_sources["capernaum"] == ["a fisherman"], "a rumor from a person records who told you")
	# the MapCanvas projection round-trips
	var c := MapCanvas.new()
	c.size = Vector2(640, 600)
	var u := Vector2(0.4, 0.3)
	t.check(c.from_screen(c.to_screen(u)).is_equal_approx(u), "screen and map coordinates convert both ways")
	c.set_zoom(4.0)
	c.focus(Vector2(35.4, 32.78))
	t.check(c.zoom == 4.0 and c.to_screen(World.project(Vector2(35.4, 32.78))).distance_to(c.size * 0.5) < 2.0, "focusing centres the chosen place")
	c.set_zoom(100.0)
	t.check(c.zoom == c.max_zoom, "zoom stops at its limit")
	c.set_zoom(0.1)
	t.check(c.zoom == 1.0, "and cannot go below the whole map")
	c.free()


# -- journal map -------------------------------------------------------------------------------
func test_journal_map() -> void:
	_fresh()
	World.note_player("kefar_zayit", Vector2(20, 14))
	World.regions_visited["kefar_zayit"] = true
	var game: Node = await _enter("kefar_zayit", "gate_east")
	var jv: JournalView = game.hud.journal_view
	jv.open()
	jv._set_tab(JournalView.Tab.MAP)
	var jm: JournalMap = jv._map
	t.check(jv.TAB_NAMES.size() == 5 and jv.TAB_NAMES[3] == "Map", "the journal has a Map tab beside the others")
	t.check(jm.visible and not jv._details.visible and not jv._list.visible, "the Map tab shows the map, not the journal list")
	jv._set_tab(JournalView.Tab.JOURNAL)
	t.check(not jm.visible and jv._details.visible, "the Journal tab is unchanged")
	jv._set_tab(JournalView.Tab.MAP)

	# strategic level: only what is known
	jm.set_level(JournalMap.Level.STRATEGIC)
	var names: Array = []
	for i in range(jm._list.item_count):
		names.append(jm._list.get_item_text(i))
	t.check(names.any(func(n): return n.begins_with("Kefar Zayit")), "the home village is listed")
	t.check(names.any(func(n): return n.begins_with("Jerusalem") and n.contains("heard of")), "a rumored place is listed as only heard of")
	t.check(not names.any(func(n): return n.begins_with("Jericho")), "an unknown place is not listed")
	t.check(jm._canvas.visible and not jm._region_map.visible, "strategic level draws the map")
	var canvas: MapCanvas = jm._canvas
	canvas.size = Vector2(700, 420)
	var jer := Vector2(World.locations["jerusalem"]["pos"][0], World.locations["jerusalem"]["pos"][1])
	var exact := canvas.ll_to_screen(jer)
	var marker := canvas._marker_pos("jerusalem")
	t.check(marker.distance_to(exact) > 3.0 and marker.distance_to(exact) < 20.0, "a rumored place is drawn near, not at, its true position (%.1f px off)" % marker.distance_to(exact))
	t.check(canvas._marker_pos("jerusalem") == marker, "and always in the same wrong place")
	var kz := Vector2(World.locations["kefar_zayit"]["pos"][0], World.locations["kefar_zayit"]["pos"][1])
	t.check(canvas._marker_pos("kefar_zayit") == canvas.ll_to_screen(kz), "a known place is drawn exactly")
	t.check(canvas.place_at(canvas._marker_pos("kefar_zayit")) == "kefar_zayit", "clicking a marker finds the place")
	t.check(canvas.place_at(Vector2(-50, -50)) == "", "clicking elsewhere finds none")
	World.reveal("jerusalem", "rumored")
	t.check(jm.place_text("jerusalem").contains("No one has told you the way there") and not jm.place_text("jerusalem").contains("Roads:"), "a rumor gives no route")
	t.check(jm.place_text("kefar_zayit").contains("Roads:") and jm.place_text("kefar_zayit").contains("Magdala"), "a visited place lists its roads")
	t.check(not jm.place_text("magdala").contains("Written of"), "a place only discovered shows no scripture note")
	World.visit("capernaum")
	t.check(jm.place_text("capernaum").contains("Matthew 4:13"), "a visited place shows where it is written of")
	World.reveal("cana", "discovered")
	t.check(jm.place_text("cana").contains("Debated"), "a debated site says so")
	jm.refresh()
	var before := jm._list.item_count
	World.reveal("bethany", "discovered")
	jm.refresh()
	t.check(jm._list.item_count == before + 1, "discovering a place adds it to the map")
	var z0 := canvas.zoom
	jm.zoom(1.3)
	t.check(canvas.zoom > z0, "the zoom keys zoom the strategic map")

	# regional level
	jm.set_level(JournalMap.Level.REGIONAL)
	t.check(jm._region_map.visible and not jm._canvas.visible, "regional level shows a region")
	t.check(jm._list.item_count == 0, "no countryside is listed until it has been walked")
	World.regions_visited["galilee_hills"] = true
	for x in range(2, 62, 3):
		World.note_player("galilee_hills", Vector2(x, 22))
	jm.refresh()
	t.check(jm._list.item_count == 2 and jm._list.get_item_text(0) == "The whole countryside" and jm._list.get_item_text(1) == "The hills above the lake", "a walked region is listed, after the whole countryside")
	t.check(jm._region_map.world_mode, "the first entry draws the whole countryside, each map where it lies")
	t.check(jm._region_map._world_bounds() == Rect2i(-176, -140, 416, 248), "over the whole extent of the shared world")
	jm._list.select(1)
	jm._on_selected(1)
	t.check(jm._region_map.region_id == "galilee_hills" and jm._region_map.labels == false and not jm._region_map.world_mode, "a single region is drawn without village labels")
	var rz := jm._region_map.zoom
	jm.zoom(1.5)
	t.check(jm._region_map.zoom > rz, "the regional map zooms")
	t.check(jm.region_text("galilee_hills").contains("Explored"), "its detail says how much is explored")
	t.check(not jm.region_text("hills_north").contains("cairn"), "the cairn is not listed before it is found")
	World.find_landmark("shepherds_cairn")
	t.check(jm.region_text("hills_north").contains("shepherds' cairn"), "a found landmark is listed")

	# local level
	jm.set_level(JournalMap.Level.LOCAL)
	t.check(jm._list.item_count == 1 and jm._list.get_item_text(0) == "Kefar Zayit", "the village is a local map")
	t.check(jm._region_map.labels == true and jm._region_map.region_id == "kefar_zayit", "with its points of interest named")
	t.check(not World.is_explored("kefar_zayit", Vector2i(2, 26)), "unvisited corners stay fogged")
	jv.close()
	t.check(GameState.mode == GameState.Mode.EXPLORE, "closing the journal returns to exploring")
	game.free()


func test_no_teleport() -> void:
	_fresh()
	World.regions_visited["galilee_hills"] = true
	World.note_player("galilee_hills", Vector2(30, 20))
	var game: Node = await _enter("galilee_hills", "camp")
	var jv: JournalView = game.hud.journal_view
	jv.open()
	jv._set_tab(JournalView.Tab.MAP)
	var jm: JournalMap = jv._map
	var region_before := GameState.region_id
	var ctx_before := World.context.duplicate()
	var day_before := WorldSim.day
	var min_before := WorldSim.minute_of_day
	var pos_before: Vector2 = game.player.global_position
	var transitions: Array = []
	var on_t := func(r, e): transitions.append(r)
	World.transition_requested.connect(on_t)
	for lv in [0, 1, 2]:
		jm.set_level(lv)
		for i in range(jm._list.item_count):
			jm._list.select(i)
			jm._on_selected(i)
			jm._on_place_clicked(str(jm._ids[i]))
			jm._list.item_activated.emit(i)
	for id in World.locations:
		jm._on_place_clicked(id)
	jm._canvas.place_clicked.emit("jerusalem")
	await t._frames(3)
	World.transition_requested.disconnect(on_t)
	t.check(transitions.is_empty(), "nothing in the map asks for a region change")
	t.check(GameState.region_id == region_before and World.context == ctx_before, "choosing places on the map changes no location")
	t.check(WorldSim.day == day_before and WorldSim.minute_of_day == min_before, "and no time passes")
	t.check(game.player.global_position == pos_before, "and the player has not moved")
	t.check(not Travel.active(), "and no journey begins")
	var buttons: Array = _all_nodes(jm).filter(func(n): return n is Button)
	t.check(buttons.size() == 3 and buttons.all(func(b): return b.text in ["Lands", "Roads", "Village"]), "the only buttons on the map are the three view levels")
	for m in ["travel", "go", "teleport", "set_out", "start"]:
		t.check(not jm.has_method(m), "JournalMap has no '%s' method" % m)
	var sigs: Array = jm.get_signal_list().filter(func(s): return s["name"] in ["travel_requested", "go_requested"])
	t.check(sigs.is_empty(), "and no travel signals")
	var ev := InputEventKey.new()
	ev.keycode = KEY_2
	ev.pressed = true
	jv._input(ev)
	t.check(jm.level == JournalMap.Level.REGIONAL and GameState.region_id == region_before, "the 2 key switches level and nothing else")
	jv.close()
	game.free()


# -- the strategic screen, through its own UI --------------------------------------------------
func _open_strategic(game: Node, modes: Array) -> StrategicView:
	var sv: StrategicView = game.hud.strategic_view
	sv.open(modes)
	await t._frames(2)
	return sv


func test_strategic_ui_walk() -> void:
	_fresh()
	WorldSim.day = 2
	WorldSim.minute_of_day = 8.0 * 60.0
	var game: Node = await _enter("kefar_zayit_outskirts", "camp")
	var marks = game.region.entities.get_children().filter(func(n): return n is WaymarkInteractable and n.place == "kefar_zayit")
	marks[0]._open_map()
	await t._frames(2)
	var sv: StrategicView = game.hud.strategic_view
	t.check(GameState.mode == GameState.Mode.MAP and sv.visible, "the road marker opens the map and pauses play")
	t.check(sv._list.item_count == 3, "three roads are offered from the countryside around Kefar Zayit")
	t.check(sv._title.text.contains("Kefar Zayit"), "titled with where the protagonist is")
	t.check(sv._clock.text.contains("Kislev"), "the date is shown")
	var texts: Array = []
	for i in range(sv._list.item_count):
		texts.append(sv._list.get_item_text(i))
	t.check(texts.any(func(s): return s.begins_with("Magdala")) and texts.all(func(s): return s.contains("km") and s.contains("on foot")), "each road shows its distance and manner of travel")
	t.check(sv._info.text.contains("You would arrive"), "the estimate gives an arrival")
	t.check(sv._canvas.here == "kefar_zayit" and sv._canvas.traveller != Vector2.ZERO, "the avatar stands at the starting place")
	for i in range(sv._options.size()):
		if sv._options[i]["to"] == "magdala":
			sv._list.select(i)
			sv._on_row_selected(i)
	var mins_before := WorldSim.minute_of_day
	sv._on_go()
	t.check(Travel.active() and sv._moving, "setting out starts the journey and the animation")
	t.check(sv._abandon.visible == false and sv._close.disabled, "the screen cannot be closed mid-journey")
	sv._on_speed()
	var start_pt := sv._canvas.traveller
	await _wait(0.35)
	t.check(sv._canvas.traveller != start_pt or not Travel.active(), "the avatar moves along the route")
	t.check(WorldSim.minute_of_day > mins_before or WorldSim.day > 2, "the clock advances while it moves")
	await _wait(2.8)
	t.check(not Travel.active() and Travel.last_arrival == "magdala", "the journey ends at Magdala")
	t.check(GameState.region_id == "magdala" and World.entry_id == "arrival", "and the protagonist is put inside Magdala at its arrival point")
	t.check(Travel.notice == "arrived", "arrival leaves a notice for the next scene")
	t.check(not sv.visible and GameState.mode == GameState.Mode.EXPLORE, "the map has closed")
	t.check(World.level_of("magdala") == "visited", "Magdala is now visited")
	game.free()


func test_strategic_ui_sabbath() -> void:
	_fresh()
	WorldSim.day = 6
	WorldSim.minute_of_day = 17.0 * 60.0
	GameState.region_id = "outskirts"
	World.context = {"location": "nazareth"}
	World.visit("nazareth")
	World.reveal("sychar", "discovered")
	World.discover_route("nazareth__sychar__land")
	var game: Node = await _enter("outskirts", "arrival")
	var sv := await _open_strategic(game, ["land"])
	var idx := -1
	for i in range(sv._options.size()):
		if sv._options[i]["to"] == "sychar":
			idx = i
	sv._list.select(idx)
	sv._on_row_selected(idx)
	t.check(sv._info.text.contains("Sabbath will begin on the way"), "the screen warns that the Sabbath will stop the journey")
	sv._on_go()
	sv._on_speed()
	await _wait(0.7)
	t.check(Travel.journey["state"] == "paused" and Travel.journey["pause"] == "sabbath", "the journey pauses for the Sabbath")
	t.check(WorldSim.day == 6 and WorldSim.minute_of_day == 1080.0, "at sunset")
	t.check(sv._msg.text.contains("Sabbath"), "the player is told")
	await _wait(1.9)
	t.check(GameState.region_id == "road_camp" and World.entry_id == "camp", "and put in a roadside camp")
	t.check(Travel.notice == "sabbath", "a Sabbath notice is waiting")
	game.free()
	game = await t._spawn_game({"mode": "resume"})
	t.check(DialogueRunner.active, "arriving in the camp, the player is told the Sabbath has begun")
	DialogueRunner.cancel()
	t.check(Travel.notice == "", "the notice is used up")
	sv = await _open_strategic(game, ["land"])
	t.check(Travel.journey["state"] == "paused" and sv._go.text == "Resume" and sv._go.disabled, "Resume is greyed out during the Sabbath")
	t.check(sv._info.text.contains("Sabbath"), "with the reason given")
	t.check(sv._abandon.visible, "the journey can be abandoned")
	t.check(sv._clock.get_theme_color("font_color") == UiTheme.GOLD, "the clock is gold on the Sabbath")
	sv._on_go()
	t.check(not sv._moving and Travel.journey["state"] == "paused", "pressing Resume during the Sabbath does nothing")
	sv.close()
	t.check(GameState.mode == GameState.Mode.EXPLORE, "the player is free to explore the camp")
	WorldSim.day = 7
	WorldSim.minute_of_day = 1079.0
	WorldSim.advance(2.0)
	sv = await _open_strategic(game, ["land"])
	t.check(not sv._go.disabled and Travel.journey["state"] == "paused", "after sunset Resume is available, and the journey has not moved on its own")
	sv._on_go()
	t.check(sv._moving and Travel.journey["state"] == "underway", "the player resumes the journey")
	sv._on_speed()
	await _wait(0.4)
	t.check(float(Travel.journey["pos"]) > 0.0 or sv._moving, "it continues")
	sv._moving = false
	game.free()


func test_strategic_ui_boat() -> void:
	_fresh()
	WorldSim.day = 3
	WorldSim.minute_of_day = 9.0 * 60.0
	GameState.region_id = "outskirts"
	World.context = {"location": "capernaum"}
	World.visit("capernaum")
	World.visit("magdala")
	var game: Node = await _enter("outskirts", "arrival")
	var sv := await _open_strategic(game, ["water"])
	t.check(sv._options.size() >= 1 and sv._options.all(func(o): return o["mode"] == "water"), "a landing offers only water routes")
	t.check(sv._list.get_item_text(0).contains("by boat"), "and says so")
	sv._on_go()
	t.check(sv._canvas.traveller_mode == "water", "the avatar is a boat")
	sv._on_speed()
	await _wait(0.6)
	t.check(sv._moving or not Travel.active(), "the boat sails")
	await _wait(2.2)
	t.check(Travel.last_arrival in ["magdala", "tiberias"] and not Travel.active(), "and arrives")
	game.free()
	_fresh()
	WorldSim.day = 6
	WorldSim.minute_of_day = 16.5 * 60.0
	GameState.region_id = "outskirts"
	World.context = {"location": "capernaum"}
	World.visit("capernaum")
	World.visit("tiberias")
	game = await _enter("outskirts", "arrival")
	sv = await _open_strategic(game, ["water"])
	var tib := -1
	for i in range(sv._options.size()):
		if sv._options[i]["to"] == "tiberias":
			tib = i
	sv._list.select(tib)
	sv._on_row_selected(tib)
	sv._on_go()
	sv._on_stop()
	t.check(sv._msg.text.contains("open water"), "a boat cannot put in at sea")
	sv._moving = false
	game.free()


func test_notices() -> void:
	_fresh()
	Travel.notice = "stop"
	var game: Node = await _enter("road_camp", "camp")
	t.check(Travel.notice == "", "a stop notice is used up when the camp is built")
	game.free()
	_fresh()
	Travel.notice = "arrived"
	Travel.last_arrival = "magdala"
	game = await _enter("magdala", "arrival")
	t.check(Travel.notice == "", "an arrival notice is used up too")
	game.free()
	_fresh()
