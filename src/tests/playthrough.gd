extends Node
## Integration soak test: loads the real Mine scene and drives it with synthetic
## input for a fixed number of physics frames, then asserts the run reached a
## terminal state or made real progress. This exercises the actual gameplay
## code paths (player, drilling, enemies, hazards, HUD, extraction) rather than
## testing systems in isolation.

const MAX_FRAMES := 4200

var _mine: Node
var _frames := 0
var _fail := false
var _phase := 0
var _log: Array = []
var _stuck_frames := 0
var _last_pos := Vector2.ZERO

func _ready() -> void:
	print("=== RUIN DIGGER playthrough soak ===")
	GameState.start_run()
	_mine = load("res://src/world/mine.tscn").instantiate()
	_mine.run_finished.connect(_on_finished)
	add_child(_mine)
	await get_tree().process_frame
	_check_invariants_after_load()
	_last_pos = _mine.player.global_position
	# A deterministic drive: move right, drill, occasionally jump and throw a
	# charge. Enough to prove the whole loop runs without script errors.
	_set_action("move_right", true)
	_set_action("drill", true)

func _check_invariants_after_load() -> void:
	check(_mine.grid != null, "mine built a terrain grid")
	check(_mine.player != null, "mine spawned a player")
	check(_mine.hud != null, "mine built a HUD")
	check(_mine.renderer != null, "mine built a terrain renderer")
	check(_mine.grid.w == Mine.WIDTH_CELLS, "grid width matches config")
	check(_mine.grid.h == Mine.HEIGHT_CELLS, "grid height matches config")
	check(_mine.grid.get_material(_mine.grid.spawn_cell.x, _mine.grid.spawn_cell.y)
			== Balance.Mat.EMPTY, "spawn cell is open")
	var enemies := get_tree().get_nodes_in_group("enemies")
	check(enemies.size() > 0, "enemies spawned (%d)" % enemies.size())
	check(_mine.player.hp > 0, "player starts alive")
	check(_mine.player.charges > 0, "player starts with charges")

func _set_action(name: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(name)
	else:
		Input.action_release(name)

func _physics_process(_delta: float) -> void:
	if _mine == null or _fail:
		return
	_frames += 1
	var p: Player = _mine.player
	if p == null or not is_instance_valid(p):
		return

	# Change behaviour periodically so movement, drilling, jumping and charges
	# all get exercised.
	if _frames % 240 == 0:
		_phase += 1
		Input.action_release("move_left")
		Input.action_release("move_right")
		Input.action_release("move_up")
		Input.action_release("move_down")
		match _phase % 4:
			0:
				Input.action_press("move_right")
				Input.action_press("drill")
			1:
				Input.action_press("move_down")
				Input.action_press("drill")
			2:
				Input.action_press("move_left")
				Input.action_press("drill")
			3:
				Input.action_press("move_right")
				Input.action_press("drill")
	if _frames % 420 == 0:
		Input.action_press("jump")
		Input.action_release("jump")
	if _frames % 900 == 0:
		Input.action_press("charge")
		Input.action_release("charge")

	# Detect a hard stall (no drilling progress at all).
	if _frames % 120 == 0:
		var moved := p.global_position.distance_to(_last_pos)
		if moved < 6.0 and p.state != Player.State.DRILL:
			_stuck_frames += 1
		_last_pos = p.global_position

	# Sanity invariants that must hold on every frame.
	if p.hp < 0 or p.hp > p.max_hp:
		fail("player hp out of range: %d/%d" % [p.hp, p.max_hp])
	if p.heat < 0.0 or p.heat > p.heat_capacity + 0.001:
		fail("heat out of range: %f/%f" % [p.heat, p.heat_capacity])
	if p.charges < 0 or p.charges > p.max_charges:
		fail("charges out of range: %d/%d" % [p.charges, p.max_charges])
	var cell: Vector2i = _mine.grid.world_to_cell(p.global_position)
	if not _mine.grid.in_bounds(cell.x, cell.y):
		fail("player left the world at %s" % str(cell))

	if _frames >= MAX_FRAMES:
		_finish_soak()

func _on_finished(result: Dictionary) -> void:
	print("  run finished early: extracted=%s cause=%s cargo=%s" % [
		result.get("extracted"), result.get("cause"), result.get("cargo")])
	_log.append("terminal state reached")
	_finish_soak()

func _finish_soak() -> void:
	if _fail:
		return
	_fail = true   # stop the loop
	Input.action_release("drill")
	Input.action_release("move_right")
	Input.action_release("move_left")
	Input.action_release("move_down")
	Input.action_release("move_up")

	var p: Player = _mine.player
	var carved: int = 0

	for i in _mine.grid.material.size():
		if _mine.grid.material[i] == Balance.Mat.EMPTY:
			carved += 1
	check(_frames > 100, "soak ran for %d frames" % _frames)
	check(carved > _mine.grid.w * 12, "player carved new tunnels (%d open cells)" % carved)
	check(GameState.max_depth_cells > 0, "player reached depth %d" % GameState.max_depth_cells)
	check(_stuck_frames < 12, "player was not permanently stalled (%d stalls)" % _stuck_frames)
	var heat_seen: bool = _mine.player.heat >= 0.0
	check(heat_seen, "heat system stayed valid")
	print("  frames=%d open_cells=%d depth=%d hp=%d/%d cargo=%d" % [
		_frames, carved, GameState.max_depth_cells, p.hp, p.max_hp, GameState.cargo_units])
	if is_instance_valid(_mine):
		_mine.free()
		_mine = null
	print("=== soak result: %s ===" % ("PASS" if _passed else "FAIL"))
	get_tree().quit(0 if _passed else 1)

var _passed := true

func check(cond: bool, name: String) -> void:
	if cond:
		print("  ok   ", name)
	else:
		print("  FAIL ", name)
		_passed = false

func fail(msg: String) -> void:
	print("  FAIL ", msg)
	_passed = false
	_fail = true
