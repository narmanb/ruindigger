class_name GenMetrics
extends RefCounted
## Diagnostics for a generated mine. Validity is RouteCheck's job; these numbers
## describe *what kind of place* was generated, so sweeps can catch dull,
## unbalanced or broken layouts (and compare generator versions).


static func compute(data: Dictionary) -> Dictionary:
	var g: TerrainGrid = data["grid"]
	var m := {}
	var doors: Dictionary = {}
	for c in data.get("door_cells", []):
		doors[c] = true
	m["route_len"] = route_length(g, data["spawn"], data["door_outside"], doors)
	m["first_reward"] = first_reward_distance(g, data)
	for s in 3:
		var st := _stratum_shape(g, s)
		m["s%d_spacious" % s] = st["spacious"]
		m["s%d_hrun" % s] = st["hrun"]
		m["s%d_vrun" % s] = st["vrun"]
		m["s%d_vmax" % s] = st["vmax"]
		m["s%d_open" % s] = st["open"]
	var w := _water(g)
	m["water_units"] = w["units"]
	m["water_bodies"] = w["bodies"]
	m["water_largest"] = w["largest"]
	m["water_max_column"] = w["max_column"]
	var o := _ore(g)
	m["ore_value"] = o["value"]
	for k in o["by_type"].keys():
		m["ore_%s" % Balance.ORE[k]["name"].to_lower()] = o["by_type"][k]
	m["props"] = data.get("water_props", []).size()
	var crawlers := 0
	var sentries := 0
	for e in data["entities"]:
		if e["type"] == "crawler":
			crawlers += 1
		elif e["type"] == "sentry":
			sentries += 1
	m["crawlers"] = crawlers
	m["sentries"] = sentries
	# planner-provided structure (absent on the legacy generator)
	var plan: Dictionary = data.get("plan", {})
	m["chambers"] = plan.get("chambers", []).size()
	m["archetypes"] = plan.get("archetype_count", 0)
	m["branches"] = plan.get("branches", 0)
	m["loops"] = plan.get("loops", 0)
	m["landmarks"] = data.get("landmarks", []).size()
	m["water_features"] = data.get("water_features", []).size()
	m["gen_ms"] = data.get("gen_ms", 0)
	return m


## Shortest guaranteed-traversal path (RouteCheck model) from spawn to target.
static func route_length(g: TerrainGrid, a: Vector2i, b: Vector2i, open_cells: Dictionary) -> int:
	var dist: Dictionary = {a: 0}
	var q: Array[Vector2i] = [a]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if c == b or (absi(c.x - b.x) <= 1 and absi(c.y - b.y) <= 1):
			return dist[c]
		for n in RouteCheck._neighbours(g, c, open_cells):
			if not dist.has(n):
				dist[n] = dist[c] + 1
				q.append(n)
	return -1


## Walking distance (open cells) from spawn to the first exposed ore or cache.
static func first_reward_distance(g: TerrainGrid, data: Dictionary) -> int:
	var caches: Dictionary = {}
	for e in data["entities"]:
		if e["type"] == "cache":
			caches[e["cell"]] = true
	var start: Vector2i = data["spawn"]
	var dist: Dictionary = {start: 0}
	var q: Array[Vector2i] = [start]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if caches.has(c):
			return dist[c]
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if g.is_solid(n.x, n.y):
				if g.get_ore(n.x, n.y) != 0:
					return dist[c] + 1
				continue
			if not dist.has(n):
				dist[n] = dist[c] + 1
				q.append(n)
	return -1


static func _stratum_shape(g: TerrainGrid, s: int) -> Dictionary:
	var y0: int = maxi(12, Balance.STRATUM_ROWS[s])
	var y1: int = (Balance.STRATUM_ROWS[s + 1] if s < 2 else g.h - 6)
	var open := 0
	var spacious := 0
	var hruns: Array[int] = []
	var vruns: Array[int] = []
	for y in range(y0, y1):
		var run := 0
		for x in range(2, g.w - 1):
			var o := not g.is_solid(x, y)
			if o:
				open += 1
				run += 1
				var cnt := 0
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						if not g.is_solid(x + dx, y + dy):
							cnt += 1
				if cnt >= 20:
					spacious += 1
			elif run > 0:
				hruns.append(run)
				run = 0
	var vmax := 0
	for x in range(2, g.w - 2):
		var run2 := 0
		for y in range(y0, y1 + 1):
			if y < y1 and not g.is_solid(x, y) and g.get_mat(x, y) != Cell.LADDER:
				run2 += 1
			elif run2 > 0:
				vruns.append(run2)
				vmax = maxi(vmax, run2)
				run2 = 0
	return {"open": open, "spacious": spacious, "hrun": _mean(hruns), "vrun": _mean(vruns), "vmax": vmax}


static func _mean(a: Array[int]) -> float:
	if a.is_empty():
		return 0.0
	var t := 0
	for v in a:
		t += v
	return snappedf(float(t) / a.size(), 0.01)


static func _water(g: TerrainGrid) -> Dictionary:
	var units := 0
	var seen: Dictionary = {}
	var bodies := 0
	var largest := 0
	var max_col := 0
	for x in g.w:
		var col := 0
		for y in g.h:
			var v := g.get_water(x, y)
			units += v
			if v >= Balance.WATER_MAX / 2:
				col += 1
				max_col = maxi(max_col, col)
			else:
				col = 0
	for y in g.h:
		for x in g.w:
			var c := Vector2i(x, y)
			if seen.has(c) or g.get_water(x, y) < Balance.WATER_MAX / 2:
				continue
			bodies += 1
			var size := 0
			var q: Array[Vector2i] = [c]
			seen[c] = true
			while not q.is_empty():
				var cc: Vector2i = q.pop_back()
				size += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = cc + d
					if not seen.has(n) and g.get_water(n.x, n.y) >= Balance.WATER_MAX / 2:
						seen[n] = true
						q.append(n)
			largest = maxi(largest, size)
	return {"units": units, "bodies": bodies, "largest": largest, "max_column": max_col}


static func _ore(g: TerrainGrid) -> Dictionary:
	var value := 0
	var by_type: Dictionary = {}
	for i in g.ore.size():
		var o: int = g.ore[i]
		if o == 0 or not Cell.is_solid(g.mat[i]):
			continue
		var info: Dictionary = Balance.ORE[o]
		value += int(info["value"]) * int(info["drops"])
		by_type[o] = int(by_type.get(o, 0)) + 1
	return {"value": value, "by_type": by_type}
