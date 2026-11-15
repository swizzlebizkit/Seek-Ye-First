class_name Npc
extends CharacterBody2D
## A character in the world. Idles and wanders near its home tile, talks, and (depending on its
## behaviour profile in data/combat/profiles.json) fights, warns, flees, surrenders or stands down.
##
## Behaviour is decided per individual from the profile, never from who the character is:
##   noncombatant  never fights; a sword swing near them or a blow makes them flee and refuse to talk
##   hostile       confronts the player on sight (optionally warning first), can flee or surrender
##   contextual    stays neutral until provoked (attacked, or witnessing an assault), then acts hostile
## Hostile and contextual characters resolve their encounter as diplomacy, avoidance or combat.

enum State { IDLE, CHALLENGE, CHASE, WINDUP, STRIKE, RECOVER, STUNNED, FLEE, SURRENDER, STANDDOWN, WARY, RETURN, ROUTED, DEAD }

## States from which turning to chase the player is a fresh aggression (so it gets a threat line).
const THREAT_FROM: Array = [State.IDLE, State.STANDDOWN, State.WARY, State.RETURN, State.ROUTED]
const LAYER_NPC := 4
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const SPEED := 34.0
const CARDINALS: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
const HIT_IFRAMES := 0.2
const STRIKE_WIDTH := 26.0
const DEATH_FADE := 0.6
const ROUTED_AVOID_RADIUS := 70.0
const EXIT_FLEE_TIME := 12.0  # a beaten enemy keeps running this long, then fades out if it never got clear
const EXIT_MARGIN := 40.0  # how far past the edge of the screen counts as gone

var npc_id := ""
var display_name := ""
var dialogue_id := ""
var sprite_id := ""
var profile_id := "villager"
var profile: Dictionary = {}
var disposition := "noncombatant"
var encounter_id := ""
var wander_radius := 32.0
var facing := "down"
var hp := 4
var max_hp := 4
var state: State = State.IDLE
var state_time := 0.0
var provoked_by := ""

var _sprite: AnimatedSprite2D
var _fx: AnimatedSprite2D
var _bark: Label
var _talk: Interactable
var _home := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _wait := 1.0
var _walk_time := 0.0
var _heading := Vector2.ZERO
var _talking := false
var _player: Player
var _invuln := 0.0
var _flash := 0.0
var _knock := Vector2.ZERO
var _lost_sight := 0.0
var _lockout := 0.0
var _low_hp_done := false
var _leaving := false
var _flee_dir := Vector2.ZERO
var _facing_locked := false


func setup(def: Dictionary) -> void:
	npc_id = def["id"]
	display_name = def.get("name", npc_id)
	dialogue_id = def.get("dialogue", npc_id)
	sprite_id = def.get("sprite", npc_id)
	profile_id = def.get("profile", "villager")
	encounter_id = def.get("encounter", "")
	facing = def.get("facing", "down")
	wander_radius = float(def.get("wander", 32))
	position = Vector2(def["tile"][0], def["tile"][1]) * 32.0


