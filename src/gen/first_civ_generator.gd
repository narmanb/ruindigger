class_name FirstCivGenerator
extends RefCounted
## Seeded generator for THE FIRST CIVILIZATION: a separate, one-way stage far
## below the Forgotten Engine (working title in the spec: the Primordial Vault).
## It builds its own 200x120 map and returns the same data contract as
## MineGenerator, so Mine runs it unchanged.
##
## PASS ORDER (load-bearing):
##  1 base rock + bedrock rim          2 natural caves
##  3 arrival shaft and hall (spawn)   4 Transit Gate hall at the bottom
##  4b Thermal Plant hall: lava tank over a heat basin, water tank over a
##     coolant basin, the engine between; valve consoles release the tanks
##  5 great vaults                     6 buried monoliths of ancient composite
##  7 link tunnels arrival -> vaults -> gate (parts left as cracked rock)
##  8 long transit tunnels             9 ore
## 10 water pockets and cooling basins, settled with the water sim
## 10b lava: pits in lower vault floors, sealed pockets, and quench pairs (a
##    water pocket over a lava pocket); never touching water; settled
## 11 basalt stabilisation            12 guardians, lamps, records
## 13 hit points                      14 validation: seal every cell that
##    cannot reach the gate, then prove arrival -> gate within the dig budget
## 15 furnishing: background structures for each named vault, the wrecked
##    lift, rails in the transit tunnels, gate pylons. Entities only, placed
##    on the final terrain; never edits a cell (own RNG stream, deco_rng)
##
## There is no lift and no way back up: fairness here means "from anywhere you
## can get into, you can still reach the Transit Gate" (DigCheck, starting gear).

const VERSION := 1

var g: TerrainGrid
var W: int
var H: int
var data: Dictionary
var space: GenSpace
var reserved: Dictionary = {}      # cells later passes must never fill or seal
var no_feature: Dictionary = {}    # cells where ore / water / enemies must not appear
var repairs := 0
var no_repair := false
var topo := RandomNumberGenerator.new()
var ore_rng := RandomNumberGenerator.new()
var water_rng := RandomNumberGenerator.new()
var enc_rng := RandomNumberGenerator.new()
var deco_rng := RandomNumberGenerator.new()
var vaults: Array = []             # [{rect, band}]
var _z := Balance.Z_FIRST


## The deep stage's seed is derived from the run's seed, so one contract seed
## always gives the same mine AND the same First Civilization.
static func deep_seed(run_seed: int) -> int:
	return hash("first-civilization:%d" % run_seed) & 0x7fffffff


func generate(seed_value: int, _contract: Dictionary = {}) -> Dictionary:
	W = Balance.DEEP_W
	H = Balance.DEEP_H
	g = TerrainGrid.new(W, H)
	topo.seed = seed_value ^ 0x31766963
	ore_rng.seed = seed_value ^ 0x3265726f
	water_rng.seed = seed_value ^ 0x33727477
	enc_rng.seed = seed_value ^ 0x34636e65
	deco_rng.seed = seed_value ^ 0x35636564
	space = GenSpace.new(W, H)
	data = {"seed": seed_value, "stage": "deep", "entities": [], "grid": g, "route": [], "version": VERSION,
		"landmarks": [], "water_features": [], "lava_features": [], "water_props": [], "finds": []}
	var col: Color = Balance.ZONE_COLORS[_z]
	data["zones"] = [
		{"id": _z, "name": Balance.DEEP_REGION_NAMES[0], "rect": Rect2i(2, 2, W - 4, Balance.DEEP_BAND_PLANT - 2), "color": col},
		{"id": _z, "name": Balance.DEEP_REGION_NAMES[1], "rect": Rect2i(2, Balance.DEEP_BAND_PLANT, W - 4, Balance.DEEP_BAND_TRANSIT - Balance.DEEP_BAND_PLANT), "color": col},
		{"id": _z, "name": Balance.DEEP_REGION_NAMES[2], "rect": Rect2i(2, Balance.DEEP_BAND_TRANSIT, W - 4, H - 4 - Balance.DEEP_BAND_TRANSIT), "color": col},
	]
	_base_fill(seed_value)
	_caves(seed_value)
	_arrival()
	_gate_hall()
	_thermal_plant()
	_great_vaults()
	_monoliths()
	_link_tunnels()
	_transit_tunnels()
	_ore()
	_water()
	_lava()
	_stabilize_basalt()
	_guardians_and_records()
	for i in g.mat.size():
		g.hp[i] = Cell.max_hp(g.mat[i])
	_validate()
	_furnish()
	data["repairs"] = repairs
	data["plan"] = {"vaults": vaults.size(), "monoliths": int(data.get("monoliths", 0)), "plugs": int(data.get("plugs", 0)),
		"overlaps": space.overlaps()}
	return data


# --- helpers -----------------------------------------------------------------
func band_of(y: int) -> int:
	return 0 if y < Balance.DEEP_BAND_PLANT else (1 if y < Balance.DEEP_BAND_TRANSIT else 2)


func _rim(x: int, y: int) -> bool:
	return x < 2 or x >= W - 2 or y < 2 or y >= H - 4


## May a pass carve or overwrite this cell? Never the rim, protected cells,
## the ancient composite, or anything a structure reserved.
func writable(x: int, y: int) -> bool:
	if not g.in_bounds(x, y) or _rim(x, y):
		return false
	if g.has_flag(x, y, Cell.F_PROTECTED) or reserved.has(Vector2i(x, y)):
		return false
	var m := g.get_mat(x, y)
	return m != Cell.ALLOY and m != Cell.BEDROCK and m != Cell.LADDER and m != Cell.PLATFORM


func _air(x: int, y: int) -> void:
	if writable(x, y):
		g.put(x, y, Cell.AIR)


func _fill(r: Rect2i, m: int, flags_on: int = 0) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if g.in_bounds(x, y) and not _rim(x, y):
				g.put(x, y, m)
				if flags_on:
					g.set_flag(x, y, flags_on)


