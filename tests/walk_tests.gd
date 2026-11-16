extends RefCounted
## W1.6 acceptance tests: the continuous physical world. Geography (compass directions, adjacency, open edges),
## crossing map edges in all four directions (by pure maths and by real key presses through real scenes), roads and
## rivers that continue across seams, settlement gates, a walk from Kefar Zayit to Cana and back, the strategic map
## staying optional, the Sabbath, discovery and saves.

var t: Node


func run(runner: Node) -> void:
	t = runner
	t._section = "walk-geography"
	test_directions()
	test_adjacency_and_edges()
	test_edge_maths()
	test_seams_align()
	t._section = "walk-routes"
	test_walkable_routes()
	t._section = "walk-live"
	await test_live_crossings()
	await test_sabbath_walking()
	await test_discovery_and_saves()


func _fresh() -> void:
	t._fresh()
	Travel.reset()


func _spawn(region: String, pos_tiles: Vector2, facing: String = "down") -> Node:
	World.set_destination(region, "")
	GameState.player_pos = pos_tiles * 32.0
	GameState.player_facing = facing
	GameState.has_saved_position = true
	return await t._spawn_game({"mode": "resume"})


func _press(action: String, frames: int = 150) -> Array:
	var got: Array = []
	var on_t := func(r, e): got.append(r)
	World.transition_requested.connect(on_t)
	Input.action_press(action)
	for i in range(frames):
		await t._frames(1)
		if not got.is_empty():
			break
	Input.action_release(action)
	World.transition_requested.disconnect(on_t)
	return got


func _first_road(region: String, row: int = -1, col: int = -1) -> Vector2i:
	var m := World.region_meta(region)
	var w := int(m["size"][0])
	var h := int(m["size"][1])
	if row >= 0:
		for x in range(w):
			if RegionTerrain.tile_class(m, x, row) == "road":
				return Vector2i(x, row)
	if col >= 0:
		for y in range(h):
			if RegionTerrain.tile_class(m, col, y) == "road":
				return Vector2i(col, y)
	return Vector2i(-1, -1)


func _world_px(region: String, pos: Vector2) -> Vector2:
	return Vector2(World.world_rect(region).position) * 32.0 + pos


# -- geography ---------------------------------------------------------------------------------
func test_directions() -> void:
	var kz := World.footprint_centre("kefar_zayit")
	var cana := World.footprint_centre("cana")
	var mag := World.footprint_centre("magdala")
	t.check(kz == Vector2.ZERO, "Kefar Zayit is at the world's origin")
	t.check(cana.x < kz.x and cana.y > kz.y, "Cana lies south-west of Kefar Zayit, on the physical map (%s)" % [cana])
	t.check(mag.x > kz.x and mag.y < kz.y, "Magdala lies north-east, on the physical map (%s)" % [mag])
	# the strategic map says the same thing
	var cs := Vector2(World.locations["cana"]["pos"][0], World.locations["cana"]["pos"][1])
	var ks := Vector2(World.locations["kefar_zayit"]["pos"][0], World.locations["kefar_zayit"]["pos"][1])
	var ms := Vector2(World.locations["magdala"]["pos"][0], World.locations["magdala"]["pos"][1])
	t.check(cs.x < ks.x and cs.y < ks.y, "and the strategic map puts Cana west and south of it too")
	t.check(ms.x > ks.x and ms.y > ks.y, "and Magdala east and north")
	for loc in ["cana", "magdala"]:
		var want := World.expected_world_tile(loc)
		var have := World.footprint_centre(str(World.locations[loc]["region"]))
		t.check(want.distance_to(have) <= 16.0, "%s sits within 16 tiles of where its coordinates put it (%.1f)" % [loc, want.distance_to(have)])
	# distances agree with the strategic roads to within a third
	for rid in ["cana__kefar_zayit__land", "kefar_zayit__magdala__land"]:
		var r: Dictionary = World.route(rid)
		var a := World.footprint_centre(str(World.locations[r["a"]]["region"]))
		var b := World.footprint_centre(str(World.locations[r["b"]]["region"]))
		var metres := a.distance_to(b) * float(World.physical["metres_per_tile"])
		var ratio := metres / (float(r["length_km"]) * 1000.0)
		t.check(ratio > 0.6 and ratio < 1.15, "%s: the physical distance is about the strategic road's length (ratio %.2f)" % [rid, ratio])
	t.check(World.validate()["errors"].is_empty(), "the shared world validates")


