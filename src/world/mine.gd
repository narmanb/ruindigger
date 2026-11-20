extends Node2D
## A single mine run. Owns the grid, its view, entities, hazards, HUD and
## camera, and implements the shared rules (damage, explosions, loot).

const C := 16
const AMBIENT := [Color(0.42, 0.36, 0.33), Color(0.27, 0.35, 0.37), Color(0.27, 0.23, 0.36), Color(0.22, 0.31, 0.42), Color(0.36, 0.25, 0.4), Color(0.35, 0.31, 0.31)]
const MUSIC := ["amb_dust", "amb_spore", "amb_engine", "amb_aqueduct", "amb_crystal", "amb_first"]

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
var run_relics: Array[RunRelic] = []
var collapse: Hazards.Collapse
var water: WaterSim
var lava: LavaSim                 # deep stage only (null where there is no lava)
var steam: SteamField
var _burn_t := 0.0
var _scald_t := 0.0
var _heat_warn_t := 0.0
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
var _hint_t := 0.0               # s into this dive (timed hints)
var _hint_scan_t := 0.0
var _hurt_ago := 99.0             # s since the digger was last hurt
var headless_test := false
var stage := "mine"               # which generated stage this scene is running
var depth_offset := 0             # cells descended before this stage (for depth read-outs)
var descent: Node2D               # Ancient Descent Platform (main mine only)
var gate: Node2D                  # Transit Gate (deep stage only)
var descent_prompt: Node
var engine: Node2D                # Thermal Engine (deep stage only)
var valves: Array = []


func _ready() -> void:
	seed_value = int(Game.run.get("seed", 1234))
	stage = String(Game.run.get("stage", "mine"))
	depth_offset = int(Game.run.get("depth_offset", 0))
	data = generate_stage(stage, seed_value, Game.run.get("contract", {}))
	grid = data["grid"]
	_build_world()
	_spawn_entities()
	if gate and engine:
		gate.powered = false      # the Thermal Engine decides
	_spawn_player()
	_spawn_roamers()
	_spawn_water_props()
	_build_ui()
	compass = OreCompass.new()
	compass.mine = self
	glow_root.add_child(compass)
	grid.cell_changed.connect(_on_cell_changed)
	Perf.begin(self)
	pressure = Pressure.new()
	pressure.mine = self
	add_child(pressure)
	if not Game.run.has("orders"):
		Game.run["orders"] = Orders.generate(data, grid, seed_value)
	if stage == "deep":
		Audio.play("rumble")
		toast("THE FIRST CIVILIZATION - no way back. Find the Transit Gate.")
		shake(0.5)
	elif stage == "mission":
		var mi := Balance.mission(String(Game.run.get("mission", "")))
		Audio.play("lift_ding")
		toast("MISSION: %s - %s" % [mi.get("name", ""), mi.get("goal", "")])
	else:
		Audio.play("lift_ding")
		toast("CONTRACT: %s - recover the relic, then ride a lift out" % Game.run.get("contract", {}).get("name", "SURVEY"))


## Stage factory: every stage returns the same data contract (grid, spawn,
## entities, zones, ...), so the rest of this scene is stage-agnostic.
static func generate_stage(stage_name: String, seed_in: int, contract: Dictionary) -> Dictionary:
	if stage_name == "deep":
		return FirstCivGenerator.new().generate(FirstCivGenerator.deep_seed(seed_in), contract)
	if stage_name == "mission":
		# a mission's map is built from its own fixed seed
		return LakeGenerator.new().generate(Balance.mission(String(Game.run.get("mission", ""))))
	return MineGenerator.new().generate(seed_in, contract)


func _exit_tree() -> void:
	Perf.finish()
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
	sand = SandSim.new(grid, water)
	sand.occupied = _cell_occupied
	sand_drops = SandDrops.new()
	sand_drops.sim = sand
	sand_drops.grid = grid
	add_child(sand_drops)
	if stage == "deep":
		steam = SteamField.new(grid)
		lava = LavaSim.new(grid, water, steam)
		for c in data.get("lava_keep_out", []):
			lava.keep_out[c] = true
		lava.occupied = _cell_occupied
		lava.wake_all()
		var lava_view := LavaRenderer.new()
		add_child(lava_view)
		lava_view.setup(grid, lava, steam, glow_root)
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
	for s in Balance.BIOME_COUNT:
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
	for spec in data.get("run_relics", []):
		# generation cannot see what the run already holds (the deep stage is built
		# from its own seed), so a relic you own is swapped for one you do not
		var rid := Game.unowned_relic_id(int(spec["id"]), stage == "deep")
		if rid < 0:
			continue
		var rr := RunRelic.new()
		rr.mine = self
		rr.id = rid
		rr.group = int(spec.get("group", 0))
		rr.position = grid.cell_center(spec["cell"])
		entity_root.add_child(rr)
		run_relics.append(rr)
	for e in data["entities"]:
		var cell: Vector2i = e["cell"]
		var pos := Vector2(cell.x * C + 8, cell.y * C + 16)   # bottom-centre of the cell
		match e["type"]:
			"lift":
				var l := Entities.Lift.new()
				l.mine = self
				l.id = e["id"]
				l.locked = bool(e.get("locked", false))
				l.cell = cell
				l.position = pos
				entity_root.add_child(l)
				lifts.append(l)
			"kin":
				spawn_kin(String(e["kind"]), cell)
			"greenery":
				var gr := Entities.Greenery.new()
				gr.mine = self
				gr.cells = e.get("cells", [cell])
				gr.seed_v = int(e.get("seed", 1))
				gr.position = grid.cell_center(cell)
				entity_root.add_child(gr)
			"ancient_descent":
				descent = Entities.AncientDescent.new()
				descent.mine = self
				descent.position = pos
				entity_root.add_child(descent)
			"thermal_engine":
				engine = Entities.ThermalEngine.new()
				engine.mine = self
				engine.position = pos
				var plant: Dictionary = data.get("plant", {})
				engine.heat_cells = plant.get("heat_basin", [])
				engine.cool_cells = plant.get("coolant_basin", [])
				entity_root.add_child(engine)
			"valve":
				var v := Entities.Valve.new()
				v.mine = self
				v.system = e["system"]
				v.outlet = e["outlet"]
				v.position = pos
				entity_root.add_child(v)
				valves.append(v)
			"transit_gate":
				gate = Entities.TransitGate.new()
				gate.mine = self
				gate.position = pos
				entity_root.add_child(gate)
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
			"decor":
				var dd := DeepDecor.new()
				dd.mine = self
				dd.kind = e["kind"]
				dd.w = int(e.get("w", 4))
				dd.h = int(e.get("h", 4))
				dd.flip = bool(e.get("flip", false))
				dd.variant = int(e.get("variant", 0))
				dd.position = Vector2(cell.x * C, (cell.y + 1) * C)
				entity_root.add_child(dd)
			"crate", "beam", "sign", "skull":
				var pr := Entities.Prop.new()
				pr.prop = e["type"] if e["type"] != "skull" else "skull"
				pr.text = e.get("text", "")
				pr.position = pos + Vector2(0, -8)
				if e["type"] == "beam":
					pr.position = Vector2(cell.x * C + 8, cell.y * C + 8)
				entity_root.add_child(pr)
			"crawler":
				spawn_crawler(cell, _breaker_here(cell))
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


func spawn_brute(cell: Vector2i) -> Brute:
	var b := Brute.new()
	b.mine = self
	# stands on the floor under `cell`, centred on the gap between two columns
	b.position = Vector2((cell.x + 1) * C, (cell.y + 1) * C - Brute.HALF.y)
	entity_root.add_child(b)
	enemies.append(b)
	return b


func spawn_flier(cell: Vector2i) -> Flier:
	var f := Flier.new()
	f.mine = self
	f.position = grid.cell_center(cell)
	entity_root.add_child(f)
	enemies.append(f)
	return f


## Spawn one of the crawler's kin ("burrower", "eater") or a spore pod.
func spawn_kin(kind: String, cell: Vector2i) -> Crawler:
	var cr: Crawler
	match kind:
		"burrower": cr = Burrower.new()
		"eater": cr = BombEater.new()
		"spore": cr = SporePod.new()
		"eel": cr = Eel.new()
		"slag": cr = Slag.new()
		_: cr = Crawler.new()
	cr.mine = self
	cr.position = grid.cell_center(cell)
	entity_root.add_child(cr)
	enemies.append(cr)
	return cr


