extends Node2D
## A single mine run. Owns the grid, its view, entities, hazards, HUD and
## camera, and implements the shared rules (damage, explosions, loot).

const C := 16
const AMBIENT := [Color(0.42, 0.36, 0.33), Color(0.27, 0.35, 0.37), Color(0.27, 0.23, 0.36), Color(0.22, 0.31, 0.42), Color(0.36, 0.25, 0.4)]
const MUSIC := ["amb_dust", "amb_spore", "amb_engine", "amb_aqueduct", "amb_crystal"]

var data: Dictionary
var grid: TerrainGrid
var view: TerrainView
var player: Player
var fx: Fx
var camera: Camera2D
var modulate_node: CanvasModulate
var glow_layer: CanvasLayer
var glow_root: Node2D
var entity_root: Node2D
var gas: Hazards.GasSystem
var keepsakes: Array[ZoneKeepsake] = []
var collapse: Hazards.Collapse
var water: WaterSim
var debris: Debris
var erosion: WaterErosion
var _water_fx_t := 0.0
var _water_fx_cursor := 0
var hud: Node
var pause_menu: Node
var enemies: Array = []
var lifts: Array = []
var relic: Node2D
var caches: Array = []
var parallax: Array = []          # [stratum, layer, node]
var trauma := 0.0
var _explore_t := 0.0
var ending := false
var _alarm_t := 0.0
var current_stratum := -1
var seed_value := 0
var tutorial_step := 0
var _tut_t := 0.0
var headless_test := false


func _ready() -> void:
	seed_value = int(Game.run.get("seed", 1234))
	var gen := MineGenerator.new()
	data = gen.generate(seed_value, Game.run.get("contract", {}))
	grid = data["grid"]
	_build_world()
	_spawn_entities()
	_spawn_player()
	_spawn_water_props()
	_build_ui()
	grid.cell_changed.connect(_on_cell_changed)
	Audio.play("lift_ding")
	toast("CONTRACT: %s - recover the relic, then ride a lift out" % Game.run.get("contract", {}).get("name", "SURVEY"))


func _exit_tree() -> void:
	Audio.stop_all_loops()
	if player:
		player.stop_sounds()


func _build_world() -> void:
	modulate_node = CanvasModulate.new()
	modulate_node.color = AMBIENT[0]
	add_child(modulate_node)
	_build_parallax()
	glow_layer = CanvasLayer.new()
	glow_layer.layer = 1
	glow_layer.follow_viewport_enabled = true
	add_child(glow_layer)
	glow_root = Node2D.new()
	glow_layer.add_child(glow_root)
	view = TerrainView.new()
	add_child(view)
	view.setup(grid, glow_root)
	water = WaterSim.new(grid)
	debris = Debris.new()
	debris.mine = self
	add_child(debris)
	debris.setup(grid, water, seed_value)
	erosion = WaterErosion.new(grid, water, damage_cell)
	var water_view := WaterRenderer.new()
	add_child(water_view)
	water_view.setup(grid, water, self)
	entity_root = Node2D.new()
	add_child(entity_root)
	collapse = Hazards.Collapse.new()
	collapse.mine = self
	add_child(collapse)
	gas = Hazards.GasSystem.new()
	gas.mine = self
	add_child(gas)
	var gg := Hazards.GasGlow.new()
	gg.gas = gas
	gg.material = _additive()
	glow_root.add_child(gg)
	gas.glow_draw = gg
	fx = Fx.new()
	fx.z_index = 4
	add_child(fx)
	fx.setup(glow_root)
	# foreground cables (in front of everything, parallax > 1)
	var fore := Parallax2D.new()
	fore.scroll_scale = Vector2(1.25, 1.1)
	fore.repeat_size = Vector2(512, 256)
	fore.repeat_times = 3
	fore.z_index = 20
	var fs := Sprite2D.new()
	fs.texture = load("res://assets/gen/bg_fore.png")
	fs.centered = false
	fs.modulate = Color(1, 1, 1, 0.8)
	fore.add_child(fs)
	add_child(fore)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 9.0
	camera.limit_left = 0
	camera.limit_top = -40
	camera.limit_right = grid.w * C
	camera.limit_bottom = grid.h * C
	add_child(camera)
	_apply_zoom()
	Settings.changed.connect(_apply_zoom)