func _reserve(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			reserved[Vector2i(x, y)] = true
			no_feature[Vector2i(x, y)] = true


func _mark_no_feature(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			no_feature[Vector2i(x, y)] = true


# --- 1-2 rock and caves --------------------------------------------------------
func _base_fill(seed_value: int) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.06
	n.fractal_octaves = 3
	for y in H:
		for x in W:
			g.stratum[g.idx(x, y)] = _z
			if _rim(x, y):
				g.put(x, y, Cell.BEDROCK)
				g.set_flag(x, y, Cell.F_PROTECTED)
				continue
			# deeper rock is harder: the lower transit level is mostly obsidian
			var thr: float = Balance.DEEP_HARD_THRESH - 0.18 * float(y) / H
			g.put(x, y, Cell.HARD if n.get_noise_2d(x, y) > thr else Cell.SOFT)


func _caves(seed_value: int) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_value + 17
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_octaves = 2
	n.frequency = 0.045
	for y in range(6, H - 8):
		for x in range(4, W - 4):
			# geothermal cracks: tall in the plant, low galleries elsewhere
			var v := n.get_noise_2d(x * 1.5, y * 0.6) if band_of(y) == 1 else n.get_noise_2d(x * 0.55, y * 1.7)
			if v > Balance.DEEP_CAVE_THRESH:
				g.put(x, y, Cell.AIR)
	# one smoothing pass, then fill confetti pockets
	var copy := g.mat.duplicate()
	for y in range(6, H - 8):
		for x in range(4, W - 4):
			var solid := 0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if Cell.is_solid(copy[g.idx(x + dx, y + dy)]):
						solid += 1
			var i := g.idx(x, y)
			if solid >= 6 and copy[i] == Cell.AIR:
				g.put(x, y, Cell.HARD)
			elif solid <= 3 and Cell.is_solid(copy[i]) and copy[i] != Cell.BEDROCK:
				g.put(x, y, Cell.AIR)
	var seen := PackedByteArray()
	seen.resize(W * H)
	var region := PackedInt32Array()
	for start in W * H:
		if g.mat[start] != Cell.AIR or seen[start] == 1:
			continue
		region.clear()
		region.append(start)
		seen[start] = 1
		var head := 0
		while head < region.size() and region.size() < 40:
			var cc := region[head]
			head += 1
			for nn in [cc + 1, cc - 1, cc + W, cc - W]:
				if nn >= 0 and nn < W * H and g.mat[nn] == Cell.AIR and seen[nn] == 0:
					seen[nn] = 1
					region.append(nn)
		if region.size() < 8:
			for cc in region:
				g.put(cc % W, cc / W, Cell.SOFT)


# --- 3 arrival -----------------------------------------------------------------
## The receiving shaft the dead elevator dropped into, and the hall under it.
## The shaft ends in bedrock: there is nothing to climb back to.
func _arrival() -> void:
	var ax := topo.randi_range(40, W - 41)
	var hall := Rect2i(ax - 12, 9, 25, 7)          # interior
	var shell := hall.grow(1)
	_fill(shell, Cell.ALLOY)
	_fill(hall, Cell.AIR, Cell.F_NO_RUBBLE)
	# the floor is the one thing here nothing may break
	for x in range(shell.position.x, shell.end.x):
		g.set_flag(x, hall.end.y, Cell.F_PROTECTED)
	# the shaft the cage fell down, open into the hall's ceiling
	for y in range(2, hall.position.y):
		for x in range(ax - 1, ax + 2):
			g.set_flag(x, y, Cell.F_PROTECTED, false)
			g.put(x, y, Cell.AIR)
			g.set_flag(x, y, Cell.F_NO_RUBBLE)
		for x in [ax - 2, ax + 2]:
			g.put(x, y, Cell.ALLOY)
	# doorways at floor level on both sides
	var fy := hall.end.y - 1
	for side_x in [shell.position.x, shell.end.x - 1]:
		for dy in range(-2, 1):
			g.put(side_x, fy + dy, Cell.AIR)
	_reserve(Rect2i(shell.position.x, 2, shell.size.x, shell.end.y - 2))
	space.claim(Rect2i(shell.position.x - 2, 2, shell.size.x + 4, shell.end.y), "anchor", "arrival")
	data["spawn"] = Vector2i(ax, fy)
	data["arrival"] = hall
	data["landmarks"].append({"kind": "arrival_hall", "rect": hall})
	data["entities"].append({"type": "sign", "cell": Vector2i(ax + 4, fy), "text": "LIFT WRECKED"})
	data["entities"].append({"type": "lamp", "cell": Vector2i(ax - 8, hall.position.y), "color": "ffb070"})
	data["entities"].append({"type": "lamp", "cell": Vector2i(ax + 8, hall.position.y), "color": "ffb070"})
	data["entities"].append({"type": "crate", "cell": Vector2i(ax - 3, fy)})


# --- 4 transit gate ------------------------------------------------------------
func _gate_hall() -> void:
	var w := 27
	var h := 9
	var x0 := topo.randi_range(24, W - w - 24)
	var y0 := H - 4 - h - 1 - topo.randi_range(1, 3)
	var hall := Rect2i(x0, y0, w, h)               # interior
	var shell := hall.grow(1)
	_fill(shell, Cell.ALLOY, Cell.F_PROTECTED)
	_fill(hall, Cell.AIR, Cell.F_NO_RUBBLE)
	for y in range(hall.position.y, hall.end.y):
		for x in range(hall.position.x, hall.end.x):
			g.set_flag(x, y, Cell.F_PROTECTED, false)
	var fy := hall.end.y - 1
	for side_x in [shell.position.x, shell.end.x - 1]:
		for dy in range(-2, 1):
			g.set_flag(side_x, fy + dy, Cell.F_PROTECTED, false)
			g.put(side_x, fy + dy, Cell.AIR)
	_reserve(shell)
	space.claim(shell.grow(2), "anchor", "gate_hall")
	var gate := Vector2i(x0 + w / 2, fy)
	data["gate"] = gate
	data["gate_hall"] = hall
	data["gate_doors"] = [Vector2i(shell.position.x, fy), Vector2i(shell.end.x - 1, fy)]
	data["landmarks"].append({"kind": "transit_gate", "rect": hall})
	data["entities"].append({"type": "transit_gate", "cell": gate})
	data["entities"].append({"type": "lamp", "cell": Vector2i(x0 + 3, y0), "color": "6ff3ff"})
	data["entities"].append({"type": "lamp", "cell": Vector2i(x0 + w - 4, y0), "color": "6ff3ff"})
	data["entities"].append({"type": "sign", "cell": Vector2i(x0 + 4, fy), "text": "TRANSIT"})


# --- 4b thermal plant -----------------------------------------------------------
## The geothermal engine that powers the Transit Gate. Layout along the hall,
## counted from the far wall (i = 0) to the door (i = 35):
##   lava tank over heat basin 1..7 | heat valve 10 | engine 13..19 |
##   coolant valve 22 | water tank over coolant basin 25..31 | walkway 32..35
## Each tank holds 3.5x what its basin needs, so a mistake is recoverable.
func _plant_x(i: int, L: int, door_right: bool) -> int:
	return L + i if door_right else L + Balance.PLANT_W - 1 - i


func _thermal_plant() -> void:
	var w: int = Balance.PLANT_W
	var h: int = Balance.PLANT_H
	var r := Rect2i()
	for attempt in 80:
		var x0 := topo.randi_range(6, W - w - 7)
		var y0 := topo.randi_range(Balance.DEEP_BAND_PLANT + 2, Balance.DEEP_BAND_TRANSIT - h - 3)
		var cand := Rect2i(x0, y0, w, h)
		if space.fits(cand.grow(5), 0):
			r = cand
			break
	if r.size.x == 0:
		r = Rect2i(W / 2 - w / 2, Balance.DEEP_BAND_PLANT + 4, w, h)
	space.claim(r.grow(5), "anchor", "thermal_plant")
	var door_right := r.get_center().x < W / 2      # the door faces the middle of the map
	var L := r.position.x
	var T := r.position.y
	var fy := r.end.y - 1
	# shell and floor of ancient composite; the room itself open
	_fill(Rect2i(L - 1, T - 1, w + 2, h + 6), Cell.ALLOY, Cell.F_PROTECTED)
	for y in range(T, fy + 1):
		for x in range(L, L + w):
			g.put(x, y, Cell.AIR)
			g.set_flag(x, y, Cell.F_PROTECTED, false)
			g.set_flag(x, y, Cell.F_NO_RUBBLE)
	var plant := {"hall": r, "door_right": door_right}
	for sys in ["heat", "coolant"]:
		var i0 := 1 if sys == "heat" else 25
		var basin: Array = []
		var outlet: Array = []
		for k in 7:
			var x := _plant_x(i0 + k, L, door_right)
			# the basin: a pit three cells deep in the floor
			for dy in range(1, 4):
				g.put(x, fy + dy, Cell.AIR)
				g.set_flag(x, fy + dy, Cell.F_PROTECTED, false)
				basin.append(Vector2i(x, fy + dy))
			# the tank: three rows of fluid in a composite shell, valve in its floor
			for dy in range(1, 4):
				g.put(x, T + dy, Cell.AIR)
				g.set_flag(x, T + dy, Cell.F_PROTECTED, false)
				if sys == "heat":
					g.lava[g.idx(x, T + dy)] = Balance.LAVA_MAX
				else:
					g.water[g.idx(x, T + dy)] = Balance.WATER_MAX
			g.put(x, T, Cell.ALLOY)
			g.set_flag(x, T, Cell.F_PROTECTED)
			g.put(x, T + 4, Cell.ALLOY)
			g.set_flag(x, T + 4, Cell.F_PROTECTED)
			if k >= 2 and k <= 4:
				outlet.append(Vector2i(x, T + 4))
		for side_i in [i0 - 1, i0 + 7]:
			var sx := _plant_x(side_i, L, door_right)
			for y in range(T, T + 5):
				g.put(sx, y, Cell.ALLOY)
				g.set_flag(sx, y, Cell.F_PROTECTED)
		plant[sys + "_basin"] = basin
		plant[sys + "_outlet"] = outlet
		var tx := mini(_plant_x(i0, L, door_right), _plant_x(i0 + 6, L, door_right))
		var tank := Rect2i(tx, T + 1, 7, 3)
		plant[sys + "_tank"] = tank
		var console_x := _plant_x(10 if sys == "heat" else 22, L, door_right)
		data["entities"].append({"type": "valve", "cell": Vector2i(console_x, fy), "system": sys, "outlet": outlet})
		data["entities"].append({"type": "sign", "cell": Vector2i(_plant_x(i0 + 3, L, door_right), fy), "text": "HEAT INTAKE" if sys == "heat" else "COOLANT"})
		if sys == "heat":
			data["lava_features"].append({"kind": "heat_tank", "rect": tank, "cells": 21, "volume": 21 * Balance.LAVA_MAX})
		else:
			data["water_features"].append({"kind": "coolant_tank", "rect": tank, "cells": 21, "volume": 21 * Balance.WATER_MAX})
	# the engine: a low composite block you can hop over, between the basins
	for k in range(13, 20):
		var x2 := _plant_x(k, L, door_right)
		for y in [fy - 1, fy]:
			g.put(x2, y, Cell.ALLOY)
			g.set_flag(x2, y, Cell.F_PROTECTED)
	var engine := Vector2i(_plant_x(16, L, door_right), fy - 2)
	data["entities"].append({"type": "thermal_engine", "cell": engine})
	data["entities"].append({"type": "lamp", "cell": Vector2i(_plant_x(11, L, door_right), T + 5), "color": "ff8a3a"})
	data["entities"].append({"type": "lamp", "cell": Vector2i(_plant_x(23, L, door_right), T + 5), "color": "6ff3ff"})
	# the door, on the side facing the middle of the map
	var door_x := L + w if door_right else L - 1
	for dy in range(-2, 1):
		g.set_flag(door_x, fy + dy, Cell.F_PROTECTED, false)
		g.put(door_x, fy + dy, Cell.AIR)
	plant["door"] = Vector2i(door_x, fy)
	plant["engine"] = engine
	_reserve(Rect2i(L - 1, T - 1, w + 2, h + 6))
	data["plant"] = plant
	data["landmarks"].append({"kind": "thermal_plant", "rect": r})


# --- 5 great vaults ------------------------------------------------------------
## Huge multi-screen chambers. A band of ancient composite forms each ceiling,
## and a hanging colonnade divides the hall without ever blocking the floor.
func _great_vaults() -> void:
	var want := topo.randi_range(Balance.DEEP_VAULTS[0], Balance.DEEP_VAULTS[1])
	var tries := 0
	while vaults.size() < want and tries < want * 8:
		tries += 1
		var w := topo.randi_range(Balance.DEEP_VAULT_W[0], Balance.DEEP_VAULT_W[1])
		var h := topo.randi_range(Balance.DEEP_VAULT_H[0], Balance.DEEP_VAULT_H[1])
		var r := space.place(topo, w, h, 22, H - 20, 4, 40, 5, W - 5)
		if r.size.x == 0:
			continue
		space.claim(r.grow(1), "chamber", "vault%d" % vaults.size())
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				_air(x, y)
				g.set_flag(x, y, Cell.F_NO_RUBBLE)
		# ceiling band and a solid floor
		for x in range(r.position.x - 1, r.end.x + 1):
			if writable(x, r.position.y - 1) or g.is_solid(x, r.position.y - 1):
				g.put(x, r.position.y - 1, Cell.ALLOY)
			if not g.is_solid(x, r.end.y):
				g.put(x, r.end.y, Cell.HARD)
		# hanging colonnade: pillars stop three cells above the floor
		var gap := topo.randi_range(7, 10)
		var px := r.position.x + gap / 2 + topo.randi_range(0, 2)
		while px < r.end.x - 2:
			for y in range(r.position.y, r.end.y - 3):
				g.put(px, y, Cell.ALLOY)
			px += gap
		_mark_no_feature(r.grow(1))
		var v := {"rect": r, "band": band_of(r.get_center().y), "basin": []}
		vaults.append(v)
		data["landmarks"].append({"kind": "great_vault", "rect": r})
	vaults.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["rect"] as Rect2i).position.y < (b["rect"] as Rect2i).position.y)


