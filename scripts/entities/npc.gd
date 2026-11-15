class_name Npc
extends CharacterBody2D
## A villager. Idles and wanders near its home tile; freezes and turns to face the player in
## dialogue. Looks come from the shared walk template (assets/characters/<id>.png).

const LAYER_NPC := 4
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const SPEED := 34.0
const CARDINALS: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]

var npc_id := ""
var display_name := ""
var dialogue_id := ""
var wander_radius := 32.0
var facing := "down"

var _sprite: AnimatedSprite2D
var _home := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _wait := 1.0
var _walk_time := 0.0
var _heading := Vector2.ZERO
var _talking := false


func setup(def: Dictionary) -> void:
	npc_id = def["id"]
	display_name = def.get("name", npc_id)
	dialogue_id = def.get("dialogue", npc_id)
	wander_radius = float(def.get("wander", 32))
	position = Vector2(def["tile"][0], def["tile"][1]) * 32.0


func _ready() -> void:
	_home = position
	_rng.seed = hash(npc_id)
	_wait = _rng.randf_range(0.5, 3.0)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = LAYER_NPC
	collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_NPC

	var body := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 8)
	body.shape = rect
	body.position = Vector2(0, -4)
	add_child(body)

	_sprite = CharacterSprites.make(npc_id)
	add_child(_sprite)

	var talk := Interactable.new()
	talk.display_name = display_name
	talk.verb = "Talk to"
	talk.radius = 30.0
	talk.position = Vector2(0, -14)
	talk.prompt_offset = Vector2(0, -50)
	talk.interacted.connect(_on_talk)
	add_child(talk)
	DialogueRunner.finished.connect(_on_dialogue_finished)


func _on_dialogue_finished() -> void:
	_talking = false


func _on_talk(by: Node) -> void:
	_talking = true
	var to_player: Vector2 = by.global_position - global_position
	facing = _facing_from(to_player)
	_play("idle")
	DialogueRunner.start(dialogue_id)


func _physics_process(delta: float) -> void:
	if _talking or GameState.mode != GameState.Mode.EXPLORE:
		velocity = Vector2.ZERO
		return
	if _walk_time > 0.0:
		_walk_time -= delta
		velocity = _heading * SPEED
		move_and_slide()
		if get_slide_collision_count() > 0 or _walk_time <= 0.0:
			_stop()
		else:
			_play("walk")
	else:
		_wait -= delta
		if _wait <= 0.0:
			_pick_heading()


func _pick_heading() -> void:
	var to_home := _home - position
	var dir: Vector2
	if to_home.length() > wander_radius:
		dir = to_home.normalized()
	else:
		dir = CARDINALS[_rng.randi_range(0, 3)]
	_heading = dir
	_walk_time = _rng.randf_range(0.4, 1.2)
	facing = _facing_from(dir)


func _stop() -> void:
	_walk_time = 0.0
	velocity = Vector2.ZERO
	_wait = _rng.randf_range(1.5, 4.0)
	_play("idle")


func _facing_from(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "right" if v.x > 0 else "left"
	return "down" if v.y > 0 else "up"


func _play(kind: String) -> void:
	var anim := "%s_%s" % [kind, facing]
	if _sprite.animation != anim:
		_sprite.play(anim)
	elif not _sprite.is_playing():
		_sprite.play(anim)
