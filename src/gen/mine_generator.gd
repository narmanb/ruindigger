class_name MineGenerator
extends RefCounted
## Seeded mine generation. ORDER MATTERS (see README "Generation"):
##  1 base rock + strata     2 natural caves + smoothing
##  3 lift room + timber shaft (protected)   4 relay lift station
##  5 ruin halls (stratum 3) 6 relic chamber (protected alloy, one door)
##  7 set pieces             8 guaranteed route carved AFTER destructive passes
##  9 loose ceilings / ore / gas on rock only, never on the route
## 10 enemies   11 validation + repair (strict traversal both ways)

var rng := RandomNumberGenerator.new()
var g: TerrainGrid
var W: int
var H: int
var contract: Dictionary
var data: Dictionary
var reserved: Dictionary = {}     # cells the route owns; later passes must not fill them
var no_feature: Dictionary = {}   # cells where ore/gas/loose must not appear
var repairs := 0
var no_repair := false


func generate(seed_value: int, contract_in: Dictionary = {}) -> Dictionary:
	rng.seed = seed_value
	contract = contract_in if not contract_in.is_empty() else Balance.CONTRACTS[0]
	W = Balance.MAP_W
	H = Balance.MAP_H
	g = TerrainGrid.new(W, H)
	data = {"seed": seed_value, "entities": [], "grid": g, "route": []}
	_base_fill(seed_value)
	_caves(seed_value)
	_worm_tunnels()
	_rail_tunnel()
	_lift_room()
	_shaft()
	_relay_station()
	_ruin_halls()
	_relic_chamber()
	_set_pieces()
	_route()
	_loose_ceilings()
	_hanging_boulders()
	_ore()
	_geodes()
	_gas()
	_water_pockets()
	_lake()
	_stabilize_basalt()
	_enemies()
	_finalize_hp()
	_validate_and_repair()
	_water_environment()
	data["repairs"] = repairs
	return data


# ---------------------------------------------------------------------------
func _base_fill(seed_value: int) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.07
	n.fractal_octaves = 3
	var phase := rng.randf() * TAU
	for y in H:
		for x in W:
			var s := 0
			for k in [1, 2]:
				var b: int = Balance.STRATUM_ROWS[k] + int(round(2.5 * sin(x * 0.19 + phase + k)))
				if y >= b:
					s = k
			g.stratum[g.idx(x, y)] = s
			var v := n.get_noise_2d(x, y)
			var hard_thr: float = [0.28, 0.12, -0.02][s]
			var m := Cell.HARD if v > hard_thr else Cell.SOFT
			if x < 2 or x >= W - 2 or y < 2 or y >= H - 6:
				m = Cell.BEDROCK
			g.put(x, y, m)


func _caves(seed_value: int) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_value + 17
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_octaves = 2
	var n2 := FastNoiseLite.new()
	n2.seed = seed_value + 31
	n2.frequency = 0.05
	for y in range(12, H - 8):
		for x in range(3, W - 3):
			var s := g.get_stratum(x, y)
			var v := 0.0
			var thr := 0.0
			match s:
				0:
					n.frequency = 0.06
					v = n.get_noise_2d(x * 0.55, y * 1.5)
					thr = 0.3
				1:
					n.frequency = 0.045
					v = n.get_noise_2d(x, y) * 0.8 + n2.get_noise_2d(x, y) * 0.35
					thr = 0.2
				2:
					n.frequency = 0.05
					v = n.get_noise_2d(x * 0.8, y * 1.2)
					thr = 0.36
			if v > thr:
				g.put(x, y, Cell.AIR)
	# smooth twice (cellular automata) so walls read as organic shapes
	for it in 2:
		var copy := g.mat.duplicate()
		for y in range(12, H - 8):
			for x in range(3, W - 3):
				var solid := 0
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if Cell.is_solid(copy[g.idx(x + dx, y + dy)]):
							solid += 1
				var i := g.idx(x, y)
				if solid >= 6 and copy[i] == Cell.AIR:
					g.put(x, y, Cell.SOFT if g.get_stratum(x, y) != 2 or rng.randf() < 0.5 else Cell.HARD)
				elif solid <= 3 and Cell.is_solid(copy[i]) and copy[i] != Cell.BEDROCK:
					g.put(x, y, Cell.AIR)
	# fill tiny pockets (< 8 cells) so the map is not full of confetti holes
	var seen: Dictionary = {}
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if g.get_mat(x, y) != Cell.AIR or seen.has(c):
				continue
			var region: Array[Vector2i] = [c]
			seen[c] = true
			var head := 0
			while head < region.size() and region.size() < 40:
				var cc: Vector2i = region[head]
				head += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nn: Vector2i = cc + d
					if g.get_mat(nn.x, nn.y) == Cell.AIR and not seen.has(nn):
						seen[nn] = true
						region.append(nn)
			if region.size() < 8:
				for cc in region:
					g.put(cc.x, cc.y, Cell.SOFT)


# ---------------------------------------------------------------------------
# Extra structure: worm tunnels and an abandoned rail tunnel (destructive, so
# they run before the protected rooms and the guaranteed route).
func _carve_free(x: int, y: int) -> void:
	if x < 3 or x >= W - 3 or y < 12 or y >= H - 8:
		return
	if g.has_flag(x, y, Cell.F_PROTECTED) or g.get_mat(x, y) == Cell.BEDROCK:
		return
	g.put(x, y, Cell.AIR)


