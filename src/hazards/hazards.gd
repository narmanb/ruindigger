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


## Lure: a thrown beacon that pings for a while. Crawlers in range drop what
## they are doing, even a chase, and go to it. Pings are not drill noise, so a
## lure does not wake the mine (no pressure).
class Lure extends Node2D:
	var mine: Node
	var vel := Vector2.ZERO
	var stuck := false
	var life := Balance.LURE_TIME
	var ping_t := 0.2
	var pulse := 0.0
	var glow: Sprite2D

	func _ready() -> void:
		glow = Sprite2D.new()
		glow.texture = load("res://assets/gen/glow.png")
		glow.scale = Vector2(0.3, 0.3)
		glow.modulate = Color(0.4, 1.0, 0.9, 0.0)
		mine.glow_root.add_child(glow)

	func _exit_tree() -> void:
		if is_instance_valid(glow):
			glow.queue_free()

	func _physics_process(delta: float) -> void:
		var g: TerrainGrid = mine.grid
		if not stuck:
			vel.y = minf(vel.y + 700.0 * delta, 380.0)
			var np := global_position + vel * delta
			if g.solid_at(np + Vector2(0, 3 * signf(vel.y))):
				vel.y = -vel.y * 0.25
				vel.x *= 0.5
				if absf(vel.y) < 40.0:
					vel = Vector2.ZERO
					stuck = true
			elif g.solid_at(np + Vector2(3 * signf(vel.x), 0)):
				vel.x = -vel.x * 0.3
			else:
				global_position = np
		else:
			if not g.solid_at(global_position + Vector2(0, 5)):
				stuck = false
			life -= delta
			ping_t -= delta
			if ping_t <= 0.0:
				ping_t = Balance.LURE_PING
				pulse = 1.0
				Audio.play_at("fuse", global_position, -2.0, 0.3, 0.0)
				for e in mine.enemies:
					if is_instance_valid(e) and e.has_method("lure") and e.global_position.distance_to(global_position) <= Balance.LURE_RADIUS * Balance.CELL:
						e.lure(global_position)
			if life <= 0.0:
				queue_free()
				return
		pulse = maxf(0.0, pulse - delta * 2.5)
		glow.global_position = global_position
		glow.modulate.a = 0.25 + 0.6 * pulse
		glow.scale = Vector2.ONE * (0.3 + 0.5 * (1.0 - pulse) * pulse)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(-3, -2, 6, 5), Color("3d4652"))
		draw_rect(Rect2(-3, -2, 6, 1), Color("8a9aa8"))
		draw_circle(Vector2(0, -3), 1.6, Color(0.4, 1.0, 0.9, 0.4 + 0.6 * pulse))
		if pulse > 0.0:
			draw_arc(Vector2.ZERO, 6.0 + (1.0 - pulse) * 26.0, 0, TAU, 24, Color(0.4, 1.0, 0.9, pulse * 0.6), 1.0)


## Cryo canister (gadget): bursts on the first thing it touches. Lava in range
## crusts, steam clears, foes freeze, and the digger's heat is vented.
class Cryo extends Node2D:
	var mine: Node
	var vel := Vector2.ZERO
	var age := 0.0

	func _physics_process(delta: float) -> void:
		age += delta
		vel.y = minf(vel.y + 700.0 * delta, 380.0)
		var np := global_position + vel * delta
		var g: TerrainGrid = mine.grid
		var c := g.world_to_cell(np)
		var hit_enemy := false
		for e in mine.enemies:
			if is_instance_valid(e) and e.has_method("hit_rect") and e.hit_rect().has_point(np):
				hit_enemy = true
		if g.solid_at(np) or g.get_lava(c.x, c.y) > 0 or g.get_water(c.x, c.y) >= Balance.WATER_MAX / 2 or hit_enemy or age > 3.0:
			mine.cryo_burst(global_position)
			queue_free()
			return
		global_position = np
		rotation += delta * 9.0
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(-3, -4, 6, 8), Color("cfe8f2"))
		draw_rect(Rect2(-3, -4, 6, 2), Color("6fd8ff"))
		draw_circle(Vector2(0, 1), 1.5, Color(0.5, 0.95, 1.0))


