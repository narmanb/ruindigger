class_name MineGenerator
extends RefCounted
## Seeded mine generation (generator v2). ORDER MATTERS (see README "Generation"):
##  1 strata-specific base rock      2 light background caves + worm tunnels
##  3 anchors claim footprints: lift room, timber shaft, relay, relic chamber
##  4 LayoutPlanner chooses chambers + roles; ChamberCarver gives them shape;
##    each backbone chamber is checked for traversal on its own
##  5 guaranteed route through the backbone chambers (carved AFTER every
##    destructive pass above), varied relic approach
##  6 supports of the route/backbone floors are marked untouchable
##  7 landmarks claim footprints and connect; branches and loops are carved as
##    organic tunnels that may never touch route cells or their supports
##  8 features on rock only (loose ceilings, boulders, ore, gas, water)
##  9 stabilise basalt, encounters, validation (strict traversal both ways),
##    environmental props, metrics
## Independent RNG streams (topology, landmarks, water, ore, encounters, props)
## keep one system's changes from reshuffling the others.

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
const VERSION := 2
var space: GenSpace
var carver: ChamberCarver
var chambers: Array = []
var support: Dictionary = {}      # solid cells that hold up the route/backbone floors
var sealed: Dictionary = {}       # container walls of water features / landmark shells
var topo := RandomNumberGenerator.new()
var land_rng := RandomNumberGenerator.new()
var water_rng := RandomNumberGenerator.new()
var ore_rng := RandomNumberGenerator.new()
var enc_rng := RandomNumberGenerator.new()
var route_rng := RandomNumberGenerator.new()
var branches := 0
var loops := 0
var chamber_fixes := 0


func generate(seed_value: int, contract_in: Dictionary = {}) -> Dictionary:
	rng.seed = seed_value
	contract = contract_in if not contract_in.is_empty() else Balance.CONTRACTS[0]
	W = Balance.MAP_W
	H = Balance.MAP_H
	g = TerrainGrid.new(W, H)
	data = {"seed": seed_value, "entities": [], "grid": g, "route": [], "version": VERSION, "landmarks": [], "water_features": []}
	var cseed: int = hash(str(contract.get("id", "survey")))
	topo.seed = seed_value ^ 0x70706f74
	land_rng.seed = seed_value ^ 0x646e616c ^ cseed
	water_rng.seed = seed_value ^ 0x72657477
	ore_rng.seed = seed_value ^ 0x2065726f ^ cseed
	enc_rng.seed = seed_value ^ 0x20636e65 ^ cseed
	route_rng.seed = seed_value ^ 0x74756f72
	space = GenSpace.new(W, H)
	# nothing may be planned inside the bedrock around the zones
	space.claim(Rect2i(0, 0, Balance.CORE_X0, Balance.SHELF_Y1), "void", "flank_w")
	space.claim(Rect2i(Balance.CORE_X1, 0, W - Balance.CORE_X1, Balance.SHELF_Y1), "void", "flank_e")
	space.claim(Rect2i(Balance.CORE_X0, Balance.STRATUM_ROWS[2], Balance.CORE_X1 - Balance.CORE_X0, Balance.SHELF_Y1 - Balance.STRATUM_ROWS[2]), "void", "shelf")
	space.claim(Rect2i(Balance.DIVIDER_X0, Balance.SHELF_Y1, Balance.DIVIDER_X1 - Balance.DIVIDER_X0, Balance.VAULT_Y0 - Balance.SHELF_Y1), "void", "divider")
	var zones: Array = []
	for z in Balance.ZONE_COUNT:
		zones.append({"id": z, "name": Balance.STRATUM_NAMES[z], "rect": Balance.ZONE_RECTS[z], "color": Balance.ZONE_COLORS[z]})
	data["zones"] = zones
	carver = ChamberCarver.new(self, topo)
	_trace("start")
	_base_fill(seed_value)
	_trace("_base_fill()")
	_caves(seed_value)
	_trace("_caves()")
	_worm_tunnels()
	_lift_room()
	_shaft()
	_relay_station()
	_relic_chamber()
	_shelf_gates()
	_trace("anchors")
	_plan_chambers()
	_trace("_plan_chambers()")
	_route()
	_trace("_route()")
	_mark_supports()
	_trace("_mark_supports()")
	_set_pieces()
	_trace("_set_pieces()")
	_landmarks_v2()
	_trace("_landmarks_v2()")
	_branches_and_loops()
	_trace("_branches_and_loops()")
	_roughen_route()
	_trace("_roughen_route()")
	_loose_ceilings()
	_trace("_loose_ceilings()")
	_hanging_boulders()
	_trace("_hanging_boulders()")
	_seal_slivers()
	_ore()
	_trace("_ore()")
	_geodes()
	_trace("_geodes()")
	_gas()
	_trace("_gas()")
	_water_pockets()
	_trace("_water_pockets()")
	_fill_basins()
	_ensure_water_encounter()
	_settle_water()
	_trace("_settle_water()")
	_stabilize_basalt()
	_trace("_stabilize_basalt()")
	_enemies()
	_trace("_enemies()")
	_finalize_hp()
	_trace("_finalize_hp()")
	_validate_and_repair()
	_trace("_validate_and_repair()")
	_water_environment()
	_trace("_water_environment()")
	data["repairs"] = repairs
	_summarise_plan()
	return data


# ---------------------------------------------------------------------------
func _base_fill(seed_value: int) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.07
	n.fractal_octaves = 3
	var phase := rng.randf() * TAU
	var warp := FastNoiseLite.new()
	warp.seed = seed_value + 5
	warp.frequency = 0.04
	for y in H:
		for x in W:
			var s := Balance.zone_of(x, y)
			if s < 0 or x < 2 or x >= W - 2 or y < 2 or y >= H - 6:
				# outside every zone: the unbreakable bedrock the world is cut into
				g.stratum[g.idx(x, y)] = _void_stratum(x, y)
				g.put(x, y, Cell.BEDROCK)
				g.set_flag(x, y, Cell.F_PROTECTED)
				continue
			# wavy boundaries where two zones meet top-to-bottom
			if s <= Balance.Z_SPORE:
				s = Balance.Z_SPORE if y >= Balance.STRATUM_ROWS[1] + int(round(2.5 * sin(x * 0.19 + phase + 1.0))) else Balance.Z_DUST
			elif y >= Balance.VAULT_Y0 + int(round(2.0 * sin(x * 0.17 + phase + 2.0))):
				s = Balance.Z_ENGINE
			elif y < Balance.VAULT_Y0:
				s = Balance.Z_AQUEDUCT if x < Balance.DIVIDER_X0 else Balance.Z_CRYSTAL
			else:
				s = Balance.Z_AQUEDUCT if x < (Balance.DIVIDER_X0 + Balance.DIVIDER_X1) / 2 else Balance.Z_CRYSTAL
			g.stratum[g.idx(x, y)] = s
			var v := n.get_noise_2d(x, y)
			var m := Cell.HARD if v > float(Balance.GEN_HARD_THRESH[s]) else Cell.SOFT
			match s:
				Balance.Z_DUST:
					# Dustworks: layered sediment. Thin, gently warped basalt beds
					# instead of blobs, so the stratum reads as mining country.
					var bed := sin(y * 0.52 + warp.get_noise_2d(x, y) * 2.2)
					m = Cell.HARD if (bed > 0.82 or v > 0.42) else Cell.SOFT
				Balance.Z_AQUEDUCT:
					# Drowned Aqueducts: level stone courses, like flooded masonry
					var course := sin(y * 0.9 + warp.get_noise_2d(x, y) * 0.8)
					m = Cell.HARD if (course > 0.45 or v > 0.34) else Cell.SOFT
				Balance.Z_CRYSTAL:
					# Crystal Hollows: steep, shard-like ribs of hard rock
					var rib := sin(x * 0.55 + y * 0.21 + warp.get_noise_2d(x, y) * 3.0)
					m = Cell.HARD if (rib > 0.35 or v > 0.22) else Cell.SOFT
			g.put(x, y, m)


## Tile set shown on bedrock outside the zones: whatever lies next to it.
func _void_stratum(x: int, y: int) -> int:
	if y >= Balance.VAULT_Y0:
		return Balance.Z_ENGINE
	if y >= Balance.SHELF_Y1:
		return Balance.Z_AQUEDUCT if x < (Balance.DIVIDER_X0 + Balance.DIVIDER_X1) / 2 else Balance.Z_CRYSTAL
	return Balance.Z_SPORE if y >= Balance.STRATUM_ROWS[1] else Balance.Z_DUST


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
			if g.mat[y * W + x] == Cell.BEDROCK:
				continue
			var s := g.get_stratum(x, y)
			var v := 0.0
			match s:
				Balance.Z_DUST:
					# long flat lenses between sediment beds
					n.frequency = 0.06
					v = n.get_noise_2d(x * 0.4, y * 1.9)
				Balance.Z_SPORE:
					n.frequency = 0.045
					v = n.get_noise_2d(x, y) * 0.8 + n2.get_noise_2d(x, y) * 0.35
				Balance.Z_ENGINE:
					# the Engine is mostly worked rock: natural voids are rare
					n.frequency = 0.05
					v = n.get_noise_2d(x * 0.8, y * 1.2)
				Balance.Z_AQUEDUCT:
					# drowned galleries: very long, low, level voids
					n.frequency = 0.05
					v = n.get_noise_2d(x * 0.3, y * 2.4)
				Balance.Z_CRYSTAL:
					# tall cracks and steep hollows
					n.frequency = 0.05
					v = n.get_noise_2d(x * 1.9, y * 0.45) * 0.85 + n2.get_noise_2d(x, y) * 0.3
			if v > float(Balance.GEN_CAVE_THRESH[s]):
				g.put(x, y, Cell.AIR)
	# smooth twice (cellular automata) so walls read as organic shapes
	for it in 2:
		var copy := g.mat.duplicate()
		for y in range(12, H - 8):
			for x in range(3, W - 3):
				if copy[y * W + x] == Cell.BEDROCK:
					continue
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


# ---------------------------------------------------------------------------
# Extra structure: worm tunnels and an abandoned rail tunnel (destructive, so
# they run before the protected rooms and the guaranteed route).
func _carve_free(x: int, y: int) -> void:
	if x < 3 or x >= W - 3 or y < 12 or y >= H - 8:
		return
	if g.has_flag(x, y, Cell.F_PROTECTED) or g.get_mat(x, y) == Cell.BEDROCK:
		return
	g.put(x, y, Cell.AIR)


func _zr(z: int) -> Rect2i:
	return Balance.ZONE_RECTS[z]


## A random cell inside zone z, at least `mx` from its sides, `top` below its
## top edge (never above row `min_y`) and `bot` above its bottom edge.
func _zone_cell(r: RandomNumberGenerator, z: int, mx: int, top: int, bot: int, min_y: int = 12) -> Vector2i:
	var zr := _zr(z)
	var lo := maxi(min_y, zr.position.y + top)
	var hi := maxi(lo, zr.end.y - 1 - bot)
	return Vector2i(r.randi_range(zr.position.x + mx, zr.end.x - 1 - mx), r.randi_range(lo, hi))


