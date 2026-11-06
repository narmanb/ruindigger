class_name RuinSentry
extends StaticBody2D
## Stationary ruin defence turret. Warns, tracks the player with line of sight,
## fires dodgeable bursts, and can be disabled by destroying its exposed power
## module (extra damage from below or from falling debris is rewarded).

signal died(pos: Vector2)

const W := 22.0
const H := 20.0

var grid: TerrainGrid
var player: Player

var hp: int = Balance.SENTRY_HP
var state: String = "dormant"
var _warn: float = 0.0
var _fire_cd: float = 0.0
var _burst_left: int = 0
var _burst_cd: float = 0.0
var _anim: AnimatedSprite2D
var _hurt: float = 0.0
var _barrel_dir := Vector2.RIGHT
var _lost_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(W, H)
	shape.shape = rect
	shape.position = Vector2(0, -2)
	add_child(shape)
	_anim = AnimatedSprite2D.new()
	_anim.sprite_frames = _make_frames()
	_anim.play("sentry_idle")
	_anim.position = Vector2(0, -3)
	add_child(_anim)
	z_index = 18

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
	for name in ["sentry_idle", "sentry_fire"]:
		if not anims.has(name):
			continue
		sf.add_animation(name)
		sf.set_animation_speed(name, 5.0 if name == "sentry_idle" else 10.0)
		sf.set_animation_loop(name, name == "sentry_idle")
		var row: int = int(anims[name]["row"])
		var frames: int = int(anims[name]["frames"])
		for i in frames:
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(i * int(cell[0]), row * int(cell[1]), int(cell[0]), int(cell[1]))
			sf.add_frame(name, at)
	return sf

func _physics_process(delta: float) -> void:
	_hurt = maxf(0.0, _hurt - delta)
	_anim.modulate = Color(1.7, 0.7, 0.7) if _hurt > 0.0 else Color.WHITE
	if player == null or not is_instance_valid(player):
		return
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_warn = maxf(0.0, _warn - delta)
	_burst_cd = maxf(0.0, _burst_cd - delta)
	var to: Vector2 = player.global_position - global_position
	var sees: bool = to.length() < Balance.SENTRY_SIGHT and \
			GridPathfinder.has_line_of_sight(grid, global_position, player.global_position)

	match state:
		"dormant":
			if sees:
				state = "warn"
				_warn = Balance.SENTRY_WARN_TIME
				Audio.play_at("alarm", global_position, player.global_position, 800.0)
		"warn":
			if sees:
				_barrel_dir = to.normalized()
				if _warn <= 0.0:
					state = "fire"
					_burst_left = Balance.SENTRY_BURST
					_burst_cd = 0.0
					_lost_timer = 0.0
			else:
				state = "dormant"
		"fire":
			if sees:
				_barrel_dir = to.normalized()
				_lost_timer = 0.0
			else:
				_lost_timer += delta
			if _burst_cd <= 0.0 and _burst_left > 0:
				_fire_one()
				_burst_left -= 1
				_burst_cd = 0.16
			if _burst_left <= 0 and _fire_cd <= 0.0:
				if _lost_timer > 0.6 or not sees:
					state = "dormant" if not sees else "warn"
					if sees:
						_warn = Balance.SENTRY_WARN_TIME * 0.4
				else:
					_burst_left = Balance.SENTRY_BURST
					_fire_cd = Balance.SENTRY_FIRE_CD
	queue_redraw()

func _fire_one() -> void:
	var shot := Node2D.new()
	shot.set_script(load("res://src/enemies/sentry_shot.gd"))
	shot.set("grid", grid)
	shot.set("player", player)
	shot.global_position = global_position + _barrel_dir * 16.0
	shot.set("dir", _barrel_dir)
	get_tree().current_scene.add_child(shot)
	Audio.play_at("laser", global_position, player.global_position, 900.0)
	_anim.play("sentry_fire")
	get_tree().create_timer(0.18).timeout.connect(func():
		if is_instance_valid(_anim):
			_anim.play("sentry_idle"))

func _draw() -> void:
	# Aim line + warning arc while tracking.
	if state == "warn":
		draw_line(Vector2.ZERO, _barrel_dir * Balance.SENTRY_SIGHT * 0.4,
				Color(1.0, 0.35, 0.3, 0.28), 1.0)
		draw_arc(Vector2.ZERO, 16.0, 0, TAU, 20, Color(1.0, 0.4, 0.3, 0.5), 1.5)
	elif state == "fire":
		draw_line(Vector2.ZERO, _barrel_dir * Balance.SENTRY_SIGHT * 0.4,
				Color(1.0, 0.2, 0.15, 0.35), 1.0)

func take_damage(amount: int, from: Vector2 = Vector2.ZERO) -> void:
	# Reward hitting the exposed power module: extra damage from below.
	var bonus := 1.0
	if from.y > global_position.y + 6.0:
		bonus = 1.8   # shot from underneath hits the module
	hp -= int(round(amount * bonus))
	_hurt = 0.2
	Fx.sparks(global_position, 6, false)
	Audio.play_at("dig_alloy", global_position, from, 700.0, 0.2)
	if state == "dormant":
		state = "warn"
		_warn = Balance.SENTRY_WARN_TIME
	if hp <= 0:
		_die()

func _die() -> void:
	Audio.play_at("enemy_death", global_position, player.global_position if player else global_position, 900.0)
	Fx.burst_ring(global_position, 30.0, Color(1.0, 0.5, 0.3, 0.7))
	Fx.sparks(global_position, 18, true)
	Fx.debris(global_position, Balance.Mat.ALLOY, 18, 1.4)
	died.emit(global_position)
	queue_free()
