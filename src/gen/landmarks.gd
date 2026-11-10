class_name Landmarks
extends RefCounted
## Optional landmark templates. Each claims a full footprint (GenSpace), keeps
## clear of the guaranteed route and its supports, and records what it is in
## data["landmarks"] (and data["water_features"] when water is involved).
##
##   floodgate          tall sealed reservoir beside a side chamber; a cracked dam
##                      at the bottom: breach it for a pressure jet that floods
##                      the chamber below (finite volume, treasure on the floor)
##   flooded_machinery  Engine ruin with a sunken, flooded machinery pit, dry
##                      door ledges, floating crates/canisters, salvage
##   hanging_gallery    cavern with basalt masses hung on sediment necks above a
##                      crawler patrol: drop the stone on the enemy
##   survey_post        small abandoned room behind a cracked wall with supplies
##   vent_cluster       a side cavern whose walls are riddled with gas sacs
##   cistern            two sealed cavities at different levels, split by a thin
##                      sediment wall: break it and the levels equalise

var gen: MineGenerator
var g: TerrainGrid
var rng: RandomNumberGenerator


func _init(generator: MineGenerator, r: RandomNumberGenerator) -> void:
	gen = generator
	g = generator.g
	rng = r


func _record(kind: String, r: Rect2i, extra: Dictionary = {}) -> void:
	var d := {"kind": kind, "rect": r}
	d.merge(extra)
	gen.data["landmarks"].append(d)


func _water(kind: String, r: Rect2i, cells: Array, extra: Dictionary = {}) -> int:
	var vol := 0
	for c in cells:
		g.water[g.idx(c.x, c.y)] = Balance.WATER_MAX
		vol += Balance.WATER_MAX
	var d := {"kind": kind, "rect": r, "volume": vol, "cells": cells.size()}
	d.merge(extra)
	gen.data["water_features"].append(d)
	return vol


func _rock_box_ok(r: Rect2i) -> bool:
	## all solid, nothing claimed/reserved/protected
	if not gen.space.fits(r, 0):
		return false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if not g.is_solid(x, y) or gen.reserved.has(c) or gen.support.has(c) or gen.no_feature.has(c):
				return false
			if g.has_flag(x, y, Cell.F_PROTECTED) or g.get_mat(x, y) == Cell.ALLOY:
				return false
	return true


# ---------------------------------------------------------------------------
func floodgate(prefer_stratum: int, strict: bool = false) -> bool:
	## Reservoir beside a non-backbone chamber whose floor sits at the dam foot.
	var cands: Array = []
	for c in gen.chambers:
		if not c["backbone"] and c["arch"] in ["hall", "works", "terraces", "cathedral"]:
			if strict and int(c["stratum"]) != prefer_stratum:
				continue
			cands.append(c)
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absi(int(a["stratum"]) - prefer_stratum) < absi(int(b["stratum"]) - prefer_stratum))
	for c in cands:
		var r: Rect2i = c["rect"]
		for side in [1, -1] if rng.randf() < 0.5 else [-1, 1]:
			var anchor: Vector2i = c["exit"] if (side == 1) == (c["exit"].x > c["entry"].x) else c["entry"]
			var fy: int = anchor.y
			var w := rng.randi_range(4, 6)
			var h := rng.randi_range(7, 10)
			var dam_x: int = r.end.x if side == 1 else r.position.x - 1
			# the chamber side of the dam must be open at the dam foot
			var open_foot := true
			for dy in range(-2, 1):
				if g.is_solid(dam_x - side, fy + dy):
					open_foot = false
			if not open_foot:
				continue
			var ix0: int = dam_x + 1 if side == 1 else dam_x - w
			var inner := Rect2i(ix0, fy - h + 1, w, h)
			var shell := inner.grow(1)
			# The rock check omits the dam, but its full footprint must be free.
			if not gen.space.fits(shell, 0):
				continue
			if not _rock_box_ok(Rect2i(shell.position.x + (1 if side == 1 else 0), shell.position.y, shell.size.x - 1, shell.size.y)):
				continue
			gen.space.claim(shell, "landmark", "floodgate")
			var cells: Array = []
			for y in range(inner.position.y, inner.end.y):
				for x in range(inner.position.x, inner.end.x):
					g.put(x, y, Cell.AIR)
					cells.append(Vector2i(x, y))
			for y in range(shell.position.y, shell.end.y):
				for x in range(shell.position.x, shell.end.x):
					if not inner.has_point(Vector2i(x, y)) and x != dam_x:
						g.put(x, y, Cell.HARD)
					gen.no_feature[Vector2i(x, y)] = true
			# dam: cracked at the foot (the readable weak point), basalt above
			for y in range(shell.position.y, shell.end.y):
				g.put(dam_x, y, Cell.CRACKED if y >= fy - 2 and y <= fy else Cell.HARD)
			# treasure on the reservoir floor
			for x in range(inner.position.x, inner.end.x):
				if rng.randf() < 0.6:
					g.put(x, inner.end.y, Cell.HARD, Cell.ORE_AETHER if c["stratum"] >= 1 and rng.randf() < 0.5 else Cell.ORE_COBALT)
			gen.seal_rect(shell)
			_water("reservoir", inner, cells, {"head": h, "outlet": Vector2i(dam_x, fy), "catch": c["id"]})
			gen.data["entities"].append({"type": "sign", "cell": Vector2i(dam_x - side * 2, fy), "text": "FLOODGATE"})
			_record("floodgate", shell, {"catch": c["id"]})
			return true
	return false


