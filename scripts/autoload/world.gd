extends Node
## The world database: strategic geography (locations, routes, features), the catalogue of playable
## regions and their transitions, and what the protagonist has discovered. Pure data plus discovery
## state; journeys live in Travel and the Sabbath is only ever asked of Calendar.
##
## Strategic positions are [longitude, latitude] degrees (approximate). Regional positions are tiles.

signal discovery_changed
signal region_changed(region_id: String)
## Emitted after the destination is stored; the playable scene answers by rebuilding itself.
signal transition_requested(region_id: String, entry: String)

const LEVELS := ["unknown", "rumored", "discovered", "visited", "investigated"]
const CATEGORIES := ["documented", "uncertain", "fictional"]
const KINDS := ["village", "town", "city", "port", "ford", "landmark"]
const MODES := ["land", "water"]
const REGION_DIR := "res://data/regions"
const KM_PER_DEG_LAT := 111.2
const BLOCK := 4  ## tiles per side of a block of explored map
const SIGHT := 7.0  ## tiles the protagonist can see around them

var map_id := "galilee_judea"
var maps: Dictionary = {}
var areas: Array = []
var features: Dictionary = {}
var locations: Dictionary = {}  # id -> def
var routes: Dictionary = {}  # id -> def (with computed "points", "length_km", "stop_list")
var travel_rules: Dictionary = {}
var physical: Dictionary = {}  # data/world/physical.json: how the playable maps sit in the shared world
var _continuous: Dictionary = {}  # region id -> Rect2i in world tiles, for regional maps that tile the world
const INSET := 24.0  ## px a crossing player is placed inside the next map, so they are not on its edge

# saved
var place_level: Dictionary = {}  # location id -> level (absent = unknown)
var route_known: Dictionary = {}  # route id -> true
var landmarks_found: Dictionary = {}  # landmark id -> true
var regions_visited: Dictionary = {}  # region id -> true
var explored: Dictionary = {}  # region id -> {block key (by * 1000 + bx): true}; the parts of a region the player has seen
var place_sources: Dictionary = {}  # location id -> [where the protagonist heard of it]
var context: Dictionary = {}  # for template regions: {"location": id} or {"route": id, "km": float}
var player_px := Vector2.ZERO  # where the player stands in the current region (not saved; for the map)
var entry_id := ""  # the entry the next region should place the player at
var entry_offset := 0.0  # tiles along that entry, so crossing an edge keeps the player's place

var _region_cache: Dictionary = {}
var _loaded := false


func _ready() -> void:
	load_geography()
	reset()
	PlayerKnowledge.learned.connect(_on_knowledge)


# -- loading -----------------------------------------------------------------------------------
func load_geography() -> void:
	var raw = DataFiles.load_json("res://data/world/geography.json")
	var rules = DataFiles.load_json("res://data/world/travel.json")
	travel_rules = rules if rules is Dictionary else {}
	var phys = DataFiles.load_json("res://data/world/physical.json")
	physical = phys if phys is Dictionary else {}
	_continuous.clear()
	_region_cache.clear()
	maps.clear()
	locations.clear()
	routes.clear()
	features.clear()
	areas.clear()
	if not raw is Dictionary:
		push_error("World: geography.json missing or invalid")
		return
	maps = raw.get("maps", {})
	areas = raw.get("areas", [])
	features = raw.get("features", {})
	_geo_dupes.clear()
	for loc in raw.get("locations", []):
		if locations.has(loc["id"]):
			_geo_dupes.append("location " + str(loc["id"]))
		locations[loc["id"]] = loc
	for r in raw.get("routes", []):
		if routes.has(r["id"]):
			_geo_dupes.append("route " + str(r["id"]))
		_finish_route(r)
		routes[r["id"]] = r
	_loaded = true


var _geo_dupes: Array = []


