class_name TerrainView
extends Node2D
## Presentation + collision derived from a TerrainGrid. Only chunks touched by
## an edit are redrawn and only chunks whose solidity changed rebuild physics.

const C := 16
const CHUNK := TerrainGrid.CHUNK
const SHADE := [1.0, 0.88, 0.79, 0.72]
const ORE_ROW := {1: 0, 2: 1, 3: 2, 4: 3}

var grid: TerrainGrid
var glow_parent: Node2D            # node inside the additive glow layer
var chunks: Dictionary = {}        # Vector2i -> TerrainChunk
var glow_chunks: Dictionary = {}   # Vector2i -> GlowChunk
var back_chunks: Dictionary = {}   # Vector2i -> BackChunk (tunnel back-walls + decor)
var bodies: Dictionary = {}        # Vector2i -> RID
var platform_bodies: Dictionary = {} # (chunk x, world row) -> one-way-only RID
var shapes: Dictionary = {}        # Vector2i -> Array[RID]
var _col_dirty: Dictionary = {}
var redraw_count := 0              # telemetry for tests
var collision_rebuilds := 0

var tex_atlas: Texture2D
var tex_cracks: Texture2D
var tex_back: Texture2D
var tex_ore: Texture2D
var tex_gas: Texture2D
var tex_props: Texture2D
var tex_glow: Texture2D
var tex_alloy_glow: Texture2D
var props_meta: Dictionary = {}
var glow_material: ShaderMaterial


func setup(g: TerrainGrid, glow_node: Node2D) -> void:
	grid = g
	glow_parent = glow_node
	tex_atlas = load("res://assets/gen/terrain_atlas.png")
	tex_cracks = load("res://assets/gen/cracks.png")
	tex_back = load("res://assets/gen/backwalls.png")
	tex_ore = load("res://assets/gen/ore_overlay.png")
	tex_gas = load("res://assets/gen/gas_sac.png")
	tex_props = load("res://assets/gen/props.png")
	tex_glow = load("res://assets/gen/glow.png")
	tex_alloy_glow = load("res://assets/gen/alloy_glow.png")
	props_meta = SpriteDB.props()
	glow_material = ShaderMaterial.new()
	glow_material.shader = load("res://src/fx/glow_pulse.gdshader")
	grid.cell_changed.connect(_on_cell_changed)
	for cy in grid.chunks_h:
		for cx in grid.chunks_w:
			var key := Vector2i(cx, cy)
			var ch := TerrainChunk.new()
			ch.view = self
			ch.key = key
			ch.position = Vector2(cx * CHUNK * C, cy * CHUNK * C)
			add_child(ch)
			chunks[key] = ch
			var gc := GlowChunk.new()
			gc.view = self
			gc.key = key
			gc.position = ch.position
			gc.material = glow_material
			glow_parent.add_child(gc)
			glow_chunks[key] = gc
			_col_dirty[key] = true
	# back-walls and decor sit behind the water layer (z -10); solid rock in front
	for key in chunks.keys():
		var bc := BackChunk.new()
		bc.view = self
		bc.key = key
		bc.position = chunks[key].position
		bc.z_index = -10
		add_child(bc)
		back_chunks[key] = bc
	grid.take_dirty()
	grid.take_water_dirty()
	_flush_collision()


func _exit_tree() -> void:
	for key in bodies.keys():
		_free_body(key)


func _free_body(key: Vector2i) -> void:
	for y in range(key.y * CHUNK, mini((key.y + 1) * CHUNK, grid.h)):
		var pk := Vector2i(key.x, y)
		if platform_bodies.has(pk):
			PhysicsServer2D.free_rid(platform_bodies[pk])
			platform_bodies.erase(pk)
	if shapes.has(key):
		for s in shapes[key]:
			PhysicsServer2D.free_rid(s)
		shapes.erase(key)
	if bodies.has(key):
		PhysicsServer2D.free_rid(bodies[key])
		bodies.erase(key)


func _on_cell_changed(x: int, y: int, _old: int, _new: int) -> void:
	_col_dirty[Vector2i(x / CHUNK, y / CHUNK)] = true


var _sand_col_t := 0.0


func _physics_process(delta: float) -> void:
	# sand settles every step; its collision is rebuilt at most SAND_COLLISION_HZ
	_sand_col_t -= delta
	if _sand_col_t <= 0.0:
		_sand_col_t = 1.0 / Balance.SAND_COLLISION_HZ
		for key in grid.take_sand_col_dirty():
			_col_dirty[key] = true
	_flush_collision()


