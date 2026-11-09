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
var drop_src := PackedInt32Array()   # emitting cell index: lets the renderer join a stream
var splashes: Array[Vector2] = []   # landing points this frame (for FX)
var deposits := 0
var motion := WaterMotion.new()
var pressure: WaterPressure


func _init(g: TerrainGrid) -> void:
	grid = g
	pressure = WaterPressure.new(g)
	grid.cell_changed.connect(_on_cell_changed)


func total() -> int:
	var t := 0
	for v in grid.water:
		t += v
	for v in drop_vol:
		t += v
	return t


## Momentum flux at a point; rock masks stale history after terrain lands.
func sample_flow(pos: Vector2) -> Vector2:
	var c := grid.world_to_cell(pos)
	return Vector2.ZERO if grid.is_solid(c.x, c.y) else motion.sample(c)


## Cross-section average: a one-cell jet touches only part of a tall body.
func sample_contact(pos: Vector2, half: Vector2) -> Vector2:
	var sum := Vector2.ZERO
	for oy in [-0.75, 0.0, 0.75]:
		for ox in [-0.65, 0.65]:
			sum += sample_flow(pos + Vector2(half.x * ox, half.y * oy))
	return sum / 6.0


## Geometric immersion: a partial cell occupies its lower portion only.
func immersion(pos: Vector2, half: Vector2) -> float:
	var wet := 0.0
	for oy in [-0.75, 0.0, 0.75]:
		for ox in [-0.65, 0.65]:
			var p := pos + Vector2(half.x * ox, half.y * oy)
			var c := grid.world_to_cell(p)
			var level := float(grid.get_water(c.x, c.y)) / Balance.WATER_MAX
			if not grid.is_solid(c.x, c.y) and level > 0.0 and p.y >= (c.y + 1.0 - level) * Balance.CELL:
				wet += 1.0
	return wet / 6.0


func _transfer_flow(a: Vector2i, b: Vector2i, amount: int) -> void:
	var velocity := Vector2(b - a) * (Balance.CELL / Balance.WATER_TICK)
	var f := float(amount) / Balance.WATER_MAX * 0.5
	motion.record(a, velocity, f)
	motion.record(b, velocity, f)


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
	pressure.surfaces.clear()
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
	var left := mini(amount, (Balance.WATER_MAX_DROPS - drop_count()) * Balance.WATER_DROP_UNITS)
	while left > 0:
		var v := mini(Balance.WATER_DROP_UNITS, left)
		left -= v
		# spread releases over the tick so the stream is continuous, not pulsed
		var lag := randf()
		var vy0 := 30.0 + 60.0 * (1.0 - lag)
		drop_pos.append(Vector2(cx + randf_range(-3.0, 3.0) + vx * Balance.WATER_TICK * (1.0 - lag), (y + 1) * 16.0 + 0.5 + vy0 * Balance.WATER_TICK * (1.0 - lag)))
		drop_vel.append(Vector2(vx + randf_range(-4.0, 4.0), vy0))
		drop_vol.append(v)
		drop_src.append(y * grid.w + x)


func _emit_jet(c: Vector2i, side: int, amount: int, speed: float) -> void:
	var p := Vector2((c.x + (1 if side > 0 else 0)) * Balance.CELL + side * 0.5, (c.y + 0.5) * Balance.CELL)
	var left := amount
	while left > 0:
		var units := mini(Balance.WATER_DROP_UNITS, left)
		left -= units
		drop_pos.append(p + Vector2(0, randf_range(-2.0, 2.0)))
		drop_vel.append(Vector2(side * speed, randf_range(-6.0, 6.0)))
		drop_vol.append(units)
		drop_src.append(grid.idx(c.x, c.y))
	motion.record(c, Vector2(side * speed, 0), float(amount) / Balance.WATER_MAX * 0.5)
	motion.record(c + Vector2i(side, 0), Vector2(side * speed, 0), float(amount) / Balance.WATER_MAX)
	pressure.jets += 1
	pressure.discharge += amount


