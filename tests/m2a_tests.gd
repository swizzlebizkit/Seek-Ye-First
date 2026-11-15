extends RefCounted
## Milestone 2A checks: Ezra's sword, equipment, sword combat, behaviour profiles, the three
## conflict resolutions, player survival, interaction targeting. Driven by test_runner.gd.

const BANNED_WORDS := ["truth", "righteous", "gospel", "faith", "salvation", "word of god", "ephesians", "armor of god", "armour of god"]
const DIRS := ["right", "left", "down", "up"]

var t: Node
var game: Node
var player: Player


func run(runner: Node) -> void:
	t = runner
	t._section = "m2a-data"
	test_data()
	t._section = "m2a-equipment"
	test_equipment()
	await test_sword_gift()
	test_targeting_pure()
	t._section = "m2a-village"
	await test_targeting_village()
	await test_village_noncombatants()
	t._section = "m2a-combat"
	test_hit_geometry()
	await open_yard()
	await test_player_attack()
	await test_mode_gating()
	await test_directional_hits()
	await test_player_damage()
	t._section = "m2a-behaviour"
	await test_noncombatant()
	await test_diplomacy()
	await test_avoidance()
	await test_combat_outcomes()
	await test_guard()
	await test_interruption()
	t._section = "m2a-save"
	await test_save_load()
	close_game()


# -- helpers -----------------------------------------------------------------------------------
func open_yard() -> void:
	close_game()
	game = await t._spawn_game({"mode": "training"})
	player = game.player
	GameState.mode = GameState.Mode.EXPLORE
	freeze_all()


func open_village() -> void:
	close_game()
	game = await t._spawn_game({"mode": "new"})
	DialogueRunner.cancel()
	player = game.player
	GameState.mode = GameState.Mode.EXPLORE


func close_game() -> void:
	if game != null and is_instance_valid(game):
		game.queue_free()
		await t.get_tree().process_frame
	game = null


func freeze_all() -> void:
	for n in game.region.npcs.values():
		if is_instance_valid(n):
			n.set_physics_process(false)


func npc(id: String):
	return game.region.npcs[id]


func spot() -> Vector2:
	return Vector2(21.5, 14.5) * 32.0


func dummy(pos: Vector2, profile: String = "cutthroat") -> Npc:
	var n := Npc.new()
	n.setup({"id": "dummy_%d" % randi(), "profile": profile, "sprite": "cutthroat", "dialogue": "", "tile": [pos.x / 32.0, pos.y / 32.0], "wander": 0})
	game.region.entities.add_child(n)
	n.set_physics_process(false)
	return n


func swing(p: Player) -> bool:
	var started := p.try_attack()
	await t._frames(32)
	return started


func word_free(text: String) -> bool:
	var low := text.to_lower()
	for w in BANNED_WORDS:
		if low.contains(w):
			return false
	return true


# -- data --------------------------------------------------------------------------------------
func test_data() -> void:
	var expected := ["belt", "body", "footwear", "shield", "helmet", "sword"]
	var ids := Equipment.slot_ids()
	t.check(ids.size() == 6, "six equipment slots")
	for e in expected:
		t.check(ids.has(e), "slot '%s' exists" % e)
	for s in Equipment.slot_defs:
		t.check(word_free(s["label"]), "slot label '%s' reveals no symbolism" % s["label"])
		var d: String = s.get("default", "")
		t.check(d == "" or (Equipment.is_equipment(d) and Equipment.slot_of(d) == s["id"]), "default for %s is a valid item for that slot" % s["id"])
	var per_slot := {}
	for id in GameState.items:
		if not Equipment.is_equipment(id):
			continue
		var def: Dictionary = GameState.items[id]
		t.check(ids.has(def.get("slot", "")), "%s: valid slot" % id)
		per_slot[def["slot"]] = int(per_slot.get(def["slot"], 0)) + 1
		t.check(word_free(def["name"] + " " + def.get("description", "")), "%s: text does not spell out the later meaning" % id)
		for k in def.get("stats", {}):
			t.check(Equipment.stat_labels.has(k) and typeof(def["stats"][k]) in [TYPE_INT, TYPE_FLOAT], "%s: stat '%s' is a labelled number" % [id, k])
			t.check(not str(k).contains("spirit") and not str(k).contains("faith"), "%s: no spiritual stat" % id)
	for e in expected:
		t.check(int(per_slot.get(e, 0)) >= 1, "at least one item for slot %s" % e)
	t.check(GameState.items["ezra_sword"].get("unique", false), "Ezra's Sword is unique")
	t.check(GameState.items["ezra_sword"].get("gift_from", "") == "ezra", "Ezra's Sword records who gave it")
	for pid in Combat.profiles:
		var p: Dictionary = Combat.profile(pid)
		t.check(["hostile", "noncombatant", "contextual"].has(p["disposition"]), "profile %s has a valid disposition" % pid)
		if p["disposition"] != "noncombatant":
			t.check(p.has("attack"), "profile %s defines an attack" % pid)
		t.check(p.has("hp"), "profile %s has hp" % pid)
		t.check(not (p.keys().has("faction") or p.keys().has("religion") or p.keys().has("ethnicity")), "profile %s is not group-based" % pid)
	for eid in Combat.encounters:
		var enc: Dictionary = Combat.encounters[eid]
		t.check(enc["valid"].has("diplomacy") and enc["valid"].has("avoidance") and enc["valid"].has("combat_victory"), "encounter %s allows all three paths" % eid)
		for o in enc["valid"]:
			t.check(Combat.outcome_labels.has(o), "encounter %s outcome %s is defined" % [eid, o])
	var yard: Dictionary = DataFiles.load_json("res://data/regions/training_yard.json")
	var actors: Array = yard["npcs"].map(func(n): return n["id"])
	for n in yard["npcs"]:
		t.check(Combat.has_profile(n["profile"]), "yard NPC %s profile exists" % n["id"])
		t.check(FileAccess.file_exists("res://assets/characters/%s.png" % n["sprite"]), "yard NPC %s has a walk sheet" % n["id"])
		t.check(FileAccess.file_exists("res://assets/characters/%s_attack.png" % n["sprite"]), "yard NPC %s has an attack sheet" % n["id"])
		if n.get("dialogue", "") != "":
			t.check(FileAccess.file_exists("res://data/dialogue/%s.json" % n["dialogue"]), "yard NPC %s dialogue exists" % n["id"])
		if n.get("encounter", "") != "":
			t.check(Combat.has_encounter(n["encounter"]), "yard NPC %s encounter exists" % n["id"])
	for eid in Combat.encounters:
		t.check(actors.has(Combat.encounters[eid]["actor"]), "encounter %s actor exists in the yard" % eid)
	t.check(FileAccess.file_exists("res://assets/characters/protagonist_attack.png"), "protagonist attack sheet exists")
	t.check(FileAccess.file_exists("res://assets/characters/swipe_fx.png"), "swipe effect sheet exists")
	for st in ["full", "half", "empty"]:
		t.check(FileAccess.file_exists("res://assets/ui/heart_%s.png" % st), "heart icon %s exists" % st)


