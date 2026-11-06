class_name UiTheme
extends RefCounted
## Shared helpers for building the mining-terminal UI in code.

const PANEL := "res://assets/ui/panel_sheet.png"
const BUTTON := "res://assets/ui/button_sheet.png"
const ICONS := "res://assets/ui/icon_sheet.png"
const CORNER := 24

static func font() -> FontFile:
	if ResourceLoader.exists("res://assets/font/font.fnt"):
		return load("res://assets/font/font.fnt")
	return null

static func theme() -> Theme:
	var t := Theme.new()
	var f := font()
	if f:
		t.default_font = f
		t.default_font_size = 15
	return t

static func panel_style(kind: int = 0) -> StyleBoxTexture:
	var st := StyleBoxTexture.new()
	var at := AtlasTexture.new()
	at.atlas = load(PANEL)
	at.region = Rect2(kind * CORNER * 2, 0, CORNER * 2, CORNER * 2)
	st.texture = at
	st.set_texture_margin_all(CORNER)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	return st

static func button_style(state: int) -> StyleBoxTexture:
	var st := StyleBoxTexture.new()
	var at := AtlasTexture.new()
	at.atlas = load(BUTTON)
	at.region = Rect2(state * CORNER * 2, 0, CORNER * 2, CORNER * 2)
	st.texture = at
	st.set_texture_margin_all(CORNER)
	st.content_margin_left = 20
	st.content_margin_right = 20
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	return st

static func icon_tex(index: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = load(ICONS)
	at.region = Rect2(index * 16, 0, 16, 16)
	return at

static func make_button(text: String, min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = theme()
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_stylebox_override("normal", button_style(0))
	b.add_theme_stylebox_override("hover", button_style(1))
	b.add_theme_stylebox_override("pressed", button_style(2))
	b.add_theme_stylebox_override("focus", button_style(1))
	b.add_theme_stylebox_override("disabled", button_style(2))
	b.add_theme_color_override("font_color", Color(0.87, 0.91, 0.96))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.82, 0.42))
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.48, 0.55))
	if min_width > 0.0:
		b.custom_minimum_size = Vector2(min_width, 44)
	b.focus_mode = Control.FOCUS_ALL
	return b

static func make_label(text: String, size: int = 15, color: Color = Color(0.87, 0.91, 0.96)) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = theme()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func make_panel(kind: int = 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = theme()
	p.add_theme_stylebox_override("panel", panel_style(kind))
	return p

static func heading(text: String, size: int = 30) -> Label:
	var l := make_label(text, size, Color(1.0, 0.78, 0.36))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
