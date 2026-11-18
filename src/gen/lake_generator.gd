class_name LakeGenerator
extends RefCounted
## Mission map "The Sunken Lake": a Dustworks-style cavern full of water
## pockets above a dry lake bed. The goal is to drain enough of that water
## down into the bed. Built from a fixed seed, so the mission is the same map
## every time; nothing is stored. Returns the same data contract as the other
## generators, so Mine runs it unchanged.
##
## Shape (W x H cells):
##   top     arrival room with the lift you came down in, and a ladder shaft
##   field   wide: caves, and water pockets from puddles to great lakes; some
##           sealed in rock, some open like ponds; a film of water on the dry
##           cave floors; greenery where there is water
##   funnel  bedrock closes in from both sides toward the centre, so water you
##           release runs to the middle
##   bed     the lake bed: narrower than the field and centred, bedrock under
##           and beside it, with a lift on a ledge that powers up once the
##           bed holds enough water
##
## PASS ORDER: 1 base rock and rim  2 caves  3 funnel walls  4 lake bed and
## lift ledge  5 arrival room and shaft  6 water pockets  7 settle  8 floor
## film, settle again  9 ore  10 basalt stabilisation  11 greenery, eels,
## lamps  12 hit points  13 measure the bed and check the way down.

const W := 96
const H := 104
const FIELD_Y0 := 13          # first row of the pocket field
const FUNNEL_Y0 := 64         # bedrock starts closing in here
const BED_Y1 := 95            # lake bed interior rows bed_y0 .. BED_Y1 (bed_y0 from the mission's depth)
const BED_HALF := 17          # the bed spans centre +/- this

var g: TerrainGrid
var data: Dictionary
var rng := RandomNumberGenerator.new()
var keep: Dictionary = {}     # cells later passes must leave alone
var pockets: Array = []       # [{c: Vector2i, rx, ry, size}]
var cx := W / 2
var bed_y0 := 82


func generate(mission: Dictionary) -> Dictionary:
	var seed_value := int(mission.get("seed", 1))
	rng.seed = seed_value
	bed_y0 = BED_Y1 - int(mission.get("bed_depth", 14)) + 1
	# the water model draws from the global random stream while it settles:
	# pin it, so the mission really is the same map every time
	seed(seed_value)
	g = TerrainGrid.new(W, H)
	data = {"seed": seed_value, "stage": "mission", "mission": String(mission.get("id", "")), "entities": [], "grid": g,
		"route": [], "version": 1, "landmarks": [], "water_features": [], "water_props": [], "finds": [], "run_relics": []}
	data["zones"] = [{"id": 0, "name": String(mission.get("name", "MISSION")), "rect": Rect2i(2, 2, W - 4, H - 5), "color": Balance.ZONE_COLORS[0]}]
	_base(seed_value)
	_caves(seed_value)
	_funnel()
	_bed()
	_arrival()
	_pockets(float(mission.get("water", 1.0)), int(mission.get("lakes", 2)))
	data["settle_steps"] = _settle(450)
	_film()
	_settle(200)
	_ore()
	_stabilize()
	_greenery()
	_eels(int(mission.get("eels", 2)))
	for i in g.mat.size():
		g.hp[i] = Cell.max_hp(g.mat[i])
	_measure(float(mission.get("target", 0.6)))
	randomize()
	return data


func _rim(x: int, y: int) -> bool:
	return x < 2 or x >= W - 2 or y < 2 or y >= H - 3


func _bedrock(x: int, y: int) -> void:
	g.put(x, y, Cell.BEDROCK)
	g.set_flag(x, y, Cell.F_PROTECTED)
	keep[Vector2i(x, y)] = true


func _free(x: int, y: int) -> bool:
	return g.in_bounds(x, y) and not _rim(x, y) and not keep.has(Vector2i(x, y)) and g.get_mat(x, y) != Cell.BEDROCK


# --- 1 base ------------------------------------------------------------------
func _base(seed_value: int) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.07
	n.fractal_octaves = 3
	for y in H:
		for x in W:
			g.stratum[g.idx(x, y)] = 0
			if _rim(x, y):
				_bedrock(x, y)
			else:
				g.put(x, y, Cell.HARD if n.get_noise_2d(x, y) > 0.3 else Cell.SOFT)


# --- 2 caves -----------------------------------------------------------------
func _caves(seed_value: int) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_value + 23
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_octaves = 2
	n.frequency = 0.05
	for y in range(FIELD_Y0, FUNNEL_Y0 + 8):
		for x in range(4, W - 4):
			if n.get_noise_2d(x * 0.6, y * 1.6) > 0.28:     # long, low galleries
				g.put(x, y, Cell.AIR)
	var copy := g.mat.duplicate()
	for y in range(FIELD_Y0, FUNNEL_Y0 + 8):
		for x in range(4, W - 4):
			var solid := 0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if Cell.is_solid(copy[g.idx(x + dx, y + dy)]):
						solid += 1
			var i := g.idx(x, y)
			if solid >= 6 and copy[i] == Cell.AIR:
				g.put(x, y, Cell.SOFT)
			elif solid <= 3 and Cell.is_solid(copy[i]) and copy[i] != Cell.BEDROCK:
				g.put(x, y, Cell.AIR)


