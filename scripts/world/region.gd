class_name Region
extends Node2D
## Builds a playable region from data/regions/<id>.json: ground and building tiles, props,
## villagers and interactables. Everything that moves or can block the player (props, NPCs,
## player) lives under `entities`, which is y-sorted so characters pass behind trees correctly.

const TILE := 32

var data: Dictionary = {}
var entities: Node2D
var npcs: Dictionary = {}  # id -> Npc

var _tileset: TileSet
var _coords: Dictionary = {}
var _prop_meta: Dictionary = {}
var _blocked: Dictionary = {}  # Vector2i tile -> true (terrain, buildings and solid props)


func load_region(id: String) -> bool:
	var loaded = DataFiles.load_json("res://data/regions/%s.json" % id)
	if not loaded is Dictionary:
		return false
	data = loaded
	var built := TilesetBuilder.build()
	_tileset = built["tileset"]
	_coords = built["coords"]
	_prop_meta = DataFiles.load_json("res://assets/props/props.json")

	var ground := _make_layer("Ground")
	_paint_ground(ground)
	var objects := _make_layer("Buildings")
	for o in data["objects"]:
		objects.set_cell(Vector2i(int(o[0]), int(o[1])), 0, _coords[o[2]])

	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)
	_index_blocked()
	_build_props()
	_build_npcs()
	_build_interactables()
	_build_exits()
	return true


## Tiles the player can never stand on, from the same data the physics uses.
func _index_blocked() -> void:
	_blocked.clear()
	var meta = DataFiles.load_json(TilesetBuilder.META_PATH)
	var solid := {}
	for n in meta["solid"]:
		solid[n] = true
	var rows: Array = data["ground"]
	for y in range(rows.size()):
		for x in range(rows[y].length()):
			if solid.has(data["ground_legend"][rows[y][x]][0]):
				_blocked[Vector2i(x, y)] = true
	for o in data["objects"]:
		if solid.has(o[2]):
			_blocked[Vector2i(int(o[0]), int(o[1]))] = true
	for p in data["props"]:
		if _prop_meta[p["prop"]]["collider"] != null:
			_blocked[Vector2i(int(p["tile"][0]), int(p["tile"][1]))] = true


func tile_blocked(tile: Vector2i) -> bool:
	return _blocked.has(tile)


## True if a point in this region is somewhere the player could actually stand.
func is_walkable_px(pos: Vector2) -> bool:
	var t := Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))
	var size: Array = data["size"]
	return t.x >= 0 and t.y >= 0 and t.x < int(size[0]) and t.y < int(size[1]) and not _blocked.has(t)


func size_px() -> Vector2:
	return Vector2(data["size"][0], data["size"][1]) * TILE


func spawn_position() -> Vector2:
	return Vector2(data["spawn"][0], data["spawn"][1]) * TILE


func has_entry(id: String) -> bool:
	return data.get("entries", {}).has(id)


## Where the player appears when arriving by `id`. An entry that runs along an edge keeps the player's
## place along it (`World.entry_offset`, in tiles), so a walk across a boundary has no jump.
func entry_position(id: String) -> Vector2:
	var e: Dictionary = data["entries"][id]
	var pos := Vector2(e["tile"][0], e["tile"][1])
	var span := float(e.get("span", 0.0))
	if span > 0.0:
		var off := clampf(World.entry_offset, 0.0, span)
		if e.get("axis", "y") == "y":
			pos.y += off
		else:
			pos.x += off
	return pos * TILE


func entry_facing(id: String) -> String:
	return str(data["entries"][id].get("facing", "down"))


## "{place}" in a template region's text becomes the name of where the protagonist is.
func _fill(v):
	if not data.get("template", false):
		return v
	if v is String:
		return v.replace("{place}", World.context_label())
	if v is Array:
		return v.map(func(x): return _fill(x))
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _fill(v[k])
		return d
	return v


func _make_layer(layer_name: String) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = _tileset
	add_child(layer)
	return layer


