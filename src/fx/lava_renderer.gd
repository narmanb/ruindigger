class_name LavaRenderer
extends Node2D
## Draws lava and steam for the cells on screen only. Lava is a glowing body
## with a crusted, slowly churning surface; steam is soft drifting puffs that
## thin out as the field decays. Both read straight from LavaSim / SteamField.

const C := 16

var grid: TerrainGrid
var lava: LavaSim
var steam: SteamField
var glow_tex: Texture2D
var body: Node2D
var vapour: Node2D
var glow: Node2D
var t := 0.0


func setup(g: TerrainGrid, l: LavaSim, s: SteamField, glow_root: Node2D) -> void:
	grid = g
	lava = l
	steam = s
	glow_tex = load("res://assets/gen/glow.png")
	body = Body.new()
	body.r = self
	body.z_index = 1
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


func _process(delta: float) -> void:
	t += delta
	body.queue_redraw()
	vapour.queue_redraw()
	glow.queue_redraw()


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


class Body extends Node2D:
	var r: LavaRenderer

	func _draw() -> void:
		var g := r.grid
		var v := r.view_cells()
		for y in range(v.position.y, v.end.y):
			for x in range(v.position.x, v.end.x):
				var l := g.get_lava(x, y)
				if l <= 0:
					continue
				var full: bool = g.get_lava(x, y - 1) > 0
				var hgt := float(C) if full else maxf(2.0, float(C) * l / Balance.LAVA_MAX)
				var top := float(y * C + C) - hgt
				var churn := 0.5 + 0.5 * sin(r.t * 1.7 + x * 0.9 + y * 1.3)
				var deep := Color(0.55, 0.08, 0.02).lerp(Color(0.85, 0.22, 0.04), churn * 0.6)
				draw_rect(Rect2(x * C, top, C, hgt), deep)
				if not full:
					# the surface: bright, with darker drifting crust plates
					draw_rect(Rect2(x * C, top, C, 2), Color(1.0, 0.72, 0.28))
					var plate := fposmod(r.t * 3.0 + x * 7.0, 16.0)
					draw_rect(Rect2(x * C + plate * 0.6, top + 1, 5, 2), Color(0.3, 0.06, 0.03, 0.85))
				elif (x * 7 + y * 3 + int(r.t * 2.0)) % 9 == 0:
					draw_rect(Rect2(x * C + 5, y * C + 6, 3, 3), Color(1.0, 0.6, 0.2, 0.7))


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
