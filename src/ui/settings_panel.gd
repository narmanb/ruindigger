class_name SettingsPanel
extends PanelContainer
## Scrollable options list shared by the title screen and pause menu.

signal closed

var first_focus: Control


func _ready() -> void:
	theme = UIKit.theme()
	custom_minimum_size = Vector2(330, 0)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)
	outer.add_child(UIKit.header("SYSTEM SETTINGS " + str(ProjectSettings.get_setting("application/config/version"))))
	outer.add_child(UIKit.Scanline.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, clampf(get_viewport_rect().size.y - 130.0, 120.0, 210.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.follow_focus = true
	# A separate, wide drag lane keeps scrolling clear of sliders and switches.
	var bar := scroll.get_v_scroll_bar()
	var track := StyleBoxFlat.new()
	track.bg_color = UIKit.PANEL_EDGE
	track.content_margin_left = 16
	track.content_margin_right = 16
	bar.add_theme_stylebox_override("scroll", track)
	var handle := StyleBoxFlat.new()
	handle.bg_color = UIKit.AMBER
	handle.set_content_margin_all(16)
	handle.content_margin_top = 20
	handle.content_margin_bottom = 20
	bar.add_theme_stylebox_override("grabber", handle)
	bar.add_theme_stylebox_override("grabber_highlight", handle)
	var pressed: StyleBoxFlat = handle.duplicate()
	pressed.bg_color = UIKit.TEAL
	bar.add_theme_stylebox_override("grabber_pressed", pressed)
	outer.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	_slider(list, "Master volume", "master_volume", 0.0, 1.0, 0.05)
	_slider(list, "Effects volume", "sfx_volume", 0.0, 1.0, 0.05)
	_slider(list, "Music volume", "music_volume", 0.0, 1.0, 0.05)
	_slider(list, "Screen shake", "screen_shake", 0.0, 1.0, 0.1)
	_toggle(list, "Reduced flashing", "reduced_flashing")
	_toggle(list, "Low effects mode", "low_effects")
	_toggle(list, "30 FPS cap (battery)", "fps_30")
	_toggle(list, "Show FPS", "show_fps")
	var row := HBoxContainer.new()
	row.add_child(_name("Touch controls"))
	var ob := OptionButton.new()
	ob.add_item("Auto", 0)
	ob.add_item("Always", 1)
	ob.add_item("Hidden", 2)
	ob.selected = int(Settings.get_value("touch_mode"))
	ob.custom_minimum_size = Vector2(110, 24)
	ob.item_selected.connect(func(i: int) -> void: Settings.set_value("touch_mode", i))
	row.add_child(ob)
	list.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_child(_name("Movement control"))
	var mc := OptionButton.new()
	mc.add_item("Fixed stick", 0)
	mc.add_item("Floating stick", 1)
	mc.add_item("D-pad", 2)
	mc.selected = int(Settings.get_value("move_control"))
	mc.custom_minimum_size = Vector2(110, 24)
	mc.item_selected.connect(func(i: int) -> void: Settings.set_value("move_control", i))
	row2.add_child(mc)
	list.add_child(row2)
	_toggle(list, "Jump grabs ladders (falling)", "jump_grabs_ladders")
	_slider(list, "Stick / D-pad size", "stick_size", 0.6, 1.8, 0.05)
	_slider(list, "Stick dead zone", "stick_deadzone", 0.05, 0.35, 0.01)
	_slider(list, "Button size", "touch_scale", 0.7, 1.5, 0.05)
	_slider(list, "Control opacity", "touch_opacity", 0.25, 1.0, 0.05)
	list.add_child(UIKit.button("EDIT TOUCH LAYOUT", _edit_layout, 200.0))
	_slider(list, "Camera zoom", "camera_zoom", 1.0, 1.8, 0.05)
	var back := UIKit.button("BACK", func() -> void:
		closed.emit()
		queue_free())
	outer.add_child(back)
	_center()
	get_viewport().size_changed.connect(_center)
	await get_tree().process_frame
	_center()
	if first_focus:
		first_focus.grab_focus()


func _edit_layout() -> void:
	var ed: Node = load("res://src/ui/layout_editor.gd").new()
	visible = false
	get_tree().root.add_child(ed)
	ed.tree_exited.connect(func() -> void:
		visible = true
		if first_focus:
			first_focus.grab_focus())


## Centre on the screen from the panel's real minimum size. (Setting anchors
## after the panel is already in the tree keeps its old position, which is what
## pushed it into the top-left corner.)
func _center() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var ms := get_combined_minimum_size()
	ms.x = minf(ms.x, vp.x - 12.0)
	ms.y = minf(ms.y, vp.y - 12.0)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -ms.x * 0.5
	offset_right = ms.x * 0.5
	offset_top = -ms.y * 0.5
	offset_bottom = ms.y * 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH


func _name(t: String) -> Label:
	var l := UIKit.label(t, 11)
	l.custom_minimum_size = Vector2(150, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _slider(list: Control, title: String, key: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	row.add_child(_name(title))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(120, 22)
	s.focus_mode = Control.FOCUS_ALL
	var val := UIKit.label("%d%%" % int(s.value * 100.0 / (hi if hi > 1.0 else 1.0)), 10, UIKit.AMBER)
	val.custom_minimum_size = Vector2(36, 0)
	s.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, v)
		val.text = "%d%%" % int(v * 100.0 / (hi if hi > 1.0 else 1.0)) if hi <= 1.0 else "%.2fx" % v)
	if hi > 1.0:
		val.text = "%.2fx" % s.value
	row.add_child(s)
	row.add_child(val)
	list.add_child(row)
	if first_focus == null:
		first_focus = s


func _toggle(list: Control, title: String, key: String) -> void:
	var c := CheckButton.new()
	c.text = title
	c.button_pressed = bool(Settings.get_value(key))
	c.focus_mode = Control.FOCUS_ALL
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	list.add_child(c)