## A dry, open floor cell a crawler-sized enemy can stand in.
func walker_fits(x: int, y: int) -> bool:
	return grid.get_mat(x, y) == Cell.AIR and grid.get_mat(x, y - 1) == Cell.AIR and grid.is_solid(x, y + 1) \
		and grid.get_water(x, y) == 0 and grid.get_lava(x, y) == 0 and not grid.has_flag(x, y, Cell.F_NO_RUBBLE) \
		and not (grid.get_mat(x, y + 1) in [Cell.GAS, Cell.LOOSE])


## A pool for an eel: three cells of deep water side by side.
func eel_fits(x: int, y: int) -> bool:
	for dx in range(-1, 2):
		if grid.is_solid(x + dx, y) or grid.get_water(x + dx, y) < Balance.WATER_MAX * 3 / 4:
			return false
	return true


## Lava for a slag salamander.
func slag_fits(x: int, y: int) -> bool:
	return not grid.is_solid(x, y) and grid.get_lava(x, y) >= Balance.LAVA_MAX / 2


## Room for a brute standing on (x, y) and (x+1, y): two columns of floor,
## three rows of dry air.
func brute_fits(x: int, y: int) -> bool:
	for dx in 2:
		if not grid.is_solid(x + dx, y + 1) or grid.get_mat(x + dx, y + 1) in [Cell.GAS, Cell.LOOSE]:
			return false
		for dy in 3:
			if grid.get_mat(x + dx, y - dy) != Cell.AIR or grid.get_water(x + dx, y - dy) > 0 or grid.get_lava(x + dx, y - dy) > 0:
				return false
			if grid.has_flag(x + dx, y - dy, Cell.F_PROTECTED) or grid.has_flag(x + dx, y - dy, Cell.F_NO_RUBBLE):
				return false
	return true


## Open air for a flier: a clear 5x5 around the cell.
func flier_fits(x: int, y: int) -> bool:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if grid.get_mat(x + dx, y + dy) != Cell.AIR or grid.get_water(x + dx, y + dy) > 0 or grid.get_lava(x + dx, y + dy) > 0:
				return false
	return true


## Brutes and fliers are placed here, on the finished map, from their own
## seeded stream: the generator and its fairness checks are untouched, and a
## seed always gets the same ones. Returns [brute cells, flier cells].
func roamer_cells() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x62727574 ^ (0x64656570 if stage == "deep" else 0)
	var start: Vector2i = data.get("spawn", Vector2i(grid.w / 2, 4))
	var taken: Array[Vector2i] = []
	var far := func(c: Vector2i) -> bool:
		if absi(c.x - start.x) + absi(c.y - start.y) < Balance.BRUTE_MIN_SPAWN_DIST:
			return false
		for o in taken:
			if absi(c.x - o.x) + absi(c.y - o.y) < 16:
				return false
		return true
	var brutes: Array[Vector2i] = []
	var plan: Array = []                 # [zone or -1, count]
	if stage == "deep":
		plan.append([-1, Balance.DEEP_BRUTES])
	else:
		for z in Balance.BRUTES_PER_ZONE.size():
			plan.append([z, int(Balance.BRUTES_PER_ZONE[z])])
	for p: Array in plan:
		var made := 0
		var tries := 0
		while made < int(p[1]) and tries < 1500:
			tries += 1
			var c := Vector2i(rng.randi_range(4, grid.w - 6), rng.randi_range(8, grid.h - 6))
			if int(p[0]) >= 0 and grid.get_stratum(c.x, c.y) != int(p[0]):
				continue
			if brute_fits(c.x, c.y) and far.call(c):
				brutes.append(c)
				taken.append(c)
				made += 1
	var fliers: Array[Vector2i] = []
	var want := Balance.DEEP_FLIERS if stage == "deep" else Balance.FLIERS_PER_MAP
	var tries2 := 0
	while fliers.size() < want and tries2 < 3000:
		tries2 += 1
		var c := Vector2i(rng.randi_range(5, grid.w - 6), rng.randi_range(8, grid.h - 6))
		if stage != "deep" and not (grid.get_stratum(c.x, c.y) in Balance.FLIER_ZONES):
			continue
		if flier_fits(c.x, c.y) and far.call(c):
			fliers.append(c)
			taken.append(c)
	# batch 2 (drawn after the brutes and fliers, so those never move):
	# burrowers per zone, a rare bomb-eater, spore pods in the Spore Veins
	var pick := func(count: int, zones: Array, fits: Callable) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		var n := 0
		while out.size() < count and n < 2500:
			n += 1
			var c := Vector2i(rng.randi_range(5, grid.w - 6), rng.randi_range(8, grid.h - 6))
			if not zones.is_empty() and not (grid.get_stratum(c.x, c.y) in zones):
				continue
			if fits.call(c.x, c.y) and far.call(c):
				out.append(c)
				taken.append(c)
		return out
	var burrowers: Array[Vector2i] = []
	var eaters: Array[Vector2i] = []
	var spores: Array[Vector2i] = []
	if stage == "deep":
		burrowers = pick.call(Balance.DEEP_BURROWERS, [], walker_fits)
		eaters = pick.call(Balance.DEEP_EATERS, [], walker_fits)
	else:
		for z in Balance.BURROWERS_PER_ZONE.size():
			burrowers.append_array(pick.call(int(Balance.BURROWERS_PER_ZONE[z]), [z], walker_fits))
		eaters = pick.call(Balance.EATERS_PER_MAP, Balance.EATER_ZONES, walker_fits)
		spores = pick.call(Balance.SPORES_PER_MAP, [Balance.SPORE_ZONE], flier_fits)
	# batch 3 (drawn last): eels where there is water, slag salamanders in lava
	var eels: Array[Vector2i] = []
	var slags: Array[Vector2i] = []
	if stage == "deep":
		eels = pick.call(Balance.DEEP_EELS, [], eel_fits)
		slags = pick.call(Balance.DEEP_SLAGS, [], slag_fits)
	else:
		eels = pick.call(Balance.EELS_PER_MAP, [Balance.Z_AQUEDUCT], eel_fits)
		eels.append_array(pick.call(Balance.EELS_ELSEWHERE, [Balance.Z_SPORE, Balance.Z_ENGINE, Balance.Z_CRYSTAL], eel_fits))
	return [brutes, fliers, burrowers, eaters, spores, eels, slags]


func _spawn_roamers() -> void:
	if stage == "mission":
		return                    # a mission's map names its own inhabitants
	var cells := roamer_cells()
	for c: Vector2i in cells[0]:
		spawn_brute(c)
	for c: Vector2i in cells[1]:
		spawn_flier(c)
	for c: Vector2i in cells[2]:
		spawn_kin("burrower", c)
	for c: Vector2i in cells[3]:
		spawn_kin("eater", c)
	for c: Vector2i in cells[4]:
		spawn_kin("spore", c)
	for c: Vector2i in cells[5]:
		spawn_kin("eel", c)
	for c: Vector2i in cells[6]:
		spawn_kin("slag", c)


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
	player.hurt.connect(func(_a: float) -> void: _hurt_ago = 0.0)
	camera.global_position = player.global_position
	camera.reset_smoothing()


func _build_ui() -> void:
	hud = load("res://src/ui/hud.gd").new()
	hud.mine = self
	add_child(hud)
	pause_menu = load("res://src/ui/pause_menu.gd").new()
	pause_menu.mine = self
	add_child(pause_menu)
	descent_prompt = load("res://src/ui/descent_prompt.gd").new()
	descent_prompt.mine = self
	add_child(descent_prompt)
	hud.hints.busy = hints_busy
	hud.hints.avoid = player_screen_rect
	hint("drill")
	if Game.slot_ammo(0) > 0:
		hint("explosive")
	if Game.slot_kind(1) != "" and Game.slot_ammo(1) > 0:
		hint("backup")


# ---------------------------------------------------------------------------
var _look := Vector2.ZERO
var _ladder_queue: Array[Vector2i] = []
var _ladder_t := 0.0


