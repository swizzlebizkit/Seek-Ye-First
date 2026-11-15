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
## Tie-breaker when several things are in reach and equally well aimed at: people beat
## pickups, which beat scenery.
var target_priority := 0
## Where the gold ring is drawn while this is the current target, relative to the node.
var ring_offset := Vector2.ZERO
## Optional extra availability test, e.g. a person who is running away cannot be talked to.
var gate: Callable = Callable()

var _icon: Sprite2D
var _focused := false
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
	z_index = 0


func _process(delta: float) -> void:
	if _icon.visible:
		_bob += delta * 6.0
		_icon.position = prompt_offset + Vector2(0, round(sin(_bob) * 1.5))


func set_focused(on: bool) -> void:
	_focused = on and is_available()
	_icon.visible = _focused
	_bob = 0.0
	queue_redraw()


## The point the player's aim and distance are measured against.
func focus_point() -> Vector2:
	return global_position


func is_available() -> bool:
	return not gate.is_valid() or gate.call()


## The ring under whatever is currently targeted, so there is never doubt what E will do.
func _draw() -> void:
	if not _focused:
		return
	var rx := clampf(radius * 0.4, 9.0, 14.0)
	var pts := PackedVector2Array()
	for i in range(25):
		var a := TAU * i / 24.0
		pts.append(ring_offset + Vector2(cos(a) * rx, sin(a) * rx * 0.45))
	draw_polyline(pts, Color(0.09, 0.06, 0.04, 0.9), 4.0)
	draw_polyline(pts, Color("e8d29a"), 2.0)


func prompt_text() -> String:
	return "%s: %s" % [verb, display_name] if display_name != "" else verb


func interact(by: Node) -> void:
	interacted.emit(by)
	_on_interact(by)


func _on_interact(_by: Node) -> void:
	pass
