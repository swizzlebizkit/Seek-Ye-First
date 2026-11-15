class_name Player
extends CharacterBody2D
## The protagonist: four-direction movement, walk animation, and interaction with whatever
## Interactable is in front of them.

signal focus_changed(target: Interactable)

const SPEED := 92.0
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_NPC := 4
const LAYER_INTERACT := 8
const FACING_VECTORS := {
	"down": Vector2(0, 1), "up": Vector2(0, -1), "left": Vector2(-1, 0), "right": Vector2(1, 0),
}

var facing := "down"
var focus: Interactable = null

var _sprite: AnimatedSprite2D
var _detector: Area2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD | LAYER_NPC

	var body := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 8)
	body.shape = rect
	body.position = Vector2(0, -4)
	add_child(body)

	_sprite = CharacterSprites.make("protagonist")
	add_child(_sprite)

	_detector = Area2D.new()
	_detector.collision_layer = 0
	_detector.collision_mask = LAYER_INTERACT
	var reach := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	reach.shape = circle
	_detector.add_child(reach)
	add_child(_detector)
	_place_detector()
	_play("idle")


func _physics_process(_delta: float) -> void:
	if GameState.mode != GameState.Mode.EXPLORE:
		velocity = Vector2.ZERO
		_play("idle")
		_set_focus(null)
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO:
		_face(dir)
	velocity = dir * SPEED
	move_and_slide()
	_play("walk" if dir != Vector2.ZERO else "idle")
	_place_detector()
	_set_focus(_best_target())


func _unhandled_input(event: InputEvent) -> void:
	if GameState.mode == GameState.Mode.EXPLORE and event.is_action_pressed("interact"):
		if focus != null and focus.is_available():
			get_viewport().set_input_as_handled()
			focus.interact(self)


func teleport(pos: Vector2, face: String = "") -> void:
	global_position = pos
	if face != "":
		facing = face
	_place_detector()
	_play("idle")


func _face(dir: Vector2) -> void:
	var h := "right" if dir.x > 0 else "left"
	var v := "down" if dir.y > 0 else "up"
	if dir.x == 0.0:
		facing = v
	elif dir.y == 0.0:
		facing = h
	elif facing != h and facing != v:
		facing = h


func _place_detector() -> void:
	_detector.position = Vector2(0, -8) + FACING_VECTORS[facing] * 14.0


func _best_target() -> Interactable:
	var origin: Vector2 = global_position + Vector2(0, -8) + FACING_VECTORS[facing] * 10.0
	var best: Interactable = null
	var best_d := INF
	for area in _detector.get_overlapping_areas():
		if area is Interactable and area.is_available():
			var d: float = origin.distance_to(area.global_position)
			if d < best_d:
				best_d = d
				best = area
	return best


func _set_focus(target: Interactable) -> void:
	if target == focus:
		return
	if is_instance_valid(focus):
		focus.set_focused(false)
	focus = target
	if focus != null:
		focus.set_focused(true)
	focus_changed.emit(focus)


func _play(kind: String) -> void:
	var anim := "%s_%s" % [kind, facing]
	if _sprite.animation != anim or not _sprite.is_playing():
		_sprite.play(anim)
