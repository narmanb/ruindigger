class_name GridPath
extends RefCounted
## Bounded BFS over grid cells (4-neighbour). Cheap enough to run a few times
## per second per enemy; returns the cell sequence excluding the start.

const MAX_NODES := 1600


static func find(g: TerrainGrid, start: Vector2i, goal: Vector2i, radius: int, ok: Callable) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if start == goal:
		return out
	# if the goal itself is not walkable (player standing in mid-air), aim for the
	# nearest walkable cell around it
	var targets: Dictionary = {}
	for dy in range(-2, 3):
		for dx in range(-1, 2):
			var t := goal + Vector2i(dx, dy)
			if ok.call(t):
				targets[t] = true
	if targets.is_empty():
		return out
	var came: Dictionary = {start: start}
	var q: Array[Vector2i] = [start]
	var head := 0
	var found := Vector2i(-9999, -9999)
	while head < q.size() and head < MAX_NODES:
		var c: Vector2i = q[head]
		head += 1
		if targets.has(c):
			found = c
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if came.has(n):
				continue
			if absi(n.x - start.x) > radius or absi(n.y - start.y) > radius:
				continue
			if not ok.call(n):
				continue
			came[n] = c
			q.append(n)
	if found.x == -9999:
		return out
	var c2 := found
	while c2 != start:
		out.push_front(c2)
		c2 = came[c2]
	return out
