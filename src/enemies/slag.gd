class_name Slag
extends PoolDweller
## Slag salamander (The First Civilization): a lizard of cooling slag that
## lives in lava and climbs out to hunt. Lava and steam do not hurt it. Out
## of lava it cools after SLAG_COOL seconds: it slows and heads back.
## Water or a cryo canister quenches it: it sets into a block of rock where
## it stands, with aetherite in it. Lure it through a puddle, pour a tank
## on it, or throw cryo.

var quenched := false


func _ready() -> void:
	super._ready()
	hp = Balance.SLAG_HP
	max_hp = hp
	sight = Balance.SLAG_SIGHT
	bite = Balance.SLAG_DAMAGE
	bite_name = "slag salamander"
	water_hurts = false
	dry_limit = Balance.SLAG_COOL
	speed_wet = Balance.SLAG_SPEED_WET
	speed_dry = Balance.SLAG_SPEED_DRY
	spr.texture = load("res://assets/gen/slag.png")
	eye_glow.scale = Vector2(0.5, 0.5)


func hit_rect() -> Rect2:
	return Rect2(global_position - Vector2(10, 7), Vector2(20, 14))


func in_pool(c: Vector2i) -> bool:
	return grid.get_lava(c.x, c.y) >= Balance.LAVA_MAX / 2


func _tune() -> void:
	super._tune()
	if not wet() and parched():
		speed_patrol = float(Balance.SLAG_SPEED_COLD[0])
		speed_chase = float(Balance.SLAG_SPEED_COLD[1])


func _physics_process(delta: float) -> void:
	if state == S.DEAD:
		return
	if grid.get_water(cell.x, cell.y) >= Balance.SLAG_QUENCH_WATER:
		quench()
		return
	super._physics_process(delta)
	if state != S.DEAD and not wet() and randf() < 0.06:
		mine.fx.sparks(global_position + Vector2(0, 4), Vector2.UP, Color(1.0, 0.55, 0.2))


## Lava and steam are home to it.
func hit(dmg: float, from: Vector2, knock: bool = true) -> void:
	if last_hit in ["lava", "steam"]:
		return
	super.hit(dmg, from, knock)


## Water or cryo: it sets into rock where it stands. Returns true if a block
## of rock (with aetherite) was left behind.
func quench(cause: String = "quench") -> bool:
	if state == S.DEAD:
		return false
	quenched = true
	last_hit = cause
	var c := cell
	var pos := global_position
	var placed := false
	var pl: Player = mine.player
	var blocked: bool = pl != null and Rect2(pl.global_position - Player.HALF, Player.HALF * 2.0).grow(2.0).intersects(Rect2(c.x * 16, c.y * 16, 16, 16))
	if grid.get_lava(c.x, c.y) > 0:
		if mine.get("lava") != null:
			mine.lava.quench(c)         # in lava, it just crusts over with the rest
	elif not grid.is_solid(c.x, c.y) and grid.get_mat(c.x, c.y) == Cell.AIR and not blocked:
		var i := grid.idx(c.x, c.y)
		grid.ore[i] = Cell.ORE_AETHER
		grid.set_mat(c.x, c.y, Cell.HARD)
		grid.flags[i] &= ~(Cell.F_DUG | Cell.F_CLAIMED)
		placed = true
	mine.fx.dust(pos, Color(0.85, 0.85, 0.9), 10)
	mine.fx.burst(pos, Color(0.5, 0.5, 0.55), 12)
	Audio.play_at("gas_hiss", pos, 0.0, 0.2, 0.0)
	mine.tell_once("t_quench", "THE SALAMANDER SET INTO STONE - there is aetherite in it")
	die()
	return placed


func _visual() -> void:
	super._visual()
	var cold := not wet() and parched()
	spr.modulate = Color(0.7, 0.7, 0.78) if cold else Color.WHITE
	eye_glow.global_position = global_position
	var k := 0.25 if cold else 0.6 + 0.15 * sin(anim_t * 5.0)
	eye_glow.modulate = Color(1.0, 0.5, 0.15, k * (0.0 if state == S.STUNNED else 1.0))
