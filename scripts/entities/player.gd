class_name Player
extends CharacterBody2D
## The protagonist: four-direction movement, walk animation, a sword swing, a dodge step, damage
## handling, and interaction with whatever Interactable is best aimed at.

signal focus_changed(target: Interactable)
signal attacked(facing: String)
signal hurt(amount: int)

const SPEED := 92.0
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_NPC := 4
const LAYER_INTERACT := 8
const FACING_VECTORS := {
	"down": Vector2(0, 1), "up": Vector2(0, -1), "left": Vector2(-1, 0), "right": Vector2(1, 0),
}

# sword swing: wind-up, active (hits are checked), then recovery. The weapon's own cooldown
# (measured from the start of the swing) decides when the next swing may begin.
const WINDUP := 0.07
const ACTIVE := 0.12
const SWING_TOTAL := 0.33
const RECOVER_SPEED := 0.5
const ATTACK_BUFFER := 0.12  # a press this close to the end of the cooldown is remembered
# taking damage
const HURT_INVULN := 0.9
const HURT_KNOCKBACK_TIME := 0.14
# dodge step
const DODGE_TIME := 0.18
const DODGE_SPEED := 210.0
const DODGE_COOLDOWN := 0.8
const DODGE_IFRAMES := 0.28

var facing := "down"
var focus: Interactable = null

## -1 = not swinging, 0 = wind-up, 1 = active, 2 = recover
var swing_phase := -1
var swing_time := 0.0
var attack_cooldown := 0.0
var invulnerable_time := 0.0
var dodge_time := 0.0
var dodge_cooldown := 0.0
var last_swing_hits: Array = []  # bodies struck by the swing in progress (or the last one)
var swings_started := 0

var _sprite: AnimatedSprite2D
var _swipe: AnimatedSprite2D
var _detector: Area2D
var _buffered := 0.0
var _hit_flash := 0.0
var _knock := Vector2.ZERO
var _knock_time := 0.0
var _dodge_dir := Vector2.ZERO
var _toast_cooldown := 0.0
var _down := false


func _ready() -> void:
	add_to_group("player")
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

	_swipe = AnimatedSprite2D.new()
	_swipe.sprite_frames = CharacterSprites.swipe_frames()
	_swipe.position = Vector2(0, -20)
	_swipe.z_index = 5
	_swipe.visible = false
	add_child(_swipe)

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


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if GameState.mode != GameState.Mode.EXPLORE or _down:
		velocity = Vector2.ZERO
		if swing_phase >= 0:
			_end_swing()
		if not _down:
			_play("idle")
		_set_focus(null)
		return

	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if swing_phase >= 0:
		_advance_swing()
	if dodge_time > 0.0:
		velocity = _dodge_dir * DODGE_SPEED
	elif _knock_time > 0.0:
		velocity = _knock
	elif swing_phase == 0 or swing_phase == 1:
		velocity = Vector2.ZERO  # committed to the swing
	else:
		if dir != Vector2.ZERO and swing_phase < 0:
			_face(dir)
		var speed := SPEED * Equipment.speed_multiplier() * (RECOVER_SPEED if swing_phase == 2 else 1.0)
		velocity = dir * speed
	move_and_slide()

	if swing_phase >= 0:
		CharacterSprites.show_attack_phase(_sprite, facing, swing_phase)
	else:
		_play("walk" if (dir != Vector2.ZERO or dodge_time > 0.0) else "idle")
	_place_detector()
	_set_focus(_best_target())


func _process(_delta: float) -> void:
	if _down:
		return
	var a := 1.0
	var tint := Color.WHITE
	if _hit_flash > 0.0:
		tint = Color(1.0, 0.45, 0.45)
	if invulnerable_time > 0.0 and dodge_time <= 0.0 and _hit_flash <= 0.0:
		a = 0.4 if int(invulnerable_time * 18.0) % 2 == 0 else 1.0
	elif dodge_time > 0.0:
		a = 0.55
	_sprite.modulate = Color(tint, a)


func _unhandled_input(event: InputEvent) -> void:
	if GameState.mode != GameState.Mode.EXPLORE or _down:
		return
	if event.is_action_pressed("interact"):
		if focus != null and focus.is_available():
			get_viewport().set_input_as_handled()
			focus.interact(self)
	elif event.is_action_pressed("attack"):
		get_viewport().set_input_as_handled()
		try_attack()
	elif event.is_action_pressed("dodge"):
		get_viewport().set_input_as_handled()
		try_dodge()
	elif event.is_action_pressed("eat"):
		get_viewport().set_input_as_handled()
		if swing_phase < 0 and dodge_time <= 0.0:
			Combat.eat()


func teleport(pos: Vector2, face: String = "") -> void:
	global_position = pos
	if face != "":
		facing = face
	_place_detector()
	_play("idle")


# -- sword -------------------------------------------------------------------------------------
func is_attacking() -> bool:
	return swing_phase >= 0


func is_invulnerable() -> bool:
	return invulnerable_time > 0.0


