class_name PickupInteractable
extends Interactable
## A collectible world object. Collected pickups are remembered by the flag "picked_<id>",
## so they stay gone after save/load.

var pickup_id := ""
var item_id := ""
var text: Array = []
var effects: Array = []
var texture: Texture2D
var sprite_origin := Vector2.ZERO


func _ready() -> void:
	super._ready()
	verb = "Pick up"
	var s := Sprite2D.new()
	s.texture = texture
	s.centered = false
	s.offset = -sprite_origin
	add_child(s)
	move_child(s, 0)


func is_available() -> bool:
	return not GameState.has_flag("picked_" + pickup_id)


func _on_interact(_by: Node) -> void:
	if not is_available():
		return
	GameState.set_flag("picked_" + pickup_id)
	GameState.add_item(item_id, 1)
	DialogueRunner.start_text(text, effects)
	queue_free()
