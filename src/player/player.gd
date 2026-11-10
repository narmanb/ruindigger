class_name Player
extends CharacterBody2D
## Exosuit miner: platforming (coyote, buffer, variable jump, jet burst, wall
## jump, ladders), short-range drill with aim assist, demolition charges.

signal died(cause: String)
signal hurt(amount: float)

const HALF := Vector2(5.5, 13.0)     # collision half extents (11 x 26)
const C := 16

var mine: Node = null                # Mine scene (grid, fx, entities)
var grid: TerrainGrid
var water: WaterSim
var water_drift := Vector2.ZERO

# stats (from upgrades)
var max_hp := 100.0
var hp := 100.0
var heat := 0.0
var heat_cap := 100.0
var drill_level := 0
var overheated := false
var invuln := 0.0
var dead := false
var controls_enabled := true
var input_override: Dictionary = {}  # tests drive the player through this

# movement state
var facing := 1
var coyote := 0.0
var buffer := 0.0
var jet_ready := true
var wall_lock := 0.0
var on_ladder := false
var was_on_floor := true
var jumping := false
var fall_peak := 0.0

# drill state
var drilling := false
var drill_dir := Vector2i(1, 0)
var drill_tick := 0.0
var cool_delay := 0.0
var targets: Array[Vector2i] = []
var drill_contact := Vector2.ZERO
var drill_blocked := false
var _shake_t := 0.0
var _anim_t := 0.0
var _step_t := 0.0
var _land_t := 0.0
var _hurt_t := 0.0
var _blocked_msg_t := 0.0
var _loop_name := ""

var body_sprite: Sprite2D
var drill_sprite: Sprite2D
var lamp: PointLight2D
var preview: Node2D
var meta: Dictionary
var flash_mat: ShaderMaterial


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 4.0
	floor_max_angle = deg_to_rad(50)
	safe_margin = 0.5
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = HALF * 2.0
	shape.shape = rect
	add_child(shape)
	meta = SpriteDB.meta().get("player", {})
	flash_mat = ShaderMaterial.new()
	flash_mat.shader = load("res://src/fx/flash.gdshader")
	body_sprite = Sprite2D.new()
	body_sprite.texture = load("res://assets/gen/player.png")
	body_sprite.hframes = 8
	body_sprite.vframes = 3
	body_sprite.offset = Vector2(0, -3)  # sprite feet (y=30) sit on collider bottom (13)
	body_sprite.material = flash_mat
	add_child(body_sprite)
	drill_sprite = Sprite2D.new()
	drill_sprite.texture = load("res://assets/gen/drill.png")
	drill_sprite.hframes = 4
	drill_sprite.vframes = 2
	drill_sprite.centered = false
	drill_sprite.offset = Vector2(-3, -8)
	drill_sprite.material = flash_mat
	add_child(drill_sprite)
	lamp = PointLight2D.new()
	lamp.texture = load("res://assets/gen/light.png")
	lamp.texture_scale = 1.55
	lamp.energy = 1.25
	lamp.color = Color(1.0, 0.9, 0.75)
	lamp.position = Vector2(4, -10)
	add_child(lamp)
	var fill := PointLight2D.new()
	fill.texture = lamp.texture
	fill.texture_scale = 0.55
	fill.energy = 0.55
	fill.color = Color(0.8, 1.0, 0.85)
	add_child(fill)
	preview = TargetPreview.new()
	preview.player = self
	preview.top_level = true
	preview.z_index = 5
	add_child(preview)


func setup_stats() -> void:
	drill_level = Progress.level("drill")
	heat_cap = Balance.heat_capacity(Progress.level("heat"))
	max_hp = Balance.hull(Progress.level("hull"))
	hp = max_hp


# ---------------------------------------------------------------------------
# input helpers (actions, or a dictionary injected by automated tests)
func _pressed(a: String) -> bool:
	if not input_override.is_empty():
		return bool(input_override.get(a, false))
	return controls_enabled and Input.is_action_pressed(a)


func _just(a: String) -> bool:
	if not input_override.is_empty():
		var v: bool = bool(input_override.get(a + "_just", false))
		input_override[a + "_just"] = false
		return v
	return controls_enabled and Input.is_action_just_pressed(a)


