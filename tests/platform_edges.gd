extends RefCounted
## Chunk seams and water must not turn a drop command into a blocked jump.
static func run(t: Node) -> void:
	t.section("platform drop edges")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	Game.start_run()
	await t._frames(40)
	var mine: Node = Game.current
	mine.set_physics_process(false) # keep fixture water still
	var p: Player = mine.player
	var g: TerrainGrid = mine.grid
	p.invuln = 1e9
	for y in range(14, 28):
		for x in range(26, 39):
			g.set_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE, false)
			g.set_water(x, y, 0)
			g.set_mat(x, y, Cell.BEDROCK if x == 26 or x == 38 or y == 27 else Cell.AIR)
	for x in range(27, 38):
		g.set_mat(x, 20, Cell.PLATFORM)
		g.set_mat(x, 23, Cell.PLATFORM)
	await t._frames(3)
	for px in [508.0, 512.0, 516.0]:
		p.global_position = Vector2(px, 20 * 16 - Player.HALF.y - 0.5)
		p.velocity = Vector2.ZERO
		p.input_override = {"x": 0.0}
		await t._frames(8)
		p.input_override = {"x": 0.0, "y": 1.0, "jump": true, "jump_just": true}
		await t._frames(1)
		p.input_override = {"x": 0.0, "y": 1.0, "jump": true}
		await t._frames(39)
		t.check(p.is_on_floor() and absf(p.global_position.y - (23 * 16 - Player.HALF.y - 0.5)) < 2, "one drop crosses the chunk seam at x=%d and stops on the lower row" % px)
	for y in range(16, 24):
		for x in range(27, 38):
			g.set_water(x, y, Balance.WATER_MAX)
	p.global_position = Vector2(33 * 16 + 8, 20 * 16 - Player.HALF.y - 0.5)
	p.velocity = Vector2.ZERO
	p.input_override = {"x": 0.0}
	await t._frames(8)
	p.input_override = {"x": 0.0, "y": 1.0, "jump": true, "jump_just": true}
	await t._frames(1)
	t.check(p.velocity.y > 0.0, "a submerged Down + Jump starts downward instead of swimming up")
	p.input_override = {"x": 0.0, "y": 1.0}
	await t._frames(60)
	t.check(p.is_on_floor() and absf(p.global_position.y - (23 * 16 - Player.HALF.y - 0.5)) < 2, "a submerged drop clears the upper slab and lands on the lower row")
	Game.goto("title", true)
	await t._frames(3)
