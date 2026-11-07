class_name WaterRenderer
extends Node2D
## Smooth liquid rendering ("metaball" technique).
##
## 1. Every visible water cell and every falling droplet is drawn as a soft,
##    blurry shape into an off-screen buffer (additive), so neighbours sum into
##    one continuous density field with no cell seams.
## 2. Two sprites show that buffer through water_composite.gdshader, which
##    thresholds the field into a crisp, smooth liquid surface. The main copy sits
##    behind the rock tiles (anything soft that bleeds into rock is hidden); a
##    faint copy sits in front of the player, masked out of rock cells.
##
## Pool cells use a 9-slice "soft rectangle" whose linear edge ramps are centred
## on the cell edges, so two neighbouring cells sum to exactly 1 along their
## shared edge, and differing surface heights blend smoothly across columns.

const M := 6                 # soft ramp half-width (px)
const BLOB_R := 4.6          # droplet blob radius (visible radius ~R/2)
const COLORS := [
	[Color(0.24, 0.56, 0.86, 0.72), Color(0.07, 0.25, 0.54, 0.88), Color(0.74, 0.92, 1.0, 0.95)],
	[Color(0.16, 0.62, 0.66, 0.72), Color(0.05, 0.3, 0.36, 0.88), Color(0.62, 1.0, 0.92, 0.95)],
	[Color(0.36, 0.34, 0.86, 0.72), Color(0.13, 0.11, 0.42, 0.88), Color(0.8, 0.76, 1.0, 0.95)],
]

var grid: TerrainGrid
var sim: WaterSim
var sv: SubViewport
var field: FieldDrawer
var back: Sprite2D
var front: Sprite2D
var back_mat: ShaderMaterial
var front_mat: ShaderMaterial
var mask_img: Image
var mask_tex: ImageTexture
var _mask_dirty := false
var _mask_t := 0.0
var disp: PackedFloat32Array   # eased display level per cell
var visible_water := 0         # cells drawn last frame (telemetry/tests)


func setup(g: TerrainGrid, s: WaterSim, parent: Node) -> void:
	grid = g
	sim = s
	disp = PackedFloat32Array()
	disp.resize(g.w * g.h)
	for i in g.water.size():
		disp[i] = g.water[i]
	sv = SubViewport.new()
	sv.transparent_bg = true
	sv.disable_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	sv.size = Vector2i(660, 380)
	add_child(sv)
	field = FieldDrawer.new()
	field.r = self
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	field.material = add
	field.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sv.add_child(field)
	field.soft9 = _make_soft9()
	field.blob = _make_blob()
	mask_img = Image.create(g.w, g.h, false, Image.FORMAT_L8)
	for y in g.h:
		for x in g.w:
			mask_img.set_pixel(x, y, Color.WHITE if g.is_solid(x, y) else Color.BLACK)
	mask_tex = ImageTexture.create_from_image(mask_img)
	g.cell_changed.connect(_on_cell_changed)
	var shader: Shader = load("res://src/fx/water_composite.gdshader")
	back_mat = ShaderMaterial.new()
	back_mat.shader = shader
	front_mat = ShaderMaterial.new()
	front_mat.shader = shader
	front_mat.set_shader_parameter("use_mask", true)
	front_mat.set_shader_parameter("opacity", 0.32)
	front_mat.set_shader_parameter("solid_mask", mask_tex)
	front_mat.set_shader_parameter("grid_size", Vector2(g.w, g.h))
	back = _sprite(back_mat, -5)
	front = _sprite(front_mat, 3)
	parent.add_child(back)
	parent.add_child(front)


func _sprite(mat: ShaderMaterial, z: int) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.centered = false
	sp.texture = sv.get_texture()
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sp.material = mat
	sp.z_index = z
	return sp


func _exit_tree() -> void:
	if is_instance_valid(back):
		back.queue_free()
	if is_instance_valid(front):
		front.queue_free()


func _on_cell_changed(x: int, y: int, _o: int, n: int) -> void:
	mask_img.set_pixel(x, y, Color.WHITE if Cell.is_solid(n) else Color.BLACK)
	_mask_dirty = true


static func _ramp(i: int) -> float:
	# 0..2M ramps up, a 3-texel plateau of 1, then mirrored ramp down
	var n := 4 * M + 3
	if i < 2 * M:
		return (i + 0.5) / (2.0 * M)
	if i < 2 * M + 3:
		return 1.0
	return (n - i - 0.5) / (2.0 * M)


func _make_soft9() -> ImageTexture:
	var n := 4 * M + 3
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := _ramp(x) * _ramp(y)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return ImageTexture.create_from_image(img)


func _make_blob() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var v := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	var vp := get_viewport()
	var inv := vp.get_canvas_transform().affine_inverse()
	var tl: Vector2 = inv * Vector2.ZERO
	var size := vp.get_visible_rect().size
	var want := Vector2i(int(ceil(size.x)) + 2, int(ceil(size.y)) + 2)
	if sv.size != want:
		sv.size = want
	sv.canvas_transform = Transform2D(0.0, -tl)
	back.position = tl
	front.position = tl
	field.view_rect = Rect2(tl, Vector2(want))
	_ease(delta, field.view_rect)
	field.queue_redraw()
	# tint by the stratum at the centre of the view
	var s := Balance.stratum_of_row(int((tl.y + size.y * 0.5) / Balance.CELL))
	var c: Array = COLORS[s]
	for m in [back_mat, front_mat]:
		m.set_shader_parameter("shallow_color", c[0])
		m.set_shader_parameter("deep_color", c[1])
		m.set_shader_parameter("surface_color", c[2])
	_mask_t -= delta
	if _mask_dirty and _mask_t <= 0.0:
		_mask_t = 0.1
		_mask_dirty = false
		mask_tex.update(mask_img)