func _just_released(a: String) -> bool:
	if not input_override.is_empty():
		return not bool(input_override.get(a, false))
	return controls_enabled and Input.is_action_just_released(a)


func _axis() -> float:
	if not input_override.is_empty():
		return float(input_override.get("x", 0.0))
	if not controls_enabled:
		return 0.0
	return Input.get_axis("move_left", "move_right")


func _aim_y() -> float:
	if not input_override.is_empty():
		return float(input_override.get("y", 0.0))
	if not controls_enabled:
		return 0.0
	return Input.get_axis("aim_up", "aim_down")


# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if dead:
		return
	invuln = maxf(0.0, invuln - delta)
	wall_lock = maxf(0.0, wall_lock - delta)
	_hurt_t = maxf(0.0, _hurt_t - delta)
	_blocked_msg_t = maxf(0.0, _blocked_msg_t - delta)
	_update_current(delta)
	var ax := _axis()
	var ay := _aim_y()
	if absf(ax) < 0.25:
		ax = 0.0
	if ax != 0.0 and wall_lock <= 0.0 and not drilling:
		facing = 1 if ax > 0 else -1
	elif ax != 0.0 and drilling and absf(ay) < 0.5:
		facing = 1 if ax > 0 else -1

	var on_floor := is_on_floor()
	if on_floor:
		coyote = Balance.COYOTE_TIME
		jet_ready = true
	else:
		coyote -= delta
	if _just("jump"):
		buffer = Balance.JUMP_BUFFER
	else:
		buffer -= delta

	# --- ladders ---
	var ladder_here := _ladder_overlap()
	if ladder_here and not on_ladder and (ay < -0.5 or (ay > 0.5 and not on_floor)):
		on_ladder = true
		velocity = Vector2.ZERO
	if on_ladder and not ladder_here:
		on_ladder = false
	if on_ladder:
		jet_ready = true
		velocity.y = ay * Balance.LADDER_SPEED if absf(ay) > 0.3 else 0.0
		velocity.x = ax * Balance.RUN_SPEED * 0.6
		if ladder_here:
			# gently centre on the ladder column for a clean climb
			var lc: float = (floorf(global_position.x / C) + 0.5) * C
			if absf(ax) < 0.1:
				global_position.x = move_toward(global_position.x, lc, 60.0 * delta)
		if buffer > 0.0:
			buffer = 0.0
			on_ladder = false
			velocity.y = -Balance.JUMP_VELOCITY * 0.85
			jumping = true
			Audio.play("jump", -6.0)
		if on_floor and ay > 0.5 and not _ladder_below():
			on_ladder = false
	else:
		_move_normal(delta, ax, on_floor)

	_update_drill(delta, ax, ay)
	if _just("charge"):
		_throw_charge(ay)
	if _just("interact") and mine:
		mine.player_interact(self)
	if _just("ladder") and mine:
		mine.build_ladder(self)

	move_and_slide()
	var now_floor := is_on_floor()
	if now_floor and not was_on_floor:
		var impact := fall_peak
		if impact > 200.0:
			_land_t = 0.12
			Audio.play_at("land", global_position, -4.0)
			if mine:
				mine.fx.dust(global_position + Vector2(0, HALF.y), Color(0.8, 0.7, 0.55), 6)
		fall_peak = 0.0
	if not now_floor:
		fall_peak = maxf(fall_peak, velocity.y)
	was_on_floor = now_floor
	_heat_and_audio(delta)
	_animate(delta, ax)


func _update_current(delta: float) -> void:
	var target := Vector2.ZERO
	if water:
		target = water.sample_contact(global_position, HALF) * Balance.WATER_PLAYER_DRIFT_GAIN
		if on_ladder or (drilling and _touching_solid()):
			target *= Balance.WATER_GRIP_RESISTANCE
		elif is_on_floor():
			target *= Balance.WATER_GROUND_RESISTANCE
		target = target.limit_length(Balance.WATER_PLAYER_DRIFT_MAX)
	water_drift = water_drift.lerp(target, 1.0 - exp(-delta * Balance.WATER_PLAYER_SMOOTH))


func submerged() -> bool:
	if grid == null:
		return false
	var c := grid.world_to_cell(global_position)
	return grid.get_water(c.x, c.y) >= Balance.WATER_MAX / 2 or grid.get_water(c.x, c.y - 1) >= Balance.WATER_MAX / 4