func _finish_route(r: Dictionary) -> void:
	var pts: Array = []
	if locations.has(r.get("a")) and locations.has(r.get("b")):
		pts.append(_ll(locations[r["a"]]["pos"]))
		for v in r.get("via", []):
			pts.append(_ll(v))
		pts.append(_ll(locations[r["b"]]["pos"]))
	r["points"] = pts
	var total := 0.0
	for i in range(pts.size() - 1):
		total += distance_km(pts[i], pts[i + 1])
	r["length_km"] = total
	var stops: Array = []
	var i := 0
	for s in r.get("stops", []):
		var d: Dictionary = s if s is Dictionary else {"at": s}
		stops.append({
			"id": "%s#%d" % [r["id"], i],
			"at": float(d.get("at", 0.5)),
			"km": float(d.get("at", 0.5)) * total,
			"name": d.get("name", "Wayside camp"),
			"region": d.get("region", ""),
		})
		i += 1
	r["stop_list"] = stops


func _ll(p) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))


## Great-circle-ish distance in km between two [lon, lat] points (flat approximation is fine here).
func distance_km(a: Vector2, b: Vector2) -> float:
	var lat := deg_to_rad((a.y + b.y) * 0.5)
	var dx := (b.x - a.x) * KM_PER_DEG_LAT * cos(lat)
	var dy := (b.y - a.y) * KM_PER_DEG_LAT
	return sqrt(dx * dx + dy * dy)


# -- lookups -----------------------------------------------------------------------------------
func location(id: String) -> Dictionary:
	return locations.get(id, {})


func location_name(id: String) -> String:
	return locations.get(id, {}).get("name", id)


func route(id: String) -> Dictionary:
	return routes.get(id, {})


func other_end(route_id: String, loc: String) -> String:
	var r: Dictionary = routes.get(route_id, {})
	return r.get("b", "") if r.get("a", "") == loc else r.get("a", "")


func routes_from(loc: String, mode: String = "") -> Array:
	var out: Array = []
	for id in routes:
		var r: Dictionary = routes[id]
		if (r["a"] == loc or r["b"] == loc) and (mode == "" or r["mode"] == mode):
			out.append(id)
	out.sort()
	return out


func neighbors(loc: String) -> Array:
	var out: Array = []
	for id in routes_from(loc):
		var o := other_end(id, loc)
		if not out.has(o):
			out.append(o)
	return out


## Position at `km` along a route measured from its `a` end, as [lon, lat].
func point_on_route(route_id: String, km: float) -> Vector2:
	var r: Dictionary = routes.get(route_id, {})
	var pts: Array = r.get("points", [])
	if pts.is_empty():
		return Vector2.ZERO
	var left := clampf(km, 0.0, float(r["length_km"]))
	for i in range(pts.size() - 1):
		var seg := distance_km(pts[i], pts[i + 1])
		if left <= seg or i == pts.size() - 2:
			var t := 0.0 if seg <= 0.0 else clampf(left / seg, 0.0, 1.0)
			return (pts[i] as Vector2).lerp(pts[i + 1], t)
		left -= seg
	return pts[pts.size() - 1]


# -- projection (strategic view) ---------------------------------------------------------------
func map_bounds() -> Dictionary:
	return maps.get(map_id, {}).get("bounds", {"lon_min": 34.35, "lon_max": 36.10, "lat_min": 31.35, "lat_max": 33.35})


## Unit-square position [0..1] for a lon/lat; x scaled by cos(latitude) so the map is not stretched.
func project(ll: Vector2) -> Vector2:
	var b := map_bounds()
	var mid := deg_to_rad((float(b["lat_min"]) + float(b["lat_max"])) * 0.5)
	var w := (float(b["lon_max"]) - float(b["lon_min"])) * cos(mid)
	var h := float(b["lat_max"]) - float(b["lat_min"])
	return Vector2((ll.x - float(b["lon_min"])) * cos(mid) / w, (float(b["lat_max"]) - ll.y) / h)


## Aspect ratio (width / height) of the projected map.
func map_aspect() -> float:
	var b := map_bounds()
	var mid := deg_to_rad((float(b["lat_min"]) + float(b["lat_max"])) * 0.5)
	return (float(b["lon_max"]) - float(b["lon_min"])) * cos(mid) / (float(b["lat_max"]) - float(b["lat_min"]))


