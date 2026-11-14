class_name SandSim
extends RefCounted
## Loose sand and rubble (granular piles). Each open cell holds 0..SAND_MAX
## pixels of sand in TerrainGrid.sand, filled from the bottom. Sand falls into
## room below and slides sideways when it stands more than SAND_REPOSE pixels
## above its neighbour, so drops spread into mounds you can walk over.
##
## Only cells that may move are simulated (the active set); settled sand costs
## nothing. Work per step is capped by the "Sand physics" setting, halves
## itself when a step runs slow, and anything beyond SAND_MAX_MOVING settles
## at once. Sand never enters rock, lava, or a cell an actor stands in.

var grid: TerrainGrid
var water: WaterSim
var active: Dictionary = {}
var occupied: Callable = Callable()
var budget_scale := 1.0
var steps := 0
var moves := 0
var instant := 0
var last_us := 0
var _acc := 0.0
var rng := RandomNumberGenerator.new()


func _init(g: TerrainGrid, w: WaterSim = null) -> void:
	grid = g
	water = w
	rng.seed = 0x73616e64


static func level() -> int:
	return clampi(int(Settings.get_value("sand_physics")), 0, Balance.SAND_LEVELS.size() - 1)


static func enabled() -> bool:
	return level() > 0


func can_hold(c: Vector2i) -> bool:
	if not grid.in_bounds(c.x, c.y):
		return false
	return _hold(c.y * grid.w + c.x)


## Same test on a flat index (the fast path the step uses).
func _hold(i: int) -> bool:
	if Cell.is_solid(grid.mat[i]) or grid.lava[i] > 0:
		return false
	return not (occupied.is_valid() and occupied.call(Vector2i(i % grid.w, i / grid.w)))


## Wake the cells around (x, y) that hold sand: only they can move.
func wake(x: int, y: int) -> void:
	for dy in range(-1, 2):
		var yy := y + dy
		if yy < 0 or yy >= grid.h:
			continue
		for dx in range(-1, 2):
			var xx := x + dx
			if xx >= 0 and xx < grid.w:
				var i := yy * grid.w + xx
				if grid.sand[i] > 0:
					active[i] = true


## Drop `amount` pixels of sand at c (stacking upward if c fills).
## Returns how much was placed.
func add(c: Vector2i, amount: int) -> int:
	var left := amount
	var cur := c
	for guard in 6:
		if left <= 0:
			break
		if not can_hold(cur):
			if guard == 0 and grid.in_bounds(cur.x, cur.y) and grid.is_solid(cur.x, cur.y):
				cur.y -= 1
				continue
			break
		var room := Balance.SAND_MAX - grid.get_sand(cur.x, cur.y)
		var put := mini(room, left)
		if put > 0:
			grid.set_sand(cur.x, cur.y, grid.get_sand(cur.x, cur.y) + put)
			_displace(cur, Vector2i(cur.x, cur.y - 1), put)
			left -= put
			wake(cur.x, cur.y)
		cur.y -= 1
	return amount - left


## Dig the sand out of a cell. Returns how much was removed.
func remove(c: Vector2i) -> int:
	var v := grid.get_sand(c.x, c.y)
	if v > 0:
		grid.set_sand(c.x, c.y, 0)
		wake(c.x, c.y)
		wake(c.x, c.y - 1)
	return v


func total() -> int:
	var t := 0
	for v in grid.sand:
		t += v
	return t


## Sand entering a cell pushes its water out into `to` (where the sand came
## from, or the cell above when sand is dropped in).
func _displace(at: Vector2i, to: Vector2i, px: int) -> void:
	var wv := grid.get_water(at.x, at.y)
	if wv <= 0:
		return
	var d := mini(wv, px * Balance.WATER_MAX / Balance.SAND_MAX)
	grid.set_water(at.x, at.y, wv - d)
	if grid.in_bounds(to.x, to.y) and not grid.is_solid(to.x, to.y):
		grid.set_water(to.x, to.y, mini(255, grid.get_water(to.x, to.y) + d))
	if water:
		water.wake(at.x, at.y)
		water.wake(to.x, to.y)