# --- 3 funnel ----------------------------------------------------------------
## Bedrock closes in from both sides between FUNNEL_Y0 and the bed, in steps,
## so released water runs toward the centre.
func _funnel() -> void:
	for y in range(FUNNEL_Y0, H - 3):
		var t := clampf(float(y - FUNNEL_Y0) / float(bed_y0 - FUNNEL_Y0), 0.0, 1.0)
		var half := int(round(lerpf(float(W / 2 - 2), float(BED_HALF), t)))
		for x in range(2, W - 2):
			if absi(x - cx) > half:
				_bedrock(x, y)


# --- 4 lake bed --------------------------------------------------------------
func _bed() -> void:
	var x0 := cx - BED_HALF
	var x1 := cx + BED_HALF
	for y in range(bed_y0, BED_Y1 + 1):
		for x in range(x0, x1 + 1):
			g.put(x, y, Cell.AIR)
			keep[Vector2i(x, y)] = true
	for x in range(x0 - 1, x1 + 2):
		_bedrock(x, BED_Y1 + 1)
	# an uneven bed: low bedrock humps, so the first water gathers in pools
	for x in range(x0, x1 + 1):
		var hump := int(round(1.2 + 1.2 * sin(float(x - x0) * 0.55) + 0.8 * sin(float(x - x0) * 1.3)))
		for k in clampi(hump, 0, 3):
			if absi(x - cx) > 2:
				_bedrock(x, BED_Y1 - k)
	# the lift: in a dry alcove cut into the east wall just above the bed's
	# rim, so a full bed never drowns it; a ladder climbs to it from the bed
	var floor_y := bed_y0 - 1
	for x in range(x1 + 1, x1 + 7):
		for y in range(floor_y - 4, floor_y + 1):
			var inside := x <= x1 + 5 and y >= floor_y - 3 and y < floor_y
			if inside:
				g.set_flag(x, y, Cell.F_PROTECTED, false)
				g.put(x, y, Cell.AIR)
				g.set_flag(x, y, Cell.F_NO_RUBBLE)
				keep[Vector2i(x, y)] = true
			else:
				_bedrock(x, y)
	for y in range(floor_y - 2, BED_Y1 + 1):
		if not g.is_solid(x1, y) or y < bed_y0:
			g.set_flag(x1, y, Cell.F_PROTECTED, false)
			g.put(x1, y, Cell.LADDER)
			g.set_flag(x1, y, Cell.F_NO_RUBBLE)
			keep[Vector2i(x1, y)] = true
	var lift := Vector2i(x1 + 3, floor_y - 1)
	data["entities"].append({"type": "lift", "id": "mission", "cell": lift, "locked": true})
	data["entities"].append({"type": "lamp", "cell": Vector2i(x1 + 2, floor_y - 3), "color": "6ff3d0"})
	data["mission_lift"] = lift
	data["bed"] = Rect2i(x0, bed_y0, x1 - x0 + 1, BED_Y1 - bed_y0 + 1)
	data["landmarks"].append({"kind": "lake_bed", "rect": data["bed"]})


# --- 5 arrival ---------------------------------------------------------------
func _arrival() -> void:
	var room := Rect2i(cx - 7, 5, 15, 4)           # interior
	for y in range(room.position.y - 1, room.end.y + 1):
		for x in range(room.position.x - 1, room.end.x + 1):
			var inside := room.has_point(Vector2i(x, y))
			g.put(x, y, Cell.AIR if inside else Cell.HARD)
			g.set_flag(x, y, Cell.F_NO_RUBBLE if inside else Cell.F_PROTECTED)
			keep[Vector2i(x, y)] = true
	var fy := room.end.y - 1
	# a ladder shaft down from the room into the field
	var sx := cx + 4
	for y in range(room.end.y, FIELD_Y0 + 12):
		for x in [sx, sx + 1]:
			g.set_flag(x, y, Cell.F_PROTECTED, false)
			g.put(x, y, Cell.AIR)
			keep[Vector2i(x, y)] = true
		g.put(sx, y, Cell.LADDER)
		g.set_flag(sx, y, Cell.F_NO_RUBBLE)
	for x in range(sx - 2, sx + 4):
		if g.get_mat(x, FIELD_Y0 + 12) == Cell.AIR:
			g.put(x, FIELD_Y0 + 12, Cell.SOFT)       # a landing under the shaft
	data["spawn"] = Vector2i(cx - 2, fy)
	data["lift"] = Vector2i(cx - 5, fy)
	data["entities"].append({"type": "lift", "id": "surface", "cell": Vector2i(cx - 5, fy)})
	data["entities"].append({"type": "lamp", "cell": Vector2i(cx - 1, room.position.y), "color": "ffb347"})
	data["entities"].append({"type": "sign", "cell": Vector2i(cx + 1, fy), "text": "LAKE BED BELOW"})
	data["entities"].append({"type": "crate", "cell": Vector2i(cx + 6, fy)})
	data["landmarks"].append({"kind": "arrival_room", "rect": room})


