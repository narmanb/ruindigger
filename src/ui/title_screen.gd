extends Control
## Title: animated dusk skyline, logo, start/settings/quit.

var menu: VBoxContainer
var t := 0.0
var sky: TextureRect
var far: TextureRect
var mid: TextureRect
var embers: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	Audio.music("amb_outpost")
	sky = _layer("outpost_sky.png", 0)
	far = _layer("outpost_far.png", 120)
	mid = _layer("outpost_mid.png", 200)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.05, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	for i in 40:
		embers.append(Vector3(randf() * 800.0, randf() * 360.0, randf_range(8.0, 30.0)))
	var logo := Logo.new()
	logo.anchor_left = 0.5
	logo.anchor_right = 0.5
	logo.offset_left = -220
	logo.offset_right = 220
	logo.offset_top = 34
	logo.offset_bottom = 120
	add_child(logo)
	menu = VBoxContainer.new()
	menu.add_theme_constant_override("separation", 6)
	menu.anchor_left = 0.5
	menu.anchor_right = 0.5
	menu.anchor_top = 1.0
	menu.anchor_bottom = 1.0
	menu.offset_left = -80
	menu.offset_right = 80
	menu.offset_top = -170
	menu.offset_bottom = -40
	add_child(menu)
	var start := UIKit.button("START", func() -> void: Game.goto("outpost"), 160)
	menu.add_child(start)
	menu.add_child(UIKit.button("SETTINGS", _settings, 160))
	if OS.get_name() not in ["Android", "iOS", "Web"]:
		menu.add_child(UIKit.button("QUIT", func() -> void: get_tree().quit(), 160))
	var st := Progress.stats
	var info := UIKit.label("Credits %d   Runs %d   Extractions %d   Relics %d   Best depth %dm" % [Progress.credits, st.get("runs", 0), st.get("extractions", 0), st.get("relics", 0), st.get("best_depth", 0)], 9, UIKit.MUTED)
	info.anchor_left = 0.0
	info.anchor_right = 1.0
	info.anchor_top = 1.0
	info.anchor_bottom = 1.0
	info.offset_top = -20
	info.offset_bottom = -6
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(info)
	var ver := UIKit.label("v" + str(ProjectSettings.get_setting("application/config/version")), 8, UIKit.MUTED)
	ver.position = Vector2(6, 4)
	add_child(ver)
	await get_tree().process_frame
	start.grab_focus()


func _layer(n: String, y: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = load("res://assets/gen/" + n)
	r.stretch_mode = TextureRect.STRETCH_TILE
	r.anchor_right = 1.0
	r.offset_top = y
	r.offset_right = 640
	r.offset_bottom = y + r.texture.get_height()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _process(d: float) -> void:
	t += d
	far.position.x = -fmod(t * 4.0, 640.0)
	mid.position.x = -fmod(t * 9.0, 640.0)
	queue_redraw()


func _draw() -> void:
	for e in embers:
		var x := fmod(e.x + t * e.z, size.x + 20.0)
		var y := fmod(e.y - t * e.z * 0.6 + 400.0, 380.0)
		var a := 0.4 + 0.4 * sin(t * 3.0 + e.x)
		draw_rect(Rect2(x, y, 1, 1), Color(1.0, 0.7, 0.35, a))


func _settings() -> void:
	menu.visible = false
	var sp := SettingsPanel.new()
	add_child(sp)
	sp.anchor_left = 0.5
	sp.anchor_top = 0.5
	sp.anchor_right = 0.5
	sp.anchor_bottom = 0.5
	sp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sp.grow_vertical = Control.GROW_DIRECTION_BOTH
	sp.closed.connect(func() -> void:
		menu.visible = true
		menu.get_child(0).grab_focus())


class Logo extends Control:
	var t := 0.0

	func _process(d: float) -> void:
		t += d
		queue_redraw()

	func _draw() -> void:
		var f := UIKit.font_head()
		var title := "RUIN DIGGER"
		var fs := 44
		var w := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := (size.x - w) * 0.5
		for o in [Vector2(3, 3), Vector2(2, 2)]:
			draw_string(f, Vector2(x, 52) + o, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.12, 0.04, 0.02))
		draw_string(f, Vector2(x, 52), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("f5a23a"))
		# glint sweeping across the logo
		var gx := fmod(t * 120.0, w + 200.0) - 100.0
		draw_string(f, Vector2(x, 52), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.9, 0.6, 0.0))
		draw_rect(Rect2(x + gx, 18, 6, 40), Color(1.0, 0.95, 0.8, 0.18))
		var tag := "Break the ground. Wake what lies below. Get out richer."
		var tw := UIKit.font_body().get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(UIKit.font_body(), Vector2((size.x - tw) * 0.5, 76), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e9ddc8"))
		draw_rect(Rect2((size.x - 200) * 0.5, 82, 200, 1), Color(1.0, 0.7, 0.3, 0.5))
