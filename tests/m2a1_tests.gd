extends RefCounted
## Milestone 2A.1 checks: scripture links in the journal, scrolls and Ezra's lessons, and the
## health options (resting regeneration and food). Driven by test_runner.gd.

var t: Node
var game: Node


func run(runner: Node) -> void:
	t = runner
	t._section = "m2a1-data"
	test_data()
	test_full_kjv()
	t._section = "m2a1-links"
	test_link_logic()
	await test_ezra_flow()
	t._section = "m2a1-world"
	await test_world_placement()
	t._section = "m2a1-health"
	test_regen()
	test_eating()
	t._section = "m2a1-save"
	test_save()


func _fresh() -> void:
	t._fresh()


# -- data --------------------------------------------------------------------------------------
func test_data() -> void:
	var raw = DataFiles.load_json("res://data/journal/entries.json")
	var rels: Dictionary = Journal.relationships
	t.check(Journal.link_ids().size() >= 4, "scripture links are loaded")
	for lid in Journal.link_ids():
		var l: Dictionary = Journal.link_def(lid)
		t.check(raw["entries"].has(l["entry"]), "link %s belongs to a real journal entry" % lid)
		t.check(rels.has(l["relationship"]), "link %s has a known relationship type" % lid)
		t.check(l["testament"] == "old", "link %s is an Old Testament passage" % lid)
		t.check(Scripture.is_complete(l["reference"]), "link %s: KJV text present for %s" % [lid, l["reference"]])
		if l.get("nt_ref", "") != "":
			t.check(Scripture.is_complete(l["nt_ref"]), "link %s: KJV text present for %s" % [lid, l["nt_ref"]])
		t.check(l.has("explicit_nt"), "link %s says whether the New Testament states it outright" % lid)
	t.check(Journal.link_def("kings_1_8")["explicit_nt"] == false and Journal.link_def("malachi_3_1")["explicit_nt"] == true,
		"explicit and implicit connections are told apart")
	t.check(Journal.link_def("kings_1_8").has("dissent"), "a teacher's disagreement can be recorded on a link")
	var entry_links := {}
	for lid in Journal.link_ids():
		var e: String = Journal.link_def(lid)["entry"]
		entry_links[e] = int(entry_links.get(e, 0)) + 1
	t.check(entry_links.values().any(func(n): return n >= 2), "one entry can carry several links")
	t.check(raw["entries"].keys().any(func(k): return not entry_links.has(k)), "not every entry needs an Old Testament link")
	for id in GameState.items:
		var def: Dictionary = GameState.items[id]
		if def.get("category", "") == "scroll":
			t.check(def.get("unique", false), "scroll %s is unique" % id)
			for lid in def.get("reveals", []):
				t.check(Journal.has_link_definition(lid), "scroll %s reveals a real link (%s)" % [id, lid])
		if def.get("category", "") == "food":
			t.check(int(def.get("heal", 0)) > 0, "food %s heals something" % id)


func test_full_kjv() -> void:
	t.check(Scripture.get_verses("Psalms 119:1-176").size() == 176, "the whole KJV is loaded (Psalm 119 has all 176 verses)")
	t.check(Scripture.is_complete("Revelation 22:21") and Scripture.is_complete("Genesis 1:1"), "first and last verses of the Bible are present")
	t.check(Scripture.get_passage("Malachi 3:1").contains("and the Lord, whom ye seek"), "Malachi 3:1 reads as the KJV has it")
	t.check(Scripture.get_passage("Malachi 4:6").contains("to their fathers"), "Malachi 4:6 reads as the KJV has it")
	t.check(Scripture.get_passage("2 Kings 1:8").contains("He was an hairy man"), "supplied-word brackets are removed from the text")
	var stray := false
	for ref in ["Genesis 1:2", "John 3:16", "Romans 8:28", "2 Kings 1:8", "Psalms 23:1-6"]:
		if Scripture.get_passage(ref).contains("[") or Scripture.get_passage(ref).contains("’"):
			stray = true
	t.check(not stray, "no bracket markers or typographic apostrophes in sampled verses")


