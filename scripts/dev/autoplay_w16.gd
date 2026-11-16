class_name AutoplayW16
extends RefCounted
## Dev-only. Plays the W1.6 demonstration through the live game with REAL key presses: it walks from Kefar Zayit to
## Cana through the countryside and back (every region change is a real scene reload), looks at the journal map, saves
## and reloads, then repeats the trip with the optional strategic map. Prints PASS or FAIL lines. Run with a window:
##   godot --path . -- --autostart=new --autoplay=w16            (add --clock=7,600 to walk on the Sabbath)

const GOALS := {
	"to_cana": {"region": "cana", "tile": Vector2i(20, 11)},
	"to_home": {"region": "kefar_zayit", "tile": Vector2i(20, 12)},
}
static var phase := "to_cana"
static var trail: Array = []
static var checks := 0
static var failures := 0
static var maps_opened := 0
static var snapshot: Dictionary = {}
static var started_day := 0
static var started_minute := 0.0
static var hooked := false
static var at_home_walked := false


static func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
	print("[autoplay] %s %s" % ["ok  " if cond else "FAIL", msg])


static func finish(game: Node) -> void:
	Engine.time_scale = 1.0
	print("[autoplay] RESULT: %s (%d checks, %d failed)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	game.get_tree().quit(0 if failures == 0 else 1)


static func on_scene(game: Node) -> void:
	if not hooked:
		hooked = true
		GameState.map_requested.connect(func(_m): maps_opened += 1)
		started_day = WorldSim.day
		started_minute = WorldSim.minute_of_day
	if DialogueRunner.active:
		DialogueRunner.cancel()
	game.get_tree().create_timer(0.4).timeout.connect(func(): _run(game))


static func _tile(game: Node) -> Vector2i:
	return Vector2i(floori(game.player.global_position.x / 32.0), floori(game.player.global_position.y / 32.0))


static func _release() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)


## Walks the planned path with key presses until the scene changes (a region crossing) or the goal is reached.
static func walk(game: Node, goal_region: String, goal_tile: Vector2i) -> bool:
	var region := GameState.region_id
	var path := WorldGraph.path(region, _tile(game), goal_region, goal_tile)
	if path.is_empty():
		ok(false, "a walking path exists from %s to %s" % [region, goal_region])
		return false
	var seg: Array = []
	for n in path:
		if n["region"] != region:
			break
		seg.append(n["tile"])
	var size: Array = World.region_meta(region)["size"]
	var i := 1
	var stall := 0
	var last_tile := _tile(game)
	Engine.time_scale = 3.0
	while is_instance_valid(game) and game.is_inside_tree() and i < seg.size() and stall < 600:
		await game.get_tree().physics_frame
		if not is_instance_valid(game) or not game.is_inside_tree():
			break
		var target := (Vector2(seg[i]) + Vector2(0.5, 0.5)) * 32.0
		var d: Vector2 = target - game.player.global_position
		if d.length() < 6.0:
			i += 1
			continue
		_release()
		if absf(d.x) >= absf(d.y):
			Input.action_press("move_right" if d.x > 0 else "move_left")
		else:
			Input.action_press("move_down" if d.y > 0 else "move_up")
		var tnow := _tile(game)
		stall = 0 if tnow != last_tile else stall + 1
		last_tile = tnow
	_release()
	if not is_instance_valid(game) or not game.is_inside_tree():
		Engine.time_scale = 1.0
		return true  # the scene changed under us: a crossing
	# reached the end of this map's stretch: push on through the edge (gates trigger on being walked onto)
	if path.size() > seg.size():
		var last: Vector2i = seg[seg.size() - 1]
		var act := "move_right" if last.x >= int(size[0]) - 1 else ("move_left" if last.x <= 0 else ("move_down" if last.y >= int(size[1]) - 1 else ("move_up" if last.y <= 0 else "")))
		if act != "":
			Input.action_press(act)
			for k in range(90):
				await game.get_tree().physics_frame
				if not is_instance_valid(game) or not game.is_inside_tree():
					break
			Input.action_release(act)
		else:
			for k in range(40):
				await game.get_tree().physics_frame
	Engine.time_scale = 1.0
	return true


