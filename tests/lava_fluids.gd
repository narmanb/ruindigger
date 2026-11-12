extends RefCounted
## Lava, the water/lava reaction, steam and cooled rock. Runs as suite=lava.

static func _box(w: int, h: int) -> TerrainGrid:
	var g := TerrainGrid.new(w, h)
	for y in h:
		for x in w:
			g.put(x, y, Cell.BEDROCK if (x == 0 or y == 0 or x == w - 1 or y == h - 1) else Cell.AIR)
			g.stratum[g.idx(x, y)] = Balance.Z_FIRST
	return g


static func _lava_total(g: TerrainGrid) -> int:
	var t := 0
	for v in g.lava:
		t += v
	return t


static func _water_total(g: TerrainGrid) -> int:
	var t := 0
	for v in g.water:
		t += v
	return t


static func run(t: Node) -> void:
	t.section("lava flow")
	# --- viscosity: the same column of water and of lava, released on a floor
	var gw := _box(40, 12)
	var gl := _box(40, 12)
	for y in range(5, 11):
		gw.water[gw.idx(3, y)] = Balance.WATER_MAX
		gl.lava[gl.idx(3, y)] = Balance.LAVA_MAX
	var ws := WaterSim.new(gw)
	ws.wake_all()
	var ls := LavaSim.new(gl)
	ls.wake_all()
	var seconds := 3.0
	var elapsed := 0.0
	while elapsed < seconds:
		ws.update(1.0 / 60.0)
		ls.update(1.0 / 60.0)
		elapsed += 1.0 / 60.0
	var reach_w := 0
	var reach_l := 0
	for x in range(1, 39):
		for y in range(1, 11):
			if gw.get_water(x, y) > 0:
				reach_w = maxi(reach_w, x)
			if gl.get_lava(x, y) > 0:
				reach_l = maxi(reach_l, x)
	t.check(reach_w >= reach_l + 6 and reach_l > 3, "water spreads far faster than lava in the same time (water to x=%d, lava to x=%d after %.0f s)" % [reach_w, reach_l, seconds])
	t.check(_lava_total(gl) == 6 * Balance.LAVA_MAX, "lava is conserved while it flows (%d units)" % _lava_total(gl))
	var settle := ls.settle(2000)
	t.check(settle < 2000 and ls.active.is_empty(), "lava comes to rest (%d steps)" % settle)
	# viscous: it rests as a mound, not a flat sheet
	var lo := 999
	var hi := 0
	for x in range(1, 39):
		var col := 0
		for y in range(1, 11):
			col += gl.get_lava(x, y)
		if col > 0:
			lo = mini(lo, col)
			hi = maxi(hi, col)
	t.check(hi - lo >= Balance.LAVA_SPREAD_MIN / 2, "resting lava keeps a slope (column heights %d..%d units)" % [lo, hi])
	t.check(_lava_total(gl) == 6 * Balance.LAVA_MAX, "lava is conserved at rest")
	# budget: a huge lake only steps a bounded number of cells
	var gb := _box(80, 40)
	for y in range(1, 30):
		for x in range(1, 79):
			gb.lava[gb.idx(x, y)] = Balance.LAVA_MAX
	var lb := LavaSim.new(gb)
	lb.wake_all()
	var before_active := lb.active.size()
	lb.step()
	t.check(before_active > Balance.LAVA_BUDGET and lb.active.size() >= before_active - Balance.LAVA_BUDGET, "a step never processes more than the lava budget (%d active, budget %d)" % [before_active, Balance.LAVA_BUDGET])
	# falling: lava pours through a hole and pools below
	var gf := _box(20, 20)
	for x in range(1, 19):
		gf.put(x, 8, Cell.HARD)
	for y in range(3, 8):
		gf.put(5, y, Cell.HARD)
		gf.put(12, y, Cell.HARD)
	for x in range(6, 12):
		for y in range(5, 8):
			gf.lava[gf.idx(x, y)] = Balance.LAVA_MAX
	var lf := LavaSim.new(gf)
	lf.wake_all()
	t.check(lf.settle(50) < 50, "a contained lava pool is at rest")
	gf.set_mat(8, 8, Cell.AIR)       # drill the floor out from under it
	var s2 := 0
	while s2 < 3000 and (not lf.active.is_empty() or s2 == 0):
		lf.step()
		s2 += 1
	var below := 0
	for y in range(9, 19):
		for x in range(1, 19):
			below += gf.get_lava(x, y)
	t.check(below > 10 * Balance.LAVA_MAX and _lava_total(gf) == 18 * Balance.LAVA_MAX, "breaching a reservoir drains it through the hole, conserved (%d units below)" % below)
	# keep-out cells are never entered
	var gk := _box(20, 10)
	for y in range(4, 9):
		gk.lava[gk.idx(3, y)] = Balance.LAVA_MAX
	var lk := LavaSim.new(gk)
	for y in range(1, 9):
		lk.keep_out[Vector2i(8, y)] = true
	lk.settle(3000)
	var beyond := 0
	for y in range(1, 9):
		for x in range(8, 19):
			beyond += gk.get_lava(x, y)
	t.check(beyond == 0, "lava never enters protected keep-out cells (%d units beyond)" % beyond)

	t.section("water meets lava")
	# --- a full water cell beside a full lava cell
	var g1 := _box(12, 8)
	for x in range(1, 11):
		g1.put(x, 6, Cell.HARD)
	g1.lava[g1.idx(4, 5)] = Balance.LAVA_MAX
	g1.water[g1.idx(5, 5)] = Balance.WATER_MAX
	var st1 := SteamField.new(g1)
	var l1 := LavaSim.new(g1, null, st1)
	l1.wake_all()
	var lava0 := _lava_total(g1)
	var water0 := _water_total(g1)
	var rock_at := -1
	for k in 40:
		l1.wake_all()
		l1.step()
		if rock_at < 0 and l1.rock_formed > 0:
			rock_at = k
	t.check(l1.rock_formed >= 1 and rock_at >= 2, "contact turns lava into rock, gradually (first rock on step %d, not the first touch)" % (rock_at + 1))
	t.check(g1.get_mat(4, 5) == Cell.HARD and g1.is_solid(4, 5), "the new rock is solid basalt in the lava's cell")
	t.check(_lava_total(g1) + l1.lava_frozen + l1.lava_lost == lava0, "lava accounting balances (now %d + frozen %d + lost %d = %d)" % [_lava_total(g1), l1.lava_frozen, l1.lava_lost, lava0])
	t.check(_water_total(g1) + l1.water_boiled == water0 and l1.water_boiled > 0, "water accounting balances (now %d + boiled %d = %d)" % [_water_total(g1), l1.water_boiled, water0])
	t.check(l1.water_boiled <= Balance.LAVA_SOLIDIFY_AT + Balance.LAVA_REACT_UNITS, "a contact is reacted once per step, not once per neighbour visit (boiled %d)" % l1.water_boiled)
	t.check(st1.made > 0.0 and st1.total() > 0.0, "the reaction gives off steam")
	# the rock can be drilled like any other
	var res := g1.damage(4, 5, 99.0, 0, false)
	t.check(res["broken"] and not g1.is_solid(4, 5) and int(res["ore"]) == 0, "cooled rock is drillable and carries no ore")
	# --- a few drops: a flash of steam, no wall of rock
	var g2 := _box(12, 8)
	for x in range(1, 11):
		g2.put(x, 6, Cell.HARD)
	for x in range(3, 8):
		g2.lava[g2.idx(x, 5)] = Balance.LAVA_MAX
	g2.water[g2.idx(5, 4)] = 12
	var st2 := SteamField.new(g2)
	var l2 := LavaSim.new(g2, null, st2)
	for k in 30:
		l2.wake_all()
		l2.step()
	t.check(l2.rock_formed == 0 and l2.water_boiled == 12 and st2.made > 0.0, "a splash of water only flashes to steam (boiled %d, rock %d)" % [l2.water_boiled, l2.rock_formed])
	# --- a lake does not turn to stone at once
	var g3 := _box(30, 14)
	for x in range(1, 29):
		for y in range(9, 13):
			g3.lava[g3.idx(x, y)] = Balance.LAVA_MAX
		for y in range(5, 9):
			g3.water[g3.idx(x, y)] = Balance.WATER_MAX
	var w3 := WaterSim.new(g3)
	var l3 := LavaSim.new(g3, w3, SteamField.new(g3))
	l3.wake_all()
	l3.step()
	l3.step()
	t.check(l3.rock_formed == 0, "a lake over lava does not convert instantly")
	for k in 60:
		w3.step()
		l3.wake_all()
		l3.step()
	var crust := 0
	for x in range(1, 29):
		if g3.is_solid(x, 9):
			crust += 1
	t.check(crust >= 20 and _lava_total(g3) > 28 * 2 * Balance.LAVA_MAX, "sustained contact builds a crust and leaves the lava beneath molten (%d crust cells, %d lava units left)" % [crust, _lava_total(g3)])
	t.check(w3.total() + l3.water_boiled + w3.lost == 28 * 4 * Balance.WATER_MAX, "water is only ever consumed, never created (now %d incl. drops, boiled %d, squeezed out %d)" % [w3.total(), l3.water_boiled, w3.lost])
	# --- a waterfall onto a lava channel builds a bridge you can stand on
	var g4 := _box(30, 20)
	for x in range(1, 29):
		g4.put(x, 16, Cell.HARD)
	for x in range(8, 22):
		g4.put(x, 6, Cell.HARD)           # the cistern floor
		for y in range(13, 16):
			g4.lava[g4.idx(x, y)] = Balance.LAVA_MAX
	for x in [7, 22]:
		for y in range(2, 16):
			g4.put(x, y, Cell.HARD)
	for x in range(8, 22):
		for y in range(2, 6):
			g4.water[g4.idx(x, y)] = Balance.WATER_MAX
	var w4 := WaterSim.new(g4)
	var st4 := SteamField.new(g4)
	var l4 := LavaSim.new(g4, w4, st4)
	g4.set_mat(15, 6, Cell.AIR)           # the player breaches the cistern
	var peak_steam := 0
	for frame in 1500:
		w4.update(1.0 / 60.0)
		l4.update(1.0 / 60.0)
		st4.update(1.0 / 60.0)
		peak_steam = maxi(peak_steam, st4.cells.size())
	var bridge := 0
	for x in range(8, 22):
		for y in range(12, 16):
			if g4.get_mat(x, y) == Cell.HARD:
				bridge += 1
				break
	t.check(l4.rock_formed >= 8 and bridge >= 8, "a breached cistern over lava leaves a lasting crust (%d rock cells across %d of 14 columns)" % [l4.rock_formed, bridge])
	t.check(peak_steam > 10 and peak_steam <= Balance.STEAM_MAX_CELLS, "the plume is visible and bounded (peak %d steam cells, cap %d)" % [peak_steam, Balance.STEAM_MAX_CELLS])
	var rock_cells := l4.rock_formed
	for frame in 1200:
		st4.update(1.0 / 60.0)
	t.check(st4.cells.is_empty(), "steam clears within 20 s once the reaction stops (%d cells left)" % st4.cells.size())
	var still := 0
	for y in range(1, 19):
		for x in range(1, 29):
			if g4.get_mat(x, y) == Cell.HARD:
				still += 1
	t.check(l4.rock_formed == rock_cells and still >= rock_cells, "the crust persists after the steam is gone")
	# --- lava poured into a wet shaft crusts and stops
	var g5 := _box(14, 20)
	for y in range(1, 19):
		for x in range(1, 13):
			if x < 6 or x > 7:
				g5.put(x, y, Cell.HARD)
	for y in range(14, 19):
		for x in [6, 7]:
			g5.water[g5.idx(x, y)] = Balance.WATER_MAX
	for y in range(1, 6):
		for x in [6, 7]:
			g5.lava[g5.idx(x, y)] = Balance.LAVA_MAX
	var w5 := WaterSim.new(g5)
	var l5 := LavaSim.new(g5, w5, SteamField.new(g5))
	l5.wake_all()
	for frame in 2400:
		w5.update(1.0 / 60.0)
		l5.update(1.0 / 60.0)
	t.check(l5.rock_formed >= 2 and l5.water_boiled > 0, "lava poured into a wet shaft forms a crust (%d rock cells)" % l5.rock_formed)
	t.check(_lava_total(g5) + l5.lava_frozen + l5.lava_lost == 10 * Balance.LAVA_MAX, "lava accounting balances in the shaft")

	t.section("solidification safety and steam")
	# rock never forms in a keep-out cell or where an actor stands
	var g6 := _box(12, 8)
	for x in range(1, 11):
		g6.put(x, 6, Cell.HARD)
	g6.lava[g6.idx(4, 5)] = Balance.LAVA_MAX
	g6.lava[g6.idx(7, 5)] = Balance.LAVA_MAX
	var l6 := LavaSim.new(g6, null, SteamField.new(g6))
	l6.keep_out[Vector2i(4, 5)] = true
	l6.occupied = func(c: Vector2i) -> bool: return c == Vector2i(7, 5)
	for k in 60:
		g6.water[g6.idx(4, 4)] = Balance.WATER_MAX
		g6.water[g6.idx(7, 4)] = Balance.WATER_MAX
		l6.wake_all()
		l6.step()
	t.check(not g6.is_solid(4, 5) and not g6.is_solid(7, 5) and l6.rock_formed == 0 and l6.deferred > 0, "rock never forms in a protected passage or on top of an actor (deferred %d times)" % l6.deferred)
	l6.occupied = func(_c: Vector2i) -> bool: return false
	for k in 10:
		g6.water[g6.idx(7, 4)] = Balance.WATER_MAX
		l6.wake_all()
		l6.step()
	t.check(g6.is_solid(7, 5) and not g6.is_solid(4, 5), "a deferred crust forms once the actor has moved away; the protected cell stays open")
	# steam: rises, spreads under a ceiling, dissipates, stays bounded
	var g7 := _box(30, 30)
	for x in range(1, 29):
		if x != 20:
			g7.put(x, 10, Cell.HARD)     # a ceiling with one chimney at x=20
	var st7 := SteamField.new(g7)
	st7.add(Vector2i(8, 25), 3.0)
	var top := 25
	for k in 14:
		st7.step()
	for c: Vector2i in st7.cells.keys():
		top = mini(top, c.y)
	t.check(top <= 13, "steam rises (reached row %d from row 25)" % top)
	for k in 400:
		st7.add(Vector2i(8, 25), 0.6)
		st7.step()
	var above := 0.0
	var spread := 0
	for c: Vector2i in st7.cells.keys():
		if c.y < 10:
			above += st7.density(c)
		if c.y == 11:
			spread += 1
	t.check(spread >= 8 and above > 0.0, "steam creeps along a ceiling and escapes up a chimney (%d cells along the ceiling, %.2f above it)" % [spread, above])
	t.check(st7.peak_cells <= Balance.STEAM_MAX_CELLS, "live steam cells never exceed the cap (%d of %d)" % [st7.peak_cells, Balance.STEAM_MAX_CELLS])
	for k in 400:
		st7.step()
	t.check(st7.cells.is_empty(), "steam dissipates completely once its source stops")
	var jg := TerrainGrid.from_dict(g4.to_dict())
	t.check(jg.lava == g4.lava, "lava volumes survive the grid's JSON round-trip")
