class_name MapCanvas
extends Control
## Draws the strategic map (seas, river, hills, roads, places, the traveller) from World's data, showing
## only what the protagonist has discovered. It does nothing but draw and report clicks, so the same
## control serves the travel screen and the journal. Positions are unit-square coordinates (0..1) over
## the map's bounds; `zoom` 1 shows the whole map.

signal place_clicked(id: String)

const LAND := Color("d8c79a")
const LAND_EDGE := Color("a58b57")
const SEA := Color("7ea3b0")
const SEA_EDGE := Color("55808f")
const ROAD := Color("6b4a2a")
const WATER_ROUTE := Color("3f6f88")
const INK := Color("2e2116")
const HILL := Color("a08a5c")
const GOLD := Color("e8d29a")
const SELECT := Color("c0392b")

var center := Vector2(0.5, 0.5)
var zoom := 1.0
var selected := ""
var highlight_route := ""
var traveller := Vector2.ZERO  ## [lon, lat]; ZERO means no traveller
var traveller_mode := "land"
var here := ""  ## location id to ring as "you are here"
var show_all := false  ## true shows every place regardless of discovery (never used by the game UI)
var max_zoom := 8.0

var _hover := ""
var _drag := false
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(360, 360)


# -- coordinates -------------------------------------------------------------------------------
func _unit_size() -> Vector2:
	var aspect := World.map_aspect()
	var h := size.y
	var w := h * aspect
	if w > size.x:
		w = size.x
		h = w / aspect
	return Vector2(w, h)


## Unit-square position to screen position in this control.
func to_screen(u: Vector2) -> Vector2:
	return size * 0.5 + (u - center) * _unit_size() * zoom


func from_screen(p: Vector2) -> Vector2:
	return center + (p - size * 0.5) / (_unit_size() * zoom)


func ll_to_screen(ll: Vector2) -> Vector2:
	return to_screen(World.project(ll))


func set_zoom(z: float, around: Vector2 = Vector2(-1, -1)) -> void:
	var before := from_screen(around) if around.x >= 0 else center
	zoom = clampf(z, 1.0, max_zoom)
	if around.x >= 0:
		center += before - from_screen(around)
	_clamp_center()
	queue_redraw()


func focus(ll: Vector2) -> void:
	center = World.project(ll)
	_clamp_center()
	queue_redraw()


func _clamp_center() -> void:
	var half := Vector2(size.x, size.y) * 0.5 / (_unit_size() * zoom)
	center.x = clampf(center.x, minf(half.x, 0.5), maxf(1.0 - half.x, 0.5))
	center.y = clampf(center.y, minf(half.y, 0.5), maxf(1.0 - half.y, 0.5))


# -- which places are drawn --------------------------------------------------------------------
func _place_shown(id: String) -> bool:
	return show_all or World.knows_place(id, "rumored")


## A rumor gives only a rough position: a fixed, repeatable offset so the marker never jumps.
func _marker_pos(id: String) -> Vector2:
	var ll := Vector2(World.locations[id]["pos"][0], World.locations[id]["pos"][1])
	var p := ll_to_screen(ll)
	if World.level_of(id) == "rumored" and not show_all:
		var h := absi(id.hash())
		var ang := float(h % 628) / 100.0
		var r := 5.0 + float((h / 628) % 6)
		p += Vector2(cos(ang), sin(ang)) * r
	return p


func place_at(p: Vector2, radius: float = 14.0) -> String:
	var best := ""
	var best_d := radius
	for id in World.locations:
		if not _place_shown(id):
			continue
		var d := _marker_pos(id).distance_to(p)
		if d < best_d:
			best_d = d
			best = id
	return best


# -- input -------------------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			set_zoom(zoom * 1.25, e.position)
			accept_event()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			set_zoom(zoom / 1.25, e.position)
			accept_event()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_drag = true
				var id := place_at(e.position)
				if id != "":
					place_clicked.emit(id)
			else:
				_drag = false
	elif event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		if _drag and zoom > 1.0:
			center -= m.relative / (_unit_size() * zoom)
			_clamp_center()
			queue_redraw()
		var id2 := place_at(m.position)
		if id2 != _hover:
			_hover = id2
			queue_redraw()


# -- drawing -----------------------------------------------------------------------------------
func _draw() -> void:
	if World.locations.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), LAND)
	_draw_features()
	_draw_areas()
	_draw_routes()
	_draw_places()
	_draw_traveller()
	draw_rect(Rect2(Vector2.ZERO, size), LAND_EDGE, false, 3.0)


func _poly(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(ll_to_screen(Vector2(p[0], p[1])))
	return out


func _draw_features() -> void:
	for id in World.features:
		var f: Dictionary = World.features[id]
		match f["kind"]:
			"sea", "lake":
				var poly := _poly(f["polygon"])
				if Geometry2D.triangulate_polygon(poly).is_empty():
					continue
				draw_colored_polygon(poly, SEA)
				var closed := poly.duplicate()
				closed.append(poly[0])
				draw_polyline(closed, SEA_EDGE, 2.0)
				if f.get("name", "") != "" and (f["kind"] == "lake" and zoom >= 2.0):
					var c := Vector2.ZERO
					for p in poly:
						c += p
					c /= poly.size()
					_text(f["name"], c, 13, Color("34576a"), true)
			"river":
				draw_polyline(_poly(f["line"]), SEA_EDGE, maxf(2.0, zoom * 0.9))
			"hill":
				var p: Vector2 = ll_to_screen(Vector2(f["pos"][0], f["pos"][1]))
				var s := 6.0 + zoom
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, s * 0.7), p + Vector2(-s, s * 0.7)]), HILL)
				if zoom >= 2.5:
					_text(f["name"], p + Vector2(0, s + 12), 12, INK.lightened(0.15), true)


