extends CanvasLayer
## Pause: resume, full map, settings, abandon. Shows the seed for bug reports.

var mine: Node
var root: Control
var panel: PanelContainer
var map_view: Minimap
var resume_btn: Button
var is_open := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.theme()
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.03, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_CENTER)
	hb.add_theme_constant_override("separation", 10)
	hb.anchor_left = 0.5
	hb.anchor_top = 0.5
	hb.anchor_right = 0.5
	hb.anchor_bottom = 0.5
	hb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hb.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(hb)
	panel = PanelContainer.new()
	hb.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UIKit.header("PAUSED"))
	v.add_child(UIKit.Scanline.new())
	resume_btn = UIKit.button("RESUME", close)
	v.add_child(resume_btn)
	v.add_child(UIKit.button("SETTINGS", _settings))
	v.add_child(UIKit.button("ABANDON RUN", _abandon))
	var c: Dictionary = Game.run.get("contract", {})
	v.add_child(UIKit.label("Contract: %s" % c.get("name", "?"), 9, UIKit.MUTED))
	v.add_child(UIKit.label("Seed: %d" % int(Game.run.get("seed", 0)), 9, UIKit.MUTED))
	v.add_child(UIKit.label("Unbanked cargo is lost if\nyou abandon or die.", 9, UIKit.MUTED))
	var mp := PanelContainer.new()
	hb.add_child(mp)
	var mv := VBoxContainer.new()
	mp.add_child(mv)
	mv.add_child(UIKit.header("SURVEY MAP"))
	map_view = Minimap.new()
	map_view.full = true
	map_view.custom_minimum_size = Vector2(110, 250)
	mv.add_child(map_view)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if is_open:
			close()
		elif not mine.ending:
			open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and not is_open and not mine.ending:
		open()
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if mine and not mine.ending and not is_open and is_inside_tree():
			open()


func open() -> void:
	if is_open:
		return
	is_open = true
	if map_view.mine == null:
		# share the HUD minimap texture instead of building a second one
		map_view.mine = mine
		map_view.grid = mine.grid
		map_view.img = mine.hud.minimap.img
		map_view.tex = mine.hud.minimap.tex
		map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_view.set_process(false)
	map_view.queue_redraw()
	root.visible = true
	get_tree().paused = true
	if mine.player:
		mine.player.stop_sounds()
	Audio.play("ui_click")
	resume_btn.grab_focus()


func close() -> void:
	is_open = false
	root.visible = false
	get_tree().paused = false
	for a in ["drill", "jump", "charge", "interact"]:
		Input.action_release(a)


func _settings() -> void:
	var layout := panel.get_parent() as Control   # pause panel + survey map
	layout.visible = false
	var sp := SettingsPanel.new()
	root.add_child(sp)
	sp.closed.connect(func() -> void:
		layout.visible = true
		resume_btn.grab_focus())


func _abandon() -> void:
	close()
	mine.abandon()