# --- 6 monoliths ---------------------------------------------------------------
## Buried machines: solid blocks of composite the drill cannot cut. They shape
## where you can dig; the trap audit makes sure they never box anything in.
func _monoliths() -> void:
	var want := topo.randi_range(Balance.DEEP_MONOLITHS[0], Balance.DEEP_MONOLITHS[1])
	var made := 0
	var tries := 0
	while made < want and tries < want * 10:
		tries += 1
		var w := topo.randi_range(3, 6)
		var h := topo.randi_range(6, 12)
		var r := space.place(topo, w, h, 20, H - 16, 3, 30, 5, W - 5)
		if r.size.x == 0:
			continue
		space.claim(r, "feature", "monolith%d" % made)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				g.put(x, y, Cell.ALLOY)
				no_feature[Vector2i(x, y)] = true
		data["landmarks"].append({"kind": "monolith", "rect": r})
		made += 1
	data["monoliths"] = made


# --- 7 link tunnels ------------------------------------------------------------
func _vault_port(r: Rect2i, toward_x: int) -> Vector2:
	# a point on the vault floor at the side facing `toward_x`
	var x := r.end.x - 2 if toward_x > r.get_center().x else r.position.x + 1
	return Vector2(x + 0.5, r.end.y - 1.5)


## Carve a wobbling passage from a to b. With `plug` a stretch in the middle is
## left as cracked rock: the trail is readable, the digging is yours.
func _passage(a: Vector2, b: Vector2, plug: bool) -> void:
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var perp := (b - a).orthogonal().normalized()
	var bend := topo.randf_range(-0.22, 0.22) * length
	var mid := a.lerp(b, 0.5) + perp * bend
	var steps := int(length * 2.0) + 4
	var plug_lo := topo.randf_range(0.3, 0.45)
	var plug_hi := plug_lo + topo.randf_range(0.12, 0.22)
	var phase := topo.randf() * TAU
	for i in steps + 1:
		var t := float(i) / steps
		var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t)      # quadratic bezier
		var c := Vector2i(int(p.x), int(p.y))
		data["route"].append(c)
		if plug and t > plug_lo and t < plug_hi:
			if writable(c.x, c.y) and g.is_solid(c.x, c.y):
				g.put(c.x, c.y, Cell.CRACKED)
				no_feature[c] = true
			continue
		var rr := 1.5 + 0.5 * sin(phase + t * 9.0)
		for yy in range(int(floor(p.y - rr * 1.15)), int(ceil(p.y + rr * 1.15)) + 1):
			for xx in range(int(floor(p.x - rr)), int(ceil(p.x + rr)) + 1):
				var dx := (xx + 0.5 - p.x) / rr
				var dy := (yy + 0.5 - p.y) / (rr * 1.15)
				if dx * dx + dy * dy <= 1.0 and writable(xx, yy):
					g.put(xx, yy, Cell.AIR)
					no_feature[Vector2i(xx, yy)] = true


