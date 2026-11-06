class_name DemoCharge
extends Node2D
## Timed demolition charge. Telegraphs its blast radius, then destroys a
## circular cluster of weaker tiles and damages enemies caught inside.

var grid: TerrainGrid
var thrower: Node = null
var fuse: float = Balance.CHARGE_FUSE
var _rng := RandomNumberGenerator.new()
var _blink: float = 0.0

func _ready() -> void:
	_rng.randomize()
	z_index = 25
	Audio.play("ui_click", 0.0, -6.0)

func _process(delta: float) -> void:
	fuse -= delta
	_blink += delta
	queue_redraw()
	if fuse <= 0.0:
		detonate()

func _draw() -> void:
	var r := Balance.CHARGE_RADIUS * Balance.CELL
	var pulse := 0.5 + 0.5 * sin(_blink * 18.0)
	var warn := Color(1.0, 0.45, 0.2, 0.10 + 0.12 * pulse)
	draw_circle(Vector2.ZERO, r, warn)
	draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(1.0, 0.6, 0.3, 0.5 + 0.4 * pulse), 2.0)
	draw_circle(Vector2.ZERO, 5.0, Color(0.9, 0.3, 0.2))
	draw_circle(Vector2.ZERO, 2.5, Color(1.0, 0.8, 0.5, 0.6 + 0.4 * pulse))

func detonate() -> void:
	var cell: Vector2i = grid.world_to_cell(global_position)
	var radius := Balance.CHARGE_RADIUS
	# Blast the terrain.
	var broken: Array = grid.damage_radius(cell.x, cell.y, radius, Balance.CHARGE_TILE_DAMAGE, 99, true)
	# Gather gas pockets in range and ignite them.
	var ignited: Array = []
	for dy in range(-int(radius) - 1, int(radius) + 2):
		for dx in range(-int(radius) - 1, int(radius) + 2):
			var nx := cell.x + dx
			var ny := cell.y + dy
			if grid.in_bounds(nx, ny) and grid.gas.has(grid.idx(nx, ny)):
				ignited.append(Vector2i(nx, ny))

	Audio.play("explosion", 0.05, 0.0)
	Fx.burst_ring(global_position, radius * Balance.CELL, Color(1.0, 0.8, 0.4, 0.7))
	Fx.sparks(global_position, 24, true)
	Fx.dust(global_position, 22, 2.0)
	Fx.debris(global_position, Balance.Mat.BASALT, 24, 1.8)
	Fx.shake(9.0)
	for b in broken:
		grid.set_material(b.x, b.y, Balance.Mat.EMPTY)

	# Damage enemies and the player.
	var r_world: float = radius * Balance.CELL
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.has_method("take_damage"):
			var d: float = node.global_position.distance_to(global_position)
			if d <= r_world:
				var falloff: float = 1.0 - clampf(d / r_world, 0.0, 1.0) * 0.6
				node.take_damage(int(Balance.CHARGE_ENEMY_DAMAGE * falloff), global_position)
	if thrower != null and is_instance_valid(thrower):
		var dp: float = thrower.global_position.distance_to(global_position)
		if dp <= r_world and thrower.has_method("take_damage"):
			var falloff: float = 1.0 - clampf(dp / r_world, 0.0, 1.0) * 0.6
			thrower.take_damage(int(Balance.CHARGE_PLAYER_DAMAGE * falloff), "blast")

	# Ignite gas pockets with a chained, readable delay.
	for i in ignited.size():
		var gp: Vector2i = ignited[i]
		if grid.gas.has(grid.idx(gp.x, gp.y)):
			grid.gas.erase(grid.idx(gp.x, gp.y))
			_chain_gas(grid.cell_to_world(gp), i * 0.06)
	queue_free()

func _chain_gas(wp: Vector2, delay: float) -> void:
	var timer := get_tree().create_timer(maxf(0.02, delay))
	timer.timeout.connect(func():
		Audio.play_at("gas_hiss", wp, global_position, 900.0)
		Fx.dust(wp, 12, 1.4)
		Fx.sparks(wp, 10, true)
	)
