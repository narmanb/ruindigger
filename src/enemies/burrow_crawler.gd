class_name BurrowCrawler
extends CharacterBody2D
## Roaming burrower. Patrols open caverns, investigates noise made by digging,
## chases the player on sight, and can slowly tunnel through soft soil.
##
## Pathfinding is throttled: a BFS is requested at most every REPATH_INTERVAL
## and only when the target cell actually moved.

signal died(pos: Vector2)

const REPATH_INTERVAL := 0.55
const W := 18.0
const H := 14.0

var grid: TerrainGrid
var player: Player

var hp: int = Balance.CRAWLER_HP
var state: String = "patrol"
var _path: Array = []
var _path_index: int = 0
var _repath: float = 0.0
var _last_goal := Vector2i(-999, -999)
var _attack_cd: float = 0.0
var _noise_target: Vector2 = Vector2.ZERO
var _noise_timer: float = 0.0
var _anim: AnimatedSprite2D
var _facing: int = 1
var _idle_dir: int = 1
var _stuck: float = 0.0
var _hurt: float = 0.0
var _tunnel_cd: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(W, H)
	shape.shape = rect
	add_child(shape)
	_anim = AnimatedSprite2D.new()
	_anim.sprite_frames = _make_frames()
	_anim.play("crawler_walk")
	add_child(_anim)
	z_index = 18
	_idle_dir = 1 if randf() < 0.5 else -1
	if player and player.has_signal("noise_made"):
		player.noise_made.connect(_on_noise)

func _make_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	var sheet: Texture2D = load("res://assets/sprites/enemy_sheet.png")
	var f := FileAccess.open("res://assets/sprites/enemy_sheet.json", FileAccess.READ)
	var meta := {}
	if f:
		meta = JSON.parse_string(f.get_as_text())
		f.close()
	var cell: Array = meta.get("cell", [24, 20])
	var anims: Dictionary = meta.get("anims", {})
	for name in ["crawler_walk", "crawler_attack"]:
		if not anims.has(name):
			continue
		sf.add_animation(name)
		sf.set_animation_speed(name, 10.0 if name == "crawler_walk" else 8.0)
		sf.set_animation_loop(name, true)
		var row: int = int(anims[name]["row"])
		var frames: int = int(anims[name]["frames"])
		for i in frames:
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(i * int(cell[0]), row * int(cell[1]), int(cell[0]), int(cell[1]))
			sf.add_frame(name, at)
	return sf

func _on_noise(pos: Vector2, radius: float) -> void:
	if global_position.distance_to(pos) <= minf(radius, Balance.CRAWLER_NOISE_HEAR):
		_noise_target = pos
		_noise_timer = 4.0
		if state == "patrol":
			state = "investigate"

