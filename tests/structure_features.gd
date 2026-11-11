extends RefCounted
## Real collision regression: dropping ignores the touched plank, never rock.
static func run(t: Node) -> void:
	t.section("platform drop-through")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	Game.start_run()
	await t._frames(40)
	var mine: Node = Game.current
	audit(t, mine.data, "live seed 7")
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


static func audit(t: Node, d: Dictionary, tag: String) -> void:
	var g: TerrainGrid = d["grid"]
	var bad_ladders := 0
	for x in g.w:
		var y := 0
		while y < g.h:
			if g.get_mat(x, y) != Cell.LADDER:
				y += 1
				continue
			var first := y
			var anchored := g.is_solid(x, y - 1)
			var protected_run := false
			while y < g.h and g.get_mat(x, y) == Cell.LADDER:
				anchored = anchored or g.is_solid(x - 1, y) or g.is_solid(x + 1, y)
				protected_run = protected_run or g.has_flag(x, y, Cell.F_PROTECTED)
				y += 1
			anchored = anchored or g.is_solid(x, y)
			if not protected_run and (y - first < 3 or not anchored): bad_ladders += 1
	t.check(bad_ladders == 0, tag + ": generated ladders have a useful length and rock attachment")
	var long_planks := 0
	for y in g.h:
		var n := 0
		for x in g.w + 1:
			if x < g.w and g.get_mat(x, y) == Cell.PLATFORM:
				n += 1
			else:
				if n > 3 and g.get_stratum(x - 1, y) != Balance.Z_ENGINE: long_planks += 1
				n = 0
	t.check(long_planks == 0, tag + ": planks outside Engine maintenance routes are short landings")
	var floating_posts := 0
	for e in d["entities"]:
		if e["type"] == "beam":
			var c: Vector2i = e["cell"]
			if g.get_mat(c.x, c.y) != Cell.AIR or g.get_mat(c.x, c.y - 1) != Cell.AIR or not g.is_solid(c.x, c.y + 1): floating_posts += 1
	t.check(floating_posts == 0, tag + ": wooden posts stand on a floor")
