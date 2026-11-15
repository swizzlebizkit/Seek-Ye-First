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

var map_id := "galilee_judea"
var maps: Dictionary = {}
var areas: Array = []
var features: Dictionary = {}
var locations: Dictionary = {}  # id -> def
var routes: Dictionary = {}  # id -> def (with computed "points", "length_km", "stop_list")
var travel_rules: Dictionary = {}

# saved
var place_level: Dictionary = {}  # location id -> level (absent = unknown)
var route_known: Dictionary = {}  # route id -> true
var landmarks_found: Dictionary = {}  # landmark id -> true
var regions_visited: Dictionary = {}  # region id -> true
var context: Dictionary = {}  # for template regions: {"location": id} or {"route": id, "km": float}
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
	GameState.region_id = region
	GameState.has_saved_position = false
	entry_id = entry
	_note_region(region)
	region_changed.emit(region)


## Called by exits at runtime: set the destination and rebuild the scene.
func go(region: String, entry: String) -> void:
	set_destination(region, entry)
	transition_requested.emit(region, entry)


func _note_region(region: String) -> void:
	regions_visited[region] = true
	var loc := current_location(region)
	if loc != "":
		visit(loc)


# -- discovery ---------------------------------------------------------------------------------
func level_index(loc: String) -> int:
	return LEVELS.find(place_level.get(loc, "unknown"))


func level_of(loc: String) -> String:
	return place_level.get(loc, "unknown")


func knows_place(loc: String, min_level: String = "rumored") -> bool:
	return level_index(loc) >= LEVELS.find(min_level)


## Raises a place to at least `level`. A rumor reveals only an approximate marker.
func reveal(loc: String, level: String) -> void:
	if not locations.has(loc) or not LEVELS.has(level):
		push_warning("World.reveal: unknown place or level (%s, %s)" % [loc, level])
		return
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
	return {"errors": errors, "warnings": warnings}


# -- persistence -------------------------------------------------------------------------------
func reset() -> void:
	place_level.clear()
	route_known.clear()
	landmarks_found.clear()
	regions_visited.clear()
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
		"context": context.duplicate(),
		"entry": entry_id,
		"offset": entry_offset,
	}


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
	context = d.get("context", {}).duplicate()
	entry_id = str(d.get("entry", ""))
	entry_offset = float(d.get("offset", 0.0))
