class_name RouteCheck
extends RefCounted
## Conservative traversal model used to prove that generated mines are
## completable WITHOUT digging, using only spawn abilities (walk, fall,
## single jump of 3 cells, ladders, one-way platforms). The real player is
## strictly more capable (air jet, wall jumps, drilling), so passing here is a
## safe guarantee.

const JUMP_CELLS := 3
const JUMP_REACH := 2


static func body_ok(g: TerrainGrid, x: int, y: int, open_cells: Dictionary = {}) -> bool:
	return _free(g, x, y, open_cells) and _free(g, x, y - 1, open_cells)


static func _free(g: TerrainGrid, x: int, y: int, open_cells: Dictionary) -> bool:
	if not g.in_bounds(x, y):
		return false
	if open_cells.has(Vector2i(x, y)):
		return true
	return not g.is_solid(x, y)


static func _on_ladder(g: TerrainGrid, x: int, y: int) -> bool:
	return g.get_mat(x, y) == Cell.LADDER or g.get_mat(x, y - 1) == Cell.LADDER


static func _grounded(g: TerrainGrid, x: int, y: int, open_cells: Dictionary) -> bool:
	if open_cells.has(Vector2i(x, y + 1)):
		return false
	return Cell.supports(g.get_mat(x, y + 1)) or _on_ladder(g, x, y) or g.get_mat(x, y + 1) == Cell.LADDER


## Returns every feet-cell reachable from `start`.
static func reachable(g: TerrainGrid, start: Vector2i, open_cells: Dictionary = {}) -> Dictionary:
	var seen: Dictionary = {}
	if not body_ok(g, start.x, start.y, open_cells):
		return seen
	var q: Array[Vector2i] = [start]
	seen[start] = true
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for n in _neighbours(g, c, open_cells):
			if not seen.has(n):
				seen[n] = true
				q.append(n)
	return seen


static func _neighbours(g: TerrainGrid, c: Vector2i, open_cells: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x := c.x
	var y := c.y
	var ladder := _on_ladder(g, x, y)
	var grounded := _grounded(g, x, y, open_cells)
	if not grounded and not ladder:
		# falling: straight down, with one cell of air drift either side
		if body_ok(g, x, y + 1, open_cells):
			out.append(Vector2i(x, y + 1))
			for dx in [-1, 1]:
				if body_ok(g, x + dx, y, open_cells) and body_ok(g, x + dx, y + 1, open_cells):
					out.append(Vector2i(x + dx, y + 1))
		return out
	for dx in [-1, 1]:
		if body_ok(g, x + dx, y, open_cells):
			out.append(Vector2i(x + dx, y))
	if ladder:
		if body_ok(g, x, y - 1, open_cells):
			out.append(Vector2i(x, y - 1))
	if body_ok(g, x, y + 1, open_cells) and (ladder or g.get_mat(x, y + 1) == Cell.LADDER or g.get_mat(x, y + 1) == Cell.PLATFORM):
		out.append(Vector2i(x, y + 1))
	if grounded or ladder:
		for dy in range(1, JUMP_CELLS + 1):
			if not body_ok(g, x, y - dy, open_cells):
				break
			out.append(Vector2i(x, y - dy))
			for sgn in [-1, 1]:
				for k in range(1, JUMP_REACH + 1):
					var nx: int = x + sgn * k
					if not body_ok(g, nx, y - dy, open_cells):
						break
					out.append(Vector2i(nx, y - dy))
	return out


static func can_reach(g: TerrainGrid, a: Vector2i, b: Vector2i, open_cells: Dictionary = {}, tolerance: int = 1) -> bool:
	var seen := reachable(g, a, open_cells)
	if seen.has(b):
		return true
	for dy in range(-tolerance, tolerance + 1):
		for dx in range(-tolerance, tolerance + 1):
			if seen.has(b + Vector2i(dx, dy)):
				return true
	return false


## Flood fill over everything that is not permanently impassable. Any open cell
## not reached is a sealed pocket (a potential softlock if the player got in).
static func sealed_pockets(g: TerrainGrid, start: Vector2i, passable_extra: Dictionary = {}) -> Array[Vector2i]:
	var seen := PackedByteArray()
	seen.resize(g.w * g.h)
	var q: Array[Vector2i] = [start]
	seen[g.idx(start.x, start.y)] = 1
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not g.in_bounds(n.x, n.y) or seen[g.idx(n.x, n.y)]:
				continue
			var m := g.get_mat(n.x, n.y)
			var wall := Cell.is_solid(m) and (m == Cell.BEDROCK or m == Cell.ALLOY or g.has_flag(n.x, n.y, Cell.F_PROTECTED))
			if wall and not passable_extra.has(n):
				continue
			seen[g.idx(n.x, n.y)] = 1
			q.append(n)
	var pockets: Array[Vector2i] = []
	for y in g.h:
		for x in g.w:
			if not g.is_solid(x, y) and not seen[g.idx(x, y)]:
				pockets.append(Vector2i(x, y))
	return pockets
