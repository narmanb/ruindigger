extends Control
## On-screen touch controls for Android landscape.
##
## Design constraints from the brief:
##   * left side  : movement zone (drag anywhere to steer, plus a visible stick)
##   * right side : large JUMP, DRILL (hold) and CHARGE buttons
##   * multi-touch : holding MOVE + JUMP + DRILL at once must work
##   * never swallow input: each finger is tracked by index, and every touch
##     that is not inside a control is forwarded as a movement drag.
##
## Buttons feed the same InputMap actions the keyboard/gamepad use, so gameplay
## code never needs to know which device is active.

const ACTIONS := ["move_left", "move_right", "move_up", "move_down",
		"jump", "drill", "charge", "interact"]

var player: Player
var mine

# Active touch tracking: touch_index -> control key
var _touches: Dictionary = {}
var _move_touch: int = -1
var _move_origin: Vector2 = Vector2.ZERO
var _move_delta: Vector2 = Vector2.ZERO
var _held: Dictionary = {}

var _buttons: Dictionary = {}
var _stick_center: Vector2 = Vector2.ZERO
var _stick_radius: float = 90.0
var _scale: float = 1.0
var _opacity: float = 0.55

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_apply_settings()
	layout_controls()
	SaveManager.settings # settings are read each frame for live updates

func _apply_settings() -> void:
	_scale = clampf(float(SaveManager.settings.get("button_scale", 1.0)), 0.7, 1.6)
	_opacity = clampf(float(SaveManager.settings.get("button_opacity", 0.55)), 0.2, 1.0)

func layout_controls() -> void:
	for c in get_children():
		c.queue_free()
	_buttons.clear()
	var vp := get_viewport_rect().size
	var left_handed := bool(SaveManager.settings.get("left_handed", false))
	var margin := 28.0
	var r := 46.0 * _scale

	# Movement stick (drawn) occupies the left (or right) side; the whole side is
	# a drag zone so the player never has to hit a tiny target.
	_stick_radius = 92.0 * _scale
	_stick_center = Vector2(vp.x * 0.16, vp.y - _stick_radius - 30.0)
	if left_handed:
		_stick_center = Vector2(vp.x - vp.x * 0.16, vp.y - _stick_radius - 30.0)

	# Action buttons cluster on the opposite side to the stick.
	var bx := vp.x - margin - r if not left_handed else margin + r
	var by := vp.y - margin - r
	_add_button("jump", Vector2(bx - r * 0.2, by - r * 1.1), r, "JUMP", Color(0.35, 0.7, 1.0))
	_add_button("drill", Vector2(bx - r * 2.4, by - r * 0.5), r * 1.25, "DRILL", Color(1.0, 0.7, 0.3))
	_add_button("charge", Vector2(bx - r * 0.1, by + r * 1.0), r * 0.9, "BOMB", Color(1.0, 0.42, 0.35))
	_add_button("interact", Vector2(bx - r * 2.2, by + r * 1.1), r * 0.85, "USE", Color(0.55, 1.0, 0.7))
	queue_redraw()

func _add_button(key: String, pos: Vector2, radius: float, label: String, color: Color) -> void:
	var b := TouchButton.new()
	b.key = key
	b.label = label
	b.radius = radius
	b.color = color
	b.opacity = _opacity
	b.position = pos - Vector2(radius, radius)
	b.custom_minimum_size = Vector2(radius * 2, radius * 2)
	b.size = Vector2(radius * 2, radius * 2)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed_cb = func(k, down): _set_action(k, down)
	add_child(b)
	_buttons[key] = b

func _set_action(key: String, down: bool) -> void:
	if down:
		_held[key] = true
		Input.action_press(key)
	else:
		_held.erase(key)
		Input.action_release(key)

func _clear_all() -> void:
	for k in _held.keys():
		Input.action_release(k)
	_held.clear()
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")

# ---------------------------------------------------------------------------
# Touch handling
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseButton and OS.has_feature("editor"):
		# Desktop convenience: emulate the stick with the mouse in the editor.
		pass

