class_name MapScreen
extends CanvasLayer
## Full-screen survey map: everything the player has explored, with pinch /
## wheel zoom and drag panning. The game is paused while it is open.

const ZOOM_MIN := 1.0
const ZOOM_MAX := 8.0

var mine: Node
var root: Control
var view: View
var is_open := false


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.theme()
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.03, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	view = View.new()
	view.screen = self
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(view)
	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -236
	bar.offset_right = -8
	bar.offset_top = 6
	bar.offset_bottom = 30
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)
	bar.add_child(UIKit.button("CENTRE", func() -> void: view.centre_on_player(), 70.0))
	bar.add_child(UIKit.button("+", func() -> void: view.zoom_by(1.5, view.size * 0.5), 28.0))
	bar.add_child(UIKit.button("-", func() -> void: view.zoom_by(1.0 / 1.5, view.size * 0.5), 28.0))
	bar.add_child(UIKit.button("CLOSE", close, 64.0))
	var title := UIKit.label("SURVEY MAP", 12, UIKit.AMBER, true)
	title.position = Vector2(10, 8)
	root.add_child(title)


func open() -> void:
	if is_open:
		return
	is_open = true
	root.visible = true
	get_tree().paused = true
	if mine.player:
		mine.player.stop_sounds()
	mine.hud.touch._release_all()
	view.setup(mine)
	Audio.play("ui_click")


func close() -> void:
	if not is_open:
		return
	is_open = false
	root.visible = false
	get_tree().paused = false
	for a in ["drill", "jump", "charge", "interact", "ladder"]:
		Input.action_release(a)


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


