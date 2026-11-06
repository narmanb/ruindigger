class_name TouchControls
extends Control
## Multi-touch on-screen controls. Every finger is tracked by its index and
## owned by exactly one control, so MOVE + JUMP + DRILL can all be held at
## once without any button swallowing another finger.
##
## Left: floating joystick (x = move, y = aim up/down).
## Right: DRILL (hold), JUMP, CHARGE and a context INTERACT button.

var mine: Node
var stick_center := Vector2.ZERO
var stick_pos := Vector2.ZERO
var stick_finger := -1
var stick_radius := 34.0
var buttons: Array = []       # {name, action, pos, r, finger, label}
var interact_label := ""
var _vec := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons = [
		{"name": "DRILL", "action": "drill", "off": Vector2(-48, -54), "r": 30.0, "finger": -1},
		{"name": "JUMP", "action": "jump", "off": Vector2(-118, -34), "r": 25.0, "finger": -1},
		{"name": "CHARGE", "action": "charge", "off": Vector2(-44, -128), "r": 19.0, "finger": -1},
		{"name": "USE", "action": "interact", "off": Vector2(-112, -100), "r": 19.0, "finger": -1},
	]
	Settings.changed.connect(queue_redraw)
	InputSetup.device_changed.connect(func(_k: String) -> void: _update_visible())
	_update_visible()


func _update_visible() -> void:
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
	return Rect2(Vector2(safe.position) * k, Vector2(safe.size) * k)


func _btn_pos(b: Dictionary) -> Vector2:
	var sr := _safe_rect()
	var s: float = Settings.get_value("touch_scale")
	return Vector2(sr.end.x, sr.end.y) + (b["off"] as Vector2) * s


func _btn_r(b: Dictionary) -> float:
	return float(b["r"]) * float(Settings.get_value("touch_scale"))


func _input(event: InputEvent) -> void:
	if not visible or get_tree().paused:
		return
	if event is InputEventScreenTouch:
		var p := _to_local(event.position)
		if event.pressed:
			# right-side buttons first (generous hit radius)
			for b in buttons:
				if b["finger"] == -1 and p.distance_to(_btn_pos(b)) < _btn_r(b) * 1.25:
					if b["action"] == "interact" and interact_label == "":
						continue
					b["finger"] = event.index
					Input.action_press(b["action"])
					queue_redraw()
					get_viewport().set_input_as_handled()
					return
			if stick_finger == -1 and p.x < get_viewport_rect().size.x * 0.45 and p.y > 60:
				stick_finger = event.index
				stick_center = p
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
			var r := stick_radius * float(Settings.get_value("touch_scale"))
			var d := stick_pos - stick_center
			if d.length() > r * 1.6:
				# drag the base along so the stick never "runs out"
				stick_center = stick_pos - d.normalized() * r * 1.6
			_apply_stick()
			get_viewport().set_input_as_handled()


func _to_local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _apply_stick() -> void:
	var r := stick_radius * float(Settings.get_value("touch_scale"))
	if stick_finger != -1:
		_vec = ((stick_pos - stick_center) / r).limit_length(1.0)
	var x := _vec.x if absf(_vec.x) > 0.2 else 0.0
	var y := _vec.y
	_set_axis("move_left", "move_right", x)
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


func _draw() -> void:
	var op: float = Settings.get_value("touch_opacity")
	var font := UIKit.font_head()
	var sc: float = Settings.get_value("touch_scale")
	# joystick
	var r := stick_radius * sc
	var base := stick_center if stick_finger != -1 else Vector2(_safe_rect().position.x + 70 * sc, _safe_rect().end.y - 62 * sc)
	draw_circle(base, r, Color(0.05, 0.04, 0.08, 0.35 * op))
	draw_arc(base, r, 0, TAU, 32, Color(1.0, 0.7, 0.3, 0.6 * op), 2.0)
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dirv := Vector2.RIGHT.rotated(a)
		draw_line(base + dirv * (r - 8), base + dirv * (r - 3), Color(1.0, 0.7, 0.3, 0.5 * op), 2.0)
	var knob := base + _vec * r
	draw_circle(knob, r * 0.45, Color(1.0, 0.65, 0.25, 0.55 * op))
	draw_arc(knob, r * 0.45, 0, TAU, 20, Color(1, 0.9, 0.7, 0.8 * op), 1.5)
	# buttons
	for b in buttons:
		var label: String = b["name"]
		if b["action"] == "interact":
			if interact_label == "":
				continue
			label = interact_label
		var p := _btn_pos(b)
		var br := _btn_r(b)
		var held: bool = b["finger"] != -1
		var col := Color(1.0, 0.6, 0.2) if b["action"] == "drill" else (Color(0.4, 0.95, 0.8) if b["action"] != "charge" else Color(1.0, 0.35, 0.3))
		draw_circle(p, br, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, (0.65 if held else 0.4) * op))
		draw_arc(p, br, 0, TAU, 32, Color(col.r, col.g, col.b, (1.0 if held else 0.75) * op), 2.0 if not held else 3.0)
		var fs := 8 if label.length() > 6 else 9
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, p + Vector2(-tw * 0.5, 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9 * op))
		if b["action"] == "charge" and Game.run.has("charges"):
			draw_string(font, p + Vector2(br - 6, -br + 6), str(Game.run["charges"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 0.8, 0.6, op))


func occupied_rects() -> Array[Rect2]:
	## Screen areas covered by controls (used by tests to check overlaps).
	var out: Array[Rect2] = []
	for b in buttons:
		var p := _btn_pos(b)
		var br := _btn_r(b)
		out.append(Rect2(p - Vector2(br, br), Vector2(br, br) * 2.0))
	return out
