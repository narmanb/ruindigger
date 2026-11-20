class_name DockGenerator
extends RefCounted
## Mission map "The Dry Dock": an old Dustworks dockyard. A bedrock pit cuts
## the dock hall's floor in two, with the lift on the far rim. Sealed sand
## hoppers sit above the hall; a service tunnel runs right under them, and
## each hopper has a sediment plug in the tunnel's ceiling. Open a plug and
## the hopper pours down its chute, through a grate in the tunnel floor, into
## the pit. Fill the pit and the lift powers up, and the sand is your bridge
## across. Built from a fixed seed with no simulation, so it is the same map
## every time. Same data contract as the other generators.
##
## Shape (W x H cells):
##   top-left  arrival room with the lift you came down in; a ladder shaft
##             down to the service tunnel
##   galleries Dustworks caves, ore, crawlers, little sand drifts, and a sealed
##             sand pocket over the tunnel that buries it if you dig into it
##   hoppers   three sealed bins of sand (protected basalt walls) over the pit;
##             plugs in the tunnel ceiling, chutes down through the hall roof
##   tunnel    runs under the hoppers; grates (one-way platforms) over the
##             chutes let the sand through, and a ladder drops into the hall
##   hall      the dock: west rim (you arrive), the pit, east rim (the lift)
##
## PASS ORDER: 1 base rock and rim  2 gallery caves  3 hall and pit
## 4 hoppers, plugs and chutes  5 service tunnel and the drop into the hall
## 6 arrival room and shaft  7 sand pocket over the tunnel  8 drifts
## 9 ore  10 basalt stabilisation  11 crawlers and lamps  12 hit points
## 13 measure the pit and check the way to the lift.

const W := 96
const H := 68
const GAL_Y0 := 10            # first row of the gallery caves
const HOP_Y0 := 19            # hopper block: top wall row
const PLUG_Y := 30            # hopper bottoms: plugs in this row
const TUN_Y0 := 31            # service tunnel rows TUN_Y0 .. TUN_Y0 + 1
const ROOF_Y0 := 33           # hall roof rows ROOF_Y0 .. HALL_Y0 - 1 (the grate row is ROOF_Y0)
const HALL_Y0 := 38           # hall air rows HALL_Y0 .. RIM_Y - 1
const RIM_Y := 52             # the rims' floor row (you walk in row RIM_Y - 1)
const HALL_X0 := 14
const HALL_X1 := 81
const PIT_X0 := 40            # pit interior columns PIT_X0 .. PIT_X1
const PIT_X1 := 55
const PIT_Y1 := 57            # pit interior rows RIM_Y .. PIT_Y1; bedrock under
const TUN_X0 := 15
const TUN_X1 := 60
const DROP_X := 22            # the ladder from the tunnel down to the west rim
## Hoppers: interior columns [x0, x1], rows HOP_Y0 + 1 .. PLUG_Y - 1, plug
## columns [p0, p1]. Walls are shared between neighbours.
const HOPPERS := [[40, 43, 41, 42], [45, 50, 47, 48], [52, 55, 53, 54]]

var g: TerrainGrid
var data: Dictionary
var rng := RandomNumberGenerator.new()
var keep: Dictionary = {}     # cells later passes must leave alone


func generate(mission: Dictionary) -> Dictionary:
	var seed_value := int(mission.get("seed", 1))
	rng.seed = seed_value
	seed(seed_value)
	g = TerrainGrid.new(W, H)
	data = {"seed": seed_value, "stage": "mission", "mission": String(mission.get("id", "")), "entities": [], "grid": g,
		"route": [], "version": 1, "landmarks": [], "water_features": [], "water_props": [], "finds": [], "run_relics": []}
	data["zones"] = [{"id": 0, "name": String(mission.get("name", "MISSION")), "rect": Rect2i(2, 2, W - 4, H - 5), "color": Balance.ZONE_COLORS[0]}]
	_base(seed_value)
	_caves(seed_value)
	_hall()
	_hoppers()
	_tunnel()
	_arrival()
	_pocket()
	_drifts()
	_ore()
	_stabilize()
	_crawlers(int(mission.get("crawlers", 4)))
	_lamps()
	for i in g.mat.size():
		g.hp[i] = Cell.max_hp(g.mat[i])
	_measure(float(mission.get("target", 1.0)), float(mission.get("full", Balance.MISSION_FULL)))
	randomize()
	return data


func _rim(x: int, y: int) -> bool:
	return x < 2 or x >= W - 2 or y < 2 or y >= H - 3


