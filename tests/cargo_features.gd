extends RefCounted
## Live cargo overlay regressions; runs in the game suite or suite=cargo.
static func run(t: Node) -> void:
	t.section("cargo manifest")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	Game.contract["reward"] = 260
	Game.start_run()
	await t._frames(40)
	var mine: Node = Game.current
	var screen: Node = mine.hud.get("cargo_screen")
	t.check(screen != null, "live HUD provides a cargo manifest")
	if screen == null:
		return
	Game.run["cargo"] = {1: 3, 2: 2}
	Game.run["relic"] = true
	mine.hud.open_cargo()
	t.check(screen.is_open and t.get_tree().paused, "cargo manifest pauses the run")
	t.check(screen.total_label.text.contains(str(Game.cargo_value(Game.run["cargo"]) + int(Game.contract["reward"]))), "manifest total includes ore and secured relic reward")
	t.check(screen.rows.get_child_count() >= Balance.ORE.size(), "manifest lists all ore types")
	screen.close()
	t.check(not screen.is_open and not t.get_tree().paused, "closing manifest resumes a running mine")
	mine.pause_menu.open()
	screen.open()
	t.check(screen.is_open and t.get_tree().paused and not mine.pause_menu.root.visible, "manifest can open above the pause menu")
	screen.close()
	t.check(t.get_tree().paused and mine.pause_menu.root.visible, "closing manifest returns to the paused menu")
	mine.pause_menu.close()
	Game.run["cargo"] = {}
	Game.run["relic"] = false
	mine.hud.open_cargo()
	t.check(screen.total_label.text.contains("0 CR"), "empty cargo has no speculative relic reward")
	screen.close()
	t.check(mine.data.get("finds", []).size() == 5, "each zone offers a keepsake to discover")
	if mine.keepsakes.is_empty():
		return
	var find: ZoneKeepsake = mine.keepsakes[0]
	var id := find.id
	Game.run["cargo"] = {1: mine.cargo_cap()}
	var units := Game.cargo_count()
	mine.player.global_position = find.global_position
	mine.player.velocity = Vector2.ZERO
	mine.player.input_override = {"x": 0.0}
	mine.player_interact(mine.player)
	find.take() # repeated interaction cannot pay twice
	t.check(Game.run["finds"].count(id) == 1, "keepsake can be recovered exactly once")
	t.check(Game.cargo_count() == units, "a keepsake fits in its own pouch even when the ore rack is full")
	var bonus := int(Balance.KEEPSAKES[id]["value"])
	t.check(Game.finds_value([id, id, -1, 99, "bad"]) == bonus, "keepsake value rejects duplicate and invalid IDs")
	screen.open()
	t.check(screen.total_label.text.contains(str(Game.cargo_value(Game.run["cargo"]) + bonus)), "manifest includes carried keepsake value")
	Input.action_press("drill")
	screen.close()
	t.check(not Input.is_action_pressed("drill"), "closing cargo clears held drill input")
	var before := Progress.credits
	var ore_value := Game.cargo_value(Game.run["cargo"])
	mine.player.global_position = mine.lifts[0].global_position
	mine.extract(mine.lifts[0])
	await t._frames(180)
	t.check(Game.current_name == "results" and Progress.credits == before + ore_value + bonus and Game.last_result.get("finds_bonus", 0) == bonus, "extraction banks ore and keepsake credits exactly once")
	Game.start_run()
	await t._frames(40)
	t.check(Game.run.get("finds", []).is_empty(), "a fresh run starts with an empty keepsake pouch")
	Game.run["finds"] = [id]
	before = Progress.credits
	Game.current.player.die("cargo audit")
	await t._frames(150)
	t.check(Progress.credits == before and Game.last_result.get("finds_bonus", -1) == 0, "death loses keepsakes without banking their value")
	Game.start_run()
	await t._frames(40)
	Game.run["finds"] = [id]
	Game.current.abandon()
	await t._frames(30)
	t.check(Progress.credits == before and Game.last_result.get("finds_bonus", -1) == 0, "abandonment loses keepsakes without banking their value")
	Game.goto("title", true)
	await t._frames(3)