# -- journal logic -----------------------------------------------------------------------------
func test_link_logic() -> void:
	_fresh()
	Journal.discover("rumor_yosef")
	t.check(Journal.links_for("rumor_yosef").is_empty(), "a new entry shows no connections by itself")
	var view := JournalView.new()
	t.check(not view._entry_bbcode(Journal.get_entry("rumor_yosef")).contains("Malachi"), "the journal does not reveal an undiscovered connection")
	t.check(Journal.discover_link("malachi_3_1", "Elder Ezra"), "a connection can be found")
	t.check(not Journal.discover_link("malachi_3_1"), "finding it twice changes nothing")
	var found: Array = Journal.links_for("rumor_yosef")
	t.check(found.size() == 1 and found[0]["reference"] == "Malachi 3:1" and found[0]["found"]["source"] == "Elder Ezra", "found connection records who showed it")
	var text: String = view._entry_bbcode(Journal.get_entry("rumor_yosef"))
	t.check(text.contains("Malachi 3:1") and text.contains("I will send my messenger"), "found connection shows its KJV text")
	t.check(text.contains("Matthew 11:10") and text.contains("says so outright"), "the player is told the New Testament makes the connection")
	t.check(text.contains("do not yet understand"), "finding is not understanding")
	t.check(Journal.get_entry("rumor_yosef")["text"].begins_with("Yosef the trader"), "the original eyewitness text is untouched")
	Journal.annotate("rumor_yosef", "later", [], "x", "n1")
	t.check(Journal.links_for("rumor_yosef").size() == 1, "later notes do not disturb found connections")
	t.check(Journal.understand_link("malachi_3_1") and not Journal.understand_link("malachi_3_1"), "understanding is a separate, one-time step")
	t.check(not Journal.understand_link("kings_1_8"), "an unfound connection cannot be understood")
	var snap: Dictionary = Journal.serialize()
	Journal.reset()
	t.check(not Journal.has_link("malachi_3_1"), "a new game starts with no connections")
	Journal.deserialize(snap)
	t.check(Journal.has_link("malachi_3_1") and Journal.links_for("rumor_yosef")[0]["found"]["understood"], "connections survive save/load, with their understanding")
	# found before the entry was written: it waits, then shows
	_fresh()
	Journal.discover_link("kings_1_8", "Elder Ezra")
	Journal.discover_link("malachi_4_5", "Elder Ezra")
	t.check(not Journal.has_entry("testimony_hannah"), "no entry yet")
	Journal.discover("testimony_hannah")
	t.check(Journal.links_for("testimony_hannah").size() == 2, "connections found early appear when their entry is written")
	var ht: String = view._entry_bbcode(Journal.get_entry("testimony_hannah"))
	t.check(ht.contains("Not everyone agrees"), "a dissenting teacher is shown")
	t.check(not ht.contains("There may be more"), "no hint of more once all are found")
	_fresh()
	Journal.discover("testimony_hannah")
	Journal.discover_link("kings_1_8")
	t.check(view._entry_bbcode(Journal.get_entry("testimony_hannah")).contains("There may be more"), "a quiet hint says more remains to be found")
	view.free()
	t.check(Journal.link_def("nope").is_empty() and not Journal.has_link("nope"), "unknown link ids are harmless to ask about")