func _bedrock(x: int, y: int) -> void:
	g.put(x, y, Cell.BEDROCK)
	g.set_flag(x, y, Cell.F_PROTECTED)
	keep[Vector2i(x, y)] = true


## Basalt nothing can break (the hopper bins).
func _wall(x: int, y: int) -> void:
	g.put(x, y, Cell.HARD)
	g.set_flag(x, y, Cell.F_PROTECTED)
	keep[Vector2i(x, y)] = true


func _air(x: int, y: int, flags: int = 0) -> void:
	g.set_flag(x, y, Cell.F_PROTECTED, false)
	g.put(x, y, Cell.AIR)
	if flags != 0:
		g.set_flag(x, y, flags)
	keep[Vector2i(x, y)] = true


func _free(x: int, y: int) -> bool:
	return g.in_bounds(x, y) and not _rim(x, y) and not keep.has(Vector2i(x, y)) and g.get_mat(x, y) != Cell.BEDROCK


# --- 1 base ------------------------------------------------------------------
func _base(seed_value: int) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.08
	n.fractal_octaves = 3
	for y in H:
		for x in W:
			g.stratum[g.idx(x, y)] = 0
			if _rim(x, y):
				_bedrock(x, y)
			else:
				g.put(x, y, Cell.HARD if n.get_noise_2d(x, y) > 0.32 else Cell.SOFT)


# --- 2 gallery caves ---------------------------------------------------------
## Long, low galleries above and beside the dock. The hall, hoppers and tunnel
## are stamped over them afterwards.
func _caves(seed_value: int) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_value + 41
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_octaves = 2
	n.frequency = 0.055
	for y in range(GAL_Y0, HALL_Y0 + 6):
		for x in range(4, W - 4):
			if n.get_noise_2d(x * 0.6, y * 1.5) > 0.3:
				g.put(x, y, Cell.AIR)
	var copy := g.mat.duplicate()
	for y in range(GAL_Y0, HALL_Y0 + 6):
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


# --- 3 hall and pit ----------------------------------------------------------
func _hall() -> void:
	# solid sediment walls and floor around the hall, so the caves don't leak in
	for y in range(ROOF_Y0, PIT_Y1 + 4):
		for x in range(HALL_X0 - 2, HALL_X1 + 3):
			if not _rim(x, y):
				g.put(x, y, Cell.SOFT)
	for y in range(HALL_Y0, RIM_Y):
		for x in range(HALL_X0, HALL_X1 + 1):
			_air(x, y)
	# the pit: bedrock sides and floor, empty inside
	for y in range(RIM_Y, PIT_Y1 + 2):
		_bedrock(PIT_X0 - 1, y)
		_bedrock(PIT_X1 + 1, y)
	for x in range(PIT_X0 - 1, PIT_X1 + 2):
		_bedrock(x, PIT_Y1 + 1)
	for y in range(RIM_Y, PIT_Y1 + 1):
		for x in range(PIT_X0, PIT_X1 + 1):
			_air(x, y)
	# the lift on the east rim, dark until the pit is full
	var lift := Vector2i(70, RIM_Y - 1)
	data["entities"].append({"type": "lift", "id": "mission", "cell": lift, "locked": true})
	data["entities"].append({"type": "sign", "cell": Vector2i(PIT_X0 - 3, RIM_Y - 1), "text": "DRY DOCK"})
	data["mission_lift"] = lift
	data["bed"] = Rect2i(PIT_X0, RIM_Y, PIT_X1 - PIT_X0 + 1, PIT_Y1 - RIM_Y + 1)
	data["landmarks"].append({"kind": "dock_pit", "rect": data["bed"]})
	data["landmarks"].append({"kind": "dock_hall", "rect": Rect2i(HALL_X0, HALL_Y0, HALL_X1 - HALL_X0 + 1, RIM_Y - HALL_Y0)})


# --- 4 hoppers ---------------------------------------------------------------
func _hoppers() -> void:
	var bx0: int = int(HOPPERS[0][0]) - 1
	var bx1: int = int(HOPPERS[HOPPERS.size() - 1][1]) + 1
	for y in range(HOP_Y0, PLUG_Y + 1):
		for x in range(bx0, bx1 + 1):
			_wall(x, y)
	var sand := 0
	for h: Array in HOPPERS:
		for y in range(HOP_Y0 + 1, PLUG_Y):
			for x in range(int(h[0]), int(h[1]) + 1):
				_air(x, y)
				g.set_sand(x, y, Balance.SAND_MAX)
				sand += Balance.SAND_MAX
		for x in range(int(h[2]), int(h[3]) + 1):
			# the plug: plain sediment, the one way into the bin
			g.set_flag(x, PLUG_Y, Cell.F_PROTECTED, false)
			g.put(x, PLUG_Y, Cell.SOFT)
			# the chute: a grate in the tunnel floor, then straight down
			_air(x, ROOF_Y0)
			g.put(x, ROOF_Y0, Cell.PLATFORM)
			for y in range(ROOF_Y0 + 1, HALL_Y0):
				_air(x, y, Cell.F_NO_RUBBLE)
		data["landmarks"].append({"kind": "hopper", "rect": Rect2i(int(h[0]), HOP_Y0 + 1, int(h[1]) - int(h[0]) + 1, PLUG_Y - HOP_Y0 - 1),
			"plug": Vector2i(int(h[2]), PLUG_Y)})
	data["sand_hoppers"] = sand


