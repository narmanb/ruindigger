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
	# only=<section>: run one section (for chasing an intermittent failure)
	if t.args.has("only"):
		match String(t.args["only"]):
			"roamers": await roamers(t)
			"roamers_b": await roamers_b(t)
			"roamers_c": await roamers_c(t)
			"charges": await charges(t)
			"drops": await drops_on_sand(t)
			"perf": await perf(t)
			"missions": await missions(t)
		return
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
	await roamers(t)
	await roamers_b(t)
	await roamers_c(t)
	await drops_on_sand(t)
	await perf(t)
	await missions(t)
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


static func mines_ignore(mine: Node) -> bool:
	return mine.mines_ignore_digger()


static func charges(t: Node) -> void:
	t.section("explosives and the Demolitions counter")
	var saved := Progress.to_dict()
	Progress.reset()
	# --- the counter: slots, stock, upgrades ---
	t.check(Progress.slots == ["charge", ""] and Progress.carry("charge") == 6 and Progress.packed("charge") == 2, "a new save packs 2 free demo charges in the main slot, no backup")
	Progress.credits = 1000
	for k in 12:
		Progress.buy_explosive("charge")
	t.check(Progress.stock("charge") == 4 and Progress.packed("charge") == 6 and Progress.credits == 1000 - 4 * int(Balance.EXPLOSIVES["charge"]["price"]), "you can buy up to what you can carry (free units count)")
	t.check(Progress.buy_demo("capacity") and Progress.carry("charge") == 8 and Progress.carry("rocket") == 4, "BIGGER RACK raises every type's carry limit")
	Progress.credits = 5000
	t.check(Progress.buy_demo("power") and Progress.buy_demo("power") and not Progress.buy_demo("power"), "BLAST POWER has two levels and then stops")
	t.check(Progress.buy_demo("radius") and Progress.buy_demo("radius") and not Progress.buy_demo("radius"), "BLAST RADIUS has two levels and then stops")
	var capped := true
	for track: String in Balance.DEMO_TRACKS:
		var info: Dictionary = Balance.DEMO_UPGRADES[track]
		var n: int = (info["costs"] as Array).size()
		if n < 1 or n > 3 or (info.has("mult") and (info["mult"] as Array).size() != n + 1) or (info.has("levels") and (info["levels"] as Array).size() != n + 1):
			capped = false
	t.check(capped and Balance.DEMO_TRACKS.size() == Balance.DEMO_UPGRADES.size(), "every Demolitions upgrade is capped and has a value for each level")
	t.check(Progress.set_slot(1, "rocket") and Progress.slots == ["charge", "rocket"], "a backup explosive can be packed")
	t.check(Progress.free_units("charge") == 2 and Progress.free_units("rocket") == 0, "only the main slot gets free units")
	t.check(Progress.set_slot(0, "rocket") and Progress.slots == ["rocket", "charge"], "picking the other slot's type swaps the two")
	t.check(not Progress.set_slot(0, "") and not Progress.set_slot(1, "nope") and Progress.slots == ["rocket", "charge"], "the main slot cannot be emptied; unknown types are refused")
	t.check(Progress.set_slot(1, "") and Progress.slots == ["rocket", ""], "the backup slot can be emptied")
	Progress.set_slot(0, "charge")
	Progress.set_slot(1, "rocket")
	Progress.buy_explosive("rocket")
	var d := Progress.to_dict()
	Progress.reset()
	Progress.from_dict(d)
	t.check(Progress.slots == ["charge", "rocket"] and Progress.stock("charge") == 4 and Progress.stock("rocket") == 1 and Progress.demo_level("capacity") == 1 and Progress.demo_level("power") == 2, "slots, stock and upgrades survive a save")
	# an old save: Charge Rack II, Sticky Charges owned, 5 charges packed
	Progress.from_dict({"version": 1, "credits": 100, "upgrades": {"drill": 1, "charge_rack": 2, "sticky": 1}, "charges": 5, "sticky_on": true})
	t.check(Progress.demo_level("capacity") == 2 and Progress.carry("charge") == 10, "old saves: the Charge Rack becomes BIGGER RACK")
	t.check(Progress.credits == 100 + Balance.STICKY_REFUND, "old saves: the retired Sticky Charges upgrade is paid back")
	t.check(Progress.stock("charge") == 5 and Progress.slots == ["charge", ""] and Progress.level("drill") == 1, "old saves: packed charges and other upgrades carry over")
	t.check(InputMap.has_action("charge2"), "the backup slot has its own input action")
	# --- a dive with two slots ---
	Progress.reset()
	Progress.slots = ["charge", "rocket"]
	Progress.explosives = {"charge": 1, "rocket": 2, "mine": 3}
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(20)
	var mine: Node = Game.current
	var pl: Player = mine.player
	pl.invuln = 1e9
	t.check(Game.run["slots"] == ["charge", "rocket"] and int(Game.run["charges"]) == 3 and int(Game.run["charges2"]) == 2, "the dive starts with both slots: 2 free + 1 bought, and 2 rockets")
	t.check(Progress.stock("charge") == 0 and Progress.stock("rocket") == 0 and Progress.stock("mine") == 3, "packed stock goes down with you; other types wait at the outpost")
	var g: TerrainGrid = mine.grid
	var pc: Vector2i = g.world_to_cell(pl.global_position)
	# a flat, open test floor around the digger
	for x in range(pc.x - 8, pc.x + 22):
		for y in range(pc.y - 5, pc.y + 4):
			if g.in_bounds(x, y):
				g.set_flag(x, y, Cell.F_PROTECTED, false)
				g.set_mat(x, y, Cell.AIR if y <= pc.y else Cell.HARD)
				g.set_water(x, y, 0)
	await t._frames(3)
	# sticky sticks, a demo charge falls
	for dy in range(-5, 1):
		g.set_mat(pc.x + 3, pc.y + dy, Cell.HARD)
	var throw_pos := Vector2(pc.x * 16 + 24, pc.y * 16 - 24)
	var ch: Hazards.Charge = mine.spawn_charge(throw_pos, Vector2(220, 0), "sticky")
	await t._frames(40)
	t.check(is_instance_valid(ch) and ch.glued and absf(ch.global_position.y - throw_pos.y) < 4.0 and ch.global_position.x > throw_pos.x + 8.0, "a sticky charge sticks to the wall where it hits")
	if is_instance_valid(ch):
		ch.queue_free()
	var ch2: Hazards.Charge = mine.spawn_charge(throw_pos, Vector2(220, 0), "charge")
	await t._frames(40)
	t.check(is_instance_valid(ch2) and not ch2.sticky and ch2.global_position.y > throw_pos.y + 8.0, "a demo charge bounces off and falls")
	if is_instance_valid(ch2):
		ch2.queue_free()
	for dy in range(-5, 1):
		g.set_mat(pc.x + 3, pc.y + dy, Cell.AIR)
	await t._frames(2)
	# slots: the backup button throws the backup type; an empty slot does nothing
	var before: int = mine.entity_root.get_child_count()
	Game.run["slots"] = ["charge", ""]
	pl.use_explosive(1, 0.0)
	t.check(mine.entity_root.get_child_count() == before and int(Game.run["charges2"]) == 2, "an empty backup slot does nothing")
	Game.run["slots"] = ["charge", "rocket"]
	# drill rocket: bores a digger-sized tunnel through basalt, then blows
	for x in range(pc.x + 3, pc.x + 16):
		for y in range(pc.y - 5, pc.y + 1):
			g.set_mat(x, y, Cell.HARD)
	pl.facing = 1
	pl.use_explosive(1, 0.0)
	var rk: Hazards.Rocket = null
	for e in mine.entity_root.get_children():
		if e is Hazards.Rocket:
			rk = e
	t.check(rk != null and int(Game.run["charges2"]) == 1, "the backup button fires a drill rocket and uses one")
	t.check(is_zero_approx(pl.drill_regrow) and rk.bit != null, "the rocket is your own drill: it leaves the arm")
	pl.input_override = {"drill": true}
	await t._frames(6)
	t.check(not pl.drilling and not pl.drill_sprite.visible, "the arm is bare for a moment and cannot drill")
	await t._frames(int(Balance.ROCKET_REGROW * 60.0) + 4)
	t.check(pl.drilling and pl.drill_sprite.visible and is_equal_approx(pl.drill_regrow, 1.0), "a new drill grows back in half a second and works again")
	pl.input_override = {}
	var row := g.world_to_cell(rk.global_position).y if rk else pc.y
	var bored := 0
	for k in 240:
		if not is_instance_valid(rk):
			break
		bored = rk.bored
		await t._frames(1)
	var tunnel := true
	for x in range(pc.x + 3, pc.x + 7):
		if g.is_solid(x, row) or g.is_solid(x, row + 1):
			tunnel = false
	t.check(not is_instance_valid(rk) and bored >= 6 and tunnel, "a drill rocket bores a two-cell-high tunnel through basalt (%d cells) and then blows" % bored)
	t.check(g.is_solid(pc.x + 4, row - 2), "the rock above the tunnel's start is left alone")
	# ...and stops dead at alloy
	for y in range(pc.y - 5, pc.y + 1):
		g.set_mat(pc.x + 3, y, Cell.ALLOY)
	var rk2: Hazards.Rocket = mine.spawn_rocket(pl.global_position + Vector2(8, -6), Vector2i(1, 0))
	for k in 60:
		if not is_instance_valid(rk2):
			break
		await t._frames(1)
	t.check(not is_instance_valid(rk2) and g.get_mat(pc.x + 3, row) == Cell.ALLOY, "a drill rocket blows at once on alloy and does not cut it")
	for x in range(pc.x - 8, pc.x + 22):
		for y in range(pc.y - 5, pc.y + 1):
			g.set_mat(x, y, Cell.AIR)
	await t._frames(3)
	# remote charge: no fuse; the same button sets it off
	Game.run["slots"] = ["remote", ""]
	Game.run["charges"] = 2
	pl.use_explosive(0, 0.0)
	t.check(mine.remotes_out() == 1 and int(Game.run["charges"]) == 1, "a remote charge is thrown")
	await t._frames(int((Balance.CHARGE_FUSE + 1.0) * 60.0))
	t.check(mine.remotes_out() == 1, "a remote charge waits: it has no fuse")
	pl.use_explosive(0, 0.0)
	t.check(int(Game.run["charges"]) == 1, "pressing again sets it off instead of throwing another")
	await t._frames(30)
	t.check(mine.remotes_out() == 0, "the remote charge has gone off")
	# proximity mine: arms once you step away; a foe sets it off
	for x in range(pc.x - 8, pc.x + 22):
		for y in range(pc.y - 5, pc.y + 4):
			g.set_mat(x, y, Cell.AIR if y <= pc.y else Cell.HARD)
	await t._frames(3)
	var home := pl.global_position
	Game.run["slots"] = ["mine", ""]
	Game.run["charges"] = 2
	pl.use_explosive(0, 0.0)
	var pm: Hazards.ProxMine = null
	for e in mine.entity_root.get_children():
		if e is Hazards.ProxMine:
			pm = e
	t.check(pm != null and int(Game.run["charges"]) == 1, "a proximity mine is laid at your feet")
	await t._frames(int((Balance.MINE_ARM + 0.5) * 60.0))
	t.check(is_instance_valid(pm) and not pm.armed, "a mine does not arm while you stand on it")
	pl.global_position = home + Vector2(7 * 16, 0)
	pl.velocity = Vector2.ZERO
	await t._frames(6)
	t.check(is_instance_valid(pm) and pm.armed and pm.tripped < 0.0, "it arms once you step away")
	var cr: Crawler = mine.spawn_crawler(g.world_to_cell(pm.global_position) + Vector2i(1, 0))
	cr.asleep = false
	var hp0 := cr.hp
	for k in 90:
		if not is_instance_valid(pm):
			break
		await t._frames(1)
	await t._frames(2)
	t.check(not is_instance_valid(pm) and (not is_instance_valid(cr) or cr.hp < hp0 or cr.state == Crawler.S.DEAD), "a crawler walking onto a mine sets it off and is hurt")
	# ...and so does a forgetful digger
	var pm2: Hazards.ProxMine = mine.spawn_mine(home + Vector2(0, Player.HALF.y - 5.0))
	await t._frames(int((Balance.MINE_ARM + 0.3) * 60.0))
	t.check(is_instance_valid(pm2) and pm2.armed, "a second mine arms while you are away")
	pl.invuln = 0.0
	var php := pl.hp
	pl.global_position = home
	pl.velocity = Vector2.ZERO
	for k in 90:
		if not is_instance_valid(pm2):
			break
		await t._frames(1)
	await t._frames(2)
	t.check(not is_instance_valid(pm2) and pl.hp < php, "walking back onto your own mine sets it off and hurts")
	pl.invuln = 1e9
	pl.hp = pl.max_hp
	# blast upgrades
	t.check(is_equal_approx(mine.blast_radius(), Balance.CHARGE_RADIUS_CELLS) and is_equal_approx(mine.blast_power(), 1.0), "no upgrades: the standard blast")
	Progress.demo = {"power": 2, "radius": 2}
	t.check(is_equal_approx(mine.blast_radius(), Balance.CHARGE_RADIUS_CELLS * 1.3) and is_equal_approx(mine.blast_power(), 1.5), "BLAST RADIUS and BLAST POWER scale your explosives")
	Progress.demo = {}
	# the other upgrades: fuse, rocket drive, blast shielding, mine sensor
	var c0: Hazards.Charge = mine.spawn_charge(home + Vector2(200, -40), Vector2.ZERO, "charge")
	var r0: Hazards.Rocket = mine.spawn_rocket(home + Vector2(200, -60), Vector2i(1, 0))
	var base_fuse := c0.fuse
	var base_life := r0.life
	c0.queue_free()
	r0.queue_free()
	Progress.demo = {"fuse": 2, "bore": 2, "sensor": 1, "shield": 2}
	var c1: Hazards.Charge = mine.spawn_charge(home + Vector2(200, -40), Vector2.ZERO, "sticky")
	var r1: Hazards.Rocket = mine.spawn_rocket(home + Vector2(200, -60), Vector2i(1, 0))
	t.check(is_equal_approx(base_fuse, Balance.CHARGE_FUSE) and is_equal_approx(c1.fuse, Balance.CHARGE_FUSE * 0.6), "QUICK FUSE shortens the fuse (%.1f s to %.1f s)" % [base_fuse, c1.fuse])
	t.check(is_equal_approx(base_life, Balance.ROCKET_LIFE) and is_equal_approx(r1.life, Balance.ROCKET_LIFE * 1.6), "ROCKET DRIVE lets a rocket bore for longer")
	c1.queue_free()
	r1.queue_free()
	t.check(is_equal_approx(mine.mine_trigger(), Balance.MINE_TRIGGER * 1.4) and not mines_ignore(mine), "MINE SENSOR I: mines sense 40% further")
	await t._frames(3)
	# blast shielding: your own blast hurts less
	pl.global_position = home
	pl.velocity = Vector2.ZERO
	Progress.demo = {}
	pl.invuln = 0.0
	pl.hp = pl.max_hp
	mine.charge_blast(home + Vector2(20, 0))
	var hurt_plain := pl.max_hp - pl.hp
	Progress.demo = {"shield": 2}
	pl.global_position = home
	pl.velocity = Vector2.ZERO
	pl.invuln = 0.0
	pl.hp = pl.max_hp
	mine.charge_blast(home + Vector2(20, 0))
	var hurt_shield := pl.max_hp - pl.hp
	t.check(hurt_plain > 0.0 and absf(hurt_shield - hurt_plain * 0.4) < 0.5, "BLAST SHIELDING II: your own blast does 60%% less (%.1f to %.1f)" % [hurt_plain, hurt_shield])
	pl.invuln = 1e9
	pl.hp = pl.max_hp
	Progress.demo = {}
	# rebuild the floor the blasts chewed up
	for x in range(pc.x - 8, pc.x + 22):
		for y in range(pc.y - 5, pc.y + 4):
			g.set_mat(x, y, Cell.AIR if y <= pc.y else Cell.HARD)
	pl.global_position = home
	pl.velocity = Vector2.ZERO
	await t._frames(3)
	# a blast sets mines off, armed or not; the next mine along chains
	var ma: Hazards.ProxMine = mine.spawn_mine(home + Vector2(5 * 16, Player.HALF.y - 5.0))
	var mb: Hazards.ProxMine = mine.spawn_mine(home + Vector2(8 * 16, Player.HALF.y - 5.0))
	var far_mine: Hazards.ProxMine = mine.spawn_mine(home + Vector2(18 * 16, Player.HALF.y - 5.0))
	await t._frames(4)
	t.check(not ma.armed and ma.tripped < 0.0, "a fresh mine is not armed yet")
	mine.charge_blast(home + Vector2(3 * 16, 0))
	t.check(ma.tripped >= 0.0 and mb.tripped < 0.0, "a blast in reach sets a mine off, even before it arms")
	for k in 120:
		if not is_instance_valid(mb):
			break
		await t._frames(1)
	t.check(not is_instance_valid(ma) and not is_instance_valid(mb), "that mine's blast sets off the next one along")
	t.check(is_instance_valid(far_mine) and far_mine.tripped < 0.0, "a mine out of reach is left alone")
	# MINE SENSOR II: your own mines ignore you
	Progress.demo = {"sensor": 2}
	for x in range(pc.x - 8, pc.x + 22):
		for y in range(pc.y - 5, pc.y + 4):
			g.set_mat(x, y, Cell.AIR if y <= pc.y else Cell.HARD)
	pl.global_position = home
	pl.velocity = Vector2.ZERO
	await t._frames(3)
	var mf: Hazards.ProxMine = mine.spawn_mine(home + Vector2(0, Player.HALF.y - 5.0))
	await t._frames(int((Balance.MINE_ARM + 0.8) * 60.0))
	t.check(mines_ignore(mine) and is_instance_valid(mf) and mf.armed and mf.tripped < 0.0, "MINE SENSOR II: a mine arms under you and does not go off")
	if is_instance_valid(mf):
		mf.queue_free()
	if is_instance_valid(far_mine):
		far_mine.queue_free()
	Progress.demo = {}
	# a supply cache restocks whatever your main explosive is
	Game.run["slots"] = ["rocket", ""]
	Game.run["charges"] = 3
	var cache := Entities.Cache.new()
	cache.mine = mine
	cache.charges = 5
	mine.entity_root.add_child(cache)
	cache.use(pl)
	t.check(int(Game.run["charges"]) == Progress.carry("rocket") + Balance.CACHE_OVERFILL, "a supply cache restocks your main explosive, up to %d over your limit" % Balance.CACHE_OVERFILL)
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