# -- equipment ---------------------------------------------------------------------------------
func test_equipment() -> void:
	t._section = "m2a-equipment"
	t._fresh()
	t.check(Equipment.equipped("belt") == "rope_belt" and Equipment.equipped("body") == "plain_tunic" and Equipment.equipped("footwear") == "worn_sandals", "new game wears sensible default clothes")
	t.check(Equipment.equipped("sword") == "" and Equipment.equipped("shield") == "" and Equipment.equipped("helmet") == "", "no sword, shield or helmet at the start")
	t.check(not Equipment.has_sword() and Equipment.weapon().is_empty(), "no weapon at the start")
	t.check(Equipment.stat("defense") == 0.0 and is_equal(Equipment.speed_multiplier(), 1.0), "default gear has no stat bonus")
	t.check(not Equipment.equip("felt_cap"), "cannot equip an item that is not owned")
	t.check(Equipment.equip_problem("water_jar") != "", "cannot equip a non-equipment item")
	GameState.add_item("felt_cap", 1, true)
	GameState.add_item("wicker_shield", 1, true)
	GameState.add_item("quilted_vest", 1, true)
	GameState.add_item("road_boots", 1, true)
	t.check(Equipment.equip("felt_cap") and Equipment.equipped("helmet") == "felt_cap", "helmet equips into its slot")
	t.check(Equipment.equip("quilted_vest") and Equipment.equipped("body") == "quilted_vest", "swapping body armor replaces the old item")
	t.check(GameState.item_count("plain_tunic") == 1, "the replaced item stays in the satchel")
	Equipment.equip("wicker_shield")
	Equipment.equip("road_boots")
	t.check(is_equal(Equipment.stat("defense"), 2.0), "defense sums over worn items (cap + vest)")
	t.check(is_equal(Equipment.stat("block"), 2.0), "shield adds frontal guard")
	t.check(is_equal(Equipment.stat("mobility"), -0.01), "mobility sums (vest -4%, shield -3%, boots +6%)")
	t.check(is_equal(Equipment.speed_multiplier(), 0.99), "speed multiplier follows mobility")
	t.check(Combat.damage_after_armor(3, false) == 1 and Combat.damage_after_armor(3, true) == 1, "damage never drops below 1")
	t.check(Combat.damage_after_armor(5, false) == 3 and Combat.damage_after_armor(5, true) == 1, "shield only helps against frontal hits")
	t.check(Equipment.unequip("helmet") and Equipment.equipped("helmet") == "", "unequip empties the slot")
	t.check(GameState.item_count("felt_cap") == 1, "unequipped item stays in the satchel")
	t.check(not Equipment.unequip("helmet"), "unequipping an empty slot is a no-op")
	# removing an owned item auto-unequips it (validation)
	GameState.remove_item("wicker_shield")
	t.check(Equipment.equipped("shield") == "", "losing an item takes it off")
	# validation of corrupt data
	Equipment.deserialize({"worn": {"sword": "rope_belt", "belt": "ghost_item", "nowhere": "rope_belt", "body": "plain_tunic"}})
	t.check(Equipment.equipped("sword") == "" and Equipment.equipped("belt") == "" and not Equipment.worn.has("nowhere"), "invalid saved equipment is dropped")
	t.check(Equipment.equipped("body") == "plain_tunic", "valid saved equipment survives validation")
	# the details text shows plain numbers
	var view := EquipmentView.new()
	var txt := view.details_bbcode("ezra_sword")
	t.check(txt.contains("Attack: 2") and txt.contains("Ezra"), "equipment details show attack and the gift's description")
	t.check(word_free(view.details_bbcode("wicker_shield")), "equipment screen text reveals no symbolism")
	view.free()


