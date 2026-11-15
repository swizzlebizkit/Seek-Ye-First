class_name Blinker
extends Control
## The small blinking triangle that says "press to continue".

var _t := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(18, 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 5.0))


func _draw() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(1, 1), Vector2(15, 1), Vector2(8, 10)]), UiTheme.GOLD)
