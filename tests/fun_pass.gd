extends RefCounted
## Fun pass systems: loot economy (S1), orders (S2), pressure (S3) and later
## segments. suite=fun
static func _settle(t: Node) -> void:
	await t._frames(3)
	var guard := 0
	while Game._busy and guard < 600:
		guard += 1
		await t._frames(1)


static func run(t: Node) -> void:
	await economy(t)
	await orders(t)
	await pressure(t)
	await terrain_weapons(t)
	await modifiers(t)


static func economy(t: Node) -> void:
	t.section("loot economy")
	t.check(Balance.cargo_capacity(0) >= 60, "the starting rack is large (%d)" % Balance.cargo_capacity(0))
	# grades: grade 0 keys are the plain ids; deeper zones are worth more
	t.check(Balance.ore_key(2, 0) == 2 and Balance.ore_value(2) == int(Balance.ORE[2]["value"]), "surface cobalt keeps its old key and value")
	var deeper := true
	for z in [1, 2, 5]:
		if Balance.ore_value(Balance.ore_key(2, z)) <= Balance.ore_value(2):
			deeper = false
	t.check(deeper and Balance.ore_value(Balance.ore_key(2, 5)) > Balance.ore_value(Balance.ore_key(2, 2)), "the same ore is worth more deeper down")
	t.check(Balance.ore_base(Balance.ore_key(3, 4)) == 3 and Balance.ore_grade(Balance.ore_key(3, 4)) == 4, "cargo keys pack ore and grade")
	t.check(Balance.ore_label(Balance.ore_key(2, 5)).contains("x3.5") and Balance.ore_label(1) == "Copper", "labels show the grade")
	# live: a full rack swaps the cheapest unit out for better ore
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	Game.start_run()
	await t._frames(30)
	var mine: Node = Game.current
	var cap: int = mine.cargo_cap()
	Game.run["cargo"] = {1: cap - 1, 2: 1}
	var copper_value := Game.cargo_value(Game.run["cargo"])
	t.check(Game.can_take(5, cap) == false and Game.can_take(3, cap), "full rack refuses scrap but takes aetherite")
	var pl: Player = mine.player
	var p: Entities.Pickup = mine.spawn_pickup(pl.global_position + Vector2(0, -2), Balance.ore_key(3, 2))
	await t._frames(50)
	var cargo: Dictionary = Game.run["cargo"]
	t.check(Game.cargo_count() == cap and int(cargo.get(1, 0)) == cap - 2 and int(cargo.get(Balance.ore_key(3, 2), 0)) == 1, "better ore replaces one copper (%s)" % str(cargo))
	t.check(Game.cargo_value(cargo) > copper_value and int(Game.run.get("swaps", 0)) == 1, "the swap raises the rack's value")
	var loose := 0
	for e in mine.entity_root.get_children():
		if e is Entities.Pickup and e.ore == 1:
			loose += 1
	t.check(loose >= 1, "the swapped-out copper drops as a loose pickup")
	# worse ore is left on the ground when full
	var scrap: Entities.Pickup = mine.spawn_pickup(pl.global_position + Vector2(0, -2), 5)
	await t._frames(40)
	t.check(is_instance_valid(scrap) and Game.cargo_count() == cap and int(Game.run["cargo"].get(5, 0)) == 0, "cheaper ore stays on the ground when full")
	# drops from the mine are graded by zone
	var key: int = -1
	var dp: Entities.Pickup = mine.spawn_ore(pl.global_position, 2)
	key = dp.ore
	var c: Vector2i = mine.grid.world_to_cell(pl.global_position)
	t.check(key == Balance.ore_key(2, maxi(0, mine.grid.get_stratum(c.x, c.y))), "fresh ore takes the grade of its zone")
	Game.goto("title", true)
	await t._frames(5)


