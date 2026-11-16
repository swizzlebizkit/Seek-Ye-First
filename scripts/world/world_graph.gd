class_name WorldGraph
extends RefCounted
## Walkability of the whole physical world, worked out from the map data alone: tiles inside a map, edges
## between neighbouring maps (by world position) and gates into settlements. Used by the validators, the tests
## and the dev walking bot, so "can this be reached on foot?" has one answer.

## A node is {"region": String, "tile": Vector2i}. Returns the cheapest walking path as an Array of nodes,
## or [] if there is none. Tiles beside obstacles cost more, so the path keeps clear of corners.
static func path(from_region: String, from_tile: Vector2i, to_region: String, to_tile: Vector2i) -> Array:
	var ids := World.region_ids()
	var idx := {}
	for i in range(ids.size()):
		idx[ids[i]] = i
	var blocked := {}
	var sizes := {}
	var exits := {}
	for id in ids:
		var m := World.region_meta(id)
		blocked[id] = RegionTerrain.blocked_tiles_cached(id, m)
		sizes[id] = Vector2i(int(m["size"][0]), int(m["size"][1]))
		exits[id] = m.get("exits", [])
	var rects := World.continuous_rects()
	var key := func(r: String, t: Vector2i) -> int:
		return (int(idx[r]) << 24) | (t.y << 12) | t.x
	var start: int = key.call(from_region, from_tile)
	var goal: int = key.call(to_region, to_tile)
	var cost := {start: 0}
	var parent := {}
	var buckets: Array = []
	var node_of := {start: {"region": from_region, "tile": from_tile}}
	_push(buckets, 0, start)
	var c := 0
	while c < buckets.size():
		var bucket: Array = buckets[c]
		buckets[c] = []
		for k in bucket:
			if cost.get(k, 1 << 30) < c:
				continue
			if k == goal:
				return _unwind(parent, node_of, goal)
			var node: Dictionary = node_of[k]
			var r: String = node["region"]
			var t: Vector2i = node["tile"]
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = t + d
				var nr := r
				var size: Vector2i = sizes[r]
				if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
					if not rects.has(r):
						continue
					var world: Vector2i = (rects[r] as Rect2i).position + n
					nr = World.region_at_world_tile(world, r)
					if nr == "":
						continue
					n = world - (rects[nr] as Rect2i).position
				if (blocked[nr] as Dictionary).has(n):
					continue
				var step := 1 + (3 if _near(blocked[nr], n) else 0)
				_relax(cost, parent, node_of, buckets, key, c + step, k, nr, n)
				# a gate: stepping onto an exit sends the walker through it
				for ex in exits[nr]:
					var rc: Array = ex["rect"]
					if n.x >= int(rc[0]) and n.x < int(rc[0]) + int(rc[2]) and n.y >= int(rc[1]) and n.y < int(rc[1]) + int(rc[3]):
						var to: Dictionary = ex["to"]
						var entry: Dictionary = World.region_meta(str(to["region"])).get("entries", {}).get(to["entry"], {})
						if not entry.is_empty():
							var et := Vector2i(int(entry["tile"][0]), int(entry["tile"][1]))
							if not (blocked[str(to["region"])] as Dictionary).has(et):
								_relax(cost, parent, node_of, buckets, key, c + step + 1, key.call(nr, n), str(to["region"]), et, true)
		c += 1
	return []


static func _near(blocked: Dictionary, t: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if blocked.has(t + d):
			return true
	return false


static func _push(buckets: Array, c: int, k: int) -> void:
	while buckets.size() <= c:
		buckets.append([])
	(buckets[c] as Array).append(k)


static func _relax(cost: Dictionary, parent: Dictionary, node_of: Dictionary, buckets: Array, key: Callable, c: int, from_k: int, r: String, t: Vector2i, _gate: bool = false) -> void:
	var nk: int = key.call(r, t)
	if c < cost.get(nk, 1 << 30):
		cost[nk] = c
		parent[nk] = from_k
		node_of[nk] = {"region": r, "tile": t}
		_push(buckets, c, nk)


static func _unwind(parent: Dictionary, node_of: Dictionary, goal: int) -> Array:
	var out: Array = []
	var k := goal
	while true:
		out.append(node_of[k])
		if not parent.has(k):
			break
		k = parent[k]
	out.reverse()
	return out


## The regions a path passes through, in order, without repeats of the same stretch.
static func regions_along(p: Array) -> Array:
	var out: Array = []
	for n in p:
		if out.is_empty() or out[out.size() - 1] != n["region"]:
			out.append(n["region"])
	return out


## The walkable tile of an entry (settlements are planned from their arrival point).
static func entry_tile(region: String, entry: String) -> Vector2i:
	var e: Dictionary = World.region_meta(region).get("entries", {}).get(entry, {})
	return Vector2i(int(e["tile"][0]), int(e["tile"][1])) if not e.is_empty() else Vector2i(-1, -1)
