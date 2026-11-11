class_name StructureLayout
extends RefCounted
## Remove abandoned scaffold fragments after carving, then let DigCheck audit
## the resulting routes. Rock, protected structures and water stay untouched.


static func clean(g: TerrainGrid, entities: Array) -> void:
	for x in g.w:
		var y := 0
		while y < g.h:
			if g.get_mat(x, y) != Cell.LADDER:
				y += 1
				continue
			var first := y
			var anchored := g.is_solid(x, y - 1)
			var protected_run := false
			while y < g.h and g.get_mat(x, y) == Cell.LADDER:
				anchored = anchored or g.is_solid(x - 1, y) or g.is_solid(x + 1, y)
				protected_run = protected_run or g.has_flag(x, y, Cell.F_PROTECTED)
				y += 1
			anchored = anchored or g.is_solid(x, y)
			if not protected_run and (y - first < Balance.GEN_LADDER_MIN_RUN or not anchored):
				for yy in range(first, y):
					g.put(x, yy, Cell.AIR)
	for y in g.h:
		var x := 0
		while x < g.w:
			if g.get_mat(x, y) != Cell.PLATFORM:
				x += 1
				continue
			var first := x
			var protected_run := false
			var ladder_landing := false
			while x < g.w and g.get_mat(x, y) == Cell.PLATFORM:
				protected_run = protected_run or g.has_flag(x, y, Cell.F_PROTECTED)
				ladder_landing = ladder_landing or g.get_mat(x, y - 1) == Cell.LADDER or g.get_mat(x, y + 1) == Cell.LADDER
				x += 1
			# Authored Engine maintenance routes cross otherwise unclimbable walls.
			if protected_run or g.get_stratum(first, y) == Balance.Z_ENGINE:
				continue
			var left := g.is_solid(first - 1, y) or g.get_mat(first - 1, y) == Cell.LADDER
			var right := g.is_solid(x, y) or g.get_mat(x, y) == Cell.LADDER
			if x - first <= Balance.GEN_LANDING_MAX_RUN and (left or right or ladder_landing):
				continue
			# Keep short ends anchored to the cave wall; open the middle of spans.
			var width := mini(Balance.GEN_LANDING_WIDTH, (x - first - 1) / 2)
			for xx in range(first, x):
				if not (left and xx < first + width) and not (right and xx >= x - width):
					g.put(xx, y, Cell.AIR)
	for e in entities.duplicate():
		if e["type"] != "beam":
			continue
		var c: Vector2i = e["cell"]
		if g.get_mat(c.x, c.y) != Cell.AIR or g.get_mat(c.x, c.y - 1) != Cell.AIR or not g.is_solid(c.x, c.y + 1):
			entities.erase(e)
