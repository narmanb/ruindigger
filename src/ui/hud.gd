extends CanvasLayer
## Industrial diagnostic HUD: hull/heat/cargo/charges, minimap, depth,
## objective compass, toasts, banners, context prompts and touch controls.

var mine: Node
var root: Control
var diag: Diag
var minimap: Minimap
var depth_panel: DepthPanel
var orders_panel: OrdersPanel
var panels: Control
var toast_label: Label
var banner_label: Label
var hint_label: Label
var prompt_label: Label
var touch: TouchControls
var pause_btn: Button
var cargo_btn: Button
var fps_label: Label
var ladder_label: Label
var _toast_t := 0.0
var _banner_t := 0.0
var _hint_t := 0.0
var _cargo_pulse := 0.0
var _scaf_pulse := 0.0
var map_screen: Node
var cargo_screen: CargoScreen


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	# the panels sit inside the display's safe area (cutouts, rounded corners)
	panels = Control.new()
	panels.set_anchors_preset(Control.PRESET_FULL_RECT)
	panels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panels)
	diag = Diag.new()
	diag.hud = self
	diag.position = Vector2(6, 6)
	diag.size = Vector2(196, 114)
	panels.add_child(diag)
	var cargo_hit := Control.new()
	cargo_hit.position = Vector2(6, 36)
	cargo_hit.size = Vector2(196, 14)
	cargo_hit.tooltip_text = "Cargo manifest (I)"
	cargo_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	cargo_hit.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			open_cargo())
	panels.add_child(cargo_hit)
	cargo_screen = CargoScreen.new()
	cargo_screen.mine = mine
	add_child(cargo_screen)
	var mframe := FrameDecor.new()
	mframe.anchor_left = 0.5
	mframe.anchor_right = 0.5
	mframe.offset_left = -64
	mframe.offset_right = 64
	mframe.offset_top = 4
	mframe.offset_bottom = 62
	panels.add_child(mframe)
	minimap = Minimap.new()
	minimap.setup(mine)
	minimap.anchor_left = 0.5
	minimap.anchor_right = 0.5
	minimap.offset_left = -59
	minimap.offset_right = 59
	minimap.offset_top = 9
	minimap.offset_bottom = 55
	panels.add_child(minimap)
	# tap the minimap to open the full survey map
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			open_map())
	map_screen = load("res://src/ui/map_screen.gd").new()
	map_screen.mine = mine
	add_child(map_screen)
	depth_panel = DepthPanel.new()
	depth_panel.hud = self
	depth_panel.anchor_left = 1.0
	depth_panel.anchor_right = 1.0
	depth_panel.offset_left = -190
	depth_panel.offset_right = -38
	depth_panel.offset_top = 4
	depth_panel.offset_bottom = 54
	panels.add_child(depth_panel)
	orders_panel = OrdersPanel.new()
	orders_panel.hud = self
	orders_panel.anchor_left = 1.0
	orders_panel.anchor_right = 1.0
	orders_panel.offset_left = -212
	orders_panel.offset_right = -4
	orders_panel.offset_top = 84
	orders_panel.offset_bottom = 132
	orders_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panels.add_child(orders_panel)
	pause_btn = _skin_button("", "pause", func() -> void: mine.pause_menu.open())
	pause_btn.offset_left = -34
	pause_btn.offset_right = -4
	pause_btn.offset_top = 4
	pause_btn.offset_bottom = 34
	panels.add_child(pause_btn)
	cargo_btn = _skin_button("CARGO", "crate", open_cargo)
	cargo_btn.offset_left = -112
	cargo_btn.offset_right = -4
	cargo_btn.offset_top = 56
	cargo_btn.offset_bottom = 80
	panels.add_child(cargo_btn)
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
	fps_label.position = Vector2(8, 122)
	panels.add_child(fps_label)
	ladder_label = UIKit.label("LADDER ATTACHED", 10, UIKit.TEAL, true)
	ladder_label.position = Vector2(8, 138)
	ladder_label.add_theme_stylebox_override("normal", UIKit.panel_box(UIKit.TEAL))
	ladder_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ladder_label.visible = false
	panels.add_child(ladder_label)
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)
	touch = TouchControls.new()
	touch.mine = mine
	root.add_child(touch)


