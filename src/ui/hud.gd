extends Control
## Industrial diagnostic HUD: health, drill heat, cargo, charges, depth, lift
## direction and the top-of-screen minimap.

var mine
var player: Player

var _hp_bar: ProgressBar
var _heat_bar: ProgressBar
var _cargo_bar: ProgressBar
var _charge_label: Label
var _depth_label: Label
var _ore_label: Label
var _lift_arrow: Label
var _objective: Label
var _toast: Label
var _toast_t: float = 0.0
var _minimap: Control
var _flash: ColorRect
var _font: FontFile

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/font/font.fnt") if ResourceLoader.exists("res://assets/font/font.fnt") else null
	_build()
	player = mine.player
	if player:
		player.health_changed.connect(_on_health)
		player.heat_changed.connect(_on_heat)
		player.charges_changed.connect(_on_charges)
		_on_health(player.hp, player.max_hp)
		_on_heat(player.heat, player.heat_capacity, false)
		_on_charges(player.charges, player.max_charges)

func _theme() -> Theme:
	var t := Theme.new()
	if _font:
		t.default_font = _font
		t.default_font_size = 14
	return t

func _build() -> void:
	var th := _theme()
	# --- Top bar -----------------------------------------------------------
	var top := PanelContainer.new()
	top.theme = th
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size = Vector2(0, 74)
	top.offset_bottom = 74
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.72)
	style.border_color = Color(0.35, 0.45, 0.55, 0.5)
	style.border_width_bottom = 2
	top.add_theme_stylebox_override("panel", style)
	add_child(top)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)

	_hp_bar = _make_bar("HULL", Color(0.86, 0.28, 0.26), 180.0)
	row.add_child(_hp_bar.get_parent())
	_heat_bar = _make_bar("DRILL", Color(1.0, 0.66, 0.24), 180.0)
	row.add_child(_heat_bar.get_parent())
	_cargo_bar = _make_bar("CARGO", Color(0.66, 0.44, 1.0), 180.0)
	row.add_child(_cargo_bar.get_parent())

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	_depth_label = _make_label("DEPTH 000 m")
	_ore_label = _make_label("ORE 0 / 0")
	_charge_label = _make_label("CHARGES 3 / 3")
	info.add_child(_depth_label)
	info.add_child(_ore_label)
	info.add_child(_charge_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_lift_arrow = _make_label("LIFT  --")
	row.add_child(_lift_arrow)

	# --- Objective banner --------------------------------------------------
	_objective = _make_label("")
	_objective.add_theme_color_override("font_color", Color(1.0, 0.78, 0.36))
	_objective.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_objective.position = Vector2(0, 84)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_objective)

	# --- Toast -------------------------------------------------------------
	_toast = _make_label("")
	_toast.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(0, -120)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toast.modulate = Color(1, 1, 1, 0)
	add_child(_toast)

	# --- Minimap (top-right, above the bar) -------------------------------
	_minimap = Control.new()
	_minimap.set_script(load("res://src/ui/minimap.gd"))
	_minimap.set("mine", mine)
	_minimap.set("compact", true)
	_minimap.custom_minimum_size = Vector2(210, 150)
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.position = Vector2(-222, 82)
	_minimap.size = Vector2(210, 150)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_minimap)

	# --- Damage / pickup flash --------------------------------------------
	_flash = ColorRect.new()
	_flash.color = Color(1, 0.2, 0.2, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = _theme()
	l.add_theme_font_size_override("font_size", 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _make_bar(title: String, color: Color, width: float) -> ProgressBar:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _make_label(title)
	l.add_theme_font_size_override("font_size", 11)
	box.add_child(l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 12)
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.11, 0.15, 0.9)
	bg.border_color = Color(0.3, 0.36, 0.44, 0.7)
	bg.set_border_width_all(1)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	box.add_child(bar)
	return bar

func _on_health(hp: int, max_hp: int) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	if hp < max_hp * 0.34:
		_hp_bar.modulate = Color(1.0, 0.6, 0.6)

func _on_heat(heat: float, capacity: float, overheated: bool) -> void:
	_heat_bar.max_value = capacity
	_heat_bar.value = heat
	_heat_bar.modulate = Color(1.4, 0.5, 0.4) if overheated else Color.WHITE

func _on_charges(count: int, capacity: int) -> void:
	_charge_label.text = "CHARGES %d / %d" % [count, capacity]

func flash_cargo(ok: bool) -> void:
	_show_toast("CARGO FULL - RETURN TO LIFT" if not ok else "ORE COLLECTED")
	if not ok:
		_flash.color = Color(1, 0.5, 0.2, 0.18)

func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_t = 1.8

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var cargo_units := GameState.cargo_units
	var cap := Balance.carry_capacity(SaveManager.upgrade_level("cargo"))
	_cargo_bar.max_value = cap
	_cargo_bar.value = cargo_units
	_ore_label.text = "ORE %d / %d" % [cargo_units, cap]
	_depth_label.text = "DEPTH %03d m" % (player.grid.world_to_cell(player.global_position).y * 2)

	# Lift direction: a simple signed arrow with distance in cells.
	var lift_world := player.grid.cell_to_world(player.grid.lift_cell)
	var d := lift_world - player.global_position
	var dist := int(d.length() / Balance.CELL)
	var dir := ""
	if absf(d.x) > Balance.CELL:
		dir += ("E" if d.x > 0 else "W")
	if absf(d.y) > Balance.CELL:
		dir += ("S" if d.y > 0 else "N")
	_lift_arrow.text = "LIFT %s %d m" % [dir, dist * 2]
	if dist < 3:
		_lift_arrow.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
		if GameState.has_banked_cargo():
			_lift_arrow.text += "  [E] EXTRACT"
	else:
		_lift_arrow.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))

	if GameState.relic_taken:
		_objective.text = "RELIC SECURED - RETURN TO THE LIFT"
	else:
		_objective.text = "DESCEND - FIND THE RELIC"

	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	else:
		_toast.modulate.a = maxf(0.0, _toast.modulate.a - delta * 2.0)
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 1.4)
