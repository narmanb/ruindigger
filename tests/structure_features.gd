extends RefCounted
## Real collision regression: dropping ignores the touched plank, never rock.
static func run(t: Node) -> void:
	t.section("platform drop-through")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	Game.start_run()
	await t._frames(40)
	var mine: Node = Game.current
	var g: TerrainGrid = mine.grid
	var p: Player = mine.player
	p.invuln = 1e9
	for y in range(14, 28):
		for x in range(28, 38):
			g.set_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE, false)
			g.set_water(x, y, 0)
			g.set_mat(x, y, Cell.BEDROCK if x == 28 or x == 37 or y == 27 else Cell.AIR)
	for x in range(29, 37):
		g.set_mat(x, 20, Cell.PLATFORM)
		g.set_mat(x, 23, Cell.PLATFORM)
	await t._frames(3)
	p.global_position = Vector2(32 * 16 + 8, 20 * 16 - Player.HALF.y - 0.5)
	p.velocity = Vector2.ZERO
	p.input_override = {"x": 0.0}
	await t._frames(8)
	t.check(p.is_on_floor(), "drop fixture starts standing on the upper plank")
	p.input_override = {"x": 0.0, "y": 1.0, "jump": true, "jump_just": true}
	await t._frames(2)
	g.set_mat(36, 18, Cell.SOFT) # rebuilding this chunk must preserve the drop exception
	await t._frames(33)
	t.check(p.is_on_floor() and absf(p.global_position.y - (23 * 16 - Player.HALF.y - 0.5)) < 2, "Down + Jump drops through one plank and lands on the next")
	p.global_position = Vector2(32 * 16 + 8, 20 * 16 - Player.HALF.y - 0.5)
	p.velocity = Vector2.ZERO
	p.input_override = {"x": 0.0}
	await t._frames(8)
	t.check(p.is_on_floor() and absf(p.global_position.y - (20 * 16 - Player.HALF.y - 0.5)) < 2, "the upper plank becomes solid again after dropping")
	p.input_override = {"x": 0.0, "jump": true, "jump_just": true}
	await t._frames(2)
	t.check(p.velocity.y < 0, "Jump without Down still jumps from a plank")
	p.global_position = Vector2(32 * 16 + 8, 27 * 16 - Player.HALF.y - 0.5)
	p.velocity = Vector2.ZERO
	p.input_override = {"x": 0.0}
	await t._frames(8)
	p.input_override = {"x": 0.0, "y": 1.0, "jump": true, "jump_just": true}
	var above_rock := true
	for i in 50:
		await t._frames(1)
		above_rock = above_rock and p.global_position.y + Player.HALF.y <= 27 * 16 + 1
	t.check(above_rock, "Down + Jump never disables collision with solid rock")
	Game.goto("title", true)
	await t._frames(3)