## Keep the panels clear of display cutouts: inset by the OS safe area.
func _apply_safe_area() -> void:
	var vp := get_viewport().get_visible_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	var l := 0.0
	var r := 0.0
	var t := 0.0
	if win.x > 0 and safe.size.x > 0:
		var k := vp.x / float(win.x)
		l = clampf(safe.position.x * k, 0.0, 60.0)
		r = clampf((win.x - safe.end.x) * k, 0.0, 60.0)
		t = clampf(safe.position.y * k, 0.0, 30.0)
	panels.offset_left = l
	panels.offset_right = -r
	panels.offset_top = t


## A HUD button drawn with the metal skin (icon + optional label).
func _skin_button(text: String, icon: String, cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.flat = true
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.pressed.connect(cb)
	var face := SkinFace.new()
	face.btn = b
	face.text = text
	face.icon_kind = icon
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(face)
	return b


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


func pulse_scaffold() -> void:
	_scaf_pulse = 1.0


func open_map() -> void:
	if mine.ending or get_tree().paused:
		return
	map_screen.open()


func open_cargo() -> void:
	if not mine.ending and not get_tree().paused:
		cargo_screen.open()


func _process(delta: float) -> void:
	_toast_t -= delta
	_banner_t -= delta
	_hint_t -= delta
	_cargo_pulse = maxf(0.0, _cargo_pulse - delta * 3.0)
	_scaf_pulse = maxf(0.0, _scaf_pulse - delta * 2.0)
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
		var sd: SandSim = mine.get("sand")
		if sd and not sd.active.is_empty():
			fps_label.text += "  SAND %d (%.1f ms)" % [sd.active.size(), sd.last_us / 1000.0]
	ladder_label.visible = mine.player != null and mine.player.on_ladder and not mine.player.dead and not mine.ending
	diag.queue_redraw()
	depth_panel.queue_redraw()
	orders_panel.queue_redraw()
	for b in [cargo_btn, pause_btn]:
		if b.get_child_count() > 0:
			b.get_child(0).queue_redraw()


## The dive's orders, top right under the cargo button.
class OrdersPanel extends Control:
	var hud: Node

	func _draw() -> void:
		var orders: Array = Game.run.get("orders", [])
		if orders.is_empty():
			return
		var h := 10.0 + orders.size() * 13.0
		HudSkin.frame(self, Rect2(0, 0, size.x, h), HudSkin.ORANGE, false, 5.0)
		for i in orders.size():
			var o: Dictionary = orders[i]
			var met := Orders.satisfied(o, Game.run)
			var y := 15.0 + i * 13.0
			var col: Color = HudSkin.YELLOW if met else HudSkin.TEXT
			draw_rect(Rect2(9, y - 7, 7, 7), col, false, 1.0)
			if met:
				draw_rect(Rect2(11, y - 5, 3, 3), col)
			HudSkin.label(self, Vector2(21, y), String(o["text"]).to_upper(), 8, col)
			var pt := Orders.progress_text(o, Game.run)
			var f := UIKit.font_head()
			var w := f.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			HudSkin.label(self, Vector2(size.x - 9 - w, y), pt, 8, HudSkin.YELLOW if met else HudSkin.TEXT)


## Draws a metal frame behind something else (the minimap).
class FrameDecor extends Control:
	var accent := HudSkin.ORANGE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		HudSkin.frame(self, Rect2(Vector2.ZERO, size), accent, true, 6.0)


## The face of a skinned HUD button: frame, icon, label, pressed state.
class SkinFace extends Control:
	var btn: Button
	var text := ""
	var icon_kind := ""

	func _draw() -> void:
		var pressed := btn != null and btn.is_pressed()
		var r := Rect2(Vector2.ZERO, size)
		HudSkin.frame(self, r, HudSkin.ORANGE, false, 5.0)
		if pressed:
			draw_rect(r.grow(-4.0), Color(1, 1, 1, 0.08))
		var push := Vector2(0, 1) if pressed else Vector2.ZERO
		if text == "":
			HudSkin.icon(self, icon_kind, r.get_center() + push, size.y * 0.5)
			return
		HudSkin.icon(self, icon_kind, Vector2(17, size.y * 0.5) + push, size.y * 0.55)
		HudSkin.label(self, Vector2(size.x * 0.5 + 9, size.y * 0.5 + 5) + push, text, 11, HudSkin.TEXT, true)


class Diag extends Control:
	var hud: Node
	const ROW := 14.0
	const Y0 := 18.0
	const BX := 52.0
	const BW := 100.0

	func _draw() -> void:
		var pl: Player = hud.mine.player
		if pl == null:
			return
		HudSkin.frame(self, Rect2(Vector2.ZERO, size))
		var t := Time.get_ticks_msec() / 1000.0
		var flash_ok := not Settings.reduced_flashing()
		_row(0, "HULL", pl.hp / pl.max_hp, HudSkin.RED, "%d" % int(ceil(pl.hp)), pl.hp / pl.max_hp < 0.3 and int(t * 4) % 2 == 0 and flash_ok)
		var hcol := HudSkin.ORANGE.lerp(HudSkin.RED, pl.heat / pl.heat_cap)
		if pl.overheated:
			hcol = Color(1, 1, 1) if int(t * 6) % 2 == 0 and flash_ok else HudSkin.RED
		_row(1, "HEAT", pl.heat / pl.heat_cap, hcol, "VENT" if pl.overheated else "%d%%" % int(pl.heat / pl.heat_cap * 100.0), false)
		var cap: int = hud.mine.cargo_cap()
		var n: int = Game.cargo_count()
		var ccol := HudSkin.GREEN.lerp(Color(1, 1, 1), hud._cargo_pulse)
		if n >= cap:
			ccol = HudSkin.ORANGE
		_row(2, "CARGO", float(n) / cap, ccol, "%d/%d" % [n, cap], false)
		# charges as red pips, lures beside them
		var y := Y0 + 3.0 * ROW
		HudSkin.label(self, Vector2(10, y), "CHRG", 9, HudSkin.MUTED)
		var ch: int = Game.run.get("charges", 0)
		for i in maxi(ch, 3):
			var r := Rect2(BX + i * 10, y - 8, 8, 9)
			if i < ch:
				draw_rect(r, HudSkin.RED)
				draw_rect(Rect2(r.position, Vector2(8, 2)), HudSkin.RED.lightened(0.45))
			else:
				draw_rect(r, HudSkin.MUTED, false, 1.0)
		# lures: cyan pips, like the charges
		var lures := int(Game.run.get("lures", 0))
		var lx := BX + maxi(ch, 3) * 10 + 10
		HudSkin.label(self, Vector2(lx, y), "LURE", 9, HudSkin.MUTED)
		lx += 34
		for i in maxi(lures, Balance.LURES_PER_RUN):
			var lr := Rect2(lx + i * 10, y - 8, 8, 9)
			if i < lures:
				draw_rect(lr, HudSkin.CYAN.darkened(0.15))
				draw_rect(Rect2(lr.position, Vector2(8, 2)), HudSkin.CYAN.lightened(0.4))
			else:
				draw_rect(lr, HudSkin.MUTED, false, 1.0)
		var scap: int = hud.mine.scaffold_cap()
		var sn: int = Game.run.get("scaffold", 0)
		var scol := HudSkin.YELLOW.lerp(HudSkin.RED, hud._scaf_pulse)
		_row(4, "SCAF", float(sn) / scap, scol, "%d" % sn, hud._scaf_pulse > 0.5 and int(t * 8) % 2 == 0)
		var pv: float = float(Game.run.get("pressure", 0.0))
		var pt := 0
		for k in Balance.PRESSURE_TIERS.size():
			if pv >= Balance.PRESSURE_TIERS[k]:
				pt = k + 1
		var pcol: Color = [HudSkin.GREEN, HudSkin.YELLOW, HudSkin.ORANGE, HudSkin.RED][pt]
		_row(5, "PRES", pv / 100.0, pcol, ["CALM", "STIR", "UNST", "COLL"][pt], pt == 3 and int(t * 3) % 2 == 0 and flash_ok)
		# gadgets: "SONAR . READY . MAGNET"
		var lo: Dictionary = Game.run.get("loadout", {})
		var gid := String(lo.get("active", ""))
		y = Y0 + 6.0 * ROW
		HudSkin.label(self, Vector2(10, y), "GADG", 9, HudSkin.MUTED)
		if gid != "":
			var cd := float(Game.run.get("gadget_cd", 0.0))
			var f := UIKit.font_head()
			var x := BX
			var gname := String(Balance.GADGETS[gid]["name"])
			HudSkin.label(self, Vector2(x, y), gname, 9, HudSkin.CYAN)
			x += f.get_string_size(gname, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 4.0
			draw_rect(Rect2(x, y - 4, 2, 2), HudSkin.CYAN)
			x += 6.0
			var st := "READY" if cd <= 0.0 else "%dS" % ceili(cd)
			HudSkin.label(self, Vector2(x, y), st, 9, HudSkin.YELLOW if cd <= 0.0 else HudSkin.MUTED)
			x += f.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 4.0
			var pid := String(lo.get("passive", ""))
			if pid != "":
				draw_circle(Vector2(x + 1, y - 3), 1.5, HudSkin.YELLOW)
				HudSkin.label(self, Vector2(x + 6, y), String(Balance.GADGETS[pid]["name"]), 9, HudSkin.YELLOW)
		if Game.run.get("relic", false):
			var rp := Vector2(size.x - 14, Y0 + 3.0 * ROW - 4.0)
			draw_colored_polygon(PackedVector2Array([rp + Vector2(0, -6), rp + Vector2(5, 0), rp + Vector2(0, 6), rp + Vector2(-5, 0)]), Color(0.4, 1.0, 1.0, 0.8 + 0.2 * sin(t * 5.0)))

	func _row(i: int, name: String, frac: float, col: Color, txt: String, blink: bool) -> void:
		var y := Y0 + i * ROW
		HudSkin.label(self, Vector2(10, y), name, 9, HudSkin.MUTED)
		HudSkin.meter(self, Rect2(BX, y - 8, BW, 9), frac, col, 12, blink)
		HudSkin.label(self, Vector2(BX + BW + 6, y), txt, 9, HudSkin.TEXT)


class DepthPanel extends Control:
	var hud: Node

	func _draw() -> void:
		var mine: Node = hud.mine
		var pl: Player = mine.player
		if pl == null:
			return
		HudSkin.frame(self, Rect2(Vector2.ZERO, size))
		var depth := int(maxf(0.0, pl.global_position.y / Balance.CELL - 9.0 + mine.depth_offset) * Balance.METERS_PER_CELL)
		HudSkin.label(self, Vector2(10, 16), "DEPTH", 9, HudSkin.MUTED)
		HudSkin.label(self, Vector2(56, 17), "%d M" % depth, 13, HudSkin.ORANGE)
		var s: int = maxi(0, mine.grid.get_stratum(int(pl.global_position.x / Balance.CELL), int(pl.global_position.y / Balance.CELL)))
		var zc: Color = Balance.ZONE_COLORS[s]
		# a small zone gem before the name
		var gp := Vector2(13, 26)
		draw_colored_polygon(PackedVector2Array([gp + Vector2(0, -4), gp + Vector2(3, 0), gp + Vector2(0, 4), gp + Vector2(-3, 0)]), zc)
		HudSkin.label(self, Vector2(20, 30), Balance.STRATUM_NAMES[s], 9, zc.lightened(0.15))
		# objective compass
		var target: Vector2
		var label := ""
		var col := UIKit.TEAL
		if mine.gate and mine.engine and not mine.gate.powered:
			# no power yet: the way out runs through the Thermal Plant
			target = mine.engine.global_position
			label = "PLANT"
			col = Color(1.0, 0.6, 0.25)
		elif mine.gate:
			# the deep stage has one way out
			target = mine.gate.global_position
			label = "GATE"
			col = Balance.ZONE_COLORS[Balance.Z_FIRST]
		elif not Game.run.get("relic", false) and mine.relic:
			target = mine.relic.global_position
			label = "RELIC"
			col = Color(0.4, 1.0, 1.0)
		else:
			var best: Node2D = null
			var bd := INF
			for l in mine.lifts:
				if not l.active and not String(l.id).begins_with("relay"):
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
		var c := Vector2(16, 39)
		var dir := to.normalized()
		var tip := c + dir * 6.0
		draw_colored_polygon(PackedVector2Array([tip, c + dir.rotated(2.5) * 5.0, c + dir.rotated(-2.5) * 5.0]), col)
		HudSkin.label(self, Vector2(28, 43), "%s %dM" % [label, dist], 9, col)
