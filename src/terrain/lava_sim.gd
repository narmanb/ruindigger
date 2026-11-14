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
## New crust is heavier than lava and water, so it FOUNDERS: a crust cell with
## liquid under it sinks through, exposing fresh lava to the water again, and
## the reaction keeps going until one of the two runs out (lots of steam, rock
## piling up at the bottom). Crust only holds near the shore: see _held().
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
var crust: Dictionary = {}          # reaction-made rock that may still founder
var slag: Dictionary = {}           # Vector2i -> lava units hardened as slag here (a full cell becomes rock)
var swapped := 0                    # lava cells that sank or spread through water
var sunk := 0                       # crust moves (one cell down each)
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
	return grid.in_bounds(x, y) and not Cell.is_solid(grid.get_mat(x, y)) and not keep_out.has(Vector2i(x, y)) \
		and grid.sand[y * grid.w + x] < Balance.SAND_MAX / 2


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


## A cell lava can push its way into by trading places: water, no lava, open.
func _swappable(c: Vector2i) -> bool:
	if not grid.in_bounds(c.x, c.y) or grid.is_solid(c.x, c.y) or keep_out.has(c):
		return false
	var j := c.y * grid.w + c.x
	return grid.lava[j] == 0 and grid.water[j] >= Balance.LAVA_SWAP_WATER