func _physics_process(delta: float) -> void:
	_grow_ladders(delta)
	_glutton_rattle(delta)
	_dust_cloak(delta)
	_dowse(delta)
	_greedy_light()
	Perf.physics_tick()
	var t0 := Time.get_ticks_usec()
	if lava:
		lava.update(delta)
		steam.update(delta)
		Perf.add_time("lava", Time.get_ticks_usec() - t0)
		for c in lava.formed_cells:
			var p := grid.cell_center(c)
			# under water the steam shows the reaction; a dust puff there reads as mud
			if grid.get_water(c.x, c.y - 1) < Balance.WATER_MAX / 4:
				fx.dust(p, Color(0.85, 0.85, 0.9), 6)
			fx.sparks(p, Vector2.UP, Color(1.0, 0.55, 0.2))
			Audio.play_at("gas_hiss", p, -8.0, 0.2, 0.15)
		lava.formed_cells.clear()
		_heat_feedback(delta)
	if sand:
		t0 = Time.get_ticks_usec()
		sand.update(delta)
		Perf.add_time("sand", Time.get_ticks_usec() - t0)
	if water:
		t0 = Time.get_ticks_usec()
		water.update(delta)
		erosion.update(delta)
		Perf.add_time("water", Time.get_ticks_usec() - t0)
		_water_feedback(delta)
		for sp in water.splashes:
			fx.splash(sp)
			if randf() < 0.2:
				Audio.play_at("step", sp, -14.0, 0.4, 0.05)


## Is a player, enemy or prop in this cell? New rock must never form there.
func _cell_occupied(c: Vector2i) -> bool:
	var r := Rect2(c.x * C, c.y * C, C, C).grow(2.0)
	if player and Rect2(player.global_position - Player.HALF, Player.HALF * 2.0).intersects(r):
		return true
	for e in enemies:
		if is_instance_valid(e) and e.has_method("hit_rect") and e.hit_rect().intersects(r):
			return true
	for p in debris.props:
		if is_instance_valid(p) and r.has_point(p.global_position):
			return true
	return false


## Lava burns on contact (on a fair cadence, never instantly), dense steam
## scalds and lifts, and heat is announced before it hurts.
func _heat_feedback(delta: float) -> void:
	if player == null or player.dead or ending:
		return
	_burn_t = maxf(0.0, _burn_t - delta)
	_scald_t = maxf(0.0, _scald_t - delta)
	_heat_warn_t = maxf(0.0, _heat_warn_t - delta)
	var pc := grid.world_to_cell(player.global_position)
	var feet := grid.world_to_cell(player.global_position + Vector2(0, Player.HALF.y - 1.0))
	var lava_here := maxi(grid.get_lava(feet.x, feet.y), grid.get_lava(pc.x, pc.y))
	if lava_here > 0 and Game.has_relic("slag"):
		_slag_heart(pc, feet)
	elif lava_here >= Balance.LAVA_BURN_MIN:
		if _burn_t <= 0.0:
			_burn_t = Balance.LAVA_BURN_INTERVAL
			player.invuln = 0.0
			player.take_damage(Balance.LAVA_BURN_DAMAGE * (0.5 if Game.has_relic("ember") else 1.0), player.global_position + Vector2(0, 12), "molten rock")
			fx.sparks(player.global_position + Vector2(0, 10), Vector2.UP, Color(1.0, 0.55, 0.2))
	elif _heat_warn_t <= 0.0:
		var r := Balance.LAVA_WARN_CELLS
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if grid.get_lava(pc.x + dx, pc.y + dy) >= Balance.LAVA_BURN_MIN:
					_heat_warn_t = 6.0
					toast("HEAT WARNING - molten rock nearby")
					break
			if _heat_warn_t > 0.0:
				break
	var d := steam.density(pc) + steam.density(Vector2i(pc.x, pc.y - 1))
	if d >= Balance.STEAM_SCALD:
		player.velocity.y -= Balance.STEAM_LIFT * delta * 10.0 * minf(d, 2.0)
		if _scald_t <= 0.0:
			_scald_t = Balance.STEAM_INTERVAL
			player.take_damage(Balance.STEAM_DAMAGE * (0.5 if Game.has_relic("ember") else 1.0), Vector2.INF, "scalding steam")
	for e in enemies:
		if not is_instance_valid(e) or not e.has_method("hit"):
			continue
		var ec := grid.world_to_cell(e.global_position)
		if steam and steam.density(ec) >= Balance.STEAM_SCALD and randf() < delta / Balance.STEAM_INTERVAL:
			e.set("last_hit", "steam")
			e.hit(Balance.STEAM_ENEMY_DAMAGE, e.global_position, false)
			if not is_instance_valid(e):
				continue
		if grid.get_lava(ec.x, ec.y) >= Balance.LAVA_BURN_MIN and randf() < delta / Balance.LAVA_BURN_INTERVAL:
			e.set("last_hit", "lava")
			e.hit(Balance.LAVA_ENEMY_DAMAGE, e.global_position + Vector2(0, 8), false)


## Slag Heart: lava you wade into crusts into rock around you instead of
## burning. Rock never forms inside the digger (LavaSim defers those cells).
func _slag_heart(pc: Vector2i, feet: Vector2i) -> void:
	if _burn_t > 0.0 or lava == null:
		return
	_burn_t = Balance.SLAG_TICK
	var r := Balance.SLAG_RADIUS
	var ri := ceili(r)
	var n := 0
	for centre: Vector2i in [feet, pc]:
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var cc: Vector2i = centre + Vector2i(dx, dy)
				if Vector2(dx, dy).length() <= r and grid.get_lava(cc.x, cc.y) > 0 and lava.quench(cc):
					n += 1
	if n > 0:
		fx.sparks(player.global_position + Vector2(0, 10), Vector2.UP, Color(1.0, 0.45, 0.2))
		Audio.play_at("gas_hiss", player.global_position, -6.0, 0.2, 0.1)
		if not _slag_told:
			_slag_told = true
			toast("SLAG HEART - the lava crusts around you")


var _slag_told := false


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
	_update_orders(delta)
	Game.run["gadget_cd"] = maxf(0.0, float(Game.run.get("gadget_cd", 0.0)) - delta * (2.0 if Game.has_relic("coil") else 1.0))
	_tick_anchors(delta)
	var depth_cells := int(player.global_position.y / C) + depth_offset
	Game.run["max_depth"] = maxi(int(Game.run.get("max_depth", 0)), depth_cells)
	if Game.run.get("relic", false):
		_alarm_t -= delta
		if _alarm_t <= 0.0:
			_alarm_t = 7.0
			noise(player.global_position, 20.0)
	_hints(delta)


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


## The zone you are in, as the game presents it (name, music, light, water,
## banner). It follows the digger, not the camera (which looks ahead), and
## only changes once you are ZONE_ENTRY_ROWS past the wavy border, so
## touching the boundary at the bottom of a wing does not count as arriving.
var presented_zone := -1


func _update_presented_zone() -> void:
	if player == null:
		return
	var c := grid.world_to_cell(player.global_position + Vector2(0, Player.HALF.y - 1.0))
	c.x = clampi(c.x, 0, grid.w - 1)
	c.y = clampi(c.y, 0, grid.h - 1)
	var s := maxi(0, grid.get_stratum(c.x, c.y))
	if presented_zone < 0:
		presented_zone = s
		_zone_reached(s)
		return
	if s == presented_zone:
		return
	var m := Balance.ZONE_ENTRY_ROWS
	var up := grid.get_stratum(c.x, clampi(c.y - m, 0, grid.h - 1))
	var dn := grid.get_stratum(c.x, clampi(c.y + m, 0, grid.h - 1))
	if up == s and dn == s:
		presented_zone = s
		_zone_reached(s)


func _atmosphere(delta: float) -> void:
	# the zone you are in sets light, backdrop and music
	_update_presented_zone()
	var mid := camera.get_screen_center_position() / C
	var y := mid.y
	var s := maxi(0, presented_zone)
	var target: Color = AMBIENT[s]
	var dark := float(Game.run.get("contract", {}).get("dark", 1.0))
	if dark < 1.0:
		target = Color(target.r * dark, target.g * dark, target.b * dark)
	if y < 12.0 and stage == "mine":
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
		if stage != "mission":
			codex_unlock("zone:%d" % s, _hint_t > 2.0)    # the zone you start in opens quietly
		Game.run["zone"] = s
	if stage == "deep":
		# the stage is one biome, so announce its three regions as the player moves
		var py := int(player.global_position.y / C)
		var region := 0 if py < Balance.DEEP_BAND_PLANT else (1 if py < Balance.DEEP_BAND_TRANSIT else 2)
		if region != _deep_region:
			if _deep_region >= 0 and hud:
				hud.banner(Balance.DEEP_REGION_NAMES[region])
			_deep_region = region


