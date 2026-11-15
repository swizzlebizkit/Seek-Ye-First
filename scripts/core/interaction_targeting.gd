class_name InteractionTargeting
extends RefCounted
## Chooses which Interactable the player is addressing. Lower score wins. The score combines
## distance, how squarely the player is facing the target, and a small bonus for people over
## scenery. Things behind the player are never chosen unless the player is standing on them.

const FACING_BONUS := 16.0
const PRIORITY_BONUS := 8.0
const BEHIND_DOT := -0.35
const TOUCHING := 10.0
## A new target must beat the current one by this much, so focus does not flicker between two
## nearly equal candidates as the player shuffles.
const HYSTERESIS := 6.0


static func score(center: Vector2, facing: Vector2, target: Interactable) -> float:
	var to := target.focus_point() - center
	var dist := to.length()
	var dot := 1.0 if dist < 0.001 else to.normalized().dot(facing)
	if dot < BEHIND_DOT and dist > TOUCHING:
		return INF
	return dist - FACING_BONUS * maxf(dot, 0.0) - PRIORITY_BONUS * target.target_priority


static func pick(center: Vector2, facing: Vector2, candidates: Array, current: Interactable = null) -> Interactable:
	var best: Interactable = null
	var best_score := INF
	var current_score := INF
	for c in candidates:
		if not (c is Interactable) or not is_instance_valid(c) or not c.is_available():
			continue
		var s := score(center, facing, c)
		if c == current:
			current_score = s
		if s < best_score:
			best_score = s
			best = c
	if current != null and current_score < INF and current_score <= best_score + HYSTERESIS:
		return current
	return best
