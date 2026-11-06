extends Node2D
## Surface outpost hub: walk between the upgrade terminal, contract board,
## supply locker and the lift headframe. Reuses the real player + terrain.

const C := 16
const GW := 44
const GH := 24
const GROUND := 17

var grid: TerrainGrid
var view: TerrainView
var player: Player
var fx: Fx
var camera: Camera2D
var glow_root: Node2D
var hud: CanvasLayer
var ui_root: Control
var prompt: Label
var credits_label: Label
var toast_label: Label
var _toast_t := 0.0
var stations: Array = []   # {name, x, label}
var panel: Control
var lifts: Array = []
var relic = null
var enemies: Array = []
var ending := false
var _dust_t := 0.0


func _ready() -> void:
	Game.run = {"charges": 0, "cargo": {}}
	Audio.music("amb_outpost")
	_build()
	if not Progress.tutorial_done:
		toast("Welcome, digger. Walk to the LIFT to take your first contract.")


func _build() -> void:
	# sky + skyline parallax
	var sky := Sprite2D.new()
	sky.texture = load("res://assets/gen/outpost_sky.png")
	sky.centered = false
	var sky_p := Parallax2D.new()
	sky_p.scroll_scale = Vector2(0.05, 0.0)
	sky_p.repeat_size = Vector2(640, 0)
	sky_p.repeat_times = 3
	sky_p.z_index = -60
	sky_p.add_child(sky)
	add_child(sky_p)
	for layer in [["outpost_far.png", 0.2, 100.0], ["outpost_mid.png", 0.45, 150.0]]:
		var p := Parallax2D.new()
		p.scroll_scale = Vector2(layer[1], 0.0)
		p.repeat_size = Vector2(640, 0)
		p.repeat_times = 3
		p.z_index = -55
		var s := Sprite2D.new()
		s.texture = load("res://assets/gen/" + layer[0])
		s.centered = false
		s.position = Vector2(0, layer[2])
		p.add_child(s)
		add_child(p)
	var cm := CanvasModulate.new()
	cm.color = Color(0.92, 0.78, 0.72)
	add_child(cm)
	var gl := CanvasLayer.new()
	gl.layer = 1
	gl.follow_viewport_enabled = true
	add_child(gl)
	glow_root = Node2D.new()
	gl.add_child(glow_root)
	grid = TerrainGrid.new(GW, GH)
	for y in GH:
		for x in GW:
			var m := Cell.AIR
			if y >= GROUND or x == 0 or x == GW - 1:
				m = Cell.SOFT if y < GROUND + 3 else Cell.HARD
			if y >= GH - 1:
				m = Cell.BEDROCK
			grid.put(x, y, m)
			grid.set_flag(x, y, Cell.F_PROTECTED)
	# a few raised ledges and a dug pit near the lift
	for x in range(4, 9):
		grid.put(x, GROUND - 1, Cell.SOFT)
	for x in range(33, 39):
		grid.put(x, GROUND, Cell.AIR)
		grid.put(x, GROUND + 1, Cell.AIR)
		grid.set_flag(x, GROUND, Cell.F_DUG)
		grid.set_flag(x, GROUND + 1, Cell.F_DUG)
	for x in range(33, 39):
		grid.put(x, GROUND + 2, Cell.HARD)
	view = TerrainView.new()
	add_child(view)
	view.setup(grid, glow_root)
	fx = Fx.new()
	add_child(fx)
	fx.setup(glow_root)
	# props
	_prop("wheel", Vector2(36 * C, (GROUND - 8) * C))
	var frame := Line2D.new()
	for pt in [Vector2(32 * C, GROUND * C), Vector2(35 * C, (GROUND - 8) * C), Vector2(37 * C, (GROUND - 8) * C), Vector2(40 * C, GROUND * C)]:
		frame.add_point(pt)
	frame.width = 3.0
	frame.default_color = Color("5c2a14")
	frame.z_index = -2
	add_child(frame)
	var cable := Line2D.new()
	cable.add_point(Vector2(36 * C, (GROUND - 8) * C + 10))
	cable.add_point(Vector2(36 * C, (GROUND + 2) * C - 40))
	cable.width = 1.0
	cable.default_color = Color(0.15, 0.13, 0.16)
	add_child(cable)
	var lift := Sprite2D.new()
	lift.texture = SpriteDB.prop_texture("lift")
	lift.position = Vector2(36 * C, (GROUND + 2) * C - 20)
	add_child(lift)
	_prop("crate", Vector2(10 * C, GROUND * C - 7))
	_prop("crate", Vector2(11 * C, GROUND * C - 7))
	_prop("crate", Vector2(10.5 * C, GROUND * C - 20))
	_prop("pipe", Vector2(17 * C, GROUND * C - 5))
	_prop("cache", Vector2(27 * C, GROUND * C - 7))
	_prop("sign", Vector2(30 * C, GROUND * C - 6))
	_prop("pebbles", Vector2(22 * C, GROUND * C - 4))
	_prop("bones", Vector2(6 * C, (GROUND - 1) * C - 4))
	for lx in [7, 15.5, 24, 31]:
		_lamp_post(Vector2(lx * C, GROUND * C))
	_terminal(Vector2(13 * C, GROUND * C), "UPGRADES")
	_terminal(Vector2(20 * C, GROUND * C), "CONTRACTS")
	stations = [
		{"name": "upgrades", "x": 13 * C, "label": "UPGRADE TERMINAL"},
		{"name": "contracts", "x": 20 * C, "label": "CONTRACT BOARD"},
		{"name": "supply", "x": 27 * C, "label": "SUPPLY LOCKER"},
		{"name": "lift", "x": 36 * C, "label": "DESCEND"},
	]
	player = Player.new()
	player.mine = self
	player.grid = grid
	player.position = Vector2(4 * C, (GROUND - 1) * C - Player.HALF.y - 1)
	add_child(player)
	player.setup_stats()
	player.lamp.energy = 0.6
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.limit_left = 0
	camera.limit_right = GW * C
	camera.limit_bottom = GH * C - 8
	add_child(camera)
	_build_ui()


