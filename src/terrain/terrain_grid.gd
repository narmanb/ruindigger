class_name TerrainGrid
extends Node
## Authoritative, serialisable terrain model for one mine.
##
## The grid owns all mutable world state (material, accumulated damage, ore
## payload, fog-of-war). Visuals (TileMapLayer) and collision (per-chunk
## StaticBody2D) are *derived* from it and only rebuilt for the chunks that
## actually changed. Nothing else in the game mutates terrain.

signal cell_changed(cx: int, cy: int, material: int)
signal chunk_dirty(cx: int, cy: int)
signal ore_mined(ore_id: int, cell: Vector2i)

const N := 1
const E := 2
const S := 4
const W := 8

const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var w: int = 0
var h: int = 0
var tile_size: int = Balance.CELL
var chunk: int = Balance.CHUNK

var material := PackedByteArray()
var damage := PackedByteArray()      # accumulated hit points removed
var ore := PackedByteArray()         # 0 = none, else Balance.ORE_TYPES id
var explored := PackedByteArray()    # fog of war
var gas := {}                        # cell index -> gas amount (int)
var variant := PackedByteArray()     # baked per-cell tile variant choice

var strata: PackedStringArray = PackedStringArray()   # stratum name per row band
var protected_cells: Dictionary = {}                   # cells never collapse / never mined
var spawn_cell := Vector2i.ZERO
var lift_cell := Vector2i.ZERO
var relic_cell := Vector2i.ZERO

var _chunks_x: int = 0
var _chunks_y: int = 0
var _chunk_bodies: Dictionary = {}     # chunk key -> StaticBody2D
var _chunk_layer: Node2D
var _collision_layer: int = 1

var _dirty: Dictionary = {}

func setup(grid_w: int, grid_h: int) -> void:
	w = grid_w
	h = grid_h
	var n: int = w * h
	material.resize(n)
	damage.resize(n)
	ore.resize(n)
	explored.resize(n)
	variant.resize(n)
	for i in n:
		material[i] = Balance.Mat.EMPTY
		damage[i] = 0
		ore[i] = 0
		explored[i] = 0
		variant[i] = i & 1
	gas.clear()
	protected_cells.clear()
	_chunks_x = int(ceil(float(w) / chunk))
	_chunks_y = int(ceil(float(h) / chunk))

func idx(x: int, y: int) -> int:
	return y * w + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h

