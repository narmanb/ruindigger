class_name TerrainRenderer
extends Node2D
## Derives all terrain visuals from the authoritative TerrainGrid.
##
## Uses a TileMapLayer with a runtime-built TileSet from the baked atlas. Only
## dirty chunks are re-emitted, so drilling never rebuilds the whole mine.
## A fog overlay (ImageTexture + shader) handles unexplored darkness.

const ATLAS_PNG := "res://assets/tiles/terrain_atlas.png"
const ATLAS_JSON := "res://assets/tiles/terrain_atlas.json"

var grid: TerrainGrid
var layer: TileMapLayer
var fog_sprite: Sprite2D

var _tile_size: int = 16
var _variants: int = 2
var _rows: Dictionary = {}
var _row_names: Dictionary = {}       # "stratum:material:stage" -> row
var _source_id: int = 0
var ore_layer: TileMapLayer
var _ore_source_id: int = 0
var _ore_tex: Texture2D

var _fog_img: Image
var _fog_tex: ImageTexture
var _fog_dirty: bool = true
var _revealed := {}

func setup(p_grid: TerrainGrid) -> void:
	grid = p_grid
	_load_meta()
	_build_tileset()
	_build_fog()

func _load_meta() -> void:
	var f := FileAccess.open(ATLAS_JSON, FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(d) == TYPE_DICTIONARY:
			_tile_size = int(d.get("tile", 16))
			_variants = int(d.get("variants", 2))
			_rows = d.get("rows", {})
			_row_names = {}
			for k in _rows:
				_row_names[k] = int(_rows[k])

func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(_tile_size, _tile_size)
	var src := TileSetAtlasSource.new()
	src.texture = load(ATLAS_PNG)
	var cols: int = int(src.texture.get_width() / _tile_size)
	var rws: int = int(src.texture.get_height() / _tile_size)
	src.texture_region_size = Vector2i(_tile_size, _tile_size)
	for y in rws:
		for x in cols:
			src.create_tile(Vector2i(x, y))
	_source_id = ts.add_source(src)
	layer = TileMapLayer.new()
	layer.tile_set = ts
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.z_index = 5
	add_child(layer)

	# Ore overlay: one atlas row of 16 px ore tiles.
	var ore_ts := TileSet.new()
	ore_ts.tile_size = Vector2i(_tile_size, _tile_size)
	var ore_src := TileSetAtlasSource.new()
	_ore_tex = load("res://assets/sprites/ore_sheet.png")
	ore_src.texture = _ore_tex
	ore_src.texture_region_size = Vector2i(_tile_size, _tile_size)
	var ore_cols: int = int(_ore_tex.get_width() / _tile_size)
	for x in ore_cols:
		ore_src.create_tile(Vector2i(x, 0))
	_ore_source_id = ore_ts.add_source(ore_src)
	ore_layer = TileMapLayer.new()
	ore_layer.tile_set = ore_ts
	ore_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ore_layer.z_index = 6
	ore_layer.modulate = Color(1.25, 1.25, 1.25, 1.0)
	add_child(ore_layer)

func _build_fog() -> void:
	_fog_img = Image.create(grid.w, grid.h, false, Image.FORMAT_L8)
	_fog_img.fill(Color(0, 0, 0))
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	fog_sprite = Sprite2D.new()
	fog_sprite.texture = _fog_tex
	fog_sprite.centered = false
	fog_sprite.position = Vector2.ZERO
	fog_sprite.z_index = 40
	fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float darkness : hint_range(0.0, 1.0) = 0.93;
void fragment() {
	float e = texture(TEXTURE, UV).r;
	float a = (1.0 - smoothstep(0.05, 0.95, e)) * darkness;
	COLOR = vec4(0.016, 0.014, 0.028, a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	fog_sprite.material = mat
	add_child(fog_sprite)

# ---------------------------------------------------------------------------

func refresh_all() -> void:
	for cy in grid._chunks_y:
		for cx in grid._chunks_x:
			refresh_chunk(cx, cy)
	_fog_dirty = true

func refresh_dirty(limit: int = 8) -> void:
	var keys: Array = grid.flush_dirty(limit)
	for key in keys:
		refresh_chunk(key.x, key.y)

func refresh_chunk(cx: int, cy: int) -> void:
	if layer == null or grid == null:
		return
	var x0: int = cx * grid.chunk
	var y0: int = cy * grid.chunk
	var x1: int = mini(x0 + grid.chunk, grid.w)
	var y1: int = mini(y0 + grid.chunk, grid.h)
	for y in range(y0, y1):
		for x in range(x0, x1):
			_set_cell(x, y)

func _set_cell(x: int, y: int) -> void:
	var mat := grid.get_material(x, y)
	if mat == Balance.Mat.EMPTY:
		layer.erase_cell(Vector2i(x, y))
		ore_layer.erase_cell(Vector2i(x, y))
		return
	var stage: int = _stage_for(x, y, mat)
	var stratum: String = grid.stratum_at(y)
	var key := "%s:%s:%d" % [stratum, _material_key(mat), stage]
	var row: int = int(_row_names.get(key, 0))
	var mask: int = grid.mask_at(x, y)
	var col: int = mask * _variants + int(grid.variant[grid.idx(x, y)]) % _variants
	layer.set_cell(Vector2i(x, y), _source_id, Vector2i(col, row))
	var ore_id: int = grid.get_ore(x, y)
	if ore_id > 0:
		ore_layer.set_cell(Vector2i(x, y), _ore_source_id,
				Vector2i(clampi(ore_id - 1, 0, 5), 0))
	else:
		ore_layer.erase_cell(Vector2i(x, y))

func _material_key(mat: int) -> String:
	match mat:
		Balance.Mat.SOIL: return "soil"
		Balance.Mat.BASALT: return "basalt"
		Balance.Mat.ALLOY: return "alloy"
		Balance.Mat.BEDROCK: return "bedrock"
		_: return "soil"

func _stage_for(x: int, y: int, mat: int) -> int:
	if mat == Balance.Mat.BEDROCK:
		return 0
	var hp: int = Balance.MATERIAL_HP.get(mat, 1)
	if hp <= 0:
		return 0
	var dmg: int = grid.get_damage(x, y)
	if dmg <= 0:
		return 0
	if dmg >= hp - 1 and hp > 1:
		return 2 if dmg >= hp else 1
	return 1

## Reveal the fog around a world position with a soft radius.
func reveal(world_pos: Vector2, radius_cells: float, reveal_map: bool = true) -> void:
	var c := grid.world_to_cell(world_pos)
	var r := int(ceil(radius_cells))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var nx: int = c.x + dx
			var ny: int = c.y + dy
			if not grid.in_bounds(nx, ny):
				continue
			var d: float = sqrt(float(dx * dx + dy * dy))
			if d > radius_cells:
				continue
			var strength: float = 1.0 - (d / radius_cells)
			var cur: float = _fog_img.get_pixel(nx, ny).r
			var val: float = maxf(cur, clampf(strength * 1.6, 0.0, 1.0))
			if val > cur + 0.004:
				_fog_img.set_pixel(nx, ny, Color(val, val, val))
				_fog_dirty = true
				if reveal_map:
					grid.mark_explored(nx, ny)

func _process(_delta: float) -> void:
	if _fog_dirty and _fog_tex:
		_fog_tex.update(_fog_img)
		_fog_dirty = false

func clear_fog_visual() -> void:
	if _fog_img:
		_fog_img.fill(Color(1, 1, 1))
		_fog_tex.update(_fog_img)