func _additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _build_parallax() -> void:
	var far: Texture2D = load("res://assets/gen/bg_far.png")
	var mid: Texture2D = load("res://assets/gen/bg_mid.png")
	for s in Balance.ZONE_COUNT:
		for layer in 2:
			var p := Parallax2D.new()
			p.scroll_scale = Vector2(0.25, 0.3) if layer == 0 else Vector2(0.5, 0.55)
			p.repeat_size = Vector2(512, 256)
			p.repeat_times = 3
			p.z_index = -50 + layer
			var sp := Sprite2D.new()
			var at := AtlasTexture.new()
			at.atlas = far if layer == 0 else mid
			at.region = Rect2(0, s * 256, 512, 256)
			sp.texture = at
			sp.centered = false
			p.add_child(sp)
			add_child(p)
			parallax.append([s, layer, p])


func _spawn_entities() -> void:
	for spec in data.get("finds", []):
		var find := ZoneKeepsake.new()
		find.mine = self
		find.id = int(spec["id"])
		find.position = grid.cell_center(spec["cell"])
		entity_root.add_child(find)
		keepsakes.append(find)
	for e in data["entities"]:
		var cell: Vector2i = e["cell"]
		var pos := Vector2(cell.x * C + 8, cell.y * C + 16)   # bottom-centre of the cell
		match e["type"]:
			"lift":
				var l := Entities.Lift.new()
				l.mine = self
				l.id = e["id"]
				l.cell = cell
				l.position = pos
				entity_root.add_child(l)
				lifts.append(l)
			"lamp":
				var lp := Entities.Lamp.new()
				lp.mine = self
				if e.has("color"):
					lp.color = Color(e["color"])
				lp.position = Vector2(cell.x * C + 8, cell.y * C + 8)
				entity_root.add_child(lp)
			"relic":
				relic = Entities.Relic.new()
				relic.mine = self
				relic.position = pos + Vector2(0, -8)
				entity_root.add_child(relic)
			"door":
				var d := Entities.Door.new()
				d.mine = self
				d.cells = e["cells"]
				d.position = Vector2(cell.x * C + 8, cell.y * C)
				entity_root.add_child(d)
			"cache":
				var c := Entities.Cache.new()
				c.mine = self
				c.charges = int(e.get("charges", 1))
				c.repair = float(e.get("repair", 0))
				c.position = pos + Vector2(0, -7)
				entity_root.add_child(c)
				caches.append(c)
			"crate", "beam", "sign", "skull":
				var pr := Entities.Prop.new()
				pr.prop = e["type"] if e["type"] != "skull" else "skull"
				pr.text = e.get("text", "")
				pr.position = pos + Vector2(0, -8)
				if e["type"] == "beam":
					pr.position = Vector2(cell.x * C + 8, cell.y * C + 8)
				entity_root.add_child(pr)
			"crawler":
				var cr := Crawler.new()
				cr.mine = self
				cr.position = grid.cell_center(cell)
				entity_root.add_child(cr)
				enemies.append(cr)
			"sentry":
				var s := Sentry.new()
				s.mine = self
				s.ceiling = e.get("ceiling", false)
				s.position = pos if not s.ceiling else Vector2(cell.x * C + 8, cell.y * C)
				entity_root.add_child(s)
				enemies.append(s)
				if e.has("module"):
					var m := Sentry.PowerModule.new()
					m.mine = self
					m.sentry = s
					var mc: Vector2i = e["module"]
					m.position = Vector2(mc.x * C + 8, mc.y * C + 10)
					entity_root.add_child(m)
					s.module = m
					enemies.append(m)


