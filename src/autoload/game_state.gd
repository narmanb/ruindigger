extends Node
## Per-run state: the seed, cargo manifest, relic status and the result of the
## last run. Kept separate from SaveManager so a run can be discarded cleanly.

signal cargo_changed()
signal run_ended(result: Dictionary)

var seed_value: int = 0
var cargo: Dictionary = {}          # ore id -> count
var cargo_units: int = 0
var relic_taken: bool = false
var depth_cells: int = 0
var max_depth_cells: int = 0
var credits_earned_this_run: int = 0
var elapsed: float = 0.0
var run_active: bool = false
var run_result: Dictionary = {}

func start_run(new_seed: int = 0) -> void:
	seed_value = new_seed if new_seed != 0 else _random_seed()
	cargo.clear()
	cargo_units = 0
	relic_taken = false
	depth_cells = 0
	max_depth_cells = 0
	credits_earned_this_run = 0
	elapsed = 0.0
	run_active = true
	run_result = {}
	SaveManager.last_seed = seed_value
	SaveManager.save()
	cargo_changed.emit()

func _random_seed() -> int:
	var t := Time.get_unix_time_from_system()
	return int(t * 1000.0) % 2147483647

func _process(delta: float) -> void:
	if run_active:
		elapsed += delta

func add_ore(ore_id: int, count: int = 1) -> bool:
	var cap := Balance.carry_capacity(SaveManager.upgrade_level("cargo"))
	if cargo_units + count * Balance.ORE_WEIGHT > cap:
		return false
	cargo[ore_id] = int(cargo.get(ore_id, 0)) + count
	cargo_units += count * Balance.ORE_WEIGHT
	cargo_changed.emit()
	return true

func cargo_full() -> bool:
	return cargo_units >= Balance.carry_capacity(SaveManager.upgrade_level("cargo"))

func cargo_value() -> int:
	var total := 0
	for id in cargo:
		total += int(Balance.ORE_TYPES[id]["value"]) * int(cargo[id])
	return total

func take_relic() -> void:
	relic_taken = true
	cargo_changed.emit()

func set_depth(cells: int) -> void:
	depth_cells = cells
	if cells > max_depth_cells:
		max_depth_cells = cells

## Called on both extraction and death. `extracted` decides whether cargo banks.
func end_run(extracted: bool, cause: String = "") -> Dictionary:
	run_active = false
	var value := cargo_value()
	var relic_bonus := Balance.RELIC_VALUE if relic_taken else 0
	var banked := 0
	if extracted:
		banked = value + relic_bonus
		SaveManager.add_credits(banked)
		SaveManager.runs_completed += 1
		SaveManager.best_depth = max(SaveManager.best_depth, max_depth_cells)
		SaveManager.save()
	run_result = {
		"extracted": extracted,
		"cause": cause,
		"cargo": cargo.duplicate(),
		"cargo_units": cargo_units,
		"cargo_value": value,
		"relic": relic_taken,
		"relic_bonus": relic_bonus,
		"banked": banked,
		"depth": max_depth_cells,
		"elapsed": elapsed,
		"seed": seed_value,
	}
	run_ended.emit(run_result)
	return run_result

func has_banked_cargo() -> bool:
	return cargo_value() > 0 or relic_taken