# --- 6 water pockets ---------------------------------------------------------
## Pockets of every size, kept apart from each other. A pocket is an ellipse
## of open space, filled with water to near its top. Where a cave cuts into
## one it becomes an open pond; the rest stay sealed in rock.
func _pockets(mult: float, lakes: int) -> void:
	var plan: Array = [[lakes, 13, 5, "lake"], [4, 7, 3, "pool"], [6, 4, 2, "pocket"], [8, 2, 1, "puddle"]]
	for entry: Array in plan:
		var made := 0
		var tries := 0
		var count := int(round(float(entry[0]) * (mult if String(entry[3]) != "lake" else 1.0)))
		while made < count and tries < 600:
			tries += 1
			var rx := int(entry[1]) + rng.randi_range(-1, 1)
			var ry := int(entry[2]) + (rng.randi_range(0, 1) if int(entry[2]) > 1 else 0)
			var c := Vector2i(rng.randi_range(6 + rx, W - 7 - rx), rng.randi_range(FIELD_Y0 + 4 + ry, FUNNEL_Y0 - 3 - ry))
			if not _pocket_ok(c, rx, ry):
				continue
			_carve_pocket(c, rx, ry, String(entry[3]))
			made += 1


func _pocket_ok(c: Vector2i, rx: int, ry: int) -> bool:
	for p: Dictionary in pockets:
		var o: Vector2i = p["c"]
		if absi(o.x - c.x) < int(p["rx"]) + rx + 3 and absi(o.y - c.y) < int(p["ry"]) + ry + 3:
			return false
	for y in range(c.y - ry - 1, c.y + ry + 2):
		for x in range(c.x - rx - 1, c.x + rx + 2):
			if not _free(x, y):
				return false
	return true


func _carve_pocket(c: Vector2i, rx: int, ry: int, size: String) -> void:
	var cells := 0
	for y in range(c.y - ry, c.y + ry + 1):
		for x in range(c.x - rx, c.x + rx + 1):
			var dx := (float(x - c.x)) / (float(rx) + 0.5)
			var dy := (float(y - c.y)) / (float(ry) + 0.5)
			if dx * dx + dy * dy <= 1.0:
				g.put(x, y, Cell.AIR)
				# water to near the top; the highest row is left as air
				if y > c.y - ry or ry <= 1:
					g.water[g.idx(x, y)] = Balance.WATER_MAX
					cells += 1
	# a floor it cannot simply fall out of
	for x in range(c.x - rx, c.x + rx + 1):
		for y in range(c.y, c.y + ry + 2):
			if g.get_mat(x, y) == Cell.AIR and g.water[g.idx(x, y)] == 0 and _free(x, y) and y > c.y + ry:
				g.put(x, y, Cell.SOFT)
	pockets.append({"c": c, "rx": rx, "ry": ry, "size": size, "cells": cells})
	data["water_features"].append({"kind": size, "rect": Rect2i(c.x - rx, c.y - ry, rx * 2 + 1, ry * 2 + 1), "volume": cells * Balance.WATER_MAX, "cells": cells})


# --- 7 settle ----------------------------------------------------------------
func _settle(steps: int) -> int:
	var sim := WaterSim.new(g)
	var n := sim.settle(steps)
	# clear 1-2 unit films that would jitter for ever
	for i in g.water.size():
		if g.water[i] > 0 and g.water[i] <= 2:
			g.water[i] = 0
	return n


# --- 8 floor film ------------------------------------------------------------
## Even the dry galleries are wet underfoot: a shallow film on many cave
## floors, which gathers into puddles in the low spots.
func _film() -> void:
	for y in range(FIELD_Y0, FUNNEL_Y0 + 6):
		for x in range(4, W - 4):
			var i := g.idx(x, y)
			if g.mat[i] == Cell.AIR and g.water[i] == 0 and g.is_solid(x, y + 1) and not keep.has(Vector2i(x, y)) and rng.randf() < 0.55:
				g.water[i] = rng.randi_range(8, 14)


