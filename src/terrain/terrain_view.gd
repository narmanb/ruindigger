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
var water_chunks: Dictionary = {}  # Vector2i -> WaterChunk
var water_redraws := 0
var bodies: Dictionary = {}        # Vector2i -> RID
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
var water_material: ShaderMaterial


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
	water_material = ShaderMaterial.new()
	water_material.shader = load("res://src/fx/water.gdshader")
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
	# water draws above terrain and above the player (z) so swimmers look submerged
	for key in chunks.keys():
		var wc := WaterChunk.new()
		wc.view = self
		wc.key = key
		wc.position = chunks[key].position
		wc.z_index = 3
		wc.material = water_material
		add_child(wc)
		water_chunks[key] = wc
	grid.take_dirty()
	grid.take_water_dirty()
	_flush_collision()


func _exit_tree() -> void:
	for key in bodies.keys():
		_free_body(key)


func _free_body(key: Vector2i) -> void:
	if shapes.has(key):
		for s in shapes[key]:
			PhysicsServer2D.free_rid(s)
		shapes.erase(key)
	if bodies.has(key):
		PhysicsServer2D.free_rid(bodies[key])
		bodies.erase(key)


func _on_cell_changed(x: int, y: int, _old: int, _new: int) -> void:
	_col_dirty[Vector2i(x / CHUNK, y / CHUNK)] = true


func _physics_process(_delta: float) -> void:
	_flush_collision()


func _process(_delta: float) -> void:
	for key in grid.take_dirty():
		if chunks.has(key):
			chunks[key].queue_redraw()
			glow_chunks[key].queue_redraw()
			water_chunks[key].queue_redraw()
			redraw_count += 1
	for key in grid.take_water_dirty():
		# neighbours too: surface blending reads across chunk edges
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var k2: Vector2i = key + d
			if water_chunks.has(k2):
				water_chunks[k2].touch()
		water_redraws += 1


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
	# one-way platforms (thin top slab)
	for y in range(y0, y1):
		for x in range(x0, x1):
			if grid.get_mat(x, y) == Cell.PLATFORM:
				var sh2 := PhysicsServer2D.rectangle_shape_create()
				PhysicsServer2D.shape_set_data(sh2, Vector2(C * 0.5, 3))
				PhysicsServer2D.body_add_shape(body, sh2, Transform2D(0.0, Vector2((x + 0.5) * C, y * C + 3)))
				PhysicsServer2D.body_set_shape_as_one_way_collision(body, idx, true, 4.0)
				new_shapes.append(sh2)
				idx += 1
	shapes[key] = new_shapes


func shape_count(key: Vector2i) -> int:
	return shapes.get(key, []).size()


# ---------------------------------------------------------------------------
# Drawing helpers used by chunks
# ---------------------------------------------------------------------------
func block_index(m: int, s: int) -> int:
	match m:
		Cell.SOFT, Cell.GAS:
			return s * 3
		Cell.HARD, Cell.CRACKED:
			return s * 3 + 1
		Cell.LOOSE:
			return s * 3 + 2
		Cell.BEDROCK:
			return 9 + s
		Cell.ALLOY:
			return 12
	return 0


func tile_rect(m: int, s: int, mask: int, x: int, y: int) -> Rect2:
	var bi := block_index(m, s)
	var var_i := (x % 4) + (y % 4) * 4
	var t := mask * 16 + var_i
	return Rect2((bi % 4) * 256 + (t % 16) * C, (bi / 4) * 256 + (t / 16) * C, C, C)


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
					if g.has_flag(x, y, Cell.F_DUG):
						draw_texture_rect_region(view.tex_back, Rect2(p, Vector2(C, C)), Rect2(s * 64 + (x % 4) * C, (y % 4) * C, C, C))
					if m == Cell.LADDER:
						draw_texture_rect_region(view.tex_props, Rect2(p, Vector2(C, C)), view.prop_rect("ladder_wood" if s == 0 else "ladder_metal"))
					elif m == Cell.PLATFORM:
						draw_texture_rect_region(view.tex_props, Rect2(p, Vector2(C, C)), view.prop_rect("platform"))
					elif not g.has_flag(x, y, Cell.F_DUG):
						view.draw_deco(self, x, y, p, s)


func draw_tile(ci: CanvasItem, m: int, s: int, mask: int, x: int, y: int, p: Vector2, col: Color) -> void:
	ci.draw_texture_rect_region(tex_atlas, Rect2(p, Vector2(C, C)), tile_rect(m, s, mask, x, y), col)


