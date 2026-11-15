class_name CharacterSprites
extends RefCounted
## Turns a generated walk sheet (assets/characters/<id>.png) into an AnimatedSprite2D.
## Sheet layout: 4 rows (down, left, right, up) x 4 columns (stand, step, stand, step).

const FRAME := Vector2i(32, 48)
const DIRECTIONS := ["down", "left", "right", "up"]
const FRAMES := 4
const WALK_FPS := 8.0

static var _cache: Dictionary = {}


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
	_cache[character_id] = sf
	return sf


## Sprite whose origin (position 0,0) is the character's feet.
static func make(character_id: String) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames_for(character_id)
	s.centered = false
	s.offset = Vector2(-FRAME.x / 2.0, -(FRAME.y - 1))
	s.animation = "idle_down"
	return s
