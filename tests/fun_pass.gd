extends RefCounted
## Fun pass systems: loot economy (S1), orders (S2), pressure (S3) and later
## segments. suite=fun
static func _settle_scene(t: Node) -> void:
	await _settle(t)


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
	await gadgets(t)
	await relics(t)
	await relics_batch_a(t)
	await relics_batch_b(t)
	await relics_batch_c(t)
	await feet(t)
	await charges(t)
	await sand(t)
	await sand_look(t)
	await zones(t)
	await kit(t)


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


static func gadgets(t: Node) -> void:
	t.section("gadgets")
	# cryo crusts lava with the normal accounting
	var g := TerrainGrid.new(10, 8)
	for y in 8:
		for x in 10:
			g.put(x, y, Cell.BEDROCK if (x == 0 or y == 0 or x == 9 or y == 7) else Cell.AIR)
			g.stratum[g.idx(x, y)] = Balance.Z_FIRST
	for x in range(1, 9):
		g.lava[g.idx(x, 6)] = Balance.LAVA_MAX
	var ls := LavaSim.new(g, null, null)
	var start := 8 * Balance.LAVA_MAX
	t.check(ls.quench(Vector2i(4, 6)) and g.get_mat(4, 6) == Cell.HARD and g.get_lava(4, 6) == 0, "cryo turns a lava cell into rock")
	var left := 0
	for x in range(1, 9):
		left += g.get_lava(x, 6)
	t.check(left + ls.lava_frozen + ls.lava_lost == start and not ls.quench(Vector2i(4, 2)), "quenching keeps the lava accounting and ignores dry cells")
	# live
	Game.loadout = {"active": "sonar", "passive": "magnet"}
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(20)
	var mine: Node = Game.current
	var pl: Player = mine.player
	pl.invuln = 1e9
	t.check(mine.active_gadget() == "sonar" and mine.has_passive("magnet"), "the run carries the packed loadout")
	var ping: Node2D = null
	mine.use_gadget(pl)
	for e in mine.entity_root.get_children():
		if e is Hazards.SonarPing:
			ping = e
	var gc: Vector2i = mine.grid.world_to_cell(pl.global_position)
	t.check(ping != null and mine.grid.has_flag(gc.x + 20, gc.y, Cell.F_EXPLORED) and float(Game.run["gadget_cd"]) > 0.0, "sonar reveals the map nearby and starts its cooldown")
	var cd := float(Game.run["gadget_cd"])
	mine.use_gadget(pl)
	var pings := 0
	for e in mine.entity_root.get_children():
		if e is Hazards.SonarPing:
			pings += 1
	t.check(pings == 1 and float(Game.run["gadget_cd"]) <= cd, "a gadget cannot be used while recharging")
	# the magnet passive pulls ore from much further
	Game.run["cargo"] = {}
	var far: Entities.Pickup = mine.spawn_pickup(pl.global_position + Vector2(80, -4), 2)
	far.vel = Vector2.ZERO
	await t._frames(70)
	t.check(Game.cargo_count() == 1, "MAGNET collects ore from 80 px away")
	Game.run["loadout"]["passive"] = "plating"
	var far2: Entities.Pickup = mine.spawn_pickup(pl.global_position + Vector2(80, -4), 2)
	far2.vel = Vector2.ZERO
	await t._frames(70)
	t.check(Game.cargo_count() == 1 and is_instance_valid(far2), "without MAGNET that ore stays put")
	# a cryo burst freezes foes and vents heat
	pl.heat = pl.heat_cap * 0.9
	var cr: Crawler = null
	for e in mine.enemies:
		if e is Crawler:
			cr = e
			break
	if cr != null:
		mine.cryo_burst(cr.global_position)
		t.check(cr.state == Crawler.S.STUNNED, "a cryo burst freezes a crawler")
	mine.cryo_burst(pl.global_position)
	t.check(pl.heat == 0.0, "a cryo burst at your feet vents your heat")
	Game.loadout = Balance.GADGET_DEFAULT.duplicate()
	await _settle(t)
	Game.goto("title", true)
	await _settle(t)