## 0.15.0 enemies: the shielded brute and the flier.
static func roamers(t: Node) -> void:
	t.section("shielded brute and flier")
	t.check(Brute.HALF.y * 2.0 > Player.HALF.y * 2.0 and Brute.HALF.x * 2.0 >= Player.HALF.x * 4.0, "the brute is taller than the digger and at least twice as wide")
	for seed_v in [7, 4242]:
		Game.contract = Balance.CONTRACTS[0].duplicate()
		Game.contract["seed"] = seed_v
		await _settle(t)
		Game.start_run()
		await _settle(t)
		await t._frames(5)
		var m0: Node = Game.current
		var cells: Array = m0.roamer_cells()
		var again: Array = m0.roamer_cells()
		var want := 0
		for n in Balance.BRUTES_PER_ZONE:
			want += int(n)
		var zones_ok := true
		var per_zone: Dictionary = {}
		var sp: Vector2i = m0.data["spawn"]
		for c: Vector2i in cells[0]:
			var z: int = m0.grid.get_stratum(c.x, c.y)
			per_zone[z] = int(per_zone.get(z, 0)) + 1
			if z == Balance.Z_DUST or absi(c.x - sp.x) + absi(c.y - sp.y) < Balance.BRUTE_MIN_SPAWN_DIST:
				zones_ok = false
		for z in per_zone:
			if int(per_zone[z]) > int(Balance.BRUTES_PER_ZONE[z]):
				zones_ok = false
		t.check(cells == again, "seed %d: brutes and fliers are placed the same way every time" % seed_v)
		t.check((cells[0] as Array).size() >= want - 1 and zones_ok, "seed %d: a brute in each zone below the Dustworks (%d of %d), none near the start" % [seed_v, (cells[0] as Array).size(), want])
		var fl_ok := (cells[1] as Array).size() <= Balance.FLIERS_PER_MAP
		for c: Vector2i in cells[1]:
			if not (m0.grid.get_stratum(c.x, c.y) in Balance.FLIER_ZONES):
				fl_ok = false
		t.check(fl_ok and (cells[1] as Array).size() >= 1, "seed %d: fliers are rare (%d) and keep to the zones below the Dustworks" % [seed_v, (cells[1] as Array).size()])
		var live_b := 0
		var live_f := 0
		for e in m0.enemies:
			if e is Brute:
				live_b += 1
			elif e is Flier and not (e is SporePod):
				live_f += 1
		t.check(live_b == (cells[0] as Array).size() and live_f == (cells[1] as Array).size(), "seed %d: they are in the mine" % seed_v)
	var mine: Node = Game.current
	var pl: Player = mine.player
	var g: TerrainGrid = mine.grid
	pl.invuln = 1e9
	var pc: Vector2i = g.world_to_cell(pl.global_position)
	var floor_it := func() -> void:
		for x in range(pc.x - 10, pc.x + 24):
			for y in range(pc.y - 6, pc.y + 4):
				if g.in_bounds(x, y):
					g.set_flag(x, y, Cell.F_PROTECTED, false)
					g.set_mat(x, y, Cell.AIR if y <= pc.y else Cell.HARD)
					g.set_water(x, y, 0)
	floor_it.call()
	await t._frames(3)
	var home := pl.global_position
	# --- the plate ---
	var br: Brute = mine.spawn_brute(Vector2i(pc.x + 5, pc.y))
	br.set_physics_process(false)
	br.facing = -1                      # plate toward the digger
	var front := br.global_position + Vector2(-40, 0)
	var back := br.global_position + Vector2(40, 0)
	var hp := br.hp
	br.last_hit = "drill"
	br.hit(40.0, front)
	t.check(is_equal_approx(hp - br.hp, 40.0 * Balance.BRUTE_PLATE), "the plate stops most of a drill hit from the front (%.0f of 40)" % (hp - br.hp))
	hp = br.hp
	br.last_hit = "drill"
	br.hit(40.0, back)
	t.check(is_equal_approx(hp - br.hp, 40.0), "a drill hit on its back does full damage")
	hp = br.hp
	br.last_hit = "charge"
	br.hit(40.0, front)
	t.check(is_equal_approx(hp - br.hp, 40.0 * Balance.BRUTE_PLATE), "the plate stops a blast from the front too")
	hp = br.hp
	br.last_hit = "gas"
	br.hit(10.0, front, false)
	t.check(is_equal_approx(hp - br.hp, 10.0), "a gas cloud gets past the plate")
	br.stun(1.2)
	t.check(br.state != Brute.S.STUNNED, "a blast's short shock does not stagger it")
	hp = br.hp
	br.crushed()
	t.check(is_equal_approx(hp - br.hp, Balance.BRUTE_RUBBLE_DAMAGE) and br.state == Brute.S.STUNNED, "falling rock ignores the plate and stuns it")
	hp = br.hp
	br.last_hit = "drill"
	br.hit(20.0, front)
	t.check(is_equal_approx(hp - br.hp, 20.0), "while it is stunned the plate is down")
	br.last_hit = "drill"
	br.hit(9999.0, back)
	t.check(br.state == Brute.S.DEAD and not mine.enemies.has(br), "it can be killed")
	await t._frames(30)
	# --- walking, turning, hitting ---
	var b2: Brute = mine.spawn_brute(Vector2i(pc.x + 4, pc.y))
	b2.facing = 1                        # looking away from the digger
	b2.charge_cd = 99.0
	await t._frames(4)
	t.check(b2.on_floor and absf(b2.global_position.y + Brute.HALF.y - (pc.y + 1) * 16.0) < 1.0, "it stands on the floor")
	var saw_turn := false
	for k in 120:
		await t._frames(1)
		if b2.state == Brute.S.TURN:
			saw_turn = true
		if b2.facing == -1:
			break
	t.check(saw_turn and b2.facing == -1, "it has to turn around to face you, and that takes a moment")
	pl.invuln = 0.0
	var php := pl.hp
	for k in 400:
		await t._frames(1)
		if pl.hp < php:
			break
	t.check(is_equal_approx(php - pl.hp, Balance.BRUTE_DAMAGE), "it walks up and shoves you with the plate (%.0f)" % (php - pl.hp))
	pl.invuln = 1e9
	pl.hp = pl.max_hp
	b2.queue_free()
	mine.enemies.erase(b2)
	pl.global_position = home
	pl.velocity = Vector2.ZERO
	floor_it.call()
	await t._frames(3)
	# --- a crawler whose ground is gone falls, and a long drop hurts ---
	for x in range(pc.x + 10, pc.x + 19):
		for y in range(pc.y - 9, pc.y + 1):
			g.set_flag(x, y, Cell.F_PROTECTED, false)
			g.set_mat(x, y, Cell.AIR)                   # open air all round, ceiling included
	g.set_mat(pc.x + 14, pc.y - 5, Cell.HARD)           # one block to cling to, high up
	var fc: Crawler = mine.spawn_crawler(Vector2i(pc.x + 14, pc.y - 6))
	await t._frames(3)
	var fhp := fc.hp
	t.check(fc.cell.y == pc.y - 6, "a crawler clings to its rock")
	g.set_mat(pc.x + 14, pc.y - 5, Cell.AIR)            # the rock is dug away
	var landed := false
	for k in 60:
		await t._frames(1)
		if is_instance_valid(fc) and fc.cell == Vector2i(pc.x + 14, pc.y):
			landed = true
			break
	await t._frames(3)
	t.check(landed, "with its rock gone a crawler falls straight to the floor instead of hanging in the air")
	t.check(is_instance_valid(fc) and is_equal_approx(fhp - fc.hp, float(6 - Balance.CRAWLER_FALL_SAFE + 1) * Balance.CRAWLER_FALL_DAMAGE), "a six-cell drop hurts it (%.0f)" % (fhp - fc.hp))
	if is_instance_valid(fc):
		fc.queue_free()
		mine.enemies.erase(fc)
	# --- its charge: through sediment, but basalt stuns it ---
	for y in range(pc.y - 5, pc.y + 1):
		g.set_mat(pc.x + 9, y, Cell.SOFT)
		g.set_mat(pc.x + 14, y, Cell.HARD)
		g.set_mat(pc.x + 15, y, Cell.HARD)
	var b3: Brute = mine.spawn_brute(Vector2i(pc.x + 4, pc.y))
	b3.facing = 1
	await t._frames(4)
	b3.state = Brute.S.CHARGE
	b3.state_t = 0.0
	b3.forget_t = 0.0
	for k in 200:
		await t._frames(1)
		if b3.state == Brute.S.STUNNED:
			break
		if b3.state != Brute.S.CHARGE:
			b3.state = Brute.S.CHARGE       # keep it charging until it meets the wall
			b3.state_t = 0.0
	t.check(not g.is_solid(pc.x + 9, pc.y) and not g.is_solid(pc.x + 9, pc.y - 1), "a charging brute goes straight through sediment")
	t.check(b3.state == Brute.S.STUNNED and b3.slams == 1 and g.get_mat(pc.x + 14, pc.y) == Cell.HARD, "charging into basalt stuns it and leaves the rock standing")
	t.check(not b3.plate_blocks(b3.global_position + Vector2(40, 0)), "after a slam the plate is down")
	b3.queue_free()
	mine.enemies.erase(b3)
	floor_it.call()
	await t._frames(3)
	# --- ledges and soft walls on the way to you ---
	for x in range(pc.x + 4, pc.x + 7):
		g.set_mat(x, pc.y, Cell.HARD)       # a one-cell step up
	for y in range(pc.y - 5, pc.y + 1):
		g.set_mat(pc.x + 3, y, Cell.SOFT)   # and a sediment wall at the far end of the ledge
	var b4: Brute = mine.spawn_brute(Vector2i(pc.x + 10, pc.y))
	b4.facing = -1
	b4.charge_cd = 99.0
	b4.attack_cd = 99.0
	var top_y := 9999.0
	for k in 900:
		await t._frames(1)
		b4.target_x = pl.global_position.x
		b4.forget_t = 5.0
		if b4.state == Brute.S.IDLE:
			b4.state = Brute.S.HUNT
		top_y = minf(top_y, b4.global_position.y)
		if b4.global_position.x < (pc.x + 3) * 16.0:
			break
	t.check(top_y <= pc.y * 16.0 - Brute.HALF.y + 1.0, "it steps up a one-cell ledge")
	t.check(not g.is_solid(pc.x + 3, pc.y - 1) and not g.is_solid(pc.x + 3, pc.y - 2) and b4.global_position.x < (pc.x + 4) * 16.0, "it smashes through a sediment wall to reach you (x %.0f, wall at %d)" % [b4.global_position.x, (pc.x + 3) * 16])
	b4.queue_free()
	mine.enemies.erase(b4)
	floor_it.call()
	await t._frames(3)
	# --- flier ---
	for x in range(pc.x - 10, pc.x + 24):
		for y in range(pc.y - 12, pc.y - 5):
			g.set_mat(x, y, Cell.AIR)
	var air := Vector2i(pc.x + 6, pc.y - 6)
	var fl: Flier = mine.spawn_flier(air)
	var cr: Crawler = mine.spawn_crawler(Vector2i(pc.x + 12, pc.y))
	await t._frames(2)
	t.check(fl.walkable(air) and not cr.walkable(air), "a flier can cross open air where a crawler cannot go")
	t.check(is_equal_approx(fl.max_hp, Balance.FLIER_HP) and fl.max_hp < cr.max_hp, "a flier is fragile")
	cr.queue_free()
	mine.enemies.erase(cr)
	fl._begin_tunnel()
	t.check(fl.state != Crawler.S.TUNNEL, "a flier never tunnels")
	pl.invuln = 0.0
	php = pl.hp
	for k in 600:
		await t._frames(1)
		if pl.hp < php:
			break
	t.check(is_equal_approx(php - pl.hp, Balance.FLIER_DAMAGE), "a flier comes down through the open air and bites (%.0f)" % (php - pl.hp))
	pl.invuln = 1e9
	fl.last_hit = "drill"
	fl.hit(Balance.FLIER_HP + 1.0, pl.global_position)
	t.check(fl.state == Crawler.S.DEAD, "one good drill hit kills a flier")
	await _settle(t)
	Game.goto("title", true)
	await _settle(t)