func test_adjacency_and_edges() -> void:
	var rects := World.continuous_rects()
	t.check(rects.size() >= 6, "at least six regional maps tile the world (%d)" % rects.size())
	var graph := {}
	for id in rects:
		graph[id] = {}
		for p in World.edge_pairs(id):
			if p["b_region"] != "":
				graph[id][p["b_region"]] = p["edge"]
		t.check(not graph[id].is_empty(), "%s has at least one neighbour" % id)
	for a in graph:
		for b in graph[a]:
			t.check(graph[b].has(a), "%s and %s are neighbours of each other" % [a, b])
	var opposite := {"north": "south", "south": "north", "east": "west", "west": "east"}
	for a in graph:
		for b in graph[a]:
			t.check(graph[b][a] == opposite[graph[a][b]], "%s is %s of %s, and %s is %s of it" % [b, graph[a][b], a, a, graph[b][a]])
	var seen := {"kefar_zayit_outskirts": true}
	var todo: Array = ["kefar_zayit_outskirts"]
	while not todo.is_empty():
		var c: String = todo.pop_back()
		for n in graph[c]:
			if not seen.has(n):
				seen[n] = true
				todo.append(n)
	t.check(seen.size() == rects.size(), "every regional map can be reached from the others across edges alone")
	# every edge that leads nowhere is a visible, solid barrier
	var nowhere := 0
	var open_nowhere := 0
	for id in rects:
		var m := World.region_meta(id)
		var blocked := RegionTerrain.blocked_tiles_cached(id, m)
		for p in World.edge_pairs(id):
			if p["b_region"] == "":
				nowhere += 1
				if not blocked.has(p["a"]):
					open_nowhere += 1
	t.check(nowhere > 400 and open_nowhere == 0, "the world's outer edge is solid cliff everywhere (%d tiles, %d open)" % [nowhere, open_nowhere])
	# no map is an invisible wall: a blocked edge tile is rock, water or wall, never empty ground
	var hidden := 0
	for id in rects:
		var m2 := World.region_meta(id)
		var blocked2 := RegionTerrain.blocked_tiles_cached(id, m2)
		for p in World.edge_pairs(id):
			if p["b_region"] == "" and blocked2.has(p["a"]) and RegionTerrain.tile_class(m2, p["a"].x, p["a"].y) == "open":
				hidden += 1
	t.check(hidden == 0, "no edge is closed by an invisible wall (%d)" % hidden)


