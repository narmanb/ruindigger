extends RefCounted
## Behavioral fixtures for the expansion. All water comes from finite reservoirs.

static func basin(width: int = 30, height: int = 20) -> TerrainGrid:
	var g := TerrainGrid.new(width, height)
	for y in height:
		for x in width:
			g.put(x, y, Cell.BEDROCK if x == 0 or y == 0 or x == width - 1 or y == height - 1 else Cell.AIR)
	return g


static func reservoir(surface: int, width: int = 6, openings: int = 1) -> WaterSim:
	var g := basin(36, 22)
	for y in range(1, 21):
		for x in range(1, width + 3):
			g.put(x, y, Cell.BEDROCK)
	for y in range(surface, 14):
		for x in range(2, width + 2):
			g.put(x, y, Cell.AIR)
			g.set_water(x, y, 64)
	var sim := WaterSim.new(g)
	for k in openings:
		g.set_mat(width + 2, 13 - k, Cell.AIR)
	sim.wake_all()
	return sim


static func released(sim: WaterSim) -> int:
	var n := 0
	for v in sim.drop_vol:
		n += v
	return n


static func run(t: Node) -> void:
	t.section("water physics")
	var api: RefCounted = WaterSim.new(basin())
	t.check(api.has_method("sample_flow") and api.has_method("sample_contact"), "water exposes shared motion/contact queries")
	if not api.has_method("sample_flow"):
		return
	var g: TerrainGrid = api.grid
	for x in range(1, 29):
		g.set_water(x, 18, 64)
	api.wake_all()
	for k in 30:
		api.update(0.06)
	t.check(api.sample_flow(Vector2(88, 296)).length() < 0.1, "settled full pool produces no current")
	var tall := reservoir(3)
	var initial := tall.total()
	tall.step()
	var fast := 0.0
	for v in tall.drop_vel:
		fast = maxf(fast, v.x)
	t.check(fast > 120.0, "deep side breach launches horizontal water")
	t.check(tall.total() + tall.lost == initial, "pressure discharge conserves reservoir plus droplets")
	var shallow := reservoir(13)
	shallow.step()
	var mild := 0.0
	for v in shallow.drop_vel:
		mild = maxf(mild, v.x)
	t.check(fast > mild + 80.0, "deep head is stronger than a one-cell shallow pocket")
	var wide := reservoir(3, 6, 2)
	wide.step()
	t.check(released(wide) > released(tall), "widening a supplied opening releases more water (%d vs %d)" % [released(wide), released(tall)])
	var lake := reservoir(13, 24)
	lake.step()
	var lake_speed := 0.0
	for v in lake.drop_vel:
		lake_speed = maxf(lake_speed, v.x)
	t.check(lake_speed < 120.0, "a broad shallow lake does not become a high pressure jet")
	var point := Vector2(8 * 16 + 8, 13 * 16 + 8)
	t.check(tall.sample_flow(point).x > 15.0, "flow follows actual sideways discharge")
	t.check(tall.sample_contact(point + Vector2(0, -48), Vector2(5, 12)).length() < 0.1, "narrow jet cannot push a character above it")
	t.check(tall.sample_flow(Vector2(8 * 16 + 8, 9 * 16 + 8)).length() < 0.1, "intact wall masks current sampling")
	for k in 600:
		tall.update(0.06)
	t.check(tall.total() + tall.lost == initial, "long flood/landing cycle conserves accounted water (%d + %d vs %d)" % [tall.total(), tall.lost, initial])
	t.check(tall.drop_count() <= 900, "droplet count remains capped")
	t.check(tall.pressure.discharge == 0 and tall.sample_flow(point).length() < 1.0, "pressure and current fade after the reservoir head drains")
	var falling: RefCounted = WaterSim.new(basin())
	falling.grid.set_water(5, 3, 64)
	falling.wake_all()
	falling.step()
	var downward: Vector2 = falling.sample_flow(Vector2(88, 72))
	t.check(downward.y > 15.0 and absf(downward.x) < downward.y, "falling water records mainly downward momentum")
	var thin: RefCounted = WaterSim.new(basin())
	thin.drop_pos.append(Vector2(100, 100))
	thin.drop_vel.append(Vector2(0, 100))
	thin.drop_vol.append(1)
	thin.drop_src.append(0)
	thin.update_drops(1.0 / 60.0)
	t.check(thin.sample_contact(Vector2(100, 100), Vector2(5, 12)).length() < 3.0, "one sparse trickle has negligible body contact force")
	var capped := reservoir(3)
	for k in 899:
		capped.drop_pos.append(Vector2(300, 100))
		capped.drop_vel.append(Vector2.ZERO)
		capped.drop_vol.append(3)
		capped.drop_src.append(0)
	var capped_before := capped.total()
	capped.step()
	t.check(capped.drop_count() <= 900 and capped.total() == capped_before, "near-cap pressure emission uses only available slots without losing volume")
	var eq := basin()
	for y in range(10, 19):
		for x in range(1, 29):
			eq.set_water(x, y, 64)
	var still: RefCounted = WaterSim.new(eq)
	still.wake_all()
	for k in 8:
		still.update(0.06)
	t.check(still.sample_flow(Vector2(200, 280)).length() < 0.1, "equal submerged pools have no pressure differential")
	# A fast drop must collide with the first wall, even over a long frame.
	var barrier := basin()
	for y in range(1, 19):
		barrier.put(8, y, Cell.BEDROCK)
	var swept := WaterSim.new(barrier)
	swept.drop_pos.append(Vector2(100, 120))
	swept.drop_vel.append(Vector2(600, 0))
	swept.drop_vol.append(3)
	swept.drop_src.append(barrier.idx(6, 7))
	swept.update_drops(0.25)
	var beyond := 0
	for y in range(1, 19):
		for x in range(9, 29):
			beyond += barrier.get_water(x, y)
	for p in swept.drop_pos:
		if p.x > 144:
			beyond += 1
	t.check(beyond == 0 and swept.total() + swept.lost == 3, "swept droplets cannot tunnel or deposit through a solid barrier")


