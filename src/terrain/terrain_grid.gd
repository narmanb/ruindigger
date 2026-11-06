class_name TerrainGrid
extends RefCounted
## Authoritative terrain model. Rendering, collision, navigation and the minimap
## all derive from this grid; nothing else stores mutable terrain state.

signal cell_changed(x: int, y: int, old_mat: int, new_mat: int)
signal cell_damaged(x: int, y: int, hp_frac: float)
signal water_changed(x: int, y: int)

const CHUNK := 16
const SHADE_REACH := 3   # interior shading looks this many cells deep

var w: int
var h: int
var mat: PackedByteArray
var hp: PackedFloat32Array
var ore: PackedByteArray
var flags: PackedByteArray
var stratum: PackedByteArray
var water: PackedByteArray         # 0..WATER_MAX in open cells
var chunks_w: int
var chunks_h: int
var _dirty: Dictionary = {}        # Vector2i chunk -> true
var _explore_dirty: Array[Vector2i] = []
var _water_dirty: Dictionary = {}  # chunk -> true (water presentation only)
var edits: int = 0                 # count of cell changes (for tests/telemetry)


func _init(width: int = 8, height: int = 8) -> void:
	w = width
	h = height
	var n := w * h
	mat = PackedByteArray()
	mat.resize(n)
	hp = PackedFloat32Array()
	hp.resize(n)
	ore = PackedByteArray()
	ore.resize(n)
	flags = PackedByteArray()
	flags.resize(n)
	stratum = PackedByteArray()
	stratum.resize(n)
	water = PackedByteArray()
	water.resize(n)
	chunks_w = ceili(float(w) / CHUNK)
	chunks_h = ceili(float(h) / CHUNK)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func idx(x: int, y: int) -> int:
	return y * w + x


