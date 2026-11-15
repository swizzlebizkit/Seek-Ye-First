class_name SwordStrike
extends RefCounted
## Geometry and line-of-sight rules for a sword swing, shared by the player and by armed NPCs.

const WIDTH := 30.0
const FORWARD_GAP := 2.0
const WORLD_MASK := 1


## The directional hit area in world space. `origin` is the attacker's feet.
static func hit_rect(origin: Vector2, facing: String, reach: float, width: float = WIDTH) -> Rect2:
	var c := origin + Vector2(0, -4)
	match facing:
		"right":
			return Rect2(c.x + FORWARD_GAP, c.y - width / 2.0, reach, width)
		"left":
			return Rect2(c.x - FORWARD_GAP - reach, c.y - width / 2.0, reach, width)
		"down":
			return Rect2(c.x - width / 2.0, c.y + FORWARD_GAP, width, reach)
		_:
			return Rect2(c.x - width / 2.0, c.y - FORWARD_GAP - reach, width, reach)


static func facing_vector(facing: String) -> Vector2:
	match facing:
		"right": return Vector2.RIGHT
		"left": return Vector2.LEFT
		"down": return Vector2.DOWN
		_: return Vector2.UP


## True if a solid obstacle lies on the straight line between two body centres.
static func blocked(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from, to, WORLD_MASK)
	q.collide_with_areas = false
	return not space.intersect_ray(q).is_empty()


## Bodies on `mask` whose shape overlaps the hit area AND are not hidden behind a wall.
static func bodies_hit(space: PhysicsDirectSpaceState2D, origin: Vector2, facing: String, reach: float,
		mask: int, exclude: Array = []) -> Array:
	var r := hit_rect(origin, facing, reach)
	var shape := RectangleShape2D.new()
	shape.size = r.size
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, r.get_center())
	q.collision_mask = mask
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var out: Array = []
	var from := origin + Vector2(0, -4)
	for hit in space.intersect_shape(q, 16):
		var body = hit["collider"]
		if exclude.has(body) or out.has(body):
			continue
		if body is Node2D and not blocked(space, from, body.global_position + Vector2(0, -4)):
			out.append(body)
	return out