static func characters(t: Node) -> void:
	t.section("character currents")
	var player: Player = Player.new()
	var api: Node = player
	t.check(api.get("water_drift") != null, "player has a smoothed current response")
	if api.get("water_drift") == null:
		player.free()
		return
	var g := basin()
	var sim: RefCounted = WaterSim.new(g)
	player.grid = g
	player.water = sim
	player.position = Vector2(200, 200)
	player.input_override = {"x": 0.0}
	t.add_child(player)
	player.set_physics_process(false)
	for k in 30:
		player._physics_process(1.0 / 60.0)
	t.check(player.water_drift.length() < 0.1, "still water leaves player control unchanged")
	player.position = Vector2(200, 80)
	player.velocity = Vector2.ZERO
	for y in range(1, 19):
		for x in range(1, 29):
			g.set_water(x, y, 64)
			sim.motion.record(Vector2i(x, y), Vector2(160, 0), 1.0)
	for k in 30:
		player._physics_process(1.0 / 60.0)
	t.check(player.water_drift.x > 20.0 and player.velocity.x > 15.0, "strong horizontal current carries an idle swimmer (drift %s, velocity %s, pos %s)" % [player.water_drift, player.velocity, player.position])
	t.check(player.water_drift.length() <= 125.0, "current response is capped so input can resist it")
	player.input_override = {"x": -1.0}
	for k in 30:
		player._physics_process(1.0 / 60.0)
	t.check(player.velocity.x < 0.0, "swimming against an ordinary strong current retains control")
	player.queue_free()


