extends Node
## Headless test suite. Run from the project root:
##   godot --headless --path . res://tests/test_runner.tscn
## Exit code 0 = all passed. Uses a throwaway save directory, never the player's saves.

const TEST_SAVE_DIR := "user://test_saves"
const EFFECT_KEYS := ["when", "set_flag", "clear_flag", "journal", "annotate", "set_status", "quest_start",
	"quest_objective", "give_item", "take_item", "knowledge", "equip", "encounter", "actor"]
const COND_KEYS := ["flag", "not_flag", "has_item", "equipped", "quest_active", "quest_done", "knows", "encounter", "actor"]

var _failures: Array[String] = []
var _checks := 0
var _section := ""
var _verbose := OS.get_cmdline_user_args().has("--verbose")


func _ready() -> void:
	SaveManager.save_dir = TEST_SAVE_DIR
	_clean_test_saves()

	_section = "data"
	test_scripture_and_refs()
	test_dialogue_data()
	test_region_data()
	_section = "systems"
	test_journal()
	test_quests()
	test_canon_and_knowledge()
	test_canon_is_player_proof()
	_section = "playthrough"
	await test_playthrough_order_a()
	await test_playthrough_order_b()
	_section = "save"
	test_save_roundtrip()
	_section = "world"
	test_region_walkability()
	_section = "integration"
	await test_integration()
	_section = "m2a"
	await load("res://tests/m2a_tests.gd").new().run(self)

	_clean_test_saves()
	print("")
	if _failures.is_empty():
		print("ALL %d CHECKS PASSED" % _checks)
	else:
		print("%d of %d CHECKS FAILED:" % [_failures.size(), _checks])
		for f in _failures:
			print("  FAIL ", f)
	get_tree().quit(0 if _failures.is_empty() else 1)


# -- helpers -----------------------------------------------------------------------------------
func check(cond: bool, msg: String) -> void:
	_checks += 1
	if _verbose:
		print(("ok    " if cond else "FAIL  ") + "[%s] %s" % [_section, msg])
	if not cond:
		_failures.append("[%s] %s" % [_section, msg])


func _fresh() -> void:
	GameState.new_game()
	GameState.mode = GameState.Mode.EXPLORE


