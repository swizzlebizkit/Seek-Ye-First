class_name RegionMap
extends Control
## A map of one playable region, drawn from its data and covered by fog until the protagonist has seen
## it. Used by the journal for the regional and local views. Draws only; nothing here can move anyone.

const GROUND := {
	"g": Color("8fa860"), "h": Color("b4ab69"), "d": Color("b79a68"), "p": Color("c9c1ad"),
	"s": Color("dfd0a0"), "w": Color("6e9bb0"), "c": Color("6c6355"), "f": Color("a99a5c"),
}
const FOG := Color("2b2118")
const INK := Color("2e2116")
const GOLD := Color("e8d29a")

var region_id := ""
var labels := false  ## local view: name the points of interest the protagonist has seen
var world_mode := false  ## draw every explored regional map together, at its place in the shared world
var zoom := 1.0
var center := Vector2(0.5, 0.5)
var _data: Dictionary = {}
var _font: Font
var _drag := false


func _ready() -> void:
	_font = ThemeDB.fallback_font
	clip_contents = true
	custom_minimum_size = Vector2(360, 300)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_region(id: String, with_labels: bool) -> void:
	world_mode = false
	region_id = id
	labels = with_labels
	_data = World.region_meta(id)
	zoom = 1.0
	center = Vector2(0.5, 0.5)
	queue_redraw()


## The whole countryside: every regional map the protagonist has walked, placed by world position.
func set_world() -> void:
	world_mode = true
	region_id = ""
	labels = false
	zoom = 1.0
	center = Vector2(0.5, 0.5)
	queue_redraw()


func _world_bounds() -> Rect2i:
	var rects := World.continuous_rects()
	var b := Rect2i()
	var first := true
	for id in rects:
		b = (rects[id] as Rect2i) if first else b.merge(rects[id])
		first = false
	return b


func set_zoom(z: float) -> void:
	zoom = clampf(z, 1.0, 6.0)
	queue_redraw()


func _scale() -> float:
	if _data.is_empty():
		return 1.0
	var s: Array = _data["size"]
	return minf(size.x / float(s[0]), size.y / float(s[1])) * zoom


func _origin() -> Vector2:
	var s: Array = _data["size"]
	var sc := _scale()
	return size * 0.5 - Vector2(float(s[0]), float(s[1])) * center * sc


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(zoom * 1.2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(zoom / 1.2)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
	elif event is InputEventMouseMotion and _drag and zoom > 1.0 and not _data.is_empty():
		var s: Array = _data["size"]
		center -= event.relative / (_scale() * Vector2(float(s[0]), float(s[1])))
		center = center.clamp(Vector2(0.0, 0.0), Vector2(1.0, 1.0))
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), FOG)
	if world_mode:
		_draw_world()
		return
	if _data.is_empty():
		return
	var sc := _scale()
	var o := _origin()
	var rows: Array = _data["ground"]
	var legend: Dictionary = _data["ground_legend"]
	var w := int((_data["size"] as Array)[0])
	var h := int((_data["size"] as Array)[1])
	for y in range(h):
		for x in range(w):
			if not World.is_explored(region_id, Vector2i(x, y)):
				continue
			var ch: String = rows[y][x]
			draw_rect(Rect2(o + Vector2(x, y) * sc, Vector2(sc + 0.6, sc + 0.6)), GROUND.get(ch, FOG))
	for obj in _data["objects"]:
		if not World.is_explored(region_id, Vector2i(int(obj[0]), int(obj[1]))):
			continue
		var name: String = obj[2]
		var col := Color("8a7a66") if name.begins_with("roof") else (Color("9b8c70") if name.begins_with("lowwall") else Color("c2b392"))
		draw_rect(Rect2(o + Vector2(float(obj[0]), float(obj[1])) * sc, Vector2(sc + 0.6, sc + 0.6)), col)
	for p in _data["props"]:
		var t := Vector2i(int(p["tile"][0]), int(p["tile"][1]))
		if World.is_explored(region_id, t) and (str(p["prop"]).begins_with("olive") or str(p["prop"]) == "cypress"):
			draw_circle(o + (Vector2(t) + Vector2(0.5, 0.5)) * sc, maxf(1.5, sc * 0.45), Color("4f6b35"))
	# ways out, where the protagonist has seen them
	for e in _data.get("exits", []):
		var rc: Array = e["rect"]
		var tile := Vector2i(int(rc[0]), int(rc[1]))
		if World.is_explored(region_id, tile):
			var to_name: String = World.region_name(str(e["to"]["region"])) if World.regions_visited.has(str(e["to"]["region"])) else "The road on"
			var c := o + (Vector2(float(rc[0]), float(rc[1])) + Vector2(float(rc[2]), float(rc[3])) * 0.5) * sc
			draw_circle(c, 5.0, GOLD)
			draw_arc(c, 5.0, 0, TAU, 16, INK, 1.5)
			_text(to_name, c + Vector2(8, 4), 13, INK)
	# landmarks and points of interest
	for it in _data["interactables"]:
		var t2 := Vector2i(int(it["tile"][0]), int(it["tile"][1]))
		if not World.is_explored(region_id, t2):
			continue
		var c2 := o + (Vector2(float(it["tile"][0]), float(it["tile"][1])) + Vector2(0.5, 0.5)) * sc
		if it["type"] == "pickup":
			continue  # things lying about are not part of the map
		var lm := str(it.get("landmark", ""))
		var found_landmark: bool = lm != "" and World.landmarks_found.get(lm, false)
		if lm != "" and not found_landmark:
			continue  # a landmark is only on the map once it has been found
		if found_landmark:
			_star(c2, 6.0, Color("c0392b"))
		elif it["type"] == "waymark":
			_star(c2, 5.0, GOLD)
		if found_landmark or it["type"] == "waymark" or labels:
			_text(str(it["name"]), c2 + Vector2(8, -6), 13, INK)
	# you are here
	if GameState.region_id == region_id and World.explored.has(region_id):
		var pp := o + (World.player_px / 32.0) * sc
		draw_circle(pp, 4.0, Color("c0392b"))
		draw_arc(pp, 7.0, 0, TAU, 16, GOLD, 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color("c9ac6e"), false, 3.0)