## Lava and water trade cells (both totals unchanged). Any cooling the lava
## had absorbed goes with it.
func _swap_with_water(from: Vector2i, to: Vector2i) -> void:
	var fi := from.y * grid.w + from.x
	var ti := to.y * grid.w + to.x
	var lv: int = grid.lava[fi]
	var wv: int = grid.water[ti]
	var fw: int = grid.water[fi]
	grid.lava[fi] = 0
	grid.lava[ti] = lv
	grid.set_water(to.x, to.y, fw)
	grid.set_water(from.x, from.y, wv)
	if cool.has(from):
		cool[to] = cool[from]
		cool.erase(from)
	if water:
		water.wake(from.x, from.y)
		water.wake(to.x, to.y)


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
	_founder()
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
		# denser than water: a lava cell over water sinks through it (swap)
		var bc := Vector2i(c.x, c.y + 1)
		if v >= Balance.LAVA_SINK_MIN and _swappable(bc):
			_swap_with_water(c, bc)
			swapped += 1
			last_moves += 1
			active[bc] = true
			continue
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
		# a pile on the floor of a pool is pushed out sideways under the water
		if v >= Balance.LAVA_SINK_MIN and resting and grid.lava[i - grid.w] > 0:
			var sorder: Array = [-1, 1] if (steps + c.x) % 2 == 0 else [1, -1]
			var spread := false
			for dx: int in sorder:
				var sc := Vector2i(c.x + dx, c.y)
				if _swappable(sc) and (grid.is_solid(sc.x, sc.y + 1) or grid.get_lava(sc.x, sc.y + 1) > 0):
					_swap_with_water(c, sc)
					swapped += 1
					spread = true
					active[sc] = true
					active[Vector2i(c.x, c.y - 1)] = true
					break
			if spread:
				last_moves += 1
				continue
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
	# water needed scales with how much lava is here: a thin packet hardens on
	# a little water instead of boiling a whole cell's worth away. A cell never
	# boils more than it still needs, however many wet faces it has.
	var need: float = Balance.LAVA_SOLIDIFY_AT * clampf(float(grid.lava[i]) / Balance.LAVA_MAX, 0.25, 1.0)
	for d in [Vector2i(0, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		var n: Vector2i = c + d
		if not grid.in_bounds(n.x, n.y):
			continue
		var wv := grid.get_water(n.x, n.y)
		if wv <= 0:
			continue
		var left := ceili(need) - int(cool.get(c, 0))
		if left <= 0:
			reacted = true      # wet and already cooled enough (e.g. it waited on an actor)
			break
		var a := mini(mini(Balance.LAVA_REACT_UNITS, wv), left)
		grid.set_water(n.x, n.y, wv - a)
		water_boiled += a
		reacted = true
		if water:
			water.wake(n.x, n.y)
		if steam:
			var vent: Vector2i = Vector2i(n.x, n.y - 1) if not grid.is_solid(n.x, n.y - 1) else n
			steam.add(vent, a * Balance.STEAM_PER_UNIT)
		cool[c] = int(cool.get(c, 0)) + a
	if reacted and float(cool.get(c, 0)) >= need:
		_crust(c, i)
	return reacted


func _is_crust(c: Vector2i) -> bool:
	return crust.has(c) and grid.get_mat(c.x, c.y) == Cell.HARD


## Does this crust cell hold? Crust sticks to the shore: a short run attached
## to rock on one side holds (CRUST_CANTILEVER), and a run wedged between rock
## on both sides holds up to CRUST_MAX_SPAN. Anything else founders.
func _held(c: Vector2i) -> bool:
	var x0 := c.x
	while _is_crust(Vector2i(x0 - 1, c.y)):
		x0 -= 1
	var x1 := c.x
	while _is_crust(Vector2i(x1 + 1, c.y)):
		x1 += 1
	var n := x1 - x0 + 1
	var l := Vector2i(x0 - 1, c.y)
	var r := Vector2i(x1 + 1, c.y)
	var la := grid.is_solid(l.x, l.y) and not crust.has(l)
	var ra := grid.is_solid(r.x, r.y) and not crust.has(r)
	if la and ra and n <= Balance.CRUST_MAX_SPAN:
		return true
	# per cell: close enough to the shore it is attached to
	return (la and c.x - x0 < Balance.CRUST_CANTILEVER) or (ra and x1 - c.x < Balance.CRUST_CANTILEVER)


## Let unsupported crust sink one cell through the liquid under it (lava or
## water swaps up into its place). Bottom-up, bounded per step.
func _founder() -> void:
	if crust.is_empty():
		return
	var cells: Array = crust.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y > b.y)
	var moved := 0
	for c: Vector2i in cells:
		if moved >= Balance.CRUST_SINK_BUDGET:
			break
		if grid.get_mat(c.x, c.y) != Cell.HARD:
			crust.erase(c)          # drilled, blasted or otherwise gone
			continue
		var b := Vector2i(c.x, c.y + 1)
		if not grid.in_bounds(b.x, b.y) or grid.is_solid(b.x, b.y) or keep_out.has(b):
			# landed on rock: it slumps off a pile like sand if liquid lies
			# diagonally below, so a pour builds a mound instead of a pillar
			var slid := false
			for dx in ([-1, 1] if (c.x + c.y + sunk) % 2 == 0 else [1, -1]):
				var sd := Vector2i(c.x + dx, c.y + 1)
				var ss := Vector2i(c.x + dx, c.y)
				if grid.in_bounds(sd.x, sd.y) and not grid.is_solid(ss.x, ss.y) and not grid.is_solid(sd.x, sd.y) and not keep_out.has(sd) \
						and (grid.get_water(sd.x, sd.y) >= 8 or grid.get_lava(sd.x, sd.y) >= Balance.LAVA_ROCK_MIN) \
						and not (occupied.is_valid() and (occupied.call(sd) or occupied.call(ss))):
					_move_crust(c, sd)
					moved += 1
					slid = true
					break
			if not slid:
				crust.erase(c)      # settled: it is ordinary rock now
			continue
		var bi := b.y * grid.w + b.x
		var lv: int = grid.lava[bi]
		if lv > 0 and lv < Balance.LAVA_ROCK_MIN:
			continue                # a thin film of lava holds it up
		# otherwise it sinks through water or deep lava, and drops through open
		# air (the liquid under it drained away); boulder rockfall leaves crust alone
		if _held(c):
			continue
		if occupied.is_valid() and (occupied.call(b) or occupied.call(Vector2i(c.x, c.y - 1))):
			continue                # never drop out from under, or onto, an actor
		_move_crust(c, b)
		moved += 1


## Move a crust block into a liquid cell; the liquid takes its old place.
func _move_crust(c: Vector2i, to: Vector2i) -> void:
	var ti := to.y * grid.w + to.x
	var lv: int = grid.lava[ti]
	var wv: int = grid.water[ti]
	grid.lava[ti] = 0
	grid.set_water(to.x, to.y, 0)
	grid.set_mat(to.x, to.y, Cell.HARD)
	grid.ore[ti] = 0
	grid.flags[ti] &= ~Cell.F_DUG
	grid.set_mat(c.x, c.y, Cell.AIR)
	var ci := c.y * grid.w + c.x
	grid.lava[ci] = lv
	grid.set_water(c.x, c.y, wv)
	cool.erase(c)
	cool.erase(to)
	crust.erase(c)
	crust[to] = true
	sunk += 1
	if lv > 0:
		active[c] = true
	if water:
		water.wake(c.x, c.y)
	wake(c.x, c.y)


## Freeze the lava in one cell right now (cryo gadget). Same rules and
## accounting as a water reaction. Returns true if any lava was there.
func quench(c: Vector2i) -> bool:
	if not grid.in_bounds(c.x, c.y):
		return false
	var i := c.y * grid.w + c.x
	if grid.lava[i] <= 0:
		return false
	_crust(c, i)
	wake(c.x, c.y)
	return true


func _crust(c: Vector2i, i: int) -> void:
	var v: int = grid.lava[i]
	if v < Balance.LAVA_ROCK_MIN:
		# a thin packet hardens as slag where it is; a full cell's worth of slag
		# collected in one spot becomes a block of rock (that may then sink)
		grid.lava[i] = 0
		lava_frozen += v
		cool.erase(c)
		var sl: int = int(slag.get(c, 0)) + v
		if sl >= Balance.LAVA_MAX and not keep_out.has(c) and not (occupied.is_valid() and occupied.call(c)) and not grid.is_solid(c.x, c.y):
			sl -= Balance.LAVA_MAX
			_place_rock(c, i)
		slag[c] = sl
		return
	if keep_out.has(c) or (occupied.is_valid() and occupied.call(c)):
		# never grow rock inside an actor or a protected passage: try again later
		deferred += 1
		cool[c] = Balance.LAVA_SOLIDIFY_AT
		return
	grid.lava[i] = 0
	lava_frozen += v
	cool.erase(c)
	_place_rock(c, i)


func _place_rock(c: Vector2i, i: int) -> void:
	grid.ore[i] = 0
	grid.set_mat(c.x, c.y, Cell.HARD)       # runtime API: collision, visuals, water displacement
	grid.flags[i] &= ~Cell.F_DUG
	rock_formed += 1
	formed_cells.append(c)
	crust[c] = true
