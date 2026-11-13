class_name Entities
extends RefCounted
## Small world entities. Each is a Node2D that talks to the Mine through a
## `mine` reference; none of them stores terrain state of its own.


## Ore / scrap pickup. Falls onto terrain, is magnetised toward the player.
class Pickup extends Node2D:
	var mine: Node
	var ore := 1
	var vel := Vector2.ZERO
	var resting := false
	var age := 0.0
	var glow: Sprite2D
	var spr: Sprite2D

	func _ready() -> void:
		spr = Sprite2D.new()
		spr.texture = load("res://assets/gen/pickups.png")
		spr.hframes = 5
		spr.frame = clampi(Balance.ore_base(ore) - 1, 0, 4)
		add_child(spr)
		glow = Sprite2D.new()
		glow.texture = load("res://assets/gen/glow.png")
		glow.scale = Vector2(0.45, 0.45)
		var c := Balance.ore_color(ore)
		c.a = 0.55
		glow.modulate = c
		mine.glow_root.add_child(glow)
		var s2 := Sprite2D.new()   # emissive copy so the pickup reads in darkness
		s2.texture = spr.texture
		s2.hframes = 5
		s2.frame = spr.frame
		s2.modulate = Color(1, 1, 1, 0.55)
		glow.add_child(s2)
		s2.scale = Vector2(1.0 / 0.45, 1.0 / 0.45)

	func _exit_tree() -> void:
		if is_instance_valid(glow):
			glow.queue_free()

	func _physics_process(delta: float) -> void:
		age += delta
		var pl: Player = mine.player
		var to := pl.global_position - global_position if pl else Vector2.INF
		var room: bool = Game.can_take(ore, mine.cargo_cap())
		var reach := Balance.PICKUP_MAGNET_RADIUS * (Balance.MAGNET_MULT if mine.has_passive("magnet") else 1.0)
		if pl and not pl.dead and age > 0.35 and room and to.length() < reach:
			vel = vel.lerp(to.normalized() * 260.0, 10.0 * delta)
			global_position += vel * delta
			resting = false
			if to.length() < 9.0:
				mine.collect(self)
				return
		elif not resting:
			vel.y = minf(vel.y + 600.0 * delta, 300.0)
			vel.x = move_toward(vel.x, 0.0, 120.0 * delta)
			var np := global_position + vel * delta
			if mine.grid.solid_at(np + Vector2(0, 4)):
				vel = Vector2(vel.x * 0.4, -vel.y * 0.3)
				if absf(vel.y) < 30.0:
					resting = true
					vel = Vector2.ZERO
			elif mine.grid.solid_at(np + Vector2(signf(vel.x) * 4, 0)):
				vel.x = -vel.x * 0.5
			else:
				global_position = np
		else:
			if not mine.grid.solid_at(global_position + Vector2(0, 6)):
				resting = false
		spr.position.y = sin(age * 4.0) * 1.0 if resting else 0.0
		glow.global_position = global_position + spr.position


## Lift cage: extraction point. The relay lift starts dormant until reached.
class Lift extends Node2D:
	var mine: Node
	var id := "surface"
	var active := true
	var cell := Vector2i.ZERO
	var light: PointLight2D
	var cage: Sprite2D
	var beacon: Sprite2D

	func _ready() -> void:
		active = id == "surface"
		cage = Sprite2D.new()
		cage.texture = SpriteDB.prop_texture("lift")
		cage.offset = Vector2(0, -20)
		add_child(cage)
		var cable := Line2D.new()
		cable.add_point(Vector2(-6, -40))
		cable.add_point(Vector2(-6, -400))
		cable.add_point(Vector2(6, -400))
		cable.add_point(Vector2(6, -40))
		cable.width = 1.0
		cable.default_color = Color(0.2, 0.2, 0.24)
		cable.z_index = -1
		add_child(cable)
		light = PointLight2D.new()
		light.texture = load("res://assets/gen/light.png")
		light.texture_scale = 0.9
		light.color = Color(1.0, 0.75, 0.4)
		light.energy = 1.0 if active else 0.25
		light.position = Vector2(0, -34)
		add_child(light)
		beacon = Sprite2D.new()
		beacon.texture = load("res://assets/gen/glow.png")
		beacon.scale = Vector2(0.6, 0.6)
		mine.glow_root.add_child(beacon)
		beacon.global_position = global_position + Vector2(0, -36)

	func _process(_d: float) -> void:
		var t := Time.get_ticks_msec() / 1000.0
		var c := Color(0.4, 1.0, 0.5, 0.5 + 0.3 * sin(t * 3.0)) if active else Color(1.0, 0.4, 0.2, 0.25 + 0.2 * sin(t * 6.0))
		beacon.modulate = c
		light.energy = (1.0 if active else 0.3) + 0.08 * sin(t * 7.0)

	func activate() -> void:
		if active:
			return
		active = true
		Audio.play("lift_ding")
		mine.toast("RELAY LIFT ONLINE - extraction available here")


