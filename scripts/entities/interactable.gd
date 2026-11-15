class_name Interactable
extends Area2D
## Anything the player can press E on. Lives on physics layer 4 ("interact"); the player's detector
## picks the best candidate and calls interact().

signal interacted(by: Node)

const LAYER_INTERACT := 8

var display_name := ""
var verb := "Examine"
var radius := 24.0
var prompt_offset := Vector2(0, -28)

var _icon: Sprite2D
var _bob := 0.0


func _init() -> void:
	collision_layer = LAYER_INTERACT
	collision_mask = 0
	monitoring = false
	monitorable = true


func _ready() -> void:
	add_to_group("interactable")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	_icon = Sprite2D.new()
	_icon.texture = load("res://assets/ui/prompt_e.png")
	_icon.position = prompt_offset
	_icon.visible = false
	_icon.z_index = 50
	add_child(_icon)


func _process(delta: float) -> void:
	if _icon.visible:
		_bob += delta * 6.0
		_icon.position = prompt_offset + Vector2(0, round(sin(_bob) * 1.5))


func set_focused(on: bool) -> void:
	_icon.visible = on and is_available()
	_bob = 0.0


func is_available() -> bool:
	return true


func prompt_text() -> String:
	return "%s: %s" % [verb, display_name] if display_name != "" else verb


func interact(by: Node) -> void:
	interacted.emit(by)
	_on_interact(by)


func _on_interact(_by: Node) -> void:
	pass
