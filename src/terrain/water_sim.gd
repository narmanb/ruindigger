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
# Free-falling water leaves the grid as droplets so it pours as a continuous
# stream with momentum, then merges back in where it lands.
var drop_pos := PackedVector2Array()
var drop_vel := PackedVector2Array()
var drop_vol := PackedInt32Array()
var splashes: Array[Vector2] = []   # landing points this frame (for FX)
var deposits := 0


func _init(g: TerrainGrid) -> void:
	grid = g
	grid.cell_changed.connect(_on_cell_changed)


func total() -> int:
	var t := 0
	for v in grid.water:
		t += v
	for v in drop_vol:
		t += v
	return t


func drop_count() -> int:
	return drop_pos.size()


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
	update_drops(delta)


func _emit(x: int, y: int, amount: int) -> void:
	# spill sideways momentum: water leaves away from the fuller side
	var lw := grid.get_water(x - 1, y) if _open(x - 1, y) else -1
	var rw := grid.get_water(x + 1, y) if _open(x + 1, y) else -1
	var vx := 0.0
	if lw > rw + 2:
		vx = 38.0
	elif rw > lw + 2:
		vx = -38.0
	var cx := x * 16.0 + 8.0
	var left := amount
	while left > 0:
		var v := mini(Balance.WATER_DROP_UNITS, left)
		left -= v
		# spread releases over the tick so the stream is continuous, not pulsed
		var lag := randf()
		var vy0 := 30.0 + 60.0 * (1.0 - lag)
		drop_pos.append(Vector2(cx + randf_range(-3.0, 3.0) + vx * Balance.WATER_TICK * (1.0 - lag), (y + 1) * 16.0 + 0.5 + vy0 * Balance.WATER_TICK * (1.0 - lag)))
		drop_vel.append(Vector2(vx + randf_range(-4.0, 4.0), vy0))
		drop_vol.append(v)


func update_drops(delta: float) -> void:
	splashes.clear()
	var i := 0
	while i < drop_pos.size():
		var p := drop_pos[i]
		var v := drop_vel[i]
		v.y = minf(v.y + Balance.WATER_DROP_GRAVITY * delta, Balance.WATER_DROP_MAX_FALL)
		var np := p + v * delta
		# sideways into rock: stop drifting
		var side := grid.world_to_cell(Vector2(np.x, p.y))
		if grid.is_solid(side.x, side.y):
			np.x = p.x
			v.x = 0.0
		var c := grid.world_to_cell(np)
		var land := Vector2i(-1, -1)
		if grid.is_solid(c.x, c.y):
			land = grid.world_to_cell(p)          # hit a floor: settle in the last open cell
		elif grid.get_water(c.x, c.y) >= Balance.WATER_MAX / 3:
			land = c                               # plunged into a pool
		elif grid.is_solid(c.x, c.y + 1) and np.y > c.y * 16.0 + 12.0:
			land = c                               # reached the floor of this cell
		if land.x >= 0:
			_deposit(land, drop_vol[i])
			if randf() < 0.35:
				splashes.append(np)
			drop_pos.remove_at(i)
			drop_vel.remove_at(i)
			drop_vol.remove_at(i)
			continue
		drop_pos[i] = np
		drop_vel[i] = v
		i += 1


func _deposit(c: Vector2i, vol: int) -> void:
	deposits += 1
	var cell := c
	var guard := 0
	while vol > 0 and guard < 24:
		guard += 1
		if not _open(cell.x, cell.y):
			cell.y -= 1
			continue
		var room := Balance.WATER_MAX - grid.get_water(cell.x, cell.y)
		var mv := mini(room, vol)
		if mv > 0:
			grid.set_water(cell.x, cell.y, grid.get_water(cell.x, cell.y) + mv)
			vol -= mv
			wake(cell.x, cell.y)
		cell.y -= 1
	lost += vol


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
		# 1) fall: into open air as droplets, into water cell-to-cell
		if _open(x, y + 1) and grid.get_water(x, y + 1) == 0 and drop_pos.size() < Balance.WATER_MAX_DROPS:
			var out := mini(lv, Balance.WATER_EMIT_PER_TICK)
			_emit(x, y, out)
			lv -= out
			grid.set_water(x, y, lv)
			changed = true
			moves += out
		elif _open(x, y + 1):
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
		for k in 4:
			update_drops(Balance.WATER_TICK / 4.0)
		if (active.is_empty() or last_moves == 0) and drop_pos.is_empty():
			return i
	return max_steps
