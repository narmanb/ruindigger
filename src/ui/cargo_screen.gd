class_name CargoScreen
extends CanvasLayer
## A paused manifest shared by touch, keyboard and the controller pause menu.

var mine: Node
var root: Control
var rows: VBoxContainer
var total_label: Label
var capacity_label: Label
var relic_label: Label
var close_btn: Button
var scroll: ScrollContainer
var is_open := false
var _was_paused := false
var _scroll_fraction := 0.0


func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.theme()
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.03, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 10
	panel.offset_top = 10
	panel.offset_right = -10
	panel.offset_bottom = -10
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := UIKit.label("CARGO MANIFEST", 17, UIKit.AMBER, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	close_btn = UIKit.button("CLOSE", close, 80)
	close_btn.custom_minimum_size.y = 32
	header.add_child(close_btn)
	capacity_label = UIKit.label("", 11, UIKit.TEXT)
	column.add_child(capacity_label)
	total_label = UIKit.label("", 13, UIKit.TEAL, true)
	column.add_child(total_label)
	relic_label = UIKit.label("", 11, UIKit.AMBER)
	column.add_child(relic_label)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 40
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.follow_focus = true
	column.add_child(scroll)
	UIKit.touch_scrollbar(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	var note := UIKit.label("Unbanked cargo is lost on death or abandonment. Extract to bank it.\nD-pad / arrows scroll. Back closes.", 10, UIKit.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)


func refresh() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var cargo: Dictionary = Game.run.get("cargo", {})
	var ore_value := Game.cargo_value(cargo)
	var relic_value := int(Game.contract.get("reward", Balance.RELIC_BONUS)) if Game.run.get("relic", false) else 0
	var finds: Array = Game.run.get("finds", [])
	capacity_label.text = "ORE RACK: %d / %d    KEEPSAKES: %d / %d" % [Game.cargo_count(), mine.cargo_cap(), finds.size(), Balance.KEEPSAKES.size()]
	total_label.text = "EXTRACT NOW: %d CR" % (ore_value + relic_value + Game.finds_value(finds))
	relic_label.text = "Relic secured: +%d CR" % relic_value if Game.run.get("relic", false) else "Relic not recovered - bonus not included"
	for id in Balance.ORE:
		var info: Dictionary = Balance.ORE[id]
		var n := int(cargo.get(id, 0))
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 30
		rows.add_child(row)
		var icon := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = load("res://assets/gen/pickups.png")
		var width := atlas.atlas.get_width() / 5
		atlas.region = Rect2((int(id) - 1) * width, 0, width, atlas.atlas.get_height())
		icon.texture = atlas
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var name_label := UIKit.label(str(info["name"]), 12, Balance.ore_color(id) if n > 0 else UIKit.MUTED)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(UIKit.label("x%d @ %d CR    %d CR" % [n, info["value"], n * int(info["value"])], 11, UIKit.TEXT if n > 0 else UIKit.MUTED))
	if cargo.is_empty():
		rows.add_child(UIKit.label("Your ore rack is empty.", 11, UIKit.MUTED))
	rows.add_child(UIKit.Scanline.new())
	rows.add_child(UIKit.label("ZONE KEEPSAKES - separate pouch", 12, UIKit.TEAL, true))
	if finds.is_empty():
		var hint := UIKit.label("Look for small glowing keepsakes in optional rooms. Recover them with USE.", 11, UIKit.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(hint)
	for id in finds:
		var info: Dictionary = Balance.KEEPSAKES[id]
		var name_label := UIKit.label("%s  +%d CR" % [info["name"], info["value"]], 12, Color(info["color"]))
		rows.add_child(name_label)
		var description := UIKit.label(info["desc"], 11, UIKit.MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(description)


func open() -> void:
	if is_open or mine.ending or mine.hud.map_screen.is_open:
		return
	_was_paused = get_tree().paused
	if _was_paused and not mine.pause_menu.is_open:
		return
	is_open = true
	_scroll_fraction = 0.0
	refresh()
	root.visible = true
	if mine.pause_menu.is_open:
		mine.pause_menu.root.visible = false
	get_tree().paused = true
	mine.player.stop_sounds()
	mine.hud.touch._release_all()
	close_btn.grab_focus()
	Audio.play("ui_click")


func close() -> void:
	if not is_open:
		return
	is_open = false
	root.visible = false
	mine.hud.touch._release_all()
	get_tree().paused = _was_paused
	for action in ["drill", "jump", "charge", "interact", "ladder"]:
		Input.action_release(action)
	if _was_paused and mine.pause_menu.is_open:
		mine.pause_menu.root.visible = true
		mine.pause_menu.resume_btn.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory") or event.is_action_pressed("pause")):
		close()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if is_open and (event.is_action("ui_up") or event.is_action("ui_down")):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open:
		return
	var direction := Input.get_axis("ui_up", "ui_down")
	if is_zero_approx(direction):
		_scroll_fraction = 0.0
		return
	_scroll_fraction += direction * Balance.CARGO_SCROLL_SPEED * delta
	var amount := int(_scroll_fraction)
	scroll.scroll_vertical += amount
	_scroll_fraction -= amount