## The relic: the contract objective.
class Relic extends Node2D:
	var mine: Node
	var taken := false
	var spr: Sprite2D
	var glow: Sprite2D
	var light: PointLight2D
	var t := 0.0

	func _ready() -> void:
		var ped := Sprite2D.new()
		ped.texture = SpriteDB.prop_texture("pedestal")
		ped.offset = Vector2(0, 0)
		add_child(ped)
		spr = Sprite2D.new()
		spr.texture = load("res://assets/gen/relic.png")
		spr.hframes = 4
		spr.position = Vector2(0, -16)
		add_child(spr)
		glow = Sprite2D.new()
		glow.texture = load("res://assets/gen/glow.png")
		glow.modulate = Color(0.4, 1.0, 1.0, 0.6)
		mine.glow_root.add_child(glow)
		light = PointLight2D.new()
		light.texture = load("res://assets/gen/light.png")
		light.color = Color(0.4, 0.95, 1.0)
		light.energy = 1.1
		light.texture_scale = 0.8
		light.position = Vector2(0, -16)
		add_child(light)

	func _process(d: float) -> void:
		t += d
		if taken:
			return
		spr.frame = int(t * 6.0) % 4
		glow.global_position = global_position + Vector2(0, -16)
		glow.scale = Vector2.ONE * (0.8 + 0.1 * sin(t * 3.0))

	func take() -> void:
		taken = true
		spr.visible = false
		glow.visible = false
		light.energy = 0.3


## Sealed alloy door of the relic chamber; opens when the player approaches.
class Door extends Node2D:
	var mine: Node
	var cells: Array = []
	var opened := false
	var spr: Sprite2D
	var frame_t := 0.0

	func _ready() -> void:
		spr = Sprite2D.new()
		spr.texture = SpriteDB.prop_texture("door0")
		spr.centered = false
		spr.position = Vector2(-8, 0)
		add_child(spr)
		spr.scale = Vector2(0.5, 1.0)

	func _process(d: float) -> void:
		if opened:
			if frame_t < 3.0:
				frame_t = minf(3.0, frame_t + d * 6.0)
				spr.texture = SpriteDB.prop_texture("door%d" % int(frame_t))
			return
		var pl: Player = mine.player
		if pl == null:
			return
		var c: Vector2i = cells[cells.size() - 1]
		var pc: Vector2i = mine.grid.world_to_cell(pl.global_position)
		if absi(pc.x - c.x) <= 4 and absi(pc.y - c.y) <= 3:
			open()

	func open() -> void:
		opened = true
		for c in cells:
			mine.grid.set_flag(c.x, c.y, Cell.F_PROTECTED, false)
			mine.grid.set_mat(c.x, c.y, Cell.AIR, false)
		Audio.play_at("hit_metal", global_position, 2.0)
		Audio.play("alarm", -8.0)
		mine.toast("RUIN VAULT UNSEALED")
		mine.shake(0.25)


## Supply cache: charges and/or hull repair, once.
class Cache extends Node2D:
	var mine: Node
	var charges := 1
	var repair := 0.0
	var used := false
	var spr: Sprite2D

	func _ready() -> void:
		spr = Sprite2D.new()
		spr.texture = SpriteDB.prop_texture("cache")
		spr.offset = Vector2(0, 1)
		add_child(spr)

	func use(pl: Player) -> void:
		if used:
			return
		used = true
		Game.run["charges"] = mini(Balance.CHARGES_MAX + 2, int(Game.run.get("charges", 0)) + charges)
		if repair > 0.0:
			pl.heal(repair)
		spr.modulate = Color(0.5, 0.5, 0.5)
		Audio.play("ui_buy")
		var parts: Array = []
		if charges > 0:
			parts.append("+%d CHARGE%s" % [charges, "S" if charges > 1 else ""])
		if repair > 0:
			parts.append("+%d HULL" % int(repair))
		mine.toast("SUPPLY CACHE: " + " ".join(parts))