func _link_tunnels() -> void:
	var spawn: Vector2i = data["spawn"]
	var hall: Rect2i = data["arrival"]
	var plugs := 0
	# chain: arrival -> vaults by depth -> gate hall
	var prev := Vector2(spawn.x, spawn.y - 0.5)
	var prev_exit_left := Vector2(hall.position.x - 1.5, hall.end.y - 1.5)
	var prev_exit_right := Vector2(hall.end.x + 1.5, hall.end.y - 1.5)
	# the thermal plant joins the chain at its depth; it is a dead end with one
	# door, so the chain enters and leaves through that door
	var chain: Array = vaults.duplicate()
	var plant: Dictionary = data["plant"]
	var pr: Rect2i = plant["hall"]
	var pin := 0
	while pin < chain.size() and (chain[pin]["rect"] as Rect2i).position.y < pr.position.y:
		pin += 1
	chain.insert(pin, {"rect": pr, "plant": true})
	var pdoor: Vector2i = plant["door"]
	var plant_port := Vector2(pdoor.x + (1.5 if plant["door_right"] else -0.5), pdoor.y - 0.5)
	for i in chain.size():
		var r: Rect2i = chain[i]["rect"]
		var is_plant: bool = chain[i].get("plant", false)
		var to := plant_port if is_plant else _vault_port(r, int(prev.x))
		var from := prev
		if i == 0:
			from = prev_exit_left if to.x < spawn.x else prev_exit_right
		var plug := i > 0 and not is_plant and topo.randf() < Balance.DEEP_PLUG_CHANCE
		_passage(from, to, plug)
		if plug:
			plugs += 1
		if is_plant:
			prev = to
			continue
		# leave each vault by its far side, so the chain crosses the hall
		prev = Vector2(r.position.x + 1.5 if to.x > r.get_center().x else r.end.x - 1.5, r.end.y - 1.5)
	var doors: Array = data["gate_doors"]
	var door: Vector2i = doors[0] if absf(prev.x - doors[0].x) < absf(prev.x - doors[1].x) else doors[1]
	var door_side := -1.0 if door == doors[0] else 1.0
	_passage(prev, Vector2(door.x + door_side * 1.5 + 0.5, door.y - 0.5), false)
	# the other gate door gets a short stub so both sides read as entrances
	var other: Vector2i = doors[1] if door == doors[0] else doors[0]
	_passage(Vector2(other.x - door_side * 1.5 + 0.5, other.y - 0.5), Vector2(other.x - door_side * 9.0, other.y - 3.0), false)
	# a few cross links between vaults make loops
	for k in mini(3, vaults.size() - 2):
		var a: Rect2i = vaults[topo.randi_range(0, vaults.size() - 1)]["rect"]
		var b: Rect2i = vaults[topo.randi_range(0, vaults.size() - 1)]["rect"]
		if a == b:
			continue
		_passage(_vault_port(a, b.get_center().x), _vault_port(b, a.get_center().x), topo.randf() < Balance.DEEP_PLUG_CHANCE)
	data["plugs"] = plugs


# --- 8 transit tunnels ---------------------------------------------------------
## Dead-straight transport tunnels in the lower level, floored with composite.
func _transit_tunnels() -> void:
	var made := 0
	var runs: Array = []
	for k in 2:
		var y := topo.randi_range(Balance.DEEP_BAND_TRANSIT + 3, H - 22)
		var x0 := topo.randi_range(6, W / 2 - 20)
		var x1 := topo.randi_range(W / 2 + 20, W - 7)
		var run_start := -1
		for x in range(x0, x1 + 1):
			var skip := x == x1 or space.kind_at(Vector2i(x, y)) != "" or space.kind_at(Vector2i(x, y - 2)) != "" or space.kind_at(Vector2i(x, y + 1)) != ""
			if skip:
				if run_start >= 0 and x - run_start >= 6:
					runs.append({"y": y, "x0": run_start, "x1": x})
				run_start = -1
				continue
			if run_start < 0:
				run_start = x
			for dy in range(-2, 1):
				_air(x, y + dy)
				no_feature[Vector2i(x, y + dy)] = true
			if writable(x, y + 1):
				g.put(x, y + 1, Cell.ALLOY if x % 6 < 4 else Cell.HARD)
		made += 1
	data["transit_tunnels"] = made
	data["transit_runs"] = runs


