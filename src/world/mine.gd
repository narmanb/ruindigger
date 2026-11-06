class_name Mine
extends Node2D
## Assembles a complete playable mine from a seed: terrain, player, camera,
## parallax, props, enemies, hazards, HUD, minimap and the extraction lift.

signal run_finished(result: Dictionary)

const WIDTH_CELLS := 168
const HEIGHT_CELLS := 132

var seed_value: int = 0
var grid: TerrainGrid
var renderer: TerrainRenderer
var player: Player
var camera: Camera2D
var hud: CanvasLayer
var minimap: Control
var world: Node2D
var bg: Node2D
var collapse: CollapseSystem
var lift_node: Node2D
var relic_node: Node2D
var pause_menu: CanvasLayer
var touch: Control
var result_layer: CanvasLayer
var _gen_result
var _finished := false
var _fps_label: Label

func _ready() -> void:
	seed_value = GameState.seed_value
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	_build_background()
	_build_terrain()
	_build_props()
	_build_player()
	_build_camera()
	_build_hazards()
	_spawn_enemies()
	_build_hud()
	_build_touch()
	_build_pause()
	_build_fps()
	Fx.register_root(world)
	renderer.reveal(player.global_position, 7.0)
	renderer.refresh_all()
	Audio.drill(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if pause_menu and pause_menu.visible:
			pause_menu.close()
		elif not _finished and pause_menu:
			pause_menu.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart") and not _finished:
		GameState.start_run()
		get_tree().reload_current_scene()

func _exit_tree() -> void:
	Fx.clear_root()

func _build_touch() -> void:
	if not bool(SaveManager.settings.get("touch_controls", true)):
		return
	var c := Control.new()
	c.set_script(load("res://src/ui/touch_controls.gd"))
	c.set("mine", self)
	c.set("player", player)
	c.name = "TouchControls"
	add_child(c)
	touch = c

func _build_pause() -> void:
	pause_menu = CanvasLayer.new()
	pause_menu.set_script(load("res://src/ui/pause_menu.gd"))
	pause_menu.set("mine", self)
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)

func _build_fps() -> void:
	_fps_label = UiTheme.make_label("", 12, Color(0.6, 0.9, 0.6))
	_fps_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_fps_label.position = Vector2(10, -22)
	add_child(_fps_label)

func _build_background() -> void:
	bg = Node2D.new()
	bg.name = "Parallax"
	bg.z_index = -20
	add_child(bg)
	var layer_names := ["far", "mid", "near"]
	var speeds := [0.08, 0.22, 0.45]
	for i in layer_names.size():
		var layer := ParallaxLayer.new()
		layer.motion_scale = Vector2(speeds[i], speeds[i] * 0.6)
		layer.motion_mirroring = Vector2(512, 0)
		var spr := Sprite2D.new()
		var tex: Texture2D = load("res://assets/bg/bg_%s_%s.png" % [_stratum_name(), layer_names[i]])
		spr.texture = tex
		spr.centered = false
		spr.modulate = Color(1, 1, 1, 0.95 if i < 2 else 0.8)
		layer.add_child(spr)
		bg.add_child(layer)

func _stratum_name() -> String:
	return "dustworks"

func _build_terrain() -> void:
	_gen_result = WorldGen.generate(seed_value, WIDTH_CELLS, HEIGHT_CELLS)
	grid = _gen_result.grid
	renderer = TerrainRenderer.new()
	renderer.name = "TerrainRenderer"
	world.add_child(renderer)
	renderer.setup(grid)
	var bodies := Node2D.new()
	bodies.name = "TerrainBodies"
	world.add_child(bodies)
	grid.build_collision(bodies)

func _build_props() -> void:
	# The lift sprite is centred on the lift cab so the player can stand inside
	# it, which is what the extraction check measures against.
	lift_node = _sprite_node("res://assets/sprites/elevator_sheet.png",
			grid.cell_to_world(grid.lift_cell),
			Vector2(3, 4))
	world.add_child(lift_node)
	relic_node = _sprite_node("res://assets/sprites/relic_sheet.png",
			grid.cell_to_world(grid.relic_cell) + Vector2(0, -8), Vector2(2, 2), true)
	world.add_child(relic_node)
	relic_node.add_to_group("relic")

func _sprite_node(path: String, pos: Vector2, cells: Vector2, animate: bool = false) -> Node2D:
	var holder := Node2D.new()
	holder.position = pos
	var spr := Sprite2D.new()
	spr.texture = load(path)
	spr.centered = true
	if cells != Vector2(1, 1):
		spr.region_enabled = true
		spr.region_rect = Rect2(0, 0, Balance.CELL * cells.x, Balance.CELL * cells.y)
	holder.add_child(spr)
	if animate:
		var tween := holder.create_tween()
		tween.set_loops()
		tween.tween_property(spr, "position:y", -4.0, 1.1).set_trans(Tween.TRANS_SINE)
		tween.tween_property(spr, "position:y", 0.0, 1.1).set_trans(Tween.TRANS_SINE)
	return holder

