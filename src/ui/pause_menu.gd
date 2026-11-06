extends CanvasLayer
## In-run pause overlay: full map, resume, restart and abandon.

var mine
var _panel: PanelContainer
var _map: Control
var _map_open: bool = true

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func open() -> void:
	visible = true
	get_tree().paused = true
	_build()
	Audio.play("ui_click")

func close() -> void:
	visible = false
	get_tree().paused = false
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
		_panel = null
		_map = null

func _build() -> void:
	if _panel and is_instance_valid(_panel):
		return
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = UiTheme.make_panel(1)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-330, -240)
	_panel.custom_minimum_size = Vector2(660, 480)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	v.add_child(UiTheme.heading("PAUSED", 28))

	var map_holder := Control.new()
	map_holder.custom_minimum_size = Vector2(620, 260)
	v.add_child(map_holder)
	_map = Control.new()
	_map.set_script(load("res://src/ui/minimap.gd"))
	_map.set("mine", mine)
	_map.set("compact", false)
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_holder.add_child(_map)

	v.add_child(UiTheme.make_label("Seed: %d      Depth: %d m      Credits in cargo: %d" % [
		GameState.seed_value,
		mine.grid.world_to_cell(mine.player.global_position).y * 2,
		GameState.cargo_value()], 14, Color(0.7, 0.76, 0.84)))
	v.add_child(UiTheme.make_label("Relic: %s" % ("SECURED" if GameState.relic_taken else "NOT FOUND"),
		14, Color(0.72, 0.5, 1.0)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var resume := UiTheme.make_button("RESUME", 160)
	resume.pressed.connect(func():
		Audio.play("ui_click")
		close()
	)
	row.add_child(resume)
	var restart := UiTheme.make_button("RESTART RUN", 180)
	restart.pressed.connect(func():
		Audio.play("ui_click")
		get_tree().paused = false
		GameState.start_run()
		get_tree().reload_current_scene()
	)
	row.add_child(restart)
	var abandon := UiTheme.make_button("ABANDON TO OUTPOST", 240)
	abandon.pressed.connect(func():
		Audio.play("ui_click")
		get_tree().paused = false
		GameState.end_run(false, "abandoned")
		get_tree().change_scene_to_file("res://src/ui/outpost.tscn")
	)
	row.add_child(abandon)
	resume.grab_focus()
