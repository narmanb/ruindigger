extends RefCounted
## The First Civilization: deep-stage generation, the one-way descent and the
## Transit Gate extraction. Runs as suite=deep.

static func _hash(d: Dictionary) -> int:
	var g: TerrainGrid = d["grid"]
	return hash(g.mat) ^ hash(g.ore) ^ hash(g.water) ^ hash(g.lava) ^ hash(g.flags) ^ hash(str(d["entities"])) ^ hash(str(d["landmarks"]))


static func generation(t: Node, n: int) -> void:
	t.section("first civilization generation x%d seeds" % n)
	var worst_ms := 0
	var total_sealed := 0
	var repaired := 0
	for i in n:
		var run_seed := 1000 + i * 7919
		var tag := "deep %d" % run_seed
		var gen := FirstCivGenerator.new()
		var t0 := Time.get_ticks_msec()
		var d := gen.generate(FirstCivGenerator.deep_seed(run_seed))
		worst_ms = maxi(worst_ms, Time.get_ticks_msec() - t0)
		var g: TerrainGrid = d["grid"]
		t.check(g.w == Balance.DEEP_W and g.h == Balance.DEEP_H and g.w == 200 and g.h == 120, tag + ": map is 200x120, independent of the main mine (%dx%d)" % [g.w, g.h])
		t.check(d["valid"], tag + ": valid")
		if int(d["repairs"]) > 0:
			print("  REPAIRED deep seed ", run_seed)
		repaired += int(d["repairs"])
		total_sealed += int(d.get("traps_sealed", 0))
		var biome_ok := true
		for s in g.stratum:
			if s != Balance.Z_FIRST:
				biome_ok = false
				break
		t.check(biome_ok, tag + ": every cell carries the sixth biome identity")
		# arrival: open, standing, on a floor nothing can break
		var sp: Vector2i = d["spawn"]
		t.check(RouteCheck.body_ok(g, sp.x, sp.y) and g.is_solid(sp.x, sp.y + 1) and g.has_flag(sp.x, sp.y + 1, Cell.F_PROTECTED), tag + ": arrival is open and stands on a protected floor")
		# no way back: no lift of any kind, and the shaft above ends in bedrock
		var lifts := 0
		var gates := 0
		for e in d["entities"]:
			if e["type"] == "lift" or e["type"] == "ancient_descent":
				lifts += 1
			if e["type"] == "transit_gate":
				gates += 1
		t.check(lifts == 0 and gates == 1, tag + ": no lift, exactly one Transit Gate (%d lifts, %d gates)" % [lifts, gates])
		var sealed_top := true
		for x in range(sp.x - 1, sp.x + 2):
			if g.get_mat(x, 1) != Cell.BEDROCK:
				sealed_top = false
		t.check(sealed_top, tag + ": the arrival shaft ends in bedrock")
		# the gate: near the bottom, on a protected floor, with headroom
		var gc: Vector2i = d["gate"]
		var gate_ok := gc.y >= Balance.DEEP_BAND_TRANSIT
		for x in range(gc.x - 2, gc.x + 3):
			if not g.is_solid(x, gc.y + 1) or not g.has_flag(x, gc.y + 1, Cell.F_PROTECTED):
				gate_ok = false
			for y in range(gc.y - 3, gc.y + 1):
				if g.is_solid(x, y):
					gate_ok = false
		t.check(gate_ok, tag + ": Transit Gate sits in the lower level on a protected floor with headroom")
		# fairness: reachable within budget, and nowhere you cannot reach the gate from
		t.check(float(d["dig_to_gate_s"]) >= 0.0 and float(d["dig_to_gate_s"]) <= Balance.DEEP_DIG_BUDGET, tag + ": gate reachable by digging within budget (%.0f s)" % d["dig_to_gate_s"])
		var dig := DigCheck.new(g)
		var traps := dig.traps(sp, gc)
		t.check(traps.is_empty(), tag + ": no cell is cut off from the gate (%d, e.g. %s)" % [traps.size(), str(traps.slice(0, 3))])
		# the plant's two tanks are sealed containers on purpose
		var tanks: Array = [d["plant"]["heat_tank"], d["plant"]["coolant_tank"]] if d.has("plant") else []
		var pockets: Array = []
		for pc in RouteCheck.sealed_pockets(g, sp):
			var in_tank := false
			for tr: Rect2i in tanks:
				if tr.has_point(pc):
					in_tank = true
			if not in_tank:
				pockets.append(pc)
		t.check(pockets.is_empty(), tag + ": no sealed pockets outside the plant tanks (%d)" % pockets.size())
		t.check((d["plan"]["overlaps"] as Array).is_empty(), tag + ": no reserved footprints overlap %s" % str(d["plan"]["overlaps"]))
		t.check(int(d["plan"]["vaults"]) >= 4, tag + ": at least 4 great vaults (%d)" % d["plan"]["vaults"])
		# content sanity
		var in_rock := 0
		var near_spawn := 0
		for e in d["entities"]:
			if e["type"] == "crawler":
				if g.is_solid(e["cell"].x, e["cell"].y):
					in_rock += 1
				if absi(e["cell"].x - sp.x) + absi(e["cell"].y - sp.y) < 30:
					near_spawn += 1
		t.check(in_rock == 0 and near_spawn == 0, tag + ": guardians stand in open space, away from arrival")
		var unsupported := 0
		for y in range(2, g.h - 4):
			for x in range(2, g.w - 2):
				if g.get_mat(x, y) == Cell.HARD and not g.is_solid(x, y + 1) and not Boulders.unsupported_mass(g, Vector2i(x, y)).is_empty():
					unsupported += 1
		t.check(unsupported == 0, tag + ": no basalt starts unsupported (%d)" % unsupported)
		var sim := WaterSim.new(g)
		var before := sim.total()
		var steps := sim.settle(40)
		g.cell_changed.disconnect(sim._on_cell_changed)
		t.check(steps < 40 and sim.total() == before, tag + ": generated water is at rest and conserved (%d steps)" % steps)
		# lava: present, at rest, never touching water, never in the entry or exit halls
		var lava_cells := 0
		var touching := 0
		for y in range(1, g.h - 1):
			for x in range(1, g.w - 1):
				if g.get_lava(x, y) <= 0:
					continue
				lava_cells += 1
				for dd in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if g.get_water(x + dd.x, y + dd.y) > 0:
						touching += 1
		t.check(lava_cells >= 20 and int(d.get("quench_pairs", 0)) >= 1 and int(d.get("sluices", 0)) >= 1, tag + ": lava, water-over-lava and lava-over-water features exist (%d lava cells, %d quench pairs, %d sluices)" % [lava_cells, d.get("quench_pairs", 0), d.get("sluices", 0)])
		t.check(touching == 0, tag + ": generated lava never touches water (%d contacts)" % touching)
		var in_halls := 0
		for c in d["lava_keep_out"]:
			if g.get_lava(c.x, c.y) > 0:
				in_halls += 1
		t.check(in_halls == 0 and (d["lava_keep_out"] as Array).size() > 0, tag + ": no lava in the arrival or gate halls")
		var ls := LavaSim.new(g)
		var lava0 := ls.total()
		var lsteps := ls.settle(30)
		g.cell_changed.disconnect(ls._on_cell_changed)
		t.check(lsteps < 30 and ls.total() == lava0 and ls.rock_formed == 0, tag + ": generated lava is at rest and conserved (%d steps)" % lsteps)
		var ore := 0
		for o in g.ore:
			if o != 0:
				ore += 1
		t.check(ore >= 60, tag + ": premium ore present (%d cells)" % ore)
		_plant_checks(t, tag, d, i < 12)
		var finds: Array = d.get("finds", [])
		var fl_ok := finds.size() == 1 and int(finds[0]["id"]) == Balance.Z_FIRST
		if fl_ok:
			var fc: Vector2i = finds[0]["cell"]
			fl_ok = fc.y >= Balance.DEEP_BAND_TRANSIT and RouteCheck.body_ok(g, fc.x, fc.y) and g.is_solid(fc.x, fc.y + 1) and g.get_water(fc.x, fc.y) == 0 and g.get_lava(fc.x, fc.y) == 0
			var fdc := DigCheck.new(g)
			fdc.allow_ladder = true
			fl_ok = fl_ok and fdc.costs_from(sp)[fc.y * g.w + fc.x] < DigCheck.UNREACHED and fdc.cost(fc, d["gate"]) >= 0.0
		t.check(fl_ok, tag + ": the First Light lies dry in the lower transit level, reachable, with a way on to the gate")
		if i < 4:
			var again := FirstCivGenerator.new().generate(FirstCivGenerator.deep_seed(run_seed))
			t.check(_hash(again) == _hash(d), tag + ": generation is deterministic")
	print("  deep seeds needing repair: %d / %d, slowest %d ms, trap cells sealed %d" % [repaired, n, worst_ms, total_sealed])
	t.check(repaired == 0, "the deep stage never needed its repair fallback")
	t.check(FirstCivGenerator.deep_seed(7) == FirstCivGenerator.deep_seed(7) and FirstCivGenerator.deep_seed(7) != FirstCivGenerator.deep_seed(8), "the deep seed is derived deterministically from the run seed")


