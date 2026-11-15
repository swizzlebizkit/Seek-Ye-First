class_name CharacterSprites
extends RefCounted
## Turns generated sprite sheets (assets/characters/<id>.png and <id>_attack.png) into an
## AnimatedSprite2D. Walk sheet: 4 rows (down, left, right, up) x 4 columns (stand, step, stand, step).
## Attack sheet: the same 4 rows x 3 columns (wind-up, swing, recover) of 48px frames, wide enough for the blade.

const FRAME := Vector2i(32, 48)
const ATTACK_FRAME := Vector2i(48, 48)
const DIRECTIONS := ["down", "left", "right", "up"]
const FRAMES := 4
const ATTACK_FRAMES := 3
const FX_FRAMES := 3
const WALK_FPS := 8.0

static var _cache: Dictionary = {}
static var _fx_cache: SpriteFrames


static func frames_for(character_id: String) -> SpriteFrames:
	if _cache.has(character_id):
		return _cache[character_id]
	var sheet: Texture2D = load("res://assets/characters/%s.png" % character_id)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for row in range(DIRECTIONS.size()):
		var d: String = DIRECTIONS[row]
		sf.add_animation("walk_" + d)
		sf.set_animation_speed("walk_" + d, WALK_FPS)
		sf.set_animation_loop("walk_" + d, true)
		sf.add_animation("idle_" + d)
		sf.set_animation_loop("idle_" + d, false)
		for col in range(FRAMES):
			var tex := AtlasTexture.new()
			tex.atlas = sheet
			tex.region = Rect2(col * FRAME.x, row * FRAME.y, FRAME.x, FRAME.y)
			sf.add_frame("walk_" + d, tex)
			if col == 0:
				sf.add_frame("idle_" + d, tex)
	var attack_path := "res://assets/characters/%s_attack.png" % character_id
	if ResourceLoader.exists(attack_path):
		_add_sheet(sf, load(attack_path), "attack_")
	_cache[character_id] = sf
	return sf


## Crescent swipe effect: animations swipe_<dir>, 3 frames each, 48x48 centred on the attacker.
static func swipe_frames() -> SpriteFrames:
	if _fx_cache == null:
		var sf := SpriteFrames.new()
		sf.remove_animation("default")
		_add_sheet(sf, load("res://assets/characters/swipe_fx.png"), "swipe_")
		_fx_cache = sf
	return _fx_cache


static func _add_sheet(sf: SpriteFrames, sheet: Texture2D, prefix: String) -> void:
	for row in range(DIRECTIONS.size()):
		var an: String = prefix + DIRECTIONS[row]
		sf.add_animation(an)
		sf.set_animation_speed(an, 1.0)
		sf.set_animation_loop(an, false)
		for col in range(ATTACK_FRAMES):
			var t := AtlasTexture.new()
			t.atlas = sheet
			t.region = Rect2(col * ATTACK_FRAME.x, row * ATTACK_FRAME.y, ATTACK_FRAME.x, ATTACK_FRAME.y)
			sf.add_frame(an, t)


## Sprite whose origin (position 0,0) is the character's feet.
static func make(character_id: String) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames_for(character_id)
	s.centered = false
	s.offset = Vector2(-FRAME.x / 2.0, -(FRAME.y - 1))
	s.animation = "idle_down"
	# attack frames are 48px wide (room for the blade), so re-centre them under the feet
	s.animation_changed.connect(func():
		var wide := String(s.animation).begins_with("attack_")
		var w: int = ATTACK_FRAME.x if wide else FRAME.x
		s.offset = Vector2(-w / 2.0, -(FRAME.y - 1)))
	return s


## Shows one phase (0 wind-up, 1 swing, 2 recover) of the attack animation and holds it.
static func show_attack_phase(s: AnimatedSprite2D, facing: String, phase: int) -> void:
	var an := "attack_" + facing
	if not s.sprite_frames.has_animation(an):
		return
	s.animation = an
	s.pause()
	s.frame = clampi(phase, 0, ATTACK_FRAMES - 1)
