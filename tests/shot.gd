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


func _process(_d: float) -> void:
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
	if frame == 20 and mine and args.has("at") and mine.get("data") != null:
		var key: String = args["at"]
		var c: Vector2i = mine.data[key] if mine.data.has(key) else Vector2i(10, 10)
		if key.begins_with("lm:") or key.begins_with("ch:"):
			var want := key.substr(3)
			var pool: Array = mine.data.get("landmarks", []) if key.begins_with("lm:") else mine.data.get("plan", {}).get("chambers", [])
			for item in pool:
				if item.get("kind", item.get("arch", "")) == want:
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
		for k in ["move_control", "touch_mode", "camera_zoom", "stick_size"]:
			if args.has(k):
				Settings.values[k] = Settings._sanitize(k, float(args[k]) if k in ["camera_zoom", "stick_size"] else int(args[k]))
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
		var img := get_viewport().get_texture().get_image()
		img.save_png(args.get("out", "/tmp/claude-0/shot.png"))
		get_tree().quit()
