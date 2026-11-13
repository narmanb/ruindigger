class_name ZoneFinds
extends RefCounted
## Optional, non-colliding collectibles. Never edits terrain or consumes a
## generator RNG stream. Uses the final route audit to guarantee a way out.

## Run relics: `count` spots you can reach and still get out from, dry, on a
## floor, away from every entity and each other. Picks which relics appear from
## the seed too. Never edits terrain. Works for any generator's grid.
static func relics(g: TerrainGrid, reachable: PackedFloat32Array, escape: PackedByteArray, seed_value: int, count: int, entities: Array, avoid: Array, pair_first: bool = false) -> Array:
	var occupied: Dictionary = {}
	for e in entities:
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				occupied[e["cell"] + Vector2i(dx, dy)] = true
	var cands: Array = []
	for y in range(4, g.h - 4):
		for x in range(4, g.w - 4):
			var i := g.idx(x, y)
			if reachable[i] >= DigCheck.UNREACHED or escape[i] == 0:
				continue
			if g.get_mat(x, y) != Cell.AIR or g.get_mat(x, y - 1) != Cell.AIR or not g.is_solid(x, y + 1):
				continue
			if g.get_mat(x, y + 1) in [Cell.GAS, Cell.LOOSE] or g.water[i] > 0 or g.lava[i] > 0 or g.lava[i + g.w] > 0:
				continue
			var c := Vector2i(x, y)
			if occupied.has(c) or g.get_stratum(x, y) < 0:
				continue
			# prefer the far end of the map from the spawn: deeper is rarer
			var score: int = (hash("%d:relic:%d" % [seed_value, i]) & 0xffff) + int(reachable[i] * 40.0)
			cands.append([score, c])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var picked: Array = []
	for cand in cands:
		if picked.size() >= count:
			break
		var c: Vector2i = cand[1]
		var ok := true
		for p in picked + avoid:
			if Vector2(c - (p as Vector2i)).length() < Balance.RUN_RELIC_SEP:
				ok = false
				break
		if ok:
			picked.append(c)
	var ids: Array = []
	for k in Balance.RUN_RELICS.size():
		ids.append(k)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x72656c63
	for k in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp: int = ids[k]
		ids[k] = ids[j]
		ids[j] = tmp
	var out: Array = []
	var next := 0
	for k in picked.size():
		var c: Vector2i = picked[k]
		var mate := Vector2i(-1, -1)
		if pair_first and k == 0:
			# a choice: a second, different relic three cells along the same
			# floor. Taking one makes the other crumble.
			for dx in [3, -3, 4, -4]:
				var m := Vector2i(c.x + dx, c.y)
				var i := g.idx(m.x, m.y)
				if g.in_bounds(m.x, m.y) and reachable[i] < DigCheck.UNREACHED and escape[i] == 1 and g.get_mat(m.x, m.y) == Cell.AIR \
						and g.get_mat(m.x, m.y - 1) == Cell.AIR and g.is_solid(m.x, m.y + 1) and g.water[i] == 0 and g.lava[i] == 0 and g.lava[i + g.w] == 0 \
						and not occupied.has(m) and not (g.get_mat(m.x, m.y + 1) in [Cell.GAS, Cell.LOOSE]):
					mate = m
					break
		var group := 1 if mate.x >= 0 else 0
		out.append({"id": ids[next % ids.size()], "cell": c, "group": group})
		next += 1
		if mate.x >= 0:
			out.append({"id": ids[next % ids.size()], "cell": mate, "group": group})
			next += 1
	return out


static func place(gen: MineGenerator, reachable: PackedFloat32Array, escape: PackedByteArray) -> Array:
	var g := gen.g
	var occupied: Dictionary = {}
	for e in gen.data["entities"] + gen.data.get("lm_props", []):
		for centre in [e["cell"], e.get("module", e["cell"])]:
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					occupied[centre + Vector2i(dx, dy)] = true
	var best: Dictionary = {}
	var scores: Dictionary = {}
	for y in range(3, g.h - 3):
		for x in range(3, g.w - 3):
			var i := g.idx(x, y)
			if reachable[i] >= DigCheck.UNREACHED or escape[i] == 0:
				continue
			if g.get_mat(x, y) != Cell.AIR or g.get_mat(x, y - 1) != Cell.AIR or not g.is_solid(x, y + 1):
				continue
			if g.get_mat(x, y + 1) in [Cell.GAS, Cell.LOOSE]:
				continue
			var c := Vector2i(x, y)
			var zone := g.get_stratum(x, y)
			if zone < 0 or zone >= Balance.ZONE_COUNT or occupied.has(c):
				continue
			var score: int = hash("%d:find:%d:%d" % [gen.data["seed"], zone, i]) & 0x7fffffff
			if gen.space.kind_at(c) in ["chamber", "landmark"]:
				score += 1 << 32
			if not gen.reserved.has(c):
				score += 1 << 33
			if g.water[i] == 0:
				score += 1 << 34
			if score > int(scores.get(zone, -1)):
				scores[zone] = score
				best[zone] = c
	var finds: Array = []
	for zone in Balance.ZONE_COUNT:      # one per main-mine zone (the sixth lives in the deep stage)
		if best.has(zone):
			finds.append({"id": zone, "cell": best[zone]})
	return finds