# --- 9 ore ---------------------------------------------------------------------
func _ore_ok(x: int, y: int) -> bool:
	var m := g.get_mat(x, y)
	return (m == Cell.SOFT or m == Cell.HARD) and not no_feature.has(Vector2i(x, y)) and not g.has_flag(x, y, Cell.F_PROTECTED)


func _near_open(x: int, y: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if not g.is_solid(x + dx, y + dy):
				return true
	return false


func _ore() -> void:
	var placed := 0
	var tries := 0
	while placed < Balance.DEEP_ORE_VEINS and tries < 4000:
		tries += 1
		var x := ore_rng.randi_range(4, W - 5)
		var y := ore_rng.randi_range(8, H - 8)
		if not _ore_ok(x, y):
			continue
		if ore_rng.randf() < 0.7 and not _near_open(x, y, 3):
			continue
		# premium ore, richer the deeper you go
		var kind := Cell.ORE_AETHER if ore_rng.randf() < 0.3 + 0.35 * float(y) / H else Cell.ORE_COBALT
		var cx := x
		var cy := y
		for k in ore_rng.randi_range(2, 5):
			if _ore_ok(cx, cy):
				g.ore[g.idx(cx, cy)] = kind
			var d: Vector2i = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][ore_rng.randi_range(0, 3)]
			cx += d.x
			cy += d.y
		placed += 1
	data["ore_veins"] = placed


# --- 10 water ------------------------------------------------------------------
func _rock_box(r: Rect2i) -> bool:
	if not space.fits(r, 1):
		return false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var m := g.get_mat(x, y)
			if not (m == Cell.SOFT or m == Cell.HARD) or no_feature.has(Vector2i(x, y)):
				return false
	return true


func _water() -> void:
	# sealed groundwater pockets in solid rock
	var want := water_rng.randi_range(Balance.DEEP_WATER_POCKETS[0], Balance.DEEP_WATER_POCKETS[1])
	var made := 0
	var tries := 0
	while made < want and tries < 600:
		tries += 1
		var w := water_rng.randi_range(5, 9)
		var h := water_rng.randi_range(3, 5)
		var x0 := water_rng.randi_range(5, W - w - 6)
		var y0 := water_rng.randi_range(22, H - h - 12)
		var shell := Rect2i(x0, y0, w + 2, h + 2)
		if not _rock_box(shell):
			continue
		space.claim(shell, "water", "pocket%d" % made)
		var inner := Rect2i(x0 + 1, y0 + 1, w, h)
		var cells := 0
		for y in range(inner.position.y, inner.end.y):
			for x in range(inner.position.x, inner.end.x):
				g.put(x, y, Cell.AIR)
				g.water[g.idx(x, y)] = Balance.WATER_MAX
				cells += 1
		_mark_no_feature(shell)
		data["water_features"].append({"kind": "pocket", "rect": inner, "cells": cells, "volume": cells * Balance.WATER_MAX})
		made += 1
	# cooling basins sunk into the floor of plant-level vaults
	for v in vaults:
		if int(v["band"]) != 1 or water_rng.randf() > 0.75:
			continue
		var r: Rect2i = v["rect"]
		var bw := mini(r.size.x - 10, water_rng.randi_range(8, 14))
		var bx := r.position.x + (r.size.x - bw) / 2
		var basin := Rect2i(bx, r.end.y, bw, 2)
		var ok := true
		for y in range(basin.position.y, basin.end.y + 1):
			for x in range(basin.position.x - 1, basin.end.x + 1):
				if not g.is_solid(x, y) or not writable(x, y):
					ok = false
		if not ok:
			continue
		var cells2: Array = []
		for y in range(basin.position.y, basin.end.y):
			for x in range(basin.position.x, basin.end.x):
				g.put(x, y, Cell.AIR)
				g.water[g.idx(x, y)] = Balance.WATER_MAX
				cells2.append(Vector2i(x, y))
		# line the basin so nothing drains it before the player does
		for y in range(basin.position.y, basin.end.y + 1):
			for x in [basin.position.x - 1, basin.end.x]:
				g.put(x, y, Cell.HARD)
				no_feature[Vector2i(x, y)] = true
		for x in range(basin.position.x, basin.end.x):
			g.put(x, basin.end.y, Cell.HARD)
			no_feature[Vector2i(x, basin.end.y)] = true
		v["basin"] = cells2
		data["water_features"].append({"kind": "cooling_basin", "rect": basin, "cells": cells2.size(), "volume": cells2.size() * Balance.WATER_MAX})
	var sim := WaterSim.new(g)
	data["settle_steps"] = sim.settle(300)
	g.cell_changed.disconnect(sim._on_cell_changed)
	data["water_total"] = sim.total()


# --- 10b lava ------------------------------------------------------------------
func _dry_rock_box(r: Rect2i) -> bool:
	if not _rock_box(r):
		return false
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			if g.get_water(x, y) > 0:
				return false
	return true


func _fill_lava(inner: Rect2i, kind: String) -> int:
	var cells := 0
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			g.put(x, y, Cell.AIR)
			g.lava[g.idx(x, y)] = Balance.LAVA_MAX
			no_feature[Vector2i(x, y)] = true
			cells += 1
	data["lava_features"].append({"kind": kind, "rect": inner, "cells": cells, "volume": cells * Balance.LAVA_MAX})
	return cells