func _worm_tunnels() -> void:
	var count := rng.randi_range(5, 8)
	for i in count:
		var x := rng.randi_range(6, W - 7)
		var y := rng.randi_range(16, Balance.STRATUM_ROWS[2] - 4)
		var dir := Vector2(1 if rng.randf() < 0.5 else -1, 0)
		for step in rng.randi_range(25, 60):
			for dy in range(-1, 2):
				for dx in range(0, 2):
					_carve_free(int(x) + dx, int(y) + dy)
			if rng.randf() < 0.18:
				dir = Vector2(dir.x if rng.randf() < 0.7 else -dir.x, rng.randf_range(-0.9, 0.9))
			x = clampi(int(round(x + dir.x)), 5, W - 7)
			y = clampi(int(round(y + dir.y * 0.6 + (1 if rng.randf() < 0.08 else 0))), 15, H - 12)


func _rail_tunnel() -> void:
	if rng.randf() < 0.25:
		return
	var y := rng.randi_range(22, 58)
	var length := rng.randi_range(24, 44)
	var x0 := rng.randi_range(3, W - length - 3)
	for x in range(x0, x0 + length):
		for dy in range(-2, 1):
			_carve_free(x, y + dy)
		if not g.is_solid(x, y + 1):
			g.put(x, y + 1, Cell.HARD)
		if not g.is_solid(x, y - 3):
			g.put(x, y - 3, Cell.SOFT)
	for x in range(x0 + 2, x0 + length - 1, 6):
		data["entities"].append({"type": "beam", "cell": Vector2i(x, y - 1)})
	for x in range(x0 + 5, x0 + length - 1, 12):
		data["entities"].append({"type": "lamp", "cell": Vector2i(x, y - 2)})
	data["entities"].append({"type": "crate", "cell": Vector2i(x0 + length / 2, y)})
	data["rail"] = Rect2i(x0, y - 2, length, 3)


# ---------------------------------------------------------------------------
func _rect_fill(x0: int, y0: int, w: int, h: int, m: int, flags_on: int = 0, keep_reserved: bool = false) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			if not g.in_bounds(x, y) or x < 2 or x >= W - 2 or y < 2 or y >= H - 6:
				continue
			if keep_reserved and reserved.has(Vector2i(x, y)):
				continue
			if g.has_flag(x, y, Cell.F_PROTECTED) and flags_on & Cell.F_PROTECTED == 0:
				continue
			g.put(x, y, m)
			if flags_on:
				g.set_flag(x, y, flags_on)


func _lift_room() -> void:
	# Room interior x 28..43, y 4..9; lift cage centred at x 34.5, floor row 10.
	var x0 := 27
	_rect_fill(x0, 2, 18, 8, Cell.AIR, Cell.F_NO_RUBBLE)
	_rect_fill(x0, 10, 18, 2, Cell.HARD)
	_rect_fill(32, 10, 6, 2, Cell.HARD, Cell.F_PROTECTED)
	# shaft opening in the ceiling where the cable comes down
	for y in range(0, 2):
		for x in range(33, 37):
			g.put(x, y, Cell.AIR)
			g.set_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE)
	# keep the bedrock ceiling over the room protected (it is anyway) + side walls normal
	data["spawn"] = Vector2i(31, 9)
	data["lift"] = Vector2i(35, 9)
	for y in range(2, 10):
		for x in range(x0, x0 + 18):
			no_feature[Vector2i(x, y)] = true
			reserved[Vector2i(x, y)] = true
	data["entities"].append({"type": "lift", "cell": Vector2i(35, 9), "id": "surface"})
	data["entities"].append({"type": "lamp", "cell": Vector2i(29, 4)})
	data["entities"].append({"type": "lamp", "cell": Vector2i(42, 4)})
	data["entities"].append({"type": "sign", "cell": Vector2i(40, 9), "text": "SHAFT A"})


func _shaft() -> void:
	# Old timber shaft: 3 wide, ladder on the east column, platforms every 7 rows.
	var sx := 39
	var top := 10
	var bottom := Balance.STRATUM_ROWS[1] - 8
	for y in range(top, bottom + 1):
		for x in range(sx - 1, sx + 2):
			g.put(x, y, Cell.AIR)
			reserved[Vector2i(x, y)] = true
			no_feature[Vector2i(x, y)] = true
		g.put(sx + 1, y, Cell.LADDER)
		g.set_flag(sx + 1, y, Cell.F_NO_RUBBLE)
	# keep a solid frame around the shaft so it reads as a constructed shaft
	for y in range(top + 2, bottom + 1):
		for x in [sx - 2, sx + 2]:
			if g.get_mat(x, y) == Cell.AIR:
				g.put(x, y, Cell.SOFT)
	for y in range(top + 6, bottom, 7):
		g.put(sx - 1, y, Cell.PLATFORM)
		g.put(sx, y, Cell.PLATFORM)
		data["entities"].append({"type": "beam", "cell": Vector2i(sx - 2, y)})
	# shaft bottom landing (short side tunnel west)
	for y in range(bottom - 2, bottom + 1):
		for x in range(sx - 8, sx + 2):
			if g.get_mat(x, y) != Cell.LADDER:
				g.put(x, y, Cell.AIR)
			reserved[Vector2i(x, y)] = true
	for x in range(sx - 8, sx + 1):
		if not g.is_solid(x, bottom + 1):
			g.put(x, bottom + 1, Cell.HARD)
	data["shaft_bottom"] = Vector2i(sx - 6, bottom)
	data["entities"].append({"type": "lamp", "cell": Vector2i(sx - 4, bottom - 2)})


func _relay_station() -> void:
	var y_floor := Balance.STRATUM_ROWS[1] + 8
	var left := rng.randf() < 0.5
	var x0 := 6 + rng.randi_range(0, 6) if left else W - 22 - rng.randi_range(0, 6)
	_rect_fill(x0, y_floor - 5, 14, 6, Cell.AIR, Cell.F_NO_RUBBLE)
	_rect_fill(x0, y_floor + 1, 14, 1, Cell.HARD)
	for y in range(y_floor - 5, y_floor + 1):
		for x in range(x0, x0 + 14):
			reserved[Vector2i(x, y)] = true
			no_feature[Vector2i(x, y)] = true
	data["relay"] = Vector2i(x0 + 7, y_floor)
	data["entities"].append({"type": "lift", "cell": Vector2i(x0 + 7, y_floor), "id": "relay"})
	data["entities"].append({"type": "lamp", "cell": Vector2i(x0 + 1, y_floor - 4)})