func _prop(n: String, p: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = SpriteDB.prop_texture(n)
	s.position = p
	add_child(s)


func _lamp_post(p: Vector2) -> void:
	var post := Line2D.new()
	post.add_point(p)
	post.add_point(p + Vector2(0, -40))
	post.add_point(p + Vector2(6, -42))
	post.width = 2.0
	post.default_color = Color("2a1a12")
	add_child(post)
	var lamp := Entities.Lamp.new()
	lamp.mine = self
	lamp.position = p + Vector2(6, -40)
	add_child(lamp)


func _terminal(p: Vector2, title: String) -> void:
	var n := TerminalProp.new()
	n.title = title
	n.position = p
	add_child(n)
	var g := Sprite2D.new()
	g.texture = load("res://assets/gen/glow.png")
	g.modulate = Color(0.3, 1.0, 0.8, 0.35)
	g.position = p + Vector2(0, -26)
	glow_root.add_child(g)


class TerminalProp extends Node2D:
	var title := ""
	var t := 0.0

	func _process(d: float) -> void:
		t += d
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(-14, -40, 28, 40), Color("2a2238"))
		draw_rect(Rect2(-14, -40, 28, 2), Color("7c6ca6"))
		draw_rect(Rect2(-11, -36, 22, 15), Color("08261f"))
		for i in 4:
			var w := 6.0 + fmod(t * 7.0 + i * 3.7, 12.0)
			draw_rect(Rect2(-9, -34 + i * 3, w, 1), Color(0.4, 1.0, 0.8, 0.8))
		draw_rect(Rect2(-14, -18, 28, 3), Color("574a78"))
		draw_rect(Rect2(-4, -12, 8, 12), Color("1a1424"))
		var f := UIKit.font_head()
		var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_rect(Rect2(-tw * 0.5 - 3, -54, tw + 6, 11), Color(0.05, 0.04, 0.07, 0.9))
		draw_string(f, Vector2(-tw * 0.5, -45), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("ffb347"))