func _lava() -> void:
	# 1) shallow pits in the floors of plant and transit vaults: visible, glowing,
	#    one cell deep so a careless step burns but is never a trap
	for v in vaults:
		if int(v["band"]) == 0 or not (v["basin"] as Array).is_empty() or water_rng.randf() > Balance.DEEP_LAVA_PITS:
			continue
		var r: Rect2i = v["rect"]
		var pw := mini(r.size.x - 12, water_rng.randi_range(3, 7))
		if pw < 3:
			continue
		var px := r.position.x + water_rng.randi_range(5, r.size.x - pw - 5)
		var pit := Rect2i(px, r.end.y, pw, 1)
		var ok := true
		for y in range(pit.position.y, pit.end.y + 1):
			for x in range(pit.position.x - 1, pit.end.x + 1):
				if not g.is_solid(x, y) or not writable(x, y) or g.get_water(x, y) > 0 or g.get_water(x, y - 1) > 0:
					ok = false
		if not ok:
			continue
		_fill_lava(pit, "lava_pit")
		for x in range(pit.position.x - 1, pit.end.x + 1):
			g.put(x, pit.end.y, Cell.HARD)
			no_feature[Vector2i(x, pit.end.y)] = true
		data["landmarks"].append({"kind": "lava_pit", "rect": pit})
	# 2) quench pairs: water sealed directly above lava, a thin rock divider
	#    between. Drill the divider and the water pours down into a crust bridge.
	var want_pairs := water_rng.randi_range(Balance.DEEP_QUENCH_PAIRS[0], Balance.DEEP_QUENCH_PAIRS[1])
	var pairs := 0
	var tries := 0
	while pairs < want_pairs and tries < 500:
		tries += 1
		var w := water_rng.randi_range(5, 8)
		var x0 := water_rng.randi_range(6, W - w - 7)
		var y0 := water_rng.randi_range(Balance.DEEP_BAND_PLANT, H - 18)
		var whole := Rect2i(x0 - 1, y0 - 1, w + 2, 9)     # water 3, divider 2, lava 2, shells
		if not _dry_rock_box(whole):
			continue
		space.claim(whole, "water", "quench%d" % pairs)
		_mark_no_feature(whole)
		var wet := Rect2i(x0, y0, w, 3)
		var cells := 0
		for y in range(wet.position.y, wet.end.y):
			for x in range(wet.position.x, wet.end.x):
				g.put(x, y, Cell.AIR)
				g.water[g.idx(x, y)] = Balance.WATER_MAX
				cells += 1
		data["water_features"].append({"kind": "quench_cistern", "rect": wet, "cells": cells, "volume": cells * Balance.WATER_MAX})
		for x in range(x0, x0 + w):
			g.put(x, y0 + 3, Cell.CRACKED)                   # the divider tells you where to drill
			g.put(x, y0 + 4, Cell.SOFT)
		_fill_lava(Rect2i(x0, y0 + 5, w, 2), "quench_lava")
		data["landmarks"].append({"kind": "quench_pair", "rect": whole})
		pairs += 1
	data["quench_pairs"] = pairs
	# 2b) sluices: lava sealed ABOVE a water pool. Drill the divider and watch
	#     the lava pour down into the water, crust, sink and boil it away.
	var want_sl := water_rng.randi_range(Balance.DEEP_SLUICE_PAIRS[0], Balance.DEEP_SLUICE_PAIRS[1])
	var sluices := 0
	tries = 0
	while sluices < want_sl and tries < 500:
		tries += 1
		var sw := water_rng.randi_range(5, 8)
		var sx := water_rng.randi_range(6, W - sw - 7)
		var sy := water_rng.randi_range(Balance.DEEP_BAND_PLANT, H - 20)
		var box := Rect2i(sx - 1, sy - 1, sw + 2, 11)      # lava 2, divider 2, water 5, shells
		if not _dry_rock_box(box):
			continue
		space.claim(box, "water", "sluice%d" % sluices)
		_mark_no_feature(box)
		_fill_lava(Rect2i(sx, sy, sw, 2), "sluice_lava")
		for x in range(sx, sx + sw):
			g.put(x, sy + 2, Cell.SOFT)
			g.put(x, sy + 3, Cell.CRACKED)                 # drill here, from the pool side or below
		var pool := Rect2i(sx, sy + 4, sw, 5)
		var pcells := 0
		for y in range(pool.position.y, pool.end.y):
			for x in range(pool.position.x, pool.end.x):
				g.put(x, y, Cell.AIR)
				g.water[g.idx(x, y)] = Balance.WATER_MAX
				pcells += 1
		data["water_features"].append({"kind": "sluice_pool", "rect": pool, "cells": pcells, "volume": pcells * Balance.WATER_MAX})
		data["landmarks"].append({"kind": "sluice", "rect": box})
		sluices += 1
	data["sluices"] = sluices
	# 3) sealed lava pockets deeper in the rock
	var want := water_rng.randi_range(Balance.DEEP_LAVA_POCKETS[0], Balance.DEEP_LAVA_POCKETS[1])
	var made := 0
	tries = 0
	while made < want and tries < 600:
		tries += 1
		var pw2 := water_rng.randi_range(4, 9)
		var ph := water_rng.randi_range(2, 4)
		var x1 := water_rng.randi_range(5, W - pw2 - 6)
		var y1 := water_rng.randi_range(Balance.DEEP_BAND_PLANT, H - ph - 10)
		var shell := Rect2i(x1, y1, pw2 + 2, ph + 2)
		if not _dry_rock_box(shell):
			continue
		space.claim(shell, "water", "lava%d" % made)
		_mark_no_feature(shell)
		_fill_lava(Rect2i(x1 + 1, y1 + 1, pw2, ph), "lava_pocket")
		made += 1
	data["lava_pockets"] = made
	var ls := LavaSim.new(g)
	data["lava_settle_steps"] = ls.settle(300)
	g.cell_changed.disconnect(ls._on_cell_changed)
	data["lava_total"] = ls.total()
	# lava never enters the halls that hold the way in and the way out
	var keep: Array = []
	# the coolant basin must never hold lava, or the engine could never cool
	for c in data["plant"]["coolant_basin"]:
		keep.append(c)
	for key in ["arrival", "gate_hall"]:
		var hall: Rect2i = data[key]
		for y in range(hall.position.y, hall.end.y):
			for x in range(hall.position.x - 1, hall.end.x + 1):
				keep.append(Vector2i(x, y))
	data["lava_keep_out"] = keep


# --- 11 basalt -----------------------------------------------------------------
func _stabilize_basalt() -> void:
	var fixed := 0
	for y in range(2, H - 4):
		for x in range(2, W - 2):
			if g.get_mat(x, y) == Cell.HARD and not g.is_solid(x, y + 1):
				for c in Boulders.unsupported_mass(g, Vector2i(x, y)):
					g.put(c.x, c.y, Cell.SOFT, g.get_ore(c.x, c.y))
					fixed += 1
	data["basalt_stabilized"] = fixed


# --- 12 guardians and records --------------------------------------------------
func _stand_ok(x: int, y: int) -> bool:
	if x < 4 or x >= W - 4 or y < 6 or y >= H - 6:
		return false
	var c := Vector2i(x, y)
	if g.is_solid(x, y) or g.is_solid(x, y - 1) or not g.is_solid(x, y + 1) or reserved.has(c):
		return false
	if g.get_mat(x, y) != Cell.AIR or g.get_water(x, y) > 0 or g.get_water(x, y - 1) > 0:
		return false
	var sp: Vector2i = data["spawn"]
	return absi(x - sp.x) + absi(y - sp.y) >= 30


func _guardians_and_records() -> void:
	var crawlers := 0
	var tries := 0
	while crawlers < Balance.DEEP_CRAWLERS and tries < 3000:
		tries += 1
		var x := enc_rng.randi_range(4, W - 5)
		var y := enc_rng.randi_range(18, H - 8)
		if _stand_ok(x, y):
			data["entities"].append({"type": "crawler", "cell": Vector2i(x, y), "role": "wander"})
			crawlers += 1
	# a ceiling sentry watches some of the great vaults
	var sentries := 0
	_assign_themes()
	for i in vaults.size():
		var r: Rect2i = vaults[i]["rect"]
		var fy := r.end.y - 1
		data["entities"].append({"type": "lamp", "cell": Vector2i(r.position.x + 2, r.position.y), "color": "6ff3d0"})
		data["entities"].append({"type": "lamp", "cell": Vector2i(r.end.x - 3, r.position.y), "color": "6ff3d0"})
		var sign_x := r.position.x + 3
		if not g.is_solid(sign_x, fy) and g.is_solid(sign_x, fy + 1):
			data["entities"].append({"type": "sign", "cell": Vector2i(sign_x, fy), "text": vaults[i]["name"]})
		var sx := r.position.x + r.size.x / 2
		if sentries < Balance.DEEP_SENTRIES and i > 0 and enc_rng.randf() < 0.6 \
				and g.get_mat(sx, r.position.y - 1) == Cell.ALLOY and not g.is_solid(sx, r.position.y) \
				and g.get_mat(sx + 3, r.position.y - 1) == Cell.ALLOY and not g.is_solid(sx + 3, r.position.y):
			data["entities"].append({"type": "sentry", "cell": Vector2i(sx, r.position.y), "ceiling": true, "module": Vector2i(sx + 3, r.position.y)})
			sentries += 1
	data["crawlers"] = crawlers
	data["sentries"] = sentries


