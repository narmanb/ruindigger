class_name SteamField
extends RefCounted
## Steam is a short-lived gas field, not a third liquid. It rises through open
## cells, slides sideways under ceilings, thins out and disappears. The number
## of live cells is hard-capped, so no reaction can flood the screen or the CPU.

var grid: TerrainGrid
var cells: Dictionary = {}      # Vector2i -> density
var _acc := 0.0
var made := 0.0                 # total density ever emitted (accounting / tests)
var peak_cells := 0


func _init(g: TerrainGrid) -> void:
	grid = g


func add(c: Vector2i, amount: float) -> void:
	if amount <= 0.0 or not grid.in_bounds(c.x, c.y) or grid.is_solid(c.x, c.y):
		return
	# steam made under water bubbles straight up and comes out at the surface
	var guard := 0
	while _submerged(c) and guard < 40:
		var up := Vector2i(c.x, c.y - 1)
		if not grid.in_bounds(up.x, up.y) or grid.is_solid(up.x, up.y):
			break
		c = up
		guard += 1
	cells[c] = minf(Balance.STEAM_MAX_DENSITY, float(cells.get(c, 0.0)) + amount)
	made += amount


func density(c: Vector2i) -> float:
	return float(cells.get(c, 0.0))


func total() -> float:
	var t := 0.0
	for v in cells.values():
		t += float(v)
	return t


func update(delta: float) -> void:
	_acc += delta
	var n := 0
	while _acc >= Balance.STEAM_TICK and n < 2:
		_acc -= Balance.STEAM_TICK
		step()
		n += 1


## Steam moves through air, not through standing water.
func _open(c: Vector2i) -> bool:
	return grid.in_bounds(c.x, c.y) and not grid.is_solid(c.x, c.y) and grid.get_water(c.x, c.y) < Balance.WATER_MAX / 4


func _submerged(c: Vector2i) -> bool:
	return grid.in_bounds(c.x, c.y) and grid.get_water(c.x, c.y) >= Balance.WATER_MAX / 4


## Signed distance along this row to the nearest open cell with open air above
## it (a chimney), scanning while the row stays open. 0 if none in reach.
func _nearest_vent(c: Vector2i) -> int:
	for dist in range(1, Balance.STEAM_VENT_SCAN + 1):
		for sgn in [-1, 1]:
			var x: int = c.x + sgn * dist
			if not _open(Vector2i(x, c.y)):
				continue
			# the row must be open all the way there
			var clear := true
			for k in range(1, dist):
				if not _open(Vector2i(c.x + sgn * k, c.y)):
					clear = false
					break
			if clear and _open(Vector2i(x, c.y - 1)):
				return sgn * dist
	return 0


func step() -> void:
	if cells.is_empty():
		return
	var next: Dictionary = {}
	for c in cells.keys():
		var d: float = float(cells[c]) * Balance.STEAM_KEEP - Balance.STEAM_DECAY
		if d <= Balance.STEAM_MIN:
			continue
		var up := Vector2i(c.x, c.y - 1)
		if _submerged(c):
			# water flowed over it: the bubble keeps rising until it reaches air
			if grid.in_bounds(up.x, up.y) and not grid.is_solid(up.x, up.y):
				next[up] = float(next.get(up, 0.0)) + d
			continue
		if _open(up):
			# most of it rises, a little lingers
			next[up] = float(next.get(up, 0.0)) + d * 0.72
			next[c] = float(next.get(c, 0.0)) + d * 0.28
		else:
			# under a ceiling: drift toward the nearest way up if there is one
			var vent_dx := _nearest_vent(c)
			if vent_dx != 0:
				var s2 := Vector2i(c.x + signi(vent_dx), c.y)
				next[s2] = float(next.get(s2, 0.0)) + d * 0.85
				next[c] = float(next.get(c, 0.0)) + d * 0.15
				continue
			# otherwise creep both ways; pressure builds if boxed in
			var sides: Array[Vector2i] = []
			for s in [Vector2i(c.x - 1, c.y), Vector2i(c.x + 1, c.y)]:
				if _open(s):
					sides.append(s)
			if sides.is_empty():
				next[c] = float(next.get(c, 0.0)) + d
			else:
				next[c] = float(next.get(c, 0.0)) + d * 0.4
				for s in sides:
					next[s] = float(next.get(s, 0.0)) + d * 0.6 / sides.size()
	for c in next.keys():
		next[c] = minf(Balance.STEAM_MAX_DENSITY, float(next[c]))
	if next.size() > Balance.STEAM_MAX_CELLS:
		# keep the densest cells; thin wisps are dropped first
		var keys: Array = next.keys()
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return float(next[a]) > float(next[b]))
		var trimmed: Dictionary = {}
		for i in Balance.STEAM_MAX_CELLS:
			trimmed[keys[i]] = next[keys[i]]
		next = trimmed
	cells = next
	peak_cells = maxi(peak_cells, cells.size())