func _ease(delta: float, r: Rect2) -> void:
	var x0 := maxi(0, int(r.position.x / 16.0) - 2)
	var y0 := maxi(0, int(r.position.y / 16.0) - 2)
	var x1 := mini(grid.w - 1, int(r.end.x / 16.0) + 2)
	var y1 := mini(grid.h - 1, int(r.end.y / 16.0) + 2)
	var k := clampf(delta * 12.0, 0.0, 1.0)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := y * grid.w + x
			var t := float(grid.water[i])
			var d := disp[i]
			if absf(d - t) < 0.3 or absf(d - t) > 40.0:
				disp[i] = t
			else:
				disp[i] = lerpf(d, t, k)


func resting(x: int, y: int) -> bool:
	return grid.is_solid(x, y + 1) or grid.get_water(x, y + 1) >= Balance.WATER_MAX - 6


func pooled(x: int, y: int) -> bool:
	if resting(x, y):
		return true
	for dx in [-1, 1]:
		if not grid.is_solid(x + dx, y) and grid.get_water(x + dx, y) >= Balance.WATER_MAX / 4 and resting(x + dx, y):
			return true
	return false


class FieldDrawer extends Node2D:
	var r: WaterRenderer
	var soft9: Texture2D
	var blob: Texture2D
	var view_rect := Rect2()

	func _soft_rect(rect: Rect2) -> void:
		## 9-slice soft rectangle: ramps of width 2M centred on each edge.
		var m := float(M)
		var xs := [rect.position.x - m, rect.position.x + m, rect.end.x - m, rect.end.x + m]
		var ys := [rect.position.y - m, rect.position.y + m, rect.end.y - m, rect.end.y + m]
		var tx := [0.0, 2.0 * m, 2.0 * m + 1.0, 2.0 * m + 2.0, 4.0 * m + 3.0]
		# texture spans per slice: ramp [0,2M), plateau texel [2M+1,2M+2), ramp [2M+3, 4M+3)
		var src_x := [Vector2(0, 2 * M), Vector2(2 * M + 1, 1), Vector2(2 * M + 3, 2 * M)]
		var src_y := src_x
		for iy in 3:
			var hy: float = ys[iy + 1] - ys[iy]
			if hy <= 0.0:
				continue
			for ix in 3:
				var wx: float = xs[ix + 1] - xs[ix]
				if wx <= 0.0:
					continue
				var sx: Vector2 = src_x[ix]
				var sy: Vector2 = src_y[iy]
				draw_texture_rect_region(soft9, Rect2(xs[ix], ys[iy], wx, hy), Rect2(sx.x, sy.x, sx.y, sy.y))

	func _draw() -> void:
		var g := r.grid
		var mx := float(Balance.WATER_MAX)
		var x0 := maxi(0, int(view_rect.position.x / 16.0) - 1)
		var y0 := maxi(0, int(view_rect.position.y / 16.0) - 1)
		var x1 := mini(g.w - 1, int(view_rect.end.x / 16.0) + 1)
		var y1 := mini(g.h - 1, int(view_rect.end.y / 16.0) + 1)
		var count := 0
		var min_h := 2.0 * M
		for y in range(y0, y1 + 1):
			var run_start := -1
			var run_top := 0.0
			var run_bottom := 0.0
			var by := (y + 1) * 16.0
			for x in range(x0, x1 + 2):
				var top := -1.0
				var bottom := 0.0
				if x <= x1 and not g.is_solid(x, y):
					var lv := r.disp[y * g.w + x]
					if lv >= 0.4:
						count += 1
						if r.pooled(x, y):
							var above := g.get_water(x, y - 1) > 0 and not g.is_solid(x, y - 1) and r.pooled(x, y - 1)
							var h := 16.0 if above else clampf(lv / mx * 16.0, 0.5, 16.0)
							top = snappedf(by - h, 0.5)
							bottom = maxf(by, top + min_h)
						else:
							# water tipping off an edge: a soft vertical stream segment
							var w := 4.0 + 8.0 * clampf(lv / mx, 0.0, 1.0)
							var cx := x * 16.0 + 8.0
							draw_texture_rect(blob, Rect2(cx - w, by - 16.0 - w * 0.5, w * 2.0, 16.0 + w * 2.0), false)
				# merge horizontal runs with the same top/bottom into one soft rect
				if run_start >= 0 and (top != run_top or bottom != run_bottom):
					_soft_rect(Rect2(run_start * 16.0, run_top, (x - run_start) * 16.0, run_bottom - run_top))
					run_start = -1
				if top >= 0.0 and run_start < 0:
					run_start = x
					run_top = top
					run_bottom = bottom
		# falling droplets: stretched blobs along their velocity
		var sim := r.sim
		var n := sim.drop_count()
		for i in n:
			var p: Vector2 = sim.drop_pos[i]
			if not view_rect.grow(16.0).has_point(p):
				continue
			var v: Vector2 = sim.drop_vel[i]
			var rad := BLOB_R + float(sim.drop_vol[i]) * 0.35
			var stretch := 1.0 + clampf(v.length() / 180.0, 0.0, 1.8)
			draw_set_transform(p - v * 0.012, v.angle() - PI * 0.5 if v.length() > 1.0 else 0.0, Vector2(1.0, stretch))
			draw_texture_rect(blob, Rect2(-rad, -rad, rad * 2.0, rad * 2.0), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		r.visible_water = count
