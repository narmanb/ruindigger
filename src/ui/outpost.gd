extends Control
## Outpost: the merchant/upgrade terminal. Three-plus persistent upgrades with
## clearly felt effects, purchased with banked credits.

var _credits_label: Label
var _rows: Dictionary = {}
var _msg: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.06, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := TextureRect.new()
	glow.texture = load("res://assets/bg/bg_dustworks_mid.png")
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	glow.modulate = Color(0.5, 0.45, 0.4, 0.6)
	add_child(glow)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	root.add_child(head)
	var title := UiTheme.heading("OUTPOST WORKBENCH", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_credits_label = UiTheme.make_label("CREDITS 0", 20, Color(1.0, 0.78, 0.36))
	head.add_child(_credits_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for id in Balance.UPGRADES:
		list.add_child(_make_upgrade_row(id))

	_msg = UiTheme.make_label("", 14, Color(0.7, 0.9, 0.7))
	root.add_child(_msg)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	root.add_child(foot)
	var back := UiTheme.make_button("BACK", 200)
	back.pressed.connect(func():
		Audio.play("ui_click")
		get_tree().change_scene_to_file("res://src/ui/title_screen.tscn")
	)
	foot.add_child(back)
	var dig := UiTheme.make_button("ENTER THE MINE", 260)
	dig.pressed.connect(func():
		Audio.play("ui_click")
		GameState.start_run()
		get_tree().change_scene_to_file("res://src/world/mine.tscn")
	)
	foot.add_child(dig)

func _make_upgrade_row(id: String) -> PanelContainer:
	var panel := UiTheme.make_panel(1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)
	var name_l := UiTheme.make_label(Balance.UPGRADES[id]["name"], 19, Color(0.95, 0.96, 1.0))
	info.add_child(name_l)
	var desc_l := UiTheme.make_label(Balance.UPGRADES[id]["desc"], 13, Color(0.66, 0.72, 0.8))
	info.add_child(desc_l)
	var level_l := UiTheme.make_label("", 13, Color(1.0, 0.78, 0.36))
	info.add_child(level_l)

	var buy := UiTheme.make_button("UPGRADE", 150)
	buy.pressed.connect(func():
		if SaveManager.buy(id):
			Audio.play("purchase")
			_msg.text = "%s upgraded to level %d." % [Balance.UPGRADES[id]["name"],
					SaveManager.upgrade_level(id)]
		else:
			Audio.play("ui_click", 0.0, -6.0)
			_msg.text = "Not enough credits."
		_refresh()
	)
	row.add_child(buy)
	_rows[id] = {"panel": panel, "level": level_l, "buy": buy, "desc": desc_l}
	return panel

func _refresh() -> void:
	_credits_label.text = "CREDITS %d" % SaveManager.credits
	for id in _rows:
		var lv := SaveManager.upgrade_level(id)
		var maxlv: int = Balance.UPGRADES[id]["max_level"]
		var costs: Array = Balance.UPGRADES[id]["costs"]
		var r = _rows[id]
		if lv >= maxlv:
			r["level"].text = "LEVEL %d / %d  -  MAXED" % [lv, maxlv]
			r["buy"].disabled = true
			r["buy"].text = "MAX"
		else:
			r["level"].text = "LEVEL %d / %d  -  NEXT COST %d" % [lv, maxlv, int(costs[lv])]
			r["buy"].disabled = not SaveManager.can_afford(id)
			r["buy"].text = "UPGRADE %d" % int(costs[lv])
		# Show the concrete effect so the upgrade is legible before buying.
		match id:
			"drill":
				r["desc"].text = "%s  (drill power x%.2f, tier %d)" % [
					Balance.UPGRADES[id]["desc"], Balance.drill_power(lv),
					Balance.drill_tier(lv)]
			"suit":
				r["desc"].text = "%s  (hull %d, heat x%.2f)" % [
					Balance.UPGRADES[id]["desc"], Balance.player_max_hp(lv),
					Balance.heat_capacity(lv)]
			"cargo":
				r["desc"].text = "%s  (capacity %d)" % [
					Balance.UPGRADES[id]["desc"], Balance.carry_capacity(lv)]
			"charges":
				r["desc"].text = "%s  (charges %d)" % [
					Balance.UPGRADES[id]["desc"], Balance.charge_capacity(lv)]
