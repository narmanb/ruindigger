extends Node
## Headless test harness. Runs the game's real code paths (no mocks) and
## reports pass/fail per check. Invoke with:
##   godot --headless res://src/tests/test_runner.tscn
##
## Exit code 0 = all tests passed, 1 = at least one failure.

var _pass := 0
var _fail := 0
var _failures: Array = []

func _ready() -> void:
	print("=== RUIN DIGGER test suite ===")
	_test_terrain_basics()
	_test_terrain_mining()
	_test_terrain_no_double_ore()
	_test_terrain_radius_damage()
	_test_protected_never_breaks()
	_test_material_tiers()
	_test_dirty_chunks_local()
	_test_generation_determinism()
	_test_generation_connectivity()
	_test_generation_ore_reachable()
	_test_generation_no_spawn_in_solid()
	_test_generation_ore_reachable_metadata()
	_test_save_roundtrip()
	_test_save_validation()
	_test_balance_upgrades()
	_test_collapse_respects_protection()
	_test_asset_integrity()
	_test_pathfinder()
	_test_line_of_sight()
	print("")
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	for f in _failures:
		print("  FAIL: ", f)
	if _fail > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)

func check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ok   ", name)
	else:
		_fail += 1
		_failures.append(name)
		print("  FAIL ", name)