var in_water := false


func _move_normal(delta: float, ax: float, on_floor: bool) -> void:
	var wet := submerged()
	if wet != in_water:
		in_water = wet
		if mine:
			for k in 3:
				mine.fx.splash(global_position + Vector2(randf_range(-6, 6), -4))
			Audio.play_at("land", global_position, -6.0, 0.2)
	if wet:
		_swim(delta, ax)
		return
	var target := ax * Balance.RUN_SPEED
	if drilling and on_floor and drill_dir.y != 0:
		target *= 0.15
	target += water_drift.x
	var accel := Balance.GROUND_ACCEL if on_floor else Balance.AIR_ACCEL
	if wall_lock > 0.0:
		accel *= 0.15
	if absf(ax) > 0.0:
		velocity.x = move_toward(velocity.x, target, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, water_drift.x, (Balance.GROUND_FRICTION if on_floor else Balance.AIR_ACCEL * 0.7) * delta)
	# gravity
	var grav := Balance.GRAVITY
	if velocity.y > 0.0:
		grav *= 1.15
	velocity.y = minf(velocity.y + (grav + water_drift.y * Balance.WATER_PLAYER_SMOOTH) * delta, Balance.MAX_FALL + maxf(0.0, water_drift.y))
	# wall slide
	var wall_dir := _wall_dir()
	var sliding := not on_floor and wall_dir != 0 and signi(int(ax)) == wall_dir and velocity.y > 0.0
	if sliding:
		velocity.y = minf(velocity.y, Balance.WALL_SLIDE_SPEED)
		jet_ready = true
	# jumping
	if buffer > 0.0:
		if coyote > 0.0:
			velocity.y = -Balance.JUMP_VELOCITY
			buffer = 0.0
			coyote = 0.0
			jumping = true
			Audio.play("jump", -6.0)
		elif wall_dir != 0 and not on_floor:
			velocity = Vector2(-wall_dir * Balance.WALL_JUMP_PUSH, -Balance.WALL_JUMP_VELOCITY)
			facing = -wall_dir
			wall_lock = Balance.WALL_JUMP_LOCK
			buffer = 0.0
			jumping = true
			Audio.play("jump", -5.0, 0.1)
			if mine:
				mine.fx.dust(global_position + Vector2(wall_dir * HALF.x, 4), Color(0.8, 0.7, 0.55), 4)
		elif jet_ready:
			velocity.y = -Balance.JET_VELOCITY
			jet_ready = false
			buffer = 0.0
			jumping = true
			Audio.play("jet", -3.0)
			if mine:
				mine.fx.jet(global_position + Vector2(-facing * 6, 4))
	if jumping and velocity.y < 0.0 and _just_released("jump"):
		velocity.y *= Balance.JUMP_CUT
		jumping = false
	if velocity.y >= 0.0:
		jumping = false


func _swim(delta: float, ax: float) -> void:
	velocity.x = move_toward(velocity.x, ax * Balance.RUN_SPEED * Balance.WATER_SPEED + water_drift.x, Balance.AIR_ACCEL * delta)
	velocity.y = minf(velocity.y + (Balance.GRAVITY * Balance.WATER_GRAVITY + water_drift.y * Balance.WATER_PLAYER_SMOOTH) * delta, Balance.WATER_MAX_FALL + maxf(0.0, water_drift.y))
	velocity.y = move_toward(velocity.y, water_drift.y, 120.0 * delta)
	jet_ready = true
	if buffer > 0.0 or (_pressed("jump") and velocity.y > -40.0):
		buffer = 0.0
		velocity.y = -Balance.WATER_SWIM
		if mine and randf() < 0.5:
			mine.fx.splash(global_position + Vector2(0, 8))


func _wall_dir() -> int:
	if not grid:
		return 0
	for d in [1, -1]:
		var px: float = global_position.x + d * (HALF.x + 2.0)
		if grid.solid_at(Vector2(px, global_position.y - 6)) and grid.solid_at(Vector2(px, global_position.y + 6)):
			return d
	return 0


## Enough scaffold energy to raise at least one ladder cell?
func can_build_ladder() -> bool:
	return int(Game.run.get("scaffold", 0)) >= Balance.SCAFFOLD_ACTIVATE_COST + Balance.SCAFFOLD_CELL_COST


