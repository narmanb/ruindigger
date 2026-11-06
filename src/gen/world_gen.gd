class_name WorldGen
extends RefCounted
## Seeded, deterministic mine generator.
##
## Layout is built around a vertical "spine" shaft so the mine is readable and
## always navigable:
##
##   surface (open sky rows)
##     [SURFACE CAB]  <- spawn stands on this floor
##     [ SHAFT ]      <- carved straight down, with side branches
##     [DEPTH CAB]    <- lift; extract from here, back to the surface
##
## Guarantees, enforced structurally rather than by hope:
##
##   1. The spine, the surface cab and the depth cab are carved first and are
##      never intersected by later random carving.
##   2. A bedrock shell seals the relic chamber, with exactly one carved
##      doorway; the guaranteed route is carved after every destructive step.
##   3. Ore and gas are only placed on solid rock that borders reachable space,
##      so every reward is physically obtainable for every seed.
##   4. Connectivity is verified and repaired as a final safety net.

class Result:
	var grid: TerrainGrid
	var spawn: Vector2i
	var lift: Vector2i
	var relic: Vector2i
	var relic_room: Rect2i
	var vaults: Array = []
	var seed_value: int = 0
	var warnings: Array = []
	var reachable_count: int = 0
	var ore_count: int = 0

const CAB_HALF_W := 3
const SHAFT_HALF_W := 2
const SURFACE_ROWS := 8