func _worm_tunnels() -> void:
	# wandering burrows: a few in the core, one in each wing
	var core := Rect2i(Balance.CORE_X0, 14, Balance.CORE_X1 - Balance.CORE_X0, Balance.STRATUM_ROWS[2] - 18)
	for i in rng.randi_range(2, 4):
		_worm(core)
	for z in [Balance.Z_AQUEDUCT, Balance.Z_CRYSTAL]:
		_worm((Balance.ZONE_RECTS[z] as Rect2i).grow(-3))


func _worm(area: Rect2i) -> void:
	var x := rng.randi_range(area.position.x + 3, area.end.x - 4)
	var y := rng.randi_range(area.position.y + 2, area.end.y - 3)
	var dir := Vector2(1 if rng.randf() < 0.5 else -1, 0)
	for step in rng.randi_range(25, 60):
		for dy in range(-1, 2):
			for dx in range(0, 2):
				_carve_free(int(x) + dx, int(y) + dy)
		if rng.randf() < 0.18:
			dir = Vector2(dir.x if rng.randf() < 0.7 else -dir.x, rng.randf_range(-0.9, 0.9))
		x = clampi(int(round(x + dir.x)), area.position.x + 2, area.end.x - 4)
		y = clampi(int(round(y + dir.y * 0.6 + (1 if rng.randf() < 0.08 else 0))), area.position.y + 1, area.end.y - 3)


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
	var ox: int = Balance.CORE_X0
	var x0 := 27 + ox
	_rect_fill(x0, 2, 18, 8, Cell.AIR, Cell.F_NO_RUBBLE)
	_rect_fill(x0, 10, 18, 2, Cell.HARD)
	_rect_fill(32 + ox, 10, 6, 2, Cell.HARD, Cell.F_PROTECTED)
	# shaft opening in the ceiling where the cable comes down
	for y in range(0, 2):
		for x in range(33 + ox, 37 + ox):
			g.put(x, y, Cell.AIR)
			g.set_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE)
	# keep the bedrock ceiling over the room protected (it is anyway) + side walls normal
	data["spawn"] = Vector2i(31 + ox, 9)
	data["lift"] = Vector2i(35 + ox, 9)
	for y in range(2, 10):
		for x in range(x0, x0 + 18):
			no_feature[Vector2i(x, y)] = true
			reserved[Vector2i(x, y)] = true
	data["entities"].append({"type": "lift", "cell": Vector2i(35 + ox, 9), "id": "surface"})
	data["entities"].append({"type": "lamp", "cell": Vector2i(29 + ox, 4)})
	data["entities"].append({"type": "lamp", "cell": Vector2i(42 + ox, 4)})
	data["entities"].append({"type": "sign", "cell": Vector2i(40 + ox, 9), "text": "SHAFT A"})
	space.claim(Rect2i(x0, 0, 18, 12), "anchor", "lift_room")


func _shaft() -> void:
	# Old timber shaft: 3 wide, ladder on the east column, platforms every 7 rows.
	var sx := 39 + Balance.CORE_X0
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
	data["shaft_x"] = sx
	space.claim(Rect2i(sx - 2, top, 5, bottom - top + 2), "anchor", "shaft")
	space.claim(Rect2i(sx - 9, bottom - 3, 12, 5), "anchor", "shaft_landing")
	var landings: Array = []
	for y in range(top + 6, bottom, 7):
		landings.append(y)
	data["shaft_landings"] = landings
	data["entities"].append({"type": "lamp", "cell": Vector2i(sx - 4, bottom - 2)})


func _relay_station() -> void:
	var y_floor := Balance.STRATUM_ROWS[1] + 8
	var left := rng.randf() < 0.5
	var x0 := Balance.CORE_X0 + 6 + rng.randi_range(0, 6) if left else Balance.CORE_X1 - 22 - rng.randi_range(0, 6)
	data["relay"] = _station(x0, y_floor, "relay")


## A lift station: a small protected room with a dormant relay lift. Returns the
## lift cell. The floor is protected and a support, so nothing can undermine it.
func _station(x0: int, y_floor: int, id: String) -> Vector2i:
	for y in range(y_floor - 5, y_floor + 1):
		for x in range(x0, x0 + 14):
			if g.get_mat(x, y) != Cell.LADDER:
				g.put(x, y, Cell.AIR)
			g.set_flag(x, y, Cell.F_PROTECTED, false)
			g.set_flag(x, y, Cell.F_NO_RUBBLE)
			reserved[Vector2i(x, y)] = true
			no_feature[Vector2i(x, y)] = true
	for x in range(x0, x0 + 14):
		if g.get_mat(x, y_floor + 1) != Cell.LADDER:
			g.put(x, y_floor + 1, Cell.HARD)
			g.set_flag(x, y_floor + 1, Cell.F_PROTECTED)
			support[Vector2i(x, y_floor + 1)] = true
	var cell := Vector2i(x0 + 7, y_floor)
	space.claim(Rect2i(x0 - 2, y_floor - 6, 18, 9), "anchor", id)
	data["entities"].append({"type": "lift", "cell": cell, "id": id})
	data["entities"].append({"type": "lamp", "cell": Vector2i(x0 + 1, y_floor - 4)})
	return cell


## The bedrock shelf under the Spore Veins is open only at its two ends. Each
## gate is an authored ladder shaft (bedrock cannot be cut into steps) from a
## landing in the Spore Veins down to a lift station at the top of a wing.
func _shelf_gates() -> void:
	var gates: Array = []
	var top_y: int = Balance.STRATUM_ROWS[2] - 1          # feet row of the landing above
	var station_floor: int = Balance.SHELF_Y1 + 6          # feet row of the station below
	for side in [-1, 1]:
		var gx: int = Balance.CORE_X0 + 4 if side < 0 else Balance.CORE_X1 - 6
		# landing alcove in the Spore Veins
		var lx0: int = gx - 1 if side < 0 else gx - 6
		for y in range(top_y - 3, top_y + 1):
			for x in range(lx0, lx0 + 9):
				g.put(x, y, Cell.AIR)
				g.set_flag(x, y, Cell.F_NO_RUBBLE)
				reserved[Vector2i(x, y)] = true
				no_feature[Vector2i(x, y)] = true
		for x in range(lx0, lx0 + 9):
			if x != gx and x != gx + 1:
				support[Vector2i(x, top_y + 1)] = true
		# the station sits right under the shelf, reaching inward under the core
		var sx0: int = gx - 2 if side < 0 else gx - 10
		var lift := _station(sx0, station_floor, "relay_l" if side < 0 else "relay_r")
		# the shaft through the shelf: 2 wide with a ladder, bedrock walls
		for y in range(top_y - 1, station_floor + 1):
			for x in [gx, gx + 1]:
				g.set_flag(x, y, Cell.F_PROTECTED, false)
				g.put(x, y, Cell.AIR)
				g.set_flag(x, y, Cell.F_NO_RUBBLE)
				reserved[Vector2i(x, y)] = true
				no_feature[Vector2i(x, y)] = true
			g.put(gx, y, Cell.LADDER)
		space.claim(Rect2i(lx0 - 1, top_y - 4, 11, 6), "anchor", "gate_landing")
		space.claim(Rect2i(gx - 1, Balance.STRATUM_ROWS[2], 4, Balance.SHELF_Y1 - Balance.STRATUM_ROWS[2]), "gate", "gate_shaft")
		var top := Vector2i(gx + (3 if side < 0 else -2), top_y)
		var bottom := Vector2i(lift.x + (5 if side < 0 else -5), station_floor)
		gates.append({"side": side, "x": gx, "top": top, "bottom": bottom, "lift": lift, "zone": Balance.Z_AQUEDUCT if side < 0 else Balance.Z_CRYSTAL})
		data["entities"].append({"type": "sign", "cell": Vector2i(gx + (4 if side < 0 else -3), top_y), "text": "WEST DESCENT" if side < 0 else "EAST DESCENT"})
		data["entities"].append({"type": "lamp", "cell": Vector2i(gx + (5 if side < 0 else -4), top_y - 3)})
	data["gates"] = gates


func _relic_chamber() -> void:
	var w := 16
	var h := 9
	# the shared vault: both wings come down into the Forgotten Engine, and the
	# relic chamber sits near its centre so either side is a fair way in
	var y0 := H - 6 - h - rng.randi_range(2, 4)
	var door_left := rng.randf() < 0.5
	var x0 := rng.randi_range(W / 2 - 22, W / 2 + 6)
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
	space.claim(Rect2i(mini(x0, ax0) - 1, y0 - 1, w + 8, h + 2), "anchor", "relic")
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
	## Landmark pool. Each template claims its whole footprint through GenSpace
	## (so nothing overlaps), is placed with the landmark RNG stream, and is joined
	## to the route by a short passage sealed with its own kind of wall.
	var pool: Array = [
		["grotto", 0.75], ["camp", 0.7], ["vault", 0.7],
	]
	for entry in pool:
		if land_rng.randf() > float(entry[1]):
			continue
		match entry[0]:
			"grotto":
				_lm_grotto()
			"camp":
				_lm_camp()
			"vault":
				_lm_vault()


## Footprint for a landmark: free in GenSpace AND clear of the guaranteed
## route and its supports (landmarks are placed after the route is carved).
func _place_landmark(rw: int, rh: int, y_lo: int, y_hi: int, margin: int, x_lo: int = -1, x_hi: int = -1) -> Rect2i:
	if x_lo < 0:
		# callers that only give rows mean the core column
		x_lo = Balance.CORE_X0 + 2
		x_hi = Balance.CORE_X1 - 2
	for attempt in 12:
		var r := space.place(land_rng, rw, rh, y_lo, y_hi, margin, 40, x_lo, x_hi)
		if r.size.x == 0:
			continue
		var clear := true
		for y in range(r.position.y - 1, r.end.y + 1):
			for x in range(r.position.x - 1, r.end.x + 1):
				var c := Vector2i(x, y)
				if reserved.has(c) or support.has(c):
					clear = false
					break
			if not clear:
				break
		if clear:
			return r
	return Rect2i()


func _lm_grotto() -> void:
	var r := _place_landmark(16, 9, 26, Balance.STRATUM_ROWS[1] - 8, 2)
	if r.size.x == 0:
		return
	space.claim(r, "landmark", "grotto")
	var gx := r.position.x + 1
	var gy := r.position.y + 1
	_rect_fill(gx - 1, gy - 1, 16, 9, Cell.HARD, 0, true)
	_ellipse_air(gx + 7, gy + 3, 6.5, 3.2)
	for k in range(0, 12):
		var fx := gx + 1 + k
		if g.is_solid(fx, gy + 6):
			g.put(fx, gy + 6, Cell.SOFT, Cell.ORE_FOSSIL if k % 2 == 0 else Cell.ORE_NONE)
	for k in [3, 5, 7, 9]:
		if g.is_solid(gx + k, gy - 0):
			g.put(gx + k, gy, Cell.SOFT, Cell.ORE_FOSSIL)
	data["entities"].append({"type": "skull", "cell": Vector2i(gx + 3, gy + 5)})
	data["grotto"] = r
	_mark_no_feature(r)
	data["landmarks"].append({"kind": "fossil_grotto", "rect": r})
	_connect_secret(r, Cell.CRACKED)


