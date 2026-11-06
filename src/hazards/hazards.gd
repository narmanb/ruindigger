class_name Hazards
extends RefCounted
## Demolition charges, gas vents/clouds and ceiling collapse.


## Thrown demolition charge with a visible fuse and blast-radius telegraph.
class Charge extends Node2D:
	var mine: Node
	var vel := Vector2.ZERO
	var fuse := Balance.CHARGE_FUSE
	var stuck := false
	var spr: Sprite2D
	var ring: Sprite2D
	var tick_t := 0.0

	func _ready() -> void:
		spr = Sprite2D.new()
		spr.texture = load("res://assets/gen/charge.png")
		spr.hframes = 2
		add_child(spr)
		ring = Sprite2D.new()
		ring.texture = load("res://assets/gen/ring.png")
		var r := Balance.CHARGE_RADIUS_CELLS * Balance.CELL
		ring.scale = Vector2.ONE * (r * 2.0 / 64.0)
		mine.glow_root.add_child(ring)

	func _exit_tree() -> void:
		if is_instance_valid(ring):
			ring.queue_free()

	func _physics_process(delta: float) -> void:
		fuse -= delta
		if not stuck:
			vel.y = minf(vel.y + 700.0 * delta, 380.0)
			var np := global_position + vel * delta
			var g: TerrainGrid = mine.grid
			if g.solid_at(np + Vector2(0, 4 * signf(vel.y))):
				vel.y = -vel.y * 0.3
				vel.x *= 0.6
				if absf(vel.y) < 40.0:
					vel = Vector2.ZERO
					stuck = true
			elif g.solid_at(np + Vector2(4 * signf(vel.x), 0)):
				vel.x = -vel.x * 0.35
			else:
				global_position = np
			rotation += vel.x * delta * 0.05
		else:
			if not mine.grid.solid_at(global_position + Vector2(0, 6)):
				stuck = false
		# telegraph: faster blinking + pulsing ring as the fuse burns
		var rate := 4.0 if fuse > 1.0 else 12.0
		tick_t -= delta * rate
		if tick_t <= 0.0:
			tick_t = 1.0
			Audio.play_at("fuse", global_position, -4.0, 0.0, 0.01)
		spr.frame = 1 if fmod(fuse * rate, 1.0) < 0.5 else 0
		ring.global_position = global_position
		var urgency := clampf(1.0 - fuse / Balance.CHARGE_FUSE, 0.0, 1.0)
		ring.modulate = Color(1.0, 0.5 - urgency * 0.3, 0.2, 0.25 + urgency * 0.5 * (0.6 + 0.4 * sin(fuse * 30.0)))
		if fuse <= 0.0:
			mine.explode(global_position, Balance.CHARGE_RADIUS_CELLS, Balance.CHARGE_TILE_DAMAGE, Balance.CHARGE_ENTITY_DAMAGE, "charge")
			queue_free()