static func generate(seed_value: int, width_cells: int = 168, height_cells: int = 132) -> Result:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var g := TerrainGrid.new()
	g.setup(width_cells, height_cells)
	g.strata = PackedStringArray(["dustworks", "spore_veins", "forgotten_engine"])

	var band: int = height_cells / 3

	# ---- 1. Solid fill by depth band ------------------------------------
	for y in height_cells:
		for x in width_cells:
			var i: int = g.idx(x, y)
			if y < SURFACE_ROWS:
				g.material[i] = Balance.Mat.EMPTY
				continue
			if y >= height_cells - 3:
				g.material[i] = Balance.Mat.BEDROCK
				continue
			var r: float = rng.randf()
			var mat: int = Balance.Mat.SOIL
			if y >= band * 2:
				mat = Balance.Mat.BASALT if r < 0.55 else (Balance.Mat.ALLOY if r < 0.85 else Balance.Mat.SOIL)
			elif y >= band:
				mat = Balance.Mat.SOIL if r < 0.5 else (Balance.Mat.BASALT if r < 0.85 else Balance.Mat.ALLOY)
			else:
				mat = Balance.Mat.SOIL if r < 0.75 else Balance.Mat.BASALT
			g.material[i] = mat
			if y > SURFACE_ROWS + 20 and rng.randf() < 0.02:
				g.material[i] = Balance.Mat.BEDROCK

	# ---- 2. Random-walk caverns -----------------------------------------
	var caves: int = 44 + int(width_cells * height_cells / 2600.0)
	for _c in caves:
		var cx: int = rng.randi_range(3, width_cells - 4)
		var cy: int = rng.randi_range(SURFACE_ROWS + 2, height_cells - 6)
		var steps: int = rng.randi_range(28, 90)
		var radius: int = rng.randi_range(2, 4)
		for _s in steps:
			_carve_disc(g, cx, cy, radius)
			cx = clampi(cx + rng.randi_range(-2, 2), 2, width_cells - 3)
			cy = clampi(cy + rng.randi_range(-2, 2), SURFACE_ROWS + 1, height_cells - 4)

	# ---- 3. Spine shaft: spawn cab -> shaft -> lift cab ------------------
	var lift_x: int = clampi(width_cells / 6, CAB_HALF_W + 3, width_cells - CAB_HALF_W - 4)
	var spawn := Vector2i(lift_x, SURFACE_ROWS + 1)
	var lift := Vector2i(lift_x, height_cells - 8)
	_carve_shaft(g, lift_x, SURFACE_ROWS + 1, height_cells - 5)
	_carve_cab(g, lift_x, spawn.y)
	_carve_cab(g, lift_x, lift.y)
	g.spawn_cell = spawn
	g.lift_cell = lift

	# ---- 4. Relic chamber (bedrock-sealed, one carved doorway) ----------
	var rx: int = rng.randi_range(width_cells * 2 / 3, width_cells - 14)
	var ry: int = rng.randi_range(band * 2 + 6, height_cells - 16)
	var room: Rect2i = Rect2i(rx - 6, ry - 4, 13, 9)
	var room_outer: Rect2i = room.grow(1)
	var relic: Vector2i = Vector2i(rx, ry + 2)
	var door_y: int = room.position.y + 2
	var door_cell: Vector2i = Vector2i(room_outer.position.x, door_y)
	var approach: Vector2i = Vector2i(room_outer.position.x - 7, door_y)

	_carve_rect(g, room)
	g.relic_cell = relic
	# Interior dressing: a shallow alloy lip along the floor, two pillars.
	_fill_row(g, rx, room.end.y - 1, room.size.x / 2, Balance.Mat.ALLOY)
	for px_ in [room.position.x + 3, room.end.x - 4]:
		for py in range(room.position.y + 1, room.end.y - 2):
			if g.in_bounds(px_, py):
				g.material[g.idx(px_, py)] = Balance.Mat.ALLOY

	# ---- 5. Treasure vaults ---------------------------------------------
	var vaults: Array = []
	for _v in 3:
		var vx: int = rng.randi_range(8, width_cells - 10)
		var vy: int = rng.randi_range(SURFACE_ROWS + 12, height_cells - 12)
		var vr: Rect2i = Rect2i(vx - 3, vy - 2, 7, 5)
		if vr.grow(3).intersects(room_outer):
			continue
		if absi(vx - lift_x) < CAB_HALF_W + 6:
			continue
		_shell_rect(g, vr.grow(1), Balance.Mat.ALLOY)
		_carve_rect(g, vr)
		# A deliberately sealed door: the vault must be breached with the drill,
		# so it reads as a reward for exploration, never a trap.
		var door: Vector2i = Vector2i(vr.position.x - 1, vr.position.y + vr.size.y / 2)
		for dy in range(-1, 2):
			if g.in_bounds(door.x, door.y + dy):
				g.material[g.idx(door.x, door.y + dy)] = Balance.Mat.BASALT
		var outside: Vector2i = _nearest_open(g, door + Vector2i(-4, 0))
		carve_corridor(g, outside, door + Vector2i(-2, 0), rng, 1)
		vaults.append({"rect": vr, "door": door})

	# ---- 6. Guaranteed route (after everything destructive) -------------
	carve_corridor(g, spawn, approach, rng, 2)
	_shell_rect(g, room_outer, Balance.Mat.BEDROCK)
	for dy in range(-1, 2):
		if g.in_bounds(door_cell.x, door_cell.y + dy):
			g.material[g.idx(door_cell.x, door_cell.y + dy)] = Balance.Mat.EMPTY
	var inside: Vector2i = Vector2i(room.position.x + 1, door_y)
	carve_corridor(g, inside, lift, rng, 2)
	carve_corridor(g, approach, door_cell, rng, 1)

	# ---- 6b. Cab floors last --------------------------------------------
	# The corridors above may clip the cabs, so the standing floors are laid
	# down after all carving. Without these the player falls down the shaft and
	# can never satisfy the lift's extraction radius. The cab interiors above
	# the floor stay open, so no second carve is needed.
	_fill_row(g, lift_x, spawn.y + 2, CAB_HALF_W, Balance.Mat.SOIL)
	_fill_row(g, lift_x, lift.y + 2, CAB_HALF_W, Balance.Mat.SOIL)

	# ---- 7. Reachability flood: the placement frontier -------------------
	# Ore and gas live in solid rock, so they go on the frontier -- solid
	# diggable cells orthogonally adjacent to space the player can walk to.
	var mask: PackedByteArray = g.reach_mask(spawn, 400000)
	var frontier: Array = []
	var open_count := 0
	for i in mask.size():
		if mask[i] == 0:
			continue
		open_count += 1
		var fx: int = i % g.w
		var fy: int = i / g.w
		for d: Vector2i in TerrainGrid.DIRS4:
			var nx: int = fx + d.x
			var ny: int = fy + d.y
			if not g.in_bounds(nx, ny):
				continue
			if not _is_diggable(g.get_material(nx, ny)):
				continue
			var key: int = g.idx(nx, ny)
			if not frontier.has(key):
				frontier.append(key)
	if frontier.is_empty():
		frontier.append(g.idx(spawn.x, spawn.y + 1))

	# ---- 8. Ore seams ----------------------------------------------------
	var ore_total: int = maxi(60, int(width_cells * height_cells / 420.0))
	var placed := 0
	var attempts := 0
	while placed < ore_total and attempts < ore_total * 10:
		attempts += 1
		var key2: int = frontier[rng.randi() % frontier.size()]
		var pick: Vector2i = Vector2i(key2 % g.w, key2 / g.w)
		if not _is_diggable(g.get_material(pick.x, pick.y)):
			continue
		if g.get_ore(pick.x, pick.y) != 0:
			continue
		_place_ore(g, pick.x, pick.y, _pick_ore(g, pick.y, false, rng))
		placed += 1
		if rng.randf() < 0.4:
			for _k in rng.randi_range(1, 3):
				var nx2: int = pick.x + rng.randi_range(-1, 1)
				var ny2: int = pick.y + rng.randi_range(-1, 1)
				if g.in_bounds(nx2, ny2) and _is_diggable(g.get_material(nx2, ny2)) \
						and g.get_ore(nx2, ny2) == 0:
					_place_ore(g, nx2, ny2, g.get_ore(pick.x, pick.y))

	for v in vaults:
		var r: Rect2i = v["rect"]
		for _k in 5:
			var ox: int = rng.randi_range(r.position.x + 1, r.end.x - 2)
			var oy: int = rng.randi_range(r.position.y + 1, r.end.y - 2)
			if _is_diggable(g.get_material(ox, oy)):
				_place_ore(g, ox, oy, _pick_ore(g, oy, true, rng))
	for _k in 4:
		var ox2: int = rng.randi_range(room.position.x + 1, room.end.x - 2)
		var oy2: int = rng.randi_range(room.position.y + 1, room.end.y - 3)
		if _is_diggable(g.get_material(ox2, oy2)):
			_place_ore(g, ox2, oy2, _pick_ore(g, oy2, true, rng))

	# ---- 9. Gas pockets --------------------------------------------------
	var gas_target: int = maxi(14, int(width_cells * height_cells / 1400.0))
	var gas_placed := 0
	var gas_attempts := 0
	while gas_placed < gas_target and gas_attempts < gas_target * 10:
		gas_attempts += 1
		var gkey: int = frontier[rng.randi() % frontier.size()]
		var gp: Vector2i = Vector2i(gkey % g.w, gkey / g.w)
		if gp.y < SURFACE_ROWS + 16:
			continue
		if absi(gp.x - lift_x) < CAB_HALF_W + 3:
			continue
		if not _is_diggable(g.get_material(gp.x, gp.y)):
			continue
		for _k in rng.randi_range(2, 5):
			var nx: int = gp.x + rng.randi_range(-1, 1)
			var ny: int = gp.y + rng.randi_range(-1, 1)
			if g.in_bounds(nx, ny) and _is_diggable(g.get_material(nx, ny)):
				g.gas[g.idx(nx, ny)] = 1
		gas_placed += 1

	# ---- 10. Protect mission-critical space ------------------------------
	g.protect(spawn.x, spawn.y, 4)
	g.protect(lift.x, lift.y, 4)
	for y in range(SURFACE_ROWS + 1, height_cells - 4):
		g.protect(lift_x, y, SHAFT_HALF_W)
	for x in range(room_outer.position.x, room_outer.end.x):
		for y in range(room_outer.position.y, room_outer.end.y):
			g.protect(x, y, 0)

	var res := Result.new()
	res.grid = g
	res.spawn = spawn
	res.lift = lift
	res.relic = relic
	res.relic_room = room
	res.vaults = vaults
	res.seed_value = seed_value
	res.reachable_count = open_count
	res.ore_count = _count_ore(g)

	_repair_connectivity(g, res, rng)
	_clear_gas_on_route(g, res)
	return res