static func relics(t: Node) -> void:
	t.section("run relics")
	var bad := 0
	var pairs := 0
	for i in 8:
		var sd := 3000 + i * 7919
		var d: Dictionary = MineGenerator.new().generate(sd, Balance.CONTRACTS[i % 4])
		var again: Dictionary = MineGenerator.new().generate(sd, Balance.CONTRACTS[i % 4])
		var rs: Array = d.get("run_relics", [])
		var g: TerrainGrid = d["grid"]
		if rs.size() < Balance.RUN_RELICS_MAIN or rs.size() > Balance.RUN_RELICS_MAIN + 1 or str(rs) != str(again.get("run_relics", [])):
			bad += 1
		var grouped: Array = []
		for r: Dictionary in rs:
			if int(r.get("group", 0)) > 0:
				grouped.append(r["cell"])
		if grouped.size() == 2:
			pairs += 1
			if absi((grouped[0] as Vector2i).x - (grouped[1] as Vector2i).x) > 4 or (grouped[0] as Vector2i).y != (grouped[1] as Vector2i).y:
				bad += 1
		elif grouped.size() != 0:
			bad += 1
		var ids: Dictionary = {}
		for r: Dictionary in rs:
			var c: Vector2i = r["cell"]
			ids[r["id"]] = true
			if g.is_solid(c.x, c.y) or not g.is_solid(c.x, c.y + 1) or g.get_water(c.x, c.y) > 0:
				bad += 1
			for f: Dictionary in d["finds"]:
				if Vector2(c - (f["cell"] as Vector2i)).length() < Balance.RUN_RELIC_SEP - 4:
					bad += 1
		if ids.size() != rs.size():
			bad += 1
	t.check(bad == 0, "every map hides %d+ distinct, reachable, dry run relics away from keepsakes (%d problems)" % [Balance.RUN_RELICS_MAIN, bad])
	t.check(pairs >= 4, "most maps offer a choice pair of relics (%d of 8)" % pairs)
	var deep_ok := 0
	for i in 4:
		var dd: Dictionary = FirstCivGenerator.new().generate(FirstCivGenerator.deep_seed(4000 + i * 7919))
		if (dd.get("run_relics", []) as Array).size() == Balance.RUN_RELICS_DEEP:
			deep_ok += 1
	t.check(deep_ok == 4, "The First Civilization hides a run relic too (%d of 4)" % deep_ok)
	# live effects
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(20)
	var mine: Node = Game.current
	var pl: Player = mine.player
	t.check(mine.run_relics.size() >= Balance.RUN_RELICS_MAIN, "the relics are in the mine")
	# a choice pair: take one, the other crumbles
	var pa: RunRelic = null
	var pb: RunRelic = null
	for r in mine.run_relics:
		if r.group > 0:
			if pa == null:
				pa = r
			else:
				pb = r
	if pa != null and pb != null:
		pl.global_position = pa.global_position
		pa.take()
		await t._frames(2)
		t.check(not is_instance_valid(pb) or pb.used, "taking one relic of a pair crumbles the other")
		Game.run["relics"] = []
	var hp0 := pl.max_hp
	var spine := -1
	for k in Balance.RUN_RELICS.size():
		if Balance.RUN_RELICS[k]["id"] == "spine":
			spine = k
	var rr := RunRelic.new()
	rr.mine = mine
	rr.id = spine
	rr.position = pl.global_position
	mine.entity_root.add_child(rr)
	mine.run_relics.append(rr)
	pl.velocity = Vector2.ZERO
	t.check(mine.nearest_interactable(pl).get("kind", "") == "run_relic", "a relic can be taken with USE")
	mine.player_interact(pl)
	t.check(Game.has_relic("spine") and is_equal_approx(pl.max_hp, hp0 + Balance.SPINE_HULL) and is_equal_approx(pl.hp, pl.max_hp), "Iron Spine adds hull and repairs")
	# a second copy does nothing: the hull bonus applies once
	var rr2 := RunRelic.new()
	rr2.mine = mine
	rr2.id = spine
	rr2.position = pl.global_position
	mine.entity_root.add_child(rr2)
	mine.run_relics.append(rr2)
	pl.hp = pl.max_hp - 30.0
	rr2.take()
	t.check(is_equal_approx(pl.max_hp, hp0 + Balance.SPINE_HULL) and is_equal_approx(pl.hp, pl.max_hp - 30.0), "a second Iron Spine does not stack")
	t.check((Game.run["relics"] as Array).count("spine") == 1, "a relic is only recorded once")
	# the run never rolls a relic it already holds (the deep stage cannot see the run)
	var held: Array = Game.run["relics"]
	held.clear()
	var n_all: int = Balance.RUN_RELICS.size()
	t.check(Game.unowned_relic_id(2) == 2, "a free relic is kept as rolled")
	var all_free := true
	for k in n_all:
		held.clear()
		held.append(Balance.RUN_RELICS[k]["id"])
		var got := Game.unowned_relic_id(k)
		if got == k or got < 0 or held.has(Balance.RUN_RELICS[got]["id"]):
			all_free = false
	t.check(all_free, "an owned relic is swapped for one the run does not hold")
	held.clear()
	for info: Dictionary in Balance.RUN_RELICS:
		held.append(info["id"])
	t.check(Game.unowned_relic_id(0) == -1, "nothing is offered once the run holds every relic")
	held.clear()
	# Prospector's Charm: one extra unit per seam
	Game.run["relics"].append("charm")
	var gc: Vector2i = mine.grid.world_to_cell(pl.global_position)
	var oc := Vector2i(gc.x + 2, gc.y)
	mine.grid.set_mat(oc.x, oc.y, Cell.SOFT)
	mine.grid.ore[mine.grid.idx(oc.x, oc.y)] = Cell.ORE_COBALT
	var before := 0
	for e in mine.entity_root.get_children():
		if e is Entities.Pickup:
			before += 1
	mine.damage_cell(oc, 999.0, 3, true, "test")
	var after := 0
	for e in mine.entity_root.get_children():
		if e is Entities.Pickup:
			after += 1
	t.check(after - before == int(Balance.ORE[Cell.ORE_COBALT]["drops"]) + 1, "Prospector's Charm drops an extra unit (%d)" % (after - before))
	Game.run["relics"].append("calm")
	t.check(is_equal_approx(mine.pressure._mult(), Balance.CALM_MULT), "Calm Stone slows the pressure")
	Game.run["relics"].append("coil")
	Game.run["gadget_cd"] = 10.0
	await t._frames(30)
	t.check(float(Game.run["gadget_cd"]) < 10.0 - 0.8, "Quick Coil recharges gadgets twice as fast (%.2f left)" % float(Game.run["gadget_cd"]))
	await _settle(t)
	Game.goto("title", true)
	await _settle(t)


