class_name Crawler
extends Node2D
## Burrow Crawler. Moves cell-to-cell along open cells that touch terrain
## (floors, walls and ceilings), so it always respects the current grid.
##
## Rules (documented in README):
##  PATROL      wander along surfaces near home.
##  INVESTIGATE heard drilling/blasts within hearing range -> path to the noise.
##  CHASE       player within sight range with grid line-of-sight -> path to player,
##              re-planned every CRAWLER_REPATH s (BFS, bounded radius).
##  ATTACK      adjacent to player -> lunge for contact damage, then cooldown.
##  TUNNEL      chasing but no open path -> chew through one SEDIMENT cell toward
##              the player (slow, audible). Never chews basalt/alloy.
##  STUNNED     hit by falling rubble or a blast -> stops for a few seconds.
##  Loses interest after CRAWLER_FORGET s with no sight and no fresh noise.

enum S { PATROL, INVESTIGATE, CHASE, ATTACK, TUNNEL, STUNNED, DEAD }

var mine: Node
var grid: TerrainGrid
var cell := Vector2i.ZERO
var next_cell := Vector2i.ZERO
var move_t := 1.0
var state := S.PATROL
var hp := Balance.CRAWLER_HP
var path: Array[Vector2i] = []
var repath_t := 0.0
var target_cell := Vector2i(-1, -1)
var forget_t := 0.0
var attack_cd := 0.0
var stun_t := 0.0
var tunnel_t := 0.0
var tunnel_cell := Vector2i(-1, -1)
var home := Vector2i.ZERO
var flash := 0.0
var facing := 1
var asleep := false
var _sleep_acc := 0.0
var spr: Sprite2D
var eye_glow: Sprite2D
var anim_t := 0.0
var mat: ShaderMaterial
var up_dir := Vector2.UP
var hitstun := 0.0
var windup := 0.0
var water_travel := Vector2.ZERO
var last_hit := ""          # what hurt it last: drill, charge, rubble, gas, lava, prop, water...


func _ready() -> void:
	grid = mine.grid
	cell = grid.world_to_cell(global_position)
	next_cell = cell
	home = cell
	global_position = grid.cell_center(cell)
	spr = Sprite2D.new()
	spr.texture = load("res://assets/gen/crawler.png")
	spr.hframes = 4
	spr.vframes = 3
	spr.offset = Vector2(-2, -2)
	mat = ShaderMaterial.new()
	mat.shader = load("res://src/fx/flash.gdshader")
	spr.material = mat
	add_child(spr)
	eye_glow = Sprite2D.new()
	eye_glow.texture = load("res://assets/gen/glow.png")
	eye_glow.scale = Vector2(0.22, 0.22)
	mine.glow_root.add_child(eye_glow)


func _exit_tree() -> void:
	if is_instance_valid(eye_glow):
		eye_glow.queue_free()


func hit_rect() -> Rect2:
	return Rect2(global_position - Vector2(9, 7), Vector2(18, 14))


func walkable(c: Vector2i) -> bool:
	if grid.is_solid(c.x, c.y) or not grid.in_bounds(c.x, c.y):
		return false
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
		if grid.is_solid(c.x + d.x, c.y + d.y):
			return true
	return false