func _ready() -> void:
	add_to_group("npc")
	_home = position
	_rng.seed = hash(npc_id)
	_wait = _rng.randf_range(0.5, 3.0)
	profile = Combat.profile(profile_id)
	disposition = profile.get("disposition", "noncombatant")
	max_hp = int(profile["hp"])
	hp = max_hp
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = LAYER_NPC
	collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_NPC

	var body := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 8)
	body.shape = rect
	body.position = Vector2(0, -4)
	add_child(body)

	_sprite = CharacterSprites.make(sprite_id)
	add_child(_sprite)
	if _armed():
		_fx = AnimatedSprite2D.new()
		_fx.sprite_frames = CharacterSprites.swipe_frames()
		_fx.position = Vector2(0, -20)
		_fx.modulate = Color(1.0, 0.7, 0.6, 0.9)
		_fx.z_index = 5
		_fx.visible = false
		add_child(_fx)

	_bark = UiTheme.outlined(UiTheme.label("", 9, UiTheme.GOLD), 4)
	_bark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bark.custom_minimum_size = Vector2(150, 0)
	_bark.position = Vector2(-75, -78)
	_bark.z_index = 60
	_bark.visible = false
	add_child(_bark)

	if dialogue_id != "":
		_talk = Interactable.new()
		_talk.display_name = display_name
		_talk.verb = "Talk to"
		_talk.radius = 24.0
		_talk.position = Vector2(0, -14)
		_talk.prompt_offset = Vector2(0, -42)
		_talk.target_priority = 2
		_talk.ring_offset = Vector2(0, 14)
		_talk.gate = _can_talk
		_talk.interacted.connect(_on_talk)
		add_child(_talk)
	DialogueRunner.finished.connect(_on_dialogue_finished)
	Combat.actor_command.connect(_on_command)
	Combat.player_swung.connect(_on_player_swung)
	Combat.assault_reported.connect(_on_assault_reported)
	_restore_saved_state()
	_play("idle")


# -- profile helpers ---------------------------------------------------------------------------
func _armed() -> bool:
	return profile.has("attack")


func _attack() -> Dictionary:
	return profile.get("attack", {})


func is_alive() -> bool:
	return state != State.DEAD


func is_fighting() -> bool:
	return state in [State.CHASE, State.WINDUP, State.STRIKE, State.RECOVER, State.STUNNED]


func status_name() -> String:
	match state:
		State.IDLE: return "idle"
		State.CHALLENGE: return "challenge"
		State.CHASE, State.WINDUP, State.STRIKE, State.RECOVER, State.STUNNED: return "fighting"
		State.FLEE: return "fleeing"
		State.SURRENDER: return "surrendered"
		State.STANDDOWN: return "stood_down"
		State.WARY: return "wary"
		State.RETURN: return "returning"
		State.ROUTED: return "routed"
		_: return "dead"


func _set_state(s: State) -> void:
	# Closing in is not an attack by itself: whoever starts coming at the player in earnest says so first.
	if s == State.CHASE and disposition != "noncombatant" and state in THREAT_FROM:
		_bark_text(profile.get("threat_line", "I'll cut you down!"), true)
	state = s
	state_time = 0.0
	_facing_locked = s in [State.WINDUP, State.STRIKE, State.RECOVER]
	if s != State.STRIKE and _fx != null and s != State.RECOVER:
		_fx.visible = false
	Combat.set_actor(npc_id, status_name(), hp)
	queue_redraw()


## Called when a saved game is loaded: lasting outcomes are remembered, momentary behaviour is not.
func _restore_saved_state() -> void:
	var saved: Dictionary = Combat.actors.get(npc_id, {})
	var status: String = saved.get("status", "")
	if not Combat.LASTING_STATUSES.has(status):
		Combat.set_actor(npc_id, "idle", hp)
		return
	hp = clampi(int(saved.get("hp", hp)), 1, max_hp)
	_low_hp_done = hp <= int(max_hp * float(profile.get("low_hp", {}).get("fraction", 0.0)))
	match status:
		"routed": _set_state(State.ROUTED)
		"surrendered": _set_state(State.SURRENDER)
		"stood_down": _set_state(State.STANDDOWN)
		_: _set_state(State.IDLE)


## After the protagonist is beaten down: anyone still fighting stands back down at their post.
func reset_after_defeat() -> void:
	if state == State.DEAD:
		return
	if is_fighting() or state in [State.CHALLENGE, State.FLEE, State.WARY, State.RETURN]:
		position = _home
		velocity = Vector2.ZERO
		hp = max_hp
		_low_hp_done = false
		provoked_by = ""
		_lockout = 4.0
		_set_state(State.IDLE)
		_play("idle")


# -- talking -----------------------------------------------------------------------------------
func _can_talk() -> bool:
	return is_alive() and not is_fighting()