func _physics_process(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_hurt = maxf(0.0, _hurt - delta)
	_tunnel_cd = maxf(0.0, _tunnel_cd - delta)
	_noise_timer = maxf(0.0, _noise_timer - delta)
	if player == null or not is_instance_valid(player):
		velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y = minf(Balance.PLAYER_MAX_FALL, velocity.y + Balance.GRAVITY * delta)

	var to_player: Vector2 = player.global_position - global_position
	var sees: bool = to_player.length() < Balance.CRAWLER_SIGHT and \
			GridPathfinder.has_line_of_sight(grid, global_position, player.global_position)
	if sees:
		state = "chase"
	elif state == "chase":
		state = "investigate" if _noise_timer > 0.0 else "patrol"
	elif state == "investigate" and _noise_timer <= 0.0:
		state = "patrol"

	match state:
		"chase":
			_steer_towards(player.global_position, Balance.CRAWLER_SPEED, delta)
			if to_player.length() < 22.0 and _attack_cd <= 0.0:
				_attack()
		"investigate":
			_steer_towards(_noise_target, Balance.CRAWLER_SPEED * 0.85, delta)
		_:
			_patrol(delta)

	# Tunnelling: if blocked against soft soil and hunting, chew through slowly.
	if state != "patrol" and is_on_wall() and _tunnel_cd <= 0.0:
		_try_tunnel()

	_anim.flip_h = _facing < 0
	_anim.modulate = Color(1.6, 0.7, 0.7) if _hurt > 0.0 else Color.WHITE
	if _anim.animation != "crawler_walk":
		_anim.play("crawler_walk")
	move_and_slide()
	if absf(velocity.x) < 6.0 and state != "patrol":
		_stuck += delta
		if _stuck > 1.0:
			_path.clear()
			_repath = 0.0
			_stuck = 0.0
	else:
		_stuck = 0.0

func _patrol(delta: float) -> void:
	# Walk along the floor; reverse at walls or ledges.
	var ahead: Vector2 = global_position + Vector2(_idle_dir * 18.0, 0)
	var below: Vector2 = ahead + Vector2(0, 22.0)
	var c_ahead: Vector2i = grid.world_to_cell(ahead)
	var c_below: Vector2i = grid.world_to_cell(below)
	if grid.get_material(c_ahead.x, c_ahead.y) != Balance.Mat.EMPTY or \
			grid.get_material(c_below.x, c_below.y) == Balance.Mat.EMPTY:
		_idle_dir *= -1
	velocity.x = move_toward(velocity.x, _idle_dir * Balance.CRAWLER_SPEED * 0.5,
			260.0 * delta)
	_facing = _idle_dir

func _steer_towards(target: Vector2, speed: float, delta: float) -> void:
	_repath -= delta
	var goal_cell: Vector2i = grid.world_to_cell(target)
	if _repath <= 0.0 or goal_cell != _last_goal or _path.is_empty():
		_repath = REPATH_INTERVAL
		_last_goal = goal_cell
		_path = GridPathfinder.find_path(grid, grid.world_to_cell(global_position),
				goal_cell, 3000, false)
		_path_index = 0
	var dir: int = 0
	if _path.size() > 0:
		# Advance along the path.
		while _path_index < _path.size():
			var wp: Vector2 = grid.cell_to_world(_path[_path_index])
			if global_position.distance_to(wp) < 12.0:
				_path_index += 1
			else:
				break
		var node: Vector2i = _path[mini(_path_index, _path.size() - 1)]
		var wp2: Vector2 = grid.cell_to_world(node)
		dir = signi(int(round(wp2.x - global_position.x)))
	else:
		dir = signi(int(round(target.x - global_position.x)))
	if dir != 0:
		_facing = dir
		velocity.x = move_toward(velocity.x, dir * speed, 420.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 420.0 * delta)
	# Simple hop when the next path node is above us.
	if _path.size() > 0 and _path_index < _path.size():
		var nw: Vector2 = grid.cell_to_world(_path[_path_index])
		if nw.y < global_position.y - 18.0 and is_on_floor():
			velocity.y = -260.0

func _try_tunnel() -> void:
	_tunnel_cd = 1.2
	var probe := global_position + Vector2(_facing * 14.0, 0)
	var c: Vector2i = grid.world_to_cell(probe)
	if grid.get_material(c.x, c.y) == Balance.Mat.SOIL:
		grid.set_material(c.x, c.y, Balance.Mat.EMPTY)
		Fx.debris(grid.cell_to_world(c), Balance.Mat.SOIL, 6, 0.8)
		Audio.play_at("dig_soft", grid.cell_to_world(c), global_position, 600.0)

func _attack() -> void:
	_attack_cd = Balance.CRAWLER_ATTACK_CD
	_anim.play("crawler_attack")
	if player:
		player.take_damage(Balance.CRAWLER_ATTACK_DAMAGE, "crawler")

func take_damage(amount: int, from: Vector2 = Vector2.ZERO) -> void:
	hp -= amount
	_hurt = 0.25
	Fx.sparks(global_position, 5, false)
	if from != Vector2.ZERO:
		var d: float = signf(global_position.x - from.x)
		if d == 0.0:
			d = 1.0
		velocity += Vector2(d * 120.0, -90.0)
	Audio.play_at("dig_rock", global_position, from, 700.0, 0.2)
	if hp <= 0:
		_die()

func _die() -> void:
	Audio.play_at("enemy_death", global_position, player.global_position if player else global_position, 900.0)
	Fx.debris(global_position, Balance.Mat.SOIL, 16, 1.3)
	Fx.dust(global_position, 10, 1.2)
	died.emit(global_position)
	queue_free()