func _physics_process(delta: float) -> void:
	if state == S.DEAD:
		return
	var pl: Player = mine.player
	var dist := pl.global_position.distance_to(global_position) if pl else 9999.0
	# far away: low-frequency update, no pathfinding
	asleep = dist > 34.0 * Balance.CELL
	if asleep:
		_sleep_acc += delta
		if _sleep_acc < 0.5:
			return
		delta = _sleep_acc
		_sleep_acc = 0.0
	flash = maxf(0.0, flash - delta * 5.0)
	attack_cd = maxf(0.0, attack_cd - delta)
	hitstun = maxf(0.0, hitstun - delta)
	if grid.get_water(cell.x, cell.y) >= Balance.WATER_MAX / 2:
		last_hit = "water"
		hit(Balance.WATER_CRAWLER_DPS * delta, global_position, false)
		if state == S.DEAD:
			return
	anim_t += delta
	if not walkable(cell) and grid.is_solid(cell.x, cell.y):
		# terrain changed under us (rubble landed): pop to a free neighbour
		_unstick()
	match state:
		S.STUNNED:
			stun_t -= delta
			if stun_t <= 0.0:
				state = S.CHASE if _sees_player() else S.PATROL
		S.PATROL:
			if _sees_player():
				_alert()
			elif _arrived():
				_wander()
		S.INVESTIGATE:
			if _sees_player():
				_alert()
			else:
				forget_t -= delta
				if forget_t <= 0.0:
					state = S.PATROL
				elif _arrived():
					if cell == target_cell or path.is_empty():
						state = S.PATROL
		S.CHASE, S.TUNNEL:
			if _sees_player():
				forget_t = Balance.CRAWLER_FORGET
				target_cell = grid.world_to_cell(pl.global_position)
			else:
				forget_t -= delta
				if forget_t <= 0.0:
					state = S.INVESTIGATE
					forget_t = 2.0
			repath_t -= delta
			if repath_t <= 0.0 and _arrived():
				repath_t = Balance.CRAWLER_REPATH
				_plan(target_cell)
				if path.is_empty() and state == S.CHASE:
					_begin_tunnel()
			if state == S.TUNNEL:
				_tunnel(delta)
			# bites are telegraphed: rear up for CRAWLER_WINDUP, then strike if
			# still in reach. A drill hit during the wind-up cancels it.
			if pl and dist < 22.0 and attack_cd <= 0.0 and windup <= 0.0 and hitstun <= 0.0 and not pl.dead:
				windup = Balance.CRAWLER_WINDUP
				Audio.play_at("crawler_alert", global_position, -8.0, 0.2, 0.3)
			if windup > 0.0:
				windup -= delta
				if windup <= 0.0:
					attack_cd = Balance.CRAWLER_ATTACK_COOLDOWN
					if pl and not pl.dead and global_position.distance_to(pl.global_position) < 26.0 and hitstun <= 0.0:
						pl.take_damage(Balance.CRAWLER_DAMAGE, global_position, "burrow crawler")
						Audio.play_at("crawler_bite", global_position)
	_step(delta)
	_current(delta)
	_visual()


func _current(delta: float) -> void:
	if mine.get("water") == null:
		return
	var flow: Vector2 = mine.water.sample_contact(global_position, Vector2(6, 5))
	if flow.length() < Balance.WATER_CRAWLER_THRESHOLD:
		water_travel = water_travel.move_toward(Vector2.ZERO, Balance.CELL * delta)
		return
	water_travel += flow * Balance.WATER_CRAWLER_DRAG * minf(delta, Balance.WATER_TICK)
	var d := Vector2i.ZERO
	if absf(water_travel.x) >= Balance.CELL:
		d.x = 1 if water_travel.x > 0 else -1
	elif absf(water_travel.y) >= Balance.CELL:
		d.y = 1 if water_travel.y > 0 else -1
	if d == Vector2i.ZERO:
		return
	water_travel = Vector2.ZERO
	var n := cell + d
	if grid.is_solid(n.x, n.y):
		return
	cell = n
	next_cell = n
	move_t = 1.0
	path.clear()
	repath_t = 0.0
	windup = 0.0
	global_position = grid.cell_center(n)


func _arrived() -> bool:
	return move_t >= 1.0


func _sees_player() -> bool:
	var pl: Player = mine.player
	if pl == null or pl.dead:
		return false
	var d := pl.global_position.distance_to(global_position)
	if d > Balance.CRAWLER_SIGHT * Balance.CELL:
		return false
	return grid.line_clear(global_position, pl.global_position + Vector2(0, -4))


func _alert() -> void:
	if state != S.CHASE:
		Audio.play_at("crawler_alert", global_position, -2.0)
	state = S.CHASE
	forget_t = Balance.CRAWLER_FORGET
	target_cell = grid.world_to_cell(mine.player.global_position)
	repath_t = 0.0


func hear(pos: Vector2, radius_cells: float) -> void:
	if state in [S.DEAD, S.STUNNED, S.CHASE, S.TUNNEL]:
		return
	if pos.distance_to(global_position) <= radius_cells * Balance.CELL:
		state = S.INVESTIGATE
		forget_t = Balance.CRAWLER_FORGET + 2.0
		target_cell = grid.world_to_cell(pos)
		_plan(target_cell)