func _clean_test_saves() -> void:
	var abs_dir := ProjectSettings.globalize_path(TEST_SAVE_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		for f in DirAccess.get_files_at(abs_dir):
			DirAccess.remove_absolute(abs_dir + "/" + f)


## Plays a dialogue to the end without UI. `picks` are choice indices used in order (default 0).
func play(dialogue_id: String, picks: Array = []) -> Array:
	var seen: Array = []
	var pick_i := [0]
	var on_line := func(_s, text, _n): seen.append(text)
	var on_choices := func(_s, texts):
		var i: int = picks[pick_i[0]] if pick_i[0] < picks.size() else 0
		pick_i[0] += 1
		seen.append("CHOICE:" + texts[i])
		DialogueRunner.choose.call_deferred(i)
	var on_line_adv := func(_s, _t, _n): DialogueRunner.advance.call_deferred()
	DialogueRunner.line_shown.connect(on_line)
	DialogueRunner.line_shown.connect(on_line_adv)
	DialogueRunner.choices_shown.connect(on_choices)
	DialogueRunner.start(dialogue_id)
	var guard := 0
	while DialogueRunner.active and guard < 200:
		await get_tree().process_frame
		guard += 1
	DialogueRunner.line_shown.disconnect(on_line)
	DialogueRunner.line_shown.disconnect(on_line_adv)
	DialogueRunner.choices_shown.disconnect(on_choices)
	check(guard < 200, "dialogue '%s' terminated" % dialogue_id)
	return seen


func _norm(v):
	if v is Dictionary:
		var d := {}
		for k in v:
			d[str(k)] = _norm(v[k])
		return d
	if v is Array:
		return v.map(func(x): return _norm(x))
	if v is float and v == floorf(v):
		return int(v)
	return v


func _same(a, b) -> bool:
	return JSON.stringify(_norm(a), "", true) == JSON.stringify(_norm(b), "", true)


# -- data integrity ----------------------------------------------------------------------------
func test_scripture_and_refs() -> void:
	check(Scripture.get_passage("Matthew 6:33").begins_with("But seek ye first the kingdom of God"), "Matthew 6:33 text")
	check(Scripture.get_verses("Matthew 3:13-17").size() == 5, "Matthew 3:13-17 has 5 verses")
	check(Scripture.get_passage("Matthew 3:17") == "And lo a voice from heaven, saying, This is my beloved Son, in whom I am well pleased.", "Matthew 3:17 exact KJV text")
	check(Scripture.get_passage("Matthew 3:16").contains("descending like a dove"), "Matthew 3:16 dove")
	check(Scripture.get_verses("Nowhere 1:1").is_empty(), "unknown book yields nothing")
	for id in Journal._defs:
		for ref in Journal._defs[id].get("refs", []):
			check(Scripture.is_complete(ref), "journal '%s' ref '%s' is in kjv.json" % [id, ref])
	for id in CanonicalTimeline.event_ids():
		for ref in CanonicalTimeline.get_event(id)["refs"]:
			check(Scripture.is_complete(ref), "canon '%s' ref '%s' is in kjv.json" % [id, ref])


func _validate_effect(e: Dictionary, where: String) -> void:
	for k in e:
		check(EFFECT_KEYS.has(k), "%s: known effect key '%s'" % [where, k])
	if e.has("when"):
		_validate_cond(e["when"], where)
	if e.has("journal"):
		check(Journal.has_definition(e["journal"]), "%s: journal '%s' exists" % [where, e["journal"]])
	if e.has("annotate"):
		check(Journal.has_definition(e["annotate"]["entry"]), "%s: annotate entry exists" % where)
		for ref in e["annotate"].get("refs", []):
			check(Scripture.is_complete(ref), "%s: annotate ref '%s' in kjv.json" % [where, ref])
	if e.has("set_status"):
		check(Journal.has_definition(e["set_status"]["entry"]), "%s: set_status entry exists" % where)
		check(Journal.statuses.has(e["set_status"]["status"]), "%s: status valid" % where)
	if e.has("quest_start"):
		check(Quests.has_definition(e["quest_start"]), "%s: quest '%s' exists" % [where, e["quest_start"]])
	if e.has("quest_objective"):
		var q: Dictionary = e["quest_objective"]
		check(Quests.has_definition(q["quest"]), "%s: quest '%s' exists" % [where, q["quest"]])
		var ids: Array = Quests.get_def(q["quest"]).get("objectives", []).map(func(o): return o["id"])
		check(ids.has(q["objective"]), "%s: objective '%s' exists" % [where, q["objective"]])
	for key in ["give_item", "take_item"]:
		if e.has(key):
			check(GameState.items.has(e[key]["item"]), "%s: item '%s' exists" % [where, e[key]["item"]])
	if e.has("knowledge"):
		check(CanonicalTimeline.has_event(e["knowledge"]["event"]), "%s: canon event exists" % where)


func _validate_cond(c: Dictionary, where: String) -> void:
	for k in c:
		check(COND_KEYS.has(k), "%s: known condition key '%s'" % [where, k])
	if c.has("has_item"):
		for i in (c["has_item"] if c["has_item"] is Array else [c["has_item"]]):
			check(GameState.items.has(i), "%s: condition item '%s' exists" % [where, i])
	for key in ["quest_active", "quest_done"]:
		if c.has(key):
			check(Quests.has_definition(c[key]), "%s: condition quest exists" % where)


func test_dialogue_data() -> void:
	var dir := DirAccess.open("res://data/dialogue")
	var files := Array(dir.get_files()).filter(func(f): return f.ends_with(".json"))
	check(files.size() >= 6, "found dialogue files")
	for f in files:
		var data = DataFiles.load_json("res://data/dialogue/" + f)
		check(data is Dictionary, "%s parses" % f)
		if not data is Dictionary:
			continue
		var nodes: Dictionary = data["nodes"]
		check(not data["entries"].is_empty() and not data["entries"].back().has("when"), "%s: last entry is an unconditional default" % f)
		for e in data["entries"]:
			check(nodes.has(e["node"]), "%s: entry node '%s' exists" % [f, e["node"]])
			if e.has("when"):
				_validate_cond(e["when"], f)
		for n in nodes:
			var node: Dictionary = nodes[n]
			var where := "%s/%s" % [f, n]
			check(node.has("lines") and not node["lines"].is_empty(), "%s has lines" % where)
			for ef in node.get("effects", []):
				_validate_effect(ef, where)
			if node.get("next") != null:
				check(nodes.has(node["next"]), "%s: next '%s' exists" % [where, node["next"]])
			for c in node.get("choices", []):
				check(c.get("next") == null or nodes.has(c["next"]), "%s: choice next '%s' exists" % [where, c.get("next")])
				for ef in c.get("effects", []):
					_validate_effect(ef, where)
				if c.has("when"):
					_validate_cond(c["when"], where)
	for q in Quests._defs:
		for ef in Quests._defs[q].get("on_complete", []):
			_validate_effect(ef, "quest " + q)


func test_region_data() -> void:
	var r: Dictionary = DataFiles.load_json("res://data/regions/kefar_zayit.json")
	var tiles: Dictionary = DataFiles.load_json("res://assets/tiles/terrain.json")["tiles"]
	var props: Dictionary = DataFiles.load_json("res://assets/props/props.json")
	check(r["ground"].size() == r["size"][1], "ground rows match height")
	for row in r["ground"]:
		check(row.length() == r["size"][0], "ground row width")
		break
	for ch in "".join(r["ground"]):
		check(r["ground_legend"].has(ch), "legend has '%s'" % ch)
		break
	for key in r["ground_legend"]:
		for t in r["ground_legend"][key]:
			check(tiles.has(t), "ground tile '%s' exists in atlas" % t)
	for o in r["objects"]:
		check(tiles.has(o[2]), "object tile '%s' exists" % o[2])
	for p in r["props"]:
		check(props.has(p["prop"]), "prop '%s' exists" % p["prop"])
		check(FileAccess.file_exists("res://assets/props/" + props[p["prop"]]["file"]), "prop image exists")
	check(r["npcs"].size() >= 3, "at least three NPCs")
	for n in r["npcs"]:
		check(FileAccess.file_exists("res://data/dialogue/%s.json" % n["dialogue"]), "NPC %s has dialogue" % n["id"])
		check(FileAccess.file_exists("res://assets/characters/%s.png" % n["id"]), "NPC %s has a sprite sheet" % n["id"])
	for i in r["interactables"]:
		for ef in i.get("effects", []):
			_validate_effect(ef, "interactable " + i["name"])
		for v in i.get("variants", []):
			for ef in v.get("effects", []):
				_validate_effect(ef, "interactable " + i["name"])
			if v.has("when"):
				_validate_cond(v["when"], "interactable " + i["name"])


# -- systems -----------------------------------------------------------------------------------
func test_journal() -> void:
	_fresh()
	check(Journal.count() == 0, "new game has an empty journal")
	check(Journal.discover("rumor_yosef"), "discover returns true first time")
	check(not Journal.discover("rumor_yosef"), "discover is idempotent")
	check(Journal.count() == 1, "one entry after duplicate discover")
	var original: String = Journal.get_entry("rumor_yosef")["text"]
	check(Journal.annotate("rumor_yosef", "A later thought.", ["Isaiah 40:3"], "Ezra", "n1"), "annotate adds a note")
	check(not Journal.annotate("rumor_yosef", "A later thought.", [], "Ezra", "n1"), "annotate with same id is idempotent")
	check(Journal.set_status("rumor_yosef", "corroborated"), "status changes")
	var rec := Journal.get_entry("rumor_yosef")
	check(rec["text"] == original, "original text is untouched by notes and status")
	check(rec["notes"].size() == 1 and rec["status"] == "corroborated", "note and status recorded")
	check(not Journal.annotate("q_who_is_john", "x"), "cannot annotate an undiscovered entry")
	check(Journal.list("rumor").size() == 1 and Journal.list("question").is_empty(), "type filter works")
	var tracked := 0
	for type_id in Journal.types:
		tracked += 1
	check(tracked == 5, "five entry types (eyewitness, testimony, rumor, observation, question)")


func test_quests() -> void:
	_fresh()
	check(Quests.start("word_jordan"), "quest starts")
	check(not Quests.start("word_jordan"), "quest start is idempotent")
	check(not Quests.complete_objective("missing_jar", "find_jar"), "objective on inactive quest is ignored")
	Quests.complete_objective("word_jordan", "hear_rumor")
	Quests.complete_objective("word_jordan", "ask_elder")
	check(Quests.is_active("word_jordan"), "still active with one objective left")
	check(not GameState.has_flag("road_east_ready"), "east road not open yet")
	Quests.complete_objective("word_jordan", "seek_witness")
	check(Quests.is_done("word_jordan"), "quest completes when all objectives done")
	check(GameState.has_flag("road_east_ready"), "on_complete flag set")
	check(Journal.has_entry("q_who_is_john"), "on_complete journal entry discovered")


func test_canon_and_knowledge() -> void:
	_fresh()
	check(CanonicalTimeline.has_occurred("john_preaching"), "John's ministry is under way at game start")
	check(not CanonicalTimeline.has_occurred("baptism_of_jesus"), "the baptism has not happened yet")
	check(PlayerKnowledge.level_of("john_preaching") == "unknown", "protagonist knows nothing at start, though the event occurred")
	PlayerKnowledge.learn("john_preaching", "rumor", "Yosef")
	check(PlayerKnowledge.knows("john_preaching", "rumor") and not PlayerKnowledge.knows("john_preaching", "testimony"), "rumor level only")
	PlayerKnowledge.learn("john_preaching", "testimony", "Hannah")
	PlayerKnowledge.learn("john_preaching", "rumor", "Someone")
	check(PlayerKnowledge.level_of("john_preaching") == "testimony", "knowledge never downgrades")
	check(PlayerKnowledge.sources_of("john_preaching").size() == 3, "sources accumulate")
	check(PlayerKnowledge.level_of("baptism_of_jesus") == "unknown", "unrelated canon event stays unknown to protagonist")
	CanonicalTimeline.reset()
	check(not CanonicalTimeline.story_advance("baptism_of_jesus"), "canon enforces scriptural order")
	check(CanonicalTimeline.story_advance("john_preaching") and CanonicalTimeline.story_advance("baptism_of_jesus"), "events advance in order")


func test_canon_is_player_proof() -> void:
	_fresh()
	var before := JSON.stringify(CanonicalTimeline.serialize())
	var every_effect := [
		{"set_flag": "baptism_of_jesus"}, {"clear_flag": "john_preaching"}, {"journal": "rumor_yosef"},
		{"quest_start": "word_jordan"}, {"give_item": {"item": "lepton", "count": 5}},
		{"knowledge": {"event": "baptism_of_jesus", "level": "witnessed", "source": "test"}},
		{"set_flag": "canon_reset"},
	]
	Effects.run_all(every_effect)
	for i in range(50):
		GameState.set_flag("flag_%d" % i, i % 2 == 0)
	check(JSON.stringify(CanonicalTimeline.serialize()) == before, "no effect or flag changes the canonical timeline")
	check(not CanonicalTimeline.has_occurred("baptism_of_jesus"), "witnessing/knowing an event does not make it occur")
	var returned := CanonicalTimeline.get_event("john_preaching")
	returned["title"] = "tampered"
	check(CanonicalTimeline.get_event("john_preaching")["title"] != "tampered", "event definitions are returned as copies")


# -- scripted playthroughs ---------------------------------------------------------------------
func test_playthrough_order_a() -> void:
	_fresh()
	await play("miriam", [0])  # accept the jar errand
	check(Quests.is_active("missing_jar"), "A: jar quest active after accepting")
	GameState.set_flag("jar_asked")
	Effects.run_all([{"quest_objective": {"quest": "missing_jar", "objective": "find_jar"}}, {"give_item": {"item": "water_jar", "count": 1}}])
	check(GameState.item_count("water_jar") == 1, "A: jar in the satchel")
	await play("miriam")
	check(Quests.is_done("missing_jar"), "A: jar quest done after returning the jar")
	check(GameState.item_count("water_jar") == 0 and GameState.item_count("lepton") == 2, "A: jar given up, two lepta received")
	var hint: Array = await play("miriam")
	check(hint.any(func(t): return str(t).contains("Yosef")), "A: Miriam points the player to Yosef")
	await play("yosef", [0, 1])  # tell me -> who might know more
	check(Journal.has_entry("rumor_yosef") and Journal.get_entry("rumor_yosef")["status"] == "unverified", "A: rumor recorded as unverified")
	check(PlayerKnowledge.level_of("john_preaching") == "rumor", "A: protagonist knows John only as a rumor")
	check(Quests.is_active("word_jordan"), "A: Word from the Jordan started")
	await play("ezra", [0])
	check(Journal.has_entry("testimony_ezra"), "A: Ezra's testimony recorded")
	check(Journal.get_entry("rumor_yosef")["notes"].size() == 1, "A: Ezra annotated the rumor (later understanding)")
	check(Journal.get_entry("rumor_yosef")["notes"][0]["refs"].has("Isaiah 40:3"), "A: annotation carries the Isaiah reference")
	check(not Quests.is_done("word_jordan"), "A: quest not done before a witness is found")
	await play("hannah", [0, 1])
	check(Journal.get_entry("rumor_yosef")["status"] == "corroborated", "A: rumor corroborated by Hannah")
	check(PlayerKnowledge.level_of("john_preaching") == "testimony", "A: knowledge upgraded to testimony")
	check(Quests.is_done("word_jordan") and GameState.has_flag("road_east_ready"), "A: quest done, east road ready")
	check(Journal.has_entry("q_who_is_john"), "A: unresolved question added")
	check(not CanonicalTimeline.has_occurred("baptism_of_jesus"), "A: baptism has not occurred")
	var again: Array = await play("yosef")
	check(not again.any(func(t): return str(t).begins_with("CHOICE:")), "A: Yosef does not repeat the rumor")


func test_playthrough_order_b() -> void:
	_fresh()
	await play("hannah", [0])  # hear Hannah first
	check(Journal.has_entry("testimony_hannah") and not Journal.has_entry("rumor_yosef"), "B: Hannah's account recorded alone")
	check(Quests.is_active("word_jordan"), "B: quest starts from Hannah's account")
	await play("ezra", [1])
	check(Journal.get_entry("testimony_hannah")["notes"].size() == 1, "B: Ezra annotates Hannah's testimony")
	await play("yosef", [0, 2])
	check(Journal.get_entry("rumor_yosef")["status"] == "corroborated", "B: rumor is corroborated on arrival because Hannah already testified")
	check(Quests.is_done("word_jordan"), "B: quest completes regardless of order")
	var jar := Journal.list()
	# Milestone 2A: Ezra's gift adds a fifth entry (his sword) to the original four
	check(jar.size() == 5, "B: five journal entries (Hannah, Ezra, Yosef, question, Ezra's sword)")


# -- save / load -------------------------------------------------------------------------------
func _snapshot() -> Dictionary:
	return {
		"game": GameState.serialize(), "journal": Journal.serialize(), "quests": Quests.serialize(),
		"knowledge": PlayerKnowledge.serialize(), "canon": CanonicalTimeline.serialize(), "world": WorldSim.serialize(),
	}


func test_save_roundtrip() -> void:
	_fresh()
	Journal.discover("rumor_yosef")
	Journal.annotate("rumor_yosef", "Note", ["Isaiah 40:3"], "Ezra", "x")
	Journal.set_status("rumor_yosef", "corroborated")
	Quests.start("word_jordan")
	Quests.complete_objective("word_jordan", "hear_rumor")
	PlayerKnowledge.learn("john_preaching", "testimony", "Hannah")
	GameState.set_flag("yosef_rumor_told")
	GameState.add_item("lepton", 3)
	GameState.player_pos = Vector2(321.5, 654.25)
	GameState.player_facing = "left"
	WorldSim.day = 2
	WorldSim.minute_of_day = 615.5
	var original_text: String = Journal.get_entry("rumor_yosef")["text"]
	var before := _snapshot()

	check(not SaveManager.has_save(2), "slot 2 starts empty")
	check(SaveManager.save_slot(2), "save succeeds")
	check(SaveManager.has_save(2) and not FileAccess.file_exists(SaveManager.slot_path(2) + ".tmp"), "save file exists and temp file is gone")
	check(SaveManager.slot_info(2)["journal_entries"] == 1, "slot info reports journal entries")

	GameState.new_game()
	check(Journal.count() == 0 and not GameState.has_flag("yosef_rumor_told"), "state wiped before load")
	check(SaveManager.load_slot(2), "load succeeds")
	check(_same(_snapshot(), before), "every subsystem round-trips exactly")
	check(Journal.get_entry("rumor_yosef")["text"] == original_text, "journal original text survives save/load")
	check(GameState.player_pos == Vector2(321.5, 654.25) and GameState.player_facing == "left" and GameState.has_saved_position, "player placement restored")
	check(GameState.item_count("lepton") == 3, "inventory restored as integers")
	check(not SaveManager.load_slot(3), "loading an empty slot fails cleanly")
	var f := FileAccess.open(SaveManager.slot_path(1), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	check(not SaveManager.load_slot(1) and SaveManager.slot_info(1)["exists"] == false, "corrupt save is rejected without crashing")


# -- map walkability ---------------------------------------------------------------------------
func test_region_walkability() -> void:
	var r: Dictionary = DataFiles.load_json("res://data/regions/kefar_zayit.json")
	var meta: Dictionary = DataFiles.load_json("res://assets/tiles/terrain.json")
	var solid := {}
	for n in meta["solid"]:
		solid[n] = true
	var w: int = r["size"][0]
	var h: int = r["size"][1]
	var blocked := {}
	for y in range(h):
		for x in range(w):
			var tile_name: String = r["ground_legend"][r["ground"][y][x]][0]
			if solid.has(tile_name):
				blocked[Vector2i(x, y)] = true
	for o in r["objects"]:
		if solid.has(o[2]):
			blocked[Vector2i(o[0], o[1])] = true
	var props: Dictionary = DataFiles.load_json("res://assets/props/props.json")
	for p in r["props"]:
		if props[p["prop"]]["collider"] != null:
			blocked[Vector2i(p["tile"][0], p["tile"][1])] = true

	var spawn := Vector2i(int(r["spawn"][0]), int(r["spawn"][1]))
	check(not blocked.has(spawn), "spawn tile is walkable")
	var seen := {spawn: true}
	var queue: Array[Vector2i] = [spawn]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h or blocked.has(n) or seen.has(n):
				continue
			seen[n] = true
			queue.append(n)

	for n in r["npcs"]:
		var t := Vector2i(int(n["tile"][0]), int(n["tile"][1]))
		check(seen.has(t), "NPC %s stands on a tile reachable from spawn %s" % [n["id"], t])
	for i in r["interactables"]:
		var t := Vector2i(int(i["tile"][0]), int(i["tile"][1]))
		var reachable := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if seen.has(t + Vector2i(dx, dy)):
					reachable = true
		check(reachable, "interactable '%s' is reachable on foot" % i["name"])
	var open_tiles := 0
	for y in range(h):
		for x in range(w):
			if not blocked.has(Vector2i(x, y)) and not seen.has(Vector2i(x, y)):
				open_tiles += 1
	check(open_tiles < 40, "few walkable tiles are cut off from the village (%d)" % open_tiles)


# -- integration: the real game scene with real input -----------------------------------------
func _press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _spawn_game(request: Dictionary) -> Node:
	GameState.start_request = request
	var game: Node = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	return game


func test_integration() -> void:
	var game := await _spawn_game({"mode": "new"})
	check(DialogueRunner.active, "new game opens with the intro narration")
	DialogueRunner.cancel()
	check(GameState.mode == GameState.Mode.EXPLORE, "exploring after the intro")
	var player: Player = game.player
	var npcs: Dictionary = game.region.npcs
	check(npcs.size() == 5, "five villagers spawned")

	# movement and walking animation
	var start := player.global_position
	Input.action_press("move_down")
	await _frames(20)
	Input.action_release("move_down")
	check(player.global_position.y > start.y + 15, "holding move_down walks the player south")
	check(player.facing == "down", "facing follows movement")

	# collision: walk north into the house wall from the front yard
	player.teleport(Vector2(7.5, 7.5) * 32.0, "up")
	Input.action_press("move_up")
	await _frames(60)
	Input.action_release("move_up")
	check(player.global_position.y >= 7.0 * 32.0, "the house wall stops the player (y=%.1f)" % player.global_position.y)

	# collision: cliffs on the map edge
	player.teleport(Vector2(10.5, 3.5) * 32.0, "up")
	Input.action_press("move_up")
	await _frames(90)
	Input.action_release("move_up")
	# rows 0-1 are solid cliff, so the collider top (y-8) can never be above y=64
	check(player.global_position.y >= 2.0 * 32.0 + 8.0 - 0.5, "boundary cliffs stop the player (y=%.1f)" % player.global_position.y)

	# talk to Yosef through the real interaction path
	var yosef: Npc = npcs["yosef"]
	yosef.set_physics_process(false)
	player.teleport(yosef.global_position + Vector2(0, 18), "up")
	await _frames(3)
	check(player.focus != null and player.focus.display_name == "Yosef the trader", "player focuses the nearby NPC")
	await _press("interact")
	check(DialogueRunner.active and GameState.mode == GameState.Mode.DIALOGUE, "E starts the dialogue")
	check(game.hud.dialogue_box.visible, "dialogue box is shown")
	var guard := 0
	while DialogueRunner.active and guard < 60:
		await _press("interact")
		guard += 1
		await _frames(2)
	check(not DialogueRunner.active, "dialogue ended through UI input (took %d presses)" % guard)
	check(Journal.has_entry("rumor_yosef"), "talking to Yosef recorded the rumor in the journal")
	check(GameState.mode == GameState.Mode.EXPLORE, "control returns to the player after dialogue")

	# journal screen opens and closes with J
	await _press("journal")
	check(game.hud.journal_view.visible and GameState.mode == GameState.Mode.JOURNAL, "J opens the journal")
	check(game.hud.journal_view._list.item_count == 1, "journal lists the new entry")
	await _press("journal")
	check(not game.hud.journal_view.visible and GameState.mode == GameState.Mode.EXPLORE, "J closes the journal")

	# pick up the jar
	var jar_pos := Vector2(8.5, 23.0) * 32.0
	player.teleport(jar_pos + Vector2(0, 14), "up")
	await _frames(3)
	check(player.focus is PickupInteractable, "player focuses the clay jar")
	await _press("interact")
	check(GameState.item_count("water_jar") == 1, "jar added to satchel")
	var presses := 0
	while DialogueRunner.active and presses < 20:
		await _press("interact")
		presses += 1
	check(not DialogueRunner.active, "pickup text closes")
	check(GameState.has_flag("picked_water_jar"), "pickup remembered by flag")

	# save through the game, reload, and compare
	player.teleport(Vector2(13.25, 11.5) * 32.0, "left")
	game._save_to(2)
	var saved_pos := player.global_position
	var journal_before := JSON.stringify(_norm(Journal.serialize()))
	game.queue_free()
	await get_tree().process_frame
	GameState.new_game()
	var game2 := await _spawn_game({"mode": "load", "slot": 2})
	check(game2.player.global_position.distance_to(saved_pos) < 0.01, "player position restored after reload")
	check(game2.player.facing == "left", "player facing restored")
	check(JSON.stringify(_norm(Journal.serialize())) == journal_before, "journal identical after reload")
	check(GameState.item_count("water_jar") == 1, "inventory restored after reload")
	check(not DialogueRunner.active, "no intro replay when loading a save")
	var jar_nodes: Array = game2.region.entities.get_children().filter(func(n): return n is PickupInteractable)
	check(jar_nodes.is_empty(), "collected jar does not respawn")
	game2.queue_free()
	await get_tree().process_frame
