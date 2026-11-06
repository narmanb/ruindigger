class_name SentryShot
extends Node2D
## Dodgeable enemy projectile.

var grid: TerrainGrid
var player: Player
var dir: Vector2 = Vector2.RIGHT
var speed: float = Balance.SENTRY_SHOT_SPEED
var damage: int = Balance.SENTRY_SHOT_DAMAGE
var life: float = 3.0

func _ready() -> void:
	z_index = 22

func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	var step: Vector2 = dir * speed * delta
	global_position += step
	queue_redraw()
	# Terrain hit
	var c: Vector2i = grid.world_to_cell(global_position)
	if grid.get_material(c.x, c.y) != Balance.Mat.EMPTY:
		Fx.sparks(global_position, 6, false)
		Fx.dust(global_position, 3, 0.6)
		queue_free()
		return
	# Player hit
	if player and is_instance_valid(player):
		if global_position.distance_to(player.global_position) < 12.0:
			player.take_damage(damage, "sentry")
			queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 4.5, Color(1.0, 0.4, 0.3, 0.35))
	draw_circle(Vector2.ZERO, 2.6, Color(1.0, 0.6, 0.4))
	draw_circle(Vector2.ZERO, 1.2, Color(1.0, 0.95, 0.85))
	draw_line(-dir * 10.0, -dir * 4.0, Color(1.0, 0.5, 0.3, 0.4), 2.0)