func _ruin_halls() -> void:
	var halls: Array = []
	var tries := 0
	while halls.size() < 3 and tries < 60:
		tries += 1
		var w := rng.randi_range(11, 16)
		var h := rng.randi_range(6, 8)
		var x0 := rng.randi_range(4, W - w - 4)
		var y0 := rng.randi_range(Balance.STRATUM_ROWS[2] + 3, H - 32)
		var r := Rect2i(x0, y0, w, h)
		var ok := true
		for o in halls:
			if (o as Rect2i).grow(4).intersects(r):
				ok = false
		if not ok:
			continue
		halls.append(r)
		# alloy shell, interior air, two doorways
		_rect_fill(x0, y0, w, h, Cell.ALLOY)
		_rect_fill(x0 + 1, y0 + 1, w - 2, h - 2, Cell.AIR)
		var fy := y0 + h - 2   # interior floor-level row (feet)
		_rect_fill(x0, fy - 2, 1, 3, Cell.AIR)
		_rect_fill(x0 + w - 1, fy - 2, 1, 3, Cell.AIR)
		# carve approach tunnels outside both doorways so they open into the cave
		_rect_fill(x0 - 3, fy - 2, 3, 3, Cell.AIR, 0, true)
		_rect_fill(x0 + w, fy - 2, 3, 3, Cell.AIR, 0, true)
		for x in range(x0 - 3, x0 + w + 3):
			if not g.is_solid(x, fy + 1):
				g.put(x, fy + 1, Cell.HARD)
		# alloy pillars inside
		if w >= 14:
			_rect_fill(x0 + w / 2, y0 + 1, 1, 2, Cell.ALLOY)
		var sentry_x := x0 + rng.randi_range(3, w - 4)
		data["entities"].append({"type": "sentry", "cell": Vector2i(sentry_x, fy), "module": Vector2i(x0 + 1 if sentry_x > x0 + w / 2 else x0 + w - 2, y0 + 1)})
		for y in range(y0, y0 + h):
			for x in range(x0, x0 + w):
				no_feature[Vector2i(x, y)] = true
		# a little aetherite set into the shell exterior as the lure
		for k in 3:
			var ax := rng.randi_range(x0, x0 + w - 1)
			var ay := y0 - 1
			if g.get_mat(ax, ay) in [Cell.SOFT, Cell.HARD]:
				g.put(ax, ay, Cell.HARD, Cell.ORE_AETHER)
	data["halls"] = halls


func _relic_chamber() -> void:
	var w := 16
	var h := 9
	var y0 := H - 6 - h - rng.randi_range(2, 5)
	var door_left := rng.randf() < 0.5
	var x0 := rng.randi_range(14, W - w - 6) if door_left else rng.randi_range(5, W - w - 14)
	# make sure surroundings are solid so the shell reads clearly
	_rect_fill(x0 - 1, y0 - 1, w + 2, h + 2, Cell.HARD)
	_rect_fill(x0, y0, w, h, Cell.ALLOY, Cell.F_PROTECTED)
	_rect_fill(x0 + 1, y0 + 1, w - 2, h - 2, Cell.AIR, Cell.F_PROTECTED | Cell.F_NO_RUBBLE)
	# clear the protected flag on interior air (it only matters for solids, but keep it tidy)
	for y in range(y0 + 1, y0 + h - 1):
		for x in range(x0 + 1, x0 + w - 1):
			g.set_flag(x, y, Cell.F_PROTECTED, false)
			no_feature[Vector2i(x, y)] = true
			reserved[Vector2i(x, y)] = true
	var fy := y0 + h - 2
	var door_x := x0 if door_left else x0 + w - 1
	var door_cells: Array = []
	for y in range(fy - 2, fy + 1):
		door_cells.append(Vector2i(door_x, y))
	var outside := Vector2i(door_x - 1 if door_left else door_x + 1, fy)
	# approach landing in front of the door
	var ax0 := outside.x - 5 if door_left else outside.x
	_rect_fill(ax0, fy - 2, 6, 3, Cell.AIR, Cell.F_NO_RUBBLE)
	for x in range(ax0, ax0 + 6):
		g.put(x, fy + 1, Cell.HARD)
		g.set_flag(x, fy + 1, Cell.F_PROTECTED)
		for y in range(fy - 2, fy + 1):
			reserved[Vector2i(x, y)] = true
			no_feature[Vector2i(x, y)] = true
	data["relic_room"] = Rect2i(x0, y0, w, h)
	data["door_cells"] = door_cells
	data["door_outside"] = outside
	data["door_left"] = door_left
	var relic := Vector2i(x0 + (w - 4 if door_left else 3), fy)
	data["relic"] = relic
	data["entities"].append({"type": "door", "cell": door_cells[0], "cells": door_cells})
	data["entities"].append({"type": "relic", "cell": relic})
	# two sentries guard the pedestal; their power modules hang on the back wall
	var sx1 := x0 + w / 2 - 2
	var sx2 := x0 + w / 2 + 2
	data["entities"].append({"type": "sentry", "cell": Vector2i(sx1, fy), "module": Vector2i(sx1 - 1, y0 + 1)})
	data["entities"].append({"type": "sentry", "cell": Vector2i(sx2, y0 + 1), "ceiling": true, "module": Vector2i(sx2 + 2, y0 + 1)})
	data["entities"].append({"type": "lamp", "cell": Vector2i(relic.x, y0 + 1), "color": "6ff3ff"})


