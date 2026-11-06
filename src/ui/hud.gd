extends CanvasLayer
## Industrial diagnostic HUD: hull/heat/cargo/charges, minimap, depth,
## objective compass, toasts, banners, context prompts and touch controls.

var mine: Node
var root: Control
var diag: Diag
var minimap: Minimap
var depth_panel: DepthPanel
var toast_label: Label
var banner_label: Label
var hint_label: Label
var prompt_label: Label
var touch: TouchControls
var pause_btn: Button
var fps_label: Label
var _toast_t := 0.0
var _banner_t := 0.0
var _hint_t := 0.0
var _cargo_pulse := 0.0


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	diag = Diag.new()
	diag.hud = self
	diag.position = Vector2(6, 6)
	diag.size = Vector2(150, 62)
	root.add_child(diag)
	minimap = Minimap.new()
	minimap.setup(mine)
	minimap.anchor_left = 0.5
	minimap.anchor_right = 0.5
	minimap.offset_left = -56
	minimap.offset_right = 56
	minimap.offset_top = 6
	minimap.offset_bottom = 58
	root.add_child(minimap)
	depth_panel = DepthPanel.new()
	depth_panel.hud = self
	depth_panel.anchor_left = 1.0
	depth_panel.anchor_right = 1.0
	depth_panel.offset_left = -176
	depth_panel.offset_right = -34
	depth_panel.offset_top = 6
	depth_panel.offset_bottom = 50
	root.add_child(depth_panel)
	pause_btn = Button.new()
	pause_btn.text = "II"
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.anchor_left = 1.0
	pause_btn.anchor_right = 1.0
	pause_btn.offset_left = -30
	pause_btn.offset_right = -6
	pause_btn.offset_top = 6
	pause_btn.offset_bottom = 30
	pause_btn.add_theme_font_override("font", UIKit.font_head())
	pause_btn.pressed.connect(func() -> void: mine.pause_menu.open())
	root.add_child(pause_btn)
	toast_label = _center_label(13, UIKit.TEXT, 66)
	banner_label = _center_label(24, UIKit.AMBER, 130, true)
	hint_label = _center_label(11, UIKit.TEAL, 0)
	hint_label.anchor_top = 1.0
	hint_label.anchor_bottom = 1.0
	hint_label.offset_top = -40
	hint_label.offset_bottom = -24
	prompt_label = _center_label(12, UIKit.AMBER, 0, true)
	prompt_label.anchor_top = 1.0
	prompt_label.anchor_bottom = 1.0
	prompt_label.offset_top = -22
	prompt_label.offset_bottom = -6
	fps_label = UIKit.label("", 9, UIKit.MUTED)
	fps_label.position = Vector2(8, 70)
	root.add_child(fps_label)
	touch = TouchControls.new()
	touch.mine = mine
	root.add_child(touch)


func _center_label(size: int, col: Color, top: float, head: bool = false) -> Label:
	var l := UIKit.label("", size, col, head)
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.offset_top = top
	l.offset_bottom = top + size + 8
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	root.add_child(l)
	return l


func toast(text: String) -> void:
	toast_label.text = text
	_toast_t = 2.6


func banner(text: String) -> void:
	banner_label.text = text
	_banner_t = 2.2


func hint(text: String) -> void:
	hint_label.text = text
	_hint_t = 6.0


func pulse_cargo() -> void:
	_cargo_pulse = 1.0


func _process(delta: float) -> void:
	_toast_t -= delta
	_banner_t -= delta
	_hint_t -= delta
	_cargo_pulse = maxf(0.0, _cargo_pulse - delta * 3.0)
	toast_label.modulate.a = clampf(_toast_t * 2.0, 0.0, 1.0)
	banner_label.modulate.a = clampf(_banner_t * 1.5, 0.0, 1.0)
	hint_label.modulate.a = clampf(_hint_t, 0.0, 1.0)
	var it: Dictionary = mine.nearest_interactable(mine.player) if mine.player else {}
	if not it.is_empty() and not touch.visible:
		var key := "Y" if InputSetup.last_device == "gamepad" else "E"
		prompt_label.text = "[%s] %s" % [key, it["label"]]
		prompt_label.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 150.0)
	else:
		prompt_label.modulate.a = 0.0
	fps_label.visible = Settings.get_value("show_fps")
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	diag.queue_redraw()
	depth_panel.queue_redraw()