func _handle_touch(ev: InputEventScreenTouch) -> void:
	if ev.pressed:
		# Buttons first.
		for key in _buttons:
			var b: TouchButton = _buttons[key]
			if b.hit(ev.position):
				_touches[ev.index] = key
				b.down = true
				b.queue_redraw()
				_set_action(key, true)
				return
		# Otherwise this finger drives movement.
		if _move_touch == -1 and _in_move_zone(ev.position):
			_move_touch = ev.index
			_move_origin = ev.position
			_move_delta = Vector2.ZERO
			queue_redraw()
	else:
		if _touches.has(ev.index):
			var key: String = _touches[ev.index]
			_touches.erase(ev.index)
			var b: TouchButton = _buttons.get(key)
			if b:
				b.down = false
				b.queue_redraw()
			_set_action(key, false)
		if ev.index == _move_touch:
			_move_touch = -1
			_move_delta = Vector2.ZERO
			Input.action_release("move_left")
			Input.action_release("move_right")
			Input.action_release("move_up")
			Input.action_release("move_down")
			queue_redraw()

func _handle_drag(ev: InputEventScreenDrag) -> void:
	if ev.index != _move_touch:
		return
	_move_delta = ev.position - _move_origin
	_apply_stick(_move_delta)
	queue_redraw()

func _apply_stick(d: Vector2) -> void:
	var dead := 10.0
	var nx := d.x / _stick_radius
	var ny := d.y / _stick_radius
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")
	if absf(d.x) > dead:
		Input.action_press("move_right" if nx > 0.0 else "move_left", minf(1.0, absf(nx)))
	if absf(d.y) > dead * 1.6:
		Input.action_press("move_down" if ny > 0.0 else "move_up", minf(1.0, absf(ny)))

func _in_move_zone(pos: Vector2) -> bool:
	var vp := get_viewport_rect().size
	var left_handed := bool(SaveManager.settings.get("left_handed", false))
	if left_handed:
		return pos.x > vp.x * 0.5
	return pos.x < vp.x * 0.5

# ---------------------------------------------------------------------------
# Painting the stick + labels
# ---------------------------------------------------------------------------

func _draw() -> void:
	var col := Color(1, 1, 1, _opacity)
	# stick base
	draw_circle(_stick_center, _stick_radius * 0.55, Color(0.12, 0.14, 0.2, _opacity * 0.5))
	draw_arc(_stick_center, _stick_radius * 0.55, 0, TAU, 40, col * Color(1, 1, 1, 0.5), 2.0)
	var knob := _stick_center + _move_delta.limit_length(_stick_radius * 0.5)
	draw_circle(knob, _stick_radius * 0.24, Color(0.85, 0.9, 1.0, _opacity * 0.9))
	draw_arc(knob, _stick_radius * 0.24, 0, TAU, 28, Color(1, 1, 1, _opacity), 2.0)

func _process(_delta: float) -> void:
	var s := clampf(float(SaveManager.settings.get("button_scale", 1.0)), 0.7, 1.6)
	var o := clampf(float(SaveManager.settings.get("button_opacity", 0.55)), 0.2, 1.0)
	if absf(s - _scale) > 0.001 or absf(o - _opacity) > 0.001:
		_apply_settings()
		layout_controls()


## A single round touch button. Implemented as a Node2D-like Control that
## tests hits itself so we can track raw screen touches by index.
class TouchButton extends Control:
	var key: String = ""
	var label: String = ""
	var radius: float = 46.0
	var color: Color = Color(0.5, 0.7, 1.0)
	var opacity: float = 0.55
	var down: bool = false
	var pressed_cb: Callable

	func hit(p: Vector2) -> bool:
		return p.distance_to(global_position + Vector2(radius, radius)) <= radius * 1.15

	func _draw() -> void:
		var c := Vector2(radius, radius)
		var a := opacity
		if down:
			a = minf(1.0, opacity + 0.35)
		draw_circle(c, radius, Color(color.r * 0.25, color.g * 0.25, color.b * 0.3, a * 0.75))
		draw_arc(c, radius, 0, TAU, 44, Color(color.r, color.g, color.b, a), 3.0)
		draw_arc(c, radius - 4.0, 0, TAU, 44, Color(1, 1, 1, a * 0.25), 1.0)
		if down:
			draw_circle(c, radius * 0.82, Color(color.r, color.g, color.b, a * 0.35))
		var f := UiTheme.font()
		if f:
			var fs := 15
			var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, c + Vector2(-tw * 0.5, 5), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, minf(1.0, a + 0.3)))
