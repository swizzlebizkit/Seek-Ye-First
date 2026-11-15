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
	_build_props()
	_build_npcs()
	_build_interactables()
	return true


func size_px() -> Vector2:
	return Vector2(data["size"][0], data["size"][1]) * TILE


func spawn_position() -> Vector2:
	return Vector2(data["spawn"][0], data["spawn"][1]) * TILE


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
		var npc := Npc.new()
		npc.setup(def)
		entities.add_child(npc)
		npcs[def["id"]] = npc


func _build_interactables() -> void:
	for def in data["interactables"]:
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
