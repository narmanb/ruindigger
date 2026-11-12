class_name LavaSim
extends RefCounted
## Lava: a slow, viscous second fluid stored in TerrainGrid.lava beside water.
## Only active cells are stepped (bounded by LAVA_BUDGET), on a much slower tick
## than water. It piles up, creeps, and keeps flowing long after a breach.
##
## Where lava touches water both are consumed. The lava cell absorbs cooling;
## once it has absorbed enough it crusts over into ordinary, drillable rock, and
## the boiled water leaves as steam. A thin film of lava just hardens away. One
## reaction per lava cell per step, so contacts are never counted twice.
##
## Accounting (nothing is ever created):
##   lava now + lava_frozen + lava_lost == lava at the start
##   water_boiled is the water this sim removed from the grid

var grid: TerrainGrid
var water: WaterSim                 # optional: woken where water is consumed
var steam: SteamField               # optional: receives the boiled water
var active: Dictionary = {}
var cool: Dictionary = {}           # Vector2i -> cooling absorbed so far
var keep_out: Dictionary = {}       # cells lava never enters and rock never forms in
var occupied: Callable              # func(cell: Vector2i) -> bool: an actor is standing there
var _acc := 0.0
var _racc := 0.0
var quenched: Dictionary = {}       # cells that reacted since the last flow step
var steps := 0
var last_moves := 0
var lava_frozen := 0                # units of lava that became rock or slag
var lava_lost := 0                  # units squeezed out by terrain placed on top
var water_boiled := 0
var rock_formed := 0                # cells of new rock
var deferred := 0                   # crusts postponed because something was in the way
var formed_cells: Array[Vector2i] = []   # rock cells made this step (FX / tests)


func _init(g: TerrainGrid, w: WaterSim = null, s: SteamField = null) -> void:
	grid = g
	water = w
	steam = s
	g.cell_changed.connect(_on_cell_changed)


func total() -> int:
	var t := 0
	for v in grid.lava:
		t += v
	return t


func wake(x: int, y: int) -> void:
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c := Vector2i(x + d.x, y + d.y)
		if grid.in_bounds(c.x, c.y) and grid.lava[c.y * grid.w + c.x] > 0:
			active[c] = true


func wake_all() -> void:
	for i in grid.lava.size():
		if grid.lava[i] > 0:
			active[Vector2i(i % grid.w, i / grid.w)] = true


func _open(x: int, y: int) -> bool:
	return grid.in_bounds(x, y) and not Cell.is_solid(grid.get_mat(x, y)) and not keep_out.has(Vector2i(x, y))


## Lava never flows into water: it stops at the water's face and reacts there,
## so the two never share a cell without the reaction deciding what happens.
func _can_enter(x: int, y: int) -> bool:
	return _open(x, y) and grid.water[y * grid.w + x] == 0


func _on_cell_changed(x: int, y: int, _old: int, new_m: int) -> void:
	if Cell.is_solid(new_m):
		var v := grid.get_lava(x, y)
		if v > 0:
			# terrain landed in lava: push it up or aside, the rest is squeezed out
			for d in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var n := Vector2i(x + d.x, y + d.y)
				if _open(n.x, n.y):
					var mv := mini(Balance.LAVA_MAX - grid.get_lava(n.x, n.y), v)
					grid.set_lava(n.x, n.y, grid.get_lava(n.x, n.y) + mv)
					v -= mv
					if v <= 0:
						break
			lava_lost += maxi(v, 0)
			grid.set_lava(x, y, 0)
		cool.erase(Vector2i(x, y))
	wake(x, y)
	wake(x, y - 1)


## Reactions run on the fast (water) tick so a pour cannot run off between
## lava steps; flowing runs on the slow lava tick.
func update(delta: float) -> void:
	_racc += delta
	var r := 0
	while _racc >= Balance.LAVA_REACT_TICK and r < 4:
		_racc -= Balance.LAVA_REACT_TICK
		react_step()
		r += 1
	_acc += delta
	var n := 0
	while _acc >= Balance.LAVA_TICK and n < 2:
		_acc -= Balance.LAVA_TICK
		flow_step()
		n += 1


## Run until nothing moves (generation / tests). Returns the steps taken.
func settle(max_steps: int = 400) -> int:
	wake_all()
	for i in max_steps:
		step()
		if active.is_empty() or last_moves == 0:
			return i
	return max_steps