## 0.10.0 relics: Echo Drill, Overdrive, Hard Hat, Blood Bargain, Glutton's
## Sack and Spare Parts.
static func relics_batch_a(t: Node) -> void:
	t.section("new relics: echo, overdrive, hard hat, bargain, glutton, spares")
	for id in ["echo", "overdrive", "hardhat", "bargain", "glutton", "spares"]:
		var found := false
		for info: Dictionary in Balance.RUN_RELICS:
			if info["id"] == id:
				found = true
		t.check(found, "relic %s is in the pool" % id)
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 11
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(10)
	var mine: Node = Game.current
	var pl: Player = mine.player
	var g: TerrainGrid = mine.grid
	var held: Array = Game.run["relics"]
	held.clear()
	# Echo Drill: the fifth block broken also breaks the one behind it
	var gc: Vector2i = g.world_to_cell(pl.global_position)
	var row := gc.y - 6
	for x in range(gc.x - 8, gc.x + 8):
		g.set_mat(x, row, Cell.SOFT)
	pl.drill_dir = Vector2i(1, 0)
	held.append("echo")
	mine._echo_n = 0
	for k in 5:
		mine.drill_cell(Vector2i(gc.x - 8 + k, row), 999.0, 0, pl)
	t.check(not g.is_solid(gc.x - 4, row) and not g.is_solid(gc.x - 3, row) and g.is_solid(gc.x - 2, row), "Echo Drill: the fifth block also breaks the one behind it, and no further")
	held.clear()
	mine._echo_n = 0
	for k in 5:
		mine.drill_cell(Vector2i(gc.x + 1 + k, row), 999.0, 0, pl)
	t.check(g.is_solid(gc.x + 6, row), "without Echo Drill nothing extra breaks")
	# Overdrive: an overheated drill keeps cutting
	pl.input_override = {"drill": true}
	pl.heat = pl.heat_cap
	pl.overheated = true
	await t._frames(3)
	t.check(not pl.drilling, "an overheated drill stops without Overdrive")
	held.append("overdrive")
	pl.heat = pl.heat_cap
	pl.overheated = true
	await t._frames(3)
	t.check(pl.drilling and pl.overheated, "Overdrive: the overheated drill keeps working")
	pl.input_override = {}
	held.clear()
	await t._frames(2)
	# Hard Hat: falling rock does no damage
	t.check(is_equal_approx(mine.rock_damage_mult(), 1.0) or is_equal_approx(mine.rock_damage_mult(), Balance.PLATING_MULT), "rock hurts without Hard Hat")
	held.append("hardhat")
	t.check(is_zero_approx(mine.rock_damage_mult()), "Hard Hat: rock damage scale is zero")
	pl.invuln = 0.0
	var hp0 := pl.hp
	mine.collapse._hit_entities(Rect2(pl.global_position - Vector2(7, 8), Vector2(14, 16)))
	t.check(is_equal_approx(pl.hp, hp0), "Hard Hat: falling rubble does not hurt")
	held.clear()
	# Blood Bargain: pay scales with missing hull
	Game.run["hull_frac"] = 0.5
	t.check(Game.bargain_pay_for(200) == 0, "no bargain pay without the relic")
	held.append("bargain")
	t.check(Game.bargain_pay_for(200) == 100, "Blood Bargain: half hull missing pays +50%")
	Game.run["hull_frac"] = 1.0
	t.check(Game.bargain_pay_for(200) == 0, "Blood Bargain: full hull pays nothing extra")
	Game.run["hull_frac"] = 0.0
	t.check(Game.bargain_pay_for(200) == int(200 * Balance.BARGAIN_MAX), "Blood Bargain caps at double")
	Game.run.erase("hull_frac")
	held.clear()
	# Glutton's Sack: a bigger rack that rattles while you move with ore
	var cap0: int = mine.cargo_cap()
	held.append("glutton")
	t.check(mine.cargo_cap() == cap0 + Balance.GLUTTON_SLOTS, "Glutton's Sack adds rack slots")
	Game.run["cargo"] = {}
	mine._rattle_t = 0.0
	pl.velocity = Vector2(120, 0)
	mine._glutton_rattle(0.1)
	t.check(is_zero_approx(mine._rattle_t), "an empty rack does not rattle")
	Game.run["cargo"] = {1: 20}
	pl.velocity = Vector2(120, 0)
	mine._glutton_rattle(0.1)
	t.check(is_equal_approx(mine._rattle_t, Balance.GLUTTON_RATTLE), "ore aboard rattles while you move")
	Game.run["cargo"] = {}
	held.clear()
	# Spare Parts: a charge (or a lure) on first arrival in each zone
	Game.run["zones_seen"] = [0]
	Game.run["charges"] = 0
	mine._zone_reached(1)
	t.check(int(Game.run["charges"]) == 0, "no spare parts without the relic")
	held.append("spares")
	mine._zone_reached(2)
	t.check(int(Game.run["charges"]) == 1, "Spare Parts: a charge on reaching a new zone")
	mine._zone_reached(2)
	mine._zone_reached(1)
	t.check(int(Game.run["charges"]) == 1, "Spare Parts: only once per zone")
	Game.run["charges"] = Progress.charges_max()
	var lures0 := int(Game.run.get("lures", 0))
	mine._zone_reached(3)
	t.check(int(Game.run["charges"]) == Progress.charges_max() and int(Game.run["lures"]) == mini(lures0 + 1, Balance.SPARE_LURES_MAX), "Spare Parts: a lure when the charge rack is full")
	held.clear()


