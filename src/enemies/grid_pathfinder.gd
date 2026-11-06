class_name GridPathfinder
extends RefCounted
## Throttled breadth-first search over open terrain cells. Shared by enemies so
## that pathfinding cost stays bounded and is never run per-enemy per-frame.

static func find_path(grid: TerrainGrid, from: Vector2i, to: Vector2i,
		max_nodes: int = 4000, allow_soft_tunnel: bool = false) -> Array:
	var start: Vector2i = _nearest_open(grid, from, 4)
	var goal: Vector2i = _nearest_open(grid, to, 4)
	if start == goal:
		return [goal]
	var open: Dictionary = {start: true}
	var came: Dictionary = {start: -1}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	var visited: int = 0
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size() and visited < max_nodes:
		var cur: Vector2i = queue[head]
		head += 1
		visited += 1
		if cur == goal:
			return _reconstruct(came, cur, start)
		for d: Vector2i in dirs:
			var n: Vector2i = cur + d
			if not grid.in_bounds(n.x, n.y) or came.has(n):
				continue
			var mat: int = grid.get_material(n.x, n.y)
			if mat == Balance.Mat.EMPTY:
				pass
			elif allow_soft_tunnel and mat == Balance.Mat.SOIL:
				pass
			else:
				continue
			came[n] = cur
			queue.append(n)
	return []

static func _reconstruct(came: Dictionary, cur: Vector2i, start: Vector2i) -> Array:
	var out: Array = [cur]
	while cur != start:
		cur = came[cur]
		out.append(cur)
	out.reverse()
	return out

static func _nearest_open(grid: TerrainGrid, c: Vector2i, r: int) -> Vector2i:
	if grid.in_bounds(c.x, c.y) and grid.get_material(c.x, c.y) == Balance.Mat.EMPTY:
		return c
	for rad in range(1, r + 1):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var n: Vector2i = Vector2i(c.x + dx, c.y + dy)
				if grid.in_bounds(n.x, n.y) and grid.get_material(n.x, n.y) == Balance.Mat.EMPTY:
					return n
	return c

static func has_line_of_sight(grid: TerrainGrid, a: Vector2, b: Vector2) -> bool:
	var steps: int = int(a.distance_to(b) / (Balance.CELL * 0.5)) + 1
	for i in range(1, steps):
		var p: Vector2 = a.lerp(b, float(i) / steps)
		var c: Vector2i = grid.world_to_cell(p)
		if grid.get_material(c.x, c.y) != Balance.Mat.EMPTY:
			return false
	return true
