class_name CollapseSystem
extends Node2D
## Bounded ceiling-instability mechanic.
##
## A full rigid-body simulation of the whole mine is explicitly out of scope, so
## this uses a small, readable rule instead: when a load-bearing cell is removed,
## scan a short column above it. An unsupported cluster of solid cells larger
## than COLLAPSE_MIN_CLUSTER starts to crumble: it is telegraphed (cracks + dust
## + rattle), then drops as a limited cascade.
##
## Mission-critical cells are protected and can never collapse, and after every
## cascade the spawn -> relic -> lift route is re-verified so a collapse can
## never permanently softlock the run.

const MAX_PENDING := 12
const SCAN_UP := 8

var grid: TerrainGrid
var renderer: TerrainRenderer
var player: Player

var _pending: Dictionary = {}       # cluster key -> {"cells": Array, "t": float}
var _rng := RandomNumberGenerator.new()
var _check_timer: float = 0.0
var _on_collapse: Callable = Callable()

func setup(p_grid: TerrainGrid, p_renderer: TerrainRenderer, p_player: Player,
		on_collapse: Callable = Callable()) -> void:
	grid = p_grid
	renderer = p_renderer
	player = p_player
	_on_collapse = on_collapse
	_rng.randomize()
	grid.cell_changed.connect(_on_cell_changed)

func _on_cell_changed(x: int, y: int, mat: int) -> void:
	if mat != Balance.Mat.EMPTY:
		return
	_scan_above(x, y)

func _scan_above(x: int, y: int) -> void:
	if _pending.size() >= MAX_PENDING:
		return
	# Walk up while cells are solid, collecting the unsupported column.
	var cells: Array = []
	var cy: int = y - 1
	var guard: int = 0
	while cy >= 0 and guard < SCAN_UP:
		guard += 1
		var mat: int = grid.get_material(x, cy)
		if mat == Balance.Mat.EMPTY:
			break
		if mat == Balance.Mat.BEDROCK or grid.is_protected(x, cy):
			return
		cells.append(Vector2i(x, cy))
		cy -= 1
	if cells.size() < Balance.COLLAPSE_MIN_CLUSTER:
		return
	if cells.size() > Balance.COLLAPSE_MAX_CLUSTER:
		cells = cells.slice(0, Balance.COLLAPSE_MAX_CLUSTER)
	# Widen slightly for a chunkier, more satisfying cascade.
	var extra: Array = []
	for c in cells:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0)]:
			var n: Vector2i = c + d
			if grid.in_bounds(n.x, n.y) and grid.get_material(n.x, n.y) != Balance.Mat.EMPTY \
					and not grid.is_protected(n.x, n.y):
				if not extra.has(n) and extra.size() < 6:
					extra.append(n)
	var cluster: Array = cells + extra
	var key: String = "%d_%d_%d" % [x, y, Time.get_ticks_msec() / 1000]
	_pending[key] = {"cells": cluster, "t": Balance.COLLAPSE_TELEGRAPH}
	_telegraph(cluster)

func _telegraph(cluster: Array) -> void:
	var first: Vector2i = cluster[0]
	Audio.play_at("rattle", grid.cell_to_world(first), player.global_position if player else Vector2.ZERO, 900.0)
	for c in cluster:
		# Pre-damage the cells so the renderer shows the cracked variant: the
		# warning is visible in-world with no extra sprite work.
		var mat: int = grid.get_material(c.x, c.y)
		var hp: int = Balance.MATERIAL_HP.get(mat, 1)
		if hp > 1:
			grid.damage[grid.idx(c.x, c.y)] = hp - 1
			grid.mark_dirty(c.x, c.y)
		Fx.dust(grid.cell_to_world(c), 3, 0.6)

func _process(delta: float) -> void:
	var finished: Array = []
	for key in _pending:
		var entry: Dictionary = _pending[key]
		entry["t"] -= delta
		if entry["t"] <= 0.0:
			finished.append(key)
	for key in finished:
		var entry: Dictionary = _pending[key]
		_pending.erase(key)
		_collapse(entry["cells"])
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 1.5
		_verify_routes()

func _collapse(cluster: Array) -> void:
	var cell: Vector2i = cluster[0]
	Audio.play_at("rattle", grid.cell_to_world(cell), player.global_position if player else Vector2.ZERO, 1100.0)
	Fx.shake(4.5)
	for c in cluster:
		var mat: int = grid.get_material(c.x, c.y)
		if mat == Balance.Mat.EMPTY:
			continue
		var wp: Vector2 = grid.cell_to_world(c)
		# Ore in a collapsing cell is lost to the rubble: this is the danger.
		grid.set_material(c.x, c.y, Balance.Mat.EMPTY)
		Fx.debris(wp, mat, 8, 1.2)
		Fx.dust(wp, 6, 1.2)
		if player and player.global_position.distance_to(wp) < Balance.CELL * 1.6:
			player.take_damage(8, "rubble")
	if _on_collapse.is_valid():
		_on_collapse.call(cluster)

## Re-verify that the run is still completable. Cheap enough at 1.5 s cadence.
func _verify_routes() -> void:
	if player == null or grid == null:
		return
	var spawn: Vector2i = grid.spawn_cell
	var target: Vector2i = Vector2i(grid.relic_cell.x, grid.relic_cell.y - 2)
	if not grid.reachable(spawn, target, 60000):
		_carve_repair(spawn, target)
	if not grid.reachable(target, grid.lift_cell, 60000):
		_carve_repair(target, grid.lift_cell)

func _carve_repair(a: Vector2i, b: Vector2i) -> void:
	var x: int = a.x
	var y: int = a.y
	while x != b.x:
		_carve(x, y)
		x += signi(b.x - x)
	while y != b.y:
		_carve(x, y)
		y += signi(b.y - y)
	_carve(b.x, b.y)
	Fx.shake(2.0)

func _carve(x: int, y: int) -> void:
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var nx: int = x + dx
			var ny: int = y + dy
			if grid.in_bounds(nx, ny):
				var mat: int = grid.get_material(nx, ny)
				if mat != Balance.Mat.BEDROCK:
					grid.set_material(nx, ny, Balance.Mat.EMPTY)