## 0.11.0 relics: Fault Line, Pressure Valve, Dust Cloak and Slag Heart.
static func relics_batch_b(t: Node) -> void:
	t.section("new relics: fault line, pressure valve, dust cloak, slag heart")
	var slag := -1
	for k in Balance.RUN_RELICS.size():
		if Balance.RUN_RELICS[k]["id"] == "slag":
			slag = k
	for id in ["faultline", "valve", "dustcloak", "slag"]:
		var found := false
		for info: Dictionary in Balance.RUN_RELICS:
			found = found or info["id"] == id
		t.check(found, "relic %s is in the pool" % id)
	# Slag Heart is only ever offered in The First Civilization
	Game.run["relics"] = []
	t.check(slag >= 0 and Game.unowned_relic_id(slag, true) == slag, "Slag Heart can be offered in the deep stage")
	var main_ok := true
	for k in Balance.RUN_RELICS.size():
		if Game.unowned_relic_id(k, false) == slag:
			main_ok = false
	t.check(main_ok, "Slag Heart is never offered in the main mine")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 13
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(10)
	var mine: Node = Game.current
	var pl: Player = mine.player
	var g: TerrainGrid = mine.grid
	var held: Array = Game.run["relics"]
	held.clear()
	var no_slag := true
	for spec: Dictionary in mine.data.get("run_relics", []):
		if int(spec["id"]) == slag:
			no_slag = false
	t.check(no_slag, "the main mine's generated relics never include Slag Heart")
	# Fault Line: the ceiling over a blast cracks and is set to fall
	var gc: Vector2i = g.world_to_cell(pl.global_position)
	var bc := Vector2i(gc.x + 12, gc.y)
	for x in range(bc.x - 2, bc.x + 3):
		for y in range(bc.y - 2, bc.y + 1):
			g.set_mat(x, y, Cell.AIR)
		g.set_mat(x, bc.y - 3, Cell.SOFT)
		g.set_mat(x, bc.y - 4, Cell.SOFT)
		g.set_flag(x, bc.y - 3, Cell.F_PROTECTED, false)
		g.set_flag(x, bc.y - 4, Cell.F_PROTECTED, false)
	var fell: int = mine.fault_line(bc, 1)
	var all_loose := true
	for x in range(bc.x - 2, bc.x + 3):
		for y in [bc.y - 3, bc.y - 4]:
			if g.get_mat(x, y) != Cell.LOOSE or not mine.collapse.pending.has(Vector2i(x, y)):
				all_loose = false
	t.check(fell == 10 and all_loose, "Fault Line: five columns of ceiling, two rows deep, crack and are set to fall (%d)" % fell)
	for x in range(bc.x - 2, bc.x + 3):
		for y in [bc.y - 3, bc.y - 4]:
			mine.collapse.pending.erase(Vector2i(x, y))
			g.set_mat(x, y, Cell.SOFT)
	# Pressure Valve: vents at high pressure and stuns foes nearby
	var pr: Node = mine.pressure
	pr.value = 85.0
	await t._frames(3)
	t.check(pr.value >= Balance.VALVE_AT, "pressure stays high without the valve")
	held.append("valve")
	await t._frames(3)
	t.check(pr.value <= 85.0 - Balance.VALVE_DROP + 1.0 and pr._valve_cd > 0.0, "Pressure Valve: the meter drops by %d" % int(Balance.VALVE_DROP))
	pr.value = 85.0
	await t._frames(3)
	t.check(pr.value >= Balance.VALVE_AT, "Pressure Valve waits for its cooldown")
	var spot := Vector2i(-1, -1)
	for r in range(5, 9):
		for dx in [r, -r]:
			for dy in range(-2, 3):
				var c := gc + Vector2i(dx, dy)
				if spot.x < 0 and not g.is_solid(c.x, c.y) and g.is_solid(c.x, c.y + 1) and g.get_water(c.x, c.y) == 0:
					spot = c
	t.check(spot.x >= 0, "found a floor cell near the digger for a test crawler")
	if spot.x >= 0:
		var cr: Crawler = mine.spawn_crawler(spot)
		await t._frames(2)
		pr._valve_cd = 0.0
		var stunned: int = pr.vent()
		t.check(stunned >= 1 and cr.state == Crawler.S.STUNNED, "Pressure Valve: a crawler nearby is stunned")
		# Dust Cloak: foes beyond 3 cells lose sight of you
		held.clear()
		held.append("dustcloak")
		mine.cloak_t = 0.0
		mine.raise_dust()
		t.check(mine.cloaked(), "Dust Cloak: raised dust hides you")
		cr.stun_t = 0.0
		cr.state = Crawler.S.CHASE
		cr.forget_t = Balance.CRAWLER_FORGET
		t.check(not cr._sees_player(), "Dust Cloak: a crawler %d cells away cannot see you" % absi(spot.x - gc.x))
		for k in 60:
			mine.cloak_t = 10.0
			await t._frames(1)
			if cr.state != Crawler.S.CHASE:
				break
		t.check(cr.state != Crawler.S.CHASE, "Dust Cloak: a chasing crawler gives up")
		mine.cloak_t = 0.0
		held.clear()
		mine.raise_dust()
		t.check(not mine.cloaked(), "no dust cloak without the relic")
		if is_instance_valid(cr):
			mine.enemies.erase(cr)
			cr.queue_free()
	held.clear()
	# Slag Heart: lava does not burn, it crusts around you (lava set up by hand:
	# the main mine has no lava simulation of its own)
	mine.steam = SteamField.new(g)
	mine.lava = LavaSim.new(g, mine.water, mine.steam)
	mine.lava.occupied = mine._cell_occupied
	pl.velocity = Vector2.ZERO
	await t._frames(2)
	var feet: Vector2i = g.world_to_cell(pl.global_position + Vector2(0, Player.HALF.y - 1.0))
	var pool: Array[Vector2i] = []
	for dx in range(-2, 3):
		var c := Vector2i(feet.x + dx, feet.y)
		if not g.is_solid(c.x, c.y):
			pool.append(c)
	for c in pool:
		g.set_lava(c.x, c.y, Balance.LAVA_MAX)
	pl.invuln = 0.0
	mine._burn_t = 0.0
	var hp1 := pl.hp
	held.append("slag")
	await t._frames(4)
	var crusted := 0
	for c in pool:
		if g.get_mat(c.x, c.y) == Cell.HARD:
			crusted += 1
	t.check(is_equal_approx(pl.hp, hp1), "Slag Heart: standing in lava does not burn")
	t.check(crusted >= 1, "Slag Heart: lava next to you crusts into rock (%d of %d cells)" % [crusted, pool.size()])
	held.clear()
	for c in pool:
		g.set_lava(c.x, c.y, Balance.LAVA_MAX if not g.is_solid(c.x, c.y) else 0)
	pl.invuln = 0.0
	mine._burn_t = 0.0
	var hp2 := pl.hp
	await t._frames(4)
	t.check(pl.hp < hp2, "without Slag Heart the lava burns")
	for y in range(feet.y - 3, feet.y + 4):
		for x in range(feet.x - 4, feet.x + 5):
			g.set_lava(x, y, 0)
	mine.lava = null
	mine.steam = null
	pl.hp = pl.max_hp


