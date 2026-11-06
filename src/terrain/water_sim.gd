class_name WaterSim
extends RefCounted
## Cellular water on the terrain grid. Each open cell holds 0..WATER_MAX units.
## Only "active" cells (recently changed or next to a change) are simulated, so a
## settled lake costs nothing. Water is conserved except when a solid lands on
## it with nowhere to go (it is then squeezed out and lost).

var grid: TerrainGrid
var active: Dictionary = {}
var _acc := 0.0
var steps := 0
var last_moves := 0
var lost := 0


func _init(g: TerrainGrid) -> void:
	grid = g
	grid.cell_changed.connect(_on_cell_changed)


func total() -> int:
	var t := 0
	for v in grid.water:
		t += v
	return t


func wake(x: int, y: int) -> void:
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c := Vector2i(x + d.x, y + d.y)
		if grid.in_bounds(c.x, c.y):
			active[c] = true


func wake_all() -> void:
	for y in grid.h:
		for x in grid.w:
			if grid.water[grid.idx(x, y)] > 0:
				active[Vector2i(x, y)] = true


func _open(x: int, y: int) -> bool:
	return grid.in_bounds(x, y) and not Cell.is_solid(grid.get_mat(x, y))


func _on_cell_changed(x: int, y: int, _old: int, new_m: int) -> void:
	if Cell.is_solid(new_m):
		var v := grid.get_water(x, y)
		if v > 0:
			# displace: up first, then sideways, otherwise squeezed out
			for d in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var n := Vector2i(x + d.x, y + d.y)
				if _open(n.x, n.y):
					var room := Balance.WATER_MAX - grid.get_water(n.x, n.y)
					var mv := mini(room, v)
					grid.set_water(n.x, n.y, grid.get_water(n.x, n.y) + mv)
					v -= mv
					if v <= 0:
						break
			lost += maxi(v, 0)
			grid.set_water(x, y, 0)
	wake(x, y)
	wake(x, y - 1)


func update(delta: float) -> void:
	_acc += delta
	var n := 0
	while _acc >= Balance.WATER_TICK and n < 3:
		_acc -= Balance.WATER_TICK
		step()
		n += 1


func step() -> void:
	if active.is_empty():
		last_moves = 0
		return
	steps += 1
	var cells: Array = active.keys()
	# bottom-up so a falling column drains in one pass; alternate the sweep
	# direction each step so spreading is symmetric
	var flip := steps % 2 == 0
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y > b.y
		return a.x < b.x if flip else a.x > b.x)
	active = {}
	var moves := 0
	var budget := Balance.WATER_BUDGET
	for c in cells:
		budget -= 1
		if budget <= 0:
			active[c] = true
			continue
		var x: int = c.x
		var y: int = c.y
		var lv := grid.get_water(x, y)
		if lv <= 0 or not _open(x, y):
			continue
		var changed := false
		# 1) fall
		if _open(x, y + 1):
			var below := grid.get_water(x, y + 1)
			if below < Balance.WATER_MAX:
				var mv := mini(lv, Balance.WATER_MAX - below)
				grid.set_water(x, y + 1, below + mv)
				lv -= mv
				grid.set_water(x, y, lv)
				changed = true
				moves += mv
		# 2) spread sideways toward lower neighbours (only once resting)
		if lv > 0 and (not _open(x, y + 1) or grid.get_water(x, y + 1) >= Balance.WATER_MAX):
			var sides: Array = [Vector2i(-1, 0), Vector2i(1, 0)] if flip else [Vector2i(1, 0), Vector2i(-1, 0)]
			for d in sides:
				var nx: int = x + d.x
				if not _open(nx, y):
					continue
				var ln := grid.get_water(nx, y)
				var diff := lv - ln
				if diff >= 2 or (diff == 1 and ln == 0 and _open(nx, y + 1) and grid.get_water(nx, y + 1) < Balance.WATER_MAX):
					var mv2 := maxi(1, diff / 2)
					grid.set_water(nx, y, ln + mv2)
					lv -= mv2
					grid.set_water(x, y, lv)
					changed = true
					moves += mv2
					active[Vector2i(nx, y)] = true
					active[Vector2i(nx, y + 1)] = true
		if changed:
			wake(x, y)
			active[Vector2i(x, y + 1)] = true
	last_moves = moves


## Runs the simulation until nothing moves (used by the generator to settle lakes).
func settle(max_steps: int = 400) -> int:
	wake_all()
	for i in max_steps:
		step()
		if active.is_empty() or last_moves == 0:
			return i
	return max_steps
