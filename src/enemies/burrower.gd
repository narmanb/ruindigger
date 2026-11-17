class_name Burrower
extends Crawler
## Burrower: a blind, armoured mole-worm. It has no eyes: it comes for noise
## (it hears drilling and blasts from twice as far as a crawler) and only
## feels you directly within BURROWER_SENSE cells, through rock or not.
## Rock is no shelter from it: where a crawler needs an open path, a burrower
## chews straight through sediment, rubble, cracked rock and basalt, leaving
## a tunnel behind. You see the rock crack and spill dust before it breaks
## through. It never digs alloy, bedrock, protected rock, ore, gas sacs, or
## rock that is holding back water or lava. Stay quiet and it loses you.

var dig_cell := Vector2i(-1, -1)
var dig_t := 0.0
var dug := 0


func _ready() -> void:
	super._ready()
	hp = Balance.BURROWER_HP
	max_hp = hp
	speed_patrol = Balance.BURROWER_SPEED_PATROL
	speed_chase = Balance.BURROWER_SPEED_CHASE
	bite = Balance.BURROWER_DAMAGE
	bite_name = "burrower"
	spr.texture = load("res://assets/gen/burrower.png")


func hit_rect() -> Rect2:
	return Rect2(global_position - Vector2(10, 8), Vector2(20, 16))


## Rock it can chew through.
func diggable(c: Vector2i) -> bool:
	if not grid.in_bounds(c.x, c.y) or not Balance.BURROWER_DIG.has(grid.get_mat(c.x, c.y)):
		return false
	if grid.has_flag(c.x, c.y, Cell.F_PROTECTED) or grid.get_ore(c.x, c.y) != 0:
		return false
	if mine.has_method("is_anchored") and mine.is_anchored(c):
		return false
	# never open a way for water or lava
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if grid.get_water(c.x + d.x, c.y + d.y) > 0 or grid.get_lava(c.x + d.x, c.y + d.y) > 0:
			return false
	return true


## Open ground along a surface, as for a crawler.
func open_walk(c: Vector2i) -> bool:
	return super.walkable(c)


## For pathfinding, rock it can chew counts as a way through.
func walkable(c: Vector2i) -> bool:
	return open_walk(c) or diggable(c)


func _begin_tunnel() -> void:
	pass          # its digging happens in _step, not as the crawler's slow chew


func _wander() -> void:
	var opts: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + d
		if open_walk(n) and (n - home).length() < 10:
			opts.append(n)
	if not opts.is_empty():
		path = [opts[randi() % opts.size()]]


## Blind: it feels you only when you are very close, through rock or not.
func _sees_player() -> bool:
	var pl: Player = mine.player
	if pl == null or pl.dead:
		return false
	return pl.global_position.distance_to(global_position) <= Balance.BURROWER_SENSE * Balance.CELL


func hear(pos: Vector2, radius_cells: float) -> void:
	super.hear(pos, radius_cells * Balance.BURROWER_HEARING)


func _step(delta: float) -> void:
	# the next cell on the way is rock: chew it out before moving in
	if move_t >= 1.0 and not path.is_empty() and state in [S.CHASE, S.INVESTIGATE] and hitstun <= 0.0 and windup <= 0.0:
		var n: Vector2i = path[0]
		if n != cell and grid.is_solid(n.x, n.y):
			if not diggable(n) or absi(n.x - cell.x) + absi(n.y - cell.y) != 1:
				path.clear()
				dig_cell = Vector2i(-1, -1)
				return
			if n != dig_cell:
				dig_cell = n
				dig_t = 0.0
			_chew(delta)
			return
	dig_cell = Vector2i(-1, -1)
	# The crawler's step finishes a move and starts the next one in the same
	# call. If the next cell is rock, hold the path back so it cannot walk
	# into it: the check above chews it out on the next step.
	var held: Array[Vector2i] = []
	if not path.is_empty() and grid.is_solid(path[0].x, path[0].y):
		held = path
		path = []
	super._step(delta)
	if not held.is_empty() and path.is_empty():
		path = held


func _chew(delta: float) -> void:
	var m := grid.get_mat(dig_cell.x, dig_cell.y)
	var need: float = Balance.BURROWER_DIG.get(m, 1.0)
	dig_t += delta
	# the rock cracks as it works (the warning), then gives way
	var res: Dictionary = mine.damage_cell(dig_cell, (9999.0 if dig_t >= need else Cell.max_hp(m) * delta / need * 0.9), 99, true, "crawler")
	var pos := grid.cell_center(dig_cell)
	if randf() < 0.5:
		mine.fx.dust(pos + Vector2(randf_range(-6, 6), randf_range(-6, 6)), Cell.debris_color(m, maxi(0, grid.get_stratum(dig_cell.x, dig_cell.y))), 2)
	if randf() < 0.12:
		Audio.play_at("hit_" + Cell.sound_class(m), pos, -6.0, 0.2, 0.08)
	if res["broken"]:
		dug += 1
		dig_cell = Vector2i(-1, -1)
	spr.position = Vector2(randf_range(-1, 1), 0).round()


func _visual() -> void:
	var shake := spr.position if dig_cell.x >= 0 else Vector2.ZERO
	super._visual()
	if dig_cell.x >= 0:
		spr.position = shake
	# no eyes: its sensor pits are a faint pale glow, red when it has you
	var alert := state in [S.CHASE, S.TUNNEL]
	eye_glow.modulate = Color(1.0, 0.3, 0.25, 0.6) if alert else Color(0.9, 0.85, 0.7, 0.25)
