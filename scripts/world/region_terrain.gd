class_name RegionTerrain
extends RefCounted
## What a region's data says about where the player can stand, without building any nodes. The region
## scene, the world validator, the tests and the dev walking bot all read it, so they cannot disagree.

static var _solid: Dictionary = {}
static var _props: Dictionary = {}


static func _load() -> void:
	if not _solid.is_empty():
		return
	var meta = DataFiles.load_json(TilesetBuilder.META_PATH)
	for n in meta["solid"]:
		_solid[n] = true
	_props = DataFiles.load_json("res://assets/props/props.json")


## Tiles (Vector2i -> true) that block the player: solid ground, solid buildings and props with a collider.
static func blocked_tiles(data: Dictionary) -> Dictionary:
	_load()
	var out := {}
	var rows: Array = data["ground"]
	var legend: Dictionary = data["ground_legend"]
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			if _solid.has(legend[row[x]][0]):
				out[Vector2i(x, y)] = true
	for o in data["objects"]:
		if _solid.has(o[2]):
			out[Vector2i(int(o[0]), int(o[1]))] = true
	for p in data["props"]:
		if _props[p["prop"]]["collider"] != null:
			out[Vector2i(int(p["tile"][0]), int(p["tile"][1]))] = true
	return out


static var _cache: Dictionary = {}


## blocked_tiles() remembered per region id, for the validators that look at the same map many times.
static func blocked_tiles_cached(id: String, data: Dictionary) -> Dictionary:
	if not _cache.has(id):
		_cache[id] = blocked_tiles(data)
	return _cache[id]


## "water", "cliff", "road" or "open": the kind of ground at a tile, for checking that terrain meets
## its neighbour across a map boundary.
static func tile_class(data: Dictionary, x: int, y: int) -> String:
	var name: String = data["ground_legend"][data["ground"][y][x]][0]
	if name.begins_with("water"):
		return "water"
	if name.begins_with("cliff"):
		return "cliff"
	if name.begins_with("dirt") or name.begins_with("path"):
		return "road"
	return "open"