func test_edge_maths() -> void:
	# south, then north again, through the Cana road and the approach to Cana
	var road := _first_road("cana_road", 71)
	t.check(road.x >= 0, "the Cana road reaches its south edge")
	var h := int(World.region_meta("cana_road")["size"][1])
	var south := World.edge_crossing("cana_road", Vector2(road.x * 32.0 + 16.0, h * 32.0 + 2.0))
	t.check(south.get("region", "") == "cana_approach" and south["edge"] == "south", "crossing the south edge loads the southern region")
	var back := World.edge_crossing("cana_approach", Vector2(south["pos"].x, -2.0))
	t.check(back.get("region", "") == "cana_road" and back["edge"] == "north", "crossing north from there returns to the Cana road")
	t.check(absf(_world_px("cana_road", Vector2(road.x * 32.0 + 16.0, 0.0)).x - _world_px("cana_approach", south["pos"]).x) < 0.5, "the position along the boundary is kept exactly (different map widths: 64 and 128)")
	t.check(south["pos"].y >= World.INSET - 0.1 and south["pos"].y < 80.0, "and the player lands just inside the next map")
	# east and west, through the gate countryside and the hills
	var er := Vector2i(95, 36)
	var east := World.edge_crossing("kefar_zayit_outskirts", Vector2(96.0 * 32.0 + 3.0, er.y * 32.0 + 16.0))
	t.check(east.get("region", "") == "galilee_hills" and east["edge"] == "east", "crossing the east edge loads the eastern region")
	t.check(absf(_world_px("kefar_zayit_outskirts", Vector2(96.0 * 32.0, er.y * 32.0 + 16.0)).y - _world_px("galilee_hills", east["pos"]).y) < 0.5, "keeping the same height")
	var west := World.edge_crossing("galilee_hills", Vector2(-3.0, east["pos"].y))
	t.check(west.get("region", "") == "kefar_zayit_outskirts" and west["edge"] == "west", "crossing the west edge returns")
	t.check(absf(west["pos"].y - (er.y * 32.0 + 16.0)) < 0.5, "to the same height")
	# north from the hills into the northern hills
	var north_road := _first_road("galilee_hills", 0)
	var north := World.edge_crossing("galilee_hills", Vector2(north_road.x * 32.0 + 16.0, -2.0))
	t.check(north.get("region", "") == "hills_north" and north["edge"] == "north" and north["pos"].y < 72.0 * 32.0, "crossing the north edge loads the northern region, near its south edge")
	# a point inside a map is no crossing; beyond the world is blocked
	t.check(World.edge_crossing("cana_road", Vector2(100.0, 100.0)).is_empty(), "no crossing inside a map")
	var wall := World.edge_crossing("cana_road", Vector2(-4.0, 20.0 * 32.0))
	t.check(wall.get("blocked", false), "an edge with nothing beyond it is blocked")
	t.check(World.edge_crossing("kefar_zayit", Vector2(-4.0, 100.0)).is_empty(), "a village map has no edge crossings: it is entered by its gates")
	# every position along a seam keeps its place
	var worst := 0.0
	for k in range(0, 40):
		var yy := 4.0 + k * 20.0
		var c := World.edge_crossing("kefar_zayit_outskirts", Vector2(96.0 * 32.0 + 1.0, yy))
		if c.has("region"):
			worst = maxf(worst, absf(_world_px("kefar_zayit_outskirts", Vector2(0, yy)).y - _world_px(c["region"], c["pos"]).y))
	t.check(worst < 0.5, "along the whole east seam the position is preserved (worst %.2f px)" % worst)


func test_seams_align() -> void:
	# roads: every road tile at a seam has a road across it
	var broken := 0
	var roads := 0
	var rivers := 0
	var broken_water := 0
	for id in World.continuous_rects():
		var m := World.region_meta(id)
		for p in World.edge_pairs(id):
			if p["b_region"] == "":
				continue
			var a: Vector2i = p["a"]
			var ca := RegionTerrain.tile_class(m, a.x, a.y)
			if ca != "road" and ca != "water":
				continue
			var mb := World.region_meta(str(p["b_region"]))
			var along := Vector2i(0, 1) if (p["edge"] == "west" or p["edge"] == "east") else Vector2i(1, 0)
			var ok := false
			for k in range(-2, 3):
				var b: Vector2i = p["b"] + along * k
				if b.x >= 0 and b.y >= 0 and b.x < int(mb["size"][0]) and b.y < int(mb["size"][1]) and RegionTerrain.tile_class(mb, b.x, b.y) == ca:
					ok = true
			if ca == "road":
				roads += 1
				broken += 0 if ok else 1
			else:
				rivers += 1
				broken_water += 0 if ok else 1
	t.check(roads >= 12 and broken == 0, "roads continue across every seam (%d road tiles at seams, %d broken)" % [roads, broken])
	t.check(rivers >= 4 and broken_water == 0, "the river continues across the seam (%d water tiles at seams, %d broken)" % [rivers, broken_water])
	# the three roads out of the walls meet the gates
	var kz_out := World.region_meta("kefar_zayit_outskirts")
	for ex in kz_out["exits"]:
		var rc: Array = ex["rect"]
		var road_beside := false
		for dx in [-2, -1, 1, 2]:
			for dy in range(int(rc[3])):
				var x: int = int(rc[0]) + dx
				var y: int = int(rc[1]) + dy
				road_beside = road_beside or RegionTerrain.tile_class(kz_out, x, y) == "road"
		t.check(road_beside, "a road reaches the %s of Kefar Zayit" % ex["id"])
	# terrain meets terrain: the cliff band and the stream have no gaps along a seam
	var rect := World.world_rect("galilee_hills")
	t.check(rect.position == Vector2i(48, -44), "the hills sit east of the village countryside")