func _lm_vault() -> void:
	var r := _place_landmark(11, 7, Balance.STRATUM_ROWS[1] + 14, Balance.STRATUM_ROWS[2] - 10, 2)
	if r.size.x == 0:
		return
	space.claim(r, "landmark", "vault")
	var vx := r.position.x
	var vy := r.position.y
	_rect_fill(vx, vy, 11, 7, Cell.HARD, 0, true)
	_rect_fill(vx + 2, vy + 2, 7, 3, Cell.AIR, 0, true)
	for x in range(vx + 2, vx + 9):
		g.put(x, vy + 1, Cell.HARD, Cell.ORE_COBALT if x % 2 == 0 else Cell.ORE_NONE)
	data["entities"].append({"type": "cache", "cell": Vector2i(vx + 5, vy + 4), "charges": 2, "repair": 40})
	data["vault"] = r
	_mark_no_feature(r)
	data["landmarks"].append({"kind": "cobalt_vault", "rect": r})
	_connect_secret(r, Cell.HARD)


func _lm_camp() -> void:
	var r := _place_landmark(14, 9, 14, 40, 2)
	if r.size.x == 0:
		return
	space.claim(r, "landmark", "camp")
	var cx := r.position.x + 1
	var cy := r.position.y + 4
	_rect_fill(cx, cy, 12, 4, Cell.AIR)
	_rect_fill(cx, cy + 4, 12, 1, Cell.HARD)
	_rect_fill(cx + 3, cy - 3, 6, 2, Cell.LOOSE)
	_rect_fill(cx + 3, cy - 1, 6, 1, Cell.SOFT)
	data["entities"].append({"type": "cache", "cell": Vector2i(cx + 9, cy + 3), "charges": 1, "repair": 0})
	data["entities"].append({"type": "crate", "cell": Vector2i(cx + 2, cy + 3)})
	data["entities"].append({"type": "lamp", "cell": Vector2i(cx + 6, cy), "color": "ffb347"})
	data["entities"].append({"type": "sign", "cell": Vector2i(cx + 1, cy + 3), "text": "UNSTABLE"})
	data["camp"] = Rect2i(cx, cy, 12, 5)
	_mark_no_feature(r)
	data["landmarks"].append({"kind": "miner_camp", "rect": r})
	_connect_secret(Rect2i(cx, cy, 12, 5), Cell.AIR)


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
	## Guaranteed route. Trunk: shaft bottom -> relay -> Spore Veins backbone
	## chambers. At the bedrock shelf it splits: each side treks to its gate,
	## drops into a wing, runs through that wing's backbone chambers and comes
	## down into the Engine vault to the relic door. Inside a backbone chamber its
	## own (pre-checked) geometry carries the player from entry to exit.
	var relay: Vector2i = data["relay"]
	var mid_x: int = (Balance.CORE_X0 + Balance.CORE_X1) / 2
	var relay_entry := Vector2i(relay.x - 5 if relay.x > mid_x else relay.x + 5, relay.y)
	var trunk: Array = _chain(relay_entry, [Balance.Z_DUST, Balance.Z_SPORE])
	var outside: Vector2i = data["door_outside"]
	var side := -1 if data["door_left"] else 1
	var approach: String = ["maintenance_shaft", "gallery", "direct"][route_rng.randi_range(0, 2)]
	data["relic_approach"] = approach
	var start: int = data["route"].size()
	_build_leg_costs()
	_trace("  leg costs")
	var cur: Vector2i = data["shaft_bottom"]
	_carve_leg(cur, relay_entry)
	cur = _carve_chain(relay_entry, trunk)
	var trunk_end := cur
	data["trunk_end"] = trunk_end
	for gate in data["gates"]:
		# the trek along the shelf to this side's gate
		_carve_leg(trunk_end, gate["top"])
		var wing: Array = _chain(gate["bottom"], [gate["zone"]])
		cur = _carve_chain(gate["bottom"], wing)
		# the wing on the door's side gets the dressed approach; the other one
		# simply finds its way to the door through the vault
		var tail: Array[Vector2i] = [outside]
		var dressed: bool = approach != "direct" and int(gate["side"]) == side
		if dressed:
			match approach:
				"maintenance_shaft":
					var sx := clampi(outside.x + side * 2, 4, W - 6)
					tail = [Vector2i(sx, Balance.VAULT_Y0 + 2), Vector2i(sx, outside.y), outside]
				"gallery":
					var gx := clampi(outside.x + side * route_rng.randi_range(10, 16), 4, W - 6)
					tail = [Vector2i(gx, Balance.VAULT_Y0 + 2), Vector2i(gx, outside.y), outside]
		var tail_start: int = data["route"].size()
		# the lined approach is an authored ruin structure: alloy walls cannot be
		# cut into steps, so it is built with plank scaffolds and is never plugged
		for k in tail.size():
			_authored_leg = dressed and k > 0
			_carve_leg(cur, tail[k])
			cur = tail[k]
		_authored_leg = false
		# dress the final approach: ruin-built lining around the last stretch
		if dressed:
			var lined := 0
			var from_k := tail_start
			for k in range(tail_start, data["route"].size()):
				if (data["route"][k] as Vector2i).y < Balance.VAULT_Y0 + 2:
					from_k = k + 1
			for k in range(from_k, data["route"].size()):
				var rc: Vector2i = data["route"][k]
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
					var n: Vector2i = rc + d
					if g.is_solid(n.x, n.y) and not reserved.has(n) and writable(n.x, n.y) and g.get_mat(n.x, n.y) != Cell.ALLOY:
						g.put(n.x, n.y, Cell.ALLOY)
						no_feature[n] = true
						lined += 1
			data["approach_lined"] = lined
	data["route_cells_main"] = data["route"].size() - start


## Backbone chambers of the given zones as route steps from `from`:
## ["leg", entry] carves a leg to the chamber, ["skip", exit] walks through it.
func _chain(from: Vector2i, zones: Array) -> Array:
	var out: Array = []
	var prev := from
	for c in chambers:
		if not c["backbone"] or not zones.has(int(c["stratum"])):
			continue
		var a: Vector2i = c["entry"]
		var b: Vector2i = c["exit"]
		if prev.distance_squared_to(b) < prev.distance_squared_to(a):
			var t := a
			a = b
			b = t
		out.append(["leg", a])
		out.append(["skip", b])
		prev = b
	return out


func _carve_chain(from: Vector2i, chain: Array) -> Vector2i:
	var cur := from
	for p in chain:
		if p[0] == "leg":
			_carve_leg(cur, p[1])
		cur = p[1]
	return cur


# ---------------------------------------------------------------------------
# Route legs are found with A* over a cost field, then carved with the usual
# corridor / ladder-shaft builders. Legs prefer existing open space, pay heavily
# to pass through other chambers or landmarks (whose floors they would cut), and
# penalise turns so they form long, readable segments.
var _leg_cost := PackedFloat32Array()
const LEG_TURN := 3.0
const LEG_VERTICAL := 1.35
const LEG_ROOM := 45.0


func _build_leg_costs() -> void:
	var n := W * H
	_leg_cost = PackedFloat32Array()
	_leg_cost.resize(n)
	# per-cell penalties first (flat arrays), then a 2x3 window sum per cell
	var pen := PackedFloat32Array()
	pen.resize(n)
	var blocked := PackedByteArray()
	blocked.resize(n)
	for cl in space.claims:
		if cl["kind"] == "anchor":
			continue
		# grow by 3: floors, basins and lips sit just outside the footprint
		var r: Rect2i = (cl["rect"] as Rect2i).grow(3)
		for y in range(maxi(0, r.position.y), mini(H, r.end.y)):
			for x in range(maxi(0, r.position.x), mini(W, r.end.x)):
				pen[y * W + x] = LEG_ROOM / 6.0
	for c in sealed.keys():
		blocked[c.y * W + c.x] = 1   # basin rims: the route must not drain a lake
	for i in n:
		var m: int = g.mat[i]
		if Cell.is_solid(m):
			if g.flags[i] & Cell.F_PROTECTED:
				blocked[i] = 1
			else:
				pen[i] += 0.25
	for y in H:
		for x in W:
			var i := y * W + x
			if x < 3 or x >= W - 4 or y < 4 or y >= H - 7:
				_leg_cost[i] = -1.0
				continue
			var cost := 1.0
			var bad := false
			for dy in range(-2, 1):
				var row := (y + dy) * W + x
				if blocked[row] or blocked[row + 1]:
					bad = true
					break
				cost += pen[row] + pen[row + 1]
			_leg_cost[i] = -1.0 if bad else cost


func _carve_leg(a: Vector2i, b: Vector2i) -> void:
	var path := _leg_path(a, b)
	if path.is_empty():
		_carve_between(a, b)   # unreachable in the cost field: legacy staircase
		return
	# compress into straight runs and carve each with the classic builders
	var i := 0
	while i < path.size() - 1:
		var p0: Vector2i = path[i]
		var horizontal := path[i + 1].y == p0.y
		var j := i + 1
		while j + 1 < path.size() and ((path[j + 1].y == path[j].y) == horizontal):
			j += 1
		# a corridor that turns straight down into a shaft must not get a floor
		# plugged under the corner (it would wall off the shaft's side)
		var floor_ok := not (horizontal and j + 1 < path.size() and path[j + 1].y > path[j].y)
		_carve_between_axis(p0, path[j], horizontal, floor_ok)
		i = j


func _carve_between_axis(a: Vector2i, b: Vector2i, horizontal: bool, floor_ok: bool = true) -> void:
	if horizontal:
		# remember which columns were solid rock: only those may become dig plugs
		var x0 := mini(a.x, b.x)
		var x1 := maxi(a.x, b.x)
		var rock: Array = []
		for x in range(x0, x1 + 1):
			var all_rock := true
			for dy in range(-2, 2):
				var m := g.get_mat(x, a.y + dy)
				if not (m == Cell.SOFT or m == Cell.HARD) or g.has_flag(x, a.y + dy, Cell.F_PROTECTED) or reserved.has(Vector2i(x, a.y + dy)):
					all_rock = false
			rock.append(all_rock)
		var x := a.x
		_carve_corridor(x, a.y)
		while x != b.x:
			x += signi(b.x - x)
			_carve_corridor(x, a.y)
		if floor_ok:
			_ensure_floor(b.x, b.y)
		_corridor_plug(x0, x1, a.y, rock)
	else:
		var y0 := mini(a.y, b.y)
		var y1 := maxi(a.y, b.y)
		var style := _shaft_style(a.x, y0, y1)
		shaft_styles[style] = int(shaft_styles.get(style, 0)) + 1
		if style == "plug":
			_carve_plug_shaft(a.x, y0, y1)
		else:
			for y in range(y0 - 2, y1 + 1):
				_carve_cell(a.x, y)
				_carve_cell(a.x + 1, y)
			if style == "ladder":
				for y in range(y0, y1 + 1):
					if not g.has_flag(a.x, y, Cell.F_PROTECTED):
						g.put(a.x, y, Cell.LADDER)
						g.set_flag(a.x, y, Cell.F_NO_RUBBLE)
			elif style == "ledges":
				# plank scaffolds one jump (3 cells) apart, bottom-up
				var r := y1 + 1 - RouteCheck.JUMP_CELLS
				while r >= y0 + 1:
					for xx in [a.x, a.x + 1]:
						if g.get_mat(xx, r) == Cell.AIR:
							g.put(xx, r, Cell.PLATFORM)
							g.set_flag(xx, r, Cell.F_NO_RUBBLE)
					r -= RouteCheck.JUMP_CELLS
		_ensure_floor(b.x, b.y)


