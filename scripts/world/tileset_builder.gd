class_name TilesetBuilder
extends RefCounted
## Builds the terrain TileSet at runtime from the procedurally generated atlas (assets/tiles).
## Tile names and solidity come from terrain.json, so regenerating art never needs hand-editing in the editor.

const TILE := 32
const ATLAS_PATH := "res://assets/tiles/terrain.png"
const META_PATH := "res://assets/tiles/terrain.json"

const WORLD_LAYER := 1  ## physics layer bit shared by walls, props and water


## Returns {"tileset": TileSet, "coords": {tile_name: Vector2i}}.
static func build() -> Dictionary:
	var meta = DataFiles.load_json(META_PATH)
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, WORLD_LAYER)
	tileset.set_physics_layer_collision_mask(0, 0)

	var atlas := TileSetAtlasSource.new()
	atlas.texture = load(ATLAS_PATH)
	atlas.texture_region_size = Vector2i(TILE, TILE)
	tileset.add_source(atlas, 0)

	var solid := {}
	for n in meta["solid"]:
		solid[n] = true
	var coords := {}
	for tile_name in meta["tiles"]:
		var c: Array = meta["tiles"][tile_name]
		var v := Vector2i(int(c[0]), int(c[1]))
		atlas.create_tile(v)
		coords[tile_name] = v
		if solid.has(tile_name):
			var data := atlas.get_tile_data(v, 0)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, _footprint(tile_name))
	return {"tileset": tileset, "coords": coords}


## Collision polygon in tile-local coordinates (origin at the tile centre).
static func _footprint(tile_name: String) -> PackedVector2Array:
	var h := TILE / 2.0
	match tile_name:
		"lowwall_h":
			return PackedVector2Array([Vector2(-h, -7), Vector2(h, -7), Vector2(h, 8), Vector2(-h, 8)])
		"lowwall_v":
			return PackedVector2Array([Vector2(-7, -h), Vector2(7, -h), Vector2(7, h), Vector2(-7, h)])
		_:
			return PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