## Warm work lamp with a real light (used sparingly).
class Lamp extends Node2D:
	var color := Color(1.0, 0.72, 0.38)
	var hanging := true
	var t := randf() * 10.0
	var light: PointLight2D
	var glow: Sprite2D
	var mine: Node

	func _ready() -> void:
		var s := Sprite2D.new()
		s.texture = SpriteDB.prop_texture("lantern")
		s.offset = Vector2(0, 0)
		add_child(s)
		light = PointLight2D.new()
		light.texture = load("res://assets/gen/light.png")
		light.color = color
		light.texture_scale = 0.75
		light.energy = 0.95
		light.position = Vector2(0, 3)
		add_child(light)
		glow = Sprite2D.new()
		glow.texture = load("res://assets/gen/glow.png")
		glow.scale = Vector2(0.4, 0.4)
		glow.modulate = Color(color.r, color.g, color.b, 0.55)
		mine.glow_root.add_child(glow)
		glow.global_position = global_position + Vector2(0, 3)

	func _process(d: float) -> void:
		t += d
		light.energy = 0.9 + 0.06 * sin(t * 9.0) + 0.04 * sin(t * 23.0)


## Static decorative sprite (signs, beams, skull, crates).
class Prop extends Node2D:
	var prop := "crate"
	var text := ""

	func _ready() -> void:
		var s := Sprite2D.new()
		s.texture = SpriteDB.prop_texture(prop)
		s.centered = false
		var r: Array = SpriteDB.props().get(prop, [0, 0, 16, 16])
		s.position = Vector2(-r[2] * 0.5, -r[3] + 8)
		add_child(s)
		if text != "":
			var l := Label.new()
			l.text = text
			l.add_theme_font_size_override("font_size", 8)
			l.add_theme_color_override("font_color", Color(0.95, 0.8, 0.5))
			l.position = Vector2(-20, -r[3] - 4)
			l.size = Vector2(40, 10)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			add_child(l)


## Ancient Descent Platform: the sealed elevator of an older civilization, found
## in a side chamber of the Forgotten Engine. Using it is a deliberate, confirmed,
## one-way trip into The First Civilization. Drawn in code (no sprite needed).
class AncientDescent extends Node2D:
	var mine: Node
	var light: PointLight2D
	var t := 0.0

	func _ready() -> void:
		light = PointLight2D.new()
		light.texture = load("res://assets/gen/light.png")
		light.texture_scale = 1.0
		light.color = Color(1.0, 0.62, 0.3)
		light.energy = 0.9
		light.position = Vector2(0, -22)
		add_child(light)

	func _process(d: float) -> void:
		t += d
		light.energy = 0.8 + 0.25 * sin(t * 2.2)
		queue_redraw()

	func _draw() -> void:
		var bronze := Color("51422a")
		var edge := Color("b59a5e")
		var dark := Color("14100a")
		# platform deck with a stepped rim
		draw_rect(Rect2(-22, -4, 44, 4), bronze)
		draw_rect(Rect2(-22, -4, 44, 1), edge)
		draw_rect(Rect2(-18, -6, 36, 2), dark)
		# two pylons and a lintel carrying the glyph
		for sx in [-20.0, 16.0]:
			draw_rect(Rect2(sx, -40, 4, 36), bronze)
			draw_rect(Rect2(sx, -40, 1, 36), edge)
		draw_rect(Rect2(-22, -44, 44, 5), bronze)
		draw_rect(Rect2(-22, -44, 44, 1), edge)
		var pulse := 0.55 + 0.45 * sin(t * 2.2)
		var glow := Color(1.0, 0.55, 0.22, pulse)
		draw_rect(Rect2(-5, -43, 10, 3), glow)
		draw_rect(Rect2(-2, -42, 4, 1), Color(1, 0.9, 0.7, pulse))
		# a shaft of heat haze dropping away under the deck
		for k in 4:
			var yy := -34.0 + k * 8.0 + fmod(t * 14.0, 8.0)
			draw_rect(Rect2(-14, yy, 28, 1), Color(1.0, 0.5, 0.2, 0.18 * pulse))


