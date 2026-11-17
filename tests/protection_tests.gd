extends RefCounted
## Canonical-character protection checks (GC-A.7 to GC-A.10): registry, combat gating inside
## protected areas, immunity, timeline-only outcomes and persistence. Driven by test_runner.gd.

const SLOT := 3

var t: Node
var game: Node
var player: Player


func run(runner: Node) -> void:
	t = runner
	t._section = "protection-data"
	test_registry_validation()
	test_registry_lookup()
	test_no_names_in_controllers()
	await open_yard()
	t._section = "protection-gating"
	await test_no_attack_in_area()
	await test_buffer_canceled_on_entry()
	await test_no_hitbox_and_hud()
	await test_leaving_restores()
	await test_unprotected_unchanged()
	t._section = "protection-immunity"
	await test_immunity_every_path()
	test_event_not_interruptible()
	test_timeline_only_outcomes()
	t._section = "protection-save"
	test_save_roundtrip()
	close_game()
	CanonicalProtection.reset()


# -- helpers -----------------------------------------------------------------------------------
func open_yard() -> void:
	game = await t._spawn_game({"mode": "training"})
	player = game.player
	GameState.mode = GameState.Mode.EXPLORE
	for n in game.region.npcs.values():
		if is_instance_valid(n):
			n.set_physics_process(false)


func close_game() -> void:
	if game != null and is_instance_valid(game):
		game.queue_free()
		await t.get_tree().process_frame
	game = null


func clean() -> void:
	CanonicalProtection.reset()
	player.attack_cooldown = 0.0
	player._buffered = 0.0
	player._end_swing()
	player.swing_phase = -1


func dummy(pos: Vector2, protect: bool = false) -> Npc:
	var n := Npc.new()
	n.setup({"id": "dummy_prot_%d" % randi(), "profile": "cutthroat", "sprite": "cutthroat", "dialogue": "", "tile": [pos.x / 32.0, pos.y / 32.0], "wander": 0})
	game.region.entities.add_child(n)
	n.set_physics_process(false)
	if protect:
		CanonicalProtection.registry[n.npc_id] = {"display_name": "Test", "canonical_character": true,
			"combat_protected": true, "protected_event": "", "combat_restriction_radius": 80}
	return n


# -- GC-A.7: data model ------------------------------------------------------------------------
func test_registry_validation() -> void:
	var ok := {"display_name": "X", "canonical_character": true, "combat_protected": true, "protected_event": "", "combat_restriction_radius": 64}
	t.check(CanonicalProtection.validate_entry(ok) == "", "a complete entry is accepted")
	var extra := ok.duplicate()
	extra["faction"] = "romans"
	t.check(CanonicalProtection.validate_entry(extra) != "", "unknown fields are rejected")
	var no_radius := ok.duplicate()
	no_radius.erase("combat_radius")
	no_radius.erase("combat_restriction_radius")
	t.check(CanonicalProtection.validate_entry(no_radius) != "", "a missing radius is rejected")
	var neg := ok.duplicate()
	neg["combat_restriction_radius"] = -1
	t.check(CanonicalProtection.validate_entry(neg) != "", "a negative radius is rejected")
	var not_canon := ok.duplicate()
	not_canon["canonical_character"] = false
	t.check(CanonicalProtection.validate_entry(not_canon) != "", "an entry must be classified canonical_character")
	var reg := CanonicalProtection.load_registry({"good": ok, "bad": extra})
	t.check(reg.has("good") and not reg.has("bad"), "loading keeps valid entries and drops invalid ones")


