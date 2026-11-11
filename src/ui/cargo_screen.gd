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
var is_open := false
var _was_paused := false


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
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 40
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.follow_focus = true
	column.add_child(scroll)
	# Match the proven finger-sized scrollbar in Settings.
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
	for style in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(style, handle)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	var note := UIKit.label("Unbanked cargo is lost on death or abandonment. Extract at a lift to bank it.", 10, UIKit.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)


func refresh() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var cargo: Dictionary = Game.run.get("cargo", {})
	var ore_value := Game.cargo_value(cargo)
	var relic_value := int(Game.contract.get("reward", Balance.RELIC_BONUS)) if Game.run.get("relic", false) else 0
	capacity_label.text = "ORE RACK: %d / %d units" % [Game.cargo_count(), mine.cargo_cap()]
	total_label.text = "EXTRACT NOW: %d CR" % (ore_value + relic_value)
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


func open() -> void:
	if is_open or mine.ending or mine.hud.map_screen.is_open:
		return
	_was_paused = get_tree().paused
	if _was_paused and not mine.pause_menu.is_open:
		return
	is_open = true
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
	if _was_paused and mine.pause_menu.is_open:
		mine.pause_menu.root.visible = true
		mine.pause_menu.resume_btn.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory") or event.is_action_pressed("pause")):
		close()
		get_viewport().set_input_as_handled()