var _deep_region := -1


func _explore() -> void:
	var c := grid.world_to_cell(player.global_position)
	var r := 7
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				grid.explore(c.x + dx, c.y + dy)


# --- Contextual hints and the codex --------------------------------------------
## Queue a contextual hint (shown once per save; see HintStrip).
func hint(id: String) -> bool:
	return hud != null and hud.hints.hint(id)


## Open a codex page; the first time, a short notice says so.
func codex_unlock(key: String, notify: bool = true) -> bool:
	if not Progress.unlock(key):
		return false
	if hud and notify:
		hud.hints.notice("CODEX: %s added" % String(CodexData.entry(key).get("name", key)))
		hint("codex")
	return true


## A one-off explanation of something that just happened (once per save).
func tell_once(id: String, text: String) -> void:
	if bool(Settings.get_value("hints")) and Progress.mark_hint(id):
		toast(text)


## Something happened that has a hint and a codex page (water, gas, ...).
func discover(id: String) -> void:
	hint(id)
	codex_unlock("hazard:" + id)


## The digger (with its drill and a little room) on screen, for the hint strip.
func player_screen_rect() -> Rect2:
	if player == null or not player.visible:
		return Rect2()
	var xf := player.get_global_transform_with_canvas()
	var a := xf * (-Player.HALF - Vector2(10, 6))
	var b := xf * (Player.HALF + Vector2(10, 2))
	return Rect2(a, b - a).abs()


## Hints wait while you are being hurt or chased.
func hints_busy() -> bool:
	if _hurt_ago < Balance.HINT_CALM or player == null or player.dead:
		return true
	for e in enemies:
		if is_instance_valid(e) and e.get("state") != null and e.state == Crawler.S.CHASE \
				and e.global_position.distance_to(player.global_position) < 10.0 * C:
			return true
	return false


func _hints(delta: float) -> void:
	_hurt_ago += delta
	_hint_t += delta
	if hud == null or player == null or player.dead:
		return
	if _hint_t > 90.0 and Progress.stats.get("runs", 0) <= 2:
		hint("lure")
	if player.heat >= player.heat_cap * Balance.HINT_HEAT:
		hint("heat")
	if player.overheated:
		hint("overheat")
	_hint_scan_t -= delta
	if _hint_scan_t > 0.0:
		return
	_hint_scan_t = 0.5
	var pc := grid.world_to_cell(player.global_position)
	var r := Balance.HINT_SCAN
	var seen := {}
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := pc.x + dx
			var y := pc.y + dy
			if not grid.in_bounds(x, y):
				continue
			if grid.get_water(x, y) >= Balance.WATER_MAX / 4:
				seen["water"] = true
			if grid.get_lava(x, y) > 0:
				seen["lava"] = true
			if grid.get_sand(x, y) >= Balance.SAND_MAX / 2:
				seen["sand"] = true
			if absi(dx) <= 2 and absi(dy) <= 2 and grid.get_mat(x, y) == Cell.LADDER:
				seen["ladder"] = true
	for k: String in seen:
		if k == "ladder":
			hint("ladder")
		else:
			discover(k)
	if steam and steam.density(pc) > 0.0:
		codex_unlock("hazard:steam")
	if Game.cargo_count() > 0:
		for l in lifts:
			if l.active and l.global_position.distance_to(player.global_position) < 6.0 * C:
				hint("lift")


# ---------------------------------------------------------------------------
# Shared rules
func cargo_cap() -> int:
	return Balance.cargo_capacity(Progress.level("cargo")) + (Balance.GLUTTON_SLOTS if Game.has_relic("glutton") else 0)


## Damage scale for falling rock, rubble and boulders hitting the digger.
func rock_damage_mult() -> float:
	if Game.has_relic("hardhat"):
		return 0.0
	return Balance.PLATING_MULT if has_passive("plating") else 1.0


func damage_cell(c: Vector2i, amount: float, tier: int, ignore_tier: bool, source: String) -> Dictionary:
	var m := grid.get_mat(c.x, c.y)
	if source == "blast" and not Cell.is_solid(m) and grid.get_sand(c.x, c.y) > 0:
		dig_sand(c)
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
			if m == Cell.SOFT:
				raise_dust()
		var o: int = res["ore"]
		if o != 0:
			var n: int = int(Balance.ORE[o]["drops"]) + (1 if Game.has_relic("charm") else 0)
			var key := Balance.ore_key(o, maxi(0, s))
			for i in n:
				spawn_pickup(pos + Vector2(randf_range(-3, 3), randf_range(-3, 3)), key)
			fx.glints(pos, Balance.ore_color(o))
			fx.flash(pos, Balance.ore_color(o), 0.45, 0.25)
			Audio.play_at("ore_rare" if o == Cell.ORE_AETHER else "ore", pos, -3.0)
			Game.run["ore_mined"] = int(Game.run.get("ore_mined", 0)) + 1
			Progress.add_stat("ore_mined")
		# loose ground: some drilled sediment and blasted rubble stays behind
		# as sand that settles into piles
		if sand and SandSim.enabled():
			if source == "drill" and m == Cell.SOFT:
				_sand_drill_n += 1
				if _sand_drill_n % Balance.SAND_DRILL_EVERY == 0:
					spray_sand(c, Balance.SAND_DRILL_AMOUNT, 4, 55.0, 0.7)
			elif source == "blast" and (m == Cell.SOFT or m == Cell.LOOSE):
				_sand_blast_n += 1
				if _sand_blast_n % Balance.SAND_BLAST_EVERY == 0:
					spray_sand(c, Balance.SAND_BLAST_AMOUNT, 4, 150.0, 1.0)
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
	if before < scaffold_cap() and int(Game.run["scaffold"]) >= scaffold_cap():
		hint("scaffold")


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
	Progress.add_stat("ladders_built")
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
	if res["broken"] and Game.has_relic("echo"):
		_echo_n += 1
		if _echo_n % Balance.ECHO_EVERY == 0:
			_echo_break(c + by.drill_dir, tier)
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


## Echo Drill: the block behind the one you just broke goes too, if your
## drill could cut it (tier, protection and bedrock rules still apply).
func _echo_break(c: Vector2i, tier: int) -> void:
	if not grid.is_solid(c.x, c.y):
		return
	var r2 := damage_cell(c, 9999.0, tier, false, "drill")
	if r2["broken"]:
		fx.flash(grid.cell_center(c), Color(Balance.RUN_RELICS[_relic_index("echo")]["color"]), 0.5, 0.25)


func _relic_index(id: String) -> int:
	for k in Balance.RUN_RELICS.size():
		if Balance.RUN_RELICS[k]["id"] == id:
			return k
	return 0


## Glutton's Sack: ore on board rattles while you move; louder the fuller you are.
func _glutton_rattle(delta: float) -> void:
	if not Game.has_relic("glutton") or player == null or player.dead or ending:
		return
	var n := Game.cargo_count()
	if n <= 0 or player.velocity.length() < 40.0:
		return
	_rattle_t -= delta
	if _rattle_t > 0.0:
		return
	_rattle_t = Balance.GLUTTON_RATTLE
	var f := clampf(float(n) / float(maxi(1, cargo_cap())), 0.0, 1.0)
	noise(player.global_position, lerpf(Balance.GLUTTON_NOISE[0], Balance.GLUTTON_NOISE[1], f))
	Audio.play_at("pickup", player.global_position, -10.0, 0.3, 0.05)


## First arrival in a zone this run. Spare Parts hands out a charge (or a
## lure when the charge rack is full).
func _zone_reached(z: int) -> void:
	var seen: Array = Game.run.get("zones_seen", [])
	if seen.has(z):
		return
	seen.append(z)
	Game.run["zones_seen"] = seen
	if Game.has_relic("cartographer"):
		reveal_zone(z)
	if not Game.has_relic("spares"):
		return
	var main := Game.slot_kind(0)
	if main != "" and int(Game.run.get("charges", 0)) < Progress.carry(main):
		Game.run["charges"] = int(Game.run.get("charges", 0)) + 1
		toast("SPARE PARTS - you rig up a %s" % String(Balance.EXPLOSIVES[main]["name"]).to_lower())
	elif int(Game.run.get("lures", 0)) < Balance.SPARE_LURES_MAX:
		Game.run["lures"] = int(Game.run.get("lures", 0)) + 1
		toast("SPARE PARTS - you rig up a lure")
	else:
		toast("SPARE PARTS - your kit is already full")
		return
	Audio.play("pickup", -4.0)