func test_registry_lookup() -> void:
	for id in ["jesus", "simon_peter", "judas_iscariot", "paul", "john_the_baptist", "mary_mother_of_jesus"]:
		t.check(CanonicalProtection.is_canonical(id) and CanonicalProtection.is_protected(id), "%s is in the registry and protected" % id)
	var twelve := ["simon_peter", "andrew", "james_zebedee", "john_zebedee", "philip", "bartholomew", "thomas", "matthew", "james_alphaeus", "thaddaeus", "simon_zealot", "judas_iscariot"]
	var n := 0
	for id in twelve:
		n += 1 if CanonicalProtection.is_protected(id) else 0
	t.check(n == 12, "all twelve apostles are protected")
	t.check(CanonicalProtection.radius_of("jesus") > 0.0 and CanonicalProtection.radius_of("no_one") == 0.0, "radius lookup works and unknown ids have none")
	t.check(CanonicalProtection.protected_event_of("john_the_baptist") == "john_preaching", "a character can be tied to a protected event")
	t.check(not CanonicalProtection.is_canonical("yard_traveler") and Combat.has_profile("villager"), "ordinary characters are not canonical")
	# classification is independent of combat profiles: any profile change leaves protection intact
	var before := CanonicalProtection.is_protected("jesus")
	Combat.profiles["cutthroat_clone"] = Combat.profiles["cutthroat"].duplicate(true)
	t.check(before and CanonicalProtection.is_protected("jesus") and Combat.profile("cutthroat_clone")["disposition"] == "hostile", "a combat profile cannot unprotect a canonical character")
	Combat.profiles.erase("cutthroat_clone")


func test_no_names_in_controllers() -> void:
	var files := ["res://scripts/autoload/combat.gd", "res://scripts/entities/player.gd", "res://scripts/entities/npc.gd", "res://scripts/combat/sword_strike.gd"]
	var leaked := ""
	for f in files:
		var text := FileAccess.get_file_as_string(f).to_lower()
		for id in CanonicalProtection.registry:
			var disp: String = str(CanonicalProtection.registry[id]["display_name"]).to_lower()
			if text.contains('"%s"' % id) or text.contains(disp):
				leaked = "%s mentions %s" % [f, id]
	t.check(leaked == "", "no canonical character name or id appears in the combat controllers (%s)" % leaked)


# -- GC-A.8: gating ----------------------------------------------------------------------------
func test_no_attack_in_area() -> void:
	clean()
	GameState.mode = GameState.Mode.EXPLORE
	var swings := player.swings_started
	t.check(player.try_attack(), "baseline: the sword swings with no protected area")
	await t._frames(32)
	player.attack_cooldown = 0.0
	CanonicalProtection.set_presence("jesus", player.global_position + Vector2(40, 0))
	await t._frames(2)
	swings = player.swings_started
	t.check(not player.try_attack(), "an attack cannot start inside a protected area")
	t.check(player.swing_phase == -1 and player.swings_started == swings, "no swing or attack animation begins")
	t.check(not player.try_dodge(), "no player-initiated combat action starts either")
	t.check(Equipment.has_sword() and Equipment.weapon().size() > 0, "the sword stays equipped, nothing confiscated")
	# movement and observation stay available
	var p0 := player.global_position
	player.velocity = Vector2(60, 0)
	player.move_and_slide()
	t.check(player.global_position != p0, "the protagonist can still move")
	clean()


func test_buffer_canceled_on_entry() -> void:
	clean()
	player._buffered = 0.1
	player.attack_cooldown = 0.5
	CanonicalProtection.set_presence("jesus", player.global_position)
	await t._frames(2)
	t.check(player._buffered == 0.0, "a buffered attack is canceled on entering the area")
	await t._frames(40)
	t.check(player.swing_phase == -1, "and it never fires afterwards")
	# a swing already underway is cut off too
	clean()
	player.try_attack()
	t.check(player.swing_phase >= 0, "a swing is underway outside the area")
	CanonicalProtection.set_presence("jesus", player.global_position)
	await t._frames(2)
	t.check(player.swing_phase == -1, "entering the area ends the swing")
	clean()


func test_no_hitbox_and_hud() -> void:
	clean()
	var target := dummy(player.global_position + Vector2(20, 0))
	player.facing = "right"
	var hp := target.hp
	CanonicalProtection.set_presence("jesus", player.global_position + Vector2(100, 0))
	await t._frames(2)
	t.check(game.hud._combat_note.visible and game.hud._combat_note.text == "Combat unavailable", "the HUD shows 'Combat unavailable' while restricted")
	var lower: String = game.hud._combat_note.text.to_lower()
	t.check(not lower.contains("scripture") and not lower.contains("forbid") and not lower.contains("divine") and not lower.contains("miracle"), "the wording claims no supernatural rule and does not cite Scripture")
	player.swing_phase = 1  # even a forced active swing creates no hit
	player._strike()
	t.check(player.last_swing_hits.is_empty() and target.hp == hp, "no hitbox is generated and no damage is applied while restricted")
	t.check(player.swing_phase == -1, "the forced swing is ended")
	target.queue_free()
	clean()
	await t._frames(2)
	t.check(not game.hud._combat_note.visible, "the HUD text disappears when unrestricted")