# --- 5 service tunnel --------------------------------------------------------
func _tunnel() -> void:
	for y in range(TUN_Y0, TUN_Y0 + 2):
		for x in range(TUN_X0, TUN_X1 + 1):
			_air(x, y, Cell.F_NO_RUBBLE)
	# its floor holds (sediment) except at the grates
	for x in range(TUN_X0 - 1, TUN_X1 + 2):
		if g.get_mat(x, ROOF_Y0) != Cell.PLATFORM:
			g.set_flag(x, ROOF_Y0, Cell.F_PROTECTED, false)
			g.put(x, ROOF_Y0, Cell.SOFT)
			keep[Vector2i(x, ROOF_Y0)] = true
	# end caps, so the galleries meet it only from above
	for y in range(TUN_Y0 - 1, TUN_Y0 + 3):
		for x in [TUN_X0 - 1, TUN_X1 + 1]:
			if not keep.has(Vector2i(x, y)):
				g.put(x, y, Cell.SOFT)
	# the drop: a ladder from the tunnel floor down to the west rim
	for y in range(ROOF_Y0, RIM_Y):
		_air(DROP_X, y, Cell.F_NO_RUBBLE)
		g.put(DROP_X, y, Cell.LADDER)
		if y < HALL_Y0:
			_air(DROP_X + 1, y, Cell.F_NO_RUBBLE)
	data["entities"].append({"type": "sign", "cell": Vector2i(44, TUN_Y0 + 1), "text": "HOPPERS"})


# --- 6 arrival ---------------------------------------------------------------
func _arrival() -> void:
	var room := Rect2i(5, 4, 13, 4)              # interior
	for y in range(room.position.y - 1, room.end.y + 1):
		for x in range(room.position.x - 1, room.end.x + 1):
			var inside := room.has_point(Vector2i(x, y))
			g.put(x, y, Cell.AIR if inside else Cell.HARD)
			g.set_flag(x, y, Cell.F_NO_RUBBLE if inside else Cell.F_PROTECTED)
			keep[Vector2i(x, y)] = true
	var fy := room.end.y - 1
	# a ladder shaft from the room down to the tunnel's west end
	var sx := TUN_X0
	for y in range(room.end.y, TUN_Y0 + 2):
		for x in [sx, sx + 1]:
			_air(x, y, Cell.F_NO_RUBBLE)
		g.put(sx, y, Cell.LADDER)
	data["spawn"] = Vector2i(room.position.x + 3, fy)
	data["lift"] = Vector2i(room.position.x + 1, fy)
	data["entities"].append({"type": "lift", "id": "surface", "cell": data["lift"]})
	data["entities"].append({"type": "lamp", "cell": Vector2i(room.position.x + 6, room.position.y), "color": "ffb347"})
	data["entities"].append({"type": "crate", "cell": Vector2i(room.position.x + 6, fy)})
	data["entities"].append({"type": "sign", "cell": Vector2i(room.position.x + 8, fy), "text": "DOCK BELOW"})
	data["landmarks"].append({"kind": "arrival_room", "rect": room})


# --- 7 sand pocket -----------------------------------------------------------
## A sealed pocket of sand in the tunnel's ceiling near the drop. Dig up into
## it and it buries the tunnel (and pours down the ladder).
func _pocket() -> void:
	var r := Rect2i(25, TUN_Y0 - 5, 5, 3)
	for y in range(r.position.y - 1, r.end.y + 2):
		for x in range(r.position.x - 1, r.end.x + 1):
			if not keep.has(Vector2i(x, y)) or y == TUN_Y0 - 1:
				g.set_flag(x, y, Cell.F_PROTECTED, false)
				g.put(x, y, Cell.SOFT)
				keep[Vector2i(x, y)] = true
	var sand := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			g.put(x, y, Cell.AIR)
			g.set_sand(x, y, Balance.SAND_MAX)
			sand += Balance.SAND_MAX
	data["sand_pocket"] = sand
	data["landmarks"].append({"kind": "sand_pocket", "rect": r})


