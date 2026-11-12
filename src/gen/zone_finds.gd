class_name ZoneFinds
extends RefCounted
## Optional, non-colliding collectibles. Never edits terrain or consumes a
## generator RNG stream. Uses the final route audit to guarantee a way out.

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
