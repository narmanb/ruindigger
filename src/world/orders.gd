class_name Orders
extends RefCounted
## Short-term goals for one dive (S2 of the fun pass). Orders are generated
## from what the map really holds, are optional, and pay on extraction.
##
## Kinds:
##   ore      bring back N units of an ore type (any grade)
##   value    extract with ore worth at least N credits
##   depth    reach row N (stored in cells, shown in metres)
##   keepsake recover a zone keepsake
##   terrain  kill N enemies with the terrain (rubble, gas, lava, props...)
##
## An order is a Dictionary: {kind, need, have, reward, done, text, ore?}.
## `done` latches for live goals (depth, keepsake, terrain); ore and value are
## judged on what the rack holds at extraction.

const TERRAIN_SOURCES := ["rubble", "gas", "lava", "prop", "water", "steam", "flood"]


static func generate(data: Dictionary, grid: TerrainGrid, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x6f726472
	# what the map holds: ore units by type, and their graded value
	var units: Dictionary = {}
	var total_value := 0
	for i in grid.ore.size():
		var o := int(grid.ore[i])
		if o == 0 or not Balance.ORE.has(o):
			continue
		var n: int = int(Balance.ORE[o]["drops"])
		units[o] = int(units.get(o, 0)) + n
		var zone := maxi(0, int(grid.stratum[i]))
		total_value += Balance.ore_value(Balance.ore_key(o, zone)) * n
	var pool: Array = []
	# ore: something worth chasing, never more than a fair share of the map
	var ore_choices: Array = []
	for o in [Cell.ORE_COBALT, Cell.ORE_AETHER, Cell.ORE_FOSSIL]:
		if int(units.get(o, 0)) >= 10:
			ore_choices.append(o)
	if not ore_choices.is_empty():
		var o: int = ore_choices[rng.randi_range(0, ore_choices.size() - 1)]
		var need := clampi(int(round(int(units[o]) * Balance.ORDER_ORE_SHARE)), 4, 24)
		pool.append({"kind": "ore", "ore": o, "need": need, "reward": Balance.ORDER_REWARD["ore"] + need * 4})
	if total_value > 0:
		# never more than a starting-sized rack of average ore could hold
		var cap_v := Balance.cargo_capacity(0) * Balance.ORDER_VALUE_PER_SLOT
		var need_v := clampi(int(round(minf(total_value * Balance.ORDER_VALUE_SHARE, cap_v) / 10.0)) * 10, 100, cap_v)
		pool.append({"kind": "value", "need": need_v, "reward": Balance.ORDER_REWARD["value"]})
	# depth: the top of a deeper zone
	var rows: Array = []
	for z in data.get("zones", []):
		if int(z["id"]) >= 2:
			rows.append((z["rect"] as Rect2i).position.y + 2)
	if not rows.is_empty():
		var row: int = rows[rng.randi_range(0, rows.size() - 1)]
		pool.append({"kind": "depth", "need": row, "reward": Balance.ORDER_REWARD["depth"]})
	if not data.get("finds", []).is_empty():
		pool.append({"kind": "keepsake", "need": 1, "reward": Balance.ORDER_REWARD["keepsake"]})
	var crawlers := 0
	for e in data.get("entities", []):
		if e["type"] in ["crawler", "sentry"]:
			crawlers += 1
	if crawlers >= 6:
		pool.append({"kind": "terrain", "need": 2, "reward": Balance.ORDER_REWARD["terrain"]})
	# a seeded shuffle, then take the first few
	for k in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp: Dictionary = pool[k]
		pool[k] = pool[j]
		pool[j] = tmp
	var out: Array = []
	for o2: Dictionary in pool:
		if out.size() >= Balance.ORDER_COUNT:
			break
		o2["have"] = 0
		o2["done"] = false
		o2["text"] = describe(o2)
		out.append(o2)
	return out


static func describe(o: Dictionary) -> String:
	match String(o["kind"]):
		"ore":
			return "Bring back %d %s" % [int(o["need"]), String(Balance.ORE[int(o["ore"])]["name"]).to_lower()]
		"value":
			return "Extract %d CR ore" % int(o["need"])
		"depth":
			return "Reach %d m" % int((int(o["need"]) - 9) * Balance.METERS_PER_CELL)
		"keepsake":
			return "Recover a keepsake"
		"terrain":
			return "%d terrain kills" % int(o["need"])
	return "?"


## Progress right now for one order, from the run state.
static func progress(o: Dictionary, run: Dictionary) -> int:
	match String(o["kind"]):
		"ore":
			var n := 0
			var cargo: Dictionary = run.get("cargo", {})
			for k in cargo.keys():
				if Balance.ore_base(int(k)) == int(o["ore"]):
					n += int(cargo[k])
			return n
		"value":
			return Game.cargo_value(run.get("cargo", {}))
		"depth":
			return int(run.get("max_depth", 0))
		"keepsake":
			return (run.get("finds", []) as Array).size()
		"terrain":
			return int(run.get("terrain_kills", 0))
	return 0


static func progress_text(o: Dictionary, run: Dictionary) -> String:
	if satisfied(o, run):
		return "DONE"
	match String(o["kind"]):
		"depth":
			return "%d/%d m" % [maxi(0, int((progress(o, run) - 9) * Balance.METERS_PER_CELL)), int((int(o["need"]) - 9) * Balance.METERS_PER_CELL)]
		"keepsake":
			return "0/1"
	return "%d/%d" % [progress(o, run), int(o["need"])]


static func latches(o: Dictionary) -> bool:
	return String(o["kind"]) in ["depth", "keepsake", "terrain"]


## Update progress; returns orders that were just completed (live kinds only).
static func update(run: Dictionary) -> Array:
	var fresh: Array = []
	for o: Dictionary in run.get("orders", []):
		o["have"] = progress(o, run)
		if latches(o) and not bool(o["done"]) and int(o["have"]) >= int(o["need"]):
			o["done"] = true
			fresh.append(o)
	return fresh


static func satisfied(o: Dictionary, run: Dictionary) -> bool:
	if latches(o):
		return bool(o["done"])
	return progress(o, run) >= int(o["need"])


## Credits for the orders met at extraction.
static func payout(run: Dictionary) -> int:
	var total := 0
	for o: Dictionary in run.get("orders", []):
		if satisfied(o, run):
			total += int(o["reward"])
	return total