## A lure pinged nearby: drop everything (even a chase) and go to it.
func lure(pos: Vector2) -> void:
	if state in [S.DEAD, S.STUNNED]:
		return
	state = S.INVESTIGATE
	forget_t = Balance.CRAWLER_FORGET + 2.0
	target_cell = grid.world_to_cell(pos)
	_plan(target_cell)


func _wander() -> void:
	var opts: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + d
		if walkable(n) and (n - home).length() < 10:
			opts.append(n)
	if opts.is_empty():
		return
	# prefer continuing forward along the surface
	var fwd := cell + Vector2i(facing, 0)
	if opts.has(fwd) and randf() < 0.7:
		path = [fwd]
	else:
		path = [opts[randi() % opts.size()]]


func _plan(goal: Vector2i) -> void:
	path = GridPath.find(grid, cell, goal, Balance.CRAWLER_PATH_RADIUS, walkable)


func _begin_tunnel() -> void:
	var pl: Player = mine.player
	if pl == null:
		return
	var to := grid.world_to_cell(pl.global_position) - cell
	var step := Vector2i(signi(to.x), 0) if absi(to.x) >= absi(to.y) else Vector2i(0, signi(to.y))
	var c := cell + step
	if grid.get_mat(c.x, c.y) == Cell.SOFT and not grid.has_flag(c.x, c.y, Cell.F_PROTECTED) and grid.get_ore(c.x, c.y) == 0:
		state = S.TUNNEL
		tunnel_cell = c
		tunnel_t = Balance.CRAWLER_TUNNEL_TIME


func _tunnel(delta: float) -> void:
	if tunnel_cell.x < 0 or grid.get_mat(tunnel_cell.x, tunnel_cell.y) != Cell.SOFT:
		state = S.CHASE
		return
	tunnel_t -= delta
	if randf() < 0.2:
		mine.fx.chips(grid.cell_center(tunnel_cell), Vector2(cell - tunnel_cell), Cell.debris_color(Cell.SOFT, grid.get_stratum(cell.x, cell.y)))
	if tunnel_t <= 0.0:
		mine.damage_cell(tunnel_cell, 99.0, 0, false, "crawler")
		Audio.play_at("break_soft", grid.cell_center(tunnel_cell), -4.0)
		path = [tunnel_cell]
		state = S.CHASE
		repath_t = 0.2


func _step(delta: float) -> void:
	var speed := Balance.CRAWLER_SPEED_CHASE if state in [S.CHASE, S.INVESTIGATE] else Balance.CRAWLER_SPEED_PATROL
	if state in [S.STUNNED, S.TUNNEL] or hitstun > 0.0 or windup > 0.0:
		speed = 0.0
	if move_t < 1.0:
		move_t = minf(1.0, move_t + speed * delta)
		if move_t >= 1.0:
			cell = next_cell
	if move_t >= 1.0 and not path.is_empty() and speed > 0.0:
		var n: Vector2i = path.pop_front()
		if n == cell:
			return
		if walkable(n) and (absi(n.x - cell.x) + absi(n.y - cell.y)) == 1:
			next_cell = n
			move_t = 0.0
			if n.x != cell.x:
				facing = signi(n.x - cell.x)
		else:
			path.clear()
	var a := grid.cell_center(cell)
	var b := grid.cell_center(next_cell)
	global_position = a.lerp(b, move_t)


func _unstick() -> void:
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
		if not grid.is_solid(cell.x + d.x, cell.y + d.y):
			cell += d
			next_cell = cell
			move_t = 1.0
			return