## Sonar ping (gadget): an expanding ring, then marks on ore, gas and loose
## rock for a few seconds. Drawn above the rock so it reads through walls.
class SonarPing extends Node2D:
	var marks: Array = []        # [Vector2 local, Color]
	var t := 0.0

	func _ready() -> void:
		z_index = 7

	func _process(delta: float) -> void:
		t += delta
		if t >= Balance.SONAR_SHOW:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var ring := t * 420.0
		var reach := Balance.SONAR_RADIUS * Balance.CELL
		if ring < reach:
			draw_arc(Vector2.ZERO, ring, 0, TAU, 64, Color(0.45, 1.0, 0.85, 0.7 * (1.0 - ring / reach)), 2.0)
		var fade := clampf((Balance.SONAR_SHOW - t) / 1.5, 0.0, 1.0)
		for m in marks:
			var p: Vector2 = m[0]
			if p.length() > ring:
				continue
			var col: Color = m[1]
			col.a = fade * (0.75 + 0.25 * sin(t * 6.0 + p.x * 0.1))
			draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), col, false, 2.0)
			var inner := col
			inner.a *= 0.35
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), inner)


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

	## Gas seeping out of the rock at a point (pressure events): same warning
	## and cloud as a ruptured pocket, without a pocket.
	func vent_at(pos: Vector2, size: int) -> void:
		vents.append({"pos": pos, "t": Balance.GAS_TELEGRAPH * 1.4, "size": size})
		Audio.play_at("gas_warn", pos, 0.0)
		mine.toast("GAS SEEPING FROM THE ROCK - back off!")

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
					e.set("last_hit", "gas")
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
	# basalt boulders
	var _boulder_checks: Dictionary = {}   # Vector2i -> true, resolved once per frame
	var boulder_pending: Array = []        # {cells: Array[Vector2i], t}
	var boulders: Array = []               # {x0, y0, cells: [[dx,dy,ore,hp,s]], off(px), vy}
	var boulders_dropped := 0
	var boulders_landed := 0
	var _claimed: Dictionary = {}          # cells already in a pending/falling boulder

	func _ready() -> void:
		tex = load("res://assets/gen/terrain_atlas.png")

	func on_opened(x: int, y: int) -> void:
		# a cell just became open: anything loose directly above may lose support,
		# and any neighbouring basalt mass may have lost its anchor
		var g: TerrainGrid = mine.grid
		if g.get_mat(x, y - 1) == Cell.LOOSE:
			_queue(Vector2i(x, y - 1))
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
			var n := Vector2i(x + d.x, y + d.y)
			if g.get_mat(n.x, n.y) == Cell.HARD:
				_boulder_checks[n] = true

	func _resolve_boulder_checks() -> void:
		if _boulder_checks.is_empty():
			return
		var g: TerrainGrid = mine.grid
		for c in _boulder_checks.keys():
			if _claimed.has(c):
				continue
			var mass := Boulders.unsupported_mass(g, c)
			if mass.is_empty() or _lava_owned(mass):
				continue
			for m in mass:
				_claimed[m] = true
			boulder_pending.append({"cells": mass, "t": Balance.BOULDER_TELEGRAPH})
			Audio.play_at("rumble", g.cell_center(mass[0]), 0.0, 0.1, 0.2)
			mine.shake(0.15)
		_boulder_checks.clear()

	## Fresh crust on lava or water belongs to LavaSim, which sinks it itself.
	func _lava_owned(mass: Array) -> bool:
		var lv: LavaSim = mine.get("lava")
		if lv == null:
			return false
		for m in mass:
			if lv.crust.has(m):
				return true
		return false

	func _drop_boulder(cells: Array) -> void:
		var g: TerrainGrid = mine.grid
		var x0 := 1 << 20
		var y0 := 1 << 20
		for c in cells:
			x0 = mini(x0, c.x)
			y0 = mini(y0, c.y)
		var parts: Array = []
		for c in cells:
			parts.append([c.x - x0, c.y - y0, g.get_ore(c.x, c.y), g.hp[g.idx(c.x, c.y)], g.get_stratum(c.x, c.y)])
		for c in cells:
			g.set_mat(c.x, c.y, Cell.AIR, false)
			_claimed.erase(c)
		boulders.append({"x0": x0, "y0": y0, "cells": parts, "off": 0.0, "vy": 0.0})
		boulders_dropped += 1

	func _boulder_rects(b: Dictionary, dy_cells: int) -> Array[Rect2]:
		var out: Array[Rect2] = []
		for p in b["cells"]:
			out.append(Rect2((b["x0"] + p[0]) * 16, (b["y0"] + p[1] + dy_cells) * 16, 16, 16))
		return out

	func _boulder_cell_set(b: Dictionary) -> Dictionary:
		var d: Dictionary = {}
		for p in b["cells"]:
			d[Vector2i(b["x0"] + p[0], b["y0"] + p[1])] = true
		return d

	func _step_boulders(delta: float) -> void:
		var g: TerrainGrid = mine.grid
		for b in boulders.duplicate():
			b["vy"] = minf(b["vy"] + 900.0 * delta, 460.0)
			b["off"] += b["vy"] * delta
			while b["off"] >= 16.0:
				# can the whole mass move down one row?
				var own := _boulder_cell_set(b)
				var blocked := false
				for c in own.keys():
					var below := Vector2i(c.x, c.y + 1)
					if not own.has(below) and (g.is_solid(below.x, below.y) or below.y >= g.h - 1):
						blocked = true
						break
				if blocked:
					b["off"] = 0.0
					_land_boulder(b)
					boulders.erase(b)
					break
				b["y0"] += 1
				b["off"] -= 16.0
			if not boulders.has(b):
				continue
			# crush whatever is underneath the moving mass
			var hit := false
			var rects := _boulder_rects(b, 0)
			for r0 in rects:
				var r: Rect2 = r0
				r.position.y += b["off"]
				var pl: Player = mine.player
				if pl and not pl.dead and Rect2(pl.global_position - Player.HALF, Player.HALF * 2.0).intersects(r.grow(-2.0)):
					pl.take_damage(Balance.BOULDER_PLAYER_DAMAGE * (Balance.PLATING_MULT if mine.has_passive("plating") else 1.0), r.get_center(), "falling basalt")
					hit = true
				for e in mine.enemies:
					if is_instance_valid(e) and e.hit_rect().intersects(r.grow(-1.0)):
						e.set("last_hit", "rubble")
						e.hit(Balance.BOULDER_ENEMY_DAMAGE, r.get_center())
						e.stun(Balance.RUBBLE_STUN)
						hit = true
				if hit:
					break
			if hit:
				# the impact breaks the boulder apart into rubble that keeps falling
				Audio.play_at("break_hard", rects[0].get_center(), 2.0)
				mine.shake(0.5)
				for p in b["cells"]:
					falling.append({"x": b["x0"] + p[0], "y": (b["y0"] + p[1]) * 16.0 + b["off"] - 18.0, "vy": b["vy"] * 0.3, "s": p[4], "nodmg": true})
				boulders.erase(b)

	func _land_boulder(b: Dictionary) -> void:
		var g: TerrainGrid = mine.grid
		boulders_landed += 1
		var centre := Vector2.ZERO
		for p in b["cells"]:
			var x: int = b["x0"] + p[0]
			var y: int = b["y0"] + p[1]
			centre += Vector2(x * 16 + 8, y * 16 + 8)
			if g.has_flag(x, y, Cell.F_NO_RUBBLE) or g.is_solid(x, y):
				mine.fx.burst(Vector2(x * 16 + 8, y * 16 + 8), Cell.debris_color(Cell.HARD, p[4]))
				continue
			g.place(x, y, Cell.HARD, p[2], p[3])
		centre /= maxf(1.0, b["cells"].size())
		Audio.play_at("break_hard", centre, 4.0, 0.05, 0.0)
		Audio.play_at("land", centre, 2.0)
		mine.fx.dust(centre + Vector2(0, 10), Color(0.7, 0.65, 0.6))
		mine.fx.dust(centre + Vector2(12, 10), Color(0.7, 0.65, 0.6))
		mine.fx.dust(centre + Vector2(-12, 10), Color(0.7, 0.65, 0.6))
		mine.shake(0.45)
		mine.noise(centre, 12.0)

	func _queue(c: Vector2i) -> void:
		if pending.has(c) or cascade_budget <= 0:
			return
		cascade_budget -= 1
		pending[c] = Balance.COLLAPSE_TELEGRAPH * randf_range(0.85, 1.25)
		if pending.size() == 1 or randf() < 0.3:
			Audio.play_at("rumble", mine.grid.cell_center(c), -2.0, 0.1, 0.4)
			mine.shake(0.12)
		if pending.size() == 1:
			mine.toast("The ceiling is giving way!")

	var _dribble_t := 0.0

	func _dribble(g: TerrainGrid) -> void:
		## Loose rubble held up by a thin layer sheds a little dust through it,
		## so unstable ceilings read before they come down.
		var pl: Player = mine.player
		if pl == null:
			return
		var pc := g.world_to_cell(pl.global_position)
		for k in 6:
			var x := pc.x + randi_range(-14, 14)
			var y := pc.y + randi_range(-10, 4)
			if g.get_mat(x, y) == Cell.LOOSE and g.is_solid(x, y + 1) and g.get_mat(x, y + 1) != Cell.LOOSE and not g.is_solid(x, y + 2):
				mine.fx.dust(Vector2(x * 16 + randf_range(3, 13), (y + 2) * 16 + 1), Color(0.85, 0.75, 0.55))
				return

	func _physics_process(delta: float) -> void:
		var g: TerrainGrid = mine.grid
		_dribble_t -= delta
		if _dribble_t <= 0.0:
			_dribble_t = 0.35
			_dribble(g)
		_resolve_boulder_checks()
		for bp in boulder_pending.duplicate():
			bp["t"] -= delta
			if randf() < 0.4:
				var cc: Vector2i = bp["cells"][randi() % bp["cells"].size()]
				mine.fx.dust(g.cell_center(cc) + Vector2(randf_range(-6, 6), 8), Color(0.7, 0.65, 0.6))
			if bp["t"] <= 0.0:
				boulder_pending.erase(bp)
				var again := Boulders.unsupported_mass(g, bp["cells"][0])
				for c in bp["cells"]:
					_claimed.erase(c)
				if not again.is_empty():
					_drop_boulder(again)
		_step_boulders(delta)
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
			if not f.get("nodmg", false) and _hit_entities(rect):
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
				pl.take_damage(Balance.RUBBLE_PLAYER_DAMAGE * (Balance.PLATING_MULT if mine.has_passive("plating") else 1.0), rect.get_center(), "falling rubble")
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
		for bp in boulder_pending:
			for c in bp["cells"]:
				var pp := Vector2(c.x * 16, c.y * 16)
				draw_rect(Rect2(pp, Vector2(16, 16)), Color(1.0, 0.5, 0.3, 0.12 + 0.12 * sin(t * 40.0)))
		for b in boulders:
			var own := _boulder_cell_set(b)
			for p in b["cells"]:
				var x: int = b["x0"] + p[0]
				var y: int = b["y0"] + p[1]
				var mask := 0
				if not own.has(Vector2i(x, y - 1)):
					mask |= 1
				if not own.has(Vector2i(x + 1, y)):
					mask |= 2
				if not own.has(Vector2i(x, y + 1)):
					mask |= 4
				if not own.has(Vector2i(x - 1, y)):
					mask |= 8
				var src: Rect2 = mine.view.tile_rect(Cell.HARD, p[4], mask, x, y)
				draw_texture_rect_region(tex, Rect2(x * 16, y * 16 + b["off"], 16, 16), src)
				if p[2] != 0:
					draw_texture_rect_region(mine.view.tex_ore, Rect2(x * 16, y * 16 + b["off"], 16, 16), Rect2(0, TerrainView.ORE_ROW.get(p[2], 0) * 16, 16, 16))
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
