class_name TouchControls
extends Control
## Multi-touch on-screen controls. Every finger is tracked by its index and
## owned by exactly one control, so MOVE + JUMP + DRILL can all be held at
## once without any button swallowing another finger.
##
## Left: movement control, chosen in Settings (x = move, y = aim up/down):
##   fixed stick   - stays at its resting spot
##   floating stick - appears under the finger anywhere in the left zone
##   d-pad         - 8-way pad at the resting spot
## Right: DRILL (hold), JUMP, CHARGE, LADDER and a context USE button.
## `edit_mode` turns the controls into draggable handles (layout editor).

const MODE_FIXED := 0
const MODE_FLOATING := 1
const MODE_DPAD := 2

var mine: Node
var stick_center := Vector2.ZERO
var stick_pos := Vector2.ZERO
var stick_finger := -1
var stick_radius := 34.0
var buttons: Array = []       # {name, action, off, r, finger}
var interact_label := ""
var edit_mode := false
var _vec := Vector2.ZERO
var _drag_name := ""          # edit mode: control being dragged
var _drag_finger := -1
var _drag_grab := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons = default_buttons()
	Settings.changed.connect(func() -> void:
		_update_visible()
		queue_redraw())
	InputSetup.device_changed.connect(func(_k: String) -> void: _update_visible())
	_update_visible()


static func default_buttons() -> Array:
	return [
		{"name": "DRILL", "action": "drill", "off": Vector2(-48, -54), "r": 30.0, "finger": -1},
		{"name": "JUMP", "action": "jump", "off": Vector2(-118, -34), "r": 25.0, "finger": -1},
		{"name": "CHARGE", "action": "charge", "off": Vector2(-44, -128), "r": 19.0, "finger": -1},
		{"name": "USE", "action": "interact", "off": Vector2(-112, -100), "r": 19.0, "finger": -1},
		{"name": "LADDER", "action": "ladder", "off": Vector2(-172, -74), "r": 19.0, "finger": -1},
	]


func _update_visible() -> void:
	if edit_mode:
		visible = true
		return
	var mode: int = Settings.get_value("touch_mode")
	if mode == 1:
		visible = true
	elif mode == 2:
		visible = false
	else:
		visible = DisplayServer.is_touchscreen_available() and InputSetup.last_device != "gamepad" and InputSetup.last_device != "keyboard" \
			or InputSetup.last_device == "touch"
	if not visible:
		_release_all()


func _safe_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or safe.size.x <= 0:
		return Rect2(Vector2.ZERO, vp)
	var k := vp.x / float(win.x)
	# the OS reports the safe area in screen space; never trust it past the viewport
	var r := Rect2(Vector2(safe.position) * k, Vector2(safe.size) * k).intersection(Rect2(Vector2.ZERO, vp))
	return r if r.size.x > 100.0 and r.size.y > 100.0 else Rect2(Vector2.ZERO, vp)


## Pure layout maths (also used by tests): where a button sits for a given
## safe rect, scale and user offset.
static func button_pos(b: Dictionary, sr: Rect2, scale: float, user_off: Vector2) -> Vector2:
	var p: Vector2 = sr.end + (b["off"] as Vector2) * scale + user_off
	var r: float = float(b["r"]) * scale
	return p.clamp(sr.position + Vector2(r, r), sr.end - Vector2(r, r))


static func move_rest_pos(sr: Rect2, radius: float, user_off: Vector2) -> Vector2:
	var p := Vector2(sr.position.x + 36.0 + radius, sr.end.y - 28.0 - radius) + user_off
	return p.clamp(sr.position + Vector2(radius, radius), sr.end - Vector2(radius, radius))


func _btn_pos(b: Dictionary) -> Vector2:
	return button_pos(b, _safe_rect(), float(Settings.get_value("touch_scale")), Settings.layout_offset(b["action"]))


func _btn_r(b: Dictionary) -> float:
	return float(b["r"]) * float(Settings.get_value("touch_scale"))


func move_mode() -> int:
	return int(Settings.get_value("move_control"))


func move_radius() -> float:
	return stick_radius * float(Settings.get_value("stick_size")) * (1.25 if move_mode() == MODE_DPAD else 1.0)


func _rest_pos() -> Vector2:
	return move_rest_pos(_safe_rect(), move_radius(), Settings.layout_offset("move"))


## The area where a floating stick may spawn: the left side, below the HUD row.
func float_zone() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(0, 60, vp.x * 0.45, vp.y - 60)