func is_equal(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func test_sword_gift() -> void:
	t._section = "m2a-sword"
	t._fresh()
	var before: Array = await t.play("ezra")
	t.check(not Equipment.has_sword() and GameState.item_count("ezra_sword") == 0, "Ezra gives no sword before the rumor is heard")
	GameState.set_flag("heard_rumor")
	var lines: Array = await t.play("ezra", [1, 0])
	t.check(lines.any(func(l): return str(l).contains("not everyone you will meet")), "Ezra warns about the road")
	t.check(lines.any(func(l): return str(l).contains("For protection on the road")), "Ezra gives the sword for protection")
	t.check(GameState.item_count("ezra_sword") == 1, "Ezra's Sword is in the satchel")
	t.check(Equipment.equipped("sword") == "ezra_sword", "Ezra's Sword is equipped through the equipment system")
	t.check(GameState.has_flag("ezra_sword_given"), "gift remembered by flag")
	t.check(Journal.has_entry("obs_ezra_sword"), "the gift is recorded in the journal")
	t.check(Quests.is_active("word_jordan") or Quests.is_done("word_jordan") or GameState.has_flag("ezra_consulted"), "gift is compatible with the quest chain")
	t.check(GameState.has_flag("ezra_consulted"), "asking Ezra is still recorded as before")
	await t.play("ezra")
	await t.play("ezra", [0, 1, 0])
	t.check(GameState.item_count("ezra_sword") == 1, "the sword cannot be acquired twice")
	t.check(not GameState.add_item("ezra_sword"), "unique items refuse duplicate acquisition")
	Effects.run({"give_item": {"item": "ezra_sword"}})
	t.check(GameState.item_count("ezra_sword") == 1, "give_item effect cannot duplicate it")
	# unequipped but owned: stays owned, does not re-give
	Equipment.unequip("sword")
	await t.play("ezra")
	t.check(GameState.item_count("ezra_sword") == 1 and not Equipment.has_sword(), "a deliberately unequipped sword is not re-given or re-equipped")
	# persistence
	Equipment.equip("ezra_sword")
	t.check(SaveManager.save_slot(3), "save with the sword equipped")
	t._fresh()
	t.check(not Equipment.has_sword(), "fresh game has no sword")
	t.check(SaveManager.load_slot(3), "load")
	t.check(Equipment.equipped("sword") == "ezra_sword" and GameState.has_flag("ezra_sword_given") and GameState.item_count("ezra_sword") == 1, "sword, equipped status and gift flag persist across save/load")
	Equipment.unequip("sword")
	SaveManager.save_slot(3)
	t._fresh()
	SaveManager.load_slot(3)
	t.check(not Equipment.has_sword() and GameState.item_count("ezra_sword") == 1, "unequipped status also persists")
	# a player who already consulted Ezra before the sword existed still receives it
	t._fresh()
	GameState.set_flag("heard_rumor")
	GameState.set_flag("ezra_consulted")
	await t.play("ezra")
	t.check(Equipment.equipped("sword") == "ezra_sword", "an earlier save that had already consulted Ezra receives the sword too")
	# saves from before equipment existed load with defaults
	t._fresh()
	SaveManager.save_slot(2)
	var path := SaveManager.slot_path(2)
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	data["version"] = 1
	data.erase("equipment")
	data.erase("combat")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	t._fresh()
	t.check(SaveManager.load_slot(2), "a version-1 save still loads")
	t.check(Equipment.equipped("belt") == "rope_belt" and Combat.player_hp == Combat.max_hp(), "version-1 save gets default equipment and full health")
	# full order-A style run keeps the whole quest chain working with the sword in the middle
	t._fresh()
	await t.play("yosef", [0, 1])
	await t.play("ezra", [0, 0])
	await t.play("hannah", [0, 1])
	t.check(Quests.is_done("word_jordan") and GameState.has_flag("road_east_ready"), "quest chain completes with the sword gift in the middle")
	t.check(Equipment.has_sword(), "and the sword is held")


# -- interaction targeting ---------------------------------------------------------------------
func test_targeting_pure() -> void:
	t._section = "m2a-targeting"
	var holder := Node2D.new()
	t.add_child(holder)
	var mk := func(pos: Vector2, prio: int) -> Interactable:
		var i := Interactable.new()
		i.target_priority = prio
		i.position = pos
		holder.add_child(i)
		return i
	var origin := Vector2(100, 100)
	var right := Vector2.RIGHT
	var person: Interactable = mk.call(Vector2(130, 100), 2)
	var door: Interactable = mk.call(Vector2(130, 104), 0)
	t.check(InteractionTargeting.pick(origin, right, [door, person]) == person, "a person beats scenery at the same spot")
	var near_door: Interactable = mk.call(Vector2(115, 100), 0)
	var far_person: Interactable = mk.call(Vector2(160, 100), 2)
	t.check(InteractionTargeting.pick(origin, right, [near_door, far_person]) == near_door, "much nearer scenery still beats a distant person")
	var behind: Interactable = mk.call(Vector2(60, 100), 2)
	var ahead: Interactable = mk.call(Vector2(135, 100), 0)
	t.check(InteractionTargeting.pick(origin, right, [behind, ahead]) == ahead, "what is behind the player is not chosen over what they face")
	t.check(InteractionTargeting.pick(origin, right, [behind]) == null, "something only behind the player is never targeted")
	t.check(InteractionTargeting.pick(origin, Vector2.LEFT, [behind, ahead]) == behind, "turning around changes the target")
	var side_person: Interactable = mk.call(Vector2(100, 128), 2)
	var front_door: Interactable = mk.call(Vector2(122, 100), 0)
	t.check(InteractionTargeting.pick(origin, right, [side_person, front_door]) == front_door, "the object being faced beats a person off to the side")
	t.check(InteractionTargeting.pick(origin, Vector2.DOWN, [side_person, front_door]) == side_person, "facing the person selects them")
	# hysteresis: current focus is kept against a marginally better candidate
	var a: Interactable = mk.call(Vector2(130, 100), 0)
	var b: Interactable = mk.call(Vector2(128, 100), 0)
	t.check(InteractionTargeting.pick(origin, right, [a, b], a) == a, "focus does not flicker between near-equal candidates")
	t.check(InteractionTargeting.pick(origin, right, [a, b]) == b, "without a current focus the closer one wins")
	t.check(InteractionTargeting.pick(origin, right, [a, b], null) == b, "null current is accepted")
	var gated: Interactable = mk.call(Vector2(120, 100), 2)
	gated.gate = func(): return false
	t.check(InteractionTargeting.pick(origin, right, [gated, far_person]) == far_person, "unavailable targets are skipped")
	holder.queue_free()


func test_targeting_village() -> void:
	t._section = "m2a-targeting"
	await open_village()
	var ezra: Npc = npc("ezra")
	ezra.set_physics_process(false)
	var door_pos := Vector2(13.5, 8.15) * 32.0
	ezra.global_position = door_pos + Vector2(0, 14)
	player.teleport(ezra.global_position + Vector2(0, 20), "up")
	await t._frames(4)
	t.check(player.focus != null and player.focus.display_name == "Elder Ezra", "facing Ezra in front of his own door targets Ezra, not the door")
	t.check(player.focus._focused, "the current target shows its highlight ring")
	await t._press("interact")
	t.check(DialogueRunner.active and not DialogueRunner._speaker.contains("Door"), "E talks to Ezra")
	DialogueRunner.cancel()
	await t._frames(2)
	# Ezra has wandered off to the side: the door is the target
	ezra.global_position = door_pos + Vector2(70, 14)
	player.teleport(door_pos + Vector2(0, 22), "up")
	await t._frames(4)
	t.check(player.focus != null and player.focus.display_name == "Elder Ezra's house", "with Ezra elsewhere, the door is targeted")
	# only one target at a time, and E activates exactly it
	var seen := []
	var on_start := func(sp): seen.append(sp)
	DialogueRunner.started.connect(on_start)
	await t._press("interact")
	DialogueRunner.started.disconnect(on_start)
	t.check(seen.size() == 1, "one press starts exactly one interaction")
	DialogueRunner.cancel()
	await t._frames(2)
	# facing away from everything: no target
	player.teleport(door_pos + Vector2(0, 80), "down")
	await t._frames(4)
	t.check(player.focus == null, "facing empty ground targets nothing")
	# existing interactions are preserved: jar pickup and well
	var well_target_ok := false
	player.teleport(Vector2(19.5, 14.8) * 32.0, "up")
	await t._frames(4)
	well_target_ok = player.focus != null and player.focus.display_name == "The well"
	t.check(well_target_ok, "the well is still targetable")


func test_village_noncombatants() -> void:
	# villagers with the sword out: nobody is harmed, everyone reacts
	GameState.set_flag("heard_rumor")
	Effects.run_all([{"give_item": {"item": "ezra_sword"}}, {"equip": "ezra_sword"}])
	var yosef: Npc = npc("yosef")
	yosef.set_physics_process(true)
	player.teleport(yosef.global_position + Vector2(-16, 0), "right")
	await t._frames(2)
	var hp_before := yosef.hp
	await swing(player)
	t.check(yosef.hp == hp_before, "a villager is never injured by the sword")
	t.check(yosef.state == Npc.State.FLEE, "a struck villager flees")
	t.check(int(Combat.consequences["noncombatants_struck"]) == 1, "the assault is recorded as a consequence")
	await t._frames(20)
	t.check(yosef._refuses_talk(), "a frightened villager refuses to talk")
	t.check(yosef.is_alive() and yosef.hp == hp_before, "a villager cannot be killed")
	for i in range(8):
		yosef._invuln = 0.0
		yosef.receive_strike(player, 99, "right")
	t.check(yosef.is_alive() and yosef.hp == hp_before, "no amount of damage kills a villager")
	await close_game()


# -- hit geometry ------------------------------------------------------------------------------
func test_hit_geometry() -> void:
	var o := Vector2(200, 200)
	var c := o + Vector2(0, -4)
	var inside := {"right": c + Vector2(15, 0), "left": c + Vector2(-15, 0), "down": c + Vector2(0, 15), "up": c + Vector2(0, -15)}
	for d in DIRS:
		var r := SwordStrike.hit_rect(o, d, 26.0)
		t.check(r.has_point(inside[d]), "%s hit area covers a target 15px ahead" % d)
		var behind: Vector2 = c - (inside[d] - c)
		t.check(not r.has_point(behind), "%s hit area does not cover a target behind" % d)
		t.check(not r.has_point(c + SwordStrike.facing_vector(d) * 40.0), "%s hit area stops at the weapon's reach" % d)
		t.check(r.has_point(c + SwordStrike.facing_vector(d) * 20.0 + SwordStrike.facing_vector(d).orthogonal() * 12.0), "%s hit area is wide enough for a sideways offset" % d)
		t.check(not r.has_point(c + SwordStrike.facing_vector(d) * 20.0 + SwordStrike.facing_vector(d).orthogonal() * 30.0), "%s hit area is not unbounded sideways" % d)
	t.check(SwordStrike.hit_rect(o, "right", 26.0).size == Vector2(26, 30) and SwordStrike.hit_rect(o, "down", 26.0).size == Vector2(30, 26), "horizontal and vertical swings have matching proportions")


# -- player combat -----------------------------------------------------------------------------
func test_player_attack() -> void:
	player.teleport(spot(), "right")
	var weapon := Equipment.weapon()
	t.check(weapon["item"] == "ezra_sword" and weapon["attack"] == 2, "the training yard starts the player with Ezra's Sword")
	var swings := player.swings_started
	t.check(player.try_attack(), "a swing starts")
	var base_swings := player.swings_started
	t.check(player.swing_phase == 0 and player.is_attacking(), "the swing begins with a wind-up")
	t.check(not player.try_attack(), "cannot start a second swing during the first")
	await t._frames(8)
	t.check(player.swing_phase == 1, "the swing reaches its active phase")
	t.check(player._swipe.visible, "a swipe effect is visible during the swing")
	t.check(String(player._sprite.animation).begins_with("attack_"), "the attack animation is distinct from walking")
	await t._frames(10)
	t.check(player.swing_phase == 2, "then recovers")
	await t._frames(6)
	t.check(not player.is_attacking() and not player._swipe.visible, "the swing ends and the effect hides")
	t.check(not player.try_attack(), "the weapon cooldown still blocks an immediate repeat swing")
	await t._frames(12)
	t.check(player.swings_started == base_swings + 1, "that early press became the next swing once the cooldown ended (buffered)")
	await t._frames(40)
	# a press in the middle of a cooldown is ignored, not queued
	player.try_attack()
	await t._frames(6)
	var mid := player.swings_started
	t.check(not player.try_attack(), "a press mid-cooldown is refused")
	await t._frames(60)
	t.check(player.swings_started == mid, "and is not remembered")
	t.check(player.try_attack(), "after the cooldown a new swing is allowed")
	await t._frames(40)
	# press buffering
	player.try_attack()
	await t._frames(30)
	player.try_attack()  # press near the end of the cooldown is remembered
	await t._frames(30)
	t.check(player.swings_started >= mid + 3, "a press just before the cooldown ends is buffered")
	# no sword, no swing
	Equipment.unequip("sword")
	var n := player.swings_started
	t.check(not player.try_attack() and player.swings_started == n, "no sword equipped means no swing")
	Equipment.equip("ezra_sword")
	await t._frames(30)
	# facing is kept in all four directions and the sprite shows that direction
	for d in DIRS:
		player.teleport(spot(), d)
		await swing(player)
		t.check(player.facing == d, "swing keeps the %s facing" % d)
	# movement: committed during the swing, normal afterwards
	player.teleport(spot(), "right")
	var p0 := player.global_position
	player.try_attack()
	Input.action_press("move_down")
	await t._frames(8)
	Input.action_release("move_down")
	t.check(player.global_position.distance_to(p0) < 1.0, "the player cannot walk while committed to the swing")
	await t._frames(40)


func test_mode_gating() -> void:
	player.teleport(spot(), "right")
	await t._frames(40)
	for mode in [GameState.Mode.DIALOGUE, GameState.Mode.JOURNAL, GameState.Mode.PAUSED, GameState.Mode.EQUIPMENT, GameState.Mode.DEFEAT, GameState.Mode.MENU]:
		GameState.mode = mode
		var n := player.swings_started
		t.check(not player.try_attack(), "no swing starts in mode %d" % mode)
		await t._press("attack")
		t.check(player.swings_started == n and not player.is_attacking(), "the attack key does nothing in mode %d" % mode)
	GameState.mode = GameState.Mode.EXPLORE
	var n2 := player.swings_started
	await t._press("attack")
	t.check(player.swings_started == n2 + 1, "the attack key swings in normal play")
	await t._frames(40)
	# opening the equipment screen mid-swing cancels the swing
	player.try_attack()
	await t._frames(3)
	game.hud.equipment_view.open()
	await t._frames(2)
	t.check(not player.is_attacking(), "opening a menu cancels a swing in progress")
	game.hud.equipment_view.close()
	t.check(GameState.mode == GameState.Mode.EXPLORE, "closing the equipment screen returns to play")
	# a dialogue-advance press does not swing
	DialogueRunner.start_text(["Test line."])
	var n3 := player.swings_started
	await t._press("interact")
	await t._press("interact")
	t.check(player.swings_started == n3, "advancing dialogue never swings the sword")
	DialogueRunner.cancel()
	await t._frames(40)


func test_directional_hits() -> void:
	var p := spot()
	var offsets := {"right": Vector2(16, 0), "left": Vector2(-16, 0), "down": Vector2(0, 16), "up": Vector2(0, -16)}
	for d in DIRS:
		# in front: hit
		player.teleport(p, d)
		var front := dummy(p + offsets[d])
		await t._frames(3)
		var hp0 := front.hp
		await swing(player)
		t.check(front.hp == hp0 - 2, "%s swing damages a target in front for the sword's attack" % d)
		t.check(front.state == Npc.State.STUNNED, "%s: the struck enemy reacts with a brief stagger" % d)
		front.queue_free()
		# behind: untouched
		player.teleport(p, d)
		var back := dummy(p - offsets[d])
		await t._frames(3)
		await swing(player)
		t.check(back.hp == back.max_hp, "%s swing does not hurt a target behind" % d)
		back.queue_free()
		# beyond reach: untouched
		player.teleport(p, d)
		var far := dummy(p + offsets[d] * 3.5)
		await t._frames(3)
		await swing(player)
		t.check(far.hp == far.max_hp, "%s swing does not reach a target far ahead" % d)
		far.queue_free()
		await t._frames(2)
	# one swing damages a target once, even though the strike is active for several frames
	player.teleport(p, "right")
	var once := dummy(p + Vector2(16, 0))
	await t._frames(3)
	await swing(player)
	t.check(once.hp == once.max_hp - 2, "a single swing hits a target once, not once per frame")
	once.queue_free()
	# solid obstacles block the blow
	player.teleport(p, "right")
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2, 40)
	shape.shape = rect
	wall.add_child(shape)
	wall.global_position = p + Vector2(8, -4)
	game.region.entities.add_child(wall)
	var hidden := dummy(p + Vector2(16, 0))
	await t._frames(4)
	await swing(player)
	t.check(hidden.hp == hidden.max_hp, "no damage through a solid obstacle")
	wall.queue_free()
	hidden.queue_free()
	await t._frames(3)
	# a real map wall also blocks (stone wall in the yard)
	var behind_wall := dummy(Vector2(18.5, 10.2) * 32.0)
	player.teleport(Vector2(18.5, 12.2) * 32.0, "up")
	await t._frames(4)
	await swing(player)
	t.check(behind_wall.hp == behind_wall.max_hp, "no damage through the yard's stone wall")
	behind_wall.queue_free()


