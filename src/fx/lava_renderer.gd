class_name LavaRenderer
extends Node2D
## Draws lava and steam for the cells on screen only.
##
## Lava uses the same "metaball" technique as water (see WaterRenderer): every
## visible lava cell is drawn as a soft shape into an off-screen density buffer,
## and lava_composite.gdshader thresholds that field into one smooth molten
## body, with no cell seams or right angles. Lava gets wider soft ramps than
## water (rounder, heavier edges), a slowly bulging surface, thick rounded
## streams where it pours, and drifting crust plates in the shader. The body
## sits behind the rock tiles, so its edges always meet rock cleanly.
## Steam is soft puffs drawn in front of the player.

const C := 16
const M := 7                  # soft ramp half-width (px): rounder than water's 6

var grid: TerrainGrid
var lava: LavaSim
var steam: SteamField
var glow_tex: Texture2D
var sv: SubViewport
var field: Field
var body: Sprite2D
var body_mat: ShaderMaterial
var vapour: Node2D
var glow: Node2D
var disp: PackedFloat32Array   # eased display level per cell (lava moves in steps)
var visible_lava := 0         # cells drawn last frame (telemetry/tests)
var t := 0.0


func setup(g: TerrainGrid, l: LavaSim, s: SteamField, glow_root: Node2D) -> void:
	grid = g
	lava = l
	steam = s
	glow_tex = load("res://assets/gen/glow.png")
	disp = PackedFloat32Array()
	disp.resize(g.w * g.h)
	for i in g.lava.size():
		disp[i] = g.lava[i]
	sv = SubViewport.new()
	sv.transparent_bg = true
	sv.disable_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	sv.size = Vector2i(660, 380)
	add_child(sv)
	field = Field.new()
	field.r = self
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	field.material = add
	field.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	field.soft9 = _make_soft9()
	field.blob = _make_blob()
	sv.add_child(field)
	body_mat = ShaderMaterial.new()
	body_mat.shader = load("res://src/fx/lava_composite.gdshader")
	body = Sprite2D.new()
	body.centered = false
	body.texture = sv.get_texture()
	body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	body.material = body_mat
	body.z_index = -5            # behind the rock tiles, like water
	add_child(body)
	vapour = Vapour.new()
	vapour.r = self
	vapour.z_index = 6          # in front of the player: steam can hide things
	add_child(vapour)
	glow = Glow.new()
	glow.r = self
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = m
	glow_root.add_child(glow)


func _exit_tree() -> void:
	if is_instance_valid(glow):
		glow.queue_free()


static func _ramp(i: int) -> float:
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
	t += delta
	var vp := get_viewport()
	var inv := vp.get_canvas_transform().affine_inverse()
	var tl: Vector2 = inv * Vector2.ZERO
	var size := vp.get_visible_rect().size / vp.get_canvas_transform().get_scale()
	var want := Vector2i(int(ceil(size.x)) + 2, int(ceil(size.y)) + 2)
	if sv.size != want:
		sv.size = want
	sv.canvas_transform = Transform2D(0.0, -tl)
	body.position = tl
	field.view_rect = Rect2(tl, Vector2(want))
	_ease(delta, field.view_rect)
	field.queue_redraw()
	vapour.queue_redraw()
	glow.queue_redraw()


## Lava moves in chunks on a slow tick; ease what is drawn so it oozes.
func _ease(delta: float, r: Rect2) -> void:
	var x0 := maxi(0, int(r.position.x / 16.0) - 2)
	var y0 := maxi(0, int(r.position.y / 16.0) - 2)
	var x1 := mini(grid.w - 1, int(r.end.x / 16.0) + 2)
	var y1 := mini(grid.h - 1, int(r.end.y / 16.0) + 2)
	var k := clampf(delta * 5.0, 0.0, 1.0)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := y * grid.w + x
			var target := float(grid.lava[i])
			var d := disp[i]
			if absf(d - target) < 0.3 or grid.mat[i] != Cell.AIR:
				disp[i] = target
			else:
				disp[i] = lerpf(d, target, k)


func view_cells() -> Rect2i:
	var vp := get_viewport()
	var inv := vp.get_canvas_transform().affine_inverse()
	var tl: Vector2 = inv * Vector2.ZERO
	var br: Vector2 = inv * vp.get_visible_rect().size
	var a := Vector2i(int(floor(tl.x / C)) - 1, int(floor(tl.y / C)) - 1)
	var b := Vector2i(int(ceil(br.x / C)) + 1, int(ceil(br.y / C)) + 1)
	a = a.clamp(Vector2i.ZERO, Vector2i(grid.w - 1, grid.h - 1))
	b = b.clamp(Vector2i.ZERO, Vector2i(grid.w, grid.h))
	return Rect2i(a, b - a)