# -- Ezra and the scrolls ------------------------------------------------------------------------
func test_ezra_flow() -> void:
	t._section = "m2a1-ezra"
	_fresh()
	GameState.set_flag("heard_rumor")
	await t.play("ezra", [1, 0])
	t.check(Journal.has_link("isaiah_40_3"), "Ezra's own reading of Isaiah is recorded as a found connection")
	t.check(not Journal.has_link("malachi_3_1") and not Journal.has_link("kings_1_8"), "nothing else is revealed yet")
	var lines: Array = await t.play("ezra")
	t.check(lines.any(func(l): return str(l).contains("a good deal more written than Isaiah")), "a new conversation after the sword: Ezra teaches looking backward")
	t.check(GameState.has_flag("ezra_scroll_hint") and Journal.has_entry("q_look_backward"), "the lesson is remembered and journaled")
	t.check(not lines.any(func(l): return str(l).to_lower().contains("fulfil")), "Ezra does not announce a fulfilment")
	lines = await t.play("ezra")
	t.check(not lines.any(func(l): return str(l).contains("good deal more")), "the lesson is not repeated")
	# a scroll is nothing until a teacher reads it
	GameState.add_item("scroll_malachi")
	t.check(not Journal.has_link("malachi_3_1"), "carrying a scroll reveals nothing")
	Journal.discover("rumor_yosef")
	lines = await t.play("ezra")
	t.check(lines.any(func(l): return str(l).contains("Hand it here")), "Ezra reads the scroll he is shown")
	t.check(lines.any(func(l): return str(l).contains("I will send my messenger, and he shall prepare the way before me")), "he reads the KJV words, not a paraphrase")
	t.check(Journal.has_link("malachi_3_1") and Journal.has_link("malachi_4_5"), "the scroll's connections are found")
	t.check(Journal.links_for("rumor_yosef").size() == 1, "and appear on the matching entry")
	t.check(GameState.item_count("scroll_malachi") == 1 and GameState.has_flag("scroll_read_scroll_malachi"), "the scroll stays in the satchel, marked as read")
	lines = await t.play("ezra")
	t.check(not lines.any(func(l): return str(l).contains("Hand it here")), "a scroll is read once")
	t.check(not GameState.add_item("scroll_malachi"), "a scroll cannot be picked up twice")
	GameState.add_item("scroll_kings")
	lines = await t.play("ezra")
	t.check(lines.any(func(l): return str(l).contains("hairy man")) and Journal.has_link("kings_1_8"), "the second scroll is read too")
	t.check(lines.any(func(l): return str(l).contains("Do not make too much of a garment")), "and Ezra cautions against reading too much into it")
	# reading a scroll that is not in the satchel does nothing
	_fresh()
	Effects.read_scroll("scroll_malachi")
	t.check(not Journal.has_link("malachi_3_1"), "an unheld scroll cannot be read")
	# before the rumor, Ezra does not read scrolls (the village flow comes first)
	GameState.add_item("scroll_malachi")
	var early: Array = await t.play("ezra")
	t.check(not Journal.has_link("malachi_3_1") and not early.any(func(l): return str(l).contains("Hand it here")), "Ezra only teaches once the protagonist has come to him with the rumor")
	# players who already had the whole sword conversation still get the lesson
	_fresh()
	GameState.set_flag("ezra_consulted")
	GameState.set_flag("ezra_sword_given")
	lines = await t.play("ezra")
	t.check(lines.any(func(l): return str(l).contains("good deal more")), "an earlier save reaches the lesson as well")
	await t.play("ezra")
	t.check(Journal.has_link("isaiah_40_3"), "an earlier save also receives Ezra's Isaiah connection")


func test_world_placement() -> void:
	_fresh()
	game = await t._spawn_game({"mode": "new"})
	DialogueRunner.cancel()
	var ids := _pickup_ids(game)
	for want in ["scroll_malachi", "scroll_kings", "village_bread"]:
		t.check(ids.has(want), "the village holds %s" % want)
	var mal = _pickup(game, "scroll_malachi")
	t.check(mal != null and mal.item_id == "scroll_malachi", "the Malachi scroll is a real pickup")
	if mal != null:
		var around: Array = []
		for c in game.region.entities.get_children():
			if c is Interactable and c != mal and c.position.distance_to(mal.position) < 40.0:
				around.append(c)
		t.check(around.is_empty(), "no other interactable crowds the scroll")
	game.queue_free()
	await t.get_tree().process_frame
	game = await t._spawn_game({"mode": "training"})
	var yids := _pickup_ids(game)
	for want in ["yard_crate_figs", "yard_crate_bread", "yard_crate_scroll", "yard_crate_scroll2"]:
		t.check(yids.has(want), "the training yard has %s" % want)
	game.queue_free()
	await t.get_tree().process_frame
	game = null


func _pickup_ids(g: Node) -> Array:
	var out: Array = []
	for c in g.region.entities.get_children():
		if c is PickupInteractable:
			out.append(c.pickup_id)
	return out


func _pickup(g: Node, id: String):
	for c in g.region.entities.get_children():
		if c is PickupInteractable and c.pickup_id == id:
			return c
	return null