func _visual() -> void:
	# orient to the surface we are clinging to
	var c := cell
	var target_up := Vector2.UP
	if grid.is_solid(c.x, c.y + 1):
		target_up = Vector2.UP
	elif grid.is_solid(c.x, c.y - 1):
		target_up = Vector2.DOWN
	elif grid.is_solid(c.x + 1, c.y):
		target_up = Vector2.LEFT
	elif grid.is_solid(c.x - 1, c.y):
		target_up = Vector2.RIGHT
	up_dir = up_dir.lerp(target_up, 0.25).normalized()
	spr.rotation = Vector2.UP.angle_to(up_dir)
	spr.flip_h = facing < 0
	var anims: Dictionary = SpriteDB.meta().get("crawler", {}).get("anims", {})
	var anim := "walk"
	match state:
		S.STUNNED:
			anim = "stun"
		S.CHASE:
			anim = "attack" if (windup > 0.0 or attack_cd > Balance.CRAWLER_ATTACK_COOLDOWN - 0.25) else "walk"
		S.INVESTIGATE:
			anim = "alert"
	if flash > 0.5:
		anim = "hurt"
	var a: Array = anims.get(anim, [0, 4])
	spr.frame = int(a[0]) + int(anim_t * (10.0 if state == S.CHASE else 6.0)) % int(a[1])
	mat.set_shader_parameter("flash", clampf(flash, 0.0, 0.6 if Settings.reduced_flashing() else 1.0))
	spr.position = Vector2(randf_range(-1, 1), 0).round() if state == S.TUNNEL else Vector2.ZERO
	if state == S.STUNNED:
		spr.position.y = sin(anim_t * 20.0)
	if windup > 0.0:
		queue_redraw()
	eye_glow.global_position = global_position + Vector2(facing * 10, -4).rotated(spr.rotation)
	var alert := state in [S.CHASE, S.TUNNEL]
	eye_glow.modulate = Color(1.0, 0.25, 0.2, 0.8) if alert else Color(1.0, 0.6, 0.2, 0.45)


func hit(dmg: float, from: Vector2, knock: bool = true) -> void:
	if state == S.DEAD:
		return
	hp -= dmg
	flash = 1.0
	queue_redraw()
	if knock:
		Audio.play_at("crawler_hit", global_position, -3.0, 0.1, 0.12)
		mine.fx.burst(global_position, Color(0.8, 0.3, 0.4), 6)
		hitstun = Balance.DRILL_HITSTUN
		windup = 0.0
		_knockback(from)
	if state == S.PATROL or state == S.INVESTIGATE:
		_alert()
	if hp <= 0.0:
		die()


func _knockback(from: Vector2) -> void:
	if move_t < 1.0:
		return
	var away := global_position - from
	var step := Vector2i(signi(int(away.x)), 0) if absf(away.x) >= absf(away.y) else Vector2i(0, signi(int(away.y)))
	var n := cell + step
	if step != Vector2i.ZERO and walkable(n):
		next_cell = n
		move_t = 0.35   # snap most of the way so the shove reads instantly
		path.clear()


func _draw() -> void:
	if hp < Balance.CRAWLER_HP and state != S.DEAD:
		var w := 18.0
		var f := clampf(hp / Balance.CRAWLER_HP, 0.0, 1.0)
		draw_rect(Rect2(-w * 0.5 - 1, -17, w + 2, 4), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-w * 0.5, -16, w * f, 2), Color(1.0, 0.35, 0.3))
	if windup > 0.0:
		draw_arc(Vector2.ZERO, 12.0 + windup * 10.0, 0, TAU, 20, Color(1.0, 0.3, 0.2, 0.7), 1.0)


func stun(t: float) -> void:
	if state == S.DEAD:
		return
	state = S.STUNNED
	stun_t = t
	path.clear()


func crushed() -> void:
	stun(Balance.RUBBLE_STUN)
	last_hit = "rubble"
	hit(Balance.RUBBLE_ENEMY_DAMAGE, global_position + Vector2(0, -16))
	if state != S.DEAD:
		mine.toast("Crawler crushed by rubble!")


func die() -> void:
	state = S.DEAD
	Audio.play_at("crawler_die", global_position)
	mine.fx.burst(global_position, Color(0.55, 0.5, 0.6), 14)
	mine.fx.burst(global_position, Color(0.85, 0.35, 0.45), 10)
	mine.spawn_ore(global_position, 5)
	mine.on_enemy_killed(self)
	var tw := create_tween()
	tw.tween_property(spr, "scale", Vector2(1.3, 0.2), 0.18)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