## 0.16.0 enemies: the burrower, the bomb-eater and the spore pod.
static func roamers_b(t: Node) -> void:
	t.section("burrower, bomb-eater and spore pod")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(5)
	var mine: Node = Game.current
	var pl: Player = mine.player
	var g: TerrainGrid = mine.grid
	var cells: Array = mine.roamer_cells()
	var bur_want := 0
	for n in Balance.BURROWERS_PER_ZONE:
		bur_want += int(n)
	var place_ok := cells.size() >= 5 and (cells[2] as Array).size() >= bur_want - 1 and (cells[3] as Array).size() <= Balance.EATERS_PER_MAP and (cells[4] as Array).size() <= Balance.SPORES_PER_MAP
	for c: Vector2i in cells[2]:
		if int(Balance.BURROWERS_PER_ZONE[g.get_stratum(c.x, c.y)]) <= 0:
			place_ok = false
	for c: Vector2i in cells[4]:
		if g.get_stratum(c.x, c.y) != Balance.SPORE_ZONE:
			place_ok = false
	t.check(place_ok, "burrowers keep to their zones (%d), the bomb-eater is rare (%d), spore pods live in the Spore Veins (%d)" % [(cells[2] as Array).size(), (cells[3] as Array).size(), (cells[4] as Array).size()])
	var kinds := {"b": 0, "e": 0, "s": 0}
	for e in mine.enemies:
		if e is Burrower:
			kinds["b"] += 1
		elif e is BombEater:
			kinds["e"] += 1
		elif e is SporePod:
			kinds["s"] += 1
	t.check(kinds["b"] == (cells[2] as Array).size() and kinds["e"] == (cells[3] as Array).size() and kinds["s"] == (cells[4] as Array).size(), "they are in the mine")
	# clear the stage: only the enemies this test makes
	for e in mine.enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	mine.enemies.clear()
	pl.invuln = 1e9
	var pc: Vector2i = g.world_to_cell(pl.global_position)
	var floor_it := func() -> void:
		for x in range(pc.x - 10, pc.x + 26):
			for y in range(pc.y - 8, pc.y + 4):
				if g.in_bounds(x, y):
					g.set_flag(x, y, Cell.F_PROTECTED, false)
					g.set_mat(x, y, Cell.AIR if y <= pc.y else Cell.HARD)
					g.ore[g.idx(x, y)] = 0
					g.set_water(x, y, 0)
	floor_it.call()
	await t._frames(3)
	var home := pl.global_position
	# --- burrower ---
	for x in range(pc.x + 6, pc.x + 11):
		for y in range(pc.y - 8, pc.y + 1):
			g.set_mat(x, y, Cell.HARD)          # a basalt wall, five cells thick
	var bw: Burrower = mine.spawn_kin("burrower", Vector2i(pc.x + 13, pc.y))
	var cw: Crawler = mine.spawn_crawler(Vector2i(pc.x + 15, pc.y))
	await t._frames(2)
	t.check(bw.diggable(Vector2i(pc.x + 10, pc.y)) and bw.walkable(Vector2i(pc.x + 10, pc.y)) and not cw.walkable(Vector2i(pc.x + 10, pc.y)), "basalt is a way through for a burrower, not for a crawler")
	g.set_mat(pc.x + 20, pc.y - 3, Cell.ALLOY)
	g.set_mat(pc.x + 21, pc.y - 3, Cell.SOFT)
	g.ore[g.idx(pc.x + 21, pc.y - 3)] = Cell.ORE_COBALT
	g.set_mat(pc.x + 22, pc.y - 3, Cell.SOFT)
	g.set_flag(pc.x + 22, pc.y - 3, Cell.F_PROTECTED)
	g.set_mat(pc.x + 23, pc.y - 5, Cell.SOFT)
	g.set_mat(pc.x + 24, pc.y - 5, Cell.AIR)
	g.set_water(pc.x + 24, pc.y - 5, Balance.WATER_MAX)
	t.check(not bw.diggable(Vector2i(pc.x + 20, pc.y - 3)) and not bw.diggable(Vector2i(pc.x + 21, pc.y - 3)) and not bw.diggable(Vector2i(pc.x + 22, pc.y - 3)), "it never digs alloy, ore or protected rock")
	t.check(not bw.diggable(Vector2i(pc.x + 23, pc.y - 5)), "it never digs rock that is holding back water")
	g.set_water(pc.x + 24, pc.y - 5, 0)
	t.check(not bw._sees_player() and bw.state == Crawler.S.PATROL, "it is blind: it does not notice you 13 cells away")
	mine.noise(home, 10.0)
	t.check(bw.state == Crawler.S.INVESTIGATE and cw.state == Crawler.S.PATROL, "it hears drilling from twice as far as a crawler")
	cw.queue_free()
	mine.enemies.erase(cw)
	pl.invuln = 0.0
	var php := pl.hp
	var in_rock := 0
	for k in 1500:
		await t._frames(1)
		if k % 30 == 0:
			mine.noise(home, 10.0)              # you keep drilling
		if g.is_solid(bw.cell.x, bw.cell.y) or g.is_solid(bw.next_cell.x, bw.next_cell.y):
			in_rock += 1
		if pl.hp < php:
			break
	var tunnel := 0
	for x in range(pc.x + 6, pc.x + 11):
		if not g.is_solid(x, pc.y):
			tunnel += 1
	var holes := ""
	for y in range(pc.y - 8, pc.y + 1):
		for x in range(pc.x + 6, pc.x + 11):
			if not g.is_solid(x, y):
				holes += "(%d,%d)" % [x - pc.x, y - pc.y]
	t.check(bw.dug >= 5 and tunnel == 5, "it chews straight through the basalt wall toward the noise (%d cells; open: %s)" % [bw.dug, holes])
	t.check(in_rock == 0, "it never moves into rock it has not chewed out (%d frames inside rock)" % in_rock)
	t.check(is_equal_approx(php - pl.hp, Balance.BURROWER_DAMAGE), "and bites when it gets to you (%.0f)" % (php - pl.hp))
	pl.invuln = 1e9
	pl.hp = pl.max_hp
	t.check(bw._sees_player(), "this close it feels you without eyes")
	bw.queue_free()
	mine.enemies.erase(bw)
	floor_it.call()
	await t._frames(3)
	# --- bomb-eater ---
	var pm: Hazards.ProxMine = mine.spawn_mine(home + Vector2(6 * 16, Player.HALF.y - 5.0))
	await t._frames(int((Balance.MINE_ARM + 0.3) * 60.0))
	t.check(pm.armed, "a mine is armed and waiting")
	var be: BombEater = mine.spawn_kin("eater", Vector2i(pc.x + 12, pc.y))
	for k in 900:
		await t._frames(1)
		if be.carrying:
			break
	t.check(be.carrying and be.eaten == 1 and not is_instance_valid(pm), "a bomb-eater walks to the mine and swallows it; the mine does not go off")
	pl.invuln = 0.0
	php = pl.hp
	for k in 900:
		await t._frames(1)
		if not is_instance_valid(be) or be.state == Crawler.S.DEAD:
			break
	await t._frames(4)
	t.check(pl.hp < php - Balance.EATER_DAMAGE - 1.0, "then it runs at you and blows beside you (%.0f damage)" % (php - pl.hp))
	pl.invuln = 1e9
	pl.hp = pl.max_hp
	floor_it.call()
	pl.global_position = home
	pl.velocity = Vector2.ZERO
	await t._frames(3)
	# a waiting remote charge is food too; killed with a bomb inside, it blows where it falls
	var rc: Hazards.Charge = mine.spawn_charge(home + Vector2(7 * 16, -8), Vector2.ZERO, "remote")
	await t._frames(40)
	var be2: BombEater = mine.spawn_kin("eater", Vector2i(pc.x + 12, pc.y))
	for k in 900:
		await t._frames(1)
		if be2.carrying:
			break
	t.check(be2.carrying and not is_instance_valid(rc) and mine.remotes_out() == 0, "it eats a waiting remote charge as well")
	be2.set_physics_process(false)
	var bc: Vector2i = g.world_to_cell(be2.global_position)
	g.set_mat(bc.x + 1, bc.y - 2, Cell.SOFT)
	be2.last_hit = "rubble"
	be2.hit(999.0, be2.global_position, false)
	await t._frames(4)
	t.check(be2.state == Crawler.S.DEAD and not g.is_solid(bc.x + 1, bc.y - 2), "killed with a bomb inside, it blows where it falls")
	floor_it.call()
	pl.global_position = home
	pl.velocity = Vector2.ZERO
	await t._frames(3)
	# --- spore pod ---
	var sp: SporePod = mine.spawn_kin("spore", Vector2i(pc.x + 6, pc.y - 4))
	await t._frames(2)
	t.check(is_zero_approx(sp.bite) and sp.walkable(Vector2i(pc.x + 6, pc.y - 4)), "a spore pod floats in open air and has no bite")
	var vents0: int = mine.gas.vents.size() + mine.gas.clouds.size()
	pl.invuln = 0.0
	php = pl.hp
	var swelled := false
	for k in 1200:
		await t._frames(1)
		if is_instance_valid(sp) and sp.swell_t >= 0.0:
			swelled = true
		if not is_instance_valid(sp) or sp.state == Crawler.S.DEAD:
			break
	t.check(swelled and sp.burst == "gas" and mine.gas.vents.size() + mine.gas.clouds.size() == vents0 + 1, "it drifts to you, swells and bursts into gas")
	t.check(is_equal_approx(pl.hp, php), "the burst itself does not hurt: the gas does, if you stay")
	pl.invuln = 1e9
	mine.gas.vents.clear()
	mine.gas.clouds.clear()
	var sp2: SporePod = mine.spawn_kin("spore", Vector2i(pc.x + 12, pc.y - 4))
	sp2.set_physics_process(false)
	sp2.last_hit = "drill"
	sp2.hit(99.0, home)
	t.check(sp2.burst == "gas" and mine.gas.vents.size() == 1, "drilling one bursts it into gas too")
	mine.gas.vents.clear()
	var sp3: SporePod = mine.spawn_kin("spore", Vector2i(pc.x + 14, pc.y - 4))
	var near: Crawler = mine.spawn_crawler(Vector2i(pc.x + 15, pc.y - 4))
	sp3.set_physics_process(false)
	near.set_physics_process(false)
	var chp := near.hp
	sp3.last_hit = "charge"
	sp3.hit(99.0, sp3.global_position + Vector2(20, 0))
	await t._frames(3)
	t.check(sp3.burst == "fire" and mine.gas.vents.is_empty(), "a blast sets its gas alight at once: a fireball, not a cloud")
	t.check(not is_instance_valid(near) or near.hp < chp or near.state == Crawler.S.DEAD, "the fireball burns the crawler next to it")
	await _settle(t)
	Game.goto("title", true)
	await _settle(t)