static func _sum(g: TerrainGrid, cells: Array, lava: bool) -> int:
	var s := 0
	for c in cells:
		s += g.get_lava(c.x, c.y) if lava else g.get_water(c.x, c.y)
	return s


## The Thermal Plant: present, reachable, enough fuel, and (for `simulate`
## seeds) actually solvable and recoverable in a headless fluid run.
static func _plant_checks(t: Node, tag: String, d: Dictionary, simulate: bool) -> void:
	var g: TerrainGrid = d["grid"]
	var p: Dictionary = d.get("plant", {})
	t.check(not p.is_empty(), tag + ": a Thermal Plant exists")
	if p.is_empty():
		return
	var valves := 0
	var engines := 0
	var consoles: Array = []
	for e in d["entities"]:
		if e["type"] == "valve":
			valves += 1
			consoles.append(e["cell"])
		elif e["type"] == "thermal_engine":
			engines += 1
	t.check(valves == 2 and engines == 1, tag + ": two valve consoles and one engine (%d, %d)" % [valves, engines])
	var heat_fuel := 0
	var cool_fuel := 0
	var tank: Rect2i = p["heat_tank"]
	for y in range(tank.position.y, tank.end.y):
		for x in range(tank.position.x, tank.end.x):
			heat_fuel += g.get_lava(x, y)
	tank = p["coolant_tank"]
	for y in range(tank.position.y, tank.end.y):
		for x in range(tank.position.x, tank.end.x):
			cool_fuel += g.get_water(x, y)
	t.check(heat_fuel >= 3 * Balance.PLANT_HEAT_NEED and cool_fuel >= 3 * Balance.PLANT_COOL_NEED, tag + ": the tanks hold over 3x what the engine needs (heat %d, coolant %d)" % [heat_fuel, cool_fuel])
	t.check(_sum(g, p["heat_basin"], true) == 0 and _sum(g, p["coolant_basin"], false) == 0, tag + ": the basins start empty (the engine starts cold)")
	var dig := DigCheck.new(g)
	dig.allow_ladder = true
	var from_spawn := dig.costs_from(d["spawn"])
	var reach := true
	for c in consoles:
		if from_spawn[c.y * g.w + c.x] >= DigCheck.UNREACHED or dig.cost(c, d["gate"]) < 0.0:
			reach = false
	t.check(reach, tag + ": both valve consoles are reachable, and the gate is reachable from them")
	if not simulate:
		return
	# solve it: open both valves on a copy and let the fluids run
	var g2 := TerrainGrid.from_dict(g.to_dict())
	var w2 := WaterSim.new(g2)
	var l2 := LavaSim.new(g2, w2, SteamField.new(g2))
	for c in p["coolant_basin"]:
		l2.keep_out[c] = true
	for c in p["heat_outlet"] + p["coolant_outlet"]:
		g2.set_mat(c.x, c.y, Cell.AIR)
	var solved_at := -1
	for frame in 1800:
		w2.update(1.0 / 60.0)
		l2.update(1.0 / 60.0)
		if frame % 30 == 0 and _sum(g2, p["heat_basin"], true) >= Balance.PLANT_HEAT_NEED and _sum(g2, p["coolant_basin"], false) >= Balance.PLANT_COOL_NEED:
			solved_at = frame
			break
	t.check(solved_at >= 0, tag + ": opening both valves powers the engine (after %.1f s)" % (solved_at / 60.0))
	# recover from a mistake: water spilled onto the heat basin crusts its top
	var heat_cells: Array = p["heat_basin"]
	for frame in 600:
		w2.update(1.0 / 60.0)
		l2.update(1.0 / 60.0)
	var top := 1 << 20
	for c in heat_cells:
		top = mini(top, c.y)
	for c in heat_cells:
		if c.y == top:
			g2.set_water(c.x, c.y - 2, Balance.WATER_MAX)
			g2.set_water(c.x, c.y - 3, Balance.WATER_MAX)
	w2.wake_all()
	l2.wake_all()
	for frame in 900:
		w2.update(1.0 / 60.0)
		l2.update(1.0 / 60.0)
	var crusted := 0
	for c in heat_cells:
		if g2.is_solid(c.x, c.y):
			crusted += 1
	t.check(crusted > 0, tag + ": water spilled on the heat intake crusts its surface (%d cells)" % crusted)
	t.check(_sum(g2, heat_cells, true) >= Balance.PLANT_HEAT_NEED, tag + ": the lava under the crust still powers the engine (%d units)" % _sum(g2, heat_cells, true))
	for c in heat_cells:
		if g2.is_solid(c.x, c.y):
			g2.damage(c.x, c.y, 99.0, 0, false)
	t.check(_sum(g2, heat_cells, true) >= Balance.PLANT_HEAT_NEED, tag + ": drilling the crust out leaves the intake working")


