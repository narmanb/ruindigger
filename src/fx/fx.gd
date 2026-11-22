class_name Fx
extends Node2D
## Pooled particle bursts and flash lights. Nothing here allocates per hit:
## emitters are created once and re-triggered round-robin.
##
## Intensity: a call asks for n particles; that becomes 1..3 pooled emitters
## (each emitter has a fixed amount, UNIT[kind]). Priority: ESSENTIAL effects
## (hazard telegraphs, the core of a blast) always play; NORMAL ones are cut to
## one emitter with Low Effects and skipped off screen; DECOR ones (the extras
## of the game-feel pass) also need Game Feel above Off, Low Effects off, and
## room in a small per-frame budget.

enum { ESSENTIAL, NORMAL, DECOR }
const UNIT := {"chips": 14, "dust": 8, "sparks": 10, "burst": 10, "glints": 10, "fire": 40, "gas": 10, "splash": 6}
const POOL := {"chips": 14, "dust": 14, "sparks": 12, "burst": 12, "glints": 6, "fire": 4, "gas": 6, "splash": 12}

var glow_layer: Node2D
var _pools: Dictionary = {}
var _idx: Dictionary = {}
var _lights: Array[PointLight2D] = []
var _light_tw: Array = []          # the fade tween that owns each light (killed when it is reused)
var _light_i := 0
var _frame := -1
var _decor_left := 0
var _view := Rect2()
var emitted := 0                   # emitters started (tests)
var skipped := 0                   # requests dropped by priority, budget or off-screen (tests)
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
	for kind: String in ["chips", "dust", "burst", "gas", "splash"]:
		_make_pool(kind, int(POOL[kind]), int(UNIT[kind]), self)
	for kind: String in ["sparks", "glints", "fire"]:
		_make_pool(kind, int(POOL[kind]), int(UNIT[kind]), glow_layer)
	for i in 6:
		var l := PointLight2D.new()
		l.texture = _light_tex
		l.energy = 0.0
		l.enabled = false
		add_child(l)
		_lights.append(l)
		_light_tw.append(null)


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
		"splash":
			p.texture = _dot_tex
			p.lifetime = 0.45
			p.gravity = Vector2(0, 500)
			p.initial_velocity_min = 30.0
			p.initial_velocity_max = 90.0
			p.direction = Vector2.UP
			p.spread = 55.0
			p.scale_amount_min = 0.2
			p.scale_amount_max = 0.4
			var g5 := Gradient.new()
			g5.set_color(0, Color(0.75, 0.9, 1.0, 0.9))
			g5.set_color(1, Color(0.5, 0.75, 1.0, 0.0))
			p.color_ramp = g5
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


## How many pooled emitters a request for n particles of `kind` uses (1..3).
static func emitters_for(kind: String, n: int) -> int:
	return clampi(int(ceil(float(n) / float(UNIT.get(kind, 10)))), 1, 3)


func _new_frame() -> void:
	var f := Engine.get_process_frames()
	if f == _frame:
		return
	_frame = f
	_decor_left = Balance.FX_DECOR_PER_FRAME
	var vp := get_viewport()
	if vp:
		_view = (vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()).grow(Balance.FX_MARGIN)


func on_screen(pos: Vector2) -> bool:
	_new_frame()
	return _view.size == Vector2.ZERO or _view.has_point(pos)


func _emit(kind: String, pos: Vector2, color: Color, dir: Vector2 = Vector2.ZERO, n: int = 0, prio: int = NORMAL) -> void:
	_new_frame()
	var count := emitters_for(kind, n if n > 0 else int(UNIT.get(kind, 10)))
	if prio != ESSENTIAL:
		if not on_screen(pos):
			skipped += 1
			return
		if Settings.low_effects():
			count = 1
	if prio == DECOR:
		if Settings.feel("decor") <= 0.0 or _decor_left <= 0:
			skipped += 1
			return
		count = mini(count, _decor_left)
		_decor_left -= count
	var arr: Array = _pools[kind]
	for k in count:
		var i: int = _idx[kind]
		_idx[kind] = (i + 1) % arr.size()
		var p: CPUParticles2D = arr[i]
		p.global_position = pos + (Vector2(randf_range(-4.0, 4.0), randf_range(-3.0, 3.0)) if k > 0 else Vector2.ZERO)
		p.color = color
		p.direction = dir.normalized() if dir != Vector2.ZERO else Vector2.UP
		p.restart()
		p.emitting = true
		emitted += 1


func splash(pos: Vector2) -> void:
	_emit("splash", pos, Color(1, 1, 1), Vector2.UP)