func test_player_damage() -> void:
	player.teleport(spot(), "right")
	Combat.heal_player()
	GameState.mode = GameState.Mode.EXPLORE
	await t._frames(60)
	var full := Combat.player_hp
	t.check(full == Combat.max_hp(), "full health at the start")
	var dealt := player.take_hit(3, player.global_position + Vector2(40, 0), 90.0)
	t.check(dealt == 3 and Combat.player_hp == full - 3, "a hit costs health (3 points)")
	t.check(player.is_invulnerable(), "taking damage grants a brief invulnerability")
	for i in range(10):
		player.take_hit(3, player.global_position + Vector2(40, 0), 0.0)
	t.check(Combat.player_hp == full - 3, "repeated hits within the invulnerable window do no further damage")
	await t._frames(30)
	t.check(player.is_invulnerable(), "still protected half a second later")
	await t._frames(40)
	t.check(not player.is_invulnerable(), "protection wears off after about a second")
	t.check(player.take_hit(3, player.global_position + Vector2(-40, 0), 0.0) == 3, "the player can be hurt again afterwards")
	# one frame, many sources: only one lands
	await t._frames(70)
	var hp_now := Combat.player_hp
	for i in range(5):
		player.take_hit(2, player.global_position + Vector2(40, 0))
	t.check(Combat.player_hp == hp_now - 2, "several enemies in the same frame still cost a single hit")
	# dodge gives protection and cooldown
	await t._frames(70)
	t.check(player.try_dodge() and player.is_invulnerable(), "a dodge step grants brief protection")
	t.check(not player.try_dodge(), "dodge has a cooldown")
	var before := Combat.player_hp
	player.take_hit(3, player.global_position + Vector2(40, 0))
	t.check(Combat.player_hp == before, "no damage during a dodge")
	await t._frames(70)
	# armor and shield
	GameState.add_item("quilted_vest", 1, true)
	GameState.add_item("felt_cap", 1, true)
	GameState.add_item("wicker_shield", 1, true)
	Equipment.equip("quilted_vest")
	Equipment.equip("felt_cap")
	Combat.heal_player()
	player.teleport(spot(), "right")
	t.check(player.take_hit(4, player.global_position + Vector2(-40, 0)) == 2, "armor lowers a hit from behind (4 - 2 defense)")
	await t._frames(70)
	Equipment.equip("wicker_shield")
	t.check(player.take_hit(4, player.global_position + Vector2(40, 0)) == 1, "a shield lowers a hit from the front further")
	await t._frames(70)
	t.check(player.take_hit(4, player.global_position + Vector2(-40, 0)) == 2, "a shield does nothing against a hit from behind")
	Equipment.unequip("shield")
	Equipment.unequip("helmet")
	Equipment.equip("plain_tunic")
	# defeat and recovery
	await t._frames(70)
	Combat.heal_player()
	var defeated := [0]
	var on_def := func(): defeated[0] += 1
	Combat.player_defeated.connect(on_def)
	player.teleport(spot() + Vector2(64, 0), "right")
	for i in range(6):
		player.take_hit(5, player.global_position + Vector2(40, 0))
		await t._frames(60)
		if Combat.is_player_down():
			break
	Combat.player_defeated.disconnect(on_def)
	t.check(Combat.player_hp == 0 and defeated[0] == 1, "health reaching zero defeats the player exactly once")
	t.check(GameState.mode == GameState.Mode.DEFEAT and player.is_down(), "defeat shows the defeat state")
	t.check(game.hud._defeat.visible, "the defeat screen is displayed")
	t.check(not player.try_attack() and player.take_hit(5, player.global_position) == 0, "a downed player cannot act or be hurt further")
	var overcome := int(Combat.consequences["times_overcome"])
	game.recover_from_defeat()
	await t._frames(3)
	t.check(Combat.player_hp == Combat.max_hp() and GameState.mode == GameState.Mode.EXPLORE and not player.is_down(), "recovery restores full health and control")
	t.check(player.global_position.distance_to(game.region.spawn_position()) < 4.0, "recovery returns the player to the start of the area")
	t.check(not game.hud._defeat.visible, "the defeat screen is dismissed")
	t.check(player.is_invulnerable(), "a moment of protection after getting up")
	t.check(overcome >= 1, "being overcome is recorded for later use")
	await t._frames(100)