## 0.12.0 relics: Dowsing Rod, Greedy Lamp and Cartographer's Eye.
static func relics_batch_c(t: Node) -> void:
	t.section("new relics: dowsing rod, greedy lamp, cartographer's eye")
	for id in ["dowsing", "greedy", "cartographer"]:
		var found := false
		for info: Dictionary in Balance.RUN_RELICS:
			found = found or info["id"] == id
		t.check(found, "relic %s is in the pool" % id)
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 17
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(10)
	var mine: Node = Game.current
	var pl: Player = mine.player
	var g: TerrainGrid = mine.grid
	var held: Array = Game.run["relics"]
	held.clear()
	var gc: Vector2i = g.world_to_cell(pl.global_position)
	# Dowsing Rod: unexplored water near you is sensed on the map
	var wc := Vector2i(gc.x + 14, gc.y + 3)
	g.set_mat(wc.x, wc.y, Cell.AIR)
	g.set_water(wc.x, wc.y, Balance.WATER_MAX)
	g.set_flag(wc.x, wc.y, Cell.F_EXPLORED, false)
	var mm: Minimap = mine.hud.minimap
	mine._dowse_t = 0.0
	mine._dowse(0.1)
	t.check(not mine.dowsed.has(wc), "nothing is sensed without the Dowsing Rod")
	held.append("dowsing")
	mine._dowse_t = 0.0
	mine._dowse(0.1)
	t.check(mine.dowsed.has(wc) and mm.sense_img.get_pixel(wc.x, wc.y).a > 0.1, "Dowsing Rod: unexplored water 14 cells away shows on the map")
	var far := Vector2i(gc.x + Balance.DOWSE_RADIUS + 3, gc.y)
	if g.in_bounds(far.x, far.y):
		g.set_mat(far.x, far.y, Cell.AIR)
		g.set_water(far.x, far.y, Balance.WATER_MAX)
		g.set_flag(far.x, far.y, Cell.F_EXPLORED, false)
		mine._dowse_t = 0.0
		mine._dowse(0.1)
		t.check(not mine.dowsed.has(far), "Dowsing Rod: water beyond %d cells is not sensed" % Balance.DOWSE_RADIUS)
		g.set_water(far.x, far.y, 0)
	g.set_water(wc.x, wc.y, 0)
	mine._dowse_t = 0.0
	mine._dowse(0.1)
	t.check(not mine.dowsed.has(wc) and mm.sense_img.get_pixel(wc.x, wc.y).a < 0.01, "Dowsing Rod: the mark clears when the water is gone")
	held.clear()
	# Cartographer's Eye: a zone you reach is fully drawn on the map
	var zone_cells := 0
	var zone_seen := 0
	for y in g.h:
		for x in g.w:
			if g.get_stratum(x, y) == Balance.Z_CRYSTAL:
				zone_cells += 1
	Game.run["zones_seen"] = [0]
	mine._zone_reached(Balance.Z_CRYSTAL)
	for y in g.h:
		for x in g.w:
			if g.get_stratum(x, y) == Balance.Z_CRYSTAL and g.has_flag(x, y, Cell.F_EXPLORED):
				zone_seen += 1
	t.check(zone_seen < zone_cells, "a zone is not revealed without the relic")
	held.append("cartographer")
	mine._zone_reached(Balance.Z_SPORE)
	var spore_left := 0
	for y in g.h:
		for x in g.w:
			if g.get_stratum(x, y) == Balance.Z_SPORE and not g.has_flag(x, y, Cell.F_EXPLORED):
				spore_left += 1
	t.check(spore_left == 0, "Cartographer's Eye: reaching a zone reveals all of it")
	# taking the relic reveals the zones you already visited
	held.clear()
	Game.run["zones_seen"] = [0, Balance.Z_SPORE, Balance.Z_AQUEDUCT]
	held.append("cartographer")
	mine.on_relic_taken("cartographer")
	var aq_left := 0
	for y in g.h:
		for x in g.w:
			if g.get_stratum(x, y) == Balance.Z_AQUEDUCT and not g.has_flag(x, y, Cell.F_EXPLORED):
				aq_left += 1
	t.check(aq_left == 0, "Cartographer's Eye: taking it reveals zones you already visited")
	held.clear()
	# Greedy Lamp: arrows to ore you can't see, a smaller lamp, a faster mine
	var cp: OreCompass = mine.compass
	for k in 120:
		await t._frames(1)
		if not cp.visible:
			break
	t.check(not cp.visible, "no compass without the Greedy Lamp")
	var lamp0: float = pl.lamp.texture_scale
	var mult0: float = mine.pressure._mult()
	held.append("greedy")
	for k in 120:
		await t._frames(1)
		if cp.visible:
			break
	t.check(is_equal_approx(pl.lamp.texture_scale, lamp0 * Balance.GREEDY_LIGHT), "Greedy Lamp: the lamp shrinks")
	t.check(is_equal_approx(mine.pressure._mult(), mult0 * Balance.GREEDY_PRESSURE), "Greedy Lamp: the mine wakes faster")
	var vr: Rect2 = cp.view_rect()
	var oc := Vector2i(-1, -1)
	for dx in range(1, Balance.GREEDY_RADIUS):
		var c := Vector2i(gc.x + dx, gc.y)
		if g.in_bounds(c.x, c.y) and not vr.has_point(g.cell_center(c)):
			oc = c
			break
	t.check(oc.x >= 0, "there is room for an ore cell just off screen")
	if oc.x >= 0:
		g.set_mat(oc.x, oc.y, Cell.HARD)
		g.ore[g.idx(oc.x, oc.y)] = Cell.ORE_AETHER
		cp.scan()
		var toward := (g.cell_center(oc) - pl.global_position).normalized()
		var points := false
		var all_off := true
		for tg: Dictionary in cp.targets:
			if absf((tg["dir"] as Vector2).angle_to(toward)) < deg_to_rad(Balance.GREEDY_SEP_DEG):
				points = true
			if vr.has_point(tg["pos"]):
				all_off = false
		t.check(points, "Greedy Lamp: an arrow points toward off-screen ore")
		t.check(all_off and cp.targets.size() <= Balance.GREEDY_ARROWS, "Greedy Lamp: arrows only for ore off screen, at most %d" % Balance.GREEDY_ARROWS)
		t.check(cp.visible, "the compass shows while you hold the relic")
	held.clear()
	# the compass updates on idle frames, which headless runs space out more
	# than the physics ticks the test waits on
	for k in 120:
		await t._frames(1)
		if not cp.visible:
			break
	t.check(not cp.visible and cp.targets.is_empty(), "without the relic the compass hides")
	t.check(is_equal_approx(pl.lamp.texture_scale, lamp0), "without the relic the lamp is back to normal (%.3f vs %.3f)" % [pl.lamp.texture_scale, lamp0])


static func feet(t: Node) -> void:
	t.section("feet on the ground")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(60)
	var mine: Node = Game.current
	var pl: Player = mine.player
	var view: TerrainView = mine.view
	var g: TerrainGrid = mine.grid
	var cy := int(floor((pl.global_position.y + Player.HALF.y + 1.0) / 16.0))
	var want := 99
	for fx in [-3.0, 0.0, 3.0]:
		var c := g.world_to_cell(Vector2(pl.global_position.x + fx, cy * 16.0 + 1.0))
		if g.is_solid(c.x, c.y):
			want = mini(want, view.surface_depth(pl.global_position.x + fx, cy))
	t.check(pl.is_on_floor() and want >= 0 and want <= Balance.FOOT_SINK_MAX, "the rock under the feet sits %d px below the cell top" % want)
	t.check(is_equal_approx(pl._sink, float(mini(want, Balance.FOOT_SINK_MAX))) and is_equal_approx(pl.body_sprite.position.y, round(pl._sink)), "the sprite sinks onto the visible rock (%.1f px)" % pl._sink)
	t.check(view.surface_depth(pl.global_position.x, cy + 1) == 0, "buried cells report no surface")
	pl.velocity.y = -200.0
	pl.global_position.y -= 40.0
	await t._frames(3)
	t.check(pl._sink < want or want == 0, "in the air the sprite lifts back")
	await _settle(t)
	Game.goto("title", true)
	await _settle(t)


