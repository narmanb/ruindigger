class_name Fx
extends Node2D
## Pooled particle bursts and flash lights. Nothing here allocates per hit:
## emitters are created once and re-triggered round-robin.

var glow_layer: Node2D
var _pools: Dictionary = {}
var _idx: Dictionary = {}
var _lights: Array[PointLight2D] = []
var _light_i := 0
var _chunk_tex: Texture2D
var _dot_tex: Texture2D
var _puff_tex: Texture2D
var _glow_tex: Texture2D
var _light_tex: Texture2D
var _add_mat: CanvasItemMaterial


func setup(glow: Node2D) -> void:
	glow_layer = glow
	_chunk_tex = load("res://assets/gen/chunks.png")
	_dot_tex = load("res://assets/gen/dot.png")
	_puff_tex = load("res://assets/gen/puff.png")
	_glow_tex = load("res://assets/gen/glow.png")
	_light_tex = load("res://assets/gen/light.png")
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_make_pool("chips", 10, 14, self)
	_make_pool("dust", 8, 8, self)
	_make_pool("sparks", 8, 10, glow_layer)
	_make_pool("burst", 6, 18, self)
	_make_pool("glints", 6, 10, glow_layer)
	_make_pool("fire", 3, 40, glow_layer)
	_make_pool("gas", 6, 10, self)
	for i in 6:
		var l := PointLight2D.new()
		l.texture = _light_tex
		l.energy = 0.0
		l.enabled = false
		add_child(l)
		_lights.append(l)


func _make_pool(kind: String, count: int, amount: int, parent: Node) -> void:
	var arr: Array = []
	for i in count:
		var p := CPUParticles2D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = amount
		p.explosiveness = 0.95
		p.local_coords = false
		_configure(p, kind)
		parent.add_child(p)
		arr.append(p)
	_pools[kind] = arr
	_idx[kind] = 0


func _configure(p: CPUParticles2D, kind: String) -> void:
	match kind:
		"chips", "burst":
			p.texture = _chunk_tex
			var m := CanvasItemMaterial.new()
			m.particles_animation = true
			m.particles_anim_h_frames = 4
			m.particles_anim_v_frames = 1
			p.material = m
			p.anim_offset_max = 1.0
			p.lifetime = 0.7 if kind == "chips" else 0.9
			p.gravity = Vector2(0, 520)
			p.initial_velocity_min = 50.0
			p.initial_velocity_max = 140.0 if kind == "chips" else 190.0
			p.spread = 50.0 if kind == "chips" else 180.0
			p.angular_velocity_min = -400
			p.angular_velocity_max = 400
			p.scale_amount_min = 0.7
			p.scale_amount_max = 1.4
			p.damping_min = 10
			p.damping_max = 30
		"dust":
			p.texture = _puff_tex
			var m2 := CanvasItemMaterial.new()
			m2.particles_animation = true
			m2.particles_anim_h_frames = 4
			m2.particles_anim_v_frames = 1
			p.material = m2
			p.anim_speed_min = 1.0
			p.anim_speed_max = 1.0
			p.lifetime = 0.8
			p.gravity = Vector2(0, -12)
			p.initial_velocity_min = 8.0
			p.initial_velocity_max = 40.0
			p.spread = 180.0
			p.damping_min = 40
			p.damping_max = 60
			p.scale_amount_min = 0.8
			p.scale_amount_max = 1.6
			var grad := Gradient.new()
			grad.set_color(0, Color(1, 1, 1, 0.75))
			grad.set_color(1, Color(1, 1, 1, 0.0))
			p.color_ramp = grad
		"sparks", "glints":
			p.texture = _dot_tex
			p.material = _add_mat
			p.lifetime = 0.35 if kind == "sparks" else 0.7
			p.gravity = Vector2(0, 380) if kind == "sparks" else Vector2(0, -20)
			p.initial_velocity_min = 60.0
			p.initial_velocity_max = 190.0 if kind == "sparks" else 60.0
			p.spread = 40.0 if kind == "sparks" else 180.0
			p.scale_amount_min = 0.25
			p.scale_amount_max = 0.5
			var g2 := Gradient.new()
			g2.set_color(0, Color(1, 1, 1, 1))
			g2.set_color(1, Color(1, 1, 1, 0))
			p.color_ramp = g2
		"fire":
			p.texture = _glow_tex
			p.material = _add_mat
			p.lifetime = 0.6
			p.gravity = Vector2(0, -60)
			p.initial_velocity_min = 30.0
			p.initial_velocity_max = 150.0
			p.spread = 180.0
			p.scale_amount_min = 0.4
			p.scale_amount_max = 1.1
			p.damping_min = 80
			p.damping_max = 140
			var g3 := Gradient.new()
			g3.set_color(0, Color(1.0, 0.95, 0.6, 0.9))
			g3.add_point(0.4, Color(1.0, 0.45, 0.1, 0.6))
			g3.set_color(g3.get_point_count() - 1, Color(0.3, 0.05, 0.05, 0.0))
			p.color_ramp = g3
		"gas":
			p.texture = _puff_tex
			var m3 := CanvasItemMaterial.new()
			m3.particles_animation = true
			m3.particles_anim_h_frames = 4
			m3.particles_anim_v_frames = 1
			p.material = m3
			p.lifetime = 1.0
			p.gravity = Vector2(0, -25)
			p.initial_velocity_min = 10.0
			p.initial_velocity_max = 45.0
			p.spread = 180.0
			p.scale_amount_min = 0.8
			p.scale_amount_max = 1.8
			var g4 := Gradient.new()
			g4.set_color(0, Color(0.8, 1.0, 0.3, 0.55))
			g4.set_color(1, Color(0.5, 0.8, 0.1, 0.0))
			p.color_ramp = g4