# --- 9 ore -------------------------------------------------------------------
func _ore() -> void:
	var made := 0
	var tries := 0
	while made < 34 and tries < 4000:
		tries += 1
		var x := rng.randi_range(5, W - 6)
		var y := rng.randi_range(FIELD_Y0, bed_y0 - 2)
		if not _free(x, y) or not (g.get_mat(x, y) in [Cell.SOFT, Cell.HARD]) or g.get_ore(x, y) != 0:
			continue
		var open := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not g.is_solid(x + d.x, y + d.y):
				open = true
		if not open:
			continue
		g.put(x, y, g.get_mat(x, y), Cell.ORE_COBALT if (y > 46 and rng.randf() < 0.4) else Cell.ORE_COPPER)
		made += 1
	data["ore_cells"] = made


# --- 10 basalt ---------------------------------------------------------------
func _stabilize() -> void:
	for y in range(2, H - 4):
		for x in range(2, W - 2):
			if g.get_mat(x, y) == Cell.HARD and not g.is_solid(x, y + 1) and not g.has_flag(x, y, Cell.F_PROTECTED):
				for c in Boulders.unsupported_mass(g, Vector2i(x, y)):
					if not g.has_flag(c.x, c.y, Cell.F_PROTECTED):
						g.put(c.x, c.y, Cell.SOFT, g.get_ore(c.x, c.y))


# --- 11 greenery and eels ----------------------------------------------------
## Patches of grass, reeds and moss on floors beside water.
func _greenery() -> void:
	var patches := 0
	var used: Dictionary = {}
	for y in range(FIELD_Y0, bed_y0):
		for x in range(4, W - 4):
			if patches >= 26:
				break
			var c := Vector2i(x, y)
			if used.has(c) or not _grows(x, y):
				continue
			var wet := false
			for dx in range(-3, 4):
				for dy in range(-1, 2):
					if g.in_bounds(x + dx, y + dy) and g.water[g.idx(x + dx, y + dy)] >= 6:
						wet = true
			# the whole cavern is damp: beside water it is lush, elsewhere sparse
			if rng.randf() > (0.7 if wet else 0.22):
				continue
			# a patch runs along the floor for a few cells
			var cells: Array = []
			for k in rng.randi_range(2, 6):
				var p := Vector2i(x + k, y)
				if _grows(p.x, p.y):
					cells.append(p)
					for dx in range(-4, 5):
						used[Vector2i(p.x + dx, y)] = true
				else:
					break
			if cells.size() >= 2:
				data["entities"].append({"type": "greenery", "cell": cells[0], "cells": cells, "seed": rng.randi()})
				patches += 1
	data["greenery"] = patches


## Somewhere greenery can root: an open floor of sediment or stone, dry or
## under shallow water (reeds stand in puddles), outside the built rooms.
func _grows(x: int, y: int) -> bool:
	return g.get_mat(x, y) == Cell.AIR and g.get_mat(x, y + 1) in [Cell.SOFT, Cell.HARD] and g.water[g.idx(x, y)] <= 40 \
		and not keep.has(Vector2i(x, y)) and not g.has_flag(x, y + 1, Cell.F_PROTECTED)


func _eels(count: int) -> void:
	var big: Array = pockets.duplicate()
	big.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["cells"]) > int(b["cells"]))
	var made := 0
	for p: Dictionary in big:
		if made >= count:
			break
		var c: Vector2i = p["c"]
		# the pocket may have drained while settling: only where it is still deep
		var ok := true
		for dx in range(-1, 2):
			if g.is_solid(c.x + dx, c.y) or g.water[g.idx(c.x + dx, c.y)] < Balance.WATER_MAX * 3 / 4:
				ok = false
		if ok:
			data["entities"].append({"type": "kin", "kind": "eel", "cell": c})
			made += 1
	data["eels"] = made


# --- 13 measure --------------------------------------------------------------
func _measure(target: float) -> void:
	var bed: Rect2i = data["bed"]
	var cap := 0
	var held := 0
	for y in range(bed.position.y, bed.end.y):
		for x in range(bed.position.x, bed.end.x):
			if not g.is_solid(x, y):
				cap += Balance.WATER_MAX
				held += g.water[g.idx(x, y)]
	var above := 0
	for y in range(2, bed.position.y):
		for x in range(2, W - 2):
			above += g.water[g.idx(x, y)]
	data["bed_capacity"] = cap
	data["bed_start"] = held
	data["bed_target"] = target
	data["water_above"] = above
	# the way down, with starting gear (the model may raise Rubble Ladders)
	var dc := DigCheck.new(g)
	dc.allow_ladder = true
	var from_spawn := dc.costs_from(data["spawn"])
	data["dig_to_lift_s"] = GenMetrics._near(dc, from_spawn, data["mission_lift"])
	data["valid"] = float(data["dig_to_lift_s"]) >= 0.0 and float(above) >= float(cap) * target * 1.3