## Transit Gate: the only way out of The First Civilization. It must be powered
## (the geothermal network decides that) and then woken by the player.
class TransitGate extends Node2D:
	var mine: Node
	var powered := true            # set by the stage's power network when one exists
	var woken := false
	var online: bool:
		get:
			return powered and woken
	var light: PointLight2D
	var t := 0.0
	var _spin := 0.0

	func _ready() -> void:
		light = PointLight2D.new()
		light.texture = load("res://assets/gen/light.png")
		light.texture_scale = 1.3
		light.color = Color(0.4, 1.0, 0.95)
		light.energy = 0.3
		light.position = Vector2(0, -26)
		add_child(light)

	func status_text() -> String:
		if not powered:
			var engine: Node = mine.get("engine")
			if engine:
				return "TRANSIT GATE: NO POWER - %s" % engine.status()
			return "TRANSIT GATE: NO POWER"
		return "TRANSIT GATE: DORMANT"

	## First use: bring the array up. Returns true if the gate is now online.
	func wake() -> bool:
		if not powered or woken:
			return online
		woken = true
		Audio.play("lift_ding")
		Audio.play("relic", -8.0)
		mine.toast("TRANSIT ARRAY ONLINE - step in to leave")
		mine.shake(0.3)
		return true

	func _process(d: float) -> void:
		t += d
		_spin += d * (2.4 if online else (0.5 if powered else 0.1))
		light.energy = (1.2 if online else (0.5 if powered else 0.15)) + 0.1 * sin(t * 5.0)
		queue_redraw()

	func _draw() -> void:
		var bronze := Color("51422a")
		var edge := Color("b59a5e")
		var col := Color(0.4, 1.0, 0.95) if online else (Color(1.0, 0.7, 0.3) if powered else Color(0.5, 0.2, 0.15))
		# plinth
		draw_rect(Rect2(-26, -4, 52, 4), bronze)
		draw_rect(Rect2(-26, -4, 52, 1), edge)
		# the ring: two concentric arcs with rotating gaps
		var c := Vector2(0, -28)
		draw_arc(c, 24.0, 0.0, TAU, 40, bronze, 5.0)
		draw_arc(c, 24.0, 0.0, TAU, 40, edge, 1.0)
		for k in 3:
			var a := _spin + k * TAU / 3.0
			draw_arc(c, 19.0, a, a + 1.3, 12, Color(col, 0.9), 2.0)
			draw_arc(c, 14.0, -a * 1.4, -a * 1.4 + 0.9, 10, Color(col, 0.6), 1.5)
		if online:
			draw_circle(c, 12.0 + sin(t * 4.0), Color(col, 0.22))
			draw_circle(c, 6.0, Color(1, 1, 1, 0.35))
		# status pips on the plinth
		for k in 3:
			var on := (k == 0 and powered) or (k == 1 and woken) or (k == 2 and online)
			draw_rect(Rect2(-8 + k * 6, -3, 4, 2), col if on else Color(0.12, 0.1, 0.1))


## A valve console in the Thermal Plant. USE opens (or closes) the floor of its
## tank so the fluid pours into the basin below. Closing is always possible,
## so an early mistake can be undone.
class Valve extends Node2D:
	var mine: Node
	var system := "heat"            # "heat" (lava) or "coolant" (water)
	var outlet: Array = []          # tank-floor cells this valve opens
	var open := false
	var t := 0.0

	func label() -> String:
		var what := "HEAT VALVE" if system == "heat" else "COOLANT VALVE"
		return ("CLOSE " if open else "OPEN ") + what

	func toggle() -> void:
		open = not open
		var g: TerrainGrid = mine.grid
		for c in outlet:
			g.set_flag(c.x, c.y, Cell.F_PROTECTED, false)
			if open:
				g.set_mat(c.x, c.y, Cell.AIR, false)
			else:
				g.set_mat(c.x, c.y, Cell.ALLOY)
				g.set_flag(c.x, c.y, Cell.F_PROTECTED)
		Audio.play("lift_ding" if open else "ui_click", -4.0)
		Audio.play_at("rumble", global_position, -10.0)
		mine.shake(0.15)
		if system == "heat":
			mine.toast("HEAT VALVE OPEN - molten feed to the intake" if open else "HEAT VALVE CLOSED")
		else:
			mine.toast("COOLANT VALVE OPEN - water to the condenser" if open else "COOLANT VALVE CLOSED")

	func _process(d: float) -> void:
		t += d
		queue_redraw()

	func _draw() -> void:
		var bronze := Color("51422a")
		var edge := Color("b59a5e")
		var col := Color(1.0, 0.55, 0.2) if system == "heat" else Color(0.35, 0.85, 1.0)
		draw_rect(Rect2(-5, -18, 10, 18), bronze)
		draw_rect(Rect2(-5, -18, 10, 1), edge)
		# the wheel turns while the valve is open
		var c := Vector2(0, -12)
		draw_arc(c, 4.0, 0, TAU, 12, edge, 1.5)
		var a := t * 3.0 if open else 0.0
		for k in 3:
			var dir := Vector2.RIGHT.rotated(a + k * TAU / 3.0)
			draw_line(c, c + dir * 4.0, edge, 1.0)
		draw_rect(Rect2(-3, -4, 6, 2), col if open else Color(0.18, 0.14, 0.12))