func get_mat(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return Cell.BEDROCK
	return mat[y * w + x]


func get_ore(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return ore[y * w + x]


func get_flags(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return Cell.F_PROTECTED
	return flags[y * w + x]


func has_flag(x: int, y: int, f: int) -> bool:
	return (get_flags(x, y) & f) != 0


func set_flag(x: int, y: int, f: int, on: bool = true) -> void:
	if not in_bounds(x, y):
		return
	var i := y * w + x
	flags[i] = (flags[i] | f) if on else (flags[i] & ~f)


func get_stratum(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return Balance.stratum_of_row(y)
	return stratum[y * w + x]


func is_solid(x: int, y: int) -> bool:
	return Cell.is_solid(get_mat(x, y))


func hp_frac(x: int, y: int) -> float:
	if not in_bounds(x, y):
		return 1.0
	var m := get_mat(x, y)
	return clampf(hp[y * w + x] / Cell.max_hp(m), 0.0, 1.0)


## Raw write used by the generator (no signals, no dirty tracking).
func put(x: int, y: int, m: int, ore_id: int = 0) -> void:
	if not in_bounds(x, y):
		return
	var i := y * w + x
	mat[i] = m
	ore[i] = ore_id
	hp[i] = Cell.max_hp(m)


func get_water(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return water[y * w + x]


func set_water(x: int, y: int, v: int) -> void:
	if not in_bounds(x, y):
		return
	var i := y * w + x
	if water[i] == v:
		return
	water[i] = clampi(v, 0, 255)
	_water_dirty[Vector2i(x / CHUNK, y / CHUNK)] = true


func take_water_dirty() -> Array:
	var k := _water_dirty.keys()
	_water_dirty.clear()
	return k


## Re-insert a solid cell with its ore and hp intact (falling boulders).
func place(x: int, y: int, m: int, ore_id: int, hp_v: float) -> void:
	if not in_bounds(x, y):
		return
	set_mat(x, y, m)
	var i := y * w + x
	ore[i] = ore_id
	hp[i] = hp_v
	flags[i] &= ~Cell.F_DUG


## Runtime write: updates hp, dirty chunks and notifies listeners.
func set_mat(x: int, y: int, m: int, mark_dug: bool = false) -> void:
	if not in_bounds(x, y):
		return
	var i := y * w + x
	var old := int(mat[i])
	if old == m:
		return
	mat[i] = m
	hp[i] = Cell.max_hp(m)
	if Cell.is_solid(m):
		ore[i] = 0 if (flags[i] & Cell.F_CLAIMED) else ore[i]
	elif mark_dug and Cell.is_solid(old):
		flags[i] |= Cell.F_DUG
	edits += 1
	_mark_dirty_around(x, y)
	cell_changed.emit(x, y, old, m)


## Apply drill/blast damage. Returns {broken, blocked, ore, mat}.
func damage(x: int, y: int, amount: float, drill_tier: int = 0, ignore_tier: bool = false) -> Dictionary:
	var res := {"broken": false, "blocked": false, "ore": 0, "mat": get_mat(x, y), "hp_frac": 1.0}
	if not in_bounds(x, y):
		res["blocked"] = true
		return res
	var m := get_mat(x, y)
	if not Cell.is_destructible(m) or has_flag(x, y, Cell.F_PROTECTED):
		res["blocked"] = true
		return res
	if not ignore_tier and Cell.tier(m) > drill_tier:
		res["blocked"] = true
		return res
	var i := y * w + x
	hp[i] -= amount
	if hp[i] <= 0.0:
		var o := int(ore[i])
		if o != 0 and (flags[i] & Cell.F_CLAIMED) == 0:
			res["ore"] = o
			flags[i] |= Cell.F_CLAIMED
		ore[i] = 0
		res["broken"] = true
		set_mat(x, y, Cell.AIR, true)
		res["hp_frac"] = 0.0
	else:
		res["hp_frac"] = hp[i] / Cell.max_hp(m)
		_mark_chunk_dirty(x, y)
		cell_damaged.emit(x, y, res["hp_frac"])
	return res


func _mark_chunk_dirty(x: int, y: int) -> void:
	_dirty[Vector2i(x / CHUNK, y / CHUNK)] = true


func _mark_dirty_around(x: int, y: int) -> void:
	# Interior shading and edge masks of neighbours change, so dirty every chunk
	# touched by the SHADE_REACH neighbourhood (usually just one chunk).
	var r := SHADE_REACH
	var c0 := Vector2i(maxi(0, x - r) / CHUNK, maxi(0, y - r) / CHUNK)
	var c1 := Vector2i(mini(w - 1, x + r) / CHUNK, mini(h - 1, y + r) / CHUNK)
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			_dirty[Vector2i(cx, cy)] = true


func take_dirty() -> Array:
	var keys := _dirty.keys()
	_dirty.clear()
	return keys


func peek_dirty() -> Array:
	return _dirty.keys()


func mark_all_dirty() -> void:
	for cy in chunks_h:
		for cx in chunks_w:
			_dirty[Vector2i(cx, cy)] = true


func explore(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	var i := y * w + x
	if flags[i] & Cell.F_EXPLORED:
		return false
	flags[i] |= Cell.F_EXPLORED
	_explore_dirty.append(Vector2i(x, y))
	return true


func take_explored() -> Array[Vector2i]:
	var a := _explore_dirty
	_explore_dirty = []
	return a


## Edge mask: bit set when that side borders open space (N=1,E=2,S=4,W=8).
func edge_mask(x: int, y: int) -> int:
	var m := 0
	if not is_solid(x, y - 1):
		m |= 1
	if not is_solid(x + 1, y):
		m |= 2
	if not is_solid(x, y + 1):
		m |= 4
	if not is_solid(x - 1, y):
		m |= 8
	return m


## Distance (0..SHADE_REACH) from a solid cell to the nearest open cell.
func depth_from_open(x: int, y: int) -> int:
	for r in range(1, SHADE_REACH + 1):
		for d in range(-r, r + 1):
			if not is_solid(x + d, y - r) or not is_solid(x + d, y + r) \
					or not is_solid(x - r, y + d) or not is_solid(x + r, y + d):
				return r - 1
	return SHADE_REACH


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / Balance.CELL), floori(p.y / Balance.CELL))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * Balance.CELL, (c.y + 0.5) * Balance.CELL)


func solid_at(p: Vector2) -> bool:
	var c := world_to_cell(p)
	return is_solid(c.x, c.y)


## Grid line-of-sight between two world points (Bresenham over cells).
func line_clear(a: Vector2, b: Vector2) -> bool:
	var c0 := world_to_cell(a)
	var c1 := world_to_cell(b)
	var dx := absi(c1.x - c0.x)
	var dy := -absi(c1.y - c0.y)
	var sx := 1 if c0.x < c1.x else -1
	var sy := 1 if c0.y < c1.y else -1
	var err := dx + dy
	var x := c0.x
	var y := c0.y
	var guard := 0
	while guard < 256:
		guard += 1
		if (x != c0.x or y != c0.y) and (x != c1.x or y != c1.y) and is_solid(x, y):
			return false
		if x == c1.x and y == c1.y:
			return true
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return false


func to_dict() -> Dictionary:
	return {
		"w": w, "h": h,
		"mat": Marshalls.raw_to_base64(mat),
		"ore": Marshalls.raw_to_base64(ore),
		"flags": Marshalls.raw_to_base64(flags),
		"stratum": Marshalls.raw_to_base64(stratum),
		"hp": Marshalls.raw_to_base64(hp.to_byte_array()),
		"water": Marshalls.raw_to_base64(water),
	}


static func from_dict(d: Dictionary) -> TerrainGrid:
	var g := TerrainGrid.new(int(d["w"]), int(d["h"]))
	g.mat = Marshalls.base64_to_raw(d["mat"])
	g.ore = Marshalls.base64_to_raw(d["ore"])
	g.flags = Marshalls.base64_to_raw(d["flags"])
	g.stratum = Marshalls.base64_to_raw(d["stratum"])
	g.hp = Marshalls.base64_to_raw(d["hp"]).to_float32_array()
	if d.has("water"):
		g.water = Marshalls.base64_to_raw(d["water"])
	return g
