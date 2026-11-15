class_name DevHooks
extends RefCounted
## Command-line helpers for automated runs and screenshots. Everything is opt-in via user args:
##   godot --path . -- --autostart=new --at=7,9 --flags=heard_rumor --journal=rumor_yosef --shot=out.png
## Nothing here runs during normal play (no args -> no-ops).

static func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


static func maybe_autostart(menu: Node) -> void:
	var args := _args()
	if args.has("autostart"):
		var request := {"mode": args["autostart"]} if args["autostart"] in ["new", "training"] else {"mode": "load", "slot": int(args["autostart"])}
		menu.start_game.call_deferred(request)
	if args.has("menushot"):
		menu.get_tree().create_timer(0.8).timeout.connect(func(): _shot(menu, args["menushot"]))


## Applied once the game scene is fully built.
static func apply(game: Node) -> void:
	var args := _args()
	if args.is_empty():
		return
	if args.has("flags"):
		for f in args["flags"].split(","):
			GameState.set_flag(f)
	if args.has("journal"):
		for id in args["journal"].split(","):
			Journal.discover(id)
	if args.has("at"):
		var p: PackedStringArray = args["at"].split(",")
		game.player.teleport(Vector2(float(p[0]), float(p[1])) * 32.0, args.get("face", ""))
	if args.has("skipintro") and DialogueRunner.active:
		DialogueRunner.cancel()
	if args.has("hp"):
		Combat.player_hp = int(args["hp"])
		Combat.player_hp_changed.emit(Combat.player_hp, Combat.max_hp())
	if args.has("give"):
		for id in args["give"].split(","):
			GameState.add_item(id, 1, true)
			Equipment.equip(id)
	if args.has("swing"):
		game.get_tree().create_timer(float(args["swing"])).timeout.connect(func(): game.player.try_attack())
	if args.has("wake"):
		for id in args["wake"].split(","):
			game.region.npcs[id].set_physics_process(true)
	match args.get("ui", ""):
		"equipment":
			game.hud.equipment_view.open()
		"journal":
			game.hud.journal_view.open()
		"pause":
			game.hud.pause_menu.open()
	if args.has("talk"):
		DialogueRunner.start(args["talk"])
	if args.has("sizes"):
		game.get_tree().create_timer(0.5).timeout.connect(func():
			var h: Hud = game.hud
			print("[dev] hud root=", h._root.size, " dialogue=", h.dialogue_box.size, " journal=", h.journal_view.size, " pause=", h.pause_menu.size)
			game.get_tree().quit())
	if args.has("shot"):
		var delay := float(args.get("delay", "0.8"))
		game.get_tree().create_timer(delay).timeout.connect(func(): _shot(game, args["shot"]))


static func _shot(game: Node, path: String) -> void:
	var img := game.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[dev] screenshot saved: ", path, " (", img.get_width(), "x", img.get_height(), ")")
	game.get_tree().quit()