## The Thermal Engine. It watches its two basins: enough lava in the heat
## intake and enough water in the coolant basin, held for a moment, and it
## powers the Transit Gate. Its state is shown on its face and announced.
class ThermalEngine extends Node2D:
	var mine: Node
	var heat_cells: Array = []
	var cool_cells: Array = []
	var heat := 0
	var coolant := 0
	var online := false
	var _check := 0.0
	var _hold := 0.0
	var _heat_ok := false
	var _cool_ok := false
	var t := 0.0
	var light: PointLight2D

	func _ready() -> void:
		light = PointLight2D.new()
		light.texture = load("res://assets/gen/light.png")
		light.texture_scale = 1.4
		light.color = Color(1.0, 0.55, 0.25)
		light.energy = 0.2
		light.position = Vector2(0, -16)
		add_child(light)

	func heat_ready() -> bool:
		return heat >= Balance.PLANT_HEAT_NEED

	func cool_ready() -> bool:
		return coolant >= Balance.PLANT_COOL_NEED

	func status() -> String:
		var h := "HEAT INPUT: READY" if heat_ready() else ("HEAT INPUT: LOW" if heat > 0 else "HEAT INPUT: NONE")
		var c := "COOLANT: READY" if cool_ready() else "COOLANT: INSUFFICIENT"
		return "%s   %s" % [h, c]

	func measure() -> void:
		var g: TerrainGrid = mine.grid
		heat = 0
		for c in heat_cells:
			heat += g.get_lava(c.x, c.y)
		coolant = 0
		for c in cool_cells:
			coolant += g.get_water(c.x, c.y)

	func _process(d: float) -> void:
		t += d
		_check -= d
		if _check <= 0.0:
			_check = Balance.PLANT_CHECK
			measure()
			var h := heat_ready()
			var c := cool_ready()
			if h != _heat_ok:
				_heat_ok = h
				mine.toast("HEAT INPUT: READY" if h else "HEAT INPUT: LOST")
			if c != _cool_ok:
				_cool_ok = c
				mine.toast("COOLANT: READY" if c else "COOLANT: INSUFFICIENT")
			if h and c:
				_hold += Balance.PLANT_CHECK
			else:
				_hold = 0.0
			var want := h and c and _hold >= Balance.PLANT_SPINUP
			if want != online:
				online = want
				if online:
					Audio.play("lift_ding")
					Audio.play_at("rumble", global_position, -4.0)
					mine.shake(0.4)
					mine.toast("THERMAL ENGINE ONLINE - the Transit Gate has power")
					if mine.hud:
						mine.hud.banner("POWER RESTORED")
				else:
					mine.toast("THERMAL ENGINE STALLED - %s" % status())
			if mine.gate:
				mine.gate.powered = online
		light.energy = (1.3 if online else (0.6 if (_heat_ok or _cool_ok) else 0.2)) + 0.1 * sin(t * 6.0)
		queue_redraw()

	func _draw() -> void:
		var bronze := Color("51422a")
		var edge := Color("b59a5e")
		# a stacked core with a turning rotor and three status lamps
		draw_rect(Rect2(-22, -26, 44, 26), bronze)
		draw_rect(Rect2(-22, -26, 44, 2), edge)
		var c := Vector2(0, -14)
		var spin := t * (6.0 if online else 0.4)
		draw_arc(c, 9.0, 0, TAU, 20, Color(0.1, 0.08, 0.06), 3.0)
		for k in 4:
			var dir := Vector2.RIGHT.rotated(spin + k * TAU / 4.0)
			draw_line(c, c + dir * 8.0, edge, 2.0)
		var lamps := [[_heat_ok, Color(1.0, 0.5, 0.2)], [_cool_ok, Color(0.35, 0.85, 1.0)], [online, Color(0.4, 1.0, 0.95)]]
		for k in 3:
			var on: bool = lamps[k][0]
			draw_rect(Rect2(-18 + k * 14, -5, 8, 3), lamps[k][1] if on else Color(0.15, 0.1, 0.1))