# ---------------------------------------------------------------------------
func _set_pieces() -> void:
	# 1) Fossil grotto in Dustworks behind a cracked wall
	var gx := rng.randi_range(6, W - 22)
	var gy := rng.randi_range(36, 56)
	if absi(gx + 7 - 39) < 10:
		gx = 6 if gx > 30 else W - 22
	_rect_fill(gx - 1, gy - 1, 16, 9, Cell.HARD)
	_ellipse_air(gx + 7, gy + 3, 6.5, 3.2)
	for k in range(0, 12):
		var fx := gx + 1 + k
		if g.is_solid(fx, gy + 6):
			g.put(fx, gy + 6, Cell.SOFT, Cell.ORE_FOSSIL if k % 2 == 0 else Cell.ORE_NONE)
	for k in [3, 5, 7, 9]:
		if g.is_solid(gx + k, gy - 0):
			g.put(gx + k, gy, Cell.SOFT, Cell.ORE_FOSSIL)
	data["entities"].append({"type": "skull", "cell": Vector2i(gx + 3, gy + 5)})
	data["grotto"] = Rect2i(gx - 1, gy - 1, 16, 9)
	_mark_no_feature(Rect2i(gx - 1, gy - 1, 16, 9))
	# 2) Spore vault: hard walls, cobalt-lined, supply cache inside
	var vx := rng.randi_range(6, W - 16)
	var vy := rng.randi_range(Balance.STRATUM_ROWS[1] + 20, Balance.STRATUM_ROWS[1] + 52)
	_rect_fill(vx, vy, 11, 7, Cell.HARD)
	_rect_fill(vx + 2, vy + 2, 7, 3, Cell.AIR)
	for x in range(vx + 2, vx + 9):
		g.put(x, vy + 1, Cell.HARD, Cell.ORE_COBALT if x % 2 == 0 else Cell.ORE_NONE)
	data["entities"].append({"type": "cache", "cell": Vector2i(vx + 5, vy + 4), "charges": 2, "repair": 40})
	data["vault"] = Rect2i(vx, vy, 11, 7)
	_mark_no_feature(Rect2i(vx, vy, 11, 7))
	# 3) Collapsed miner camp: a room with a crumbling ceiling and a cache
	var cx := rng.randi_range(5, 18) if rng.randf() < 0.5 else rng.randi_range(W - 30, W - 18)
	var cy := rng.randi_range(18, 28)
	_rect_fill(cx, cy, 12, 4, Cell.AIR)
	_rect_fill(cx, cy + 4, 12, 1, Cell.HARD)
	_rect_fill(cx + 3, cy - 3, 6, 2, Cell.LOOSE)
	_rect_fill(cx + 3, cy - 1, 6, 1, Cell.SOFT)
	data["entities"].append({"type": "cache", "cell": Vector2i(cx + 9, cy + 3), "charges": 1, "repair": 0})
	data["entities"].append({"type": "crate", "cell": Vector2i(cx + 2, cy + 3)})
	data["entities"].append({"type": "lamp", "cell": Vector2i(cx + 6, cy), "color": "ffb347"})
	data["entities"].append({"type": "sign", "cell": Vector2i(cx + 1, cy + 3), "text": "UNSTABLE"})
	data["camp"] = Rect2i(cx, cy, 12, 5)
	_mark_no_feature(Rect2i(cx - 1, cy - 4, 14, 9))


