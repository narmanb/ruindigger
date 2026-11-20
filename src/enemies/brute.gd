class_name Brute
extends Node2D
## Shielded Brute: a big, slow walker behind a tall front plate. Drill and
## blast damage from the front mostly glances off the plate; its back is soft.
## Beat it with the terrain or by getting behind it:
##   - jump over it and drill its back (it turns slowly)
##   - drop a ceiling on it (falling rock ignores the plate and stuns it)
##   - stick a charge to its back, or let a blast go off behind it
##   - bait its charge into rock it cannot break: it stuns itself
## It walks on floors, steps up one-cell ledges, falls off edges, and smashes
## through sediment, rubble and cracked rock in its way. It cannot climb.

enum S { IDLE, HUNT, TURN, WINDUP, BRACE, CHARGE, SMASH, STUNNED, DEAD }

const HALF := Vector2(12, 15)      # collision half extents (24 x 30: the digger is 11 x 26)

var mine: Node
var grid: TerrainGrid
var state := S.IDLE
var hp := Balance.BRUTE_HP
var facing := 1
var vel := Vector2.ZERO
var on_floor := false
var target_x := 0.0
var forget_t := 0.0
var state_t := 0.0
var attack_cd := 0.0
var charge_cd := 2.0
var stun_t := 0.0
var flash := 0.0
var anim_t := 0.0
var last_hit := ""
var asleep := false
var smash_cells: Array[Vector2i] = []
var slams := 0
var blocked_hits := 0
var spr: Sprite2D
var mat: ShaderMaterial
var eye_glow: Sprite2D
var _step_t := 0.0


func _ready() -> void:
	grid = mine.grid
	spr = Sprite2D.new()
	spr.texture = load("res://assets/gen/brute.png")
	spr.hframes = 4
	spr.vframes = 4
	spr.offset = Vector2(0, -5)        # frame 48x40, feet at y=38: body centre sits 5 px lower than the frame's
	mat = ShaderMaterial.new()
	mat.shader = load("res://src/fx/flash.gdshader")
	spr.material = mat
	add_child(spr)
	eye_glow = Sprite2D.new()
	eye_glow.texture = load("res://assets/gen/glow.png")
	eye_glow.scale = Vector2(0.28, 0.28)
	mine.glow_root.add_child(eye_glow)
	target_x = global_position.x


func _exit_tree() -> void:
	if is_instance_valid(eye_glow):
		eye_glow.queue_free()


func hit_rect() -> Rect2:
	return Rect2(global_position - HALF, HALF * 2.0)


## Is the body rect at `p` clear of solid cells?
func _free(p: Vector2) -> bool:
	var r := Rect2(p - HALF + Vector2(0.5, 0.5), HALF * 2.0 - Vector2(1, 1))
	var c0 := grid.world_to_cell(r.position)
	var c1 := grid.world_to_cell(r.end)
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			if grid.is_solid(x, y) or not grid.in_bounds(x, y):
				return false
	return true