## Cartographer's Eye: every cell of a zone is drawn on the map. Returns how
## many cells were newly revealed.
func reveal_zone(z: int) -> int:
	var n := 0
	for y in grid.h:
		for x in grid.w:
			if grid.get_stratum(x, y) == z and grid.explore(x, y):
				n += 1
	if n > 0:
		toast("CARTOGRAPHER'S EYE - %s is on your map" % Balance.STRATUM_NAMES[clampi(z, 0, Balance.STRATUM_NAMES.size() - 1)])
	return n


## A run relic was just taken (RunRelic.take): effects that start at once.
func on_relic_taken(id: String) -> void:
	hint("relic")
	codex_unlock("relic:" + id)
	match id:
		"cartographer":
			for z in Game.run.get("zones_seen", []):
				reveal_zone(int(z))
		"dowsing":
			_dowse_t = 0.0


var _dowse_t := 0.0
var dowsed: Dictionary = {}      # Vector2i -> true: water cells sensed on the map


## Dowsing Rod: water near you shows on the map before you see it.
func _dowse(delta: float) -> void:
	if not Game.has_relic("dowsing") or player == null or hud == null or hud.get("minimap") == null:
		return
	_dowse_t -= delta
	if _dowse_t > 0.0:
		return
	_dowse_t = Balance.DOWSE_TICK
	var mm: Minimap = hud.minimap
	var pc := grid.world_to_cell(player.global_position)
	var r := Balance.DOWSE_RADIUS
	var now: Dictionary = {}
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var c := pc + Vector2i(dx, dy)
			if not grid.in_bounds(c.x, c.y) or grid.has_flag(c.x, c.y, Cell.F_EXPLORED):
				continue
			if not grid.is_solid(c.x, c.y) and grid.get_water(c.x, c.y) >= Balance.WATER_MAX / 3:
				now[c] = true
	for c in dowsed.keys():
		if not now.has(c):
			mm.sense(c.x, c.y, false)
	for c in now.keys():
		if not dowsed.has(c):
			mm.sense(c.x, c.y, true)
	dowsed = now


var compass: OreCompass
var _lamp_base := -1.0


## Greedy Lamp's cost: a smaller lamp (the pressure part is in Pressure._mult).
func _greedy_light() -> void:
	if player == null or player.lamp == null:
		return
	if _lamp_base < 0.0:
		_lamp_base = player.lamp.texture_scale
	player.lamp.texture_scale = _lamp_base * (Balance.GREEDY_LIGHT if Game.has_relic("greedy") else 1.0)


var _echo_n := 0
var _rattle_t := 0.0
var cloak_t := 0.0
var _cloak_fx_t := 0.0


## Dust Cloak: hidden from foes more than DUST_CLOAK_NEAR cells away.
func cloaked() -> bool:
	return cloak_t > 0.0


## Dust Cloak: dust raised (running on sand, drilling sand or sediment).
func raise_dust() -> void:
	if not Game.has_relic("dustcloak") or player == null:
		return
	if cloak_t <= 0.0:
		toast("DUST CLOAK - they can't see you through the dust")
	cloak_t = Balance.DUST_CLOAK_TIME


func _dust_cloak(delta: float) -> void:
	cloak_t = maxf(0.0, cloak_t - delta)
	if player == null or player.dead or not Game.has_relic("dustcloak"):
		return
	if player.is_on_floor() and absf(player.velocity.x) >= Balance.DUST_CLOAK_RUN:
		var f := player.feet_cell()
		if grid.get_sand(f.x, f.y) > 0 or grid.get_sand(f.x, f.y + 1) > 0:
			raise_dust()
	if cloak_t > 0.0:
		_cloak_fx_t -= delta
		if _cloak_fx_t <= 0.0:
			_cloak_fx_t = 0.25
			fx.dust(player.global_position + Vector2(randf_range(-8, 8), 6), Color(0.85, 0.78, 0.6), 3)


func drill_enemies(r: Rect2, dmg: float, by: Player) -> void:
	debris.drill_rect(r, dmg)
	for e in enemies:
		if is_instance_valid(e) and e.hit_rect().intersects(r):
			e.set("last_hit", "drill")
			e.hit(dmg, by.global_position)


func noise(pos: Vector2, radius_cells: float) -> void:
	if pressure:
		pressure.on_noise(radius_cells)
	for e in enemies:
		if is_instance_valid(e) and e.has_method("hear"):
			e.hear(pos, radius_cells)


func explode(pos: Vector2, radius_cells: float, tile_dmg: float, ent_dmg: float, cause: String, ignite: bool = true) -> void:
	var r := radius_cells * C
	fx.explosion(pos, r)
	Audio.play_at("explode", pos, 2.0, 0.08, 0.0)
	shake(0.6)
	var c := grid.world_to_cell(pos)
	var ri := ceili(radius_cells)
	var ladders: Array[Vector2i] = []
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var cc := c + Vector2i(dx, dy)
			var d := grid.cell_center(cc).distance_to(pos) / r
			if d > 1.0:
				continue
			var m := grid.get_mat(cc.x, cc.y)
			if m == Cell.LADDER:
				ladders.append(cc)       # every ladder breaks, even a protected one
				continue
			if Cell.blast_proof(m) or grid.has_flag(cc.x, cc.y, Cell.F_PROTECTED):
				continue
			damage_cell(cc, tile_dmg * lerpf(1.0, 0.45, d), 99, true, "blast")
	break_ladders(ladders)
	for e in enemies:
		if is_instance_valid(e):
			var ed: float = e.global_position.distance_to(pos)
			if ed < r + 8.0:
				e.set("last_hit", "charge" if cause in ["charge", "eater"] else "gas")
				e.hit(ent_dmg * lerpf(1.0, 0.5, ed / (r + 8.0)), pos)
				e.stun(1.2)
	if player and not player.dead:
		var pd := player.global_position.distance_to(pos)
		if pd < r + 6.0:
			var self_dmg := Balance.CHARGE_SELF_DAMAGE * Balance.demo_mult("shield", Progress.demo_level("shield")) if cause == "charge" else ent_dmg * 0.55
			player.take_damage(self_dmg * lerpf(1.0, 0.4, pd / (r + 6.0)), pos, {"charge": "own charge", "eater": "bomb-eater blast"}.get(cause, "gas ignition"))
	debris.blast(pos, r)
	noise(pos, 16.0)
	_chain_mines(pos, r)
	if ignite:
		gas.ignite_near(pos, r)
	if cause == "charge" and Game.has_relic("faultline"):
		fault_line(c, ri)


## A blast breaks the ladder cells in it; the rest of each ladder above the
## blast loses its footing and falls, and the part below stays. Returns how
## many ladder cells went (broken + fallen).
func break_ladders(hit: Array[Vector2i]) -> int:
	if hit.is_empty():
		return 0
	var tops := {}
	for c in hit:
		if not tops.has(c.x) or c.y < int(tops[c.x]):
			tops[c.x] = c.y
	var n := 0
	for c in hit:
		_drop_ladder_cell(c, false)
		n += 1
	for x: int in tops:
		var y: int = int(tops[x]) - 1
		while grid.in_bounds(x, y) and grid.get_mat(x, y) == Cell.LADDER:
			_drop_ladder_cell(Vector2i(x, y), true)
			n += 1
			y -= 1
	if n > 0:
		Audio.play_at("break_soft", grid.cell_center(hit[0]), 0.0, 0.15, 0.05)
	ladders_broken += n
	return n


var ladders_broken := 0