static func props(t: Node) -> void:
	t.section("debris and buoyancy")
	t.check(ResourceLoader.exists("res://src/world/debris.gd"), "material debris and prop manager exists")
	if not ResourceLoader.exists("res://src/world/debris.gd"):
		return
	var g := basin()
	var sim: RefCounted = WaterSim.new(g)
	for y in range(1, 19):
		for x in range(1, 29):
			g.set_water(x, y, 64)
	var debris: Node2D = load("res://src/world/debris.gd").new()
	t.add_child(debris)
	debris.setup(g, sim, 7123)
	var wood: RigidBody2D = debris.spawn_prop("crate", Vector2(100, 100))
	var rock: RigidBody2D = debris.spawn_prop("stone", Vector2(150, 100))
	t.check(wood != null and rock != null, "props spawn in clear water")
	if wood == null or rock == null:
		debris.queue_free()
		return
	t.check(wood.fluid_acceleration().y < -100.0, "submerged wooden crate rises")
	t.check(rock.fluid_acceleration().y > 300.0, "heavy rock sinks")
	for y in range(1, 19):
		for x in range(1, 29):
			sim.motion.record(Vector2i(x, y), Vector2(140, 0), 1.0)
	t.check(wood.fluid_acceleration().x > rock.fluid_acceleration().x, "light objects respond more to the same current")
	t.check((wood.collision_layer & 2) == 0 and (wood.collision_mask & 2) == 0, "props collide with terrain and each other while allowing the miner through")
	var before := rock.linear_velocity
	debris.blast(Vector2(130, 100), 80.0)
	t.check(rock.linear_velocity.distance_to(before) > 1.0, "blast imparts momentum to heavy props")
	g.set_mat(12, 6, Cell.BEDROCK)
	t.check(debris.spawn_prop("crate", g.cell_center(Vector2i(12, 6))) == null, "props reject embedded spawn positions")
	for k in 180:
		debris.on_broken(Vector2i(5 + k % 10, 10), Cell.GAS, "drill")
	t.check(debris.fragments.is_empty(), "gas rupture leaves no persistent solids")
	for k in 500:
		debris.on_broken(Vector2i(5 + k % 10, 10), Cell.SOFT if k % 2 == 0 else Cell.HARD, "drill")
	t.check(debris.fragments.size() > 0 and debris.fragments.size() <= 96, "prolonged drilling produces restrained bounded fragments")
	for k in 80:
		debris.spawn_prop("canister", Vector2(50 + k % 20 * 16, 200))
	t.check(debris.props.size() <= 24, "meaningful physics body count stays bounded")
	debris.queue_free()


static func erosion(t: Node) -> void:
	t.section("flow erosion")
	t.check(ResourceLoader.exists("res://src/terrain/water_erosion.gd"), "sustained erosion system exists")
	if not ResourceLoader.exists("res://src/terrain/water_erosion.gd"):
		return
	var g := basin()
	var sim := WaterSim.new(g)
	for y in range(5, 10):
		for x in range(4, 14):
			g.set_water(x, y, 64)
	g.put(6, 8, Cell.SOFT, Cell.ORE_COPPER)
	g.put(8, 8, Cell.HARD)
	g.put(10, 8, Cell.SOFT)
	g.set_flag(10, 8, Cell.F_PROTECTED)
	g.put(12, 8, Cell.SOFT)
	g.set_flag(12, 8, 32) # generator's route-support water safeguard
	var rewards: Array[int] = [0]
	var damage := func(c: Vector2i, amount: float, tier: int, ignore: bool, source: String) -> Dictionary:
		var res := g.damage(c.x, c.y, amount, tier, ignore)
		if res.ore != 0:
			rewards[0] += 1
		return res
	var wear: RefCounted = load("res://src/terrain/water_erosion.gd").new(g, sim, damage)
	for k in 100:
		wear.update(0.12)
	t.check(g.hp_frac(6, 8) == 1.0, "calm submerged sediment never erodes")
	for k in 60:
		for x in [6, 8, 10, 12]:
			sim.motion.record(Vector2i(x, 7), Vector2(2, 0), 1.0)
		wear.update(0.12)
		sim.motion.advance(0.12)
	t.check(g.hp_frac(6, 8) == 1.0, "subthreshold trickle leaves terrain intact")
	for k in 4:
		sim.motion.record(Vector2i(6, 7), Vector2(140, 0), 1.0)
		wear.update(0.12)
	t.check(g.hp_frac(6, 8) == 1.0, "passing wave does not instantly damage terrain")
	for k in 100:
		for x in [6, 8, 10, 12]:
			sim.motion.record(Vector2i(x, 7), Vector2(140, 0), 1.0)
		wear.update(0.12)
		sim.motion.advance(0.12)
	t.check(g.get_mat(6, 8) == Cell.AIR, "sustained strong flow cuts exposed sediment")
	t.check(rewards[0] == 1, "erosion breakage awards an ore cell once")
	t.check(g.get_mat(8, 8) == Cell.HARD and g.hp_frac(8, 8) == 1.0, "basalt resists sustained erosion")
	t.check(g.hp_frac(10, 8) == 1.0 and g.hp_frac(12, 8) == 1.0, "protected terrain and route supports survive flow")
	t.check(wear.last_edits <= 4, "erosion bounds terrain edits per tick")
	var crowded := basin()
	var crowded_sim := WaterSim.new(crowded)
	for x in range(3, 28, 3):
		crowded.put(x, 8, Cell.SOFT)
	var crowded_damage := func(cell: Vector2i, amount: float, tier: int, ignore: bool, _source: String) -> Dictionary:
		return crowded.damage(cell.x, cell.y, amount, tier, ignore)
	var crowded_wear: RefCounted = load("res://src/terrain/water_erosion.gd").new(crowded, crowded_sim, crowded_damage)
	for k in 24:
		for x in range(3, 28, 3):
			crowded_sim.motion.record(Vector2i(x, 7), Vector2(160, 0), 1.0)
		crowded_wear.update(0.12)
	var all_worn := true
	for x in range(3, 28, 3):
		all_worn = all_worn and crowded.hp_frac(x, 8) < 1.0
	t.check(all_worn, "erosion edit budget shares work across all exposed faces")


