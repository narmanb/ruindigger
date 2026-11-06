extends Node
## Objective test: proves the mission is completable through the real code
## paths. The player is teleported (the only shortcut) to the relic chamber to
## collect the relic, then to the lift cab to extract. Pickup radius, extraction
## timer, reward banking and the save mutation all run exactly as in a real game.

var _mine: Node
var _finished_result: Dictionary = {}
var _done := false
var _passed := true
var _phase := 0
var _t := 0.0
var _credits_before := 0
var _runs_before := 0

func _ready() -> void:
	# The game pauses the tree when it shows the result screen, so the test node
	# must keep processing in order to evaluate the outcome.
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("=== RUIN DIGGER objective test ===")
	GameState.start_run(4242)
	check(not GameState.relic_taken, "start_run resets the relic flag")
	_credits_before = SaveManager.credits
	_runs_before = SaveManager.runs_completed
	_mine = load("res://src/world/mine.tscn").instantiate()
	_mine.run_finished.connect(_on_run_finished)
	add_child(_mine)
	await get_tree().process_frame
	check(_mine.grid != null, "mine loaded")
	check(_mine.player.global_position.distance_to(
			_mine.grid.cell_to_world(_mine.grid.relic_cell)) > 200.0,
			"player does not spawn on the relic")

	var g = _mine.grid
	var spawn: Vector2i = g.spawn_cell
	var relic: Vector2i = g.relic_cell
	var lift: Vector2i = g.lift_cell
	print("  spawn=%s relic=%s lift=%s" % [spawn, relic, lift])

	# Spawn cab: the player must have headroom and a floor to stand on.
	check(g.get_material(spawn.x, spawn.y) == Balance.Mat.EMPTY, "spawn cell is open")
	check(g.get_material(spawn.x, spawn.y + 1) == Balance.Mat.EMPTY, "spawn has headroom")
	check(g.get_material(spawn.x, spawn.y + 2) != Balance.Mat.EMPTY, "spawn has a floor")

	# Lift cab: open above, solid below -- otherwise the player falls through
	# and the extraction radius can never be satisfied.
	check(g.get_material(lift.x, lift.y) == Balance.Mat.EMPTY, "lift cell is open")
	check(g.get_material(lift.x, lift.y + 1) == Balance.Mat.EMPTY, "lift has headroom")
	check(g.get_material(lift.x, lift.y + 2) != Balance.Mat.EMPTY, "lift has a floor")

	# The relic chamber must be walkable space, sealed except for its doorway.
	check(g.get_material(relic.x, relic.y) == Balance.Mat.EMPTY, "relic cell is open")
	check(g.get_material(relic.x, relic.y + 1) == Balance.Mat.EMPTY, "relic has headroom")
	check(g.get_material(relic.x, relic.y + 2) != Balance.Mat.EMPTY, "relic has a floor")

	# The whole objective must be reachable by walking/drilling from spawn.
	var walk: PackedByteArray = g.reach_mask(spawn, 400000)
	check(walk[g.idx(relic.x, relic.y)] == 1, "relic reachable on foot from spawn")
	check(walk[g.idx(lift.x, lift.y)] == 1, "lift reachable on foot from spawn")
	var dig: PackedByteArray = g.reach_mask_diggable(spawn, 400000)
	check(dig[g.idx(relic.x, relic.y)] == 1, "relic reachable by drilling from spawn")

func _physics_process(delta: float) -> void:
	if _mine == null:
		return
	if _done:
		_evaluate()
		return
	_t += delta
	match _phase:
		0:
			# Settle first: assert the player really is standing in the spawn cab
			# before the test starts teleporting them around.
			var spawn_dist: float = _mine.player.global_position.distance_to(
					_mine.grid.cell_to_world(_mine.grid.spawn_cell))
			if _t > 0.35:
				check(spawn_dist < Balance.CELL * 2.0,
						"player stands in the spawn cab (%.1f px off)" % spawn_dist)
				check(not GameState.relic_taken, "relic still untaken after settling")
				_phase = 1
				_t = 0.0
		1:
			_mine.player.global_position = _mine.grid.cell_to_world(_mine.grid.relic_cell)
			_mine.player.velocity = Vector2.ZERO
			if _t > 0.4:
				_phase = 2
				_t = 0.0
		2:
			check(GameState.relic_taken, "walking onto the relic collected it")
			_phase = 3
			_t = 0.0
		3:
			# Stand exactly on the lift cab and hold interact.
			_mine.player.global_position = _mine.grid.cell_to_world(_mine.grid.lift_cell)
			_mine.player.velocity = Vector2.ZERO
			Input.action_press("interact")
			if _t > 2.0:
				print("  in_lift=%s extract_timer=%s" % [
						_mine.player.in_lift(), _mine.player._extract_timer])
				Input.action_release("interact")
				check(false, "extraction completed within 2s")
				_done = true

func _on_run_finished(r: Dictionary) -> void:
	_finished_result = r
	_done = true

func _evaluate() -> void:
	if _mine == null:
		return
	_mine = null
	Input.action_release("interact")
	check(not _finished_result.is_empty(), "run produced a result")
	check(bool(_finished_result.get("extracted", false)), "run recorded as extracted")
	check(bool(_finished_result.get("relic", false)), "relic bonus was banked")
	var banked: int = int(_finished_result.get("banked", 0))
	check(banked >= Balance.RELIC_VALUE, "extraction banked relic value (%d)" % banked)
	check(SaveManager.credits >= _credits_before + banked, "credits were added to the save")
	check(SaveManager.runs_completed == _runs_before + 1, "run counter incremented")
	check(not GameState.run_active, "run state was closed out")
	GameState.start_run()
	check(not GameState.relic_taken and GameState.cargo_units == 0,
			"new run starts with clean state")
	if is_instance_valid(_mine):
		_mine.free()
		_mine = null
	print("=== objective result: %s ===" % ("PASS" if _passed else "FAIL"))
	get_tree().quit(0 if _passed else 1)

func check(cond: bool, name: String) -> void:
	if cond:
		print("  ok   ", name)
	else:
		print("  FAIL ", name)
		_passed = false