func draw_deco(ci: CanvasItem, x: int, y: int, p: Vector2, s: int) -> void:
	var hsh := hash2(x, y)
	var above := grid.get_mat(x, y - 1)
	var below := grid.get_mat(x, y + 1)
	if (above == Cell.SOFT or above == Cell.HARD) and hsh % 5 == 0:
		var n := ""
		match s:
			0:
				n = "roots%d" % (hsh / 7 % 3)
			1:
				n = "tendril%d" % (hsh / 7 % 2)
			2:
				n = "cable%d" % (hsh / 7 % 2)
		ci.draw_texture_rect_region(tex_props, Rect2(p, Vector2(C, C)), prop_rect(n))
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


const WATER_COL := [Color(0.16, 0.42, 0.78, 0.62), Color(0.1, 0.55, 0.62, 0.62), Color(0.32, 0.3, 0.8, 0.62)]
const WATER_TOP := [Color(0.6, 0.85, 1.0, 0.9), Color(0.55, 1.0, 0.9, 0.9), Color(0.75, 0.7, 1.0, 0.9)]


class WaterChunk extends Node2D:
	## Smooth water: each surface column blends into its neighbours, levels ease
	## toward the simulation instead of stepping, the shader rolls waves, and
	## free-falling water is left to the droplet renderer.
	var view: TerrainView
	var key: Vector2i
	var disp: PackedFloat32Array
	var animating := false

	func _ready() -> void:
		disp = PackedFloat32Array()
		disp.resize(CHUNK * CHUNK)
		var g := view.grid
		for ly in CHUNK:
			for lx in CHUNK:
				disp[ly * CHUNK + lx] = g.get_water(key.x * CHUNK + lx, key.y * CHUNK + ly)

	func touch() -> void:
		animating = true
		set_process(true)

	func _process(delta: float) -> void:
		if not animating:
			set_process(false)
			return
		var g := view.grid
		var k := clampf(delta * 10.0, 0.0, 1.0)
		var settled := true
		for ly in CHUNK:
			for lx in CHUNK:
				var i := ly * CHUNK + lx
				var target := float(g.get_water(key.x * CHUNK + lx, key.y * CHUNK + ly))
				var d := disp[i]
				if absf(d - target) > 0.4:
					disp[i] = lerpf(d, target, k)
					settled = false
				else:
					disp[i] = target
		queue_redraw()
		if settled:
			animating = false

	func _flat(r: Rect2, c: Color) -> void:
		# uv.y = 0 everywhere so the wave shader leaves these vertices still
		var z := Vector2.ZERO
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([c, c, c, c]), PackedVector2Array([z, z, z, z]))

	func _lv(x: int, y: int) -> float:
		var lx := x - key.x * CHUNK
		var ly := y - key.y * CHUNK
		if lx >= 0 and ly >= 0 and lx < CHUNK and ly < CHUNK:
			return disp[ly * CHUNK + lx]
		return float(view.grid.get_water(x, y))

	func _resting(g: TerrainGrid, x: int, y: int) -> bool:
		return g.is_solid(x, y + 1) or g.get_water(x, y + 1) >= Balance.WATER_MAX - 6

	func _pooled(g: TerrainGrid, x: int, y: int) -> bool:
		if _resting(g, x, y):
			return true
		# a drain column inside a pool still reads as pool, not as a spout
		for dx in [-1, 1]:
			if not g.is_solid(x + dx, y) and g.get_water(x + dx, y) >= Balance.WATER_MAX / 4 and _resting(g, x + dx, y):
				return true
		return false

	func _surface_h(g: TerrainGrid, x: int, y: int) -> float:
		## height (px) of the water column top in cell (x,y), or -1 if none
		if g.is_solid(x, y):
			return -1.0
		var lv := _lv(x, y)
		if lv < 0.5 or not _pooled(g, x, y):
			return -1.0
		if g.get_water(x, y - 1) > 0 and _pooled(g, x, y - 1):
			return 16.0
		return clampf(lv / float(Balance.WATER_MAX) * 16.0, 0.6, 16.0)

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
				var lv := _lv(x, y)
				if lv < 0.5 or g.is_solid(x, y):
					continue
				var s := g.get_stratum(x, y)
				var col: Color = WATER_COL[s]
				var bx := lx * C
				var by := ly * C + C
				if not _pooled(g, x, y):
					# water about to pour off a ledge: a thin spout (droplets do the rest)
					# water tipping over an edge: a straight narrow lip that meets the
					# droplet stream below (no wedge shapes)
					var w := 3.0 + 5.0 * clampf(lv / float(Balance.WATER_MAX), 0.0, 1.0)
					var top_y := by - clampf(lv / float(Balance.WATER_MAX) * 16.0, 2.0, 16.0)
					_flat(Rect2(bx + 8 - w * 0.5, top_y, w, by - top_y), Color(col.r, col.g, col.b, col.a * 0.8))
					continue
				var h := _surface_h(g, x, y)
				if h >= 16.0:
					var deep := col.darkened(0.25)
					_flat(Rect2(bx, by - 16, C, C), deep)
					continue
				# blend edge heights with neighbouring columns for a continuous surface
				var hl := _surface_h(g, x - 1, y)
				var hr := _surface_h(g, x + 1, y)
				var el := (h + hl) * 0.5 if hl >= 0.0 else (h if g.is_solid(x - 1, y) else h * 0.55)
				var er := (h + hr) * 0.5 if hr >= 0.0 else (h if g.is_solid(x + 1, y) else h * 0.55)
				el = minf(el, 16.0)
				er = minf(er, 16.0)
				var top := col.lightened(0.12)
				var bot := col.darkened(0.2)
				var pts := PackedVector2Array([Vector2(bx, by), Vector2(bx + C, by), Vector2(bx + C, by - er), Vector2(bx + 8, by - h), Vector2(bx, by - el)])
				var cols := PackedColorArray([bot, bot, top, top, top])
				var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0.5, 1), Vector2(0, 1)])
				draw_polygon(pts, cols, uvs)
				# surface highlight strip (also rides the waves: uv.y = 1)
				var hi: Color = WATER_TOP[s]
				var strip := PackedVector2Array([Vector2(bx, by - el), Vector2(bx + 8, by - h), Vector2(bx + C, by - er), Vector2(bx + C, by - er + 1.2), Vector2(bx + 8, by - h + 1.2), Vector2(bx, by - el + 1.2)])
				draw_polygon(strip, PackedColorArray([hi, hi, hi, hi, hi, hi]), PackedVector2Array([Vector2(0, 1), Vector2(0.5, 1), Vector2(1, 1), Vector2(1, 1), Vector2(0.5, 1), Vector2(0, 1)]))


