class_name BombEater
extends Crawler
## Bomb-eater: a rare, squat scavenger. It smells any explosive you have
## placed that has not gone off (a charge or sticky charge with fuse left, a
## remote charge, a proximity mine; never a drill rocket) from EATER_SENSE
## cells away, walks to it and swallows it. For EATER_CALM seconds it acts
## normal; then its belly pulses red, it comes for you faster, and when
## EATER_COUNTDOWN runs out it blows, wherever it is, with a fixed blast
## bigger than a charge. Killed with a bomb inside, it blows where it falls.
## It can climb ladders, so a ladder is no escape: blowing it up might be.

var eats_bombs := true            # ProxMine checks this: mines ignore it
var carrying := false
var eaten := 0
var calm_t := -1.0                # s left looking normal after a swallow
var fuse_t := -1.0                # s left on the countdown (-1: not started)
var blew := false                 # it went off (tests)
var ladder_steps := 0             # cells climbed on ladders (tests)
var _scan_t := 0.0
var _bomb: Node2D = null
var _blink := 0.0


func _ready() -> void:
	super._ready()
	hp = Balance.EATER_HP
	max_hp = hp
	bite = Balance.EATER_DAMAGE
	bite_name = "bomb-eater"
	spr.texture = load("res://assets/gen/eater.png")


func hit_rect() -> Rect2:
	return Rect2(global_position - Vector2(10, 8), Vector2(20, 16))


## Ladders hold it as well as rock does.
func walkable(c: Vector2i) -> bool:
	if super.walkable(c):
		return true
	return grid.in_bounds(c.x, c.y) and grid.get_mat(c.x, c.y) == Cell.LADDER


## On a ladder with no rock to cling to.
func on_ladder() -> bool:
	return grid.get_mat(cell.x, cell.y) == Cell.LADDER and not super.walkable(cell)


func move_speed() -> float:
	var s := super.move_speed()
	if on_ladder() or grid.get_mat(next_cell.x, next_cell.y) == Cell.LADDER and not super.walkable(next_cell):
		s *= Balance.EATER_LADDER_SPEED
	return s


## Is this explosive still food? Placed by you and not going off this instant.
static func edible(b: Node2D) -> bool:
	if not is_instance_valid(b) or b.is_queued_for_deletion():
		return false
	if b is Hazards.ProxMine:
		return b.tripped < 0.0
	if b is Hazards.Charge:
		if b.shear or b.host != null:
			return false
		if b.remote and not b.armed:
			return true
		return b.armed and b.fuse > Balance.EATER_LIT_MIN
	return false


## The nearest bomb worth eating.
func _find_bomb() -> Node2D:
	var best: Node2D = null
	var bd := Balance.EATER_SENSE * Balance.CELL
	var cands: Array = []
	cands.append_array(mine.mines)
	cands.append_array(mine.charges)
	for b in cands:
		if not edible(b):
			continue
		var d: float = b.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = b
	return best


## A bomb comes first: while it is going for one, it does not react to you.
func _sees_player() -> bool:
	if not carrying and _bomb != null and is_instance_valid(_bomb):
		return false
	return super._sees_player()


func _physics_process(delta: float) -> void:
	if state == S.DEAD:
		return
	_blink += delta
	if carrying:
		_tick_bomb(delta)
		if state == S.DEAD:
			return
	elif state != S.STUNNED and not asleep:
		_forage(delta)
	if fuse_t >= 0.0 and state != S.STUNNED:
		_rush()
	var was := cell
	super._physics_process(delta)
	if cell != was and grid.get_mat(cell.x, cell.y) == Cell.LADDER:
		ladder_steps += 1


func _forage(delta: float) -> void:
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.4
		_bomb = _find_bomb()
		if _bomb != null:
			target_cell = grid.world_to_cell(_bomb.global_position)
			if path.is_empty() or path[path.size() - 1] != target_cell:
				_plan(target_cell)
	if _bomb == null or not edible(_bomb):
		_bomb = null
		return
	# a bomb comes before anything else, even a chase
	state = S.INVESTIGATE
	forget_t = Balance.CRAWLER_FORGET
	if _bomb.global_position.distance_to(global_position) <= Balance.EATER_GULP:
		_swallow(_bomb)