var shaft_styles: Dictionary = {}
var _authored_leg := false
var corridor_plugs := 0


## Which kind of vertical route section to build. The Dustworks keeps its
## ladders (tutorial zone); deeper down the player mostly cuts their own way.
func _shaft_style(x: int, y0: int, y1: int) -> String:
	if y1 - y0 <= RouteCheck.JUMP_CELLS:
		return "open"   # a single jump covers it
	var s := g.get_stratum(x, y0)
	if s == 0:
		return "ladder"
	if _authored_leg:
		return "ledges"   # ruin maintenance scaffolds: climbable without a ladder
	# shafts lined with unbreakable walls would be pits: those keep a ladder
	for y in range(y0, y1 + 1):
		for xx in [x - 1, x + 2]:
			var m := g.get_mat(xx, y)
			if m == Cell.ALLOY or m == Cell.BEDROCK or (Cell.is_solid(m) and g.has_flag(xx, y, Cell.F_PROTECTED)):
				return "ladder"
	var w: Array = Balance.GEN_SHAFT_STYLE[s]
	var roll := route_rng.randf()
	var names := ["ladder", "ledges", "open", "plug"]
	for i in names.size():
		roll -= float(w[i])
		if roll <= 0.0:
			return names[i]
	return "open"


## A route section left as cracked rock: the player drills down through it and
## climbs back up the bore with a Rubble Ladder. Existing caves it crosses stay open.
func _carve_plug_shaft(x: int, y0: int, y1: int) -> void:
	for y in range(y0 + 1, y1 - 2):
		var c := Vector2i(x, y)
		var m := g.get_mat(x, y)
		if (m == Cell.SOFT or m == Cell.HARD) and not g.has_flag(x, y, Cell.F_PROTECTED) and not reserved.has(c) and not support.has(c) and not sealed.has(c):
			g.put(x, y, Cell.CRACKED)
		# part of the route even though it is rock: landmarks, gas and ore keep off
		reserved[c] = true
		no_feature[c] = true
		no_feature[Vector2i(x + 1, y)] = true
		data["route"].append(c)
	# open the two ends so the cracked column is found from above and below
	for y in range(y0 - 2, y0 + 1):
		_carve_cell(x, y)
		_carve_cell(x + 1, y)
	for y in range(y1 - 2, y1 + 1):
		_carve_cell(x, y)
		_carve_cell(x + 1, y)


## Now and then a corridor is left blocked by a short cracked wall the player
## has to drill through (never across caves, protected rock or the ends).
func _corridor_plug(x0: int, x1: int, y: int, rock: Array) -> void:
	if g.get_stratum(x0, y) == 0 or _authored_leg:
		return
	# one chance of a plug per stretch of corridor, never within 3 cells of an end
	var x := x0 + 3
	while x <= x1 - 3 - Balance.GEN_CORRIDOR_PLUG_LEN[0]:
		var want := mini(route_rng.randi_range(Balance.GEN_CORRIDOR_PLUG_LEN[0], Balance.GEN_CORRIDOR_PLUG_LEN[1]), x1 - 3 - x)
		var gap := route_rng.randi_range(0, 4)
		if route_rng.randf() > Balance.GEN_CORRIDOR_PLUG_CHANCE:
			x += Balance.GEN_CORRIDOR_PLUG_SPACING
			continue
		var start := x + gap
		var ok := start + want <= x1 - 3
		if ok:
			for xx in range(start, start + want):
				if not rock[xx - x0]:
					ok = false
		if ok:
			for xx in range(start, start + want):
				for dy in range(-2, 1):
					g.put(xx, y + dy, Cell.CRACKED)
			corridor_plugs += 1
		x += Balance.GEN_CORRIDOR_PLUG_SPACING


var _hk := PackedFloat32Array()   # heap keys
var _hv := PackedInt32Array()     # heap values
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


func _leg_path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := W * H
	var best := PackedFloat32Array()
	best.resize(n * 2)
	best.fill(1e30)
	var came := PackedInt32Array()
	came.resize(n * 2)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n * 2)
	_hn = 0
	var start_i := a.y * W + a.x
	var goal_i := b.y * W + b.x
	for axis in 2:
		best[start_i * 2 + axis] = 0.0
		_hpush(absi(a.x - b.x) + absi(a.y - b.y), start_i * 2 + axis)
	var found := -1
	var expansions := 0
	var dxs := [1, -1, 0, 0]
	var dys := [0, 0, 1, -1]
	while _hn > 0 and expansions < 40000:
		var st := _hpop()
		if closed[st]:
			continue
		closed[st] = 1
		expansions += 1
		var idx := st >> 1
		var axis := st & 1
		if idx == goal_i:
			found = st
			break
		var gcost := best[st]
		var x := idx % W
		var y := idx / W
		for k in 4:
			var nx: int = x + dxs[k]
			var ny: int = y + dys[k]
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var ni := ny * W + nx
			var near_end := absi(nx - b.x) + absi(ny - b.y) <= 3 or absi(nx - a.x) + absi(ny - a.y) <= 3
			var cell_cost := _leg_cost[ni]
			if ni == goal_i or ni == start_i:
				cell_cost = 1.0
			elif cell_cost < 0.0:
				continue          # protected rock stays blocked even near the ends
			elif near_end:
				cell_cost = 1.0   # only the room penalty is waived at the anchors
			var naxis := 0 if k < 2 else 1
			var step := cell_cost * (LEG_VERTICAL if naxis == 1 else 1.0)
			if naxis != axis:
				step += LEG_TURN
			var ns := ni * 2 + naxis
			var ng := gcost + step
			if ng < best[ns]:
				best[ns] = ng
				came[ns] = st
				_hpush(ng + absi(nx - b.x) + absi(ny - b.y), ns)
	if found < 0:
		return out
	var s2 := found
	while s2 >= 0:
		var id := s2 >> 1
		out.push_front(Vector2i(id % W, id / W))
		s2 = came[s2]
	return out


## Walls/floors that hold up the guaranteed route and backbone chamber floors.
## Later destructive passes (branches, landmark passages) must not touch these.
func _mark_supports() -> void:
	support.clear()
	for c in reserved.keys():
		var b := Vector2i(c.x, c.y + 1)
		if g.is_solid(b.x, b.y) or g.get_mat(b.x, b.y) == Cell.PLATFORM:
			support[b] = true
	for ch in chambers:
		if not ch["backbone"]:
			continue
		var r: Rect2i = ch["rect"]
		for y in range(r.position.y - 1, r.end.y + 3):
			for x in range(r.position.x - 1, r.end.x + 1):
				if g.is_solid(x, y) and not g.is_solid(x, y - 1):
					support[Vector2i(x, y)] = true


var _prof_t := 0
func _trace(tag: String) -> void:
	if OS.get_environment("RD_PROFILE") != "":
		var now := Time.get_ticks_usec()
		if _prof_t > 0:
			print("PROF %-24s %6.1f ms" % [tag, (now - _prof_t) / 1000.0])
		_prof_t = now
	var ce := OS.get_environment("RD_CELL")
	if ce != "":
		var pp := ce.split(",")
		print("CELL after ", tag, ": mat ", g.get_mat(int(pp[0]), int(pp[1])))
	if OS.get_environment("RD_TRACE") == "":
		return
	var bad: Array = []
	for c in chambers:
		if c["backbone"] and not (RouteCheck.can_reach(g, c["entry"], c["exit"]) and RouteCheck.can_reach(g, c["exit"], c["entry"])):
			bad.append(c["arch"])
	print("TRACE after ", tag, ": broken chambers ", bad)
	if tag == "_route()":
		var chars := {0: ".", 1: "s", 2: "H", 3: "o", 4: "A", 5: "#", 6: "g", 7: "c", 8: "L", 9: "="}
		for c in chambers:
			if c["arch"] != "cathedral":
				continue
			var rr: Rect2i = c["rect"]
			print("entry ", c["entry"], " exit ", c["exit"], " rect ", rr)
			for yy in range(rr.position.y - 3, rr.end.y + 4):
				var line := ""
				for xx in range(rr.position.x - 3, rr.end.x + 3):
					var ch: String = chars[g.get_mat(xx, yy)]
					if reserved.has(Vector2i(xx, yy)) and ch == ".":
						ch = "r"
					line += ch
				print("   %3d %s" % [yy, line])


## Mark the solid cells around a set of (future) water cells as a sealed
## container: no later tunnel, passage or roughening may open them.
func seal_around(cells: Array) -> void:
	var set_: Dictionary = {}
	for c in cells:
		set_[c] = true
	for c in cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				if not set_.has(n) and g.is_solid(n.x, n.y):
					sealed[n] = true


