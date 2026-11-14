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
## Right: a 2x2 block of octagonal buttons (LADDER DRILL / CHARGE JUMP), a
## context USE button beside it (only when something is in reach), and a
## retractable gadget toolbar above the block (the active gadget and LURE).
## The toolbar's tab slides it off the right edge and back; its state is
## saved. When tucked away only the tab takes touches.
## `edit_mode` turns the controls into draggable handles (layout editor).
## The look comes from HudSkin, shared with the rest of the HUD.

const MODE_FIXED := 0
const MODE_FLOATING := 1
const MODE_DPAD := 2

const BAR_SLIDE := 0.2           # seconds for the toolbar to slide
const BAR_BTN := Vector2(52, 26) # one toolbar button, base px
const BAR_H := 34.0
const TAB := Vector2(14, 26)
const GAP := 5.0

var mine: Node
var stick_center := Vector2.ZERO
var stick_pos := Vector2.ZERO
var stick_finger := -1
var stick_radius := 34.0
var buttons: Array = []       # {name, action, off, hw, hh, r, finger, icon, accent}
var interact_label := ""
var edit_mode := false
var _vec := Vector2.ZERO
var _drag_name := ""          # edit mode: control being dragged
var _drag_finger := -1
var _drag_grab := Vector2.ZERO
# gadget toolbar: bar_t 1 = fully open, 0 = tucked away behind its tab
var bar_open := true
var bar_t := 1.0
var bar_buttons: Array = [
	{"name": "GADGET", "action": "gadget", "finger": -1},
	{"name": "LURE", "action": "lure", "finger": -1},
]
var _tab_finger := -1
var show_bar := true          # the outpost has no gadgets: it turns the toolbar off


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons = default_buttons()
	bar_open = bool(Settings.get_value("gadget_bar_open"))
	bar_t = 1.0 if bar_open else 0.0
	Settings.changed.connect(func() -> void:
		bar_open = bool(Settings.get_value("gadget_bar_open"))
		_update_visible()
		queue_redraw())
	InputSetup.device_changed.connect(func(_k: String) -> void: _update_visible())
	_update_visible()