## The entrance in the main mine: present, in the Engine vault, safe to stand in,
## reachable, and never a trap.
static func entrance(t: Node, n: int) -> void:
	t.section("ancient descent entrance x%d seeds" % n)
	var missing := 0
	for i in n:
		var seed_value := 1000 + i * 7919
		var tag := "seed %d" % seed_value
		var gen := MineGenerator.new()
		var d := gen.generate(seed_value, Balance.CONTRACTS[i % Balance.CONTRACTS.size()])
		var g: TerrainGrid = d["grid"]
		var c: Vector2i = d.get("descent", Vector2i(-1, -1))
		if c.x < 0:
			missing += 1
			continue
		t.check(g.get_stratum(c.x, c.y) == Balance.Z_ENGINE, tag + ": descent platform is in the Forgotten Engine")
		var room_ok := true
		for x in range(c.x - 2, c.x + 3):
			if not g.is_solid(x, c.y + 1) or not g.has_flag(x, c.y + 1, Cell.F_PROTECTED):
				room_ok = false
			for y in range(c.y - 2, c.y + 1):
				if g.is_solid(x, y) or g.get_water(x, y) > 0:
					room_ok = false
		t.check(room_ok, tag + ": descent platform has a protected floor, headroom and no water")
		var dig := DigCheck.new(g, gen.door_open_cells())
		dig.allow_ladder = true
		var from_spawn := dig.costs_from(d["spawn"])
		t.check(from_spawn[c.y * g.w + c.x] < DigCheck.UNREACHED, tag + ": descent platform is reachable from the surface")
		t.check(dig.cost(c, d["lift"]) >= 0.0, tag + ": you can still walk away from the platform to a lift")
		var far := absi(c.x - d["relic"].x) + absi(c.y - d["relic"].y) >= 8
		t.check(far, tag + ": descent platform is separate from the relic chamber")
	t.check(missing == 0, "every mine has an Ancient Descent Platform (%d of %d missing)" % [missing, n])