## Gas: breaking a gas sac starts a telegraphed vent, then a lingering cloud.
## Any explosion touching a vent or cloud ignites it (big, readable fireball).
class GasSystem extends Node2D:
	var mine: Node
	var vents: Array = []    # {pos, t, size}
	var clouds: Array = []   # {pos, t, r}
	var _hiss_on := false
	var glow_draw: Node2D

	func vent(cell: Vector2i) -> void:
		var g: TerrainGrid = mine.grid
		# the whole connected sac cluster vents together
		var cluster: Array[Vector2i] = [cell]
		var head := 0
		while head < cluster.size() and cluster.size() < 8:
			var c: Vector2i = cluster[head]
			head += 1
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if g.get_mat(n.x, n.y) == Cell.GAS and not cluster.has(n):
					cluster.append(n)
		var centre := Vector2.ZERO
		for c in cluster:
			centre += g.cell_center(c)
			if g.get_mat(c.x, c.y) == Cell.GAS:
				g.set_mat(c.x, c.y, Cell.AIR, true)
		centre /= cluster.size()
		vents.append({"pos": centre, "t": Balance.GAS_TELEGRAPH, "size": cluster.size()})
		Audio.play_at("gas_warn", centre, 0.0)
		mine.toast("GAS POCKET RUPTURED - back off!")

	func ignite_near(pos: Vector2, radius: float) -> void:
		for v in vents.duplicate():
			if v["pos"].distance_to(pos) < radius + 20.0:
				vents.erase(v)
				_fireball(v["pos"], 1.0 + v["size"] * 0.15)
		for c in clouds.duplicate():
			if c["pos"].distance_to(pos) < radius + c["r"]:
				clouds.erase(c)
				_fireball(c["pos"], 1.0 + c["r"] / 80.0)

	func _fireball(pos: Vector2, k: float) -> void:
		Audio.play_at("ignite", pos, 3.0)
		var r := Balance.GAS_IGNITE_RADIUS * k
		mine.explode(pos, r / Balance.CELL, Balance.GAS_IGNITE_TILE_DAMAGE, Balance.GAS_IGNITE_DAMAGE, "gas", false)
		mine.fx.flash(pos, Color(1.0, 0.7, 0.2), r / 40.0, 0.7)

	func _physics_process(delta: float) -> void:
		for v in vents.duplicate():
			v["t"] -= delta
			if randf() < 0.5:
				mine.fx.gas_puff(v["pos"] + Vector2(randf_range(-6, 6), randf_range(-6, 6)))
			if v["t"] <= 0.0:
				vents.erase(v)
				clouds.append({"pos": v["pos"], "t": Balance.GAS_CLOUD_TIME, "r": Balance.GAS_CLOUD_RADIUS * (0.8 + v["size"] * 0.12)})
		var pl: Player = mine.player
		for c in clouds.duplicate():
			c["t"] -= delta
			if randf() < 0.35:
				var a := randf() * TAU
				mine.fx.gas_puff(c["pos"] + Vector2(cos(a), sin(a)) * randf() * c["r"])
			if pl and pl.global_position.distance_to(c["pos"]) < c["r"]:
				# gas bypasses invulnerability frames as a slow, steady burn
				pl.hp -= Balance.GAS_DPS * delta
				if pl.hp <= 0.0:
					pl.hp = 0.0
					pl.die("toxic gas")
			for e in mine.enemies:
				if is_instance_valid(e) and e.global_position.distance_to(c["pos"]) < c["r"]:
					e.hit(Balance.GAS_DPS * delta, c["pos"], false)
			if c["t"] <= 0.0:
				clouds.erase(c)
		var any := not vents.is_empty() or not clouds.is_empty()
		if any != _hiss_on:
			_hiss_on = any
			Audio.loop("gas_hiss", any, -10.0)
		queue_redraw()
		if glow_draw:
			glow_draw.queue_redraw()

	func _draw() -> void:
		var t := Time.get_ticks_msec() / 1000.0
		for v in vents:
			var k: float = 1.0 - v["t"] / Balance.GAS_TELEGRAPH
			var r: float = 10.0 + k * 30.0
			draw_arc(v["pos"], r, 0, TAU, 28, Color(0.9, 1.0, 0.2, 0.5 + 0.4 * sin(t * 20.0)), 1.5)
		for c in clouds:
			var fade: float = clampf(c["t"] / 1.5, 0.0, 1.0)
			for i in 3:
				var rr: float = c["r"] * (0.55 + 0.2 * i) + sin(t * 2.0 + i) * 3.0
				draw_circle(c["pos"], rr, Color(0.6, 0.85, 0.15, 0.09 * fade))
			draw_arc(c["pos"], c["r"], 0, TAU, 32, Color(0.85, 1.0, 0.3, 0.35 * fade), 1.0)