# -- walking routes ----------------------------------------------------------------------------
func test_walkable_routes() -> void:
	var kz := WorldGraph.entry_tile("kefar_zayit", "arrival")
	var cana := WorldGraph.entry_tile("cana", "arrival")
	var to_cana := WorldGraph.path("kefar_zayit", kz, "cana", cana)
	t.check(not to_cana.is_empty(), "a walking path exists from inside Kefar Zayit to inside Cana (%d steps)" % to_cana.size())
	var regions := WorldGraph.regions_along(to_cana)
	t.check(regions == ["kefar_zayit", "kefar_zayit_outskirts", "cana_road", "cana_approach", "cana"], "it goes out of the village gate, across two map boundaries, and in at Cana's gate (%s)" % [regions])
	var edge_steps := 0
	for i in range(1, to_cana.size()):
		var a: Dictionary = to_cana[i - 1]
		var b: Dictionary = to_cana[i]
		if a["region"] != b["region"] and World.continuous_rects().has(a["region"]) and World.continuous_rects().has(b["region"]):
			edge_steps += 1
	t.check(edge_steps >= 2, "with at least two crossings of map edges (%d)" % edge_steps)
	t.check(to_cana.size() < 400, "and no long detour")
	var back := WorldGraph.path("cana", cana, "kefar_zayit", kz)
	t.check(not back.is_empty() and WorldGraph.regions_along(back) == ["cana", "cana_approach", "cana_road", "kefar_zayit_outskirts", "kefar_zayit"], "and the way back is the same road")
	# every strategic land route marked physical can be walked, from one place's arrival point to the other's
	var checked := 0
	for rid in World.routes:
		var r: Dictionary = World.routes[rid]
		if r["mode"] != "land" or not r.get("physical", false):
			continue
		var ra := str(World.locations[r["a"]]["region"])
		var rb := str(World.locations[r["b"]]["region"])
		var p := WorldGraph.path(ra, WorldGraph.entry_tile(ra, "arrival"), rb, WorldGraph.entry_tile(rb, "arrival"))
		t.check(not p.is_empty(), "%s can be walked without the strategic map" % rid)
		checked += 1
	t.check(checked >= 2, "at least two strategic land routes have a physical road (%d)" % checked)
	var mag := WorldGraph.entry_tile("magdala", "arrival")
	t.check(not WorldGraph.path("kefar_zayit", kz, "magdala", mag).is_empty(), "Magdala can be walked to as well")
	# the landing on the lake shore can be reached on foot
	var pier := Vector2i(227 - 112, -112 + 140)
	t.check(not WorldGraph.path("kefar_zayit", kz, "magdala_shore", pier).is_empty(), "the pier on the lake shore can be walked to")
	# and the strategic map is still offered on top
	_fresh()
	World.context = {"location": "kefar_zayit", "via_waymark": true}
	var options := Travel.options()
	t.check(options.any(func(o): return o["to"] == "cana") and options.any(func(o): return o["to"] == "magdala"), "the strategic map still offers Cana and Magdala from Kefar Zayit")
	t.check(Travel.can_start(options[0])["ok"] or Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day), "and strategic travel can be started")