## The right-hand block (centres offset from the safe rect's bottom-right):
##   LADDER  DRILL
##   CHARGE  JUMP      plus USE to the left, only when something is in reach.
## hw/hh are the octagon's half extents; r (= hh) is kept for older callers.
static func default_buttons() -> Array:
	return [
		{"name": "DRILL", "action": "drill", "off": Vector2(-41, -86), "hw": 33.0, "hh": 24.0, "r": 24.0, "finger": -1, "icon": "drill", "accent": HudSkin.ORANGE},
		{"name": "JUMP", "action": "jump", "off": Vector2(-41, -32), "hw": 33.0, "hh": 24.0, "r": 24.0, "finger": -1, "icon": "jump", "accent": HudSkin.CYAN},
		{"name": "CHARGE", "action": "charge", "off": Vector2(-112, -32), "hw": 33.0, "hh": 24.0, "r": 24.0, "finger": -1, "icon": "charge", "accent": HudSkin.ORANGE},
		{"name": "LADDER", "action": "ladder", "off": Vector2(-112, -86), "hw": 33.0, "hh": 24.0, "r": 24.0, "finger": -1, "icon": "ladder", "accent": HudSkin.ORANGE},
		{"name": "USE", "action": "interact", "off": Vector2(-180, -59), "hw": 31.0, "hh": 20.0, "r": 20.0, "finger": -1, "icon": "use", "accent": HudSkin.TEAL},
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
	var ext := Vector2(float(b.get("hw", b["r"])), float(b.get("hh", b["r"]))) * scale
	return p.clamp(sr.position + ext, sr.end - ext)


## The octagon's bounding box (layout maths and tests).
static func button_rect(b: Dictionary, sr: Rect2, scale: float, user_off: Vector2) -> Rect2:
	var ext := Vector2(float(b.get("hw", b["r"])), float(b.get("hh", b["r"]))) * scale
	return Rect2(button_pos(b, sr, scale, user_off) - ext, ext * 2.0)


## Gadget toolbar geometry for a slide amount t (1 open, 0 tucked away):
## {tab, panel, buttons: [rect, rect]}. It sits right-aligned above the
## block's top row and slides off the right edge, leaving only its tab.
static func bar_layout(sr: Rect2, scale: float, top_y: float, right_x: float, t: float) -> Dictionary:
	var s := scale
	var bw := BAR_BTN.x * s
	var pw := (BAR_BTN.x * 2.0 + 10.0) * s
	var ph := BAR_H * s
	var tw := TAB.x * s
	var th := TAB.y * s
	var y := roundf(top_y - GAP * s - ph)
	var open_px := roundf(right_x - pw)
	var closed_px := sr.end.x + 2.0
	var px := roundf(lerpf(closed_px, open_px, clampf(t, 0.0, 1.0)))
	var tab_x := minf(px - tw + 2.0 * s, sr.end.x - tw)
	var panel := Rect2(px, y, pw, ph)
	var tab := Rect2(roundf(tab_x), roundf(y + (ph - th) * 0.5), tw, th)
	var b0 := Rect2(px + 4.0 * s, roundf(y + (ph - BAR_BTN.y * s) * 0.5), bw, BAR_BTN.y * s)
	var b1 := Rect2(b0.end.x + 2.0 * s, b0.position.y, bw, BAR_BTN.y * s)
	return {"tab": tab, "panel": panel, "buttons": [b0, b1]}


func _btn_pos(b: Dictionary) -> Vector2:
	return button_pos(b, _safe_rect(), float(Settings.get_value("touch_scale")), Settings.layout_offset(b["action"]))


func _btn_rect(b: Dictionary) -> Rect2:
	return button_rect(b, _safe_rect(), float(Settings.get_value("touch_scale")), Settings.layout_offset(b["action"]))


func _btn_r(b: Dictionary) -> float:
	return float(b["r"]) * float(Settings.get_value("touch_scale"))


func _hit(b: Dictionary, p: Vector2) -> bool:
	return _btn_rect(b).grow(4.0 * float(Settings.get_value("touch_scale"))).has_point(p)


func _bar() -> Dictionary:
	var top := INF
	var right := -INF
	for b in buttons:
		if b["action"] in ["drill", "ladder", "jump", "charge"]:
			var r := _btn_rect(b)
			top = minf(top, r.position.y)
			right = maxf(right, r.end.x)
	return bar_layout(_safe_rect(), float(Settings.get_value("touch_scale")), top, right, bar_t)


func toggle_bar() -> void:
	bar_open = not bar_open
	Settings.set_value("gadget_bar_open", bar_open)
	Audio.play("ui_click", -6.0)
	for bb in bar_buttons:
		if bb["finger"] != -1:
			Input.action_release(bb["action"])
			bb["finger"] = -1
	queue_redraw()


func move_mode() -> int:
	return int(Settings.get_value("move_control"))


func move_radius() -> float:
	return stick_radius * float(Settings.get_value("stick_size")) * (1.25 if move_mode() == MODE_DPAD else 1.0)


func _rest_pos() -> Vector2:
	return move_rest_pos(_safe_rect(), move_radius(), Settings.layout_offset("move"))


static func move_rest_pos(sr: Rect2, radius: float, user_off: Vector2) -> Vector2:
	var p := Vector2(sr.position.x + 36.0 + radius, sr.end.y - 28.0 - radius) + user_off
	return p.clamp(sr.position + Vector2(radius, radius), sr.end - Vector2(radius, radius))


## The area where a floating stick may spawn: the left side, below the status panel.
func float_zone() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(0, 124, vp.x * 0.45, vp.y - 124)


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
			# the toolbar tab, then the toolbar itself (only once fully open)
			var bar := _bar()
			if show_bar and _tab_finger == -1 and (bar["tab"] as Rect2).grow(3.0).has_point(p):
				_tab_finger = event.index
				toggle_bar()
				get_viewport().set_input_as_handled()
				return
			if show_bar and bar_t >= 1.0:
				for k in bar_buttons.size():
					var bb: Dictionary = bar_buttons[k]
					if bb["finger"] == -1 and (bar["buttons"][k] as Rect2).grow(2.0).has_point(p):
						bb["finger"] = event.index
						Input.action_press(bb["action"])
						queue_redraw()
						get_viewport().set_input_as_handled()
						return
			# the main buttons
			for b in buttons:
				if b["finger"] == -1 and _button_visible(b) and _hit(b, p):
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
			for b in buttons + bar_buttons:
				if b["finger"] == event.index:
					b["finger"] = -1
					Input.action_release(b["action"])
			if event.index == _tab_finger:
				_tab_finger = -1
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
static func move_vector(mode: int, d: Vector2, radius: float, deadzone: float, vertical_assist: bool = false) -> Vector2:
	if mode == MODE_DPAD:
		if d.length() < radius * 0.22:
			return Vector2.ZERO
		var a := snappedf(d.angle(), PI / 4.0)
		var v := Vector2.RIGHT.rotated(a)
		return Vector2(signf(v.x) if absf(v.x) > 0.3 else 0.0, signf(v.y) if absf(v.y) > 0.3 else 0.0)
	var out := (d / radius).limit_length(1.0)
	if absf(out.x) <= deadzone:
		out.x = 0.0
	if vertical_assist and absf(out.y) > Balance.TOUCH_STICK_VERTICAL_MIN and absf(out.x) < absf(out.y) * Balance.TOUCH_STICK_VERTICAL_RATIO:
		out.x = 0.0
	return out


func _apply_stick() -> void:
	if stick_finger != -1:
		_vec = move_vector(move_mode(), stick_pos - stick_center, move_radius(), float(Settings.get_value("stick_deadzone")), bool(Settings.get_value("touch_stick_vertical_assist")))
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
	for b in buttons + bar_buttons:
		if b["finger"] != -1:
			Input.action_release(b["action"])
		b["finger"] = -1
	_tab_finger = -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_release_all()


func _process(delta: float) -> void:
	if mine and mine.player:
		var it: Dictionary = mine.nearest_interactable(mine.player)
		var lbl: String = it.get("label", "")
		if lbl != interact_label:
			interact_label = lbl
			queue_redraw()
	var want := 1.0 if bar_open else 0.0
	if bar_t != want:
		bar_t = move_toward(bar_t, want, delta / BAR_SLIDE)
		queue_redraw()
	elif visible and Engine.get_process_frames() % 6 == 0:
		queue_redraw()      # cooldown and lure counts on the toolbar


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
		if _hit(b, p):
			return b["action"]
	if p.distance_to(_rest_pos()) < move_radius() * 1.3:
		return "move"
	return ""


# --- drawing ----------------------------------------------------------------
func _draw() -> void:
	var op: float = Settings.get_value("touch_opacity")
	if edit_mode:
		op = 1.0
	# the metal skin reads best a little more solid than the old outlines
	op = clampf(op * 1.25, 0.0, 1.0)
	var sc := float(Settings.get_value("touch_scale"))
	var r := move_radius()
	var mode := move_mode()
	var held := stick_finger != -1
	var base := stick_center if held and mode == MODE_FLOATING else _rest_pos()
	# a resting floating stick is only a faint ghost: it shows where to touch
	var ghost := 0.45 if (mode == MODE_FLOATING and not held and not edit_mode) else 1.0
	if mode == MODE_DPAD:
		_draw_dpad(base, r, op)
	else:
		_draw_stick(base, r, op * ghost)
	for b in buttons:
		if not _button_visible(b):
			continue
		var label: String = b["name"]
		if b["action"] == "interact" and interact_label != "":
			label = interact_label
		var dim := 1.0
		if b["action"] == "ladder" and mine and mine.player and not edit_mode and not mine.player.can_build_ladder():
			dim = 0.45
		if b["action"] == "charge" and not edit_mode and Game.run.has("charges") and int(Game.run["charges"]) <= 0:
			dim = 0.45
		var bheld: bool = b["finger"] != -1 or (edit_mode and _drag_name == b["action"])
		var hw := float(b.get("hw", b["r"])) * sc
		var hh := float(b.get("hh", b["r"])) * sc
		_draw_button(_btn_pos(b), hw, hh, b["accent"], b["icon"], label, bheld, dim, op)
		if b["action"] == "charge" and Game.run.has("charges"):
			_badge(_btn_pos(b) + Vector2(hw - 10.0, -hh + 8.0), str(Game.run["charges"]), op)
	if show_bar:
		_draw_bar(op, sc)


func _draw_button(c: Vector2, hw: float, hh: float, accent: Color, icon: String, label: String, pressed: bool, dim: float, op: float) -> void:
	var push := Vector2(0, 1) if pressed else Vector2.ZERO
	HudSkin.button(self, c, hw, hh, accent, pressed, dim, op)
	var fs := clampi(int(round(hh * 0.4)), 8, 14)
	HudSkin.icon(self, icon, c + Vector2(0, -hh * 0.26) + push, hh * 0.86, op * dim)
	HudSkin.label(self, c + Vector2(0, hh * 0.6) + push, label, fs if label.length() <= 6 else maxi(8, fs - 1), Color(HudSkin.TEXT, op * dim), true)


func _badge(c: Vector2, txt: String, op: float) -> void:
	var r := Rect2((c - Vector2(6, 6)).round(), Vector2(12, 12))
	draw_colored_polygon(HudSkin.chamfer(r, 3.0), Color(HudSkin.OUTLINE, op))
	draw_colored_polygon(HudSkin.chamfer(r.grow(-1.0), 2.0), Color(HudSkin.ORANGE_DK, op))
	HudSkin.label(self, c + Vector2(0, 4), txt, 8, Color(HudSkin.TEXT, op), true)


func _draw_stick(base: Vector2, r: float, a: float) -> void:
	# a metal ring with four orange arrow notches and a dark rubber knob
	draw_circle(base, r + 4.0, Color(HudSkin.OUTLINE, 0.9 * a))
	draw_circle(base, r + 3.0, Color(HudSkin.METAL, 0.95 * a))
	draw_arc(base, r + 2.5, PI * 1.0, PI * 1.5, 12, Color(HudSkin.METAL_HI, a), 1.0)
	draw_arc(base, r + 2.5, 0.0, PI * 0.5, 12, Color(HudSkin.METAL_LO, a), 1.0)
	draw_circle(base, r, Color(0.05, 0.045, 0.08, 0.78 * a))
	draw_arc(base, r, 0, TAU, 32, Color(HudSkin.ORANGE_DK, 0.9 * a), 1.0)
	for k in 4:
		var ang := k * PI * 0.5
		var d := Vector2.RIGHT.rotated(ang)
		var side := Vector2(-d.y, d.x)
		var tip := base + d * (r - 4.0)
		draw_colored_polygon(PackedVector2Array([tip, tip - d * 5.0 + side * 4.0, tip - d * 5.0 - side * 4.0]), Color(HudSkin.ORANGE, a))
		# orange brackets on the rim between the arrows
		draw_arc(base, r + 3.0, ang + 0.6, ang + 0.97, 4, Color(HudSkin.ORANGE, 0.85 * a), 2.0)
	var knob := base + _vec * r * 0.8
	var kr := r * 0.42
	draw_circle(knob + Vector2(0, 2), kr, Color(0, 0, 0, 0.45 * a))
	draw_circle(knob, kr, Color(HudSkin.METAL_LO.lightened(0.15), a))
	draw_circle(knob, kr - 2.0, Color(HudSkin.METAL.darkened(0.1), a))
	draw_arc(knob, kr - 1.0, PI * 1.05, PI * 1.7, 10, Color(HudSkin.METAL_HI, a), 1.0)
	draw_arc(knob, kr, 0, TAU, 24, Color(HudSkin.OUTLINE, a), 1.0)


func _draw_bar(op: float, sc: float) -> void:
	var bar := _bar()
	var tab: Rect2 = bar["tab"]
	var panel: Rect2 = bar["panel"]
	if panel.position.x < get_viewport_rect().size.x:
		HudSkin.frame(self, panel, HudSkin.ORANGE, true, 5.0 * sc)
		var gid := String(Game.run.get("loadout", {}).get("active", "sonar"))
		var cd := float(Game.run.get("gadget_cd", 0.0))
		var lures := int(Game.run.get("lures", 0))
		for k in 2:
			var rect: Rect2 = bar["buttons"][k]
			var held: bool = bar_buttons[k]["finger"] != -1
			var dim := 1.0
			var icon := gid if k == 0 else "lure"
			var label := String(Balance.GADGETS.get(gid, {"name": "GADGET"})["name"]) if k == 0 else "LURE"
			if (k == 0 and cd > 0.0) or (k == 1 and lures <= 0):
				dim = 0.45
			if held:
				draw_rect(rect.grow(-1.0), Color(1, 1, 1, 0.1 * op))
			var c := rect.get_center()
			HudSkin.icon(self, icon, c + Vector2(0, -rect.size.y * 0.18), rect.size.y * 0.5, op * dim)
			HudSkin.label(self, c + Vector2(0, rect.size.y * 0.44), label, clampi(int(9 * sc), 8, 13), Color(HudSkin.TEXT, op * dim), true)
			if k == 0 and cd > 0.0:
				HudSkin.label(self, c + Vector2(rect.size.x * 0.33, -rect.size.y * 0.08), "%d" % ceili(cd), 8, Color(HudSkin.YELLOW, op), true)
			if k == 1:
				HudSkin.label(self, c + Vector2(rect.size.x * 0.33, -rect.size.y * 0.08), str(lures), 8, Color(HudSkin.CYAN if lures > 0 else HudSkin.MUTED, op), true)
		var b0: Rect2 = bar["buttons"][0]
		draw_rect(Rect2(roundf(b0.end.x), b0.position.y + 3.0, maxf(1.0, roundf(sc)), b0.size.y - 6.0), Color(HudSkin.METAL, op))
	# the tab: a small metal block whose arrow points where the bar will go
	HudSkin.frame(self, tab, HudSkin.ORANGE, false, 3.0)
	HudSkin.arrow(self, tab.get_center(), tab.size.y * 0.42, 1 if bar_open else -1, Color(HudSkin.ORANGE, op))


func _draw_dpad(c: Vector2, r: float, op: float) -> void:
	var arm := r * 0.36
	var bg := Color(HudSkin.INTERIOR, 0.8 * op)
	var pts := PackedVector2Array([
		c + Vector2(-arm, -r), c + Vector2(arm, -r), c + Vector2(arm, -arm), c + Vector2(r, -arm),
		c + Vector2(r, arm), c + Vector2(arm, arm), c + Vector2(arm, r), c + Vector2(-arm, r),
		c + Vector2(-arm, arm), c + Vector2(-r, arm), c + Vector2(-r, -arm), c + Vector2(-arm, -arm)])
	var outer := PackedVector2Array()
	for p in pts:
		outer.append(c + (p - c) * 1.08)
	draw_colored_polygon(outer, Color(HudSkin.METAL, 0.95 * op))
	draw_colored_polygon(pts, bg)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color(HudSkin.ORANGE_DK, op), 1.0)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var on: bool = _vec != Vector2.ZERO and _vec.dot(d) > 0.3
		var tip: Vector2 = c + d * (r - 6.0)
		var side: Vector2 = Vector2(-d.y, d.x) * arm * 0.55
		var back: Vector2 = c + d * (r - 6.0 - arm * 0.8)
		draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), Color(HudSkin.ORANGE.lightened(0.3 if on else 0.0), (0.95 if on else 0.6) * op))


func occupied_rects() -> Array[Rect2]:
	## Screen areas covered by controls (used by tests to check overlaps).
	var out: Array[Rect2] = []
	for b in buttons:
		out.append(_btn_rect(b))
	if show_bar:
		var bar := _bar()
		out.append(bar["tab"])
		if bar_t > 0.0:
			out.append(bar["panel"])
	return out