func get_material(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return Balance.Mat.BEDROCK   # outside the map is solid
	return material[idx(x, y)]

func is_solid(x: int, y: int) -> bool:
	return get_material(x, y) != Balance.Mat.EMPTY

func set_material(x: int, y: int, mat: int) -> void:
	if not in_bounds(x, y):
		return
	var i := idx(x, y)
	if material[i] == mat:
		return
	material[i] = mat
	damage[i] = 0
	if mat == Balance.Mat.EMPTY:
		ore[i] = 0
	mark_dirty(x, y)
	cell_changed.emit(x, y, mat)

func get_damage(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return damage[idx(x, y)]

func get_ore(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return ore[idx(x, y)]

func set_ore(x: int, y: int, id: int) -> void:
	if not in_bounds(x, y):
		return
	ore[idx(x, y)] = id

func is_explored(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return explored[idx(x, y)] != 0

func mark_explored(x: int, y: int, radius: int = 0) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius + radius:
				continue
			var nx := x + dx
			var ny := y + dy
			if in_bounds(nx, ny):
				explored[idx(nx, ny)] = 1

func is_protected(x: int, y: int) -> bool:
	return protected_cells.has(idx(x, y))

func protect(x: int, y: int, radius: int = 0) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var nx := x + dx
			var ny := y + dy
			if in_bounds(nx, ny):
				protected_cells[idx(nx, ny)] = true

# ---------------------------------------------------------------------------
# Damage / mining
# ---------------------------------------------------------------------------

## Returns true when the tile breaks on this call. `power` is drill strength.
func apply_damage(x: int, y: int, amount: int, miner_tier: int = 99) -> bool:
	if not in_bounds(x, y):
		return false
	var i := idx(x, y)
	var mat: int = material[i]
	if mat == Balance.Mat.EMPTY:
		return false
	if is_protected(x, y):
		return false
	if Balance.DRILL_MIN_TIER.get(mat, 99) > miner_tier:
		return false
	var hp: int = Balance.MATERIAL_HP.get(mat, 1)
	damage[i] = min(hp, damage[i] + amount)
	if damage[i] >= hp:
		_break(x, y)
		return true
	mark_dirty(x, y)
	cell_changed.emit(x, y, mat)
	return false

func can_mine(x: int, y: int, miner_tier: int) -> bool:
	if not in_bounds(x, y):
		return false
	var mat := material[idx(x, y)]
	if mat == Balance.Mat.EMPTY or is_protected(x, y):
		return false
	return Balance.DRILL_MIN_TIER.get(mat, 99) <= miner_tier

func _break(x: int, y: int) -> void:
	var i := idx(x, y)
	var ore_id: int = ore[i]
	material[i] = Balance.Mat.EMPTY
	damage[i] = 0
	ore[i] = 0
	gas.erase(i)
	mark_dirty(x, y)
	if ore_id != 0:
		ore_mined.emit(ore_id, Vector2i(x, y))
	cell_changed.emit(x, y, Balance.Mat.EMPTY)

## Damage a radius (explosions, collapses). Returns the list of cells broken.
func damage_radius(cx: int, cy: int, radius_cells: float, amount: int,
		miner_tier: int = 99, skip_protected: bool = true) -> Array:
	var broken: Array = []
	var r: int = int(ceil(radius_cells))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d := sqrt(float(dx * dx + dy * dy))
			if d > radius_cells:
				continue
			var nx := cx + dx
			var ny := cy + dy
			if not in_bounds(nx, ny):
				continue
			if skip_protected and is_protected(nx, ny):
				continue
			var falloff := 1.0 - (d / maxf(0.001, radius_cells)) * 0.5
			var amt := int(round(amount * falloff))
			if amt <= 0:
				continue
			if apply_damage(nx, ny, amt, miner_tier):
				broken.append(Vector2i(nx, ny))
	return broken

## The neighbour exposure mask used to pick the correct baked tile.
func mask_at(x: int, y: int) -> int:
	var m := 0
	if get_material(x, y - 1) == Balance.Mat.EMPTY:
		m |= N
	if get_material(x + 1, y) == Balance.Mat.EMPTY:
		m |= E
	if get_material(x, y + 1) == Balance.Mat.EMPTY:
		m |= S
	if get_material(x - 1, y) == Balance.Mat.EMPTY:
		m |= W
	return m

# ---------------------------------------------------------------------------
# Chunk bookkeeping
# ---------------------------------------------------------------------------

func mark_dirty(x: int, y: int) -> void:
	var cx: int = x / chunk
	var cy: int = y / chunk
	_dirty[Vector2i(cx, cy)] = true
	# Adjacent chunks need a refresh too: an edge change alters the neighbour's
	# exposure mask, and their collision runs may now connect.
	for oy in [-1, 0, 1]:
		for ox in [-1, 0, 1]:
			var nx: int = x + ox * chunk
			var ny: int = y + oy * chunk
			if in_bounds(nx, ny):
				_dirty[Vector2i(nx / chunk, ny / chunk)] = true

func flush_dirty(limit: int = 8) -> Array:
	var out: Array = []
	var keys: Array = _dirty.keys()
	var n: int = mini(limit, keys.size())
	for i in n:
		out.append(keys[i])
		_dirty.erase(keys[i])
	return out

func take_all_dirty() -> Array:
	var out := _dirty.keys()
	_dirty.clear()
	return out

# ---------------------------------------------------------------------------
# Collision derivation
# ---------------------------------------------------------------------------

func build_collision(parent: Node2D) -> void:
	_chunk_layer = parent
	for cy in _chunks_y:
		for cx in _chunks_x:
			rebuild_chunk_collision(cx, cy)

func rebuild_chunk_collision(cx: int, cy: int) -> void:
	var key: Vector2i = Vector2i(cx, cy)
	var body: StaticBody2D = _chunk_bodies.get(key)
	if body == null:
		body = StaticBody2D.new()
		body.collision_layer = _collision_layer
		body.collision_mask = 0
		body.position = Vector2(cx * chunk * tile_size, cy * chunk * tile_size)
		_chunk_layer.add_child(body)
		_chunk_bodies[key] = body
	for c in body.get_children():
		c.queue_free()
	_emit_runs(body, cx, cy)

func _emit_runs(body: StaticBody2D, cx: int, cy: int) -> void:
	var x0: int = cx * chunk
	var y0: int = cy * chunk
	var x1: int = mini(x0 + chunk, w)
	var y1: int = mini(y0 + chunk, h)
	for y in range(y0, y1):
		var run_start: int = -1
		for x in range(x0, x1 + 1):
			var solid: bool = x < x1 and material[idx(x, y)] != Balance.Mat.EMPTY
			if solid and run_start < 0:
				run_start = x
			elif not solid and run_start >= 0:
				_add_run_shape(body, run_start, y, x - run_start)
				run_start = -1

func _add_run_shape(body: StaticBody2D, x: int, y: int, length: int) -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(length * tile_size, tile_size)
	shape.shape = rect
	# Shapes are positioned relative to the chunk body, which already sits at the
	# chunk's world origin. Forgetting the subtraction here silently shifts all
	# collision away from the visible tiles.
	var origin: Vector2 = body.position
	shape.position = Vector2(x * tile_size + length * tile_size * 0.5 - origin.x,
			y * tile_size + tile_size * 0.5 - origin.y)
	body.add_child(shape)

# ---------------------------------------------------------------------------
# Queries used by AI, generation and the minimap
# ---------------------------------------------------------------------------

func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / tile_size)), int(floor(p.y / tile_size)))

func cell_to_world(c: Vector2i) -> Vector2:
	return Vector2(c.x * tile_size + tile_size * 0.5, c.y * tile_size + tile_size * 0.5)

func cell_top_left(c: Vector2i) -> Vector2:
	return Vector2(c.x * tile_size, c.y * tile_size)

func stratum_at(y: int) -> String:
	var band: int = int(float(y) / maxf(1.0, float(h)) * maxf(1.0, float(strata.size())))
	return strata[clampi(band, 0, strata.size() - 1)] if strata.size() > 0 else "dustworks"

## Breadth-first reachability over *currently open* cells. Used by generation
## validation and the anti-softlock checker.
func count_material(mat: int) -> int:
	var c := 0
	for i in material.size():
		if material[i] == mat:
			c += 1
	return c

# ---------------------------------------------------------------------------
# Flood fill / pathfinding
#
# These are on the hot path during generation (called once per candidate map
# and repeatedly by the softlock checkers), so they use flat packed arrays and
# integer indices rather than Dictionary-of-Vector2i, which is dramatically
# faster in GDScript.
# ---------------------------------------------------------------------------

## Returns a PackedByteArray where 1 marks a cell reachable from `from` through
## currently-open terrain. Also returns the reachable count via `count_out`.
func reach_mask(from: Vector2i, max_nodes: int = 200000) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(w * h)
	mask.fill(0)
	if not in_bounds(from.x, from.y) or is_solid(from.x, from.y):
		return mask
	var queue := PackedInt32Array()
	queue.resize(1024)
	var head := 0
	var tail := 0
	var start := idx(from.x, from.y)
	queue[tail] = start
	tail += 1
	mask[start] = 1
	var visited := 1
	while head < tail and visited < max_nodes:
		var cur: int = queue[head]
		head += 1
		var cx: int = cur % w
		var cy: int = cur / w
		if cx > 0 and _try_visit(mask, queue, tail, cur - 1, cx - 1, cy):
			tail += 1
			visited += 1
		if cx < w - 1 and _try_visit(mask, queue, tail, cur + 1, cx + 1, cy):
			tail += 1
			visited += 1
		if cy > 0 and _try_visit(mask, queue, tail, cur - w, cx, cy - 1):
			tail += 1
			visited += 1
		if cy < h - 1 and _try_visit(mask, queue, tail, cur + w, cx, cy + 1):
			tail += 1
			visited += 1
		if tail + 4 >= queue.size():
			queue.resize(queue.size() * 2)
	return mask

func _try_visit(mask: PackedByteArray, queue: PackedInt32Array, tail: int,
		nidx: int, nx: int, ny: int) -> bool:
	if mask[nidx] != 0:
		return false
	if material[nidx] != Balance.Mat.EMPTY:
		return false
	mask[nidx] = 1
	queue[tail] = nidx
	return true

## Like reach_mask, but movement is allowed through any cell the drill can
## eventually remove (soil / basalt / alloy). This is the true "can the player
## ever get there" flood, used to prove every placed reward is obtainable.
func reach_mask_diggable(from: Vector2i, max_nodes: int = 400000) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(w * h)
	mask.fill(0)
	if not in_bounds(from.x, from.y):
		return mask
	var queue := PackedInt32Array()
	queue.resize(1024)
	var head := 0
	var tail := 0
	var start := idx(from.x, from.y)
	queue[tail] = start
	tail += 1
	mask[start] = 1
	var visited := 1
	while head < tail and visited < max_nodes:
		if tail + 4 >= queue.size():
			queue.resize(queue.size() * 2)
		var cur: int = queue[head]
		head += 1
		var cx: int = cur % w
		var cy: int = cur / w
		if cx > 0 and _try_visit_diggable(mask, queue, tail, cur - 1):
			tail += 1
			visited += 1
		if cx < w - 1 and _try_visit_diggable(mask, queue, tail, cur + 1):
			tail += 1
			visited += 1
		if cy > 0 and _try_visit_diggable(mask, queue, tail, cur - w):
			tail += 1
			visited += 1
		if cy < h - 1 and _try_visit_diggable(mask, queue, tail, cur + w):
			tail += 1
			visited += 1
	return mask

func _try_visit_diggable(mask: PackedByteArray, queue: PackedInt32Array, tail: int,
		nidx: int) -> bool:
	if mask[nidx] != 0:
		return false
	if material[nidx] == Balance.Mat.BEDROCK:
		return false
	mask[nidx] = 1
	queue[tail] = nidx
	return true

## True if `to` is reachable from `from`. Early-exits as soon as it is found.
func reachable(from: Vector2i, to: Vector2i, max_nodes: int = 200000) -> bool:
	if not in_bounds(from.x, from.y) or not in_bounds(to.x, to.y):
		return false
	if is_solid(from.x, from.y) or is_solid(to.x, to.y):
		return false
	var goal := idx(to.x, to.y)
	var mask := PackedByteArray()
	mask.resize(w * h)
	mask.fill(0)
	var queue := PackedInt32Array()
	queue.resize(1024)
	var head := 0
	var tail := 0
	var start := idx(from.x, from.y)
	queue[tail] = start
	tail += 1
	mask[start] = 1
	var visited := 0
	while head < tail and visited < max_nodes:
		var cur: int = queue[head]
		head += 1
		visited += 1
		if cur == goal:
			return true
		var cx: int = cur % w
		var cy: int = cur / w
		if cx > 0 and _try_visit(mask, queue, tail, cur - 1, cx - 1, cy):
			tail += 1
		if cx < w - 1 and _try_visit(mask, queue, tail, cur + 1, cx + 1, cy):
			tail += 1
		if cy > 0 and _try_visit(mask, queue, tail, cur - w, cx, cy - 1):
			tail += 1
		if cy < h - 1 and _try_visit(mask, queue, tail, cur + w, cx, cy + 1):
			tail += 1
		if tail + 4 >= queue.size():
			queue.resize(queue.size() * 2)
	return false

## BFS shortest path through open cells. Empty if unreachable.
func path_between(from: Vector2i, to: Vector2i, max_nodes: int = 200000) -> Array:
	if not in_bounds(from.x, from.y) or not in_bounds(to.x, to.y):
		return []
	if is_solid(from.x, from.y) or is_solid(to.x, to.y):
		return []
	var parent := PackedInt32Array()
	parent.resize(w * h)
	parent.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(1024)
	var head := 0
	var tail := 0
	var start := idx(from.x, from.y)
	var goal := idx(to.x, to.y)
	queue[tail] = start
	tail += 1
	parent[start] = start
	var visited := 0
	var found := false
	while head < tail and visited < max_nodes:
		var cur: int = queue[head]
		head += 1
		visited += 1
		if cur == goal:
			found = true
			break
		var cx: int = cur % w
		var cy: int = cur / w
		if cx > 0:
			tail = _visit_path(parent, queue, tail, cur - 1, cur)
		if cx < w - 1:
			tail = _visit_path(parent, queue, tail, cur + 1, cur)
		if cy > 0:
			tail = _visit_path(parent, queue, tail, cur - w, cur)
		if cy < h - 1:
			tail = _visit_path(parent, queue, tail, cur + w, cur)
		if tail + 4 >= queue.size():
			queue.resize(queue.size() * 2)
	if not found:
		return []
	var out: Array = []
	var cur2 := goal
	while cur2 != start:
		out.append(Vector2i(cur2 % w, cur2 / w))
		cur2 = parent[cur2]
	out.append(Vector2i(start % w, start / w))
	out.reverse()
	return out

func _visit_path(parent: PackedInt32Array, queue: PackedInt32Array, tail: int,
		nidx: int, from_idx: int) -> int:
	if parent[nidx] != -1:
		return tail
	if material[nidx] != Balance.Mat.EMPTY:
		return tail
	parent[nidx] = from_idx
	queue[tail] = nidx
	return tail + 1

func serialise() -> Dictionary:
	return {
		"w": w, "h": h, "tile": tile_size,
		"material": material, "damage": damage, "ore": ore,
		"explored": explored, "variant": variant, "gas": gas,
		"strata": strata, "spawn": spawn_cell, "lift": lift_cell, "relic": relic_cell,
		"protected": protected_cells.keys(),
	}

func deserialise(d: Dictionary) -> void:
	setup(int(d["w"]), int(d["h"]))
	tile_size = int(d.get("tile", Balance.CELL))
	material = d["material"]
	damage = d["damage"]
	ore = d["ore"]
	explored = d["explored"]
	variant = d["variant"]
	gas = d.get("gas", {})
	strata = d.get("strata", PackedStringArray())
	spawn_cell = d.get("spawn", Vector2i.ZERO)
	lift_cell = d.get("lift", Vector2i.ZERO)
	relic_cell = d.get("relic", Vector2i.ZERO)
	protected_cells.clear()
	for i in d.get("protected", []):
		protected_cells[int(i)] = true
