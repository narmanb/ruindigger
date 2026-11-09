class_name WaterProp
extends RigidBody2D
## Limited meaningful props; collider layer 4 never blocks the player (layer 2).
## They exchange momentum with rock and each other, sample the same water motion
## as characters, and can always be cleared with the existing drill.

var grid: TerrainGrid
var water: WaterSim
var mine: Node
var kind := "stone"
var half := Vector2(5, 5)
var buoyancy := 0.15
var water_drag := 1.0
var durability := 4.0
var _hit_t := 0.0


func configure(prop_kind: String) -> void:
	kind = prop_kind if Balance.WATER_PROPS.has(prop_kind) else "stone"
	var spec: Dictionary = Balance.WATER_PROPS[kind]
	mass = spec.mass
	buoyancy = spec.buoyancy
	water_drag = spec.drag
	durability = spec.hp
	half = spec.half
	collision_layer = 4
	collision_mask = 1 | 4
	gravity_scale = 0.0
	linear_damp = Balance.PROP_AIR_DAMP
	angular_damp = Balance.PROP_SPIN_DAMP
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE


func _ready() -> void:
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = half * 2.0
	collider.shape = shape
	add_child(collider)
	var pm := PhysicsMaterial.new()
	pm.friction = Balance.PROP_FRICTION
	pm.bounce = Balance.PROP_BOUNCE
	physics_material_override = pm


func fluid_acceleration() -> Vector2:
	var acceleration := Vector2(0, Balance.GRAVITY)
	if water == null:
		return acceleration
	# Expand the sample box when rotated so a bobbing crate follows its actual
	# exposed extent instead of jumping between submerged and dry states.
	var wet := water.immersion(global_position, half)
	var flow := water.sample_contact(global_position, half)
	acceleration.y -= Balance.GRAVITY * buoyancy * wet
	acceleration += (flow - linear_velocity) * water_drag * maxf(wet, minf(1.0, flow.length() / Balance.WATER_FLOW_MAX))
	return acceleration


func _physics_process(delta: float) -> void:
	_hit_t = maxf(0.0, _hit_t - delta)
	var accel := fluid_acceleration()
	if sleeping and (accel.y < 0.0 or accel.x * accel.x > Balance.PROP_WAKE_ACCEL * Balance.PROP_WAKE_ACCEL):
		sleeping = false
	if not sleeping:
		apply_central_force(accel * mass)
		linear_velocity = linear_velocity.limit_length(Balance.PROP_MAX_SPEED)
		angular_velocity = clampf(angular_velocity, -Balance.PROP_MAX_SPIN, Balance.PROP_MAX_SPIN)
	if mine and _hit_t <= 0.0 and linear_velocity.length() > Balance.PROP_HIT_SPEED:
		for e in mine.enemies.duplicate():
			if is_instance_valid(e) and e.hit_rect().grow(half.length()).has_point(global_position):
				e.hit(minf(Balance.PROP_MAX_DAMAGE, linear_velocity.length() * mass * Balance.PROP_DAMAGE_SCALE), global_position)
				_hit_t = Balance.PROP_HIT_GRACE
				break


func damage(amount: float) -> void:
	durability -= amount
	if durability <= 0.0:
		queue_free()


func _draw() -> void:
	var rect := Rect2(-half, half * 2.0)
	match kind:
		"crate":
			draw_rect(rect, Color("805134"))
			draw_rect(rect.grow(-1), Color("bd8850"), false, 1.0)
			draw_line(-half + Vector2.ONE, half - Vector2.ONE, Color("e0b571"), 2.0)
			draw_line(Vector2(-half.x + 1, half.y - 1), Vector2(half.x - 1, -half.y + 1), Color("593d2e"), 1.0)
		"canister":
			draw_rect(rect, Color("426d70"))
			draw_rect(Rect2(-half.x, -half.y + 2, half.x * 2, 2), Color("a0d0bc"))
			draw_rect(Rect2(-half.x, half.y - 3, half.x * 2, 2), Color("a0d0bc"))
		"scrap":
			draw_rect(rect, Color("6a6d87"))
			draw_line(-half, Vector2(half.x, -half.y), Color("bcb5c6"), 2.0)
		_:
			draw_colored_polygon(PackedVector2Array([Vector2(-half.x, 0), Vector2(-half.x + 2, -half.y), Vector2(half.x - 1, -half.y), half, Vector2(-half.x + 1, half.y)]), Color("736d7e"))
			draw_line(Vector2(-half.x + 2, -half.y), Vector2(half.x - 1, -half.y), Color("b0a7ae"), 1.0)
