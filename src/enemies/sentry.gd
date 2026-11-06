class_name Sentry
extends Node2D
## Ruin Sentry. Stationary turret with an explicit, readable cycle:
##   DORMANT  cyan eye. Player inside SENTRY_RANGE with line of sight -> WARN.
##   WARN     amber pulse + rising beep for SENTRY_WARN s (time to take cover).
##   FIRE     red eye, a burst of SENTRY_BURST slow dodgeable bolts.
##   COOLDOWN then re-warn (shorter) if still in sight; after SENTRY_FORGET s
##            without sight it goes dormant again.
## Disabled by destroying it (drill/charge), destroying its exposed power
## module, or by dropping rubble on it.

enum S { DORMANT, WARN, FIRE, COOLDOWN, DEAD }

var mine: Node
var grid: TerrainGrid
var ceiling := false
var state := S.DORMANT
var hp := Balance.SENTRY_HP
var t := 0.0
var shots_left := 0
var lost_t := 0.0
var aim := Vector2.RIGHT
var module: PowerModule
var base: Sprite2D
var head: Sprite2D
var eye: Sprite2D
var light: PointLight2D
var flash := 0.0
var mat: ShaderMaterial
var sheet: Texture2D


func _ready() -> void:
	grid = mine.grid
	sheet = load("res://assets/gen/sentry.png")
	mat = ShaderMaterial.new()
	mat.shader = load("res://src/fx/flash.gdshader")
	base = Sprite2D.new()
	base.texture = sheet
	base.hframes = 7
	base.frame = 0
	base.offset = Vector2(0, -4)
	base.material = mat
	add_child(base)
	head = Sprite2D.new()
	head.texture = sheet
	head.hframes = 7
	head.frame = 1
	head.offset = Vector2(2, -9)
	head.position = Vector2(0, -6)
	head.material = mat
	add_child(head)
	if ceiling:
		rotation = PI
	eye = Sprite2D.new()
	eye.texture = load("res://assets/gen/glow.png")
	eye.scale = Vector2(0.35, 0.35)
	mine.glow_root.add_child(eye)
	light = PointLight2D.new()
	light.texture = load("res://assets/gen/light.png")
	light.texture_scale = 0.45
	light.energy = 0.6
	light.position = Vector2(0, -14)
	add_child(light)


func _exit_tree() -> void:
	if is_instance_valid(eye):
		eye.queue_free()


func hit_rect() -> Rect2:
	return Rect2(global_position + (Vector2(-10, -22) if not ceiling else Vector2(-10, 2)), Vector2(20, 20))


func _eye_pos() -> Vector2:
	return head.global_position + (Vector2(0, -10) if not ceiling else Vector2(0, 10))


func _sees() -> bool:
	var pl: Player = mine.player
	if pl == null or pl.dead:
		return false
	var e := _eye_pos()
	if e.distance_to(pl.global_position) > Balance.SENTRY_RANGE * Balance.CELL:
		return false
	return grid.line_clear(e, pl.global_position + Vector2(0, -4))


func _physics_process(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 5.0)
	if state == S.DEAD:
		_visual()
		return
	if module and module.dead:
		_disable("power cut")
		return
	var pl: Player = mine.player
	var sees := _sees()
	if sees:
		lost_t = 0.0
		var want := (pl.global_position + Vector2(0, -4) - _eye_pos()).normalized()
		aim = aim.slerp(want, clampf(delta * 6.0, 0.0, 1.0))
	else:
		lost_t += delta
	t -= delta
	match state:
		S.DORMANT:
			if sees:
				state = S.WARN
				t = Balance.SENTRY_WARN
				Audio.play_at("sentry_warn", global_position, 0.0)
		S.WARN:
			if t <= 0.0:
				state = S.FIRE
				shots_left = Balance.SENTRY_BURST
				t = 0.0
		S.FIRE:
			if t <= 0.0:
				if shots_left > 0:
					_fire()
					shots_left -= 1
					t = Balance.SENTRY_BURST_GAP
				else:
					state = S.COOLDOWN
					t = Balance.SENTRY_COOLDOWN
		S.COOLDOWN:
			if t <= 0.0:
				if sees:
					state = S.WARN
					t = Balance.SENTRY_REWARN
					Audio.play_at("sentry_warn", global_position, -4.0)
				elif lost_t > Balance.SENTRY_FORGET:
					state = S.DORMANT
	_visual()


func _fire() -> void:
	var b := Bolt.new()
	b.mine = mine
	b.vel = aim * Balance.SENTRY_BOLT_SPEED
	mine.entity_root.add_child(b)
	b.global_position = _eye_pos() + aim * 12.0
	Audio.play_at("sentry_shot", global_position, -2.0)
	mine.fx.sparks(b.global_position, aim, Color(1.0, 0.3, 0.4))


func _visual() -> void:
	var frame := 1
	var col := Color(0.3, 0.9, 1.0, 0.5)
	var tt := Time.get_ticks_msec() / 1000.0
	match state:
		S.WARN:
			frame = 2
			col = Color(1.0, 0.75, 0.2, 0.6 + 0.4 * sin(tt * 25.0))
		S.FIRE:
			frame = 3
			col = Color(1.0, 0.2, 0.25, 0.9)
		S.COOLDOWN:
			frame = 2
			col = Color(1.0, 0.6, 0.2, 0.4)
		S.DEAD:
			frame = 4
			col = Color(0, 0, 0, 0)
	head.frame = frame
	var ang := aim.angle()
	if ceiling:
		ang = (aim * Vector2(1, -1)).angle() * -1.0
	# head faces left/right and tilts toward aim
	var left := aim.x < 0.0
	head.flip_h = left
	head.rotation = clampf(wrapf(ang - (PI if left else 0.0), -PI, PI), -0.7, 0.7) if state != S.DEAD else 0.4
	eye.global_position = _eye_pos()
	eye.modulate = col
	light.color = Color(col.r, col.g, col.b)
	light.energy = 0.0 if state == S.DEAD else 0.55
	mat.set_shader_parameter("flash", clampf(flash, 0.0, 0.6 if Settings.reduced_flashing() else 1.0))