func feet_cell() -> Vector2i:
	return grid.world_to_cell(global_position + Vector2(0, HALF.y - 1.0))


func _ladder_overlap() -> bool:
	if not grid:
		return false
	for oy in [-8.0, 6.0]:
		var c := grid.world_to_cell(global_position + Vector2(0, oy))
		if grid.get_mat(c.x, c.y) == Cell.LADDER:
			return true
	return false


func _ladder_below() -> bool:
	var c := grid.world_to_cell(global_position + Vector2(0, HALF.y + 4))
	return grid.get_mat(c.x, c.y) == Cell.LADDER


# ---------------------------------------------------------------------------
# Drill
func _update_drill(delta: float, ax: float, ay: float) -> void:
	var want := _pressed("drill") and not overheated
	if ay < -0.5:
		drill_dir = Vector2i(0, -1)
	elif ay > 0.5:
		drill_dir = Vector2i(0, 1)
	else:
		drill_dir = Vector2i(facing, 0)
	targets = compute_targets(drill_dir)
	drilling = want
	drill_blocked = false
	if not drilling:
		drill_tick = 0.0
		return
	cool_delay = Balance.HEAT_COOL_DELAY
	# aim assist: when drilling vertically, slide onto the target column
	if drill_dir.y != 0 and targets.size() > 0 and absf(ax) < 0.2:
		var cx := (targets[0].x + 0.5) * C
		global_position.x = move_toward(global_position.x, cx, 70.0 * delta)
	drill_tick -= delta
	var heat_mult := 0.25
	for t0 in targets:
		var m0 := grid.get_mat(t0.x, t0.y)
		if Cell.is_solid(m0):
			heat_mult = maxf(heat_mult, float(Balance.MATERIAL.get(m0, {"heat": 1.0})["heat"]))
	if drill_tick <= 0.0:
		drill_tick = Balance.DRILL_TICK
		var dmg := Balance.drill_power(drill_level) * Balance.DRILL_TICK
		var hit_any := false
		for t in targets:
			var m := grid.get_mat(t.x, t.y)
			if not Cell.is_solid(m):
				continue
			hit_any = true
			if mine:
				mine.drill_cell(t, dmg, drill_level, self)
			if Cell.tier(m) > drill_level or grid.has_flag(t.x, t.y, Cell.F_PROTECTED) or m == Cell.BEDROCK:
				drill_blocked = true
		if mine:
			mine.drill_enemies(drill_hit_rect(), Balance.DRILL_ENEMY_DPS * Balance.DRILL_TICK, self)
			if hit_any:
				mine.noise(global_position, Balance.CRAWLER_HEARING)
		if drill_blocked and _blocked_msg_t <= 0.0 and mine:
			_blocked_msg_t = 2.0
			mine.toast("Too tough - needs DRILL Mk.IV or a charge" if grid.get_mat(targets[0].x, targets[0].y) == Cell.ALLOY else "Indestructible")
		_shake_t = 0.06
		if drill_dir.y > 0 and hit_any:
			velocity.y = minf(velocity.y, 30.0)
	# drill bite: while the bit is in rock above or beside you, it holds your
	# weight, so you can tunnel upward and cling to walls
	if _touching_solid() and not is_on_floor() and drill_dir.y <= 0:
		velocity.y = minf(velocity.y, 0.0 if drill_dir.y < 0 else 25.0)
		jet_ready = true
	heat = minf(heat_cap, heat + Balance.HEAT_PER_SEC * heat_mult * delta)
	if heat >= heat_cap:
		overheated = true
		drilling = false
		Audio.play("overheat")
		if mine:
			mine.toast("DRILL OVERHEAT - venting")
			mine.fx.steam(global_position + Vector2(facing * 10, -6))


func _touching_solid() -> bool:
	for t in targets:
		if grid.is_solid(t.x, t.y):
			return true
	return false