## 0.17.0 enemies: the eel (water) and the slag salamander (lava).
static func roamers_c(t: Node) -> void:
	t.section("eel and slag salamander")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(5)
	var mine: Node = Game.current
	var pl: Player = mine.player
	var g: TerrainGrid = mine.grid
	var cells: Array = mine.roamer_cells()
	var eels_ok := cells.size() == 7 and (cells[5] as Array).size() >= 1 and (cells[5] as Array).size() <= Balance.EELS_PER_MAP + Balance.EELS_ELSEWHERE
	for c: Vector2i in cells[5]:
		if g.get_water(c.x, c.y) < Balance.WATER_MAX / 2:
			eels_ok = false
	t.check(eels_ok, "eels start in deep water (%d on this map)" % (cells[5] as Array).size())
	t.check((cells[6] as Array).is_empty(), "no slag salamanders in the main mine (it has no lava)")
	for e in mine.enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	mine.enemies.clear()
	pl.invuln = 1e9
	var pc: Vector2i = g.world_to_cell(pl.global_position)
	# a flat floor with a walled basin: x+5..x+10, three cells deep
	var pool: Array[Vector2i] = []
	var stage_it := func(fill: bool) -> void:
		pool.clear()
		for x in range(pc.x - 10, pc.x + 26):
			for y in range(pc.y - 8, pc.y + 6):
				if g.in_bounds(x, y):
					g.set_flag(x, y, Cell.F_PROTECTED, false)
					g.set_mat(x, y, Cell.AIR if y <= pc.y else Cell.HARD)
					g.ore[g.idx(x, y)] = 0
					g.set_water(x, y, 0)
					g.set_lava(x, y, 0)
		for x in range(pc.x + 5, pc.x + 11):
			for y in range(pc.y + 1, pc.y + 4):
				g.set_mat(x, y, Cell.AIR)
				pool.append(Vector2i(x, y))
				if fill:
					g.set_water(x, y, Balance.WATER_MAX)
	stage_it.call(true)
	await t._frames(5)
	var home := pl.global_position
	# --- eel ---
	var mid := Vector2i(pc.x + 7, pc.y + 2)
	var eel: Eel = mine.spawn_kin("eel", mid)
	var cr: Crawler = mine.spawn_crawler(Vector2i(pc.x + 9, pc.y + 3))
	await t._frames(3)
	t.check(eel.wet() and eel.walkable(mid) and not cr.walkable(mid), "an eel swims through open water where a crawler cannot go")
	t.check(is_equal_approx(eel.speed_chase, float(Balance.EEL_SPEED_WET[1])) and is_equal_approx(eel.bite, Balance.EEL_DAMAGE_WET), "in water it is fast and bites hard")
	var ehp := eel.hp
	var chp := cr.hp
	await t._frames(90)
	t.check(is_equal_approx(eel.hp, ehp) and (not is_instance_valid(cr) or cr.hp < chp), "water does not hurt it (a crawler in the same pool is drowning)")
	if is_instance_valid(cr):
		cr.queue_free()
		mine.enemies.erase(cr)
	# it bites you in its pool
	pl.global_position = g.cell_center(Vector2i(pc.x + 9, pc.y + 2))
	pl.velocity = Vector2.ZERO
	pl.set_physics_process(false)
	pl.invuln = 0.0
	var php := pl.hp
	for k in 600:
		await t._frames(1)
		if pl.hp < php:
			break
	t.check(is_equal_approx(php - pl.hp, Balance.EEL_DAMAGE_WET), "it comes for you through the water and bites (%.0f)" % (php - pl.hp))
	pl.invuln = 1e9
	pl.hp = pl.max_hp
	pl.set_physics_process(true)
	pl.global_position = home
	pl.velocity = Vector2.ZERO
	# drain the pool: it is stranded
	for c in pool:
		g.set_water(c.x, c.y, 0)
	await t._frames(20)
	t.check(not eel.wet() and is_equal_approx(eel.speed_chase, float(Balance.EEL_SPEED_DRY[1])) and is_equal_approx(eel.bite, Balance.EEL_DAMAGE_DRY), "with its pool drained it is slow and bites weakly")
	ehp = eel.hp
	eel.last_hit = "drill"
	eel.hit(5.0, home)
	t.check(is_equal_approx(ehp - eel.hp, 5.0 * Balance.EEL_DRY_VULN), "out of water it takes double damage")
	var kills0 := int(Game.run.get("terrain_kills", 0))
	for k in int((Balance.EEL_DRY_LIMIT + Balance.EEL_HP / Balance.EEL_DRY_DPS + 3.0) * 60.0):
		await t._frames(1)
		if not is_instance_valid(eel) or eel.state == Crawler.S.DEAD:
			break
	t.check(not is_instance_valid(eel) or eel.state == Crawler.S.DEAD, "left dry, it dries out and dies")
	t.check(int(Game.run.get("terrain_kills", 0)) == kills0 + 1, "draining its pool counts as a terrain kill")
	# it turns back for its pool when it has been out too long
	stage_it.call(true)
	await t._frames(5)
	var eel2: Eel = mine.spawn_kin("eel", mid)
	await t._frames(3)
	eel2.cell = Vector2i(pc.x + 14, pc.y)
	eel2.next_cell = eel2.cell
	eel2.move_t = 1.0
	eel2.global_position = g.cell_center(eel2.cell)
	eel2.path.clear()
	eel2.dry_t = Balance.EEL_DRY_LIMIT + 0.1
	for k in 900:
		await t._frames(1)
		if not is_instance_valid(eel2) or eel2.wet():
			break
	t.check(is_instance_valid(eel2) and eel2.wet() and eel2.state != Crawler.S.DEAD, "out too long, it turns back and makes it to its pool")
	if is_instance_valid(eel2):
		eel2.queue_free()
		mine.enemies.erase(eel2)
	# --- slag salamander (lava set up by hand: the main mine has no lava sim) ---
	stage_it.call(false)
	mine.steam = SteamField.new(g)
	mine.lava = LavaSim.new(g, mine.water, mine.steam)
	mine.lava.occupied = mine._cell_occupied
	for c in pool:
		g.set_lava(c.x, c.y, Balance.LAVA_MAX)
	await t._frames(3)
	var sl: Slag = mine.spawn_kin("slag", mid)
	await t._frames(3)
	t.check(sl.wet() and sl.walkable(mid), "a slag salamander swims in lava")
	var shp := sl.hp
	await t._frames(90)
	sl.last_hit = "lava"
	sl.hit(30.0, sl.global_position, false)
	t.check(is_equal_approx(sl.hp, shp), "lava does not hurt it")
	sl.set_physics_process(false)
	sl.cell = Vector2i(pc.x + 14, pc.y)
	sl.next_cell = sl.cell
	sl.global_position = g.cell_center(sl.cell)
	sl.dry_t = Balance.SLAG_COOL + 1.0
	sl._tune()
	t.check(is_equal_approx(sl.speed_chase, float(Balance.SLAG_SPEED_COLD[1])) and sl.parched(), "out of lava for %d seconds it cools and slows" % int(Balance.SLAG_COOL))
	# water sets it into stone, with aetherite in it
	var sc := sl.cell
	g.set_water(sc.x, sc.y, Balance.SLAG_QUENCH_WATER)
	kills0 = int(Game.run.get("terrain_kills", 0))
	sl.set_physics_process(true)
	await t._frames(3)
	t.check(sl.quenched and g.get_mat(sc.x, sc.y) == Cell.HARD and g.get_ore(sc.x, sc.y) == Cell.ORE_AETHER, "a puddle sets it into a block of rock with aetherite in it")
	t.check(int(Game.run.get("terrain_kills", 0)) == kills0 + 1, "quenching it counts as a terrain kill")
	var res: Dictionary = mine.damage_cell(sc, 999.0, 3, true, "drill")
	t.check(res["broken"] and int(res["ore"]) == Cell.ORE_AETHER, "drilling the block pays out the aetherite")
	# cryo does the same
	g.set_water(sc.x, sc.y, 0)
	var sl2: Slag = mine.spawn_kin("slag", Vector2i(pc.x + 16, pc.y))
	sl2.set_physics_process(false)
	mine.cryo_burst(sl2.global_position)
	t.check(sl2.quenched and g.get_mat(pc.x + 16, pc.y) == Cell.HARD, "a cryo canister sets it into stone too")
	# never a block on top of the digger
	var sl3: Slag = mine.spawn_kin("slag", g.world_to_cell(pl.global_position))
	sl3.set_physics_process(false)
	var here := sl3.cell
	t.check(not sl3.quench() and not g.is_solid(here.x, here.y) and sl3.state == Crawler.S.DEAD, "quenched in your own cell it crumbles instead of walling you in")
	for c in pool:
		g.set_lava(c.x, c.y, 0)
	mine.lava = null
	mine.steam = null
	# --- in The First Civilization ---
	Game.descend(100.0, Balance.MAP_H)
	await _settle(t)
	await t._frames(10)
	var deep: Node = Game.current
	var dcells: Array = deep.roamer_cells()
	var slag_ok: bool = deep.stage == "deep" and (dcells[6] as Array).size() >= 1 and (dcells[6] as Array).size() <= Balance.DEEP_SLAGS
	for c: Vector2i in dcells[6]:
		if deep.grid.get_lava(c.x, c.y) < Balance.LAVA_MAX / 2:
			slag_ok = false
	var live := 0
	for e in deep.enemies:
		if e is Slag:
			live += 1
	t.check(slag_ok and live == (dcells[6] as Array).size(), "The First Civilization has slag salamanders, each starting in lava (%d)" % live)
	await _settle(t)
	Game.goto("title", true)
	await _settle(t)