func seal_rect(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			sealed[Vector2i(x, y)] = true


func writable(x: int, y: int) -> bool:
	if not g.in_bounds(x, y) or x < 2 or x >= W - 2 or y < 2 or y >= H - 6:
		return false
	return not g.has_flag(x, y, Cell.F_PROTECTED) and g.get_mat(x, y) != Cell.BEDROCK


func tunnel_ok(x: int, y: int) -> bool:
	if x < 3 or x >= W - 3 or y < 12 or y >= H - 8 or not writable(x, y):
		return false
	var c := Vector2i(x, y)
	if reserved.has(c) or support.has(c) or sealed.has(c):
		return false
	var m := g.get_mat(x, y)
	return m != Cell.ALLOY and m != Cell.LADDER and m != Cell.PLATFORM


# ---------------------------------------------------------------------------
func _plan_chambers() -> void:
	var planner := LayoutPlanner.new(self, topo)
	chambers = planner.plan()
	var halls: Array = []
	for c in chambers:
		carver.carve(c)
		var r: Rect2i = c["rect"]
		if c["arch"] == "ruin":
			halls.append(r)
			for sdef in c.get("sentries", []):
				data["entities"].append({"type": "sentry", "cell": sdef["cell"], "module": sdef["module"]})
			# aetherite set into the shell exterior as the lure
			for k in 3:
				var ax := topo.randi_range(r.position.x, r.end.x - 1)
				if g.get_mat(ax, r.position.y - 1) in [Cell.SOFT, Cell.HARD]:
					g.put(ax, r.position.y - 1, Cell.HARD, Cell.ORE_AETHER)
		if c["arch"] in ["ruin", "works"]:
			_mark_no_feature(r)
	data["halls"] = halls
	for c in chambers:
		seal_around(c.get("basin", []))
	# each backbone chamber must carry the player between its anchors on its own
	for c in chambers:
		if not c["backbone"]:
			continue
		var a: Vector2i = c["entry"]
		var b: Vector2i = c["exit"]
		# a frayed fissure only has to carry the player down; the way back up is a
		# Rubble Ladder, proven by the whole-mine DigCheck at the end
		var up_ok: bool = c.get("frayed", false) or RouteCheck.can_reach(g, b, a)
		if RouteCheck.can_reach(g, a, b) and up_ok:
			continue
		if OS.get_environment("RD_NOFIX") != "":
			print("chamber fails: ", c["arch"], " entry ", a, " exit ", b, " a->b ", RouteCheck.can_reach(g, a, b), " b->a ", RouteCheck.can_reach(g, b, a))
			var rs := RouteCheck.reachable(g, b)
			var minx := 999
			for k in rs.keys():
				if k.y >= a.y - 3 and k.y <= a.y + 4:
					minx = mini(minx, k.x)
			print("  from exit: reached min x near floor ", minx, " count ", rs.size())
			var chars := {0: ".", 1: "s", 2: "H", 3: "o", 4: "A", 5: "#", 6: "g", 7: "c", 8: "L", 9: "="}
			var rr: Rect2i = c["rect"]
			for yy in range(rr.position.y - 2, rr.end.y + 3):
				var line := ""
				for xx in range(rr.position.x - 2, rr.end.x + 2):
					var ch: String = chars[g.get_mat(xx, yy)]
					if Vector2i(xx, yy) == a:
						ch = "A"
					elif Vector2i(xx, yy) == b:
						ch = "B"
					line += ch
				print("   %3d %s" % [yy, line])
			continue
		chamber_fixes += 1
		c["fixed"] = true
		_carve_between_straight(a, b)


func _branches_and_loops() -> void:
	## Optional structure: side chambers branch off the spine/route, a couple of
	## loops give alternate ways round, all as organic tunnels.
	var sx: int = data["shaft_x"]
	var landings: Array = data["shaft_landings"]
	var s0: Array = []
	for c in chambers:
		var r: Rect2i = c["rect"]
		var centre := Vector2(r.get_center())
		if c["stratum"] == 0:
			s0.append(c)
			# join the shaft at the nearest platform landing
			var best_y: int = landings[0]
			for ly in landings:
				if absi(ly - r.get_center().y) < absi(best_y - r.get_center().y):
					best_y = ly
			var west := centre.x < sx
			var mouth_x := sx - 2 if west else sx + 2
			var anchor: Vector2i = c["entry"] if absf(c["entry"].x - mouth_x) < absf(c["exit"].x - mouth_x) else c["exit"]
			carver.tunnel(Vector2(anchor) + Vector2(0.5, -0.5), Vector2(mouth_x + (-2 if west else 2), best_y - 1.5), 1.4, 1.9, 0.25)
			# a clean walkable mouth onto the landing (feet row best_y - 1)
			for k in range(0, 4):
				var mx: int = mouth_x + (-k if west else k)
				for dy in range(-3, 0):
					if tunnel_ok(mx, best_y + dy):
						g.put(mx, best_y + dy, Cell.AIR)
				if not g.is_solid(mx, best_y) and tunnel_ok(mx, best_y):
					g.put(mx, best_y, Cell.HARD)
			branches += 1
		elif not c["backbone"]:
			# side chamber: tunnel to the nearest route cell
			var best := Vector2i(-1, -1)
			var bd := 1 << 30
			for rc in data["route"]:
				var d: int = absi(rc.x - int(centre.x)) + absi(rc.y - int(centre.y))
				if d < bd:
					bd = d
					best = rc
			if best.x >= 0:
				var anchor2: Vector2i = c["entry"] if c["entry"].distance_squared_to(best) < c["exit"].distance_squared_to(best) else c["exit"]
				carver.tunnel(Vector2(anchor2) + Vector2(0.5, -0.5), Vector2(best) + Vector2(0.5, -0.5), 1.3, 2.0, 0.3)
				branches += 1
	# loop in Dustworks: two side chambers linked to each other (and both to the shaft)
	if s0.size() >= 2:
		var a: Dictionary = s0[0]
		var b: Dictionary = s0[1]
		carver.tunnel(Vector2((a["rect"] as Rect2i).get_center()), Vector2((b["rect"] as Rect2i).get_center()), 1.3, 1.8, 0.35)
		loops += 1
	# loops between consecutive backbone chambers of the same stratum
	var bb: Array = []
	for c in chambers:
		if c["backbone"]:
			bb.append(c)
	for i in range(bb.size() - 1):
		if bb[i]["stratum"] != bb[i + 1]["stratum"]:
			continue
		var ra: Rect2i = bb[i]["rect"]
		var rb: Rect2i = bb[i + 1]["rect"]
		var pa := Vector2(ra.position.x + ra.size.x * topo.randf_range(0.2, 0.8), ra.position.y + 1.5)
		var pb := Vector2(rb.position.x + rb.size.x * topo.randf_range(0.2, 0.8), rb.position.y + 1.5)
		carver.tunnel(pa, pb, 1.2, 1.7, 0.4)
		loops += 1


## Cosmetic: give stretches of constructed route corridor an uneven natural
## ceiling (never touching floors, supports or reserved cells).
func _roughen_route() -> void:
	var n := FastNoiseLite.new()
	n.seed = int(data["seed"]) + 909
	n.frequency = 0.15
	for rc in data["route"]:
		var above := Vector2i(rc.x, rc.y - 1)
		if reserved.has(above) or not g.is_solid(above.x, above.y):
			continue
		var lift := int(round((n.get_noise_2d(rc.x, rc.y) + 0.2) * 2.0))
		for k in range(0, lift):
			var c := Vector2i(rc.x, rc.y - 1 - k)
			if tunnel_ok(c.x, c.y) and g.is_solid(c.x, c.y) and g.get_mat(c.x, c.y) != Cell.ALLOY:
				g.put(c.x, c.y, Cell.AIR)
			else:
				break


func _summarise_plan() -> void:
	var kinds: Dictionary = {}
	var summary: Array = []
	for c in chambers:
		var key: String = c["arch"] + ("/" + c["variant"] if c.get("variant", "") != "" else "")
		kinds[key] = true
		summary.append({"id": c["id"], "arch": c["arch"], "variant": c.get("variant", ""), "stratum": c["stratum"], "rect": c["rect"], "backbone": c["backbone"], "fixed": c.get("fixed", false)})
	data["plan"] = {"chambers": summary, "archetype_count": kinds.size(), "branches": branches, "loops": loops,
		"chamber_fixes": chamber_fixes, "relic_approach": data.get("relic_approach", ""), "overlaps": space.overlaps(),
		"shaft_styles": shaft_styles, "corridor_plugs": corridor_plugs}


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
			if not reserved.has(Vector2i(xx, y + 1)) and space.kind_at(Vector2i(xx, y + 1)) != "chamber":
				g.put(xx, y + 1, Cell.HARD)


func _connect_secret(r: Rect2i, wall_mat: int) -> void:
	# Find the nearest route cell to the room centre and run a passage toward it.
	var centre := r.get_center()
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	var zone := g.get_stratum(centre.x, centre.y)
	for c in data["route"]:
		if g.get_stratum(c.x, c.y) != zone:
			continue   # never aim a passage through the bedrock between zones
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
			if support.has(cc):
				continue
			if not reserved.has(cc) or Cell.is_solid(g.get_mat(cc.x, cc.y)):
				if g.get_mat(cc.x, cc.y) != Cell.LADDER and g.get_mat(cc.x, cc.y) != Cell.PLATFORM:
					g.put(cc.x, cc.y, Cell.AIR)
		if not r.grow(1).has_point(Vector2i(x, fy)) and not placed_wall and not col_reserved:
			# first free column outside the room: seal it with the secret wall
			for dy in range(-2, 1):
				g.put(x, fy + dy, wall_mat)
			placed_wall = true
		var floor_cell := Vector2i(x, fy + 1)
		# A passage through an existing room must not fill its open floor space.
		if not g.is_solid(x, fy + 1) and not reserved.has(floor_cell) and g.get_mat(x, fy + 1) != Cell.LADDER \
				and space.kind_at(floor_cell) not in ["chamber", "landmark"]:
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
			if support.has(Vector2i(xx, y)):
				continue
			if g.get_mat(xx, y) != Cell.LADDER and g.get_mat(xx, y) != Cell.PLATFORM:
				g.put(xx, y, Cell.AIR)
		if g.get_mat(x, y) != Cell.PLATFORM and not support.has(Vector2i(x, y)):
			g.put(x, y, Cell.LADDER)


# ---------------------------------------------------------------------------
func _loose_ceilings() -> void:
	var counts: Array = Balance.GEN_LOOSE
	for s in Balance.ZONE_COUNT:
		var placed := 0
		var tries := 0
		while placed < int(counts[s]) and tries < 400:
			tries += 1
			var lc := _zone_cell(rng, s, 5, 2, 4, 14)
			var x := lc.x
			var y := lc.y
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


## Inside an anchor, a landmark, or a chamber the guaranteed route crosses.
func _protected_space(c: Vector2i) -> bool:
	var k := space.kind_at(c)
	if k == "anchor" or k == "landmark":
		return true
	for ch in chambers:
		if ch["backbone"] and (ch["rect"] as Rect2i).grow(1).has_point(c):
			return true
	return false


func _free_region(cx: int, cy: int, rx: int, ry: int, need_solid: bool) -> bool:
	# features may not intrude on any claimed footprint (rooms, landmarks, anchors)
	if not space.fits(Rect2i(cx - rx, cy - ry, rx * 2 + 1, ry * 2 + 1), 0):
		return false
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
	var pmask := PackedByteArray()
	pmask.resize(W * H)
	for cl in space.claims:
		if cl["kind"] in ["anchor", "landmark"]:
			var r0: Rect2i = cl["rect"]
			for y in range(maxi(0, r0.position.y), mini(H, r0.end.y)):
				for x in range(maxi(0, r0.position.x), mini(W, r0.end.x)):
					pmask[y * W + x] = 1
	for ch in chambers:
		if ch["backbone"]:
			var r1: Rect2i = (ch["rect"] as Rect2i).grow(1)
			for y in range(maxi(0, r1.position.y), mini(H, r1.end.y)):
				for x in range(maxi(0, r1.position.x), mini(W, r1.end.x)):
					pmask[y * W + x] = 1
	var counts: Array = Balance.GEN_BOULDERS
	var placed_total := 0
	for st in Balance.ZONE_COUNT:
		var placed := 0
		var tries := 0
		while placed < int(counts[st]) and tries < 800:
			tries += 1
			var bc := _zone_cell(rng, st, 4, 1, 8, 16)
			var x := bc.x
			var y := bc.y
			if not g.is_solid(x, y) or g.get_mat(x, y) == Cell.ALLOY:
				continue
			var ok := true
			for yy in range(y + 1, y + 7):
				for xx in range(x - 2, x + 3):
					if g.is_solid(xx, yy) or reserved.has(Vector2i(xx, yy)) or no_feature.has(Vector2i(xx, yy)) or (g.in_bounds(xx, yy) and pmask[yy * W + xx] == 1):
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
	var made := 0
	for z in Balance.ZONE_COUNT:
		var spec: Variant = Balance.GEN_GEODES[z]
		var want: int = rng.randi_range(int(spec[0]), int(spec[1])) if typeof(spec) == TYPE_ARRAY else int(spec)
		var done := 0
		var tries := 0
		while done < want and tries < 200:
			tries += 1
			if _geode(z, made):
				made += 1
				done += 1
	data["geodes"] = made


func _geode(z: int, made: int) -> bool:
	var gc := _zone_cell(rng, z, 7, 6, 8, 14)
	var cx := gc.x
	var cy := gc.y
	var rx := rng.randi_range(3, 5)
	var ry := rng.randi_range(2, 4)
	if not _free_region(cx, cy, rx + 1, ry + 1, false):
		return false
	space.claim(Rect2i(cx - rx - 1, cy - ry - 1, rx * 2 + 3, ry * 2 + 3), "feature", "geode%d" % made)
	var kind := Cell.ORE_COBALT if z == Balance.Z_SPORE else Cell.ORE_AETHER
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
	return true


## Sealed flooded pockets. Treasure lines the floor; breach the wall and the
## water floods out into whatever you have dug.
func _water_pockets() -> void:
	# small groundwater pockets: common but modest, irregular blobs
	var counts: Array = []
	for z in Balance.ZONE_COUNT:
		counts.append(water_rng.randi_range(int(Balance.GEN_POCKETS[z][0]), int(Balance.GEN_POCKETS[z][1])))
	var pockets: Array = []
	for st in Balance.ZONE_COUNT:
		var placed := 0
		var tries := 0
		while placed < counts[st] and tries < 400:
			tries += 1
			var rx := water_rng.randi_range(2, 5)
			var ry := water_rng.randi_range(2, 3)
			var pc := _zone_cell(water_rng, st, 4 + rx, ry + 2, ry + 3, 18)
			var cx := pc.x
			var cy := pc.y
			if not _free_region(cx, cy, rx + 2, ry + 2, true):
				continue
			space.claim(Rect2i(cx - rx - 2, cy - ry - 2, rx * 2 + 5, ry * 2 + 5), "water", "pocket%d" % pockets.size())
			var cells: Array[Vector2i] = []
			var ox := float(water_rng.randi_range(-1, 1))
			var oy := float(water_rng.randi_range(-1, 1)) * 0.5
			for y in range(cy - ry, cy + ry + 1):
				for x in range(cx - rx, cx + rx + 1):
					var dx := (x + 0.5 - cx) / (rx + 0.5)
					var dy := (y + 0.5 - cy) / (ry + 0.5)
					var dx2 := (x + 0.5 - cx - ox * rx * 0.6) / (rx * 0.6 + 0.5)
					var dy2 := (y + 0.5 - cy - oy * ry) / (ry * 0.7 + 0.5)
					if dx * dx + dy * dy <= 0.8 or dx2 * dx2 + dy2 * dy2 <= 1.0:
						cells.append(Vector2i(x, y))
			var fill_from := cy - ry + water_rng.randi_range(0, 2)
			for c in cells:
				g.put(c.x, c.y, Cell.AIR)
				if c.y >= fill_from:
					g.water[g.idx(c.x, c.y)] = Balance.WATER_MAX
			# treasure on the floor, a cracked-looking hint above
			for c in cells:
				if not cells.has(c + Vector2i(0, 1)) and g.get_mat(c.x, c.y + 1) in [Cell.SOFT, Cell.HARD] and water_rng.randf() < 0.5:
					g.ore[g.idx(c.x, c.y + 1)] = Cell.ORE_AETHER if st == 2 or rng.randf() < 0.3 else Cell.ORE_COBALT
			for y in range(cy - ry - 2, cy + ry + 3):
				for x in range(cx - rx - 2, cx + rx + 3):
					no_feature[Vector2i(x, y)] = true
			pockets.append(Rect2i(cx - rx, cy - ry, rx * 2 + 1, ry * 2 + 1))
			var filled := 0
			for c in cells:
				if c.y >= fill_from:
					filled += 1
			data["water_features"].append({"kind": "pocket", "rect": Rect2i(cx - rx, cy - ry, rx * 2 + 1, ry * 2 + 1), "cells": filled, "volume": filled * Balance.WATER_MAX, "head": cy + ry - fill_from + 1})
			placed += 1
	data["water_pockets"] = pockets


## Chamber basins built by the carver: the cathedral lake always fills; a
## terrace's perched basin fills most of the time (a waterfall waiting for its
## sediment lip to be broken).
func _fill_basins() -> void:
	for c in chambers:
		var basin: Array = c.get("basin", [])
		if basin.is_empty():
			continue
		var is_lake: bool = c["arch"] == "cathedral"
		if not is_lake and water_rng.randf() > 0.7:
			continue
		# later passes may have opened the basin's rim: lower the waterline until
		# the body is contained, rather than letting it drain while settling
		var cells: Array = []
		for b in basin:
			if not g.is_solid(b.x, b.y) and not reserved.has(b):
				cells.append(b)
		while not cells.is_empty() and not _contained(cells):
			var top := 1 << 20
			for b in cells:
				top = mini(top, b.y)
			cells = cells.filter(func(b: Vector2i) -> bool: return b.y > top)
		var filled := cells.size()
		if filled < 3:
			continue
		for b in cells:
			g.water[g.idx(b.x, b.y)] = Balance.WATER_MAX
		var r: Rect2i = c["rect"]
		data["water_features"].append({"kind": "lake" if is_lake else "perched_pool", "rect": r, "cells": filled, "volume": filled * Balance.WATER_MAX, "head": 3 if is_lake else 2, "chamber": c["id"]})


## True if water standing in `cells` cannot escape: every open cell reachable
## at or below the waterline stays within a small margin of the body itself.
func _contained(cells: Array) -> bool:
	var top := 1 << 20
	for b in cells:
		top = mini(top, b.y)
	var seen := {}
	var stack: Array = cells.duplicate()
	for b in cells:
		seen[b] = true
	var cap := cells.size() + Balance.GEN_BASIN_LEAK_SLACK
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.y < top or seen.has(n) or not g.in_bounds(n.x, n.y) or g.is_solid(n.x, n.y):
				continue
			seen[n] = true
			if seen.size() > cap:
				return false
			stack.append(n)
	return true


## Every mine gets at least one significant water encounter in the Spore Veins
## (a lake, a reservoir, a flooded cistern), with fallbacks instead of hoping a
## random cavity turns up.
func _ensure_water_encounter() -> void:
	for wf in data["water_features"]:
		var r: Rect2i = wf["rect"]
		if wf["kind"] != "pocket" and int(wf.get("cells", 0)) >= 20 and g.get_stratum(r.get_center().x, r.get_center().y) == Balance.Z_SPORE:
			return
	var lm := Landmarks.new(self, water_rng)
	if OS.get_environment("RD_TRACE") != "":
		print("WATER GUARANTEE: none found, trying fallbacks")
	if lm.floodgate(1, true):
		return
	if lm.cistern():
		return
	lm.buried_reservoir(1)


func _water_in(r: Rect2i) -> int:
	var t := 0
	for y in range(r.position.y - 1, r.end.y + 2):
		for x in range(r.position.x - 1, r.end.x + 1):
			t += g.get_water(x, y)
	return t


## Let every body of water find its level now so the mine starts calm.
func _settle_water() -> void:
	var sim := WaterSim.new(g)
	var before: Array = []
	for wf in data["water_features"]:
		before.append(_water_in(wf["rect"]))
	data["settle_steps"] = sim.settle(600)
	# quench: clear stray 1-2 unit films that would jitter forever, then confirm
	# the whole map is at rest (the generator's water must start calm)
	var quenched := 0
	for k in 8:
		sim.wake_all()
		sim.step()
		if sim.last_moves == 0 and sim.drop_count() == 0:
			break
		for c in sim.active.keys():
			var v := g.get_water(c.x, c.y)
			if v > 0 and v <= 2:
				quenched += v
				g.water[g.idx(c.x, c.y)] = 0
		for k2 in 20:
			sim.step()
			for k3 in 4:
				sim.update_drops(Balance.WATER_TICK / 4.0)
	data["water_quenched"] = quenched
	var leaks: Array = []
	for i in data["water_features"].size():
		var wf: Dictionary = data["water_features"][i]
		var after := _water_in(wf["rect"])
		wf["settled_volume"] = after
		if before[i] > 0 and after < before[i] * 0.85:
			leaks.append("%s %s %d->%d" % [wf["kind"], str(wf["rect"]), before[i], after])
	data["water_leaks"] = leaks
	# features that drained while settling are dry now: do not report them
	var kept: Array = []
	for wf in data["water_features"]:
		if int(wf.get("settled_volume", 1)) > int(wf.get("volume", 0)) * 0.4:
			kept.append(wf)
	data["water_features"] = kept
	if OS.get_environment("RD_TRACE") != "":
		print("SETTLE steps ", data["settle_steps"], " leaks ", leaks)
	if OS.get_environment("RD_TRACE") != "" and data["settle_steps"] >= 600:
		var sample: Array = sim.active.keys().slice(0, 12)
		print("UNSETTLED active=", sim.active.size(), " drops=", sim.drop_count(), " sample ", sample, " moves ", sim.last_moves)
		var c0: Vector2i = sample[0]
		for k in 4:
			for yy in range(c0.y - 3, c0.y + 3):
				var line := ""
				for xx in range(c0.x - 5, c0.x + 6):
					var m := g.get_mat(xx, yy)
					var wv := g.get_water(xx, yy)
					line += ("%3d" % wv) if not Cell.is_solid(m) else "  #"
					if m == Cell.LADDER:
						line[line.length() - 1] = "L"
					if m == Cell.PLATFORM:
						line[line.length() - 1] = "="
				print("  ", yy, line)
			print("  --")
			sim.step()
	g.cell_changed.disconnect(sim._on_cell_changed)
	data["water_total"] = sim.total()
	var lake := 0
	for wf in data["water_features"]:
		if wf["kind"] in ["lake", "reservoir", "flooded_ruin", "cistern"]:
			lake = maxi(lake, int(wf["cells"]))
	data["lake"] = {"cells": lake}


func _landmarks_v2() -> void:
	var lm := Landmarks.new(self, land_rng)
	var cid: String = contract.get("id", "survey")
	var odds: Dictionary = Balance.GEN_LANDMARK_ODDS.duplicate()
	match cid:
		"gas":
			odds["vent_cluster"] = 1.0
		"rich":
			odds["hanging_gallery"] = 1.0
			odds["floodgate"] = 0.8
		"quiet":
			odds["flooded_machinery"] = 0.4
	# the wings carry their biome's signature set pieces
	var channels := 0
	for k in land_rng.randi_range(int(Balance.GEN_AQUEDUCT_CHANNELS[0]), int(Balance.GEN_AQUEDUCT_CHANNELS[1])):
		if lm.aqueduct_channel():
			channels += 1
	data["aqueduct_channels"] = channels
	if land_rng.randf() < 0.8:
		lm.floodgate(Balance.Z_AQUEDUCT, true)
	if land_rng.randf() < 0.6:
		lm.cistern(Balance.Z_AQUEDUCT)
	if land_rng.randf() < 0.5:
		lm.flooded_machinery(Balance.Z_AQUEDUCT)
	var galleries := 0
	for k in land_rng.randi_range(1, 2):
		if lm.hanging_gallery(Balance.Z_CRYSTAL):
			galleries += 1
	data["crystal_galleries"] = galleries
	if land_rng.randf() < 0.5:
		lm.survey_post(Balance.Z_CRYSTAL)
	# a deterministic but shuffled order, so the same few don't always win space
	var order: Array = ["floodgate", "flooded_machinery", "hanging_gallery", "cistern", "survey_post", "vent_cluster"]
	for i in range(order.size() - 1, 0, -1):
		var j := land_rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	for kind in order:
		if land_rng.randf() > float(odds[kind]):
			continue
		match kind:
			"floodgate":
				lm.floodgate(land_rng.randi_range(0, 1))
			"flooded_machinery":
				lm.flooded_machinery(Balance.Z_ENGINE)
			"hanging_gallery":
				lm.hanging_gallery(land_rng.randi_range(0, 1))
			"cistern":
				lm.cistern()
			"survey_post":
				lm.survey_post(land_rng.randi_range(0, 2))
			"vent_cluster":
				lm.vent_cluster()
				if cid == "gas":
					lm.vent_cluster()
	# every mine gets at least two v2 landmarks: fall back to the compact ones
	var placed := 0
	for l in data["landmarks"]:
		if not (l["kind"] in ["fossil_grotto", "miner_camp", "cobalt_vault"]):
			placed += 1
	for kind in ["survey_post", "hanging_gallery", "cistern", "survey_post", "vent_cluster"]:
		if placed >= Balance.GEN_MIN_LANDMARKS:
			break
		var ok := false
		match kind:
			"survey_post":
				ok = lm.survey_post(land_rng.randi_range(0, 1))
			"hanging_gallery":
				ok = lm.hanging_gallery(land_rng.randi_range(0, 1))
			"cistern":
				ok = lm.cistern()
			"vent_cluster":
				ok = lm.vent_cluster()
		if ok:
			placed += 1


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
	## Geological ore: background veins plus structures that tell a story and
	## reward exploration (seams on chamber walls, sparse fault veins, a fossil
	## band in the sediment, exposed hints leading into richer hidden pockets).
	var mult: float = contract.get("ore", 1.0)
	var counts: Array = []
	for z in Balance.ZONE_COUNT:
		counts.append(int(float(Balance.GEN_ORE_VEINS[z]) * mult))
	for s in Balance.ZONE_COUNT:
		var placed := 0
		var tries := 0
		while placed < counts[s] and tries < 2000:
			tries += 1
			var oc := _zone_cell(ore_rng, s, 1, 0, 1, 12)
			var x := oc.x
			var y := oc.y
			if not _ore_ok(x, y):
				continue
			if ore_rng.randf() < 0.7 and not _near_open(x, y, 3):
				continue
			var kind := _pick_ore(s, y)
			var length := ore_rng.randi_range(2, 6) if kind != Cell.ORE_AETHER else ore_rng.randi_range(1, 3)
			var cx := x
			var cy := y
			for k in length:
				if _ore_ok(cx, cy):
					g.ore[g.idx(cx, cy)] = kind
				var d: Vector2i = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][ore_rng.randi_range(0, 3)]
				cx += d.x
				cy += d.y
			placed += 1
	data["ore_structures"] = {"seams": 0, "faults": 0, "hints": 0, "fossil_band": 0}
	# contact seams: ore following a chamber wall
	for c in chambers:
		for k in (1 if ore_rng.randf() < 0.5 else 2):
			if _contact_seam(c):
				data["ore_structures"]["seams"] += 1
	# fault veins: long, sparse, angled lines through rock
	for s in Balance.ZONE_COUNT:
		for k in ore_rng.randi_range(1, 2):
			var p := Vector2(_zone_cell(ore_rng, s, 3, 0, 2, 14))
			var ang := ore_rng.randf_range(0.5, 1.1) * (1.0 if ore_rng.randf() < 0.5 else -1.0)
			var dir := Vector2(cos(ang), sin(ang))
			var kind: int = int(Balance.GEN_ZONE_ORE[s]) if ore_rng.randf() < 0.8 else _pick_ore(s, int(p.y))
			for t in ore_rng.randi_range(12, 22):
				var c := Vector2i(int(round(p.x + dir.x * t)), int(round(p.y + dir.y * t)))
				if _ore_ok(c.x, c.y) and ore_rng.randf() < 0.42 * mult:
					g.ore[g.idx(c.x, c.y)] = kind
			data["ore_structures"]["faults"] += 1
	# fossil band: one sedimentary horizon in the Dustworks
	var by := ore_rng.randi_range(22, Balance.STRATUM_ROWS[1] - 12)
	for x in range(Balance.CORE_X0 + 1, Balance.CORE_X1 - 1):
		var y := by + int(round(sin(x * 0.2) * 1.5))
		if _ore_ok(x, y) and ore_rng.randf() < 0.09:
			g.ore[g.idx(x, y)] = Cell.ORE_FOSSIL
			data["ore_structures"]["fossil_band"] += 1
	# hints: one exposed crystal on a chamber wall, a richer pocket behind it
	var premium := Cell.ORE_AETHER if contract.get("id", "") == "rich" else -1
	for c in chambers:
		if ore_rng.randf() < 0.55 and _hint_pocket(c, premium):
			data["ore_structures"]["hints"] += 1


