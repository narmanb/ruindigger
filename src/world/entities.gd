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
		spr.frame = clampi(ore - 1, 0, 4)
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
		var room: bool = Game.cargo_count() < mine.cargo_cap() or ore == 0
		if pl and not pl.dead and age > 0.35 and room and to.length() < Balance.PICKUP_MAGNET_RADIUS:
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