func test_leaving_restores() -> void:
	clean()
	CanonicalProtection.set_presence("jesus", player.global_position)
	await t._frames(2)
	t.check(not player.try_attack(), "restricted inside")
	CanonicalProtection.set_presence("jesus", player.global_position + Vector2(CanonicalProtection.radius_of("jesus") + 40.0, 0))
	await t._frames(2)
	t.check(not CanonicalProtection.restricted, "outside the radius the restriction lifts")
	t.check(player.try_attack(), "combat is available again after leaving")
	await t._frames(32)
	clean()


func test_unprotected_unchanged() -> void:
	clean()
	var foe := dummy(player.global_position + Vector2(20, 0))
	player.facing = "right"
	var hp := foe.hp
	CanonicalProtection.set_presence("jesus", player.global_position + Vector2(5000, 0))
	t.check(player.try_attack(), "a distant protected character does not restrict the protagonist")
	await t._frames(32)
	t.check(foe.hp < hp or foe.state == Npc.State.DEAD, "an ordinary opponent outside any area is hurt as before")
	foe.queue_free()
	clean()


# -- GC-A.9: immunity, events, outcomes --------------------------------------------------------
func test_immunity_every_path() -> void:
	clean()
	var vip := dummy(player.global_position + Vector2(20, 0), true)
	var hp := vip.hp
	var far := player.global_position + Vector2(3000, 0)
	var attacker := dummy(far)
	# 1 the player's real swing (the protected character's own area is not registered in presence,
	# so the protagonist is free to try)
	player.facing = "right"
	player.try_attack()
	await t._frames(32)
	t.check(vip.hp == hp and vip.state != Npc.State.DEAD, "a real sword swing does no damage to a protected character")
	# 2 direct strike call
	vip.receive_strike(player, 99, "right")
	t.check(vip.hp == hp, "a direct strike does nothing")
	# 3 strike by another (fictional-combat) actor
	vip._invuln = 0.0
	vip.receive_strike(attacker, 99, "right")
	t.check(vip.hp == hp and vip.state != Npc.State.DEAD, "another combatant cannot damage them either")
	# 4 recorded status, assault report, provocation
	Combat.set_actor(vip.npc_id, "dead", 0)
	t.check(Combat.actor_status(vip.npc_id) != "dead", "ordinary combat cannot record a lasting state for them")
	var struck: int = Combat.consequences["noncombatants_struck"]
	Combat.report_assault(vip.npc_id, vip.global_position)
	t.check(Combat.consequences["noncombatants_struck"] == struck, "an assault on them is not even recorded")
	Combat.command_actor(vip.npc_id, "provoke")
	t.check(vip.state != Npc.State.CHASE, "they cannot be provoked into a fight")
	# 5 damage while out of sight or inside dialogue
	vip._talking = true
	vip.receive_strike(player, 99, "right")
	vip._talking = false
	t.check(vip.hp == hp, "damage in dialogue is ignored")
	t.check(not CanonicalProtection.can_be_harmed(vip.npc_id) and CanonicalProtection.can_be_harmed("someone_else"), "the shared gate agrees")
	vip.queue_free()
	attacker.queue_free()
	clean()