## Starts a swing if everything allows it. Returns true if one began.
func try_attack() -> bool:
	if GameState.mode != GameState.Mode.EXPLORE or _down:
		return false
	if not Combat.offense_allowed(global_position):
		_buffered = 0.0
		return false
	var weapon := Equipment.weapon()
	if weapon.is_empty():
		if _toast_cooldown <= 0.0:
			GameState.toast.emit("You have nothing to fight with.")
			_toast_cooldown = 3.0
		return false
	if swing_phase >= 0 or dodge_time > 0.0:
		return false
	if attack_cooldown > 0.0:
		if attack_cooldown <= ATTACK_BUFFER:
			_buffered = ATTACK_BUFFER
		return false
	swing_phase = 0
	swing_time = 0.0
	attack_cooldown = float(weapon["cooldown"])
	last_swing_hits = []
	swings_started += 1
	Combat.swung(global_position)
	attacked.emit(facing)
	return true


func _advance_swing() -> void:
	if swing_phase == 0 and swing_time >= WINDUP:
		swing_phase = 1
		_swipe.play("swipe_" + facing)
		_swipe.pause()
		_swipe.frame = 1
		_swipe.visible = true
	if swing_phase == 1:
		_strike()
		if swing_time >= WINDUP + ACTIVE:
			swing_phase = 2
			_swipe.frame = 2
	if swing_phase == 2 and swing_time >= SWING_TOTAL:
		_end_swing()


## One hit check against everything the blade currently reaches. A target is struck once per swing.
func _strike() -> void:
	var weapon := Equipment.weapon()
	if weapon.is_empty():
		return
	if not Combat.offense_allowed(global_position):
		_end_swing()  # re-checked before any damage: no hitbox is made while restricted
		return
	var space := get_world_2d().direct_space_state
	for body in SwordStrike.bodies_hit(space, global_position, facing, float(weapon["reach"]), LAYER_NPC, [self]):
		if last_swing_hits.has(body):
			continue
		last_swing_hits.append(body)
		if body.has_method("receive_strike"):
			body.receive_strike(self, int(weapon["attack"]), facing)


func _end_swing() -> void:
	swing_phase = -1
	_swipe.visible = false


# -- dodge and damage --------------------------------------------------------------------------
func try_dodge() -> bool:
	if GameState.mode != GameState.Mode.EXPLORE or _down or not Combat.offense_allowed(global_position):
		return false
	if swing_phase >= 0 or dodge_time > 0.0 or dodge_cooldown > 0.0:
		return false
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_dodge_dir = dir.normalized() if dir != Vector2.ZERO else -FACING_VECTORS[facing]
	dodge_time = DODGE_TIME
	dodge_cooldown = DODGE_COOLDOWN
	invulnerable_time = maxf(invulnerable_time, DODGE_IFRAMES)
	return true


## An enemy's blow lands. Returns the damage taken (0 if the player was invulnerable).
## Armor lowers every hit; a shield lowers hits that come from the front.
func take_hit(raw_damage: int, from_pos: Vector2, knockback: float = 0.0) -> int:
	if _down or invulnerable_time > 0.0 or Combat.is_player_down():
		return 0
	var away := global_position - from_pos
	away = away.normalized() if away.length() > 0.001 else -FACING_VECTORS[facing]
	var from_front := (-away).dot(FACING_VECTORS[facing]) > 0.3
	var dealt := Combat.hurt_player(Combat.damage_after_armor(raw_damage, from_front))
	invulnerable_time = HURT_INVULN
	_hit_flash = 0.18
	_knock = away * knockback
	_knock_time = HURT_KNOCKBACK_TIME if knockback > 0.0 else 0.0
	if swing_phase >= 0:
		_end_swing()
	hurt.emit(dealt)
	return dealt


## Falls over (defeat) or gets back up (recovery).
func set_down(down: bool) -> void:
	_down = down
	_sprite.rotation_degrees = 90.0 if down else 0.0
	_sprite.modulate = Color(0.7, 0.6, 0.6, 1.0) if down else Color.WHITE
	if down:
		_end_swing()
		velocity = Vector2.ZERO
	else:
		invulnerable_time = 1.5
		_play("idle")


func is_down() -> bool:
	return _down


## Entering a protected area cancels any swing and any buffered attack input at once.
func _update_restriction() -> void:
	var was := CanonicalProtection.restricted
	var now := CanonicalProtection.update_restriction(global_position)
	if now and (not was or _buffered > 0.0 or swing_phase >= 0):
		_buffered = 0.0
		if swing_phase >= 0:
			_end_swing()


func _tick_timers(delta: float) -> void:
	_update_restriction()
	if swing_phase >= 0 and GameState.mode == GameState.Mode.EXPLORE:
		swing_time += delta
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	dodge_time = maxf(0.0, dodge_time - delta)
	dodge_cooldown = maxf(0.0, dodge_cooldown - delta)
	invulnerable_time = maxf(0.0, invulnerable_time - delta)
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_knock_time = maxf(0.0, _knock_time - delta)
	_toast_cooldown = maxf(0.0, _toast_cooldown - delta)
	if _buffered > 0.0:
		_buffered -= delta
		if attack_cooldown <= 0.0 and swing_phase < 0:
			_buffered = 0.0
			try_attack()


# -- movement helpers and interaction ----------------------------------------------------------
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
	var center: Vector2 = global_position + Vector2(0, -8)
	return InteractionTargeting.pick(center, FACING_VECTORS[facing], _detector.get_overlapping_areas(),
			focus if is_instance_valid(focus) else null)


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
