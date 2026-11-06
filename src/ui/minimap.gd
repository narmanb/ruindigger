class_name Minimap
extends Control
## Fog-of-war minimap built from the grid's explored flags. One pixel per cell,
## updated incrementally (only newly explored or edited cells are rewritten).

var mine: Node
var grid: TerrainGrid
var img: Image
var tex: ImageTexture
var _dirty := false
var _upload_t := 0.0
var view_cells := Vector2i(52, 26)
var scale_px := 2.0
var full := false   # full-map mode (pause screen)


func setup(m: Node) -> void:
	mine = m
	grid = m.grid
	img = Image.create(grid.w, grid.h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	tex = ImageTexture.create_from_image(img)
	grid.cell_changed.connect(_on_changed)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func cell_color(g: TerrainGrid, x: int, y: int) -> Color:
	var m := g.get_mat(x, y)
	var s := g.get_stratum(x, y)
	var o := g.get_ore(x, y)
	if o != 0 and Cell.is_solid(m):
		return Balance.ore_color(o)
	match m:
		Cell.AIR:
			return Color(0.05, 0.04, 0.07, 0.85)
		Cell.LADDER:
			return Color(0.85, 0.7, 0.3, 0.9)
		Cell.PLATFORM:
			return Color(0.6, 0.45, 0.3, 0.9)
		Cell.SOFT, Cell.CRACKED:
			return [Color("7d4c25"), Color("1f5a50"), Color("4a3c56")][s]
		Cell.HARD:
			return [Color("8a8078"), Color("4c6378"), Color("5b4a70")][s]
		Cell.LOOSE:
			return Color("c9a86e")
		Cell.ALLOY:
			return Color("9b7cff")
		Cell.GAS:
			return Color("b6e03a")
		Cell.BEDROCK:
			return Color("1a1724")
	return Color.MAGENTA


func _on_changed(x: int, y: int, _o: int, _n: int) -> void:
	if grid.has_flag(x, y, Cell.F_EXPLORED):
		img.set_pixel(x, y, cell_color(grid, x, y))
		_dirty = true


func _process(delta: float) -> void:
	if grid == null:
		return
	for c in grid.take_explored():
		img.set_pixel(c.x, c.y, cell_color(grid, c.x, c.y))
		_dirty = true
	_upload_t -= delta
	if _dirty and _upload_t <= 0.0:
		_upload_t = 0.2
		_dirty = false
		tex.update(img)
	queue_redraw()


func _draw() -> void:
	if mine == null or mine.player == null or tex == null:
		return
	var pc: Vector2 = mine.player.global_position / Balance.CELL
	var area := size
	var sc := scale_px
	var origin := Vector2.ZERO
	var src: Rect2
	if full:
		sc = minf(area.x / grid.w, area.y / grid.h)
		var w := grid.w * sc
		var h := grid.h * sc
		origin = Vector2((area.x - w) * 0.5, (area.y - h) * 0.5)
		src = Rect2(0, 0, grid.w, grid.h)
	else:
		var vc := Vector2(area.x / sc, area.y / sc)
		var tl := (pc - vc * 0.5).clamp(Vector2.ZERO, Vector2(grid.w, grid.h) - vc)
		src = Rect2(tl, vc)
	draw_rect(Rect2(Vector2.ZERO, area), Color(0.02, 0.015, 0.03, 0.85))
	draw_texture_rect_region(tex, Rect2(origin, src.size * sc), src)
	var t := Time.get_ticks_msec() / 1000.0
	# markers
	for l in mine.lifts:
		var lc: Vector2 = l.global_position / Balance.CELL
		if grid.has_flag(int(lc.x), int(lc.y) - 1, Cell.F_EXPLORED) or l.id == "surface":
			_marker(origin + (lc - src.position) * sc, Color(0.3, 1.0, 0.4) if l.active else Color(1.0, 0.5, 0.2), 3.0, area)
	if mine.relic and not mine.relic.taken:
		var rc: Vector2 = mine.relic.global_position / Balance.CELL
		if grid.has_flag(int(rc.x), int(rc.y), Cell.F_EXPLORED):
			_marker(origin + (rc - src.position) * sc, Color(0.4, 1.0, 1.0), 3.0, area)
	if int(t * 3.0) % 2 == 0 or full:
		_marker(origin + (pc - src.position) * sc, Color(1.0, 0.75, 0.3), 2.5, area)
	draw_rect(Rect2(Vector2.ZERO, area), Color(0.35, 0.28, 0.5), false, 1.0)


func _marker(p: Vector2, c: Color, r: float, area: Vector2) -> void:
	if p.x < 0 or p.y < 0 or p.x > area.x or p.y > area.y:
		return
	draw_rect(Rect2(p - Vector2(r, r) * 0.5 - Vector2.ONE, Vector2(r, r) + Vector2(2, 2)), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(p - Vector2(r, r) * 0.5, Vector2(r, r)), c)