## Glow companion for gas (drawn in the additive layer so warnings read in the dark).
class GasGlow extends Node2D:
	var gas: GasSystem

	func _draw() -> void:
		var tex: Texture2D = preload("res://assets/gen/glow.png")
		var t := Time.get_ticks_msec() / 1000.0
		for v in gas.vents:
			var s := 50.0 + sin(t * 18.0) * 8.0
			draw_texture_rect(tex, Rect2(v["pos"] - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(0.9, 1.0, 0.2, 0.6))
		for c in gas.clouds:
			var s2: float = c["r"] * 2.4
			draw_texture_rect(tex, Rect2(c["pos"] - Vector2(s2, s2) * 0.5, Vector2(s2, s2)), false, Color(0.5, 0.8, 0.1, 0.22 * clampf(c["t"] / 1.5, 0.0, 1.0)))


## Ceiling instability: LOOSE cells with nothing beneath shake for a moment
## (cracks + dust + rumble), then drop as falling rubble that stuns/damages
## whatever it lands on. Bounded: max falling count and per-trigger cascade.
class Collapse extends Node2D:
	var mine: Node
	var pending: Dictionary = {}   # Vector2i -> time left
	var falling: Array = []        # {cell_x, y(px), vy}
	var cascade_budget := Balance.COLLAPSE_MAX_CASCADE
	var _budget_t := 0.0
	var tex: Texture2D
	var landed := 0
	var shattered := 0

	func _ready() -> void:
		tex = load("res://assets/gen/terrain_atlas.png")

	func on_opened(x: int, y: int) -> void:
		# a cell just became open: anything loose directly above may lose support
		var g: TerrainGrid = mine.grid
		if g.get_mat(x, y - 1) == Cell.LOOSE:
			_queue(Vector2i(x, y - 1))

	func _queue(c: Vector2i) -> void:
		if pending.has(c) or cascade_budget <= 0:
			return
		cascade_budget -= 1
		pending[c] = Balance.COLLAPSE_TELEGRAPH * randf_range(0.85, 1.25)
		if pending.size() == 1 or randf() < 0.3:
			Audio.play_at("rumble", mine.grid.cell_center(c), -2.0, 0.1, 0.4)
			mine.shake(0.12)

	func _physics_process(delta: float) -> void:
		var g: TerrainGrid = mine.grid
		_budget_t -= delta
		if _budget_t <= 0.0:
			_budget_t = 1.5
			cascade_budget = Balance.COLLAPSE_MAX_CASCADE
		for c in pending.keys():
			pending[c] -= delta
			if randf() < 0.25:
				mine.fx.dust(g.cell_center(c) + Vector2(randf_range(-6, 6), 8), Color(0.8, 0.7, 0.5))
			if pending[c] <= 0.0:
				pending.erase(c)
				if g.get_mat(c.x, c.y) == Cell.LOOSE and not g.is_solid(c.x, c.y + 1) and falling.size() < Balance.COLLAPSE_MAX_FALLING:
					var s := g.get_stratum(c.x, c.y)
					g.set_mat(c.x, c.y, Cell.AIR, false)
					falling.append({"x": c.x, "y": c.y * 16.0, "vy": 0.0, "s": s})
		for f in falling.duplicate():
			f["vy"] = minf(f["vy"] + 900.0 * delta, 420.0)
			var ny: float = f["y"] + f["vy"] * delta
			var below_cell := int(floor((ny + 16.0) / 16.0))
			var rect := Rect2(f["x"] * 16 + 1, ny, 14, 16)
			if _hit_entities(rect):
				falling.erase(f)
				_shatter(Vector2(f["x"] * 16 + 8, ny + 8), f["s"])
				continue
			if g.is_solid(f["x"], below_cell) or below_cell >= g.h - 1:
				var land_y := below_cell - 1
				falling.erase(f)
				_land(f["x"], land_y, f["s"])
				continue
			f["y"] = ny
		queue_redraw()

	func _hit_entities(rect: Rect2) -> bool:
		var pl: Player = mine.player
		if pl and not pl.dead:
			var pr := Rect2(pl.global_position - Player.HALF, Player.HALF * 2.0)
			if pr.intersects(rect):
				pl.take_damage(Balance.RUBBLE_PLAYER_DAMAGE, rect.get_center(), "falling rubble")
				pl.velocity.y = maxf(pl.velocity.y, 60.0)
				return true
		for e in mine.enemies:
			if is_instance_valid(e) and e.hit_rect().intersects(rect):
				e.crushed()
				return true
		return false

	func _land(x: int, y: int, s: int) -> void:
		var g: TerrainGrid = mine.grid
		var r := Rect2(x * 16, y * 16, 16, 16)
		var blocked := g.has_flag(x, y, Cell.F_NO_RUBBLE) or g.is_solid(x, y) or g.get_mat(x, y) != Cell.AIR
		var pl: Player = mine.player
		if pl and Rect2(pl.global_position - Player.HALF, Player.HALF * 2.0).grow(1.0).intersects(r):
			blocked = true   # never materialise a block inside the player
		for e in mine.enemies:
			if is_instance_valid(e) and e.hit_rect().intersects(r):
				blocked = true
		if blocked:
			_shatter(r.get_center(), s)
			return
		landed += 1
		g.set_mat(x, y, Cell.LOOSE, false)
		g.set_flag(x, y, Cell.F_DUG, false)
		Audio.play_at("rubble", r.get_center(), -2.0, 0.1, 0.06)
		mine.fx.dust(r.get_center() + Vector2(0, 6), Color(0.8, 0.7, 0.5))
		mine.shake(0.08)

	func _shatter(pos: Vector2, s: int) -> void:
		shattered += 1
		mine.fx.burst(pos, Cell.debris_color(Cell.LOOSE, s))
		mine.fx.dust(pos, Color(0.8, 0.7, 0.5))
		Audio.play_at("break_soft", pos, -2.0)

	func _draw() -> void:
		var g: TerrainGrid = mine.grid
		var t := Time.get_ticks_msec() / 1000.0
		for c in pending.keys():
			var p := Vector2(c.x * 16, c.y * 16)
			var off := Vector2(sin(t * 60.0 + c.x) * 1.0, 0).round()
			draw_rect(Rect2(p + off, Vector2(16, 16)), Color(1.0, 0.85, 0.5, 0.18 + 0.12 * sin(t * 30.0)))
		for f in falling:
			var s: int = f["s"]
			var bi := s * 3 + 2
			var src := Rect2((bi % 4) * 256 + (15 * 16 % 256), (bi / 4) * 256 + 15 * 16, 16, 16)
			# mask 15 (all sides exposed) row: tile index 15*16 -> (0, 240)
			src = Rect2((bi % 4) * 256, (bi / 4) * 256 + 240, 16, 16)
			draw_texture_rect_region(tex, Rect2(f["x"] * 16, f["y"], 16, 16), src)
