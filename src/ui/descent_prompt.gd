class_name DescentPrompt
extends CanvasLayer
## The one-way warning shown before using the Ancient Descent Platform. The
## game pauses; nothing happens unless the player chooses DESCEND.

var mine: Node
var root: Control
var is_open := false
var stay_btn: Button
var go_btn: Button


func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.theme()
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.01, 0.01, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel", UIKit.panel_box(UIKit.RED))
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UIKit.label("ANCIENT DESCENT PLATFORM", 14, Balance.ZONE_COLORS[Balance.Z_FIRST], true))
	v.add_child(UIKit.Scanline.new())
	v.add_child(UIKit.label("ONE-WAY DESCENT", 16, UIKit.RED, true))
	var body := UIKit.label("NO RETURN UNTIL THE EXIT IS FOUND.\n\nThis machine is older than the Engine. It goes down\nand it does not come back. No lift reaches that deep.\n\nEverything you carry stays at risk until you find\nand restore the Transit Gate at the bottom.\nYou can still ride a normal lift out instead.", 10, UIKit.TEXT)
	body.custom_minimum_size = Vector2(300, 0)
	v.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	stay_btn = UIKit.button("STAY", close, 120.0)
	row.add_child(stay_btn)
	go_btn = UIKit.button("DESCEND", _confirm, 120.0)
	row.add_child(go_btn)


func open() -> void:
	if is_open or mine.ending:
		return
	is_open = true
	root.visible = true
	get_tree().paused = true
	if mine.player:
		mine.player.stop_sounds()
	if mine.hud and mine.hud.touch:
		mine.hud.touch._release_all()
	Audio.play("alarm", -8.0)
	stay_btn.grab_focus()      # the safe choice is the default


func close() -> void:
	if not is_open:
		return
	is_open = false
	root.visible = false
	get_tree().paused = false
	for a in ["drill", "jump", "charge", "interact", "ladder"]:
		Input.action_release(a)


func _confirm() -> void:
	close()
	mine.begin_descent()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		close()
		get_viewport().set_input_as_handled()