func _spawn_water_props() -> void:
	for spec in data.get("water_props", []):
		debris.spawn_prop(spec.kind, grid.cell_center(spec.cell))


func _spawn_player() -> void:
	player = Player.new()
	player.mine = self
	player.grid = grid
	player.water = water
	var sp: Vector2i = data["spawn"]
	player.position = Vector2(sp.x * C + 8, (sp.y + 1) * C - Player.HALF.y - 0.5)
	add_child(player)
	player.setup_stats()
	player.died.connect(_on_player_died)
	camera.global_position = player.global_position
	camera.reset_smoothing()


func _build_ui() -> void:
	hud = load("res://src/ui/hud.gd").new()
	hud.mine = self
	add_child(hud)
	pause_menu = load("res://src/ui/pause_menu.gd").new()
	pause_menu.mine = self
	add_child(pause_menu)


# ---------------------------------------------------------------------------
var _look := Vector2.ZERO
var _ladder_queue: Array[Vector2i] = []
var _ladder_t := 0.0


func _physics_process(delta: float) -> void:
	_grow_ladders(delta)
	if water:
		water.update(delta)
		erosion.update(delta)
		_water_feedback(delta)
		for sp in water.splashes:
			fx.splash(sp)
			if randf() < 0.2:
				Audio.play_at("step", sp, -14.0, 0.4, 0.05)


func _water_feedback(delta: float) -> void:
	_water_fx_t -= delta
	if _water_fx_t > 0.0 or player == null:
		return
	_water_fx_t = Balance.WATER_FX_TICK
	for c in erosion.wear_points:
		var pos := grid.cell_center(c)
		if pos.distance_to(player.global_position) < Balance.WATER_FX_RADIUS:
			fx.chips(pos, Vector2.DOWN, Cell.debris_color(grid.get_mat(c.x, c.y), grid.get_stratum(c.x, c.y)))
	var cells: Array = water.motion.cells.keys()
	if cells.is_empty():
		return
	var shown := 0
	_water_fx_cursor %= cells.size()
	for k in mini(cells.size(), Balance.EROSION_SCAN_BUDGET):
		var c: Vector2i = cells[(_water_fx_cursor + k) % cells.size()]
		var pos := grid.cell_center(c)
		var flow := water.sample_flow(pos)
		if flow.length() < Balance.WATER_FX_MIN_FLOW or pos.distance_to(player.global_position) > Balance.WATER_FX_RADIUS:
			continue
		# Surface flecks/spray follow real momentum, using existing pooled FX.
		fx.spray(pos, flow.normalized())
		shown += 1
		if shown >= Balance.WATER_FX_BUDGET:
			break
	_water_fx_cursor += Balance.EROSION_SCAN_BUDGET


func water_diagnostics() -> Dictionary:
	return {"active_cells": water.active.size(), "droplets": water.drop_count(), "motion_cells": water.motion.cells.size(),
		"pressure_work": water.pressure.work, "jets": water.pressure.jets, "discharge": water.pressure.discharge,
		"props": debris.props.size(), "fragments": debris.fragments.size(), "erosion_faces": erosion.exposure.size(),
		"erosion_edits": erosion.last_edits, "water_lost": water.lost}


func _process(delta: float) -> void:
	if player == null:
		return
	_camera(delta)
	_atmosphere(delta)
	_explore_t -= delta
	if _explore_t <= 0.0:
		_explore_t = 0.12
		_explore()
	Game.run["time"] = float(Game.run.get("time", 0.0)) + delta
	var depth_cells := int(player.global_position.y / C)
	Game.run["max_depth"] = maxi(int(Game.run.get("max_depth", 0)), depth_cells)
	if Game.run.get("relic", false):
		_alarm_t -= delta
		if _alarm_t <= 0.0:
			_alarm_t = 7.0
			noise(player.global_position, 20.0)
	_tutorial(delta)