func test_event_not_interruptible() -> void:
	CanonicalProtection.reset()
	CanonicalProtection.begin_event("john_preaching")
	CanonicalProtection.set_presence("john_the_baptist", Vector2(100, 100))
	var before := Combat.actors.duplicate(true)
	Combat.swung(Vector2(100, 120))
	Combat.report_assault("john_the_baptist", Vector2(100, 100))
	Combat.command_actor("john_the_baptist", "provoke")
	Combat.set_actor("john_the_baptist", "dead", 0)
	Combat.set_actor("john_the_baptist", "fled", 3)
	t.check(CanonicalProtection.is_event_active("john_preaching") and not CanonicalProtection.combat_can_disrupt("john_preaching"), "combat cannot disrupt an active protected event")
	t.check(_same(before, Combat.actors), "combat commands leave the participants' recorded state untouched")
	t.check(CanonicalProtection.restricted_at(Vector2(100, 120)) and not CanonicalProtection.restricted_at(Vector2(900, 900)), "the event area restricts combat only nearby")
	CanonicalProtection.set_area("scripted_scene", Vector2(500, 500), 60.0, "private_event")
	t.check(CanonicalProtection.restricted_at(Vector2(520, 500)), "a scripted area restricts combat without any character present")
	CanonicalProtection.reset()


func test_timeline_only_outcomes() -> void:
	CanonicalProtection.reset()
	var accepted := {}
	for src in ["player", "combat", "npc", "", "Timeline", "world_sim"]:
		accepted[src] = CanonicalProtection.apply_outcome("jesus", "death", src)
	var any := false
	for k in accepted:
		any = any or accepted[k]
	t.check(not any and CanonicalProtection.outcome_of("jesus") == "", "a non-timeline source is refused")
	t.check(not CanonicalProtection.apply_outcome("jesus", "vanish", "timeline"), "an unknown outcome is rejected")
	t.check(not CanonicalProtection.apply_outcome("nobody", "death", "timeline"), "an unknown character is rejected")
	# ordinary combat can neither cause nor prevent it
	CanonicalProtection.set_presence("andrew", Vector2(10, 10))
	Combat.set_actor("andrew", "dead", 0)
	t.check(CanonicalProtection.outcome_of("andrew") == "", "combat cannot cause an outcome")
	t.check(CanonicalProtection.apply_outcome("andrew", "arrest", "timeline"), "the timeline can apply an outcome regardless of combat")
	CanonicalProtection.set_presence("john_zebedee", Vector2(10, 10))
	t.check(CanonicalProtection.apply_outcome("john_zebedee", "death", "timeline") and Combat.actor_status("john_zebedee") == "dead", "a timeline death is recorded")
	t.check(CanonicalProtection.outcome_of("andrew") == "arrest", "and persists as recorded")
	CanonicalProtection.reset()


# -- GC-A.10: persistence ----------------------------------------------------------------------
func test_save_roundtrip() -> void:
	t._fresh()
	CanonicalProtection.begin_event("john_preaching")
	CanonicalProtection.set_presence("jesus", Vector2(64, 96))
	CanonicalProtection.set_area("scene", Vector2(300, 300), 50.0, "private_event")
	CanonicalProtection.apply_outcome("judas_iscariot", "injury", "timeline")
	CanonicalProtection.update_restriction(Vector2(64, 100))
	var before := CanonicalProtection.serialize()
	t.check(SaveManager.save_slot(SLOT), "a save with protection state succeeds")
	t._fresh()
	t.check(CanonicalProtection.serialize()["events"].is_empty() and not CanonicalProtection.restricted, "new game starts with no protection state")
	t.check(SaveManager.load_slot(SLOT), "load succeeds")
	t.check(_same(CanonicalProtection.serialize(), before), "active restriction, event, areas and applied outcomes round-trip")
	t.check(CanonicalProtection.restricted and CanonicalProtection.is_event_active("john_preaching") and CanonicalProtection.outcome_of("judas_iscariot") == "injury", "the restored state behaves as saved")
	# an older save has no protection block: defaults apply and everything else loads
	var data := SaveManager.read_slot(SLOT)
	data.erase("protection")
	var f := FileAccess.open(SaveManager.slot_path(SLOT), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	CanonicalProtection.begin_event("stale")
	t.check(SaveManager.load_slot(SLOT), "a save without the protection block loads")
	t.check(CanonicalProtection.serialize()["events"].is_empty() and CanonicalProtection.applied.is_empty() and not CanonicalProtection.restricted, "and the protection state defaults")
	t.check(SaveManager.VERSION == 3 and int(data.get("version", 0)) == 3, "the save version is unchanged")
	SaveManager.delete_slot(SLOT)


func _same(a: Variant, b: Variant) -> bool:
	return JSON.stringify(a, "", true) == JSON.stringify(b, "", true)