# --- 8 drifts ----------------------------------------------------------------
## Low dunes on flat floors, for the look of the place: never steeper than
## sand stands, so they lie still until something moves them.
func _drifts() -> void:
	var made := 0
	# one on the west rim, clear of the ladder and the pit's edge
	if _drift_at(27, RIM_Y - 1, 7):
		made += 1
	var tries := 0
	while made < 5 and tries < 400:
		tries += 1
		var x := rng.randi_range(6, W - 12)
		var y := rng.randi_range(GAL_Y0, HOP_Y0 + 8)
		if _drift_at(x, y, 5):
			made += 1
	data["drifts"] = made


func _drift_at(x0: int, y: int, width: int) -> bool:
	for x in range(x0 - 1, x0 + width + 1):
		if not g.in_bounds(x, y + 1) or not g.is_solid(x, y + 1) or g.get_mat(x, y) != Cell.AIR or g.get_sand(x, y) > 0 \
				or keep.has(Vector2i(x, y)) and y != RIM_Y - 1 or g.get_mat(x, y - 1) != Cell.AIR:
			return false
	var mid := (width - 1) / 2.0
	for k in width:
		var px := int(round(Balance.SAND_MAX * (1.0 - absf(k - mid) / (mid + 1.0))))
		g.set_sand(x0 + k, y, clampi(px, 2, Balance.SAND_MAX))
	return true


# --- 9 ore -------------------------------------------------------------------
func _ore() -> void:
	var made := 0
	var tries := 0
	while made < 26 and tries < 4000:
		tries += 1
		var x := rng.randi_range(5, W - 6)
		var y := rng.randi_range(GAL_Y0, PIT_Y1)
		if not _free(x, y) or not (g.get_mat(x, y) in [Cell.SOFT, Cell.HARD]) or g.get_ore(x, y) != 0:
			continue
		var open := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not g.is_solid(x + d.x, y + d.y):
				open = true
		if not open:
			continue
		g.put(x, y, g.get_mat(x, y), Cell.ORE_COBALT if (y > 40 and rng.randf() < 0.4) else Cell.ORE_COPPER)
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


# --- 11 crawlers and lamps ---------------------------------------------------
func _crawlers(count: int) -> void:
	var made := 0
	var tries := 0
	var spawn: Vector2i = data["spawn"]
	while made < count and tries < 2000:
		tries += 1
		var c := Vector2i(rng.randi_range(6, W - 7), rng.randi_range(GAL_Y0, HOP_Y0 + 9))
		if absi(c.x - spawn.x) + absi(c.y - spawn.y) < 24 or keep.has(c) or g.get_sand(c.x, c.y) > 0:
			continue
		if g.get_mat(c.x, c.y) != Cell.AIR or g.get_mat(c.x, c.y - 1) != Cell.AIR or not g.is_solid(c.x, c.y + 1):
			continue
		data["entities"].append({"type": "kin", "kind": "crawler", "cell": c})
		made += 1
	data["crawlers"] = made


func _lamps() -> void:
	for x in [30, 58]:
		data["entities"].append({"type": "lamp", "cell": Vector2i(x, TUN_Y0), "color": "ffb347"})
	for x in [26, 44, 51, 64]:
		data["entities"].append({"type": "lamp", "cell": Vector2i(x, HALL_Y0), "color": "ffb347"})
	data["entities"].append({"type": "lamp", "cell": Vector2i(71, HALL_Y0), "color": "6ff3d0"})


# --- 13 measure --------------------------------------------------------------
func _measure(target: float, full: float) -> void:
	var bed: Rect2i = data["bed"]
	var cap := 0
	var held := 0
	for y in range(bed.position.y, bed.end.y):
		for x in range(bed.position.x, bed.end.x):
			if not g.is_solid(x, y):
				cap += Balance.SAND_MAX
				held += g.get_sand(x, y)
	data["bed_capacity"] = cap
	data["bed_start"] = held
	data["bed_target"] = target
	data["sand_above"] = int(data["sand_hoppers"])
	var dc := DigCheck.new(g)
	dc.allow_ladder = true
	var from_spawn := dc.costs_from(data["spawn"])
	data["dig_to_lift_s"] = GenMetrics._near(dc, from_spawn, data["mission_lift"])
	data["valid"] = float(data["dig_to_lift_s"]) >= 0.0 and float(data["sand_above"]) >= float(cap) * target * full * 1.3