func _paint_ground(layer: TileMapLayer) -> void:
	var legend: Dictionary = data["ground_legend"]
	var rows: Array = data["ground"]
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			var variants: Array = legend[row[x]]
			# deterministic per-tile variation so the world looks identical on every run
			var h: int = abs((x * 73856093) ^ (y * 19349663)) % variants.size()
			layer.set_cell(Vector2i(x, y), 0, _coords[variants[h]])


func _build_props() -> void:
	for p in data["props"]:
		var meta: Dictionary = _prop_meta[p["prop"]]
		var holder := Node2D.new()
		holder.position = Vector2((p["tile"][0] + 0.5) * TILE, (p["tile"][1] + 1.0) * TILE)
		var sprite := Sprite2D.new()
		sprite.texture = load("res://assets/props/%s" % meta["file"])
		sprite.centered = false
		sprite.offset = -Vector2(meta["origin"][0], meta["origin"][1])
		holder.add_child(sprite)
		if meta["collider"] != null:
			var body := StaticBody2D.new()
			body.collision_layer = TilesetBuilder.WORLD_LAYER
			body.collision_mask = 0
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(meta["collider"][0], meta["collider"][1])
			shape.shape = rect
			shape.position = Vector2(0, -rect.size.y / 2.0)
			body.add_child(shape)
			holder.add_child(body)
		entities.add_child(holder)


func _build_npcs() -> void:
	for def in data["npcs"]:
		if Combat.actor_status(def["id"]) in ["dead", "fled"]:
			continue  # defeated earlier; the save remembers
		if def.has("when") and not GameState.check(def["when"]):
			continue  # this person is not here at this time or in this state of the world
		var npc := Npc.new()
		npc.setup(def)
		entities.add_child(npc)
		npcs[def["id"]] = npc


func _build_interactables() -> void:
	for raw in data["interactables"]:
		var def: Dictionary = _fill(raw)
		if def.has("when") and not GameState.check(def["when"]):
			continue
		var pos := Vector2(def["tile"][0], def["tile"][1]) * TILE
		match def["type"]:
			"examine":
				var ex := ExamineInteractable.new()
				ex.display_name = def["name"]
				ex.radius = float(def.get("radius", 24))
				ex.position = pos
				ex.once_flag = def.get("once_flag", "")
				if def.has("variants"):
					ex.variants = def["variants"]
				else:
					ex.variants = [{"text": def["text"]}]
				entities.add_child(ex)
			"waymark":
				var wm := WaymarkInteractable.new()
				wm.display_name = def["name"]
				wm.radius = float(def.get("radius", 30))
				wm.position = pos
				wm.text = def.get("text", [])
				wm.modes = def.get("modes", ["land", "water"])
				wm.landmark = def.get("landmark", "")
				entities.add_child(wm)
			"ledger":
				var lg := LedgerInteractable.new()
				lg.display_name = def["name"]
				lg.radius = float(def.get("radius", 28))
				lg.position = pos
				entities.add_child(lg)
			"pickup":
				if GameState.has_flag("picked_" + def["id"]):
					continue
				var meta: Dictionary = _prop_meta[def["prop"]]
				var pk := PickupInteractable.new()
				pk.pickup_id = def["id"]
				pk.item_id = def["item"]
				pk.display_name = def["name"]
				pk.radius = float(def.get("radius", 22))
				pk.text = def["text"]
				pk.effects = def.get("effects", [])
				pk.texture = load("res://assets/props/%s" % meta["file"])
				pk.sprite_origin = Vector2(meta["origin"][0], meta["origin"][1])
				pk.prompt_offset = Vector2(0, -22)
				pk.position = Vector2((def["tile"][0] + 0.5) * TILE, (def["tile"][1] + 1.0) * TILE)
				entities.add_child(pk)
			_:
				push_warning("Unknown interactable type: %s" % def["type"])


func _build_exits() -> void:
	for def in data.get("exits", []):
		var ex := RegionExit.new()
		ex.setup(def)
		add_child(ex)