static func charges(t: Node) -> void:
	t.section("charge upgrades")
	var saved := Progress.to_dict()
	Progress.reset()
	t.check(Progress.charges_max() == 6 and not Progress.sticky_active(), "no upgrades: 6 charges max, no sticky charges")
	Progress.upgrades["charge_rack"] = 2
	Progress.upgrades["sticky"] = 1
	t.check(Progress.charges_max() == 10 and Progress.sticky_active(), "Charge Rack II carries 10; Sticky unlocked is on by default")
	Progress.credits = 1000
	for k in 12:
		Progress.buy_charge()
	t.check(Progress.charges + Balance.CHARGES_FREE == 10, "you can pack charges up to the rack size (%d)" % (Progress.charges + Balance.CHARGES_FREE))
	Progress.sticky_on = false
	var d := Progress.to_dict()
	Progress.from_dict(d)
	t.check(Progress.level("charge_rack") == 2 and Progress.charges == 8 and not Progress.sticky_on and not Progress.sticky_active(), "rack, packed charges and the sticky toggle survive a save")
	Progress.sticky_on = true
	# live: a sticky charge thrown at a wall stays there; a normal one drops
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(20)
	var mine: Node = Game.current
	var pl: Player = mine.player
	pl.invuln = 1e9
	t.check(bool(Game.run.get("sticky", false)) and int(Game.run["charges"]) == 10, "the run gets sticky charges and the full rack")
	var g: TerrainGrid = mine.grid
	var pc: Vector2i = g.world_to_cell(pl.global_position)
	# build a wall 3 cells to the right, open air in front of it
	for dy in range(-4, 1):
		for dx in range(1, 3):
			g.set_mat(pc.x + dx, pc.y + dy, Cell.AIR)
		g.set_mat(pc.x + 3, pc.y + dy, Cell.HARD)
	var sticky_pos := Vector2(pc.x * 16 + 24, pc.y * 16 - 24)
	mine.spawn_charge(sticky_pos, Vector2(220, 0))
	var ch: Node2D = null
	for e in mine.entity_root.get_children():
		if e is Hazards.Charge:
			ch = e
	await t._frames(40)
	var stuck_y := ch.global_position.y if is_instance_valid(ch) else -1.0
	var stuck_ok: bool = is_instance_valid(ch) and ch.glued and absf(stuck_y - sticky_pos.y) < 4.0 and ch.global_position.x > sticky_pos.x + 8.0
	t.check(stuck_ok, "a sticky charge sticks to the wall where it hits")
	if is_instance_valid(ch):
		ch.queue_free()
	Game.run["sticky"] = false
	mine.spawn_charge(sticky_pos, Vector2(220, 0))
	var ch2: Node2D = null
	for e in mine.entity_root.get_children():
		if e is Hazards.Charge and not e.is_queued_for_deletion():
			ch2 = e
	await t._frames(40)
	t.check(is_instance_valid(ch2) and not ch2.sticky and ch2.global_position.y > sticky_pos.y + 8.0, "with sticky off, a charge falls as before")
	if is_instance_valid(ch2):
		ch2.queue_free()
	Progress.from_dict(saved)
	await _settle(t)
	Game.goto("title", true)
	await _settle(t)


static func _sand_box(w: int, h: int) -> TerrainGrid:
	var g := TerrainGrid.new(w, h)
	for y in h:
		for x in w:
			g.put(x, y, Cell.BEDROCK if (x == 0 or y == 0 or x == w - 1 or y == h - 1) else Cell.AIR)
	return g


static func _settle_sand(sim: SandSim, max_steps: int = 600) -> int:
	var n := 0
	while not sim.active.is_empty() and n < max_steps:
		sim.step()
		n += 1
	return n