## Rows and columns of zone z that landmarks may use (clear of zone edges).
func band(z: int) -> Rect2i:
	var zr: Rect2i = Balance.ZONE_RECTS[z]
	var top := 16 if z == Balance.Z_DUST else zr.position.y + (3 if z == Balance.Z_ENGINE else 8)
	var bottom := zr.end.y - (1 if z == Balance.Z_ENGINE else 5)
	return Rect2i(zr.position.x + 2, top, zr.size.x - 4, bottom - top)


func _place(z: int, w: int, h: int) -> Rect2i:
	var b := band(z)
	return gen._place_landmark(w, h, b.position.y, b.end.y, 2, b.position.x, b.end.x)


func flooded_machinery(z: int = Balance.Z_ENGINE) -> bool:
	var w := rng.randi_range(12, 16)
	var h := 9
	var r := _place(z, w, h)
	if r.size.x == 0:
		return false
	gen.space.claim(r, "landmark", "flooded_machinery")
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			g.put(x, y, Cell.ALLOY)
			gen.no_feature[Vector2i(x, y)] = true
	for y in range(r.position.y + 1, r.end.y - 1):
		for x in range(r.position.x + 1, r.end.x - 1):
			g.put(x, y, Cell.AIR)
	var pit_top := r.end.y - 4          # water rows: pit_top .. r.end.y - 2
	var feet := pit_top - 1             # door sills sit just above the water
	for k in [1, 2]:
		g.put(r.position.x + k, pit_top, Cell.ALLOY)
		g.put(r.end.x - 1 - k, pit_top, Cell.ALLOY)
		for y in range(pit_top + 1, r.end.y - 1):
			g.put(r.position.x + k, y, Cell.ALLOY)
			g.put(r.end.x - 1 - k, y, Cell.ALLOY)
	for dy in range(-2, 1):
		g.put(r.position.x, feet + dy, Cell.AIR)
		g.put(r.end.x - 1, feet + dy, Cell.AIR)
	var cells: Array = []
	for y in range(pit_top, r.end.y - 1):
		for x in range(r.position.x + 3, r.end.x - 3):
			cells.append(Vector2i(x, y))
	gen.seal_around(cells)
	_water("flooded_ruin", r, cells, {"head": r.end.y - 1 - pit_top})
	# salvage on the pit floor, floating junk, a ceiling sentry over the pit
	for x in range(r.position.x + 3, r.end.x - 3):
		if rng.randf() < 0.35:
			g.put(x, r.end.y - 1, Cell.ALLOY)
			g.put(x, r.end.y, Cell.HARD, Cell.ORE_AETHER)
	var props: Array = gen.data.get("lm_props", [])
	for k in rng.randi_range(2, 3):
		var px := rng.randi_range(r.position.x + 4, r.end.x - 5)
		props.append({"kind": ["crate", "canister"][k % 2], "cell": Vector2i(px, pit_top)})
	gen.data["lm_props"] = props
	var sx := r.position.x + r.size.x / 2
	gen.data["entities"].append({"type": "sentry", "cell": Vector2i(sx, r.position.y + 1), "ceiling": true, "module": Vector2i(r.position.x + 1, r.position.y + 1)})
	# doors open onto short approaches and a passage toward the route
	for side in [-1, 1]:
		var dx: int = r.position.x if side == -1 else r.end.x - 1
		for k in range(1, 3):
			for dy in range(-2, 1):
				var c := Vector2i(dx + side * k, feet + dy)
				if gen.tunnel_ok(c.x, c.y):
					g.put(c.x, c.y, Cell.AIR)
			var fc := Vector2i(dx + side * k, feet + 1)
			if not g.is_solid(fc.x, fc.y) and gen.tunnel_ok(fc.x, fc.y):
				g.put(fc.x, fc.y, Cell.HARD)
	_connect_to_route(Vector2(r.position.x - 2, feet - 0.5) if rng.randf() < 0.5 else Vector2(r.end.x + 1, feet - 0.5))
	_record("flooded_machinery", r)
	return true