func hit(dmg: float, _from: Vector2, knock: bool = true) -> void:
	if state == S.DEAD:
		return
	hp -= dmg
	flash = 1.0
	if knock:
		Audio.play_at("hit_metal", global_position, -4.0, 0.1, 0.1)
		mine.fx.sparks(global_position + Vector2(0, -10), Vector2.UP, Color(0.7, 0.6, 1.0))
	if state == S.DORMANT:
		state = S.WARN
		t = Balance.SENTRY_WARN
	if hp <= 0.0:
		_disable("destroyed")


func crushed() -> void:
	hit(Balance.RUBBLE_SENTRY_DAMAGE, global_position)
	mine.toast("Sentry crushed by rubble!")


func stun(_t: float) -> void:
	pass


func _disable(reason: String) -> void:
	if state == S.DEAD:
		return
	state = S.DEAD
	Audio.play_at("sentry_die", global_position)
	mine.fx.explosion(global_position + Vector2(0, -10), 30.0, Color(0.6, 0.4, 1.0))
	mine.spawn_pickup(global_position + Vector2(0, -12), 5)
	mine.spawn_pickup(global_position + Vector2(4, -12), 5)
	mine.on_enemy_killed(self)
	if reason == "power cut":
		mine.toast("Sentry offline: power module destroyed")
	_visual()


## Exposed power conduit that keeps a sentry alive.
class PowerModule extends Node2D:
	var mine: Node
	var sentry: Node2D
	var hp := Balance.POWER_MODULE_HP
	var dead := false
	var spr: Sprite2D
	var glow: Sprite2D
	var flash := 0.0

	func _ready() -> void:
		spr = Sprite2D.new()
		spr.texture = load("res://assets/gen/sentry.png")
		spr.hframes = 7
		spr.frame = 5
		add_child(spr)
		glow = Sprite2D.new()
		glow.texture = load("res://assets/gen/glow.png")
		glow.scale = Vector2(0.4, 0.4)
		mine.glow_root.add_child(glow)

	func _exit_tree() -> void:
		if is_instance_valid(glow):
			glow.queue_free()

	func hit_rect() -> Rect2:
		return Rect2(global_position - Vector2(6, 10), Vector2(12, 20))

	func _process(d: float) -> void:
		flash = maxf(0.0, flash - d * 4.0)
		var tt := Time.get_ticks_msec() / 1000.0
		glow.global_position = global_position
		glow.modulate = Color(0.3, 0.9, 1.0, 0.0 if dead else 0.45 + 0.2 * sin(tt * 4.0))
		spr.modulate = Color(1, 1, 1).lerp(Color(2, 2, 2), flash)
		queue_redraw()

	func _draw() -> void:
		if sentry and is_instance_valid(sentry):
			var to := sentry.global_position - global_position + Vector2(0, -6)
			var mid := to * 0.5 + Vector2(0, 10)
			var col := Color(0.15, 0.12, 0.2) if dead else Color(0.25, 0.75, 0.9, 0.8)
			draw_polyline([Vector2(0, 8), mid, to], col, 1.0)

	func hit(dmg: float, _from: Vector2, _knock: bool = true) -> void:
		if dead:
			return
		hp -= dmg
		flash = 1.0
		Audio.play_at("hit_metal", global_position, -6.0, 0.15, 0.1)
		if hp <= 0.0:
			dead = true
			spr.frame = 6
			mine.fx.explosion(global_position, 22.0, Color(0.3, 0.9, 1.0))
			Audio.play_at("explode", global_position, -10.0)

	func crushed() -> void:
		hit(99.0, global_position)

	func stun(_t: float) -> void:
		pass


## Slow, glowing energy bolt. Stops on terrain and chips loose/soft cells.
class Bolt extends Node2D:
	var mine: Node
	var vel := Vector2.ZERO
	var life := 3.5
	var spr: Sprite2D

	func _ready() -> void:
		spr = Sprite2D.new()
		spr.texture = load("res://assets/gen/bolt.png")
		mine.glow_root.add_child(spr)
		var g := Sprite2D.new()
		g.texture = load("res://assets/gen/glow.png")
		g.scale = Vector2(0.3, 0.3)
		g.modulate = Color(1.0, 0.25, 0.35, 0.7)
		spr.add_child(g)

	func _exit_tree() -> void:
		if is_instance_valid(spr):
			spr.queue_free()

	func _physics_process(delta: float) -> void:
		life -= delta
		global_position += vel * delta
		spr.global_position = global_position
		spr.rotation = vel.angle()
		var pl: Player = mine.player
		if pl and not pl.dead and Rect2(pl.global_position - Player.HALF, Player.HALF * 2.0).has_point(global_position):
			pl.take_damage(Balance.SENTRY_BOLT_DAMAGE, global_position - vel, "ruin sentry")
			_pop()
			return
		var c: Vector2i = mine.grid.world_to_cell(global_position)
		if mine.grid.is_solid(c.x, c.y):
			var m: int = mine.grid.get_mat(c.x, c.y)
			if m == Cell.SOFT or m == Cell.LOOSE:
				mine.damage_cell(c, 0.5, 0, false, "bolt")
			_pop()
			return
		if life <= 0.0:
			_pop()

	func _pop() -> void:
		mine.fx.sparks(global_position, -vel, Color(1.0, 0.3, 0.4))
		queue_free()