func _refuses_talk() -> bool:
	return state in [State.FLEE, State.WARY, State.ROUTED]


func _on_dialogue_finished() -> void:
	_talking = false


func _on_talk(by: Node) -> void:
	_face_point(by.global_position)
	_play("idle")
	if _refuses_talk():
		var text: String = profile.get("refusal", "Leave me alone!")
		DialogueRunner.start_text([text], [], display_name, false)
		return
	_talking = true
	DialogueRunner.start(dialogue_id)


# -- being struck ------------------------------------------------------------------------------
## The player's sword lands. Noncombatants are never injured: they flee and remember it.
func receive_strike(by: Node, damage: int, from_dir: String) -> void:
	if state == State.DEAD or _invuln > 0.0:
		return
	_invuln = HIT_IFRAMES
	_flash = 0.15
	if disposition == "noncombatant":
		_struck_noncombatant(by)
		return
	if state == State.SURRENDER:
		GameState.toast.emit("%s has surrendered. You lower your sword." % display_name)
		return
	hp = maxi(0, hp - damage)
	_knock = SwordStrike.facing_vector(from_dir) * 110.0
	if disposition == "contextual" and not is_fighting():
		provoked_by = "attacked"
	if hp <= 0:
		_die()
		return
	_stagger()


func _struck_noncombatant(by: Node) -> void:
	Combat.report_assault(npc_id, global_position)
	_bark_text("Help! Somebody help!")
	_start_flee(float(profile.get("flee_time", 5.0)), by.global_position, bool(profile.get("seek_help", false)))


func _stagger() -> void:
	_set_state(State.STUNNED)
	_play("idle")
	queue_redraw()


func _after_stun() -> void:
	var low: Dictionary = profile.get("low_hp", {})
	if not _low_hp_done and not low.is_empty() and hp <= int(ceil(max_hp * float(low["fraction"]))):
		_low_hp_done = true
		match low.get("behavior", "fight_on"):
			"flee":
				_hostile_flee()
				return
			"surrender":
				_surrender()
				return
	_set_state(State.CHASE)


func _hostile_flee() -> void:
	_bark_text("Enough! I'm leaving!")
	_resolve("combat_routed")
	_start_flee(EXIT_FLEE_TIME, _player_pos(), false)
	_leaving = true


func _surrender() -> void:
	_bark_text("I yield! Hold your hand!")
	_resolve("combat_surrender")
	_set_state(State.SURRENDER)
	velocity = Vector2.ZERO
	_face_point(_player_pos())
	_play("idle")


func _die() -> void:
	hp = 0
	_resolve("combat_victory")
	_set_state(State.DEAD)
	Combat.set_actor(npc_id, "dead", 0)
	velocity = Vector2.ZERO
	collision_layer = 0
	if _talk != null:
		_talk.monitorable = false
		_talk.visible = false
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate:a", 0.0, DEATH_FADE)
	tw.tween_callback(queue_free)


func _resolve(outcome: String) -> void:
	if encounter_id != "":
		Combat.resolve_encounter(encounter_id, outcome)


# -- reactions to the world --------------------------------------------------------------------
func _on_command(id: String, command: String) -> void:
	if id != npc_id or state == State.DEAD:
		return
	match command:
		"stand_down":
			provoked_by = ""
			_lost_sight = 0.0
			_set_state(State.STANDDOWN)
		"release":
			if state == State.SURRENDER:
				_set_state(State.STANDDOWN)
		"provoke":
			provoked_by = "attacked"
			_set_state(State.CHASE)
		_:
			push_warning("Unknown actor command '%s'" % command)


func _on_player_swung(origin: Vector2) -> void:
	if disposition != "noncombatant" or state in [State.DEAD, State.FLEE]:
		return
	var alarm := float(profile.get("alarm_radius", 96))
	if origin.distance_to(global_position) <= alarm and _has_los_to(origin + Vector2(0, -4)):
		_bark_text("Put that away!")
		_start_flee(float(profile.get("flee_time", 5.0)) * 0.6, origin, false)