func hanging_gallery(s: int) -> bool:
	var r := _place(s, rng.randi_range(16, 20), 8)
	if r.size.x == 0:
		return false
	gen.space.claim(r, "landmark", "hanging_gallery")
	var fy := r.end.y - 1
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, fy + 1):
			g.put(x, y, Cell.AIR)
		if not g.is_solid(x, fy + 1):
			g.put(x, fy + 1, Cell.HARD)
		g.put(x, r.position.y - 1, Cell.SOFT)
		gen.no_feature[Vector2i(x, fy)] = true
	# basalt masses hung on single sediment necks from the ceiling
	var n := rng.randi_range(2, 3)
	var spacing := r.size.x / (n + 1)
	for k in n:
		var bx := r.position.x + spacing * (k + 1)
		var ny := r.position.y
		g.put(bx, ny, Cell.SOFT)                  # neck
		for yy in range(ny + 1, ny + 3):
			for xx in range(bx - 1, bx + 2):
				g.put(xx, yy, Cell.HARD, Cell.ORE_COBALT if rng.randf() < 0.15 else Cell.ORE_NONE)
				gen.no_feature[Vector2i(xx, yy)] = true
		var sp: Vector2i = gen.data["spawn"]
		if absi(bx - sp.x) + absi(fy - sp.y) >= 26:
			gen.data["entities"].append({"type": "crawler", "cell": Vector2i(bx, fy), "role": "patrol"})
	_connect_to_route(Vector2(r.position.x + 0.5, fy - 0.5) if rng.randf() < 0.5 else Vector2(r.end.x - 0.5, fy - 0.5))
	_record("hanging_gallery", r, {"boulders": n})
	gen.data["boulders"] = int(gen.data.get("boulders", 0)) + n
	return true


func survey_post(z: int = -1) -> bool:
	if z < 0:
		z = rng.randi_range(0, Balance.ZONE_COUNT - 1)
	var r := _place(z, 9, 6)
	if r.size.x == 0:
		return false
	gen.space.claim(r, "landmark", "survey_post")
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			g.put(x, y, Cell.HARD)
			gen.no_feature[Vector2i(x, y)] = true
	var inner := Rect2i(r.position.x + 1, r.position.y + 1, r.size.x - 2, r.size.y - 2)
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			g.put(x, y, Cell.AIR)
	var fy := inner.end.y - 1
	gen.data["entities"].append({"type": "cache", "cell": Vector2i(inner.position.x + 1, fy), "charges": 1, "repair": 25})
	gen.seal_rect(r)
	gen.data["entities"].append({"type": "lamp", "cell": Vector2i(inner.position.x + inner.size.x / 2, inner.position.y)})
	gen.data["entities"].append({"type": "sign", "cell": Vector2i(inner.end.x - 2, fy), "text": "SURVEY POST"})
	gen._connect_secret(Rect2i(inner.position.x, inner.position.y, inner.size.x, inner.size.y + 1), Cell.CRACKED)
	_record("survey_post", r)
	return true