class View extends Control:
	var screen: Node
	var mine: Node
	var grid: TerrainGrid
	var tex: ImageTexture
	var zoom := 1.0            # multiple of the fit-to-screen scale
	var centre := Vector2.ZERO # map cell at the middle of the view
	var touches: Dictionary = {}
	var _mouse_drag := false
	var _tap_t := 0.0
	var _picked := ""

	func setup(m: Node) -> void:
		mine = m
		grid = m.grid
		tex = m.hud.minimap.tex
		m.hud.minimap.tex.update(m.hud.minimap.img)
		touches.clear()
		zoom = 2.0
		centre_on_player()

	func fit_scale() -> float:
		return minf(size.x / grid.w, (size.y - 40.0) / grid.h)

	func px() -> float:
		return fit_scale() * zoom

	func centre_on_player() -> void:
		centre = mine.player.global_position / Balance.CELL
		_clamp()
		queue_redraw()

	func _clamp() -> void:
		zoom = clampf(zoom, MapScreen.ZOOM_MIN, MapScreen.ZOOM_MAX)
		var half := size / px() * 0.5
		# never scroll past the map; when the map is smaller than the view, centre it
		centre.x = grid.w * 0.5 if half.x * 2.0 >= grid.w else clampf(centre.x, half.x, grid.w - half.x)
		centre.y = grid.h * 0.5 if half.y * 2.0 >= grid.h else clampf(centre.y, half.y, grid.h - half.y)

	func to_screen(cell: Vector2) -> Vector2:
		return size * 0.5 + (cell - centre) * px()

	func to_cell(p: Vector2) -> Vector2:
		return centre + (p - size * 0.5) / px()

	## Zoom keeping the map point under `anchor` (screen px) fixed.
	func zoom_by(f: float, anchor: Vector2) -> void:
		var before := to_cell(anchor)
		zoom = clampf(zoom * f, MapScreen.ZOOM_MIN, MapScreen.ZOOM_MAX)
		centre += before - to_cell(anchor)
		_clamp()
		queue_redraw()

	func pan(delta_px: Vector2) -> void:
		centre -= delta_px / px()
		_clamp()
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventScreenTouch:
			if e.pressed:
				touches[e.index] = e.position
				var now := Time.get_ticks_msec() / 1000.0
				if touches.size() == 1 and now - _tap_t < 0.3:
					zoom_by(2.0, e.position)
				_tap_t = now
				_pick(e.position)
			else:
				touches.erase(e.index)
			accept_event()
		elif e is InputEventScreenDrag:
			if touches.size() >= 2 and touches.has(e.index):
				var other := Vector2.ZERO
				for k in touches.keys():
					if k != e.index:
						other = touches[k]
				var d0: float = (touches[e.index] as Vector2).distance_to(other)
				var d1: float = (e.position as Vector2).distance_to(other)
				if d0 > 4.0:
					zoom_by(d1 / d0, (e.position + other) * 0.5)
				pan(e.relative * 0.5)
			else:
				pan(e.relative)
			touches[e.index] = e.position
			accept_event()
		elif e is InputEventMouseButton:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
				zoom_by(1.2, e.position)
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
				zoom_by(1.0 / 1.2, e.position)
			elif e.button_index == MOUSE_BUTTON_LEFT:
				_mouse_drag = e.pressed and touches.is_empty()
				if e.pressed:
					_pick(e.position)
		elif e is InputEventMouseMotion and _mouse_drag and touches.is_empty():
			pan(e.relative)

	## Tap a discovered landmark to read its name.
	func _pick(p: Vector2) -> void:
		_picked = ""
		var c := to_cell(p)
		for l in mine.data.get("landmarks", []):
			var r: Rect2i = l["rect"]
			if Rect2(r).grow(1.5).has_point(c) and _seen(r):
				_picked = String(l["kind"]).replace("_", " ").to_upper()
		queue_redraw()

	func _seen(r: Rect2i) -> bool:
		var c := r.get_center()
		for d in [Vector2i.ZERO, Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if grid.has_flag(c.x + d.x, c.y + d.y, Cell.F_EXPLORED):
				return true
		return false

	func _draw() -> void:
		if grid == null or tex == null:
			return
		var s := px()
		var tl := to_screen(Vector2.ZERO)
		draw_rect(Rect2(tl, Vector2(grid.w, grid.h) * s), Color(0.05, 0.04, 0.07, 1.0))
		draw_texture_rect(tex, Rect2(tl, Vector2(grid.w, grid.h) * s), false)
		draw_rect(Rect2(tl, Vector2(grid.w, grid.h) * s), Color(0.35, 0.28, 0.5), false, 1.0)
		var f := UIKit.font_head()
		_overlay(f)


	func _overlay(f: Font) -> void:
		var s := px()
		# zone names and boundaries
		for z in mine.data.get("zones", []):
			var zr: Rect2i = z["rect"]
			var zp := to_screen(Vector2(zr.position))
			draw_line(zp, zp + Vector2(zr.size.x * s, 0), Color(1, 1, 1, 0.12), 1.0)
			draw_string(f, zp + Vector2(4, 11), z["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(z.get("color", Color.WHITE), 0.7))
		# markers
		for l in mine.lifts:
			var lc: Vector2 = l.global_position / Balance.CELL
			if grid.has_flag(int(lc.x), int(lc.y) - 1, Cell.F_EXPLORED) or l.id == "surface":
				_mark(to_screen(lc), Color(0.3, 1.0, 0.4) if l.active else Color(1.0, 0.5, 0.2), 4.0)
		if mine.relic and not mine.relic.taken:
			var rc: Vector2 = mine.relic.global_position / Balance.CELL
			if grid.has_flag(int(rc.x), int(rc.y), Cell.F_EXPLORED):
				_mark(to_screen(rc), Color(0.4, 1.0, 1.0), 4.0)
		for special in [mine.descent, mine.gate, mine.engine]:
			if special:
				var sc2: Vector2 = special.global_position / Balance.CELL
				if grid.has_flag(int(sc2.x), int(sc2.y) - 1, Cell.F_EXPLORED):
					_mark(to_screen(sc2), Balance.ZONE_COLORS[Balance.Z_FIRST], 5.0)
					draw_string(f, to_screen(sc2) + Vector2(6, 3), "DESCENT" if special == mine.descent else ("TRANSIT GATE" if special == mine.gate else "THERMAL PLANT"), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Balance.ZONE_COLORS[Balance.Z_FIRST])
		for lm in mine.data.get("landmarks", []):
			var r: Rect2i = lm["rect"]
			if _seen(r):
				var p := to_screen(Vector2(r.get_center()) + Vector2(0.5, 0.5))
				draw_arc(p, 4.0, 0, TAU, 12, Color(1.0, 0.8, 0.35, 0.9), 1.0)
		var pp := to_screen(mine.player.global_position / Balance.CELL)
		_mark(pp, Color(1.0, 0.75, 0.3), 5.0)
		draw_arc(pp, 8.0 + 2.0 * sin(Time.get_ticks_msec() / 200.0), 0, TAU, 20, Color(1.0, 0.75, 0.3, 0.7), 1.0)
		# header and legend strips keep text readable over the map
		draw_rect(Rect2(0, 0, size.x, 38), Color(0.03, 0.02, 0.05, 0.9))
		draw_rect(Rect2(0, size.y - 18, size.x, 18), Color(0.03, 0.02, 0.05, 0.9))
		var ly := size.y - 6.0
		var lx := 10.0
		for item in [["YOU", Color(1.0, 0.75, 0.3)], ["LIFT", Color(0.3, 1.0, 0.4)], ["DORMANT LIFT", Color(1.0, 0.5, 0.2)], ["RELIC", Color(0.4, 1.0, 1.0)], ["WATER", Color(0.2, 0.5, 0.9)], ["LANDMARK (TAP)", Color(1.0, 0.8, 0.35)]]:
			draw_rect(Rect2(lx, ly - 6, 6, 6), item[1])
			draw_string(f, Vector2(lx + 9, ly), item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UIKit.MUTED)
			lx += 16.0 + f.get_string_size(item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string(f, Vector2(10, 32), "ZOOM %.1fx   pinch / wheel to zoom, drag to scroll" % zoom, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UIKit.MUTED)
		if _picked != "":
			draw_string(f, Vector2(10, 52), _picked, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.AMBER)

	func _process(_d: float) -> void:
		if screen.is_open:
			queue_redraw()

	func _mark(p: Vector2, c: Color, r: float) -> void:
		draw_rect(Rect2(p - Vector2(r, r) * 0.5 - Vector2.ONE, Vector2(r, r) + Vector2(2, 2)), Color(0, 0, 0, 0.85))
		draw_rect(Rect2(p - Vector2(r, r) * 0.5, Vector2(r, r)), c)