func _drop_ladder_cell(c: Vector2i, falls: bool) -> void:
	var s := grid.get_stratum(c.x, c.y)
	grid.set_flag(c.x, c.y, Cell.F_PROTECTED, false)
	grid.set_mat(c.x, c.y, Cell.AIR, true)
	_ladder_queue.erase(c)
	var pos := grid.cell_center(c)
	if falls:
		var bit := Hazards.LadderBit.new()
		bit.mine = self
		bit.tex = view.tex_props
		bit.region = view.prop_rect("ladder_wood" if s == 0 else "ladder_metal")
		bit.position = pos
		bit.vel = Vector2(randf_range(-12, 12), randf_range(-20, 10))
		bit.spin = randf_range(-2.0, 2.0)
		entity_root.add_child(bit)
	else:
		fx.burst(pos, Color(0.75, 0.5, 0.3), 5)


## Fault Line: the ceiling over a charge cracks and falls a moment later.
## Returns the number of cells set to fall.
func fault_line(c: Vector2i, blast_r: int) -> int:
	var n := 0
	for dx in range(-Balance.FAULT_HALF, Balance.FAULT_HALF + 1):
		var x := c.x + dx
		var roof := -1
		for y in range(c.y - 1, c.y - blast_r - Balance.FAULT_SCAN, -1):
			if grid.is_solid(x, y):
				roof = y
				break
		if roof < 0:
			continue
		for k in 2:
			var cc := Vector2i(x, roof - k)
			if not breakable_support(cc) or collapse.pending.has(cc):
				break
			grid.set_mat(cc.x, cc.y, Cell.LOOSE)
			collapse.pending[cc] = Balance.FAULT_WARN * randf_range(0.9, 1.2) + 0.3 * k
			n += 1
	if n > 0:
		Audio.play_at("rumble", grid.cell_center(c), -2.0, 0.1, 0.2)
		toast("FAULT LINE - the ceiling is coming down!")
	return n


# --- gadgets ----------------------------------------------------------------
func has_passive(id: String) -> bool:
	return String(Game.run.get("loadout", {}).get("passive", "")) == id


func active_gadget() -> String:
	return String(Game.run.get("loadout", {}).get("active", ""))


func use_gadget(pl: Player) -> void:
	var id := active_gadget()
	if id == "" or pl.dead or ending:
		return
	var cd := float(Game.run.get("gadget_cd", 0.0))
	if cd > 0.0:
		toast("%s recharging - %ds" % [Balance.GADGETS[id]["name"], ceili(cd)])
		Audio.play("ui_deny")
		return
	Game.run["gadget_cd"] = float(Balance.GADGETS[id]["cooldown"])
	match id:
		"sonar":
			sonar(pl.global_position)
		"cryo":
			var cr := Hazards.Cryo.new()
			cr.mine = self
			cr.vel = Vector2(Balance.CRYO_THROW.x * pl.facing, Balance.CRYO_THROW.y) + pl.velocity * 0.4
			cr.position = pl.global_position + Vector2(pl.facing * 6, -8)
			entity_root.add_child(cr)
			Audio.play("throw")


## Reveal the map nearby and mark what matters in the rock.
func sonar(pos: Vector2) -> Node2D:
	var c := grid.world_to_cell(pos)
	var r := Balance.SONAR_RADIUS
	var ping := Hazards.SonarPing.new()
	ping.position = pos
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var cc := c + Vector2i(dx, dy)
			if not grid.in_bounds(cc.x, cc.y):
				continue
			grid.explore(cc.x, cc.y)
			if ping.marks.size() >= Balance.SONAR_MAX_MARKS:
				continue
			var m := grid.get_mat(cc.x, cc.y)
			var col := Color(0, 0, 0, 0)
			var o := grid.get_ore(cc.x, cc.y)
			if o != 0 and Cell.is_solid(m):
				col = Balance.ore_color(o)
			elif m == Cell.GAS:
				col = Color(0.75, 1.0, 0.25)
			elif m == Cell.LOOSE:
				col = Color(1.0, 0.6, 0.25)
			if col.a > 0.0:
				ping.marks.append([grid.cell_center(cc) - pos, col])
	entity_root.add_child(ping)
	Audio.play("lift_ding", -6.0, 0.3, 0.0)
	toast("SONAR - %d marks" % ping.marks.size())
	return ping


func cryo_burst(pos: Vector2) -> void:
	var c := grid.world_to_cell(pos)
	var r := Balance.CRYO_RADIUS
	var ri := ceili(r)
	var crusted := 0
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var cc := c + Vector2i(dx, dy)
			if Vector2(dx, dy).length() > r or not grid.in_bounds(cc.x, cc.y):
				continue
			if lava and grid.get_lava(cc.x, cc.y) > 0:
				if lava.quench(cc):
					crusted += 1
			if steam:
				steam.cells.erase(cc)
	for e in enemies:
		if is_instance_valid(e) and e.global_position.distance_to(pos) <= (r + 1.0) * C:
			if e.has_method("quench"):
				e.quench()                 # a slag salamander sets into stone
				continue
			e.stun(Balance.CRYO_STUN)
			if e is Crawler:
				e.flash = 1.0
	if player and player.global_position.distance_to(pos) <= (r + 1.5) * C:
		player.heat = 0.0
		player.overheated = false
	fx.burst(pos, Color(0.6, 0.95, 1.0), 16)
	fx.flash(pos, Color(0.5, 0.9, 1.0), 0.9, 0.35)
	Audio.play_at("gas_hiss", pos, -2.0, 0.2, 0.1)
	if crusted > 0:
		toast("CRYO - %d cells of lava crusted" % crusted)


# --- anchors, shear charges, bolts ---------------------------------------------
var anchored: Dictionary = {}      # Vector2i -> seconds left (rock pinned by bolts)


func is_anchored(c: Vector2i) -> bool:
	return anchored.has(c)


func _tick_anchors(delta: float) -> void:
	if anchored.is_empty():
		return
	for c in anchored.keys():
		anchored[c] = float(anchored[c]) - delta
		if float(anchored[c]) <= 0.0:
			anchored.erase(c)


## Can a collapse, a tremor or a breaker take this cell?
func breakable_support(c: Vector2i) -> bool:
	if not grid.in_bounds(c.x, c.y) or grid.has_flag(c.x, c.y, Cell.F_PROTECTED) or is_anchored(c):
		return false
	var m := grid.get_mat(c.x, c.y)
	return m == Cell.SOFT or m == Cell.HARD or m == Cell.LOOSE or m == Cell.CRACKED


## Loosen ground that has nothing under it any more, around a cut: soft
## ground slumps as rubble (after a short warning), hard rock goes to the
## boulder system as a falling mass. Returns how many cells were set to fall.
func drop_unsupported(c: Vector2i, reach: Vector2i, warn: float) -> int:
	var n := 0
	for y in range(c.y, c.y - reach.y - 1, -1):
		for x in range(c.x - reach.x, c.x + reach.x + 1):
			var cc := Vector2i(x, y)
			if not breakable_support(cc) or grid.is_solid(x, y + 1):
				continue
			var m := grid.get_mat(x, y)
			if m == Cell.HARD:
				collapse._boulder_checks[cc] = true
				n += 1
			elif not collapse.pending.has(cc):
				if m != Cell.LOOSE:
					grid.set_mat(x, y, Cell.LOOSE)
				collapse.pending[cc] = warn * randf_range(0.9, 1.3)
				n += 1
	return n


## A shear charge: a small, clean cut, then whatever rested on it comes down.
func shear_blast(pos: Vector2) -> void:
	var c := grid.world_to_cell(pos)
	var r := Balance.SHEAR_RADIUS
	var ri := ceili(r)
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var cc := c + Vector2i(dx, dy)
			if Vector2(dx, dy).length() > r or not breakable_support(cc):
				continue
			damage_cell(cc, 999.0, 99, true, "shear")
	for e in enemies:
		if is_instance_valid(e) and e.global_position.distance_to(pos) < (r + 1.0) * C:
			e.set("last_hit", "rubble")
			e.hit(Balance.SHEAR_ENTITY_DAMAGE, pos)
	fx.burst(pos, Color(0.7, 0.85, 1.0), 10)
	fx.flash(pos, Color(0.6, 0.85, 1.0), 0.5, 0.25)
	Audio.play_at("explode", pos, -6.0, 0.15, 0.0)
	shake(0.35)
	noise(pos, 10.0)
	var dropped := drop_unsupported(c, Balance.SHEAR_REACH, Balance.SHEAR_DROP_WARN)
	if dropped > 0:
		toast("SHEARED - the ground above is coming down!")