func vent_cluster() -> bool:
	## A side chamber whose walls are riddled with gas sacs. The route never runs
	## through it, so the danger is opt-in and readable from the doorway.
	for c in gen.chambers:
		if c["backbone"] or c.get("vents", false):
			continue
		var r: Rect2i = c["rect"]
		var placed := 0
		for y in range(r.position.y - 1, r.end.y + 2):
			for x in range(r.position.x - 1, r.end.x + 1):
				if not g.is_solid(x, y) or g.get_mat(x, y) in [Cell.ALLOY, Cell.BEDROCK, Cell.GAS]:
					continue
				var cc := Vector2i(x, y)
				if gen.reserved.has(cc) or gen.support.has(cc) or gen.no_feature.has(cc) or g.has_flag(x, y, Cell.F_PROTECTED):
					continue
				if not gen._near_open(x, y, 1) or rng.randf() > 0.32:
					continue
				# never under a standing surface (gas sacs are breakable floors)
				if not g.is_solid(x, y - 1) and y >= r.end.y - 1:
					continue
				g.put(x, y, Cell.GAS)
				gen.no_feature[cc] = true
				placed += 1
		if placed >= 6:
			c["vents"] = true
			gen.data["entities"].append({"type": "sign", "cell": c["entry"], "text": "VENTS"})
			_record("vent_cluster", r, {"sacs": placed, "chamber": c["id"]})
			return true
	return false


func cistern(z: int = Balance.Z_SPORE) -> bool:
	var zb := band(z)
	for attempt in 80:
		var w1 := rng.randi_range(5, 6)
		var w2 := rng.randi_range(4, 6)
		var h1 := rng.randi_range(4, 6)
		var drop := rng.randi_range(2, 3)
		var x0 := rng.randi_range(zb.position.x + 2, zb.end.x - w1 - w2 - 4)
		var y0 := rng.randi_range(zb.position.y, zb.end.y - h1 - drop - 2)
		var a := Rect2i(x0, y0, w1, h1)                     # upper, full
		var b := Rect2i(x0 + w1 + 1, y0 + drop, w2, h1)     # lower, empty
		var whole := Rect2i(x0 - 1, y0 - 1, w1 + w2 + 3, h1 + drop + 2)
		if not _rock_box_ok(whole):
			continue
		gen.space.claim(whole, "landmark", "cistern")
		for y in range(whole.position.y, whole.end.y):
			for x in range(whole.position.x, whole.end.x):
				g.put(x, y, Cell.HARD)
				gen.no_feature[Vector2i(x, y)] = true
		var cells: Array = []
		for y in range(a.position.y, a.end.y):
			for x in range(a.position.x, a.end.x):
				g.put(x, y, Cell.AIR)
				cells.append(Vector2i(x, y))
		for y in range(b.position.y, b.end.y):
			for x in range(b.position.x, b.end.x):
				g.put(x, y, Cell.AIR)
		# the thin divider: sediment, readable and breakable
		for y in range(y0, y0 + h1 + drop):
			g.put(x0 + w1, y, Cell.SOFT)
		for x in range(b.position.x, b.end.x):
			if rng.randf() < 0.5:
				g.put(x, b.end.y, Cell.HARD, Cell.ORE_COBALT)
		gen.seal_rect(whole)
		_water("cistern", whole, cells, {"head": h1, "pair": b})
		_record("cistern", whole)
		return true
	return false