func _wall_cells(c: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r: Rect2i = (c["rect"] as Rect2i).grow(2)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if _ore_ok(x, y) and _near_open(x, y, 1):
				out.append(Vector2i(x, y))
	return out


func _contact_seam(c: Dictionary) -> bool:
	var walls := _wall_cells(c)
	if walls.is_empty():
		return false
	var set_: Dictionary = {}
	for w in walls:
		set_[w] = true
	var cur: Vector2i = walls[ore_rng.randi_range(0, walls.size() - 1)]
	var s: int = c["stratum"]
	var kind: int = [Cell.ORE_COPPER, Cell.ORE_COBALT, Cell.ORE_AETHER if ore_rng.randf() < 0.5 else Cell.ORE_COBALT, Cell.ORE_COBALT, Cell.ORE_AETHER if ore_rng.randf() < 0.6 else Cell.ORE_COBALT][s]
	var length := ore_rng.randi_range(4, 8)
	var placed := 0
	for k in length:
		if ore_rng.randf() < 0.75 and _ore_ok(cur.x, cur.y):
			g.ore[g.idx(cur.x, cur.y)] = kind
			placed += 1
		set_.erase(cur)
		var moved := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			if set_.has(cur + d):
				cur = cur + d
				moved = true
				break
		if not moved:
			break
	return placed > 0


func _hint_pocket(c: Dictionary, premium: int) -> bool:
	var walls := _wall_cells(c)
	if walls.is_empty():
		return false
	var w: Vector2i = walls[ore_rng.randi_range(0, walls.size() - 1)]
	# direction into the rock: away from the nearest open neighbour
	var into := Vector2i.ZERO
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not g.is_solid(w.x + d.x, w.y + d.y):
			into = -d
			break
	if into == Vector2i.ZERO:
		return false
	var s: int = c["stratum"]
	var hint_kind: int = [Cell.ORE_COPPER, Cell.ORE_COBALT, Cell.ORE_COBALT, Cell.ORE_COPPER, Cell.ORE_COBALT][s]
	var rich_kind: int = premium if premium > 0 else [Cell.ORE_COBALT, Cell.ORE_AETHER, Cell.ORE_AETHER, Cell.ORE_AETHER, Cell.ORE_AETHER][s]
	g.ore[g.idx(w.x, w.y)] = hint_kind
	var centre := w + into * 3
	var made := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p := centre + Vector2i(dx, dy)
			if _ore_ok(p.x, p.y) and not _near_open(p.x, p.y, 1) and ore_rng.randf() < 0.7:
				g.ore[g.idx(p.x, p.y)] = rich_kind
				made += 1
	return made > 0


func _ore_ok(x: int, y: int) -> bool:
	var m := g.get_mat(x, y)
	return (m == Cell.SOFT or m == Cell.HARD) and not no_feature.has(Vector2i(x, y)) \
		and not g.has_flag(x, y, Cell.F_PROTECTED) and g.get_ore(x, y) == 0


func _pick_ore(s: int, y: int) -> int:
	var r := ore_rng.randf()
	match s:
		0:
			return Cell.ORE_FOSSIL if r < 0.08 else (Cell.ORE_COBALT if r < 0.14 and y > 50 else Cell.ORE_COPPER)
		1:
			return Cell.ORE_AETHER if r < 0.06 else (Cell.ORE_COPPER if r < 0.3 else Cell.ORE_COBALT)
		Balance.Z_AQUEDUCT:
			return Cell.ORE_AETHER if r < 0.12 else (Cell.ORE_COPPER if r < 0.3 else Cell.ORE_COBALT)
		Balance.Z_CRYSTAL:
			return Cell.ORE_COBALT if r < 0.5 else Cell.ORE_AETHER
		_:
			return Cell.ORE_COBALT if r < 0.42 else Cell.ORE_AETHER


func _gas() -> void:
	## Background gas: fewer than before (vent clusters carry the drama) and
	## never within two cells of the guaranteed route, so it is opt-in.
	var mult: float = contract.get("gas", 1.0)
	var counts: Array = []
	for z in Balance.ZONE_COUNT:
		counts.append(int(round(float(Balance.GEN_GAS[z]) * mult)))
	var anchors: Array = [data["spawn"], data["relay"], data["door_outside"]]
	for gate in data["gates"]:
		anchors.append(gate["lift"])
	for s in Balance.ZONE_COUNT:
		var placed := 0
		var tries := 0
		while placed < counts[s] and tries < 1500:
			tries += 1
			var gc := _zone_cell(enc_rng, s, 2, 1, 2, 16)
			var x := gc.x
			var y := gc.y
			var far := true
			for a in anchors:
				if absi(a.x - x) + absi(a.y - y) < 9:
					far = false
			if not far or not _ore_ok(x, y) or not _near_open(x, y, 1) or _near_route(x, y, 2):
				continue
			var n := enc_rng.randi_range(2, 4)
			var cx := x
			var cy := y
			for k in n:
				if _ore_ok(cx, cy) and not _near_route(cx, cy, 2):
					g.put(cx, cy, Cell.GAS)
					no_feature[Vector2i(cx, cy)] = true
				var d: Vector2i = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][enc_rng.randi_range(0, 3)]
				cx += d.x
				cy += d.y
			placed += 1