func _wet_near(c: Vector2i) -> bool:
	for d in [Vector2i(0, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		if grid.get_water(c.x + d.x, c.y + d.y) > 0:
			return true
	return false


## One full step (tests, generation): react, then flow.
func step() -> void:
	formed_cells.clear()
	react_step()
	var made := formed_cells.duplicate()
	flow_step()
	formed_cells = made


## Every lava cell next to water reacts once. Candidates come from cells water
## is moving through (water does not know about lava) and from active lava.
func react_step() -> void:
	var cand: Dictionary = {}
	if water:
		for wc: Vector2i in water.active.keys():
			for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = wc + d
				if grid.in_bounds(n.x, n.y) and grid.lava[n.y * grid.w + n.x] > 0:
					cand[n] = true
	for c in active.keys():
		cand[c] = true
	var done := 0
	for c: Vector2i in cand.keys():
		if done >= Balance.LAVA_BUDGET:
			break
		var i := c.y * grid.w + c.x
		if grid.lava[i] <= 0 or grid.is_solid(c.x, c.y):
			continue
		done += 1
		if _react(c):
			last_moves += 1
			quenched[c] = true
			if grid.lava[i] > 0 and not grid.is_solid(c.x, c.y):
				active[c] = true


func flow_step() -> void:
	steps += 1
	last_moves = 0
	if active.is_empty():
		quenched.clear()
		return
	var cells: Array = active.keys()
	active.clear()
	var was_quenched := quenched
	quenched = {}
	# bottom-up so a falling column moves as one
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y > b.y or (a.y == b.y and a.x < b.x))
	var done := 0
	for c: Vector2i in cells:
		if done >= Balance.LAVA_BUDGET:
			active[c] = true     # over budget: carry on next step
			continue
		done += 1
		var i := c.y * grid.w + c.x
		var v: int = grid.lava[i]
		if v <= 0:
			continue
		if was_quenched.has(c):
			# a cell being quenched does not flow: its skin is cooling
			last_moves += 1
			active[c] = true
			continue
		var moved := false
		# fall
		if _can_enter(c.x, c.y + 1):
			var room: int = Balance.LAVA_MAX - grid.lava[i + grid.w]
			var mv := mini(mini(v, room), Balance.LAVA_FALL)
			if mv > 0:
				grid.lava[i + grid.w] += mv
				v -= mv
				grid.lava[i] = v
				moved = true
				active[Vector2i(c.x, c.y + 1)] = true
		# creep sideways only when it cannot simply fall, and only down a real slope
		var resting: bool = not _can_enter(c.x, c.y + 1) or grid.lava[i + grid.w] >= Balance.LAVA_MAX
		if v > 0 and resting:
			var order: Array = [-1, 1] if (steps + c.x) % 2 == 0 else [1, -1]
			for dx: int in order:
				if not _can_enter(c.x + dx, c.y):
					continue
				var nv: int = grid.lava[i + dx]
				var diff := v - nv
				if diff >= Balance.LAVA_SPREAD_MIN:
					var mv2 := mini(Balance.LAVA_SIDE, diff / 3)
					if mv2 > 0:
						grid.lava[i + dx] = nv + mv2
						v -= mv2
						grid.lava[i] = v
						moved = true
						active[Vector2i(c.x + dx, c.y)] = true
		if moved:
			last_moves += 1
			active[c] = true
			# whatever was resting on or beside this cell may now move too
			for d in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var n: Vector2i = c + d
				if grid.in_bounds(n.x, n.y) and grid.lava[n.y * grid.w + n.x] > 0:
					active[n] = true
		elif v > 0 and _wet_near(c):
			active[c] = true     # resting against water: stay awake until it reacts


## React this lava cell with every wet face it touches (its own cell, above,
## sides, below): each lava-water contact is processed exactly once per step,
## because only lava cells start reactions. Returns true if anything happened.
func _react(c: Vector2i) -> bool:
	var i := c.y * grid.w + c.x
	var reacted := false
	for d in [Vector2i(0, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		var n: Vector2i = c + d
		if not grid.in_bounds(n.x, n.y):
			continue
		var wv := grid.get_water(n.x, n.y)
		if wv <= 0:
			continue
		var a := mini(Balance.LAVA_REACT_UNITS, wv)
		grid.set_water(n.x, n.y, wv - a)
		water_boiled += a
		reacted = true
		if water:
			water.wake(n.x, n.y)
		if steam:
			var vent: Vector2i = Vector2i(n.x, n.y - 1) if not grid.is_solid(n.x, n.y - 1) else n
			steam.add(vent, a * Balance.STEAM_PER_UNIT)
		cool[c] = int(cool.get(c, 0)) + a
	if reacted and int(cool.get(c, 0)) >= Balance.LAVA_SOLIDIFY_AT:
		_crust(c, i)
	return reacted


func _crust(c: Vector2i, i: int) -> void:
	var v: int = grid.lava[i]
	if v < Balance.LAVA_ROCK_MIN:
		# a thin film: it hardens away as slag and steam, no new rock. The spot
		# stays cold, so the next lava to arrive here crusts at once.
		grid.lava[i] = 0
		lava_frozen += v
		return
	if keep_out.has(c) or (occupied.is_valid() and occupied.call(c)):
		# never grow rock inside an actor or a protected passage: try again later
		deferred += 1
		cool[c] = Balance.LAVA_SOLIDIFY_AT
		return
	grid.lava[i] = 0
	lava_frozen += v
	cool.erase(c)
	grid.ore[i] = 0
	grid.set_mat(c.x, c.y, Cell.HARD)       # runtime API: collision, visuals, water displacement
	grid.flags[i] &= ~Cell.F_DUG
	rock_formed += 1
	formed_cells.append(c)