func _move(a: int, b: int, px: int) -> void:
	var w := grid.w
	grid.set_sand(a % w, a / w, grid.sand[a] - px)
	grid.set_sand(b % w, b / w, grid.sand[b] + px)
	if grid.water[b] > 0:
		_displace(Vector2i(b % w, b / w), Vector2i(a % w, a / w), px)
	wake(a % w, a / w)
	wake(b % w, b / w)
	moves += 1


func update(delta: float) -> void:
	var lv := level()
	if lv == 0 or active.is_empty():
		_acc = 0.0
		return
	var tick: float = Balance.SAND_LEVELS[lv]["tick"]
	_acc += delta
	var n := 0
	while _acc >= tick and n < 2:
		_acc -= tick
		step()
		n += 1


func step() -> void:
	if active.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var lv := maxi(1, level())
	var cap := maxi(20, int(float(Balance.SAND_LEVELS[lv]["budget"]) * budget_scale))
	var cells: Array = active.keys()
	active = {}
	cells.sort()          # flat indices: rows top to bottom...
	cells.reverse()       # ...so walk them bottom first
	var w := grid.w
	var smax := Balance.SAND_MAX
	var done := 0
	for i: int in cells:
		var s: int = grid.sand[i]
		if s <= 0:
			continue
		if done >= cap:
			active[i] = true            # carried over to the next step
			continue
		done += 1
		var x := i % w
		var y := i / w
		# fall into room below
		var bi := i + w
		if y + 1 < grid.h and grid.sand[bi] < smax and _hold(bi):
			_move(i, bi, mini(s, smax - grid.sand[bi]))
			continue
		# slide toward a lower neighbour
		var first := -1 if rng.randf() < 0.5 else 1
		for d: int in [first, -first]:
			var nx := x + d
			if nx < 0 or nx >= w:
				continue
			var ni := i + d
			if not _hold(ni):
				continue
			var nh: int = grid.sand[ni]
			var nbi := ni + w
			if y + 1 < grid.h and grid.sand[nbi] < smax and _hold(nbi):
				nh = -smax / 2                   # a drop beside us: pour over the edge
			var diff := s - nh
			if diff > Balance.SAND_REPOSE:
				var mv := clampi(diff / 2, 1, mini(s, smax - grid.sand[ni]))
				if mv > 0:
					_move(i, ni, mv)
					break
	# too much moving at once: the rest settles straight down right away
	if active.size() > Balance.SAND_MAX_MOVING:
		var extra: Array = active.keys()
		extra.sort()                     # top rows first
		for k in active.size() - Balance.SAND_MAX_MOVING:
			_settle_now(extra[k])
	steps += 1
	last_us = Time.get_ticks_usec() - t0
	if last_us > Balance.SAND_STEP_MAX_US:
		budget_scale = maxf(0.25, budget_scale * 0.5)
	else:
		budget_scale = minf(1.0, budget_scale + 0.05)


## Drop a cell's sand straight down to where it would come to rest.
func _settle_now(i: int) -> void:
	active.erase(i)
	var c := Vector2i(i % grid.w, i / grid.w)
	var s := grid.get_sand(c.x, c.y)
	if s <= 0:
		return
	var y := c.y
	while can_hold(Vector2i(c.x, y + 1)) and grid.get_sand(c.x, y + 1) < Balance.SAND_MAX and y < c.y + 40:
		y += 1
	if y == c.y:
		return
	var left := s
	grid.set_sand(c.x, c.y, 0)
	while left > 0 and y >= c.y:
		var room := Balance.SAND_MAX - grid.get_sand(c.x, y)
		var put := mini(room, left)
		grid.set_sand(c.x, y, grid.get_sand(c.x, y) + put)
		left -= put
		y -= 1
	if left > 0:
		grid.set_sand(c.x, c.y, grid.get_sand(c.x, c.y) + left)
	instant += 1