static func sand(t: Node) -> void:
	t.section("sand piles")
	var keep_level: int = Settings.get_value("sand_physics")
	Settings.values["sand_physics"] = 2
	# a heap dropped in the air falls, then slumps into a mound
	var g := _sand_box(16, 10)
	var sim := SandSim.new(g)
	for k in 4:
		sim.add(Vector2i(8, 2), Balance.SAND_MAX)
		for j in 6:
			sim.step()
	var start := sim.total()
	var n := _settle_sand(sim)
	var floating := 0
	var steep := 0
	var width := 0
	for x in range(1, 15):
		if g.get_sand(x, 8) > 0:
			width += 1
		for y in range(1, 9):
			var v := g.get_sand(x, y)
			if v > 0 and not g.is_solid(x, y + 1) and g.get_sand(x, y + 1) < Balance.SAND_MAX:
				floating += 1
		var a := g.get_sand(x, 8)
		var b := g.get_sand(x + 1, 8)
		if not g.is_solid(x + 1, 8) and absi(a - b) > Balance.SAND_REPOSE + 1 and g.get_sand(x, 7) == 0 and g.get_sand(x + 1, 7) == 0:
			steep += 1
	t.check(sim.total() == start and start == 4 * Balance.SAND_MAX, "sand is conserved while it moves (%d px)" % sim.total())
	t.check(n < 600 and floating == 0, "the heap comes to rest with nothing floating (%d steps)" % n)
	t.check(width >= 4 and steep == 0, "it slumps into a mound %d cells wide, no step steeper than the angle of repose" % width)
	# never into an actor's cell
	var g2 := _sand_box(10, 8)
	var sim2 := SandSim.new(g2)
	var blocked := Vector2i(4, 6)
	sim2.occupied = func(c: Vector2i) -> bool: return c == blocked
	sim2.add(Vector2i(4, 2), Balance.SAND_MAX)
	_settle_sand(sim2)
	t.check(g2.get_sand(4, 6) == 0 and sim2.total() == Balance.SAND_MAX, "sand never enters a cell an actor stands in")
	# sand that lands in water pushes the water up
	var g3 := _sand_box(6, 8)
	var sim3 := SandSim.new(g3)
	for x in range(1, 5):
		g3.set_water(x, 6, Balance.WATER_MAX)
	var w0 := 0
	for v in g3.water:
		w0 += v
	sim3.add(Vector2i(2, 2), Balance.SAND_MAX)
	_settle_sand(sim3)
	var w1 := 0
	for v in g3.water:
		w1 += v
	t.check(w1 == w0 and g3.get_sand(2, 6) > 0, "sand sinks into a pool and displaces its water (%d -> %d)" % [w0, w1])
	# live: a pile you walk over, sources, digging, the Off setting
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	await _settle_scene(t)
	Game.start_run()
	await _settle_scene(t)
	await t._frames(20)
	var mine: Node = Game.current
	var pl: Player = mine.player
	pl.invuln = 1e9
	var mg: TerrainGrid = mine.grid
	var pc: Vector2i = mg.world_to_cell(pl.global_position)
	var fy := pc.y + 1                 # the floor row under the feet
	# a flat corridor 12 cells long, then a mound in the middle of it
	for x in range(pc.x - 1, pc.x + 12):
		for y in range(pc.y - 3, pc.y + 1):
			mg.set_mat(x, y, Cell.AIR)
		mg.set_mat(x, fy, Cell.HARD)
	mg.set_mat(pc.x + 12, pc.y, Cell.HARD)
	for x in range(pc.x + 4, pc.x + 7):
		mine.sand.add(Vector2i(x, pc.y), 12)
	mine.sand.add(Vector2i(pc.x + 5, pc.y - 1), 4)
	await t._frames(40)
	var y0 := pl.global_position.y
	var top := y0
	pl.input_override = {"x": 1.0}
	for k in 90:
		await t.get_tree().physics_frame
		top = minf(top, pl.global_position.y)
	pl.input_override = {"x": 0.0}
	t.check(y0 - top >= 6.0, "walking over a sand mound lifts the digger onto it (%.1f px)" % (y0 - top))
	t.check(pl.global_position.x > (pc.x + 7) * 16.0, "and carries on past it")
	var before: int = mine.sand.total()
	var soft: Array[Vector2i] = []
	for k in 3:
		var c := Vector2i(pc.x + 2 + k, pc.y - 2)
		mg.set_mat(c.x, c.y, Cell.SOFT)
		soft.append(c)
	var lost0: int = mine.sand_drops.lost
	for c in soft:
		mine.damage_cell(c, 999.0, 3, true, "drill")
	t.check(mine.sand_drops.in_flight() == Balance.SAND_DRILL_AMOUNT, "drilled sediment throws its sand as flying grains (%d px in the air)" % mine.sand_drops.in_flight())
	for k in 240:
		if mine.sand_drops.pos.is_empty():
			break
		await t.get_tree().physics_frame
	t.check(mine.sand_drops.pos.is_empty() and mine.sand.total() - before == Balance.SAND_DRILL_AMOUNT and mine.sand_drops.lost == lost0, "the grains land and become sand where they fall (+%d px, one in %d cells)" % [mine.sand.total() - before, Balance.SAND_DRILL_EVERY])
	var sc := Vector2i(-1, -1)
	for x in range(pc.x + 3, pc.x + 8):
		if mg.get_sand(x, pc.y) > 0:
			sc = Vector2i(x, pc.y)
			break
	var had := mg.get_sand(sc.x, sc.y)
	mine.dig_sand(sc)
	t.check(had > 0 and mg.get_sand(sc.x, sc.y) == 0, "the drill takes sand away in one bite")
	# a fallen ceiling block lands as rubble that slumps
	var land := Vector2i(pc.x + 9, pc.y)
	mg.set_flag(land.x, land.y, Cell.F_NO_RUBBLE, false)
	var before2: int = mine.sand.total()
	mine.collapse._land(land.x, land.y, 0)
	for k in 240:
		if mine.sand_drops.pos.is_empty():
			break
		await t.get_tree().physics_frame
	t.check(mine.sand.total() - before2 == Balance.SAND_RUBBLE_AMOUNT and mg.get_mat(land.x, land.y) == Cell.AIR, "a falling ceiling block lands as scattered rubble that piles up (+%d px)" % (mine.sand.total() - before2))
	# Off: the old behaviour, no new sand
	Settings.values["sand_physics"] = 0
	var before3: int = mine.sand.total()
	for k in 6:
		var c2 := Vector2i(pc.x + 1 + k, pc.y - 3)
		mg.set_mat(c2.x, c2.y, Cell.SOFT)
		mine.damage_cell(c2, 999.0, 3, true, "drill")
	t.check(mine.sand.total() == before3 and mine.sand_drops.pos.is_empty(), "with Sand physics off, no new sand appears")
	Settings.values["sand_physics"] = keep_level
	await _settle_scene(t)
	Game.goto("title", true)
	await _settle_scene(t)



static func sand_look(t: Node) -> void:
	t.section("sand piles sit on the ground")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(10)
	var mine: Node = Game.current
	var view: TerrainView = mine.view
	var g: TerrainGrid = mine.grid
	var pc: Vector2i = g.world_to_cell(mine.player.global_position)
	var c := Vector2i(pc.x + 4, pc.y)
	for x in range(c.x - 2, c.x + 3):
		g.set_mat(x, c.y, Cell.AIR)
		g.set_mat(x, c.y + 1, Cell.HARD)
	mine.sand.add(c, 12)
	var foot_l := view.sand_height(c.x - 1, c.y, 0.0)
	var foot_r := view.sand_height(c.x + 1, c.y, 16.0)
	var peak := view.sand_height(c.x, c.y, 8.0)
	t.check(peak >= 11.5 and foot_l < 0.5 and foot_r < 0.5, "a pile rises from nothing at its feet to its peak (%.1f / %.1f / %.1f)" % [foot_l, peak, foot_r])
	var smooth := true
	var prev := view.sand_height(c.x - 1, c.y, 0.0)
	for k in range(1, 48):
		var x := c.x - 1 + k / 16
		var h := view.sand_height(x, c.y, float(k % 16))
		if absf(h - prev) > 2.0:
			smooth = false
		prev = h
	t.check(smooth, "the surface has no steps or hard corners")
	var b := view.sand_base(c.x, c.y, 8.0)
	t.check(b > (c.y + 1) * 16.0, "the pile sits on the visible ground line, not on the cell edge above it")
	await _settle(t)
	Game.goto("title", true)
	await _settle(t)