func in_bounds(ll: Vector2) -> bool:
	var b := map_bounds()
	var e := 0.0005  # Vector2 holds 32-bit floats, so an edge point can round to just outside
	return ll.x >= float(b["lon_min"]) - e and ll.x <= float(b["lon_max"]) + e and ll.y >= float(b["lat_min"]) - e and ll.y <= float(b["lat_max"]) + e


# -- regions -----------------------------------------------------------------------------------
func region_ids() -> Array:
	var out: Array = []
	var dir := DirAccess.open(REGION_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


func region_meta(id: String) -> Dictionary:
	if not _region_cache.has(id):
		var d = DataFiles.load_json("%s/%s.json" % [REGION_DIR, id])
		_region_cache[id] = d if d is Dictionary else {}
	return _region_cache[id]


## Display name of a region; template regions take their name from the current context.
func region_name(id: String) -> String:
	var m := region_meta(id)
	if m.is_empty():
		return id
	if m.get("template", false):
		var label := context_label()
		return str(m.get("name", id)).replace("{place}", label)
	return str(m.get("name", id))


func context_label() -> String:
	if context.has("route"):
		var r := route(str(context["route"]))
		return str(r.get("name", "the road"))
	if context.has("location"):
		return location_name(str(context["location"]))
	return "the road"


## The strategic location the protagonist is at, or "" while on the open road.
func current_location(region_id: String = "") -> String:
	if context.get("via_waymark", false):
		return str(context.get("location", ""))  # a road marker names the place it belongs to
	var id := region_id if region_id != "" else GameState.region_id
	var m := region_meta(id)
	if m.get("template", false):
		return str(context.get("location", ""))
	return str(m.get("anchor", ""))


func current_route() -> String:
	return str(context.get("route", ""))


## Where leaving `region` by `exit_id` leads, or {} if unknown.
func exit_target(region_id: String, exit_id: String) -> Dictionary:
	for e in region_meta(region_id).get("exits", []):
		if e["id"] == exit_id:
			return e["to"]
	return {}


## Records the destination (state only). Game reloads the scene to build it.
func set_destination(region: String, entry: String = "") -> void:
	context.erase("via_waymark")
	GameState.region_id = region
	GameState.has_saved_position = false
	entry_id = entry
	_note_region(region)
	region_changed.emit(region)


## Placing the player at an exact spot (px, in the new region) rather than at a named entry. Used when
## walking across a map edge, where the position along the boundary is what matters.
func go_position(region: String, pos_px: Vector2, facing: String) -> void:
	set_destination(region, "")
	GameState.player_pos = pos_px
	GameState.player_facing = facing
	GameState.has_saved_position = true
	transition_requested.emit(region, "")


## Called by exits at runtime: set the destination and rebuild the scene.
func go(region: String, entry: String) -> void:
	set_destination(region, entry)
	transition_requested.emit(region, entry)


## Marks the blocks of a region around a tile as seen. Returns true if anything new was revealed.
func note_player(region: String, tile: Vector2) -> bool:
	var m := region_meta(region)
	if m.is_empty():
		return false
	var seen: Dictionary = explored.get(region, {})
	var size: Array = m["size"]
	var fresh := false
	var r := int(ceil(SIGHT))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > SIGHT * SIGHT:
				continue
			var tx := int(tile.x) + dx
			var ty := int(tile.y) + dy
			if tx < 0 or ty < 0 or tx >= int(size[0]) or ty >= int(size[1]):
				continue
			var key := (ty / BLOCK) * 1000 + (tx / BLOCK)
			if not seen.has(key):
				seen[key] = true
				fresh = true
	explored[region] = seen
	if fresh:
		discovery_changed.emit()
	return fresh


func is_explored(region: String, tile: Vector2i) -> bool:
	return explored.get(region, {}).has((tile.y / BLOCK) * 1000 + (tile.x / BLOCK))


func explored_fraction(region: String) -> float:
	var m := region_meta(region)
	if m.is_empty():
		return 0.0
	var size: Array = m["size"]
	var total := int(ceil(float(size[0]) / BLOCK)) * int(ceil(float(size[1]) / BLOCK))
	return float(explored.get(region, {}).size()) / maxf(1.0, float(total))


func _note_region(region: String) -> void:
	regions_visited[region] = true
	var loc := current_location(region)
	if loc != "":
		visit(loc)
	for s in region_meta(region).get("sights", []):  # places in view from this ground
		reveal(str(s["place"]), str(s.get("level", "discovered")))


# -- the shared world ---------------------------------------------------------------------------
## Regional maps that tile the world, with their rectangle in world tiles. Local maps and templates are
## not in this list: a village sits inside a regional map's footprint and is entered through its gates.
func continuous_rects() -> Dictionary:
	if _continuous.is_empty():
		for id in region_ids():
			var m := region_meta(id)
			if m.get("kind", "") == "regional" and m.has("world"):
				_continuous[id] = Rect2i(int(m["world"][0]), int(m["world"][1]), int(m["size"][0]), int(m["size"][1]))
	return _continuous


## Any region that has a place in the world (regional or local), as a rectangle of world tiles.
func world_rect(id: String) -> Rect2i:
	var m := region_meta(id)
	if m.is_empty() or not m.has("world"):
		return Rect2i()
	return Rect2i(int(m["world"][0]), int(m["world"][1]), int(m["size"][0]), int(m["size"][1]))


func region_at_world_tile(t: Vector2i, exclude: String = "") -> String:
	var rects := continuous_rects()
	for id in rects:
		if id != exclude and (rects[id] as Rect2i).has_point(t):
			return id
	return ""


## Where a place should be, in world tiles, from its longitude and latitude: the same geography seen
## through the physical scale.
func expected_world_tile(loc: String) -> Vector2:
	var o: Dictionary = locations[str(physical.get("origin_location", "kefar_zayit"))]
	var p: Dictionary = locations[loc]
	var lat := deg_to_rad((float(o["pos"][1]) + float(p["pos"][1])) * 0.5)
	var m_per_tile := float(physical.get("metres_per_tile", 50))
	var east_km := (float(p["pos"][0]) - float(o["pos"][0])) * KM_PER_DEG_LAT * cos(lat)
	var north_km := (float(p["pos"][1]) - float(o["pos"][1])) * KM_PER_DEG_LAT
	return Vector2(east_km * 1000.0 / m_per_tile, -north_km * 1000.0 / m_per_tile)


## The centre, in world tiles, of the village or town whose local map is `region`.
func footprint_centre(region: String) -> Vector2:
	var r := world_rect(region)
	return Vector2(r.position) + Vector2(r.size) * 0.5


## If `pos_px` (in `region`) is past one of its edges, returns {"region", "pos", "edge"} for the neighbouring
## map, found by world position: the same point of ground, whatever the two maps' sizes. {} if inside.
## {"blocked": true} if nothing lies beyond (such an edge is a barrier, and the validator insists on it).
func edge_crossing(region: String, pos_px: Vector2) -> Dictionary:
	var rects := continuous_rects()
	if not rects.has(region):
		return {}
	var rect: Rect2i = rects[region]
	var size_px := Vector2(rect.size) * 32.0
	var edge := ""
	if pos_px.x < 0.0:
		edge = "west"
	elif pos_px.x >= size_px.x:
		edge = "east"
	elif pos_px.y < 0.0:
		edge = "north"
	elif pos_px.y >= size_px.y:
		edge = "south"
	if edge == "":
		return {}
	var world := Vector2(rect.position) * 32.0 + pos_px
	var tile := Vector2i(floori(world.x / 32.0), floori(world.y / 32.0))
	var other := region_at_world_tile(tile, region)
	if other == "":
		return {"blocked": true, "edge": edge}
	var orect: Rect2i = rects[other]
	var npos := world - Vector2(orect.position) * 32.0
	var osize := Vector2(orect.size) * 32.0
	match edge:
		"east":
			npos.x = maxf(npos.x, INSET)
		"west":
			npos.x = minf(npos.x, osize.x - INSET)
		"south":
			npos.y = maxf(npos.y, INSET)
		"north":
			npos.y = minf(npos.y, osize.y - INSET)
	return {"region": other, "pos": npos, "edge": edge}


# -- discovery ---------------------------------------------------------------------------------
func level_index(loc: String) -> int:
	return LEVELS.find(place_level.get(loc, "unknown"))


func level_of(loc: String) -> String:
	return place_level.get(loc, "unknown")


func knows_place(loc: String, min_level: String = "rumored") -> bool:
	return level_index(loc) >= LEVELS.find(min_level)


## Raises a place to at least `level`. A rumor reveals only an approximate marker.
func reveal(loc: String, level: String, source: String = "") -> void:
	if not locations.has(loc) or not LEVELS.has(level):
		push_warning("World.reveal: unknown place or level (%s, %s)" % [loc, level])
		return
	if source != "":
		var heard: Array = place_sources.get(loc, [])
		if not heard.has(source):
			heard.append(source)
		place_sources[loc] = heard
	if LEVELS.find(level) > level_index(loc):
		place_level[loc] = level
		discovery_changed.emit()


## Standing in a place shows the roads that leave it and lets neighbours be seen (not visited).
func visit(loc: String) -> void:
	if not locations.has(loc):
		return
	reveal(loc, "visited")
	for id in routes_from(loc):
		discover_route(id)
		reveal(other_end(id, loc), "discovered")


func investigate(loc: String) -> void:
	reveal(loc, "investigated")


func discover_route(id: String) -> void:
	if routes.has(id) and not route_known.get(id, false):
		route_known[id] = true
		discovery_changed.emit()


func route_is_known(id: String) -> bool:
	return route_known.get(id, false)


func find_landmark(id: String) -> void:
	if not landmarks_found.get(id, false):
		landmarks_found[id] = true
		discovery_changed.emit()


## Known routes leaving `loc` whose far end is at least discovered.
func usable_routes_from(loc: String) -> Array:
	var out: Array = []
	for id in routes_from(loc):
		if route_is_known(id) and knows_place(other_end(id, loc), "discovered"):
			out.append(id)
	return out


## Places can be tied to canon events in data ("reveal_on"): hearing of the event puts them on the map.
## The event is never altered; only the protagonist's map changes.
func _on_knowledge(event_id: String, level: String) -> void:
	for id in locations:
		var ro: Dictionary = locations[id].get("reveal_on", {})
		if ro.get("event", "") == event_id and PlayerKnowledge.knows(event_id, ro.get("level", "rumor")):
			reveal(id, ro.get("reveal", "rumored"))


# -- validation --------------------------------------------------------------------------------
## Returns {"errors": [...], "warnings": [...]} describing every problem in the world data.
func validate() -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	for d in _geo_dupes:
		errors.append("duplicate id: " + str(d))
	var rids := region_ids()
	for id in locations:
		var l: Dictionary = locations[id]
		if not CATEGORIES.has(l.get("category", "")):
			errors.append("location %s: bad category" % id)
		if not KINDS.has(l.get("kind", "")):
			errors.append("location %s: bad kind" % id)
		if str(l.get("certainty", "")) == "":
			errors.append("location %s: missing certainty note" % id)
		if not l.has("pos") or not in_bounds(_ll(l["pos"])):
			errors.append("location %s: position outside the map" % id)
		if not LEVELS.has(l.get("start_level", "unknown")):
			errors.append("location %s: bad start_level" % id)
		var reg = l.get("region")
		if reg != null and not rids.has(str(reg)):
			errors.append("location %s: region %s does not exist" % [id, reg])
		elif reg != null and region_meta(str(reg)).get("anchor", "") != id:
			errors.append("location %s: region %s is not anchored to it" % [id, reg])
		elif reg != null and not region_meta(str(reg)).get("entries", {}).has("arrival"):
			errors.append("location %s: region %s has no arrival entry for travellers" % [id, reg])
	for id in routes:
		var r: Dictionary = routes[id]
		if not locations.has(r.get("a", "")) or not locations.has(r.get("b", "")):
			errors.append("route %s: unknown endpoint" % id)
			continue
		if r["a"] == r["b"]:
			errors.append("route %s: loops to itself" % id)
		if not MODES.has(r.get("mode", "")):
			errors.append("route %s: bad mode" % id)
		if id != "%s__%s__%s" % [r["a"], r["b"], r["mode"]] or str(r["a"]) >= str(r["b"]):
			errors.append("route %s: id must be a__b__mode with a before b" % id)
		for p in r["points"]:
			if not in_bounds(p):
				errors.append("route %s: waypoint outside the map" % id)
		if float(r["length_km"]) <= 0.0:
			errors.append("route %s: zero length" % id)
		if r["mode"] == "land" and r["stop_list"].is_empty():
			errors.append("route %s: a land route needs a stopping point" % id)
		for s in r["stop_list"]:
			if float(s["at"]) <= 0.0 or float(s["at"]) >= 1.0:
				errors.append("route %s: stop outside the route" % id)
			if str(s["region"]) != "" and not rids.has(str(s["region"])):
				errors.append("route %s: stop region %s does not exist" % [id, s["region"]])
	for fid in features:
		var f: Dictionary = features[fid]
		for p in f.get("polygon", []) + f.get("line", []):
			if not in_bounds(_ll(p)):
				errors.append("feature %s: point outside the map" % fid)
		if f.has("pos") and not in_bounds(_ll(f["pos"])):
			errors.append("feature %s: outside the map" % fid)
	# the strategic graph must be one connected piece
	if not locations.is_empty():
		var seen := {}
		var todo: Array = [locations.keys()[0]]
		while not todo.is_empty():
			var cur: String = todo.pop_back()
			if seen.has(cur):
				continue
			seen[cur] = true
			todo.append_array(neighbors(cur))
		for id in locations:
			if not seen.has(id):
				errors.append("location %s is not connected to the route network" % id)
	# playable regions
	for rid in rids:
		var m := region_meta(rid)
		if str(m.get("id", rid)) != rid:
			errors.append("region %s: id does not match the file name" % rid)
		var anchor := str(m.get("anchor", ""))
		if anchor != "" and not locations.has(anchor):
			errors.append("region %s: anchor %s is not a location" % [rid, anchor])
		var size: Array = m.get("size", [0, 0])
		var entries: Dictionary = m.get("entries", {})
		for eid in entries:
			var t: Array = entries[eid]["tile"]
			if t[0] < 0 or t[1] < 0 or t[0] > size[0] or t[1] > size[1]:
				errors.append("region %s: entry %s is outside the region" % [rid, eid])
		var exit_ids := {}
		for e in m.get("exits", []):
			if exit_ids.has(e["id"]):
				errors.append("region %s: duplicate exit %s" % [rid, e["id"]])
			exit_ids[e["id"]] = true
			var rc: Array = e["rect"]
			if rc[0] < 0 or rc[1] < 0 or rc[0] + rc[2] > size[0] or rc[1] + rc[3] > size[1]:
				errors.append("region %s: exit %s is outside the region" % [rid, e["id"]])
			var to: Dictionary = e["to"]
			var dest := region_meta(str(to.get("region", "")))
			if dest.is_empty():
				errors.append("region %s: exit %s leads to a missing region" % [rid, e["id"]])
			elif not dest.get("entries", {}).has(to.get("entry", "")):
				errors.append("region %s: exit %s leads to a missing entry" % [rid, e["id"]])
			else:
				var back := false
				for e2 in dest.get("exits", []):
					if str(e2["to"].get("region", "")) == rid:
						back = true
				if not back:
					warnings.append("region %s: exit %s has no way back" % [rid, e["id"]])
	_validate_physical(errors, warnings)
	return {"errors": errors, "warnings": warnings}


## Every tile along every edge of a continuous map, paired with the tile across the boundary:
## [{"a": Vector2i (in `id`), "b_region": String ("" if nothing lies beyond), "b": Vector2i, "edge": String}].
func edge_pairs(id: String) -> Array:
	var rects := continuous_rects()
	var out: Array = []
	if not rects.has(id):
		return out
	var r: Rect2i = rects[id]
	for y in range(r.size.y):
		out.append(_pair(id, r, Vector2i(0, y), Vector2i(-1, 0), "west"))
		out.append(_pair(id, r, Vector2i(r.size.x - 1, y), Vector2i(1, 0), "east"))
	for x in range(r.size.x):
		out.append(_pair(id, r, Vector2i(x, 0), Vector2i(0, -1), "north"))
		out.append(_pair(id, r, Vector2i(x, r.size.y - 1), Vector2i(0, 1), "south"))
	return out


func _pair(id: String, r: Rect2i, a: Vector2i, step: Vector2i, edge: String) -> Dictionary:
	var world := r.position + a + step
	var other := region_at_world_tile(world, id)
	var b := Vector2i(-1, -1)
	if other != "":
		b = world - (continuous_rects()[other] as Rect2i).position
	return {"a": a, "b_region": other, "b": b, "edge": edge}


func _validate_physical(errors: Array, warnings: Array) -> void:
	var rects := continuous_rects()
	var ids := rects.keys()
	# maps of the world must not overlap each other
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			if (rects[ids[i]] as Rect2i).intersects(rects[ids[j]]):
				errors.append("regions %s and %s overlap in the world" % [ids[i], ids[j]])
	# terrain meets terrain across every shared boundary; an open edge must lead somewhere
	for id in ids:
		var m := region_meta(id)
		var blocked := RegionTerrain.blocked_tiles(m)
		var dead := 0
		var blocked_across := 0
		var broken := 0
		for p in edge_pairs(id):
			var a: Vector2i = p["a"]
			var ca := RegionTerrain.tile_class(m, a.x, a.y)
			var walk_a := not blocked.has(a)
			if p["b_region"] == "":
				if walk_a:
					dead += 1
				continue
			var mb := region_meta(str(p["b_region"]))
			var b: Vector2i = p["b"]
			if walk_a and RegionTerrain.blocked_tiles_cached(str(p["b_region"]), mb).has(b):
				blocked_across += 1
			if ca == "road" or ca == "water":
				# a road or river must carry on across the seam (within two tiles, since it may cross at an angle)
				var along := Vector2i(0, 1) if (p["edge"] == "west" or p["edge"] == "east") else Vector2i(1, 0)
				var ok := false
				var bsize: Array = mb["size"]
				for k in [-2, -1, 0, 1, 2]:
					var bb: Vector2i = b + along * k
					if bb.x >= 0 and bb.y >= 0 and bb.x < int(bsize[0]) and bb.y < int(bsize[1]) and RegionTerrain.tile_class(mb, bb.x, bb.y) == ca:
						ok = true
				if not ok:
					broken += 1
		if dead > 0:
			errors.append("region %s: %d walkable edge tiles lead nowhere (a blocked edge must be a visible barrier)" % [id, dead])
		if blocked_across > 0:
			errors.append("region %s: %d walkable edge tiles meet a solid tile across the boundary" % [id, blocked_across])
		if broken > 0:
			errors.append("region %s: %d road or river tiles do not continue across the boundary" % [id, broken])
	# villages and towns sit inside a map and where their longitude and latitude say they should
	var tol := float(physical.get("position_tolerance_tiles", 16))
	var placed: Array = []
	for lid in locations:
		var reg = locations[lid].get("region")
		if reg == null or not region_meta(str(reg)).has("world"):
			continue
		var rect := world_rect(str(reg))
		var inside := ""
		for rid in ids:
			if (rects[rid] as Rect2i).encloses(rect):
				inside = rid
		if inside == "":
			errors.append("local map %s does not sit inside any regional map of the world" % reg)
		var d := footprint_centre(str(reg)).distance_to(expected_world_tile(lid))
		if d > tol:
			errors.append("%s is %.0f tiles from where its longitude and latitude put it" % [lid, d])
		placed.append(lid)
	# and every pair of them lies in the right compass direction from the other
	var tol_deg := float(physical.get("direction_tolerance_degrees", 20))
	for i in range(placed.size()):
		for j in range(i + 1, placed.size()):
			var want := expected_world_tile(placed[j]) - expected_world_tile(placed[i])
			var have := footprint_centre(str(locations[placed[j]]["region"])) - footprint_centre(str(locations[placed[i]]["region"]))
			if want.length() > 1.0 and have.length() > 1.0 and rad_to_deg(absf(want.angle_to(have))) > tol_deg:
				errors.append("%s lies in the wrong direction from %s on the physical map" % [placed[j], placed[i]])
	# road markers belong to a real place or road
	for rid in region_ids():
		for it in region_meta(rid).get("interactables", []):
			if it.get("type", "") != "waymark":
				continue
			if it.has("place") and not locations.has(str(it["place"])):
				errors.append("region %s: marker names unknown place %s" % [rid, it["place"]])
			if it.has("route") and not routes.has(str(it["route"])):
				errors.append("region %s: marker names unknown route %s" % [rid, it["route"]])
			if not it.has("place") and not it.has("route") and region_meta(rid).get("kind", "") != "template":
				errors.append("region %s: marker '%s' says neither a place nor a road" % [rid, it.get("name", "")])
		for s in region_meta(rid).get("sights", []):
			if not locations.has(str(s.get("place", ""))):
				errors.append("region %s: sight names unknown place %s" % [rid, s.get("place", "")])


# -- persistence -------------------------------------------------------------------------------
func reset() -> void:
	place_level.clear()
	route_known.clear()
	landmarks_found.clear()
	regions_visited.clear()
	explored.clear()
	place_sources.clear()
	context.clear()
	entry_id = ""
	entry_offset = 0.0
	_apply_start_levels()


func _apply_start_levels() -> void:
	for id in locations:
		var lv: String = locations[id].get("start_level", "unknown")
		if lv == "visited":
			visit(id)
		elif lv != "unknown":
			reveal(id, lv)


func serialize() -> Dictionary:
	return {
		"v": 1,
		"places": place_level.duplicate(),
		"routes": route_known.keys(),
		"landmarks": landmarks_found.keys(),
		"regions": regions_visited.keys(),
		"explored": _explored_out(),
		"sources": place_sources.duplicate(true),
		"context": context.duplicate(),
		"entry": entry_id,
		"offset": entry_offset,
	}


func _explored_out() -> Dictionary:
	var out := {}
	for rid in explored:
		out[rid] = explored[rid].keys()
	return out


## Absent or partial data (older saves) falls back to the start-of-game knowledge.
func deserialize(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	for id in d.get("places", {}):
		var lv: String = d["places"][id]
		if locations.has(id) and LEVELS.has(lv):
			place_level[id] = lv
	for id in d.get("routes", []):
		if routes.has(id):
			route_known[id] = true
	for id in d.get("landmarks", []):
		landmarks_found[id] = true
	for id in d.get("regions", []):
		regions_visited[id] = true
	for rid in d.get("explored", {}):
		if region_meta(rid).is_empty():
			continue
		var seen := {}
		for k in d["explored"][rid]:
			seen[int(k)] = true
		explored[rid] = seen
	for id in d.get("sources", {}):
		if locations.has(id):
			place_sources[id] = (d["sources"][id] as Array).duplicate()
	context = d.get("context", {}).duplicate()
	entry_id = str(d.get("entry", ""))
	entry_offset = float(d.get("offset", 0.0))