func _apply_zoom() -> void:
	var z: float = Settings.get_value("camera_zoom")
	camera.zoom = Vector2(z, z)


func _camera(delta: float) -> void:
	# look ahead in the direction of travel / drilling so a close camera never
	# hides what is coming (eased, so turning around does not snap the view)
	var view := get_viewport().get_visible_rect().size / camera.zoom
	var want := Vector2(player.facing * view.x * Balance.CAMERA_LOOK_AHEAD, 0.0)
	if player.drill_dir.y != 0 and player.drilling:
		want = Vector2(0, player.drill_dir.y * view.y * 0.2)
	elif player.velocity.y > 200.0:
		want.y = view.y * 0.22
	_look = _look.lerp(want, clampf(delta * 3.5, 0.0, 1.0))
	camera.global_position = player.global_position + _look + Vector2(0, -10)
	trauma = maxf(0.0, trauma - delta * 1.6)
	var amt := trauma * trauma * 7.0 * Settings.shake_scale()
	camera.offset = Vector2(randf_range(-amt, amt), randf_range(-amt, amt))


func shake(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


func _atmosphere(delta: float) -> void:
	# the zone under the middle of the screen sets light, backdrop and music
	var mid := camera.get_screen_center_position() / C
	var y := mid.y
	var s := grid.get_stratum(clampi(int(mid.x), 0, grid.w - 1), clampi(int(y), 0, grid.h - 1))
	var target: Color = AMBIENT[s]
	if y < 12.0:
		target = target.lerp(Color(0.55, 0.48, 0.44), clampf((12.0 - y) / 8.0, 0.0, 1.0))
	modulate_node.color = modulate_node.color.lerp(target, clampf(delta * 3.0, 0.0, 1.0))
	for entry in parallax:
		var node: Parallax2D = entry[2]
		var want := 1.0 if int(entry[0]) == s else 0.0
		node.modulate.a = move_toward(node.modulate.a, want, delta * 1.5)
		node.visible = node.modulate.a > 0.01
	if s != current_stratum:
		current_stratum = s
		Audio.music(MUSIC[s])
		if hud:
			hud.banner(Balance.STRATUM_NAMES[s])


func _explore() -> void:
	var c := grid.world_to_cell(player.global_position)
	var r := 7
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				grid.explore(c.x + dx, c.y + dy)


func _tutorial(delta: float) -> void:
	if Progress.tutorial_done or hud == null:
		return
	_tut_t += delta
	var tips := [
		["Hold DRILL to bore. Aim UP/DOWN to drill vertically.", 1.0],
		["Climb ladders with UP. JUMP again in mid-air for a jet burst.", 9.0],
		["Ore glows. Break seams and collect the chunks.", 17.0],
		["CHARGE throws a demolition charge. Mind the red ring!", 26.0],
		["Breaking rock fills SCAF. LADDER raises a ladder from your feet to the ceiling.", 36.0],
		["Deeper down the ladders run out: drill your own way, cracked rock marks the route.", 48.0],
	]
	if tutorial_step < tips.size() and _tut_t > tips[tutorial_step][1]:
		hud.hint(tips[tutorial_step][0])
		tutorial_step += 1


# ---------------------------------------------------------------------------
# Shared rules
func cargo_cap() -> int:
	return Balance.cargo_capacity(Progress.level("cargo"))


func damage_cell(c: Vector2i, amount: float, tier: int, ignore_tier: bool, source: String) -> Dictionary:
	var m := grid.get_mat(c.x, c.y)
	var res := grid.damage(c.x, c.y, amount, tier, ignore_tier)
	if res["broken"]:
		debris.on_broken(c, m, source)
		var pos := grid.cell_center(c)
		var s := grid.get_stratum(c.x, c.y)
		fx.burst(pos, Cell.debris_color(m, s))
		fx.dust(pos, Cell.debris_color(m, s))
		var cls := Cell.sound_class(m)
		Audio.play_at("break_hard" if cls != "soft" else "break_soft", pos, -2.0, 0.12, 0.04)
		if source == "drill":
			shake(0.07 if cls == "soft" else 0.12)
		var o: int = res["ore"]
		if o != 0:
			var n: int = int(Balance.ORE[o]["drops"])
			for i in n:
				spawn_pickup(pos + Vector2(randf_range(-3, 3), randf_range(-3, 3)), o)
			fx.glints(pos, Balance.ore_color(o))
			fx.flash(pos, Balance.ore_color(o), 0.45, 0.25)
			Audio.play_at("ore_rare" if o == Cell.ORE_AETHER else "ore", pos, -3.0)
			Game.run["ore_mined"] = int(Game.run.get("ore_mined", 0)) + 1
		if m == Cell.GAS:
			gas.vent(c)
		if source in ["drill", "blast"]:
			add_scaffold(int(Balance.SCAFFOLD_GAIN.get(m, 0)) + (Balance.SCAFFOLD_ORE_BONUS if o != 0 else 0))
	return res


# --- Rubble Ladder ----------------------------------------------------------
func scaffold_cap() -> int:
	return Balance.scaffold_capacity(Progress.level("scaffold"))


func add_scaffold(n: int) -> void:
	if n <= 0:
		return
	var before := int(Game.run.get("scaffold", 0))
	Game.run["scaffold"] = mini(scaffold_cap(), before + n)
	if before < scaffold_cap() and int(Game.run["scaffold"]) >= scaffold_cap() and not Game.run.get("scaffold_tip", false) and hud:
		Game.run["scaffold_tip"] = true
		hud.hint("Scaffold full. LADDER raises a ladder from your feet to the ceiling.")


## Cells a ladder raised from `from` would fill: straight up to the first solid
## cell. One-way platforms and existing ladders are passed through (and are free).
func ladder_plan(from: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var y := from.y
	var steps := 0
	while y >= 2 and steps < Balance.SCAFFOLD_MAX_LEN:
		var m := grid.get_mat(from.x, y)
		if Cell.is_solid(m):
			break
		if m == Cell.AIR:
			out.append(Vector2i(from.x, y))
		y -= 1
		steps += 1
	return out


## Spend scaffold energy to materialise a ladder. Returns the number of cells
## queued (0 when there is no room or no energy; nothing is spent then).
func build_ladder(by: Player) -> int:
	var cells := ladder_plan(by.feet_cell())
	var energy := int(Game.run.get("scaffold", 0))
	var afford := (energy - Balance.SCAFFOLD_ACTIVATE_COST) / Balance.SCAFFOLD_CELL_COST if energy >= Balance.SCAFFOLD_ACTIVATE_COST else 0
	if cells.is_empty() or afford <= 0:
		if hud:
			hud.toast("NO ROOM FOR A LADDER" if cells.is_empty() else "SCAFFOLD EMPTY - BREAK ROCK TO REFILL")
			hud.pulse_scaffold()
		Audio.play("ui_deny", -6.0)
		return 0
	var n := mini(cells.size(), afford)
	Game.run["scaffold"] = energy - Balance.SCAFFOLD_ACTIVATE_COST - n * Balance.SCAFFOLD_CELL_COST
	Game.run["ladders_built"] = int(Game.run.get("ladders_built", 0)) + 1
	for i in n:
		_ladder_queue.append(cells[i])
	if n < cells.size() and hud:
		hud.toast("SCAFFOLD RAN OUT")
		hud.pulse_scaffold()
	Audio.play_at("throw", by.global_position, -4.0)
	return n


func _grow_ladders(delta: float) -> void:
	if _ladder_queue.is_empty():
		return
	_ladder_t += delta * Balance.SCAFFOLD_BUILD_RATE
	while _ladder_t >= 1.0 and not _ladder_queue.is_empty():
		_ladder_t -= 1.0
		var c: Vector2i = _ladder_queue.pop_front()
		if grid.get_mat(c.x, c.y) != Cell.AIR:
			continue   # something fell or was built there meanwhile
		grid.set_mat(c.x, c.y, Cell.LADDER)
		grid.set_flag(c.x, c.y, Cell.F_PLAYER_BUILT | Cell.F_NO_RUBBLE)
		fx.dust(grid.cell_center(c), Color(0.85, 0.72, 0.45), 3)
		if _ladder_queue.size() % 3 == 0:
			Audio.play_at("hit_soft", grid.cell_center(c), -12.0, 0.2, 0.0)
	if _ladder_queue.is_empty():
		_ladder_t = 0.0


func drill_cell(c: Vector2i, amount: float, tier: int, by: Player) -> void:
	var m := grid.get_mat(c.x, c.y)
	var res := damage_cell(c, amount, tier, false, "drill")
	var pos := grid.cell_center(c)
	var toward := (by.global_position - pos).normalized()
	var contact := pos + toward * 7.0
	var s := grid.get_stratum(c.x, c.y)
	if res["blocked"]:
		fx.sparks(contact, toward, Color(1.0, 0.85, 0.5))
		Audio.play_at("hit_metal", contact, -6.0, 0.15, 0.12)
	elif not res["broken"]:
		fx.chips(contact, toward + Vector2(randf_range(-0.4, 0.4), -0.3), Cell.debris_color(m, s))
		if Cell.sound_class(m) != "soft":
			fx.sparks(contact, toward, Color(1.0, 0.8, 0.45))
		Audio.play_at("hit_" + Cell.sound_class(m), contact, -8.0, 0.12, 0.07)
		if grid.get_ore(c.x, c.y) != 0 and randf() < 0.3:
			fx.glints(contact, Balance.ore_color(grid.get_ore(c.x, c.y)))


func drill_enemies(r: Rect2, dmg: float, by: Player) -> void:
	debris.drill_rect(r, dmg)
	for e in enemies:
		if is_instance_valid(e) and e.hit_rect().intersects(r):
			e.hit(dmg, by.global_position)


func noise(pos: Vector2, radius_cells: float) -> void:
	for e in enemies:
		if is_instance_valid(e) and e is Crawler:
			e.hear(pos, radius_cells)


func explode(pos: Vector2, radius_cells: float, tile_dmg: float, ent_dmg: float, cause: String, ignite: bool = true) -> void:
	var r := radius_cells * C
	fx.explosion(pos, r)
	Audio.play_at("explode", pos, 2.0, 0.08, 0.0)
	shake(0.6)
	var c := grid.world_to_cell(pos)
	var ri := ceili(radius_cells)
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var cc := c + Vector2i(dx, dy)
			var d := grid.cell_center(cc).distance_to(pos) / r
			if d > 1.0:
				continue
			var m := grid.get_mat(cc.x, cc.y)
			if Cell.blast_proof(m) or grid.has_flag(cc.x, cc.y, Cell.F_PROTECTED):
				continue
			damage_cell(cc, tile_dmg * lerpf(1.0, 0.45, d), 99, true, "blast")
	for e in enemies:
		if is_instance_valid(e):
			var ed: float = e.global_position.distance_to(pos)
			if ed < r + 8.0:
				e.hit(ent_dmg * lerpf(1.0, 0.5, ed / (r + 8.0)), pos)
				e.stun(1.2)
	if player and not player.dead:
		var pd := player.global_position.distance_to(pos)
		if pd < r + 6.0:
			var self_dmg := Balance.CHARGE_SELF_DAMAGE if cause == "charge" else ent_dmg * 0.55
			player.take_damage(self_dmg * lerpf(1.0, 0.4, pd / (r + 6.0)), pos, "own charge" if cause == "charge" else "gas ignition")
	debris.blast(pos, r)
	noise(pos, 16.0)
	if ignite:
		gas.ignite_near(pos, r)


func spawn_charge(pos: Vector2, v: Vector2) -> void:
	var ch := Hazards.Charge.new()
	ch.mine = self
	ch.vel = v
	ch.position = pos
	entity_root.add_child(ch)


func spawn_pickup(pos: Vector2, ore: int) -> void:
	var p := Entities.Pickup.new()
	p.mine = self
	p.ore = ore
	p.vel = Vector2(randf_range(-60, 60), randf_range(-140, -60))
	p.position = pos
	entity_root.add_child(p)


func collect(p: Node) -> void:
	var cargo: Dictionary = Game.run["cargo"]
	cargo[p.ore] = int(cargo.get(p.ore, 0)) + 1
	Audio.play("pickup", -6.0, 0.1, 0.02)
	if hud:
		hud.pulse_cargo()
	if Game.cargo_count() >= cargo_cap():
		toast("CARGO FULL - extract at a lift to bank it")
	p.queue_free()


func on_enemy_killed(e: Node) -> void:
	Game.run["kills"] = int(Game.run.get("kills", 0)) + 1
	enemies.erase(e)


func toast(text: String) -> void:
	if hud:
		hud.toast(text)


func _on_cell_changed(x: int, y: int, old_m: int, new_m: int) -> void:
	if Cell.is_solid(old_m) and not Cell.is_solid(new_m):
		collapse.on_opened(x, y)


# ---------------------------------------------------------------------------
# Interaction & run end
func nearest_interactable(pl: Player) -> Dictionary:
	var pc := pl.global_position
	for l in lifts:
		if l.global_position.distance_to(pc + Vector2(0, 13)) < 26.0:
			return {"kind": "lift", "node": l, "label": "EXTRACT" if l.active else "ACTIVATE"}
	if relic and not relic.taken and relic.global_position.distance_to(pc) < 28.0:
		return {"kind": "relic", "node": relic, "label": "TAKE RELIC"}
	for c in caches:
		if not c.used and c.global_position.distance_to(pc) < 22.0:
			return {"kind": "cache", "node": c, "label": "OPEN CACHE"}
	for find in keepsakes:
		if not find.used and find.global_position.distance_to(pc) < 22.0:
			return {"kind": "find", "node": find, "label": "TAKE"}
	return {}


func player_interact(pl: Player) -> void:
	var it := nearest_interactable(pl)
	if it.is_empty() or ending:
		return
	match it["kind"]:
		"find":
			it["node"].take()
		"lift":
			var l: Entities.Lift = it["node"]
			if not l.active:
				l.activate()
			else:
				extract(l)
		"relic":
			relic.take()
			Game.run["relic"] = true
			Audio.play("relic")
			Audio.play("alarm", -4.0)
			shake(0.4)
			toast("RELIC SECURED! The ruin is awake - get to a lift!")
			if hud:
				hud.banner("RELIC SECURED")
			_alarm_t = 2.0
			noise(pl.global_position, 30.0)
		"cache":
			it["node"].use(pl)


func extract(l: Node2D) -> void:
	if ending:
		return
	ending = true
	player.controls_enabled = false
	player.stop_sounds()
	Audio.loop("lift_hum", true, -6.0)
	toast("EXTRACTING...")
	var tw := create_tween()
	tw.tween_property(player, "global_position", l.global_position + Vector2(0, -14), 0.3)
	tw.tween_callback(func() -> void: player.set_physics_process(false))
	tw.parallel().tween_property(l, "position:y", l.position.y - 160.0, 1.6).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(player, "global_position:y", player.global_position.y - 174.0, 1.6).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		Audio.loop("lift_hum", false)
		Game.end_run(true))


func _on_player_died(cause: String) -> void:
	if ending:
		return
	ending = true
	fx.explosion(player.global_position, 30.0, Color(1.0, 0.5, 0.2))
	player.visible = false
	if hud:
		hud.banner("SUIT FAILURE")
	get_tree().create_timer(1.8).timeout.connect(func() -> void: Game.end_run(false, cause))


func abandon() -> void:
	if ending:
		return
	ending = true
	Game.end_run(false, "abandoned contract")