# ---------------------------------------------------------------------------
# Carving helpers
# ---------------------------------------------------------------------------

static func _is_diggable(mat: int) -> bool:
	return mat == Balance.Mat.SOIL or mat == Balance.Mat.BASALT or mat == Balance.Mat.ALLOY

static func _carve_shaft(g: TerrainGrid, cx: int, top: int, bottom: int) -> void:
	for y in range(top, bottom):
		for x in range(cx - SHAFT_HALF_W, cx + SHAFT_HALF_W + 1):
			if g.in_bounds(x, y):
				g.material[g.idx(x, y)] = Balance.Mat.EMPTY
				g.ore[g.idx(x, y)] = 0

static func _carve_cab(g: TerrainGrid, cx: int, cy: int) -> void:
	for dy in range(-2, 3):
		for x in range(cx - CAB_HALF_W, cx + CAB_HALF_W + 1):
			if g.in_bounds(x, cy + dy):
				g.material[g.idx(x, cy + dy)] = Balance.Mat.EMPTY
				g.ore[g.idx(x, cy + dy)] = 0

static func _fill_row(g: TerrainGrid, cx: int, y: int, half_w: int, mat: int) -> void:
	for x in range(cx - half_w, cx + half_w + 1):
		if g.in_bounds(x, y):
			g.material[g.idx(x, y)] = mat

static func _carve_disc(g: TerrainGrid, cx: int, cy: int, r: int) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r + r:
				continue
			var x: int = cx + dx
			var y: int = cy + dy
			if not g.in_bounds(x, y):
				continue
			var i: int = g.idx(x, y)
			if g.material[i] == Balance.Mat.BEDROCK:
				continue
			g.material[i] = Balance.Mat.EMPTY
			g.ore[i] = 0
			g.gas.erase(i)

