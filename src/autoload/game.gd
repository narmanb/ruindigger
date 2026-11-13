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
		"finds": [],
		"banked": {},
		"relic": false,
		"max_depth": 0,
		"kills": 0,
		"time": 0.0,
		"ore_mined": 0,
		"scaffold": Balance.scaffold_capacity(Progress.level("scaffold")),
		"ladders_built": 0,
		"stage": "mine",          # "mine" (five zones) or "deep" (The First Civilization)
		"depth_offset": 0,        # cells already descended in earlier stages
		"deep_exit": false,
	}
	goto("mine")


## One-way descent into The First Civilization. The SAME run continues: cargo,
## relic, finds, charges, scaffold, hull and the contract all carry over.
func descend(hull_now: float, from_depth_cells: int) -> void:
	if run.get("stage", "mine") == "deep":
		return
	run["stage"] = "deep"
	run["hp"] = hull_now
	run["depth_offset"] = from_depth_cells
	run["max_depth"] = maxi(int(run.get("max_depth", 0)), from_depth_cells)
	goto("mine")


func in_deep() -> bool:
	return run.get("stage", "mine") == "deep"


func cargo_count() -> int:
	var n := 0
	for k in run.get("cargo", {}).keys():
		n += int(run["cargo"][k])
	return n


func cargo_value(cargo: Dictionary) -> int:
	var v := 0
	for k in cargo.keys():
		v += Balance.ore_value(int(k)) * int(cargo[k])
	return v


## Cheapest key in the rack, or -1 when empty.
func cheapest_cargo() -> int:
	var best := -1
	var bv := 1 << 30
	for k in run.get("cargo", {}).keys():
		if int(run["cargo"][k]) <= 0:
			continue
		var v := Balance.ore_value(int(k))
		if v < bv:
			bv = v
			best = int(k)
	return best


## Can this ore key go into a rack of `cap`? Yes if there is room, or if it is
## worth more than the cheapest thing carried (it will be swapped in).
func can_take(key: int, cap: int) -> bool:
	if cargo_count() < cap:
		return true
	var c := cheapest_cargo()
	return c >= 0 and Balance.ore_value(key) > Balance.ore_value(c)


func finds_value(finds: Array) -> int:
	var value := 0
	var seen: Dictionary = {}
	for id in finds:
		if typeof(id) == TYPE_INT and id >= 0 and id < Balance.KEEPSAKES.size() and not seen.has(id):
			seen[id] = true
			value += int(Balance.KEEPSAKES[id]["value"])
	return value


func end_run(extracted: bool, cause: String = "") -> void:
	var cargo: Dictionary = run.get("cargo", {}).duplicate()
	var credits := 0
	var relic_bonus := 0
	var finds: Array = run.get("finds", []).duplicate()
	var finds_bonus := finds_value(finds) if extracted else 0
	var deep: bool = run.get("stage", "mine") == "deep"
	var deep_bonus := Balance.DEEP_EXIT_BONUS if (extracted and deep and run.get("deep_exit", false)) else 0
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
	Progress.add_credits(credits + relic_bonus + finds_bonus + deep_bonus)
	Progress.tutorial_done = true
	Progress.save_progress()
	last_result = {
		"extracted": extracted, "cause": cause, "cargo": cargo, "credits": credits,
		"relic": run.get("relic", false), "relic_bonus": relic_bonus, "depth": depth_m,
		"finds": finds, "finds_bonus": finds_bonus,
		"deep": deep, "deep_exit": extracted and deep and run.get("deep_exit", false), "deep_bonus": deep_bonus,
		"kills": run.get("kills", 0), "time": run.get("time", 0.0), "seed": run.get("seed", 0),
		"contract": contract.get("name", ""),
	}
	roll_contracts()
	goto("results")
