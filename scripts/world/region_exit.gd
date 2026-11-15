class_name RegionExit
extends Area2D
## An edge of a region that leads somewhere else. Built from the region's `exits` data; knows only
## where it goes ({region, entry}). Walking into it hands over to World, which rebuilds the scene.
## Nothing about the player is lost: health, items, flags, clock and any journey live in autoloads.

const TILE := 32

var exit_id := ""
var to_region := ""
var to_entry := ""
var vertical := true
var rect_tiles := Rect2()
var _fired := false


func setup(def: Dictionary) -> void:
	exit_id = def["id"]
	to_region = def["to"]["region"]
	to_entry = def["to"]["entry"]
	var r: Array = def["rect"]
	rect_tiles = Rect2(r[0], r[1], r[2], r[3])
	vertical = rect_tiles.size.y >= rect_tiles.size.x
	collision_layer = 0
	collision_mask = Player.LAYER_PLAYER
	monitoring = true
	monitorable = false
	name = "Exit_" + exit_id


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect_tiles.size * TILE
	shape.shape = box
	shape.position = (rect_tiles.position + rect_tiles.size * 0.5) * TILE
	add_child(shape)
	body_entered.connect(_on_body)


func _on_body(body: Node) -> void:
	if _fired or not body is Player or GameState.mode != GameState.Mode.EXPLORE:
		return
	_fired = true
	var along: float = (body.global_position.y if vertical else body.global_position.x) / TILE
	World.entry_offset = along - (rect_tiles.position.y if vertical else rect_tiles.position.x)
	GameState.player_pos = body.global_position
	World.go.call_deferred(to_region, to_entry)