func _mark_no_feature(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			no_feature[Vector2i(x, y)] = true


func _ellipse_air(cx: float, cy: float, rx: float, ry: float) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0 and g.in_bounds(x, y) and not g.has_flag(x, y, Cell.F_PROTECTED) and g.get_mat(x, y) != Cell.BEDROCK:
				g.put(x, y, Cell.AIR)


# ---------------------------------------------------------------------------
# Guaranteed route: shaft bottom -> relay station -> deep caves -> relic door.
func _route() -> void:
	var relay: Vector2i = data["relay"]
	var relay_entry := Vector2i(relay.x - 5 if relay.x > W / 2 else relay.x + 5, relay.y)
	var pts: Array[Vector2i] = [data["shaft_bottom"], relay_entry]
	var mid_y := rng.randi_range(Balance.STRATUM_ROWS[1] + 30, Balance.STRATUM_ROWS[2] - 6)
	pts.append(Vector2i(rng.randi_range(8, W - 9), mid_y))
	var outside: Vector2i = data["door_outside"]
	var stage := Vector2i(outside.x - 6 if data["door_left"] else outside.x + 6, outside.y)
	stage.x = clampi(stage.x, 4, W - 5)
	pts.append(Vector2i(stage.x, Balance.STRATUM_ROWS[2] + 4))
	pts.append(stage)
	pts.append(outside)
	for i in range(pts.size() - 1):
		_carve_between(pts[i], pts[i + 1])
	# grotto and vault get a short side passage from the route, sealed by a weak wall
	_connect_secret(data["grotto"], Cell.CRACKED)
	_connect_secret(data["vault"], Cell.HARD)
	_connect_secret(data["camp"], Cell.AIR)


func _carve_corridor(x: int, y: int) -> void:
	# feet at y: clear rows y-2..y
	for dy in range(-2, 1):
		_carve_cell(x, y + dy)
	# bridge gaps where the corridor crosses an open cave: old plank walkway
	var below := Vector2i(x, y + 1)
	if g.in_bounds(x, y + 1) and g.get_mat(x, y + 1) == Cell.AIR and not reserved.has(below):
		g.put(x, y + 1, Cell.PLATFORM)
		reserved[below] = true
		no_feature[below] = true


func _carve_cell(x: int, y: int) -> void:
	if not g.in_bounds(x, y) or x < 2 or x >= W - 2 or y < 2 or y >= H - 6:
		return
	if g.has_flag(x, y, Cell.F_PROTECTED) and g.is_solid(x, y):
		return
	if g.get_mat(x, y) != Cell.LADDER and g.get_mat(x, y) != Cell.PLATFORM:
		g.put(x, y, Cell.AIR)
	reserved[Vector2i(x, y)] = true
	no_feature[Vector2i(x, y)] = true
	data["route"].append(Vector2i(x, y))


func _carve_between(a: Vector2i, b: Vector2i) -> void:
	var c := a
	var guard := 0
	while c != b and guard < 400:
		guard += 1
		var dx := b.x - c.x
		var dy := b.y - c.y
		var go_h := dx != 0 and (dy == 0 or rng.randf() < 0.55)
		if go_h:
			var step := signi(dx) * mini(absi(dx), rng.randi_range(4, 11))
			var tx := c.x + step
			var x := c.x
			while x != tx:
				x += signi(step)
				_carve_corridor(x, c.y)
			c.x = tx
			_ensure_floor(c.x, c.y)
		else:
			var stepy := signi(dy) * mini(absi(dy), rng.randi_range(4, 12))
			var ty := c.y + stepy
			var y0 := mini(c.y, ty)
			var y1 := maxi(c.y, ty)
			# 2-wide shaft with a full-height ladder on column c.x
			for y in range(y0 - 2, y1 + 1):
				_carve_cell(c.x, y)
				_carve_cell(c.x + 1, y)
			for y in range(y0, y1 + 1):
				if not g.has_flag(c.x, y, Cell.F_PROTECTED):
					g.put(c.x, y, Cell.LADDER)
					g.set_flag(c.x, y, Cell.F_NO_RUBBLE)
			c.y = ty
			_ensure_floor(c.x, c.y)


func _ensure_floor(x: int, y: int) -> void:
	# guarantee something to stand on at a corridor/shaft junction
	for xx in [x - 1, x, x + 1]:
		if not g.is_solid(xx, y + 1) and g.get_mat(xx, y + 1) != Cell.LADDER:
			if not reserved.has(Vector2i(xx, y + 1)):
				g.put(xx, y + 1, Cell.HARD)


func _connect_secret(r: Rect2i, wall_mat: int) -> void:
	# Find the nearest route cell to the room centre and run a passage toward it.
	var centre := r.get_center()
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	for c in data["route"]:
		var d: int = absi(c.x - centre.x) + absi(c.y - centre.y) * 2
		if d < bd:
			bd = d
			best = c
	if best.x < 0:
		return
	# horizontal passage at room floor level, then vertical to the route
	var fy := r.end.y - 2
	var x := centre.x
	var dirx := signi(best.x - centre.x)
	var placed_wall := false
	var steps := 0
	while x != best.x and steps < 60:
		steps += 1
		x += dirx
		var col_reserved := false
		for dy in range(-2, 1):
			if g.has_flag(x, fy + dy, Cell.F_PROTECTED) or g.get_mat(x, fy + dy) == Cell.BEDROCK:
				return
			if reserved.has(Vector2i(x, fy + dy)):
				col_reserved = true
		for dy in range(-2, 1):
			var cc := Vector2i(x, fy + dy)
			if not reserved.has(cc) or Cell.is_solid(g.get_mat(cc.x, cc.y)):
				if g.get_mat(cc.x, cc.y) != Cell.LADDER and g.get_mat(cc.x, cc.y) != Cell.PLATFORM:
					g.put(cc.x, cc.y, Cell.AIR)
		if not r.grow(1).has_point(Vector2i(x, fy)) and not placed_wall and not col_reserved:
			# first free column outside the room: seal it with the secret wall
			for dy in range(-2, 1):
				g.put(x, fy + dy, wall_mat)
			placed_wall = true
		if not g.is_solid(x, fy + 1) and not reserved.has(Vector2i(x, fy + 1)) and g.get_mat(x, fy + 1) != Cell.LADDER:
			g.put(x, fy + 1, Cell.HARD)
	var ystep := signi(best.y - fy)
	var y := fy
	steps = 0
	while y != best.y and steps < 80:
		steps += 1
		y += ystep
		for xx in [x, x + 1]:
			if g.has_flag(xx, y, Cell.F_PROTECTED) or g.get_mat(xx, y) == Cell.BEDROCK:
				return
			if g.get_mat(xx, y) != Cell.LADDER and g.get_mat(xx, y) != Cell.PLATFORM:
				g.put(xx, y, Cell.AIR)
		if g.get_mat(x, y) != Cell.PLATFORM:
			g.put(x, y, Cell.LADDER)


# ---------------------------------------------------------------------------
func _loose_ceilings() -> void:
	var counts := [14, 10, 6]
	for s in 3:
		var placed := 0
		var tries := 0
		while placed < counts[s] and tries < 400:
			tries += 1
			var x := rng.randi_range(4, W - 8)
			var y := rng.randi_range(maxi(14, Balance.STRATUM_ROWS[s] + 2), (Balance.STRATUM_ROWS[s + 1] if s < 2 else H - 10) - 2)
			# need: (x..x+w, y) solid support row with open air directly below,
			# and two solid rows above it to become rubble
			var w := rng.randi_range(2, 4)
			var ok := true
			for xx in range(x, x + w):
				if not (g.get_mat(xx, y) in [Cell.SOFT, Cell.HARD]) or g.is_solid(xx, y + 1):
					ok = false
					break
				for yy in [y - 1, y - 2]:
					if not (g.get_mat(xx, yy) in [Cell.SOFT, Cell.HARD]) or no_feature.has(Vector2i(xx, yy)):
						ok = false
				if no_feature.has(Vector2i(xx, y)) or no_feature.has(Vector2i(xx, y + 1)):
					ok = false
			if not ok:
				continue
			for xx in range(x, x + w):
				g.put(xx, y - 1, Cell.LOOSE)
				g.put(xx, y - 2, Cell.LOOSE)
				g.put(xx, y, Cell.SOFT)
				no_feature[Vector2i(xx, y - 1)] = true
				no_feature[Vector2i(xx, y - 2)] = true
			placed += 1


func _free_region(cx: int, cy: int, rx: int, ry: int, need_solid: bool) -> bool:
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			if x < 3 or x >= W - 3 or y < 14 or y >= H - 8:
				return false
			var c := Vector2i(x, y)
			if reserved.has(c) or no_feature.has(c) or g.has_flag(x, y, Cell.F_PROTECTED):
				return false
			if need_solid and not g.is_solid(x, y):
				return false
			if g.get_mat(x, y) == Cell.ALLOY:
				return false
	return true


## Basalt blobs hanging from cave ceilings by a single sediment "neck". Dig or
## blast the neck and the boulder drops, crushing whatever is below it.
func _hanging_boulders() -> void:
	var counts := [5, 4, 2]
	var placed_total := 0
	for st in 3:
		var placed := 0
		var tries := 0
		while placed < counts[st] and tries < 1500:
			tries += 1
			var x := rng.randi_range(5, W - 6)
			var lo: int = maxi(16, Balance.STRATUM_ROWS[st])
			var hi: int = (Balance.STRATUM_ROWS[st + 1] if st < 2 else H - 10) - 8
			var y := rng.randi_range(lo, hi)
			if not g.is_solid(x, y) or g.get_mat(x, y) == Cell.ALLOY:
				continue
			var ok := true
			for yy in range(y + 1, y + 7):
				for xx in range(x - 2, x + 3):
					if g.is_solid(xx, yy) or reserved.has(Vector2i(xx, yy)) or no_feature.has(Vector2i(xx, yy)):
						ok = false
			if not ok:
				continue
			if g.get_mat(x, y) != Cell.SOFT:
				g.put(x, y, Cell.SOFT)
			g.put(x, y + 1, Cell.SOFT)            # the neck
			var big := rng.randf() < 0.5
			for yy in range(y + 2, y + (5 if big else 4)):
				for xx in range(x - 1, x + 2):
					if big or absi(xx - x) + (yy - y - 2) < 2 or yy == y + 2:
						g.put(xx, yy, Cell.HARD, Cell.ORE_COBALT if (st > 0 and rng.randf() < 0.2) else Cell.ORE_NONE)
						no_feature[Vector2i(xx, yy)] = true
			no_feature[Vector2i(x, y + 1)] = true
			placed += 1
			placed_total += 1
	data["boulders"] = placed_total


## Hollow crystal geodes sealed in basalt.
func _geodes() -> void:
	var n := rng.randi_range(1, 3)
	var made := 0
	var tries := 0
	while made < n and tries < 200:
		tries += 1
		var cx := rng.randi_range(8, W - 9)
		var cy := rng.randi_range(Balance.STRATUM_ROWS[1] + 6, H - 16)
		var rx := rng.randi_range(3, 5)
		var ry := rng.randi_range(2, 4)
		if not _free_region(cx, cy, rx + 1, ry + 1, false):
			continue
		var kind := Cell.ORE_AETHER if cy > Balance.STRATUM_ROWS[2] else Cell.ORE_COBALT
		for y in range(cy - ry - 1, cy + ry + 2):
			for x in range(cx - rx - 1, cx + rx + 2):
				var dx := (x + 0.5 - cx) / (rx + 0.5)
				var dy := (y + 0.5 - cy) / (ry + 0.5)
				var d := dx * dx + dy * dy
				if d <= 0.55:
					g.put(x, y, Cell.AIR)
				elif d <= 1.0:
					g.put(x, y, Cell.HARD, kind if rng.randf() < 0.55 else Cell.ORE_NONE)
				elif d <= 1.6:
					g.put(x, y, Cell.HARD)
				no_feature[Vector2i(x, y)] = true
		made += 1
	data["geodes"] = made


## Sealed flooded pockets. Treasure lines the floor; breach the wall and the
## water floods out into whatever you have dug.
func _water_pockets() -> void:
	var counts := [2, 5, 2]
	var pockets: Array = []
	for st in 3:
		var placed := 0
		var tries := 0
		while placed < counts[st] and tries < 400:
			tries += 1
			var rx := rng.randi_range(3, 6)
			var ry := rng.randi_range(2, 3)
			var cx := rng.randi_range(6 + rx, W - 7 - rx)
			var lo: int = maxi(18, Balance.STRATUM_ROWS[st] + ry + 2)
			var hi: int = (Balance.STRATUM_ROWS[st + 1] if st < 2 else H - 10) - ry - 3
			if hi <= lo:
				continue
			var cy := rng.randi_range(lo, hi)
			if not _free_region(cx, cy, rx + 2, ry + 2, true):
				continue
			var cells: Array[Vector2i] = []
			for y in range(cy - ry, cy + ry + 1):
				for x in range(cx - rx, cx + rx + 1):
					var dx := (x + 0.5 - cx) / (rx + 0.5)
					var dy := (y + 0.5 - cy) / (ry + 0.5)
					if dx * dx + dy * dy <= 1.0:
						cells.append(Vector2i(x, y))
			var fill_from := cy - ry + rng.randi_range(0, 1)
			for c in cells:
				g.put(c.x, c.y, Cell.AIR)
				if c.y >= fill_from:
					g.water[g.idx(c.x, c.y)] = Balance.WATER_MAX
			# treasure on the floor, a cracked-looking hint above
			for c in cells:
				if not cells.has(c + Vector2i(0, 1)) and g.get_mat(c.x, c.y + 1) in [Cell.SOFT, Cell.HARD] and rng.randf() < 0.5:
					g.ore[g.idx(c.x, c.y + 1)] = Cell.ORE_AETHER if st == 2 or rng.randf() < 0.3 else Cell.ORE_COBALT
			for y in range(cy - ry - 2, cy + ry + 3):
				for x in range(cx - rx - 2, cx + rx + 3):
					no_feature[Vector2i(x, y)] = true
			pockets.append(Rect2i(cx - rx, cy - ry, rx * 2 + 1, ry * 2 + 1))
			placed += 1
	data["water_pockets"] = pockets


## A partly flooded natural cavern in the Spore Veins.
func _lake() -> void:
	for attempt in 40:
		var x := rng.randi_range(6, W - 7)
		var y := rng.randi_range(Balance.STRATUM_ROWS[1] + 10, Balance.STRATUM_ROWS[2] - 8)
		if g.is_solid(x, y) or reserved.has(Vector2i(x, y)):
			continue
		var region: Array[Vector2i] = [Vector2i(x, y)]
		var seen: Dictionary = {Vector2i(x, y): true}
		var head := 0
		var bad := false
		while head < region.size() and region.size() < 500:
			var c: Vector2i = region[head]
			head += 1
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if seen.has(n) or g.is_solid(n.x, n.y):
					continue
				if reserved.has(n):
					bad = true
				seen[n] = true
				region.append(n)
		if bad or region.size() < 50 or region.size() >= 500:
			continue
		var maxy := 0
		for c in region:
			maxy = maxi(maxy, c.y)
		var depth := rng.randi_range(2, 4)
		var filled := 0
		for c in region:
			if c.y > maxy - depth:
				g.water[g.idx(c.x, c.y)] = Balance.WATER_MAX
				filled += 1
		data["lake"] = {"cells": filled, "at": Vector2i(x, y)}
		break
	# let lakes find their level now so the mine starts calm
	var sim := WaterSim.new(g)
	data["settle_steps"] = sim.settle(600)
	g.cell_changed.disconnect(sim._on_cell_changed)
	data["water_total"] = sim.total()


## No basalt starts out unsupported: anything that would fall immediately is
## turned into sediment (it then anchors its neighbours).
func _stabilize_basalt() -> void:
	var fixed := 0
	for y in range(2, H - 6):
		for x in range(2, W - 2):
			if g.get_mat(x, y) == Cell.HARD and not g.is_solid(x, y + 1):
				var mass := Boulders.unsupported_mass(g, Vector2i(x, y))
				for c in mass:
					g.put(c.x, c.y, Cell.SOFT, g.get_ore(c.x, c.y))
					fixed += 1
	data["basalt_stabilized"] = fixed


func _near_open(x: int, y: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if not g.is_solid(x + dx, y + dy):
				return true
	return false


func _ore() -> void:
	var mult: float = contract.get("ore", 1.0)
	var counts := [int(34 * mult), int(30 * mult), int(26 * mult)]
	for s in 3:
		var placed := 0
		var tries := 0
		while placed < counts[s] and tries < 2000:
			tries += 1
			var x := rng.randi_range(3, W - 4)
			var lo: int = maxi(12, Balance.STRATUM_ROWS[s])
			var hi: int = (Balance.STRATUM_ROWS[s + 1] if s < 2 else H - 7) - 1
			var y := rng.randi_range(lo, hi)
			if not _ore_ok(x, y):
				continue
			if rng.randf() < 0.7 and not _near_open(x, y, 3):
				continue
			var kind := _pick_ore(s, y)
			var length := rng.randi_range(2, 6) if kind != Cell.ORE_AETHER else rng.randi_range(1, 3)
			var cx := x
			var cy := y
			for k in length:
				if _ore_ok(cx, cy):
					g.ore[g.idx(cx, cy)] = kind
				var d: Vector2i = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][rng.randi_range(0, 3)]
				cx += d.x
				cy += d.y
			placed += 1


func _ore_ok(x: int, y: int) -> bool:
	var m := g.get_mat(x, y)
	return (m == Cell.SOFT or m == Cell.HARD) and not no_feature.has(Vector2i(x, y)) \
		and not g.has_flag(x, y, Cell.F_PROTECTED) and g.get_ore(x, y) == 0


func _pick_ore(s: int, y: int) -> int:
	var r := rng.randf()
	match s:
		0:
			return Cell.ORE_FOSSIL if r < 0.08 else (Cell.ORE_COBALT if r < 0.14 and y > 50 else Cell.ORE_COPPER)
		1:
			return Cell.ORE_AETHER if r < 0.06 else (Cell.ORE_COPPER if r < 0.3 else Cell.ORE_COBALT)
		_:
			return Cell.ORE_COBALT if r < 0.42 else Cell.ORE_AETHER


func _gas() -> void:
	var mult: float = contract.get("gas", 1.0)
	var counts := [int(round(3 * mult)), int(round(12 * mult)), int(round(5 * mult))]
	var anchors: Array = [data["spawn"], data["relay"], data["door_outside"]]
	for s in 3:
		var placed := 0
		var tries := 0
		while placed < counts[s] and tries < 1500:
			tries += 1
			var x := rng.randi_range(3, W - 4)
			var lo: int = maxi(16, Balance.STRATUM_ROWS[s])
			var hi: int = (Balance.STRATUM_ROWS[s + 1] if s < 2 else H - 7) - 1
			var y := rng.randi_range(lo, hi)
			var far := true
			for a in anchors:
				if absi(a.x - x) + absi(a.y - y) < 9:
					far = false
			if not far or not _ore_ok(x, y) or not _near_open(x, y, 1):
				continue
			var n := rng.randi_range(2, 4)
			var cx := x
			var cy := y
			for k in n:
				if _ore_ok(cx, cy):
					g.put(cx, cy, Cell.GAS)
					no_feature[Vector2i(cx, cy)] = true
				var d: Vector2i = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][rng.randi_range(0, 3)]
				cx += d.x
				cy += d.y
			placed += 1


