class_name BombEater
extends Crawler
## Bomb-eater: a rare, squat scavenger. It smells a proximity mine or a
## remote charge that is waiting for its signal from EATER_SENSE cells away,
## walks to it and swallows it (mines do not go off for it). Then its belly
## blinks with the fuse light and it runs at you: beside you it beeps for
## EATER_FUSE seconds and blows. If it dies with a bomb inside, it blows
## where it falls. So: kill it from a distance, or do not leave bombs lying
## about. Without a bomb it is a weak crawler.

var eats_bombs := true            # ProxMine checks this: mines ignore it
var carrying := false
var eaten := 0
var fuse_t := -1.0
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


## The nearest bomb worth eating: a mine that has not been set off, or a
## remote charge waiting for its signal.
func _find_bomb() -> Node2D:
	var best: Node2D = null
	var bd := Balance.EATER_SENSE * Balance.CELL
	var cands: Array = []
	cands.append_array(mine.mines)
	cands.append_array(mine.remotes)
	for b in cands:
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		if b is Hazards.ProxMine and b.tripped >= 0.0:
			continue
		if b is Hazards.Charge and b.armed:
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
	if state != S.STUNNED and not asleep:
		if carrying:
			_rush(delta)
		else:
			_forage(delta)
	super._physics_process(delta)


func _forage(delta: float) -> void:
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.4
		_bomb = _find_bomb()
		if _bomb != null:
			target_cell = grid.world_to_cell(_bomb.global_position)
			if path.is_empty() or path[path.size() - 1] != target_cell:
				_plan(target_cell)
	if _bomb == null or not is_instance_valid(_bomb):
		return
	# a bomb comes before anything else, even a chase
	state = S.INVESTIGATE
	forget_t = Balance.CRAWLER_FORGET
	if _bomb.global_position.distance_to(global_position) <= Balance.EATER_GULP:
		_swallow(_bomb)


func _swallow(b: Node2D) -> void:
	mine.mines.erase(b)
	mine.remotes.erase(b)
	b.queue_free()
	_bomb = null
	carrying = true
	eaten += 1
	speed_chase = Balance.EATER_RUSH
	flash = 1.0
	Audio.play_at("crawler_bite", global_position, 0.0)
	Audio.play_at("fuse", global_position, 0.0)
	mine.tell_once("t_eater", "A BOMB-EATER SWALLOWED YOUR CHARGE - it's coming back with it!")


## It has a bomb: it knows where you are and comes straight for you.
func _rush(delta: float) -> void:
	var pl: Player = mine.player
	if pl == null or pl.dead:
		return
	state = S.CHASE
	forget_t = Balance.CRAWLER_FORGET
	target_cell = grid.world_to_cell(pl.global_position)
	if fuse_t < 0.0 and pl.global_position.distance_to(global_position) <= Balance.EATER_REACH:
		fuse_t = Balance.EATER_FUSE
		Audio.play_at("gas_warn", global_position, 0.0, 0.0, 0.0)
	if fuse_t >= 0.0:
		fuse_t -= delta
		if fuse_t <= 0.0:
			die()


func die() -> void:
	var boom := carrying
	var pos := global_position
	carrying = false
	super.die()
	if boom:
		# deferred: this may be running inside another blast's loop
		mine.call_deferred("charge_blast", pos)


func _draw() -> void:
	super._draw()
	if carrying:
		# the swallowed bomb's light, blinking through its belly
		var rate := 14.0 if fuse_t >= 0.0 else 5.0
		var on := fmod(_blink * rate, 1.0) < 0.5
		draw_circle(Vector2(-3, 3), 4.0, Color(1.0, 0.25, 0.15, 0.85 if on else 0.3))
		draw_circle(Vector2(-3, 3), 1.5, Color(1.0, 0.9, 0.6, 1.0 if on else 0.4))
		if fuse_t >= 0.0:
			draw_arc(Vector2.ZERO, 14.0 + (Balance.EATER_FUSE - fuse_t) * 16.0, 0, TAU, 20, Color(1.0, 0.3, 0.2, 0.7), 1.5)


func _visual() -> void:
	super._visual()
	if carrying:
		queue_redraw()
