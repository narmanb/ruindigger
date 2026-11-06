extends Control
## Settings terminal. Volume, screen shake, reduced flash, low-effects mode,
## touch control scale/opacity, handedness and an FPS toggle. All values persist.

var _controls: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.06, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 32)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := UiTheme.heading("SYSTEM SETTINGS", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	_add_slider(list, "master_volume", "MASTER VOLUME", 0.0, 1.0, 0.05)
	_add_slider(list, "sfx_volume", "EFFECTS VOLUME", 0.0, 1.0, 0.05)
	_add_slider(list, "screen_shake", "SCREEN SHAKE", 0.0, 2.0, 0.1)
	_add_slider(list, "button_scale", "TOUCH BUTTON SIZE", 0.7, 1.6, 0.05)
	_add_slider(list, "button_opacity", "TOUCH BUTTON OPACITY", 0.2, 1.0, 0.05)
	_add_toggle(list, "reduced_flash", "REDUCED FLASHING")
	_add_toggle(list, "low_effects", "LOW EFFECTS MODE")
	_add_toggle(list, "left_handed", "LEFT HANDED LAYOUT")
	_add_toggle(list, "touch_controls", "SHOW TOUCH CONTROLS")
	_add_toggle(list, "show_fps", "SHOW FPS")

	root.add_child(UiTheme.make_label(
		"Keyboard: A/D or arrows move, W/S aim up/down, SPACE jump, J drill, B charge, E interact, ESC pause.",
		12, Color(0.6, 0.66, 0.74)))
	root.add_child(UiTheme.make_label(
		"Gamepad: left stick move/aim, A jump, X drill, B charge, Y interact, Start pause.",
		12, Color(0.6, 0.66, 0.74)))

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	root.add_child(foot)
	var back := UiTheme.make_button("BACK", 200)
	back.pressed.connect(func():
		SaveManager.save()
		Audio.apply_settings()
		Audio.play("ui_click")
		get_tree().change_scene_to_file("res://src/ui/title_screen.tscn")
	)
	foot.add_child(back)
	var reset := UiTheme.make_button("RESET PROGRESS", 240)
	reset.pressed.connect(func():
		SaveManager.reset_progress()
		Audio.play("ui_click", 0.0, -6.0)
		_show_msg("Progress reset. Settings kept.")
	)
	foot.add_child(reset)

func _add_slider(parent: Node, key: String, label: String, mn: float, mx: float, step: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var l := UiTheme.make_label(label, 16)
	l.custom_minimum_size = Vector2(280, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(SaveManager.settings[key])
	s.custom_minimum_size = Vector2(320, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v):
		SaveManager.settings[key] = v
		SaveManager.save()
		Audio.apply_settings()
	)
	row.add_child(s)
	var val := UiTheme.make_label("%.2f" % s.value, 14, Color(1.0, 0.78, 0.36))
	s.value_changed.connect(func(v): val.text = "%.2f" % v)
	row.add_child(val)
	_controls[key] = s

func _add_toggle(parent: Node, key: String, label: String) -> void:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = bool(SaveManager.settings[key])
	cb.theme = UiTheme.theme()
	cb.add_theme_font_size_override("font_size", 16)
	cb.toggled.connect(func(v):
		SaveManager.settings[key] = v
		SaveManager.save()
		Audio.apply_settings()
	)
	parent.add_child(cb)
	_controls[key] = cb

func _show_msg(text: String) -> void:
	var l := UiTheme.make_label(text, 14, Color(0.7, 0.9, 0.7))
	add_child(l)
	l.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	l.position = Vector2(-420, -40)
	var t := get_tree().create_timer(2.0)
	t.timeout.connect(func(): l.queue_free())
