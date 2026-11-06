extends Node
## Screenshot harness (needs a display, e.g. xvfb-run):
## godot --path . res://tests/shot.tscn -- screen=mine seed=7 frames=90 out=/tmp/a.png [drill_down=1] [teleport=x,y]

var args := {}
var frame := 0
var target := 90


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
	var mine: Node = Game.current
	if frame == 20 and mine and mine.get("player") != null and args.has("teleport"):
		var p: PackedStringArray = args["teleport"].split(",")
		mine.player.global_position = Vector2(float(p[0]) * 16 + 8, float(p[1]) * 16)
		mine.camera.reset_smoothing()
	if frame == 20 and mine and args.has("at") and mine.get("data") != null:
		var key: String = args["at"]
		var c: Vector2i = mine.data[key] if mine.data.has(key) else Vector2i(10, 10)
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
	if mine and args.has("charge") and frame == 40:
		mine.player.input_override = {"charge_just": true, "x": 0.0}
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
		var img := get_viewport().get_texture().get_image()
		img.save_png(args.get("out", "/tmp/claude-0/shot.png"))
		get_tree().quit()
