class_name WaterErosion
extends RefCounted
## Exposure accumulates only beside actual moving water. Damage goes through the
## mine callback, so ore, gas, collapse and debris retain their normal semantics.

var grid: TerrainGrid
var water: WaterSim
var damage: Callable
var exposure: Dictionary = {}  # solid face cell -> accumulated seconds
var last_edits := 0
var total_edits := 0
var checked := 0
var wear_points: Array[Vector2i] = []
var _acc := 0.0
var _cursor := 0
var _edit_cursor := 0
const DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]


func _init(g: TerrainGrid, sim: WaterSim, damage_cell: Callable) -> void:
	grid = g
	water = sim
	damage = damage_cell


func eligible(c: Vector2i) -> bool:
	return Balance.EROSION_MATERIAL.has(grid.get_mat(c.x, c.y)) and not grid.has_flag(c.x, c.y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE | Cell.F_WATER_SAFE)


func update(delta: float) -> void:
	_acc += delta
	if _acc < Balance.EROSION_TICK:
		return
	# One bounded pass after a long frame, rather than a destructive catch-up.
	var dt := minf(_acc, Balance.EROSION_TICK * 2.0)
	_acc = 0.0
	last_edits = 0
	checked = 0
	wear_points.clear()
	var candidates: Dictionary = {}
	var cells: Array = water.motion.cells.keys()
	if not cells.is_empty():
		_cursor %= cells.size()
		for k in mini(cells.size(), Balance.EROSION_SCAN_BUDGET):
			var wet: Vector2i = cells[(_cursor + k) % cells.size()]
			checked += 1
			if grid.is_solid(wet.x, wet.y):
				continue
			var flow: Vector2 = water.motion.sample(wet)
			if flow.length() < Balance.EROSION_FLOW_THRESHOLD:
				continue
			for d in DIRS:
				var solid: Vector2i = wet + d
				if eligible(solid):
					candidates[solid] = maxf(float(candidates.get(solid, 0.0)), flow.length())
		_cursor += checked
	for c in exposure.keys():
		if not eligible(c):
			exposure.erase(c)
		elif not candidates.has(c):
			# Discovery is budgeted, but omission is not evidence of dry rock.
			# Recheck the four neighbours of at most FACE_CAP tracked faces.
			var strength := 0.0
			for d in DIRS:
				var wet: Vector2i = c + d
				if not grid.is_solid(wet.x, wet.y):
					strength = maxf(strength, water.motion.sample(wet).length())
			if strength >= Balance.EROSION_FLOW_THRESHOLD:
				candidates[c] = strength
				continue
			var seconds: float = exposure[c] - dt * Balance.EROSION_RECOVERY
			if seconds <= 0:
				exposure.erase(c)
			else:
				exposure[c] = seconds
	for c in candidates:
		if not exposure.has(c) and exposure.size() >= Balance.EROSION_FACE_CAP:
			continue
		var seconds: float = minf(float(exposure.get(c, 0.0)) + dt, Balance.EROSION_WARMUP * 2.0)
		exposure[c] = seconds
	var faces: Array = candidates.keys()
	if faces.is_empty():
		return
	_edit_cursor %= faces.size()
	for k in faces.size():
		var c: Vector2i = faces[(_edit_cursor + k) % faces.size()]
		if not eligible(c) or float(exposure.get(c, 0.0)) < Balance.EROSION_WARMUP:
			continue
		if last_edits >= Balance.EROSION_EDIT_BUDGET:
			break
		var material := grid.get_mat(c.x, c.y)
		var strength := clampf((float(candidates[c]) - Balance.EROSION_FLOW_THRESHOLD) / Balance.EROSION_FLOW_SCALE, 0.0, Balance.EROSION_MAX_STRENGTH)
		var amount: float = dt * strength * Balance.EROSION_DPS * Balance.EROSION_MATERIAL[material]
		damage.call(c, amount, 0, true, "erosion")
		last_edits += 1
		total_edits += 1
		wear_points.append(c)
		if not eligible(c):
			exposure.erase(c)
	_edit_cursor += maxi(1, last_edits)