func _swallow(b: Node2D) -> void:
	mine.mines.erase(b)
	mine.remotes.erase(b)
	mine.charges.erase(b)
	b.queue_free()
	_bomb = null
	carrying = true
	eaten += 1
	calm_t = Balance.EATER_CALM
	flash = 1.0
	Audio.play_at("crawler_bite", global_position, 0.0)
	mine.tell_once("t_eater", "A BOMB-EATER SWALLOWED YOUR EXPLOSIVE - get away from it!")


## The swallowed bomb: a calm moment, then the countdown. It goes off when
## the countdown ends, wherever it is.
func _tick_bomb(delta: float) -> void:
	if calm_t >= 0.0:
		calm_t -= delta
		if calm_t < 0.0:
			fuse_t = Balance.EATER_COUNTDOWN
			speed_chase = Balance.EATER_RUSH
			Audio.play_at("fuse", global_position, 0.0)
		return
	if fuse_t < 0.0:
		return
	var before := fuse_t
	fuse_t -= delta
	# a beep that speeds up as the end nears
	var step := 0.5 if fuse_t > 2.0 else 0.18
	if int(before / step) != int(fuse_t / step):
		Audio.play_at("fuse", global_position, -4.0, 0.0, 0.0)
	if fuse_t <= 0.0:
		die()


## Counting down: it knows where you are and comes straight for you.
func _rush() -> void:
	var pl: Player = mine.player
	if pl == null or pl.dead:
		return
	state = S.CHASE
	forget_t = Balance.CRAWLER_FORGET
	target_cell = grid.world_to_cell(pl.global_position)


## How hard the red pulse beats: 0 calm, up to 1 at the end of the countdown.
func pulse() -> float:
	if fuse_t < 0.0:
		return 0.0
	var urgency := 1.0 - clampf(fuse_t / Balance.EATER_COUNTDOWN, 0.0, 1.0)
	var rate := lerpf(1.5, 7.0, urgency)
	return (0.55 + 0.45 * urgency) * (0.5 + 0.5 * sin(_blink * rate * TAU))


func die() -> void:
	var boom := carrying
	var pos := global_position
	carrying = false
	super.die()
	if boom:
		blew = true
		# deferred: this may be running inside another blast's loop
		mine.call_deferred("eater_blast", pos)


func _draw() -> void:
	super._draw()
	if carrying:
		# the swallowed bomb's light through its belly; red and beating once counting
		var counting := fuse_t >= 0.0
		var p := pulse()
		var on := fmod(_blink * 5.0, 1.0) < 0.5
		var a := (0.4 + 0.6 * p) if counting else (0.85 if on else 0.3)
		draw_circle(Vector2(-3, 3), 4.0 + 2.0 * p, Color(1.0, 0.2, 0.12, a))
		draw_circle(Vector2(-3, 3), 1.5, Color(1.0, 0.9, 0.6, 1.0 if counting or on else 0.4))
		if counting:
			draw_arc(Vector2.ZERO, 12.0 + 6.0 * p, 0, TAU, 20, Color(1.0, 0.25, 0.15, 0.25 + 0.5 * p), 1.5)


func _visual() -> void:
	super._visual()
	if on_ladder():
		# climbing: body along the ladder, head the way it is going, legs working
		var head_up := next_cell.y <= cell.y
		up_dir = Vector2.LEFT if (facing > 0) == head_up else Vector2.RIGHT
		spr.rotation = Vector2.UP.angle_to(up_dir)
	if carrying:
		var p := pulse()
		spr.self_modulate = Color(1.0, 1.0 - 0.6 * p, 1.0 - 0.7 * p)
		queue_redraw()
	else:
		spr.self_modulate = Color.WHITE
