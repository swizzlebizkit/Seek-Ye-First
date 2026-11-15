class_name AutoplayW1
extends RefCounted
## Dev-only. Drives the W1 demonstration through the live game (real scene reloads, real map screens, real
## input for the exits) and prints PASS or FAIL lines. Run it with a window:
##   godot --path . -- --autostart=new --autoplay=w1
## Each region scene starts the next step, because every transition rebuilds the scene.

static var step := 0
static var checks := 0
static var failures := 0
static var snapshot: Dictionary = {}


static func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
	print("[autoplay] %s %s" % ["ok  " if cond else "FAIL", msg])


static func finish(game: Node) -> void:
	print("[autoplay] RESULT: %s (%d checks, %d failed)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	game.get_tree().quit(0 if failures == 0 else 1)


static func wait(game: Node, seconds: float) -> bool:
	await game.get_tree().create_timer(seconds).timeout
	return is_instance_valid(game) and game.is_inside_tree()


## Waits until the scene has been rebuilt (the node is freed) or the time is up.
static func wait_for_reload(game: Node, seconds: float) -> bool:
	var t := 0.0
	while t < seconds:
		if not await wait(game, 0.2):
			return true
		t += 0.2
	return false


static func open_map(game: Node, modes: Array, to: String, fast := true, stop_first := false, resume := false) -> void:
	var sv: StrategicView = game.hud.strategic_view
	GameState.map_requested.emit(modes)
	await wait(game, 0.3)
	var picked := false
	for i in range(sv._options.size()):
		if sv._options[i]["to"] == to and modes.has(sv._options[i]["mode"]):
			sv._list.select(i)
			sv._on_row_selected(i)
			picked = true
	if resume:
		ok(Travel.journey.get("state", "") == "paused" and sv._go.text == "Resume", "the map shows the paused journey with Resume")
	else:
		ok(picked, "the map offers a route to %s" % to)
	if stop_first:
		sv._on_go()
		sv._on_stop()
	else:
		sv._on_go()
	if fast:
		sv._on_speed()


static func walk_into_exit(game: Node, from_tile: Vector2, action: String) -> void:
	game.player.teleport(from_tile * 32.0, "right" if action == "move_right" else "left")
	Input.action_press(action)
	await wait_for_reload(game, 4.0)
	Input.action_release(action)


## Called at the end of Game._ready (via DevHooks.apply) in every scene build.
static func on_scene(game: Node) -> void:
	if DialogueRunner.active and step != 8:
		DialogueRunner.cancel()
	game.get_tree().create_timer(0.7).timeout.connect(func(): _run(game))


static func _run(game: Node) -> void:
	if not is_instance_valid(game):
		return
	var region := GameState.region_id
	match step:
		0:
			ok(region == "kefar_zayit", "step 0: the game begins in Kefar Zayit")
			step = 1
			await walk_into_exit(game, Vector2(36.5, 13.5), "move_right")
			if is_instance_valid(game):
				ok(false, "the east road did not lead anywhere")
				finish(game)
		1:
			ok(region == "galilee_hills", "step 1: leaving by the east road enters the Galilean countryside")
			ok(game.player.global_position.x < 6.0 * 32.0, "arrived at the village side of the hills")
			var cairn = game.region.entities.get_children().filter(func(n): return n is ExamineInteractable and n.display_name == "The shepherds' cairn")
			ok(cairn.size() == 1, "the landmark is in the countryside")
			Effects.run_all(cairn[0].variants[0]["effects"])
			ok(World.landmarks_found.get("shepherds_cairn", false), "the landmark is discovered")
			ok(game.region.npcs.has("hills_highwayman") == (WorldSim.minute_of_day >= 360.0 and WorldSim.minute_of_day < 1080.0), "the optional encounter is present by day")
			step = 2
			await walk_into_exit(game, Vector2(60.5, 23.5), "move_right")
			if is_instance_valid(game):
				ok(false, "the east end of the hills did not lead anywhere")
				finish(game)
		2:
			ok(region == "magdala_shore", "step 2: the next region is the lake shore at Magdala")
			step = 3
			await open_map(game, ["land"], "capernaum", true, true)
			await wait_for_reload(game, 12.0)
		3:
			ok(region == "road_camp" and Travel.phase() == Travel.Phase.PAUSED and Travel.journey["pause"] == "player", "step 3: the walker stopped at a camp on the road to Capernaum")
			ok(float(Travel.journey["pos"]) > 0.0 and float(Travel.journey["pos"]) < float(World.route("capernaum__magdala__land")["length_km"]), "with the journey part-way along")
			step = 4
			await open_map(game, ["land"], "capernaum", true, false, true)
			ok(Travel.journey["state"] == "underway", "the player resumed")
			await wait_for_reload(game, 12.0)
		4:
			ok(region == "outskirts" and World.current_location() == "capernaum", "step 4: arrived at Capernaum")
			WorldSim.day = 3
			WorldSim.minute_of_day = 9.0 * 60.0
			step = 5
			await open_map(game, ["water"], "magdala")
			await wait_for_reload(game, 12.0)
		5:
			ok(region == "magdala_shore" and World.context.get("location", "") == "magdala", "step 5: the ferry brought the traveller back to Magdala")
			step = 6
			await open_map(game, ["land"], "kefar_zayit")
			await wait_for_reload(game, 12.0)
		6:
			ok(region == "kefar_zayit" and game.player.global_position.distance_to(game.region.entry_position("arrival")) < 4.0, "step 6: home in Kefar Zayit, by the road")
			step = 7
			await open_map(game, ["land"], "nazareth")
			await wait_for_reload(game, 12.0)
		7:
			ok(region == "outskirts" and World.current_location() == "nazareth", "step 7: arrived at Nazareth")
			WorldSim.day = 6
			WorldSim.minute_of_day = 16.0 * 60.0
			World.reveal("sychar", "discovered")
			World.discover_route("nazareth__sychar__land")
			step = 8
			await open_map(game, ["land"], "sychar")
			await wait_for_reload(game, 12.0)
		8:
			ok(region == "road_camp" and Travel.journey.get("pause", "") == "sabbath", "step 8: the Sabbath stopped the walk")
			ok(WorldSim.day == 6 and WorldSim.minute_of_day >= 1080.0 and WorldSim.minute_of_day < 1100.0, "at sunset on the sixth day (%s)" % WorldSim.time_string())
			ok(absf(float(Travel.journey["pos"]) - 16.0 / 4.0 * 0.0) >= 0.0 and float(Travel.journey["pos"]) > 0.0, "with the exact progress kept (%.2f km)" % float(Travel.journey["pos"]))
			ok(DialogueRunner.active, "the player was told")
			DialogueRunner.cancel()
			ok(not Travel.can_resume()["ok"] and not Travel.resume(), "the journey cannot resume during the Sabbath")
			game.player.teleport(Vector2(10.5, 10.5) * 32.0, "up")
			await wait(game, 0.4)
			ok(GameState.mode == GameState.Mode.EXPLORE and game.region.is_walkable_px(game.player.global_position), "the player is free to explore the camp")
			WorldSim.advance(24.0 * 60.0)
			ok(not Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day), "the Sabbath has ended")
			ok(Travel.journey["state"] == "paused", "the journey did not resume itself")
			step = 9
			await open_map(game, ["land"], "sychar", true, false, true)
			ok(Travel.journey["state"] == "underway", "the player resumed after the Sabbath")
			await wait_for_reload(game, 15.0)
		9:
			ok(region == "outskirts" and World.current_location() == "sychar" and World.level_of("sychar") == "visited", "step 9: arrived at Sychar")
			game.hud.journal_view.open()
			game.hud.journal_view._set_tab(JournalView.Tab.MAP)
			await wait(game, 0.3)
			var jm: JournalMap = game.hud.journal_view._map
			ok(jm._list.item_count >= 6, "the journal map lists the places now known (%d)" % jm._list.item_count)
			jm.set_level(JournalMap.Level.REGIONAL)
			ok(jm._list.item_count >= 2, "and the countryside that was walked (%d regions)" % jm._list.item_count)
			game.hud.journal_view.close()
			snapshot = {"world": World.serialize(), "day": WorldSim.day, "min": WorldSim.minute_of_day, "region": GameState.region_id}
			ok(SaveManager.save_slot(2), "saved")
			GameState.start_request = {"mode": "load", "slot": 2}
			step = 10
			game.get_tree().reload_current_scene()
		10:
			ok(region == snapshot["region"] and WorldSim.day == snapshot["day"] and absf(WorldSim.minute_of_day - float(snapshot["min"])) < 1.5, "step 10: reloaded in the same place at the same time")
			var now := World.serialize()
			ok(now["places"] == snapshot["world"]["places"] and now["routes"].size() == snapshot["world"]["routes"].size(), "discovered places and routes survived")
			ok(now["explored"].keys().size() == snapshot["world"]["explored"].keys().size(), "explored country survived")
			ok(now["landmarks"] == snapshot["world"]["landmarks"], "found landmarks survived")
			SaveManager.delete_slot(2)
			finish(game)