## 0.17.1: a droplet caught inside a sand pile must not hang there.
static func drops_on_sand(t: Node) -> void:
	t.section("water droplets and sand piles")
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(5)
	var mine: Node = Game.current
	var g: TerrainGrid = mine.grid
	var w: WaterSim = mine.water
	var pc: Vector2i = g.world_to_cell(mine.player.global_position)
	for x in range(pc.x + 3, pc.x + 12):
		for y in range(pc.y - 6, pc.y + 1):
			g.set_mat(x, y, Cell.AIR)
			g.set_water(x, y, 0)
			g.set_sand(x, y, 0)
		g.set_mat(x, pc.y + 1, Cell.HARD)
	for y in range(pc.y - 6, pc.y + 2):
		g.set_mat(pc.x + 2, y, Cell.HARD)
		g.set_mat(pc.x + 12, y, Cell.HARD)
	# a pile: three cells, the middle one full, with droplets caught inside it
	var mid := Vector2i(pc.x + 7, pc.y)
	g.set_sand(mid.x - 1, mid.y, Balance.SAND_MAX / 2)
	g.set_sand(mid.x, mid.y, Balance.SAND_MAX)
	g.set_sand(mid.x + 1, mid.y, Balance.SAND_MAX / 2)
	await t._frames(2)
	var vol := 0
	for c in [mid, Vector2i(mid.x - 1, mid.y), Vector2i(mid.x + 1, mid.y), mid]:
		w.drop_pos.append(g.cell_center(c) + Vector2(0, -5))
		w.drop_vel.append(Vector2.ZERO)
		w.drop_vol.append(Balance.WATER_DROP_UNITS)
		w.drop_src.append(g.idx(c.x, c.y))
		vol += Balance.WATER_DROP_UNITS
	var lost0: int = w.lost
	for k in 240:
		await t._frames(1)
		if w.drop_count() == 0:
			break
	t.check(w.drop_count() == 0, "droplets caught in a sand pile do not hang there (%d left)" % w.drop_count())
	var held := 0
	for x in range(pc.x + 3, pc.x + 12):
		for y in range(pc.y - 6, pc.y + 1):
			held += g.get_water(x, y)
	t.check(held == vol and w.lost == lost0, "their water runs off the pile and none of it is lost (%d of %d)" % [held, vol])
	await _settle(t)
	Game.goto("title", true)
	await _settle(t)