# -- behaviour: noncombatants ------------------------------------------------------------------
func test_noncombatant() -> void:
	freeze_all()
	var trav: Npc = npc("yard_traveler")
	var guard: Npc = npc("yard_guard")
	trav.global_position = Vector2(20, 22) * 32.0 / 1.0
	trav.global_position = Vector2(14.5, 18.2) * 32.0
	guard.global_position = Vector2(9.5, 19.0) * 32.0  # out of sight behind scenery: not a witness yet
	guard._home = guard.global_position
	trav.set_physics_process(true)
	player.teleport(trav.global_position + Vector2(-18, 0), "right")
	await t._frames(3)
	t.check(trav.disposition == "noncombatant" and trav.profile_id == "wayfarer", "the traveler uses the wayfarer profile")
	t.check(trav.state == Npc.State.IDLE, "an unprovoked traveler idles")
	var hp := trav.hp
	await swing(player)
	t.check(trav.hp == hp, "the traveler is not injured")
	t.check(trav.state in [Npc.State.FLEE, Npc.State.WARY], "the traveler flees from the sword")
	t.check(trav._refuses_talk(), "and refuses to talk")
	var texts: Array = []
	var on_line := func(_s, text, _n): texts.append(text)
	DialogueRunner.line_shown.connect(on_line)
	trav._on_talk(player)
	DialogueRunner.line_shown.disconnect(on_line)
	t.check(texts.size() == 1 and str(texts[0]).contains("no trouble"), "refusing to talk gives a line, not the normal conversation")
	DialogueRunner.cancel()
	t.check(trav.is_alive() and Combat.actor_status("yard_traveler") != "dead", "the traveler is alive and well")
	# the flight takes them away from the player, then they calm down
	await t._frames(30)
	t.check(trav.global_position.distance_to(player.global_position) > 30.0, "the traveler moves away from the player")
	trav._walk_time = 0.01
	await t._frames(10)
	t.check(trav.state == Npc.State.WARY, "after running they stay wary")
	trav._walk_time = 0.01
	await t._frames(10)
	t.check(trav.state == Npc.State.IDLE, "and eventually calm down")
	# the profile is data: a villager profile can be given to anyone and a hostile one to anyone
	t.check(Combat.profile("villager")["disposition"] == "noncombatant" and Combat.profile("highwayman")["disposition"] == "hostile" and Combat.profile("guard")["disposition"] == "contextual", "three behaviour kinds exist as data")
	t.check(Combat.profile("no_such_profile")["disposition"] == "noncombatant", "unknown profiles fall back to harmless")
	trav.set_physics_process(false)


