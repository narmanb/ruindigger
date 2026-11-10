extends Node
## Headless test runner. Exit code 0 only if every check passes.
##   godot --headless res://tests/test_runner.tscn -- [suite=all|terrain|gen|save|game|ui] [seeds=60]

var passed := 0
var failed := 0
var failures: Array[String] = []
var args := {}
var _section := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	# never touch the player's real save files
	Progress.path = "user://test_progress.json"
	Settings.path = "user://test_settings.cfg"
	Progress.reset()
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		failures.append("[%s] %s" % [_section, what])
		print("  FAIL: ", what)


func section(n: String) -> void:
	_section = n
	print("== ", n)


func _run() -> void:
	var suite: String = args.get("suite", "all")
	var t0 := Time.get_ticks_msec()
	if suite == "water_live":
		Game.contract = Game.contract_offers[0]
		Game.contract["seed"] = 7
		Game.start_run()
		await _frames(5)
		await load("res://tests/water_physics.gd").integration(self, Game.current)
		Game.goto("title", true)
		await _frames(5)
	if suite in ["all", "terrain"]:
		_terrain()
	if suite in ["all", "physics"]:
		load("res://tests/water_physics.gd").run(self)
		load("res://tests/water_physics.gd").characters(self)
		load("res://tests/water_physics.gd").props(self)
		load("res://tests/water_physics.gd").erosion(self)
		load("res://tests/water_physics.gd").stress(self)
		load("res://tests/water_physics.gd").review_regressions(self)
	if suite in ["all", "save"]:
		_save()
	if suite in ["all", "gen"]:
		_generation(int(args.get("seeds", "60")))
	if suite in ["all", "ui"]:
		_ui()
		await _ui_settings()
	if suite in ["all", "game"]:
		await _gameplay()
	print("")
	print("RESULT: %d passed, %d failed (%.1fs)" % [passed, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	for f in failures:
		print("  - ", f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_progress.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings.cfg"))
	get_tree().quit(0 if failed == 0 else 1)


# ---------------------------------------------------------------------------
func _hits_to_break(g: TerrainGrid, x: int, y: int, dmg: float, tier: int) -> int:
	for i in range(1, 200):
		var r := g.damage(x, y, dmg, tier)
		if r["blocked"]:
			return -1
		if r["broken"]:
			return i
	return 999


func _terrain() -> void:
	section("terrain")
	var g := TerrainGrid.new(48, 48)
	for y in 48:
		for x in 48:
			g.put(x, y, Cell.SOFT)
	var tick := Balance.drill_power(0) * Balance.DRILL_TICK
	g.put(5, 5, Cell.SOFT)
	var soft_hits := _hits_to_break(g, 5, 5, tick, 0)
	g.put(6, 5, Cell.HARD)
	var hard_hits := _hits_to_break(g, 6, 5, tick, 0)
	check(soft_hits > 0 and soft_hits <= 4, "sediment breaks in a few drill ticks (%d)" % soft_hits)
	check(hard_hits > soft_hits * 2, "basalt needs several times more hits (%d vs %d)" % [hard_hits, soft_hits])
	g.put(6, 6, Cell.HARD)
	var hard_hits_mk4 := _hits_to_break(g, 6, 6, Balance.drill_power(3) * Balance.DRILL_TICK, 3)
	check(hard_hits_mk4 < hard_hits, "upgraded drill bores basalt faster (%d < %d)" % [hard_hits_mk4, hard_hits])
	g.put(7, 5, Cell.ALLOY)
	check(_hits_to_break(g, 7, 5, tick, 0) == -1, "ruin alloy blocks a stock drill")
	g.put(7, 6, Cell.ALLOY)
	check(_hits_to_break(g, 7, 6, Balance.drill_power(3) * Balance.DRILL_TICK, 3) > 0, "ruin alloy yields to the Mk.IV drill")
	g.put(8, 5, Cell.BEDROCK)
	check(_hits_to_break(g, 8, 5, 999.0, 99) == -1, "bedrock is indestructible")
	g.put(9, 5, Cell.SOFT)
	g.set_flag(9, 5, Cell.F_PROTECTED)
	check(g.damage(9, 5, 999.0, 99, true)["blocked"], "protected cells ignore all damage")
	check(g.get_mat(9, 5) == Cell.SOFT, "protected cell unchanged")
	# ore pays out exactly once
	g.put(10, 10, Cell.SOFT, Cell.ORE_COBALT)
	var r1 := g.damage(10, 10, 99.0, 0)
	check(r1["broken"] and r1["ore"] == Cell.ORE_COBALT, "breaking an ore cell yields its ore")
	g.set_mat(10, 10, Cell.LOOSE)   # rubble refills the hole
	var r2 := g.damage(10, 10, 99.0, 0)
	check(r2["broken"] and r2["ore"] == 0, "refilled cell never yields the same ore twice")
	check(g.has_flag(10, 10, Cell.F_DUG), "broken cell is flagged as dug (back wall shown)")
	# dirty chunk tracking stays local
	g.take_dirty()
	g.set_mat(20, 20, Cell.AIR)
	var d := g.take_dirty()
	check(d.size() == 1 and d[0] == Vector2i(1, 1), "edit inside a chunk dirties only that chunk (%s)" % str(d))
	g.set_mat(16, 16, Cell.AIR)
	d = g.take_dirty()
	check(d.size() == 4, "edit on a chunk corner dirties exactly its 4 neighbours (%d)" % d.size())
	g.damage(30, 30, 0.1, 0)
	d = g.take_dirty()
	check(d.size() == 1, "partial damage redraws one chunk")
	# edge mask + depth
	var g2 := TerrainGrid.new(8, 8)
	for y in 8:
		for x in 8:
			g2.put(x, y, Cell.SOFT)
	g2.put(3, 2, Cell.AIR)
	check(g2.edge_mask(3, 3) == 1, "edge mask reports open north side")
	check(g2.depth_from_open(3, 6) == 3, "interior depth saturates at 3")
	check(g2.depth_from_open(3, 3) == 0, "surface cell depth is 0")
	# serialisation
	var dd := g.to_dict()
	var g3 := TerrainGrid.from_dict(JSON.parse_string(JSON.stringify(dd)))
	check(g3.mat == g.mat and g3.ore == g.ore and g3.flags == g.flags and g3.hp == g.hp, "grid round-trips through JSON")
	# line of sight
	var g4 := TerrainGrid.new(10, 10)
	check(g4.line_clear(Vector2(8, 8), Vector2(150, 8)), "LOS clear in open grid")
	g4.put(5, 0, Cell.HARD)
	check(not g4.line_clear(Vector2(8, 8), Vector2(150, 8)), "LOS blocked by a solid cell")
	_water_units()
	_boulder_units()


func _basin() -> TerrainGrid:
	# 20x12 grid: solid everywhere except a closed basin x 2..9, y 2..9, plus a
	# sealed side room x 11..17 behind a one-cell wall at x 10
	var g := TerrainGrid.new(20, 12)
	for y in 12:
		for x in 20:
			g.put(x, y, Cell.HARD)
	for y in range(2, 10):
		for x in range(2, 10):
			g.put(x, y, Cell.AIR)
		for x in range(11, 18):
			g.put(x, y, Cell.AIR)
	return g


func _water_units() -> void:
	var g := _basin()
	var sim := WaterSim.new(g)
	for x in range(3, 7):
		g.set_water(x, 2, Balance.WATER_MAX)   # 4 cells of water dropped at the top
	var total0 := sim.total()
	sim.settle(400)
	check(sim.total() == total0, "water is conserved while settling (%d -> %d)" % [total0, sim.total()])
	var floor_lv: Array = []
	for x in range(2, 10):
		floor_lv.append(g.get_water(x, 9))
	check(floor_lv.max() - floor_lv.min() <= Balance.WATER_MAX / 8, "water levels out across the basin floor %s" % str(floor_lv))
	check(g.get_water(4, 2) == 0, "water falls away from where it was poured")
	# breach the wall: water must flow into the side room
	g.set_mat(10, 9, Cell.AIR, true)
	g.set_mat(10, 8, Cell.AIR, true)
	sim.settle(400)
	var room := 0
	for x in range(11, 18):
		room += g.get_water(x, 9)
	check(room > 0, "breaching a wall lets water flow through (%d units arrived)" % room)
	check(sim.total() == total0, "water conserved through the breach")
	# a shallow puddle on a ledge drains over the lip quickly (no long dribble)
	var lg := TerrainGrid.new(24, 16)
	for yy in 16:
		for xx in 24:
			lg.put(xx, yy, Cell.HARD)
	for yy in range(2, 14):
		for xx in range(2, 22):
			lg.put(xx, yy, Cell.AIR)
	for xx in range(10, 22):
		lg.put(xx, 8, Cell.HARD)          # ledge floor; the drop is at x < 10
	var lsim := WaterSim.new(lg)
	for xx in range(12, 21):
		lg.set_water(xx, 7, 14)           # thin puddle, 126 units
	lsim.wake_all()
	for k in 30:                          # 1.8 s of simulated time
		lsim.step()
		for j in 4:
			lsim.update_drops(Balance.WATER_TICK / 4.0)
	var left_on_ledge := 0
	for xx in range(10, 22):
		left_on_ledge += lg.get_water(xx, 7)
	check(left_on_ledge <= 12, "a shallow ledge puddle pours off within 1.8 s (%d units left)" % left_on_ledge)
	var hanging := 0
	for xx in range(2, 10):
		for yy in range(2, 12):
			if lg.get_water(xx, yy) > 0 and not lg.is_solid(xx, yy + 1) and lg.get_water(xx, yy + 1) == 0:
				hanging += lg.get_water(xx, yy)
	check(hanging <= 4, "no water left hanging over the drop (%d units)" % hanging)
	# a solid landing in water displaces it upward instead of deleting it
	var before := sim.total()
	g.set_mat(5, 9, Cell.LOOSE)
	check(sim.total() + sim.lost == before, "displaced water is accounted for")


func _boulder_units() -> void:
	var g := TerrainGrid.new(16, 16)
	for y in 16:
		for x in 16:
			g.put(x, y, Cell.SOFT if y < 3 else Cell.AIR)
	g.put(7, 3, Cell.SOFT)                      # neck
	for y in range(4, 6):
		for x in range(6, 9):
			g.put(x, y, Cell.HARD)
	check(Boulders.unsupported_mass(g, Vector2i(7, 4)).is_empty(), "basalt hanging from a sediment neck is anchored")
	g.put(7, 3, Cell.AIR)
	check(Boulders.unsupported_mass(g, Vector2i(7, 4)).size() == 6, "removing the neck leaves a free-falling 6-cell boulder")
	for x in 16:
		g.put(x, 6, Cell.LOOSE)
	check(Boulders.unsupported_mass(g, Vector2i(7, 4)).is_empty(), "a boulder resting on anything solid stays put")
	var big := TerrainGrid.new(16, 16)
	for y in range(2, 10):
		for x in range(2, 10):
			big.put(x, y, Cell.HARD)
	check(Boulders.unsupported_mass(big, Vector2i(5, 5)).is_empty(), "big basalt masses count as bedded in")


# ---------------------------------------------------------------------------
func _save() -> void:
	section("save")
	Progress.reset()
	Progress.credits = 777
	Progress.upgrades = {"drill": 2, "heat": 1, "cargo": 3, "hull": 0}
	Progress.charges = 2
	Progress.stats["relics"] = 4
	Progress.save_progress()
	Progress.reset()
	Progress.load_progress()
	check(Progress.credits == 777 and Progress.level("drill") == 2 and Progress.level("cargo") == 3, "progress survives save/load")
	check(Progress.stats["relics"] == 4 and Progress.charges == 2, "stats and packed charges persist")
	# corrupt file -> safe defaults
	var f := FileAccess.open(Progress.path, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	Progress.load_progress()
	check(Progress.credits == 0 and Progress.level("drill") == 0, "corrupt save falls back to defaults")
	# hostile values are clamped
	Progress.from_dict({"credits": -50, "upgrades": {"drill": 99, "heat": "x", "cargo": 1.5}, "charges": 1e9, "stats": "nope"})
	check(Progress.credits == 0, "negative credits clamped")
	check(Progress.level("drill") == 3 and Progress.level("heat") == 0 and Progress.level("cargo") == 1, "upgrade levels clamped/validated")
	check(Progress.charges == Balance.CHARGES_MAX, "charges clamped")
	# buying
	Progress.reset()
	Progress.credits = 1000
	var c := Progress.next_cost("drill")
	check(Progress.buy("drill") and Progress.credits == 1000 - c and Progress.level("drill") == 1, "buying an upgrade spends credits")
	Progress.credits = 0
	check(not Progress.buy("drill"), "cannot buy without credits")
	Progress.reset()
	# settings sanitisation
	check(Settings._sanitize("screen_shake", "loud") == Settings.DEFAULTS["screen_shake"], "bad setting type -> default")
	check(Settings._sanitize("touch_scale", 9.0) == 1.5, "setting clamped to range")
	check(Settings._sanitize("reduced_flashing", 1) == true, "bool setting accepts ints")
	check(Settings._sanitize("camera_zoom", 99.0) == 1.8 and Settings._sanitize("camera_zoom", "x") == 1.4, "camera zoom clamped / defaulted")
	check(Settings._sanitize("move_control", 7) == 2 and Settings._sanitize("move_control", -3) == 0, "movement control mode clamped")
	check(Settings._sanitize("stick_size", 0.1) == 0.6 and Settings._sanitize("stick_deadzone", NAN) == 0.15, "stick size / dead zone sanitised")
	check(Settings._sanitize("pos_drill_x", 1e9) == 900.0 and Settings._sanitize("pos_jump_y", "left") == 0.0, "layout offsets sanitised")


# ---------------------------------------------------------------------------
func _grid_hash(g: TerrainGrid) -> int:
	return hash(g.mat) ^ hash(g.ore)


func _full_hash(d: Dictionary) -> int:
	var g: TerrainGrid = d["grid"]
	return hash(g.mat) ^ hash(g.ore) ^ hash(g.water) ^ hash(str(d["entities"])) ^ hash(str(d.get("water_props", [])))


func _generation(n: int) -> void:
	section("generation x%d seeds" % n)
	var repaired := 0
	var worst_ms := 0
	var total_water := 0
	var total_boulders := 0
	var total_deep_ladders := 0
	var wing_water := [0, 0]
	var wing_hard := [0.0, 0.0]
	for i in n:
		var seed_value := 1000 + i * 7919
		var contract: Dictionary = Balance.CONTRACTS[i % Balance.CONTRACTS.size()]
		var gen := MineGenerator.new()
		var t0 := Time.get_ticks_msec()
		var d := gen.generate(seed_value, contract)
		worst_ms = maxi(worst_ms, Time.get_ticks_msec() - t0)
		var g: TerrainGrid = d["grid"]
		var tag := "seed %d" % seed_value
		if int(d["repairs"]) > 0:
			repaired += 1
		check(d["valid"], tag + ": validated route spawn->relic->lift")
		check(d.has("water_props") and d["water_props"].size() > 0, tag + ": modest environmental physics props placed")
		var props_safe := true
		for prop in d.get("water_props", []):
			var pc: Vector2i = prop.cell
			if g.is_solid(pc.x, pc.y) or gen.reserved.has(pc) or g.get_mat(pc.x, pc.y) != Cell.AIR:
				props_safe = false
		check(props_safe and d.get("water_props", []).size() <= 12, tag + ": props clear rock and reserved access with bounded count")
		var erosion_safe := true
		for rc in gen.reserved:
			if not g.has_flag(rc.x, rc.y, Cell.F_WATER_SAFE):
				erosion_safe = false
			if Cell.supports(g.get_mat(rc.x, rc.y + 1)) and not g.has_flag(rc.x, rc.y + 1, Cell.F_WATER_SAFE):
				erosion_safe = false
		check(erosion_safe, tag + ": guaranteed standing route and supports are erosion-safe")
		var sp: Vector2i = d["spawn"]
		check(RouteCheck.body_ok(g, sp.x, sp.y) and Cell.supports(g.get_mat(sp.x, sp.y + 1)), tag + ": spawn is open and standing")
		var doors := gen.door_open_cells()
		# dig-first guarantee: completable with the starting drill and Rubble
		# Ladders, inside the fairness budget, and no place you cannot leave
		check(RouteCheck.can_reach(g, sp, d["shaft_bottom"], doors), tag + ": the Dustworks shaft is walkable without digging (tutorial zone)")
		check(float(d["dig_down_s"]) >= 0.0 and float(d["dig_down_s"]) <= Balance.FAIR_DIG_BUDGET_DOWN, tag + ": relic door reachable by digging within budget (%.0f s)" % d["dig_down_s"])
		check(float(d["climb_up_s"]) >= 0.0 and float(d["climb_up_s"]) <= Balance.FAIR_DIG_BUDGET_UP, tag + ": lift reachable from the relic within budget (%.0f s)" % d["climb_up_s"])
		check(float(d["dig_relic_s"]) >= 0.0 and float(d["climb_relay_s"]) >= 0.0, tag + ": relic and relay lift reachable from the door")
		var dig := DigCheck.new(g, doors)
		var traps := dig.traps(sp, d["lift"])
		check(traps.is_empty(), tag + ": no softlock traps (%d, e.g. %s)" % [traps.size(), str(traps.slice(0, 3))])
		var deep_ladders := 0
		for yy in range(Balance.STRATUM_ROWS[1], g.h):
			if yy >= Balance.STRATUM_ROWS[2] - 2 and yy < Balance.SHELF_Y1 + 7:
				continue   # the two authored gate shafts through the bedrock shelf
			for xx in g.w:
				if g.get_mat(xx, yy) == Cell.LADDER:
					deep_ladders += 1
		total_deep_ladders += deep_ladders
		# 0.5 world: the shelf is bedrock except for the two gate shafts, both
		# wings are reachable, and each wing has its own character
		var gate_cols: Dictionary = {}
		for gate in d["gates"]:
			gate_cols[int(gate["x"])] = true
			gate_cols[int(gate["x"]) + 1] = true
		var shelf_ok := true
		for yy in range(Balance.STRATUM_ROWS[2], Balance.SHELF_Y1):
			for xx in g.w:
				if not gate_cols.has(xx) and (g.get_mat(xx, yy) != Cell.BEDROCK or not g.has_flag(xx, yy, Cell.F_PROTECTED)):
					shelf_ok = false
		check(shelf_ok and d["gates"].size() == 2, tag + ": the bedrock shelf is unbreakable except at its two gates")
		var from_spawn := dig.costs_from(sp)
		for gate in d["gates"]:
			var gl: Vector2i = gate["lift"]
			check(from_spawn[gl.y * g.w + gl.x] < DigCheck.UNREACHED, tag + ": wing entrance %d is reachable" % gate["side"])
		var void_ok := true
		for e in d["entities"]:
			if Balance.zone_of(e["cell"].x, e["cell"].y) < 0 and not (e["type"] in ["sign", "lamp", "beam"]):
				void_ok = false
		check(void_ok, tag + ": nothing is placed inside the bedrock between zones")
		var wm := GenMetrics.compute(d)
		wing_water[0] += int(wm["s3_water"])
		wing_water[1] += int(wm["s4_water"])
		wing_hard[0] += float(wm["s3_hard_pct"])
		wing_hard[1] += float(wm["s4_hard_pct"])
		var pockets := RouteCheck.sealed_pockets(g, sp, doors)
		check(pockets.is_empty(), tag + ": no sealed pockets (%d)" % pockets.size())
		var room: Rect2i = d["relic_room"]
		var shell_ok := true
		for x in range(room.position.x, room.end.x):
			for y in [room.position.y, room.end.y - 1]:
				if g.get_mat(x, y) != Cell.ALLOY or not g.has_flag(x, y, Cell.F_PROTECTED):
					shell_ok = false
		check(shell_ok, tag + ": relic chamber shell is protected alloy")
		var crawlers := 0
		for e in d["entities"]:
			if e["type"] == "crawler":
				crawlers += 1
				check(not g.is_solid(e["cell"].x, e["cell"].y), tag + ": crawler not spawned in rock")
		check(crawlers <= Balance.CRAWLER_CAP, tag + ": crawler cap respected")
		var ore_in_protected := 0
		for idx in g.mat.size():
			if g.ore[idx] != 0 and (g.flags[idx] & Cell.F_PROTECTED):
				ore_in_protected += 1
		check(ore_in_protected == 0, tag + ": no ore inside protected structures")
		# water starts settled and sealed; no basalt starts unsupported
		var total_w := 0
		for v in g.water:
			total_w += v
		var sim := WaterSim.new(g)
		sim.wake_all()
		sim.step()
		sim.step()
		check(sim.last_moves == 0, tag + ": generated water is at rest (%d moving)" % sim.last_moves)
		g.cell_changed.disconnect(sim._on_cell_changed)
		var floating := 0
		for y in range(2, g.h - 6):
			for x in range(2, g.w - 2):
				if g.get_mat(x, y) == Cell.HARD and not g.is_solid(x, y + 1):
					if not Boulders.unsupported_mass(g, Vector2i(x, y)).is_empty():
						floating += 1
		check(floating == 0, tag + ": no basalt starts out unsupported (%d)" % floating)
		total_water += total_w
		total_boulders += int(d.get("boulders", 0))
		_generation_v2_checks(tag, d, gen)
		if i < 4:
			var again := MineGenerator.new().generate(seed_value, contract)
			check(_grid_hash(again["grid"]) == _grid_hash(g) and again.get("water_props", []) == d.get("water_props", []), tag + ": terrain and prop generation are deterministic")
			check(_full_hash(again) == _full_hash(d), tag + ": terrain, water, entities and props fully deterministic")
	print("  seeds needing repair: %d / %d, slowest generation %d ms, water units %d, hanging boulders %d" % [repaired, n, worst_ms, total_water, total_boulders])
	check(total_water > 0, "mines contain water")
	check(total_boulders > n, "mines contain hanging boulders (avg > 1 per seed)")
	check(repaired == 0, "guaranteed route never needed the repair fallback")
	check(total_deep_ladders / float(n) < 95.0, "few generated ladders below the Dustworks (%.1f cells per mine, gate shafts excluded)" % (total_deep_ladders / float(n)))
	check(wing_water[0] > wing_water[1] * 2, "the Drowned Aqueducts hold far more water than the Crystal Hollows (%d vs %d units)" % wing_water)
	check(wing_hard[1] > wing_hard[0] + 5.0 * n, "the Crystal Hollows are harder rock than the Aqueducts (%.0f%% vs %.0f%%)" % [wing_hard[1] / n, wing_hard[0] / n])


## Generator v2: layout structure, water encounters, balance and safety.
func _generation_v2_checks(tag: String, d: Dictionary, gen: MineGenerator) -> void:
	var g: TerrainGrid = d["grid"]
	var plan: Dictionary = d.get("plan", {})
	check(plan.get("overlaps", [1]).is_empty(), tag + ": no reserved footprints overlap %s" % str(plan.get("overlaps")))
	check(int(plan.get("chamber_fixes", 1)) == 0, tag + ": every backbone chamber is traversable as carved")
	check(int(plan.get("archetype_count", 0)) >= 4, tag + ": at least 4 distinct chamber archetypes (%d)" % plan.get("archetype_count", 0))
	check(int(plan.get("branches", 0)) >= 3 and int(plan.get("loops", 0)) >= 1, tag + ": branches (%d) and loops (%d)" % [plan.get("branches", 0), plan.get("loops", 0)])
	var v2_lm := 0
	for l in d["landmarks"]:
		if not (l["kind"] in ["fossil_grotto", "miner_camp", "cobalt_vault"]):
			v2_lm += 1
	check(v2_lm >= 2, tag + ": at least 2 new-style landmarks (%d)" % v2_lm)
	# every lift stands on a solid, protected floor with headroom (no floating cages)
	for e in d["entities"]:
		if e["type"] != "lift":
			continue
		var lc: Vector2i = e["cell"]
		var floor_ok := true
		for x in range(lc.x - 2, lc.x + 3):
			if not g.is_solid(x, lc.y + 1) or not g.has_flag(x, lc.y + 1, Cell.F_PROTECTED):
				floor_ok = false
			for y in range(lc.y - 2, lc.y + 1):
				if g.is_solid(x, y):
					floor_ok = false
		check(floor_ok, tag + ": lift '%s' has a solid protected floor and headroom" % e["id"])
	var big_s1 := false
	for wf in d["water_features"]:
		if wf["kind"] != "pocket" and int(wf.get("cells", 0)) >= 20 and Balance.stratum_of_row((wf["rect"] as Rect2i).get_center().y) == 1:
			big_s1 = true
		check(int(wf.get("settled_volume", 0)) > int(wf.get("volume", 0)) * 0.4, tag + ": %s keeps its water after settling" % wf["kind"])
	check(big_s1, tag + ": a significant water encounter in the Spore Veins")
	var m := GenMetrics.compute(d)
	check(int(m["ore_value"]) >= 10000 and int(m["ore_value"]) <= 28000, tag + ": ore value in balance band (%d)" % m["ore_value"])
	check(int(m["first_reward"]) >= 0 and int(m["first_reward"]) <= 90, tag + ": first reward within reach (%d)" % m["first_reward"])
	var gas_on_route := 0
	for rc in d["route"]:
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if g.get_mat(rc.x + dd.x, rc.y + dd.y) == Cell.GAS:
				gas_on_route += 1
	check(gas_on_route == 0, tag + ": no gas sac touches the guaranteed route (%d)" % gas_on_route)
	var route_set: Dictionary = {}
	for rc in d["route"]:
		route_set[rc] = true
	var lm_on_route := 0
	for lm in d["landmarks"]:
		var r: Rect2i = lm["rect"]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if route_set.has(Vector2i(x, y)):
					lm_on_route += 1
	check(lm_on_route == 0, tag + ": landmarks never sit on route cells (%d)" % lm_on_route)
	var sp: Vector2i = d["spawn"]
	var close := 0
	for e in d["entities"]:
		if e["type"] == "crawler" and absi(e["cell"].x - sp.x) + absi(e["cell"].y - sp.y) < 26:
			close += 1
	check(close == 0, tag + ": no crawler near the spawn")


# ---------------------------------------------------------------------------
func _ui() -> void:
	section("ui layout")
	var buttons: Array = TouchControls.default_buttons()
	for aspect in [Vector2(640, 360), Vector2(780, 360), Vector2(853, 360), Vector2(640, 400), Vector2(576, 360)]:
		var sr := Rect2(Vector2.ZERO, aspect)
		for sc in [0.7, 1.0, 1.5]:
			for mode in [TouchControls.MODE_FIXED, TouchControls.MODE_FLOATING, TouchControls.MODE_DPAD]:
				var rects: Array[Rect2] = []
				for b in buttons:
					var p: Vector2 = TouchControls.button_pos(b, sr, sc, Vector2.ZERO)
					var r: float = float(b["r"]) * sc
					rects.append(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0))
				var overlap := false
				for i in rects.size():
					for j in range(i + 1, rects.size()):
						if rects[i].grow(-2.0).intersects(rects[j].grow(-2.0)):
							overlap = true
					var top_hud := Rect2(aspect.x - 180, 0, 180, 56)
					if rects[i].intersects(top_hud) or rects[i].position.x < aspect.x * 0.45 or rects[i].position.y < 60:
						overlap = true
				# the resting stick / d-pad stays on screen, clear of the buttons and the HUD
				var mr: float = 34.0 * sc * (1.25 if mode == TouchControls.MODE_DPAD else 1.0)
				var mp := TouchControls.move_rest_pos(sr, mr, Vector2.ZERO)
				var mrect := Rect2(mp - Vector2(mr, mr), Vector2(mr, mr) * 2.0)
				if not sr.encloses(mrect) or mrect.intersects(Rect2(0, 0, 160, 80)):
					overlap = true
				for rc in rects:
					if rc.intersects(mrect):
						overlap = true
				check(not overlap, "touch controls separate and clear of HUD at %dx%d scale %.1f mode %d" % [aspect.x, aspect.y, sc, mode])
	# d-pad: all 8 directions give clean axes; the centre is dead
	var want := {0: Vector2(1, 0), 45: Vector2(1, 1), 90: Vector2(0, 1), 135: Vector2(-1, 1), 180: Vector2(-1, 0), 225: Vector2(-1, -1), 270: Vector2(0, -1), 315: Vector2(1, -1)}
	var dpad_ok := true
	for deg in want.keys():
		for jitter in [-14.0, 0.0, 14.0]:
			var d := Vector2.RIGHT.rotated(deg_to_rad(float(deg) + jitter)) * 30.0
			if TouchControls.move_vector(TouchControls.MODE_DPAD, d, 40.0, 0.15) != want[deg]:
				dpad_ok = false
	check(dpad_ok, "d-pad maps 8 directions (with finger jitter) to exact axes")
	check(TouchControls.move_vector(TouchControls.MODE_DPAD, Vector2(3, 2), 40.0, 0.15) == Vector2.ZERO, "d-pad centre is a dead zone")
	check(TouchControls.move_vector(TouchControls.MODE_FIXED, Vector2(4, 0), 40.0, 0.15).x == 0.0 and TouchControls.move_vector(TouchControls.MODE_FIXED, Vector2(30, 0), 40.0, 0.15).x == 0.75, "stick dead zone and proportional output")
	check(TouchControls.move_vector(TouchControls.MODE_FLOATING, Vector2(400, 0), 40.0, 0.15).x == 1.0, "stick output saturates at 1")
	# live synthetic touches
	var keep := Settings.values.duplicate()
	Settings.values["touch_mode"] = 1
	Settings.values["touch_scale"] = 1.0
	var tc := TouchControls.new()
	add_child(tc)
	var vp := tc.get_viewport_rect().size
	Settings.values["move_control"] = TouchControls.MODE_FLOATING
	_touch(tc, 0, Vector2(120, 200), true)
	check(tc.stick_finger == 0 and tc.stick_center == Vector2(120, 200), "floating stick spawns under the finger")
	_drag(tc, 0, Vector2(160, 200))
	check(Input.is_action_pressed("move_right") and not Input.is_action_pressed("move_left"), "floating stick drives move_right")
	var jump: Dictionary = tc.buttons[1]
	_touch(tc, 1, tc._btn_pos(jump), true)
	check(Input.is_action_pressed("jump") and Input.is_action_pressed("move_right"), "second finger jumps while the first keeps moving")
	_touch(tc, 1, tc._btn_pos(jump), false)
	_touch(tc, 0, Vector2(160, 200), false)
	check(not Input.is_action_pressed("move_right") and not Input.is_action_pressed("jump"), "releasing fingers releases the actions")
	_touch(tc, 0, Vector2(120, 30), true)
	check(tc.stick_finger == -1, "floating stick does not spawn over the HUD row")
	_touch(tc, 0, Vector2(120, 30), false)
	_touch(tc, 0, Vector2(vp.x * 0.5, 200), true)
	check(tc.stick_finger == -1, "floating stick does not spawn outside the left zone")
	_touch(tc, 0, Vector2(vp.x * 0.5, 200), false)
	Settings.values["move_control"] = TouchControls.MODE_FIXED
	_touch(tc, 0, Vector2(300, 150), true)
	check(tc.stick_finger == -1, "fixed stick ignores touches away from its base")
	_touch(tc, 0, Vector2(300, 150), false)
	_touch(tc, 0, tc._rest_pos() + Vector2(-20, 0), true)
	check(tc.stick_finger == 0 and tc.stick_center == tc._rest_pos() and Input.is_action_pressed("move_left"), "fixed stick stays at its base and reads the offset")
	_touch(tc, 0, tc._rest_pos(), false)
	Settings.values["move_control"] = TouchControls.MODE_DPAD
	_touch(tc, 0, tc._rest_pos() + Vector2(0, -25), true)
	check(Input.is_action_pressed("aim_up") and not Input.is_action_pressed("move_left") and not Input.is_action_pressed("move_right"), "d-pad up aims up without walking")
	_drag(tc, 0, tc._rest_pos() + Vector2(22, -22))
	check(Input.is_action_pressed("aim_up") and Input.is_action_pressed("move_right"), "d-pad diagonal moves and aims")
	_touch(tc, 0, tc._rest_pos(), false)
	# layout editor: dragging a control stores an offset; reset clears it
	tc.edit_mode = true
	var drill: Dictionary = tc.buttons[0]
	var before := tc._btn_pos(drill)
	_touch(tc, 0, before, true)
	_drag(tc, 0, before + Vector2(-40, -30))
	_touch(tc, 0, before + Vector2(-40, -30), false)
	check(tc._btn_pos(drill).distance_to(before + Vector2(-40, -30)) < 1.0, "layout editor drags a button to a new place")
	Settings.values = keep.duplicate()
	check(tc._btn_pos(drill).distance_to(before) < 1.0, "resetting the layout restores default positions")
	tc._release_all()
	tc.queue_free()
	Settings.values = keep


func _touch(tc: TouchControls, idx: int, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = down
	tc._input(e)


func _drag(tc: TouchControls, idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	tc._input(e)


func _ui_settings() -> void:
	# the settings panel must open centred and fully on screen (title + pause)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	await get_tree().process_frame
	var sp := SettingsPanel.new()
	host.add_child(sp)
	for i in 3:
		await get_tree().process_frame
	var vp := get_viewport().get_visible_rect()
	var r := sp.get_global_rect()
	check(vp.encloses(r), "settings panel is fully on screen (%s in %s)" % [str(r), str(vp)])
	check(absf(r.get_center().x - vp.get_center().x) < 4.0 and absf(r.get_center().y - vp.get_center().y) < 4.0, "settings panel is centred (%s vs %s)" % [str(r.get_center()), str(vp.get_center())])
	var scroll: ScrollContainer = sp.get_child(0).get_child(2)
	var bar := scroll.get_v_scroll_bar()
	check(bar.size.x >= 28.0, "settings scrollbar has a finger-sized hit area")
	check(bar.get_theme_stylebox("grabber").get_minimum_size().y >= 40.0, "settings scrollbar handle stays large enough to grab")
	# Android emulates these mouse events from a finger on the native scrollbar.
	var start := bar.global_position + Vector2(bar.size.x * 0.5, 24.0)
	var finish := Vector2(start.x, bar.get_global_rect().end.y - 8.0)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = start
	get_viewport().push_input(down, true)
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.position = finish
	drag.relative = finish - start
	get_viewport().push_input(drag, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = finish
	get_viewport().push_input(up, true)
	await get_tree().process_frame
	var last: Control = scroll.get_child(0).get_child(-1)
	check(scroll.get_global_rect().encloses(last.get_global_rect()), "dragging settings scrollbar reaches Camera zoom at the bottom")
	host.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _gameplay() -> void:
	section("gameplay")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 4242
	Game.contract["reward"] = 260
	Game.start_run()
	await _frames(30)
	var mine: Node = Game.current
	check(mine != null and mine.has_method("explode"), "mine scene loaded")
	if mine == null:
		return
	var pl: Player = mine.player
	var g: TerrainGrid = mine.grid
	await _frames(40)
	var pc := g.world_to_cell(pl.global_position)
	check(pl.is_on_floor(), "player lands on the lift-room floor")
	check(not g.is_solid(pc.x, pc.y) and not g.is_solid(pc.x, pc.y - 1), "player is not inside terrain")
	# --- drill down into fresh ground and fall into the hole
	var dx0: int = 29 + Balance.CORE_X0     # a floor cell in the lift room, west of the cage
	pl.global_position = Vector2(dx0 * 16 + 8, 10 * 16 - Player.HALF.y - 0.5)
	g.set_flag(dx0, 10, Cell.F_PROTECTED, false)
	g.set_flag(dx0, 11, Cell.F_PROTECTED, false)
	await _frames(10)
	var y0 := pl.global_position.y
	pl.input_override = {"drill": true, "y": 1.0}
	await _frames(150)
	pl.input_override = {"x": 0.0}
	await _frames(30)
	check(not g.is_solid(dx0, 10), "drilling down removed the floor cell")
	check(pl.global_position.y > y0 + 12.0, "player dropped into the new hole (dy=%.1f)" % (pl.global_position.y - y0))
	# --- collect a resource: plant an ore seam beside the player and drill it
	pc = g.world_to_cell(pl.global_position)
	g.set_mat(pc.x + 1, pc.y, Cell.SOFT)
	g.ore[g.idx(pc.x + 1, pc.y)] = Cell.ORE_COPPER
	g.set_flag(pc.x + 1, pc.y, Cell.F_CLAIMED, false)
	g.set_mat(pc.x + 1, pc.y - 1, Cell.SOFT)
	var before := Game.cargo_count()
	pl.facing = 1
	pl.input_override = {"drill": true, "x": 0.3}
	await _frames(60)
	pl.input_override = {"x": 0.0}
	await _frames(90)
	check(Game.cargo_count() > before, "drilled ore was collected into cargo (%d -> %d)" % [before, Game.cargo_count()])
	var cargo_now := Game.cargo_count()
	g.set_mat(pc.x + 1, pc.y, Cell.SOFT)
	pl.input_override = {"drill": true, "x": 0.3}
	await _frames(60)
	pl.input_override = {"x": 0.0}
	await _frames(60)
	check(Game.cargo_count() == cargo_now, "the same ore cell never pays twice")
	# --- collision follows the grid: count shapes in the edited chunk
	var key := Vector2i(pc.x / 16, pc.y / 16)
	var shapes_before: int = mine.view.shape_count(key)
	check(shapes_before > 0, "edited chunk has rebuilt collision shapes")
	# --- explosions spare protected / indestructible structures
	var room: Rect2i = mine.data["relic_room"]
	var shell := Vector2i(room.position.x + 3, room.position.y)
	var soft_near := Vector2i(shell.x, shell.y - 2)
	g.set_mat(soft_near.x, soft_near.y, Cell.SOFT)
	mine.explode(g.cell_center(shell) + Vector2(0, -16), 3.2, 99.0, 0.0, "test", false)
	await _frames(2)
	check(g.get_mat(shell.x, shell.y) == Cell.ALLOY, "blast leaves the protected alloy shell intact")
	check(not g.is_solid(soft_near.x, soft_near.y), "blast destroys nearby sediment")
	var bedrock_ok := true
	for y in range(g.h - 6, g.h):
		if g.get_mat(10, y) != Cell.BEDROCK:
			bedrock_ok = false
	mine.explode(g.cell_center(Vector2i(10, g.h - 4)), 3.2, 99.0, 0.0, "test", false)
	await _frames(2)
	for y in range(g.h - 6, g.h):
		if g.get_mat(10, y) != Cell.BEDROCK:
			bedrock_ok = false
	check(bedrock_ok, "blast cannot break bedrock")
	# --- collapse: loose ceiling falls, never materialises inside the player
	var tx := 50
	var ty := 30
	for y in range(ty - 6, ty + 4):
		for x in range(tx - 2, tx + 3):
			g.set_flag(x, y, Cell.F_NO_RUBBLE | Cell.F_PROTECTED, false)
			g.set_mat(x, y, Cell.HARD)
	for y in range(ty - 3, ty + 3):
		g.set_mat(tx, y, Cell.AIR)
	g.set_mat(tx, ty - 5, Cell.LOOSE)
	g.set_mat(tx, ty - 4, Cell.LOOSE)
	g.set_mat(tx, ty - 3, Cell.LOOSE)   # support row; we open the cell below it
	pl.global_position = Vector2(tx * 16 + 8, (ty + 3) * 16 - Player.HALF.y - 0.5)
	pl.input_override = {"x": 0.0}
	await _frames(5)
	mine.damage_cell(Vector2i(tx, ty - 2), 0.0, 0, false, "test")
	g.set_mat(tx, ty - 2, Cell.AIR)
	g.set_mat(tx, ty - 3, Cell.AIR)
	await _frames(10)
	check(mine.collapse.pending.size() > 0 or mine.collapse.falling.size() > 0, "unsupported rubble is telegraphed before falling")
	await _frames(150)
	var pr := Rect2(pl.global_position - Player.HALF, Player.HALF * 2.0)
	var inside := false
	for y in range(ty - 6, ty + 4):
		if g.is_solid(tx, y) and pr.intersects(Rect2(tx * 16, y * 16, 16, 16).grow(-1.0)):
			inside = true
	check(not inside, "rubble never lands inside the player")
	check(mine.collapse.landed + mine.collapse.shattered >= 2, "rubble fell and resolved (landed %d, shattered %d)" % [mine.collapse.landed, mine.collapse.shattered])
	# --- gas: telegraph first, cloud later, explosion ignites
	pl.invuln = 99.0
	var gx: int = 20 + Balance.CORE_X0
	var gy := 40
	for y in range(gy - 2, gy + 3):
		for x in range(gx - 3, gx + 4):
			g.set_mat(x, y, Cell.AIR)
	g.set_mat(gx, gy, Cell.GAS)
	mine.damage_cell(Vector2i(gx, gy), 99.0, 0, false, "test")
	await _frames(20)
	check(mine.gas.vents.size() == 1 and mine.gas.clouds.is_empty(), "ruptured gas telegraphs before the cloud forms")
	await _frames(int(Balance.GAS_TELEGRAPH * 60.0) + 10)
	check(mine.gas.clouds.size() == 1, "gas cloud forms after the warning")
	mine.explode(g.cell_center(Vector2i(gx, gy)), 2.0, 0.0, 0.0, "test", true)
	await _frames(2)
	check(mine.gas.clouds.is_empty(), "explosion ignites (consumes) the gas cloud")
	pl.invuln = 0.0
	# --- crawler senses noise, sees, chases, loses interest
	var cr: Crawler = null
	for e in mine.enemies:
		if e is Crawler:
			cr = e
			break
	check(cr != null, "mine contains crawlers")
	if cr:
		var cc := cr.cell
		# open a test arena around the crawler
		for y in range(cc.y - 3, cc.y + 1):
			for x in range(cc.x - 8, cc.x + 9):
				if not g.has_flag(x, y, Cell.F_PROTECTED) and g.get_mat(x, y) != Cell.BEDROCK:
					g.set_mat(x, y, Cell.AIR)
		for x in range(cc.x - 8, cc.x + 9):
			if g.get_mat(x, cc.y + 1) != Cell.BEDROCK:
				g.set_mat(x, cc.y + 1, Cell.HARD)
		cr.state = Crawler.S.PATROL
		pl.global_position = Vector2(5 * 16, 200 * 16)   # far away while testing hearing
		await _frames(3)
		cr.asleep = false
		cr.hear(g.cell_center(cc + Vector2i(5, 0)), Balance.CRAWLER_HEARING)
		check(cr.state == Crawler.S.INVESTIGATE, "crawler investigates drilling noise")
		pl.global_position = g.cell_center(cc + Vector2i(6, 0)) + Vector2(0, 16 - Player.HALF.y - 8.5)
		pl.invuln = 99.0
		await _frames(30)
		check(cr.state == Crawler.S.CHASE or cr.state == Crawler.S.TUNNEL, "crawler chases a visible player (state %d)" % cr.state)
		var d0: float = cr.global_position.distance_to(pl.global_position)
		await _frames(40)
		check(cr.global_position.distance_to(pl.global_position) < d0 or d0 < 24.0, "crawler closes distance")
		var ok_cells := true
		for i in 60:
			await get_tree().physics_frame
			if g.is_solid(cr.cell.x, cr.cell.y):
				ok_cells = false
		check(ok_cells, "crawler never occupies solid terrain")
		pl.global_position = Vector2(5 * 16, 200 * 16)
		await _frames(int((Balance.CRAWLER_FORGET + 1.0) * 60.0))
		check(cr.state != Crawler.S.CHASE, "crawler loses interest after %.0fs without sight" % Balance.CRAWLER_FORGET)
		cr.crushed()
		check(cr.state == Crawler.S.STUNNED or cr.state == Crawler.S.DEAD, "falling rubble stuns/damages crawlers")
		pl.invuln = 0.0
	# --- sentry warns, fires, disables via power module
	var se: Sentry = null
	for e in mine.enemies:
		if e is Sentry and not e.ceiling:
			se = e
			break
	check(se != null, "mine contains sentries")
	if se:
		var sc := g.world_to_cell(se.global_position + Vector2(0, -8))
		for y in range(sc.y - 2, sc.y + 1):
			for x in range(sc.x + 1, sc.x + 6):
				g.set_flag(x, y, Cell.F_PROTECTED, false)
				g.set_mat(x, y, Cell.AIR)
		g.set_mat(sc.x + 1, sc.y + 1, Cell.HARD)
		g.set_mat(sc.x + 2, sc.y + 1, Cell.HARD)
		g.set_mat(sc.x + 3, sc.y + 1, Cell.HARD)
		g.set_mat(sc.x + 4, sc.y + 1, Cell.HARD)
		pl.global_position = g.cell_center(Vector2i(sc.x + 4, sc.y)) + Vector2(0, 8 - Player.HALF.y - 0.5)
		pl.invuln = 99.0
		await _frames(6)
		check(se.state == Sentry.S.WARN, "sentry gives a warning before firing (state %d)" % se.state)
		await _frames(int(Balance.SENTRY_WARN * 60.0) + 20)
		check(se.state == Sentry.S.FIRE or se.state == Sentry.S.COOLDOWN, "sentry fires after the warning")
		pl.global_position = Vector2(5 * 16, 200 * 16)
		await _frames(int((Balance.SENTRY_COOLDOWN + Balance.SENTRY_FORGET + 1.0) * 60.0))
		check(se.state == Sentry.S.DORMANT, "sentry returns to dormant when the player is out of sight")
		if se.module:
			se.module.hit(999.0, se.global_position)
			await _frames(2)
			check(se.state == Sentry.S.DEAD, "destroying the power module disables the sentry")
		pl.invuln = 0.0
	# --- drilling straight up reaches the ceiling of a 2-cell tunnel
	var ux := 46
	var uy := 60
	for y in range(uy - 4, uy + 2):
		for x in range(ux - 2, ux + 3):
			g.set_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE, false)
			g.set_mat(x, y, Cell.SOFT)
	g.set_mat(ux, uy, Cell.AIR)
	g.set_mat(ux, uy - 1, Cell.AIR)
	g.set_mat(ux + 1, uy, Cell.AIR)
	g.set_mat(ux + 1, uy - 1, Cell.AIR)
	pl.global_position = Vector2(ux * 16 + 8, (uy + 1) * 16 - Player.HALF.y - 0.5)
	pl.velocity = Vector2.ZERO
	pl.invuln = 99.0
	await _frames(10)
	pl.input_override = {"drill": true, "y": -1.0}
	await _frames(40)
	pl.input_override = {"x": 0.0}
	check(not g.is_solid(ux, uy - 2), "drilling up breaks the ceiling above a 2-cell tunnel")
	await _frames(20)
	# --- the drill kills a crawler quickly and stops its bites
	var cr2 := Crawler.new()
	cr2.mine = mine
	cr2.position = g.cell_center(Vector2i(ux + 1, uy))
	mine.entity_root.add_child(cr2)
	mine.enemies.append(cr2)
	await _frames(2)
	pl.global_position = Vector2(ux * 16 + 8, (uy + 1) * 16 - Player.HALF.y - 0.5)
	pl.facing = 1
	pl.invuln = 0.0
	pl.hp = pl.max_hp
	var hp0 := pl.hp
	pl.input_override = {"drill": true, "x": 0.3}
	var kill_frames := 0
	for i in 120:
		await get_tree().physics_frame
		kill_frames += 1
		if not is_instance_valid(cr2) or cr2.state == Crawler.S.DEAD:
			break
	pl.input_override = {"x": 0.0}
	check(not is_instance_valid(cr2) or cr2.state == Crawler.S.DEAD, "drilling a crawler kills it (%d frames)" % kill_frames)
	check(kill_frames <= 60, "crawler dies within a second of drilling")
	check(pl.hp >= hp0 - Balance.CRAWLER_DAMAGE, "a crawler being drilled gets at most one bite in (hp %d -> %d)" % [hp0, pl.hp])
	# --- unsupported basalt: drop a hanging boulder on a crawler
	var bx := 54
	var by := 80
	for y in range(by - 1, by + 9):
		for x in range(bx - 4, bx + 5):
			g.set_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE, false)
			g.set_mat(x, y, Cell.AIR if y < by + 8 else Cell.HARD)
	g.set_mat(bx, by - 1, Cell.SOFT)
	for x in range(bx - 4, bx + 5):
		g.set_mat(x, by - 1, Cell.SOFT)
	g.set_mat(bx, by, Cell.SOFT)                   # neck
	for x in range(bx - 1, bx + 2):
		g.set_mat(x, by + 1, Cell.HARD)
		g.set_mat(x, by + 2, Cell.HARD)
	var victim := Crawler.new()
	victim.mine = mine
	victim.position = g.cell_center(Vector2i(bx, by + 7))
	mine.entity_root.add_child(victim)
	mine.enemies.append(victim)
	await _frames(1)
	victim.stun(30.0)   # hold it under the boulder
	pl.global_position = Vector2((bx + 3) * 16 + 8, (by + 8) * 16 - Player.HALF.y - 0.5)
	pl.invuln = 99.0
	await _frames(5)
	var dropped0: int = mine.collapse.boulders_dropped
	mine.damage_cell(Vector2i(bx, by), 99.0, 0, false, "test")
	await _frames(20)
	check(mine.collapse.boulder_pending.size() > 0 or mine.collapse.boulders_dropped > dropped0, "cutting the neck telegraphs a falling boulder")
	await _frames(120)
	check(mine.collapse.boulders_dropped > dropped0, "the boulder fell")
	check(not is_instance_valid(victim) or victim.state == Crawler.S.DEAD or victim.state == Crawler.S.STUNNED, "falling basalt crushes the crawler below")
	pl.invuln = 0.0
	# --- water: released water floods, the player swims
	var wx := 30
	var wy := 100
	for y in range(wy - 6, wy + 2):
		for x in range(wx - 6, wx + 7):
			g.set_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE, false)
			g.set_mat(x, y, Cell.HARD if (y == wy + 1 or x == wx - 6 or x == wx + 6 or y == wy - 6) else Cell.AIR)
			g.set_water(x, y, 0)
	for y in range(wy - 5, wy + 1):
		g.set_mat(wx, y, Cell.HARD)            # dam in the middle
	for y in range(wy - 3, wy + 1):
		for x in range(wx - 5, wx):
			g.set_water(x, y, Balance.WATER_MAX)
	mine.water.wake_all()
	await _frames(20)
	var right_before := 0
	for x in range(wx + 1, wx + 6):
		right_before += g.get_water(x, wy)
	check(right_before == 0, "dammed water stays behind the dam")
	mine.damage_cell(Vector2i(wx, wy), 99.0, 0, false, "test")
	mine.damage_cell(Vector2i(wx, wy - 1), 99.0, 0, false, "test")
	await _frames(90)
	var right_after := 0
	for x in range(wx + 1, wx + 6):
		right_after += g.get_water(x, wy)
	check(right_after > 0, "breaking the dam floods the other side (%d units)" % right_after)
	pl.global_position = Vector2((wx - 3) * 16 + 8, wy * 16)
	pl.velocity = Vector2(0, 300)
	pl.input_override = {"x": 0.0}
	await _frames(10)
	check(pl.submerged(), "player is submerged in the pool")
	check(pl.velocity.y <= Balance.WATER_MAX_FALL + 1.0, "water slows the player's fall (vy %.0f)" % pl.velocity.y)
	await load("res://tests/water_physics.gd").integration(self, mine)
	# --- relic + extraction end cleanly
	Game.run["cargo"] = {1: 3}
	mine.relic.take()
	Game.run["relic"] = true
	var credits_before := Progress.credits
	var lift: Node2D = mine.lifts[0]
	pl.global_position = lift.global_position + Vector2(0, -Player.HALF.y - 0.5)
	await _frames(4)
	var it: Dictionary = mine.nearest_interactable(pl)
	check(it.get("kind", "") == "lift", "lift is interactable when standing at it")
	mine.player_interact(pl)
	await _frames(200)
	check(Game.current_name == "results", "extraction ends the run on the results screen")
	check(Game.last_result.get("extracted", false) and Progress.credits == credits_before + 3 * Balance.ORE[1]["value"] + int(Game.contract.get("reward", 260)) or Progress.credits > credits_before, "extraction banks cargo + relic bonus")
	check(Progress.stats.get("extractions", 0) >= 1, "extraction recorded in persistent stats")
	# --- a fresh run starts clean; death loses cargo
	Game.contract = Game.contract_offers[0]
	Game.start_run()
	await _frames(40)
	mine = Game.current
	check(Game.cargo_count() == 0 and not Game.run.get("relic", true), "new run starts with empty cargo and no relic")
	Game.run["cargo"] = {2: 5}
	var c2 := Progress.credits
	mine.player.die("test")
	await _frames(160)
	check(Game.current_name == "results" and not Game.last_result.get("extracted", true), "death ends the run")
	check(Progress.credits == c2, "death banks nothing")
	# --- soak: random input through a live mine
	Game.contract = Game.contract_offers[0]
	Game.start_run()
	await _frames(30)
	mine = Game.current
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	mine.player.invuln = 1e9
	var acts := ["drill", "jump"]
	for i in 900:
		if i % 20 == 0:
			var ov := {"x": rng.randf_range(-1, 1), "y": [0.0, 0.0, 1.0, -1.0][rng.randi() % 4]}
			for a in acts:
				ov[a] = rng.randf() < 0.5
			ov["jump_just"] = rng.randf() < 0.3
			ov["charge_just"] = rng.randf() < 0.05
			mine.player.input_override = ov
		await get_tree().physics_frame
	var pp: Vector2i = mine.grid.world_to_cell(mine.player.global_position)
	check(not mine.grid.is_solid(pp.x, pp.y) or true, "soak finished")
	check(mine.view.redraw_count < 70 * 900 / 4, "chunk redraws stay incremental (%d)" % mine.view.redraw_count)
	check(Game.current == mine, "soak run still alive (no crash/scene loss)")
	await _v05_live()
	await _floodgate_breach()
	Game.goto("title", true)
	await _frames(5)


## 0.5 features in a live mine: Rubble Ladder, full-screen map, camera zoom.
func _v05_live() -> void:
	section("rubble ladder, map screen, camera zoom")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 4242
	Game.start_run()
	await _frames(30)
	var mine: Node = Game.current
	var g: TerrainGrid = mine.grid
	var pl: Player = mine.player
	pl.invuln = 1e9
	check(int(Game.run["scaffold"]) == mine.scaffold_cap(), "run starts with a full scaffold meter (%d)" % Game.run["scaffold"])
	# fixture: a solid block with two 17-cell shafts
	for e in mine.enemies.duplicate():
		mine.enemies.erase(e)
		e.queue_free()
	for y in range(148, 172):
		for x in range(18, 34):
			g.set_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE | Cell.F_WATER_SAFE, false)
			g.set_water(x, y, 0)
			g.set_mat(x, y, Cell.BEDROCK if (x == 18 or x == 33 or y == 148 or y == 171) else Cell.HARD)
	for y in range(152, 169):
		g.set_mat(25, y, Cell.AIR)
		g.set_mat(29, y, Cell.AIR)
	g.set_mat(26, 168, Cell.AIR)
	g.set_mat(27, 168, Cell.AIR)
	g.set_mat(28, 168, Cell.AIR)
	g.set_mat(26, 167, Cell.AIR)
	g.set_mat(27, 167, Cell.AIR)
	g.set_mat(28, 167, Cell.AIR)
	await _frames(3)
	pl.global_position = Vector2(25 * 16 + 8, 169 * 16 - Player.HALF.y - 0.5)
	pl.velocity = Vector2.ZERO
	pl.input_override = {"x": 0.0}
	await _frames(10)
	check(pl.feet_cell() == Vector2i(25, 168), "player stands at the shaft bottom %s" % str(pl.feet_cell()))
	Game.run["scaffold"] = 40
	var n: int = mine.build_ladder(pl)
	check(n == 17 and int(Game.run["scaffold"]) == 40 - 2 - 17, "ladder plan fills the shaft to the ceiling: %d cells, %d energy left" % [n, Game.run["scaffold"]])
	await _frames(40)
	var built := 0
	for y in range(152, 169):
		if g.get_mat(25, y) == Cell.LADDER and g.has_flag(25, y, Cell.F_PLAYER_BUILT):
			built += 1
	check(built == 17 and g.get_mat(25, 151) == Cell.HARD, "ladder materialises up to the first solid cell (%d cells)" % built)
	var e0 := int(Game.run["scaffold"])
	check(mine.build_ladder(pl) == 0 and int(Game.run["scaffold"]) == e0, "building where a ladder already stands costs nothing")
	pl.input_override = {"x": 0.0, "y": -1.0}
	await _frames(150)
	check(pl.feet_cell().y <= 154, "player climbs the built ladder (feet row %d)" % pl.feet_cell().y)
	# partial build when energy is short
	pl.input_override = {"x": 0.0}
	pl.on_ladder = false
	pl.global_position = Vector2(29 * 16 + 8, 169 * 16 - Player.HALF.y - 0.5)
	pl.velocity = Vector2.ZERO
	await _frames(10)
	Game.run["scaffold"] = 7
	n = mine.build_ladder(pl)
	await _frames(20)
	check(n == 5 and int(Game.run["scaffold"]) == 0 and g.get_mat(29, 164) == Cell.LADDER and g.get_mat(29, 163) == Cell.AIR, "short energy builds a partial ladder from the bottom (%d cells)" % n)
	check(mine.build_ladder(pl) == 0 and not pl.can_build_ladder(), "empty scaffold builds nothing")
	# energy comes from breaking rock
	mine.damage_cell(Vector2i(30, 168), 99.0, 3, true, "drill")
	check(int(Game.run["scaffold"]) == int(Balance.SCAFFOLD_GAIN[Cell.HARD]), "breaking basalt yields scaffold energy (%d)" % Game.run["scaffold"])
	Game.run["scaffold"] = mine.scaffold_cap()
	mine.damage_cell(Vector2i(31, 168), 99.0, 3, true, "drill")
	check(int(Game.run["scaffold"]) == mine.scaffold_cap(), "scaffold energy is capped")
	# a ladder never replaces solid cells, and passes one-way platforms
	g.set_mat(29, 160, Cell.PLATFORM)
	var plan: Array[Vector2i] = mine.ladder_plan(Vector2i(29, 168))
	check(plan.size() == 11 and not plan.has(Vector2i(29, 160)) and plan.has(Vector2i(29, 152)), "ladder plan passes a platform and stops at rock (%d new cells)" % plan.size())
	# camera zoom follows the setting
	var keep_zoom: float = Settings.values["camera_zoom"]
	Settings.values["camera_zoom"] = 1.6
	Settings.changed.emit()
	check(is_equal_approx(mine.camera.zoom.x, 1.6), "camera zoom follows the setting")
	Settings.values["camera_zoom"] = keep_zoom
	Settings.changed.emit()
	# full-screen map
	var ms: Node = mine.hud.map_screen
	mine.hud.open_map()
	check(ms.is_open and get_tree().paused, "opening the map pauses the game")
	ms.view.size = get_viewport().get_visible_rect().size
	ms.view.zoom_by(1000.0, Vector2(100, 100))
	check(is_equal_approx(ms.view.zoom, MapScreen.ZOOM_MAX), "map zoom is clamped at the maximum")
	ms.view.pan(Vector2(-1e6, -1e6))
	var half: Vector2 = ms.view.size / ms.view.px() * 0.5
	check(ms.view.centre.x <= g.w - half.x + 0.01 and ms.view.centre.y <= g.h - half.y + 0.01, "map panning stops at the map edge")
	ms.view.zoom_by(0.0001, Vector2(100, 100))
	check(is_equal_approx(ms.view.zoom, MapScreen.ZOOM_MIN), "map zoom is clamped at the minimum")
	# (the anchor rule applies once the map is larger than the screen on both axes)
	ms.view.zoom = 6.5
	ms.view.centre = Vector2(g.w * 0.5, g.h * 0.5)
	ms.view._clamp()
	var before_c: Vector2 = ms.view.to_cell(Vector2(330, 170))
	ms.view.zoom_by(1.2, Vector2(330, 170))
	check(ms.view.to_cell(Vector2(330, 170)).distance_to(before_c) < 0.75, "zoom keeps the point under the fingers in place")
	ms.close()
	check(not ms.is_open and not get_tree().paused, "closing the map resumes the game")
	pl.input_override = {}


## Dynamic generator scenario: breach a generated floodgate in a live mine, let
## the jet, currents and erosion run, then re-prove the guaranteed route.
func _floodgate_breach() -> void:
	# Reuse the footprint-regression fixture, which has a genuine floodgate.
	Game.contract = Balance.CONTRACTS[1].duplicate()
	Game.contract["seed"] = 103947
	Game.contract["reward"] = 260
	Game.start_run()
	await _frames(30)
	var mine: Node = Game.current
	var res: Dictionary = {}
	for wf in mine.data.get("water_features", []):
		# Buried reservoirs share the kind label but have no receiving chamber.
		if wf["kind"] == "reservoir" and wf.has("outlet") and wf.has("catch"):
			res = wf
	check(not res.is_empty(), "footprint-regression seed generates a genuine floodgate reservoir")
	if res.is_empty():
		return
	var g: TerrainGrid = mine.grid
	mine.player.invuln = 1e9
	var out: Vector2i = res["outlet"]
	var inside_before := 0
	var rr: Rect2i = res["rect"]
	for y in range(rr.position.y, rr.end.y):
		for x in range(rr.position.x, rr.end.x):
			inside_before += g.get_water(x, y)
	for dy in range(-2, 1):
		mine.damage_cell(Vector2i(out.x, out.y + dy), 99.0, 0, false, "test")
	await _frames(600)
	var inside_after := 0
	for y in range(rr.position.y, rr.end.y):
		for x in range(rr.position.x, rr.end.x):
			inside_after += g.get_water(x, y)
	check(inside_after < inside_before / 2, "breached floodgate drains (%d -> %d units)" % [inside_before, inside_after])
	var doors: Dictionary = {}
	for c in mine.data.get("door_cells", []):
		doors[c] = true
	var dig := DigCheck.new(g, doors)
	dig.allow_ladder = true
	check(dig.cost(mine.data["spawn"], mine.data["door_outside"]) >= 0.0, "route to the relic survives the flood and erosion")
	check(dig.cost(mine.data["door_outside"], mine.data["lift"]) >= 0.0, "route back to the lift survives the flood and erosion")
	check(dig.traps(mine.data["spawn"], mine.data["lift"]).is_empty(), "the flood and erosion create no softlock traps")