static func zones(t: Node) -> void:
	t.section("zone you are in")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(10)
	var mine: Node = Game.current
	var g: TerrainGrid = mine.grid
	var pl: Player = mine.player
	pl.invuln = 1e9
	# find a column where a wing meets the Engine: the first Engine row
	var bx := -1
	var by := -1
	for x in range(10, 60):
		for y in range(196, 214):
			if g.get_stratum(x, y) == Balance.Z_ENGINE and g.get_stratum(x, y - 1) == Balance.Z_AQUEDUCT:
				bx = x
				by = y
				break
		if bx >= 0:
			break
	t.check(bx >= 0, "found the wing / Engine border")
	if bx < 0:
		return
	mine.presented_zone = Balance.Z_AQUEDUCT
	var place := func(row: int) -> void:
		pl.global_position = Vector2(bx * 16 + 8, (row + 1) * 16 - Player.HALF.y - 0.5)
		pl.velocity = Vector2.ZERO
		mine._update_presented_zone()
	place.call(by)
	t.check(mine.presented_zone == Balance.Z_AQUEDUCT, "just past the border you are still in the wing")
	place.call(by + Balance.ZONE_ENTRY_ROWS + 1)
	t.check(mine.presented_zone == Balance.Z_ENGINE, "a few rows in, you are in the Forgotten Engine")
	place.call(by - 1)
	t.check(mine.presented_zone == Balance.Z_ENGINE, "stepping back over the line does not flicker the zone")
	place.call(by - Balance.ZONE_ENTRY_ROWS - 1)
	t.check(mine.presented_zone == Balance.Z_AQUEDUCT, "climbing well back up returns you to the wing")
	await _settle(t)
	Game.goto("title", true)
	await _settle(t)



## A test room beside the digger: open floor, a soft roof 3 cells thick.
static func _roofed_room(mine: Node, pc: Vector2i) -> Array[Vector2i]:
	var g: TerrainGrid = mine.grid
	var roof: Array[Vector2i] = []
	for x in range(pc.x - 1, pc.x + 12):
		for y in range(pc.y - 8, pc.y + 2):
			g.set_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE, false)
			g.set_water(x, y, 0)
			if y == pc.y + 1 or x == pc.x - 1 or x == pc.x + 11:
				g.set_mat(x, y, Cell.HARD)
			elif y <= pc.y - 5:
				g.set_mat(x, y, Cell.SOFT)
				if y == pc.y - 5:
					roof.append(Vector2i(x, y))
			else:
				g.set_mat(x, y, Cell.AIR)
	return roof


static func kit(t: Node) -> void:
	t.section("shear charges, anchor bolts, breakers")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(10)
	var mine: Node = Game.current
	var g: TerrainGrid = mine.grid
	var pl: Player = mine.player
	pl.invuln = 1e9
	t.check(int(Game.run["shears"]) == Balance.SHEARS_PER_RUN and int(Game.run["bolts"]) == Balance.BOLTS_PER_RUN, "a dive starts with shear charges and anchor bolts")
	var pc: Vector2i = g.world_to_cell(pl.global_position)
	var roof := _roofed_room(mine, pc)
	await t._frames(3)
	# bolt the roof above the digger, then shear the roof further along
	pl.global_position = Vector2((pc.x + 2) * 16 + 8, (pc.y + 1) * 16 - Player.HALF.y - 0.5)
	var bolted: bool = mine.fire_bolt(pl, Vector2i.UP)
	var held := Vector2i(pc.x + 2, pc.y - 5)
	t.check(bolted and mine.is_anchored(held), "an anchor bolt pins the roof above you")
	mine.shear_blast(Vector2((pc.x + 7) * 16 + 8, (pc.y - 4) * 16 + 8))
	for k in 150:
		await t.get_tree().physics_frame
	var fell := 0
	for c in roof:
		if absi(c.x - (pc.x + 7)) <= 3 and not g.is_solid(c.x, c.y):
			fell += 1
	t.check(fell >= 4, "a shear charge brings the roof around it down (%d cells)" % fell)
	t.check(g.is_solid(held.x, held.y), "the bolted part of the roof holds")
	# bolts work loose
	var bolt: Node = null
	for e in mine.entity_root.get_children():
		if e is Hazards.Bolt:
			bolt = e
	if bolt:
		bolt.t = Balance.BOLT_TIME - 0.02
		await t._frames(5)
	t.check(not mine.is_anchored(held), "a bolt works loose after %d s" % int(Balance.BOLT_TIME))
	# a breaker gnaws the roof over the digger
	roof = _roofed_room(mine, pc)
	mine.anchored.clear()
	await t._frames(3)
	pl.global_position = Vector2((pc.x + 7) * 16 + 8, (pc.y + 1) * 16 - Player.HALF.y - 0.5)
	pl.velocity = Vector2.ZERO
	await t._frames(3)
	var br: Breaker = mine.spawn_crawler(Vector2i(pc.x + 2, pc.y), true)
	await t._frames(2)
	t.check(br is Breaker and br.hp == Balance.BREAKER_HP, "breakers are tougher burrowers")
	t.check(br.try_gnaw() and br.gnawing, "a breaker that sees you under a roof starts gnawing it")
	var hp0 := br.hp
	br.hit(10.0, br.global_position, false)
	t.check(is_equal_approx(hp0 - br.hp, 10.0 * Balance.BREAKER_GNAW_MULT), "it takes double damage while it gnaws")
	var target: Array[Vector2i] = br.gnaw_cells.duplicate()
	pl.global_position.x -= 48.0           # step out from under it
	for k in int(60 * (Balance.BREAKER_GNAW + Balance.BREAKER_DROP_WARN + 1.5)):
		await t.get_tree().physics_frame
	var gone := 0
	for c in target:
		if not g.is_solid(c.x, c.y):
			gone += 1
	t.check(gone >= 2 and br.gnaws == 1, "after its warning the gnawed roof comes down (%d cells)" % gone)
	# bolted roofs defeat it
	roof = _roofed_room(mine, pc)
	await t._frames(3)
	pl.global_position = Vector2((pc.x + 7) * 16 + 8, (pc.y + 1) * 16 - Player.HALF.y - 0.5)
	mine.fire_bolt(pl, Vector2i.UP)
	br.gnaw_cd = 0.0
	if is_instance_valid(br) and br.state != Crawler.S.DEAD:
		br.state = Crawler.S.CHASE
		var started: bool = br.try_gnaw()
		t.check(not started, "a breaker cannot gnaw a bolted roof")
	# breakers only appear in their zones
	var wrong := 0
	for e in mine.enemies:
		if e is Breaker and e != br:
			var ec: Vector2i = g.world_to_cell(e.global_position)
			if not (g.get_stratum(ec.x, ec.y) in Balance.BREAKER_ZONES):
				wrong += 1
	t.check(wrong == 0, "breakers spawn only in the Forgotten Engine and Drowned Aqueducts")
	await _settle(t)
	Game.goto("title", true)
	await _settle(t)
