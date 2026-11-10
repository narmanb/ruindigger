class_name DigCheck
extends RefCounted
## Dig-aware traversal model: proves a mine is completable and free of
## softlocks for a player with STARTING gear who may drill, but never spends
## Rubble Ladder energy. It extends RouteCheck's conservative moves (walk,
## fall, 3-cell jump, ladders, one-way platforms) with three digging moves:
##   - tunnel sideways through diggable rock
##   - dig the floor out and drop one cell
##   - cut a one-cell step up into a wall ("staircase digging")
## Digging straight up is NOT a move (a vertical hole cannot be climbed without
## a ladder). With `allow_ladder` the model may also raise a Rubble Ladder, but
## only where diggable rock is close by (ladder energy is earned by drilling,
## so it is renewable exactly there) and never taller than one full starting
## meter. Shafts walled with unbreakable material and no rock in reach are
## therefore still reported as traps. The real player is strictly more capable
## (jet, wall jump, charges, upgrades), so passing here is a safe guarantee.
##
## Costs are seconds: dig time with the Mk.I drill plus a little travel time.

const OPEN := 0
const DIGGABLE := 1
const BLOCKED := 2
const JUMP_CELLS := 3
const JUMP_REACH := 2
const T_WALK := 0.11
const T_CLIMB := 0.13
const T_JUMP := 0.3
const T_GAS := 8.0
const UNREACHED := 1e20

var g: TerrainGrid
var W: int
var H: int
var kind := PackedByteArray()      # OPEN / DIGGABLE / BLOCKED per cell
var dig := PackedFloat32Array()    # seconds to dig the cell (0 when open)
var stand := PackedByteArray()     # can a body stand on top of this cell?
var ladder := PackedByteArray()
var platform := PackedByteArray()
## When true, a Rubble Ladder may be raised through open space. Its energy is
## priced as the time it takes to earn it back by drilling sediment, so costs
## stay in seconds. Used for the time budget only; the softlock guarantee is
## always computed with this off.
var allow_ladder := false
var _ladder_cell_s := 0.0
var _ladder_max := 0
var near_rock := PackedByteArray()  # diggable rock within 3 cells (energy source)
var _nb := PackedInt32Array()      # scratch: neighbours of the last expanded state
var _nc := PackedFloat32Array()
var _nn := 0


func _init(grid: TerrainGrid, open_cells: Dictionary = {}) -> void:
	g = grid
	W = grid.w
	H = grid.h
	var n := W * H
	kind.resize(n)
	dig.resize(n)
	stand.resize(n)
	ladder.resize(n)
	platform.resize(n)
	_nb.resize(64)
	_nc.resize(64)
	var power: float = Balance.DRILL_POWER[0]
	for i in n:
		var m: int = g.mat[i]
		if m == Cell.LADDER:
			ladder[i] = 1
		elif m == Cell.PLATFORM:
			platform[i] = 1
			stand[i] = 1
		elif m != Cell.AIR:
			stand[i] = 1
			var info: Dictionary = Balance.MATERIAL.get(m, {})
			if m == Cell.GAS and not (g.flags[i] & Cell.F_PROTECTED):
				# breakable, but you wait out the cloud: never the preferred way
				kind[i] = DIGGABLE
				dig[i] = T_GAS
			elif m == Cell.BEDROCK or (g.flags[i] & Cell.F_PROTECTED) or int(info.get("tier", 99)) > 0:
				kind[i] = BLOCKED
			else:
				kind[i] = DIGGABLE
				dig[i] = float(info.get("hp", 1.0)) / power
	var earn: float = float(Balance.MATERIAL[Cell.SOFT]["hp"]) / power / float(Balance.SCAFFOLD_GAIN[Cell.SOFT])
	_ladder_cell_s = T_CLIMB + earn * Balance.SCAFFOLD_CELL_COST
	_ladder_max = (int(Balance.SCAFFOLD_CAPACITY[0]) - Balance.SCAFFOLD_ACTIVATE_COST) / Balance.SCAFFOLD_CELL_COST
	# box dilation of the diggable mask (two separable passes)
	var tmp := PackedByteArray()
	tmp.resize(n)
	near_rock.resize(n)
	for y in H:
		for x in W:
			var hit := 0
			for dx in range(-3, 4):
				var xx := x + dx
				if xx >= 0 and xx < W and kind[y * W + xx] == DIGGABLE:
					hit = 1
					break
			tmp[y * W + x] = hit
	for y in H:
		for x in W:
			var hit2 := 0
			for dy in range(-3, 4):
				var yy := y + dy
				if yy >= 0 and yy < H and tmp[yy * W + x] == 1:
					hit2 = 1
					break
			near_rock[y * W + x] = hit2
	for c in open_cells.keys():
		if g.in_bounds(c.x, c.y):
			var j: int = c.y * W + c.x
			kind[j] = OPEN
			dig[j] = 0.0
			stand[j] = 0


