extends Control
## Title screen. Plain Node scene entry point: everything is built in code so
## the project needs no hand-authored .tscn files to run.

var _bg: TextureRect
var _menu: VBoxContainer
var _settings_panel: PanelContainer
var _credits_label: Label
var _t: float = 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_bg()
	_build_title()
	_build_menu()
	_build_footer()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_bg() -> void:
	var tr := TextureRect.new()
	tr.texture = load("res://assets/bg/bg_dustworks_far.png")
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.modulate = Color(0.75, 0.75, 0.85)
	add_child(tr)
	var vig := ColorRect.new()
	vig.color = Color(0.02, 0.02, 0.04, 0.45)
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vig)

func _build_title() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(0, 90)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	var t := UiTheme.heading("RUIN DIGGER", 58)
	box.add_child(t)
	var sub := UiTheme.make_label("BREAK THE GROUND. WAKE WHAT LIES BELOW. GET OUT RICHER.",
			15, Color(0.75, 0.82, 0.9))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

func _build_menu() -> void:
	_menu = VBoxContainer.new()
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.position = Vector2(0, 40)
	_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu.add_theme_constant_override("separation", 12)
	_menu.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_menu)

	_credits_label = UiTheme.make_label("", 16, Color(1.0, 0.78, 0.36))
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(_credits_label)

	var btn_dig := _add_button("ENTER THE MINE", _on_play)
	btn_dig.theme = UiTheme.theme()
	var btn_out := _add_button("OUTPOST / UPGRADES", _on_outpost)
	var btn_set := _add_button("SETTINGS", _on_settings)
	var btn_quit := _add_button("QUIT", _on_quit)
	_update_credits()
	if btn_dig:
		btn_dig.grab_focus()

func _add_button(text: String, cb: Callable) -> Button:
	var b := UiTheme.make_button(text, 320)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		Audio.play("ui_click")
		cb.call()
	)
	_menu.add_child(b)
	return b

func _build_footer() -> void:
	var l := UiTheme.make_label("v0.1.0  |  Godot 4.6  |  original procedural art", 11,
			Color(0.5, 0.56, 0.64))
	l.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	l.position = Vector2(16, -28)
	add_child(l)

func _update_credits() -> void:
	_credits_label.text = "CREDITS  %d        BEST DEPTH  %d m        RUNS  %d" % [
		SaveManager.credits, SaveManager.best_depth * 2, SaveManager.runs_completed]

func _on_play() -> void:
	GameState.start_run()
	get_tree().change_scene_to_file("res://src/world/mine.tscn")

func _on_outpost() -> void:
	get_tree().change_scene_to_file("res://src/ui/outpost.tscn")

func _on_settings() -> void:
	get_tree().change_scene_to_file("res://src/ui/settings.tscn")

func _on_quit() -> void:
	SaveManager.save()
	get_tree().quit()

func _process(delta: float) -> void:
	_t += delta