func spawn_shear(pos: Vector2, v: Vector2) -> void:
	var ch := Hazards.Charge.new()
	ch.mine = self
	ch.shear = true
	ch.fuse = Balance.SHEAR_FUSE
	ch.sticky = Game.has_explosive("sticky")
	ch.vel = v
	ch.position = pos
	entity_root.add_child(ch)


## Fire an anchor bolt from the digger toward where it aims (up by default):
## it pins the rock around the spot it hits for BOLT_TIME.
func fire_bolt(pl: Player, aim: Vector2i) -> bool:
	var from := grid.world_to_cell(pl.global_position + Vector2(0, -8))
	var hit := Vector2i(-1, -1)
	for k in range(1, Balance.BOLT_RANGE + 1):
		var cc := from + aim * k
		if grid.is_solid(cc.x, cc.y):
			hit = cc
			break
	if hit.x < 0:
		toast("Nothing in reach to bolt into")
		Audio.play("ui_deny")
		return false
	var held: Array[Vector2i] = []
	var ri := ceili(Balance.BOLT_RADIUS)
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var cc := hit + Vector2i(dx, dy)
			if Vector2(dx, dy).length() <= Balance.BOLT_RADIUS and grid.in_bounds(cc.x, cc.y) and grid.is_solid(cc.x, cc.y):
				anchored[cc] = Balance.BOLT_TIME
				collapse.pending.erase(cc)
				held.append(cc)
	var b := Hazards.Bolt.new()
	b.mine = self
	b.cells = held
	b.dir = aim
	b.position = grid.cell_center(hit) - Vector2(aim) * 7.0
	entity_root.add_child(b)
	Audio.play_at("hit_metal", b.position, -2.0, 0.1, 0.0)
	return true


func spawn_lure(pos: Vector2, v: Vector2) -> Node2D:
	var lu := Hazards.Lure.new()
	lu.mine = self
	lu.vel = v
	lu.position = pos
	entity_root.add_child(lu)
	return lu


## A thrown explosive: "charge" (bounces), "sticky" or "remote".
func spawn_charge(pos: Vector2, v: Vector2, kind: String = "charge") -> Hazards.Charge:
	var ch := Hazards.Charge.new()
	ch.mine = self
	ch.sticky = kind == "sticky"
	ch.remote = kind == "remote"
	ch.fuse = Balance.CHARGE_FUSE * Balance.demo_mult("fuse", Progress.demo_level("fuse"))
	ch.vel = v
	ch.position = pos
	entity_root.add_child(ch)
	if ch.remote:
		remotes.append(ch)
	charges.append(ch)
	return ch


var remotes: Array = []          # remote charges waiting for their signal
var charges: Array = []          # thrown charges of every kind (bomb-eaters look here)


func remotes_out() -> int:
	var live: Array = []
	for ch in remotes:
		if is_instance_valid(ch) and not ch.is_queued_for_deletion() and not ch.armed:
			live.append(ch)
	remotes = live
	return remotes.size()


## Set off every remote charge that is out. Returns how many.
func detonate_remotes() -> int:
	var n := remotes_out()
	for ch in remotes:
		ch.detonate()
	remotes.clear()
	if n > 0:
		Audio.play("ui_confirm", -4.0)
	return n


func spawn_rocket(pos: Vector2, dir: Vector2i) -> Hazards.Rocket:
	var rk := Hazards.Rocket.new()
	rk.mine = self
	rk.dir = dir
	rk.life = Balance.ROCKET_LIFE * Balance.demo_mult("bore", Progress.demo_level("bore"))
	rk.position = pos
	entity_root.add_child(rk)
	return rk


func spawn_mine(pos: Vector2) -> Hazards.ProxMine:
	var pm := Hazards.ProxMine.new()
	pm.mine = self
	pm.position = pos
	entity_root.add_child(pm)
	mines.append(pm)
	return pm


var mines: Array = []            # proximity mines lying in the mine


## How close (cells) something must come to set a proximity mine off.
func mine_trigger() -> float:
	return Balance.MINE_TRIGGER * Balance.demo_mult("sensor", Progress.demo_level("sensor"))


## MINE SENSOR at its top level: mines no longer react to the digger.
func mines_ignore_digger() -> bool:
	return Progress.demo_level("sensor") >= Balance.MINE_FRIENDLY_LEVEL


## A blast catches the mines in reach: they go off too, after their beep.
func _chain_mines(pos: Vector2, r: float) -> int:
	var n := 0
	var live: Array = []
	for pm in mines:
		if not is_instance_valid(pm) or pm.is_queued_for_deletion():
			continue
		live.append(pm)
		if pm.tripped < 0.0 and pm.global_position.distance_to(pos) <= r + 4.0:
			pm.trip()
			n += 1
	mines = live
	return n


## Blast radius (cells) and power of your explosives, with the Demolitions
## upgrades applied.
func blast_radius() -> float:
	return Balance.CHARGE_RADIUS_CELLS * Balance.demo_mult("radius", Progress.demo_level("radius"))


func blast_power() -> float:
	return Balance.demo_mult("power", Progress.demo_level("power"))


## One of your explosives going off (charge, sticky, remote, rocket, mine).
func charge_blast(pos: Vector2) -> void:
	var p := blast_power()
	explode(pos, blast_radius(), Balance.CHARGE_TILE_DAMAGE * p, Balance.CHARGE_ENTITY_DAMAGE * p, "charge")


## A bomb-eater going off: a fixed, bigger blast that your upgrades don't touch.
func eater_blast(pos: Vector2) -> void:
	explode(pos, Balance.EATER_BLAST_CELLS, Balance.CHARGE_TILE_DAMAGE, Balance.CHARGE_ENTITY_DAMAGE, "eater")


## A fresh ore drop, graded by the zone it came from.
func spawn_ore(pos: Vector2, ore: int) -> Entities.Pickup:
	var c := grid.world_to_cell(pos)
	return spawn_pickup(pos, Balance.ore_key(ore, maxi(0, grid.get_stratum(c.x, c.y))))


func spawn_pickup(pos: Vector2, ore: int) -> Entities.Pickup:
	var p := Entities.Pickup.new()
	p.mine = self
	p.ore = ore
	p.vel = Vector2(randf_range(-60, 60), randf_range(-140, -60))
	p.position = pos
	entity_root.add_child(p)
	return p


func collect(p: Node) -> void:
	var cargo: Dictionary = Game.run["cargo"]
	var key: int = p.ore
	if Game.cargo_count() >= cargo_cap():
		# full: swap out one unit of the cheapest ore for this better one; the
		# cheap unit drops as a loose pickup you can still take back later
		var cheap := Game.cheapest_cargo()
		if cheap < 0 or Balance.ore_value(key) <= Balance.ore_value(cheap):
			return
		cargo[cheap] = int(cargo[cheap]) - 1
		if int(cargo[cheap]) <= 0:
			cargo.erase(cheap)
		var dropped := spawn_pickup(p.global_position + Vector2(0, -6), cheap)
		if dropped:
			dropped.age = -Balance.SWAP_DROP_IGNORE
		Game.run["swaps"] = int(Game.run.get("swaps", 0)) + 1
		toast("SWAPPED %s FOR %s" % [Balance.ore_label(cheap).to_upper(), Balance.ore_label(key).to_upper()])
	cargo[key] = int(cargo.get(key, 0)) + 1
	hint("ore")
	Audio.play("pickup", -6.0, 0.1, 0.02)
	if hud:
		hud.pulse_cargo()
	if Game.cargo_count() >= cargo_cap() and int(Game.run.get("swaps", 0)) == 0 and not _full_warned:
		_full_warned = true
		toast("CARGO FULL - better ore now replaces your cheapest")
		hint("full")
	p.queue_free()


var _full_warned := false


func on_enemy_killed(e: Node) -> void:
	Game.run["kills"] = int(Game.run.get("kills", 0)) + 1
	Progress.add_stat("kills")
	codex_unlock("creature:" + codex_kind(e))
	var src: String = String(e.get("last_hit")) if e.get("last_hit") != null else ""
	if src in Orders.TERRAIN_SOURCES:
		Progress.add_stat("terrain_kills")
		Game.run["terrain_kills"] = int(Game.run.get("terrain_kills", 0)) + 1
		toast("TERRAIN KILL - %s" % {"rubble": "crushed", "gas": "gassed", "lava": "burned", "prop": "flattened", "water": "drowned", "steam": "scalded", "flood": "swept away", "dry": "left high and dry", "quench": "turned to stone", "fall": "fell to its death"}.get(src, src))
	enemies.erase(e)