func _build_player() -> void:
	player = Player.new()
	player.name = "Player"
	player.grid = grid
	player.renderer = renderer
	player.world = world
	player.configure_from_save()
	player.global_position = grid.cell_to_world(grid.spawn_cell)
	world.add_child(player)
	player.died.connect(_on_player_died)
	player.extracted.connect(_on_extracted)
	player.cargo_pickup.connect(_on_cargo_pickup)
	grid.ore_mined.connect(_on_ore_mined)

func _build_camera() -> void:
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.limit_left = 0
	camera.limit_top = -Balance.CELL * 8
	camera.limit_right = grid.w * Balance.CELL
	camera.limit_bottom = grid.h * Balance.CELL
	camera.zoom = Vector2(1.35, 1.35)
	camera.position = Vector2.ZERO
	player.add_child(camera)
	camera.make_current()

func _build_hazards() -> void:
	collapse = CollapseSystem.new()
	collapse.name = "Collapse"
	world.add_child(collapse)
	collapse.setup(grid, renderer, player, func(_cluster):
		renderer.refresh_all()
	)

func _spawn_enemies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x5A5A
	for i in 10:
		var c := BurrowCrawler.new()
		c.grid = grid
		c.player = player
		var pos := _random_open_cell(rng, 12)
		if pos.x < 0:
			continue
		c.global_position = grid.cell_to_world(pos)
		c.died.connect(_on_enemy_died)
		world.add_child(c)
	for i in 8:
		var s := RuinSentry.new()
		s.grid = grid
		s.player = player
		var pos := _random_open_cell(rng, 8)
		if pos.x < 0:
			continue
		s.global_position = grid.cell_to_world(pos)
		s.died.connect(_on_enemy_died)
		world.add_child(s)

func _random_open_cell(rng: RandomNumberGenerator, tries: int) -> Vector2i:
	for i in tries:
		var x := rng.randi_range(6, grid.w - 7)
		var y := rng.randi_range(12, grid.h - 8)
		if grid.get_material(x, y) == Balance.Mat.EMPTY and \
				grid.get_material(x, y + 1) != Balance.Mat.EMPTY:
			if Vector2(x, y).distance_to(Vector2(grid.spawn_cell)) > 14.0:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 10
	add_child(hud)
	var h := Control.new()
	h.set_script(load("res://src/ui/hud.gd"))
	h.set("mine", self)
	hud.add_child(h)

# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------

func _on_ore_mined(ore_id: int, cell: Vector2i) -> void:
	var ok := GameState.add_ore(ore_id, 1)
	var wp := grid.cell_to_world(cell)
	Audio.play_at("ore_chime", wp, player.global_position, 800.0)
	Fx.sparks(wp, 8, true)
	player.cargo_pickup.emit(ore_id, ok)

func _on_cargo_pickup(_ore_id: int, ok: bool) -> void:
	if hud and hud.get_child_count() > 0:
		var h = hud.get_child(0)
		if h and h.has_method("flash_cargo"):
			h.flash_cargo(ok)

func _on_enemy_died(_pos: Vector2) -> void:
	if randf() < 0.28 and player and is_instance_valid(player):
		player.add_charge(1)

func _on_player_died(cause: String) -> void:
	_finish(false, cause)

func _on_extracted() -> void:
	_finish(true, "")

func _finish(extracted: bool, cause: String) -> void:
	if _finished:
		return
	_finished = true
	Audio.drill(false)
	if touch and is_instance_valid(touch):
		touch.set_process(false)
	if extracted:
		Audio.play("extract_win", 0.0, 0.0)
	var result := GameState.end_run(extracted, cause)
	var t := get_tree().create_timer(0.9)
	t.timeout.connect(func():
		run_finished.emit(result)
		_show_result(result)
	)

func _show_result(result: Dictionary) -> void:
	result_layer = CanvasLayer.new()
	result_layer.layer = 30
	var c := Control.new()
	c.set_script(load("res://src/ui/result_screen.gd"))
	c.set("result", result)
	c.name = "ResultScreen"
	result_layer.add_child(c)
	add_child(result_layer)
	get_tree().paused = true

func _process(_delta: float) -> void:
	if camera and player and is_instance_valid(player):
		camera.offset = Fx.shake_offset()
	if renderer:
		renderer.refresh_dirty(6)
	if _fps_label:
		_fps_label.visible = bool(SaveManager.settings.get("show_fps", false))
		if _fps_label.visible:
			_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
