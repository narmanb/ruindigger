class_name Player
extends CharacterBody2D
## The mining exosuit. Owns movement, drilling, heat, charges and health.
##
## Terrain interaction goes exclusively through TerrainGrid so that visuals,
## collision and the minimap all stay consistent with one source of truth.

signal health_changed(hp: int, max_hp: int)
signal heat_changed(heat: float, capacity: float, overheated: bool)
signal charges_changed(count: int, capacity: int)
signal cargo_pickup(ore_id: int, ok: bool)
signal died(cause: String)
signal extracted()
signal noise_made(pos: Vector2, radius: float)

const W := 20.0
const H := 24.0

enum State { MOVE, DRILL, HURT, DEAD }

var grid: TerrainGrid
var renderer: TerrainRenderer
var camera: Camera2D
var world: Node2D

var hp: int = 100
var max_hp: int = 100
var heat: float = 0.0
var heat_capacity: float = 1.0
var overheated: bool = false
var overheat_timer: float = 0.0
var charges: int = 3
var max_charges: int = 3
var drill_tier: int = 0
var drill_power: float = 1.0

var facing: int = 1
var aim_dir: Vector2i = Vector2i.RIGHT
var state: State = State.MOVE

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _invuln: float = 0.0
var _hurt_flash: float = 0.0
var _drill_accum: float = 0.0
var _drill_cell: Vector2i = Vector2i(-99, -99)
var _anim: AnimatedSprite2D
var _charge_scene_preload := preload("res://src/hazards/demo_charge.gd")
var _noise_timer: float = 0.0
var _extract_timer: float = 0.0
var _in_lift: bool = false
var _was_on_floor: bool = false
var _land_vel: float = 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(W, H)
	shape.shape = rect
	shape.position = Vector2(0, 0)
	add_child(shape)
	_build_anim()
	z_index = 20

func _build_anim() -> void:
	_anim = AnimatedSprite2D.new()
	var sf := SpriteFrames.new()
	var sheet: Texture2D = load("res://assets/sprites/player_sheet.png")
	var meta := _load_json("res://assets/sprites/player_sheet.json")
	var cell: Array = meta.get("cell", [20, 24])
	var anims: Dictionary = meta.get("anims", {})
	var fps := {"idle": 6.0, "run": 12.0, "jump": 6.0, "fall": 5.0, "drill": 14.0, "hurt": 8.0}
	var loops := {"idle": true, "run": true, "jump": false, "fall": true, "drill": true, "hurt": false}
	for name in anims:
		sf.add_animation(name)
		sf.set_animation_speed(name, fps.get(name, 8.0))
		sf.set_animation_loop(name, loops.get(name, true))
		var row: int = int(anims[name]["row"])
		var frames: int = int(anims[name]["frames"])
		for i in frames:
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(i * int(cell[0]), row * int(cell[1]), int(cell[0]), int(cell[1]))
			sf.add_frame(name, at)
	_anim.sprite_frames = sf
	_anim.position = Vector2(0, -2)
	add_child(_anim)
	_anim.play("idle")

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}

func configure_from_save() -> void:
	var drill_lv := SaveManager.upgrade_level("drill")
	var suit_lv := SaveManager.upgrade_level("suit")
	drill_tier = Balance.drill_tier(drill_lv)
	drill_power = Balance.drill_power(drill_lv)
	max_hp = Balance.player_max_hp(suit_lv)
	hp = max_hp
	heat_capacity = Balance.heat_capacity(suit_lv)
	max_charges = Balance.charge_capacity(SaveManager.upgrade_level("charges"))
	charges = max_charges
	health_changed.emit(hp, max_hp)
	heat_changed.emit(heat, heat_capacity, false)
	charges_changed.emit(charges, max_charges)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		return

	_tick_timers(delta)
	_read_input(delta)
	_apply_gravity(delta)
	_apply_movement(delta)
	_was_on_floor = is_on_floor()
	move_and_slide()
	if is_on_floor() and not _was_on_floor and _land_vel > 180.0:
		Audio.play("land", 0.1, -4.0)
		Fx.dust(global_position + Vector2(0, H * 0.5), 6, 0.8)
	_land_vel = velocity.y
	_post_move(delta)