func _button_visible(b: Dictionary) -> bool:
	return edit_mode or b["action"] != "interact" or interact_label != ""


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if edit_mode:
		_edit_input(event)
		return
	if get_tree().paused:
		return
	if event is InputEventScreenTouch:
		var p := _to_local(event.position)
		if event.pressed:
			# right-side buttons first (generous hit radius)
			for b in buttons:
				if b["finger"] == -1 and _button_visible(b) and p.distance_to(_btn_pos(b)) < _btn_r(b) * 1.25:
					b["finger"] = event.index
					Input.action_press(b["action"])
					queue_redraw()
					get_viewport().set_input_as_handled()
					return
			if stick_finger == -1 and _move_grab(p):
				stick_finger = event.index
				stick_center = p if move_mode() == MODE_FLOATING else _rest_pos()
				stick_pos = p
				_apply_stick()
				get_viewport().set_input_as_handled()
		else:
			if event.index == stick_finger:
				stick_finger = -1
				_vec = Vector2.ZERO
				_apply_stick()
			for b in buttons:
				if b["finger"] == event.index:
					b["finger"] = -1
					Input.action_release(b["action"])
			queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == stick_finger:
			stick_pos = _to_local(event.position)
			var r := move_radius()
			var d := stick_pos - stick_center
			if move_mode() == MODE_FLOATING and d.length() > r * 1.6:
				# drag the base along so the stick never "runs out"
				stick_center = stick_pos - d.normalized() * r * 1.6
			_apply_stick()
			get_viewport().set_input_as_handled()


## Does a new touch at p take hold of the movement control?
func _move_grab(p: Vector2) -> bool:
	match move_mode():
		MODE_FLOATING:
			return float_zone().has_point(p)
		_:
			return p.distance_to(_rest_pos()) < move_radius() * 1.7
	return false


func _to_local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


## Movement vector for a finger offset d (pure; tests call it directly).
static func move_vector(mode: int, d: Vector2, radius: float, deadzone: float) -> Vector2:
	if mode == MODE_DPAD:
		if d.length() < radius * 0.22:
			return Vector2.ZERO
		var a := snappedf(d.angle(), PI / 4.0)
		var v := Vector2.RIGHT.rotated(a)
		return Vector2(signf(v.x) if absf(v.x) > 0.3 else 0.0, signf(v.y) if absf(v.y) > 0.3 else 0.0)
	var out := (d / radius).limit_length(1.0)
	if absf(out.x) <= deadzone:
		out.x = 0.0
	return out


func _apply_stick() -> void:
	if stick_finger != -1:
		_vec = move_vector(move_mode(), stick_pos - stick_center, move_radius(), float(Settings.get_value("stick_deadzone")))
	var x := _vec.x
	var y := _vec.y
	_set_axis("move_left", "move_right", x)
	if move_mode() == MODE_DPAD:
		_set_axis("aim_up", "aim_down", y)
	else:
		# aim needs a clear vertical push so walking isn't mistaken for aiming
		_set_axis("aim_up", "aim_down", y if absf(y) > 0.55 and absf(y) > absf(x) * 0.8 else 0.0)
	queue_redraw()


func _set_axis(neg: String, pos: String, v: float) -> void:
	if v < 0.0:
		Input.action_press(neg, -v)
		Input.action_release(pos)
	elif v > 0.0:
		Input.action_press(pos, v)
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func _release_all() -> void:
	stick_finger = -1
	_vec = Vector2.ZERO
	for a in ["move_left", "move_right", "aim_up", "aim_down"]:
		Input.action_release(a)
	for b in buttons:
		if b["finger"] != -1:
			Input.action_release(b["action"])
		b["finger"] = -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_release_all()


func _process(_d: float) -> void:
	if mine and mine.player:
		var it: Dictionary = mine.nearest_interactable(mine.player)
		var lbl: String = it.get("label", "")
		if lbl != interact_label:
			interact_label = lbl
			queue_redraw()


# --- layout editor ----------------------------------------------------------
func _edit_input(event: InputEvent) -> void:
	var pressed := false
	var released := false
	var idx := 0
	var p := Vector2.ZERO
	var moved := false
	if event is InputEventScreenTouch:
		idx = event.index
		p = _to_local(event.position)
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		idx = event.index
		p = _to_local(event.position)
		moved = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		p = _to_local(event.position)
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion and _drag_name != "":
		p = _to_local(event.position)
		moved = true
	else:
		return
	if pressed and _drag_name == "":
		var name := _control_at(p)
		if name != "":
			_drag_name = name
			_drag_finger = idx
			_drag_grab = p - _control_pos(name)
			get_viewport().set_input_as_handled()
	elif moved and _drag_name != "" and idx == _drag_finger:
		var want := p - _drag_grab
		var cur := _control_pos(_drag_name)
		Settings.set_layout_offset(_drag_name, Settings.layout_offset(_drag_name) + (want - cur))
		get_viewport().set_input_as_handled()
	elif released and idx == _drag_finger:
		_drag_name = ""


func _control_pos(name: String) -> Vector2:
	if name == "move":
		return _rest_pos()
	for b in buttons:
		if b["action"] == name:
			return _btn_pos(b)
	return Vector2.ZERO