func _build_ui() -> void:
	hud = CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = UIKit.theme()
	hud.add_child(ui_root)
	var top := PanelContainer.new()
	top.position = Vector2(6, 6)
	ui_root.add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	top.add_child(hb)
	hb.add_child(UIKit.label("OUTPOST 7", 11, UIKit.AMBER, true))
	credits_label = UIKit.label("", 11, UIKit.TEAL, true)
	hb.add_child(credits_label)
	prompt = UIKit.label("", 12, UIKit.AMBER, true)
	prompt.anchor_left = 0.0
	prompt.anchor_right = 1.0
	prompt.anchor_top = 1.0
	prompt.anchor_bottom = 1.0
	prompt.offset_top = -24
	prompt.offset_bottom = -8
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_root.add_child(prompt)
	toast_label = UIKit.label("", 12, UIKit.TEXT)
	toast_label.anchor_right = 1.0
	toast_label.offset_top = 40
	toast_label.offset_bottom = 60
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_root.add_child(toast_label)
	var touch := TouchControls.new()
	touch.mine = self
	ui_root.add_child(touch)
	var menu_btn := Button.new()
	menu_btn.text = "MENU"
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.anchor_left = 1.0
	menu_btn.anchor_right = 1.0
	menu_btn.offset_left = -60
	menu_btn.offset_right = -6
	menu_btn.offset_top = 6
	menu_btn.offset_bottom = 30
	menu_btn.pressed.connect(func() -> void: Game.goto("title"))
	ui_root.add_child(menu_btn)


func _process(delta: float) -> void:
	credits_label.text = "%d CR" % Progress.credits
	camera.global_position = player.global_position + Vector2(0, -30)
	_toast_t -= delta
	toast_label.modulate.a = clampf(_toast_t * 2.0, 0.0, 1.0)
	var it := nearest_interactable(player)
	if not it.is_empty() and panel == null:
		var key := "Y" if InputSetup.last_device == "gamepad" else ("USE" if InputSetup.last_device == "touch" else "E")
		prompt.text = "[%s] %s" % [key, it["label"]]
	else:
		prompt.text = ""
	_dust_t -= delta
	if _dust_t <= 0.0:
		_dust_t = 0.6
		fx.dust(Vector2(randf_range(0, GW * C), GROUND * C - 4), Color(0.9, 0.7, 0.5))


func _unhandled_input(event: InputEvent) -> void:
	if panel != null and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		_close_panel()
		get_viewport().set_input_as_handled()
	elif panel == null and event.is_action_pressed("pause"):
		Game.goto("title")


# --- the "mine" interface the Player expects -------------------------------
func drill_cell(c: Vector2i, _a: float, _t: int, _by: Player) -> void:
	var pos := grid.cell_center(c)
	fx.sparks(pos, (player.global_position - pos).normalized())
	Audio.play_at("hit_hard", pos, -10.0, 0.1, 0.1)


func drill_enemies(_r: Rect2, _d: float, _b: Player) -> void:
	pass


func noise(_p: Vector2, _r: float) -> void:
	pass


func shake(_a: float) -> void:
	pass


func spawn_charge(_p: Vector2, _v: Vector2) -> void:
	pass


func cargo_cap() -> int:
	return Balance.cargo_capacity(Progress.level("cargo"))


func toast(text: String) -> void:
	toast_label.text = text
	_toast_t = 3.0


func nearest_interactable(pl: Player) -> Dictionary:
	if panel != null:
		return {}
	for s in stations:
		if absf(pl.global_position.x - s["x"]) < 22.0:
			return {"kind": s["name"], "label": s["label"]}
	return {}


func player_interact(pl: Player) -> void:
	var it := nearest_interactable(pl)
	if it.is_empty():
		return
	Audio.play("ui_confirm", -4.0)
	match it["kind"]:
		"upgrades":
			_open_panel(_upgrade_panel())
		"contracts":
			_open_panel(_contract_panel())
		"supply":
			_open_panel(_supply_panel())
		"lift":
			_open_panel(_launch_panel())


func _open_panel(p: Control) -> void:
	_close_panel()
	panel = p
	player.controls_enabled = false
	ui_root.add_child(p)
	p.anchor_left = 0.5
	p.anchor_top = 0.5
	p.anchor_right = 0.5
	p.anchor_bottom = 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	await get_tree().process_frame
	var btn := _first_button(p)
	if btn:
		btn.grab_focus()


func _first_button(n: Node) -> Button:
	for c in n.get_children():
		if c is Button and not c.disabled:
			return c
		var b := _first_button(c)
		if b:
			return b
	return null


func _close_panel() -> void:
	if panel:
		panel.queue_free()
		panel = null
	player.controls_enabled = true


