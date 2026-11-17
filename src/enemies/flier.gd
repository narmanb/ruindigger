class_name Flier
extends Crawler
## Flier: a rare moth-drone. It hunts like a crawler (sight, noise, lures) but
## flies: any open cell is a path, so shafts, caverns and open water gaps do
## not stop it. It is fragile, never tunnels, and bobs as it moves.

var _bob := 0.0


func _ready() -> void:
	super._ready()
	hp = Balance.FLIER_HP
	max_hp = hp
	speed_patrol = Balance.FLIER_SPEED_PATROL
	speed_chase = Balance.FLIER_SPEED_CHASE
	bite = Balance.FLIER_DAMAGE
	sight = Balance.FLIER_SIGHT
	bite_name = "flier"
	spr.texture = load("res://assets/gen/flier.png")
	spr.hframes = 4
	spr.vframes = 3
	spr.offset = Vector2.ZERO
	_bob = randf() * TAU


func hit_rect() -> Rect2:
	return Rect2(global_position - Vector2(8, 7), Vector2(16, 13))


## Any open cell will do: it needs no surface to cling to.
func walkable(c: Vector2i) -> bool:
	return grid.in_bounds(c.x, c.y) and not grid.is_solid(c.x, c.y)


## Fliers finish their approach right to the goal cell (see Crawler).
func _plan(goal: Vector2i) -> void:
	super._plan(goal)
	_finish_approach(goal)


func _begin_tunnel() -> void:
	pass          # it cannot chew rock


func _wander() -> void:
	var opts: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + d
		if walkable(n) and (n - home).length() < 8 and grid.get_water(n.x, n.y) == 0:
			opts.append(n)
	if not opts.is_empty():
		path = [opts[randi() % opts.size()]]


func _visual() -> void:
	_bob += get_physics_process_delta_time() * 7.0
	var anims: Dictionary = SpriteDB.meta().get("flier", {}).get("anims", {})
	var anim := "fly"
	if state == S.STUNNED:
		anim = "stun"
	elif windup > 0.0 or attack_cd > Balance.CRAWLER_ATTACK_COOLDOWN - 0.25:
		anim = "attack"
	if flash > 0.5:
		anim = "hurt"
	var a: Array = anims.get(anim, [0, 4])
	spr.frame = int(a[0]) + int(anim_t * 14.0) % int(a[1])
	spr.rotation = 0.0
	spr.flip_h = facing < 0
	# a stunned flier drops to the floor of its cell; otherwise it bobs
	spr.position = Vector2(0, 5) if state == S.STUNNED else Vector2(0, sin(_bob) * 2.0).round()
	mat.set_shader_parameter("flash", clampf(flash, 0.0, 0.6 if Settings.reduced_flashing() else 1.0))
	if windup > 0.0:
		queue_redraw()
	eye_glow.global_position = global_position + spr.position + Vector2(facing * 5, -1)
	var alert := state in [S.CHASE, S.TUNNEL]
	eye_glow.modulate = Color(1.0, 0.25, 0.2, 0.8) if alert else Color(1.0, 0.65, 0.2, 0.5)