func spray(pos: Vector2, direction: Vector2) -> void:
	_emit("splash", pos, Color(0.8, 0.95, 1.0), direction)


func chips(pos: Vector2, dir: Vector2, color: Color, n: int = 0, prio: int = NORMAL) -> void:
	_emit("chips", pos, color, dir, n, prio)


func dust(pos: Vector2, color: Color, n: int = 6, prio: int = NORMAL) -> void:
	_emit("dust", pos, color.lerp(Color(0.85, 0.8, 0.7), 0.4), Vector2.ZERO, n, prio)


func sparks(pos: Vector2, dir: Vector2, color: Color = Color(1.0, 0.8, 0.4), n: int = 0, prio: int = NORMAL) -> void:
	_emit("sparks", pos, color, dir, n, prio)


func glints(pos: Vector2, color: Color) -> void:
	_emit("glints", pos, color)


func burst(pos: Vector2, color: Color, n: int = 12, prio: int = NORMAL) -> void:
	_emit("burst", pos, color, Vector2.ZERO, n, prio)


func jet(pos: Vector2) -> void:
	_emit("sparks", pos, Color(0.5, 1.0, 0.7), Vector2.DOWN)
	_emit("dust", pos + Vector2(0, 6), Color(0.7, 0.8, 0.75))


func steam(pos: Vector2) -> void:
	_emit("dust", pos, Color(0.9, 0.95, 1.0))
	_emit("dust", pos + Vector2(0, -8), Color(0.9, 0.95, 1.0))


func gas_puff(pos: Vector2) -> void:
	_emit("gas", pos, Color(1, 1, 1), Vector2.ZERO, 0, ESSENTIAL)     # a vent's warning


## A blast, sized by its radius (px): a shear charge is small, a bomb-eater
## big. The fire and the flash always play; the rest scales.
func explosion(pos: Vector2, radius: float, color: Color = Color(1.0, 0.6, 0.2)) -> void:
	var k := radius / (Balance.CHARGE_RADIUS_CELLS * Balance.CELL)     # 1 = an un-upgraded charge
	_emit("fire", pos, Color(1, 1, 1), Vector2.ZERO, 0, ESSENTIAL)
	if k > 1.2:
		_emit("fire", pos + Vector2(0, -radius * 0.2), Color(1, 1, 1), Vector2.ZERO, 0, ESSENTIAL)
	_emit("burst", pos, Color(0.6, 0.5, 0.45), Vector2.ZERO, int(round(10.0 * k)), ESSENTIAL)
	_emit("dust", pos, Color(0.6, 0.55, 0.5))
	_emit("dust", pos + Vector2(radius * 0.4, 0), Color(0.6, 0.55, 0.5))
	_emit("dust", pos - Vector2(radius * 0.4, 0), Color(0.6, 0.55, 0.5))
	_emit("sparks", pos, Color(1.0, 0.8, 0.4), Vector2.UP, int(round(10.0 * k)))
	# game feel: a wider ring of dust and a spray of chips for the bigger blasts
	if k >= 0.9:
		_emit("dust", pos + Vector2(radius * 0.75, -4), Color(0.6, 0.55, 0.5), Vector2.ZERO, 0, DECOR)
		_emit("dust", pos - Vector2(radius * 0.75, 4), Color(0.6, 0.55, 0.5), Vector2.ZERO, 0, DECOR)
		_emit("chips", pos, Color(0.55, 0.48, 0.42), Vector2.UP, int(round(14.0 * k)), DECOR)
	flash(pos, color, radius / 60.0, 0.45, true)


## A short light. `boost`: a big event, brighter at Strong (Reduced Flashing
## caps it). Each of the six lights belongs to its newest flash: the older
## fade is killed, so it can't switch the light off early.
func flash(pos: Vector2, color: Color, scale_v: float, time: float, boost: bool = false) -> void:
	var i := _light_i
	_light_i = (_light_i + 1) % _lights.size()
	var l := _lights[i]
	var old: Tween = _light_tw[i]
	if old != null and old.is_valid():
		old.kill()
	l.global_position = pos
	l.color = color
	l.texture_scale = maxf(0.5, scale_v * 1.8)
	l.enabled = true
	var peak := 1.2 if Settings.reduced_flashing() else 2.4
	if boost:
		peak *= Settings.feel("flash")
	l.energy = peak
	var tw := create_tween()
	tw.tween_property(l, "energy", 0.0, time)
	tw.tween_callback(func() -> void: l.enabled = false)
	_light_tw[i] = tw


func lights_on() -> int:
	var n := 0
	for l in _lights:
		if l.enabled:
			n += 1
	return n