func _control_at(p: Vector2) -> String:
	for b in buttons:
		if p.distance_to(_btn_pos(b)) < _btn_r(b) * 1.25:
			return b["action"]
	if p.distance_to(_rest_pos()) < move_radius() * 1.3:
		return "move"
	return ""


# --- drawing ----------------------------------------------------------------
func _draw() -> void:
	var op: float = Settings.get_value("touch_opacity")
	if edit_mode:
		op = 1.0
	var font := UIKit.font_head()
	var r := move_radius()
	var mode := move_mode()
	var held := stick_finger != -1
	var base := stick_center if held and mode == MODE_FLOATING else _rest_pos()
	# a resting floating stick is only a faint ghost: it shows where to touch
	var ghost := 0.45 if (mode == MODE_FLOATING and not held and not edit_mode) else 1.0
	if mode == MODE_DPAD:
		_draw_dpad(base, r, op)
	else:
		draw_circle(base, r, Color(0.05, 0.04, 0.08, 0.35 * op * ghost))
		draw_arc(base, r, 0, TAU, 32, Color(1.0, 0.7, 0.3, 0.6 * op * ghost), 2.0)
		for a in [0.0, PI * 0.5, PI, PI * 1.5]:
			var dirv := Vector2.RIGHT.rotated(a)
			draw_line(base + dirv * (r - 8), base + dirv * (r - 3), Color(1.0, 0.7, 0.3, 0.5 * op * ghost), 2.0)
		var knob := base + _vec * r
		draw_circle(knob, r * 0.45, Color(1.0, 0.65, 0.25, 0.55 * op * ghost))
		draw_arc(knob, r * 0.45, 0, TAU, 20, Color(1, 0.9, 0.7, 0.8 * op * ghost), 1.5)
	# buttons
	for b in buttons:
		var label: String = b["name"]
		if b["action"] == "interact":
			if not _button_visible(b):
				continue
			if interact_label != "":
				label = interact_label
		var p := _btn_pos(b)
		var br := _btn_r(b)
		var bheld: bool = b["finger"] != -1 or (edit_mode and _drag_name == b["action"])
		var col := Color(0.4, 0.95, 0.8)
		match b["action"]:
			"drill":
				col = Color(1.0, 0.6, 0.2)
			"charge":
				col = Color(1.0, 0.35, 0.3)
			"ladder":
				col = Color(0.95, 0.8, 0.35)
		var dim := 1.0
		if b["action"] == "ladder" and mine and mine.player and not edit_mode and not mine.player.can_build_ladder():
			dim = 0.4
		draw_circle(p, br, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, (0.65 if bheld else 0.4) * op))
		draw_arc(p, br, 0, TAU, 32, Color(col.r, col.g, col.b, (1.0 if bheld else 0.75) * op * dim), 2.0 if not bheld else 3.0)
		var fs := 8 if label.length() > 5 else 9
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, p + Vector2(-tw * 0.5, 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9 * op * dim))
		if b["action"] == "charge" and Game.run.has("charges"):
			draw_string(font, p + Vector2(br - 6, -br + 6), str(Game.run["charges"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 0.8, 0.6, op))


func _draw_dpad(c: Vector2, r: float, op: float) -> void:
	var arm := r * 0.36
	var col := Color(1.0, 0.7, 0.3, 0.6 * op)
	var bg := Color(0.05, 0.04, 0.08, 0.4 * op)
	draw_rect(Rect2(c - Vector2(arm, r), Vector2(arm * 2.0, r * 2.0)), bg)
	draw_rect(Rect2(c - Vector2(r, arm), Vector2(r * 2.0, arm * 2.0)), bg)
	var pts := PackedVector2Array([
		c + Vector2(-arm, -r), c + Vector2(arm, -r), c + Vector2(arm, -arm), c + Vector2(r, -arm),
		c + Vector2(r, arm), c + Vector2(arm, arm), c + Vector2(arm, r), c + Vector2(-arm, r),
		c + Vector2(-arm, arm), c + Vector2(-r, arm), c + Vector2(-r, -arm), c + Vector2(-arm, -arm), c + Vector2(-arm, -r)])
	draw_polyline(pts, col, 2.0)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var on: bool = _vec != Vector2.ZERO and _vec.dot(d) > 0.3
		var tip: Vector2 = c + d * (r - 6.0)
		var side: Vector2 = Vector2(-d.y, d.x) * arm * 0.55
		var back: Vector2 = c + d * (r - 6.0 - arm * 0.8)
		draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), Color(1.0, 0.9, 0.6, (0.95 if on else 0.45) * op))


func occupied_rects() -> Array[Rect2]:
	## Screen areas covered by controls (used by tests to check overlaps).
	var out: Array[Rect2] = []
	for b in buttons:
		var p := _btn_pos(b)
		var br := _btn_r(b)
		out.append(Rect2(p - Vector2(br, br), Vector2(br, br) * 2.0))
	return out