## 0.18.0: the performance recorder.
static func perf(t: Node) -> void:
	t.section("performance recorder")
	var keep: bool = bool(Settings.get_value("perf_record"))
	Settings.values["perf_record"] = false
	Perf.last_report = ""
	Game.contract = Balance.CONTRACTS[0].duplicate()
	Game.contract["seed"] = 7
	await _settle(t)
	Game.start_run()
	await _settle(t)
	await t._frames(30)
	t.check(not Perf.active and not Perf.has_report(), "nothing is recorded unless the setting is on")
	Game.goto("title", true)
	await _settle(t)
	Settings.values["perf_record"] = true
	Game.start_run()
	await _settle(t)
	t.check(Perf.active, "with the setting on, a dive is recorded")
	var mine: Node = Game.current
	for k in 2000:
		await t._frames(1)
		if Perf.frames >= 200 and Perf.seconds >= Perf.INTERVAL * 2.0 + 0.2:
			break
	t.check(Perf.rows.size() >= 2 and Perf.frames >= 200, "it keeps a timeline (%d rows in %.1f s)" % [Perf.rows.size(), Perf.seconds])
	t.check(float(Perf._sys_total["water"]) > 0.0, "it times the water update")
	t.check(Perf.copy_report(), "a report can be copied in the middle of a dive")
	t.check(is_instance_valid(mine) and mine.grid != null, "recording does not disturb the dive")
	Game.goto("title", true)
	await _settle(t)
	var rep: String = Perf.last_report
	var ok := not Perf.active and rep.begins_with("RUIN DIGGER PERFORMANCE REPORT") and rep.ends_with("END OF REPORT")
	for part in ["device:", "SUMMARY", "fps: average", "SLOW FRAMES", "TIMELINE", "t_s,zone,fps", str(ProjectSettings.get_setting("application/config/version"))]:
		if not rep.contains(part):
			ok = false
	t.check(ok, "leaving the dive finishes the report: device, summary, slow frames and timeline (%d characters)" % rep.length())
	t.check(Perf.last_path != "" and FileAccess.file_exists(Perf.last_path), "the report is also saved as a text file")
	t.check(rep.length() < 120000, "the report is small enough to paste")
	Settings.values["perf_record"] = keep


