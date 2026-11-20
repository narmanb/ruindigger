class_name HintStrip
extends Control
## The contextual hint line: a small see-through strip under the top HUD row,
## clear of the player (screen centre) and the touch buttons (bottom corners).
## One line at a time, with a gap between hints; codex notices use it too.
## A hint is only marked seen once it has actually been on screen.

var busy: Callable                 # returns true while now is a bad moment (a fight)
var avoid: Callable                # returns the player's rect on screen; the strip keeps off it
var top := Balance.HINT_TOP
var queue: Array = []              # {id, text, notice}
var showing: Dictionary = {}
var shown: Array = []              # ids shown this session (tests)
var _t := 0.0
var _gap := 1.0
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -Balance.HINT_WIDTH * 0.5
	offset_right = Balance.HINT_WIDTH * 0.5
	offset_top = top
	offset_bottom = top + 40
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := UIKit.panel_box(UIKit.TEAL, Color(0.05, 0.04, 0.07, 0.62))
	box.set_content_margin_all(4)
	box.content_margin_left = 8
	box.content_margin_right = 8
	_panel.add_theme_stylebox_override("panel", box)
	add_child(_panel)
	_label = UIKit.label("", 10, UIKit.TEAL)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	modulate.a = 0.0


## Queue a hint by id. False when hints are off, it was seen, or it is queued.
func hint(id: String) -> bool:
	if not bool(Settings.get_value("hints")) or Progress.seen_hint(id) or not CodexData.HINTS.has(id):
		return false
	if String(showing.get("id", "")) == id:
		return false
	for q: Dictionary in queue:
		if q["id"] == id:
			return false
	queue.append({"id": id, "text": String(CodexData.HINTS[id]), "notice": false})
	return true


## A short notice ("CODEX: Eel added"). Shown even with hints off.
func notice(text: String) -> void:
	queue.append({"id": "", "text": text, "notice": true})


func is_showing() -> bool:
	return not showing.is_empty()


func _process(delta: float) -> void:
	if not showing.is_empty():
		_place()
		_t -= delta
		modulate.a = clampf(minf(_t, Balance.HINT_SHOW - _t) * 3.0, 0.0, 1.0)
		if _t <= 0.0:
			_gap = Balance.NOTICE_GAP if bool(showing["notice"]) else Balance.HINT_GAP
			showing = {}
			modulate.a = 0.0
		return
	_gap -= delta
	if _gap > 0.0 or queue.is_empty():
		return
	# notices go first; hints wait out a fight
	var pick := -1
	for i in queue.size():
		if bool(queue[i]["notice"]):
			pick = i
			break
	if pick < 0:
		if busy.is_valid() and bool(busy.call()):
			return
		pick = 0
	showing = queue[pick]
	queue.remove_at(pick)
	var id := String(showing["id"])
	if id != "":
		if Progress.seen_hint(id):
			showing = {}
			return
		Progress.mark_hint(id)
		shown.append(id)
	_t = Balance.HINT_SHOW
	_label.text = String(showing["text"])
	_label.add_theme_color_override("font_color", UIKit.AMBER if bool(showing["notice"]) else UIKit.TEAL)
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var w := _label.get_minimum_size().x
	if w > Balance.HINT_WIDTH - 16.0:
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.custom_minimum_size.x = minf(Balance.HINT_WIDTH - 16.0, w * 0.56 + 8.0)   # two even lines
	else:
		_label.custom_minimum_size.x = 0.0
	_panel.reset_size()
	_panel.offset_left = -_panel.get_combined_minimum_size().x * 0.5
	_panel.offset_right = _panel.get_combined_minimum_size().x * 0.5


## Under the top HUD normally; if the player is up there (a high zoom, a
## camera catching up), drop to the gap between the stick and the buttons.
func _place() -> void:
	var y := top
	if avoid.is_valid():
		var pr: Rect2 = avoid.call()
		var mine_rect := Rect2(global_position.x + _panel.position.x, top, _panel.size.x, _panel.size.y + 4.0)
		if pr.size != Vector2.ZERO and pr.intersects(mine_rect):
			y = get_viewport_rect().size.y - Balance.HINT_LOW - _panel.size.y
	offset_top = y
	offset_bottom = y + 40