func _emit(kind: String, pos: Vector2, color: Color, dir: Vector2 = Vector2.ZERO, amount_scale: float = 1.0) -> void:
	if Settings.low_effects() and randf() < 0.5:
		return
	var arr: Array = _pools[kind]
	var i: int = _idx[kind]
	_idx[kind] = (i + 1) % arr.size()
	var p: CPUParticles2D = arr[i]
	p.global_position = pos
	p.color = color
	if dir != Vector2.ZERO:
		p.direction = dir.normalized()
	else:
		p.direction = Vector2.UP
	p.restart()
	p.emitting = true


func chips(pos: Vector2, dir: Vector2, color: Color) -> void:
	_emit("chips", pos, color, dir)


func dust(pos: Vector2, color: Color, _n: int = 6) -> void:
	_emit("dust", pos, color.lerp(Color(0.85, 0.8, 0.7), 0.4))


func sparks(pos: Vector2, dir: Vector2, color: Color = Color(1.0, 0.8, 0.4)) -> void:
	_emit("sparks", pos, color, dir)


func glints(pos: Vector2, color: Color) -> void:
	_emit("glints", pos, color)


func burst(pos: Vector2, color: Color, _n: int = 12) -> void:
	_emit("burst", pos, color)


func jet(pos: Vector2) -> void:
	_emit("sparks", pos, Color(0.5, 1.0, 0.7), Vector2.DOWN)
	_emit("dust", pos + Vector2(0, 6), Color(0.7, 0.8, 0.75))


func steam(pos: Vector2) -> void:
	_emit("dust", pos, Color(0.9, 0.95, 1.0))
	_emit("dust", pos + Vector2(0, -8), Color(0.9, 0.95, 1.0))


func gas_puff(pos: Vector2) -> void:
	_emit("gas", pos, Color(1, 1, 1))


func explosion(pos: Vector2, radius: float, color: Color = Color(1.0, 0.6, 0.2)) -> void:
	_emit("fire", pos, Color(1, 1, 1))
	_emit("burst", pos, Color(0.6, 0.5, 0.45))
	_emit("dust", pos, Color(0.6, 0.55, 0.5))
	_emit("dust", pos + Vector2(radius * 0.4, 0), Color(0.6, 0.55, 0.5))
	_emit("dust", pos - Vector2(radius * 0.4, 0), Color(0.6, 0.55, 0.5))
	_emit("sparks", pos, Color(1.0, 0.8, 0.4), Vector2.UP)
	flash(pos, color, radius / 60.0, 0.45)


func flash(pos: Vector2, color: Color, scale_v: float, time: float) -> void:
	var l := _lights[_light_i]
	_light_i = (_light_i + 1) % _lights.size()
	l.global_position = pos
	l.color = color
	l.texture_scale = maxf(0.5, scale_v * 1.8)
	l.enabled = true
	var peak := 1.2 if Settings.reduced_flashing() else 2.4
	l.energy = peak
	var tw := create_tween()
	tw.tween_property(l, "energy", 0.0, time)
	tw.tween_callback(func() -> void: l.enabled = false)
