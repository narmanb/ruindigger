class_name WaterMotion
extends RefCounted
## Sparse recent momentum, measured only from actual transfers. Fullness alone
## never creates a current. Values are volume-weighted pixels/second.

var cells: Dictionary = {}       # Vector2i -> Vector2


func advance(delta: float) -> void:
	var decay := exp(-delta / Balance.WATER_FLOW_MEMORY)
	for c in cells.keys():
		var v: Vector2 = cells[c] * decay
		if v.length_squared() < 0.25:
			cells.erase(c)
		else:
			cells[c] = v


func record(c: Vector2i, velocity: Vector2, fraction: float) -> void:
	if not cells.has(c) and cells.size() >= Balance.WATER_FLOW_CELL_CAP:
		return
	var prev: Vector2 = cells.get(c, Vector2.ZERO)
	cells[c] = (prev + velocity * fraction).limit_length(Balance.WATER_FLOW_MAX)


func sample(c: Vector2i) -> Vector2:
	return cells.get(c, Vector2.ZERO)
