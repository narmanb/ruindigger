class_name SettingsPanel
extends PanelContainer
## Scrollable options list shared by the title screen and pause menu.

signal closed

var first_focus: Control


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(330, 0)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)
	outer.add_child(UIKit.header("SYSTEM SETTINGS"))
	outer.add_child(UIKit.Scanline.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 210)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	_slider(list, "Button size", "touch_scale", 0.7, 1.5, 0.05)
	_slider(list, "Button opacity", "touch_opacity", 0.25, 1.0, 0.05)
	var back := UIKit.button("BACK", func() -> void:
		closed.emit()
		queue_free())
	outer.add_child(back)
	await get_tree().process_frame
	if first_focus:
		first_focus.grab_focus()


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