func compute_targets(dir: Vector2i) -> Array[Vector2i]:
	## Cells the drill bit touches: the body-adjacent column/row only, so the
	## drill can never reach through a wall.
	var out: Array[Vector2i] = []
	if not grid:
		return out
	var p := global_position
	if dir.x != 0:
		var x := p.x + dir.x * (HALF.x + 5.0)
		for oy in [-HALF.y + 5.0, HALF.y - 5.0]:
			var c := grid.world_to_cell(Vector2(x, p.y + oy))
			if not out.has(c):
				out.append(c)
		# feet cell first so tunnels are dug at walking height
		out.reverse()
	elif dir.y > 0:
		out.append(grid.world_to_cell(Vector2(p.x, p.y + HALF.y + 5.0)))
	else:
		# the head sits ~6 px below the top of a 2-cell tunnel, so probe a cell
		# above the head (still only the first solid cell, never through rock)
		var head := grid.world_to_cell(Vector2(p.x, p.y - HALF.y - 2.0))
		if grid.is_solid(head.x, head.y):
			out.append(head)
		else:
			out.append(Vector2i(head.x, head.y - 1) if p.y - HALF.y - (head.y * C) < 9.0 else head)
	return out


func drill_hit_rect() -> Rect2:
	var p := global_position
	if drill_dir.x != 0:
		return Rect2(p.x + (HALF.x if drill_dir.x > 0 else -HALF.x - 18), p.y - 10, 18, 20)
	if drill_dir.y > 0:
		return Rect2(p.x - 8, p.y + HALF.y - 2, 16, 16)
	return Rect2(p.x - 8, p.y - HALF.y - 14, 16, 16)


func _heat_and_audio(delta: float) -> void:
	if not drilling:
		cool_delay -= delta
		if cool_delay <= 0.0:
			heat = maxf(0.0, heat - Balance.heat_cooling(Progress.level("heat")) * delta * (1.4 if overheated else 1.0) * (Balance.WATER_COOLING if in_water else 1.0))
	if overheated and heat <= heat_cap * Balance.HEAT_RECOVER_FRACTION:
		overheated = false
		Audio.play("ui_confirm", -6.0)
	var loop := ""
	if drilling:
		loop = "drill_idle"
		for t in targets:
			var m := grid.get_mat(t.x, t.y)
			if Cell.is_solid(m):
				loop = "drill_" + Cell.sound_class(m)
				break
	if loop != _loop_name:
		if _loop_name != "":
			Audio.loop(_loop_name, false)
		_loop_name = loop
	if loop != "":
		Audio.loop(loop, true, -7.0 if loop == "drill_idle" else -3.0, 1.0 + heat / heat_cap * 0.25)


func stop_sounds() -> void:
	if _loop_name != "":
		Audio.loop(_loop_name, false)
		_loop_name = ""


# ---------------------------------------------------------------------------
func _throw_charge(ay: float) -> void:
	if not mine or Game.run.get("charges", 0) <= 0:
		if mine:
			mine.toast("No charges left")
			Audio.play("ui_deny")
		return
	Game.run["charges"] = int(Game.run["charges"]) - 1
	var v := Vector2(Balance.CHARGE_THROW.x * facing, Balance.CHARGE_THROW.y)
	if ay > 0.5:
		v = Vector2(0, 40)          # drop at feet
	elif ay < -0.5:
		v = Vector2(40 * facing, -260)
	v += velocity * 0.4
	mine.spawn_charge(global_position + Vector2(facing * 6, -6), v)
	Audio.play("throw")


func take_damage(amount: float, from: Vector2 = Vector2.INF, cause: String = "hazard") -> void:
	if dead or invuln > 0.0 or amount <= 0.0:
		return
	hp -= amount
	invuln = Balance.INVULN_TIME
	_hurt_t = 0.3
	hurt.emit(amount)
	Audio.play("hurt")
	if from != Vector2.INF:
		var d := signf(global_position.x - from.x)
		if d == 0.0:
			d = -facing
		velocity = Vector2(d * 140.0, -150.0)
	if mine:
		mine.shake(0.35)
		mine.fx.burst(global_position, Color(1.0, 0.5, 0.2), 8)
	if hp <= 0.0:
		hp = 0.0
		die(cause)


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)


func die(cause: String) -> void:
	if dead:
		return
	dead = true
	stop_sounds()
	Audio.play("death")
	velocity = Vector2.ZERO
	died.emit(cause)