func _enemies() -> void:
	var mult: float = contract.get("crawlers", 1.0)
	var counts := [int(round(3 * mult)), int(round(5 * mult)), int(round(3 * mult))]
	var total := 0
	var spawn: Vector2i = data["spawn"]
	var relay: Vector2i = data["relay"]
	for s in 3:
		var placed := 0
		var tries := 0
		while placed < counts[s] and tries < 800 and total < Balance.CRAWLER_CAP:
			tries += 1
			var x := rng.randi_range(4, W - 5)
			var lo: int = maxi(20, Balance.STRATUM_ROWS[s])
			var hi: int = (Balance.STRATUM_ROWS[s + 1] if s < 2 else H - 7) - 1
			var y := rng.randi_range(lo, hi)
			if g.is_solid(x, y) or not g.is_solid(x, y + 1) or g.get_mat(x, y) != Cell.AIR:
				continue
			if absi(x - spawn.x) + absi(y - spawn.y) < 26 or absi(x - relay.x) + absi(y - relay.y) < 10:
				continue
			if g.has_flag(x, y, Cell.F_NO_RUBBLE):
				continue
			data["entities"].append({"type": "crawler", "cell": Vector2i(x, y)})
			placed += 1
			total += 1


func _finalize_hp() -> void:
	for i in g.mat.size():
		g.hp[i] = Cell.max_hp(g.mat[i])