static func orders(t: Node) -> void:
	t.section("orders")
	var bad := 0
	var kinds_seen: Dictionary = {}
	for i in 10:
		var sd := 1000 + i * 7919
		var d: Dictionary = MineGenerator.new().generate(sd, Balance.CONTRACTS[i % 4])
		var g: TerrainGrid = d["grid"]
		var os: Array = Orders.generate(d, g, sd)
		var again: Array = Orders.generate(d, g, sd)
		if os.size() != Balance.ORDER_COUNT or str(os) != str(again):
			bad += 1
		var kinds: Dictionary = {}
		for o: Dictionary in os:
			kinds_seen[o["kind"]] = true
			if kinds.has(o["kind"]):
				bad += 1
			kinds[o["kind"]] = true
			if o["kind"] == "ore":
				var units := 0
				for k in g.ore.size():
					if int(g.ore[k]) == int(o["ore"]):
						units += int(Balance.ORE[int(o["ore"])]["drops"])
				if int(o["need"]) > units / 2:
					bad += 1
			if o["kind"] == "depth" and (int(o["need"]) <= Balance.STRATUM_ROWS[1] or int(o["need"]) >= g.h - 4):
				bad += 1
			if String(o["text"]).is_empty() or int(o["reward"]) <= 0:
				bad += 1
	t.check(bad == 0, "orders are deterministic, distinct, described and achievable on 10 maps (%d problems)" % bad)
	t.check(kinds_seen.size() >= 4, "several kinds of order appear (%s)" % str(kinds_seen.keys()))
	# live: progress, latching and payout
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	Game.start_run()
	await t._frames(30)
	var mine: Node = Game.current
	var os2: Array = Game.run.get("orders", [])
	t.check(os2.size() == Balance.ORDER_COUNT, "a dive starts with %d orders" % Balance.ORDER_COUNT)
	t.check(mine.hud.orders_panel != null, "the HUD shows the orders")
	Game.run["orders"] = [
		{"kind": "ore", "ore": 2, "need": 3, "reward": 50, "have": 0, "done": false, "text": "Bring back 3 cobalt"},
		{"kind": "depth", "need": 60, "reward": 40, "have": 0, "done": false, "text": "Reach 102 m"},
		{"kind": "terrain", "need": 1, "reward": 30, "have": 0, "done": false, "text": "Kill 1 foe with the terrain"},
	]
	Game.run["cargo"] = {Balance.ore_key(2, 1): 2, 2: 1}
	Game.run["max_depth"] = 61
	await t._frames(20)
	var o0: Dictionary = Game.run["orders"][0]
	var o1: Dictionary = Game.run["orders"][1]
	t.check(Orders.satisfied(o0, Game.run), "graded ore counts toward an ore order")
	t.check(bool(o1["done"]), "reaching the depth latches the order")
	Game.run["max_depth"] = 0
	t.check(Orders.satisfied(o1, Game.run), "a latched order stays done")
	# a crawler killed by rubble counts as a terrain kill
	var cr: Node = null
	for e in mine.enemies:
		if e is Crawler:
			cr = e
			break
	if cr != null:
		cr.crushed()
		cr.crushed()
		cr.crushed()
	await t._frames(20)
	t.check(int(Game.run.get("terrain_kills", 0)) >= 1 and bool(Game.run["orders"][2]["done"]), "a crawler crushed by rubble is a terrain kill")
	var before := Progress.credits
	var cargo_v := Game.cargo_value(Game.run["cargo"])
	Game.end_run(true)
	t.check(int(Game.last_result.get("orders_bonus", 0)) == 120 and Progress.credits == before + cargo_v + 120, "met orders pay on extraction (%d)" % int(Game.last_result.get("orders_bonus", 0)))
	await _settle(t)
	Game.goto("title", true)
	await _settle(t)