func _draw_world() -> void:
	var b := _world_bounds()
	if b.size.x <= 0:
		return
	var sc := minf(size.x / float(b.size.x), size.y / float(b.size.y)) * zoom
	var o := size * 0.5 - Vector2(b.size) * center * sc - Vector2(b.position) * sc
	var rects := World.continuous_rects()
	for rid in rects:
		var r: Rect2i = rects[rid]
		var m := World.region_meta(rid)
		var rows: Array = m["ground"]
		var legend: Dictionary = m["ground_legend"]
		var seen: Dictionary = World.explored.get(rid, {})
		for key in seen:
			var bx: int = int(key) % 1000
			var by: int = int(key) / 1000
			for y in range(by * World.BLOCK, mini((by + 1) * World.BLOCK, r.size.y)):
				for x in range(bx * World.BLOCK, mini((bx + 1) * World.BLOCK, r.size.x)):
					draw_rect(Rect2(o + Vector2(r.position + Vector2i(x, y)) * sc, Vector2(sc + 0.5, sc + 0.5)), GROUND.get(rows[y][x], FOG))
	# the villages and towns known to the protagonist, where they stand
	for lid in World.locations:
		var reg = World.locations[lid].get("region")
		if reg == null or not World.region_meta(str(reg)).has("world") or not World.knows_place(lid, "discovered"):
			continue
		var fr := World.world_rect(str(reg))
		var rc := Rect2(o + Vector2(fr.position) * sc, Vector2(fr.size) * sc)
		draw_rect(rc, Color("8a7a66", 0.85))
		draw_rect(rc, INK, false, 1.5)
		_text(str(World.locations[lid]["name"]), rc.position + Vector2(rc.size.x * 0.5 - 24.0, rc.size.y * 0.5 + 4.0), 13, INK)
	# you are here
	var here_region := GameState.region_id
	var wp := Vector2.INF
	if rects.has(here_region):
		wp = Vector2((rects[here_region] as Rect2i).position) + World.player_px / 32.0
	elif World.region_meta(here_region).has("world"):
		wp = Vector2(World.world_rect(here_region).position) + World.player_px / 32.0
	if wp != Vector2.INF:
		var pp := o + wp * sc
		draw_circle(pp, 4.0, Color("c0392b"))
		draw_arc(pp, 7.0, 0, TAU, 16, GOLD, 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color("c9ac6e"), false, 3.0)


func _star(c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var rr := r if i % 2 == 0 else r * 0.45
		var a := -PI / 2.0 + TAU * i / 10.0
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, color)
	pts.append(pts[0])
	draw_polyline(pts, INK, 1.0)


func _text(text: String, pos: Vector2, font_size: int, color: Color) -> void:
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color("f1e6cc", 0.9))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