## Renders airborne droplets as stretched, overlapping blobs so a waterfall reads
## as one continuous stream.
class WaterDrops extends Node2D:
	var sim: WaterSim
	var grid: TerrainGrid

	func _process(_d: float) -> void:
		if sim and (sim.drop_count() > 0 or _had):
			queue_redraw()
		_had = sim != null and sim.drop_count() > 0

	var _had := false

	func _draw() -> void:
		if sim == null:
			return
		var n := sim.drop_count()
		for i in n:
			var p: Vector2 = sim.drop_pos[i]
			var v: Vector2 = sim.drop_vel[i]
			var s := grid.get_stratum(int(p.x / 16.0), int(p.y / 16.0))
			var c: Color = WATER_COL[s]
			c.a = 0.75
			# soft capsule along the motion: overlapping discs merge into a ribbon
			var r := 2.3 + float(sim.drop_vol[i]) * 0.3
			var tail := p - v * 0.04
			for k in 4:
				draw_circle(p.lerp(tail, k / 3.0), r * (1.0 - k * 0.12), c)
			if i % 4 == 0:
				draw_line(p.lerp(tail, 0.8) + Vector2(-0.6, 0), p + Vector2(-0.6, 0), Color(1, 1, 1, 0.25), 1.0)


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
						draw_texture_rect_region(view.tex_alloy_glow, Rect2(p, Vector2(C, C)), Rect2((x % 4) * C, (y % 4) * C, C, C), Color(0.55, 0.4, 1.0, 0.8))
				elif m == Cell.AIR and not g.has_flag(x, y, Cell.F_DUG):
					var hsh := TerrainView.hash2(x, y)
					var s := g.get_stratum(x, y)
					var below := g.get_mat(x, y + 1)
					if s == 1 and (below == Cell.SOFT or below == Cell.HARD) and hsh % 6 == 1:
						var cc := Color(0.4, 1.0, 1.0, 0.35) if hsh / 11 % 3 == 1 else Color(0.85, 0.45, 1.0, 0.35)
						draw_texture_rect(view.tex_glow, Rect2(p + Vector2(-6, -6), Vector2(28, 28)), false, cc)