# -- behaviour: diplomacy ----------------------------------------------------------------------
func test_diplomacy() -> void:
	freeze_all()
	Combat.reset()
	var toll: Npc = npc("yard_toll_taker")
	t.check(toll.state == Npc.State.IDLE and Combat.outcome_of("yard_toll") == "", "the toll-taker starts unresolved")
	toll.set_physics_process(true)
	player.teleport(toll.global_position + Vector2(-60, 0), "right")
	await t._frames(10)
	t.check(toll.state == Npc.State.CHALLENGE, "a hostile who warns first challenges instead of striking")
	t.check(toll._can_talk(), "a challenging opponent can be talked to")
	# bluffing fails: the dialogue can lead to a fight
	var hp := Combat.player_hp
	await t.play("yard_toll_taker", [1])
	t.check(toll.state == Npc.State.CHASE and Combat.outcome_of("yard_toll") == "", "a failed bluff turns the toll-taker hostile without resolving anything")
	# reset to a fresh challenge and talk honestly
	toll.reset_after_defeat()
	toll._lockout = 0.0
	player.teleport(toll.global_position + Vector2(-60, 0), "right")
	await t._frames(10)
	t.check(toll.state == Npc.State.CHALLENGE, "challenged again")
	await t.play("yard_toll_taker", [0])  # "honest" is the first visible choice without a coin
	t.check(toll.state == Npc.State.STANDDOWN, "an honest answer makes the toll-taker stand down")
	t.check(Combat.outcome_of("yard_toll") == "diplomacy", "diplomacy is registered as a valid outcome")
	t.check(GameState.check({"encounter": {"id": "yard_toll", "outcome": "diplomacy"}}) and GameState.check({"encounter": {"id": "yard_toll"}}), "the encounter condition reads the outcome")
	t.check(not GameState.check({"encounter": {"id": "yard_toll", "outcome": "avoidance"}}), "and distinguishes outcomes")
	await t._frames(60)
	t.check(toll.state == Npc.State.STANDDOWN and Combat.player_hp == hp, "a stood-down opponent does not attack")
	t.check(Combat.actor_status("yard_toll_taker") == "stood_down", "the new status is recorded")
	t.check(not Combat.resolve_encounter("yard_toll", "avoidance") and Combat.outcome_of("yard_toll") == "diplomacy", "the first resolution stands")
	t.check(not Combat.resolve_encounter("yard_toll", "not_an_outcome"), "an undefined outcome is rejected")
	t.check(not Combat.resolve_encounter("no_such_encounter", "diplomacy"), "an undefined encounter is rejected")
	# paying a coin is another way to talk it through
	Combat.outcomes.erase("yard_toll")
	toll.provoked_by = ""
	toll._set_state(Npc.State.IDLE)
	GameState.add_item("lepton", 1, true)
	toll._lockout = 0.0
	player.teleport(toll.global_position + Vector2(-60, 0), "right")
	await t._frames(10)
	var coins := GameState.item_count("lepton")
	await t.play("yard_toll_taker", [0])  # first visible choice is now "Pay him a lepton"
	t.check(GameState.item_count("lepton") == coins - 1 and Combat.outcome_of("yard_toll") == "diplomacy", "paying the toll is also diplomacy and costs a coin")
	toll.set_physics_process(false)


