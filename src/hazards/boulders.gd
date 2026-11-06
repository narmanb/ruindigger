class_name Boulders
extends RefCounted
## Rule for loose basalt (shared by the generator and the runtime collapse system):
## a connected basalt mass of at most BOULDER_MAX_CELLS falls when
##   * none of its cells touches an anchoring solid (sediment, cracked wall, gas
##     sac, alloy, bedrock, or any protected cell), and
##   * none of its cells rests on a solid cell outside the mass.
## Bigger masses count as bedded into the strata and never fall.


static func is_anchor(g: TerrainGrid, x: int, y: int) -> bool:
	var m := g.get_mat(x, y)
	if not Cell.is_solid(m):
		return false
	if g.has_flag(x, y, Cell.F_PROTECTED):
		return true
	return m != Cell.HARD and m != Cell.LOOSE


## Returns the cells of the unsupported basalt mass containing `start`, or [] if
## it is anchored, resting, too big, or `start` is not basalt.
static func unsupported_mass(g: TerrainGrid, start: Vector2i, limit: int = Balance.BOULDER_MAX_CELLS) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if g.get_mat(start.x, start.y) != Cell.HARD or g.has_flag(start.x, start.y, Cell.F_PROTECTED):
		return none
	var cells: Array[Vector2i] = [start]
	var seen: Dictionary = {start: true}
	var head := 0
	while head < cells.size():
		var c: Vector2i = cells[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			if g.get_mat(n.x, n.y) == Cell.HARD and not g.has_flag(n.x, n.y, Cell.F_PROTECTED):
				seen[n] = true
				cells.append(n)
				if cells.size() > limit:
					return none
			elif is_anchor(g, n.x, n.y):
				return none
	for c in cells:
		var b := Vector2i(c.x, c.y + 1)
		if not seen.has(b) and g.is_solid(b.x, b.y):
			return none
	return cells