func approx(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps

# ---------------------------------------------------------------------------

func _make_grid(w: int = 40, h: int = 40) -> TerrainGrid:
	var g := TerrainGrid.new()
	g.setup(w, h)
	g.strata = PackedStringArray(["dustworks", "spore_veins", "forgotten_engine"])
	for y in h:
		for x in w:
			g.material[g.idx(x, y)] = Balance.Mat.SOIL
	return g

func _test_terrain_basics() -> void:
	print("[terrain basics]")
	var g := _make_grid()
	check(g.w == 40 and g.h == 40, "grid dimensions stored")
	check(g.get_material(5, 5) == Balance.Mat.SOIL, "material readable")
	check(g.is_solid(5, 5), "solid test true for soil")
	check(not g.in_bounds(-1, 0), "out of bounds detected")
	check(g.get_material(-1, 0) == Balance.Mat.BEDROCK, "outside map reads as bedrock")
	g.set_material(5, 5, Balance.Mat.EMPTY)
	check(not g.is_solid(5, 5), "cleared cell is not solid")

func _test_terrain_mining() -> void:
	print("[terrain mining]")
	var g := _make_grid()
	# Soil has 1 hp: one point of damage breaks it.
	var broke := g.apply_damage(10, 10, 1, 0)
	check(broke, "soil breaks in one hit")
	check(g.get_material(10, 10) == Balance.Mat.EMPTY, "broken cell becomes empty")
	# Basalt needs 4.
	g.set_material(11, 10, Balance.Mat.BASALT)
	check(not g.apply_damage(11, 10, 1, 0), "basalt survives first hit")
	check(g.get_damage(11, 10) == 1, "damage accumulates")
	g.apply_damage(11, 10, 3, 0)
	check(g.get_material(11, 10) == Balance.Mat.EMPTY, "basalt breaks at hp")
	check(g.get_damage(11, 10) == 0, "damage resets after break")

func _test_terrain_no_double_ore() -> void:
	print("[ore awarded exactly once]")
	var g := _make_grid()
	g.set_ore(7, 7, 2)
	var awarded := []
	g.ore_mined.connect(func(id, cell): awarded.append(id))
	g.apply_damage(7, 7, 1, 0)
	check(awarded.size() == 1, "ore emitted once on break")
	check(awarded[0] == 2, "correct ore id emitted")
	g.apply_damage(7, 7, 5, 0)   # already empty
	check(awarded.size() == 1, "no second award from empty cell")
	check(g.get_ore(7, 7) == 0, "ore cleared from grid")

func _test_terrain_radius_damage() -> void:
	print("[radius damage]")
	var g := _make_grid()
	var broken := g.damage_radius(20, 20, 2.0, 5, 99, true)
	check(broken.size() > 8, "radius breaks a cluster (got %d)" % broken.size())
	# Cells far outside the radius must be untouched.
	check(g.get_material(20 + 5, 20) == Balance.Mat.SOIL, "outside radius untouched")
	check(g.get_material(20, 20) == Balance.Mat.EMPTY, "centre broken")

func _test_protected_never_breaks() -> void:
	print("[protected cells]")
	var g := _make_grid()
	g.protect(30, 30, 2)
	check(g.is_protected(30, 30), "cell reports protected")
	var broke := g.apply_damage(30, 30, 999, 99)
	check(not broke, "protected cell never breaks")
	check(g.get_material(30, 30) == Balance.Mat.SOIL, "protected material intact")
	# Explosions must skip protected cells too.
	g.damage_radius(30, 30, 3.0, 999, 99, true)
	check(g.get_material(30, 30) == Balance.Mat.SOIL, "explosion respects protection")

func _test_material_tiers() -> void:
	print("[material drill tiers]")
	var g := _make_grid()
	g.set_material(2, 2, Balance.Mat.ALLOY)
	check(not g.can_mine(2, 2, 0), "tier 0 cannot mine alloy")
	check(g.can_mine(2, 2, 1), "tier 1 can mine alloy")
	check(not g.apply_damage(2, 2, 99, 0), "tier 0 alloy damage rejected")
	check(g.get_material(2, 2) == Balance.Mat.ALLOY, "alloy intact after rejected hit")
	check(g.apply_damage(2, 2, 99, 1), "tier 1 alloy damage accepted")
	# Bedrock is indestructible at every tier.
	g.set_material(3, 3, Balance.Mat.BEDROCK)
	check(not g.apply_damage(3, 3, 9999, 99), "bedrock never breaks")

func _test_dirty_chunks_local() -> void:
	print("[chunk-local updates]")
	var g := TerrainGrid.new()
	g.setup(128, 128)
	g.chunk = 16
	g.mark_dirty(4, 4)
	var dirty := g.take_all_dirty()
	# Editing one cell must dirty at most a 3x3 block of chunks, never all of them.
	check(dirty.size() <= 9, "one edit dirties <= 9 chunks (got %d)" % dirty.size())
	check(dirty.size() > 0, "one edit dirties at least one chunk")
	var total_chunks := (128 / 16) * (128 / 16)
	check(dirty.size() < total_chunks, "does not dirty the whole map")

func _test_generation_determinism() -> void:
	print("[generation determinism]")
	var a := WorldGen.generate(12345, 90, 70)
	var b := WorldGen.generate(12345, 90, 70)
	check(a.grid.material == b.grid.material, "same seed -> identical material")
	check(a.spawn == b.spawn and a.lift == b.lift and a.relic == b.relic,
			"same seed -> identical landmarks")
	check(a.grid.ore == b.grid.ore, "same seed -> identical ore")
	var c := WorldGen.generate(54321, 90, 70)
	check(a.grid.material != c.grid.material, "different seed -> different map")

func _test_generation_connectivity() -> void:
	print("[generation connectivity]")
	var seeds := [1, 2, 3, 7, 42, 99, 1234, 55555, 777, 31337]
	var all_ok := true
	for s in seeds:
		var r := WorldGen.generate(s, 120, 100)
		var target := Vector2i(r.relic.x, r.relic.y - 2)
		var to_relic: bool = r.grid.reachable(r.spawn, target, 400000)
		var back: bool = r.grid.reachable(target, r.lift, 400000)
		if not (to_relic and back):
			all_ok = false
			print("    seed %d: to_relic=%s back=%s" % [s, to_relic, back])
	check(all_ok, "spawn->relic->lift reachable for all sampled seeds")

func _test_generation_ore_reachable() -> void:
	print("[ore is always lootable]")
	# Every ore cell must sit on the reachable frontier, so no seed can place a
	# reward that is physically impossible to collect.
	var all_ok := true
	for s in [11, 222, 3333, 44444]:
		var r := WorldGen.generate(s, 110, 96)
		var mask: PackedByteArray = r.grid.reach_mask_diggable(r.spawn, 400000)
		var unreachable := 0
		for i in r.grid.ore.size():
			if r.grid.ore[i] == 0:
				continue
			if mask[i] == 0:
				unreachable += 1
		if unreachable > 0:
			all_ok = false
			print("    seed %d: %d unreachable ore cells" % [s, unreachable])
	check(all_ok, "every ore vein is reachable by drilling")

func _test_generation_no_spawn_in_solid() -> void:
	print("[spawn safety]")
	var ok := true
	for s in [5, 50, 500, 5000]:
		var r := WorldGen.generate(s, 100, 90)
		if r.grid.is_solid(r.spawn.x, r.spawn.y):
			ok = false
		# Player collider is roughly 1 cell: the cell above must be open too.
		if r.grid.is_solid(r.spawn.x, r.spawn.y - 1):
			ok = false
	check(ok, "player never spawns inside solid terrain")

func _test_generation_ore_reachable_metadata() -> void:
	print("[generation metadata]")
	var r := WorldGen.generate(2024, 120, 100)
	check(r.relic_room.size.x > 0, "relic chamber has area")
	check(r.grid.get_material(r.relic.x, r.relic.y) == Balance.Mat.EMPTY,
			"relic cell is open")
	check(r.grid.is_protected(r.lift.x, r.lift.y), "lift cell is protected")
	var ore_count := 0
	for i in r.grid.ore.size():
		if r.grid.ore[i] != 0:
			ore_count += 1
	check(ore_count > 20, "map contains ore (got %d)" % ore_count)
	var gas_count := r.grid.gas.size()
	check(gas_count > 0, "map contains gas pockets (got %d)" % gas_count)

func _test_save_roundtrip() -> void:
	print("[save roundtrip]")
	var sm := SaveManager
	var orig_credits := sm.credits
	var orig_drill := sm.upgrade_level("drill")
	sm.credits = 777
	sm.upgrades["drill"] = 2
	sm.save()
	sm.credits = 0
	sm.upgrades["drill"] = 0
	sm.load_save()
	check(sm.credits == 777, "credits persisted")
	check(sm.upgrade_level("drill") == 2, "upgrades persisted")
	sm.credits = orig_credits
	sm.upgrades["drill"] = orig_drill
	sm.save()

func _test_save_validation() -> void:
	print("[save validation]")
	var sm := SaveManager
	var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	sm.load_save()   # must not crash
	check(true, "corrupt save does not crash load")
	sm._apply({"version": 1, "credits": -50,
			"upgrades": {"drill": 999}, "settings": {"master_volume": 99.0}})
	check(sm.credits == 0, "negative credits clamped to 0")
	check(sm.upgrade_level("drill") == Balance.UPGRADES["drill"]["max_level"],
			"out-of-range upgrade clamped to max")
	check(sm.settings["master_volume"] <= 1.0, "volume clamped to 1.0")
	sm.save()

func _test_balance_upgrades() -> void:
	print("[balance derivations]")
	check(Balance.drill_power(0) == 1.0, "level 0 drill power is 1.0")
	check(Balance.drill_power(3) > Balance.drill_power(1), "drill power increases")
	check(Balance.drill_tier(0) == 0 and Balance.drill_tier(1) == 1, "tier gate at level 1")
	check(Balance.player_max_hp(2) > Balance.player_max_hp(0), "suit adds hull")
	check(Balance.carry_capacity(3) > Balance.carry_capacity(0), "cargo adds capacity")
	check(Balance.charge_capacity(2) > Balance.charge_capacity(0), "charges upgrade works")

func _test_collapse_respects_protection() -> void:
	print("[collapse protection]")
	var g := _make_grid(30, 30)
	g.protect(15, 15, 3)
	# A protected column must not be collected as a collapsing cluster.
	var collapsed := []
	var cs := CollapseSystem.new()
	cs.grid = g
	cs._scan_above(15, 20)
	check(cs._pending.size() == 0, "protected column never queues a collapse")

func _test_asset_integrity() -> void:
	print("[asset integrity]")
	var required := [
		"res://assets/tiles/terrain_atlas.png",
		"res://assets/tiles/terrain_atlas.json",
		"res://assets/sprites/player_sheet.png",
		"res://assets/sprites/player_sheet.json",
		"res://assets/sprites/enemy_sheet.png",
		"res://assets/sprites/enemy_sheet.json",
		"res://assets/sprites/ore_sheet.png",
		"res://assets/fx/fx_sheet.png",
		"res://assets/ui/panel_sheet.png",
		"res://assets/ui/button_sheet.png",
		"res://assets/font/font.fnt",
		"res://assets/bg/bg_dustworks_far.png",
		"res://assets/audio/dig_soft.wav",
		"res://assets/audio/explosion.wav",
	]
	var all_present := true
	for p in required:
		if not ResourceLoader.exists(p):
			all_present = false
			print("    missing: ", p)
	check(all_present, "all critical assets present")
	# Verify the terrain atlas row metadata matches the generator's layout.
	var f := FileAccess.open("res://assets/tiles/terrain_atlas.json", FileAccess.READ)
	var meta = JSON.parse_string(f.get_as_text())
	f.close()
	check(typeof(meta) == TYPE_DICTIONARY, "terrain atlas json parses")
	var rows: Dictionary = meta.get("rows", {})
	check(rows.has("dustworks:soil:0"), "soil row metadata present")
	check(rows.has("forgotten_engine:alloy:2"), "alloy rubble row metadata present")
	var tex: Texture2D = load("res://assets/tiles/terrain_atlas.png")
	check(tex.get_width() == 16 * 2 * 16, "atlas width = masks*variants*tile")
	var expected_rows := 3 * 3 * 3 + 3   # 3 strata x (soil,basalt,alloy) x 3 stages + bedrock
	check(tex.get_height() == expected_rows * 16, "atlas height = rows*tile (got %d)" % tex.get_height())

func _test_pathfinder() -> void:
	print("[pathfinder]")
	var g := _make_grid(30, 30)
	# Open a horizontal corridor.
	for x in range(2, 28):
		g.material[g.idx(x, 15)] = Balance.Mat.EMPTY
	var path := GridPathfinder.find_path(g, Vector2i(3, 15), Vector2i(26, 15))
	check(path.size() > 0, "path found along corridor")
	check(path[0] == Vector2i(3, 15), "path starts at origin")
	check(path[path.size() - 1] == Vector2i(26, 15), "path ends at goal")
	# A goal inside solid rock with no route should fail cleanly.
	var g2 := _make_grid(20, 20)
	g2.material[g2.idx(10, 10)] = Balance.Mat.EMPTY
	var path2 := GridPathfinder.find_path(g2, Vector2i(10, 10), Vector2i(19, 19), 500)
	check(path2.size() == 0, "unreachable goal returns empty path")

func _test_line_of_sight() -> void:
	print("[line of sight]")
	var g := _make_grid(20, 20)
	var a := g.cell_to_world(Vector2i(2, 10))
	var b := g.cell_to_world(Vector2i(17, 10))
	check(not GridPathfinder.has_line_of_sight(g, a, b), "solid rock blocks LOS")
	for x in range(2, 18):
		g.material[g.idx(x, 10)] = Balance.Mat.EMPTY
	check(GridPathfinder.has_line_of_sight(g, a, b), "open corridor allows LOS")
