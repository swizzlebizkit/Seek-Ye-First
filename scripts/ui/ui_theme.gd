class_name UiTheme
extends RefCounted
## Shared look for every screen: dark parchment panels with a gold rule, warm cream text.

const PARCHMENT := Color("2b2118")
const PARCHMENT_LIGHT := Color("3b2d20")
const BORDER := Color("c9ac6e")
const GOLD := Color("e8d29a")
const TEXT := Color("f1e6cc")
const MUTED := Color("b3a27c")
const DISABLED := Color("7d705a")


static func panel(alpha: float = 0.95) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(PARCHMENT, alpha)
	s.border_color = BORDER
	s.set_border_width_all(3)
	s.set_corner_radius_all(3)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s


static func label(text: String, size: int = 20, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func outlined(l: Label, outline_size: int = 5) -> Label:
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.04, 1))
	l.add_theme_constant_override("outline_size", outline_size)
	return l


static func style_button(b: Button, size: int = 22) -> void:
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", DISABLED)
	b.add_theme_stylebox_override("normal", _button_box(PARCHMENT, 1))
	b.add_theme_stylebox_override("hover", _button_box(PARCHMENT_LIGHT, 2))
	b.add_theme_stylebox_override("focus", _button_box(PARCHMENT_LIGHT, 2))
	b.add_theme_stylebox_override("pressed", _button_box(PARCHMENT_LIGHT, 2))
	b.add_theme_stylebox_override("disabled", _button_box(Color(PARCHMENT, 0.6), 1))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT


static func _button_box(bg: Color, border: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(bg, 0.92)
	s.border_color = BORDER if border > 1 else Color(BORDER, 0.35)
	s.set_border_width_all(border)
	s.set_corner_radius_all(2)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s
