extends Control
## End-of-run summary (extraction or death).

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	var r: Dictionary = Game.last_result
	var ok: bool = r.get("extracted", false)
	Audio.music("amb_outpost")
	Audio.play("ui_buy" if ok else "ui_deny")
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel", UIKit.panel_box(UIKit.AMBER if ok else UIKit.RED))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(UIKit.label("EXTRACTION COMPLETE" if ok else "SIGNAL LOST", 20, UIKit.AMBER if ok else UIKit.RED, true))
	v.add_child(UIKit.label(str(r.get("contract", "")), 10, UIKit.MUTED, true))
	v.add_child(UIKit.Scanline.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if not ok:
		list.add_child(UIKit.label("Cause: %s" % r.get("cause", "unknown"), 11, UIKit.TEXT))
	var cargo: Dictionary = r.get("cargo", {})
	if cargo.is_empty():
		list.add_child(UIKit.label("No cargo recovered.", 11, UIKit.MUTED))
	for k in cargo.keys():
		var info: Dictionary = Balance.ORE[int(k)]
		var n := int(cargo[k])
		var line := "%-10s x%-3d  %s" % [info["name"], n, ("%d CR" % (n * int(info["value"]))) if ok else "LOST"]
		list.add_child(UIKit.label(line, 11, Balance.ore_color(int(k)) if ok else UIKit.MUTED))
	if r.get("relic", false):
		list.add_child(UIKit.label("Relic recovered: +%d CR" % r.get("relic_bonus", 0) if ok else "Relic lost in the dark", 11, Color(0.4, 1.0, 1.0)))
	list.add_child(UIKit.label("Depth %dm   Time %s   Kills %d" % [r.get("depth", 0), _time(r.get("time", 0.0)), r.get("kills", 0)], 10, UIKit.MUTED))
	list.add_child(UIKit.label("Seed %d" % r.get("seed", 0), 9, UIKit.MUTED))
	var total: int = int(r.get("credits", 0)) + int(r.get("relic_bonus", 0))
	v.add_child(UIKit.label("EARNED: %d CR    BALANCE: %d CR" % [total, Progress.credits], 12, UIKit.TEAL, true))
	var b := UIKit.button("RETURN TO OUTPOST", func() -> void: Game.goto("outpost"), 200)
	v.add_child(b)
	await get_tree().process_frame
	b.grab_focus()


func _time(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]