func _process(_delta: float) -> void:
	for key in grid.take_dirty():
		if chunks.has(key):
			chunks[key].queue_redraw()
			glow_chunks[key].queue_redraw()
			back_chunks[key].queue_redraw()
			redraw_count += 1
	grid.take_water_dirty()   # water is drawn by WaterRenderer every frame


func _flush_collision() -> void:
	if _col_dirty.is_empty():
		return
	for key in _col_dirty.keys():
		_rebuild_collision(key)
	_col_dirty.clear()


func _rebuild_collision(key: Vector2i) -> void:
	collision_rebuilds += 1
	var space := get_world_2d().space
	if not bodies.has(key):
		var b := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(b, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_set_space(b, space)
		PhysicsServer2D.body_set_collision_layer(b, 1)
		PhysicsServer2D.body_set_collision_mask(b, 0)
		PhysicsServer2D.body_attach_object_instance_id(b, get_instance_id())
		bodies[key] = b
		shapes[key] = []
	var body: RID = bodies[key]
	PhysicsServer2D.body_clear_shapes(body)
	for y in range(key.y * CHUNK, mini((key.y + 1) * CHUNK, grid.h)):
		var pk := Vector2i(key.x, y)
		if platform_bodies.has(pk):
			PhysicsServer2D.body_clear_shapes(platform_bodies[pk])
	for s in shapes[key]:
		PhysicsServer2D.free_rid(s)
	var new_shapes: Array = []
	var x0 := key.x * CHUNK
	var y0 := key.y * CHUNK
	var x1 := mini(x0 + CHUNK, grid.w)
	var y1 := mini(y0 + CHUNK, grid.h)
	# Greedy rectangles: horizontal runs, then merge identical runs downward.
	var open_runs: Dictionary = {}   # Vector2i(start,end) -> [y_start, height]
	var rects: Array = []
	for y in range(y0, y1 + 1):
		var runs: Dictionary = {}
		if y < y1:
			var x := x0
			while x < x1:
				if grid.is_solid(x, y):
					var s := x
					while x < x1 and grid.is_solid(x, y):
						x += 1
					runs[Vector2i(s, x)] = true
				else:
					x += 1
		for r in open_runs.keys():
			if runs.has(r):
				open_runs[r][1] += 1
				runs.erase(r)
			else:
				rects.append([r.x, open_runs[r][0], r.y - r.x, open_runs[r][1]])
				open_runs.erase(r)
		for r in runs.keys():
			open_runs[r] = [y, 1]
	var idx := 0
	for r in rects:
		var sh := PhysicsServer2D.rectangle_shape_create()
		PhysicsServer2D.shape_set_data(sh, Vector2(r[2] * C * 0.5, r[3] * C * 0.5))
		var t := Transform2D(0.0, Vector2((r[0] + r[2] * 0.5) * C, (r[1] + r[3] * 0.5) * C))
		PhysicsServer2D.body_add_shape(body, sh, t)
		new_shapes.append(sh)
		idx += 1
	# sand piles: two convex quads per cell (left and right half), their top
	# edge following the same slope the pile is drawn with
	for y in range(y0, y1):
		for x in range(x0, x1):
			if not has_sand_shape(x, y) or not _sand_floor(x, y):
				continue                   # falling sand does not collide
			var pr := sand_profile(x, y)
			var bot := (y + 1) * C
			for half in 2:
				var xa := x * C + half * C * 0.5
				var xb := xa + C * 0.5
				var ha: float = pr.x if half == 0 else pr.y
				var hb: float = pr.y if half == 0 else pr.z
				if ha < 0.5 and hb < 0.5:
					continue
				var pts := PackedVector2Array([Vector2(xa, bot)])
				if ha >= 0.5:
					pts.append(Vector2(xa, bot - ha))
				if hb >= 0.5:
					pts.append(Vector2(xb, bot - hb))
				pts.append(Vector2(xb, bot))
				var ps := PhysicsServer2D.convex_polygon_shape_create()
				PhysicsServer2D.shape_set_data(ps, pts)
				PhysicsServer2D.body_add_shape(body, ps, Transform2D.IDENTITY)
				new_shapes.append(ps)
	# one-way platforms (thin top slab)
	for y in range(y0, y1):
		var platform_idx := 0
		for x in range(x0, x1):
			if grid.get_mat(x, y) == Cell.PLATFORM:
				var pk := Vector2i(key.x, y)
				if not platform_bodies.has(pk):
					var pb := PhysicsServer2D.body_create()
					PhysicsServer2D.body_set_mode(pb, PhysicsServer2D.BODY_MODE_STATIC)
					PhysicsServer2D.body_set_space(pb, space)
					PhysicsServer2D.body_set_collision_layer(pb, 1)
					PhysicsServer2D.body_set_collision_mask(pb, 0)
					PhysicsServer2D.body_attach_object_instance_id(pb, get_instance_id())
					platform_bodies[pk] = pb
				var platform_body: RID = platform_bodies[pk]
				var sh2 := PhysicsServer2D.rectangle_shape_create()
				PhysicsServer2D.shape_set_data(sh2, Vector2(C * 0.5, 3))
				PhysicsServer2D.body_add_shape(platform_body, sh2, Transform2D(0.0, Vector2((x + 0.5) * C, y * C + 3)))
				PhysicsServer2D.body_set_shape_as_one_way_collision(platform_body, platform_idx, true, 4.0)
				new_shapes.append(sh2)
				platform_idx += 1
	shapes[key] = new_shapes


func platform_row_bodies(body: RID) -> Array[RID]:
	var result: Array[RID] = []
	var row_key: Variant = platform_bodies.find_key(body)
	if row_key == null:
		return result
	# A character straddling a chunk seam may report only one supporting RID.
	# Ignore the whole touched row, while lower rows and rock still collide.
	for key in platform_bodies:
		if key.y == row_key.y:
			result.append(platform_bodies[key])
	return result


func shape_count(key: Vector2i) -> int:
	return shapes.get(key, []).size()


# ---------------------------------------------------------------------------
# Drawing helpers used by chunks
# ---------------------------------------------------------------------------
const ATLAS_COLS := 8   # terrain_atlas.png is 8 x 4 blocks (see tools/assetgen/gen_tiles.py)


func block_index(m: int, s: int) -> int:
	if s == Balance.Z_FIRST:
		# the sixth biome was added after the atlas order was fixed: slots 21-25
		match m:
			Cell.SOFT, Cell.GAS:
				return 21
			Cell.HARD, Cell.CRACKED:
				return 22
			Cell.LOOSE:
				return 23
			Cell.BEDROCK:
				return 24
			Cell.ALLOY:
				return 25
		return 21
	match m:
		Cell.SOFT, Cell.GAS:
			return s * 3
		Cell.HARD, Cell.CRACKED:
			return s * 3 + 1
		Cell.LOOSE:
			return s * 3 + 2
		Cell.BEDROCK:
			return 15 + s
		Cell.ALLOY:
			return 20
	return 0


func tile_rect(m: int, s: int, mask: int, x: int, y: int) -> Rect2:
	var bi := block_index(m, s)
	var var_i := (x % 4) + (y % 4) * 4
	var t := mask * 16 + var_i
	return Rect2((bi % ATLAS_COLS) * 256 + (t % 16) * C, (bi / ATLAS_COLS) * 256 + (t / 16) * C, C, C)


## Sand surface of a cell as heights in px above its floor: left edge, middle,
## right edge. Edges meet the neighbour halfway (a wall keeps the height), so
## piles read as smooth mounds and walk as slopes.
func sand_profile(x: int, y: int) -> Vector3:
	if grid.is_solid(x, y):
		return Vector3.ZERO
	var h := float(grid.get_sand(x, y))
	if h <= 0.0:
		# a skirt: bare floor beside a pile slopes up to meet it, so a mound
		# rises from the ground instead of starting with a step
		if not _sand_floor(x, y):
			return Vector3.ZERO
		return Vector3(_skirt(x - 1, y), 0.0, _skirt(x + 1, y))
	if not _sand_floor(x, y):
		return Vector3(h, h, h)        # still falling: a flat clump
	return Vector3(_sand_edge(h, x - 1, y), h, _sand_edge(h, x + 1, y))


func _sand_floor(x: int, y: int) -> bool:
	return grid.is_solid(x, y + 1) or grid.get_sand(x, y + 1) >= Balance.SAND_MAX


func _skirt(nx: int, y: int) -> float:
	if not grid.in_bounds(nx, y) or grid.is_solid(nx, y):
		return 0.0
	return float(grid.get_sand(nx, y)) * 0.5


## Does this cell draw or collide as sand (a pile, or a skirt beside one)?
func has_sand_shape(x: int, y: int) -> bool:
	if grid.get_sand(x, y) > 0:
		return not grid.is_solid(x, y)
	return (grid.get_sand(x - 1, y) > 0 or grid.get_sand(x + 1, y) > 0) and not grid.is_solid(x, y) and _sand_floor(x, y)


func _sand_edge(h: float, nx: int, y: int) -> float:
	if not grid.in_bounds(nx, y) or grid.is_solid(nx, y):
		return h
	return (h + float(grid.get_sand(nx, y))) * 0.5


func draw_sand(ci: CanvasItem, x: int, y: int, p: Vector2) -> void:
	var pr := sand_profile(x, y)
	var s := maxi(0, grid.get_stratum(x, y))
	var base := Cell.debris_color(Cell.SOFT, s).lightened(0.12)
	var top := base.lightened(0.3)
	var dark := base.darkened(0.25)
	var b := p.y + C
	var mid := p.x + C * 0.5
	var poly := PackedVector2Array([Vector2(p.x, b), Vector2(p.x, b - pr.x), Vector2(mid, b - pr.y), Vector2(p.x + C, b - pr.z), Vector2(p.x + C, b)])
	ci.draw_colored_polygon(poly, base)
	if pr.x > 0.5 or pr.y > 0.5:
		ci.draw_line(Vector2(p.x, b - pr.x), Vector2(mid, b - pr.y), top, 1.0)
	if pr.y > 0.5 or pr.z > 0.5:
		ci.draw_line(Vector2(mid, b - pr.y), Vector2(p.x + C, b - pr.z), top, 1.0)
	# grains: a few darker specks, fixed per cell so they do not shimmer
	var hs := TerrainView.hash2(x, y)
	for k in 4:
		var gx := p.x + 1.0 + float(((hs >> (k * 4)) & 0xff) % 14)
		var gyf := float((hs >> (k * 3 + 2)) & 7) / 7.0
		var surf: float = lerpf(pr.x, pr.y, clampf((gx - p.x) / (C * 0.5), 0.0, 1.0)) if gx < mid else lerpf(pr.y, pr.z, clampf((gx - mid) / (C * 0.5), 0.0, 1.0))
		if surf > 3.0:
			ci.draw_rect(Rect2(gx, b - 1.0 - gyf * (surf - 3.0), 1, 1), dark)


## How far below the top of its cell the drawn surface sits at world x, in
## pixels, for an exposed solid cell in row `cy` (0 when the cell is not an
## exposed top). The tiles' top edges are rough and rounded at the corners;
## the player uses this to plant its feet on the rock you can see. Read from
## the atlas image itself, so it always matches the art.
var _atlas_img: Image
var _depth_cache: Dictionary = {}


func surface_depth(wx: float, cy: int) -> int:
	var x := int(floor(wx / C))
	if not grid.in_bounds(x, cy) or not grid.is_solid(x, cy) or grid.is_solid(x, cy - 1):
		return 0
	var m := grid.get_mat(x, cy)
	var r := tile_rect(m, grid.get_stratum(x, cy), grid.edge_mask(x, cy), x, cy)
	var col := clampi(int(wx) - x * int(C), 0, int(C) - 1)
	var key := Vector2i(int(r.position.x) + col, int(r.position.y))
	if _depth_cache.has(key):
		return _depth_cache[key]
	if _atlas_img == null:
		_atlas_img = tex_atlas.get_image()
		if _atlas_img == null:
			return 0
		if _atlas_img.is_compressed():
			_atlas_img.decompress()
	var d := 0
	while d < int(C) - 1 and _atlas_img.get_pixel(key.x, key.y + d).a < 0.5:
		d += 1
	# the first solid row is a near-black outline that vanishes against the
	# dark cave behind it; the ground you see starts below it. Feet stand ON
	# the outline row, so the boot's own outline overlaps it.
	var px := _atlas_img.get_pixel(key.x, key.y + d)
	if px.get_luminance() < 0.25 and d < int(C) - 2:
		d += 1
	_depth_cache[key] = d
	return d


func prop_rect(n: String) -> Rect2:
	var r: Array = props_meta.get(n, [0, 0, 1, 1])
	return Rect2(r[0], r[1], r[2], r[3])


static func hash2(x: int, y: int) -> int:
	var hsh := x * 374761393 + y * 668265263
	hsh = (hsh ^ (hsh >> 13)) * 1274126177
	return absi(hsh ^ (hsh >> 16))


class TerrainChunk extends Node2D:
	var view: TerrainView
	var key: Vector2i

	func _draw() -> void:
		var g := view.grid
		var x0 := key.x * CHUNK
		var y0 := key.y * CHUNK
		var cracked_tex := view.tex_cracks
		for ly in CHUNK:
			var y := y0 + ly
			if y >= g.h:
				break
			for lx in CHUNK:
				var x := x0 + lx
				if x >= g.w:
					break
				var m := g.get_mat(x, y)
				var p := Vector2(lx * C, ly * C)
				var s := g.get_stratum(x, y)
				if Cell.is_solid(m):
					var mask := g.edge_mask(x, y)
					var d := g.depth_from_open(x, y)
					var sh: float = SHADE[d]
					var col := Color(sh, sh, sh)
					view.draw_tile(self, m, s, mask, x, y, p, col)
					var o := g.get_ore(x, y)
					if o != 0:
						var row: int = ORE_ROW.get(o, 0)
						var v := (x * 3 + y * 7) % 4
						draw_texture_rect_region(view.tex_ore, Rect2(p, Vector2(C, C)), Rect2(v * C, row * C, C, C), col)
					if m == Cell.GAS:
						draw_texture_rect_region(view.tex_gas, Rect2(p, Vector2(C, C)), Rect2(0, 0, C, C), col)
					if m == Cell.CRACKED:
						draw_texture_rect_region(cracked_tex, Rect2(p, Vector2(C, C)), Rect2(((x + y) % 4) * C, 2 * C, C, C), Color(1, 0.85, 0.6, 0.9))
					var f := g.hp_frac(x, y)
					if f < 0.92:
						var stage := 0 if f > 0.6 else (1 if f > 0.3 else 2)
						draw_texture_rect_region(cracked_tex, Rect2(p, Vector2(C, C)), Rect2(((x * 5 + y) % 4) * C, stage * C, C, C))
				else:
					if m == Cell.LADDER:
						draw_texture_rect_region(view.tex_props, Rect2(p, Vector2(C, C)), view.prop_rect("ladder_wood" if s == 0 else "ladder_metal"))
					elif m == Cell.PLATFORM:
						draw_texture_rect_region(view.tex_props, Rect2(p, Vector2(C, C)), view.prop_rect("platform"))
					if view.has_sand_shape(x, y):
						view.draw_sand(self, x, y, p)


class BackChunk extends Node2D:
	var view: TerrainView
	var key: Vector2i

	func _draw() -> void:
		var g := view.grid
		var x0 := key.x * CHUNK
		var y0 := key.y * CHUNK
		for ly in CHUNK:
			var y := y0 + ly
			if y >= g.h:
				break
			for lx in CHUNK:
				var x := x0 + lx
				if x >= g.w:
					break
				var m := g.get_mat(x, y)
				if Cell.is_solid(m):
					continue
				var p := Vector2(lx * C, ly * C)
				var s := g.get_stratum(x, y)
				if g.has_flag(x, y, Cell.F_DUG):
					draw_texture_rect_region(view.tex_back, Rect2(p, Vector2(C, C)), Rect2(s * 64 + (x % 4) * C, (y % 4) * C, C, C))
				elif m == Cell.AIR:
					view.draw_deco(self, x, y, p, s)


func draw_tile(ci: CanvasItem, m: int, s: int, mask: int, x: int, y: int, p: Vector2, col: Color) -> void:
	ci.draw_texture_rect_region(tex_atlas, Rect2(p, Vector2(C, C)), tile_rect(m, s, mask, x, y), col)


func draw_deco(ci: CanvasItem, x: int, y: int, p: Vector2, s: int) -> void:
	var hsh := hash2(x, y)
	var above := grid.get_mat(x, y - 1)
	var below := grid.get_mat(x, y + 1)
	if (above == Cell.SOFT or above == Cell.HARD) and hsh % 5 == 0:
		var n := ""
		var tint := Color.WHITE
		match s:
			0:
				n = "roots%d" % (hsh / 7 % 3)
			1:
				n = "tendril%d" % (hsh / 7 % 2)
			2:
				n = "cable%d" % (hsh / 7 % 2)
			3:
				n = "tendril%d" % (hsh / 7 % 2)
				tint = Color(0.45, 0.8, 1.0)     # dripping weed
			4:
				n = "roots%d" % (hsh / 7 % 3)
				tint = Color(1.0, 0.6, 1.0)      # crystal fringes
		ci.draw_texture_rect_region(tex_props, Rect2(p, Vector2(C, C)), prop_rect(n), tint)
	elif (below == Cell.SOFT or below == Cell.HARD) and hsh % 6 == 1:
		match s:
			0:
				var n0 := "pebbles" if hsh / 11 % 3 != 0 else "bones"
				ci.draw_texture_rect_region(tex_props, Rect2(p + Vector2(0, 8), Vector2(16, 8)), prop_rect(n0))
			1:
				ci.draw_texture_rect_region(tex_props, Rect2(p, Vector2(C, C)), prop_rect("shroom%d" % (hsh / 11 % 3)))
			2:
				if hsh / 11 % 2 == 0:
					ci.draw_texture_rect_region(tex_props, Rect2(p + Vector2(0, 8), Vector2(16, 8)), prop_rect("pebbles"), Color(0.7, 0.6, 0.9))
			3:
				if hsh / 11 % 2 == 0:
					ci.draw_texture_rect_region(tex_props, Rect2(p + Vector2(0, 8), Vector2(16, 8)), prop_rect("pebbles"), Color(0.55, 0.8, 1.0))
			4:
				ci.draw_texture_rect_region(tex_props, Rect2(p + Vector2(0, 8), Vector2(16, 8)), prop_rect("pebbles"), Color(1.0, 0.7, 1.0))




class GlowChunk extends Node2D:
	var view: TerrainView
	var key: Vector2i

	func _draw() -> void:
		var g := view.grid
		var x0 := key.x * CHUNK
		var y0 := key.y * CHUNK
		for ly in CHUNK:
			var y := y0 + ly
			if y >= g.h:
				break
			for lx in CHUNK:
				var x := x0 + lx
				if x >= g.w:
					break
				var m := g.get_mat(x, y)
				var p := Vector2(lx * C, ly * C)
				if Cell.is_solid(m):
					var o := g.get_ore(x, y)
					if o != 0 and o != Cell.ORE_FOSSIL:
						var c := Balance.ore_color(o)
						c.a = 0.42 if o == Cell.ORE_AETHER else 0.3
						draw_texture_rect(view.tex_glow, Rect2(p - Vector2(10, 10), Vector2(36, 36)), false, c)
					elif m == Cell.GAS:
						draw_texture_rect(view.tex_glow, Rect2(p - Vector2(12, 12), Vector2(40, 40)), false, Color(0.75, 0.95, 0.2, 0.3))
					elif m == Cell.ALLOY and g.edge_mask(x, y) != 0:
						draw_texture_rect_region(view.tex_alloy_glow, Rect2(p, Vector2(C, C)), Rect2((x % 4) * C, (y % 4) * C, C, C), Color(0.2, 0.95, 0.85, 0.8) if g.get_stratum(x, y) == Balance.Z_FIRST else Color(0.55, 0.4, 1.0, 0.8))
				elif m == Cell.AIR and not g.has_flag(x, y, Cell.F_DUG):
					var hsh := TerrainView.hash2(x, y)
					var s := g.get_stratum(x, y)
					var below := g.get_mat(x, y + 1)
					if s == 4 and (below == Cell.SOFT or below == Cell.HARD) and hsh % 6 == 1:
						# crystals light the Hollows from the floor
						var c4 := Color(1.0, 0.5, 0.95, 0.5) if hsh / 11 % 3 != 1 else Color(0.5, 0.95, 1.0, 0.5)
						draw_texture_rect(view.tex_glow, Rect2(p + Vector2(-8, -8), Vector2(32, 32)), false, c4)
					if s == 1 and (below == Cell.SOFT or below == Cell.HARD) and hsh % 6 == 1:
						var cc := Color(0.4, 1.0, 1.0, 0.35) if hsh / 11 % 3 == 1 else Color(0.85, 0.45, 1.0, 0.35)
						draw_texture_rect(view.tex_glow, Rect2(p + Vector2(-6, -6), Vector2(28, 28)), false, cc)