static func live(t: Node) -> void:
	t.section("one-way descent and transit gate")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	Game.contract["reward"] = 260
	Game.start_run()
	await t._frames(40)
	var mine: Node = Game.current
	t.check(mine.stage == "mine" and mine.descent != null and mine.gate == null, "the main mine has a descent platform and no transit gate")
	if mine.descent == null:
		return
	var pl: Player = mine.player
	pl.invuln = 1e9
	var main_has_lava: bool = mine.lava != null or mine.steam != null
	# a normal lift is still a lift: the platform is a different interactable
	t.check(mine.nearest_interactable(pl).get("kind", "") != "descent", "the descent is not offered from the lift room")
	Game.run["cargo"] = {1: 3, 3: 2}
	Game.run["relic"] = true
	Game.run["charges"] = 3
	Game.run["scaffold"] = 17
	Game.run["finds"] = [2]
	Game.run["kills"] = 4
	pl.hp = 61.0
	var time_before := float(Game.run["time"])
	pl.input_override = {"x": 0.0}
	pl.global_position = mine.descent.global_position + Vector2(0, -Player.HALF.y - 0.5)
	pl.velocity = Vector2.ZERO
	await t._frames(12)
	var it: Dictionary = mine.nearest_interactable(pl)
	t.check(it.get("kind", "") == "descent" and it.get("label", "") == "DESCEND", "standing on the platform offers DESCEND (%s)" % str(it.get("label", "")))
	# one press only raises the warning
	mine.player_interact(pl)
	var prompt: Node = mine.descent_prompt
	t.check(prompt.is_open and t.get_tree().paused and Game.run["stage"] == "mine" and not mine.ending, "using the platform shows the one-way warning and does not descend")
	t.check(prompt.get_viewport().gui_get_focus_owner() == prompt.stay_btn, "the safe choice (STAY) has focus by default")
	prompt.close()
	t.check(not prompt.is_open and not t.get_tree().paused and Game.current == mine and Game.run["stage"] == "mine", "STAY closes the warning and nothing changes")
	await t._frames(5)
	mine.player_interact(pl)
	prompt._confirm()
	t.check(mine.ending and not pl.controls_enabled, "confirming starts the descent sequence")
	var guard := 0
	while (Game.current == mine or Game.current == null or Game.current.get("player") == null) and guard < 600:
		guard += 1
		await t.get_tree().physics_frame
	var deep: Node = Game.current
	t.check(deep != mine and deep != null and deep.get("stage") == "deep", "the run continues in a new stage (after %d frames)" % guard)
	if deep == null or deep.get("stage") != "deep":
		return
	# snapshot the run the moment the new stage exists, before anything down
	# here (a crawler burning in lava, a falling boulder) can change it
	var arrived := [Game.run["cargo"].duplicate(), Game.run["relic"], int(Game.run["charges"]), int(Game.run["scaffold"]), Game.run["finds"].duplicate(), int(Game.run["kills"])]
	await t._frames(30)
	var g: TerrainGrid = deep.grid
	var dp: Player = deep.player
	dp.invuln = 1e9
	t.check(g.w == 200 and g.h == 120, "the deep stage runs its own 200x120 map")
	t.check(arrived == [{1: 3, 3: 2}, true, 3, 17, [2], 4], "cargo, relic, charges, scaffold, finds and kills are unchanged by the descent (%s)" % str(arrived))
	t.check(int(Game.run["seed"]) == 7 and Game.run["contract"]["id"] == Balance.CONTRACTS[0]["id"], "seed and contract are unchanged")
	t.check(is_equal_approx(dp.hp, 61.0), "hull carries over (%.0f)" % dp.hp)
	t.check(float(Game.run["time"]) > time_before, "the run clock keeps counting")
	t.check(deep.lifts.is_empty() and deep.descent == null and deep.relic == null, "no lift, no way back and no second relic down here")
	t.check(deep.gate != null and not deep.gate.online and not deep.gate.powered, "a dormant, unpowered Transit Gate exists")
	t.check(deep.engine != null and deep.valves.size() == 2 and not deep.engine.online, "the Thermal Plant is cold: an engine and two closed valves")
	t.check(int(Game.run["max_depth"]) >= Balance.MAP_H and deep.depth_offset == Balance.MAP_H, "depth keeps counting from the Engine (%d cells)" % Game.run["max_depth"])
	t.check(dp.is_on_floor() and not g.is_solid(g.world_to_cell(dp.global_position).x, g.world_to_cell(dp.global_position).y), "the player arrives standing in the arrival hall")
	t.check(deep.current_stratum == Balance.Z_FIRST, "the stage uses the sixth biome (light, backdrop, music)")
	t.check(deep.lava != null and deep.steam != null and not main_has_lava, "lava and steam run in the deep stage only")
	# live lava: wading burns on a fair cadence and slows you; water on lava crusts
	var lx := 30
	var ly := 30
	for y in range(ly - 4, ly + 3):
		for x in range(lx - 6, lx + 7):
			g.set_flag(x, y, Cell.F_PROTECTED, false)
			g.set_water(x, y, 0)
			g.set_lava(x, y, 0)
			g.set_mat(x, y, Cell.BEDROCK if (y == ly + 2 or x == lx - 6 or x == lx + 6 or y == ly - 4) else Cell.AIR)
	for e in deep.enemies.duplicate():
		if is_instance_valid(e) and Rect2(Vector2(lx - 8, ly - 6) * 16, Vector2(18, 10) * 16).has_point(e.global_position):
			deep.enemies.erase(e)
			e.queue_free()
	for x in range(lx - 2, lx + 3):
		g.set_lava(x, ly + 1, Balance.LAVA_MAX)
	deep.lava.wake_all()
	dp.invuln = 0.0
	dp.hp = dp.max_hp
	dp.global_position = Vector2(lx * 16 + 8, (ly + 2) * 16 - Player.HALF.y - 0.5)
	dp.velocity = Vector2.ZERO
	var hp0 := dp.hp
	await t._frames(20)
	var first_hit := dp.max_hp - dp.hp
	t.check(first_hit > 0.0 and first_hit <= Balance.LAVA_BURN_DAMAGE + 0.01, "standing in lava burns, one burn at a time (%.0f)" % first_hit)
	await t._frames(60)
	var burned := hp0 - dp.hp
	t.check(burned > first_hit and burned < Balance.LAVA_BURN_DAMAGE * 4.0 and not dp.dead, "burns repeat on a fair cadence, never an instant kill (%.0f over ~1.3 s)" % burned)
	dp.hp = dp.max_hp
	dp.invuln = 1e9
	dp.global_position = Vector2((lx - 4) * 16 + 8, (ly + 2) * 16 - Player.HALF.y - 0.5)
	# a cistern's worth of water (three rows) over five cells of lava
	for x in range(lx - 2, lx + 3):
		for y in range(ly - 3, ly):
			g.set_water(x, y, Balance.WATER_MAX)
	deep.water.wake_all()
	var formed := 0
	for k in 300:
		await t.get_tree().physics_frame
		formed = deep.lava.rock_formed
		if formed >= 3:
			break
	t.check(formed >= 3, "water poured on live lava forms new rock in the running game (%d cells)" % formed)
	var crust_ok := false
	for x in range(lx - 2, lx + 3):
		if g.get_mat(x, ly + 1) == Cell.HARD:
			crust_ok = true
	t.check(crust_ok, "the crust forms where the lava was")
	dp.invuln = 1e9
	# HUD, map and pause still work here
	var ms: Node = deep.hud.map_screen
	deep.hud.open_map()
	t.check(ms.is_open and t.get_tree().paused, "the full-screen map opens in the deep stage")
	ms.close()
	deep.pause_menu.open()
	t.check(deep.pause_menu.is_open, "the pause menu opens in the deep stage")
	deep.pause_menu.close()
	t.check(deep.nearest_interactable(dp).is_empty(), "nothing in the arrival hall offers an exit")
	# the gate: without power it explains what is missing and stays shut
	dp.input_override = {"x": 0.0}
	dp.global_position = deep.gate.global_position + Vector2(0, -Player.HALF.y - 0.5)
	dp.velocity = Vector2.ZERO
	await t._frames(12)
	var gi: Dictionary = deep.nearest_interactable(dp)
	t.check(gi.get("kind", "") == "gate", "the Transit Gate can be used from its platform")
	deep.player_interact(dp)
	t.check(not deep.gate.online and not deep.ending and deep.gate.status_text().contains("HEAT INPUT") and deep.gate.status_text().contains("COOLANT"), "an unpowered gate refuses and says which inputs are missing")
	# restore power: go to each valve console and open it
	for v in deep.valves:
		dp.global_position = v.global_position + Vector2(0, -Player.HALF.y - 0.5)
		dp.velocity = Vector2.ZERO
		await t._frames(10)
		var vi: Dictionary = deep.nearest_interactable(dp)
		t.check(vi.get("kind", "") == "valve" and String(vi.get("label", "")).begins_with("OPEN"), "a valve console offers %s" % vi.get("label", "?"))
		deep.player_interact(dp)
		t.check(v.open, "using the console opens the %s valve" % v.system)
	var powered_at := -1
	for frame in 2400:
		await t.get_tree().physics_frame
		if deep.engine.online:
			powered_at = frame
			break
	t.check(powered_at >= 0 and deep.gate.powered, "molten feed and coolant bring the Thermal Engine online (after %d frames)" % powered_at)
	t.check(deep.engine.heat_ready() and deep.engine.cool_ready(), "the engine reads both inputs ready (%s)" % deep.engine.status())
	dp.global_position = deep.gate.global_position + Vector2(0, -Player.HALF.y - 0.5)
	dp.velocity = Vector2.ZERO
	await t._frames(12)
	deep.player_interact(dp)
	t.check(deep.gate.online and not deep.ending, "with power, the first use wakes the gate without leaving")
	var credits_before: int = Progress.credits
	deep.player_interact(dp)
	t.check(deep.ending, "the second use starts the transit")
	guard = 0
	while Game.current_name != "results" and guard < 400:
		guard += 1
		await t.get_tree().physics_frame
	var r: Dictionary = Game.last_result
	t.check(Game.current_name == "results" and r.get("extracted", false), "leaving through the gate is a successful extraction")
	t.check(r.get("deep", false) and r.get("deep_exit", false) and int(r.get("deep_bonus", 0)) == Balance.DEEP_EXIT_BONUS, "the result records the deep exit and its bonus")
	var expect: int = Game.cargo_value({1: 3, 3: 2}) + 260 + Game.finds_value([2]) + Balance.DEEP_EXIT_BONUS
	t.check(Progress.credits - credits_before == expect, "everything is banked exactly once (%d, expected %d)" % [Progress.credits - credits_before, expect])
	t.check(int(r.get("depth", 0)) >= int(Balance.MAP_H * Balance.METERS_PER_CELL), "the recorded depth spans both stages (%d m)" % r.get("depth", 0))
	await t._frames(5)
	# death in the deep stage loses everything, as in the mine
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 123
	Game.start_run()
	await t._frames(30)
	t.check(Game.run["stage"] == "mine" and int(Game.run["depth_offset"]) == 0 and not Game.run.has("hp"), "a new run starts in the mine with clean stage state")
	Game.run["cargo"] = {2: 5}
	Game.descend(80.0, Balance.MAP_H)
	guard = 0
	while (Game.current == null or Game.current.get("stage") != "deep" or Game.current.get("player") == null) and guard < 300:
		guard += 1
		await t.get_tree().physics_frame
	await t._frames(20)
	var credits2: int = Progress.credits
	Game.current.abandon()
	guard = 0
	while Game.current_name != "results" and guard < 300:
		guard += 1
		await t.get_tree().physics_frame
	r = Game.last_result
	t.check(not r.get("extracted", true) and r.get("deep", false) and int(r.get("deep_bonus", 0)) == 0 and Progress.credits == credits2, "abandoning in the deep stage banks nothing")
	Game.goto("title", true)
	await t._frames(5)