# -- health ------------------------------------------------------------------------------------
func test_regen() -> void:
	_fresh()
	GameState.mode = GameState.Mode.EXPLORE
	t.check(Combat.regen.get("enabled", false), "resting recovery is on by default")
	t.check(Combat.regen_ceiling() == 6, "resting recovers up to half of full health")
	Combat.hurt_player(8)
	t.check(Combat.player_hp == 4, "wounded")
	Combat._process(7.0)
	t.check(Combat.player_hp == 4, "no recovery straight after a fight")
	Combat._process(1.5)
	Combat._process(4.1)
	t.check(Combat.player_hp == 5, "after resting a while, health slowly returns")
	Combat._process(4.1)
	t.check(Combat.player_hp == 6, "one point per interval")
	for i in 5:
		Combat._process(4.1)
	t.check(Combat.player_hp == 6, "resting alone stops at the ceiling")
	Combat.hurt_player(1)
	Combat._process(7.9)
	Combat._process(0.05)
	t.check(Combat.player_hp == 5, "taking a hit restarts the wait")
	Combat.swung(Vector2.ZERO)
	Combat._process(7.9)
	Combat._process(0.05)
	t.check(Combat.player_hp == 5, "swinging a sword also counts as fighting")
	GameState.mode = GameState.Mode.DIALOGUE
	Combat._process(30.0)
	Combat._process(30.0)
	t.check(Combat.player_hp == 5, "no recovery while in dialogue or a menu")
	GameState.mode = GameState.Mode.EXPLORE
	Combat.regen["enabled"] = false
	Combat._process(30.0)
	Combat._process(30.0)
	t.check(Combat.player_hp == 5, "regeneration can be switched off in data")
	Combat.regen["enabled"] = true
	Combat.player_hp = 0
	Combat._process(30.0)
	Combat._process(30.0)
	t.check(Combat.player_hp == 0, "the fallen do not regenerate")
	Combat.reset()


func test_eating() -> void:
	_fresh()
	t.check(InputMap.has_action("eat"), "an eat control exists")
	t.check(Combat.eat() == "", "no food, nothing eaten")
	GameState.add_item("flatbread", 2, true)
	GameState.add_item("fig_cake", 1, true)
	t.check(Combat.eat() == "" and GameState.item_count("flatbread") == 2, "nothing is eaten when unhurt")
	Combat.player_hp = 10
	t.check(Combat.eat() == "flatbread" and Combat.player_hp == 12 and GameState.item_count("flatbread") == 1, "a small wound uses the small food")
	Combat.player_hp = 4
	t.check(Combat.eat() == "fig_cake" and Combat.player_hp == 8 and GameState.item_count("fig_cake") == 0, "a big wound uses the big food")
	Combat.player_hp = 11
	Combat.eat()
	t.check(Combat.player_hp == 12 and GameState.item_count("flatbread") == 0, "healing never exceeds full health")
	Combat.player_hp = 3
	t.check(Combat.eat() == "", "an empty satchel gives nothing")
	Combat.player_hp = 0
	GameState.add_item("flatbread", 1, true)
	t.check(Combat.eat() == "" and GameState.item_count("flatbread") == 1, "the fallen cannot eat")
	Combat.reset()


# -- saves -------------------------------------------------------------------------------------
func test_save() -> void:
	_fresh()
	Journal.discover("testimony_hannah")
	Journal.discover_link("kings_1_8", "Elder Ezra")
	GameState.add_item("scroll_kings", 1, true)
	GameState.set_flag("scroll_read_scroll_kings")
	t.check(SaveManager.save_slot(2), "save")
	_fresh()
	t.check(SaveManager.load_slot(2), "load")
	t.check(Journal.has_link("kings_1_8") and Journal.links_for("testimony_hannah").size() == 1, "found connections come back after loading")
	t.check(not Journal.has_link("malachi_4_5"), "and undiscovered ones stay hidden")
	t.check(GameState.item_count("scroll_kings") == 1 and GameState.has_flag("scroll_read_scroll_kings"), "the scroll and its read mark persist")
	# an older save has no links block at all
	var d: Dictionary = Journal.serialize()
	d.erase("links")
	Journal.deserialize(d)
	t.check(not Journal.has_link("kings_1_8"), "an older save without links loads cleanly")
	Journal.deserialize({"entries": {}, "order": [], "links": {"gone_link": {"day": 1}, "kings_1_8": {"day": 3, "source": "x"}}})
	t.check(Journal.has_link("kings_1_8") and not Journal.has_link("gone_link"), "a link dropped from the data is quietly forgotten")