# ---------------------------------------------------------------------------
func door_open_cells() -> Dictionary:
	var d: Dictionary = {}
	for c in data.get("door_cells", []):
		d[c] = true
	return d


func _validate_and_repair() -> void:
	var spawn: Vector2i = data["spawn"]
	var outside: Vector2i = data["door_outside"]
	var doors := door_open_cells()
	for attempt in (0 if no_repair else 3):
		var down := RouteCheck.can_reach(g, spawn, outside, doors)
		var up := RouteCheck.can_reach(g, outside, data["lift"], doors)
		var relic_in := RouteCheck.can_reach(g, outside, data["relic"], doors)
		data["diag_%d" % attempt] = [down, up, relic_in]
		if down and up and relic_in:
			data["valid"] = true
			return
		repairs += 1
		# Repair: re-carve the guaranteed route (later passes may have touched it)
		# and drop a straight ladder spine from the shaft bottom to the door.
		var pts: Array[Vector2i] = [data["shaft_bottom"], Vector2i(outside.x, data["shaft_bottom"].y), outside]
		for i in range(pts.size() - 1):
			_carve_between_straight(pts[i], pts[i + 1])
	data["valid"] = RouteCheck.can_reach(g, spawn, outside, doors) and RouteCheck.can_reach(g, outside, data["lift"], doors)