## Fallback water encounter: a tall sealed reservoir buried in rock. Only needs
## a free patch of rock, so it fits even in crowded strata.
func buried_reservoir(s: int) -> bool:
	var zb := band(s)
	var y_lo: int = zb.position.y
	var y_hi: int = zb.end.y
	for attempt in 240:
		var w := rng.randi_range(4, 5)
		var h := rng.randi_range(6, 8)
		var x0 := rng.randi_range(zb.position.x + 1, zb.end.x - w - 2)
		var y0 := rng.randi_range(y_lo, maxi(y_lo, y_hi - h))
		var inner := Rect2i(x0, y0, w, h)
		var shell := inner.grow(1)
		if not _rock_box_ok(shell):
			continue
		gen.space.claim(shell, "water", "reservoir")
		var cells: Array = []
		for y in range(shell.position.y, shell.end.y):
			for x in range(shell.position.x, shell.end.x):
				gen.no_feature[Vector2i(x, y)] = true
				if inner.has_point(Vector2i(x, y)):
					g.put(x, y, Cell.AIR)
					cells.append(Vector2i(x, y))
				else:
					g.put(x, y, Cell.HARD)
		# a cracked seam low on one side hints at the weak point
		var side_x := shell.position.x if rng.randf() < 0.5 else shell.end.x - 1
		g.put(side_x, inner.end.y - 1, Cell.CRACKED)
		for x in range(inner.position.x, inner.end.x):
			if rng.randf() < 0.5:
				g.put(x, inner.end.y, Cell.HARD, Cell.ORE_COBALT)
		gen.seal_rect(shell)
		_water("reservoir", inner, cells, {"head": h, "outlet": Vector2i(side_x, inner.end.y - 1)})
		return true
	return false


func _connect_to_route(from: Vector2) -> void:
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	var z := g.get_stratum(int(from.x), int(from.y))
	for rc in gen.data["route"]:
		if g.get_stratum(rc.x, rc.y) != z:
			continue   # never aim a passage through the bedrock between zones
		var d: int = absi(rc.x - int(from.x)) + absi(rc.y - int(from.y))
		if d < bd:
			bd = d
			best = rc
	if best.x >= 0 and bd < 60:
		gen.carver.tunnel(from, Vector2(best) + Vector2(0.5, -0.5), 1.3, 1.8, 0.25)
		gen.branches += 1


## Drowned Aqueducts: a long stone channel still full of water. Walk the rim
## above it, dive for the ore on its bed, or crack an end wall low down and
## send the whole length pouring into the galleries below.
func aqueduct_channel() -> bool:
	var w := rng.randi_range(16, 26)
	var h := 6
	var r := _place(Balance.Z_AQUEDUCT, w, h)
	if r.size.x == 0:
		r = _place(Balance.Z_AQUEDUCT, 14, h)
	if r.size.x == 0:
		return false
	gen.space.claim(r, "landmark", "aqueduct")
	var bed := r.end.y - 1                 # stone bed row
	var water_top := bed - 2               # two rows of water
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == bed
			g.put(x, y, Cell.HARD if edge else Cell.AIR)
			gen.no_feature[Vector2i(x, y)] = true
	# piers every few cells carry the vault (and give the swimmer cover)
	var cells: Array = []
	for x in range(r.position.x + 1, r.end.x - 1):
		var pier := (x - r.position.x) % 6 == 3
		for y in range(water_top, bed):
			if pier:
				g.put(x, y, Cell.HARD)
			else:
				cells.append(Vector2i(x, y))
		if not pier and rng.randf() < 0.3:
			g.put(x, bed, Cell.HARD, Cell.ORE_AETHER if rng.randf() < 0.35 else Cell.ORE_COBALT)
	# the weak point: a cracked block low in one end wall
	var weak_x := r.position.x if rng.randf() < 0.5 else r.end.x - 1
	g.put(weak_x, bed - 1, Cell.CRACKED)
	gen.seal_rect(r)
	_water("aqueduct", r, cells, {"head": 2, "outlet": Vector2i(weak_x, bed - 1)})
	# entrance over the rim at the far end from the weak point
	var door_x := r.end.x - 1 if weak_x == r.position.x else r.position.x
	var feet := water_top - 1
	for dy in range(-1, 1):
		g.put(door_x, feet + dy, Cell.AIR)
	gen.data["entities"].append({"type": "lamp", "cell": Vector2i(r.position.x + r.size.x / 2, r.position.y + 1), "color": "6fd8ff"})
	_connect_to_route(Vector2(door_x + (1.5 if door_x > weak_x else -0.5), feet - 0.5))
	_record("aqueduct", r)
	return true