func update_drops(delta: float) -> void:
	splashes.clear()
	var i := drop_count() - 1
	while i >= 0:
		var p := drop_pos[i]
		var v := drop_vel[i]
		if grid.solid_at(p):
			# Falling terrain may overwrite a droplet between frames. Displace
			# only into an immediate open neighbour, never through solid rock.
			var origin := grid.world_to_cell(p)
			var displaced := false
			for d in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
				var n: Vector2i = origin + d
				if _open(n.x, n.y):
					p = grid.cell_center(n)
					v = Vector2.ZERO
					displaced = true
					break
			if not displaced:
				lost += drop_vol[i]  # same explicit squeeze policy as grid water
				_remove_drop(i)
				i -= 1
				continue
		v.y = minf(v.y + Balance.WATER_DROP_GRAVITY * delta, Balance.WATER_DROP_MAX_FALL)
		var distance := v.length() * delta
		var samples := maxi(1, ceili(distance / Balance.WATER_DROP_SWEEP))
		var dt := delta / samples
		var land := Vector2i(-1, -1)
		for k in samples:
			var np := p + v * dt
			var c := grid.world_to_cell(np)
			if grid.is_solid(c.x, c.y):
				land = grid.world_to_cell(p)
				break
			p = np
			motion.record(c, v, float(drop_vol[i]) / Balance.WATER_MAX * dt / Balance.WATER_TICK)
			if grid.get_water(c.x, c.y) >= Balance.WATER_MAX / 3 or (grid.is_solid(c.x, c.y + 1) and p.y > c.y * 16.0 + 12.0):
				land = c
				break
		if land.x >= 0:
			var remaining := _deposit(land, drop_vol[i])
			if remaining == 0:
				if randf() < 0.35:
					splashes.append(p)
				_remove_drop(i)
			else:
				# An obstructed full column retains overflow in its droplets until
				# a connected cell has room. No water vanishes at a landing.
				drop_vol[i] = remaining
				drop_pos[i] = p
				drop_vel[i] = Vector2.ZERO
		else:
			drop_pos[i] = p
			drop_vel[i] = v
		i -= 1


func _remove_drop(i: int) -> void:
	# Keep emission order: the existing renderer connects successive droplets.
	drop_pos.remove_at(i)
	drop_vel.remove_at(i)
	drop_vol.remove_at(i)
	drop_src.remove_at(i)


func _deposit(c: Vector2i, vol: int) -> int:
	deposits += 1
	var queue: Array[Vector2i] = [c]
	var seen: Dictionary = {c: true}
	var i := 0
	while vol > 0 and i < queue.size():
		var cell := queue[i]
		i += 1
		if not _open(cell.x, cell.y):
			continue
		var room := Balance.WATER_MAX - grid.get_water(cell.x, cell.y)
		var mv := mini(room, vol)
		if mv > 0:
			grid.set_water(cell.x, cell.y, grid.get_water(cell.x, cell.y) + mv)
			vol -= mv
			wake(cell.x, cell.y)
		if vol > 0:
			# Only contiguous open neighbours, never past a rock ceiling/wall.
			for d in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
				var n: Vector2i = cell + d
				if not seen.has(n) and queue.size() < Balance.WATER_DEPOSIT_BUDGET and _open(n.x, n.y):
					seen[n] = true
					queue.append(n)
	return vol