func _tick_timers(delta: float) -> void:
	_coyote = maxf(0.0, _coyote - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_invuln = maxf(0.0, _invuln - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta * 3.0)
	_noise_timer = maxf(0.0, _noise_timer - delta)
	if overheated:
		overheat_timer -= delta
		if overheat_timer <= 0.0:
			overheated = false
			heat = heat_capacity * 0.35
			heat_changed.emit(heat, heat_capacity, false)
	else:
		if heat > 0.0:
			heat = maxf(0.0, heat - Balance.DRILL_HEAT_COOL * delta)
			heat_changed.emit(heat, heat_capacity, false)

func _read_input(delta: float) -> void:
	var ix: float = Input.get_axis("move_left", "move_right")
	if absf(ix) > 0.15:
		facing = 1 if ix > 0 else -1
	# Aim: up/down held wins for drilling direction, else facing.
	var iy: float = Input.get_axis("move_up", "move_down")
	if Input.is_action_pressed("move_up"):
		aim_dir = Vector2i(0, -1)
	elif Input.is_action_pressed("move_down") and not is_on_floor():
		aim_dir = Vector2i(0, 1)
	elif absf(ix) > 0.15:
		aim_dir = Vector2i(facing, 0)
	elif not is_on_floor():
		aim_dir = Vector2i(0, 1)
	else:
		aim_dir = Vector2i(facing, 0)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer = Balance.PLAYER_JUMP_BUFFER
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= Balance.PLAYER_JUMP_CUT
	if Input.is_action_just_pressed("charge"):
		_throw_charge()

	var drilling: bool = Input.is_action_pressed("drill")
	if drilling and not overheated:
		state = State.DRILL
		_do_drill(delta)
	else:
		state = State.MOVE
		Audio.drill(false)
		_drill_accum = 0.0
		_drill_cell = Vector2i(-99, -99)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(Balance.PLAYER_MAX_FALL, velocity.y + Balance.GRAVITY * delta)

func _apply_movement(delta: float) -> void:
	var ix: float = Input.get_axis("move_left", "move_right")
	var target: float = ix * Balance.PLAYER_WALK_SPEED
	var accel: float = Balance.PLAYER_ACCEL if is_on_floor() else Balance.PLAYER_AIR_ACCEL
	if absf(ix) < 0.15:
		velocity.x = move_toward(velocity.x, 0.0, Balance.PLAYER_FRICTION * delta)
	else:
		velocity.x = move_toward(velocity.x, target, accel * delta)

	if is_on_floor():
		_coyote = Balance.PLAYER_COYOTE_TIME
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = Balance.PLAYER_JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		Audio.play("jump", 0.1, -3.0)
		Fx.dust(global_position + Vector2(0, H * 0.5), 5, 0.7)

	# Drill dive: holding down + drill while airborne gives downward thrust.
	if state == State.DRILL and not is_on_floor() and aim_dir == Vector2i(0, 1):
		velocity.y = maxf(velocity.y, Balance.DRILL_DIVE_VELOCITY)

func _post_move(delta: float) -> void:
	# Animation selection
	var anim: String = "idle"
	if state == State.DRILL:
		anim = "drill"
	elif _hurt_flash > 0.0:
		anim = "hurt"
	elif not is_on_floor():
		anim = "jump" if velocity.y < 0.0 else "fall"
	elif absf(velocity.x) > 12.0:
		anim = "run"
	if _anim.animation != anim:
		_anim.play(anim)
	_anim.flip_h = facing < 0
	_anim.modulate = Color(1, 1, 1) if _invuln <= 0.0 or fmod(_invuln, 0.2) > 0.1 else Color(1, 0.5, 0.5)

	# Reveal fog and record depth
	if renderer:
		renderer.reveal(global_position, 5.0)
	var depth: int = grid.world_to_cell(global_position).y
	GameState.set_depth(depth)

	# Relic pickup
	if not GameState.relic_taken:
		for r in get_tree().get_nodes_in_group("relic"):
			if is_instance_valid(r) and global_position.distance_to(r.global_position) < 26.0:
				GameState.take_relic()
				Audio.play("extract_win", 0.0, -6.0)
				Fx.sparks(r.global_position, 26, true)
				Fx.burst_ring(r.global_position, 46.0, Color(1.0, 0.85, 0.4, 0.8))
				Fx.shake(3.0)
				if r is Node2D:
					r.queue_free()
				break

	# Lift proximity
	_in_lift = global_position.distance_to(grid.cell_to_world(grid.lift_cell)) < Balance.CELL * 2.0
	if _in_lift and Input.is_action_pressed("interact"):
		_extract_timer += delta
		if _extract_timer > 0.6:
			extracted.emit()
	else:
		_extract_timer = 0.0

# ---------------------------------------------------------------------------
# Drilling
# ---------------------------------------------------------------------------

func _drill_target_cell() -> Vector2i:
	var origin: Vector2 = global_position
	var best: Vector2i = Vector2i(-99, -99)
	var best_d: float = 1e9
	# Consider the aimed direction plus a limited diagonal assist.
	var dirs: Array[Vector2i] = [aim_dir]
	if aim_dir.x != 0:
		dirs.append(Vector2i(aim_dir.x, -1))
		if not is_on_floor():
			dirs.append(Vector2i(aim_dir.x, 1))
	else:
		dirs.append(Vector2i(facing, aim_dir.y))
	for d in dirs:
		for step in range(1, int(ceil(Balance.DRILL_REACH)) + 1):
			var c: Vector2i = grid.world_to_cell(origin) + d * step
			if not grid.in_bounds(c.x, c.y):
				continue
			if grid.get_material(c.x, c.y) == Balance.Mat.EMPTY:
				continue
			if not grid.can_mine(c.x, c.y, drill_tier):
				# Cannot mine, but do not look past it either.
				break
			var wp: Vector2 = grid.cell_to_world(c)
			var dist: float = wp.distance_to(origin)
			if dist > Balance.DRILL_REACH * grid.tile_size:
				break
			if dist < best_d:
				best_d = dist
				best = c
			break
	return best

func _do_drill(delta: float) -> void:
	var cell: Vector2i = _drill_target_cell()
	if cell.x < 0:
		Audio.drill(false)
		return
	var mat: int = grid.get_material(cell.x, cell.y)
	Audio.drill(true, mat)
	if cell != _drill_cell:
		_drill_cell = cell
		_drill_accum = 0.0
	_drill_accum += delta
	var hit_time: float = Balance.MATERIAL_DRILL_TIME.get(mat, 0.2) / maxf(0.2, drill_power)
	while _drill_accum >= hit_time:
		_drill_accum -= hit_time
		_hit_tile(cell, mat)

func _hit_tile(cell: Vector2i, mat: int) -> void:
	var wp: Vector2 = grid.cell_to_world(cell)
	Fx.sparks(wp, 5, mat != Balance.Mat.ALLOY)
	Fx.debris(wp, mat, 6, 0.7)
	Audio.dig_hit(mat)
	_make_noise(wp, 220.0)
	heat = minf(heat_capacity, heat + Balance.DRILL_HEAT_PER_TICK)
	heat_changed.emit(heat, heat_capacity, overheated)
	if heat >= heat_capacity:
		overheated = true
		overheat_timer = Balance.DRILL_OVERHEAT_LOCK
		Audio.play("alarm", 0.0, -6.0)
		Fx.sparks(wp, 12, true)
		heat_changed.emit(heat, heat_capacity, true)
	var broke: bool = grid.apply_damage(cell.x, cell.y, maxi(1, int(round(drill_power))), drill_tier)
	if broke:
		Fx.dust(wp, 8, 1.0)
		Fx.debris(wp, mat, 10, 1.0)
		Fx.shake(1.6)
		_check_gas(cell)

func _check_gas(cell: Vector2i) -> void:
	var i: int = grid.idx(cell.x, cell.y)
	if grid.gas.has(i):
		grid.gas.erase(i)
		_vent_gas(cell)

func _vent_gas(cell: Vector2i) -> void:
	var wp: Vector2 = grid.cell_to_world(cell)
	Audio.play_at("gas_hiss", wp, global_position, 700.0)
	Fx.dust(wp, 14, 1.6)
	Fx.burst_ring(wp, 26.0, Color(0.6, 1.0, 0.6, 0.5))
	# Gas damages the player if close, and is very dangerous near a charge.
	var d: float = wp.distance_to(global_position)
	if d < Balance.GAS_IGNITE_RADIUS * grid.tile_size:
		take_damage(Balance.GAS_DAMAGE, "gas")
	# Chain to neighbouring pockets with a short delay effect.
	for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nc: Vector2i = cell + n
		if grid.in_bounds(nc.x, nc.y) and grid.gas.has(grid.idx(nc.x, nc.y)):
			grid.gas.erase(grid.idx(nc.x, nc.y))
			Fx.dust(grid.cell_to_world(nc), 6, 1.0)

func _make_noise(pos: Vector2, radius: float) -> void:
	if _noise_timer > 0.0:
		return
	_noise_timer = 0.2
	noise_made.emit(pos, radius)

# ---------------------------------------------------------------------------
# Charges
# ---------------------------------------------------------------------------

func _throw_charge() -> void:
	if charges <= 0:
		Audio.play("ui_click", 0.0, -8.0)
		return
	charges -= 1
	charges_changed.emit(charges, max_charges)
	var c := Node2D.new()
	c.set_script(_charge_scene_preload)
	c.set("grid", grid)
	c.set("thrower", self)
	c.global_position = global_position + Vector2(aim_dir.x, aim_dir.y) * 14.0
	world.add_child(c)

# ---------------------------------------------------------------------------
# Damage / health
# ---------------------------------------------------------------------------

func take_damage(amount: int, cause: String = "") -> void:
	if state == State.DEAD or _invuln > 0.0:
		return
	hp = maxi(0, hp - amount)
	_invuln = Balance.PLAYER_HIT_INVULN
	_hurt_flash = 1.0
	health_changed.emit(hp, max_hp)
	Audio.play("hurt", 0.08, -2.0)
	Fx.sparks(global_position, 8, false)
	Fx.shake(4.0)
	var kb: Vector2 = Vector2(-facing * 90.0, -140.0)
	velocity += kb
	if hp <= 0:
		_die(cause)

func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)
	health_changed.emit(hp, max_hp)

func add_charge(n: int = 1) -> void:
	charges = mini(max_charges, charges + n)
	charges_changed.emit(charges, max_charges)

func _die(cause: String) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	Audio.drill(false)
	Audio.play("enemy_death", 0.0, -4.0)
	Fx.debris(global_position, Balance.Mat.ALLOY, 22, 1.6)
	Fx.shake(7.0)
	died.emit(cause)

func is_invulnerable() -> bool:
	return _invuln > 0.0

func in_lift() -> bool:
	return _in_lift