# --- 14 validation -------------------------------------------------------------
## One-way fairness: every cell you can get into must still be able to reach
## the gate, and arrival -> gate must fit the dig budget with starting gear.
func _audit() -> bool:
	var dc: DigCheck
	var from_spawn: PackedFloat32Array
	var clean := false
	for round in 3:
		dc = DigCheck.new(g)
		dc.allow_ladder = true
		from_spawn = dc.costs_from(data["spawn"])
		var escape := dc.escape_set(data["gate"])
		var sealed_n := _seal_traps(from_spawn, escape)
		if sealed_n == 0:
			clean = true
			break
		if sealed_n < 0:
			break
		data["traps_sealed"] = int(data.get("traps_sealed", 0)) + sealed_n
	if not clean:
		return false
	data["dig_to_gate_s"] = GenMetrics._near(dc, from_spawn, data["gate"])
	_place_first_light(from_spawn, dc.escape_set(data["gate"]))
	return data["dig_to_gate_s"] >= 0.0 and data["dig_to_gate_s"] <= Balance.DEEP_DIG_BUDGET


## The First Light: the zone's unique find, on a dry, safe standing cell in
## the lower transit level that you can reach and still get to the gate from.
## Deterministic from the seed; never edits terrain.
func _place_first_light(from_spawn: PackedFloat32Array, escape: PackedByteArray) -> void:
	var best := Vector2i(-1, -1)
	var best_score := -1
	var occupied: Dictionary = {}
	for e in data["entities"]:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				occupied[e["cell"] + Vector2i(dx, dy)] = true
	for y in range(Balance.DEEP_BAND_TRANSIT, H - 5):
		for x in range(4, W - 4):
			var i := y * W + x
			if from_spawn[i] >= DigCheck.UNREACHED or escape[i] == 0:
				continue
			if g.get_mat(x, y) != Cell.AIR or g.get_mat(x, y - 1) != Cell.AIR or not g.is_solid(x, y + 1):
				continue
			var c := Vector2i(x, y)
			if reserved.has(c) or occupied.has(c) or g.water[i] > 0 or g.lava[i] > 0 or g.lava[i + W] > 0:
				continue
			var score: int = hash("%d:first-light:%d" % [data["seed"], i]) & 0x7fffffff
			if score > best_score:
				best_score = score
				best = c
	data["finds"] = [] if best.x < 0 else [{"id": Balance.Z_FIRST, "cell": best}]


func _seal_traps(from_spawn: PackedFloat32Array, escape: PackedByteArray) -> int:
	var n := 0
	var filled: Dictionary = {}
	for i in W * H:
		if from_spawn[i] >= DigCheck.UNREACHED or escape[i] == 1:
			continue
		var c := Vector2i(i % W, i / W)
		if reserved.has(c) or g.has_flag(c.x, c.y, Cell.F_PROTECTED):
			return -1
		g.put(c.x, c.y, Cell.ALLOY)
		g.water[i] = 0
		filled[c] = true
		n += 1
	if n > 0:
		# sealing feet can leave the air above them enclosed: fill that too
		for c in RouteCheck.sealed_pockets(g, data["spawn"]):
			if _in_container(c):
				continue      # the plant's tanks are sealed on purpose
			if reserved.has(c) or g.has_flag(c.x, c.y, Cell.F_PROTECTED):
				return -1
			g.put(c.x, c.y, Cell.ALLOY)
			g.water[g.idx(c.x, c.y)] = 0
			filled[c] = true
			n += 1
		for e in data["entities"].duplicate():
			if filled.has(e["cell"]) or filled.has(e.get("module", Vector2i(-1, -1))):
				data["entities"].erase(e)
	return n


func _in_container(c: Vector2i) -> bool:
	var p: Dictionary = data.get("plant", {})
	for key in ["heat_tank", "coolant_tank"]:
		if p.has(key) and (p[key] as Rect2i).has_point(c):
			return true
	return false


func _validate() -> void:
	for attempt in (0 if no_repair else 2):
		if _audit():
			data["valid"] = true
			return
		repairs += 1
		# repair: a plain dug line from the arrival hall to a gate door
		var sp: Vector2i = data["spawn"]
		var door: Vector2i = data["gate_doors"][0]
		_passage(Vector2(sp.x + 0.5, sp.y - 0.5), Vector2(door.x - 1.0, door.y - 0.5), false)
		for i in g.mat.size():
			g.hp[i] = Cell.max_hp(g.mat[i])
	data["valid"] = _audit()


# --- 15 furnishing -------------------------------------------------------------
const THEME_PREF := [
	["FIRST HALL", "STILL HALL", "ARCHIVE", "CONDUIT", "HEAT WORKS", "DEEP ROAD"],
	["HEAT WORKS", "CONDUIT", "STILL HALL", "ARCHIVE", "FIRST HALL", "DEEP ROAD"],
	["DEEP ROAD", "ARCHIVE", "CONDUIT", "STILL HALL", "HEAT WORKS", "FIRST HALL"],
]


## Each vault gets a theme that decides its name and what stands in it. The
## shallowest vault, nearest the arrival, is always the FIRST HALL; the rest
## prefer themes that suit their depth. Repeats get a numeral.
func _assign_themes() -> void:
	var used: Dictionary = {}
	for i in vaults.size():
		var theme := "FIRST HALL"
		if i > 0:
			var pref: Array = THEME_PREF[int(vaults[i]["band"])]
			var free: Array = []
			for n in pref:
				if not used.has(n):
					free.append(n)
			if free.is_empty():
				free = pref.duplicate()
			theme = free[deco_rng.randi_range(0, mini(1, free.size() - 1))]
		used[theme] = int(used.get(theme, 0)) + 1
		vaults[i]["theme"] = theme
		vaults[i]["name"] = theme if used[theme] == 1 else "%s %s" % [theme, ["", "I", "II", "III", "IV"][mini(used[theme], 4)]]
		for lm in data["landmarks"]:
			if lm["kind"] == "great_vault" and lm["rect"] == vaults[i]["rect"]:
				lm["name"] = vaults[i]["name"]