func step() -> void:
	motion.advance(Balance.WATER_TICK)
	pressure.begin_step()
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
		# Head-driven free outflow. Remove the exact emitted volume first.
		for side in ([-1, 1] if flip else [1, -1]):
			var speed := pressure.outlet_speed(c, side)
			if speed <= 0.0:
				continue
			var slots := Balance.WATER_MAX_DROPS - drop_count()
			var out := mini(mini(lv, Balance.WATER_JET_DISCHARGE), slots * Balance.WATER_DROP_UNITS)
			if out <= 0:
				continue
			lv -= out
			grid.set_water(x, y, lv)
			_emit_jet(c, side, out, speed)
			changed = true
			moves += out
		# 1) fall: into open air as droplets, into water cell-to-cell
		if _open(x, y + 1) and grid.get_water(x, y + 1) == 0 and drop_pos.size() < Balance.WATER_MAX_DROPS:
			var out := mini(mini(lv, Balance.WATER_EMIT_PER_TICK), (Balance.WATER_MAX_DROPS - drop_count()) * Balance.WATER_DROP_UNITS)
			_emit(x, y, out)
			_transfer_flow(c, c + Vector2i.DOWN, out)
			lv -= out
			grid.set_water(x, y, lv)
			changed = true
			moves += out
		elif _open(x, y + 1):
			var below := grid.get_water(x, y + 1)
			if below < Balance.WATER_MAX:
				var mv := mini(lv, Balance.WATER_MAX - below)
				grid.set_water(x, y + 1, below + mv)
				_transfer_flow(c, c + Vector2i.DOWN, mv)
				lv -= mv
				grid.set_water(x, y, lv)
				changed = true
				moves += mv
		# 2) spread sideways toward lower neighbours (only once resting)
		if lv > 0 and (not _open(x, y + 1) or grid.get_water(x, y + 1) >= Balance.WATER_MAX):
			var sides: Array = [Vector2i(-1, 0), Vector2i(1, 0)] if flip else [Vector2i(1, 0), Vector2i(-1, 0)]
			# sheet flow: water lying on a floor runs toward the nearest edge it
			# can pour over, instead of only levelling out neighbour by neighbour
			var run_dir := _drop_dir(x, y) if not _open(x, y + 1) else 0
			if run_dir != 0:
				sides = [Vector2i(run_dir, 0), Vector2i(-run_dir, 0)]
			for d in sides:
				if lv <= 0:
					break
				var nx: int = x + d.x
				if not _open(nx, y):
					continue
				var ln := grid.get_water(nx, y)
				var diff := lv - ln
				var below_n := grid.get_water(nx, y + 1)
				# a lone unit only spills into genuinely empty space below; this stops
				# single-unit films from flip-flopping at the rim of a near-full pool
				var drop_off := _open(nx, y + 1) and (below_n == 0 if lv == 1 else below_n < Balance.WATER_MAX)
				var mv2 := 0
				if d.x == run_dir and not drop_off and lv >= 2 and ln <= lv and ln < Balance.WATER_MAX and not _open(nx, y + 1):
					# sheet flow runs only along a floor (receiver also on solid), so
					# it keeps flowing the same way instead of being levelled back
					mv2 = mini(maxi(1, (lv + 1) / 2), Balance.WATER_MAX - ln)
				elif drop_off and ln < Balance.WATER_MAX:
					# the neighbour pours away below: water runs over the lip
					# quickly instead of dribbling out one unit per tick
					mv2 = mini(maxi(1, (lv + 1) / 2), Balance.WATER_MAX - ln)
				elif diff >= 2:
					mv2 = maxi(1, diff / 2)
				if mv2 > 0:
					grid.set_water(nx, y, ln + mv2)
					_transfer_flow(c, Vector2i(nx, y), mv2)
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


const RUN_SCAN := 12


## Direction (-1/+1) of the nearest edge along this floor where water can pour
## down, within RUN_SCAN cells; 0 if none.
func _drop_dir(x: int, y: int) -> int:
	var best := RUN_SCAN + 1
	var dir := 0
	for s in [-1, 1]:
		for k in range(1, RUN_SCAN + 1):
			var cx: int = x + s * k
			if not _open(cx, y):
				break
			if _open(cx, y + 1) and grid.get_water(cx, y + 1) < Balance.WATER_MAX:
				if k < best:
					best = k
					dir = s
				break
	return dir


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