## Solid cells the body would overlap one step ahead.
func _blocking(dir: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x := global_position.x + dir * (HALF.x + 2.0)
	var cx := grid.world_to_cell(Vector2(x, 0)).x
	var y0 := grid.world_to_cell(Vector2(0, global_position.y - HALF.y + 1.0)).y
	var y1 := grid.world_to_cell(Vector2(0, global_position.y + HALF.y - 1.0)).y
	for y in range(y0, y1 + 1):
		if grid.is_solid(cx, y):
			out.append(Vector2i(cx, y))
	return out


func _smashable(c: Vector2i) -> bool:
	var m := grid.get_mat(c.x, c.y)
	return m in [Cell.SOFT, Cell.LOOSE, Cell.CRACKED, Cell.GAS] and not grid.has_flag(c.x, c.y, Cell.F_PROTECTED)


func _player_rect() -> Rect2:
	var pl: Player = mine.player
	return Rect2(pl.global_position - Player.HALF, Player.HALF * 2.0)


func _sees_player() -> bool:
	var pl: Player = mine.player
	if pl == null or pl.dead:
		return false
	var d := pl.global_position.distance_to(global_position)
	if d > Balance.BRUTE_SIGHT * Balance.CELL:
		return false
	if d > Balance.DUST_CLOAK_NEAR * Balance.CELL and mine.has_method("cloaked") and mine.cloaked():
		return false
	return grid.line_clear(global_position + Vector2(0, -HALF.y + 3.0), pl.global_position + Vector2(0, -4))


## Drilling and blasts draw it, like the crawlers.
func hear(pos: Vector2, radius_cells: float) -> void:
	if state in [S.DEAD, S.STUNNED, S.CHARGE, S.BRACE]:
		return
	if pos.distance_to(global_position) <= radius_cells * Balance.CELL:
		target_x = pos.x
		forget_t = Balance.BRUTE_FORGET
		if state == S.IDLE:
			_go(S.HUNT)
			Audio.play_at("crawler_alert", global_position, -2.0, 0.0, 0.0)


func _go(s: S) -> void:
	state = s
	state_t = 0.0


func _physics_process(delta: float) -> void:
	if state == S.DEAD:
		return
	var pl: Player = mine.player
	var dist := pl.global_position.distance_to(global_position) if pl else 9999.0
	asleep = dist > 34.0 * Balance.CELL
	if asleep:
		return
	flash = maxf(0.0, flash - delta * 5.0)
	attack_cd = maxf(0.0, attack_cd - delta)
	charge_cd = maxf(0.0, charge_cd - delta)
	state_t += delta
	anim_t += delta
	var sees := _sees_player()
	if sees:
		target_x = pl.global_position.x
		forget_t = Balance.BRUTE_FORGET
	else:
		forget_t = maxf(0.0, forget_t - delta)
	var want := 0.0
	match state:
		S.IDLE:
			if sees:
				_go(S.HUNT)
				Audio.play_at("crawler_alert", global_position, -2.0, 0.0, 0.0)
		S.HUNT:
			if forget_t <= 0.0:
				_go(S.IDLE)
			else:
				want = _hunt(pl, sees)
		S.TURN:
			if state_t >= Balance.BRUTE_TURN:
				facing = -facing
				_go(S.HUNT)
		S.WINDUP:
			if state_t >= Balance.BRUTE_WINDUP:
				attack_cd = Balance.BRUTE_ATTACK_COOLDOWN
				if pl and not pl.dead and _reach_rect().intersects(_player_rect()):
					pl.take_damage(Balance.BRUTE_DAMAGE, global_position, "shielded brute")
					Audio.play_at("hit_metal", global_position, 0.0, 0.1, 0.0)
					mine.shake(0.3)
				_go(S.HUNT)
		S.BRACE:
			if randf() < 0.4:
				mine.fx.dust(global_position + Vector2(-facing * 8, HALF.y), Color(0.8, 0.7, 0.55), 2)
			if state_t >= Balance.BRUTE_BRACE:
				_go(S.CHARGE)
				Audio.play_at("rumble", global_position, -4.0, 0.1, 0.3)
		S.CHARGE:
			want = facing * Balance.BRUTE_CHARGE_SPEED
			if pl and not pl.dead and hit_rect().grow(2.0).intersects(_player_rect()):
				pl.take_damage(Balance.BRUTE_CHARGE_DAMAGE, global_position, "shielded brute")
				mine.shake(0.4)
				charge_cd = Balance.BRUTE_CHARGE_COOLDOWN
				_go(S.HUNT)
			elif state_t >= Balance.BRUTE_CHARGE_TIME or not on_floor and state_t > 0.3:
				charge_cd = Balance.BRUTE_CHARGE_COOLDOWN
				_go(S.HUNT)
		S.SMASH:
			if randf() < 0.3 and not smash_cells.is_empty():
				mine.fx.chips(grid.cell_center(smash_cells[0]), Vector2(-facing, -0.4), Color(0.75, 0.65, 0.5))
			if state_t >= Balance.BRUTE_SMASH:
				_smash_now()
				_go(S.HUNT)
		S.STUNNED:
			stun_t -= delta
			if stun_t <= 0.0:
				_go(S.HUNT if forget_t > 0.0 else S.IDLE)
	_move(want, delta)
	_visual()


## Walk toward the target and pick an attack. Returns the wanted x speed.
func _hunt(pl: Player, sees: bool) -> float:
	var dx := target_x - global_position.x
	var dir := signi(int(signf(dx))) if absf(dx) > 6.0 else 0
	if dir != 0 and dir != facing:
		_go(S.TURN)
		return 0.0
	if pl and not pl.dead and sees:
		var pr := _player_rect()
		if attack_cd <= 0.0 and _reach_rect().intersects(pr):
			_go(S.WINDUP)
			Audio.play_at("crawler_alert", global_position, -6.0, 0.1, 0.0)
			return 0.0
		var level := absf(pl.global_position.y - global_position.y) < 20.0
		var cells := absf(dx) / Balance.CELL
		if level and on_floor and charge_cd <= 0.0 and dir == facing and cells >= float(Balance.BRUTE_CHARGE_RANGE[0]) and cells <= float(Balance.BRUTE_CHARGE_RANGE[1]):
			_go(S.BRACE)
			Audio.play_at("crawler_alert", global_position, 0.0, 0.0, 0.0)
			return 0.0
	return dir * Balance.BRUTE_SPEED


func _reach_rect() -> Rect2:
	var r := hit_rect()
	if facing > 0:
		return Rect2(r.end.x - 2.0, r.position.y, Balance.BRUTE_REACH + 2.0, r.size.y)
	return Rect2(r.position.x - Balance.BRUTE_REACH, r.position.y, Balance.BRUTE_REACH + 2.0, r.size.y)


func _move(want: float, delta: float) -> void:
	# gravity
	vel.y = minf(vel.y + Balance.GRAVITY * delta, Balance.MAX_FALL)
	var ny := global_position + Vector2(0, vel.y * delta)
	if _free(ny):
		global_position = ny
		on_floor = false
	else:
		if vel.y > 0.0:
			# settle onto the cell top
			var foot := global_position.y + HALF.y
			var snap := floorf((foot + vel.y * delta) / Balance.CELL) * Balance.CELL - HALF.y
			if snap >= global_position.y - 0.5 and _free(Vector2(global_position.x, snap)):
				global_position.y = snap
			on_floor = true
		vel.y = 0.0
	if want == 0.0 or state in [S.STUNNED, S.DEAD]:
		return
	var dir := 1 if want > 0.0 else -1
	var nx := global_position + Vector2(want * delta, 0)
	if _free(nx):
		global_position = nx
		_step_t -= delta
		if _step_t <= 0.0 and on_floor:
			_step_t = 0.2 if state == S.CHARGE else 0.5
			Audio.play_at("land", global_position, -8.0 if state != S.CHARGE else -3.0, 0.15, 0.0)
			if state == S.CHARGE:
				mine.fx.dust(global_position + Vector2(-dir * 8, HALF.y), Color(0.8, 0.7, 0.55), 3)
		return
	# blocked: step up a one-cell ledge if there is room
	var up := nx + Vector2(0, -Balance.CELL)
	if on_floor and state != S.CHARGE and _free(up) and _free(global_position + Vector2(0, -Balance.CELL)):
		global_position = up
		return
	var cells := _blocking(dir)
	if cells.is_empty():
		return
	var soft := true
	for c in cells:
		if not _smashable(c):
			soft = false
	if state == S.CHARGE:
		if soft:
			smash_cells = cells
			_smash_now()          # a charge goes straight through soft ground
		else:
			_slam()
	elif soft and state == S.HUNT:
		smash_cells = cells
		_go(S.SMASH)
		Audio.play_at("hit_soft", global_position, -2.0, 0.1, 0.0)


func _smash_now() -> void:
	for c in smash_cells:
		if grid.is_solid(c.x, c.y) and _smashable(c):
			mine.damage_cell(c, 999.0, 0, false, "brute")
	if not smash_cells.is_empty():
		Audio.play_at("break_soft", grid.cell_center(smash_cells[0]), 0.0, 0.1, 0.0)
		mine.shake(0.15)
		mine.noise(global_position, 6.0)
	smash_cells.clear()


## It charged into rock it cannot break: it stuns itself.
func _slam() -> void:
	slams += 1
	charge_cd = Balance.BRUTE_CHARGE_COOLDOWN
	mine.shake(0.5)
	Audio.play_at("hit_metal", global_position, 2.0, 0.05, 0.0)
	mine.fx.sparks(global_position + Vector2(facing * HALF.x, -4), Vector2(-facing, -0.5), Color(1.0, 0.85, 0.5))
	mine.fx.dust(global_position + Vector2(facing * HALF.x, 0), Color(0.8, 0.75, 0.7), 8)
	stun(Balance.BRUTE_SLAM_STUN)
	mine.tell_once("t_slam", "THE BRUTE STUNNED ITSELF - hit it now, the plate is down!")


## Does a hit from `from` land on the plate?
func plate_blocks(from: Vector2) -> bool:
	if state == S.STUNNED or state == S.DEAD:
		return false
	return signi(int(signf(from.x - global_position.x))) == facing


func hit(dmg: float, from: Vector2, knock: bool = true) -> void:
	if state == S.DEAD:
		return
	# the plate stops the drill and blasts from the front; never falling rock,
	# lava, gas clouds, steam or water
	if knock and last_hit in ["drill", "charge", "gas", "prop"] and plate_blocks(from):
		dmg *= Balance.BRUTE_PLATE
		blocked_hits += 1
		if randf() < 0.5:
			mine.fx.sparks(global_position + Vector2(facing * HALF.x, randf_range(-10, 8)), Vector2(facing, -0.4), Color(1.0, 0.85, 0.5))
		if last_hit == "drill" and randf() < 0.3:
			Audio.play_at("hit_metal", global_position, -8.0, 0.15, 0.1)
		if blocked_hits >= 6:
			mine.tell_once("t_plate", "ITS PLATE STOPS YOUR DRILL - get behind it, or bring the roof down")
	else:
		flash = 1.0
		if knock:
			Audio.play_at("crawler_hit", global_position, -3.0, 0.1, 0.0)
			mine.fx.burst(global_position, Color(0.8, 0.3, 0.4), 6)
	hp -= dmg
	queue_redraw()
	if state == S.IDLE:
		forget_t = Balance.BRUTE_FORGET
		target_x = from.x
		_go(S.HUNT)
	if hp <= 0.0:
		die()


## Too heavy to stagger: a short stun (a blast's shock) does nothing. Falling
## rock, cryo, a pressure vent or its own slam put it down properly.
func stun(t: float) -> void:
	if state == S.DEAD or t < Balance.BRUTE_STUN_MIN:
		return
	stun_t = maxf(stun_t if state == S.STUNNED else 0.0, t)
	_go(S.STUNNED)


## Falling rock: the plate is no help from above.
func crushed() -> void:
	last_hit = "rubble"
	hit(Balance.BRUTE_RUBBLE_DAMAGE, global_position + Vector2(0, -24), false)
	stun(Balance.RUBBLE_STUN)
	if state != S.DEAD:
		mine.toast("Brute crushed by rubble - it's stunned!")


func die() -> void:
	state = S.DEAD
	Audio.play_at("crawler_die", global_position, 2.0, 0.0, 0.0)
	mine.fx.burst(global_position, Color(0.55, 0.5, 0.6), 18)
	mine.fx.burst(global_position, Color(0.85, 0.35, 0.45), 14)
	mine.shake(0.4)
	for k in 4:
		mine.spawn_ore(global_position + Vector2(randf_range(-10, 10), randf_range(-8, 4)), 5)
	for k in 2:
		mine.spawn_ore(global_position + Vector2(randf_range(-10, 10), randf_range(-8, 4)), Cell.ORE_COBALT)
	mine.on_enemy_killed(self)
	var tw := create_tween()
	tw.tween_property(spr, "scale", Vector2(1.25, 0.2), 0.22)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)


