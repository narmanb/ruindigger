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
	Game.goto("title", true)
	await t._frames(3)