# ---------------------------------------------------------------------------
func _animate(delta: float, ax: float) -> void:
	_anim_t += delta
	var anims: Dictionary = meta.get("anims", {})
	var anim := "idle"
	var speed := 6.0
	var on_floor := is_on_floor()
	if _hurt_t > 0.0:
		anim = "hurt"
	elif on_ladder:
		anim = "climb"
		speed = 8.0 if absf(velocity.y) > 1.0 else 0.0
	elif not on_floor:
		if _wall_dir() != 0 and velocity.y > 0.0 and signi(int(ax)) == _wall_dir():
			anim = "wall"
		else:
			anim = "jump" if velocity.y < -40.0 else "fall"
	elif _land_t > 0.0:
		anim = "land"
		_land_t -= delta
	elif absf(velocity.x) > 12.0:
		anim = "run"
		speed = 13.0 * absf(velocity.x) / Balance.RUN_SPEED
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.28
			Audio.play_at("step", global_position + Vector2(0, 12), -10.0, 0.15, 0.1)
	var a: Array = anims.get(anim, [0, 1])
	var frame_i: int = int(a[0]) + (int(_anim_t * speed) % int(a[1]) if speed > 0.0 else 0)
	body_sprite.frame = frame_i
	body_sprite.flip_h = facing < 0
	var vib := Vector2.ZERO
	if drilling:
		vib = Vector2(randf_range(-0.6, 0.6), randf_range(-0.5, 0.5)).round()
	body_sprite.position = vib
	# drill arm at the shoulder point of this frame
	var shoulders: Array = meta.get("shoulders", [])
	var sh := Vector2(19, 13)
	if frame_i < shoulders.size():
		sh = Vector2(shoulders[frame_i][0], shoulders[frame_i][1])
	var local := Vector2(sh.x - 16, sh.y - 16 - 3)
	if facing < 0:
		local.x = -local.x
	drill_sprite.position = local + vib
	var spin := int(_anim_t * 30.0) % 4 if drilling else 0
	drill_sprite.frame = spin + (4 if drilling else 0)
	if drill_dir.y < 0:
		drill_sprite.rotation = -PI / 2
		drill_sprite.flip_v = facing < 0
		drill_sprite.flip_h = false
	elif drill_dir.y > 0:
		drill_sprite.rotation = PI / 2
		drill_sprite.flip_v = facing > 0
		drill_sprite.flip_h = false
	else:
		drill_sprite.rotation = 0.0
		drill_sprite.flip_h = false
		drill_sprite.flip_v = false
		drill_sprite.scale.x = float(facing)
	if drill_dir.y != 0:
		drill_sprite.scale.x = 1.0
	lamp.position = Vector2(6 * facing, -10)
	# hurt / invulnerability flicker
	var fl := 0.0
	if _hurt_t > 0.0:
		fl = 0.45 if Settings.reduced_flashing() else 0.9
	flash_mat.set_shader_parameter("flash", fl)
	flash_mat.set_shader_parameter("flash_color", Color(1, 0.35, 0.3) if Settings.reduced_flashing() else Color(1, 1, 1))
	var blink := invuln > 0.0 and int(invuln * 14.0) % 2 == 0 and not Settings.reduced_flashing()
	var tint := Color(0.62, 0.82, 1.0) if in_water else Color.WHITE   # submerged look
	body_sprite.modulate = Color(tint.r, tint.g, tint.b, 0.55 if blink else 1.0)
	drill_sprite.modulate = body_sprite.modulate
	preview.queue_redraw()


class TargetPreview extends Node2D:
	var player: Player

	func _draw() -> void:
		if player.grid == null or player.dead:
			return
		var t := Time.get_ticks_msec() / 1000.0
		for c in player.targets:
			if not player.grid.is_solid(c.x, c.y):
				continue
			var r := Rect2(c.x * 16, c.y * 16, 16, 16)
			var blocked := player.grid.has_flag(c.x, c.y, Cell.F_PROTECTED) or Cell.tier(player.grid.get_mat(c.x, c.y)) > player.drill_level
			var col := Color(1.0, 0.3, 0.25, 0.8) if blocked else Color(1.0, 0.85, 0.35, 0.85 if player.drilling else 0.35)
			var k := 3.0 + (sin(t * 10.0) * 0.8 if player.drilling else 0.0)
			# corner brackets
			for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
				var sx := 1.0 if corner.x == r.position.x else -1.0
				var sy := 1.0 if corner.y == r.position.y else -1.0
				draw_line(corner, corner + Vector2(sx * k, 0), col, 1.0)
				draw_line(corner, corner + Vector2(0, sy * k), col, 1.0)