func _near_route(x: int, y: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if reserved.has(Vector2i(x + dx, y + dy)):
				return true
	return false


func _enemies() -> void:
	## Crawlers by role first (a guard in optional chambers, a patrol on backbone
	## chambers), then the remaining budget as wanderers in natural caves.
	var mult: float = contract.get("crawlers", 1.0)
	var counts: Array = []
	for z in Balance.ZONE_COUNT:
		counts.append(int(round(float(Balance.GEN_CRAWLERS[z]) * mult)))
	var total := 0
	for e in data["entities"]:
		if e["type"] == "crawler":
			total += 1
			counts[g.get_stratum(e["cell"].x, e["cell"].y)] -= 1
	var spawn: Vector2i = data["spawn"]
	var relay: Vector2i = data["relay"]
	var order: Array = chambers.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := enc_rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	for c in order:
		var s: int = c["stratum"]
		if counts[s] <= 0 or total >= Balance.CRAWLER_CAP or c.get("vents", false):
			continue
		var r: Rect2i = c["rect"]
		var floor_cells: Array[Vector2i] = []
		for y in range(r.position.y, r.end.y + 2):
			for x in range(r.position.x, r.end.x):
				if _crawler_ok(x, y, spawn, relay):
					floor_cells.append(Vector2i(x, y))
		if floor_cells.is_empty():
			continue
		var cell: Vector2i = floor_cells[enc_rng.randi_range(0, floor_cells.size() - 1)]
		data["entities"].append({"type": "crawler", "cell": cell, "role": "patrol" if c["backbone"] else "guard"})
		counts[s] -= 1
		total += 1
	for s in Balance.ZONE_COUNT:
		var tries := 0
		while counts[s] > 0 and tries < 800 and total < Balance.CRAWLER_CAP:
			tries += 1
			var ec := _zone_cell(enc_rng, s, 2, 1, 2, 20)
			var x := ec.x
			var y := ec.y
			if not _crawler_ok(x, y, spawn, relay):
				continue
			data["entities"].append({"type": "crawler", "cell": Vector2i(x, y), "role": "wander"})
			counts[s] -= 1
			total += 1


func _crawler_ok(x: int, y: int, spawn: Vector2i, relay: Vector2i) -> bool:
	if g.is_solid(x, y) or not g.is_solid(x, y + 1) or g.get_mat(x, y) != Cell.AIR:
		return false
	if absi(x - spawn.x) + absi(y - spawn.y) < 26 or absi(x - relay.x) + absi(y - relay.y) < 10:
		return false
	if g.has_flag(x, y, Cell.F_NO_RUBBLE) or g.get_water(x, y) > 0:
		return false
	for e in data["entities"]:
		if e["type"] == "crawler" and absi(e["cell"].x - x) + absi(e["cell"].y - y) < 6:
			return false
	return true


func _finalize_hp() -> void:
	for i in g.mat.size():
		g.hp[i] = Cell.max_hp(g.mat[i])


# ---------------------------------------------------------------------------
func door_open_cells() -> Dictionary:
	var d: Dictionary = {}
	for c in data.get("door_cells", []):
		d[c] = true
	return d


## A one-cell-wide strip of diggable rock between two unbreakable walls is a
## pit: drill down into it with an empty scaffold meter and there is no wall to
## cut steps into. Such slivers become part of the wall they touch.
func _seal_slivers() -> void:
	var sealed_n := 0
	for y in range(2, H - 2):
		for x in range(1, W - 1):
			var m := g.get_mat(x, y)
			if not (m == Cell.SOFT or m == Cell.HARD or m == Cell.LOOSE or m == Cell.CRACKED) or g.has_flag(x, y, Cell.F_PROTECTED):
				continue
			if _unbreakable(x - 1, y) and _unbreakable(x + 1, y):
				var alloy := g.get_mat(x - 1, y) == Cell.ALLOY or g.get_mat(x + 1, y) == Cell.ALLOY
				g.put(x, y, Cell.ALLOY if alloy else Cell.BEDROCK)
				sealed_n += 1
	data["slivers_sealed"] = sealed_n


func _unbreakable(x: int, y: int) -> bool:
	if not g.in_bounds(x, y):
		return true
	var m := g.get_mat(x, y)
	return m == Cell.ALLOY or m == Cell.BEDROCK or (Cell.is_solid(m) and g.has_flag(x, y, Cell.F_PROTECTED))


## The mine must be completable with starting gear (DigCheck: drill plus
## Rubble Ladders raised where rock is in reach), inside the fairness budget,
## in both directions. The no-ladder numbers are kept as diagnostics.
func _dig_valid() -> bool:
	var dc: DigCheck
	var from_spawn: PackedFloat32Array
	var escape: PackedByteArray
	var clean := false
	# audit for softlock traps (places you can get into but never out of) and
	# seal any that turn up; re-audit, since sealing changes the terrain
	for round in 3:
		dc = DigCheck.new(g, door_open_cells())
		dc.allow_ladder = true
		from_spawn = dc.costs_from(data["spawn"])
		escape = dc.escape_set(data["lift"])
		var sealed_n := _seal_traps(from_spawn, escape)
		if sealed_n == 0:
			clean = true
			break
		if sealed_n < 0:
			break   # a trap on the route itself: cannot be sealed, needs repair
		data["traps_sealed"] = int(data.get("traps_sealed", 0)) + sealed_n
	if not clean:
		return false
	var outside: Vector2i = data["door_outside"]
	data["dig_down_s"] = GenMetrics._near(dc, from_spawn, outside)
	# every wing entrance must be reachable on the way down
	var gates_ok := true
	for gate in data["gates"]:
		if GenMetrics._near(dc, from_spawn, gate["lift"]) < 0.0:
			gates_ok = false
	# the way out may use Rubble Ladders (priced in seconds, see DigCheck)
	var with_ladder := dc.costs_from(outside)
	data["climb_up_s"] = GenMetrics._near(dc, with_ladder, data["lift"])
	data["climb_relay_s"] = GenMetrics._near(dc, with_ladder, data["relay"])
	data["dig_relic_s"] = GenMetrics._near(dc, with_ladder, data["relic"])
	data["finds"] = ZoneFinds.place(self, from_spawn, escape)
	return gates_ok and data["dig_down_s"] >= 0.0 and data["dig_down_s"] <= Balance.FAIR_DIG_BUDGET_DOWN \
		and data["climb_up_s"] >= 0.0 and data["climb_up_s"] <= Balance.FAIR_DIG_BUDGET_UP \
		and data["dig_relic_s"] >= 0.0 and data["climb_relay_s"] >= 0.0


## Turn every trap cell into part of the unbreakable wall beside it. Returns the
## number of cells sealed, 0 when there are no traps, -1 if one cannot be sealed.
func _seal_traps(from_spawn: PackedFloat32Array, escape: PackedByteArray) -> int:
	var n := 0
	var filled: Dictionary = {}
	for i in W * H:
		if from_spawn[i] >= DigCheck.UNREACHED or escape[i] == 1:
			continue
		var c := Vector2i(i % W, i / W)
		if reserved.has(c) or g.has_flag(c.x, c.y, Cell.F_PROTECTED):
			return -1
		var alloy := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0)]:
			if g.get_mat(c.x + d.x, c.y + d.y) == Cell.ALLOY:
				alloy = true
		g.put(c.x, c.y, Cell.ALLOY if alloy else Cell.BEDROCK)
		g.water[i] = 0
		g.ore[i] = 0
		no_feature[c] = true
		filled[c] = true
		n += 1
	if n > 0:
		# Sealing feet can cut off the remaining air above them. Fill that
		# enclosed space too, rather than leaving an inaccessible cavity.
		for c in RouteCheck.sealed_pockets(g, data["spawn"], door_open_cells()):
			if reserved.has(c) or g.has_flag(c.x, c.y, Cell.F_PROTECTED):
				return -1
			var wall := Cell.BEDROCK
			for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				if g.get_mat(c.x + d.x, c.y + d.y) == Cell.ALLOY:
					wall = Cell.ALLOY
			g.put(c.x, c.y, wall) # put clears ore and sets the new material's hp
			g.water[g.idx(c.x, c.y)] = 0
			no_feature[c] = true
			filled[c] = true
			n += 1
		# Remove only entities affected by this sealing, including modules.
		for e in data["entities"].duplicate():
			if filled.has(e["cell"]) or filled.has(e.get("module", Vector2i(-1, -1))):
				data["entities"].erase(e)
	return n


