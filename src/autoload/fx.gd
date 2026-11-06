extends Node
## Central place to spawn one-shot visual effects. Everything is pooled so
## heavy drilling and collapsing never allocates during play.

const POOL_SIZE := 320

var _pool: Array[CPUParticles2D] = []
var _root: Node2D
var _shake: float = 0.0
var _shake_decay: float = 3.2
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func register_root(root: Node2D) -> void:
	_root = root
	_build_pool()

## Drops references to the pooled particles. The pool lives under the mine's
## world node, so when that scene is torn down these become dangling unless we
## let go of them; without this the engine reports leaked RIDs at exit.
func clear_root() -> void:
	_pool.clear()
	_root = null

func _build_pool() -> void:
	for i in POOL_SIZE:
		var p := CPUParticles2D.new()
		p.emitting = false
		p.one_shot = true
		p.local_coords = false
		p.z_index = 30
		p.texture = load("res://assets/fx/fx_sheet.png")
		_root.add_child(p)
		_pool.append(p)

func _take() -> CPUParticles2D:
	for p in _pool:
		if not p.emitting:
			return p
	return _pool[0] if _pool.size() > 0 else null

func _region(tex_row: int, tex_col: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	var sheet := load("res://assets/fx/fx_sheet.png")
	at.atlas = sheet
	at.region = Rect2(tex_col * 64, tex_row * 64, 64, 64)
	return at

## Debris burst when a tile breaks. `mat` selects chunk tint.
func debris(pos: Vector2, mat: int, amount: int = 10, power: float = 1.0) -> void:
	var p := _take()
	if p == null:
		return
	var tint := _material_tint(mat)
	p.position = pos
	p.texture = _region(1, clampi(mat - 1, 0, 3))
	p.amount = clampi(amount, 3, 32)
	p.lifetime = 0.55
	p.explosiveness = 0.85
	p.spread = 180.0
	p.gravity = Vector2(0, 700)
	p.initial_velocity_min = 40 * power
	p.initial_velocity_max = 150 * power
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.8
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	p.color = Color(tint.r, tint.g, tint.b, 1.0)
	p.emitting = true

func dust(pos: Vector2, amount: int = 8, power: float = 1.0) -> void:
	var p := _take()
	if p == null:
		return
	p.position = pos
	p.texture = _region(3, 0)
	p.amount = clampi(amount, 2, 20)
	p.lifetime = 0.8
	p.explosiveness = 0.7
	p.spread = 70.0
	p.gravity = Vector2(0, -30)
	p.initial_velocity_min = 10 * power
	p.initial_velocity_max = 55 * power
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	p.color = Color(0.72, 0.68, 0.62, 0.55)
	p.emitting = true

func sparks(pos: Vector2, amount: int = 8, warm: bool = true) -> void:
	var p := _take()
	if p == null:
		return
	p.position = pos
	p.texture = _region(2, 1 if warm else 2)
	p.amount = clampi(amount, 2, 20)
	p.lifetime = 0.35
	p.explosiveness = 0.9
	p.spread = 180.0
	p.gravity = Vector2(0, 420)
	p.initial_velocity_min = 60
	p.initial_velocity_max = 220
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.6
	p.color = Color(1.0, 0.85, 0.55) if warm else Color(0.6, 0.95, 1.0)
	p.emitting = true

func burst_ring(pos: Vector2, radius: float, color: Color) -> void:
	var p := _take()
	if p == null:
		return
	p.position = pos
	p.texture = _region(2, 3)
	p.amount = 3
	p.lifetime = 0.32
	p.explosiveness = 1.0
	p.spread = 0.0
	p.initial_velocity_min = 0
	p.initial_velocity_max = 0
	p.scale_amount_min = radius / 32.0
	p.scale_amount_max = radius / 32.0
	p.color = color
	p.emitting = true

func _material_tint(mat: int) -> Color:
	match mat:
		Balance.Mat.SOIL:
			return Color(0.58, 0.44, 0.28)
		Balance.Mat.BASALT:
			return Color(0.42, 0.38, 0.34)
		Balance.Mat.ALLOY:
			return Color(0.55, 0.5, 0.62)
		_:
			return Color(0.5, 0.5, 0.55)

func shake(amount: float) -> void:
	var scale := float(SaveManager.settings.get("screen_shake", 1.0))
	_shake = max(_shake, amount * scale)

func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = max(0.0, _shake - _shake_decay * delta)

func shake_offset() -> Vector2:
	if _shake <= 0.0:
		return Vector2.ZERO
	var m := _shake
	return Vector2(_rng.randf_range(-m, m), _rng.randf_range(-m, m))