func _on_assault_reported(victim_id: String, pos: Vector2) -> void:
	if victim_id == npc_id:
		return
	if disposition == "contextual" and pos.distance_to(global_position) <= 280.0 and _has_los_to(pos + Vector2(0, -4)):
		provoke("assault_witnessed")


## A contextual character reacts only if their profile lists this reason.
func provoke(reason: String) -> void:
	if disposition != "contextual" or state == State.DEAD or state == State.SURRENDER:
		return
	if not profile.get("provoked_by", []).has(reason):
		return
	if is_fighting() or state == State.CHALLENGE:
		return
	provoked_by = reason
	_lost_sight = 0.0
	if reason == "attacked":
		_set_state(State.CHASE)
	else:
		_begin_challenge()


# -- per-frame behaviour -----------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _talking or GameState.mode != GameState.Mode.EXPLORE:
		velocity = Vector2.ZERO
		return
	state_time += delta
	_invuln = maxf(0.0, _invuln - delta)
	_lockout = maxf(0.0, _lockout - delta)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		_sprite.modulate = Color(1.6, 1.6, 1.6) if _flash > 0.0 else Color.WHITE
	match state:
		State.IDLE, State.STANDDOWN:
			_wander(delta)
			if state == State.IDLE:
				_watch_for_player()
		State.CHALLENGE:
			_do_challenge(delta)
		State.CHASE:
			_do_chase(delta)
		State.WINDUP:
			_do_windup()
		State.STRIKE:
			_do_strike()
		State.RECOVER:
			_do_recover()
		State.STUNNED:
			_do_stunned(delta)
		State.FLEE:
			_do_flee(delta)
		State.WARY, State.ROUTED:
			_keep_away(delta)
		State.RETURN:
			_do_return(delta)
		State.SURRENDER:
			velocity = Vector2.ZERO
			_face_point(_player_pos())
			_play("idle")


func _watch_for_player() -> void:
	if disposition != "hostile" or _lockout > 0.0:
		return
	if _sees_player(float(profile.get("aggro_radius", 100))):
		if float(profile.get("warn_time", 0.0)) > 0.0:
			_begin_challenge()
		else:
			_lost_sight = 0.0
			_set_state(State.CHASE)


func _begin_challenge() -> void:
	_set_state(State.CHALLENGE)
	_bark_text(profile.get("warn_line", "Stop right there!"))
	_face_point(_player_pos())


func _do_challenge(delta: float) -> void:
	velocity = Vector2.ZERO
	_face_point(_player_pos())
	_play("idle")
	if _track_player(delta):
		_disengage()
	elif state_time >= float(profile.get("warn_time", 5.0)):
		_bark_text("Last warning!")
		_set_state(State.CHASE)


## Updates how long the player has been out of sight. True if this character should give up.
func _track_player(delta: float) -> bool:
	var p := _player_pos()
	var far := p.distance_to(global_position) > float(profile.get("lose_radius", 200))
	if _has_los_to(p + Vector2(0, -4)):
		_lost_sight = 0.0
	else:
		_lost_sight += delta
	return far or _lost_sight > float(profile.get("lose_sight_time", 3.0))


func _do_chase(delta: float) -> void:
	if _track_player(delta):
		_disengage()
		return
	var p := _player_pos()
	var to_p := p - global_position
	_face_dir(to_p)
	if to_p.length() <= float(_attack().get("reach", 22.0)) + 8.0:
		velocity = Vector2.ZERO
		_set_state(State.WINDUP)
		_face_dir(to_p)
		_show_attack_phase(0)
		return
	velocity = to_p.normalized() * float(profile.get("speed", 50.0))
	move_and_slide()
	_play("walk")


