class_name Eel
extends PoolDweller
## Eel: a pale, frilled hunter of flooded places. In water it is fast and
## bites hard, and you are slow there. Out of water it flops along, bites
## weakly, takes double damage, and after EEL_DRY_LIMIT seconds it turns
## back and starts to dry out. So: fight it on dry ground, or drain its pool
## (breach the wall, drill the floor) and leave it stranded.


func _ready() -> void:
	super._ready()
	hp = Balance.EEL_HP
	max_hp = hp
	sight = Balance.EEL_SIGHT
	bite_name = "eel"
	water_hurts = false
	dry_limit = Balance.EEL_DRY_LIMIT
	speed_wet = Balance.EEL_SPEED_WET
	speed_dry = Balance.EEL_SPEED_DRY
	spr.texture = load("res://assets/gen/eel.png")
	eye_glow.scale = Vector2(0.3, 0.3)


func hit_rect() -> Rect2:
	return Rect2(global_position - Vector2(10, 6), Vector2(20, 12))


func in_pool(c: Vector2i) -> bool:
	return grid.get_water(c.x, c.y) >= Balance.WATER_MAX / 2


func _tune() -> void:
	super._tune()
	bite = Balance.EEL_DAMAGE_WET if wet() else Balance.EEL_DAMAGE_DRY


func _physics_process(delta: float) -> void:
	if state == S.DEAD:
		return
	if parched() and not asleep:
		last_hit = "dry"
		hit(Balance.EEL_DRY_DPS * delta, global_position, false)
		if state == S.DEAD:
			return
	super._physics_process(delta)


func hit(dmg: float, from: Vector2, knock: bool = true) -> void:
	if not wet() and last_hit != "dry":
		dmg *= Balance.EEL_DRY_VULN
	super.hit(dmg, from, knock)


func _visual() -> void:
	super._visual()
	var dry := not wet()
	# its belly light: bright in water, guttering out of it
	var k := 0.25 + 0.15 * sin(anim_t * 12.0) if dry else 0.8
	if parched():
		k *= 0.5
	eye_glow.global_position = global_position
	eye_glow.modulate = Color(0.35, 0.75, 1.0, k * (0.0 if state == S.STUNNED else 1.0))
	spr.modulate = Color(0.75, 0.72, 0.68) if parched() else Color.WHITE
	if dry and state != S.STUNNED:
		spr.position += Vector2(0, absf(sin(anim_t * 9.0)) * -2.0).round()     # flopping