## The codex creature id of an enemy (most specific class first).
static func codex_kind(e: Node) -> String:
	if e is SporePod:
		return "spore"
	if e is BombEater:
		return "eater"
	if e is Breaker:
		return "breaker"
	if e is Burrower:
		return "burrower"
	if e is Eel:
		return "eel"
	if e is Slag:
		return "slag"
	if e is Flier:
		return "flier"
	if e is Brute:
		return "brute"
	if e is Sentry:
		return "sentry"
	return "crawler"


var _orders_t := 0.0
var pressure: Pressure
var sand: SandSim
var sand_drops: SandDrops
var _sand_drill_n := 0


## Throw loose dirt from a broken or fallen cell as flying grains.
func spray_sand(c: Vector2i, total: int, grains: int, speed: float, up: float) -> void:
	if sand_drops == null:
		return
	var col := Cell.debris_color(Cell.SOFT, maxi(0, grid.get_stratum(c.x, c.y))).lightened(0.12)
	sand_drops.spray(grid.cell_center(c), total, grains, speed, up, col)
var _sand_blast_n := 0


## Dig the sand out of a cell (drill or blast).
func dig_sand(c: Vector2i) -> void:
	if sand == null or sand.remove(c) <= 0:
		return
	raise_dust()
	var pos := grid.cell_center(c) + Vector2(0, 4)
	fx.dust(pos, Cell.debris_color(Cell.SOFT, maxi(0, grid.get_stratum(c.x, c.y))), 4)
	Audio.play_at("break_soft", pos, -8.0, 0.15, 0.05)


## One in BREAKER_EVERY crawlers in the breaker zones is a breaker (fixed per
## cell, so a seed always has the same ones).
func _breaker_here(cell: Vector2i) -> bool:
	var z := grid.get_stratum(cell.x, cell.y)
	return z in Balance.BREAKER_ZONES and TerrainView.hash2(cell.x * 7 + seed_value, cell.y) % Balance.BREAKER_EVERY == 0


func spawn_crawler(cell: Vector2i, breaker: bool = false) -> Crawler:
	var cr: Crawler = Breaker.new() if breaker else Crawler.new()
	cr.mine = self
	cr.position = grid.cell_center(cell)
	entity_root.add_child(cr)
	enemies.append(cr)
	return cr


func _update_orders(delta: float) -> void:
	_orders_t -= delta
	if _orders_t > 0.0:
		return
	_orders_t = 0.25
	if stage == "mission":
		Game.run["mission_fill"] = lake_fill()
	for o: Dictionary in Orders.update(Game.run):
		if String(o["kind"]) == "mission":
			_mission_goal_met(o)
			continue
		toast("ORDER DONE: %s  +%d CR on extraction" % [o["text"], int(o["reward"])])
		Audio.play("lift_ding", -4.0)


## How full the mission's lake bed is, in whole percent (0..100).
func lake_fill() -> int:
	if not data.has("bed") or int(data.get("bed_capacity", 0)) <= 0:
		return 0
	var bed: Rect2i = data["bed"]
	var held := 0
	for y in range(bed.position.y, bed.end.y):
		for x in range(bed.position.x, bed.end.x):
			held += grid.get_water(x, y)
	return clampi(int(floor(100.0 * float(held) / (float(data["bed_capacity"]) * Balance.MISSION_FULL))), 0, 100)


## The mission's goal is met: the lift by the lake bed powers up.
func _mission_goal_met(o: Dictionary) -> void:
	for l in lifts:
		if l.locked:
			l.unlock()
	Audio.play("relic")
	shake(0.3)
	if hud:
		hud.banner("LAKE FILLED")
	toast("THE LAKE IS FULL ENOUGH - the lift beside it is online. Ride it out for +%d CR" % int(o["reward"]))


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
			return {"kind": "lift", "node": l, "label": "EXTRACT" if l.active else ("NO POWER" if l.locked else "ACTIVATE")}
	if relic and not relic.taken and relic.global_position.distance_to(pc) < 28.0:
		return {"kind": "relic", "node": relic, "label": "TAKE RELIC"}
	for c in caches:
		if not c.used and c.global_position.distance_to(pc) < 22.0:
			return {"kind": "cache", "node": c, "label": "OPEN CACHE"}
	for find in keepsakes:
		if not find.used and find.global_position.distance_to(pc) < 22.0:
			return {"kind": "find", "node": find, "label": "TAKE"}
	for rr in run_relics:
		if not rr.used and rr.global_position.distance_to(pc) < 22.0:
			return {"kind": "run_relic", "node": rr, "label": "TAKE"}
	if descent and absf(descent.global_position.x - pc.x) < 40.0 and absf(descent.global_position.y - (pc.y + 13.0)) < 26.0:
		return {"kind": "descent", "node": descent, "label": "DESCEND"}
	for v in valves:
		if v.global_position.distance_to(pc + Vector2(0, 13)) < 22.0:
			return {"kind": "valve", "node": v, "label": v.label()}
	if gate and gate.global_position.distance_to(pc + Vector2(0, 13)) < 30.0:
		return {"kind": "gate", "node": gate, "label": "TRANSIT" if gate.online else "GATE"}
	return {}


func player_interact(pl: Player) -> void:
	var it := nearest_interactable(pl)
	if ending:
		return
	if it.is_empty():
		# nothing to use here: throw a lure instead
		pl.throw_lure()
		return
	match it["kind"]:
		"find":
			it["node"].take()
		"run_relic":
			it["node"].take()
		"descent":
			# never a one-press action: the warning must be confirmed
			descent_prompt.open()
		"valve":
			it["node"].toggle()
		"gate":
			if gate.online:
				extract_gate()
			elif not gate.wake():
				toast(gate.status_text())
		"lift":
			var l: Entities.Lift = it["node"]
			if l.locked:
				toast("NO POWER - fill the lake bed to %d%% first (now %d%%)" % [int(round(float(data.get("bed_target", 0.6)) * 100.0)), lake_fill()])
				Audio.play("ui_deny")
			elif not l.active:
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
	Game.run["hull_frac"] = player.hp / maxf(1.0, player.max_hp)
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


## Confirmed one-way descent: a short sequence, then the same run continues in
## the deep stage. Nothing is banked and nothing is reset.
func begin_descent() -> void:
	if ending or stage != "mine":
		return
	ending = true
	player.controls_enabled = false
	player.invuln = 99.0          # the fall is theatre, never a cheap hit
	player.stop_sounds()
	Audio.loop("lift_hum", true, -6.0)
	Audio.play("rumble")
	shake(0.6)
	if hud:
		hud.banner("DESCENDING")
	var hull_now := player.hp
	var from_depth := grid.h
	var tw := create_tween()
	tw.tween_property(player, "global_position", descent.global_position + Vector2(0, -14), 0.3)
	tw.tween_callback(func() -> void: player.set_physics_process(false))
	tw.parallel().tween_property(descent, "position:y", descent.position.y + 220.0, Balance.DEEP_DESCENT_SECONDS).set_delay(0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(player, "global_position:y", player.global_position.y + 206.0, Balance.DEEP_DESCENT_SECONDS).set_delay(0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		Audio.loop("lift_hum", false)
		Game.descend(hull_now, from_depth))


## Leaving through the Transit Gate ends the same run successfully.
func extract_gate() -> void:
	if ending or gate == null or not gate.online:
		return
	ending = true
	Game.run["hull_frac"] = player.hp / maxf(1.0, player.max_hp)
	player.controls_enabled = false
	player.stop_sounds()
	Game.run["deep_exit"] = true
	Audio.play("relic")
	Audio.loop("lift_hum", true, -6.0)
	toast("TRANSIT ARRAY ONLINE")
	if hud:
		hud.banner("TRANSIT")
	fx.flash(gate.global_position + Vector2(0, -20), Color(0.4, 1.0, 0.95), 1.6, 1.2)
	var tw := create_tween()
	tw.tween_property(player, "global_position", gate.global_position + Vector2(0, -14), 0.35)
	tw.tween_callback(func() -> void: player.set_physics_process(false))
	tw.tween_property(player, "modulate:a", 0.0, 1.1)
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
