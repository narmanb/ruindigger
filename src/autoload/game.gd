extends Node
## Screen flow (title -> outpost -> mine -> results) and current-run state.

signal run_changed

const SCREENS := {
	"title": "res://src/ui/title_screen.gd",
	"outpost": "res://src/world/outpost.gd",
	"mine": "res://src/world/mine.gd",
	"results": "res://src/ui/results_screen.gd",
}

var current: Node = null
var current_name := ""
var contract: Dictionary = {}
var contract_offers: Array = []
var run: Dictionary = {}
var last_result: Dictionary = {}
var _fade: ColorRect
var _fade_layer: CanvasLayer
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.03, 0.02, 0.05, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade)
	roll_contracts()


func roll_contracts() -> void:
	contract_offers.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pool: Array = Balance.CONTRACTS.duplicate()
	# Standard survey is always offered so new players have a baseline.
	var first: Dictionary = pool.pop_front()
	pool.shuffle()
	for c in [first, pool[0], pool[1]]:
		var d: Dictionary = c.duplicate()
		d["seed"] = rng.randi_range(1000, 999999)
		d["reward"] = int(Balance.RELIC_BONUS * float(d["bonus"]))
		contract_offers.append(d)
	contract = contract_offers[0]


func choose_contract(i: int) -> void:
	if i >= 0 and i < contract_offers.size():
		contract = contract_offers[i]
		run_changed.emit()


func goto(screen: String, instant: bool = false) -> void:
	if _busy:
		return
	_busy = true
	get_tree().paused = false
	if not instant and current != null:
		var tw := create_tween()
		tw.tween_property(_fade, "color:a", 1.0, 0.25)
		await tw.finished
	if current != null:
		current.queue_free()
		await get_tree().process_frame
	var script: GDScript = load(SCREENS[screen])
	current = script.new()
	current.name = screen.capitalize().replace(" ", "")
	current_name = screen
	get_tree().root.add_child(current)
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.35)
	_busy = false


func start_run() -> void:
	var charges: int = Balance.CHARGES_FREE + Progress.charges
	Progress.charges = 0
	Progress.stats["runs"] = int(Progress.stats.get("runs", 0)) + 1
	Progress.save_progress()
	run = {
		"seed": int(contract.get("seed", 1234)),
		"contract": contract,
		"charges": charges,
		"cargo": {},
		"banked": {},
		"relic": false,
		"max_depth": 0,
		"kills": 0,
		"time": 0.0,
		"ore_mined": 0,
	}
	goto("mine")


func cargo_count() -> int:
	var n := 0
	for k in run.get("cargo", {}).keys():
		n += int(run["cargo"][k])
	return n


func cargo_value(cargo: Dictionary) -> int:
	var v := 0
	for k in cargo.keys():
		v += int(Balance.ORE[int(k)]["value"]) * int(cargo[k])
	return v


func end_run(extracted: bool, cause: String = "") -> void:
	var cargo: Dictionary = run.get("cargo", {}).duplicate()
	var credits := 0
	var relic_bonus := 0
	if extracted:
		credits = cargo_value(cargo)
		if run.get("relic", false):
			relic_bonus = int(contract.get("reward", Balance.RELIC_BONUS))
		Progress.stats["extractions"] = int(Progress.stats.get("extractions", 0)) + 1
		if run.get("relic", false):
			Progress.stats["relics"] = int(Progress.stats.get("relics", 0)) + 1
	else:
		Progress.stats["deaths"] = int(Progress.stats.get("deaths", 0)) + 1
	var depth_m := int(run.get("max_depth", 0) * Balance.METERS_PER_CELL)
	Progress.stats["best_depth"] = maxi(int(Progress.stats.get("best_depth", 0)), depth_m)
	Progress.add_credits(credits + relic_bonus)
	Progress.tutorial_done = true
	Progress.save_progress()
	last_result = {
		"extracted": extracted, "cause": cause, "cargo": cargo, "credits": credits,
		"relic": run.get("relic", false), "relic_bonus": relic_bonus, "depth": depth_m,
		"kills": run.get("kills", 0), "time": run.get("time", 0.0), "seed": run.get("seed", 0),
		"contract": contract.get("name", ""),
	}
	roll_contracts()
	goto("results")