class Diag extends Control:
	var hud: Node

	func _draw() -> void:
		var pl: Player = hud.mine.player
		if pl == null:
			return
		var f := UIKit.font_head()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.04, 0.07, 0.78))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.28, 0.5), false, 1.0)
		draw_rect(Rect2(0, 0, 3, size.y), UIKit.AMBER)
		var t := Time.get_ticks_msec() / 1000.0
		_bar(f, 8, 5, "HULL", pl.hp / pl.max_hp, Color("ff5a4a"), "%d" % int(ceil(pl.hp)), pl.hp / pl.max_hp < 0.3 and int(t * 4) % 2 == 0)
		var hcol := Color("ffb347").lerp(Color("ff3020"), pl.heat / pl.heat_cap)
		if pl.overheated:
			hcol = Color(1, 1, 1) if int(t * 6) % 2 == 0 and not Settings.reduced_flashing() else Color("ff3020")
		_bar(f, 8, 19, "HEAT", pl.heat / pl.heat_cap, hcol, "VENT" if pl.overheated else "%d%%" % int(pl.heat / pl.heat_cap * 100.0), false)
		var cap: int = hud.mine.cargo_cap()
		var n: int = Game.cargo_count()
		var ccol := Color("6ff3d0").lerp(Color(1, 1, 1), hud._cargo_pulse)
		if n >= cap:
			ccol = Color("ffb347")
		_bar(f, 8, 33, "CARGO", float(n) / cap, ccol, "%d/%d" % [n, cap], false)
		# charges
		draw_string(f, Vector2(8, 55), "CHRG", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UIKit.MUTED)
		var ch: int = Game.run.get("charges", 0)
		for i in maxi(ch, 3):
			var r := Rect2(44 + i * 9, 48, 7, 8)
			if i < ch:
				draw_rect(r, Color("d8373f"))
				draw_rect(Rect2(r.position, Vector2(7, 2)), Color("ff8a8a"))
			else:
				draw_rect(r, Color(0.3, 0.25, 0.35), false, 1.0)
		if Game.run.get("relic", false):
			var rp := Vector2(size.x - 16, 50)
			draw_colored_polygon(PackedVector2Array([rp + Vector2(0, -6), rp + Vector2(5, 0), rp + Vector2(0, 6), rp + Vector2(-5, 0)]), Color(0.4, 1.0, 1.0, 0.8 + 0.2 * sin(t * 5.0)))

	func _bar(f: Font, x: float, y: float, name: String, frac: float, col: Color, txt: String, blink: bool) -> void:
		draw_string(f, Vector2(x, y + 8), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UIKit.MUTED)
		var bx := x + 36.0
		var bw := 74.0
		draw_rect(Rect2(bx, y + 1, bw, 8), Color(0.12, 0.1, 0.15))
		var segs := 12
		var filled := int(round(clampf(frac, 0.0, 1.0) * segs))
		for i in segs:
			var sr := Rect2(bx + 1 + i * (bw - 2) / segs, y + 2, (bw - 2) / segs - 1, 6)
			if i < filled:
				draw_rect(sr, col if not blink else col.lightened(0.5))
				draw_rect(Rect2(sr.position, Vector2(sr.size.x, 1)), col.lightened(0.35))
			else:
				draw_rect(sr, Color(0.2, 0.17, 0.24))
		draw_string(f, Vector2(bx + bw + 4, y + 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UIKit.TEXT)


class DepthPanel extends Control:
	var hud: Node

	func _draw() -> void:
		var mine: Node = hud.mine
		var pl: Player = mine.player
		if pl == null:
			return
		var f := UIKit.font_head()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.04, 0.07, 0.78))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.28, 0.5), false, 1.0)
		var depth := int(maxf(0.0, pl.global_position.y / Balance.CELL - 9.0) * Balance.METERS_PER_CELL)
		draw_string(f, Vector2(6, 11), "DEPTH", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UIKit.MUTED)
		draw_string(f, Vector2(44, 12), "%4d M" % depth, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.AMBER)
		var s := Balance.stratum_of_row(int(pl.global_position.y / Balance.CELL))
		draw_string(f, Vector2(6, 23), Balance.STRATUM_NAMES[s], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, [Color("e0a060"), Color("6ff3d0"), Color("b48cff")][s])
		# objective compass
		var target: Vector2
		var label := ""
		var col := UIKit.TEAL
		if not Game.run.get("relic", false) and mine.relic:
			target = mine.relic.global_position
			label = "RELIC"
			col = Color(0.4, 1.0, 1.0)
		else:
			var best: Node2D = null
			var bd := INF
			for l in mine.lifts:
				if not l.active and l.id != "relay":
					continue
				var d: float = l.global_position.distance_to(pl.global_position)
				if d < bd:
					bd = d
					best = l
			if best == null:
				return
			target = best.global_position
			label = "LIFT" if best.active else "RELAY?"
			col = Color(0.4, 1.0, 0.5) if best.active else Color(1.0, 0.6, 0.3)
		var to := target - pl.global_position
		var dist := int(to.length() / Balance.CELL * Balance.METERS_PER_CELL)
		var c := Vector2(14, 36)
		var dir := to.normalized()
		var tip := c + dir * 6.0
		draw_colored_polygon(PackedVector2Array([tip, c + dir.rotated(2.5) * 5.0, c + dir.rotated(-2.5) * 5.0]), col)
		draw_string(f, Vector2(26, 40), "%s %dM" % [label, dist], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