func _do_windup() -> void:
	velocity = Vector2.ZERO
	_show_attack_phase(0)
	if state_time >= float(_attack().get("windup", 0.5)):
		_set_state(State.STRIKE)
		_show_attack_phase(1)
		_land_blow()
		if _fx != null:
			_fx.play("swipe_" + facing)
			_fx.pause()
			_fx.frame = 1
			_fx.visible = true


## One hit check per blow, so a single strike can never damage the player twice.
func _land_blow() -> void:
	var p := _player_pos()
	var reach := float(_attack().get("reach", 22.0))
	var rect := SwordStrike.hit_rect(global_position, facing, reach, STRIKE_WIDTH)
	var target := Rect2(p + Vector2(-6, -8), Vector2(12, 8))
	if not rect.intersects(target):
		return
	if not _has_los_to(p + Vector2(0, -4)) or _player == null:
		return
	_player.take_hit(int(_attack().get("damage", 2)), global_position, float(_attack().get("knockback", 80.0)))


func _do_strike() -> void:
	velocity = Vector2.ZERO
	if state_time >= float(_attack().get("strike", 0.12)):
		_set_state(State.RECOVER)
		_show_attack_phase(2)
		if _fx != null:
			_fx.frame = 2


func _do_recover() -> void:
	velocity = Vector2.ZERO
	if state_time >= float(_attack().get("recover", 0.8)):
		if _fx != null:
			_fx.visible = false
		_set_state(State.CHASE)


func _do_stunned(delta: float) -> void:
	var t := float(profile.get("hit_stun", 0.3))
	velocity = _knock * maxf(0.0, 1.0 - state_time / t)
	move_and_slide()
	if state_time >= t:
		_after_stun()


func _start_flee(duration: float, from: Vector2, toward_help: bool) -> void:
	var away := (global_position - from)
	_flee_dir = away.normalized() if away.length() > 0.01 else Vector2.DOWN
	if toward_help:
		var guard := _nearest_guard()
		if guard != null:
			var to_g := (guard.global_position - global_position).normalized()
			_flee_dir = (_flee_dir * 0.4 + to_g * 0.6).normalized()
	_set_state(State.FLEE)
	_walk_time = duration


func _nearest_guard() -> Npc:
	var best: Npc = null
	var best_d := 360.0
	for n in get_tree().get_nodes_in_group("npc"):
		if n is Npc and n != self and n.disposition == "contextual" and n.is_alive():
			var d: float = n.global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				best = n
	return best


func _do_flee(delta: float) -> void:
	_walk_time -= delta
	velocity = _flee_dir * float(profile.get("flee_speed", 74.0))
	_face_dir(_flee_dir)
	move_and_slide()
	if get_slide_collision_count() > 0:
		# slide along whatever is in the way, keeping the dominant direction away from the player
		_flee_dir = _flee_dir.slide(get_slide_collision(0).get_normal()).normalized()
	_play("walk")
	if _leaving:
		if not _on_screen(EXIT_MARGIN):
			_leave()
		elif _walk_time <= 0.0:
			_leave(true)
		return
	if _walk_time <= 0.0:
		velocity = Vector2.ZERO
		if disposition == "noncombatant":
			_set_state(State.WARY)
			_walk_time = float(profile.get("wary_time", 20.0))
		else:
			_set_state(State.ROUTED)
		_play("idle")


## True if this character is within the visible screen area (grown by `margin`).
func _on_screen(margin: float) -> bool:
	var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()
	return view.grow(margin).has_point(global_position)


## A beaten enemy that has run clear of the screen is gone for good: it neither lingers nor comes back.
func _leave(fade: bool = false) -> void:
	_leaving = false
	velocity = Vector2.ZERO
	_set_state(State.DEAD)
	Combat.set_actor(npc_id, "fled", hp)
	collision_layer = 0
	if _talk != null:
		_talk.monitorable = false
		_talk.visible = false
	if fade:
		var tw := create_tween()
		tw.tween_property(_sprite, "modulate:a", 0.0, 0.6)
		tw.tween_callback(queue_free)
	else:
		queue_free()