# -- live: real key presses through real scenes -----------------------------------------------
func test_live_crossings() -> void:
	_fresh()
	# south and north (the Cana road and the approach to Cana)
	var road := _first_road("cana_road", 69)
	var game: Node = await _spawn("cana_road", Vector2(road.x + 0.5, 69.5), "down")
	var start_world := _world_px("cana_road", game.player.global_position)
	var got := await _press("move_down")
	t.check(got == ["cana_approach"], "walking south off the Cana road loads the approach to Cana")
	var landed := GameState.player_pos
	t.check(absf(_world_px("cana_approach", landed).x - start_world.x) < 14.0, "at the same place along the boundary (%.1f px)" % absf(_world_px("cana_approach", landed).x - start_world.x))
	t.check(GameState.player_facing == "down", "still facing south")
	game.free()
	game = await t._spawn_game({"mode": "resume"})
	t.check(game.region.data["id"] == "cana_approach" and game.player.facing == "down" and game.region.is_walkable_px(game.player.global_position), "the new region is built with the player on open ground, facing south")
	await t._frames(20)
	t.check(GameState.region_id == "cana_approach", "and does not bounce back")
	# north again
	game.player.teleport(Vector2(landed.x, 1.5 * 32.0), "up")
	got = await _press("move_up")
	t.check(got == ["cana_road"] and GameState.player_facing == "up", "walking north returns to the Cana road, facing north")
	game.free()
	# east and west (the village countryside and the hills)
	game = await _spawn("kefar_zayit_outskirts", Vector2(93.5, 36.5), "right")
	got = await _press("move_right")
	t.check(got == ["galilee_hills"] and GameState.player_facing == "right", "walking east off the countryside loads the hills, facing east")
	var hy := _world_px("galilee_hills", GameState.player_pos).y
	t.check(absf(hy - (_world_px("kefar_zayit_outskirts", Vector2(0, 36.5 * 32.0)).y)) < 12.0, "at the same height")
	game.free()
	game = await t._spawn_game({"mode": "resume"})
	game.player.teleport(Vector2(1.5, GameState.player_pos.y / 32.0) * 32.0, "left")
	got = await _press("move_left")
	t.check(got == ["kefar_zayit_outskirts"] and GameState.player_facing == "left", "walking west returns, facing west")
	game.free()
	# north from the hills into the northern hills and back, repeatedly
	var nroad := _first_road("galilee_hills", 2)
	var trips: Array = []
	for i in range(3):
		game = await _spawn("galilee_hills", Vector2(nroad.x + 0.5, 1.6), "up")
		got = await _press("move_up")
		trips.append(got)
		game.free()
		game = await t._spawn_game({"mode": "resume"})
		await t._frames(10)
		trips.append(GameState.region_id)
		game.player.teleport(Vector2(GameState.player_pos.x / 32.0, 70.4) * 32.0, "down")
		got = await _press("move_down")
		trips.append(got)
		game.free()
	t.check(trips == [["hills_north"], "hills_north", ["galilee_hills"], ["hills_north"], "hills_north", ["galilee_hills"], ["hills_north"], "hills_north", ["galilee_hills"]], "three round trips across the hills seam alternate cleanly, without loops or stalls (%s)" % [trips])


func test_sabbath_walking() -> void:
	_fresh()
	WorldSim.day = 7
	WorldSim.minute_of_day = 10.0 * 60.0
	t.check(Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day), "it is the Sabbath")
	var game: Node = await _spawn("kefar_zayit_outskirts", Vector2(93.5, 36.5), "right")
	t.check(WorldSim.clock_multiplier == 4.0, "walking the countryside runs the clock four times faster")
	var got := await _press("move_right")
	t.check(got == ["galilee_hills"], "walking across a map edge works on the Sabbath")
	game.free()
	game = await t._spawn_game({"mode": "resume"})
	var x0: float = game.player.global_position.x
	Input.action_press("move_right")
	await t._frames(30)
	Input.action_release("move_right")
	t.check(game.player.global_position.x > x0 + 20.0, "and so does walking within a map")
	# and the gates
	game.free()
	game = await _spawn("kefar_zayit", Vector2(36.5, 13.5), "right")
	t.check(WorldSim.clock_multiplier == 1.0, "inside a village the clock runs at the ordinary rate")
	got = await _press("move_right")
	t.check(got == ["kefar_zayit_outskirts"], "leaving the village by its gate works on the Sabbath")
	game.free()
	# but strategic overland travel does not
	World.context = {"location": "kefar_zayit", "via_waymark": true}
	var options := Travel.options()
	var land := options.filter(func(o): return o["mode"] == "land")
	t.check(not land.is_empty() and land.all(func(o): return not Travel.can_start(o)["ok"]), "while strategic overland travel is refused until sunset")
	_fresh()