func _validate_and_repair() -> void:
	var outside: Vector2i = data["door_outside"]
	for attempt in (0 if no_repair else 3):
		if _dig_valid():
			data["valid"] = true
			return
		repairs += 1
		# Repair: re-carve the guaranteed route (later passes may have touched it)
		# and drop a straight ladder spine from the shaft bottom to the door.
		var pts: Array[Vector2i] = [data["shaft_bottom"], Vector2i(outside.x, data["shaft_bottom"].y), outside]
		for i in range(pts.size() - 1):
			_carve_between_straight(pts[i], pts[i + 1])
	data["valid"] = _dig_valid()


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
	for find in data.get("finds", []):
		occupied[find.cell] = true
	# Upgrade a suitable camp's existing decorative crate rather than duplicating
	# it. Some seeds carve the route through it; those keep their old decoration.
	for entity in data.entities.duplicate():
		if entity.type == "crate" and not reserved.has(entity.cell) and g.get_mat(entity.cell.x, entity.cell.y) == Cell.AIR:
			data.water_props.append({"kind": "crate", "cell": entity.cell})
			data.entities.erase(entity)
	for lp in data.get("lm_props", []):
		if data.water_props.size() < Balance.DEBRIS_GENERATED_CAP:
			data.water_props.append(lp)
			occupied[lp.cell] = true
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
		data.water_props.append({"kind": _prop_kind(c, props_rng), "cell": c})


## Props have roles: floaters where water can move them, heavy stone on dry
## slopes and drop zones, scrap/canisters around Engine machinery, crates in the
## Dustworks works.
func _prop_kind(c: Vector2i, prng: RandomNumberGenerator) -> String:
	var wet := false
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if g.get_water(c.x + dx, c.y + dy) > 0:
				wet = true
	if wet:
		return "crate" if prng.randf() < 0.55 else "canister"
	var s := g.get_stratum(c.x, c.y)
	if s == Balance.Z_ENGINE:
		return "scrap" if prng.randf() < 0.6 else "canister"
	var k := space.kind_at(c)
	if s == 0 and (k == "chamber" or k == "landmark") and prng.randf() < 0.6:
		return "crate"
	return "stone" if prng.randf() < 0.7 else "crate"