## Wary and routed characters stay clear of the player; wary ones calm down after a while.
func _keep_away(delta: float) -> void:
	velocity = Vector2.ZERO
	var p := _player_pos()
	var to_p := p - global_position
	if to_p.length() < ROUTED_AVOID_RADIUS and _has_los_to(p + Vector2(0, -4)):
		velocity = -to_p.normalized() * float(profile.get("flee_speed", 74.0)) * 0.7
		_face_dir(-to_p)
		move_and_slide()
		_play("walk")
	else:
		_play("idle")
	if state == State.WARY:
		_walk_time -= delta
		if _walk_time <= 0.0:
			_set_state(State.IDLE)


## The player got away (or this character gave up): record avoidance and head home.
func _disengage() -> void:
	_resolve("avoidance")
	provoked_by = ""
	_lockout = 4.0
	_lost_sight = 0.0
	_bark_text("Hmph. Gone.")
	_set_state(State.RETURN)


func _do_return(delta: float) -> void:
	var to_home := _home - position
	if to_home.length() < 4.0:
		velocity = Vector2.ZERO
		_set_state(State.IDLE)
		_play("idle")
		return
	velocity = to_home.normalized() * float(profile.get("speed", 50.0)) * 0.8
	_face_dir(to_home)
	move_and_slide()
	_play("walk")
	if disposition == "hostile" and _lockout <= 0.0 and _sees_player(float(profile.get("aggro_radius", 100))):
		_set_state(State.IDLE)


func _wander(delta: float) -> void:
	if wander_radius <= 0.0:
		velocity = Vector2.ZERO
		_play("idle")
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


# -- senses ------------------------------------------------------------------------------------
func _player_pos() -> Vector2:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	return _player.global_position if _player != null else global_position + Vector2(9999, 9999)


func _has_los_to(point: Vector2) -> bool:
	return not SwordStrike.blocked(get_world_2d().direct_space_state, global_position + Vector2(0, -4), point)


func _sees_player(radius: float) -> bool:
	_player_pos()
	if _player == null or _player.is_down():
		return false
	var p := _player.global_position
	return p.distance_to(global_position) <= radius and _has_los_to(p + Vector2(0, -4))


# -- presentation ------------------------------------------------------------------------------
func _bark_text(text: String, threat: bool = false) -> void:
	_bark.text = text
	_bark.add_theme_color_override("font_color", Color("ff6a5a") if threat else UiTheme.GOLD)
	_bark.visible = true
	_bark.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(_bark, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): _bark.visible = false)


func _show_attack_phase(phase: int) -> void:
	CharacterSprites.show_attack_phase(_sprite, facing, phase)


func _face_dir(v: Vector2) -> void:
	if not _facing_locked:
		facing = _facing_from(v)


func _face_point(p: Vector2) -> void:
	facing = _facing_from(p - global_position)


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


func _draw() -> void:
	if state == State.DEAD:
		return
	if disposition != "noncombatant" and hp < max_hp:
		var w := 22.0
		draw_rect(Rect2(-w / 2.0 - 1, -57, w + 2, 5), Color(0.09, 0.06, 0.04, 0.9))
		draw_rect(Rect2(-w / 2.0, -56, w * float(hp) / float(max_hp), 3), Color(0.8, 0.22, 0.2))
	if state == State.WINDUP:
		draw_rect(Rect2(-1, -64, 3, 7), Color(0.09, 0.06, 0.04))
		draw_rect(Rect2(-1, -56, 3, 3), Color(0.09, 0.06, 0.04))
		draw_rect(Rect2(0, -63, 1, 5), Color(0.95, 0.25, 0.2))
		draw_rect(Rect2(0, -55, 1, 1), Color(0.95, 0.25, 0.2))


func _process(_delta: float) -> void:
	if state == State.WINDUP or _flash > 0.0 or hp < max_hp:
		queue_redraw()