static func pressure(t: Node) -> void:
	t.section("pressure")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	Game.start_run()
	await t._frames(30)
	var guard := 0
	while (Game.current == null or Game.current.get("pressure") == null) and guard < 300:
		guard += 1
		await t._frames(1)
	var mine: Node = Game.current
	var pr: Pressure = mine.pressure
	t.check(pr != null and pr.tier == 0 and pr.value < 1.0, "a dive starts calm")
	var v0 := pr.value
	mine.noise(mine.player.global_position, 16.0)
	t.check(pr.value > v0, "a blast raises the pressure")
	# crossing a tier announces itself and arms events
	pr.value = 31.0
	await t._frames(3)
	t.check(pr.tier == 1 and pr.event_t <= Balance.PRESSURE_FIRST_EVENT, "crossing 30 enters tier 1 and arms an event")
	# a tremor loosens a ceiling near the player, never straight overhead below tier 3
	var g: TerrainGrid = mine.grid
	var pl: Player = mine.player
	pl.invuln = 1e9
	var pc: Vector2i = g.world_to_cell(pl.global_position)
	var made: Array[Vector2i] = []
	for dx in range(3, 8):
		for dy in range(-4, 0):
			var c := Vector2i(pc.x + dx, pc.y + dy)
			if g.has_flag(c.x, c.y, Cell.F_PROTECTED):
				continue
			g.set_mat(c.x, c.y, Cell.SOFT if dy == -4 else Cell.AIR)
			if dy == -4:
				made.append(c)
	var got := ""
	for k in 6:
		got = pr.trigger_event("tremor")
		if got != "":
			break
	var loose := 0
	var overhead := 0
	var queued: Array = mine.collapse.pending.keys()
	for c: Vector2i in queued:
		if g.get_mat(c.x, c.y) == Cell.LOOSE:
			loose += 1
			if absi(c.x - pc.x) <= Balance.PRESSURE_TREMOR_SAFE:
				overhead += 1
	t.check(got == "tremor" and loose >= 1 and overhead == 0, "a tremor loosens a ceiling nearby, not overhead (%d loose)" % loose)
	await t._frames(int(60 * (Balance.PRESSURE_TREMOR_WARN * 1.4 + 1.0)))
	var fell := 0
	for c: Vector2i in queued:
		if not g.is_solid(c.x, c.y):
			fell += 1
	t.check(fell >= 1, "the loosened ceiling comes down after its warning (%d cells)" % fell)
	var vents_before: int = mine.gas.vents.size() + mine.gas.clouds.size()
	t.check(pr.trigger_event("gas") == "gas" and mine.gas.vents.size() + mine.gas.clouds.size() > vents_before, "gas can seep out of the rock near you")
	var enemies_before: int = mine.enemies.size()
	var sw := pr.trigger_event("swarm")
	var far := true
	for e in pr.spawned:
		if is_instance_valid(e) and e.global_position.distance_to(pl.global_position) < 13 * Balance.CELL:
			far = false
	t.check(sw == "swarm" and mine.enemies.size() > enemies_before and far, "a swarm arrives from off screen (%d new)" % (mine.enemies.size() - enemies_before))
	var capped := true
	for k in 8:
		pr.trigger_event("swarm")
	var alive := 0
	for e in pr.spawned:
		if is_instance_valid(e):
			alive += 1
	t.check(alive <= Balance.PRESSURE_SWARM_MAX, "swarms are capped (%d alive)" % alive)
	# retreating to shallower ground eases it
	pr._deepest_rank = 3
	pr.value = 50.0
	await t._frames(60)
	t.check(pr.value < 50.0, "retreating above your deepest zone lowers the pressure (%.1f)" % pr.value)
	t.check(is_equal_approx(float(Game.run["pressure"]), pr.value), "the run remembers the pressure")
	Game.goto("title", true)
	await t._frames(5)