func _decor(kind: String, cell: Vector2i, ww: int, hh: int, flip: bool = false, variant: int = 0) -> void:
	data["entities"].append({"type": "decor", "kind": kind, "cell": cell, "w": ww, "h": hh, "flip": flip, "variant": variant})


## Floor columns of a vault where a piece may stand: open and dry at floor
## level with headroom, on solid ground, not already used.
func _floor_ok(x: int, fy: int, taken: Dictionary) -> bool:
	if taken.has(x) or g.is_solid(x, fy) or g.is_solid(x, fy - 1) or not g.is_solid(x, fy + 1):
		return false
	var i := fy * W + x
	return g.water[i] < 8 and g.lava[i] == 0 and g.lava[i + W] == 0 and g.water[i - W] < 8


func _place_ground(r: Rect2i, taken: Dictionary, kind: String, ww: int, hh: int, count: int, gap: int, variant_fn: Callable = Callable()) -> Array:
	var fy := r.end.y - 1
	var xs: Array = []
	for x in range(r.position.x + 1, r.end.x - ww):
		xs.append(x)
	# deterministic shuffle on this system's own stream
	for k in range(xs.size() - 1, 0, -1):
		var j := deco_rng.randi_range(0, k)
		var tmp: int = xs[k]
		xs[k] = xs[j]
		xs[j] = tmp
	var placed: Array = []
	for x: int in xs:
		if placed.size() >= count:
			break
		# the floor is not flat everywhere (tunnels and pits cut it): try the
		# vault floor first, then a few rows lower or higher
		var base := -1
		for y in [fy, fy + 1, fy + 2, fy + 3, fy - 1, fy + 4, fy - 2]:
			var ok := true
			for xx in range(x, x + ww):
				if not _floor_ok(xx, y, taken):
					ok = false
					break
			if ok:
				base = y
				break
		if base < 0:
			continue
		for xx in range(x - gap, x + ww + gap):
			taken[xx] = true
		var variant := 0 if not variant_fn.is_valid() else int(variant_fn.call(placed.size()))
		_decor(kind, Vector2i(x, base), ww, hh + (base - fy if kind == "furnace" else 0), deco_rng.randf() < 0.5, variant)
		placed.append(Vector2i(x, base))
	return placed


func _furnish() -> void:
	var furnished := 0
	var per_vault: Array = []
	for v in vaults:
		var before := furnished
		var r: Rect2i = v["rect"]
		var fy := r.end.y - 1
		var taken: Dictionary = {}
		# keep entities' footing clear (signs, crates, guardians, the cache spot)
		for e in data["entities"]:
			var c: Vector2i = e["cell"]
			if c.y >= r.position.y and c.y <= fy + 1 and c.x >= r.position.x - 1 and c.x <= r.end.x:
				for dx in range(-1, 2):
					taken[c.x + dx] = true
		var head := r.size.y          # rows from the floor up to the ceiling band
		match String(v["theme"]):
			"FIRST HALL":
				var hh := clampi(head - 2, 6, 10)
				var n := _place_ground(r, taken, "colossus", 5, hh, 3, 2, func(k: int) -> int: return 1 if k == 1 else 0).size()
				if n >= 2:
					_place_ground(r, taken, "fallen_head", 3, 2, 1, 1)
				furnished += n
			"HEAT WORKS":
				furnished += _place_ground(r, taken, "furnace", 4, head, 3, 2).size()
				_decor("pipes", Vector2i(r.position.x, r.position.y + 1), r.size.x, 1, false, 1)
			"CONDUIT":
				for frac in [0.38, 0.66]:
					var row := fy - int(head * frac)
					if row > r.position.y:
						_decor("conduit", Vector2i(r.position.x, row), r.size.x, 1)
				furnished += 2 + _place_ground(r, taken, "junction", 2, 3, 3, 3).size()
			"STILL HALL":
				furnished += _place_ground(r, taken, "husk", 4, 5, 4, 2).size()
			"DEEP ROAD":
				furnished += _rails(r.position.x, r.end.x, fy)
				furnished += _place_ground(r, taken, "railcar", 5, 3, 2, 3, func(k: int) -> int: return k % 2).size()
				for sx in [r.position.x + 1, r.end.x - 2]:
					if _floor_ok(sx, fy, {}):
						_decor("signal", Vector2i(sx, fy), 1, 4, false, 0)
			"ARCHIVE":
				var hh2 := clampi(head - 3, 5, 8)
				furnished += _place_ground(r, taken, "shelves", 3, hh2, 5, 1).size()
				var cache_done := false
				for x in range(r.position.x + 2, r.end.x - 2):
					for y in [fy, fy + 1, fy + 2, fy - 1]:
						if not cache_done and _floor_ok(x, y, taken):
							data["entities"].append({"type": "cache", "cell": Vector2i(x, y), "charges": 1, "repair": 30})
							taken[x] = true
							cache_done = true
					if cache_done:
						break
		per_vault.append(furnished - before)
	# the arrival hall: the cage that brought you down, and its snapped cables
	var hall: Rect2i = data["arrival"]
	var sp: Vector2i = data["spawn"]
	_decor("lift_wreck", Vector2i(sp.x + 6, hall.end.y - 1), 6, 4, false)
	_decor("cables", Vector2i(sp.x - 1, hall.position.y + 2), 3, hall.position.y)
	# the transit tunnels: rails, abandoned cars and signals
	for run in data.get("transit_runs", []):
		var y: int = run["y"]
		furnished += _rails(int(run["x0"]), int(run["x1"]), y)
		var x := int(run["x0"]) + deco_rng.randi_range(4, 14)
		while x < int(run["x1"]) - 6:
			if deco_rng.randf() < 0.5:
				var ok := true
				for xx in range(x, x + 5):
					if not _floor_ok(xx, y, {}):
						ok = false
				if ok:
					_decor("railcar", Vector2i(x, y), 5, 3, deco_rng.randf() < 0.5, 1 if deco_rng.randf() < 0.3 else 0)
					furnished += 1
			elif _floor_ok(x, y, {}):
				_decor("signal", Vector2i(x, y), 1, 3, false, 1 if deco_rng.randf() < 0.5 else 0)
			x += deco_rng.randi_range(16, 28)
	# the gate hall: two pylons flank the gate and light up with power
	var gate: Vector2i = data["gate"]
	for dx in [-7, 6]:
		_decor("pylon", Vector2i(gate.x + dx, gate.y), 2, 6, false)
	data["furnished"] = furnished
	data["vault_decor"] = per_vault


## Lay rail along every stretch of open, dry floor on this row.
func _rails(x0: int, x1: int, fy: int) -> int:
	var made := 0
	var start := -1
	for x in range(x0, x1 + 1):
		var ok := x < x1 and _floor_ok(x, fy, {})
		if ok and start < 0:
			start = x
		elif not ok and start >= 0:
			if x - start >= 4:
				_decor("rail", Vector2i(start, fy), x - start, 1)
				made += 1
			start = -1
	return made
