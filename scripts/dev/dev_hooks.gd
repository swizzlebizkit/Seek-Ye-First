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


## Applied after the game state exists but before the region is built (starting place, clock, journeys).
##   --region=galilee_hills --entry=from_village   start in a region by one of its entries
##   --loc=nazareth								 stand at a strategic place (outskirts scene)
##   --clock=6,1040								 day, minute of day
##   --visit=a,b --discover=a,b --explore=region,.. mark places visited / discovered, regions explored
##   --journey=route,dir,km,pause				   a journey paused on the road (pause: sabbath, player)
static func before_build() -> void:
	var args := _args()
	if args.is_empty():
		return
	if args.has("clock"):
		var c: PackedStringArray = args["clock"].split(",")
		WorldSim.day = int(c[0])
		WorldSim.minute_of_day = float(c[1])
	if args.has("loc"):
		GameState.region_id = "outskirts"
		World.context = {"location": args["loc"]}
		World.visit(args["loc"])
	if args.has("region"):
		World.set_destination(args["region"], args.get("entry", ""))
	for id in args.get("visit", "").split(",", false):
		World.visit(id)
	for id in args.get("discover", "").split(",", false):
		World.reveal(id, "discovered")
	for rid in args.get("explore", "").split(",", false):
		var size: Array = World.region_meta(rid)["size"]
		World.regions_visited[rid] = true
		for y in range(0, int(size[1]), World.BLOCK):
			for x in range(0, int(size[0]), World.BLOCK):
				World.note_player(rid, Vector2(x + 2, y + 2))
	if args.has("journey"):
		var j: PackedStringArray = args["journey"].split(",")
		var r := World.route(j[0])
		var dir := int(j[1])
		var km := float(j[2])
		var opt := {"route": j[0], "to": r["b"] if dir > 0 else r["a"], "dir": dir, "mode": r["mode"], "from_km": km}
		Travel.journey = Travel._new_journey(opt)
		Travel.journey["from"] = r["a"] if dir > 0 else r["b"]
		Travel.journey["state"] = "paused"
		Travel.journey["pause"] = j[3] if j.size() > 3 else "player"
		Travel.journey["stop"] = Travel._nearest_stop(Travel.journey)
		World.context = {"route": j[0], "km": km}
		World.reveal(str(Travel.journey["from"]), "visited")
		World.reveal(str(Travel.journey["to"]), "discovered")
		World.discover_route(j[0])
		World.set_destination(Travel.pause_destination()["region"], "camp")
		if Travel.journey["pause"] == "sabbath":
			Travel.notice = "sabbath"


## Applied once the game scene is fully built.
static func apply(game: Node) -> void:
	var args := _args()
	if args.is_empty():
		return
	if args.get("autoplay", "") == "w1":
		AutoplayW1.on_scene(game)
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
	if args.get("ui", "") == "strategic":
		var sv: StrategicView = game.hud.strategic_view
		sv.open(args.get("modes", "land,water").split(",", false))
		if args.has("travel"):
			for i in range(sv._options.size()):
				if sv._options[i]["route"] == args["travel"]:
					sv._list.select(i)
					sv._on_row_selected(i)
			if args.get("go", "1") == "1":
				sv._on_go()
			if args.has("fast"):
				sv._on_speed()
	match args.get("ui", ""):
		"map":
			game.hud.journal_view.open()
			game.hud.journal_view._set_tab(JournalView.Tab.MAP)
			game.hud.journal_view._map.set_level(int(args.get("maplevel", "0")))
			if args.has("mapzoom"):
				game.hud.journal_view._map.zoom(float(args["mapzoom"]))
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