static func stress(t: Node) -> void:
	t.section("bounded flood stress")
	seed(1701)
	var g := basin(52, 60)
	for y in range(1, 59):
		g.put(28, y, Cell.BEDROCK)
	for y in range(5, 50):
		for x in range(1, 28):
			g.set_water(x, y, 64)
	for x in range(1, 28):
		g.put(x, 50, Cell.BEDROCK)
	var sim := WaterSim.new(g)
	for y in range(43, 50):
		g.set_mat(28, y, Cell.AIR)
	sim.wake_all()
	var before := sim.total()
	var times: Array[int] = []
	var peak_drops := 0
	var peak_work := 0
	var peak_motion := 0
	for k in 1200:
		var start := Time.get_ticks_usec()
		sim.update(1.0 / 60.0)
		times.append(Time.get_ticks_usec() - start)
		peak_drops = maxi(peak_drops, sim.drop_count())
		peak_work = maxi(peak_work, sim.pressure.work)
		peak_motion = maxi(peak_motion, sim.motion.cells.size())
	times.sort()
	var average := 0.0
	for value in times:
		average += value / 1200.0
	t.check(sim.total() == before and sim.lost == 0, "closed finite flood retains water even at obstructed landings (%d lost)" % sim.lost)
	t.check(peak_drops <= 900 and peak_work <= 2048 and peak_motion <= 4096, "stress remains within droplet, head-work and motion budgets")
	print("  flood CPU only: mean %.3f ms, p95 %.3f ms, max %.3f ms; peak drops %d, pressure nodes %d, motion cells %d, loss %d" % [average / 1000.0, times[1140] / 1000.0, times[-1] / 1000.0, peak_drops, peak_work, peak_motion, sim.lost])