func _draw_areas() -> void:
	if zoom > 3.0:
		return
	for a in World.areas:
		var p := ll_to_screen(Vector2(a["label"][0], a["label"][1]))
		_text(String(a["name"]).to_upper(), p, 15 if zoom < 2.0 else 18, Color(INK, 0.5), true)


func _draw_routes() -> void:
	for id in World.routes:
		if not World.route_is_known(id) and not show_all:
			continue
		var r: Dictionary = World.routes[id]
		var pts := PackedVector2Array()
		for p in r["points"]:
			pts.append(ll_to_screen(p))
		var hl: bool = id == highlight_route
		if r["mode"] == "water":
			_dashed(pts, SELECT if hl else WATER_ROUTE, 3.0 if hl else 2.0)
		else:
			draw_polyline(pts, SELECT if hl else ROAD, 4.0 if hl else 2.5)
		if zoom >= 3.0 and r["mode"] == "land":
			for s in r["stop_list"]:
				draw_circle(ll_to_screen(World.point_on_route(id, s["km"])), 2.5, ROAD)


func _dashed(pts: PackedVector2Array, color: Color, width: float) -> void:
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var n := int(a.distance_to(b) / 9.0)
		for k in range(0, n, 2):
			draw_line(a.lerp(b, float(k) / maxf(n, 1)), a.lerp(b, float(k + 1) / maxf(n, 1)), color, width)


func _draw_places() -> void:
	for id in World.locations:
		if not _place_shown(id):
			continue
		var level := "visited" if show_all else World.level_of(id)
		var p := _marker_pos(id)
		var uncertain: bool = World.locations[id]["category"] == "uncertain"
		var ring := GOLD if id == selected else INK
		match level:
			"rumored":
				_dashed_circle(p, 6.0, Color(INK, 0.7))
				_text(String(World.locations[id]["name"]) + "?", p + Vector2(10, 4), 13, Color(INK, 0.65), false, true)
			"discovered":
				draw_circle(p, 5.0, LAND)
				draw_arc(p, 5.0, 0, TAU, 20, ring, 2.0)
				_text(World.locations[id]["name"], p + Vector2(9, 5), 14, INK, false, true)
			_:
				draw_circle(p, 6.0, INK)
				if level == "investigated":
					draw_arc(p, 9.0, 0, TAU, 24, GOLD, 2.5)
				if uncertain:
					draw_arc(p, 9.0 if level != "investigated" else 12.0, 0, TAU, 24, Color(INK, 0.6), 1.0)
				_text(World.locations[id]["name"], p + Vector2(10, 5), 15, INK, false, true)
		if id == selected:
			draw_arc(p, 11.0, 0, TAU, 28, SELECT, 3.0)
		if id == here:
			draw_arc(p, 14.0, 0, TAU, 28, GOLD, 3.0)
		if id == _hover and id != selected:
			draw_arc(p, 11.0, 0, TAU, 28, Color(SELECT, 0.6), 2.0)


func _dashed_circle(p: Vector2, r: float, color: Color) -> void:
	for k in range(0, 12, 2):
		draw_arc(p, r, TAU * k / 12.0, TAU * (k + 1) / 12.0, 4, color, 2.0)


func _draw_traveller() -> void:
	if traveller == Vector2.ZERO:
		return
	var p := ll_to_screen(traveller)
	if traveller_mode == "water":
		var hull := PackedVector2Array([p + Vector2(-9, 2), p + Vector2(9, 2), p + Vector2(5, 8), p + Vector2(-5, 8)])
		draw_colored_polygon(hull, Color("5a3a1e"))
		draw_line(p + Vector2(0, 2), p + Vector2(0, -10), INK, 2.0)
		draw_colored_polygon(PackedVector2Array([p + Vector2(1, -10), p + Vector2(9, 0), p + Vector2(1, 0)]), Color("f1e6cc"))
	else:
		draw_circle(p + Vector2(0, 1), 9.0, Color(0, 0, 0, 0.25))
		draw_circle(p + Vector2(0, -6), 4.0, Color("e0b98a"))
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -3), p + Vector2(6, 8), p + Vector2(-6, 8)]), Color("a8452f"))
		draw_line(p + Vector2(7, 8), p + Vector2(7, -8), INK, 2.0)
	draw_arc(p, 14.0, 0, TAU, 24, GOLD, 2.0)


func _text(text: String, pos: Vector2, font_size: int, color: Color, centered: bool = false, outline: bool = false) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := pos - Vector2(w * 0.5, 0) if centered else pos
	if outline or centered:
		draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(LAND, 0.9))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