func resting(x: int, y: int) -> bool:
	return grid.is_solid(x, y + 1) or grid.get_lava(x, y + 1) >= Balance.LAVA_MAX - 4


class Field extends Node2D:
	var r: LavaRenderer
	var soft9: Texture2D
	var blob: Texture2D
	var view_rect := Rect2()

	func _soft_rect(rect: Rect2) -> void:
		## 9-slice soft rectangle: ramps of width 2M centred on each edge, so
		## neighbouring cells sum to a seamless field (see WaterRenderer).
		var m := float(M)
		var xs := [rect.position.x - m, rect.position.x + m, rect.end.x - m, rect.end.x + m]
		var ys := [rect.position.y - m, rect.position.y + m, rect.end.y - m, rect.end.y + m]
		var src := [Vector2(0, 2 * M), Vector2(2 * M + 1, 1), Vector2(2 * M + 3, 2 * M)]
		for iy in 3:
			var hy: float = ys[iy + 1] - ys[iy]
			if hy <= 0.0:
				continue
			for ix in 3:
				var wx: float = xs[ix + 1] - xs[ix]
				if wx <= 0.0:
					continue
				var sx: Vector2 = src[ix]
				var sy: Vector2 = src[iy]
				draw_texture_rect_region(soft9, Rect2(xs[ix], ys[iy], wx, hy), Rect2(sx.x, sy.x, sx.y, sy.y))

	func _draw() -> void:
		var g := r.grid
		var mx := float(Balance.LAVA_MAX)
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
					if lv >= 0.5:
						count += 1
						var above := g.get_lava(x, y - 1) > 0 and not g.is_solid(x, y - 1)
						if r.resting(x, y):
							var h := 16.0 if above else clampf(lv / mx * 16.0, 1.0, 16.0)
							top = snappedf(by - h, 0.5)
							bottom = maxf(by, top + min_h)
							if not above:
								# a slow, heavy bulge on the open surface
								var bulge := 6.0 + 2.5 * sin(r.t * 1.1 + x * 1.7) * (0.5 + 0.5 * sin(r.t * 0.37 + x))
								var cx := x * 16.0 + 8.0 + 2.0 * sin(r.t * 0.6 + x * 2.3)
								draw_texture_rect(blob, Rect2(cx - bulge * 1.4, top - bulge * 0.35, bulge * 2.8, bulge * 1.4), false)
						else:
							# pouring: a thick rounded stream, wider when more is flowing
							var f := clampf(lv / mx, 0.0, 1.0)
							var w := 5.0 + 6.0 * sqrt(f)
							var cx2 := x * 16.0 + 8.0
							var top2 := by - 16.0 - (w if not above else 0.0)
							draw_texture_rect(blob, Rect2(cx2 - w, top2 - w * 0.5, w * 2.0, by - top2 + w * 1.5), false)
				if run_start >= 0 and (top != run_top or bottom != run_bottom):
					_soft_rect(Rect2(run_start * 16.0, run_top, (x - run_start) * 16.0, run_bottom - run_top))
					run_start = -1
				if top >= 0.0 and run_start < 0:
					run_start = x
					run_top = top
					run_bottom = bottom
		r.visible_lava = count


class Vapour extends Node2D:
	var r: LavaRenderer

	func _draw() -> void:
		if r.steam == null or r.steam.cells.is_empty():
			return
		var v := r.view_cells()
		for c: Vector2i in r.steam.cells.keys():
			if not v.has_point(c):
				continue
			var d: float = r.steam.cells[c]
			var a := clampf(0.15 + d * 0.45, 0.0, 0.8)
			var wob := Vector2(sin(r.t * 1.3 + c.y) * 3.0, cos(r.t * 1.1 + c.x) * 2.0)
			var sz := 26.0 + d * 10.0
			draw_texture_rect(r.glow_tex, Rect2(Vector2(c.x * C + 8, c.y * C + 8) + wob - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(0.92, 0.94, 0.97, a))


class Glow extends Node2D:
	var r: LavaRenderer

	func _draw() -> void:
		var g := r.grid
		var v := r.view_cells()
		# light only from exposed lava surfaces, every other cell, to stay cheap
		for y in range(v.position.y, v.end.y):
			for x in range(v.position.x, v.end.x, 2):
				var l := g.get_lava(x, y)
				if l <= 0 or g.get_lava(x, y - 1) > 0:
					continue
				var a := 0.28 + 0.08 * sin(r.t * 2.0 + x)
				draw_texture_rect(r.glow_tex, Rect2(Vector2(x * C + 8, y * C + 4) - Vector2(30, 30), Vector2(60, 60)), false, Color(1.0, 0.45, 0.12, a))