static func integration(t: Node, mine: Node) -> void:
	t.section("live water integration")
	var g: TerrainGrid = mine.grid
	# Runtime placement API, no direct mutation of material/ore backing arrays.
	var c := Vector2i(10, 195)
	# Isolate this finite exposure from the earlier dam/blast fixtures. Their
	# independent ore-bearing faces must not enter this fixture's reward count.
	mine.water.motion.cells.clear()
	mine.erosion.exposure.clear()
	for y in range(c.y - 2, c.y + 2):
		for x in range(c.x - 1, c.x + 2):
			g.set_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE | Cell.F_WATER_SAFE | Cell.F_CLAIMED, false)
			g.set_mat(x, y, Cell.AIR)
	g.place(c.x, c.y, Cell.SOFT, Cell.ORE_COPPER, 1.0)
	var before := int(Game.run.get("ore_mined", 0))
	for k in 140:
		mine.water.motion.record(c + Vector2i.UP, Vector2(160, 0), 1.0)
		mine.erosion.update(0.12)
	t.check(g.get_mat(c.x, c.y) == Cell.AIR and int(Game.run.get("ore_mined", 0)) == before + 1, "live erosion uses normal mining rewards exactly once (mat %d, hp %.2f, mined %d -> %d, exposure %s)" % [g.get_mat(c.x, c.y), g.hp_frac(c.x, c.y), before, int(Game.run.get("ore_mined", 0)), mine.erosion.exposure.get(c, 0)])
	# A closed flooded room exercises actual Godot rigid bodies and localized
	# terrain collisions, in addition to the force-level buoyancy unit checks.
	for y in range(175, 188):
		for x in range(43, 57):
			g.set_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE | Cell.F_WATER_SAFE, false)
			var border := x == 43 or x == 56 or y == 175 or y == 187
			g.set_mat(x, y, Cell.BEDROCK if border else Cell.AIR)
			g.set_water(x, y, 0 if border else 64)
	await t._frames(3)
	var crate: RigidBody2D = mine.debris.spawn_prop("crate", g.cell_center(Vector2i(46, 181)))
	var stone: RigidBody2D = mine.debris.spawn_prop("stone", g.cell_center(Vector2i(52, 181)))
	t.check(crate != null and stone != null, "live flooded-room props spawn safely")
	if crate and stone:
		var start_y := crate.position.y
		await t._frames(45)
		t.check(crate.position.y < start_y - 5 and stone.position.y > start_y + 5, "actual physics raises wood and sinks stone")
		t.check(not g.solid_at(crate.position) and not g.solid_at(stone.position), "physical props remain outside intact terrain")


static func review_regressions(t: Node) -> void:
	t.section("crowded flow and falling-solid regressions")
	var g := basin(52, 60)
	var sim := WaterSim.new(g)
	g.put(3, 3, Cell.SOFT)
	# Sustained moving field larger than one erosion scan, with only one
	# susceptible face. Unvisited faces are not evidence of dry conditions.
	for y in range(1, 59):
		for x in range(1, 51):
			sim.motion.record(Vector2i(x, y), Vector2(140, 0), 1.0)
	var damage := func(c: Vector2i, amount: float, tier: int, ignore: bool, _source: String) -> Dictionary:
		return g.damage(c.x, c.y, amount, tier, ignore)
	var wear := WaterErosion.new(g, sim, damage)
	for k in 200:
		wear.update(0.12)
	t.check(g.get_mat(3, 3) == Cell.AIR or g.hp_frac(3, 3) < 1.0, "continuous exposure survives omission from a crowded scan budget")
	var rock_grid := basin()
	var drops := WaterSim.new(rock_grid)
	drops.drop_pos.append(Vector2(88, 88))
	drops.drop_vel.append(Vector2.ZERO)
	drops.drop_vol.append(3)
	drops.drop_src.append(rock_grid.idx(5, 5))
	rock_grid.set_mat(5, 5, Cell.HARD)
	drops.update_drops(0.06)
	var in_rock := false
	for p in drops.drop_pos:
		in_rock = in_rock or rock_grid.solid_at(p)
	t.check(not in_rock and drops.total() == 3 and drops.lost == 0, "a newly landed solid displaces its droplet into adjacent open space")
	var sealed := basin()
	for y in range(4, 7):
		for x in range(4, 7):
			sealed.put(x, y, Cell.HARD)
	var squeezed := WaterSim.new(sealed)
	squeezed.drop_pos.append(Vector2(88, 88))
	squeezed.drop_vel.append(Vector2.ZERO)
	squeezed.drop_vol.append(3)
	squeezed.drop_src.append(sealed.idx(5, 5))
	squeezed.update_drops(0.06)
	t.check(squeezed.drop_count() == 0 and squeezed.lost == 3, "completely enclosed displacement counts squeeze loss and releases its droplet slot")