# -- behaviour: avoidance ----------------------------------------------------------------------
func test_avoidance() -> void:
	freeze_all()
	Combat.reset()
	var hw: Npc = npc("yard_highwayman")
	hw.global_position = Vector2(24.5, 12.0) * 32.0
	hw._home = hw.global_position
	hw._set_state(Npc.State.IDLE)
	hw.hp = hw.max_hp
	hw.set_physics_process(true)
	player.teleport(hw.global_position + Vector2(-90, 0), "right")
	await t._frames(6)
	t.check(hw.is_fighting(), "the highwayman gives chase on sight")
	t.check(not hw._can_talk(), "a pursuer cannot be talked to")
	# run away far beyond the pursuit range
	player.teleport(Vector2(3.5, 3.5) * 32.0, "down")
	await t._frames(20)
	t.check(not hw.is_fighting(), "he gives up once the player is far away")
	t.check(Combat.outcome_of("yard_highwayman") == "avoidance", "avoidance is registered as a valid outcome")
	t.check(Combat.player_hp == Combat.max_hp(), "the player took no damage getting away")
	hw.set_physics_process(false)
	# breaking line of sight also works
	Combat.reset()
	hw.global_position = Vector2(18.5, 9.0) * 32.0
	hw._home = hw.global_position
	hw._lockout = 0.0
	hw._set_state(Npc.State.IDLE)
	player.teleport(Vector2(18.5, 7.0) * 32.0, "down")  # north of the wall row y=11
	hw.set_physics_process(true)
	await t._frames(4)
	t.check(hw.is_fighting(), "chase begins in the open")
	player.teleport(Vector2(18.5, 13.5) * 32.0, "down")  # now behind the wall
	await t._frames(240)
	t.check(not hw.is_fighting(), "losing sight of the player ends the chase")
	t.check(Combat.outcome_of("yard_highwayman") == "avoidance", "avoidance by breaking line of sight is registered")
	hw.set_physics_process(false)


# -- behaviour: combat -------------------------------------------------------------------------
func hit_until(n: Npc, times: int) -> void:
	player.teleport(n.global_position + Vector2(-16, 0), "right")
	player.invulnerable_time = 999.0
	for i in range(times):
		n._invuln = 0.0
		n.receive_strike(player, 2, "right")
		await t._frames(24)


func test_combat_outcomes() -> void:
	freeze_all()
	Combat.reset()
	# the highwayman fights to the end: lethal outcome
	var hw: Npc = npc("yard_highwayman")
	hw.hp = hw.max_hp
	hw._low_hp_done = false
	hw._set_state(Npc.State.IDLE)
	hw.set_physics_process(true)
	player.teleport(Vector2(30.5, 3.5) * 32.0, "down")
	hw.global_position = Vector2(24.5, 12.0) * 32.0
	await hit_until(hw, 3)
	t.check(hw.hp == 0 or not is_instance_valid(hw), "three sword blows defeat the highwayman")
	t.check(Combat.outcome_of("yard_highwayman") == "combat_victory", "combat victory is registered")
	t.check(Combat.actor_status("yard_highwayman") == "dead", "his defeat is remembered")
	await t._frames(60)
	t.check(not is_instance_valid(hw) or hw.is_queued_for_deletion(), "the defeated opponent leaves the field")
	# the cutthroat runs when hurt
	var ct: Npc = npc("yard_cutthroat")
	ct.set_physics_process(true)
	player.teleport(Vector2(30.5, 3.5) * 32.0, "down")
	await hit_until(ct, 2)
	t.check(Combat.outcome_of("yard_cutthroat") == "combat_routed", "an enemy that flees registers as driven off")
	t.check(ct.state in [Npc.State.FLEE, Npc.State.ROUTED], "the cutthroat runs away")
	ct._walk_time = 0.01
	await t._frames(10)
	t.check(ct.state == Npc.State.ROUTED and Combat.actor_status("yard_cutthroat") == "routed", "then keeps away for good")
	t.check(ct.hp > 0, "the one who fled is alive")
	# the toll-taker yields when beaten
	var toll: Npc = npc("yard_toll_taker")
	Combat.outcomes.erase("yard_toll")
	toll.hp = toll.max_hp
	toll._low_hp_done = false
	toll._set_state(Npc.State.IDLE)
	toll.set_physics_process(true)
	await hit_until(toll, 2)
	t.check(toll.state == Npc.State.SURRENDER, "the toll-taker surrenders when hurt")
	t.check(Combat.outcome_of("yard_toll") == "combat_surrender", "surrender is registered")
	var hp := toll.hp
	toll._invuln = 0.0
	toll.receive_strike(player, 2, "right")
	t.check(toll.hp == hp and toll.state == Npc.State.SURRENDER, "a surrendered opponent cannot be struck")
	t.check(toll._can_talk() and not toll._refuses_talk(), "a surrendered opponent can be spoken to")
	await t.play("yard_toll_taker", [0])
	t.check(toll.state == Npc.State.STANDDOWN and Combat.outcome_of("yard_toll") == "combat_surrender", "showing mercy stands them down without changing the recorded outcome")
	var cons := Combat.consequences
	t.check(cons["defeated"] == 1 and cons["routed"] == 1 and cons["yielded"] == 1, "consequence counters track each kind of ending")
	t.check(Combat.ledger_lines().size() == Combat.encounters.size(), "the ledger lists every encounter")
	# all five outcomes are valid for every yard encounter, none required
	for eid in Combat.encounters:
		for o in Combat.encounters[eid]["valid"]:
			t.check(Combat.is_valid_outcome(eid, o), "%s accepts %s" % [eid, o])
	# the enemy really hurts: a fresh cutthroat strikes the player
	var foe := dummy(Vector2(22.5, 15.5) * 32.0, "highwayman")
	foe.encounter_id = ""
	foe.set_physics_process(true)
	Combat.heal_player()
	player.teleport(Vector2(21.0, 15.5) * 32.0, "right")
	player.invulnerable_time = 0.0
	await t._frames(180)
	t.check(Combat.player_hp < Combat.max_hp(), "an enemy that reaches the player can hurt them")
	t.check((Combat.max_hp() - Combat.player_hp) % 3 == 0 or Combat.player_hp == 0, "damage comes in whole blows (3 each), never per frame")
	foe.queue_free()