func _visual() -> void:
	var anims: Dictionary = SpriteDB.meta().get("brute", {}).get("anims", {})
	var anim := "idle"
	var rate := 3.0
	match state:
		S.HUNT:
			anim = "walk"
			rate = 6.0
		S.TURN:
			anim = "idle"
		S.WINDUP:
			anim = "attack"
			rate = 2.0 / Balance.BRUTE_WINDUP
		S.BRACE:
			anim = "brace"
			rate = 8.0
		S.CHARGE:
			anim = "charge"
			rate = 12.0
		S.SMASH:
			anim = "attack"
			rate = 5.0
		S.STUNNED:
			anim = "stun"
			rate = 5.0
	if flash > 0.5:
		anim = "hurt"
	var a: Array = anims.get(anim, [0, 4])
	var t := state_t if state == S.WINDUP else anim_t
	spr.frame = int(a[0]) + int(t * rate) % int(a[1])
	# half-way through a turn it shows its back, so the turn reads
	var face := facing
	if state == S.TURN and state_t > Balance.BRUTE_TURN * 0.5:
		face = -facing
	spr.flip_h = face < 0
	spr.position = Vector2(randf_range(-1, 1), 0).round() if state in [S.BRACE, S.SMASH] else Vector2.ZERO
	mat.set_shader_parameter("flash", clampf(flash, 0.0, 0.6 if Settings.reduced_flashing() else 1.0))
	eye_glow.global_position = global_position + Vector2(face * 8, -HALF.y - 1)
	eye_glow.visible = state != S.STUNNED
	eye_glow.modulate = Color(1.0, 0.2, 0.2, 0.85) if state in [S.HUNT, S.BRACE, S.CHARGE, S.WINDUP, S.SMASH, S.TURN] else Color(1.0, 0.45, 0.2, 0.4)
	queue_redraw()


func _draw() -> void:
	if hp < Balance.BRUTE_HP and state != S.DEAD:
		var w := 28.0
		var f := clampf(hp / Balance.BRUTE_HP, 0.0, 1.0)
		draw_rect(Rect2(-w * 0.5 - 1, -HALF.y - 12, w + 2, 4), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-w * 0.5, -HALF.y - 11, w * f, 2), Color(1.0, 0.35, 0.3))
	if state == S.BRACE:
		# the charge warning: an arrow of dashes along the floor ahead
		var k := clampf(state_t / Balance.BRUTE_BRACE, 0.0, 1.0)
		for i in 5:
			var x := facing * (HALF.x + 6.0 + i * 12.0)
			draw_rect(Rect2(x - 3.0, HALF.y - 3.0, 6.0, 2.0), Color(1.0, 0.3, 0.2, (0.9 if float(i) / 5.0 < k else 0.25)))
	elif state == S.WINDUP:
		draw_arc(Vector2(facing * HALF.x, 0), 10.0 + state_t * 14.0, -1.0, 1.0, 12, Color(1.0, 0.3, 0.2, 0.7), 1.5)