func _frame(title: String) -> Array:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(UIKit.header(title))
	v.add_child(UIKit.Scanline.new())
	return [p, v]


func _upgrade_panel() -> Control:
	var fr := _frame("UPGRADE TERMINAL")
	var v: VBoxContainer = fr[1]
	v.add_child(UIKit.label("CREDITS: %d" % Progress.credits, 11, UIKit.TEAL, true))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for track in Progress.TRACKS:
		var info: Dictionary = Balance.UPGRADES[track]
		var lv := Progress.level(track)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pips := ""
		for i in info["costs"].size():
			pips += "#" if i < lv else "-"
		left.add_child(UIKit.label("%s  [%s]" % [info["name"], pips], 11, UIKit.AMBER, true))
		var now_d: String = info["desc"][lv]
		var nxt: String = info["desc"][lv + 1] if lv + 1 < info["desc"].size() else "MAXED"
		left.add_child(UIKit.label("%s  ->  %s" % [now_d, nxt], 9, UIKit.TEXT))
		row.add_child(left)
		var cost := Progress.next_cost(track)
		var b := UIKit.button("MAX" if cost < 0 else "%d CR" % cost, func() -> void:
			if Progress.buy(track):
				Audio.play("ui_buy")
				_open_panel(_upgrade_panel())
			else:
				Audio.play("ui_deny"), 88)
		b.disabled = cost < 0 or Progress.credits < cost
		row.add_child(b)
		list.add_child(row)
	v.add_child(UIKit.button("CLOSE", _close_panel))
	return fr[0]


func _contract_panel() -> Control:
	var fr := _frame("CONTRACT BOARD")
	var v: VBoxContainer = fr[1]
	for i in Game.contract_offers.size():
		var c: Dictionary = Game.contract_offers[i]
		var chosen: bool = c == Game.contract
		var b := UIKit.button("%s%s  -  bonus %d CR" % ["> " if chosen else "", c["name"], c["reward"]], func() -> void:
			Game.choose_contract(i)
			Audio.play("ui_confirm")
			_open_panel(_contract_panel()), 360)
		v.add_child(b)
		v.add_child(UIKit.label("   " + c["desc"] + "   (seed %d)" % c["seed"], 9, UIKit.MUTED))
	v.add_child(UIKit.button("CLOSE", _close_panel))
	return fr[0]


func _supply_panel() -> Control:
	var fr := _frame("SUPPLY LOCKER")
	var v: VBoxContainer = fr[1]
	v.add_child(UIKit.label("Each contract includes %d free demolition charges." % Balance.CHARGES_FREE, 10))
	v.add_child(UIKit.label("Packed for next run: %d extra (max %d total)" % [Progress.charges, Balance.CHARGES_MAX], 10, UIKit.TEAL))
	var b := UIKit.button("BUY CHARGE - %d CR" % Balance.CHARGE_PRICE, func() -> void:
		if Progress.buy_charge():
			Audio.play("ui_buy")
			_open_panel(_supply_panel())
		else:
			Audio.play("ui_deny"), 220)
	b.disabled = Progress.credits < Balance.CHARGE_PRICE or Progress.charges + Balance.CHARGES_FREE >= Balance.CHARGES_MAX
	v.add_child(b)
	v.add_child(UIKit.button("CLOSE", _close_panel))
	return fr[0]


func _launch_panel() -> Control:
	var fr := _frame("LIFT CONTROL")
	var v: VBoxContainer = fr[1]
	var c: Dictionary = Game.contract
	v.add_child(UIKit.label("CONTRACT: " + str(c.get("name", "")), 11, UIKit.AMBER, true))
	v.add_child(UIKit.label(str(c.get("desc", "")), 10))
	v.add_child(UIKit.label("Relic bonus: %d CR    Charges: %d    Cargo: %d" % [c.get("reward", 0), Balance.CHARGES_FREE + Progress.charges, cargo_cap()], 10, UIKit.TEAL))
	v.add_child(UIKit.label("Death loses unbanked cargo. Upgrades are permanent.", 9, UIKit.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UIKit.button("DESCEND", func() -> void:
		Audio.play("lift_ding")
		Game.start_run(), 140))
	row.add_child(UIKit.button("NOT YET", _close_panel, 110))
	v.add_child(row)
	return fr[0]