static func terrain_weapons(t: Node) -> void:
	t.section("terrain weapons")
	await _settle(t)
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	Game.start_run()
	await _settle(t)
	await t._frames(20)
	var mine: Node = Game.current
	var pl: Player = mine.player
	pl.invuln = 1e9
	t.check(int(Game.run.get("lures", 0)) == Balance.LURES_PER_RUN, "a dive starts with %d lures" % Balance.LURES_PER_RUN)
	# a lure pulls a crawler away, even from a chase
	var cr: Crawler = null
	for e in mine.enemies:
		if e is Crawler:
			cr = e
			break
	t.check(cr != null, "the test map has a crawler")
	if cr == null:
		return
	var lu: Node2D = mine.spawn_lure(cr.global_position + Vector2(48, -20), Vector2.ZERO)
	cr.state = Crawler.S.CHASE
	await t._frames(80)
	t.check(cr.state == Crawler.S.INVESTIGATE or cr.target_cell == mine.grid.world_to_cell(lu.global_position) or cr.global_position.distance_to(lu.global_position) < 40.0, "a lure distracts a crawler mid-chase")
	var p_before := float(Game.run.get("pressure", 0.0))
	await t._frames(60)
	t.check(float(Game.run.get("pressure", 0.0)) - p_before < 1.0, "lure pings do not wake the mine")
	# USE with nothing nearby throws a lure
	var n0 := int(Game.run["lures"])
	pl.global_position = cr.global_position + Vector2(0, -2)
	if mine.nearest_interactable(pl).is_empty():
		mine.player_interact(pl)
		t.check(int(Game.run["lures"]) == n0 - 1, "USE with nothing nearby throws a lure")
	Game.run["lures"] = 0
	mine.player_interact(pl)
	t.check(int(Game.run["lures"]) == 0, "no lures, no throw")
	# drowning counts as a terrain kill
	var kills0 := int(Game.run.get("terrain_kills", 0))
	var cc: Vector2i = cr.cell
	mine.grid.set_water(cc.x, cc.y, Balance.WATER_MAX)
	cr.hp = 1.0
	await t._frames(30)
	t.check(int(Game.run.get("terrain_kills", 0)) == kills0 + 1, "a crawler that drowns is a terrain kill")
	await _settle(t)
	Game.goto("title", true)
	await _settle(t)


static func modifiers(t: Node) -> void:
	t.section("dive modifiers")
	Game.modifiers = []
	t.check(Game.toggle_modifier("flooded") and Game.toggle_modifier("swarm") and not Game.toggle_modifier("gassy") and Game.modifiers.size() == 2, "up to two modifiers can be chosen")
	t.check(Game.toggle_modifier("swarm") and Game.modifiers == ["flooded"], "a modifier can be switched off again")
	var mc := Game.modded_contract(Balance.CONTRACTS[1], ["swarm", "deep_veins"])
	t.check(is_equal_approx(float(mc["crawlers"]), 1.5 * 1.8) and is_equal_approx(float(mc["ore"]), 1.4 * 1.4) and is_equal_approx(float(mc["mod_bonus"]), 0.3), "modifiers stack onto the contract")
	# every modifier still makes fair maps, and FLOODED really floods
	var bad := 0
	var wet_more := 0
	for m: Dictionary in Balance.MODIFIERS:
		for i in 3:
			var sd := 2000 + i * 7919
			var base: Dictionary = Balance.CONTRACTS[i % 4]
			var d: Dictionary = MineGenerator.new().generate(sd, Game.modded_contract(base, [m["id"]]))
			if not bool(d.get("valid", false)) or int(d.get("repairs", 0)) != 0:
				bad += 1
			if m["id"] == "flooded":
				var plain: Dictionary = MineGenerator.new().generate(sd, base)
				var w0 := 0
				var w1 := 0
				for f: Dictionary in plain.get("water_features", []):
					w0 += int(f.get("volume", 0))
				for f: Dictionary in d.get("water_features", []):
					w1 += int(f.get("volume", 0))
				if w1 > w0:
					wet_more += 1
	t.check(bad == 0, "every modifier generates valid maps with no repairs (%d bad of %d)" % [bad, Balance.MODIFIERS.size() * 3])
	t.check(wet_more == 3, "FLOODED maps hold more water (%d of 3)" % wet_more)
	# live: modifiers ride along in the run and pay on ore
	Game.modifiers = ["blackout", "brittle"]
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(20)
	var rc: Dictionary = Game.run["contract"]
	t.check(is_equal_approx(float(rc.get("pressure", 1.0)), 1.6) and float(rc.get("dark", 1.0)) < 1.0 and Game.run["modifiers"] == ["blackout", "brittle"], "the run carries its modifiers")
	Game.run["cargo"] = {2: 10}
	var before := Progress.credits
	Game.end_run(true)
	var pay := int(round(150 * 0.55))
	t.check(int(Game.last_result.get("mod_pay", 0)) == pay and Progress.credits - before == 150 + pay + int(Game.last_result.get("orders_bonus", 0)), "modifiers raise ore pay (+%d CR)" % int(Game.last_result.get("mod_pay", 0)))
	Game.modifiers = []
	await _settle(t)
	Game.goto("title", true)
	await _settle(t)