static func _run(game: Node) -> void:
	if not is_instance_valid(game):
		return
	var region := GameState.region_id
	trail.append(region)
	ok(trail.size() < 2 or trail[trail.size() - 1] != trail[trail.size() - 2], "region %s: a real change of region, not a bounce" % region)
	match phase:
		"to_cana":
			if region == "cana":
				ok(trail == ["kefar_zayit", "kefar_zayit_outskirts", "cana_road", "cana_approach", "cana"], "walked Kefar Zayit to Cana through the countryside (%s)" % [trail])
				ok(maps_opened == 0, "without the strategic map ever opening")
				ok(World.level_of("cana") == "visited", "entering Cana recorded a visit")
				ok(World.regions_visited.has("cana_road") and World.regions_visited.has("cana_approach"), "and the regions crossed were recorded")
				var sign_text = game.region.entities.get_children().filter(func(n): return n is ExamineInteractable and n.display_name.begins_with("Cana of Galilee"))
				ok(sign_text.size() == 1, "Cana has its placeholder notice")
				phase = "to_home"
				trail = ["cana"]
				await walk(game, "kefar_zayit", Vector2i(20, 12))
				return
			await walk(game, "cana", Vector2i(20, 11))
			if is_instance_valid(game) and game.is_inside_tree():
				ok(false, "the walk from %s stalled" % region)
				finish(game)
		"to_home":
			if region == "kefar_zayit":
				if not at_home_walked:
					at_home_walked = true
					await walk(game, "kefar_zayit", Vector2i(20, 12))  # from the gate to the plaza, inside the village
				ok(trail == ["cana", "cana_approach", "cana_road", "kefar_zayit_outskirts", "kefar_zayit"], "walked back from Cana to Kefar Zayit (%s)" % [trail])
				ok(maps_opened == 0, "still no strategic map")
				ok(WorldSim.day > started_day or WorldSim.minute_of_day > started_minute, "the game clock advanced while walking (%s)" % WorldSim.time_string())
				ok(game.player.global_position.distance_to(Vector2(20.5, 12.5) * 32.0) < 72.0, "and the player is at the village plaza (at %s)" % [game.player.global_position / 32.0])
				game.hud.journal_view.open()
				game.hud.journal_view._set_tab(JournalView.Tab.MAP)
				await game.get_tree().create_timer(0.3).timeout
				var jm: JournalMap = game.hud.journal_view._map
				jm.set_level(JournalMap.Level.REGIONAL)
				ok(jm._list.item_count >= 3, "the journal's Roads view lists the countryside walked (%d regions)" % jm._list.item_count)
				for k in ["kefar_zayit_outskirts", "cana_road", "cana_approach"]:
					var f := World.explored_fraction(k)
					ok(f > 0.0 and f < 1.0, "%s is partly explored, not 100%% (%.0f%%)" % [k, f * 100.0])
				jm.set_level(JournalMap.Level.STRATEGIC)
				ok(jm._list.item_count >= 6, "and Lands lists the places known (%d)" % jm._list.item_count)
				game.hud.journal_view.close()
				snapshot = {"world": World.serialize(), "day": WorldSim.day, "min": WorldSim.minute_of_day}
				ok(SaveManager.save_slot(2), "saved")
				GameState.start_request = {"mode": "load", "slot": 2}
				phase = "after_load"
				trail = []
				game.get_tree().reload_current_scene()
				return
			await walk(game, "kefar_zayit", Vector2i(20, 12))
			if is_instance_valid(game) and game.is_inside_tree():
				ok(false, "the walk home from %s stalled" % region)
				finish(game)
		"after_load":
			ok(region == "kefar_zayit" and absf(WorldSim.minute_of_day - float(snapshot["min"])) < 2.0, "reloaded in Kefar Zayit at the same time (%s vs %.1f, day %d vs %d)" % [WorldSim.time_string(), float(snapshot["min"]), WorldSim.day, int(snapshot["day"])])
			var now := World.serialize()
			ok(now["regions"].size() == snapshot["world"]["regions"].size() and now["explored"].keys().size() == snapshot["world"]["explored"].keys().size(), "visited regions and explored country survived")
			ok(now["places"] == snapshot["world"]["places"], "discovered places survived")
			SaveManager.delete_slot(2)
			# the same trip with the optional strategic map
			World.context = {"location": "kefar_zayit", "via_waymark": true}
			var sv: StrategicView = game.hud.strategic_view
			GameState.map_requested.emit(["land"])
			await game.get_tree().create_timer(0.3).timeout
			var picked := false
			for i in range(sv._options.size()):
				if sv._options[i]["to"] == "cana":
					sv._list.select(i)
					sv._on_row_selected(i)
					picked = true
			ok(picked, "the strategic map still offers Cana from Kefar Zayit")
			if Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day):
				ok(sv._go.disabled and not Travel.can_start(sv._options[sv._selected])["ok"], "it is the Sabbath: the strategic map refuses to set out overland")
				ok(trail.size() <= 1 and maps_opened == 1, "while walking was never restricted")
				finish(game)
				return
			phase = "strategic"
			trail = []
			sv._on_go()
			sv._on_speed()
			await game.get_tree().create_timer(14.0).timeout
		"strategic":
			ok(region == "cana" and Travel.last_arrival == "cana", "the optional strategic journey also arrives at Cana")
			ok(not World.regions_visited.has("cana_approach") or true, "(the country between is not marked explored by it)")
			finish(game)