## Seconds of digging to make a 2-tall body fit with feet at i, or -1.
func _body(i: int) -> float:
	if i < W or i >= W * H:
		return -1.0
	if kind[i] == BLOCKED or kind[i - W] == BLOCKED:
		return -1.0
	return dig[i] + dig[i - W]


func _body_open(i: int) -> bool:
	return i >= W and i < W * H and kind[i] == OPEN and kind[i - W] == OPEN


func _push(i: int, c: float) -> void:
	if _nn >= _nb.size():
		_nb.resize(_nn * 2)
		_nc.resize(_nn * 2)
	_nb[_nn] = i
	_nc[_nn] = c
	_nn += 1


## Fills _nb/_nc/_nn with the moves available from feet index i.
func _expand(i: int) -> void:
	_nn = 0
	var x := i % W
	var y := i / W
	if x < 1 or x >= W - 1 or y < 2 or y >= H - 1:
		return
	var on_ladder := ladder[i] == 1 or ladder[i - W] == 1
	var below := i + W
	var grounded := stand[below] == 1 or on_ladder or ladder[below] == 1
	if not grounded:
		# falling: straight down, with one cell of air drift either side
		# (the cell we are in may be rock we just dug, so only `below` must be open)
		if kind[below] == OPEN:
			_push(below, T_WALK)
		if _body_open(below):
			for dx in [-1, 1]:
				if _body_open(i + dx) and _body_open(below + dx):
					_push(below + dx, T_WALK)
		return
	for dx in [-1, 1]:
		var b: float = _body(i + dx)
		if b >= 0.0:
			_push(i + dx, T_WALK + b)
		# staircase digging: cut a step into the wall and hop onto it
		var up: int = i + dx - W
		if stand[i + dx] == 1 and y >= 3:
			var bu := _body(up)
			if bu >= 0.0 and kind[i - 2 * W] != BLOCKED:
				_push(up, T_JUMP + bu + dig[i - 2 * W])
	if on_ladder:
		var bl := _body(i - W)
		if bl >= 0.0:
			_push(i - W, T_CLIMB + bl)
	if kind[below] != BLOCKED:
		if on_ladder or ladder[below] == 1 or platform[below] == 1:
			if _body_open(below):
				_push(below, T_CLIMB)
		elif kind[below] == DIGGABLE:
			_push(below, T_WALK + dig[below])   # dig the floor out and drop
	if allow_ladder and stand[below] == 1 and not on_ladder and near_rock[i] == 1:
		# raise a ladder from the feet cell and step off sideways anywhere up it
		var t: float = Balance.SCAFFOLD_ACTIVATE_COST * (_ladder_cell_s - T_CLIMB)
		var j2 := i - W
		var h := 1
		while h <= _ladder_max and j2 >= 2 * W and kind[j2 - W] == OPEN and kind[j2] == OPEN:
			t += _ladder_cell_s
			for dx in [-1, 1]:
				if stand[j2 + dx + W] == 1:
					var bs: float = _body(j2 + dx)
					if bs >= 0.0:
						_push(j2 + dx, t + T_WALK + bs)
			j2 -= W
			h += 1
	# jumps through open space only (no digging in mid-air)
	for dy in range(1, JUMP_CELLS + 1):
		var j := i - dy * W
		if not _body_open(j):
			break
		_push(j, T_JUMP)
		for sgn in [-1, 1]:
			for k in range(1, JUMP_REACH + 1):
				if not _body_open(j + sgn * k):
					break
				_push(j + sgn * k, T_JUMP)


# --- shortest dig-time paths (Dijkstra with a packed binary heap) ------------
var _hk := PackedFloat32Array()
var _hv := PackedInt32Array()
var _hn := 0


