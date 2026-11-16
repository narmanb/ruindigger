class_name UIKit
extends RefCounted
## Shared look for every menu: dark terminal panels, amber/teal readouts,
## chunky focusable buttons that work with touch, mouse and gamepad.

const AMBER := Color("ffb347")
const AMBER_DIM := Color("8a5a22")
const TEAL := Color("6ff3d0")
const RED := Color("ff5a5a")
const TEXT := Color("e9ddc8")
const MUTED := Color("8c8296")
const PANEL := Color(0.07, 0.055, 0.09, 0.94)
const PANEL_EDGE := Color("3a2f52")

static var _theme: Theme
static var _font_body: Font
static var _font_head: Font


static func font_body() -> Font:
	if _font_body == null:
		var f := FontVariation.new()
		f.base_font = load("res://assets/fonts/PixelifySans.ttf")
		_font_body = f
	return _font_body


static func font_head() -> Font:
	if _font_head == null:
		_font_head = load("res://assets/fonts/Silkscreen-Regular.ttf")
	return _font_head


static func panel_box(edge: Color = PANEL_EDGE, bg: Color = PANEL) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(2)
	s.set_corner_radius_all(0)
	s.corner_detail = 1
	s.set_content_margin_all(8)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 3
	s.shadow_offset = Vector2(2, 2)
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font_body()
	t.default_font_size = 11
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.1, 0.16)
	normal.border_color = AMBER_DIM
	normal.set_border_width_all(1)
	normal.border_width_bottom = 3
	normal.set_content_margin_all(6)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	var hover := normal.duplicate()
	hover.bg_color = Color(0.2, 0.14, 0.12)
	hover.border_color = AMBER
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.3, 0.18, 0.08)
	pressed.border_width_bottom = 1
	pressed.content_margin_top = 8
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = TEAL
	focus.set_border_width_all(2)
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.09, 0.08, 0.1)
	disabled.border_color = Color(0.25, 0.22, 0.28)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("focus", cls, focus)
		t.set_stylebox("disabled", cls, disabled)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, AMBER)
		t.set_color("font_pressed_color", cls, AMBER)
		t.set_color("font_focus_color", cls, TEAL)
		t.set_color("font_disabled_color", cls, MUTED)
		t.set_font_size("font_size", cls, 12)
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.15, 0.12, 0.18)
	slider_bg.content_margin_top = 3
	slider_bg.content_margin_bottom = 3
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = AMBER_DIM
	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.1, 0.15)
	t.set_stylebox("scroll", "VScrollBar", sb)
	var grab := StyleBoxFlat.new()
	grab.bg_color = AMBER_DIM
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	_theme = t
	return t


static func label(text: String, size: int = 11, color: Color = TEXT, head: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if head:
		l.add_theme_font_override("font", font_head())
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


static func button(text: String, cb: Callable, min_w: float = 150.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 26)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void:
		Audio.play("ui_click", -4.0)
		cb.call())
	return b


static func header(text: String) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var bar := ColorRect.new()
	bar.color = AMBER
	bar.custom_minimum_size = Vector2(4, 12)
	box.add_child(bar)
	box.add_child(label(text, 12, AMBER, true))
	return box


## Animated diagnostic accent: a scanning bar with tick marks.
class Scanline extends Control:
	var t := 0.0
	var color := TEAL

	func _ready() -> void:
		custom_minimum_size = Vector2(80, 4)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		t += d
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		draw_rect(Rect2(0, 1, w, 1), Color(color.r, color.g, color.b, 0.25))
		for i in range(0, int(w), 8):
			draw_rect(Rect2(i, 0, 1, 3), Color(color.r, color.g, color.b, 0.35))
		var x := fmod(t * 60.0, w + 30.0) - 30.0
		draw_rect(Rect2(x, 0, 30, 3), Color(color.r, color.g, color.b, 0.7))


static func touch_scrollbar(scroll: ScrollContainer) -> void:
	# Match the proven finger-sized scrollbar in Settings.
	var bar := scroll.get_v_scroll_bar()
	var track := StyleBoxFlat.new()
	track.bg_color = UIKit.PANEL_EDGE
	track.content_margin_left = 16
	track.content_margin_right = 16
	bar.add_theme_stylebox_override("scroll", track)
	var handle := StyleBoxFlat.new()
	handle.bg_color = UIKit.AMBER
	handle.set_content_margin_all(16)
	handle.content_margin_top = 20
	handle.content_margin_bottom = 20
	for style in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(style, handle)
