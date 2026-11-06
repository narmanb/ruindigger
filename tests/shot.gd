extends Node
## Screenshot harness (needs a display, e.g. xvfb-run):
## godot --path . res://tests/shot.tscn -- screen=mine seed=7 frames=90 out=/tmp/a.png [drill_down=1] [teleport=x,y]

var args := {}
var frame := 0
var target := 90


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	target = int(args.get("frames", "90"))
	var screen: String = args.get("screen", "mine")
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
	if mine and mine.get("player") != null and mine.player:
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