# -- behaviour: contextual guard ---------------------------------------------------------------
func test_guard() -> void:
	freeze_all()
	Combat.reset()
	var guard: Npc = npc("yard_guard")
	var trav: Npc = npc("yard_traveler")
	guard.global_position = Vector2(14.5, 14.5) * 32.0
	guard._home = guard.global_position
	guard.hp = guard.max_hp
	guard._set_state(Npc.State.IDLE)
	trav.global_position = Vector2(16.5, 14.5) * 32.0
	trav._set_state(Npc.State.IDLE)
	guard.set_physics_process(true)
	trav.set_physics_process(true)
	player.teleport(Vector2(15.5, 15.6) * 32.0, "up")
	await t._frames(90)
	t.check(guard.state == Npc.State.IDLE and guard.disposition == "contextual", "a guard does not attack a peaceful player standing next to him")
	# striking a bystander in the guard's sight provokes him
	player.teleport(trav.global_position + Vector2(-18, 0), "right")
	await t._frames(3)
	await swing(player)
	t.check(guard.state == Npc.State.CHALLENGE, "witnessing an assault makes the guard warn the player")
	t.check(Combat.actor_status("yard_guard") == "challenge", "his state is queryable by dialogue")
	await t.play("yard_guard", [0])  # apologise
	t.check(guard.state == Npc.State.STANDDOWN and Combat.outcome_of("yard_guard") == "diplomacy", "apologising stands the guard down (diplomacy)")
	# attacking the guard himself is different: he fights back
	guard._set_state(Npc.State.IDLE)
	guard.set_physics_process(true)
	player.teleport(guard.global_position + Vector2(-16, 0), "right")
	await t._frames(3)
	guard._invuln = 0.0
	guard.receive_strike(player, 2, "right")
	await t._frames(40)
	t.check(guard.is_fighting(), "a guard who is attacked fights back")
	# fleeing out of sight ends it
	Combat.outcomes.erase("yard_guard")
	player.teleport(Vector2(3.5, 3.5) * 32.0, "down")
	await t._frames(240)
	t.check(not guard.is_fighting(), "and gives up when the player is gone")
	t.check(Combat.outcome_of("yard_guard") == "avoidance", "that registers as avoidance")
	# the rule is by behaviour, not identity: the same profile on another character behaves the same
	var other := dummy(Vector2(26.5, 4.5) * 32.0, "guard")
	t.check(other.disposition == "contextual", "any character can be given the guard profile")
	other.queue_free()
	guard.set_physics_process(false)
	trav.set_physics_process(false)


func test_interruption() -> void:
	freeze_all()
	var hw = npc("yard_highwayman")
	if not is_instance_valid(hw) or hw.state == Npc.State.DEAD:
		hw = dummy(Vector2(24.5, 12.0) * 32.0, "highwayman")
	hw.set_physics_process(true)
	hw._set_state(Npc.State.CHASE)
	hw.global_position = Vector2(24.5, 12.0) * 32.0
	player.teleport(Vector2(21.0, 12.0) * 32.0, "right")
	player.invulnerable_time = 0.0
	Combat.heal_player()
	GameState.mode = GameState.Mode.DIALOGUE
	var p0: Vector2 = hw.global_position
	var hp0 := Combat.player_hp
	await t._frames(90)
	t.check(hw.global_position.distance_to(p0) < 0.5 and Combat.player_hp == hp0, "enemies hold still and deal no damage during dialogue or menus")
	GameState.mode = GameState.Mode.EXPLORE
	hw.set_physics_process(false)


# -- save / load of combat state ---------------------------------------------------------------
func test_save_load() -> void:
	t._section = "m2a-save"
	freeze_all()
	Combat.reset()
	Combat.resolve_encounter("yard_toll", "diplomacy")
	Combat.set_actor("yard_toll_taker", "stood_down", 6)
	Combat.set_actor("yard_cutthroat", "routed", 2)
	Combat.set_actor("yard_highwayman", "dead", 0)
	Combat.player_hp = 7
	GameState.add_item("wicker_shield", 1, true)
	Equipment.equip("wicker_shield")
	Equipment.equip("ezra_sword")
	player.teleport(spot(), "left")
	game._save_to(1)
	var snapshot := JSON.stringify(t._norm({"c": Combat.serialize(), "e": Equipment.serialize()}))
	close_game()
	await t.get_tree().process_frame
	GameState.new_game()
	game = await t._spawn_game({"mode": "load", "slot": 1})
	player = game.player
	t.check(JSON.stringify(t._norm({"c": Combat.serialize(), "e": Equipment.serialize()})) == snapshot, "combat and equipment state identical after reload")
	t.check(Combat.player_hp == 7, "health restored after reload")
	t.check(Equipment.equipped("sword") == "ezra_sword" and Equipment.equipped("shield") == "wicker_shield", "equipment restored after reload")
	t.check(Combat.outcome_of("yard_toll") == "diplomacy", "encounter outcomes restored")
	t.check(not game.region.npcs.has("yard_highwayman"), "a defeated enemy does not come back after reload")
	t.check(npc("yard_toll_taker").state == Npc.State.STANDDOWN, "a stood-down opponent is still calm after reload")
	t.check(npc("yard_cutthroat").state == Npc.State.ROUTED, "a routed opponent is still routed after reload")
	t.check(game.hud._hearts.get_child_count() == 6, "six hearts are drawn")
	t.check(player.global_position.distance_to(spot()) < 0.1 and player.facing == "left", "position restored in the training yard")
	t.check(SaveManager.slot_info(1)["place"] == "Training Yard (dev)", "the save slot names the place")
	# a very low save is never loaded into a defeat screen
	Combat.player_hp = 0
	game._save_to(2)
	GameState.new_game()
	SaveManager.load_slot(2)
	t.check(Combat.player_hp == Combat.max_hp(), "a save taken at zero health loads with full health")
	# hearts for half points
	game.hud._on_hp_changed(5, 12)
	t.check(game.hud._hearts.get_child_count() == 6, "hearts keep a constant count")
