extends Control
## Legible minimap. Draws only explored cells (fog of war), solid vs open, ore
## glints, the player, the lift and the relic. `compact` scales it down for the
## in-game corner; the pause screen uses the same control at full size.

var mine
var compact: bool = false
var scale_px: float = 2.0
var _tex: ImageTexture
var _img: Image
var _dirty: bool = true
var _accum: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ensure_image() -> void:
	if _img != null or mine == null or mine.grid == null:
		return
	var g: TerrainGrid = mine.grid
	_img = Image.create(g.w, g.h, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0))
	_tex = ImageTexture.create_from_image(_img)

func _process(delta: float) -> void:
	_accum += delta
	if _accum < 0.25:
		return
	_accum = 0.0
	_ensure_image()
	if _img == null:
		return
	_redraw_image()
	queue_redraw()

func _redraw_image() -> void:
	var g: TerrainGrid = mine.grid
	var revealed := {}
	for y in g.h:
		for x in g.w:
			if not g.is_explored(x, y):
				continue
			var mat: int = g.get_material(x, y)
			var col: Color
			if mat == Balance.Mat.EMPTY:
				col = Color(0.10, 0.11, 0.15, 1.0)
			elif mat == Balance.Mat.BEDROCK:
				col = Color(0.24, 0.20, 0.28, 1.0)
			elif mat == Balance.Mat.ALLOY:
				col = Color(0.42, 0.36, 0.52, 1.0)
			else:
				col = Color(0.34, 0.28, 0.20, 1.0)
			if g.get_ore(x, y) > 0:
				col = Color(0.95, 0.78, 0.35, 1.0)
			if g.gas.has(g.idx(x, y)):
				col = Color(0.45, 0.75, 0.45, 1.0)
			_img.set_pixel(x, y, col)
	_tex.update(_img)

func _draw() -> void:
	_ensure_image()
	if _tex == null or mine == null:
		return
	var g: TerrainGrid = mine.grid
	var box: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(box, Color(0.04, 0.05, 0.08, 0.78), true)
	draw_rect(box, Color(0.35, 0.45, 0.55, 0.6), false, 1.0)
	var inner: Rect2 = Rect2(Vector2(4, 4), size - Vector2(8, 8))
	# Fit the whole map inside the box.
	var sx: float = inner.size.x / float(g.w)
	var sy: float = inner.size.y / float(g.h)
	var s: float = minf(sx, sy)
	var draw_size: Vector2 = Vector2(g.w * s, g.h * s)
	var origin: Vector2 = inner.position + (inner.size - draw_size) * 0.5
	draw_texture_rect(_tex, Rect2(origin, draw_size), false)

	# Markers
	var lift_c: Vector2i = g.lift_cell
	var p: Vector2 = origin + Vector2((lift_c.x + 0.5) * s, (lift_c.y + 0.5) * s)
	draw_circle(p, 3.5, Color(1.0, 0.78, 0.35))
	if g.is_explored(g.relic_cell.x, g.relic_cell.y) or GameState.relic_taken:
		var rp: Vector2 = origin + Vector2((g.relic_cell.x + 0.5) * s, (g.relic_cell.y + 0.5) * s)
		draw_circle(rp, 3.5, Color(0.72, 0.45, 1.0))
	if mine.player and is_instance_valid(mine.player):
		var pc: Vector2i = g.world_to_cell(mine.player.global_position)
		var pp: Vector2 = origin + Vector2((pc.x + 0.5) * s, (pc.y + 0.5) * s)
		draw_circle(pp, 3.0, Color(1, 1, 1))
		draw_circle(pp, 1.6, Color(1.0, 0.5, 0.2))