func _carve_between_straight(a: Vector2i, b: Vector2i) -> void:
	var x := a.x
	while x != b.x:
		x += signi(b.x - x)
		_carve_corridor(x, a.y)
	_ensure_floor(b.x, a.y)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	for y in range(y0 - 2, y1 + 1):
		_carve_cell(b.x, y)
		_carve_cell(b.x + 1, y)
	for y in range(y0, y1 + 1):
		if not g.has_flag(b.x, y, Cell.F_PROTECTED):
			g.put(b.x, y, Cell.LADDER)
	_ensure_floor(b.x, b.y)


## Final non-destructive pass with its own RNG: adding scenery never changes
## ore, enemies, water or route generation for an existing seed.
func _water_environment() -> void:
	var props_rng := RandomNumberGenerator.new()
	props_rng.seed = int(data.seed) ^ 0x50524f50
	data["water_props"] = []
	# Reserve route standing surfaces as well as its open body cells. This is a
	# separate flag: drilling remains possible, moving water cannot undercut it.
	for c in reserved:
		g.set_flag(c.x, c.y, Cell.F_WATER_SAFE)
		if Cell.supports(g.get_mat(c.x, c.y + 1)):
			g.set_flag(c.x, c.y + 1, Cell.F_WATER_SAFE)
	var occupied: Dictionary = {}
	for entity in data.entities:
		occupied[entity.cell] = true
	# Upgrade a suitable camp's existing decorative crate rather than duplicating
	# it. Some seeds carve the route through it; those keep their old decoration.
	for entity in data.entities.duplicate():
		if entity.type == "crate" and not reserved.has(entity.cell) and g.get_mat(entity.cell.x, entity.cell.y) == Cell.AIR:
			data.water_props.append({"kind": "crate", "cell": entity.cell})
			data.entities.erase(entity)
	var candidates: Array[Vector2i] = []
	for y in range(8, H - 8):
		for x in range(3, W - 3):
			var c := Vector2i(x, y)
			if g.get_mat(x, y) != Cell.AIR or reserved.has(c) or no_feature.has(c) or occupied.has(c):
				continue
			if g.has_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE | Cell.F_WATER_SAFE):
				continue
			if not Cell.supports(g.get_mat(x, y + 1)) and g.get_water(x, y) < Balance.WATER_MAX / 2:
				continue
			var near_reserved := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if reserved.has(c + Vector2i(dx, dy)) or occupied.has(c + Vector2i(dx, dy)):
						near_reserved = true
			if not near_reserved:
				candidates.append(c)
	while not candidates.is_empty() and data.water_props.size() < Balance.DEBRIS_GENERATED_CAP:
		var c: Vector2i = candidates.pop_at(props_rng.randi_range(0, candidates.size() - 1))
		var near := false
		for prop in data.water_props:
			if Vector2(prop.cell - c).length() < 3.0:
				near = true
		if near:
			continue
		var kind: String = ["crate", "stone", "canister", "scrap"][props_rng.randi_range(0, 3)]
		data.water_props.append({"kind": kind, "cell": c})