## 0.19.0: missions and The Sunken Lake.
static func missions(t: Node) -> void:
	t.section("missions: the sunken lake map")
	for m: Dictionary in Balance.MISSIONS:
		var t0 := Time.get_ticks_msec()
		var d: Dictionary = LakeGenerator.new().generate(m)
		var ms := Time.get_ticks_msec() - t0
		var g: TerrainGrid = d["grid"]
		var need := float(d["bed_capacity"]) * float(d["bed_target"])
		if OS.has_environment("RD_DBG"):
			print("LAKE %s gen %d ms settle %d dig %.0f cap %d start %d above %d (x%.2f) eels %d green %d ore %d" % [m["id"], ms, d["settle_steps"], d["dig_to_lift_s"], d["bed_capacity"], d["bed_start"], d["water_above"], float(d["water_above"]) / need, d["eels"], d["greenery"], d["ore_cells"]])
			if m["id"] == "lake":
				for y in g.h:
					var row := ""
					for x in g.w:
						var mt := g.get_mat(x, y)
						var w := g.get_water(x, y)
						row += "B" if mt == Cell.BEDROCK else ("#" if mt == Cell.HARD else ("+" if mt == Cell.SOFT else ("H" if mt == Cell.LADDER else ("~" if w >= 32 else ("," if w > 0 else " ")))))
					print(row)
		t.check(bool(d["valid"]) and float(d["dig_to_lift_s"]) >= 0.0, "%s: the lift by the lake bed can be reached with starting gear (%.0f s of digging)" % [m["id"], d["dig_to_lift_s"]])
		t.check(float(d["water_above"]) >= need * 1.3 and float(d["water_above"]) <= need * 2.4, "%s: there is water to spare above the bed, but not endless (%.1f times what the goal needs)" % [m["id"], float(d["water_above"]) / need])
		t.check(float(d["bed_start"]) < need * 0.25, "%s: the bed starts nearly dry (%d%% full)" % [m["id"], int(100.0 * float(d["bed_start"]) / float(d["bed_capacity"]))])
		var d2: Dictionary = LakeGenerator.new().generate(m)
		t.check(hash((d2["grid"] as TerrainGrid).mat) == hash(g.mat) and hash((d2["grid"] as TerrainGrid).water) == hash(g.water), "%s: the map is the same every time" % m["id"])
		t.check(ms < 4000, "%s: it builds quickly (%d ms)" % [m["id"], ms])

	# --- the mission, live ---
	t.section("missions: playing the sunken lake")
	var saved := Progress.to_dict()
	Progress.reset()
	t.check(Progress.mission_open("lake") and not Progress.mission_open("lake2"), "the first mission is open; the second is locked")
	t.check(Progress.mission_locks("lake2").size() == 2, "the second needs the first done and a depth reached (%s)" % str(Progress.mission_locks("lake2")))
	await _settle(t)
	t.check(Game.start_mission("lake"), "a mission starts from the terminal, free")
	await _settle(t)
	await t._frames(20)
	var mine: Node = Game.current
	t.check(mine.stage == "mission" and mine.data.has("bed") and Game.in_mission(), "it runs on the mission's own map")
	t.check(mine.relic == null and mine.descent == null, "no relic and no way down to The First Civilization")
	var eels := 0
	var others := 0
	for e in mine.enemies:
		if e is Eel:
			eels += 1
		else:
			others += 1
	t.check(eels >= 1 and others == 0, "only the mission's own inhabitants: %d eels, nothing else" % eels)
	var greens := 0
	for n in mine.entity_root.get_children():
		if n is Entities.Greenery:
			greens += 1
	t.check(greens >= 4, "there is greenery by the water (%d patches)" % greens)
	var locked: Entities.Lift = null
	for l in mine.lifts:
		if l.locked:
			locked = l
	t.check(locked != null and not locked.active, "the lift by the lake bed has no power yet")
	var pv: float = mine.pressure.value
	mine.noise(mine.player.global_position, 20.0)
	await t._frames(120)
	t.check(is_equal_approx(mine.pressure.value, pv) and is_zero_approx(pv), "the mine stays calm: no pressure in this mission")
	# wading through the film of water splashes
	var pl: Player = mine.player
	var g: TerrainGrid = mine.grid
	var fc := pl.feet_cell()
	for x in range(fc.x - 3, fc.x + 4):
		g.set_water(x, fc.y, 10)
	var w0 := pl.wade_steps
	pl.input_override = {"x": 1.0}
	await t._frames(60)
	pl.input_override = {"x": -1.0}
	await t._frames(60)
	pl.input_override = {}
	t.check(pl.wade_steps > w0, "walking through shallow water splashes (%d splashing steps)" % (pl.wade_steps - w0))
	# fill the bed: the goal is met and the lift powers up
	var bed: Rect2i = mine.data["bed"]
	for y in range(bed.position.y, bed.end.y):
		for x in range(bed.position.x, bed.end.x):
			if not g.is_solid(x, y):
				g.set_water(x, y, Balance.WATER_MAX)
	await t._frames(30)
	t.check(int(Game.run.get("mission_fill", 0)) >= int(round(float(mine.data["bed_target"]) * 100.0)), "the lake bed is measured as it fills (%d%%)" % int(Game.run.get("mission_fill", 0)))
	t.check(Game.mission_goal_met() and not locked.locked and locked.active, "filling it to the top powers up the lift")
	var lc: Vector2i = mine.data["mission_lift"]
	await t._frames(60)
	t.check(g.get_water(lc.x, lc.y) == 0 and g.get_water(lc.x, lc.y - 1) == 0, "with the bed full to the top, the lift stands dry in its alcove")
	var cr0 := Progress.credits
	pl.global_position = locked.global_position + Vector2(0, -14)
	mine.extract(locked)
	for k in 300:
		await t._frames(1)
		if Game.current_name == "results":
			break
	await _settle(t)
	t.check(Game.last_result.get("mission_won", false) and Progress.mission_done("lake"), "riding it out completes the mission")
	t.check(Progress.credits >= cr0 + int(Balance.mission("lake")["reward"]), "and pays its reward (+%d CR)" % (Progress.credits - cr0))
	t.check(Progress.mission_locks("lake2").size() == 1, "completing it opens the way to the next one (depth still needed)")
	Progress.stats["best_depth"] = 200
	t.check(Progress.mission_open("lake2"), "with the depth reached, the next mission opens")
	var d := Progress.to_dict()
	Progress.reset()
	Progress.from_dict(d)
	t.check(Progress.mission_done("lake"), "completed missions are saved")
	Progress.from_dict(saved)
	Game.goto("title", true)
	await _settle(t)
