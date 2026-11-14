extends Node
## Screenshot harness (needs a display, e.g. xvfb-run):
## godot --path . res://tests/shot.tscn -- screen=mine seed=7 frames=90 out=/tmp/a.png [drill_down=1] [teleport=x,y]

var args := {}
var frame := 0
var target := 90
var wall_times: Array[float] = []
var physics_times: Array[float] = []
var previous_us := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	target = int(args.get("frames", "90"))
	var screen: String = args.get("screen", "mine")
	if screen == "results":
		Game.last_result = {"extracted": args.get("ok", "1") == "1", "cause": "burrow crawler", "cargo": {1: 9, 2: 4, 3: 2, 5: 3},
			"credits": 200, "relic": true, "relic_bonus": 260, "depth": 388, "kills": 3, "time": 612.0, "seed": 4242, "contract": "STANDARD SURVEY"}
	if screen == "mine":
		Game.contract = Game.contract_offers[0]
		Game.contract["seed"] = int(args.get("seed", "7"))
		Game.start_run.call_deferred()
	else:
		Game.goto.call_deferred(screen, true)


var _deep_started := false


func _process(_d: float) -> void:
	# deep=1: descend first, then restart the frame count in the deep stage
	if args.has("deep"):
		var cur: Node = Game.current
		if not _deep_started:
			if cur and cur.get("player") != null:
				_deep_started = true
				Game.descend(100.0, Balance.MAP_H)
			return
		if cur == null or cur.get("stage") != "deep" or cur.get("player") == null:
			return
	frame += 1
	if args.has("profile"):
		var now := Time.get_ticks_usec()
		if frame > 30 and previous_us > 0:
			wall_times.append((now - previous_us) / 1000.0)
			physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		previous_us = now
	var mine: Node = Game.current
	if frame == 20 and mine and mine.get("player") != null and args.has("teleport"):
		var p: PackedStringArray = args["teleport"].split(",")
		mine.player.global_position = Vector2(float(p[0]) * 16 + 8, float(p[1]) * 16)
		mine.camera.reset_smoothing()
	if frame == 20 and mine and args.has("deep") and mine.get("data") != null:
		var names: Array = []
		for lm in mine.data.get("landmarks", []):
			if lm.has("name"):
				names.append(lm["name"])
		print("VAULTS ", names, " furnished ", mine.data.get("furnished", 0))
	if frame == 20 and mine and args.has("runrelic") and mine.get("data") != null and not mine.data.get("run_relics", []).is_empty():
		var rc: Vector2i = mine.data["run_relics"][int(args["runrelic"]) % mine.data["run_relics"].size()]["cell"]
		mine.player.global_position = Vector2((rc.x - 2) * 16 + 8, (rc.y + 1) * 16 - Player.HALF.y - 0.5)
		mine.player.invuln = 1e9
		mine.camera.reset_smoothing()
	if frame == 20 and mine and args.has("decor") and mine.get("data") != null:
		var nth := int(args.get("nth", "0"))
		for e in mine.data["entities"]:
			if e["type"] == "decor" and e["kind"] == args["decor"]:
				if nth > 0:
					nth -= 1
					continue
				var dc: Vector2i = e["cell"]
				print("DECOR at ", dc, " w ", e["w"], " h ", e["h"])
				mine.player.global_position = Vector2((dc.x + int(e["w"]) / 2) * 16 + 8, (dc.y + 1) * 16 - Player.HALF.y - 0.5)
				mine.player.invuln = 1e9
				mine.camera.reset_smoothing()
				break
	if frame == 20 and mine and args.has("at") and mine.get("data") != null:
		var key: String = args["at"]
		var c: Vector2i = mine.data[key] if mine.data.has(key) else Vector2i(10, 10)
		if key.begins_with("lm:") or key.begins_with("ch:"):
			var want := key.substr(3)
			var pool: Array = mine.data.get("landmarks", []) if key.begins_with("lm:") else mine.data.get("plan", {}).get("chambers", [])
			for item in pool:
				if item.get("kind", item.get("arch", "")) == want or item.get("name", "") == want.replace("_", " "):
					var rr: Rect2i = item["rect"]
					c = Vector2i(rr.position.x + rr.size.x / 2, rr.end.y - 1)
					# stand on the first open cell above solid ground near the centre
					for dy in range(-12, 12):
						var t := Vector2i(c.x, c.y + dy)
						if not mine.grid.is_solid(t.x, t.y) and not mine.grid.is_solid(t.x, t.y - 1) and mine.grid.is_solid(t.x, t.y + 1):
							c = t
							break
					break
		if key == "hall":
			var r: Rect2i = mine.data["halls"][0]
			c = Vector2i(r.position.x - 2, r.end.y - 2)
		if key == "pocket":
			var pr: Rect2i = mine.data["water_pockets"][int(args.get("i", "0"))]
			c = Vector2i(pr.position.x - 3, pr.end.y - 1)
			for yy in range(c.y - 2, c.y + 1):
				for xx in range(c.x - 2, c.x + 1):
					mine.grid.set_mat(xx, yy, Cell.AIR, true)
		if key == "crawler":
			for e in mine.data["entities"]:
				if e["type"] == "crawler":
					c = e["cell"] + Vector2i(4, 0)
					break
		mine.player.global_position = Vector2(c.x * 16 + 8, (c.y + 1) * 16 - 14)
		mine.player.invuln = 999.0
		mine.camera.reset_smoothing()
	if mine and args.has("settings") and frame == 25:
		if mine.has_method("_settings"):
			mine._settings()
		elif mine.get("pause_menu") != null:
			mine.pause_menu.open()
			mine.pause_menu._settings()
	if mine and args.has("waterfall") and frame == 20:
		var g: TerrainGrid = mine.grid
		var ox := 22
		var oy := 100
		for y in range(oy - 10, oy + 12):
			for x in range(ox - 12, ox + 16):
				g.set_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE, false)
				var m := Cell.AIR
				if y >= oy + 10 or x <= ox - 11 or x >= ox + 15 or y <= oy - 9:
					m = Cell.HARD
				if y >= oy and y <= oy + 1 and x <= ox:
					m = Cell.HARD   # shelf
				g.set_mat(x, y, m, true)
				g.set_water(x, y, 0)
		g.set_mat(ox, oy - 1, Cell.HARD)
		g.set_mat(ox, oy - 2, Cell.HARD)
		g.set_mat(ox, oy - 3, Cell.HARD)
		if args.has("ledge"):
			for x in range(ox - 10, ox):
				g.set_water(x, oy - 1, 20)
		else:
			for y in range(oy - 5, oy):
				for x in range(ox - 10, ox):
					g.set_water(x, y, Balance.WATER_MAX)
		mine.water.wake_all()
		if args.has("physics"):
			mine.debris.spawn_prop("crate", g.cell_center(Vector2i(ox - 5, oy - 3)))
			mine.debris.spawn_prop("canister", g.cell_center(Vector2i(ox - 8, oy - 2)))
			mine.debris.spawn_prop("stone", g.cell_center(Vector2i(ox + 5, oy + 5)))
			for x in range(ox + 2, ox + 5):
				g.set_mat(x, oy + 5, Cell.SOFT)
		mine.player.global_position = Vector2((ox + 8) * 16, (oy + 10) * 16 - 14)
		mine.player.invuln = 999.0
		mine.camera.reset_smoothing()
	if mine and args.has("waterfall") and frame == 40:
		mine.damage_cell(Vector2i(22, 99), 99.0, 0, false, "shot")
		mine.damage_cell(Vector2i(22, 98), 99.0, 0, false, "shot")
		mine.damage_cell(Vector2i(22, 97), 99.0, 0, false, "shot")
	if mine and args.has("charge") and frame == 40:
		mine.player.input_override = {"charge_just": true, "x": 0.0}
	if frame == 2:
		for k in ["move_control", "touch_mode", "camera_zoom", "stick_size", "gadget_bar_open", "touch_scale"]:
			if args.has(k):
				Settings.values[k] = Settings._sanitize(k, float(args[k]) if k in ["camera_zoom", "stick_size", "touch_scale"] else int(args[k]))
		Settings.changed.emit()
	if mine and args.has("map") and frame == target - 6 and mine.get("hud") != null:
		for y in range(0, mine.grid.h):
			for x in range(0, mine.grid.w):
				if (x + y * 3) % 7 != 0 and y < int(args["map"]):
					mine.grid.set_flag(x, y, Cell.F_EXPLORED)
					mine.hud.minimap.img.set_pixel(x, y, Minimap.cell_color(mine.grid, x, y))
		mine.hud.open_map()
		if args.has("mapzoom"):
			mine.hud.map_screen.view.zoom_by(float(args["mapzoom"]) / 2.0, Vector2(320, 180))
	# quench=1: open a viewing pocket beside the first quench pair and drill out
	# its divider, so the water pours onto the lava (deep stage)
	if mine and args.has("quench") and frame == 20 and mine.get("data") != null:
		for lm in mine.data.get("landmarks", []):
			if lm["kind"] == "quench_pair":
				var qr: Rect2i = lm["rect"]
				var vx := qr.end.x + 4
				var vy := qr.end.y - 1
				for yy in range(qr.position.y, qr.end.y + 1):
					for xx in range(qr.end.x + 1, qr.end.x + 9):
						mine.grid.set_mat(xx, yy, Cell.AIR if yy < qr.end.y else Cell.HARD, true)
				mine.player.global_position = Vector2(vx * 16 + 8, (vy + 1) * 16 - Player.HALF.y - 0.5)
				mine.player.invuln = 1e9
				mine.camera.global_position = Vector2((qr.get_center().x + 3) * 16, qr.get_center().y * 16)
				mine.camera.reset_smoothing()
				for xx in range(qr.position.x + 1, qr.end.x - 1):
					for dy in [4, 5]:
						mine.damage_cell(Vector2i(xx, qr.position.y + dy), 99.0, 0, false, "shot")
				break
	if mine and args.has("valves") and frame == 22 and mine.get("valves") != null:
		for v in mine.valves:
			v.toggle()
		mine.player.invuln = 1e9
	# sluice=1: open a viewing pocket beside the first sluice and drill a hole
	# in its divider, so the lava pours down into the water pool (deep stage)
	if mine and args.has("sluice") and frame == 20 and mine.get("data") != null:
		for lm in mine.data.get("landmarks", []):
			if lm["kind"] == "sluice":
				var sr: Rect2i = lm["rect"]
				for yy in range(sr.position.y, sr.end.y + 1):
					for xx in range(sr.end.x + 1, sr.end.x + 9):
						mine.grid.set_mat(xx, yy, Cell.AIR if yy < sr.end.y else Cell.HARD, true)
				var vx := sr.end.x + 4
				mine.player.global_position = Vector2(vx * 16 + 8, sr.end.y * 16 - Player.HALF.y - 0.5)
				mine.player.invuln = 1e9
				var cx := sr.position.x + sr.size.x / 2
				for dy in [3, 4]:
					mine.damage_cell(Vector2i(cx, sr.position.y + dy), 99.0, 0, false, "shot")
				break
	# pourtest=1: a lava reservoir over a water pool; pourtest=2: water over a
	# wide lava pool. A purpose-built chamber in the deep stage, so the pour can
	# be watched; a hole is drilled in the divider at frame 30.
	if mine and args.has("pourtest") and frame == 20 and mine.get("lava") != null:
		var g: TerrainGrid = mine.grid
		var ox := 88
		var oy := 58
		var lava_top: bool = args["pourtest"] == "1"
		for y in range(oy, oy + 21):
			for x in range(ox, ox + 24):
				g.set_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE, false)
				g.set_water(x, y, 0)
				g.set_lava(x, y, 0)
				var edge := x == ox or x == ox + 23 or y == oy or y == oy + 20
				g.set_mat(x, y, Cell.BEDROCK if edge else Cell.AIR)
		for x in range(ox + 1, ox + 23):
			g.set_mat(x, oy + 5, Cell.HARD)          # divider under the top reservoir
		for y in range(oy + 11, oy + 20):
			g.set_mat(ox + 3, y, Cell.HARD)
			g.set_mat(ox + 16, y, Cell.HARD)
		for x in range(ox + 17, ox + 23):
			g.set_mat(x, oy + 13, Cell.HARD)          # viewing ledge
		for y in range(oy + 6, oy + 13):
			g.set_mat(ox + 3, y, Cell.HARD)
		for x in range(ox + 1, ox + 3):
			for y in range(oy + 6, oy + 20):
				g.set_mat(x, y, Cell.HARD)
		for x in range(ox + 4, ox + 16):
			for y in range(oy + 2, oy + 5):
				if lava_top:
					g.set_lava(x, y, Balance.LAVA_MAX)
				else:
					g.set_water(x, y, Balance.WATER_MAX)
			for y in range(oy + 13, oy + 20):
				if lava_top:
					g.set_water(x, y, Balance.WATER_MAX)
				elif y >= oy + 16:
					g.set_lava(x, y, Balance.LAVA_MAX)
		mine.lava.wake_all()
		mine.water.wake_all()
		mine.player.global_position = Vector2((ox + 19) * 16 + 8, (oy + 13) * 16 - Player.HALF.y - 0.5)
		mine.player.invuln = 1e9
		mine.player.input_override = {"x": 0.0}
		for e in mine.enemies.duplicate():
			if Rect2(Vector2(ox - 4, oy - 4) * 16, Vector2(32, 30) * 16).has_point(e.global_position):
				mine.enemies.erase(e)
				e.queue_free()
	if mine and args.has("pourtest") and frame == 30:
		mine.grid.set_mat(98, 63, Cell.AIR)
		mine.grid.set_mat(99, 63, Cell.AIR)
	if mine and args.has("pourtest") and frame == target - 1:
		if args.has("hide"):
			for ch in mine.get_children():
				var nm: String = ch.get_script().get_global_name() if ch.get_script() != null else ch.get_class()
				if nm in str(args["hide"]).split(","):
					ch.visible = false
					print("hid ", nm)
		print("POUR formed=%d sunk=%d swapped=%d boiled=%d frozen=%d steam_peak=%d" % [mine.lava.rock_formed, mine.lava.sunk, mine.lava.swapped, mine.lava.water_boiled, mine.lava.lava_frozen, mine.steam.peak_cells])
	if mine and args.has("gadget") and frame == target - 12:
		if args["gadget"] != "1":
			Game.run["loadout"]["active"] = String(args["gadget"])
		mine.use_gadget(mine.player)
	if mine and args.has("feet") and frame == target - 1:
		var pl: Player = mine.player
		print("FEET bottom=%.2f cell_top=%.2f sink=%.2f floor=%s" % [pl.global_position.y + Player.HALF.y, floor((pl.global_position.y + Player.HALF.y + 1.0) / 16.0) * 16.0, pl._sink, str(pl.is_on_floor())])
	# sandtest=1: a corridor; sand pours onto the floor from above and piles up,
	# then the digger walks over it
	if mine and args.has("sandtest") and frame == 20:
		var g: TerrainGrid = mine.grid
		var pl: Player = mine.player
		var pc: Vector2i = g.world_to_cell(pl.global_position)
		for x in range(pc.x - 2, pc.x + 16):
			for y in range(pc.y - 6, pc.y + 1):
				g.set_flag(x, y, Cell.F_PROTECTED | Cell.F_NO_RUBBLE, false)
				g.set_water(x, y, 0)
				g.set_mat(x, y, Cell.AIR)
			g.set_mat(x, pc.y + 1, Cell.HARD)
			g.set_mat(x, pc.y - 7, Cell.HARD)
		g.set_mat(pc.x + 16, pc.y, Cell.HARD)
		pl.invuln = 1e9
		set_meta("sand_pc", pc)
	if mine and args.has("sandtest") and frame >= 22 and frame < 60 and frame % 3 == 0:
		var pc2: Vector2i = get_meta("sand_pc")
		mine.sand.add(Vector2i(pc2.x + 6, pc2.y - 5), Balance.SAND_MAX)
		if frame % 6 == 0:
			mine.sand.add(Vector2i(pc2.x + 11, pc2.y - 5), Balance.SAND_MAX)
	if mine and args.has("sandtest") and frame == int(args.get("walkat", "100000")):
		mine.player.input_override = {"x": 1.0}
	if mine and args.has("ladder") and frame == target - 30:
		mine.build_ladder(mine.player)
	if mine and args.has("layout") and frame == target - 6:
		get_tree().root.add_child(load("res://src/ui/layout_editor.gd").new())
	if mine and args.has("pause") and frame == target - 5 and mine.get("pause_menu") != null:
		mine.pause_menu.open()
	if mine and args.has("panel") and frame == 30 and mine.has_method("_upgrade_panel"):
		Progress.credits = 400
		mine._open_panel(mine.call("_" + args["panel"] + "_panel"))
	if mine and mine.get("player") != null and mine.player and not args.has("charge"):
		var ov := {}
		if args.has("drill_down") and frame > 25:
			ov = {"drill": true, "y": 1.0}
		if args.has("drill_right") and frame > 25:
			ov = {"drill": true, "x": 1.0}
		if args.has("walk") and frame > 25:
			ov = {"x": float(args["walk"])}
		if not ov.is_empty():
			mine.player.input_override = ov
	if frame == target:
		if args.has("profile") and not wall_times.is_empty():
			wall_times.sort()
			physics_times.sort()
			var p95 := mini(wall_times.size() - 1, int(wall_times.size() * 0.95))
			print("GL software scene: frame median %.2f ms, p95 %.2f ms; physics median %.2f ms, p95 %.2f ms" % [wall_times[wall_times.size() / 2], wall_times[p95], physics_times[physics_times.size() / 2], physics_times[p95]])
			if mine and mine.has_method("water_diagnostics"):
				print("WATER DIAGNOSTICS: ", mine.water_diagnostics(), "; total erosion calls: ", mine.erosion.total_edits)
		if args.has("quench") and mine and mine.get("lava") != null:
			print("QUENCH rock_formed=%d boiled=%d steam_cells=%d steam_peak=%d player=%s" % [mine.lava.rock_formed, mine.lava.water_boiled, mine.steam.cells.size(), mine.steam.peak_cells, str(mine.grid.world_to_cell(mine.player.global_position))])
		var img := get_viewport().get_texture().get_image()
		img.save_png(args.get("out", "/tmp/claude-0/shot.png"))
		get_tree().quit()
