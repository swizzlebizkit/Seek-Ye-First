extends Node2D
## The playable scene: builds the region, spawns the player, camera and HUD, and routes
## top-level input (journal, pause, quick save/load).

const SAVE_QUICK_SLOT := 1

var region: Region
var player: Player
var hud: Hud


func _ready() -> void:
	var request := GameState.start_request
	var is_new := true
	if request.get("mode", "new") == "resume":
		is_new = false  # a region change: every autoload already holds the game
	elif request.get("mode", "new") == "load":
		if SaveManager.load_slot(int(request["slot"])):
			is_new = false
		else:
			push_warning("Could not load slot %s; starting a new game" % request.get("slot"))
	if is_new:
		GameState.new_game()
		if request.get("mode", "new") == "training":
			_set_up_training_yard()

	DevHooks.before_build()
	WorldSim.clock_multiplier = float(World.travel_rules.get("regional_clock_multiplier", 4.0)) if World.region_meta(GameState.region_id).get("kind", "") == "regional" else 1.0
	region = Region.new()
	region.name = "Region"
	add_child(region)
	region.load_region(GameState.region_id)

	player = Player.new()
	player.name = "Player"
	region.entities.add_child(player)
	if GameState.has_saved_position and region.is_walkable_px(GameState.player_pos):
		player.teleport(GameState.player_pos, GameState.player_facing)
	elif region.has_entry(World.entry_id):
		player.teleport(region.entry_position(World.entry_id), region.entry_facing(World.entry_id))
	else:
		player.teleport(region.spawn_position(), "down")  # new game, or a saved spot that is no longer valid

	var camera := Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.offset = Vector2(0, -16)
	var bounds := region.size_px()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(bounds.x)
	camera.limit_bottom = int(bounds.y)
	player.add_child(camera)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.bind(player)
	hud.save_requested.connect(_save_to)
	hud.load_requested.connect(_load_from)
	hud.quit_requested.connect(_quit_to_menu)
	Combat.player_defeated.connect(_on_player_defeated)
	World.transition_requested.connect(_on_transition)
	hud.defeat_continue.connect(recover_from_defeat)

	World.note_player(GameState.region_id, player.global_position / 32.0)
	GameState.mode = GameState.Mode.EXPLORE
	if is_new and request.get("mode", "new") != "training" and Travel.notice == "":
		DialogueRunner.start("narration_intro")
	_show_travel_notice()
	DevHooks.apply(self)


## Tells the player why they are here when a journey has just put them in a place.
func _show_travel_notice() -> void:
	match Travel.notice:
		"sabbath":
			DialogueRunner.start_text(["The sun has gone down, and the Sabbath has begun.",
				"No one sets out on the road tonight. Strategic overland travel has paused until the Sabbath ends at sunset tomorrow. You may still walk about the country, look around, and speak with people."])
		"stop":
			hud.show_toast("You make camp on the road.")
		"arrived":
			hud.show_toast("You arrive at %s." % World.location_name(Travel.last_arrival))
	Travel.notice = ""


## Leaving through an exit (or stopping on a journey) rebuilds the scene around the new region.
func _on_transition(_region: String, _entry: String) -> void:
	if get_tree().current_scene != self:
		return  # not the live game (e.g. under test)
	GameState.start_request = {"mode": "resume"}
	GameState.mode = GameState.Mode.EXPLORE
	get_tree().reload_current_scene()


var _sight_tile := Vector2i(-1, -1)
var _crossing := false


func _exit_tree() -> void:
	WorldSim.clock_multiplier = 1.0


## Walking off the edge of a map continues into whatever lies beyond it, at the same point of ground.
func _physics_process(_delta: float) -> void:
	if player == null or region == null or _crossing or GameState.mode != GameState.Mode.EXPLORE:
		return
	var cross := World.edge_crossing(GameState.region_id, player.global_position)
	if cross.is_empty():
		return
	if cross.get("blocked", false):
		var limit := region.size_px() - Vector2(8, 8)
		player.global_position = player.global_position.clamp(Vector2(8, 8), limit)
		return
	_crossing = true
	GameState.player_pos = cross["pos"]
	World.go_position(cross["region"], cross["pos"], player.facing)


func _process(_delta: float) -> void:
	if player == null or region == null or GameState.mode == GameState.Mode.MENU:
		return
	World.player_px = player.global_position
	var t := Vector2i(floori(player.global_position.x / 32.0), floori(player.global_position.y / 32.0))
	if t != _sight_tile:
		_sight_tile = t
		World.note_player(GameState.region_id, Vector2(t))


func _unhandled_input(event: InputEvent) -> void:
	var exploring := GameState.mode == GameState.Mode.EXPLORE
	if event.is_action_pressed("journal") and exploring:
		get_viewport().set_input_as_handled()
		hud.journal_view.open()
	elif event.is_action_pressed("equipment") and exploring:
		get_viewport().set_input_as_handled()
		hud.equipment_view.open()
	elif event.is_action_pressed("pause") and exploring:
		get_viewport().set_input_as_handled()
		hud.pause_menu.open()
	elif event.is_action_pressed("quick_save") and exploring:
		_save_to(SAVE_QUICK_SLOT)
	elif event.is_action_pressed("quick_load") and exploring:
		if SaveManager.has_save(SAVE_QUICK_SLOT):
			_load_from(SAVE_QUICK_SLOT)
		else:
			hud.show_toast("No quick save yet (F5 saves).")


## Dev-only sandbox: a fresh protagonist who already carries Ezra's Sword, in the training yard.
func _set_up_training_yard() -> void:
	GameState.region_id = "training_yard"
	GameState.set_flag("training_yard")
	GameState.set_flag("heard_rumor")
	GameState.add_item("ezra_sword", 1, true)
	Equipment.equip("ezra_sword")


func _on_player_defeated() -> void:
	player.set_down(true)
	GameState.mode = GameState.Mode.DEFEAT
	hud.show_defeat()


## There is no game-over: the protagonist comes to, whole again, back at the start of the area,
## and anyone still fighting stands down at their post.
func recover_from_defeat() -> void:
	Combat.heal_player()
	player.set_down(false)
	player.teleport(region.spawn_position(), "down")
	for npc in region.npcs.values():
		if is_instance_valid(npc):
			npc.reset_after_defeat()
	GameState.mode = GameState.Mode.EXPLORE
	hud.hide_defeat()


func _save_to(slot: int) -> void:
	GameState.player_pos = player.global_position
	GameState.player_facing = player.facing
	if SaveManager.save_slot(slot):
		hud.show_toast("Game saved (slot %d)" % slot)
	else:
		hud.show_toast("Save failed. See the log for details.")


func _load_from(slot: int) -> void:
	GameState.start_request = {"mode": "load", "slot": slot}
	GameState.mode = GameState.Mode.EXPLORE
	get_tree().reload_current_scene()


func _quit_to_menu() -> void:
	GameState.mode = GameState.Mode.MENU
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