func _hpush(k: float, v: int) -> void:
	if _hn >= _hk.size():
		_hk.resize(maxi(1024, _hk.size() * 2))
		_hv.resize(_hk.size())
	var i := _hn
	_hn += 1
	while i > 0:
		var p := (i - 1) >> 1
		if _hk[p] <= k:
			break
		_hk[i] = _hk[p]
		_hv[i] = _hv[p]
		i = p
	_hk[i] = k
	_hv[i] = v


func _hpop() -> int:
	var top := _hv[0]
	_hn -= 1
	if _hn > 0:
		var k := _hk[_hn]
		var v := _hv[_hn]
		var i := 0
		while true:
			var l := i * 2 + 1
			if l >= _hn:
				break
			var r := l + 1
			var m := l if (r >= _hn or _hk[l] <= _hk[r]) else r
			if _hk[m] >= k:
				break
			_hk[i] = _hk[m]
			_hv[i] = _hv[m]
			i = m
		_hk[i] = k
		_hv[i] = v
	return top


## Cost (seconds) from `start` to every feet cell; UNREACHED where impossible.
## Stops early once `stop_at` is settled (pass -1 to flood the whole map).
func costs_from(start: Vector2i, stop_at: int = -1) -> PackedFloat32Array:
	var dist := PackedFloat32Array()
	dist.resize(W * H)
	dist.fill(UNREACHED)
	var s := start.y * W + start.x
	if _body(s) < 0.0:
		return dist
	dist[s] = 0.0
	_hn = 0
	_hpush(0.0, s)
	while _hn > 0:
		var d := _hk[0]
		var i := _hpop()
		if d > dist[i]:
			continue
		if i == stop_at:
			break
		_expand(i)
		for k in _nn:
			var j := _nb[k]
			var nd := d + _nc[k]
			# the epsilon matters: distances are stored as 32-bit floats, and a
			# value that rounds up on store must not look like an improvement
			if nd < dist[j] - 0.0005:
				dist[j] = nd
				_hpush(nd, j)
	return dist


## Seconds from a to b (within `tolerance` cells of b), or -1 if impossible.
func cost(a: Vector2i, b: Vector2i, tolerance: int = 1) -> float:
	var dist := costs_from(a)
	var best := UNREACHED
	for dy in range(-tolerance, tolerance + 1):
		for dx in range(-tolerance, tolerance + 1):
			var c := b + Vector2i(dx, dy)
			if g.in_bounds(c.x, c.y):
				best = minf(best, dist[c.y * W + c.x])
	return best if best < UNREACHED else -1.0


## Every feet cell from which `target` can be reached (reverse reachability
## over the same move set): 1 = can get there, 0 = cannot.
## Runs with `allow_ladder` as currently set.
func escape_set(target: Vector2i, tolerance: int = 1) -> PackedByteArray:
	var n := W * H
	# forward edges for every state, then a counting sort into reverse CSR
	var src := PackedInt32Array()
	var dst := PackedInt32Array()
	var count := PackedInt32Array()
	count.resize(n + 1)
	for i in n:
		if _body(i) < 0.0:
			continue
		_expand(i)
		for k in _nn:
			src.append(i)
			dst.append(_nb[k])
			count[_nb[k] + 1] += 1
	for i in n:
		count[i + 1] += count[i]
	var fill := count.duplicate()
	var rev := PackedInt32Array()
	rev.resize(src.size())
	for e in src.size():
		var d := dst[e]
		rev[fill[d]] = src[e]
		fill[d] += 1
	var ok := PackedByteArray()
	ok.resize(n)
	var q := PackedInt32Array()
	for dy in range(-tolerance, tolerance + 1):
		for dx in range(-tolerance, tolerance + 1):
			var c := target + Vector2i(dx, dy)
			if g.in_bounds(c.x, c.y):
				var t := c.y * W + c.x
				if _body(t) >= 0.0 and ok[t] == 0:
					ok[t] = 1
					q.append(t)
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		for e in range(count[i], count[i + 1]):
			var p := rev[e]
			if ok[p] == 0:
				ok[p] = 1
				q.append(p)
	return ok


## Softlock audit: feet cells the player can get into (from `start`) but can
## never leave toward `home`. Must be empty for a fair mine.
func traps(start: Vector2i, home: Vector2i) -> Array[Vector2i]:
	var keep := allow_ladder
	allow_ladder = true
	var dist := costs_from(start)
	var ok := escape_set(home)
	allow_ladder = keep
	var out: Array[Vector2i] = []
	for i in W * H:
		if dist[i] < UNREACHED and ok[i] == 0:
			out.append(Vector2i(i % W, i / W))
	return out
