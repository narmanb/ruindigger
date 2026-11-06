extends Control
## End-of-run summary: extraction (cargo banked) or death (cargo lost).

var result: Dictionary = {}

func setup(res: Dictionary) -> void:
	result = res
	_build()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build() -> void:
	var extracted := bool(result.get("extracted", false))
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.07, 1.0) if extracted else Color(0.09, 0.04, 0.05, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UiTheme.make_panel(1 if extracted else 4)
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	var head := "EXTRACTED" if extracted else "SUIT DESTROYED"
	v.add_child(UiTheme.heading(head, 34))
	if not extracted:
		v.add_child(UiTheme.make_label("Cause: %s" % str(result.get("cause", "unknown")),
				14, Color(1.0, 0.6, 0.55)))

	var cargo: Dictionary = result.get("cargo", {})
	if cargo.size() > 0:
		v.add_child(UiTheme.make_label("CARGO MANIFEST", 16, Color(0.8, 0.85, 0.92)))
		for id in cargo:
			var name := str(Balance.ORE_TYPES[id]["name"])
			var cnt := int(cargo[id])
			var val := int(Balance.ORE_TYPES[id]["value"]) * cnt
			v.add_child(UiTheme.make_label("   %-14s x%-3d  %5d" % [name, cnt, val],
					14, Color(0.78, 0.82, 0.9)))
	else:
		v.add_child(UiTheme.make_label("   (no cargo recovered)", 14, Color(0.6, 0.64, 0.72)))

	if bool(result.get("relic", false)):
		v.add_child(UiTheme.make_label("   RELIC SECURED            %5d" % int(result.get("relic_bonus", 0)),
				15, Color(0.75, 0.5, 1.0)))

	v.add_child(UiTheme.make_label("", 6))
	v.add_child(UiTheme.make_label("Cargo value:  %d" % int(result.get("cargo_value", 0)),
			16, Color(1.0, 0.9, 0.6)))
	if extracted:
		v.add_child(UiTheme.make_label("BANKED:  +%d credits" % int(result.get("banked", 0)),
				20, Color(0.5, 1.0, 0.6)))
	else:
		v.add_child(UiTheme.make_label("UNBANKED CARGO LOST:  %d" % int(result.get("cargo_value", 0)),
				16, Color(1.0, 0.45, 0.4)))
	v.add_child(UiTheme.make_label("Depth reached: %d m      Time: %s      Seed: %d" % [
		int(result.get("depth", 0)) * 2,
		_format_time(float(result.get("elapsed", 0.0))),
		int(result.get("seed", 0))], 13, Color(0.62, 0.68, 0.76)))
	v.add_child(UiTheme.make_label("Total credits: %d" % SaveManager.credits, 14,
			Color(1.0, 0.78, 0.36)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var again := UiTheme.make_button("NEW RUN", 170)
	again.pressed.connect(func():
		Audio.play("ui_click")
		GameState.start_run()
		get_tree().change_scene_to_file("res://src/world/mine.tscn")
	)
	row.add_child(again)
	var out := UiTheme.make_button("OUTPOST", 170)
	out.pressed.connect(func():
		Audio.play("ui_click")
		get_tree().change_scene_to_file("res://src/ui/outpost.tscn")
	)
	row.add_child(out)
	var title := UiTheme.make_button("TITLE", 150)
	title.pressed.connect(func():
		Audio.play("ui_click")
		get_tree().change_scene_to_file("res://src/ui/title_screen.tscn")
	)
	row.add_child(title)
	again.grab_focus()

func _format_time(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	return "%d:%02d" % [m, s]
