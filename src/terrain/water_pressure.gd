class_name WaterPressure
extends RefCounted
## Bounded connected wet-region head approximation. Cached for one water tick,
## only queried at active, freely draining side openings. Actual local inventory
## and refill constrain discharge; reservoir area does not multiply velocity.

var grid: TerrainGrid
var surfaces: Dictionary = {}
var work := 0
var jets := 0
var discharge := 0
const DIRS := [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]


func _init(g: TerrainGrid) -> void:
	grid = g


func begin_step() -> void:
	surfaces.clear()
	work = 0
	jets = 0
	discharge = 0


func head_at(c: Vector2i) -> float:
	if surfaces.has(c):
		return maxf(0.0, c.y + 1.0 - float(surfaces[c]))
	if work >= Balance.WATER_PRESSURE_BUDGET:
		return 0.0
	var queue: Array[Vector2i] = [c]
	var seen: Dictionary = {c: true}
	var i := 0
	var top := c.y + 1.0 - float(grid.get_water(c.x, c.y)) / Balance.WATER_MAX
	while i < queue.size() and i < Balance.WATER_PRESSURE_REGION and work < Balance.WATER_PRESSURE_BUDGET:
		var p := queue[i]
		i += 1
		work += 1
		top = minf(top, p.y + 1.0 - float(grid.get_water(p.x, p.y)) / Balance.WATER_MAX)
		for d in DIRS:
			var n: Vector2i = p + d
			if not seen.has(n) and not grid.is_solid(n.x, n.y) and grid.get_water(n.x, n.y) >= Balance.WATER_MAX / 2:
				seen[n] = true
				if queue.size() < Balance.WATER_PRESSURE_REGION:
					queue.append(n)
	for p in queue:
		surfaces[p] = top
	return maxf(0.0, c.y + 1.0 - top)


func outlet_speed(c: Vector2i, side: int) -> float:
	var n := c + Vector2i(side, 0)
	if grid.is_solid(n.x, n.y) or grid.get_water(n.x, n.y) >= Balance.WATER_MAX / 2 or grid.get_water(n.x, n.y - 1) >= Balance.WATER_MAX / 2:
		return 0.0  # submerged equalizing pools are handled by ordinary transfers
	if grid.get_water(c.x, c.y) < Balance.WATER_PRESSURE_MIN_FILL:
		return 0.0
	if not grid.is_solid(c.x, c.y + 1) and grid.get_water(c.x, c.y + 1) < Balance.WATER_MAX / 2:
		return 0.0  # unsupported streams fall normally
	var head := head_at(c) - Balance.WATER_PRESSURE_FREE_HEAD
	if head <= 0.0:
		return 0.0
	return minf(Balance.WATER_JET_MAX_SPEED, sqrt(head) * Balance.WATER_JET_HEAD_SPEED)
