class_name PoolDweller
extends Crawler
## Shared base for the enemies that live in a fluid: the Eel (water) and the
## Slag salamander (lava). In its pool one swims freely through any cell that
## holds enough of its fluid, and is fast. Out of it, it crawls along
## surfaces like a crawler, slower, and after `dry_limit` seconds it turns
## back for the last pool cell it was in.

var dry_t := 0.0
var dry_limit := 4.0
var last_pool := Vector2i(-1, -1)
var speed_wet: Array = [2.0, 4.0]
var speed_dry: Array = [1.0, 1.5]
var _home_t := 0.0


## Does this cell hold enough of its fluid to swim in? (subclasses decide)
func in_pool(_c: Vector2i) -> bool:
	return false


func wet() -> bool:
	return in_pool(cell)


## Past its limit out of the pool.
func parched() -> bool:
	return dry_t > dry_limit


func walkable(c: Vector2i) -> bool:
	if not grid.in_bounds(c.x, c.y) or grid.is_solid(c.x, c.y):
		return false
	# the pool, the air just over its surface (so it can climb out onto a
	# bank and back in), or any surface a crawler could cling to
	return in_pool(c) or in_pool(Vector2i(c.x, c.y + 1)) or super.walkable(c)


## Swim (or crawl) right to the goal cell, not just near it.
func _plan(goal: Vector2i) -> void:
	super._plan(goal)
	_finish_approach(goal)


func _begin_tunnel() -> void:
	pass


func _wander() -> void:
	var opts: Array[Vector2i] = []
	var here := wet()
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + d
		# it does not leave its pool for no reason
		if walkable(n) and (n - home).length() < 10 and (in_pool(n) or not here):
			opts.append(n)
	if not opts.is_empty():
		path = [opts[randi() % opts.size()]]


func _physics_process(delta: float) -> void:
	if state == S.DEAD:
		return
	if wet():
		dry_t = 0.0
		last_pool = cell
	elif not asleep:
		dry_t += delta
	_tune()
	# out too long: forget the chase and go home
	if parched() and state != S.STUNNED and last_pool.x >= 0 and not asleep:
		state = S.INVESTIGATE
		forget_t = Balance.CRAWLER_FORGET
		target_cell = last_pool
		_home_t -= delta
		if _home_t <= 0.0 and _arrived():
			_home_t = 0.5
			_plan(last_pool)
	super._physics_process(delta)


## Set speeds and bite for where it is now (subclasses add to this).
func _tune() -> void:
	var sp: Array = speed_wet if wet() else speed_dry
	speed_patrol = float(sp[0])
	speed_chase = float(sp[1])


func _sees_player() -> bool:
	if parched():
		return false          # it only wants its pool now
	return super._sees_player()