func test_discovery_and_saves() -> void:
	_fresh()
	var game: Node = await _spawn("kefar_zayit", Vector2(36.5, 13.5), "right")
	t.check(World.explored_fraction("kefar_zayit") < 0.5 and World.explored_fraction("kefar_zayit") > 0.0, "a new game has explored only part of the village (%.0f%%)" % (World.explored_fraction("kefar_zayit") * 100.0))
	t.check(not World.regions_visited.has("cana_road") and World.level_of("cana") != "visited", "and nothing beyond it")
	var got := await _press("move_right")
	game.free()
	game = await t._spawn_game({"mode": "resume"})
	t.check(World.regions_visited.has("kefar_zayit_outskirts"), "crossing into a new region records it as visited")
	# walk the road westward by real movement, then check what was explored
	game.player.teleport(Vector2(21.5, 36.5) * 32.0, "left")
	Input.action_press("move_left")
	await t._frames(120)
	Input.action_release("move_left")
	var fraction := World.explored_fraction("kefar_zayit_outskirts")
	t.check(fraction > 0.0 and fraction < 0.5, "walking explores only what was seen (%.0f%% of the countryside)" % (fraction * 100.0))
	game.free()
	# arriving at Cana's approach shows the village in the distance; entering it visits it
	World.place_level.erase("cana")
	game = await _spawn("cana_approach", Vector2(60.5, 10.5), "down")
	t.check(World.level_of("cana") == "discovered", "reaching the approach to Cana puts Cana on the map as seen")
	game.free()
	game = await _spawn("cana", Vector2(20.5, 6.5), "down")
	t.check(World.level_of("cana") == "visited", "entering Cana records a visit")
	game.free()
	# strategic travel does not fill in the country between
	_fresh()
	var before: Dictionary = World.explored.duplicate(true)
	World.context = {"location": "kefar_zayit", "via_waymark": true}
	var opt: Dictionary = Travel.options().filter(func(o): return o["to"] == "cana")[0]
	WorldSim.day = 2
	WorldSim.minute_of_day = 8.0 * 60.0
	Travel.start(opt)
	Travel.run(1.0e6)
	t.check(Travel.last_arrival == "cana" and World.level_of("cana") == "visited", "a strategic journey reaches Cana")
	t.check(World.explored == before and not World.regions_visited.has("cana_road"), "but the country it crossed is not marked explored, and its regions are not marked visited")
	# save and load after changing regions
	_fresh()
	game = await _spawn("kefar_zayit_outskirts", Vector2(93.5, 36.5), "right")
	got = await _press("move_right")
	game.free()
	game = await t._spawn_game({"mode": "resume"})
	game.player.teleport(Vector2(10.5, 44.5) * 32.0, "up")
	World.note_player("galilee_hills", Vector2(10, 44))
	GameState.player_pos = game.player.global_position
	GameState.player_facing = "up"
	t.check(SaveManager.save_slot(1), "saved in the hills after crossing from the countryside")
	game.free()
	_fresh()
	t.check(SaveManager.load_slot(1), "loaded")
	game = await t._spawn_game({"mode": "resume"})
	t.check(GameState.region_id == "galilee_hills" and game.player.global_position.distance_to(Vector2(10.5, 44.5) * 32.0) < 1.0 and game.player.facing == "up", "the region, position and facing are restored")
	t.check(World.regions_visited.has("kefar_zayit_outskirts") and World.regions_visited.has("galilee_hills") and World.is_explored("galilee_hills", Vector2i(10, 44)), "and so are the regions visited and the ground explored")
	game.free()
	SaveManager.delete_slot(1)
	_fresh()