static func _carve_rect(g: TerrainGrid, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not g.in_bounds(x, y):
				continue
			var i: int = g.idx(x, y)
			g.material[i] = Balance.Mat.EMPTY
			g.ore[i] = 0
			g.gas.erase(i)

static func _shell_rect(g: TerrainGrid, r: Rect2i, mat: int) -> void:
	for x in range(r.position.x, r.end.x):
		for y in [r.position.y, r.end.y - 1]:
			if g.in_bounds(x, y):
				g.material[g.idx(x, y)] = mat
	for y in range(r.position.y, r.end.y):
		for x in [r.position.x, r.end.x - 1]:
			if g.in_bounds(x, y):
				g.material[g.idx(x, y)] = mat

## L-shaped corridor, never destructive to bedrock, so it can never breach a
## sealed chamber.
static func carve_corridor(g: TerrainGrid, a: Vector2i, b: Vector2i,
		_rng: RandomNumberGenerator, half_width: int = 1) -> void:
	var x: int = a.x
	var y: int = a.y
	while x != b.x:
		_carve_box(g, x, y, half_width)
		x += signi(b.x - x)
	while y != b.y:
		_carve_box(g, x, y, half_width)
		y += signi(b.y - y)
	_carve_box(g, b.x, b.y, half_width)

static func _carve_box(g: TerrainGrid, x: int, y: int, hw: int) -> void:
	for dx in range(-hw, hw + 1):
		for dy in range(-hw, hw + 1):
			var nx: int = x + dx
			var ny: int = y + dy
			if not g.in_bounds(nx, ny):
				continue
			var i: int = g.idx(nx, ny)
			if g.material[i] == Balance.Mat.BEDROCK:
				continue
			g.material[i] = Balance.Mat.EMPTY
			g.ore[i] = 0

static func _nearest_open(g: TerrainGrid, from: Vector2i) -> Vector2i:
	for r in range(0, 60):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x: int = from.x + dx
				var y: int = from.y + dy
				if g.in_bounds(x, y) and g.get_material(x, y) == Balance.Mat.EMPTY:
					return Vector2i(x, y)
	return from

static func _pick_ore(g: TerrainGrid, y: int, rare: bool, rng: RandomNumberGenerator) -> int:
	var band: int = int(float(y) / maxf(1.0, float(g.h)) * 3.0)
	var pool: Array
	if rare:
		pool = [2, 3, 4, 5, 6]
	else:
		match band:
			0: pool = [1, 1, 2, 2, 1]
			1: pool = [2, 3, 3, 4, 2]
			_: pool = [4, 5, 5, 6, 3]
	return pool[rng.randi() % pool.size()]

static func _place_ore(g: TerrainGrid, x: int, y: int, ore_id: int) -> void:
	if not g.in_bounds(x, y) or ore_id == 0:
		return
	if not _is_diggable(g.get_material(x, y)):
		return
	g.set_ore(x, y, ore_id)

static func _count_ore(g: TerrainGrid) -> int:
	var c := 0
	for i in g.ore.size():
		if g.ore[i] != 0:
			c += 1
	return c

# ---------------------------------------------------------------------------
# Connectivity verification + repair
# ---------------------------------------------------------------------------

static func _repair_connectivity(g: TerrainGrid, res: Result, rng: RandomNumberGenerator) -> void:
	var target: Vector2i = Vector2i(res.relic.x, res.relic.y - 2)
	var attempts: int = 0
	while attempts < 30:
		attempts += 1
		if not g.reachable(res.spawn, target, 400000):
			carve_corridor(g, res.spawn, target, rng, 2)
			res.warnings.append("repaired spawn->relic (attempt %d)" % attempts)
			continue
		if not g.reachable(target, res.lift, 400000):
			carve_corridor(g, target, res.lift, rng, 2)
			res.warnings.append("repaired relic->lift (attempt %d)" % attempts)
			continue
		break
	if not g.reachable(res.spawn, target, 400000):
		carve_corridor(g, res.spawn, target, rng, 3)
		res.warnings.append("forced spawn->relic shaft")
	if not g.reachable(target, res.lift, 400000):
		carve_corridor(g, target, res.lift, rng, 3)
		res.warnings.append("forced relic->lift shaft")

## Gas on the guaranteed route is removed: the critical path must be traversable
## without a forced detonation.
static func _clear_gas_on_route(g: TerrainGrid, res: Result) -> void:
	var target: Vector2i = Vector2i(res.relic.x, res.relic.y - 2)
	var path: Array = g.path_between(res.spawn, target, 400000)
	path.append_array(g.path_between(target, res.lift, 400000))
	for c: Vector2i in path:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var nx: int = c.x + dx
				var ny: int = c.y + dy
				if g.in_bounds(nx, ny):
					g.gas.erase(g.idx(nx, ny))
